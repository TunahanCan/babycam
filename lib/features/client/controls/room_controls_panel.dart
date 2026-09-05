import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/protocol/pairing_session.dart';
import '../../../l10n/app_strings.dart';
import 'client_room_controls.dart';
import 'room_audio_detection_notice.dart';

class RoomControlsPanel extends StatefulWidget {
  const RoomControlsPanel({
    super.key,
    required this.controls,
    required this.session,
    this.onError,
  });

  final ClientRoomControls controls;
  final PairingSession session;
  final ValueChanged<Object>? onError;

  @override
  State<RoomControlsPanel> createState() => _RoomControlsPanelState();
}

class _RoomControlsPanelState extends State<RoomControlsPanel>
    with WidgetsBindingObserver {
  StreamSubscription<ClientRoomControlSnapshot>? _subscription;
  late ClientRoomControlSnapshot _snapshot;
  String _trackId = 'white_noise';
  double _volume = .5;
  bool _comfortBusy = false;
  bool _talkBusy = false;
  int? _talkPointer;
  int _talkIntentGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _snapshot = widget.controls.currentState;
    _listen();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant RoomControlsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controlsChanged = !identical(oldWidget.controls, widget.controls);
    final sessionChanged = oldWidget.session != widget.session;
    if (controlsChanged || sessionChanged) {
      _talkIntentGeneration++;
      _talkPointer = null;
      _talkBusy = false;
      unawaited(oldWidget.controls.stopTalking().catchError((_) {}));
    }
    if (controlsChanged) {
      _subscription?.cancel();
      _snapshot = widget.controls.currentState;
      _listen();
    }
    if (sessionChanged) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _talkIntentGeneration++;
    _talkPointer = null;
    // stopTalking serializes behind an in-flight start, so requesting cleanup
    // unconditionally also closes the race where this panel disappears before
    // the first `talking: true` snapshot arrives.
    unawaited(widget.controls.stopTalking().catchError((_) {}));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _endTalking(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final comfort = _snapshot.comfort;
    final playing = comfort?.playing ?? false;
    final talking = _snapshot.talking;
    final canStopTalking = talking || _talkPointer != null;
    final talkControlEnabled = !_talkBusy || canStopTalking;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: const Color(0xFFFFFBFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFFFDCE5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.spa_rounded, color: Color(0xFFD84E78)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.ui('comfortAudio'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF182B49),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              strings.ui('comfortAudioDescription'),
              style: const TextStyle(color: Color(0xFF657289), fontSize: 13),
            ),
            RoomAudioDetectionNotice(
              controls: widget.controls,
              session: widget.session,
              alwaysShowHelp: true,
              pollForChanges: false,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _trackChip(strings, 'white_noise', 'whiteNoise'),
                _trackChip(strings, 'pink_noise', 'pinkNoise'),
                _trackChip(strings, 'rain', 'rainSound'),
                _trackChip(strings, 'soft_lullaby', 'softLullaby'),
                _trackChip(strings, 'shushing', 'shushingSound'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.volume_down_rounded, size: 20),
                Expanded(
                  child: Slider(
                    value: _volume,
                    onChanged: _comfortBusy
                        ? null
                        : (value) => setState(() => _volume = value),
                    onChangeEnd: (_) => _setVolume(),
                  ),
                ),
                Text('${(_volume * 100).round()}%'),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _comfortBusy ? null : _toggleComfort,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow),
                label: Text(
                  strings.ui(playing ? 'pauseComfort' : 'playComfort'),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Semantics(
              container: true,
              button: true,
              enabled: talkControlEnabled,
              toggled: talking,
              label: strings.ui(talking ? 'talkingNow' : 'holdToTalk'),
              hint: strings.ui('talkAccessibilityHint'),
              onTap: talkControlEnabled ? _toggleTalkingFromSemantics : null,
              excludeSemantics: true,
              child: Listener(
                onPointerDown: _startTalking,
                onPointerUp: _stopTalking,
                onPointerCancel: _stopTalking,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: talking
                        ? const Color(0xFFC44870)
                        : const Color(0xFF182B49),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_talkBusy)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        Icon(
                          talking ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          strings.ui(talking ? 'talkingNow' : 'holdToTalk'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.ui('talkHelp'),
              style: const TextStyle(color: Color(0xFF657289), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackChip(AppStrings strings, String id, String labelKey) =>
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: ChoiceChip(
          materialTapTargetSize: MaterialTapTargetSize.padded,
          label: Text(strings.ui(labelKey)),
          selected: _trackId == id,
          onSelected: _comfortBusy
              ? null
              : (_) {
                  setState(() => _trackId = id);
                  if (_snapshot.comfort?.playing == true) {
                    unawaited(_playComfort());
                  }
                },
        ),
      );

  void _listen() {
    _subscription = widget.controls.states.listen((state) {
      if (!mounted) return;
      setState(() {
        _snapshot = state;
        final comfort = state.comfort;
        if (comfort?.trackId != null) _trackId = comfort!.trackId!;
        if (comfort != null) _volume = comfort.volume;
      });
      final error = state.lastError;
      if (error != null) widget.onError?.call(error);
    });
  }

  void _refresh() {
    unawaited(widget.controls.refreshComfort(widget.session).catchError(
      (Object error) {
        widget.onError?.call(error);
        return null;
      },
    ));
  }

  Future<void> _toggleComfort() async {
    if (_comfortBusy) return;
    setState(() => _comfortBusy = true);
    try {
      if (_snapshot.comfort?.playing == true) {
        await widget.controls.setComfort(widget.session, action: 'pause');
      } else {
        await _playComfort();
      }
    } catch (error) {
      widget.onError?.call(error);
    } finally {
      if (mounted) setState(() => _comfortBusy = false);
    }
  }

  Future<void> _playComfort() => widget.controls.setComfort(
        widget.session,
        action: 'play',
        trackId: _trackId,
        volume: _volume,
        loop: true,
      );

  void _setVolume() {
    if (_snapshot.comfort == null) return;
    unawaited(widget.controls
        .setComfort(
      widget.session,
      action: 'setVolume',
      volume: _volume,
    )
        .catchError((Object error) {
      widget.onError?.call(error);
      return null;
    }));
  }

  void _startTalking(PointerDownEvent event) {
    _beginTalking(event.pointer);
  }

  void _beginTalking(int pointer) {
    if (_talkPointer != null || _talkBusy || _snapshot.talking) return;
    final generation = ++_talkIntentGeneration;
    _talkPointer = pointer;
    setState(() => _talkBusy = true);
    unawaited(widget.controls.startTalking(widget.session).then((_) {
      if (mounted && generation == _talkIntentGeneration) {
        setState(() => _talkBusy = false);
      }
    }).catchError((Object error) {
      if (!mounted || generation != _talkIntentGeneration) return;
      _talkPointer = null;
      setState(() => _talkBusy = false);
      widget.onError?.call(error);
    }));
  }

  void _stopTalking(PointerEvent event) {
    if (_talkPointer != event.pointer) return;
    _endTalking();
  }

  void _toggleTalkingFromSemantics() {
    if (_snapshot.talking || _talkPointer != null || _talkBusy) {
      _endTalking(force: true);
    } else {
      // A synthetic pointer identifier keeps the same single-flight ownership
      // as touch while allowing TalkBack and VoiceOver to toggle talk mode.
      _beginTalking(-1);
    }
  }

  void _endTalking({bool force = false}) {
    if (!force && _talkPointer == null && !_snapshot.talking && !_talkBusy) {
      return;
    }
    final generation = ++_talkIntentGeneration;
    _talkPointer = null;
    if (mounted && _talkBusy) {
      setState(() => _talkBusy = false);
    }
    unawaited(widget.controls.stopTalking().catchError((Object error) {
      if (mounted && generation == _talkIntentGeneration) {
        widget.onError?.call(error);
      }
    }));
  }
}
