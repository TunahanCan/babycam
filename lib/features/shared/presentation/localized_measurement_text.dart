import '../../../l10n/app_strings.dart';

String localizedSecondsLabel(
  AppStrings strings,
  num seconds, {
  int fractionDigits = 0,
}) {
  final value = seconds.toStringAsFixed(fractionDigits);
  if (strings.isChinese) return '$value 秒';
  if (strings.isHindi) return '$value सेकंड';
  if (strings.isArabic) return '$value ث';
  if (strings.locale.languageCode == 'en') return '$value sec';
  return '$value s';
}
