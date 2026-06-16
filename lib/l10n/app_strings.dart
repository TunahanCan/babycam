import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings)!;

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
    return _t(
      tr: '🔊 Ağlama olasılığı yüksek ($confidencePercent%). Ses ortamdan ${ambientDeltaDb.toStringAsFixed(1)} dB yüksek; ağlama bandı %$cryBandPercent. $calibration. Önce güvenli şekilde odayı kontrol et: açlık, bez, gaz, sıcak/soğuk veya sarılma ihtiyacı olabilir.',
      en: '🔊 Cry likelihood is high ($confidencePercent%). Sound is ${ambientDeltaDb.toStringAsFixed(1)} dB above ambient; cry-band energy is $cryBandPercent%. $calibration. Please check the room safely: hunger, diaper, gas, temperature, or need for comfort may be possible.',
      zh: '🔊 哭声可能性较高（$confidencePercent%）。声音比环境高 ${ambientDeltaDb.toStringAsFixed(1)} dB；哭声频段能量 $cryBandPercent%。$calibration。请安全查看房间：可能是饿了、尿布、胀气、冷热或需要安抚。',
      hi: '🔊 रोने की संभावना अधिक है ($confidencePercent%)। आवाज़ परिवेश से ${ambientDeltaDb.toStringAsFixed(1)} dB अधिक है; रोने वाले बैंड की ऊर्जा $cryBandPercent%। $calibration। कमरे को सुरक्षित रूप से देखें: भूख, डायपर, गैस, तापमान या आराम की ज़रूरत हो सकती है।',
      es: '🔊 La probabilidad de llanto es alta ($confidencePercent%). El sonido está ${ambientDeltaDb.toStringAsFixed(1)} dB por encima del ambiente; energía de banda de llanto $cryBandPercent%. $calibration. Revisa la habitación con seguridad: puede ser hambre, pañal, gases, temperatura o necesidad de consuelo.',
      fr: '🔊 Probabilité de pleurs élevée ($confidencePercent %). Le son est ${ambientDeltaDb.toStringAsFixed(1)} dB au-dessus de l’ambiance ; énergie de la bande des pleurs $cryBandPercent %. $calibration. Vérifiez la chambre en sécurité : faim, couche, gaz, température ou besoin de réconfort possibles.',
    );
  }

  String parentLoudSoundAlert({
    required double dbfs,
    required double ambientDeltaDb,
  }) =>
      _t(
        tr: '🔔 Ani yüksek ses algılandı. Seviye ${dbfs.toStringAsFixed(1)} dBFS; ortamdan ${ambientDeltaDb.toStringAsFixed(1)} dB yüksek. Bebeğin uyanıp uyanmadığını ve odada beklenmeyen bir ses kaynağı olup olmadığını kontrol et.',
        en: '🔔 Sudden loud sound detected. Level ${dbfs.toStringAsFixed(1)} dBFS; ${ambientDeltaDb.toStringAsFixed(1)} dB above ambient. Check whether the baby woke up and whether there is an unexpected noise source.',
        zh: '🔔 检测到突然的大声响。音量 ${dbfs.toStringAsFixed(1)} dBFS，比环境高 ${ambientDeltaDb.toStringAsFixed(1)} dB。请查看宝宝是否醒来，以及房间是否有异常声源。',
        hi: '🔔 अचानक तेज़ आवाज़ मिली। स्तर ${dbfs.toStringAsFixed(1)} dBFS; परिवेश से ${ambientDeltaDb.toStringAsFixed(1)} dB अधिक। देखें कि बच्चा जागा है या कमरे में कोई अनपेक्षित आवाज़ है।',
        es: '🔔 Se detectó un sonido fuerte repentino. Nivel ${dbfs.toStringAsFixed(1)} dBFS; ${ambientDeltaDb.toStringAsFixed(1)} dB sobre el ambiente. Revisa si el bebé se despertó o si hay una fuente de ruido inesperada.',
        fr: '🔔 Son fort soudain détecté. Niveau ${dbfs.toStringAsFixed(1)} dBFS ; ${ambientDeltaDb.toStringAsFixed(1)} dB au-dessus de l’ambiance. Vérifiez si le bébé s’est réveillé ou s’il y a une source de bruit inattendue.',
      );

  String parentMotionAlert({
    required int scorePercent,
    required int activeAreaPercent,
    required double meanDiff,
  }) =>
      _t(
        tr: '👶 Hareket algılandı ($scorePercent%). Görüntünün yaklaşık %$activeAreaPercent bölgesinde değişim var; ortalama değişim ${meanDiff.toStringAsFixed(1)}. Bebeğin pozisyonunu ve örtü/kenar güvenliğini kontrol et.',
        en: '👶 Motion detected ($scorePercent%). About $activeAreaPercent% of the image changed; average change ${meanDiff.toStringAsFixed(1)}. Check the baby’s position and blanket/edge safety.',
        zh: '👶 检测到活动（$scorePercent%）。画面约 $activeAreaPercent% 区域发生变化；平均变化 ${meanDiff.toStringAsFixed(1)}。请查看宝宝姿势以及毯子/床边安全。',
        hi: '👶 गतिविधि मिली ($scorePercent%)। चित्र के लगभग $activeAreaPercent% हिस्से में बदलाव है; औसत बदलाव ${meanDiff.toStringAsFixed(1)}। बच्चे की स्थिति और कंबल/किनारे की सुरक्षा देखें।',
        es: '👶 Movimiento detectado ($scorePercent%). Cambió aproximadamente el $activeAreaPercent% de la imagen; cambio medio ${meanDiff.toStringAsFixed(1)}. Revisa la posición del bebé y la seguridad de la manta/borde.',
        fr: '👶 Mouvement détecté ($scorePercent %). Environ $activeAreaPercent % de l’image a changé ; variation moyenne ${meanDiff.toStringAsFixed(1)}. Vérifiez la position du bébé et la sécurité couverture/bord.',
      );

  String parentLightChangeAlert({
    required int scorePercent,
    required double lumaShift,
  }) =>
      _t(
        tr: '💡 Oda ışığı değişti ($scorePercent%). Parlaklık kayması ${lumaShift.toStringAsFixed(1)}. Kamera görüşü veya gece lambası değişmiş olabilir; görüntüyü hızlıca kontrol et.',
        en: '💡 Room light changed ($scorePercent%). Brightness shift ${lumaShift.toStringAsFixed(1)}. Camera view or night light may have changed; quickly check the image.',
        zh: '💡 房间光线发生变化（$scorePercent%）。亮度偏移 ${lumaShift.toStringAsFixed(1)}。可能是摄像头视野或夜灯变化；请快速查看画面。',
        hi: '💡 कमरे की रोशनी बदली ($scorePercent%)। चमक बदलाव ${lumaShift.toStringAsFixed(1)}। कैमरा दृश्य या नाइट लाइट बदली हो सकती है; चित्र जल्दी देखें।',
        es: '💡 Cambió la luz de la habitación ($scorePercent%). Desplazamiento de brillo ${lumaShift.toStringAsFixed(1)}. Puede haber cambiado la vista de la cámara o la luz nocturna; revisa la imagen.',
        fr: '💡 La lumière de la chambre a changé ($scorePercent %). Décalage de luminosité ${lumaShift.toStringAsFixed(1)}. La vue caméra ou la veilleuse a peut-être changé ; vérifiez rapidement l’image.',
      );
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
