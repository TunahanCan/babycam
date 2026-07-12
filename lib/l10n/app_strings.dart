import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/media/adaptive_media_profile.dart';
import 'src/app_ui_text_catalog.dart';
import 'src/app_ui_text_catalog_extra.dart';

class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = [
    Locale('en'),
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
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
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

  String _decimal(double value) {
    final text = value.toStringAsFixed(1);
    return isTurkish || isSpanish || isFrench || isGerman
        ? text.replaceAll('.', ',')
        : text;
  }

  String get appTitle => 'MimiCam';
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
      tr: 'MimiCam uyarısı',
      en: 'MimiCam alert',
      zh: 'MimiCam 提醒',
      hi: 'MimiCam अलर्ट',
      es: 'Alerta de MimiCam',
      fr: 'Alerte MimiCam',
      de: 'MimiCam Warnung',
      ar: 'تنبيه MimiCam');
  String get notificationChannelName => _t(
      tr: 'MimiCam Uyarıları',
      en: 'MimiCam Alerts',
      zh: 'MimiCam 提醒',
      hi: 'MimiCam अलर्ट',
      es: 'Alertas de MimiCam',
      fr: 'Alertes MimiCam',
      de: 'MimiCam Warnungen',
      ar: 'تنبيهات MimiCam');

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
        tr: '🔊 $reason. Sinyal gücü %$confidencePercent. $summary',
        en: '🔊 $reason. Signal strength $confidencePercent%. $summary',
        zh: '🔊 $reason。信号强度 $confidencePercent%。$summary',
        hi: '🔊 $reason। संकेत की ताकत $confidencePercent%। $summary',
        es: '🔊 $reason. Intensidad de señal $confidencePercent%. $summary',
        fr: '🔊 $reason. Intensité du signal $confidencePercent %. $summary',
        de: '🔊 $reason. Signalstärke $confidencePercent%. $summary',
        ar: '🔊 $reason. قوة الإشارة $confidencePercent%. $summary',
      );
  String motionAlert(int scorePercent) => _t(
      tr: '👶 Hareket notu. Skor: $scorePercent%',
      en: '👶 Motion note. Score: $scorePercent%',
      zh: '👶 活动提示。评分：$scorePercent%',
      hi: '👶 हलचल नोट। स्कोर: $scorePercent%',
      es: '👶 Nota de movimiento. Puntuación: $scorePercent%',
      fr: '👶 Note de mouvement. Score : $scorePercent %',
      de: '👶 Bewegungsnotiz. Wert: $scorePercent%',
      ar: '👶 ملاحظة حركة. النتيجة: $scorePercent%');
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
          tr: 'seviye ${dbfs.toStringAsFixed(1)} dBFS, ortam ${ambientDbfs.toStringAsFixed(1)} dBFS, F0 $f0, merkez $centroidHz Hz, bant $bandwidthHz Hz, ZCR ${zcr.toStringAsFixed(2)}, entropi ${entropy.toStringAsFixed(2)}, ağlama $cryPercent%, inleme $moanPercent%',
          en: 'level ${dbfs.toStringAsFixed(1)} dBFS, ambient ${ambientDbfs.toStringAsFixed(1)} dBFS, F0 $f0, center $centroidHz Hz, band $bandwidthHz Hz, ZCR ${zcr.toStringAsFixed(2)}, entropy ${entropy.toStringAsFixed(2)}, crying $cryPercent%, moaning $moanPercent%',
          zh: '音量 ${dbfs.toStringAsFixed(1)} dBFS，环境 ${ambientDbfs.toStringAsFixed(1)} dBFS，F0 $f0，中心 $centroidHz Hz，带宽 $bandwidthHz Hz，ZCR ${zcr.toStringAsFixed(2)}，熵 ${entropy.toStringAsFixed(2)}，哭声 $cryPercent%，低吟 $moanPercent%',
          hi: 'स्तर ${dbfs.toStringAsFixed(1)} dBFS, परिवेश ${ambientDbfs.toStringAsFixed(1)} dBFS, F0 $f0, केंद्र $centroidHz Hz, बैंड $bandwidthHz Hz, ZCR ${zcr.toStringAsFixed(2)}, एंट्रॉपी ${entropy.toStringAsFixed(2)}, रोना $cryPercent%, कराहना $moanPercent%',
          es: 'nivel ${dbfs.toStringAsFixed(1)} dBFS, ambiente ${ambientDbfs.toStringAsFixed(1)} dBFS, F0 $f0, centro $centroidHz Hz, banda $bandwidthHz Hz, ZCR ${zcr.toStringAsFixed(2)}, entropía ${entropy.toStringAsFixed(2)}, llanto $cryPercent%, quejido $moanPercent%',
          fr: 'niveau ${dbfs.toStringAsFixed(1)} dBFS, ambiance ${ambientDbfs.toStringAsFixed(1)} dBFS, F0 $f0, centre $centroidHz Hz, bande $bandwidthHz Hz, ZCR ${zcr.toStringAsFixed(2)}, entropie ${entropy.toStringAsFixed(2)}, pleurs $cryPercent %, gémissement $moanPercent %',
          de: 'Pegel ${dbfs.toStringAsFixed(1)} dBFS, Raum ${ambientDbfs.toStringAsFixed(1)} dBFS, F0 $f0, Zentrum $centroidHz Hz, Band $bandwidthHz Hz, ZCR ${zcr.toStringAsFixed(2)}, Entropie ${entropy.toStringAsFixed(2)}, Weinen $cryPercent%, Wimmern $moanPercent%',
          ar: 'المستوى ${dbfs.toStringAsFixed(1)} dBFS، الغرفة ${ambientDbfs.toStringAsFixed(1)} dBFS، F0 $f0، المركز $centroidHz Hz، النطاق $bandwidthHz Hz، ZCR ${zcr.toStringAsFixed(2)}، الإنتروبيا ${entropy.toStringAsFixed(2)}، البكاء $cryPercent%، الأنين $moanPercent%');
  String pitchSuffix(int fundamentalHz) => fundamentalHz > 0
      ? _t(
          tr: ', temel frekans $fundamentalHz Hz',
          en: ', fundamental frequency $fundamentalHz Hz',
          zh: '，基频 $fundamentalHz Hz',
          hi: ', मूल आवृत्ति $fundamentalHz Hz',
          es: ', frecuencia fundamental $fundamentalHz Hz',
          fr: ', fréquence fondamentale $fundamentalHz Hz',
          de: ', Grundfrequenz $fundamentalHz Hz',
          ar: '، التردد الأساسي $fundamentalHz Hz')
      : '';
  String cryLikeReason(String pitch, int centroidHz) => _t(
      tr: 'Ağlama benzeri vokal ses$pitch, parlaklık $centroidHz Hz',
      en: 'Cry-like vocal sound$pitch, brightness $centroidHz Hz',
      zh: '类似哭声的人声$pitch，明亮度 $centroidHz Hz',
      hi: 'रोने जैसी स्वर ध्वनि$pitch, चमक $centroidHz Hz',
      es: 'Sonido vocal similar al llanto$pitch, brillo $centroidHz Hz',
      fr: 'Son vocal semblable à des pleurs$pitch, brillance $centroidHz Hz',
      de: 'Weinähnlicher Stimmton$pitch, Helligkeit $centroidHz Hz',
      ar: 'صوت صوتي يشبه البكاء$pitch، السطوع $centroidHz Hz');
  String moanLikeReason(String pitch, int centroidHz) => _t(
      tr: 'İnleme benzeri düşük frekanslı sürekli ses$pitch, merkez $centroidHz Hz',
      en: 'Moan-like low-frequency sustained sound$pitch, center $centroidHz Hz',
      zh: '类似低频持续低吟的声音$pitch，中心 $centroidHz Hz',
      hi: 'कराह जैसी कम-आवृत्ति की लगातार ध्वनि$pitch, केंद्र $centroidHz Hz',
      es: 'Sonido sostenido de baja frecuencia similar a un quejido$pitch, centro $centroidHz Hz',
      fr: 'Son grave soutenu semblable à un gémissement$pitch, centre $centroidHz Hz',
      de: 'Wimmerähnlicher tiefer Dauerton$pitch, Zentrum $centroidHz Hz',
      ar: 'صوت منخفض مستمر يشبه الأنين$pitch، المركز $centroidHz Hz');

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
        '👶 Bebeğiniz ağlıyor olabilir ($signal). Ses oda seviyesinin $delta dB üstünde; ağlama sinyali %$cryBandPercent. $calibration Sakin bir kontrol iyi olur: konfor, bez, beslenme, gaz veya sıcaklık.',
        '🍼 Küçük bir oda kontrolü gerekebilir ($signal). Ses $delta dB yükseldi; ağlama sinyali %$cryBandPercent. $calibration Bebeğinizin neye ihtiyaç duyduğunu nazikçe kontrol edin.',
        '🔊 Ağlama benzeri bir ses fark edildi ($signal). Oda sesinin $delta dB üstünde; ağlama sinyali %$cryBandPercent. $calibration Lütfen telaşsızca görüntüye bakın.',
      ],
      en: [
        '👶 Baby may be crying ($signal). Sound is $delta dB above the room level; cry signal is $cryBandPercent%. $calibration A calm check may help: comfort, diaper, feeding, gas, or temperature.',
        '🍼 A gentle room check may be helpful ($signal). Audio rose $delta dB; cry signal is $cryBandPercent%. $calibration Please look in calmly and see what baby needs.',
        '🔊 Cry-like sound noticed ($signal). It is $delta dB above room level; cry signal is $cryBandPercent%. $calibration Please check the video without rushing.',
      ],
      zh: [
        '👶 宝宝可能在哭（$signal）。声音比房间基线高 $delta dB；哭声信号 $cryBandPercent%。$calibration。请平静查看：安抚、尿布、喂奶、胀气或温度。',
        '🍼 也许需要轻轻看一眼（$signal）。声音上升 $delta dB；哭声信号 $cryBandPercent%。$calibration。请安心查看宝宝需要什么。',
        '🔊 注意到类似哭声（$signal）。比房间基线高 $delta dB；哭声信号 $cryBandPercent%。$calibration。请不慌不忙地查看画面。',
      ],
      hi: [
        '👶 बच्चा रो रहा हो सकता है ($signal)। आवाज़ कमरे के स्तर से $delta dB ऊपर है; रोने का संकेत $cryBandPercent% है। $calibration। शांति से देखें: आराम, डायपर, दूध, गैस या तापमान।',
        '🍼 कमरे में हल्की जाँच मदद कर सकती है ($signal)। आवाज़ $delta dB बढ़ी; रोने का संकेत $cryBandPercent% है। $calibration। प्यार से देखें कि बच्चे को क्या चाहिए।',
        '🔊 रोने जैसी आवाज़ नोट हुई ($signal)। यह कमरे के स्तर से $delta dB ऊपर है; रोने का संकेत $cryBandPercent% है। $calibration। बिना घबराए वीडियो देखें।',
      ],
      es: [
        '👶 Puede que el bebé esté llorando ($signal). El sonido está $delta dB sobre el nivel de la habitación; señal de llanto $cryBandPercent%. $calibration Revisa con calma: consuelo, pañal, toma, gases o temperatura.',
        '🍼 Quizá venga bien una mirada tranquila ($signal). El audio subió $delta dB; señal de llanto $cryBandPercent%. $calibration Mira sin prisa qué necesita el bebé.',
        '🔊 Se notó un sonido parecido al llanto ($signal). Está $delta dB sobre el nivel de la habitación; señal de llanto $cryBandPercent%. $calibration Revisa el video con calma.',
      ],
      fr: [
        '👶 Bébé pleure peut-être ($signal). Le son est $delta dB au-dessus du niveau de la pièce ; signal de pleurs $cryBandPercent %. $calibration Vérifiez calmement : réconfort, couche, repas, gaz ou température.',
        '🍼 Un petit coup d’œil peut aider ($signal). L’audio a monté de $delta dB ; signal de pleurs $cryBandPercent %. $calibration Regardez tranquillement ce dont bébé a besoin.',
        '🔊 Son proche de pleurs remarqué ($signal). Il est $delta dB au-dessus du niveau de la pièce ; signal de pleurs $cryBandPercent %. $calibration Vérifiez la vidéo sans vous presser.',
      ],
      de: [
        '👶 Das Baby könnte weinen ($signal). Der Ton liegt $delta dB über dem Zimmerpegel; Weinsignal $cryBandPercent%. $calibration Eine ruhige Kontrolle hilft: Trost, Windel, Füttern, Bauchweh oder Temperatur.',
        '🍼 Ein sanfter Blick ins Zimmer kann helfen ($signal). Audio stieg um $delta dB; Weinsignal $cryBandPercent%. $calibration Schau in Ruhe, was das Baby braucht.',
        '🔊 Weinähnlicher Ton bemerkt ($signal). Er liegt $delta dB über dem Zimmerpegel; Weinsignal $cryBandPercent%. $calibration Prüfe das Video ohne Eile.',
      ],
      ar: [
        '👶 ربما يبكي الطفل ($signal). الصوت أعلى من مستوى الغرفة بـ $delta dB؛ إشارة البكاء $cryBandPercent%. $calibration تحقق بهدوء: الراحة أو الحفاض أو الرضاعة أو الغازات أو الحرارة.',
        '🍼 قد تساعد نظرة هادئة إلى الغرفة ($signal). ارتفع الصوت $delta dB؛ إشارة البكاء $cryBandPercent%. $calibration تحقق بلطف مما يحتاجه الطفل.',
        '🔊 لوحظ صوت يشبه البكاء ($signal). أعلى من مستوى الغرفة بـ $delta dB؛ إشارة البكاء $cryBandPercent%. $calibration راجع الفيديو بهدوء.',
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
        '🔔 Odada kısa bir ses yükselmesi oldu. Seviye $level dBFS; oda sesinden $delta dB yüksek. Bebeğinizin rahat olduğundan nazikçe emin olun.',
        '🚪 Kısa ve belirgin bir ses duyuldu. Seviye $level dBFS, oda seviyesinin $delta dB üstünde. Kapı, oyuncak veya ev sesi olabilir; sakin bir bakış yeterli.',
        '🔊 Ses bir an yükseldi ($level dBFS). Oda farkı $delta dB. Bebeğiniz uyuyorsa görüntüyü sessizce kontrol edin.',
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
        '🔔 Brève hausse sonore dans la chambre. Niveau $level dBFS ; $delta dB au-dessus du niveau de la pièce. Vérifiez doucement que bébé est bien.',
        '🚪 Un son court et net a été entendu. Niveau $level dBFS, $delta dB au-dessus de la pièce. Porte, jouet ou bruit de maison possible ; un regard calme suffit.',
        '🔊 L’audio a monté un instant ($level dBFS). Écart avec la pièce : $delta dB. Si bébé dort, vérifiez la vidéo discrètement.',
      ],
      de: [
        '🔔 Kurzer Tonanstieg im Zimmer. Pegel $level dBFS; $delta dB über dem Zimmerpegel. Schau sanft nach, ob es dem Baby gut geht.',
        '🚪 Ein kurzer, klarer Ton wurde gehört. Pegel $level dBFS, $delta dB über dem Zimmerpegel. Tür, Spielzeug oder Alltagsgeräusch möglich; ein ruhiger Blick reicht.',
        '🔊 Audio stieg kurz an ($level dBFS). Abstand zum Zimmerpegel: $delta dB. Wenn das Baby schläft, prüfe das Video leise.',
      ],
      ar: [
        '🔔 حدث ارتفاع صوت قصير في الغرفة. المستوى $level dBFS؛ أعلى من مستوى الغرفة بـ $delta dB. تحقق بلطف أن الطفل مرتاح.',
        '🚪 سُمع صوت قصير وواضح. المستوى $level dBFS، أعلى من مستوى الغرفة بـ $delta dB. قد يكون باباً أو لعبة أو صوتاً منزلياً؛ تكفي نظرة هادئة.',
        '🔊 ارتفع الصوت للحظة ($level dBFS). الفرق عن الغرفة $delta dB. إذا كان الطفل نائماً، راجع الفيديو بهدوء.',
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
        '👶 Kamera görüntüsünde hafif hareket fark edildi ($scorePercent%). Görüntünün yaklaşık %$activeAreaPercent bölümü değişti; ortalama değişim $mean. Bebeğinizin rahat pozisyonda olduğundan emin olun.',
        '🧸 Görüntünün bebek alanına yakın bölümünde değişim var ($scorePercent%). Görüntü değişimi %$activeAreaPercent, ortalama fark $mean. Örtü ve yatak kenarını sakin bir bakışla kontrol edin.',
        '📹 Kamera bir hareket sinyali gönderdi ($scorePercent%). Aktif alan %$activeAreaPercent; değişim $mean. Görüntüye bakıp her şeyin yolunda olduğunu doğrulayın.',
      ],
      en: [
        '👶 Gentle movement appeared in the camera view ($scorePercent%). About $activeAreaPercent% of the image changed; average change $mean. Make sure baby is resting comfortably.',
        '🧸 A change appeared near the baby area in the image ($scorePercent%). Image change $activeAreaPercent%, average difference $mean. Calmly check the blanket and crib edge.',
        '📹 The camera detected a motion signal ($scorePercent%). Active area $activeAreaPercent%; change $mean. Look at the video and confirm all is well.',
      ],
      zh: [
        '👶 摄像头画面出现轻微变化（$scorePercent%）。约 $activeAreaPercent% 的画面发生变化；平均变化 $mean。请确认宝宝睡得舒服。',
        '🧸 宝宝区域附近的画面出现变化（$scorePercent%）。画面变化 $activeAreaPercent%，平均差异 $mean。请平静检查毯子和床边。',
        '📹 摄像头检测到活动信号（$scorePercent%）。活动区域 $activeAreaPercent%；变化 $mean。看一眼画面，确认一切安好。',
      ],
      hi: [
        '👶 कैमरा दृश्य में हल्का बदलाव दिखा ($scorePercent%)। चित्र का लगभग $activeAreaPercent% हिस्सा बदला; औसत बदलाव $mean। देखें कि बच्चा आराम से लेटा है।',
        '🧸 बच्चे के पास के चित्र में बदलाव है ($scorePercent%)। चित्र बदलाव $activeAreaPercent%, औसत फर्क $mean। कंबल और पालने के किनारे को शांति से देखें।',
        '📹 कैमरे ने गतिविधि संकेत भेजा ($scorePercent%)। सक्रिय क्षेत्र $activeAreaPercent%; बदलाव $mean। वीडियो देखकर पुष्टि करें कि सब ठीक है।',
      ],
      es: [
        '👶 Se notó un cambio suave en la imagen ($scorePercent%). Cambió cerca del $activeAreaPercent% de la imagen; cambio medio $mean. Confirma que el bebé esté cómodo.',
        '🧸 Hay un cambio en la imagen cerca de la zona del bebé ($scorePercent%). Cambio de imagen $activeAreaPercent%, diferencia media $mean. Revisa con calma manta y borde de la cuna.',
        '📹 La cámara envió una nota de movimiento ($scorePercent%). Área activa $activeAreaPercent%; cambio $mean. Mira el video y confirma que todo esté bien.',
      ],
      fr: [
        '👶 Léger changement dans l’image ($scorePercent %). Environ $activeAreaPercent % de l’image a changé ; variation moyenne $mean. Vérifiez que bébé est bien installé.',
        '🧸 Changement dans l’image près de la zone de bébé ($scorePercent %). Changement d’image $activeAreaPercent %, écart moyen $mean. Vérifiez calmement couverture et bord du lit.',
        '📹 La caméra a envoyé une note de mouvement ($scorePercent %). Zone active $activeAreaPercent % ; variation $mean. Regardez la vidéo et confirmez que tout va bien.',
      ],
      de: [
        '👶 Sanfte Bildveränderung bemerkt ($scorePercent%). Etwa $activeAreaPercent% des Bildes änderte sich; mittlere Änderung $mean. Vergewissere dich, dass das Baby bequem liegt.',
        '🧸 Bildveränderung in der Nähe des Babybereichs ($scorePercent%). Bildänderung $activeAreaPercent%, mittlere Differenz $mean. Prüfe Decke und Krippenrand in Ruhe.',
        '📹 Die Kamera sendet eine Bewegungsnotiz ($scorePercent%). Aktiver Bereich $activeAreaPercent%; Änderung $mean. Schau ins Video und bestätige, dass alles gut ist.',
      ],
      ar: [
        '👶 لوحظ تغير خفيف في صورة الكاميرا ($scorePercent%). تغيّر نحو $activeAreaPercent% من الصورة؛ متوسط التغير $mean. تأكد أن الطفل مستريح.',
        '🧸 ظهر تغير في الصورة قرب منطقة الطفل ($scorePercent%). تغيّر الصورة $activeAreaPercent%، ومتوسط الفرق $mean. افحص البطانية وحافة السرير بهدوء.',
        '📹 أرسلت الكاميرا ملاحظة حركة ($scorePercent%). المنطقة النشطة $activeAreaPercent%؛ التغير $mean. راجع الفيديو وتأكد أن كل شيء بخير.',
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
        '💡 Oda ışığı değişmiş olabilir ($scorePercent%). Parlaklık farkı $shift. Gece lambası, perde ya da kapı aralığı etkili olabilir; görüntüye sakin bir bakış yeterli.',
        '🌙 Işık seviyesi farklı görünüyor ($scorePercent%). Parlaklık kayması $shift. Kamera görüntüsünü nazikçe kontrol edin.',
        '📷 Kamera ışık değişimi notu gönderdi ($scorePercent%). Parlaklık değişimi $shift. Hareketten çok ışık gibi görünüyor; yine de bir kez bakın.',
      ],
      en: [
        '💡 Room light may have changed ($scorePercent%). Brightness difference $shift. Night light, curtain, or door gap may be affecting the view; a calm look is enough.',
        '🌙 Light level looks different ($scorePercent%). Brightness shift $shift. Please gently check the camera view.',
        '📷 Camera sent a light-change note ($scorePercent%). Brightness shift $shift. It looks more like light than motion; still, take one look.',
      ],
      zh: [
        '💡 房间光线可能有变化（$scorePercent%）。亮度差 $shift。夜灯、窗帘或门缝可能影响画面；平静看一眼即可。',
        '🌙 光线水平看起来不同（$scorePercent%）。亮度偏移 $shift。请轻轻查看摄像头画面。',
        '📷 摄像头发送了光线变化提示（$scorePercent%）。亮度变化 $shift。更像光线而不是动作；仍建议看一次。',
      ],
      hi: [
        '💡 कमरे की रोशनी बदल सकती है ($scorePercent%)। चमक अंतर $shift। नाइट लाइट, पर्दा या दरवाज़े की दरार असर कर सकती है; शांत होकर देखना पर्याप्त है।',
        '🌙 रोशनी का स्तर अलग दिख रहा है ($scorePercent%)। चमक बदलाव $shift। कैमरा दृश्य प्यार से देख लें।',
        '📷 कैमरे ने रोशनी बदलाव की सूचना भेजी ($scorePercent%)। चमक में बदलाव $shift। यह हलचल से ज़्यादा रोशनी जैसा लगता है; फिर भी एक बार देखें।',
      ],
      es: [
        '💡 Puede haber cambiado la luz de la habitación ($scorePercent%). Diferencia de brillo $shift. Luz nocturna, cortina o puerta pueden afectar la vista; una mirada tranquila basta.',
        '🌙 El nivel de luz se ve distinto ($scorePercent%). Desplazamiento de brillo $shift. Revisa la cámara con calma.',
        '📷 La cámara envió una nota de cambio de luz ($scorePercent%). Cambio de brillo $shift. Parece más luz que movimiento; aun así mira una vez.',
      ],
      fr: [
        '💡 La lumière de la chambre a peut-être changé ($scorePercent %). Écart de luminosité $shift. Veilleuse, rideau ou porte entrouverte peuvent influencer l’image ; un regard calme suffit.',
        '🌙 Le niveau de lumière semble différent ($scorePercent %). Décalage de luminosité $shift. Vérifiez doucement la caméra.',
        '📷 La caméra a envoyé une note de lumière ($scorePercent %). Variation de luminosité $shift. Cela ressemble plus à la lumière qu’à un mouvement ; regardez quand même une fois.',
      ],
      de: [
        '💡 Das Zimmerlicht hat sich vielleicht geändert ($scorePercent%). Helligkeitsunterschied $shift. Nachtlicht, Vorhang oder Türspalt können das Bild beeinflussen; ein ruhiger Blick reicht.',
        '🌙 Das Licht wirkt anders ($scorePercent%). Helligkeitsverschiebung $shift. Prüfe die Kameraansicht sanft.',
        '📷 Die Kamera sendet eine Lichtnotiz ($scorePercent%). Helligkeitsänderung $shift. Es wirkt eher wie Licht als Bewegung; schau trotzdem einmal hin.',
      ],
      ar: [
        '💡 قد تكون إضاءة الغرفة تغيّرت ($scorePercent%). فرق السطوع $shift. قد يؤثر ضوء الليل أو الستار أو فتحة الباب على الصورة؛ تكفي نظرة هادئة.',
        '🌙 يبدو مستوى الإضاءة مختلفاً ($scorePercent%). انحراف السطوع $shift. تحقق من عرض الكاميرا بلطف.',
        '📷 أرسلت الكاميرا ملاحظة تغير ضوء ($scorePercent%). تغير السطوع $shift. يبدو أنه ضوء أكثر من حركة؛ ومع ذلك ألقِ نظرة واحدة.',
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
        tr: 'son kamera hareketi yok',
        en: 'no recent camera motion',
        zh: '最近没有相机活动',
        hi: 'हाल की कैमरा हलचल नहीं',
        es: 'sin movimiento reciente de cámara',
        fr: 'aucun mouvement récent de caméra',
        de: 'keine aktuelle Kamerabewegung',
        ar: 'لا توجد حركة حديثة للكاميرا',
      );
    }
    final seconds = (agoMs / 1000).round();
    return _t(
      tr: 'kamera $seconds sn önce',
      en: '$seconds sec ago on camera',
      zh: '$seconds 秒前相机活动',
      hi: 'कैमरा $seconds सेकंड पहले',
      es: 'cámara hace $seconds s',
      fr: 'caméra il y a $seconds s',
      de: 'Kamera vor $seconds s',
      ar: 'للكاميرا قبل $seconds ث',
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
          'Ağlama benzeri ses yaklaşık $seconds sn sürdü. Son kamera hareketi $motionAgo. Yayın kalitesi: $networkTier; sakin bir kontrol iyi olur.',
          'Ağlama benzeri ses bir süre güçlü devam etti ($seconds sn). Kamera hareketi: $motionAgo. Bağlantı kalitesi: $networkTier; lütfen odayı nazikçe kontrol edin.',
          'Uzayan bir ağlama benzeri ses notu var: ~$seconds sn. Son kamera hareketi $motionAgo. Yayın kalitesi: $networkTier; ses önceliği korunuyor.',
        ],
        en: [
          'A cry-like sound lasted about $seconds sec. Last camera motion $motionAgo. Stream quality: $networkTier; a calm check may help.',
          'A cry-like sound stayed noticeable for $seconds sec. Camera motion: $motionAgo. Connection quality: $networkTier; please check the room gently.',
          'Longer cry-like sound note: ~$seconds sec. Last camera motion $motionAgo. Stream quality: $networkTier; audio priority is preserved.',
        ],
        zh: [
          '类似哭声持续约 $seconds 秒。最后相机活动：$motionAgo。直播状态：$networkTier；平静查看会有帮助。',
          '类似哭声信号持续了 $seconds 秒。相机活动信息：$motionAgo。连接状态：$networkTier；请轻轻查看房间。',
          '较长类似哭声提示：约 $seconds 秒。最后相机活动 $motionAgo。直播状态：$networkTier，已保持音频优先。',
        ],
        hi: [
          'रोने जैसी आवाज़ लगभग $seconds सेकंड चली। अंतिम कैमरा हलचल $motionAgo। स्ट्रीम की गुणवत्ता: $networkTier; शांत जाँच मदद कर सकती है।',
          'रोने जैसा संकेत $seconds सेकंड तक स्पष्ट रहा। कैमरा हलचल: $motionAgo। कनेक्शन की गुणवत्ता: $networkTier; कमरे को प्यार से देखें।',
          'लंबी रोने जैसी आवाज़ की सूचना: ~$seconds सेकंड। अंतिम कैमरा हलचल $motionAgo। स्ट्रीम की गुणवत्ता: $networkTier; ऑडियो प्राथमिकता सुरक्षित है।',
        ],
        es: [
          'Un sonido parecido al llanto duró unos $seconds s. Último movimiento de cámara: $motionAgo. Calidad de transmisión: $networkTier; una revisión tranquila puede ayudar.',
          'La señal parecida al llanto se mantuvo $seconds s. Movimiento de cámara: $motionAgo. Calidad de conexión: $networkTier; revisa la habitación con suavidad.',
          'Aviso de sonido parecido al llanto: ~$seconds s. Último movimiento de cámara $motionAgo. Calidad de transmisión: $networkTier; se mantiene prioridad de audio.',
        ],
        fr: [
          'Un son proche de pleurs a duré environ $seconds s. Dernier mouvement de caméra $motionAgo. Qualité du flux : $networkTier ; un contrôle calme peut aider.',
          'Le signal proche de pleurs est resté net $seconds s. Mouvement de caméra : $motionAgo. Qualité de connexion : $networkTier ; vérifiez doucement la chambre.',
          'Note de son proche de pleurs : ~$seconds s. Dernier mouvement de caméra $motionAgo. Qualité du flux : $networkTier ; priorité audio conservée.',
        ],
        de: [
          'Ein weinähnlicher Ton dauerte etwa $seconds s. Letzte Kamerabewegung: $motionAgo. Streamqualität: $networkTier; ein ruhiger Blick kann helfen.',
          'Das weinähnliche Signal blieb $seconds s deutlich. Kamerabewegung: $motionAgo. Verbindungsqualität: $networkTier; prüfe das Zimmer sanft.',
          'Längerer Hinweis auf einen weinähnlichen Ton: ~$seconds s. Letzte Kamerabewegung $motionAgo. Streamqualität: $networkTier; Audio bleibt priorisiert.',
        ],
        ar: [
          'استمر صوت يشبه البكاء حوالي $seconds ث. آخر حركة للكاميرا: $motionAgo. جودة البث: $networkTier؛ قد تساعد نظرة هادئة.',
          'بقيت إشارة تشبه البكاء واضحة لمدة $seconds ث. حركة الكاميرا: $motionAgo. جودة الاتصال: $networkTier؛ تحقق من الغرفة بلطف.',
          'ملاحظة صوت أطول يشبه البكاء: حوالي $seconds ث. آخر حركة للكاميرا $motionAgo. جودة البث: $networkTier؛ أولوية الصوت محفوظة.',
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
          'थोड़ी देर आवाज़ बढ़ी। अभी सब शांत लगता है; दोहराई तो बताऊँगा।',
          'छोटी बेचैनी की आवाज़ सुनी गई। अभी यह लंबा रोना नहीं लग रहा; मैंने नोट कर लिया।',
          'आवाज़ थोड़ी देर बढ़ी और फिर शांत हुई। दोहराई तो हल्के से सूचना दूँगा।',
        ],
        es: [
          'Hubo una subida breve de sonido. Por ahora se ve tranquilo; avisaré si se repite.',
          'Se oyó un sonido breve de inquietud. Ahora no parece llanto largo; queda anotado.',
          'El audio subió un momento y luego se calmó. Te avisaré con suavidad si se repite.',
        ],
        fr: [
          'Brève hausse sonore. Pour l’instant tout semble calme ; je vous préviens si cela revient.',
          'Un bref son d’inconfort a été entendu. Cela ne ressemble pas à des pleurs longs pour le moment ; c’est noté.',
          'Le son a monté un instant puis s’est calmé. Je vous préviendrai doucement si cela se répète.',
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
          'Ağlama benzeri sinyal yaklaşık $seconds sn sürdü. Yayın kalitesi: $networkTier; sakin bir bakış iyi olur.',
          '$seconds sn kadar süren huzursuzluk sesi var. Bağlantı kalitesi: $networkTier; ses takibi açık.',
          'Ağlama benzeri sinyal $seconds sn sürdü. Yayın kalitesi: $networkTier; gerekirse görüntü yerine ses öncelikli tutulur.',
        ],
        en: [
          'A cry-like signal lasted about $seconds sec. Stream quality: $networkTier; a calm look may help.',
          'Fuss sound continued for around $seconds sec. Connection quality: $networkTier; audio monitoring is active.',
          'A cry-like signal lasted $seconds sec. Stream quality: $networkTier; audio may be prioritized if needed.',
        ],
        zh: [
          '类似哭声持续约 $seconds 秒。直播状态：$networkTier；平静看一眼会有帮助。',
          '烦躁声音持续约 $seconds 秒。连接状态：$networkTier；声音监测已开启。',
          '已记录类似哭声提示，持续 $seconds 秒。直播状态：$networkTier；必要时会优先保证声音。',
        ],
        hi: [
          'रोने जैसी आवाज़ लगभग $seconds सेकंड चली। स्ट्रीम की गुणवत्ता: $networkTier; शांत होकर देखना मदद कर सकता है।',
          'बेचैनी की आवाज़ करीब $seconds सेकंड चली। कनेक्शन की गुणवत्ता: $networkTier; ऑडियो निगरानी सक्रिय है।',
          'रोने जैसी आवाज़ का संकेत $seconds सेकंड चला। स्ट्रीम की गुणवत्ता: $networkTier; ज़रूरत हो तो ऑडियो को प्राथमिकता मिलेगी।',
        ],
        es: [
          'Un sonido parecido al llanto duró unos $seconds s. Calidad de transmisión: $networkTier; una mirada tranquila puede ayudar.',
          'El sonido de inquietud continuó unos $seconds s. Calidad de conexión: $networkTier; monitoreo de audio activo.',
          'La señal parecida al llanto duró $seconds s. Calidad de transmisión: $networkTier; el audio puede tener prioridad si hace falta.',
        ],
        fr: [
          'Un son proche de pleurs a duré environ $seconds s. Qualité du flux : $networkTier ; un regard calme peut aider.',
          'Le son d’inconfort a continué environ $seconds s. Qualité de connexion : $networkTier ; suivi audio actif.',
          'Le signal proche de pleurs a duré $seconds s. Qualité du flux : $networkTier ; l’audio peut être prioritaire si besoin.',
        ],
        de: [
          'Weinähnlicher Ton dauerte etwa $seconds s. Streamqualität: $networkTier; ein ruhiger Blick kann helfen.',
          'Unruheton lief rund $seconds s weiter. Verbindungsqualität: $networkTier; Audioüberwachung ist aktiv.',
          'Hinweis auf einen weinähnlichen Ton über $seconds s. Streamqualität: $networkTier; Audio kann bei Bedarf priorisiert werden.',
        ],
        ar: [
          'استمر صوت يشبه البكاء حوالي $seconds ث. جودة البث: $networkTier؛ قد تساعد نظرة هادئة.',
          'استمر صوت انزعاج نحو $seconds ث. جودة الاتصال: $networkTier؛ مراقبة الصوت نشطة.',
          'استمرت إشارة تشبه البكاء $seconds ث. جودة البث: $networkTier؛ قد تُعطى أولوية للصوت عند الحاجة.',
        ],
      ));

  String _addressParent(String message) {
    final address = _t(
      tr: 'Anne',
      en: 'Mom',
      zh: '妈妈',
      hi: 'माँ',
      es: 'Mamá',
      fr: 'Maman',
      de: 'Mama',
      ar: 'يا أمي',
    );
    return '$address, $message';
  }

  String _signalLabel(int percent) => _t(
        tr: 'sinyal gücü %$percent',
        en: 'signal strength $percent%',
        zh: '信号强度 $percent%',
        hi: 'संकेत की ताकत $percent%',
        es: 'intensidad de señal $percent%',
        fr: 'intensité du signal $percent %',
        de: 'Signalstärke $percent%',
        ar: 'قوة الإشارة $percent%',
      );

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
    var value = ui(key);
    for (final entry in params.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
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
    return SynchronousFuture(AppStrings(const Locale('en')));
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
