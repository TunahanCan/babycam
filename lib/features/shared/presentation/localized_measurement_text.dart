import '../../../l10n/app_strings.dart';

String localizedSecondsLabel(
  AppStrings strings,
  num seconds, {
  int fractionDigits = 0,
}) {
  final value = strings.formatNumber(seconds, decimalDigits: fractionDigits);
  if (strings.isChinese) return '$value 秒';
  if (strings.isHindi) return '$value सेकंड';
  if (strings.isArabic) return '$value ث';
  if (strings.locale.languageCode == 'en') return '$value sec';
  return '$value s';
}

String localizedMillisecondsLabel(AppStrings strings, num milliseconds) {
  final value = strings.formatNumber(milliseconds);
  if (strings.isChinese) return '$value 毫秒';
  if (strings.isHindi) return '$value मि.से.';
  if (strings.isArabic) return '$value مللي ثانية';
  return '$value ms';
}
