import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../core/media/adaptive_media_profile.dart';
import 'src/app_ui_text_catalog.dart';
import 'src/app_ui_text_catalog_extra.dart';

class AppStrings {
  AppStrings(this.locale) {
    if (!_dateSymbolsInitialized) {
      // The bundled initializer installs symbols synchronously; its returned
      // future only reports completion. Sharing alerts also works before a
      // MaterialLocalizations widget has been built.
      unawaited(initializeDateFormatting());
      _dateSymbolsInitialized = true;
    }
  }

  final Locale locale;
  static bool _dateSymbolsInitialized = false;
  final _numberFormats = <String, NumberFormat>{};
  final _percentFormats = <int, NumberFormat>{};

  static const fallbackLocale = Locale('en', 'US');

  static const supportedLocales = [
    fallbackLocale,
    Locale('tr'),
    Locale('zh'),
    Locale('hi'),
    Locale('es'),
    Locale('fr'),
    Locale('de'),
    Locale('ar', 'SA'),
    Locale('ar', 'QA'),
  ];

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static AppStrings of(BuildContext context) {
    final localized = Localizations.of<AppStrings>(context, AppStrings);
    if (localized != null) return localized;
    final locale =
        Localizations.maybeLocaleOf(context) ?? AppStrings.fallbackLocale;
    return AppStrings(locale);
  }

  bool get isTurkish => locale.languageCode == 'tr';
  bool get isChinese => locale.languageCode == 'zh';
  bool get isHindi => locale.languageCode == 'hi';
  bool get isSpanish => locale.languageCode == 'es';
  bool get isFrench => locale.languageCode == 'fr';
  bool get isGerman => locale.languageCode == 'de';
  bool get isArabic => locale.languageCode == 'ar';

  String _t({
    required String tr,
    required String en,
    required String zh,
    String? hi,
    String? es,
    String? fr,
    String? de,
    String? ar,
  }) {
    if (isTurkish) return tr;
    if (isChinese) return zh;
    if (isHindi) return hi ?? en;
    if (isSpanish) return es ?? en;
    if (isFrench) return fr ?? en;
    if (isGerman) return de ?? en;
    if (isArabic) return ar ?? en;
    return en;
  }

  String _variant({
    required int seed,
    required List<String> tr,
    required List<String> en,
    required List<String> zh,
    required List<String> hi,
    required List<String> es,
    required List<String> fr,
    List<String>? de,
    List<String>? ar,
  }) {
    // Seeded variants keep parent messages varied without random output that
    // would make alert tests and history snapshots flaky.
    final values = isTurkish
        ? tr
        : isChinese
            ? zh
            : isHindi
                ? hi
                : isSpanish
                    ? es
                    : isFrench
                        ? fr
                        : isGerman && de != null
                            ? de
                            : isArabic && ar != null
                                ? ar
                                : en;
    return values[seed.abs() % values.length];
  }

  String get _intlLocale => supportedLocales
          .any((supported) => supported.languageCode == locale.languageCode)
      ? locale.toString()
      : fallbackLocale.toString();

  // intl bundles Arabic-Indic number symbols under ar_EG, while its generic
  // ar fallback uses Latin digits. The supported Gulf locales ar-SA/ar-QA
  // use the Arabic-Indic system (Unicode CLDR numbers data).
  String get _numberLocale => isArabic ? 'ar_EG' : _intlLocale;

  String formatNumber(num value,
      {int? decimalDigits, bool useGrouping = false}) {
    if (!value.isFinite) return '—';
    final key = '$decimalDigits:$useGrouping';
    final format = _numberFormats.putIfAbsent(key, () {
      final result = NumberFormat.decimalPattern(_numberLocale);
      if (decimalDigits != null) {
        result.minimumFractionDigits = decimalDigits;
        result.maximumFractionDigits = decimalDigits;
      }
      if (!useGrouping) result.turnOffGrouping();
      return result;
    });
    return format.format(value);
  }

  /// [percentage] is in 0..100 units, not a 0..1 ratio.
  String formatPercent(num percentage, {int decimalDigits = 0}) {
    if (!percentage.isFinite) return '—';
    final format = _percentFormats.putIfAbsent(decimalDigits, () {
      final result = NumberFormat.percentPattern(_numberLocale)
        ..minimumFractionDigits = decimalDigits
        ..maximumFractionDigits = decimalDigits;
      result.turnOffGrouping();
      return result;
    });
    return format.format(percentage / 100);
  }

  String formatDateTime(DateTime time) {
    final text = DateFormat.yMd(_intlLocale).add_jm().format(time.toLocal());
    if (!isArabic) return text;
    return text.replaceAllMapped(RegExp(r'[0-9]'),
        (match) => String.fromCharCode(0x0660 + int.parse(match[0]!)));
  }

  String _decimal(double value) => formatNumber(value, decimalDigits: 1);

  String get alertDetailsUnavailable => _t(
        tr: 'Bu uyarının ayrıntıları bu sürümde gösterilemiyor. Canlı görüntüyü kontrol edin.',
        en: 'Details of this alert are unavailable in this version. Check the live view.',
        zh: '此版本无法显示这条提醒的详情。请查看实时画面。',
        hi: 'इस संस्करण में इस अलर्ट का विवरण उपलब्ध नहीं है। लाइव दृश्य देखें।',
        es: 'Los detalles de esta alerta no están disponibles en esta versión. Revisa la vista en directo.',
        fr: 'Les détails de cette alerte ne sont pas disponibles dans cette version. Vérifiez la vue en direct.',
        de: 'Die Einzelheiten dieser Warnung sind in dieser Version nicht verfügbar. Prüfe die Live-Ansicht.',
        ar: 'تفاصيل هذا التنبيه غير متاحة في هذا الإصدار. تحققي من البث المباشر.',
      );

  String alertShareText({
    required String message,
    required DateTime time,
    required double score,
    required String deviceId,
  }) {
    final timestamp = formatDateTime(time);
    final scoreText = formatPercent(score * 100);
    return _t(
      tr: 'MiuCam uyarısı: $message\nZaman: $timestamp\nSkor: $scoreText\nCihaz: $deviceId',
      en: 'MiuCam alert: $message\nTime: $timestamp\nScore: $scoreText\nDevice: $deviceId',
      zh: 'MiuCam 提醒：$message\n时间：$timestamp\n评分：$scoreText\n设备：$deviceId',
      hi: 'MiuCam अलर्ट: $message\nसमय: $timestamp\nस्कोर: $scoreText\nडिवाइस: $deviceId',
      es: 'Alerta de MiuCam: $message\nFecha y hora: $timestamp\nPuntuación: $scoreText\nDispositivo: $deviceId',
      fr: 'Alerte MiuCam : $message\nDate et heure : $timestamp\nScore : $scoreText\nAppareil : $deviceId',
      de: 'MiuCam-Warnung: $message\nZeit: $timestamp\nWert: $scoreText\nGerät: $deviceId',
      ar: 'تنبيه MiuCam: $message\nالوقت: $timestamp\nالنتيجة: $scoreText\nالجهاز: $deviceId',
    );
  }

  String get appTitle => 'MiuCam';
  String get reset => _t(
      tr: 'Sıfırla',
      en: 'Reset',
      zh: '重置',
      hi: 'रीसेट',
      es: 'Restablecer',
      fr: 'Réinitialiser',
      de: 'Zurücksetzen',
      ar: 'إعادة ضبط');
  String get server => 'Server';
  String get client => 'Client';
  String get selectRoleStatus => _t(
      tr: 'Rol seçin: Server yayın yapar, Client yayını izler.',
      en: 'Choose a role: Server streams, Client watches the stream.',
      zh: '请选择角色：Server 负责直播，Client 负责观看。',
      hi: 'भूमिका चुनें: Server प्रसारण करता है, Client प्रसारण देखता है।',
      es: 'Elige un rol: Server transmite y Client mira la transmisión.',
      fr: 'Choisissez un rôle : Server diffuse, Client regarde le flux.',
      de: 'Rolle wählen: Der Server streamt, der Client sieht zu.',
      ar: 'اختر الدور: الخادم يبث والعميل يشاهد البث.');
  String serverActiveStatus(String url) => _t(
      tr: 'Server aktif. Client cihazlarda bu adresi açın: $url',
      en: 'Server is active. Open this address on client devices: $url',
      zh: 'Server 已启动。请在 Client 设备打开此地址：$url',
      hi: 'Server सक्रिय है। Client उपकरणों पर यह पता खोलें: $url',
      es: 'Server está activo. Abre esta dirección en los dispositivos Client: $url',
      fr: 'Server est actif. Ouvrez cette adresse sur les appareils Client : $url',
      de: 'Server ist aktiv. Öffne diese Adresse auf Client-Geräten: $url',
      ar: 'الخادم نشط. افتح هذا العنوان على أجهزة العميل: $url');
  String get clientSearchingLog => _t(
      tr: 'Client modu: QR veya IP ile eşleşmeye hazır.',
      en: 'Client mode: ready to pair via QR or IP.',
      zh: 'Client 模式：可通过二维码或 IP 配对。',
      hi: 'Client मोड: QR या IP से पेयर करने के लिए तैयार।',
      es: 'Modo Client: listo para emparejar por QR o IP.',
      fr: 'Mode Client : prêt à s’appairer par QR ou IP.',
      de: 'Client-Modus: bereit zum Koppeln per QR oder IP.',
      ar: 'وضع العميل: جاهز للإقران عبر QR أو IP.');
  String get clientActiveStatus => _t(
      tr: 'Client modu aktif. QR veya IP ile bebek odasına bağlan.',
      en: 'Client mode is active. Connect to the baby room via QR or IP.',
      zh: 'Client 模式已启用。请通过二维码或 IP 连接婴儿房。',
      hi: 'Client मोड सक्रिय है। QR या IP से बच्चे के कमरे से जुड़ें।',
      es: 'Modo Client activo. Conecta con la habitación del bebé por QR o IP.',
      fr: 'Mode Client actif. Connectez-vous à la chambre du bébé par QR ou IP.',
      de: 'Client-Modus aktiv. Verbinde dich per QR oder IP mit dem Babyzimmer.',
      ar: 'وضع العميل نشط. اتصل بغرفة الطفل عبر QR أو IP.');
  String get alertWebSocketDisconnected => _t(
      tr: 'Uyarı WebSocket bağlantısı koptu.',
      en: 'Alert WebSocket connection was lost.',
      zh: '提醒 WebSocket 连接已断开。',
      hi: 'चेतावनी WebSocket कनेक्शन टूट गया।',
      es: 'Se perdió la conexión WebSocket de alertas.',
      fr: 'La connexion WebSocket des alertes a été perdue.',
      de: 'Die Alert-WebSocket-Verbindung wurde getrennt.',
      ar: 'انقطع اتصال WebSocket الخاص بالتنبيهات.');
  String clientConnectedStatus(String url) => _t(
      tr: 'Client bağlı: $url',
      en: 'Client connected: $url',
      zh: 'Client 已连接：$url',
      hi: 'Client जुड़ा: $url',
      es: 'Client conectado: $url',
      fr: 'Client connecté : $url',
      de: 'Client verbunden: $url',
      ar: 'العميل متصل: $url');
  String serverAlertLog(String message) => _t(
      tr: 'Server uyarısı: $message',
      en: 'Server alert: $message',
      zh: 'Server 提醒：$message',
      hi: 'Server चेतावनी: $message',
      es: 'Alerta de Server: $message',
      fr: 'Alerte Server : $message',
      de: 'Server-Warnung: $message',
      ar: 'تنبيه الخادم: $message');
  String get roleResetStatus => _t(
      tr: 'Rol sıfırlandı. Server veya Client seçin.',
      en: 'Role reset. Choose Server or Client.',
      zh: '角色已重置。请选择 Server 或 Client。',
      hi: 'भूमिका रीसेट हो गई। Server या Client चुनें।',
      es: 'Rol restablecido. Elige Server o Client.',
      fr: 'Rôle réinitialisé. Choisissez Server ou Client.',
      de: 'Rolle zurückgesetzt. Wähle Server oder Client.',
      ar: 'تمت إعادة ضبط الدور. اختر الخادم أو العميل.');
  String get addressPreparing => _t(
      tr: 'Adres hazırlanıyor...',
      en: 'Preparing address...',
      zh: '正在准备地址…',
      hi: 'पता तैयार हो रहा है…',
      es: 'Preparando dirección…',
      fr: 'Préparation de l’adresse…',
      de: 'Adresse wird vorbereitet...',
      ar: 'يتم تجهيز العنوان...');
  String get serverAddressLabel => _t(
      tr: 'Server adresi (IP veya IP:8080)',
      en: 'Server address (IP or IP:8080)',
      zh: 'Server 地址（IP 或 IP:8080）',
      hi: 'Server पता (IP या IP:8080)',
      es: 'Dirección de Server (IP o IP:8080)',
      fr: 'Adresse Server (IP ou IP:8080)',
      de: 'Server-Adresse (IP oder IP:8080)',
      ar: 'عنوان الخادم (IP أو IP:8080)');
  String get waitingForServer => _t(
      tr: 'Server bekleniyor...',
      en: 'Waiting for server...',
      zh: '等待 Server…',
      hi: 'Server की प्रतीक्षा…',
      es: 'Esperando Server…',
      fr: 'En attente de Server…',
      de: 'Warte auf Server...',
      ar: 'بانتظار الخادم...');

  String get notificationTitle => _t(
      tr: 'MiuCam · Bebek odası',
      en: 'MiuCam · Nursery',
      zh: 'MiuCam · 宝宝房',
      hi: 'MiuCam · बच्चे का कमरा',
      es: 'MiuCam · Habitación del bebé',
      fr: 'MiuCam · Chambre de bébé',
      de: 'MiuCam · Babyzimmer',
      ar: 'MiuCam · غرفة الطفل');

  String alertNotificationTitle({
    required String type,
    required String messageKey,
  }) {
    final normalizedKey = messageKey.trim().toLowerCase();
    final normalizedType = _alertTypeForKey(type, normalizedKey);
    if (normalizedKey == 'parentcryalert' ||
        normalizedKey == 'parentepisodehighcryalert' ||
        normalizedKey == 'parentepisodecryalert' ||
        (normalizedType == 'crydetected' &&
            normalizedKey != 'parentepisodeshortsoundalert')) {
      return _t(
        tr: 'Bebeğin ağlıyor olabilir',
        en: 'Your baby may be crying',
        zh: '宝宝可能在哭',
        hi: 'शायद बच्चा रो रहा है',
        es: 'Puede que tu bebé esté llorando',
        fr: 'Bébé pleure peut-être',
        de: 'Dein Baby weint vielleicht',
        ar: 'قد يكون طفلك يبكي',
      );
    }
    if (normalizedKey == 'parentloudsoundalert' ||
        (normalizedType == 'loudsound' &&
            normalizedKey != 'parentepisodeshortsoundalert')) {
      return _t(
        tr: 'Bebek odasında yüksek ses var',
        en: 'Loud sound detected in the nursery',
        zh: '宝宝房里出现较大声音',
        hi: 'बच्चे के कमरे में तेज़ आवाज़ सुनाई दी',
        es: 'Se oyó un sonido fuerte en la habitación',
        fr: 'Un son fort a été détecté dans la chambre',
        de: 'Lautes Geräusch im Babyzimmer erkannt',
        ar: 'تم رصد صوت عالٍ في غرفة الطفل',
      );
    }
    if (normalizedKey == 'parentepisodeshortsoundalert') {
      return _t(
        tr: 'Bebek odasında bir ses var',
        en: 'Sound detected in the nursery',
        zh: '宝宝房里有声音',
        hi: 'बच्चे के कमरे में आवाज़ सुनाई दी',
        es: 'Se oyó un sonido en la habitación',
        fr: 'Un son a été détecté dans la chambre',
        de: 'Geräusch im Babyzimmer erkannt',
        ar: 'تم رصد صوت في غرفة الطفل',
      );
    }
    if (normalizedKey == 'parentmotionalert' ||
        normalizedType == 'motiondetected') {
      return _t(
        tr: 'Bebek odasında hareket var',
        en: 'Movement detected in the nursery',
        zh: '宝宝房里有动静',
        hi: 'बच्चे के कमरे में हलचल मिली',
        es: 'Movimiento detectado en la habitación',
        fr: 'Mouvement détecté dans la chambre',
        de: 'Bewegung im Babyzimmer erkannt',
        ar: 'تم رصد حركة في غرفة الطفل',
      );
    }
    if (normalizedKey == 'parentlightchangealert' ||
        normalizedType == 'globallightchange') {
      return _t(
        tr: 'Bebek odasının ışığı değişti',
        en: 'The nursery light changed',
        zh: '宝宝房的光线变了',
        hi: 'बच्चे के कमरे की रोशनी बदली',
        es: 'Cambió la luz de la habitación',
        fr: 'La lumière de la chambre a changé',
        de: 'Das Licht im Babyzimmer hat sich verändert',
        ar: 'تغيّرت إضاءة غرفة الطفل',
      );
    }
    if (normalizedKey == 'batterylow' || normalizedType == 'batterylow') {
      return _t(
        tr: 'Bebek odası telefonunun pili azalıyor',
        en: 'The nursery phone battery is low',
        zh: '宝宝房手机电量不足',
        hi: 'बच्चे के कमरे वाले फ़ोन की बैटरी कम है',
        es: 'El teléfono de la habitación tiene poca batería',
        fr: 'Le téléphone de la chambre manque de batterie',
        de: 'Der Akku des Babyzimmer-Handys ist fast leer',
        ar: 'بطارية هاتف غرفة الطفل منخفضة',
      );
    }
    if (normalizedType == 'systemwarning') {
      return _t(
        tr: 'Bebek odasından bir durum notu',
        en: 'Nursery status update',
        zh: '宝宝房状态更新',
        hi: 'बच्चे के कमरे की स्थिति',
        es: 'Novedad de la habitación',
        fr: 'Nouvelle de la chambre',
        de: 'Statushinweis aus dem Babyzimmer',
        ar: 'تحديث من غرفة الطفل',
      );
    }
    return notificationTitle;
  }

  String? alertNotificationBody({
    required String type,
    required String messageKey,
  }) {
    final normalizedKey = messageKey.trim().toLowerCase();
    final normalizedType = _alertTypeForKey(type, normalizedKey);
    if (normalizedKey == 'parentepisodehighcryalert' ||
        normalizedKey == 'parentepisodecryalert') {
      return _addressParent(_t(
        tr: 'Ağlama benzeri ses bir süredir devam ediyor. Müsait olduğunda bir bak.',
        en: 'A cry-like sound has continued for a little while. Take a quick look when you can.',
        zh: '类似哭声持续了一会儿。方便时看一眼吧。',
        hi: 'रोने जैसी आवाज़ कुछ देर से सुनाई दे रही है। समय मिले तो एक बार देख लें।',
        es: 'Se oye un sonido parecido al llanto desde hace un rato. Échale un vistazo cuando puedas.',
        fr: 'Un son ressemblant à des pleurs dure depuis un moment. Regarde quand tu peux.',
        de: 'Seit einer Weile ist ein weinähnliches Geräusch zu hören. Schau kurz nach, wenn du kannst.',
        ar: 'يُسمع صوت يشبه البكاء منذ قليل. ألقي نظرة عندما تستطيعين.',
      ));
    }
    if (normalizedKey == 'parentcryalert' ||
        (normalizedType == 'crydetected' &&
            normalizedKey != 'parentepisodeshortsoundalert')) {
      return _addressParent(_t(
        tr: 'Ağlama benzeri bir ses duydum. Müsait olduğunda bir bak.',
        en: 'I heard a cry-like sound. Take a quick look when you can.',
        zh: '听到了类似哭声。方便时看一眼吧。',
        hi: 'रोने जैसी आवाज़ सुनाई दी। समय मिले तो एक बार देख लें।',
        es: 'Se oye un sonido parecido al llanto. Échale un vistazo cuando puedas.',
        fr: 'Un son ressemble à des pleurs. Regarde quand tu peux.',
        de: 'Ein Geräusch klingt nach Weinen. Schau kurz nach, wenn du kannst.',
        ar: 'سُمع صوت يشبه البكاء. ألقي نظرة عندما تستطيعين.',
      ));
    }
    if (normalizedKey == 'parentepisodeshortsoundalert') {
      return _addressParent(_t(
        tr: 'Kısa bir huzursuzluk sesi oldu ama şimdilik sakin. Tekrarlarsa haber vereceğim.',
        en: 'There was a brief fuss, but it is calm for now. I’ll let you know if it happens again.',
        zh: '刚才有一小段烦躁声，现在已经平静。如果再次出现，我会提醒你。',
        hi: 'थोड़ी देर बेचैनी की आवाज़ आई, लेकिन अभी शांति है। दोबारा होने पर आपको सूचना मिलेगी।',
        es: 'Hubo un breve sonido de inquietud, pero ahora está tranquilo. Te avisaré si se repite.',
        fr: 'Un bref son d’inconfort a été entendu, mais tout est calme maintenant. Je te préviendrai si cela recommence.',
        de: 'Es war kurz ein unruhiges Geräusch zu hören, aber jetzt ist es ruhig. Ich melde mich, wenn es wiederkommt.',
        ar: 'سُمع صوت انزعاج قصير، لكن الوضع هادئ الآن. سأخبركِ إذا تكرر.',
      ));
    }
    if (normalizedKey == 'parentloudsoundalert' ||
        normalizedType == 'loudsound') {
      return _addressParent(_t(
        tr: 'Odada yüksek bir ses duyuldu. Uygun olduğunda görüntüyü kontrol et.',
        en: 'A loud sound was heard in the nursery. Check the video when you can.',
        zh: '宝宝房里听到了较大的声音。方便时看一下画面。',
        hi: 'बच्चे के कमरे में तेज़ आवाज़ सुनाई दी। समय मिले तो वीडियो देख लें।',
        es: 'Se oyó un sonido fuerte en la habitación. Revisa el video cuando puedas.',
        fr: 'Un son fort a été entendu dans la chambre. Regarde la vidéo quand tu peux.',
        de: 'Im Babyzimmer war ein lautes Geräusch zu hören. Schau ins Video, wenn du kannst.',
        ar: 'سُمع صوت عالٍ في غرفة الطفل. راجعي الفيديو عندما تستطيعين.',
      ));
    }
    if (normalizedKey == 'parentmotionalert' ||
        normalizedType == 'motiondetected') {
      return _addressParent(_t(
        tr: 'Kamera görüntüsünde hareket var. Müsait olduğunda bir bak.',
        en: 'There is movement in the nursery view. Take a quick look when you can.',
        zh: '宝宝房画面里有动静。方便时看一眼吧。',
        hi: 'बच्चे के कमरे की तस्वीर में हलचल है। समय मिले तो एक बार देख लें।',
        es: 'Hay movimiento en la imagen de la habitación. Échale un vistazo cuando puedas.',
        fr: 'Il y a du mouvement dans l’image de la chambre. Regarde quand tu peux.',
        de: 'Im Bild des Babyzimmers ist Bewegung zu sehen. Schau kurz nach, wenn du kannst.',
        ar: 'توجد حركة في صورة غرفة الطفل. ألقي نظرة عندما تستطيعين.',
      ));
    }
    if (normalizedKey == 'parentlightchangealert' ||
        normalizedType == 'globallightchange') {
      return _addressParent(_t(
        tr: 'Odanın ışığı değişmiş olabilir. Görüntüyü kontrol edebilirsin.',
        en: 'The nursery light may have changed. You can check the camera view.',
        zh: '宝宝房的光线可能变了。可以看一下摄像头画面。',
        hi: 'बच्चे के कमरे की रोशनी बदली हो सकती है। कैमरा दृश्य देख लें।',
        es: 'Puede haber cambiado la luz de la habitación. Puedes revisar la cámara.',
        fr: 'La lumière de la chambre a peut-être changé. Tu peux vérifier la caméra.',
        de: 'Das Licht im Babyzimmer hat sich vielleicht verändert. Du kannst die Kameraansicht prüfen.',
        ar: 'ربما تغيّرت إضاءة غرفة الطفل. يمكنكِ مراجعة صورة الكاميرا.',
      ));
    }
    if (normalizedKey == 'batterylow' || normalizedType == 'batterylow') {
      return _addressParent(_t(
        tr: 'Bebek odası telefonunu yakında şarja bağlaman iyi olur.',
        en: 'The nursery phone needs to be charged soon.',
        zh: '宝宝房的手机需要尽快充电。',
        hi: 'बच्चे के कमरे वाले फ़ोन को जल्द चार्ज करना होगा।',
        es: 'Conviene cargar pronto el teléfono de la habitación.',
        fr: 'Il faudra bientôt recharger le téléphone de la chambre.',
        de: 'Das Babyzimmer-Handy sollte bald geladen werden.',
        ar: 'يُفضّل شحن هاتف غرفة الطفل قريباً.',
      ));
    }
    if (normalizedType == 'systemwarning') {
      return _addressParent(_t(
        tr: 'MiuCam’den bir durum güncellemesi geldi. Ayrıntıları görmek için uygulamayı açabilirsin.',
        en: 'MiuCam sent a nursery update. Open the app to see the details.',
        zh: 'MiuCam 发来了一条宝宝房动态。打开应用即可查看详情。',
        hi: 'MiuCam ने बच्चे के कमरे से नई जानकारी भेजी है। विवरण देखने के लिए ऐप खोलें।',
        es: 'MiuCam envió una novedad de la habitación. Abre la app para ver los detalles.',
        fr: 'MiuCam a envoyé une nouvelle de la chambre. Ouvre l’app pour voir les détails.',
        de: 'MiuCam hat ein Update aus dem Babyzimmer gesendet. Öffne die App für weitere Details.',
        ar: 'أرسل MiuCam تحديثاً من غرفة الطفل. افتحي التطبيق للاطلاع على التفاصيل.',
      ));
    }
    return null;
  }

  String _alertTypeForKey(String type, String normalizedKey) =>
      switch (normalizedKey) {
        'parentcryalert' ||
        'parentepisodehighcryalert' ||
        'parentepisodecryalert' =>
          'crydetected',
        'parentloudsoundalert' || 'parentepisodeshortsoundalert' => 'loudsound',
        'parentmotionalert' => 'motiondetected',
        'parentlightchangealert' => 'globallightchange',
        'batterylow' => 'batterylow',
        _ => type.trim().toLowerCase(),
      };

  String get notificationChannelName => _t(
      tr: 'MiuCam Uyarıları',
      en: 'MiuCam Alerts',
      zh: 'MiuCam 提醒',
      hi: 'MiuCam अलर्ट',
      es: 'Alertas de MiuCam',
      fr: 'Alertes MiuCam',
      de: 'MiuCam Warnungen',
      ar: 'تنبيهات MiuCam');
  String get notificationUpdatesChannelName => _t(
      tr: 'MiuCam Oda Notları',
      en: 'MiuCam Nursery Updates',
      zh: 'MiuCam 房间动态',
      hi: 'MiuCam कमरे की जानकारी',
      es: 'Novedades de la habitación',
      fr: 'Nouvelles de la chambre',
      de: 'MiuCam Zimmerhinweise',
      ar: 'تحديثات غرفة الطفل');

  /// Pairing errors are deliberately phrased as recovery steps. Raw HTTP and
  /// nonce errors make a stressed caregiver repeat the same failing action.
  String pairingFailureMessage(String code) => switch (code) {
        'payloadExpired' || 'nonceInvalidOrExpired' => _t(
            tr: 'Bu QR kodu kullanılmış ya da süresi dolmuş. Oda telefonunda yeni QR oluşturup tekrar deneyin.',
            en: 'This QR code was used or has expired. Show a new QR code on the room phone and try again.',
            zh: '此二维码已使用或已过期。请在房间手机上显示新的二维码后重试。',
            hi: 'यह QR कोड इस्तेमाल हो चुका है या इसकी समय-सीमा समाप्त हो गई है। कमरे वाले फ़ोन पर नया QR दिखाकर फिर कोशिश करें।',
            es: 'Este código QR ya se usó o caducó. Muestra un código nuevo en el teléfono de la habitación e inténtalo de nuevo.',
            fr: 'Ce code QR a déjà été utilisé ou a expiré. Affichez un nouveau code sur le téléphone de la chambre, puis réessayez.',
            de: 'Dieser QR-Code wurde bereits verwendet oder ist abgelaufen. Zeige auf dem Zimmertelefon einen neuen Code an und versuche es erneut.',
            ar: 'تم استخدام رمز QR هذا أو انتهت صلاحيته. اعرض رمزاً جديداً على هاتف الغرفة ثم حاول مرة أخرى.'),
        'pairingNotActive' => _t(
            tr: 'Oda telefonunda eşleştirme açık değil. Yayın ekranından “Eşleştir”i açıp yeni QR kodu okutun.',
            en: 'Pairing is not open on the room phone. Open Pair on the broadcast screen and scan the new QR code.',
            zh: '房间手机未开启配对。请在直播页面打开“配对”，然后扫描新的二维码。',
            hi: 'कमरे वाले फ़ोन पर पेयरिंग खुली नहीं है। प्रसारण स्क्रीन से पेयरिंग खोलें और नया QR स्कैन करें।',
            es: 'La vinculación no está abierta en el teléfono de la habitación. Abre Vincular en la pantalla de transmisión y escanea el nuevo QR.',
            fr: 'L’association n’est pas ouverte sur le téléphone de la chambre. Ouvrez Associer sur l’écran de diffusion et scannez le nouveau QR.',
            de: 'Auf dem Zimmertelefon ist die Kopplung nicht geöffnet. Öffne auf dem Übertragungsbildschirm „Koppeln“ und scanne den neuen QR-Code.',
            ar: 'الإقران غير مفتوح على هاتف الغرفة. افتح «إقران» من شاشة البث وامسح رمز QR الجديد.'),
        'rateLimited' => _t(
            tr: 'Çok fazla eşleştirme denemesi yapıldı. Bir dakika bekleyip yeni QR koduyla tekrar deneyin.',
            en: 'There were too many pairing attempts. Wait a minute, then try again with a new QR code.',
            zh: '配对尝试过多。请等待一分钟，再使用新的二维码重试。',
            hi: 'बहुत अधिक पेयरिंग प्रयास किए गए। एक मिनट रुकें, फिर नए QR कोड से कोशिश करें।',
            es: 'Hubo demasiados intentos de vinculación. Espera un minuto e inténtalo de nuevo con un código QR nuevo.',
            fr: 'Il y a eu trop de tentatives d’association. Attendez une minute, puis réessayez avec un nouveau code QR.',
            de: 'Es gab zu viele Kopplungsversuche. Warte eine Minute und versuche es dann mit einem neuen QR-Code erneut.',
            ar: 'كان هناك عدد كبير جداً من محاولات الإقران. انتظر دقيقة ثم حاول مرة أخرى برمز QR جديد.'),
        'selfPairingNotAllowed' => _t(
            tr: 'Bir telefon kendi oda yayınına bağlanamaz. İzlemek için diğer telefonu Client modunda kullanın.',
            en: 'A phone cannot connect to its own room broadcast. Use the other phone in Client mode to watch.',
            zh: '手机不能连接到自己的房间直播。请使用另一部处于 Client 模式的手机观看。',
            hi: 'कोई फ़ोन अपने ही कमरे के प्रसारण से नहीं जुड़ सकता। देखने के लिए दूसरे फ़ोन को Client मोड में उपयोग करें।',
            es: 'Un teléfono no puede conectarse a su propia transmisión de habitación. Usa el otro teléfono en modo Client para mirar.',
            fr: 'Un téléphone ne peut pas se connecter à sa propre diffusion de chambre. Utilisez l’autre téléphone en mode Client pour regarder.',
            de: 'Ein Telefon kann sich nicht mit seiner eigenen Zimmerübertragung verbinden. Verwende zum Zuschauen das andere Telefon im Client-Modus.',
            ar: 'لا يمكن للهاتف الاتصال ببث غرفته نفسه. استخدم الهاتف الآخر في وضع العميل للمشاهدة.'),
        'maxTrustedClientsReached' => _t(
            tr: 'Bu oda için izin verilen ebeveyn cihazı sayısına ulaşıldı. Oda telefonundaki bağlı cihazlar listesinden eski bir cihazı kaldırın.',
            en: 'This room has reached its allowed number of parent devices. Remove an old device from the connected-devices list on the room phone.',
            zh: '此房间已达到允许的家长设备数量。请在房间手机的已连接设备列表中移除旧设备。',
            hi: 'इस कमरे के लिए अनुमत अभिभावक डिवाइस की सीमा पूरी हो गई है। कमरे वाले फ़ोन की कनेक्टेड डिवाइस सूची से पुराना डिवाइस हटाएँ।',
            es: 'Esta habitación alcanzó el número permitido de dispositivos parentales. Elimina un dispositivo antiguo de la lista de dispositivos conectados del teléfono de la habitación.',
            fr: 'Cette chambre a atteint le nombre autorisé d’appareils parents. Retirez un ancien appareil de la liste des appareils connectés sur le téléphone de la chambre.',
            de: 'Dieses Zimmer hat die erlaubte Anzahl an Eltern-Geräten erreicht. Entferne ein altes Gerät aus der Liste verbundener Geräte auf dem Zimmertelefon.',
            ar: 'بلغت هذه الغرفة العدد المسموح به من أجهزة الوالدين. أزل جهازاً قديماً من قائمة الأجهزة المتصلة على هاتف الغرفة.'),
        'maxChildProfilesReached' => _t(
            tr: 'Bu telefonda en fazla dört oda kaydedilebilir. Ayarlardan artık kullanmadığınız bir odayı kaldırıp tekrar deneyin.',
            en: 'This phone can save up to four rooms. Remove a room you no longer use in Settings, then try again.',
            zh: '此手机最多可保存四个房间。请在“设置”中移除不再使用的房间后重试。',
            hi: 'इस फ़ोन में अधिकतम चार कमरे सहेजे जा सकते हैं। सेटिंग में जिस कमरे का उपयोग नहीं करते उसे हटाकर फिर कोशिश करें।',
            es: 'Este teléfono puede guardar hasta cuatro habitaciones. Elimina una que ya no uses en Ajustes y vuelve a intentarlo.',
            fr: 'Ce téléphone peut enregistrer jusqu’à quatre chambres. Supprimez une chambre inutilisée dans Réglages, puis réessayez.',
            de: 'Dieses Telefon kann bis zu vier Zimmer speichern. Entferne in den Einstellungen ein nicht mehr verwendetes Zimmer und versuche es erneut.',
            ar: 'يمكن لهذا الهاتف حفظ ما يصل إلى أربع غرف. أزل غرفة لا تستخدمها من الإعدادات ثم حاول مرة أخرى.'),
        'connectionUnavailable' => _t(
            tr: 'Oda telefonuna ulaşılamadı. İki telefonun aynı Wi-Fi ağında olduğundan ve odadaki yayının açık olduğundan emin olun.',
            en: 'The room phone could not be reached. Check that both phones are on the same Wi-Fi network and that the room broadcast is on.',
            zh: '无法连接到房间手机。请确认两部手机连接到同一 Wi-Fi，且房间直播已开启。',
            hi: 'कमरे वाले फ़ोन तक नहीं पहुँचा जा सका। जाँचें कि दोनों फ़ोन एक ही Wi-Fi पर हैं और कमरे का प्रसारण चालू है।',
            es: 'No se pudo localizar el teléfono de la habitación. Comprueba que ambos teléfonos estén en la misma red Wi-Fi y que la transmisión esté activa.',
            fr: 'Le téléphone de la chambre est inaccessible. Vérifiez que les deux téléphones sont sur le même Wi-Fi et que la diffusion est active.',
            de: 'Das Zimmertelefon ist nicht erreichbar. Prüfe, ob beide Telefone im selben WLAN sind und die Zimmerübertragung aktiv ist.',
            ar: 'تعذر الوصول إلى هاتف الغرفة. تأكد من أن الهاتفين على شبكة Wi-Fi نفسها وأن بث الغرفة قيد التشغيل.'),
        'pairingInProgress' => _t(
            tr: 'Eşleştirme zaten sürüyor. Lütfen bağlantı sonucunu bekleyin.',
            en: 'Pairing is already in progress. Please wait for the connection result.',
            zh: '配对正在进行中。请等待连接结果。',
            hi: 'पेयरिंग पहले से चल रही है। कृपया कनेक्शन परिणाम की प्रतीक्षा करें।',
            es: 'La vinculación ya está en curso. Espera el resultado de la conexión.',
            fr: 'L’association est déjà en cours. Attendez le résultat de la connexion.',
            de: 'Die Kopplung läuft bereits. Bitte warte auf das Verbindungsergebnis.',
            ar: 'الإقران جارٍ بالفعل. يرجى انتظار نتيجة الاتصال.'),
        _ => _t(
            tr: 'Şu an bağlanılamadı. İki telefonun aynı Wi-Fi ağında olduğunu kontrol edip yeni QR koduyla tekrar deneyin.',
            en: 'Could not connect right now. Check that both phones are on the same Wi-Fi network, then try again with a new QR code.',
            zh: '暂时无法连接。请确认两部手机在同一 Wi-Fi 网络上，然后使用新的二维码重试。',
            hi: 'अभी कनेक्ट नहीं हो सका। जाँचें कि दोनों फ़ोन एक ही Wi-Fi नेटवर्क पर हैं, फिर नए QR कोड से कोशिश करें।',
            es: 'No se pudo conectar ahora. Comprueba que ambos teléfonos estén en la misma red Wi-Fi e inténtalo de nuevo con un código QR nuevo.',
            fr: 'Connexion impossible pour le moment. Vérifiez que les deux téléphones sont sur le même réseau Wi-Fi, puis réessayez avec un nouveau code QR.',
            de: 'Eine Verbindung ist gerade nicht möglich. Prüfe, ob beide Telefone im selben WLAN sind, und versuche es mit einem neuen QR-Code erneut.',
            ar: 'تعذر الاتصال الآن. تأكد من أن الهاتفين على شبكة Wi-Fi نفسها ثم حاول مرة أخرى برمز QR جديد.'),
      };

  String get cameraNotFound => _t(
      tr: 'Kamera bulunamadı.',
      en: 'Camera not found.',
      zh: '未找到摄像头。',
      hi: 'कैमरा नहीं मिला।',
      es: 'No se encontró la cámara.',
      fr: 'Caméra introuvable.',
      de: 'Kamera nicht gefunden.',
      ar: 'لم يتم العثور على الكاميرا.');
  String get cameraPermissionMissing => _t(
      tr: 'Kamera izni yok; kamera yayını başlatılamadı.',
      en: 'Camera permission is missing; camera streaming could not start.',
      zh: '缺少摄像头权限；无法开始摄像头直播。',
      hi: 'कैमरा अनुमति नहीं है; कैमरा स्ट्रीम शुरू नहीं हो सकी।',
      es: 'Falta el permiso de cámara; no se pudo iniciar la transmisión de cámara.',
      fr: 'L’autorisation caméra manque ; le flux caméra n’a pas pu démarrer.',
      de: 'Kameraberechtigung fehlt; der Kamerastream konnte nicht gestartet werden.',
      ar: 'إذن الكاميرا مفقود؛ تعذر بدء بث الكاميرا.');
  String serverStartedLog(String url) => _t(
      tr: 'Server başladı: $url',
      en: 'Server started: $url',
      zh: 'Server 已启动：$url',
      hi: 'Server शुरू हुआ: $url',
      es: 'Server iniciado: $url',
      fr: 'Server démarré : $url',
      de: 'Server gestartet: $url',
      ar: 'تم تشغيل الخادم: $url');
  String get microphonePermissionMissing => _t(
      tr: 'Mikrofon izni yok; ses analizi devre dışı.',
      en: 'Microphone permission is missing; audio analysis is disabled.',
      zh: '缺少麦克风权限；声音分析已关闭。',
      hi: 'माइक्रोफ़ोन अनुमति नहीं है; ध्वनि विश्लेषण बंद है।',
      es: 'Falta el permiso del micrófono; el análisis de audio está desactivado.',
      fr: 'L’autorisation du microphone manque ; l’analyse audio est désactivée.',
      de: 'Mikrofonberechtigung fehlt; Audioanalyse ist deaktiviert.',
      ar: 'إذن الميكروفون مفقود؛ تم تعطيل تحليل الصوت.');
  String audioAnalysisLog(String summary) => _t(
      tr: 'Ses analizi: $summary',
      en: 'Audio analysis: $summary',
      zh: '声音分析：$summary',
      hi: 'ऑडियो विश्लेषण: $summary',
      es: 'Análisis de audio: $summary',
      fr: 'Analyse audio : $summary',
      de: 'Audioanalyse: $summary',
      ar: 'تحليل الصوت: $summary');
  String audioAlert(String reason, int confidencePercent, String summary) => _t(
        tr: '🔊 $reason. Sinyal gücü ${formatPercent(confidencePercent)}. $summary',
        en: '🔊 $reason. Signal strength ${formatPercent(confidencePercent)}. $summary',
        zh: '🔊 $reason。信号强度 ${formatPercent(confidencePercent)}。$summary',
        hi: '🔊 $reason। संकेत की ताकत ${formatPercent(confidencePercent)}। $summary',
        es: '🔊 $reason. Intensidad de señal ${formatPercent(confidencePercent)}. $summary',
        fr: '🔊 $reason. Intensité du signal ${formatPercent(confidencePercent)}. $summary',
        de: '🔊 $reason. Signalstärke ${formatPercent(confidencePercent)}. $summary',
        ar: '🔊 $reason. قوة الإشارة ${formatPercent(confidencePercent)}. $summary',
      );
  String motionAlert(int scorePercent) => _t(
      tr: '👶 Hareket notu. Skor: ${formatPercent(scorePercent)}',
      en: '👶 Motion note. Score: ${formatPercent(scorePercent)}',
      zh: '👶 活动提示。评分：${formatPercent(scorePercent)}',
      hi: '👶 हलचल नोट। स्कोर: ${formatPercent(scorePercent)}',
      es: '👶 Nota de movimiento. Puntuación: ${formatPercent(scorePercent)}',
      fr: '👶 Note de mouvement. Score : ${formatPercent(scorePercent)}',
      de: '👶 Bewegungsnotiz. Wert: ${formatPercent(scorePercent)}',
      ar: '👶 ملاحظة حركة. النتيجة: ${formatPercent(scorePercent)}');
  String webSocketClientConnected(String address) => _t(
      tr: 'WebSocket client bağlandı: $address',
      en: 'WebSocket client connected: $address',
      zh: 'WebSocket Client 已连接：$address',
      hi: 'WebSocket Client जुड़ा: $address',
      es: 'Client WebSocket conectado: $address',
      fr: 'Client WebSocket connecté : $address',
      de: 'WebSocket-Client verbunden: $address',
      ar: 'عميل WebSocket متصل: $address');

  String get unknownFundamentalFrequency => _t(
      tr: 'belirsiz',
      en: 'unknown',
      zh: '未知',
      hi: 'अज्ञात',
      es: 'desconocido',
      fr: 'inconnu',
      de: 'unbekannt',
      ar: 'غير معروف');
  String get noSoundReason => _t(
      tr: 'Ses yok',
      en: 'No sound',
      zh: '无声音',
      hi: 'कोई आवाज़ नहीं',
      es: 'Sin sonido',
      fr: 'Aucun son',
      de: 'Kein Ton',
      ar: 'لا يوجد صوت');
  String get cryingSound => _t(
      tr: 'ağlama',
      en: 'crying',
      zh: '哭声',
      hi: 'रोना',
      es: 'llanto',
      fr: 'pleurs',
      de: 'Weinen',
      ar: 'بكاء');
  String get moaningSound => _t(
      tr: 'inleme',
      en: 'moaning',
      zh: '低吟声',
      hi: 'कराहना',
      es: 'quejido',
      fr: 'gémissement',
      de: 'Wimmern',
      ar: 'أنين');
  String audioSummary(
          {required double dbfs,
          required double ambientDbfs,
          required String f0,
          required int centroidHz,
          required int bandwidthHz,
          required double zcr,
          required double entropy,
          required int cryPercent,
          required int moanPercent}) =>
      _t(
          tr: 'seviye ${_decimal(dbfs)} dBFS, ortam ${_decimal(ambientDbfs)} dBFS, F0 $f0, merkez ${formatNumber(centroidHz)} Hz, bant ${formatNumber(bandwidthHz)} Hz, ZCR ${formatNumber(zcr, decimalDigits: 2)}, entropi ${formatNumber(entropy, decimalDigits: 2)}, ağlama ${formatPercent(cryPercent)}, inleme ${formatPercent(moanPercent)}',
          en: 'level ${_decimal(dbfs)} dBFS, ambient ${_decimal(ambientDbfs)} dBFS, F0 $f0, center ${formatNumber(centroidHz)} Hz, band ${formatNumber(bandwidthHz)} Hz, ZCR ${formatNumber(zcr, decimalDigits: 2)}, entropy ${formatNumber(entropy, decimalDigits: 2)}, crying ${formatPercent(cryPercent)}, moaning ${formatPercent(moanPercent)}',
          zh: '音量 ${_decimal(dbfs)} dBFS，环境 ${_decimal(ambientDbfs)} dBFS，F0 $f0，中心 ${formatNumber(centroidHz)} Hz，带宽 ${formatNumber(bandwidthHz)} Hz，ZCR ${formatNumber(zcr, decimalDigits: 2)}，熵 ${formatNumber(entropy, decimalDigits: 2)}，哭声 ${formatPercent(cryPercent)}，低吟 ${formatPercent(moanPercent)}',
          hi: 'स्तर ${_decimal(dbfs)} dBFS, परिवेश ${_decimal(ambientDbfs)} dBFS, F0 $f0, केंद्र ${formatNumber(centroidHz)} Hz, बैंड ${formatNumber(bandwidthHz)} Hz, ZCR ${formatNumber(zcr, decimalDigits: 2)}, एंट्रॉपी ${formatNumber(entropy, decimalDigits: 2)}, रोना ${formatPercent(cryPercent)}, कराहना ${formatPercent(moanPercent)}',
          es: 'nivel ${_decimal(dbfs)} dBFS, ambiente ${_decimal(ambientDbfs)} dBFS, F0 $f0, centro ${formatNumber(centroidHz)} Hz, banda ${formatNumber(bandwidthHz)} Hz, ZCR ${formatNumber(zcr, decimalDigits: 2)}, entropía ${formatNumber(entropy, decimalDigits: 2)}, llanto ${formatPercent(cryPercent)}, quejido ${formatPercent(moanPercent)}',
          fr: 'niveau ${_decimal(dbfs)} dBFS, ambiance ${_decimal(ambientDbfs)} dBFS, F0 $f0, centre ${formatNumber(centroidHz)} Hz, bande ${formatNumber(bandwidthHz)} Hz, ZCR ${formatNumber(zcr, decimalDigits: 2)}, entropie ${formatNumber(entropy, decimalDigits: 2)}, pleurs ${formatPercent(cryPercent)}, gémissement ${formatPercent(moanPercent)}',
          de: 'Pegel ${_decimal(dbfs)} dBFS, Raum ${_decimal(ambientDbfs)} dBFS, F0 $f0, Zentrum ${formatNumber(centroidHz)} Hz, Band ${formatNumber(bandwidthHz)} Hz, ZCR ${formatNumber(zcr, decimalDigits: 2)}, Entropie ${formatNumber(entropy, decimalDigits: 2)}, Weinen ${formatPercent(cryPercent)}, Wimmern ${formatPercent(moanPercent)}',
          ar: 'المستوى ${_decimal(dbfs)} dBFS، الغرفة ${_decimal(ambientDbfs)} dBFS، F0 $f0، المركز ${formatNumber(centroidHz)} Hz، النطاق ${formatNumber(bandwidthHz)} Hz، ZCR ${formatNumber(zcr, decimalDigits: 2)}، الإنتروبيا ${formatNumber(entropy, decimalDigits: 2)}، البكاء ${formatPercent(cryPercent)}، الأنين ${formatPercent(moanPercent)}');
  String pitchSuffix(int fundamentalHz) => fundamentalHz > 0
      ? _t(
          tr: ', temel frekans ${formatNumber(fundamentalHz)} Hz',
          en: ', fundamental frequency ${formatNumber(fundamentalHz)} Hz',
          zh: '，基频 ${formatNumber(fundamentalHz)} Hz',
          hi: ', मूल आवृत्ति ${formatNumber(fundamentalHz)} Hz',
          es: ', frecuencia fundamental ${formatNumber(fundamentalHz)} Hz',
          fr: ', fréquence fondamentale ${formatNumber(fundamentalHz)} Hz',
          de: ', Grundfrequenz ${formatNumber(fundamentalHz)} Hz',
          ar: '، التردد الأساسي ${formatNumber(fundamentalHz)} Hz')
      : '';
  String cryLikeReason(String pitch, int centroidHz) => _t(
      tr: 'Ağlama benzeri vokal ses$pitch, parlaklık ${formatNumber(centroidHz)} Hz',
      en: 'Cry-like vocal sound$pitch, brightness ${formatNumber(centroidHz)} Hz',
      zh: '类似哭声的人声$pitch，明亮度 ${formatNumber(centroidHz)} Hz',
      hi: 'रोने जैसी स्वर ध्वनि$pitch, चमक ${formatNumber(centroidHz)} Hz',
      es: 'Sonido vocal similar al llanto$pitch, brillo ${formatNumber(centroidHz)} Hz',
      fr: 'Son vocal semblable à des pleurs$pitch, brillance ${formatNumber(centroidHz)} Hz',
      de: 'Weinähnlicher Stimmton$pitch, Helligkeit ${formatNumber(centroidHz)} Hz',
      ar: 'صوت صوتي يشبه البكاء$pitch، السطوع ${formatNumber(centroidHz)} Hz');
  String moanLikeReason(String pitch, int centroidHz) => _t(
      tr: 'İnleme benzeri düşük frekanslı sürekli ses$pitch, merkez ${formatNumber(centroidHz)} Hz',
      en: 'Moan-like low-frequency sustained sound$pitch, center ${formatNumber(centroidHz)} Hz',
      zh: '类似低频持续低吟的声音$pitch，中心 ${formatNumber(centroidHz)} Hz',
      hi: 'कराह जैसी कम-आवृत्ति की लगातार ध्वनि$pitch, केंद्र ${formatNumber(centroidHz)} Hz',
      es: 'Sonido sostenido de baja frecuencia similar a un quejido$pitch, centro ${formatNumber(centroidHz)} Hz',
      fr: 'Son grave soutenu semblable à un gémissement$pitch, centre ${formatNumber(centroidHz)} Hz',
      de: 'Wimmerähnlicher tiefer Dauerton$pitch, Zentrum ${formatNumber(centroidHz)} Hz',
      ar: 'صوت منخفض مستمر يشبه الأنين$pitch، المركز ${formatNumber(centroidHz)} Hz');

  String get streamActiveHtml => _t(
      tr: 'LAN MJPEG yayını aktif.',
      en: 'LAN MJPEG stream is active.',
      zh: 'LAN MJPEG 直播已启动。',
      hi: 'LAN MJPEG स्ट्रीम सक्रिय है।',
      es: 'La transmisión LAN MJPEG está activa.',
      fr: 'Le flux LAN MJPEG est actif.',
      de: 'LAN-MJPEG-Stream ist aktiv.',
      ar: 'بث LAN MJPEG نشط.');
  String get audioOnlyHtml => _t(
      tr: 'Sadece WAV ses akışı',
      en: 'WAV audio stream only',
      zh: '仅 WAV 音频流',
      hi: 'केवल WAV ऑडियो स्ट्रीम',
      es: 'Solo flujo de audio WAV',
      fr: 'Flux audio WAV uniquement',
      de: 'Nur WAV-Audiostream',
      ar: 'بث صوت WAV فقط');

  String parentCryAlert({
    required int confidencePercent,
    required double ambientDeltaDb,
    required int cryBandPercent,
    required bool calibrated,
  }) {
    final calibration = calibrated
        ? _t(
            tr: 'Oda sesine göre kalibre.',
            en: 'Calibrated for room sound.',
            zh: '已按房间噪声校准',
            hi: 'कमरे की आवाज़ के अनुसार सेट',
            es: 'Calibrado según el ruido de la habitación.',
            fr: 'Calibré selon le bruit de la pièce.',
            de: 'Auf Raumgeräusch kalibriert.',
            ar: 'تمت المعايرة حسب صوت الغرفة.')
        : _t(
            tr: 'Kalibrasyon sürüyor.',
            en: 'Calibrating.',
            zh: '正在校准',
            hi: 'कैलिब्रेशन जारी है',
            es: 'Calibrando.',
            fr: 'Calibrage en cours.',
            de: 'Kalibrierung läuft.',
            ar: 'المعايرة قيد التنفيذ.');
    final delta = _decimal(ambientDeltaDb);
    final signal = _signalLabel(confidencePercent);
    final seed = confidencePercent +
        cryBandPercent +
        ambientDeltaDb.round() +
        (calibrated ? 1 : 0);
    return _addressParent(_variant(
      seed: seed,
      tr: [
        '👶 Bebeğin ağlıyor olabilir ($signal). Ses oda seviyesinin $delta dB üstünde; ağlama sinyali ${formatPercent(cryBandPercent)}. $calibration Sakin bir kontrol iyi olur: konfor, bez, beslenme, gaz veya sıcaklık.',
        '🍼 Küçük bir oda kontrolü gerekebilir ($signal). Ses $delta dB yükseldi; ağlama sinyali ${formatPercent(cryBandPercent)}. $calibration Bebeğinin neye ihtiyaç duyduğunu nazikçe kontrol et.',
        '🔊 Ağlama benzeri bir ses fark edildi ($signal). Oda sesinin $delta dB üstünde; ağlama sinyali ${formatPercent(cryBandPercent)}. $calibration Telaşlanmadan görüntüye bak.',
      ],
      en: [
        '👶 Baby may be crying ($signal). Sound is $delta dB above the room level; cry signal is ${formatPercent(cryBandPercent)}. $calibration A calm check may help: comfort, diaper, feeding, gas, or temperature.',
        '🍼 A gentle room check may be helpful ($signal). Audio rose $delta dB; cry signal is ${formatPercent(cryBandPercent)}. $calibration Please look in calmly and see what baby needs.',
        '🔊 Cry-like sound noticed ($signal). It is $delta dB above room level; cry signal is ${formatPercent(cryBandPercent)}. $calibration Please check the video without rushing.',
      ],
      zh: [
        '👶 宝宝可能在哭（$signal）。声音比房间基线高 $delta dB；哭声信号 ${formatPercent(cryBandPercent)}。$calibration。请平静查看：安抚、尿布、喂奶、胀气或温度。',
        '🍼 也许需要轻轻看一眼（$signal）。声音上升 $delta dB；哭声信号 ${formatPercent(cryBandPercent)}。$calibration。请安心查看宝宝需要什么。',
        '🔊 注意到类似哭声（$signal）。比房间基线高 $delta dB；哭声信号 ${formatPercent(cryBandPercent)}。$calibration。请不慌不忙地查看画面。',
      ],
      hi: [
        '👶 बच्चा रो रहा हो सकता है ($signal)। आवाज़ कमरे के स्तर से $delta dB ऊपर है; रोने का संकेत ${formatPercent(cryBandPercent)} है। $calibration। शांति से देखें: आराम, डायपर, दूध, गैस या तापमान।',
        '🍼 कमरे में हल्की जाँच मदद कर सकती है ($signal)। आवाज़ $delta dB बढ़ी; रोने का संकेत ${formatPercent(cryBandPercent)} है। $calibration। प्यार से देखें कि बच्चे को क्या चाहिए।',
        '🔊 रोने जैसी आवाज़ नोट हुई ($signal)। यह कमरे के स्तर से $delta dB ऊपर है; रोने का संकेत ${formatPercent(cryBandPercent)} है। $calibration। बिना घबराए वीडियो देखें।',
      ],
      es: [
        '👶 Puede que el bebé esté llorando ($signal). El sonido está $delta dB sobre el nivel de la habitación; señal de llanto ${formatPercent(cryBandPercent)}. $calibration Revisa con calma: consuelo, pañal, toma, gases o temperatura.',
        '🍼 Quizá venga bien una mirada tranquila ($signal). El audio subió $delta dB; señal de llanto ${formatPercent(cryBandPercent)}. $calibration Mira sin prisa qué necesita el bebé.',
        '🔊 Se notó un sonido parecido al llanto ($signal). Está $delta dB sobre el nivel de la habitación; señal de llanto ${formatPercent(cryBandPercent)}. $calibration Revisa el video con calma.',
      ],
      fr: [
        '👶 Bébé pleure peut-être ($signal). Le son est $delta dB au-dessus du niveau de la pièce ; signal de pleurs ${formatPercent(cryBandPercent)}. $calibration Vérifie calmement : réconfort, couche, repas, gaz ou température.',
        '🍼 Un petit coup d’œil peut aider ($signal). Le son a monté de $delta dB ; signal de pleurs ${formatPercent(cryBandPercent)}. $calibration Regarde tranquillement ce dont bébé a besoin.',
        '🔊 Un son proche de pleurs a été remarqué ($signal). Il est $delta dB au-dessus du niveau de la pièce ; signal de pleurs ${formatPercent(cryBandPercent)}. $calibration Regarde la vidéo sans te presser.',
      ],
      de: [
        '👶 Das Baby könnte weinen ($signal). Der Ton liegt $delta dB über dem Zimmerpegel; Weinsignal ${formatPercent(cryBandPercent)}. $calibration Eine ruhige Kontrolle hilft: Trost, Windel, Füttern, Bauchweh oder Temperatur.',
        '🍼 Ein sanfter Blick ins Zimmer kann helfen ($signal). Audio stieg um $delta dB; Weinsignal ${formatPercent(cryBandPercent)}. $calibration Schau in Ruhe, was das Baby braucht.',
        '🔊 Weinähnlicher Ton bemerkt ($signal). Er liegt $delta dB über dem Zimmerpegel; Weinsignal ${formatPercent(cryBandPercent)}. $calibration Prüfe das Video ohne Eile.',
      ],
      ar: [
        '👶 ربما يبكي الطفل ($signal). الصوت أعلى من مستوى الغرفة بـ $delta dB؛ إشارة البكاء ${formatPercent(cryBandPercent)}. $calibration تحققي بهدوء: الراحة أو الحفاض أو الرضاعة أو الغازات أو الحرارة.',
        '🍼 قد تساعد نظرة هادئة إلى الغرفة ($signal). ارتفع الصوت $delta dB؛ إشارة البكاء ${formatPercent(cryBandPercent)}. $calibration تحققي بلطف مما يحتاجه الطفل.',
        '🔊 لوحظ صوت يشبه البكاء ($signal). أعلى من مستوى الغرفة بـ $delta dB؛ إشارة البكاء ${formatPercent(cryBandPercent)}. $calibration راجعي الفيديو بهدوء.',
      ],
    ));
  }

  String parentLoudSoundAlert({
    required double dbfs,
    required double ambientDeltaDb,
  }) {
    final level = _decimal(dbfs);
    final delta = _decimal(ambientDeltaDb);
    final seed = (dbfs.abs() + ambientDeltaDb).floor();
    return _addressParent(_variant(
      seed: seed,
      tr: [
        '🔔 Odada kısa bir ses yükselmesi oldu. Seviye $level dBFS; oda sesinden $delta dB yüksek. Bebeğinin rahat olduğundan nazikçe emin ol.',
        '🚪 Kısa ve belirgin bir ses duyuldu. Seviye $level dBFS, oda seviyesinin $delta dB üstünde. Kapı, oyuncak veya ev sesi olabilir; sakin bir bakış yeterli.',
        '🔊 Ses bir an yükseldi ($level dBFS). Oda farkı $delta dB. Bebeğin uyuyorsa görüntüyü sessizce kontrol et.',
      ],
      en: [
        '🔔 A brief sound rise happened in the room. Level $level dBFS; $delta dB above room level. Please gently check that baby is comfortable.',
        '🚪 A short, clear sound was heard. Level $level dBFS, $delta dB above room level. It may be a door, toy, or home sound; a calm look is enough.',
        '🔊 Audio rose for a moment ($level dBFS). Room difference is $delta dB. If baby is sleeping, quietly check the video.',
      ],
      zh: [
        '🔔 房间里有短暂声音升高。音量 $level dBFS，比房间基线高 $delta dB。请轻轻确认宝宝是否舒适。',
        '🚪 听到短促清楚的声音。音量 $level dBFS，比房间基线高 $delta dB。可能是门、玩具或家中声音；平静看一眼即可。',
        '🔊 声音短暂升高（$level dBFS）。比房间基线高 $delta dB。如果宝宝在睡觉，请安静查看画面。',
      ],
      hi: [
        '🔔 कमरे में थोड़ी देर आवाज़ बढ़ी। स्तर $level dBFS; कमरे के स्तर से $delta dB ऊपर। प्यार से देख लें कि बच्चा आराम में है।',
        '🚪 छोटी और साफ़ आवाज़ सुनी गई। स्तर $level dBFS, कमरे के स्तर से $delta dB ऊपर। यह दरवाज़ा, खिलौना या घर की आवाज़ हो सकती है; शांत होकर देखें।',
        '🔊 आवाज़ पल भर के लिए बढ़ी ($level dBFS)। कमरे से फर्क $delta dB है। बच्चा सो रहा हो तो वीडियो चुपचाप देखें।',
      ],
      es: [
        '🔔 Hubo una subida breve de sonido. Nivel $level dBFS; $delta dB sobre la habitación. Revisa con suavidad que el bebé esté cómodo.',
        '🚪 Se oyó un sonido corto y claro. Nivel $level dBFS, $delta dB sobre la habitación. Puede ser puerta, juguete o ruido de casa; basta una mirada tranquila.',
        '🔊 El audio subió un momento ($level dBFS). Diferencia con la habitación: $delta dB. Si el bebé duerme, mira el video en silencio.',
      ],
      fr: [
        '🔔 Brève hausse sonore dans la chambre. Niveau $level dBFS ; $delta dB au-dessus du niveau de la pièce. Vérifie doucement que bébé va bien.',
        '🚪 Un son court et net a été entendu. Niveau $level dBFS, $delta dB au-dessus de la pièce. Porte, jouet ou bruit de maison possible ; un regard calme suffit.',
        '🔊 L’audio a monté un instant ($level dBFS). Écart avec la pièce : $delta dB. Si bébé dort, vérifiez la vidéo discrètement.',
      ],
      de: [
        '🔔 Kurzer Tonanstieg im Zimmer. Pegel $level dBFS; $delta dB über dem Zimmerpegel. Schau sanft nach, ob es dem Baby gut geht.',
        '🚪 Ein kurzer, klarer Ton wurde gehört. Pegel $level dBFS, $delta dB über dem Zimmerpegel. Tür, Spielzeug oder Alltagsgeräusch möglich; ein ruhiger Blick reicht.',
        '🔊 Audio stieg kurz an ($level dBFS). Abstand zum Zimmerpegel: $delta dB. Wenn das Baby schläft, prüfe das Video leise.',
      ],
      ar: [
        '🔔 حدث ارتفاع صوت قصير في الغرفة. المستوى $level dBFS؛ أعلى من مستوى الغرفة بـ $delta dB. تحققي بلطف أن الطفل مرتاح.',
        '🚪 سُمع صوت قصير وواضح. المستوى $level dBFS، أعلى من مستوى الغرفة بـ $delta dB. قد يكون باباً أو لعبة أو صوتاً منزلياً؛ تكفي نظرة هادئة.',
        '🔊 ارتفع الصوت للحظة ($level dBFS). الفرق عن الغرفة $delta dB. إذا كان الطفل نائماً، راجعي الفيديو بهدوء.',
      ],
    ));
  }

  String parentMotionAlert({
    required int scorePercent,
    required int activeAreaPercent,
    required double meanDiff,
  }) {
    final mean = _decimal(meanDiff);
    final seed = scorePercent + activeAreaPercent + meanDiff.round();
    return _addressParent(_variant(
      seed: seed,
      tr: [
        '👶 Kamera görüntüsünde hafif hareket fark edildi (${formatPercent(scorePercent)}). Görüntünün yaklaşık ${formatPercent(activeAreaPercent)} bölümü değişti; ortalama değişim $mean. Bebeğinin rahat pozisyonda olduğundan emin ol.',
        '🧸 Görüntünün bir bölümünde değişim var (${formatPercent(scorePercent)}). Değişen alan ${formatPercent(activeAreaPercent)}, ortalama fark $mean. Örtü ve yatak çevresini sakin bir bakışla kontrol et.',
        '📹 Kamera bir hareket sinyali gönderdi (${formatPercent(scorePercent)}). Aktif alan ${formatPercent(activeAreaPercent)}; değişim $mean. Görüntüye bakıp her şeyin yolunda olduğunu doğrula.',
      ],
      en: [
        '👶 Gentle movement appeared in the camera view (${formatPercent(scorePercent)}). About ${formatPercent(activeAreaPercent)} of the image changed; average change $mean. Make sure baby is resting comfortably.',
        '🧸 A change appeared in part of the image (${formatPercent(scorePercent)}). Changed area ${formatPercent(activeAreaPercent)}, average difference $mean. Calmly check the blanket and crib area.',
        '📹 The camera detected a motion signal (${formatPercent(scorePercent)}). Active area ${formatPercent(activeAreaPercent)}; change $mean. Look at the video and confirm all is well.',
      ],
      zh: [
        '👶 摄像头画面出现轻微变化（${formatPercent(scorePercent)}）。约 ${formatPercent(activeAreaPercent)} 的画面发生变化；平均变化 $mean。请确认宝宝睡得舒服。',
        '🧸 画面的一部分出现变化（${formatPercent(scorePercent)}）。变化区域 ${formatPercent(activeAreaPercent)}，平均差异 $mean。请平静检查毯子和婴儿床周围。',
        '📹 摄像头检测到活动信号（${formatPercent(scorePercent)}）。活动区域 ${formatPercent(activeAreaPercent)}；变化 $mean。看一眼画面，确认一切安好。',
      ],
      hi: [
        '👶 कैमरा दृश्य में हल्का बदलाव दिखा (${formatPercent(scorePercent)})। चित्र का लगभग ${formatPercent(activeAreaPercent)} हिस्सा बदला; औसत बदलाव $mean। देखें कि बच्चा आराम से लेटा है।',
        '🧸 तस्वीर के एक हिस्से में बदलाव है (${formatPercent(scorePercent)})। बदला हुआ क्षेत्र ${formatPercent(activeAreaPercent)}, औसत फर्क $mean। कंबल और पालने के आसपास शांति से देखें।',
        '📹 कैमरे ने गतिविधि संकेत भेजा (${formatPercent(scorePercent)})। सक्रिय क्षेत्र ${formatPercent(activeAreaPercent)}; बदलाव $mean। वीडियो देखकर पुष्टि करें कि सब ठीक है।',
      ],
      es: [
        '👶 Se notó un cambio suave en la imagen (${formatPercent(scorePercent)}). Cambió cerca del ${formatPercent(activeAreaPercent)} de la imagen; cambio medio $mean. Confirma que el bebé esté cómodo.',
        '🧸 Hay un cambio en una parte de la imagen (${formatPercent(scorePercent)}). Área modificada ${formatPercent(activeAreaPercent)}, diferencia media $mean. Revisa con calma la manta y la cuna.',
        '📹 La cámara envió una nota de movimiento (${formatPercent(scorePercent)}). Área activa ${formatPercent(activeAreaPercent)}; cambio $mean. Mira el video y confirma que todo esté bien.',
      ],
      fr: [
        '👶 Léger changement dans l’image (${formatPercent(scorePercent)}). Environ ${formatPercent(activeAreaPercent)} de l’image a changé ; variation moyenne $mean. Vérifie que bébé est bien installé.',
        '🧸 Une partie de l’image a changé (${formatPercent(scorePercent)}). Zone modifiée ${formatPercent(activeAreaPercent)}, écart moyen $mean. Vérifie calmement la couverture et le lit.',
        '📹 La caméra a détecté un mouvement (${formatPercent(scorePercent)}). Zone active ${formatPercent(activeAreaPercent)} ; variation $mean. Regarde la vidéo et vérifie que tout va bien.',
      ],
      de: [
        '👶 Sanfte Bildveränderung bemerkt (${formatPercent(scorePercent)}). Etwa ${formatPercent(activeAreaPercent)} des Bildes änderte sich; mittlere Änderung $mean. Vergewissere dich, dass das Baby bequem liegt.',
        '🧸 Ein Teil des Bildes hat sich verändert (${formatPercent(scorePercent)}). Geänderter Bereich ${formatPercent(activeAreaPercent)}, mittlere Differenz $mean. Prüfe Decke und Babybett in Ruhe.',
        '📹 Die Kamera sendet eine Bewegungsnotiz (${formatPercent(scorePercent)}). Aktiver Bereich ${formatPercent(activeAreaPercent)}; Änderung $mean. Schau ins Video und bestätige, dass alles gut ist.',
      ],
      ar: [
        '👶 لوحظ تغير خفيف في صورة الكاميرا (${formatPercent(scorePercent)}). تغيّر نحو ${formatPercent(activeAreaPercent)} من الصورة؛ متوسط التغير $mean. تأكدي أن الطفل مستريح.',
        '🧸 ظهر تغير في جزء من الصورة (${formatPercent(scorePercent)}). المنطقة المتغيرة ${formatPercent(activeAreaPercent)}، ومتوسط الفرق $mean. تحققي من البطانية ومحيط السرير بهدوء.',
        '📹 رصدت الكاميرا حركة (${formatPercent(scorePercent)}). المنطقة النشطة ${formatPercent(activeAreaPercent)}؛ التغير $mean. راجعي الفيديو وتأكدي أن كل شيء بخير.',
      ],
    ));
  }

  String parentLightChangeAlert({
    required int scorePercent,
    required double lumaShift,
  }) {
    final shift = _decimal(lumaShift);
    final seed = scorePercent + lumaShift.round();
    return _addressParent(_variant(
      seed: seed,
      tr: [
        '💡 Oda ışığı değişmiş olabilir (${formatPercent(scorePercent)}). Parlaklık farkı $shift. Gece lambası, perde ya da kapı aralığı etkili olabilir; görüntüye sakin bir bakış yeterli.',
        '🌙 Işık seviyesi farklı görünüyor (${formatPercent(scorePercent)}). Parlaklık kayması $shift. Kamera görüntüsünü nazikçe kontrol et.',
        '📷 Kamera ışık değişimi notu gönderdi (${formatPercent(scorePercent)}). Parlaklık değişimi $shift. Hareketten çok ışık gibi görünüyor; yine de bir kez bak.',
      ],
      en: [
        '💡 Room light may have changed (${formatPercent(scorePercent)}). Brightness difference $shift. Night light, curtain, or door gap may be affecting the view; a calm look is enough.',
        '🌙 Light level looks different (${formatPercent(scorePercent)}). Brightness shift $shift. Please gently check the camera view.',
        '📷 Camera sent a light-change note (${formatPercent(scorePercent)}). Brightness shift $shift. It looks more like light than motion; still, take one look.',
      ],
      zh: [
        '💡 房间光线可能有变化（${formatPercent(scorePercent)}）。亮度差 $shift。夜灯、窗帘或门缝可能影响画面；平静看一眼即可。',
        '🌙 光线水平看起来不同（${formatPercent(scorePercent)}）。亮度偏移 $shift。请轻轻查看摄像头画面。',
        '📷 摄像头发送了光线变化提示（${formatPercent(scorePercent)}）。亮度变化 $shift。更像光线而不是动作；仍建议看一次。',
      ],
      hi: [
        '💡 कमरे की रोशनी बदल सकती है (${formatPercent(scorePercent)})। चमक अंतर $shift। नाइट लाइट, पर्दा या दरवाज़े की दरार असर कर सकती है; शांत होकर देखना पर्याप्त है।',
        '🌙 रोशनी का स्तर अलग दिख रहा है (${formatPercent(scorePercent)})। चमक बदलाव $shift। कैमरा दृश्य प्यार से देख लें।',
        '📷 कैमरे ने रोशनी बदलाव की सूचना भेजी (${formatPercent(scorePercent)})। चमक में बदलाव $shift। यह हलचल से ज़्यादा रोशनी जैसा लगता है; फिर भी एक बार देखें।',
      ],
      es: [
        '💡 Puede haber cambiado la luz de la habitación (${formatPercent(scorePercent)}). Diferencia de brillo $shift. Luz nocturna, cortina o puerta pueden afectar la vista; una mirada tranquila basta.',
        '🌙 El nivel de luz se ve distinto (${formatPercent(scorePercent)}). Desplazamiento de brillo $shift. Revisa la cámara con calma.',
        '📷 La cámara envió una nota de cambio de luz (${formatPercent(scorePercent)}). Cambio de brillo $shift. Parece más luz que movimiento; aun así mira una vez.',
      ],
      fr: [
        '💡 La lumière de la chambre a peut-être changé (${formatPercent(scorePercent)}). Écart de luminosité $shift. Veilleuse, rideau ou porte entrouverte peuvent influencer l’image ; un regard calme suffit.',
        '🌙 Le niveau de lumière semble différent (${formatPercent(scorePercent)}). Décalage de luminosité $shift. Vérifie doucement la caméra.',
        '📷 La caméra a envoyé une note de lumière (${formatPercent(scorePercent)}). Variation de luminosité $shift. Cela ressemble plus à la lumière qu’à un mouvement ; regardez quand même une fois.',
      ],
      de: [
        '💡 Das Zimmerlicht hat sich vielleicht geändert (${formatPercent(scorePercent)}). Helligkeitsunterschied $shift. Nachtlicht, Vorhang oder Türspalt können das Bild beeinflussen; ein ruhiger Blick reicht.',
        '🌙 Das Licht wirkt anders (${formatPercent(scorePercent)}). Helligkeitsverschiebung $shift. Prüfe die Kameraansicht sanft.',
        '📷 Die Kamera sendet eine Lichtnotiz (${formatPercent(scorePercent)}). Helligkeitsänderung $shift. Es wirkt eher wie Licht als Bewegung; schau trotzdem einmal hin.',
      ],
      ar: [
        '💡 قد تكون إضاءة الغرفة تغيّرت (${formatPercent(scorePercent)}). فرق السطوع $shift. قد يؤثر ضوء الليل أو الستار أو فتحة الباب على الصورة؛ تكفي نظرة هادئة.',
        '🌙 يبدو مستوى الإضاءة مختلفاً (${formatPercent(scorePercent)}). انحراف السطوع $shift. تحققي من صورة الكاميرا.',
        '📷 رصدت الكاميرا تغيراً في الإضاءة (${formatPercent(scorePercent)}). تغير السطوع $shift. يبدو أنه ضوء أكثر من حركة؛ ومع ذلك ألقي نظرة واحدة.',
      ],
    ));
  }

  String networkQualityLabel(NetworkQualityTier tier) => switch (tier) {
        NetworkQualityTier.excellent => ui('netExcellent'),
        NetworkQualityTier.good => ui('netGood'),
        NetworkQualityTier.weak => ui('netWeak'),
        NetworkQualityTier.critical => ui('netCritical'),
        NetworkQualityTier.offline => ui('netOffline'),
        NetworkQualityTier.unknown => ui('measuring'),
      };

  String parentMotionAgo(int? agoMs) {
    if (agoMs == null) {
      return _t(
        tr: 'Kamerada yakın zamanda hareket görünmedi.',
        en: 'No recent camera movement was detected.',
        zh: '摄像头最近没有检测到活动。',
        hi: 'कैमरे में हाल की कोई हलचल नहीं दिखी।',
        es: 'No se detectó movimiento reciente en la cámara.',
        fr: 'Aucun mouvement récent n’a été détecté par la caméra.',
        de: 'Die Kamera hat zuletzt keine Bewegung erkannt.',
        ar: 'لم ترصد الكاميرا حركة حديثة.',
      );
    }
    final seconds = (agoMs / 1000).round();
    return _t(
      tr: 'Kameradaki son hareket ${formatNumber(seconds)} sn önceydi.',
      en: 'The last camera movement was ${formatNumber(seconds)} sec ago.',
      zh: '摄像头上次检测到活动是在 ${formatNumber(seconds)} 秒前。',
      hi: 'कैमरे में आखिरी हलचल ${formatNumber(seconds)} सेकंड पहले थी।',
      es: 'El último movimiento en cámara fue hace ${formatNumber(seconds)} s.',
      fr: 'Le dernier mouvement filmé remonte à ${formatNumber(seconds)} s.',
      de: 'Die letzte Kamerabewegung war vor ${formatNumber(seconds)} s.',
      ar: 'كانت آخر حركة رصدتها الكاميرا قبل ${formatNumber(seconds)} ث.',
    );
  }

  String parentEpisodeHighCryAlert({
    required int seconds,
    required String motionAgo,
    required String networkTier,
  }) =>
      _addressParent(_variant(
        seed: seconds,
        tr: [
          'Ağlama benzeri ses yaklaşık ${formatNumber(seconds)} sn sürdü. $motionAgo Yayın kalitesi: $networkTier. Sakin bir kontrol iyi olur.',
          'Ağlama benzeri ses ${formatNumber(seconds)} sn boyunca belirgin kaldı. $motionAgo Bağlantı kalitesi: $networkTier. Odayı nazikçe kontrol et.',
          'Uzayan bir ağlama benzeri ses notu var: yaklaşık ${formatNumber(seconds)} sn. $motionAgo Yayın kalitesi: $networkTier; ses önceliği korunuyor.',
        ],
        en: [
          'A cry-like sound lasted about ${formatNumber(seconds)} sec. $motionAgo Stream quality: $networkTier. A calm check may help.',
          'A cry-like sound stayed noticeable for ${formatNumber(seconds)} sec. $motionAgo Connection quality: $networkTier. Please check the room gently.',
          'A longer cry-like sound lasted about ${formatNumber(seconds)} sec. $motionAgo Stream quality: $networkTier; audio stays prioritized.',
        ],
        zh: [
          '类似哭声持续约 ${formatNumber(seconds)} 秒。$motionAgo 直播状态：$networkTier。平静看一眼会有帮助。',
          '类似哭声持续了 ${formatNumber(seconds)} 秒。$motionAgo 连接状态：$networkTier。请轻轻查看房间。',
          '较长的类似哭声持续约 ${formatNumber(seconds)} 秒。$motionAgo 直播状态：$networkTier，已保持声音优先。',
        ],
        hi: [
          'रोने जैसी आवाज़ लगभग ${formatNumber(seconds)} सेकंड चली। $motionAgo स्ट्रीम की गुणवत्ता: $networkTier। शांति से देखना मदद कर सकता है।',
          'रोने जैसी आवाज़ ${formatNumber(seconds)} सेकंड तक स्पष्ट रही। $motionAgo कनेक्शन की गुणवत्ता: $networkTier। कमरे को प्यार से देखें।',
          'लंबी रोने जैसी आवाज़ लगभग ${formatNumber(seconds)} सेकंड चली। $motionAgo स्ट्रीम की गुणवत्ता: $networkTier; ऑडियो को प्राथमिकता दी जा रही है।',
        ],
        es: [
          'Un sonido parecido al llanto duró unos ${formatNumber(seconds)} s. $motionAgo Calidad de transmisión: $networkTier. Una revisión tranquila puede ayudar.',
          'El sonido parecido al llanto se mantuvo ${formatNumber(seconds)} s. $motionAgo Calidad de conexión: $networkTier. Revisa la habitación con calma.',
          'Un sonido parecido al llanto duró unos ${formatNumber(seconds)} s. $motionAgo Calidad de transmisión: $networkTier; el audio sigue siendo prioritario.',
        ],
        fr: [
          'Un son proche de pleurs a duré environ ${formatNumber(seconds)} s. $motionAgo Qualité du flux : $networkTier. Un contrôle calme peut aider.',
          'Le son proche de pleurs est resté net ${formatNumber(seconds)} s. $motionAgo Qualité de connexion : $networkTier. Vérifie doucement la chambre.',
          'Un son proche de pleurs a duré environ ${formatNumber(seconds)} s. $motionAgo Qualité du flux : $networkTier ; l’audio reste prioritaire.',
        ],
        de: [
          'Ein weinähnlicher Ton dauerte etwa ${formatNumber(seconds)} s. $motionAgo Streamqualität: $networkTier. Ein ruhiger Blick kann helfen.',
          'Der weinähnliche Ton blieb ${formatNumber(seconds)} s deutlich. $motionAgo Verbindungsqualität: $networkTier. Prüfe das Zimmer sanft.',
          'Ein weinähnlicher Ton dauerte etwa ${formatNumber(seconds)} s. $motionAgo Streamqualität: $networkTier; Audio bleibt priorisiert.',
        ],
        ar: [
          'استمر صوت يشبه البكاء حوالي ${formatNumber(seconds)} ث. $motionAgo جودة البث: $networkTier. قد تساعد نظرة هادئة.',
          'بقي صوت يشبه البكاء واضحاً لمدة ${formatNumber(seconds)} ث. $motionAgo جودة الاتصال: $networkTier. تحققي من الغرفة بلطف.',
          'استمر صوت يشبه البكاء حوالي ${formatNumber(seconds)} ث. $motionAgo جودة البث: $networkTier؛ أولوية الصوت محفوظة.',
        ],
      ));

  String parentEpisodeShortSoundAlert({required int seconds}) =>
      _addressParent(_variant(
        seed: seconds,
        tr: [
          'Kısa bir ses yükselmesi oldu. Şimdilik sakin görünüyor; tekrarlarsa haber vereceğim.',
          'Kısa bir huzursuzluk sesi duyuldu. Uzayan bir ağlama gibi görünmüyor; yine de not ettim.',
          'Ses kısa süre yükseldi ve sonra sakinleşti. Tekrarlarsa nazikçe bildireceğim.',
        ],
        en: [
          'A brief sound rise happened. It looks calm for now; I’ll let you know if it repeats.',
          'A short fuss sound was heard. It does not look like longer crying right now; I noted it.',
          'Audio rose briefly and then settled. I’ll gently alert you if it repeats.',
        ],
        zh: [
          '出现短暂声音升高。现在看起来平静；如果重复，我会再提醒。',
          '听到短暂烦躁声。目前不像持续哭声；已为你记录。',
          '声音短暂升高后恢复。若再次出现，我会轻轻提醒。',
        ],
        hi: [
          'थोड़ी देर आवाज़ बढ़ी। अभी सब शांत लगता है; दोबारा होने पर आपको सूचना मिलेगी।',
          'छोटी बेचैनी की आवाज़ सुनी गई। अभी यह लंबा रोना नहीं लग रहा; इसे दर्ज कर लिया गया है।',
          'आवाज़ थोड़ी देर बढ़ी और फिर शांत हुई। दोहराई तो हल्के से सूचना दूँगा।',
        ],
        es: [
          'Hubo una subida breve de sonido. Por ahora se ve tranquilo; avisaré si se repite.',
          'Se oyó un sonido breve de inquietud. Ahora no parece llanto largo; queda anotado.',
          'El audio subió un momento y luego se calmó. Te avisaré con suavidad si se repite.',
        ],
        fr: [
          'Brève hausse sonore. Pour l’instant tout semble calme ; je te préviens si cela revient.',
          'Un bref son d’inconfort a été entendu. Cela ne ressemble pas à des pleurs longs pour le moment ; c’est noté.',
          'Le son a monté un instant puis s’est calmé. Je te préviendrai si cela se répète.',
        ],
        de: [
          'Kurzer Tonanstieg. Im Moment wirkt alles ruhig; ich melde mich, falls es sich wiederholt.',
          'Ein kurzes Unruhegeräusch wurde gehört. Es wirkt gerade nicht wie längeres Weinen; ich habe es notiert.',
          'Audio stieg kurz an und beruhigte sich wieder. Wenn es sich wiederholt, warne ich sanft.',
        ],
        ar: [
          'حدث ارتفاع صوت قصير. يبدو الوضع هادئاً الآن؛ سأخبرك إذا تكرر.',
          'سُمع صوت انزعاج قصير. لا يبدو الآن كبكاء طويل؛ تم تسجيله.',
          'ارتفع الصوت قليلاً ثم هدأ. سأرسل تنبيهاً لطيفاً إذا تكرر.',
        ],
      ));

  String parentEpisodeCryAlert({
    required int seconds,
    required String networkTier,
  }) =>
      _addressParent(_variant(
        seed: seconds,
        tr: [
          'Ağlama benzeri sinyal yaklaşık ${formatNumber(seconds)} sn sürdü. Yayın kalitesi: $networkTier; sakin bir bakış iyi olur.',
          '${formatNumber(seconds)} sn kadar süren huzursuzluk sesi var. Bağlantı kalitesi: $networkTier; ses takibi açık.',
          'Ağlama benzeri sinyal ${formatNumber(seconds)} sn sürdü. Yayın kalitesi: $networkTier; gerekirse görüntü yerine ses öncelikli tutulur.',
        ],
        en: [
          'A cry-like signal lasted about ${formatNumber(seconds)} sec. Stream quality: $networkTier; a calm look may help.',
          'Fuss sound continued for around ${formatNumber(seconds)} sec. Connection quality: $networkTier; audio monitoring is active.',
          'A cry-like signal lasted ${formatNumber(seconds)} sec. Stream quality: $networkTier; audio may be prioritized if needed.',
        ],
        zh: [
          '类似哭声持续约 ${formatNumber(seconds)} 秒。直播状态：$networkTier；平静看一眼会有帮助。',
          '烦躁声音持续约 ${formatNumber(seconds)} 秒。连接状态：$networkTier；声音监测已开启。',
          '已记录类似哭声提示，持续 ${formatNumber(seconds)} 秒。直播状态：$networkTier；必要时会优先保证声音。',
        ],
        hi: [
          'रोने जैसी आवाज़ लगभग ${formatNumber(seconds)} सेकंड चली। स्ट्रीम की गुणवत्ता: $networkTier; शांत होकर देखना मदद कर सकता है।',
          'बेचैनी की आवाज़ करीब ${formatNumber(seconds)} सेकंड चली। कनेक्शन की गुणवत्ता: $networkTier; ऑडियो निगरानी सक्रिय है।',
          'रोने जैसी आवाज़ का संकेत ${formatNumber(seconds)} सेकंड चला। स्ट्रीम की गुणवत्ता: $networkTier; ज़रूरत हो तो ऑडियो को प्राथमिकता मिलेगी।',
        ],
        es: [
          'Un sonido parecido al llanto duró unos ${formatNumber(seconds)} s. Calidad de transmisión: $networkTier; una mirada tranquila puede ayudar.',
          'El sonido de inquietud continuó unos ${formatNumber(seconds)} s. Calidad de conexión: $networkTier; monitoreo de audio activo.',
          'La señal parecida al llanto duró ${formatNumber(seconds)} s. Calidad de transmisión: $networkTier; el audio puede tener prioridad si hace falta.',
        ],
        fr: [
          'Un son proche de pleurs a duré environ ${formatNumber(seconds)} s. Qualité du flux : $networkTier ; un regard calme peut aider.',
          'Le son d’inconfort a continué environ ${formatNumber(seconds)} s. Qualité de connexion : $networkTier ; suivi audio actif.',
          'Le signal proche de pleurs a duré ${formatNumber(seconds)} s. Qualité du flux : $networkTier ; l’audio peut être prioritaire si besoin.',
        ],
        de: [
          'Weinähnlicher Ton dauerte etwa ${formatNumber(seconds)} s. Streamqualität: $networkTier; ein ruhiger Blick kann helfen.',
          'Unruheton lief rund ${formatNumber(seconds)} s weiter. Verbindungsqualität: $networkTier; Audioüberwachung ist aktiv.',
          'Hinweis auf einen weinähnlichen Ton über ${formatNumber(seconds)} s. Streamqualität: $networkTier; Audio kann bei Bedarf priorisiert werden.',
        ],
        ar: [
          'استمر صوت يشبه البكاء حوالي ${formatNumber(seconds)} ث. جودة البث: $networkTier؛ قد تساعد نظرة هادئة.',
          'استمر صوت انزعاج نحو ${formatNumber(seconds)} ث. جودة الاتصال: $networkTier؛ مراقبة الصوت نشطة.',
          'استمرت إشارة تشبه البكاء ${formatNumber(seconds)} ث. جودة البث: $networkTier؛ قد تُعطى أولوية للصوت عند الحاجة.',
        ],
      ));

  String _addressParent(String message) {
    return _t(
      tr: 'Anne, $message',
      en: 'Mom, $message',
      zh: '妈妈，$message',
      hi: 'माँ, $message',
      es: 'Mamá, $message',
      fr: 'Maman, $message',
      de: 'Mama, $message',
      ar: 'ماما، $message',
    );
  }

  String _signalLabel(int percent) => _t(
        tr: 'sinyal gücü ${formatPercent(percent)}',
        en: 'signal strength ${formatPercent(percent)}',
        zh: '信号强度 ${formatPercent(percent)}',
        hi: 'संकेत की ताकत ${formatPercent(percent)}',
        es: 'intensidad de señal ${formatPercent(percent)}',
        fr: 'intensité du signal ${formatPercent(percent)}',
        de: 'Signalstärke ${formatPercent(percent)}',
        ar: 'قوة الإشارة ${formatPercent(percent)}',
      );

  String notificationCount(int count) {
    final number = formatNumber(count);
    if (isChinese) return '$number 条提醒';
    if (isHindi) return '$number अलर्ट';
    if (isSpanish) return count == 1 ? '1 alerta' : '$number alertas';
    if (isFrench) return count <= 1 ? '$number alerte' : '$number alertes';
    if (isGerman) return count == 1 ? '1 Hinweis' : '$number Hinweise';
    if (isArabic) {
      if (count == 0) return 'لا توجد تنبيهات';
      if (count == 1) return 'تنبيه واحد';
      if (count == 2) return 'تنبيهان';
      final remainder = count % 100;
      if (remainder >= 3 && remainder <= 10) return '$number تنبيهات';
      if (remainder >= 11) return '$number تنبيهاً';
      return '$number تنبيه';
    }
    if (isTurkish) return '$number bildirim';
    return count == 1 ? '1 alert' : '$number alerts';
  }

  String ui(String key) {
    final values = appUiTextCatalog[key];
    if (values == null) return key;
    final languageCode = locale.languageCode;
    return extraUiText(languageCode, key, values['en']) ??
        values[languageCode] ??
        values['en'] ??
        key;
  }

  String uiFormat(String key, Map<String, Object?> params) {
    return ui(key).replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (match) {
      final name = match.group(1)!;
      if (!params.containsKey(name)) return match.group(0)!;
      final parameter = params[name];
      final text = parameter is num ? formatNumber(parameter) : '$parameter';
      return text;
    });
  }
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) {
    for (final supported in AppStrings.supportedLocales) {
      if (supported.languageCode == locale.languageCode &&
          supported.countryCode == locale.countryCode) {
        return SynchronousFuture(AppStrings(supported));
      }
    }
    for (final supported in AppStrings.supportedLocales) {
      if (supported.languageCode == locale.languageCode) {
        return SynchronousFuture(AppStrings(supported));
      }
    }
    return SynchronousFuture(AppStrings(AppStrings.fallbackLocale));
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
