part of '../client_home_screen.dart';

class _ClientSettingsList extends StatelessWidget {
  const _ClientSettingsList({
    required this.onNotificationsTap,
    required this.onOpenSystemSettings,
    required this.onLanguageTap,
    required this.languageLabel,
    required this.keepScreenAwake,
    required this.onKeepScreenAwakeChanged,
  });

  final VoidCallback onNotificationsTap;
  final Future<bool> Function() onOpenSystemSettings;
  final VoidCallback onLanguageTap;
  final String languageLabel;
  final bool keepScreenAwake;
  final ValueChanged<bool> onKeepScreenAwakeChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      children: [
        _SettingsRow(
          icon: Icons.notifications_none_rounded,
          title: strings.ui('navNotifications'),
          text: strings.ui('notificationsManageText'),
          backgroundColor: MimiCamDesignTokens.blushSoft,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onNotificationsTap,
        ),
        const SizedBox(height: 12),
        _SettingsRow(
          icon: Icons.language_rounded,
          title: strings.ui('language'),
          text: strings.ui('languageSelectText'),
          backgroundColor: MimiCamDesignTokens.mintSoft,
          trailing: SizedBox(
            width: 92,
            child: Text(
              languageLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Color(0xFF4CB89E),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          onTap: onLanguageTap,
        ),
        const SizedBox(height: 12),
        _SettingsRow(
          icon: Icons.nights_stay_rounded,
          title: strings.ui('keepDeviceAwake'),
          text: strings.ui('keepAwakeClientText'),
          backgroundColor: MimiCamDesignTokens.lavenderSoft,
          trailing: Switch(
            value: keepScreenAwake,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF51C796),
            onChanged: onKeepScreenAwakeChanged,
          ),
          onTap: () => onKeepScreenAwakeChanged(!keepScreenAwake),
        ),
        const SizedBox(height: 12),
        _SystemNotificationSettingsCard(
            onOpenSystemSettings: onOpenSystemSettings),
        const SizedBox(height: 28),
        _PrivacyNote(text: strings.ui('serverSettingsHiddenText')),
      ],
    );
  }
}

class _SystemNotificationSettingsCard extends StatelessWidget {
  const _SystemNotificationSettingsCard({required this.onOpenSystemSettings});

  final Future<bool> Function() onOpenSystemSettings;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: MimiCamDesignTokens.cardDecoration().copyWith(
        color: MimiCamDesignTokens.lavenderSoft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.notifications_outlined,
              color: MimiCamDesignTokens.pink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.ui('navNotifications'),
                  style: const TextStyle(
                    color: MimiCamDesignTokens.navy,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  strings.ui('notificationsManageText'),
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 13,
                    height: 1.28,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => unawaited(onOpenSystemSettings()),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(strings.ui('openAppSettings')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.text,
    required this.backgroundColor,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color backgroundColor;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: MimiCamDesignTokens.cardDecoration().copyWith(
            color: backgroundColor,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: .72),
                child: Icon(icon, color: MimiCamDesignTokens.nightPlum),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: MimiCamDesignTokens.cardTitle),
                    const SizedBox(height: 6),
                    Text(
                      text,
                      style: const TextStyle(
                        color: MimiCamDesignTokens.slate,
                        fontSize: 13.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.text,
    required this.active,
    required this.onTap,
  });

  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: ShapeDecoration(
              color: active ? MimiCamDesignTokens.pink : Colors.white,
              shape: StadiumBorder(
                side: BorderSide(
                  color: active
                      ? MimiCamDesignTokens.pink
                      : const Color(0xFFE2E8F0),
                  width: 1.5,
                ),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: active ? Colors.white : MimiCamDesignTokens.nightPlum,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TinyLabel extends StatelessWidget {
  const _TinyLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: MimiCamDesignTokens.pink,
        fontSize: 10.5,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
