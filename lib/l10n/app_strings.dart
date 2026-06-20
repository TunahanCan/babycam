import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/media/adaptive_media_profile.dart';
import 'src/app_ui_text_catalog.dart';

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

  String _t({
    required String tr,
    required String en,
    required String zh,
    String? hi,
    String? es,
    String? fr,
  }) {
    if (isTurkish) return tr;
    if (isChinese) return zh;
    if (isHindi) return hi ?? en;
    if (isSpanish) return es ?? en;
    if (isFrench) return fr ?? en;
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
                        : en;
    return values[seed.abs() % values.length];
  }

  String get appTitle => 'MimiCam';
  String get reset => _t(
      tr: 'Sıfırla',
      en: 'Reset',
      zh: '重置',
      hi: 'रीसेट',
      es: 'Restablecer',
      fr: 'Réinitialiser');
  String get server => 'Server';
  String get client => 'Client';
  String get selectRoleStatus => _t(
      tr: 'Rol seçin: Server yayın yapar, Client yayını izler.',
      en: 'Choose a role: Server streams, Client watches the stream.',
      zh: '请选择角色：Server 负责直播，Client 负责观看。',
      hi: 'भूमिका चुनें: Server प्रसारण करता है, Client प्रसारण देखता है।',
      es: 'Elige un rol: Server transmite y Client mira la transmisión.',
      fr: 'Choisissez un rôle : Server diffuse, Client regarde le flux.');
  String serverActiveStatus(String url) => _t(
      tr: 'Server aktif. Client cihazlarda bu adresi açın: $url',
      en: 'Server is active. Open this address on client devices: $url',
      zh: 'Server 已启动。请在 Client 设备打开此地址：$url',
      hi: 'Server सक्रिय है। Client उपकरणों पर यह पता खोलें: $url',
      es: 'Server está activo. Abre esta dirección en los dispositivos Client: $url',
      fr: 'Server est actif. Ouvrez cette adresse sur les appareils Client : $url');
  String get clientSearchingLog => _t(
      tr: 'Client modu: QR veya IP ile eşleşmeye hazır.',
      en: 'Client mode: ready to pair via QR or IP.',
      zh: 'Client 模式：可通过二维码或 IP 配对。',
      hi: 'Client मोड: QR या IP से पेयर करने के लिए तैयार।',
      es: 'Modo Client: listo para emparejar por QR o IP.',
      fr: 'Mode Client : prêt à s’appairer par QR ou IP.');
  String get clientActiveStatus => _t(
      tr: 'Client modu aktif. QR veya IP ile bebek odasına bağlan.',
      en: 'Client mode is active. Connect to the baby room via QR or IP.',
      zh: 'Client 模式已启用。请通过二维码或 IP 连接婴儿房。',
      hi: 'Client मोड सक्रिय है। QR या IP से बच्चे के कमरे से जुड़ें।',
      es: 'Modo Client activo. Conecta con la habitación del bebé por QR o IP.',
      fr: 'Mode Client actif. Connectez-vous à la chambre du bébé par QR ou IP.');
  String get alertWebSocketDisconnected => _t(
      tr: 'Uyarı WebSocket bağlantısı koptu.',
      en: 'Alert WebSocket connection was lost.',
      zh: '提醒 WebSocket 连接已断开。',
      hi: 'Alert WebSocket कनेक्शन टूट गया।',
      es: 'Se perdió la conexión WebSocket de alertas.',
      fr: 'La connexion WebSocket des alertes a été perdue.');
  String clientConnectedStatus(String url) => _t(
      tr: 'Client bağlı: $url',
      en: 'Client connected: $url',
      zh: 'Client 已连接：$url',
      hi: 'Client जुड़ा: $url',
      es: 'Client conectado: $url',
      fr: 'Client connecté : $url');
  String serverAlertLog(String message) => _t(
      tr: 'Server uyarısı: $message',
      en: 'Server alert: $message',
      zh: 'Server 提醒：$message',
      hi: 'Server अलर्ट: $message',
      es: 'Alerta de Server: $message',
      fr: 'Alerte Server : $message');
  String get roleResetStatus => _t(
      tr: 'Rol sıfırlandı. Server veya Client seçin.',
      en: 'Role reset. Choose Server or Client.',
      zh: '角色已重置。请选择 Server 或 Client。',
      hi: 'भूमिका रीसेट हो गई। Server या Client चुनें।',
      es: 'Rol restablecido. Elige Server o Client.',
      fr: 'Rôle réinitialisé. Choisissez Server ou Client.');
  String get addressPreparing => _t(
      tr: 'Adres hazırlanıyor...',
      en: 'Preparing address...',
      zh: '正在准备地址…',
      hi: 'पता तैयार हो रहा है…',
      es: 'Preparando dirección…',
      fr: 'Préparation de l’adresse…');
  String get serverAddressLabel => _t(
      tr: 'Server adresi (IP veya IP:8080)',
      en: 'Server address (IP or IP:8080)',
      zh: 'Server 地址（IP 或 IP:8080）',
      hi: 'Server पता (IP या IP:8080)',
      es: 'Dirección de Server (IP o IP:8080)',
      fr: 'Adresse Server (IP ou IP:8080)');
  String get waitingForServer => _t(
      tr: 'Server bekleniyor...',
      en: 'Waiting for server...',
      zh: '等待 Server…',
      hi: 'Server की प्रतीक्षा…',
      es: 'Esperando Server…',
      fr: 'En attente de Server…');

  String get notificationTitle => _t(
      tr: 'MimiCam uyarısı',
      en: 'MimiCam alert',
      zh: 'MimiCam 提醒',
      hi: 'MimiCam अलर्ट',
      es: 'Alerta de MimiCam',
      fr: 'Alerte MimiCam');
  String get notificationChannelName => _t(
      tr: 'MimiCam Uyarıları',
      en: 'MimiCam Alerts',
      zh: 'MimiCam 提醒',
      hi: 'MimiCam अलर्ट',
      es: 'Alertas de MimiCam',
      fr: 'Alertes MimiCam');

  String get cameraNotFound => _t(
      tr: 'Kamera bulunamadı.',
      en: 'Camera not found.',
      zh: '未找到摄像头。',
      hi: 'कैमरा नहीं मिला।',
      es: 'No se encontró la cámara.',
      fr: 'Caméra introuvable.');
  String serverStartedLog(String url) => _t(
      tr: 'Server başladı: $url',
      en: 'Server started: $url',
      zh: 'Server 已启动：$url',
      hi: 'Server शुरू हुआ: $url',
      es: 'Server iniciado: $url',
      fr: 'Server démarré : $url');
  String get microphonePermissionMissing => _t(
      tr: 'Mikrofon izni yok; ses analizi devre dışı.',
      en: 'Microphone permission is missing; audio analysis is disabled.',
      zh: '缺少麦克风权限；声音分析已关闭。',
      hi: 'माइक्रोफ़ोन अनुमति नहीं है; ध्वनि विश्लेषण बंद है।',
      es: 'Falta el permiso del micrófono; el análisis de audio está desactivado.',
      fr: 'L’autorisation du microphone manque ; l’analyse audio est désactivée.');
  String audioAnalysisLog(String summary) => _t(
      tr: 'Ses analizi: $summary',
      en: 'Audio analysis: $summary',
      zh: '声音分析：$summary',
      hi: 'ऑडियो विश्लेषण: $summary',
      es: 'Análisis de audio: $summary',
      fr: 'Analyse audio : $summary');
  String audioAlert(String reason, int confidencePercent, String summary) => _t(
      tr: '🔊 $reason. Güven $confidencePercent%. $summary',
      en: '🔊 $reason. Confidence $confidencePercent%. $summary',
      zh: '🔊 $reason。置信度 $confidencePercent%。$summary',
      hi: '🔊 $reason। भरोसा $confidencePercent%. $summary',
      es: '🔊 $reason. Confianza $confidencePercent%. $summary',
      fr: '🔊 $reason. Confiance $confidencePercent %. $summary');
  String motionAlert(int scorePercent) => _t(
      tr: '👶 Hareket algılandı. Skor: $scorePercent%',
      en: '👶 Motion detected. Score: $scorePercent%',
      zh: '👶 检测到活动。评分：$scorePercent%',
      hi: '👶 गतिविधि मिली। स्कोर: $scorePercent%',
      es: '👶 Movimiento detectado. Puntuación: $scorePercent%',
      fr: '👶 Mouvement détecté. Score : $scorePercent %');
  String webSocketClientConnected(String address) => _t(
      tr: 'WebSocket client bağlandı: $address',
      en: 'WebSocket client connected: $address',
      zh: 'WebSocket Client 已连接：$address',
      hi: 'WebSocket Client जुड़ा: $address',
      es: 'Client WebSocket conectado: $address',
      fr: 'Client WebSocket connecté : $address');

  String get unknownFundamentalFrequency => _t(
      tr: 'belirsiz',
      en: 'unknown',
      zh: '未知',
      hi: 'अज्ञात',
      es: 'desconocido',
      fr: 'inconnu');
  String get noSoundReason => _t(
      tr: 'Ses yok',
      en: 'No sound',
      zh: '无声音',
      hi: 'कोई आवाज़ नहीं',
      es: 'Sin sonido',
      fr: 'Aucun son');
  String get cryingSound => _t(
      tr: 'ağlama',
      en: 'crying',
      zh: '哭声',
      hi: 'रोना',
      es: 'llanto',
      fr: 'pleurs');
  String get moaningSound => _t(
      tr: 'inleme',
      en: 'moaning',
      zh: '低吟声',
      hi: 'कराहना',
      es: 'quejido',
      fr: 'gémissement');
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
          fr: 'niveau ${dbfs.toStringAsFixed(1)} dBFS, ambiance ${ambientDbfs.toStringAsFixed(1)} dBFS, F0 $f0, centre $centroidHz Hz, bande $bandwidthHz Hz, ZCR ${zcr.toStringAsFixed(2)}, entropie ${entropy.toStringAsFixed(2)}, pleurs $cryPercent %, gémissement $moanPercent %');
  String pitchSuffix(int fundamentalHz) => fundamentalHz > 0
      ? _t(
          tr: ', temel frekans $fundamentalHz Hz',
          en: ', fundamental frequency $fundamentalHz Hz',
          zh: '，基频 $fundamentalHz Hz',
          hi: ', मूल आवृत्ति $fundamentalHz Hz',
          es: ', frecuencia fundamental $fundamentalHz Hz',
          fr: ', fréquence fondamentale $fundamentalHz Hz')
      : '';
  String cryLikeReason(String pitch, int centroidHz) => _t(
      tr: 'Ağlama benzeri vokal ses$pitch, parlaklık $centroidHz Hz',
      en: 'Cry-like vocal sound$pitch, brightness $centroidHz Hz',
      zh: '类似哭声的人声$pitch，明亮度 $centroidHz Hz',
      hi: 'रोने जैसी स्वर ध्वनि$pitch, चमक $centroidHz Hz',
      es: 'Sonido vocal similar al llanto$pitch, brillo $centroidHz Hz',
      fr: 'Son vocal semblable à des pleurs$pitch, brillance $centroidHz Hz');
  String moanLikeReason(String pitch, int centroidHz) => _t(
      tr: 'İnleme benzeri düşük frekanslı sürekli ses$pitch, merkez $centroidHz Hz',
      en: 'Moan-like low-frequency sustained sound$pitch, center $centroidHz Hz',
      zh: '类似低频持续低吟的声音$pitch，中心 $centroidHz Hz',
      hi: 'कराह जैसी कम-आवृत्ति की लगातार ध्वनि$pitch, केंद्र $centroidHz Hz',
      es: 'Sonido sostenido de baja frecuencia similar a un quejido$pitch, centro $centroidHz Hz',
      fr: 'Son grave soutenu semblable à un gémissement$pitch, centre $centroidHz Hz');

  String get streamActiveHtml => _t(
      tr: 'LAN MJPEG yayını aktif.',
      en: 'LAN MJPEG stream is active.',
      zh: 'LAN MJPEG 直播已启动。',
      hi: 'LAN MJPEG स्ट्रीम सक्रिय है।',
      es: 'La transmisión LAN MJPEG está activa.',
      fr: 'Le flux LAN MJPEG est actif.');
  String get audioOnlyHtml => _t(
      tr: 'Sadece WAV ses akışı',
      en: 'WAV audio stream only',
      zh: '仅 WAV 音频流',
      hi: 'केवल WAV ऑडियो स्ट्रीम',
      es: 'Solo flujo de audio WAV',
      fr: 'Flux audio WAV uniquement');

  String parentCryAlert({
    required int confidencePercent,
    required double ambientDeltaDb,
    required int cryBandPercent,
    required bool calibrated,
  }) {
    final calibration = calibrated
        ? _t(
            tr: 'oda sesine göre kalibre',
            en: 'room-calibrated',
            zh: '已按房间噪声校准',
            hi: 'कमरे की आवाज़ के अनुसार कैलिब्रेटेड',
            es: 'calibrado según el ruido de la habitación',
            fr: 'calibré selon le bruit de la pièce')
        : _t(
            tr: 'kalibrasyon sürüyor',
            en: 'calibrating',
            zh: '正在校准',
            hi: 'कैलिब्रेशन जारी है',
            es: 'calibrando',
            fr: 'calibrage en cours');
    final delta = ambientDeltaDb.toStringAsFixed(1);
    final seed = confidencePercent +
        cryBandPercent +
        ambientDeltaDb.round() +
        (calibrated ? 1 : 0);
    return _variant(
      seed: seed,
      tr: [
        '🔊 Ağlama olasılığı yüksek ($confidencePercent%). Ses ortamdan $delta dB yüksek; ağlama bandı %$cryBandPercent. $calibration. Önce güvenli şekilde odayı kontrol et: açlık, bez, gaz, sıcak/soğuk veya sarılma ihtiyacı olabilir.',
        '👶 Bebeğin sesi ağlamaya benziyor ($confidencePercent%). Ortamın $delta dB üstünde ve ağlama bandı %$cryBandPercent. $calibration. Kısa bir oda kontrolü iyi olur: rahatlık, bez, gaz ve sıcaklık.',
        '🍼 Uzayan bir huzursuzluk sinyali var ($confidencePercent%). Ses $delta dB yükseldi; ağlama bandı %$cryBandPercent. $calibration. Önce sakin bir görsel kontrol yap, sonra ihtiyaçları sırayla değerlendir.',
      ],
      en: [
        '🔊 Cry likelihood is high ($confidencePercent%). Sound is $delta dB above ambient; cry-band energy is $cryBandPercent%. $calibration. Please check the room safely: hunger, diaper, gas, temperature, or need for comfort may be possible.',
        '👶 Baby sounds likely to be crying ($confidencePercent%). The room is $delta dB louder than baseline and cry-band energy is $cryBandPercent%. $calibration. A calm room check is recommended: comfort, diaper, gas, and temperature.',
        '🍼 A sustained fuss/cry signal is building ($confidencePercent%). Audio rose $delta dB; cry-band energy is $cryBandPercent%. $calibration. Start with a safe visual check, then review likely needs one by one.',
      ],
      zh: [
        '🔊 哭声可能性较高（$confidencePercent%）。声音比环境高 $delta dB；哭声频段能量 $cryBandPercent%。$calibration。请安全查看房间：可能是饿了、尿布、胀气、冷热或需要安抚。',
        '👶 宝宝的声音像在哭（$confidencePercent%）。房间声音比基线高 $delta dB，哭声频段 $cryBandPercent%。$calibration。建议平静地查看：安抚、尿布、胀气和温度。',
        '🍼 检测到持续烦躁/哭声信号（$confidencePercent%）。声音上升 $delta dB；哭声频段 $cryBandPercent%。$calibration。先安全查看画面，再逐项确认需求。',
      ],
      hi: [
        '🔊 रोने की संभावना अधिक है ($confidencePercent%)। आवाज़ परिवेश से $delta dB अधिक है; रोने वाले बैंड की ऊर्जा $cryBandPercent%। $calibration। कमरे को सुरक्षित रूप से देखें: भूख, डायपर, गैस, तापमान या आराम की ज़रूरत हो सकती है।',
        '👶 बच्चे की आवाज़ रोने जैसी लग रही है ($confidencePercent%)। कमरा बेसलाइन से $delta dB तेज़ है और cry-band ऊर्जा $cryBandPercent% है। $calibration। शांत होकर देखें: आराम, डायपर, गैस और तापमान।',
        '🍼 लगातार बेचैनी/रोने का संकेत बन रहा है ($confidencePercent%)। ऑडियो $delta dB बढ़ा; cry-band ऊर्जा $cryBandPercent%। $calibration। पहले सुरक्षित दृश्य जाँच करें, फिर ज़रूरतों को क्रम से देखें।',
      ],
      es: [
        '🔊 La probabilidad de llanto es alta ($confidencePercent%). El sonido está $delta dB por encima del ambiente; energía de banda de llanto $cryBandPercent%. $calibration. Revisa la habitación con seguridad: puede ser hambre, pañal, gases, temperatura o necesidad de consuelo.',
        '👶 El sonido del bebé parece llanto ($confidencePercent%). La habitación está $delta dB sobre la base y la banda de llanto marca $cryBandPercent%. $calibration. Conviene revisar con calma: consuelo, pañal, gases y temperatura.',
        '🍼 Se forma una señal sostenida de inquietud/llanto ($confidencePercent%). El audio subió $delta dB; banda de llanto $cryBandPercent%. $calibration. Empieza con una revisión visual segura y luego mira las necesidades probables.',
      ],
      fr: [
        '🔊 Probabilité de pleurs élevée ($confidencePercent %). Le son est $delta dB au-dessus de l’ambiance ; énergie de la bande des pleurs $cryBandPercent %. $calibration. Vérifiez la chambre en sécurité : faim, couche, gaz, température ou besoin de réconfort possibles.',
        '👶 Le son du bébé ressemble à des pleurs ($confidencePercent %). La chambre est $delta dB au-dessus du niveau de base et la bande des pleurs est à $cryBandPercent %. $calibration. Vérifiez calmement : réconfort, couche, gaz et température.',
        '🍼 Un signal prolongé d’inconfort/pleurs apparaît ($confidencePercent %). L’audio a monté de $delta dB ; bande des pleurs $cryBandPercent %. $calibration. Commencez par un contrôle visuel sûr, puis vérifiez les besoins probables.',
      ],
    );
  }

  String parentLoudSoundAlert({
    required double dbfs,
    required double ambientDeltaDb,
  }) {
    final level = dbfs.toStringAsFixed(1);
    final delta = ambientDeltaDb.toStringAsFixed(1);
    final seed = (dbfs.abs() + ambientDeltaDb).floor();
    return _variant(
      seed: seed,
      tr: [
        '🔔 Ani yüksek ses algılandı. Seviye $level dBFS; ortamdan $delta dB yüksek. Bebeğin uyanıp uyanmadığını ve odada beklenmeyen bir ses kaynağı olup olmadığını kontrol et.',
        '🚪 Odada kısa ve güçlü bir ses yükselmesi var. Seviye $level dBFS, ortamın $delta dB üstünde. Kapı, oyuncak, ev sesi veya bebeğin irkilmesi açısından bakmak iyi olur.',
        '⚠️ Ses seviyesi bir anda yükseldi ($level dBFS). Ortam farkı $delta dB. Eğer bebek uyuyorsa görüntüyü ve çevrede düşen/çarpan bir şey olup olmadığını kontrol et.',
      ],
      en: [
        '🔔 Sudden loud sound detected. Level $level dBFS; $delta dB above ambient. Check whether the baby woke up and whether there is an unexpected noise source.',
        '🚪 A short, strong sound spike happened in the room. Level $level dBFS, $delta dB above baseline. Check for a door, toy, household noise, or a startled baby.',
        '⚠️ Audio jumped quickly ($level dBFS). Difference from ambient is $delta dB. If the baby is sleeping, check the image and whether something fell or bumped nearby.',
      ],
      zh: [
        '🔔 检测到突然的大声响。音量 $level dBFS，比环境高 $delta dB。请查看宝宝是否醒来，以及房间是否有异常声源。',
        '🚪 房间出现短促而明显的声音峰值。音量 $level dBFS，比基线高 $delta dB。请查看门、玩具、家中噪声或宝宝是否受惊。',
        '⚠️ 声音突然升高（$level dBFS）。比环境高 $delta dB。如果宝宝在睡觉，请查看画面以及附近是否有掉落或碰撞。',
      ],
      hi: [
        '🔔 अचानक तेज़ आवाज़ मिली। स्तर $level dBFS; परिवेश से $delta dB अधिक। देखें कि बच्चा जागा है या कमरे में कोई अनपेक्षित आवाज़ है।',
        '🚪 कमरे में छोटी लेकिन तेज़ आवाज़ आई। स्तर $level dBFS, बेसलाइन से $delta dB ऊपर। दरवाज़ा, खिलौना, घर की आवाज़ या बच्चे के चौंकने की जाँच करें।',
        '⚠️ आवाज़ अचानक बढ़ी ($level dBFS)। परिवेश से फर्क $delta dB है। बच्चा सो रहा हो तो तस्वीर और आसपास गिरी/टकराई चीज़ देखें।',
      ],
      es: [
        '🔔 Se detectó un sonido fuerte repentino. Nivel $level dBFS; $delta dB sobre el ambiente. Revisa si el bebé se despertó o si hay una fuente de ruido inesperada.',
        '🚪 Hubo un pico de sonido breve y fuerte en la habitación. Nivel $level dBFS, $delta dB sobre la base. Revisa puerta, juguete, ruido de casa o si el bebé se sobresaltó.',
        '⚠️ El audio subió de golpe ($level dBFS). Diferencia con el ambiente: $delta dB. Si el bebé duerme, mira la imagen y si algo cayó o golpeó cerca.',
      ],
      fr: [
        '🔔 Son fort soudain détecté. Niveau $level dBFS ; $delta dB au-dessus de l’ambiance. Vérifiez si le bébé s’est réveillé ou s’il y a une source de bruit inattendue.',
        '🚪 Un pic sonore bref et fort a eu lieu dans la chambre. Niveau $level dBFS, $delta dB au-dessus du niveau de base. Vérifiez porte, jouet, bruit domestique ou bébé surpris.',
        '⚠️ L’audio a brusquement monté ($level dBFS). Écart avec l’ambiance : $delta dB. Si le bébé dort, regardez l’image et vérifiez si quelque chose est tombé ou a heurté.',
      ],
    );
  }

  String parentMotionAlert({
    required int scorePercent,
    required int activeAreaPercent,
    required double meanDiff,
  }) {
    final mean = meanDiff.toStringAsFixed(1);
    final seed = scorePercent + activeAreaPercent + meanDiff.round();
    return _variant(
      seed: seed,
      tr: [
        '👶 Hareket algılandı ($scorePercent%). Görüntünün yaklaşık %$activeAreaPercent bölgesinde değişim var; ortalama değişim $mean. Bebeğin pozisyonunu ve örtü/kenar güvenliğini kontrol et.',
        '🧸 Bebek alanında hareket var ($scorePercent%). Görüntü değişimi %$activeAreaPercent, ortalama fark $mean. Pozisyon değiştiyse örtü ve yatak kenarını hızlıca kontrol et.',
        '📹 Kamera hareket sinyali yakaladı ($scorePercent%). Aktif alan %$activeAreaPercent; değişim $mean. Görüntüye bakıp bebeğin rahat durduğundan emin ol.',
      ],
      en: [
        '👶 Motion detected ($scorePercent%). About $activeAreaPercent% of the image changed; average change $mean. Check the baby’s position and blanket/edge safety.',
        '🧸 Movement appeared around the baby area ($scorePercent%). Image change $activeAreaPercent%, average difference $mean. If position changed, quickly check blanket and crib edge.',
        '📹 Camera caught a motion signal ($scorePercent%). Active area $activeAreaPercent%; change $mean. Look at the image and make sure the baby is resting comfortably.',
      ],
      zh: [
        '👶 检测到活动（$scorePercent%）。画面约 $activeAreaPercent% 区域发生变化；平均变化 $mean。请查看宝宝姿势以及毯子/床边安全。',
        '🧸 宝宝区域有活动（$scorePercent%）。画面变化 $activeAreaPercent%，平均差异 $mean。若姿势改变，请快速检查毯子和床边。',
        '📹 摄像头捕捉到活动信号（$scorePercent%）。活动区域 $activeAreaPercent%；变化 $mean。请查看画面，确认宝宝舒适安全。',
      ],
      hi: [
        '👶 गतिविधि मिली ($scorePercent%)। चित्र के लगभग $activeAreaPercent% हिस्से में बदलाव है; औसत बदलाव $mean। बच्चे की स्थिति और कंबल/किनारे की सुरक्षा देखें।',
        '🧸 बच्चे वाले क्षेत्र में हलचल है ($scorePercent%)। चित्र बदलाव $activeAreaPercent%, औसत फर्क $mean। स्थिति बदली हो तो कंबल और पालने के किनारे को जल्दी देखें।',
        '📹 कैमरे ने गतिविधि संकेत पकड़ा ($scorePercent%)। सक्रिय क्षेत्र $activeAreaPercent%; बदलाव $mean। चित्र देखकर सुनिश्चित करें कि बच्चा आराम से है।',
      ],
      es: [
        '👶 Movimiento detectado ($scorePercent%). Cambió aproximadamente el $activeAreaPercent% de la imagen; cambio medio $mean. Revisa la posición del bebé y la seguridad de la manta/borde.',
        '🧸 Hay movimiento en la zona del bebé ($scorePercent%). Cambio de imagen $activeAreaPercent%, diferencia media $mean. Si cambió de posición, revisa rápido manta y borde de la cuna.',
        '📹 La cámara captó movimiento ($scorePercent%). Área activa $activeAreaPercent%; cambio $mean. Mira la imagen y confirma que el bebé está cómodo.',
      ],
      fr: [
        '👶 Mouvement détecté ($scorePercent %). Environ $activeAreaPercent % de l’image a changé ; variation moyenne $mean. Vérifiez la position du bébé et la sécurité couverture/bord.',
        '🧸 Mouvement dans la zone du bébé ($scorePercent %). Changement d’image $activeAreaPercent %, écart moyen $mean. Si la position a changé, vérifiez vite couverture et bord du lit.',
        '📹 La caméra a capté un mouvement ($scorePercent %). Zone active $activeAreaPercent % ; variation $mean. Regardez l’image et confirmez que le bébé est bien installé.',
      ],
    );
  }

  String parentLightChangeAlert({
    required int scorePercent,
    required double lumaShift,
  }) {
    final shift = lumaShift.toStringAsFixed(1);
    final seed = scorePercent + lumaShift.round();
    return _variant(
      seed: seed,
      tr: [
        '💡 Oda ışığı değişti ($scorePercent%). Parlaklık kayması $shift. Kamera görüşü veya gece lambası değişmiş olabilir; görüntüyü hızlıca kontrol et.',
        '🌙 Işık seviyesi farklılaştı ($scorePercent%). Parlaklık farkı $shift. Perde, kapı aralığı ya da gece lambası görüntüyü etkilemiş olabilir.',
        '📷 Kamera ışık değişimi algıladı ($scorePercent%). Luma kayması $shift. Hareket değil ışık değişimi gibi görünüyor; yine de görüntüyü bir kez kontrol et.',
      ],
      en: [
        '💡 Room light changed ($scorePercent%). Brightness shift $shift. Camera view or night light may have changed; quickly check the image.',
        '🌙 Light level changed ($scorePercent%). Brightness difference $shift. Curtain, door gap, or night light may be affecting the image.',
        '📷 Camera detected a lighting change ($scorePercent%). Luma shift $shift. It looks like light rather than motion; still, check the image once.',
      ],
      zh: [
        '💡 房间光线发生变化（$scorePercent%）。亮度偏移 $shift。可能是摄像头视野或夜灯变化；请快速查看画面。',
        '🌙 光线水平有变化（$scorePercent%）。亮度差 $shift。窗帘、门缝或夜灯可能影响画面。',
        '📷 摄像头检测到光线变化（$scorePercent%）。亮度偏移 $shift。看起来更像光线而非动作；仍建议查看一次画面。',
      ],
      hi: [
        '💡 कमरे की रोशनी बदली ($scorePercent%)। चमक बदलाव $shift। कैमरा दृश्य या नाइट लाइट बदली हो सकती है; चित्र जल्दी देखें।',
        '🌙 रोशनी का स्तर बदला ($scorePercent%)। चमक अंतर $shift। पर्दा, दरवाज़े की दरार या नाइट लाइट चित्र को प्रभावित कर सकती है।',
        '📷 कैमरे ने रोशनी बदलाव पकड़ा ($scorePercent%)। लूमा बदलाव $shift। यह हलचल से ज़्यादा रोशनी जैसा लगता है; फिर भी चित्र एक बार देखें।',
      ],
      es: [
        '💡 Cambió la luz de la habitación ($scorePercent%). Desplazamiento de brillo $shift. Puede haber cambiado la vista de la cámara o la luz nocturna; revisa la imagen.',
        '🌙 Cambió el nivel de luz ($scorePercent%). Diferencia de brillo $shift. Cortina, rendija de puerta o luz nocturna pueden afectar la imagen.',
        '📷 La cámara detectó cambio de luz ($scorePercent%). Desplazamiento luma $shift. Parece luz más que movimiento; aun así revisa la imagen una vez.',
      ],
      fr: [
        '💡 La lumière de la chambre a changé ($scorePercent %). Décalage de luminosité $shift. La vue caméra ou la veilleuse a peut-être changé ; vérifiez rapidement l’image.',
        '🌙 Le niveau de lumière a changé ($scorePercent %). Différence de luminosité $shift. Rideau, porte entrouverte ou veilleuse peuvent affecter l’image.',
        '📷 La caméra a détecté un changement lumineux ($scorePercent %). Décalage luma $shift. Cela ressemble plus à la lumière qu’à un mouvement ; vérifiez quand même l’image.',
      ],
    );
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
        tr: 'son hareket yok',
        en: 'no recent motion',
        zh: '最近没有动作',
        hi: 'हाल की हलचल नहीं',
        es: 'sin movimiento reciente',
        fr: 'aucun mouvement récent',
      );
    }
    final seconds = (agoMs / 1000).round();
    return _t(
      tr: '$seconds sn önce',
      en: '$seconds sec ago',
      zh: '$seconds 秒前',
      hi: '$seconds सेकंड पहले',
      es: 'hace $seconds s',
      fr: 'il y a $seconds s',
    );
  }

  String parentEpisodeHighCryAlert({
    required int seconds,
    required String motionAgo,
    required String networkTier,
  }) =>
      _variant(
        seed: seconds,
        tr: [
          'Yaklaşık $seconds sn süren yüksek ağlama algılandı. Son hareket $motionAgo. Yayın $networkTier modunda.',
          'Ağlama güçlü ve $seconds sn civarı sürdü. Hareket bilgisi: $motionAgo. Bağlantı kalitesi $networkTier; önce odayı güvenle kontrol et.',
          'Uzayan yüksek ağlama var: ~$seconds sn. Son hareket $motionAgo. Yayın $networkTier seviyesinde; ses önceliği korunuyor.',
        ],
        en: [
          'High-intensity crying lasted about $seconds sec. Last motion $motionAgo. Stream is in $networkTier mode.',
          'Crying stayed strong for around $seconds sec. Motion info: $motionAgo. Connection quality is $networkTier; please check the room safely.',
          'Sustained high crying detected: ~$seconds sec. Last motion $motionAgo. Stream is $networkTier; audio priority is preserved.',
        ],
        zh: [
          '检测到约 $seconds 秒的高强度哭声。最后动作：$motionAgo。直播处于 $networkTier 模式。',
          '哭声明显持续约 $seconds 秒。动作信息：$motionAgo。连接质量为 $networkTier；请安全查看房间。',
          '检测到持续高强度哭声：约 $seconds 秒。最后动作 $motionAgo。直播 $networkTier，已保持音频优先。',
        ],
        hi: [
          'लगभग $seconds सेकंड तक तेज़ रोना मिला। अंतिम हलचल $motionAgo। स्ट्रीम $networkTier मोड में है।',
          'रोना करीब $seconds सेकंड तक तेज़ रहा। हलचल जानकारी: $motionAgo। कनेक्शन गुणवत्ता $networkTier है; कमरे को सुरक्षित रूप से देखें।',
          'लगातार तेज़ रोना मिला: ~$seconds सेकंड। अंतिम हलचल $motionAgo। स्ट्रीम $networkTier है; ऑडियो प्राथमिकता सुरक्षित है।',
        ],
        es: [
          'Llanto intenso durante unos $seconds s. Último movimiento $motionAgo. La transmisión está en modo $networkTier.',
          'El llanto se mantuvo fuerte unos $seconds s. Movimiento: $motionAgo. Calidad de conexión $networkTier; revisa la habitación con seguridad.',
          'Llanto intenso sostenido: ~$seconds s. Último movimiento $motionAgo. Transmisión $networkTier; se mantiene prioridad de audio.',
        ],
        fr: [
          'Pleurs intenses pendant environ $seconds s. Dernier mouvement $motionAgo. Le flux est en mode $networkTier.',
          'Les pleurs sont restés forts environ $seconds s. Mouvement : $motionAgo. Qualité de connexion $networkTier ; vérifiez la chambre en sécurité.',
          'Pleurs intenses prolongés : ~$seconds s. Dernier mouvement $motionAgo. Flux $networkTier ; priorité audio conservée.',
        ],
      );

  String parentEpisodeShortSoundAlert({required int seconds}) => _variant(
        seed: seconds,
        tr: [
          'Kısa süreli ses yükselmesi algılandı. Devam ederse tekrar bildirilecek.',
          'Kısa bir huzursuzluk sesi duyuldu; şu an uzayan ağlama gibi görünmüyor.',
          'Ses kısa süre yükseldi ve sakinleşti. Tekrarlarsa yeni uyarı göndereceğim.',
        ],
        en: [
          'Short sound rise detected. If it continues, another alert will be sent.',
          'A brief fuss sound was heard; it does not look like sustained crying right now.',
          'Audio rose briefly and settled. I’ll alert again if it repeats.',
        ],
        zh: [
          '检测到短暂声音升高。如果持续，会再次提醒。',
          '听到短暂烦躁声；目前不像持续哭声。',
          '声音短暂升高后恢复。若再次出现，会再次提醒。',
        ],
        hi: [
          'थोड़ी देर की आवाज़ बढ़ी। जारी रही तो फिर सूचना भेजी जाएगी।',
          'छोटी बेचैनी की आवाज़ सुनी गई; अभी यह लगातार रोना नहीं लग रहा।',
          'आवाज़ थोड़ी देर बढ़ी और शांत हुई। दोहराई तो फिर अलर्ट भेजूँगा।',
        ],
        es: [
          'Se detectó una subida breve de sonido. Si continúa, se enviará otra alerta.',
          'Se oyó un sonido breve de inquietud; ahora no parece llanto sostenido.',
          'El audio subió un momento y se calmó. Avisaré de nuevo si se repite.',
        ],
        fr: [
          'Courte hausse sonore détectée. Si elle continue, une autre alerte sera envoyée.',
          'Un bref son d’inconfort a été entendu ; cela ne ressemble pas à des pleurs prolongés pour l’instant.',
          'Le son a monté brièvement puis s’est calmé. J’alerterai à nouveau si cela se répète.',
        ],
      );

  String parentEpisodeCryAlert({
    required int seconds,
    required String networkTier,
  }) =>
      _variant(
        seed: seconds,
        tr: [
          'Yaklaşık $seconds sn süren ağlama sinyali algılandı. Yayın $networkTier modunda.',
          '$seconds sn civarı devam eden huzursuzluk/ağlama var. Bağlantı $networkTier; ses takibi aktif.',
          'Ağlama sinyali doğrulandı ve $seconds sn sürdü. Yayın $networkTier; görüntü kalitesi gerekirse düşürüldü.',
        ],
        en: [
          'Crying signal lasted about $seconds sec. Stream is in $networkTier mode.',
          'Fuss/cry signal continued for around $seconds sec. Connection $networkTier; audio monitoring is active.',
          'Crying signal was confirmed and lasted $seconds sec. Stream $networkTier; video quality may be reduced if needed.',
        ],
        zh: [
          '检测到约 $seconds 秒的哭声信号。直播处于 $networkTier 模式。',
          '烦躁/哭声信号持续约 $seconds 秒。连接 $networkTier；声音监测已开启。',
          '哭声信号已确认并持续 $seconds 秒。直播 $networkTier；必要时会降低画质。',
        ],
        hi: [
          'लगभग $seconds सेकंड का रोने का संकेत मिला। स्ट्रीम $networkTier मोड में है।',
          'बेचैनी/रोने का संकेत करीब $seconds सेकंड चला। कनेक्शन $networkTier; ऑडियो निगरानी सक्रिय है।',
          'रोने का संकेत पुष्टि हुआ और $seconds सेकंड चला। स्ट्रीम $networkTier; ज़रूरत हो तो वीडियो गुणवत्ता घटेगी।',
        ],
        es: [
          'Se detectó señal de llanto durante unos $seconds s. La transmisión está en modo $networkTier.',
          'La señal de inquietud/llanto continuó unos $seconds s. Conexión $networkTier; monitoreo de audio activo.',
          'La señal de llanto se confirmó y duró $seconds s. Transmisión $networkTier; la calidad de video puede bajar si hace falta.',
        ],
        fr: [
          'Signal de pleurs détecté pendant environ $seconds s. Le flux est en mode $networkTier.',
          'Le signal inconfort/pleurs a continué environ $seconds s. Connexion $networkTier ; suivi audio actif.',
          'Signal de pleurs confirmé pendant $seconds s. Flux $networkTier ; la qualité vidéo peut baisser si nécessaire.',
        ],
      );

  String ui(String key) {
    final values = appUiTextCatalog[key];
    if (values == null) return key;
    return values[locale.languageCode] ?? values['en'] ?? key;
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
    final languageCode = AppStrings.supportedLocales
            .any((supported) => supported.languageCode == locale.languageCode)
        ? locale.languageCode
        : 'en';
    return SynchronousFuture(AppStrings(Locale(languageCode)));
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
