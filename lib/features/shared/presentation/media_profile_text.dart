import '../../../core/media/adaptive_media_profile.dart';
import '../../../l10n/app_strings.dart';

String localizedMediaProfileLabel(
  AppStrings strings,
  MediaQualityProfile profile,
) {
  final id = profile.id;
  if (id.startsWith('shared_critical')) {
    return _mediaText(
      strings,
      tr: 'Çoklu izleme',
      zh: '多人观看',
      en: 'Multi-view',
      hi: 'बहु-दृश्य',
      es: 'Vista múltiple',
      fr: 'Visionnage multiple',
      de: 'Mehrfachansicht',
      ar: 'مشاهدة متعددة',
    );
  }
  if (id.startsWith('shared_weak')) {
    return '${_normal(strings)} / ${_shared(strings)}';
  }
  if (id.startsWith('weak')) {
    return _weakNetwork(strings);
  }
  if (id.startsWith('critical')) {
    return _criticalNetwork(strings);
  }
  if (id.startsWith('survival')) {
    return _mediaText(
      strings,
      tr: 'Hayatta kalma',
      zh: '保底模式',
      en: 'Survival',
      hi: 'सुरक्षा मोड',
      es: 'Supervivencia',
      fr: 'Survie',
      de: 'Notfallmodus',
      ar: 'وضع البقاء',
    );
  }
  return _normal(strings);
}

String localizedMediaProfileSummary(
  AppStrings strings,
  MediaQualityProfile profile,
) =>
    '${localizedMediaProfileLabel(strings, profile)} · '
    '${profile.width}x${profile.height} · '
    '${profile.targetFps}fps · JPG ${profile.jpegQuality}';

String _normal(AppStrings strings) => _mediaText(
      strings,
      tr: 'Normal',
      zh: '正常',
      en: 'Normal',
      hi: 'सामान्य',
      es: 'Normal',
      fr: 'Normal',
      de: 'Normal',
      ar: 'عادي',
    );

String _shared(AppStrings strings) => _mediaText(
      strings,
      tr: 'paylaşımlı',
      zh: '共享',
      en: 'shared',
      hi: 'साझा',
      es: 'compartido',
      fr: 'partagé',
      de: 'geteilt',
      ar: 'مشترك',
    );

String _weakNetwork(AppStrings strings) => _mediaText(
      strings,
      tr: 'Zayıf ağ',
      zh: '弱网络',
      en: 'Weak network',
      hi: 'कमज़ोर नेटवर्क',
      es: 'Red débil',
      fr: 'Réseau faible',
      de: 'Schwaches Netz',
      ar: 'شبكة ضعيفة',
    );

String _criticalNetwork(AppStrings strings) => _mediaText(
      strings,
      tr: 'Kritik ağ',
      zh: '网络严重',
      en: 'Critical network',
      hi: 'गंभीर नेटवर्क',
      es: 'Red crítica',
      fr: 'Réseau critique',
      de: 'Kritisches Netz',
      ar: 'شبكة حرجة',
    );

String _mediaText(
  AppStrings strings, {
  required String tr,
  required String zh,
  required String en,
  required String hi,
  required String es,
  required String fr,
  required String de,
  required String ar,
}) {
  if (strings.isTurkish) return tr;
  if (strings.isChinese) return zh;
  if (strings.isHindi) return hi;
  if (strings.isSpanish) return es;
  if (strings.isFrench) return fr;
  if (strings.isGerman) return de;
  if (strings.isArabic) return ar;
  return en;
}
