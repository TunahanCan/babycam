import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/media/adaptive_media_profile.dart';

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
    final values = _uiText[key];
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

const _uiText = <String, Map<String, String>>{
  'bootstrapPreparing': {
    'tr': 'MimiCam hazırlanıyor...',
    'en': 'Preparing MimiCam...',
    'zh': 'MimiCam 正在准备…',
    'hi': 'MimiCam तैयार हो रहा है…',
    'es': 'Preparando MimiCam…',
    'fr': 'Préparation de MimiCam…',
  },
  'roleSwitching': {
    'tr': 'Rol değiştiriliyor...',
    'en': 'Switching role...',
    'zh': '正在切换角色…',
    'hi': 'भूमिका बदली जा रही है…',
    'es': 'Cambiando rol…',
    'fr': 'Changement de rôle…',
  },
  'confirmLeaveServerTitle': {
    'tr': 'Server modundan çıkılsın mı?',
    'en': 'Leave Server mode?',
    'zh': '要离开 Server 模式吗？',
    'hi': 'Server मोड से बाहर निकलें?',
    'es': '¿Salir del modo Server?',
    'fr': 'Quitter le mode Server ?',
  },
  'confirmLeaveServerBody': {
    'tr':
        'Client moduna geçersen bebek odası yayını ve yerel servisler kapatılır.',
    'en':
        'If you switch to Client mode, the baby room stream and local services will stop.',
    'zh': '切换到 Client 模式后，婴儿房直播和本地服务会停止。',
    'hi':
        'Client मोड में जाने पर बच्चे के कमरे की स्ट्रीम और स्थानीय सेवाएँ बंद हो जाएँगी।',
    'es':
        'Si cambias al modo Client, la transmisión de la habitación y los servicios locales se detendrán.',
    'fr':
        'Si vous passez en mode Client, le flux de la chambre et les services locaux seront arrêtés.',
  },
  'cancel': {
    'tr': 'Vazgeç',
    'en': 'Cancel',
    'zh': '取消',
    'hi': 'रद्द करें',
    'es': 'Cancelar',
    'fr': 'Annuler'
  },
  'switchToClient': {
    'tr': 'Client’a geç',
    'en': 'Switch to Client',
    'zh': '切换到 Client',
    'hi': 'Client पर जाएँ',
    'es': 'Cambiar a Client',
    'fr': 'Passer à Client'
  },
  'roleSelectionTitle': {
    'tr': 'Bu cihaz ne olacak?',
    'en': 'What will this device be?',
    'zh': '这台设备要做什么？',
    'hi': 'यह डिवाइस क्या बनेगा?',
    'es': '¿Qué será este dispositivo?',
    'fr': 'Quel sera le rôle de cet appareil ?',
  },
  'roleSelectionSubtitle': {
    'tr':
        'Bu cihaz genelde bir kez seçilir; değişim ayarlarda küçük bir rozet olarak kalır.',
    'en':
        'This is usually chosen once; role switching stays as a small badge in settings.',
    'zh': '通常只需选择一次；角色切换会作为一个小徽章保留在设置中。',
    'hi':
        'आमतौर पर यह एक बार चुना जाता है; बदलाव सेटिंग में छोटे बैज की तरह रहता है।',
    'es':
        'Normalmente se elige una vez; el cambio queda como una pequeña insignia en ajustes.',
    'fr':
        'Ce choix se fait généralement une seule fois ; le changement reste dans un petit badge des réglages.',
  },
  'babyRoomDeviceTitle': {
    'tr': 'Bebek Odası Cihazı',
    'en': 'Baby Room Device',
    'zh': '婴儿房设备',
    'hi': 'बच्चे के कमरे का डिवाइस',
    'es': 'Dispositivo de la habitación',
    'fr': 'Appareil chambre bébé'
  },
  'babyRoomDeviceDescription': {
    'tr':
        'Kamera ve mikrofon bu telefonda açılır. Yayın QR kod ile paylaşılır.',
    'en':
        'Camera and microphone run on this phone. The stream is shared with a QR code.',
    'zh': '摄像头和麦克风会在这部手机上运行。直播通过二维码分享。',
    'hi':
        'कैमरा और माइक्रोफ़ोन इसी फ़ोन पर चलेंगे। स्ट्रीम QR कोड से साझा होगी।',
    'es':
        'La cámara y el micrófono se abren en este teléfono. La transmisión se comparte con QR.',
    'fr':
        'La caméra et le micro tournent sur ce téléphone. Le flux se partage avec un QR code.',
  },
  'recommended': {
    'tr': 'Önerilen',
    'en': 'Recommended',
    'zh': '推荐',
    'hi': 'अनुशंसित',
    'es': 'Recomendado',
    'fr': 'Recommandé'
  },
  'parentDeviceTitle': {
    'tr': 'Ebeveyn Cihazı',
    'en': 'Parent Device',
    'zh': '家长设备',
    'hi': 'माता-पिता का डिवाइस',
    'es': 'Dispositivo del padre/madre',
    'fr': 'Appareil parent'
  },
  'parentDeviceDescription': {
    'tr':
        'Aynı Wi-Fi içinde server bulunur, canlı yayın izlenir ve uyarılar bildirim olur.',
    'en':
        'The server is found on the same Wi‑Fi, live video is watched, and alerts become notifications.',
    'zh': '在同一 Wi‑Fi 中找到 server，可观看直播，提醒会变成通知。',
    'hi':
        'उसी Wi‑Fi में server मिलता है, लाइव स्ट्रीम देखी जाती है और अलर्ट सूचना बनते हैं।',
    'es':
        'Encuentra el server en el mismo Wi‑Fi, mira el directo y recibe las alertas como notificaciones.',
    'fr':
        'Trouve le server sur le même Wi‑Fi, regarde le direct et reçoit les alertes en notifications.',
  },
  'viewer': {
    'tr': 'İzleyici',
    'en': 'Viewer',
    'zh': '观看端',
    'hi': 'दर्शक',
    'es': 'Visor',
    'fr': 'Visionneur'
  },
  'setupPermissionsTitle': {
    'tr': 'İlk kurulum izinleri',
    'en': 'First setup permissions',
    'zh': '首次设置权限',
    'hi': 'पहली सेटअप अनुमतियाँ',
    'es': 'Permisos de configuración inicial',
    'fr': 'Autorisations de première configuration'
  },
  'setupPermissionsText': {
    'tr':
        'Seçimden sonra gerekli kamera, mikrofon, bildirim ve pil/arka plan izinleri istenir.',
    'en':
        'After selection, required camera, microphone, notification, and battery/background permissions are requested.',
    'zh': '选择后会请求必要的摄像头、麦克风、通知以及电池/后台权限。',
    'hi':
        'चयन के बाद कैमरा, माइक्रोफ़ोन, सूचना और बैटरी/बैकग्राउंड अनुमतियाँ माँगी जाती हैं।',
    'es':
        'Después de elegir, se piden permisos de cámara, micrófono, notificaciones y batería/segundo plano.',
    'fr':
        'Après le choix, les autorisations caméra, micro, notifications et batterie/arrière-plan sont demandées.',
  },
  'securityNoteTitle': {
    'tr': 'Güvenlik notu',
    'en': 'Security note',
    'zh': '安全说明',
    'hi': 'सुरक्षा नोट',
    'es': 'Nota de seguridad',
    'fr': 'Note de sécurité'
  },
  'securityNoteText': {
    'tr': 'Bu uygulama aynı Wi-Fi/LAN içinde kullanım için tasarlandı.',
    'en': 'This app is designed for use on the same Wi‑Fi/LAN.',
    'zh': '此应用设计用于同一 Wi‑Fi/LAN 内。',
    'hi': 'यह ऐप उसी Wi‑Fi/LAN में उपयोग के लिए बनाया गया है।',
    'es': 'Esta app está diseñada para usarse en la misma Wi‑Fi/LAN.',
    'fr': 'Cette app est conçue pour le même Wi‑Fi/LAN.'
  },
  'changeRole': {
    'tr': 'Rol değiştir',
    'en': 'Change role',
    'zh': '切换角色',
    'hi': 'भूमिका बदलें',
    'es': 'Cambiar rol',
    'fr': 'Changer de rôle'
  },
  'clientRoleTitle': {
    'tr': 'CLIENT',
    'en': 'CLIENT',
    'zh': 'CLIENT',
    'hi': 'CLIENT',
    'es': 'CLIENT',
    'fr': 'CLIENT'
  },
  'serverRoleTitle': {
    'tr': 'SERVER',
    'en': 'SERVER',
    'zh': 'SERVER',
    'hi': 'SERVER',
    'es': 'SERVER',
    'fr': 'SERVER'
  },
  'parentRoleSubtitle': {
    'tr': 'EBEVEYN',
    'en': 'PARENT',
    'zh': '家长',
    'hi': 'अभिभावक',
    'es': 'PADRE/MADRE',
    'fr': 'PARENT'
  },
  'babyRoomRoleSubtitle': {
    'tr': 'BEBEK ODASI',
    'en': 'BABY ROOM',
    'zh': '婴儿房',
    'hi': 'बच्चे का कमरा',
    'es': 'HABITACIÓN',
    'fr': 'CHAMBRE BÉBÉ'
  },
  'roleBadgeTooltip': {
    'tr': '{title} rolü aktif. Değiştirmek için dokun.',
    'en': '{title} role is active. Tap to change.',
    'zh': '{title} 角色已启用。点按即可切换。',
    'hi': '{title} भूमिका सक्रिय है। बदलने के लिए टैप करें।',
    'es': 'El rol {title} está activo. Toca para cambiar.',
    'fr': 'Le rôle {title} est actif. Touchez pour changer.'
  },
  'navWatch': {
    'tr': 'İzle',
    'en': 'Watch',
    'zh': '观看',
    'hi': 'देखें',
    'es': 'Ver',
    'fr': 'Voir'
  },
  'navFind': {
    'tr': 'Bul',
    'en': 'Find',
    'zh': '查找',
    'hi': 'ढूँढें',
    'es': 'Buscar',
    'fr': 'Trouver'
  },
  'navNotifications': {
    'tr': 'Bildirim',
    'en': 'Alerts',
    'zh': '通知',
    'hi': 'सूचनाएँ',
    'es': 'Alertas',
    'fr': 'Alertes'
  },
  'navHistory': {
    'tr': 'Geçmiş',
    'en': 'History',
    'zh': '历史',
    'hi': 'इतिहास',
    'es': 'Historial',
    'fr': 'Historique'
  },
  'navSettings': {
    'tr': 'Ayarlar',
    'en': 'Settings',
    'zh': '设置',
    'hi': 'सेटिंग्स',
    'es': 'Ajustes',
    'fr': 'Réglages'
  },
  'navStream': {
    'tr': 'Yayın',
    'en': 'Stream',
    'zh': '直播',
    'hi': 'स्ट्रीम',
    'es': 'Directo',
    'fr': 'Flux'
  },
  'navQrIp': {
    'tr': 'QR/IP',
    'en': 'QR/IP',
    'zh': 'QR/IP',
    'hi': 'QR/IP',
    'es': 'QR/IP',
    'fr': 'QR/IP'
  },
  'navService': {
    'tr': 'Servis',
    'en': 'Service',
    'zh': '服务',
    'hi': 'सेवा',
    'es': 'Servicio',
    'fr': 'Service'
  },
  'parentMode': {
    'tr': 'Ebeveyn modu',
    'en': 'Parent mode',
    'zh': '家长模式',
    'hi': 'अभिभावक मोड',
    'es': 'Modo padre/madre',
    'fr': 'Mode parent'
  },
  'clientTitleUnpaired': {
    'tr': 'Odayı bulalım',
    'en': 'Let’s find the room',
    'zh': '一起找到房间',
    'hi': 'कमरा ढूँढते हैं',
    'es': 'Busquemos la habitación',
    'fr': 'Trouvons la chambre'
  },
  'clientTitleScanningQr': {
    'tr': 'QR kodu tarat',
    'en': 'Scan the QR code',
    'zh': '扫描二维码',
    'hi': 'QR कोड स्कैन करें',
    'es': 'Escanea el QR',
    'fr': 'Scannez le QR'
  },
  'clientTitlePairing': {
    'tr': 'Güvenli eşleşiyor',
    'en': 'Pairing securely',
    'zh': '正在安全配对',
    'hi': 'सुरक्षित पेयरिंग हो रही है',
    'es': 'Emparejando de forma segura',
    'fr': 'Appairage sécurisé'
  },
  'clientTitlePairedIdle': {
    'tr': 'Bebek odası hazır',
    'en': 'Baby room is ready',
    'zh': '婴儿房已就绪',
    'hi': 'बच्चे का कमरा तैयार है',
    'es': 'Habitación lista',
    'fr': 'Chambre bébé prête'
  },
  'clientTitleRenewingToken': {
    'tr': 'Oturum yenileniyor',
    'en': 'Renewing session',
    'zh': '正在刷新会话',
    'hi': 'सत्र नवीनीकृत हो रहा है',
    'es': 'Renovando sesión',
    'fr': 'Renouvellement de session'
  },
  'clientTitleWatching': {
    'tr': 'Canlı izleme açık',
    'en': 'Live watch is on',
    'zh': '实时观看已开启',
    'hi': 'लाइव देखना चालू है',
    'es': 'Vista en directo activa',
    'fr': 'Visionnage en direct actif'
  },
  'clientTitleAlertOnly': {
    'tr': 'Uyarılar takipte',
    'en': 'Alerts are being watched',
    'zh': '提醒监控中',
    'hi': 'अलर्ट देखे जा रहे हैं',
    'es': 'Alertas en seguimiento',
    'fr': 'Alertes surveillées'
  },
  'clientTitleReconnecting': {
    'tr': 'Yeniden bağlanıyor',
    'en': 'Reconnecting',
    'zh': '正在重新连接',
    'hi': 'फिर से जुड़ रहा है',
    'es': 'Reconectando',
    'fr': 'Reconnexion'
  },
  'clientTitleOffline': {
    'tr': 'Oda çevrim dışı',
    'en': 'Room is offline',
    'zh': '房间离线',
    'hi': 'कमरा ऑफ़लाइन है',
    'es': 'Habitación sin conexión',
    'fr': 'Chambre hors ligne'
  },
  'clientTitleRevoked': {
    'tr': 'Eşleşme iptal edildi',
    'en': 'Pairing was revoked',
    'zh': '配对已撤销',
    'hi': 'पेयरिंग रद्द हो गई',
    'es': 'Emparejamiento revocado',
    'fr': 'Appairage révoqué'
  },
  'clientTitleError': {
    'tr': 'Bağlantıyı toparlayalım',
    'en': 'Let’s fix the connection',
    'zh': '让我们修复连接',
    'hi': 'कनेक्शन ठीक करें',
    'es': 'Arreglemos la conexión',
    'fr': 'Réparons la connexion'
  },
  'clientSubtitleDefault': {
    'tr':
        'MimiCam yakındaki bebek odası cihazını sakin ve güvenli şekilde arar.',
    'en': 'MimiCam calmly and securely looks for the nearby baby room device.',
    'zh': 'MimiCam 会安静安全地查找附近的婴儿房设备。',
    'hi':
        'MimiCam पास के बच्चे के कमरे के डिवाइस को शांत और सुरक्षित रूप से ढूँढता है।',
    'es':
        'MimiCam busca con calma y seguridad el dispositivo cercano de la habitación.',
    'fr':
        'MimiCam cherche calmement et sûrement l’appareil proche de la chambre.'
  },
  'clientSubtitleError': {
    'tr': 'Ağ bağlantısını kontrol et; QR veya IP ile yeniden deneyebilirsin.',
    'en': 'Check the network connection; you can try again with QR or IP.',
    'zh': '请检查网络连接；可以用二维码或 IP 重试。',
    'hi': 'नेटवर्क जाँचें; QR या IP से फिर कोशिश कर सकते हैं।',
    'es': 'Revisa la red; puedes intentarlo otra vez con QR o IP.',
    'fr': 'Vérifiez le réseau ; vous pouvez réessayer avec QR ou IP.'
  },
  'clientSubtitleOffline': {
    'tr': 'Bebek odası cihazı aynı ağda görünmüyor. Yakında tekrar arayacağız.',
    'en':
        'The baby room device is not visible on the same network. We will try again soon.',
    'zh': '同一网络中看不到婴儿房设备。我们很快会重试。',
    'hi':
        'बच्चे के कमरे का डिवाइस उसी नेटवर्क पर नहीं दिख रहा। हम जल्द फिर कोशिश करेंगे।',
    'es':
        'El dispositivo de la habitación no aparece en la misma red. Reintentaremos pronto.',
    'fr':
        'L’appareil de la chambre n’est pas visible sur le même réseau. Nouvel essai bientôt.'
  },
  'clientSubtitleWatching': {
    'tr': 'Canlı yayın ve son uyarılar izleme ekranında hazır.',
    'en': 'Live video and recent alerts are ready on the watch screen.',
    'zh': '直播和最新提醒已在观看屏幕准备好。',
    'hi': 'लाइव वीडियो और हाल के अलर्ट देखने की स्क्रीन पर तैयार हैं।',
    'es':
        'El directo y las alertas recientes están listos en la pantalla de vista.',
    'fr':
        'Le direct et les alertes récentes sont prêts sur l’écran de visionnage.'
  },
  'sameWifi': {
    'tr': 'Aynı Wi‑Fi',
    'en': 'Same Wi‑Fi',
    'zh': '同一 Wi‑Fi',
    'hi': 'वही Wi‑Fi',
    'es': 'Misma Wi‑Fi',
    'fr': 'Même Wi‑Fi'
  },
  'qrReady': {
    'tr': 'QR hazır',
    'en': 'QR ready',
    'zh': 'QR 已就绪',
    'hi': 'QR तैयार',
    'es': 'QR listo',
    'fr': 'QR prêt'
  },
  'alertsShort': {
    'tr': 'Uyarılar',
    'en': 'Alerts',
    'zh': '提醒',
    'hi': 'अलर्ट',
    'es': 'Alertas',
    'fr': 'Alertes'
  },
  'parentPriority': {
    'tr': 'ANNE İÇİN ÖNCELİK',
    'en': 'PARENT PRIORITY',
    'zh': '家长优先',
    'hi': 'अभिभावक प्राथमिकता',
    'es': 'PRIORIDAD PARA PADRES',
    'fr': 'PRIORITÉ PARENT'
  },
  'latestStatusTracked': {
    'tr': 'Son durum takipte',
    'en': 'Latest status is tracked',
    'zh': '正在跟踪最新状态',
    'hi': 'नवीनतम स्थिति देखी जा रही है',
    'es': 'Último estado en seguimiento',
    'fr': 'Dernier état suivi'
  },
  'pairRoomForNotifications': {
    'tr': 'Bildirim için oda eşleştir',
    'en': 'Pair a room for alerts',
    'zh': '配对房间以接收提醒',
    'hi': 'अलर्ट के लिए कमरा पेयर करें',
    'es': 'Empareja una habitación para alertas',
    'fr': 'Appairez une chambre pour les alertes'
  },
  'latestStatusTrackedText': {
    'tr': 'Ağlama, hareket ve bağlantı uyarıları bu anne ekranında öne çıkar.',
    'en':
        'Cry, motion, and connection alerts are highlighted on this parent screen.',
    'zh': '哭声、活动和连接提醒会在家长屏幕突出显示。',
    'hi':
        'रोना, गतिविधि और कनेक्शन अलर्ट इस अभिभावक स्क्रीन पर प्रमुख दिखते हैं।',
    'es':
        'Las alertas de llanto, movimiento y conexión destacan en esta pantalla de padres.',
    'fr':
        'Les alertes de pleurs, mouvement et connexion sont mises en avant sur cet écran parent.'
  },
  'pairRoomForNotificationsText': {
    'tr': 'QR veya IP ile eşleşince bebeğin son durumu burada görünür.',
    'en': 'After pairing with QR or IP, the baby’s latest status appears here.',
    'zh': '通过二维码或 IP 配对后，宝宝最新状态会显示在这里。',
    'hi': 'QR या IP से पेयर होने पर बच्चे की नवीनतम स्थिति यहाँ दिखेगी।',
    'es': 'Al emparejar con QR o IP, el último estado del bebé aparece aquí.',
    'fr': 'Après appairage par QR ou IP, le dernier état du bébé apparaît ici.'
  },
  'openNotifications': {
    'tr': 'Bildirimleri aç',
    'en': 'Open alerts',
    'zh': '打开提醒',
    'hi': 'अलर्ट खोलें',
    'es': 'Abrir alertas',
    'fr': 'Ouvrir les alertes'
  },
  'pairRoom': {
    'tr': 'Odayı eşleştir',
    'en': 'Pair room',
    'zh': '配对房间',
    'hi': 'कमरा पेयर करें',
    'es': 'Emparejar habitación',
    'fr': 'Appairer la chambre'
  },
  'live': {
    'tr': 'Canlı',
    'en': 'Live',
    'zh': '实时',
    'hi': 'लाइव',
    'es': 'Directo',
    'fr': 'Direct'
  },
  'chooseRoomFirst': {
    'tr': 'Önce oda seç',
    'en': 'Choose a room first',
    'zh': '请先选择房间',
    'hi': 'पहले कमरा चुनें',
    'es': 'Elige primero una habitación',
    'fr': 'Choisissez d’abord une chambre'
  },
  'clientWatchOnlyPairedStream': {
    'tr': 'Client izleme ekranı sadece eşleşmiş server yayınını gösterir.',
    'en': 'The Client watch screen only shows the paired Server stream.',
    'zh': 'Client 观看屏幕只显示已配对 Server 的直播。',
    'hi': 'Client देखने की स्क्रीन केवल पेयर Server की स्ट्रीम दिखाती है।',
    'es': 'La pantalla Client solo muestra el directo del Server emparejado.',
    'fr': 'L’écran Client montre uniquement le flux du Server appairé.'
  },
  'liveAndAlertsParentText': {
    'tr': 'Canlı yayın ve son uyarılar ebeveyn cihazında takip edilir.',
    'en': 'Live stream and recent alerts are followed on the parent device.',
    'zh': '直播和最新提醒会在家长设备上查看。',
    'hi': 'लाइव स्ट्रीम और हाल के अलर्ट अभिभावक डिवाइस पर देखे जाते हैं।',
    'es':
        'El directo y las alertas recientes se siguen en el dispositivo padre/madre.',
    'fr': 'Le direct et les alertes récentes sont suivis sur l’appareil parent.'
  },
  'pairedWithQr': {
    'tr': 'QR ile eşleşti',
    'en': 'Paired with QR',
    'zh': '已通过二维码配对',
    'hi': 'QR से पेयर हुआ',
    'es': 'Emparejado con QR',
    'fr': 'Appairé par QR'
  },
  'pairedDevice': {
    'tr': 'Eşleşmiş cihaz',
    'en': 'Paired device',
    'zh': '已配对设备',
    'hi': 'पेयर डिवाइस',
    'es': 'Dispositivo emparejado',
    'fr': 'Appareil appairé'
  },
  'qrWaiting': {
    'tr': 'QR bekleniyor',
    'en': 'Waiting for QR',
    'zh': '等待二维码',
    'hi': 'QR की प्रतीक्षा',
    'es': 'Esperando QR',
    'fr': 'En attente du QR'
  },
  'onlyScannedServerConnects': {
    'tr': 'Kendi kendine oda göstermeyecek; sadece taranan server bağlanır.',
    'en': 'It will not invent a room; only the scanned server will connect.',
    'zh': '不会自动虚构房间；只会连接已扫描的 server。',
    'hi': 'यह अपने-आप कमरा नहीं दिखाएगा; केवल स्कैन किया server जुड़ेगा।',
    'es':
        'No mostrará una habitación inventada; solo conecta el server escaneado.',
    'fr': 'Aucune chambre fictive ; seul le server scanné se connecte.'
  },
  'liveWatchDashboard': {
    'tr': 'Canlı izleme dashboard',
    'en': 'Live watch dashboard',
    'zh': '实时观看面板',
    'hi': 'लाइव देखने का डैशबोर्ड',
    'es': 'Panel de vista en directo',
    'fr': 'Tableau de bord du direct'
  },
  'liveWatchSummary': {
    'tr': 'Video, WS durumu ve son uyarılar bu ebeveyn alanında açılır.',
    'en': 'Video, WS status, and recent alerts open in this parent area.',
    'zh': '视频、WS 状态和最新提醒会在这个家长区域打开。',
    'hi': 'वीडियो, WS स्थिति और हाल के अलर्ट इस अभिभावक क्षेत्र में खुलते हैं।',
    'es':
        'Vídeo, estado WS y alertas recientes se abren en esta zona de padres.',
    'fr': 'Vidéo, état WS et alertes récentes s’ouvrent dans cette zone parent.'
  },
  'openLiveWatch': {
    'tr': 'Canlı izlemeyi aç',
    'en': 'Open live watch',
    'zh': '打开实时观看',
    'hi': 'लाइव देखना खोलें',
    'es': 'Abrir directo',
    'fr': 'Ouvrir le direct'
  },
  'connectBabyRoom': {
    'tr': 'Bebek odasına bağlan',
    'en': 'Connect to baby room',
    'zh': '连接婴儿房',
    'hi': 'बच्चे के कमरे से जुड़ें',
    'es': 'Conectar con la habitación',
    'fr': 'Se connecter à la chambre'
  },
  'connectBabyRoomSubtitle': {
    'tr': 'Oda cihazını QR ile eşleştir; gerekirse IP adresini elle gir.',
    'en': 'Pair the room device with QR; enter the IP manually if needed.',
    'zh': '用二维码配对房间设备；必要时手动输入 IP。',
    'hi': 'कमरे के डिवाइस को QR से पेयर करें; ज़रूरत हो तो IP हाथ से लिखें।',
    'es': 'Empareja con QR; si hace falta, escribe la IP manualmente.',
    'fr': 'Appairez avec QR ; saisissez l’IP manuellement si besoin.'
  },
  'fastestWay': {
    'tr': 'En hızlı yol',
    'en': 'Fastest way',
    'zh': '最快方式',
    'hi': 'सबसे तेज़ तरीका',
    'es': 'La vía más rápida',
    'fr': 'Le plus rapide'
  },
  'manualConnect': {
    'tr': 'Elle bağlan',
    'en': 'Connect manually',
    'zh': '手动连接',
    'hi': 'मैन्युअल जुड़ें',
    'es': 'Conexión manual',
    'fr': 'Connexion manuelle'
  },
  'connectionWays': {
    'tr': 'Bağlantı yolları',
    'en': 'Connection options',
    'zh': '连接方式',
    'hi': 'कनेक्शन विकल्प',
    'es': 'Opciones de conexión',
    'fr': 'Options de connexion'
  },
  'scanQrSecurely': {
    'tr': 'QR tarayarak güvenli eşleş; gerekirse IP:port yazarak bağlan.',
    'en': 'Scan QR for secure pairing; use IP:port if needed.',
    'zh': '扫描二维码安全配对；必要时输入 IP:port。',
    'hi': 'सुरक्षित पेयरिंग के लिए QR स्कैन करें; ज़रूरत हो तो IP:port लिखें।',
    'es': 'Escanea QR para emparejar; usa IP:puerto si hace falta.',
    'fr': 'Scannez le QR pour appairer ; utilisez IP:port si besoin.'
  },
  'scanQr': {
    'tr': 'QR Tara',
    'en': 'Scan QR',
    'zh': '扫描二维码',
    'hi': 'QR स्कैन करें',
    'es': 'Escanear QR',
    'fr': 'Scanner QR'
  },
  'ipOrHostPort': {
    'tr': 'IP veya IP:port',
    'en': 'IP or IP:port',
    'zh': 'IP 或 IP:port',
    'hi': 'IP या IP:port',
    'es': 'IP o IP:puerto',
    'fr': 'IP ou IP:port'
  },
  'connectWithIp': {
    'tr': 'IP ile bağlan',
    'en': 'Connect with IP',
    'zh': '用 IP 连接',
    'hi': 'IP से जुड़ें',
    'es': 'Conectar con IP',
    'fr': 'Connexion par IP'
  },
  'invalidQrCode': {
    'tr': 'Geçersiz veya süresi dolmuş MimiCam QR kodu.',
    'en': 'Invalid or expired MimiCam QR code.',
    'zh': 'MimiCam 二维码无效或已过期。',
    'hi': 'MimiCam QR कोड अमान्य या समाप्त है।',
    'es': 'Código QR MimiCam no válido o caducado.',
    'fr': 'QR code MimiCam invalide ou expiré.'
  },
  'pairedMessage': {
    'tr': '{name} eşleşti.',
    'en': '{name} paired.',
    'zh': '{name} 已配对。',
    'hi': '{name} पेयर हो गया।',
    'es': '{name} emparejado.',
    'fr': '{name} appairé.'
  },
  'pairingFailed': {
    'tr': 'Eşleşme kurulamadı: {error}',
    'en': 'Pairing failed: {error}',
    'zh': '配对失败：{error}',
    'hi': 'पेयरिंग विफल: {error}',
    'es': 'No se pudo emparejar: {error}',
    'fr': 'Échec de l’appairage : {error}'
  },
  'securityFingerprintMismatch': {
    'tr':
        'Server güvenlik parmak izi eşleşmedi. QR’ı yenileyip tekrar deneyin.',
    'en':
        'Server security fingerprint did not match. Refresh the QR and try again.',
    'zh': 'Server 安全指纹不匹配。请刷新二维码后重试。',
    'hi':
        'Server सुरक्षा फिंगरप्रिंट मेल नहीं खाया। QR को रीफ़्रेश करके फिर कोशिश करें।',
    'es':
        'La huella de seguridad del server no coincide. Actualiza el QR e inténtalo de nuevo.',
    'fr':
        'L’empreinte de sécurité du server ne correspond pas. Actualisez le QR puis réessayez.'
  },
  'invalidIpFormat': {
    'tr': 'IP formatı geçersiz. Örnek: 192.168.1.20:8080',
    'en': 'Invalid IP format. Example: 192.168.1.20:8080',
    'zh': 'IP 格式无效。示例：192.168.1.20:8080',
    'hi': 'IP प्रारूप अमान्य है। उदाहरण: 192.168.1.20:8080',
    'es': 'Formato IP no válido. Ejemplo: 192.168.1.20:8080',
    'fr': 'Format IP invalide. Exemple : 192.168.1.20:8080'
  },
  'manualPairingFailed': {
    'tr': 'IP ile eşleşme kurulamadı: {error}',
    'en': 'IP pairing failed: {error}',
    'zh': 'IP 配对失败：{error}',
    'hi': 'IP पेयरिंग विफल: {error}',
    'es': 'No se pudo emparejar por IP: {error}',
    'fr': 'Échec de l’appairage par IP : {error}'
  },
  'serverNotFound': {
    'tr': 'Server bulunamadı: {code}',
    'en': 'Server not found: {code}',
    'zh': '未找到 Server：{code}',
    'hi': 'Server नहीं मिला: {code}',
    'es': 'Server no encontrado: {code}',
    'fr': 'Server introuvable : {code}'
  },
  'invalidServerResponse': {
    'tr': 'Geçersiz server yanıtı',
    'en': 'Invalid server response',
    'zh': 'Server 响应无效',
    'hi': 'Server प्रतिक्रिया अमान्य है',
    'es': 'Respuesta del server no válida',
    'fr': 'Réponse server invalide'
  },
  'missingPairingNonce': {
    'tr': 'Server pairing nonce üretmedi',
    'en': 'Server did not create a pairing nonce',
    'zh': 'Server 未生成配对 nonce',
    'hi': 'Server ने pairing nonce नहीं बनाया',
    'es': 'El server no creó nonce de emparejamiento',
    'fr': 'Le server n’a pas créé de nonce d’appairage'
  },
  'scanServerQrFirst': {
    'tr': 'Önce server QR kodunu tara.',
    'en': 'Scan the Server QR code first.',
    'zh': '请先扫描 Server 二维码。',
    'hi': 'पहले Server QR कोड स्कैन करें।',
    'es': 'Escanea primero el QR del Server.',
    'fr': 'Scannez d’abord le QR du Server.'
  },
  'latestStatusAndNotifications': {
    'tr': 'Son durum ve bildirimler',
    'en': 'Latest status and alerts',
    'zh': '最新状态和提醒',
    'hi': 'नवीनतम स्थिति और अलर्ट',
    'es': 'Último estado y alertas',
    'fr': 'Dernier état et alertes'
  },
  'parentEventsPriorityText': {
    'tr': 'Ağlama, hareket ve sistem olayları anne ekranında öne çıkar.',
    'en': 'Cry, motion, and system events stand out on the parent screen.',
    'zh': '哭声、活动和系统事件会在家长屏幕突出显示。',
    'hi': 'रोना, गतिविधि और सिस्टम घटनाएँ अभिभावक स्क्रीन पर प्रमुख दिखती हैं।',
    'es':
        'Llanto, movimiento y eventos del sistema destacan en la pantalla de padres.',
    'fr':
        'Pleurs, mouvement et événements système ressortent sur l’écran parent.'
  },
  'waitingLatestStatus': {
    'tr': 'Son durum bekleniyor',
    'en': 'Waiting for latest status',
    'zh': '等待最新状态',
    'hi': 'नवीनतम स्थिति की प्रतीक्षा',
    'es': 'Esperando último estado',
    'fr': 'En attente du dernier état'
  },
  'pairedServerAlertAppears': {
    'tr':
        'Eşleşmiş server uyarı gönderdiğinde en önemli durum burada görünecek.',
    'en':
        'When the paired Server sends an alert, the most important status appears here.',
    'zh': '已配对 Server 发送提醒时，最重要的状态会显示在这里。',
    'hi': 'पेयर Server अलर्ट भेजेगा तो सबसे महत्वपूर्ण स्थिति यहाँ दिखेगी।',
    'es':
        'Cuando el Server emparejado envíe una alerta, el estado más importante aparecerá aquí.',
    'fr':
        'Quand le Server appairé enverra une alerte, l’état le plus important apparaîtra ici.'
  },
  'parentDevicePreferences': {
    'tr': 'Ebeveyn cihazı tercihleri',
    'en': 'Parent device preferences',
    'zh': '家长设备偏好',
    'hi': 'अभिभावक डिवाइस प्राथमिकताएँ',
    'es': 'Preferencias del dispositivo padre/madre',
    'fr': 'Préférences de l’appareil parent'
  },
  'noServerControlsText': {
    'tr':
        'Bildirim ve izleme davranışı burada kalır; server portu veya yayın kontrolü yoktur.',
    'en':
        'Notification and watch behavior stays here; there are no server port or stream controls.',
    'zh': '通知和观看行为在这里设置；没有 server 端口或直播控制。',
    'hi':
        'सूचना और देखने का व्यवहार यहाँ रहता है; server पोर्ट या स्ट्रीम नियंत्रण नहीं हैं।',
    'es':
        'Aquí quedan notificaciones y vista; no hay puerto server ni control del directo.',
    'fr':
        'Notifications et visionnage restent ici ; pas de port server ni contrôle de flux.'
  },
  'clientSettings': {
    'tr': 'Client ayarları',
    'en': 'Client settings',
    'zh': 'Client 设置',
    'hi': 'Client सेटिंग्स',
    'es': 'Ajustes Client',
    'fr': 'Réglages Client'
  },
  'clientSettingsPlaceholder': {
    'tr': 'Yerel bildirim, reconnect ve viewer tercihleri burada yönetilecek.',
    'en':
        'Local notifications, reconnect, and viewer preferences will be managed here.',
    'zh': '本地通知、重新连接和观看端偏好将在这里管理。',
    'hi':
        'स्थानीय सूचनाएँ, reconnect और viewer प्राथमिकताएँ यहाँ प्रबंधित होंगी।',
    'es':
        'Notificaciones locales, reconexión y preferencias del visor se gestionarán aquí.',
    'fr':
        'Notifications locales, reconnexion et préférences de visionnage seront gérées ici.'
  },
  'liveWatching': {
    'tr': 'Canlı izleme',
    'en': 'Live watch',
    'zh': '实时观看',
    'hi': 'लाइव देखना',
    'es': 'Vista en directo',
    'fr': 'Visionnage en direct'
  },
  'liveStreamConnectedSubtitle': {
    'tr': 'Bebek odası yayını bağlı. Son olaylar altta görünür.',
    'en': 'Baby room stream is connected. Recent events appear below.',
    'zh': '婴儿房直播已连接。最新事件显示在下方。',
    'hi': 'बच्चे के कमरे की स्ट्रीम जुड़ी है। हाल की घटनाएँ नीचे दिखती हैं।',
    'es':
        'El directo de la habitación está conectado. Los eventos recientes aparecen abajo.',
    'fr':
        'Le flux de la chambre est connecté. Les événements récents apparaissent dessous.'
  },
  'connected': {
    'tr': 'Bağlı',
    'en': 'Connected',
    'zh': '已连接',
    'hi': 'जुड़ा',
    'es': 'Conectado',
    'fr': 'Connecté'
  },
  'lastAlert': {
    'tr': 'Son uyarı',
    'en': 'Last alert',
    'zh': '最新提醒',
    'hi': 'आखिरी अलर्ट',
    'es': 'Última alerta',
    'fr': 'Dernière alerte'
  },
  'cryingDetectedAt': {
    'tr': 'Ağlama algılandı · 09:38',
    'en': 'Cry detected · 09:38',
    'zh': '检测到哭声 · 09:38',
    'hi': 'रोना मिला · 09:38',
    'es': 'Llanto detectado · 09:38',
    'fr': 'Pleurs détectés · 09:38'
  },
  'motionCalmScore': {
    'tr': 'Sakin · skor %08',
    'en': 'Calm · score 08%',
    'zh': '安静 · 评分 08%',
    'hi': 'शांत · स्कोर 08%',
    'es': 'Calma · puntuación 08%',
    'fr': 'Calme · score 08 %'
  },
  'localNotificationOn': {
    'tr': 'Yerel bildirim açık',
    'en': 'Local notifications on',
    'zh': '本地通知已开启',
    'hi': 'स्थानीय सूचनाएँ चालू',
    'es': 'Notificaciones locales activas',
    'fr': 'Notifications locales activées'
  },
  'quickActions': {
    'tr': 'Hızlı işlemler',
    'en': 'Quick actions',
    'zh': '快捷操作',
    'hi': 'त्वरित क्रियाएँ',
    'es': 'Acciones rápidas',
    'fr': 'Actions rapides'
  },
  'reconnect': {
    'tr': 'Yeniden bağlan',
    'en': 'Reconnect',
    'zh': '重新连接',
    'hi': 'फिर जुड़ें',
    'es': 'Reconectar',
    'fr': 'Reconnecter'
  },
  'changeAddress': {
    'tr': 'Adresi değiştir',
    'en': 'Change address',
    'zh': '更改地址',
    'hi': 'पता बदलें',
    'es': 'Cambiar dirección',
    'fr': 'Changer l’adresse'
  },
  'openHistory': {
    'tr': 'Geçmişi aç',
    'en': 'Open history',
    'zh': '打开历史',
    'hi': 'इतिहास खोलें',
    'es': 'Abrir historial',
    'fr': 'Ouvrir l’historique'
  },
  'alertHistory': {
    'tr': 'Uyarı geçmişi',
    'en': 'Alert history',
    'zh': '提醒历史',
    'hi': 'अलर्ट इतिहास',
    'es': 'Historial de alertas',
    'fr': 'Historique des alertes'
  },
  'alertHistorySubtitle': {
    'tr': 'Ağlama, hareket ve sistem olaylarını zaman çizgisi olarak takip et.',
    'en': 'Follow cry, motion, and system events as a timeline.',
    'zh': '以时间线查看哭声、活动和系统事件。',
    'hi': 'रोना, गतिविधि और सिस्टम घटनाओं को टाइमलाइन में देखें।',
    'es': 'Sigue llanto, movimiento y sistema como línea de tiempo.',
    'fr': 'Suivez pleurs, mouvement et système sur une timeline.'
  },
  'all': {
    'tr': 'Tümü',
    'en': 'All',
    'zh': '全部',
    'hi': 'सभी',
    'es': 'Todo',
    'fr': 'Tout'
  },
  'audio': {
    'tr': 'Ses',
    'en': 'Audio',
    'zh': '声音',
    'hi': 'ऑडियो',
    'es': 'Audio',
    'fr': 'Audio'
  },
  'motion': {
    'tr': 'Hareket',
    'en': 'Motion',
    'zh': '活动',
    'hi': 'गतिविधि',
    'es': 'Movimiento',
    'fr': 'Mouvement'
  },
  'system': {
    'tr': 'Sistem',
    'en': 'System',
    'zh': '系统',
    'hi': 'सिस्टम',
    'es': 'Sistema',
    'fr': 'Système'
  },
  'dailySummary': {
    'tr': 'Günlük özeti',
    'en': 'Daily summary',
    'zh': '每日摘要',
    'hi': 'दैनिक सारांश',
    'es': 'Resumen diario',
    'fr': 'Résumé du jour'
  },
  'todayEventSummary': {
    'tr': 'Bugün 2 ses, 1 hareket, 2 sistem olayı var.',
    'en': 'Today there are 2 audio, 1 motion, and 2 system events.',
    'zh': '今天有 2 个声音、1 个活动和 2 个系统事件。',
    'hi': 'आज 2 ऑडियो, 1 गतिविधि और 2 सिस्टम घटनाएँ हैं।',
    'es': 'Hoy hay 2 eventos de audio, 1 de movimiento y 2 de sistema.',
    'fr': 'Aujourd’hui : 2 événements audio, 1 mouvement et 2 système.'
  },
  'watchSettingsSubtitle': {
    'tr':
        'Gürültü, hareket, bildirim ve entegrasyonları sade kontrollerle yönet.',
    'en':
        'Manage noise, motion, notifications, and integrations with simple controls.',
    'zh': '用简单控制管理噪声、活动、通知和集成。',
    'hi':
        'सरल नियंत्रणों से शोर, गतिविधि, सूचनाएँ और integrations प्रबंधित करें।',
    'es':
        'Gestiona ruido, movimiento, notificaciones e integraciones con controles simples.',
    'fr':
        'Gérez bruit, mouvement, notifications et intégrations avec des contrôles simples.'
  },
  'notificationCooldown': {
    'tr': 'Bildirim cooldown',
    'en': 'Notification cooldown',
    'zh': '通知冷却',
    'hi': 'सूचना cooldown',
    'es': 'Pausa de notificaciones',
    'fr': 'Cooldown des notifications'
  },
  'repeatedAlertsLimit': {
    'tr': 'Tekrarlayan uyarıları sınırlar.',
    'en': 'Limits repeated alerts.',
    'zh': '限制重复提醒。',
    'hi': 'दोहराए गए अलर्ट सीमित करता है।',
    'es': 'Limita alertas repetidas.',
    'fr': 'Limite les alertes répétées.'
  },
  'cryThreshold': {
    'tr': 'Ağlama eşiği',
    'en': 'Cry threshold',
    'zh': '哭声阈值',
    'hi': 'रोने की सीमा',
    'es': 'Umbral de llanto',
    'fr': 'Seuil de pleurs'
  },
  'ambientCrySensitivity': {
    'tr': 'Ortam sesine göre algılama hassasiyeti.',
    'en': 'Detection sensitivity based on ambient sound.',
    'zh': '基于环境声音的检测灵敏度。',
    'hi': 'परिवेश ध्वनि के आधार पर पहचान संवेदनशीलता।',
    'es': 'Sensibilidad según el sonido ambiente.',
    'fr': 'Sensibilité selon le son ambiant.'
  },
  'motionThreshold': {
    'tr': 'Hareket eşiği',
    'en': 'Motion threshold',
    'zh': '活动阈值',
    'hi': 'गतिविधि सीमा',
    'es': 'Umbral de movimiento',
    'fr': 'Seuil de mouvement'
  },
  'cameraMotionSensitivity': {
    'tr': 'Kamera görüntüsündeki değişim hassasiyeti.',
    'en': 'Sensitivity to changes in the camera image.',
    'zh': '摄像头画面变化灵敏度。',
    'hi': 'कैमरा चित्र में बदलाव की संवेदनशीलता।',
    'es': 'Sensibilidad a cambios en la imagen de cámara.',
    'fr': 'Sensibilité aux changements de l’image caméra.'
  },
  'integrations': {
    'tr': 'Entegrasyonlar',
    'en': 'Integrations',
    'zh': '集成',
    'hi': 'इंटीग्रेशन',
    'es': 'Integraciones',
    'fr': 'Intégrations'
  },
  'keepDeviceAwake': {
    'tr': 'Cihaz uyumasın',
    'en': 'Keep device awake',
    'zh': '保持设备唤醒',
    'hi': 'डिवाइस जागा रखें',
    'es': 'Mantener dispositivo activo',
    'fr': 'Garder l’appareil éveillé'
  },
  'enabledInServerMode': {
    'tr': 'Server modunda açık',
    'en': 'Enabled in Server mode',
    'zh': 'Server 模式已启用',
    'hi': 'Server मोड में चालू',
    'es': 'Activo en modo Server',
    'fr': 'Activé en mode Server'
  },
  'language': {
    'tr': 'Dil',
    'en': 'Language',
    'zh': '语言',
    'hi': 'भाषा',
    'es': 'Idioma',
    'fr': 'Langue'
  },
  'languageAuto': {
    'tr': 'Telefon dili / English',
    'en': 'Phone language / English',
    'zh': '手机语言 / English',
    'hi': 'फ़ोन भाषा / English',
    'es': 'Idioma del teléfono / English',
    'fr': 'Langue du téléphone / English'
  },
  'audioFirstMode': {
    'tr': 'Ses öncelikli mod',
    'en': 'Audio-first mode',
    'zh': '音频优先模式',
    'hi': 'ऑडियो-प्राथमिक मोड',
    'es': 'Modo audio primero',
    'fr': 'Mode audio prioritaire'
  },
  'connectionStable': {
    'tr': 'Bağlantı dengede',
    'en': 'Connection is stable',
    'zh': '连接稳定',
    'hi': 'कनेक्शन स्थिर है',
    'es': 'Conexión estable',
    'fr': 'Connexion stable'
  },
  'audioFirstModeText': {
    'tr':
        'Wi‑Fi zayıflayınca görüntü FPS/kalite düşer; ses ve uyarılar korunur.',
    'en':
        'When Wi‑Fi weakens, video FPS/quality drops while audio and alerts are preserved.',
    'zh': 'Wi‑Fi 变弱时会降低视频 FPS/质量，同时保留声音和提醒。',
    'hi':
        'Wi‑Fi कमज़ोर होने पर वीडियो FPS/गुणवत्ता घटती है; ऑडियो और अलर्ट सुरक्षित रहते हैं।',
    'es':
        'Si la Wi‑Fi se debilita, baja FPS/calidad de vídeo; audio y alertas se conservan.',
    'fr':
        'Si le Wi‑Fi faiblit, FPS/qualité vidéo baissent ; audio et alertes restent prioritaires.'
  },
  'autoQualityModeText': {
    'tr': 'Ağ ölçülüyor; server kaliteyi otomatik ayarlıyor.',
    'en': 'Network is measured; the Server adjusts quality automatically.',
    'zh': '正在测量网络；Server 会自动调整质量。',
    'hi': 'नेटवर्क मापा जा रहा है; Server गुणवत्ता अपने-आप समायोजित करता है।',
    'es': 'Se mide la red; el Server ajusta la calidad automáticamente.',
    'fr': 'Le réseau est mesuré ; le Server ajuste la qualité automatiquement.'
  },
  'automaticQuality': {
    'tr': 'Otomatik kalite',
    'en': 'Automatic quality',
    'zh': '自动质量',
    'hi': 'स्वचालित गुणवत्ता',
    'es': 'Calidad automática',
    'fr': 'Qualité automatique'
  },
  'autoQualityDescription': {
    'tr': 'Server eski/yeni cihaz ve Wi‑Fi durumuna göre profili seçer.',
    'en': 'The Server chooses a profile based on device age and Wi‑Fi state.',
    'zh': 'Server 会根据设备新旧和 Wi‑Fi 状态选择配置。',
    'hi': 'Server डिवाइस और Wi‑Fi स्थिति के आधार पर प्रोफ़ाइल चुनता है।',
    'es': 'El Server elige perfil según dispositivo y estado Wi‑Fi.',
    'fr': 'Le Server choisit un profil selon l’appareil et l’état Wi‑Fi.'
  },
  'audioMetric': {
    'tr': 'Ses: {value}',
    'en': 'Audio: {value}',
    'zh': '声音：{value}',
    'hi': 'ऑडियो: {value}',
    'es': 'Audio: {value}',
    'fr': 'Audio : {value}'
  },
  'latencyMetric': {
    'tr': 'Gecikme: {value}',
    'en': 'Latency: {value}',
    'zh': '延迟：{value}',
    'hi': 'देरी: {value}',
    'es': 'Latencia: {value}',
    'fr': 'Latence : {value}'
  },
  'networkMetric': {
    'tr': 'Ağ: {value}',
    'en': 'Network: {value}',
    'zh': '网络：{value}',
    'hi': 'नेटवर्क: {value}',
    'es': 'Red: {value}',
    'fr': 'Réseau : {value}'
  },
  'audioPriority': {
    'tr': 'Öncelikli',
    'en': 'Priority',
    'zh': '优先',
    'hi': 'प्राथमिक',
    'es': 'Prioritario',
    'fr': 'Prioritaire'
  },
  'open': {
    'tr': 'Açık',
    'en': 'On',
    'zh': '开启',
    'hi': 'चालू',
    'es': 'Activo',
    'fr': 'Activé'
  },
  'measuring': {
    'tr': 'Ölçülüyor',
    'en': 'Measuring',
    'zh': '测量中',
    'hi': 'मापा जा रहा है',
    'es': 'Midiendo',
    'fr': 'Mesure'
  },
  'netExcellent': {
    'tr': 'Çok iyi',
    'en': 'Excellent',
    'zh': '很好',
    'hi': 'बहुत अच्छा',
    'es': 'Excelente',
    'fr': 'Excellent'
  },
  'netGood': {
    'tr': 'İyi',
    'en': 'Good',
    'zh': '良好',
    'hi': 'अच्छा',
    'es': 'Buena',
    'fr': 'Bonne'
  },
  'netWeak': {
    'tr': 'Zayıf',
    'en': 'Weak',
    'zh': '较弱',
    'hi': 'कमज़ोर',
    'es': 'Débil',
    'fr': 'Faible'
  },
  'netCritical': {
    'tr': 'Kritik',
    'en': 'Critical',
    'zh': '严重',
    'hi': 'गंभीर',
    'es': 'Crítica',
    'fr': 'Critique'
  },
  'netOffline': {
    'tr': 'Çevrim dışı',
    'en': 'Offline',
    'zh': '离线',
    'hi': 'ऑफ़लाइन',
    'es': 'Sin conexión',
    'fr': 'Hors ligne'
  },
  'qrScanCameraError': {
    'tr': 'Kamera açılamadı. QR kodunu alttan yapıştırabilirsin.',
    'en': 'Camera could not open. You can paste the QR text below.',
    'zh': '无法打开摄像头。你可以在下方粘贴二维码文本。',
    'hi': 'कैमरा नहीं खुला। आप नीचे QR टेक्स्ट पेस्ट कर सकते हैं।',
    'es': 'No se pudo abrir la cámara. Puedes pegar el texto QR abajo.',
    'fr':
        'La caméra ne peut pas s’ouvrir. Vous pouvez coller le texte QR ci-dessous.'
  },
  'qrCodeText': {
    'tr': 'QR kod metni',
    'en': 'QR code text',
    'zh': '二维码文本',
    'hi': 'QR कोड टेक्स्ट',
    'es': 'Texto del código QR',
    'fr': 'Texte du QR code'
  },
  'qrIpTicketTitle': {
    'tr': 'QR / IP bağlantı bileti',
    'en': 'QR / IP connection ticket',
    'zh': 'QR / IP 连接票据',
    'hi': 'QR / IP कनेक्शन टिकट',
    'es': 'Ticket de conexión QR / IP',
    'fr': 'Ticket de connexion QR / IP'
  },
  'qrIpTicketSubtitle': {
    'tr':
        'Bu ekran QR taramaz; sadece ebeveyn cihazının bağlanacağı bilgiyi üretir.',
    'en':
        'This screen does not scan QR; it only creates the connection info for the parent device.',
    'zh': '此屏幕不扫描二维码；只生成家长设备要连接的信息。',
    'hi':
        'यह स्क्रीन QR स्कैन नहीं करती; यह केवल अभिभावक डिवाइस के लिए कनेक्शन जानकारी बनाती है।',
    'es':
        'Esta pantalla no escanea QR; solo crea la información de conexión para el dispositivo padre/madre.',
    'fr':
        'Cet écran ne scanne pas de QR ; il crée seulement les infos de connexion pour l’appareil parent.'
  },
  'serviceStatus': {
    'tr': 'Servis durumu',
    'en': 'Service status',
    'zh': '服务状态',
    'hi': 'सेवा स्थिति',
    'es': 'Estado del servicio',
    'fr': 'État du service'
  },
  'serviceStatusSubtitle': {
    'tr': 'Kamera, mikrofon ve WebSocket server alanında izlenir.',
    'en': 'Camera, microphone, and WebSocket are monitored in the Server area.',
    'zh': '摄像头、麦克风和 WebSocket 在 Server 区域监控。',
    'hi': 'कैमरा, माइक्रोफ़ोन और WebSocket Server क्षेत्र में देखे जाते हैं।',
    'es': 'Cámara, micrófono y WebSocket se vigilan en el área Server.',
    'fr': 'Caméra, micro et WebSocket sont suivis dans la zone Server.'
  },
  'serverSettings': {
    'tr': 'Server ayarları',
    'en': 'Server settings',
    'zh': 'Server 设置',
    'hi': 'Server सेटिंग्स',
    'es': 'Ajustes Server',
    'fr': 'Réglages Server'
  },
  'serverSettingsSubtitle': {
    'tr':
        'Eşikler, cooldown ve teknik davranış yalnızca bebek odası cihazını etkiler.',
    'en':
        'Thresholds, cooldown, and technical behavior affect only the baby room device.',
    'zh': '阈值、冷却和技术行为只影响婴儿房设备。',
    'hi':
        'सीमाएँ, cooldown और तकनीकी व्यवहार केवल बच्चे के कमरे के डिवाइस को प्रभावित करते हैं।',
    'es':
        'Umbrales, pausas y comportamiento técnico solo afectan al dispositivo de la habitación.',
    'fr':
        'Seuils, cooldown et comportement technique n’affectent que l’appareil de la chambre.'
  },
  'phaseStopped': {
    'tr': 'Durdu',
    'en': 'Stopped',
    'zh': '已停止',
    'hi': 'रुका',
    'es': 'Detenido',
    'fr': 'Arrêté'
  },
  'phasePairingIdle': {
    'tr': 'Eşleşme bekliyor',
    'en': 'Waiting to pair',
    'zh': '等待配对',
    'hi': 'पेयरिंग की प्रतीक्षा',
    'es': 'Esperando emparejar',
    'fr': 'En attente d’appairage'
  },
  'phasePairingActive': {
    'tr': 'Yayında',
    'en': 'Broadcasting',
    'zh': '直播中',
    'hi': 'प्रसारण में',
    'es': 'Transmitiendo',
    'fr': 'Diffusion'
  },
  'phaseClientPaired': {
    'tr': 'Client bağlı',
    'en': 'Client connected',
    'zh': 'Client 已连接',
    'hi': 'Client जुड़ा',
    'es': 'Client conectado',
    'fr': 'Client connecté'
  },
  'phaseMediaIdle': {
    'tr': 'Medya beklemede',
    'en': 'Media idle',
    'zh': '媒体待机',
    'hi': 'मीडिया प्रतीक्षा में',
    'es': 'Medios en espera',
    'fr': 'Média en attente'
  },
  'phaseMediaStarting': {
    'tr': 'Medya başlıyor',
    'en': 'Media starting',
    'zh': '媒体启动中',
    'hi': 'मीडिया शुरू हो रहा है',
    'es': 'Iniciando medios',
    'fr': 'Démarrage média'
  },
  'phaseMediaActive': {
    'tr': 'Medya aktif',
    'en': 'Media active',
    'zh': '媒体已启用',
    'hi': 'मीडिया सक्रिय',
    'es': 'Medios activos',
    'fr': 'Média actif'
  },
  'phaseError': {
    'tr': 'Hata',
    'en': 'Error',
    'zh': '错误',
    'hi': 'त्रुटि',
    'es': 'Error',
    'fr': 'Erreur'
  },
  'babyRoomMode': {
    'tr': 'BEBEK ODASI MODU',
    'en': 'BABY ROOM MODE',
    'zh': '婴儿房模式',
    'hi': 'बच्चे का कमरा मोड',
    'es': 'MODO HABITACIÓN',
    'fr': 'MODE CHAMBRE BÉBÉ'
  },
  'roomStreamReady': {
    'tr': 'Oda yayına hazır',
    'en': 'Room stream is ready',
    'zh': '房间直播已就绪',
    'hi': 'कमरे की स्ट्रीम तैयार है',
    'es': 'Directo de habitación listo',
    'fr': 'Flux de la chambre prêt'
  },
  'serverHeroReadyText': {
    'tr': 'Kamera açık, eşleşme hazır. Telefonu sabit bir yere bırakabilirsin.',
    'en':
        'Camera is on and pairing is ready. You can place the phone somewhere steady.',
    'zh': '摄像头已开启，配对已就绪。请把手机放在稳定的位置。',
    'hi':
        'कैमरा चालू है और पेयरिंग तैयार है। फ़ोन को स्थिर जगह पर रख सकते हैं।',
    'es':
        'Cámara activa y emparejamiento listo. Puedes dejar el teléfono en un lugar estable.',
    'fr':
        'Caméra active et appairage prêt. Placez le téléphone à un endroit stable.'
  },
  'cameraOpen': {
    'tr': 'Kamera açık',
    'en': 'Camera on',
    'zh': '摄像头开启',
    'hi': 'कैमरा चालू',
    'es': 'Cámara activa',
    'fr': 'Caméra active'
  },
  'cameraWaiting': {
    'tr': 'Kamera bekliyor',
    'en': 'Camera waiting',
    'zh': '摄像头等待中',
    'hi': 'कैमरा प्रतीक्षा में',
    'es': 'Cámara en espera',
    'fr': 'Caméra en attente'
  },
  'parentsCount': {
    'tr': '{count} ebeveyn',
    'en': '{count} parent(s)',
    'zh': '{count} 位家长',
    'hi': '{count} अभिभावक',
    'es': '{count} padre/madre',
    'fr': '{count} parent(s)'
  },
  'qualityMeasuring': {
    'tr': 'Kalite ölçülüyor',
    'en': 'Measuring quality',
    'zh': '正在测量质量',
    'hi': 'गुणवत्ता मापी जा रही है',
    'es': 'Midiendo calidad',
    'fr': 'Mesure de qualité'
  },
  'stopRoomStream': {
    'tr': 'Oda yayınını durdur',
    'en': 'Stop room stream',
    'zh': '停止房间直播',
    'hi': 'कमरे की स्ट्रीम रोकें',
    'es': 'Detener directo',
    'fr': 'Arrêter le flux'
  },
  'secureQrPairing': {
    'tr': 'Güvenli QR eşleşme',
    'en': 'Secure QR pairing',
    'zh': '安全二维码配对',
    'hi': 'सुरक्षित QR पेयरिंग',
    'es': 'Emparejamiento QR seguro',
    'fr': 'Appairage QR sécurisé'
  },
  'parentQrScanText': {
    'tr': 'Ebeveyn cihazında QR tara; bağlantı bilgisi otomatik aktarılır.',
    'en':
        'Scan QR on the parent device; connection info transfers automatically.',
    'zh': '在家长设备扫描二维码；连接信息会自动传输。',
    'hi': 'अभिभावक डिवाइस पर QR स्कैन करें; कनेक्शन जानकारी अपने-आप जाएगी।',
    'es':
        'Escanea QR en el dispositivo padre/madre; la conexión se transfiere sola.',
    'fr':
        'Scannez le QR sur l’appareil parent ; les infos se transfèrent automatiquement.'
  },
  'keepCodeVisible': {
    'tr': 'Kod görünür kalsın; eşleşme bitince yayın izlenebilir.',
    'en': 'Keep the code visible; the stream can be watched after pairing.',
    'zh': '保持代码可见；配对完成后即可观看直播。',
    'hi': 'कोड दिखता रहे; पेयरिंग के बाद स्ट्रीम देखी जा सकती है।',
    'es': 'Mantén el código visible; tras emparejar se puede ver el directo.',
    'fr': 'Gardez le code visible ; le flux sera visible après appairage.'
  },
  'qrTicketRefreshed': {
    'tr': 'QR bağlantı bileti yenilendi.',
    'en': 'QR connection ticket refreshed.',
    'zh': 'QR 连接票据已刷新。',
    'hi': 'QR कनेक्शन टिकट रीफ़्रेश हुआ।',
    'es': 'Ticket QR actualizado.',
    'fr': 'Ticket QR actualisé.'
  },
  'refreshQr': {
    'tr': 'QR yenile',
    'en': 'Refresh QR',
    'zh': '刷新 QR',
    'hi': 'QR रीफ़्रेश करें',
    'es': 'Actualizar QR',
    'fr': 'Actualiser QR'
  },
  'ticketCopied': {
    'tr': 'Bağlantı bileti kopyalandı.',
    'en': 'Connection ticket copied.',
    'zh': '连接票据已复制。',
    'hi': 'कनेक्शन टिकट कॉपी हुआ।',
    'es': 'Ticket de conexión copiado.',
    'fr': 'Ticket de connexion copié.'
  },
  'copyAddress': {
    'tr': 'Adresi kopyala',
    'en': 'Copy address',
    'zh': '复制地址',
    'hi': 'पता कॉपी करें',
    'es': 'Copiar dirección',
    'fr': 'Copier l’adresse'
  },
  'camera': {
    'tr': 'Kamera',
    'en': 'Camera',
    'zh': '摄像头',
    'hi': 'कैमरा',
    'es': 'Cámara',
    'fr': 'Caméra'
  },
  'microphone': {
    'tr': 'Mikrofon',
    'en': 'Microphone',
    'zh': '麦克风',
    'hi': 'माइक्रोफ़ोन',
    'es': 'Micrófono',
    'fr': 'Micro'
  },
  'clientCount': {
    'tr': 'Client sayısı',
    'en': 'Client count',
    'zh': 'Client 数量',
    'hi': 'Client संख्या',
    'es': 'Número de Client',
    'fr': 'Nombre de Client'
  },
  'active': {
    'tr': 'Aktif',
    'en': 'Active',
    'zh': '活动',
    'hi': 'सक्रिय',
    'es': 'Activo',
    'fr': 'Actif'
  },
  'preparing': {
    'tr': 'Hazırlanıyor',
    'en': 'Preparing',
    'zh': '准备中',
    'hi': 'तैयार हो रहा है',
    'es': 'Preparando',
    'fr': 'Préparation'
  },
  'off': {
    'tr': 'Kapalı',
    'en': 'Off',
    'zh': '关闭',
    'hi': 'बंद',
    'es': 'Apagado',
    'fr': 'Désactivé'
  },
  'eventClientsCount': {
    'tr': '{count} event client',
    'en': '{count} event client(s)',
    'zh': '{count} 个事件 client',
    'hi': '{count} event client',
    'es': '{count} client de eventos',
    'fr': '{count} client(s) événement'
  },
  'connectedCount': {
    'tr': '{count} bağlı',
    'en': '{count} connected',
    'zh': '{count} 已连接',
    'hi': '{count} जुड़ा',
    'es': '{count} conectado(s)',
    'fr': '{count} connecté(s)'
  },
  'parent': {
    'tr': 'Ebeveyn',
    'en': 'Parent',
    'zh': '家长',
    'hi': 'अभिभावक',
    'es': 'Padre/madre',
    'fr': 'Parent'
  },
  'waiting': {
    'tr': 'Bekleniyor',
    'en': 'Waiting',
    'zh': '等待中',
    'hi': 'प्रतीक्षा',
    'es': 'Esperando',
    'fr': 'En attente'
  },
  'listening': {
    'tr': 'Dinliyor',
    'en': 'Listening',
    'zh': '监听中',
    'hi': 'सुन रहा है',
    'es': 'Escuchando',
    'fr': 'Écoute'
  },
  'quality': {
    'tr': 'Kalite',
    'en': 'Quality',
    'zh': '质量',
    'hi': 'गुणवत्ता',
    'es': 'Calidad',
    'fr': 'Qualité'
  },
  'automatic': {
    'tr': 'Otomatik',
    'en': 'Automatic',
    'zh': '自动',
    'hi': 'स्वचालित',
    'es': 'Automático',
    'fr': 'Automatique'
  },
  'smartAlerts': {
    'tr': 'Akıllı uyarılar',
    'en': 'Smart alerts',
    'zh': '智能提醒',
    'hi': 'स्मार्ट अलर्ट',
    'es': 'Alertas inteligentes',
    'fr': 'Alertes intelligentes'
  },
  'smartAlertsSubtitle': {
    'tr': 'Sadece önemli değişimleri sakin uyarılara dönüştürür.',
    'en': 'Turns only important changes into calm alerts.',
    'zh': '只把重要变化转成平静提醒。',
    'hi': 'केवल महत्वपूर्ण बदलावों को शांत अलर्ट में बदलता है।',
    'es': 'Convierte solo cambios importantes en alertas tranquilas.',
    'fr': 'Transforme seulement les changements importants en alertes calmes.'
  },
  'cryTracking': {
    'tr': 'Ağlama takibi',
    'en': 'Cry tracking',
    'zh': '哭声跟踪',
    'hi': 'रोना ट्रैकिंग',
    'es': 'Seguimiento de llanto',
    'fr': 'Suivi des pleurs'
  },
  'motionTracking': {
    'tr': 'Hareket takibi',
    'en': 'Motion tracking',
    'zh': '活动跟踪',
    'hi': 'गतिविधि ट्रैकिंग',
    'es': 'Seguimiento de movimiento',
    'fr': 'Suivi du mouvement'
  },
  'ready': {
    'tr': 'Hazır',
    'en': 'Ready',
    'zh': '就绪',
    'hi': 'तैयार',
    'es': 'Listo',
    'fr': 'Prêt'
  },
  'operatingMode': {
    'tr': 'Çalışma modu',
    'en': 'Operating mode',
    'zh': '运行模式',
    'hi': 'ऑपरेटिंग मोड',
    'es': 'Modo de trabajo',
    'fr': 'Mode de fonctionnement'
  },
  'streamProfile': {
    'tr': 'Yayın profili',
    'en': 'Stream profile',
    'zh': '直播配置',
    'hi': 'स्ट्रीम प्रोफ़ाइल',
    'es': 'Perfil de directo',
    'fr': 'Profil du flux'
  },
  'autoMeasuring': {
    'tr': 'Otomatik ölçülüyor',
    'en': 'Measuring automatically',
    'zh': '自动测量中',
    'hi': 'अपने-आप मापा जा रहा है',
    'es': 'Midiendo automáticamente',
    'fr': 'Mesure automatique'
  },
  'notificationTracking': {
    'tr': 'Uyarı takibi',
    'en': 'Alert tracking',
    'zh': '提醒跟踪',
    'hi': 'अलर्ट ट्रैकिंग',
    'es': 'Seguimiento de alertas',
    'fr': 'Suivi des alertes'
  },
  'roomReady': {
    'tr': 'Oda hazır',
    'en': 'Room ready',
    'zh': '房间就绪',
    'hi': 'कमरा तैयार',
    'es': 'Habitación lista',
    'fr': 'Chambre prête'
  },
  'roomCamera': {
    'tr': 'Oda kamerası',
    'en': 'Room camera',
    'zh': '房间摄像头',
    'hi': 'कमरे का कैमरा',
    'es': 'Cámara de habitación',
    'fr': 'Caméra de la chambre'
  },
  'livePreview': {
    'tr': 'Canlı önizleme',
    'en': 'Live preview',
    'zh': '实时预览',
    'hi': 'लाइव पूर्वावलोकन',
    'es': 'Vista previa en directo',
    'fr': 'Aperçu en direct'
  },
  'cameraStarting': {
    'tr': 'Kamera açılıyor',
    'en': 'Camera starting',
    'zh': '摄像头启动中',
    'hi': 'कैमरा शुरू हो रहा है',
    'es': 'Iniciando cámara',
    'fr': 'Démarrage caméra'
  },
  'cameraRoomCheckText': {
    'tr':
        'Telefonun bebek odasına baktığını buradan hızlıca kontrol edebilirsin.',
    'en': 'You can quickly check that the phone is facing the baby room here.',
    'zh': '你可以在这里快速确认手机正对婴儿房。',
    'hi': 'यहाँ जल्दी देख सकते हैं कि फ़ोन बच्चे के कमरे की ओर है।',
    'es': 'Aquí puedes revisar rápido que el teléfono apunta a la habitación.',
    'fr': 'Vous pouvez vérifier ici que le téléphone regarde bien la chambre.'
  },
  'cameraPermissionPreviewText': {
    'tr': 'Kamera izni verildiğinde oda görüntüsü burada görünecek.',
    'en': 'When camera permission is granted, the room image appears here.',
    'zh': '授予摄像头权限后，房间画面会显示在这里。',
    'hi': 'कैमरा अनुमति मिलने पर कमरे की छवि यहाँ दिखेगी।',
    'es': 'Al conceder permiso de cámara, la imagen aparecerá aquí.',
    'fr': 'Quand la permission caméra sera accordée, l’image apparaîtra ici.'
  },
  'cameraPreparing': {
    'tr': 'Kamera hazırlanıyor',
    'en': 'Camera preparing',
    'zh': '摄像头准备中',
    'hi': 'कैमरा तैयार हो रहा है',
    'es': 'Preparando cámara',
    'fr': 'Préparation caméra'
  },
  'silentSafeDetection': {
    'tr': 'Sessiz ve güvenli algılama',
    'en': 'Quiet and safe detection',
    'zh': '安静安全检测',
    'hi': 'शांत और सुरक्षित पहचान',
    'es': 'Detección tranquila y segura',
    'fr': 'Détection calme et sûre'
  },
  'resetDefaults': {
    'tr': 'Varsayılanlara dön',
    'en': 'Reset defaults',
    'zh': '恢复默认',
    'hi': 'डिफ़ॉल्ट पर लौटें',
    'es': 'Restablecer valores',
    'fr': 'Réinitialiser'
  },
  'detectionSettingsSubtitle': {
    'tr':
        'Hassasiyeti bebeğin odasına göre ayarla; değişiklikler otomatik kaydedilir.',
    'en':
        'Adjust sensitivity for the baby room; changes are saved automatically.',
    'zh': '根据婴儿房调整灵敏度；更改会自动保存。',
    'hi':
        'बच्चे के कमरे के अनुसार संवेदनशीलता सेट करें; बदलाव अपने-आप सेव होते हैं।',
    'es':
        'Ajusta la sensibilidad para la habitación; los cambios se guardan solos.',
    'fr':
        'Réglez la sensibilité pour la chambre ; les changements sont enregistrés automatiquement.'
  },
  'cryThresholdDescription': {
    'tr': 'Daha düşük değer, daha sessiz ağlamalara da tepki verir.',
    'en': 'A lower value reacts to quieter cries too.',
    'zh': '较低值也会对更小的哭声作出反应。',
    'hi': 'कम मान शांत रोने पर भी प्रतिक्रिया देता है।',
    'es': 'Un valor menor reacciona también a llantos más suaves.',
    'fr': 'Une valeur plus basse réagit aussi aux pleurs plus faibles.'
  },
  'motionThresholdDescription': {
    'tr': 'Battaniye veya ışık değişimlerini ne kadar önemseyeceğini ayarlar.',
    'en': 'Controls how much blanket or light changes matter.',
    'zh': '控制毯子或光线变化的重要程度。',
    'hi': 'कंबल या रोशनी बदलावों को कितना महत्व देना है, यह तय करता है।',
    'es': 'Define cuánto importan cambios de manta o luz.',
    'fr': 'Définit l’importance des changements de couverture ou lumière.'
  },
  'notificationCooldownDescription': {
    'tr': 'Aynı uyarının üst üste rahatsız etmesini engeller.',
    'en': 'Prevents the same alert from disturbing repeatedly.',
    'zh': '避免同一提醒连续打扰。',
    'hi': 'एक ही अलर्ट को बार-बार परेशान करने से रोकता है।',
    'es': 'Evita que la misma alerta moleste repetidamente.',
    'fr': 'Évite que la même alerte dérange plusieurs fois.'
  },
  'cryMinimumDuration': {
    'tr': 'Ağlama minimum süre',
    'en': 'Cry minimum duration',
    'zh': '哭声最短持续时间',
    'hi': 'रोने की न्यूनतम अवधि',
    'es': 'Duración mínima de llanto',
    'fr': 'Durée minimale des pleurs'
  },
  'cryMinimumDurationDescription': {
    'tr': 'Sesin uyarı sayılması için eşik üstünde kalma süresi.',
    'en': 'How long sound must stay over threshold to count as an alert.',
    'zh': '声音需高于阈值多久才算提醒。',
    'hi': 'अलर्ट मानने के लिए ध्वनि को सीमा से ऊपर कितनी देर रहना है।',
    'es': 'Tiempo que el sonido debe superar el umbral para alertar.',
    'fr': 'Durée pendant laquelle le son doit dépasser le seuil.'
  },
  'motionMinimumDuration': {
    'tr': 'Hareket minimum süre',
    'en': 'Motion minimum duration',
    'zh': '活动最短持续时间',
    'hi': 'गतिविधि न्यूनतम अवधि',
    'es': 'Duración mínima de movimiento',
    'fr': 'Durée minimale du mouvement'
  },
  'motionMinimumDurationDescription': {
    'tr': 'Kısa ışık/parazit değişimlerini filtrelemek için süre.',
    'en': 'Duration used to filter short light/noise changes.',
    'zh': '用于过滤短暂光线/噪声变化的持续时间。',
    'hi': 'छोटी रोशनी/शोर बदलावों को फ़िल्टर करने की अवधि।',
    'es': 'Duración para filtrar cambios breves de luz/ruido.',
    'fr': 'Durée pour filtrer les courts changements lumière/bruit.'
  },
  'localNotification': {
    'tr': 'Yerel bildirim',
    'en': 'Local notification',
    'zh': '本地通知',
    'hi': 'स्थानीय सूचना',
    'es': 'Notificación local',
    'fr': 'Notification locale'
  },
  'sentToClientDevice': {
    'tr': 'Client cihazına gönderilir',
    'en': 'Sent to the Client device',
    'zh': '发送到 Client 设备',
    'hi': 'Client डिवाइस को भेजा जाता है',
    'es': 'Se envía al dispositivo Client',
    'fr': 'Envoyé à l’appareil Client'
  },
  'saving': {
    'tr': 'Kaydediliyor',
    'en': 'Saving',
    'zh': '保存中',
    'hi': 'सेव हो रहा है',
    'es': 'Guardando',
    'fr': 'Enregistrement'
  },
  'realSettings': {
    'tr': 'Gerçek ayarlar',
    'en': 'Real settings',
    'zh': '真实设置',
    'hi': 'वास्तविक सेटिंग्स',
    'es': 'Ajustes reales',
    'fr': 'Réglages réels'
  },
  'goodMorning': {
    'tr': 'Günaydın',
    'en': 'Good morning',
    'zh': '早上好',
    'hi': 'सुप्रभात',
    'es': 'Buenos días',
    'fr': 'Bonjour',
  },
  'babySleepingWell': {
    'tr': 'Bebeğiniz iyi uyuyor.',
    'en': 'Your baby is sleeping well.',
    'zh': '宝宝睡得很好。',
    'hi': 'आपका बच्चा अच्छी तरह सो रहा है।',
    'es': 'Tu bebé está durmiendo bien.',
    'fr': 'Votre bébé dort bien.',
  },
  'noRoomCalmText': {
    'tr':
        'Bebek odası cihazını bulup bağladıktan sonra buradan izleyebilirsiniz.',
    'en': 'After connecting the baby room device, you can watch it here.',
    'zh': '连接宝宝房设备后，你可以在这里观看。',
    'hi': 'बच्चे के कमरे का डिवाइस जोड़ने के बाद आप यहाँ देख सकते हैं।',
    'es':
        'Después de conectar el dispositivo de la habitación, podrás verlo aquí.',
    'fr':
        'Après connexion à l’appareil de la chambre, vous pourrez regarder ici.',
  },
  'findAndConnectRoom': {
    'tr': 'Oda bul ve bağlan',
    'en': 'Find and connect room',
    'zh': '查找并连接房间',
    'hi': 'कमरा ढूँढें और जोड़ें',
    'es': 'Buscar y conectar habitación',
    'fr': 'Trouver et connecter la chambre',
  },
  'roomStatus': {
    'tr': 'Oda Durumu',
    'en': 'Room status',
    'zh': '房间状态',
    'hi': 'कमरे की स्थिति',
    'es': 'Estado de la habitación',
    'fr': 'État de la chambre',
  },
  'temperatureHumidity': {
    'tr': '22.5 °C   %45',
    'en': '22.5 °C   45%',
    'zh': '22.5 °C   45%',
    'hi': '22.5 °C   45%',
    'es': '22.5 °C   45%',
    'fr': '22.5 °C   45 %',
  },
  'fine': {
    'tr': 'İyi',
    'en': 'Good',
    'zh': '良好',
    'hi': 'ठीक',
    'es': 'Bien',
    'fr': 'Bien',
  },
  'lastMotion': {
    'tr': 'Son Hareket',
    'en': 'Last motion',
    'zh': '最近活动',
    'hi': 'अंतिम हलचल',
    'es': 'Último movimiento',
    'fr': 'Dernier mouvement',
  },
  'twoMinutesAgo': {
    'tr': '2 dk önce',
    'en': '2 min ago',
    'zh': '2 分钟前',
    'hi': '2 मिनट पहले',
    'es': 'Hace 2 min',
    'fr': 'Il y a 2 min',
  },
  'lightMotionDetected': {
    'tr': 'Hafif hareket algılandı',
    'en': 'Light motion detected',
    'zh': '检测到轻微活动',
    'hi': 'हल्की हलचल मिली',
    'es': 'Movimiento leve detectado',
    'fr': 'Mouvement léger détecté',
  },
  'or': {
    'tr': 'veya',
    'en': 'or',
    'zh': '或',
    'hi': 'या',
    'es': 'o',
    'fr': 'ou',
  },
  'manualIpConnectTitle': {
    'tr': 'Manuel IP ile Bağlan',
    'en': 'Connect with manual IP',
    'zh': '使用手动 IP 连接',
    'hi': 'मैनुअल IP से कनेक्ट करें',
    'es': 'Conectar con IP manual',
    'fr': 'Connexion par IP manuelle',
  },
  'manualIpConnectText': {
    'tr': 'Cihazın IP adresini girerek bağlantı kurun.',
    'en': 'Connect by entering the device IP address.',
    'zh': '输入设备 IP 地址进行连接。',
    'hi': 'डिवाइस का IP पता डालकर कनेक्ट करें।',
    'es': 'Conecta ingresando la dirección IP del dispositivo.',
    'fr': 'Connectez-vous en saisissant l’adresse IP de l’appareil.',
  },
  'localNetworkPrivacyNote': {
    'tr':
        'Sadece yerel ağınızdaki cihazlar listelenir. Verileriniz dışarıya gönderilmez.',
    'en':
        'Only devices on your local network are listed. Your data is not sent outside.',
    'zh': '只会列出本地网络中的设备。你的数据不会发送到外部。',
    'hi':
        'केवल आपके स्थानीय नेटवर्क के डिवाइस दिखते हैं। आपका डेटा बाहर नहीं भेजा जाता।',
    'es':
        'Solo se muestran dispositivos de tu red local. Tus datos no se envían fuera.',
    'fr':
        'Seuls les appareils de votre réseau local sont listés. Vos données ne sortent pas.',
  },
  'important': {
    'tr': 'Önemli',
    'en': 'Important',
    'zh': '重要',
    'hi': 'महत्वपूर्ण',
    'es': 'Importante',
    'fr': 'Important',
  },
  'info': {
    'tr': 'Bilgi',
    'en': 'Info',
    'zh': '信息',
    'hi': 'जानकारी',
    'es': 'Información',
    'fr': 'Info',
  },
  'warning': {
    'tr': 'Uyarı',
    'en': 'Warning',
    'zh': '警告',
    'hi': 'चेतावनी',
    'es': 'Advertencia',
    'fr': 'Avertissement',
  },
  'cryDetectedTitle': {
    'tr': 'Ağlama algılandı',
    'en': 'Cry detected',
    'zh': '检测到哭声',
    'hi': 'रोना मिला',
    'es': 'Llanto detectado',
    'fr': 'Pleurs détectés',
  },
  'cryDetectedText': {
    'tr': 'Bebeğinizin ağlaması algılandı.',
    'en': 'Your baby crying was detected.',
    'zh': '检测到宝宝哭声。',
    'hi': 'आपके बच्चे के रोने का संकेत मिला।',
    'es': 'Se detectó el llanto de tu bebé.',
    'fr': 'Les pleurs de votre bébé ont été détectés.',
  },
  'motionDetectedTitle': {
    'tr': 'Hareket algılandı',
    'en': 'Motion detected',
    'zh': '检测到活动',
    'hi': 'हलचल मिली',
    'es': 'Movimiento detectado',
    'fr': 'Mouvement détecté',
  },
  'motionDetectedText': {
    'tr': 'Bebek odasında hareket algılandı.',
    'en': 'Motion was detected in the baby room.',
    'zh': '宝宝房检测到活动。',
    'hi': 'बच्चे के कमरे में हलचल मिली।',
    'es': 'Se detectó movimiento en la habitación del bebé.',
    'fr': 'Un mouvement a été détecté dans la chambre du bébé.',
  },
  'temperatureWarningTitle': {
    'tr': 'Sıcaklık uyarısı',
    'en': 'Temperature warning',
    'zh': '温度警告',
    'hi': 'तापमान चेतावनी',
    'es': 'Alerta de temperatura',
    'fr': 'Alerte température',
  },
  'temperatureWarningText': {
    'tr': 'Oda sıcaklığı 28.0 °C’ye yükseldi.',
    'en': 'Room temperature rose to 28.0 °C.',
    'zh': '房间温度升至 28.0 °C。',
    'hi': 'कमरे का तापमान 28.0 °C तक बढ़ गया।',
    'es': 'La temperatura de la habitación subió a 28.0 °C.',
    'fr': 'La température de la chambre est montée à 28,0 °C.',
  },
  'connectionRenewedTitle': {
    'tr': 'Bağlantı yenilendi',
    'en': 'Connection renewed',
    'zh': '连接已恢复',
    'hi': 'कनेक्शन नवीनीकृत',
    'es': 'Conexión renovada',
    'fr': 'Connexion renouvelée',
  },
  'connectionRenewedText': {
    'tr': 'Bebek odası cihazı çevrimiçi.',
    'en': 'The baby room device is online.',
    'zh': '宝宝房设备已在线。',
    'hi': 'बच्चे के कमरे का डिवाइस ऑनलाइन है।',
    'es': 'El dispositivo de la habitación está en línea.',
    'fr': 'L’appareil de la chambre est en ligne.',
  },
  'humidityNormalTitle': {
    'tr': 'Nem seviyesi normal',
    'en': 'Humidity level normal',
    'zh': '湿度正常',
    'hi': 'नमी स्तर सामान्य',
    'es': 'Humedad normal',
    'fr': 'Humidité normale',
  },
  'humidityNormalText': {
    'tr': 'Oda nem seviyesi %45.',
    'en': 'Room humidity is 45%.',
    'zh': '房间湿度为 45%。',
    'hi': 'कमरे की नमी 45% है।',
    'es': 'La humedad de la habitación es 45%.',
    'fr': 'L’humidité de la chambre est de 45 %.',
  },
  'notificationsManageText': {
    'tr': 'Uyarı ve sistem bildirimlerini yönetin.',
    'en': 'Manage alert and system notifications.',
    'zh': '管理提醒和系统通知。',
    'hi': 'अलर्ट और सिस्टम सूचनाएँ प्रबंधित करें।',
    'es': 'Gestiona alertas y notificaciones del sistema.',
    'fr': 'Gérez les alertes et notifications système.',
  },
  'languageSelectText': {
    'tr': 'Uygulama dilini seçin.',
    'en': 'Choose the app language.',
    'zh': '选择应用语言。',
    'hi': 'ऐप की भाषा चुनें।',
    'es': 'Elige el idioma de la app.',
    'fr': 'Choisissez la langue de l’application.',
  },
  'turkishShort': {
    'tr': 'Türkçe',
    'en': 'TR',
    'zh': 'TR',
    'hi': 'TR',
    'es': 'TR',
    'fr': 'TR',
  },
  'keepAwakeClientText': {
    'tr': 'Ekranın canlı izleme sırasında uykuya geçmesini önler.',
    'en': 'Prevents the screen from sleeping during live watch.',
    'zh': '防止屏幕在实时观看时休眠。',
    'hi': 'लाइव देखने के दौरान स्क्रीन को स्लीप होने से रोकता है।',
    'es': 'Evita que la pantalla se apague durante la vista en vivo.',
    'fr': 'Empêche l’écran de se mettre en veille pendant le direct.',
  },
  'serverSettingsHiddenText': {
    'tr':
        'Sunucu ayarları bu cihazda gösterilmez. Sunucu yönetimi için server cihazını kullanın.',
    'en':
        'Server settings are not shown on this device. Use the server device to manage them.',
    'zh': '此设备不显示 Server 设置。请使用 Server 设备进行管理。',
    'hi':
        'इस डिवाइस पर Server सेटिंग्स नहीं दिखतीं। प्रबंधन के लिए Server डिवाइस इस्तेमाल करें।',
    'es':
        'Los ajustes del Server no se muestran en este dispositivo. Usa el dispositivo Server para gestionarlos.',
    'fr':
        'Les réglages Server ne sont pas affichés sur cet appareil. Utilisez l’appareil Server pour les gérer.',
  },
  'stopLiveWatch': {
    'tr': 'Canlı İzlemeyi Durdur',
    'en': 'Stop live watch',
    'zh': '停止实时观看',
    'hi': 'लाइव देखना रोकें',
    'es': 'Detener vista en vivo',
    'fr': 'Arrêter le direct',
  },
  'latency': {
    'tr': 'Gecikme',
    'en': 'Latency',
    'zh': '延迟',
    'hi': 'विलंब',
    'es': 'Latencia',
    'fr': 'Latence',
  },
  'viewers': {
    'tr': 'İzleyen',
    'en': 'Viewers',
    'zh': '观看者',
    'hi': 'दर्शक',
    'es': 'Visores',
    'fr': 'Spectateurs',
  },
  'connection': {
    'tr': 'bağlantı',
    'en': 'connection',
    'zh': '连接',
    'hi': 'कनेक्शन',
    'es': 'conexión',
    'fr': 'connexion',
  },
  'resolution': {
    'tr': 'Çözünürlük',
    'en': 'Resolution',
    'zh': '分辨率',
    'hi': 'रिज़ॉल्यूशन',
    'es': 'Resolución',
    'fr': 'Résolution',
  },
  'detectionStatus': {
    'tr': 'Algılama Durumu',
    'en': 'Detection status',
    'zh': '检测状态',
    'hi': 'पहचान स्थिति',
    'es': 'Estado de detección',
    'fr': 'État de détection',
  },
};

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
