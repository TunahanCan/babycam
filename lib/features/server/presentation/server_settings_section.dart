import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/async/serialized_async_executor.dart';
import '../../../l10n/app_strings.dart';
import '../../../services/configuration_service.dart';
import '../../shared/presentation/localized_measurement_text.dart';
import '../../shared/presentation/miucam_design_tokens.dart';
import '../../shared/presentation/miucam_shells.dart';
import 'server_trusted_devices_card.dart';
import '../server_runtime.dart';
import 'server_home_components.dart';

class ServerSettingsSection extends StatefulWidget {
  const ServerSettingsSection({
    super.key,
    required this.config,
    required this.runtime,
  });

  final ConfigurationService config;
  final ServerRuntime runtime;

  @override
  State<ServerSettingsSection> createState() => _ServerSettingsSectionState();
}

class _ServerSettingsSectionState extends State<ServerSettingsSection> {
  final _mutations = SerializedAsyncExecutor(
    closedErrorMessage: 'Server settings section is closed.',
  );

  late double _motionThreshold;
  late double _cryScoreThreshold;
  late double _notifyCooldownSeconds;
  late double _motionDurationSeconds;
  late double _cryDurationSeconds;
  int _pendingMutations = 0;

  bool get _saving => _pendingMutations > 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void didUpdateWidget(covariant ServerSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) _loadSettings();
  }

  @override
  void dispose() {
    unawaited(_mutations.close());
    super.dispose();
  }

  void _loadSettings() {
    _motionThreshold = widget.config.motionThreshold.clamp(.10, .60).toDouble();
    _cryScoreThreshold =
        widget.config.cryScoreThreshold.clamp(.45, .95).toDouble();
    _notifyCooldownSeconds =
        (widget.config.notifyCooldownMs / 1000).clamp(10, 180).toDouble();
    _motionDurationSeconds =
        (widget.config.motionMinDurationMs / 1000).clamp(1, 6).toDouble();
    _cryDurationSeconds =
        (widget.config.cryMinDurationMs / 1000).clamp(1.5, 6).toDouble();
  }

  Future<bool> _runMutation(Future<void> Function() mutation) async {
    if (!mounted || _mutations.isClosed) return false;
    setState(() => _pendingMutations++);
    try {
      await _mutations.run(() async {
        await mutation();
        await widget.runtime.reloadAnalysisSettings();
      });
      return true;
    } catch (_) {
      if (mounted) {
        final strings = AppStrings.of(context);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(strings.ui('settingsSaveFailed'))),
          );
      }
      return false;
    } finally {
      if (mounted) setState(() => _pendingMutations--);
    }
  }

  Future<void> _saveSetting(Future<void> Function() mutation) async {
    final saved = await _runMutation(mutation);
    if (!saved && mounted) setState(_loadSettings);
  }

  Future<void> _confirmResetSettings() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.ui('resetSettingsTitle')),
        content: Text(strings.ui('resetSettingsDescription')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.ui('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.ui('resetDefaults')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runMutation(widget.config.resetToDefaults);
    if (mounted) setState(_loadSettings);
  }

  Future<void> _applyDetectionPreset(_DetectionPreset preset) async {
    final values = preset.settings;
    setState(() {
      _motionThreshold = values.motionThreshold;
      _cryScoreThreshold = values.cryScoreThreshold;
      _notifyCooldownSeconds = values.notifyCooldownSeconds;
      _motionDurationSeconds = values.motionDurationSeconds;
      _cryDurationSeconds = values.cryDurationSeconds;
    });
    await _runMutation(() async {
      await Future.wait<void>([
        widget.config.setMotionThreshold(values.motionThreshold),
        widget.config.setCryScoreThreshold(values.cryScoreThreshold),
        widget.config
            .setNotifyCooldownMs((values.notifyCooldownSeconds * 1000).round()),
        widget.config.setMotionMinDurationMs(
          (values.motionDurationSeconds * 1000).round(),
        ),
        widget.config.setCryMinDurationMs(
          (values.cryDurationSeconds * 1000).round(),
        ),
      ]);
    });
    if (mounted) setState(_loadSettings);
  }

  _DetectionPreset? get _activeDetectionPreset {
    for (final preset in _DetectionPreset.values) {
      final values = preset.settings;
      if ((_motionThreshold - values.motionThreshold).abs() < .001 &&
          (_cryScoreThreshold - values.cryScoreThreshold).abs() < .001 &&
          (_notifyCooldownSeconds - values.notifyCooldownSeconds).abs() < .01 &&
          (_motionDurationSeconds - values.motionDurationSeconds).abs() < .01 &&
          (_cryDurationSeconds - values.cryDurationSeconds).abs() < .01) {
        return preset;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ServerSectionHeader(
          title: strings.ui('serverSettings'),
          subtitle: strings.ui('serverSettingsSubtitle'),
        ),
        const SizedBox(height: 10),
        _ServerSettingsCard(
          motionThreshold: _motionThreshold,
          cryScoreThreshold: _cryScoreThreshold,
          notifyCooldownSeconds: _notifyCooldownSeconds,
          motionDurationSeconds: _motionDurationSeconds,
          cryDurationSeconds: _cryDurationSeconds,
          saving: _saving,
          activePreset: _activeDetectionPreset,
          onPresetSelected: (preset) =>
              unawaited(_applyDetectionPreset(preset)),
          onReset: _confirmResetSettings,
          onMotionThresholdChangeEnd: (value) {
            setState(() => _motionThreshold = value);
            unawaited(
              _saveSetting(() => widget.config.setMotionThreshold(value)),
            );
          },
          onCryScoreThresholdChangeEnd: (value) {
            setState(() => _cryScoreThreshold = value);
            unawaited(
              _saveSetting(() => widget.config.setCryScoreThreshold(value)),
            );
          },
          onNotifyCooldownChangeEnd: (value) {
            setState(() => _notifyCooldownSeconds = value);
            unawaited(
              _saveSetting(
                () => widget.config.setNotifyCooldownMs((value * 1000).round()),
              ),
            );
          },
          onMotionDurationChangeEnd: (value) {
            setState(() => _motionDurationSeconds = value);
            unawaited(
              _saveSetting(
                () => widget.config
                    .setMotionMinDurationMs((value * 1000).round()),
              ),
            );
          },
          onCryDurationChangeEnd: (value) {
            setState(() => _cryDurationSeconds = value);
            unawaited(
              _saveSetting(
                () => widget.config.setCryMinDurationMs((value * 1000).round()),
              ),
            );
          },
        ),
        if (widget.runtime.canManageTrustedClients) ...[
          const SizedBox(height: 14),
          ServerTrustedDevicesCard(runtime: widget.runtime),
        ],
      ],
    );
  }
}

enum _DetectionPreset {
  sensitive,
  balanced,
  fewerAlerts;

  IconData get icon => switch (this) {
        sensitive => Icons.hearing_rounded,
        balanced => Icons.balance_rounded,
        fewerAlerts => Icons.notifications_paused_rounded,
      };

  _DetectionPresetSettings get settings => switch (this) {
        sensitive => const _DetectionPresetSettings(
            motionThreshold: .15,
            cryScoreThreshold: .50,
            notifyCooldownSeconds: 45,
            motionDurationSeconds: 1,
            cryDurationSeconds: 1.5,
          ),
        balanced => const _DetectionPresetSettings(
            motionThreshold: .22,
            cryScoreThreshold: .65,
            notifyCooldownSeconds: 60,
            motionDurationSeconds: 2,
            cryDurationSeconds: 1.5,
          ),
        fewerAlerts => const _DetectionPresetSettings(
            motionThreshold: .35,
            cryScoreThreshold: .78,
            notifyCooldownSeconds: 90,
            motionDurationSeconds: 3.5,
            cryDurationSeconds: 2.5,
          ),
      };

  String label(AppStrings strings) => switch (this) {
        sensitive => strings.ui('sensitivePreset'),
        balanced => strings.ui('balancedPreset'),
        fewerAlerts => strings.ui('fewerAlertsPreset'),
      };

  String description(AppStrings strings) => switch (this) {
        sensitive => strings.ui('sensitivePresetDescription'),
        balanced => strings.ui('balancedPresetDescription'),
        fewerAlerts => strings.ui('fewerAlertsPresetDescription'),
      };
}

class _DetectionPresetSettings {
  const _DetectionPresetSettings({
    required this.motionThreshold,
    required this.cryScoreThreshold,
    required this.notifyCooldownSeconds,
    required this.motionDurationSeconds,
    required this.cryDurationSeconds,
  });

  final double motionThreshold;
  final double cryScoreThreshold;
  final double notifyCooldownSeconds;
  final double motionDurationSeconds;
  final double cryDurationSeconds;
}

class _ServerSettingsCard extends StatelessWidget {
  const _ServerSettingsCard({
    required this.motionThreshold,
    required this.cryScoreThreshold,
    required this.notifyCooldownSeconds,
    required this.motionDurationSeconds,
    required this.cryDurationSeconds,
    required this.saving,
    required this.activePreset,
    required this.onPresetSelected,
    required this.onReset,
    required this.onMotionThresholdChangeEnd,
    required this.onCryScoreThresholdChangeEnd,
    required this.onNotifyCooldownChangeEnd,
    required this.onMotionDurationChangeEnd,
    required this.onCryDurationChangeEnd,
  });

  final double motionThreshold;
  final double cryScoreThreshold;
  final double notifyCooldownSeconds;
  final double motionDurationSeconds;
  final double cryDurationSeconds;
  final bool saving;
  final _DetectionPreset? activePreset;
  final ValueChanged<_DetectionPreset> onPresetSelected;
  final VoidCallback onReset;
  final ValueChanged<double> onMotionThresholdChangeEnd;
  final ValueChanged<double> onCryScoreThresholdChangeEnd;
  final ValueChanged<double> onNotifyCooldownChangeEnd;
  final ValueChanged<double> onMotionDurationChangeEnd;
  final ValueChanged<double> onCryDurationChangeEnd;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return MiuCamCard(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                strings.ui('silentSafeDetection'),
                style: const TextStyle(
                  color: MiuCamDesignTokens.serverText,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              _SettingsSaveChip(saving: saving),
              TextButton.icon(
                onPressed: saving ? null : onReset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(strings.ui('resetDefaults')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            strings.ui('detectionSettingsSubtitle'),
            style: const TextStyle(
              color: MiuCamDesignTokens.serverTextMuted,
              fontSize: 14.5,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            strings.ui('quickSetup'),
            style: const TextStyle(
              color: MiuCamDesignTokens.serverText,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _DetectionPreset.values)
                ChoiceChip(
                  selected: activePreset == preset,
                  onSelected: saving ? null : (_) => onPresetSelected(preset),
                  showCheckmark: false,
                  selectedColor:
                      MiuCamDesignTokens.serverCyan.withValues(alpha: .18),
                  backgroundColor: MiuCamDesignTokens.serverSurfaceRaised
                      .withValues(alpha: .74),
                  side: BorderSide(
                    color: activePreset == preset
                        ? MiuCamDesignTokens.serverCyan
                        : MiuCamDesignTokens.serverOutline,
                  ),
                  avatar: Icon(
                    preset.icon,
                    size: 17,
                    color: activePreset == preset
                        ? MiuCamDesignTokens.serverCyan
                        : MiuCamDesignTokens.serverTextMuted,
                  ),
                  labelStyle: TextStyle(
                    color: activePreset == preset
                        ? MiuCamDesignTokens.serverText
                        : MiuCamDesignTokens.serverTextMuted,
                    fontWeight: activePreset == preset
                        ? FontWeight.w900
                        : FontWeight.w700,
                  ),
                  label: Text(preset.label(strings)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            activePreset?.description(strings) ??
                strings.ui('customDetectionPresetDescription'),
            style: const TextStyle(
              color: MiuCamDesignTokens.serverTextMuted,
              fontSize: 13.5,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  strings.ui('advancedSettings'),
                  style: const TextStyle(
                    color: MiuCamDesignTokens.serverText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  strings.ui('advancedSettingsDescription'),
                  style: const TextStyle(
                    color: MiuCamDesignTokens.serverTextMuted,
                  ),
                ),
                iconColor: MiuCamDesignTokens.serverCyan,
                collapsedIconColor: MiuCamDesignTokens.serverTextMuted,
                children: [
                  for (final spec in _sliderSpecs(strings)) ...[
                    _SettingSlider(
                      title: spec.title,
                      description: spec.description,
                      valueLabel: spec.valueLabel,
                      value: spec.value,
                      min: spec.min,
                      max: spec.max,
                      divisions: spec.divisions,
                      color: spec.color,
                      onChangeEnd: spec.onChangeEnd,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          ServerKeyValue(
            strings.ui('localNotification'),
            strings.ui('sentToClientDevice'),
          ),
        ],
      ),
    );
  }

  List<_SettingSliderSpec> _sliderSpecs(AppStrings strings) {
    return [
      _SettingSliderSpec(
        title: strings.ui('cryThreshold'),
        description: strings.ui('cryThresholdDescription'),
        valueLabel: (value) => strings.formatPercent((value * 100).round()),
        value: cryScoreThreshold,
        min: .45,
        max: .95,
        divisions: 50,
        color: MiuCamDesignTokens.serverCyan,
        onChangeEnd: onCryScoreThresholdChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('motionThreshold'),
        description: strings.ui('motionThresholdDescription'),
        valueLabel: (value) => strings.formatPercent((value * 100).round()),
        value: motionThreshold,
        min: .10,
        max: .60,
        divisions: 50,
        color: MiuCamDesignTokens.serverViolet,
        onChangeEnd: onMotionThresholdChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('notificationCooldown'),
        description: strings.ui('notificationCooldownDescription'),
        valueLabel: (value) => localizedSecondsLabel(strings, value),
        value: notifyCooldownSeconds,
        min: 10,
        max: 180,
        divisions: 34,
        color: MiuCamDesignTokens.serverBlue,
        onChangeEnd: onNotifyCooldownChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('cryMinimumDuration'),
        description: strings.ui('cryMinimumDurationDescription'),
        valueLabel: (value) => localizedSecondsLabel(
          strings,
          value,
          fractionDigits: 1,
        ),
        value: cryDurationSeconds,
        min: 1.5,
        max: 6,
        divisions: 9,
        color: MiuCamDesignTokens.serverCyan,
        onChangeEnd: onCryDurationChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('motionMinimumDuration'),
        description: strings.ui('motionMinimumDurationDescription'),
        valueLabel: (value) => localizedSecondsLabel(
          strings,
          value,
          fractionDigits: 1,
        ),
        value: motionDurationSeconds,
        min: 1,
        max: 6,
        divisions: 10,
        color: MiuCamDesignTokens.serverViolet,
        onChangeEnd: onMotionDurationChangeEnd,
      ),
    ];
  }
}

class _SettingSliderSpec {
  const _SettingSliderSpec({
    required this.title,
    required this.description,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.color,
    required this.onChangeEnd,
  });

  final String title;
  final String description;
  final String Function(double value) valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color color;
  final ValueChanged<double> onChangeEnd;
}

class _SettingsSaveChip extends StatelessWidget {
  const _SettingsSaveChip({required this.saving});

  final bool saving;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: saving
            ? MiuCamDesignTokens.serverBlue
            : MiuCamDesignTokens.serverSuccess,
        shape: const StadiumBorder(),
      ),
      child: Text(
        saving ? strings.ui('saving') : strings.ui('realSettings'),
        style: const TextStyle(
          color: MiuCamDesignTokens.serverOnAccent,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SettingSlider extends StatefulWidget {
  const _SettingSlider({
    required this.title,
    required this.description,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.color,
    required this.onChangeEnd,
  });

  final String title;
  final String description;
  final String Function(double value) valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color color;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_SettingSlider> createState() => _SettingSliderState();
}

class _SettingSliderState extends State<_SettingSlider> {
  late double _value;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _value = _safeValue(widget.value);
  }

  @override
  void didUpdateWidget(covariant _SettingSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.value != widget.value) {
      _value = _safeValue(widget.value);
    }
  }

  double _safeValue(double value) =>
      value.clamp(widget.min, widget.max).toDouble();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: MiuCamDesignTokens.serverText,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  widget.valueLabel(_value),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.description,
            style: const TextStyle(
              color: MiuCamDesignTokens.serverTextMuted,
              fontSize: 13.5,
              height: 1.25,
            ),
          ),
          RepaintBoundary(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                tickMarkShape: SliderTickMarkShape.noTickMark,
              ),
              child: Slider(
                activeColor: widget.color,
                inactiveColor:
                    MiuCamDesignTokens.serverOutline.withValues(alpha: .58),
                value: _value,
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                semanticFormatterCallback: widget.valueLabel,
                onChangeStart: (_) => _dragging = true,
                onChanged: (value) {
                  final next = _safeValue(value);
                  if (next == _value) return;
                  setState(() => _value = next);
                },
                onChangeEnd: (value) {
                  _dragging = false;
                  widget.onChangeEnd(value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
