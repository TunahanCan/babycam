/// Severity semantics shared by analysis and notification presentation.
enum AlertSeverity {
  info('info'),
  attention('attention'),
  warning('warning'),
  critical('critical');

  const AlertSeverity(this.wireValue);

  final String wireValue;

  bool get isInterruptive => this != info;

  /// Unknown values stay unknown; an unrecognized server value must not gain
  /// an interruptive notification merely because it contains a known word.
  static AlertSeverity? tryParse(String value) =>
      switch (value.trim().toLowerCase()) {
        'info' || 'low' => info,
        'attention' => attention,
        'warning' || 'medium' => warning,
        'critical' || 'high' => critical,
        _ => null,
      };

  /// Preserves badges for older stored descriptive severity labels. This
  /// permissive interpretation is intentionally separate from sound policy.
  static AlertSeverity? fromLegacyLabel(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('critical') || normalized.contains('high')) {
      return critical;
    }
    if (normalized.contains('warning') || normalized.contains('medium')) {
      return warning;
    }
    if (normalized.contains('attention')) return attention;
    if (normalized.contains('info') || normalized.contains('low')) return info;
    return null;
  }
}
