import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/protocol/pairing_session.dart';
import '../../../l10n/app_strings.dart';
import 'client_room_controls.dart';

/// Shows the room's actual detection state, including output started by a
/// different parent. Polling is limited to the visible, foreground screen.
class RoomAudioDetectionNotice extends StatefulWidget {
  const RoomAudioDetectionNotice({
    super.key,
    required this.controls,
    required this.session,
    this.alwaysShowHelp = false,
    this.pollForChanges = true,
    this.dark = false,
  });

  final ClientRoomControls controls;
  final PairingSession session;
  final bool alwaysShowHelp;
  final bool pollForChanges;
  final bool dark;

  @override
  State<RoomAudioDetectionNotice> createState() =>
      _RoomAudioDetectionNoticeState();
}

class _RoomAudioDetectionNoticeState extends State<RoomAudioDetectionNotice>
    with WidgetsBindingObserver {
  StreamSubscription<ClientRoomControlSnapshot>? _subscription;
  Timer? _timer;
  bool _refreshing = false;
  late ClientRoomControlSnapshot _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    _configurePolling();
  }

  void _subscribe() {
    _state = widget.controls.currentState;
    _subscription = widget.controls.states.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  void _configurePolling() {
    _timer?.cancel();
    if (!widget.pollForChanges) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant RoomAudioDetectionNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controls, widget.controls)) {
      _subscription?.cancel();
      _subscribe();
    }
    if (oldWidget.session != widget.session ||
        oldWidget.pollForChanges != widget.pollForChanges ||
        !identical(oldWidget.controls, widget.controls)) {
      _configurePolling();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted || !widget.pollForChanges || _refreshing) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _refreshing = true;
    try {
      await widget.controls.refreshComfort(widget.session);
    } catch (_) {
      // Keep the last known pause and the permanent help text. The screen's
      // connection indicator owns transport errors; failure is never "active".
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paused = _state.isAudioDetectionPaused;
    if (!paused && !widget.alwaysShowHelp) return const SizedBox.shrink();
    final strings = AppStrings.of(context);
    return Semantics(
      liveRegion: paused,
      child: Container(
        key: ValueKey(
            paused ? 'audio-detection-paused' : 'audio-detection-help'),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: EdgeInsets.all(paused ? 12 : 0),
        decoration: paused
            ? BoxDecoration(
                color: const Color(0xFFFFF1CC),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (paused) ...[
              Text(
                strings.ui('roomAudioDetectionPaused'),
                style: const TextStyle(
                  color: Color(0xFF5C4100),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              strings.ui('roomAudioDetectionHelp'),
              style: TextStyle(
                color: paused
                    ? const Color(0xFF5C4100)
                    : widget.dark
                        ? Colors.white70
                        : const Color(0xFF657289),
                fontSize: 12,
                height: 1.3,
              ),
            ),
            if (paused) ...[
              const SizedBox(height: 4),
              Text(
                strings.ui('roomAudioDetectionResumeHelp'),
                style: const TextStyle(
                  color: Color(0xFF5C4100),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
