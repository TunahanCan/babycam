// Internal UI text catalog used by AppStrings.
// Kept separate so AppStrings stays a small localization facade.

const appUiTextCatalog = <String, Map<String, String>>{
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
  'babyRoomName': {
    'tr': 'Bebek Odası',
    'en': 'Baby Room',
    'zh': '婴儿房',
    'hi': 'बच्चे का कमरा',
    'es': 'Habitación del bebé',
    'fr': 'Chambre bébé'
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
        'Aynı Wi-Fi içinde bebek odası cihazı bulunur, canlı yayın izlenir ve uyarılar bildirim olur.',
    'en':
        'The server is found on the same Wi‑Fi, live video is watched, and alerts become notifications.',
    'zh': '在同一 Wi‑Fi 中找到婴儿房设备，可观看直播，提醒会变成通知。',
    'hi':
        'उसी Wi‑Fi में बच्चे के कमरे का डिवाइस मिलता है, लाइव स्ट्रीम देखी जाती है और अलर्ट सूचना बनते हैं।',
    'es':
        'Encuentra el dispositivo de la habitación en el mismo Wi‑Fi, mira el directo y recibe las alertas como notificaciones.',
    'fr':
        'Trouve l’appareil de la chambre sur le même Wi‑Fi, regarde le direct et reçoit les alertes en notifications.',
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
    'tr': 'EBEVEYN',
    'en': 'CLIENT',
    'zh': '客户端',
    'hi': 'अभिभावक',
    'es': 'CLIENTE',
    'fr': 'PARENT'
  },
  'serverRoleTitle': {
    'tr': 'SUNUCU',
    'en': 'SERVER',
    'zh': '服务器',
    'hi': 'सर्वर',
    'es': 'SERVIDOR',
    'fr': 'SERVEUR'
  },
  'parentRoleSubtitle': {
    'tr': 'EBEVEYN',
    'en': 'PARENT',
    'zh': '家长',
    'hi': 'अभिभावक',
    'es': 'PADRE/MADRE',
    'fr': 'PARENTS'
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
    'fr': 'Services'
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
    'tr':
        'Ebeveyn izleme ekranı sadece eşleşmiş bebek odası yayınını gösterir.',
    'en': 'The Client watch screen only shows the paired Server stream.',
    'zh': '家长观看屏幕只显示已配对婴儿房设备的直播。',
    'hi':
        'अभिभावक देखने की स्क्रीन केवल पेयर बच्चे के कमरे की स्ट्रीम दिखाती है।',
    'es':
        'La pantalla de padres solo muestra el directo del cuarto emparejado.',
    'fr': 'L’écran parent montre uniquement le direct de la chambre appairée.'
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
    'tr':
        'Kendi kendine oda göstermeyecek; sadece taranan bebek odası cihazı bağlanır.',
    'en': 'It will not invent a room; only the scanned server will connect.',
    'zh': '不会自动虚构房间；只会连接已扫描的婴儿房设备。',
    'hi': 'यह अपने-आप कमरा नहीं दिखाएगा; केवल स्कैन किया सर्वर डिवाइस जुड़ेगा।',
    'es':
        'No mostrará una habitación inventada; solo conecta el dispositivo escaneado.',
    'fr': 'Aucune chambre fictive ; seul l’appareil scanné se connecte.'
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
        'Sunucu güvenlik parmak izi eşleşmedi. QR’ı yenileyip tekrar deneyin.',
    'en':
        'Server security fingerprint did not match. Refresh the QR and try again.',
    'zh': '服务器安全指纹不匹配。请刷新二维码后重试。',
    'hi':
        'सर्वर सुरक्षा फिंगरप्रिंट मेल नहीं खाया। QR को रीफ़्रेश करके फिर कोशिश करें।',
    'es':
        'La huella de seguridad del servidor no coincide. Actualiza el QR e inténtalo de nuevo.',
    'fr':
        'L’empreinte de sécurité du serveur ne correspond pas. Actualisez le QR puis réessayez.'
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
    'tr': 'Sunucu bulunamadı: {code}',
    'en': 'Server not found: {code}',
    'zh': '未找到服务器：{code}',
    'hi': 'सर्वर नहीं मिला: {code}',
    'es': 'Servidor no encontrado: {code}',
    'fr': 'Serveur introuvable : {code}'
  },
  'invalidServerResponse': {
    'tr': 'Geçersiz sunucu yanıtı',
    'en': 'Invalid server response',
    'zh': '服务器响应无效',
    'hi': 'सर्वर प्रतिक्रिया अमान्य है',
    'es': 'Respuesta del servidor no válida',
    'fr': 'Réponse du serveur invalide'
  },
  'missingPairingNonce': {
    'tr': 'Sunucu eşleşme nonce değerini üretmedi',
    'en': 'Server did not create a pairing nonce',
    'zh': '服务器未生成配对 nonce',
    'hi': 'सर्वर ने pairing nonce नहीं बनाया',
    'es': 'El servidor no creó el nonce de emparejamiento',
    'fr': 'Le serveur n’a pas créé le nonce d’appairage'
  },
  'scanServerQrFirst': {
    'tr': 'Önce sunucu QR kodunu tara.',
    'en': 'Scan the Server QR code first.',
    'zh': '请先扫描服务器二维码。',
    'hi': 'पहले सर्वर QR कोड स्कैन करें।',
    'es': 'Escanea primero el QR del servidor.',
    'fr': 'Scannez d’abord le QR du serveur.'
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
    'tr': 'Önemli ses, hareket ve sistem notları burada sakin şekilde görünür.',
    'en': 'Important sound, motion, and system notes appear here calmly.',
    'zh': '重要声音、活动和系统提示会在这里平静显示。',
    'hi': 'ज़रूरी ध्वनि, हलचल और सिस्टम नोट यहाँ शांत ढंग से दिखते हैं।',
    'es':
        'Las notas importantes de sonido, movimiento y sistema aparecen aquí con calma.',
    'fr':
        'Les notes importantes de son, mouvement et système apparaissent ici calmement.'
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
        'Eşleşmiş bebek odası cihazı uyarı gönderdiğinde en önemli durum burada görünecek.',
    'en':
        'When the paired Server sends an alert, the most important status appears here.',
    'zh': '已配对婴儿房设备发送提醒时，最重要的状态会显示在这里。',
    'hi':
        'पेयर बच्चे के कमरे का डिवाइस अलर्ट भेजेगा तो सबसे महत्वपूर्ण स्थिति यहाँ दिखेगी।',
    'es':
        'Cuando el cuarto emparejado envíe una alerta, el estado más importante aparecerá aquí.',
    'fr':
        'Quand la chambre appairée enverra une alerte, l’état le plus important apparaîtra ici.'
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
        'Bildirim ve izleme davranışı burada kalır; sunucu portu veya yayın kontrolü yoktur.',
    'en':
        'Notification and watch behavior stays here; there are no server port or stream controls.',
    'zh': '通知和观看行为在这里设置；没有服务器端口或直播控制。',
    'hi':
        'सूचना और देखने का व्यवहार यहाँ रहता है; सर्वर पोर्ट या स्ट्रीम नियंत्रण नहीं हैं।',
    'es':
        'Aquí quedan notificaciones y vista; no hay puerto de servidor ni control del directo.',
    'fr':
        'Notifications et visionnage restent ici ; pas de port serveur ni contrôle de flux.'
  },
  'clientSettings': {
    'tr': 'Ebeveyn cihazı ayarları',
    'en': 'Client settings',
    'zh': '家长设备设置',
    'hi': 'अभिभावक डिवाइस सेटिंग्स',
    'es': 'Ajustes del dispositivo padre/madre',
    'fr': 'Réglages de l’appareil parent'
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
    'es': 'Sonido',
    'fr': 'Son'
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
        'सरल नियंत्रणों से शोर, गतिविधि, सूचनाएँ और जोड़ विकल्प प्रबंधित करें।',
    'es':
        'Gestiona ruido, movimiento, notificaciones e integraciones con controles simples.',
    'fr':
        'Gérez bruit, mouvement, notifications et intégrations avec des contrôles simples.'
  },
  'notificationCooldown': {
    'tr': 'Bildirim aralığı',
    'en': 'Notification cooldown',
    'zh': '通知冷却',
    'hi': 'सूचना विराम',
    'es': 'Pausa de notificaciones',
    'fr': 'Pause des notifications'
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
    'hi': 'जोड़ विकल्प',
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
    'tr': 'Ağ ölçülüyor; sunucu kaliteyi otomatik ayarlıyor.',
    'en': 'Network is measured; the Server adjusts quality automatically.',
    'zh': '正在测量网络；服务器会自动调整质量。',
    'hi': 'नेटवर्क मापा जा रहा है; सर्वर गुणवत्ता अपने-आप समायोजित करता है।',
    'es': 'Se mide la red; el servidor ajusta la calidad automáticamente.',
    'fr': 'Le réseau est mesuré ; le serveur ajuste la qualité automatiquement.'
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
    'tr': 'Sunucu cihaz ve Wi‑Fi durumuna göre profili seçer.',
    'en': 'The Server chooses a profile based on device age and Wi‑Fi state.',
    'zh': '服务器会根据设备新旧和 Wi‑Fi 状态选择配置。',
    'hi': 'सर्वर डिवाइस और Wi‑Fi स्थिति के आधार पर प्रोफ़ाइल चुनता है।',
    'es': 'El servidor elige perfil según dispositivo y estado Wi‑Fi.',
    'fr': 'Le serveur choisit un profil selon l’appareil et l’état Wi‑Fi.'
  },
  'audioMetric': {
    'tr': 'Ses: {value}',
    'en': 'Audio: {value}',
    'zh': '声音：{value}',
    'hi': 'ऑडियो: {value}',
    'es': 'Sonido: {value}',
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
    'hi': 'बहुत अच्छी',
    'es': 'Excelente',
    'fr': 'Très bon'
  },
  'netGood': {
    'tr': 'İyi',
    'en': 'Good',
    'zh': '良好',
    'hi': 'अच्छी',
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
    'tr': 'Kamera, mikrofon ve WebSocket sunucu alanında izlenir.',
    'en': 'Camera, microphone, and WebSocket are monitored in the Server area.',
    'zh': '摄像头、麦克风和 WebSocket 在服务器区域监控。',
    'hi': 'कैमरा, माइक्रोफ़ोन और WebSocket सर्वर क्षेत्र में देखे जाते हैं।',
    'es': 'Cámara, micrófono y WebSocket se vigilan en el área del servidor.',
    'fr': 'Caméra, micro et WebSocket sont suivis dans la zone serveur.'
  },
  'serverSettings': {
    'tr': 'Sunucu ayarları',
    'en': 'Server settings',
    'zh': '服务器设置',
    'hi': 'सर्वर सेटिंग्स',
    'es': 'Ajustes del servidor',
    'fr': 'Réglages du serveur'
  },
  'serverSettingsSubtitle': {
    'tr':
        'Eşikler, bildirim aralığı ve teknik davranış yalnızca bebek odası cihazını etkiler.',
    'en':
        'Thresholds, cooldown, and technical behavior affect only the baby room device.',
    'zh': '阈值、冷却和技术行为只影响婴儿房设备。',
    'hi':
        'सीमाएँ, सूचना विराम और तकनीकी व्यवहार केवल बच्चे के कमरे के डिवाइस को प्रभावित करते हैं।',
    'es':
        'Umbrales, pausas y comportamiento técnico solo afectan al dispositivo de la habitación.',
    'fr':
        'Seuils, pause de notifications et comportement technique n’affectent que l’appareil de la chambre.'
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
    'tr': 'Ebeveyn cihazı bağlı',
    'en': 'Client connected',
    'zh': '家长设备已连接',
    'hi': 'पैरेंट डिवाइस जुड़ा',
    'es': 'Dispositivo padre conectado',
    'fr': 'Appareil parent connecté'
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
    'es': 'Fallo',
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
    'fr': '{count} parent(s) connecté(s)'
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
    'tr': 'Ebeveyn cihazı sayısı',
    'en': 'Client count',
    'zh': '客户端数量',
    'hi': 'क्लाइंट संख्या',
    'es': 'Número de clientes',
    'fr': 'Nombre de clients'
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
    'tr': '{count} olay bağlantısı',
    'en': '{count} event client(s)',
    'zh': '{count} 个事件连接',
    'hi': '{count} घटना कनेक्शन',
    'es': '{count} conexión de eventos',
    'fr': '{count} connexion événement'
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
    'fr': 'Parent connecté'
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
    'fr': 'À noter',
  },
  'info': {
    'tr': 'Bilgi',
    'en': 'Info',
    'zh': '信息',
    'hi': 'जानकारी',
    'es': 'Información',
    'fr': 'Information',
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
    'tr': 'Ağlama sesi',
    'en': 'Crying sound',
    'zh': '哭声提示',
    'hi': 'रोने की आवाज़',
    'es': 'Sonido de llanto',
    'fr': 'Son de pleurs',
  },
  'cryDetectedText': {
    'tr': 'Bebeğinizden ağlama benzeri bir ses geldi.',
    'en': 'A cry-like sound came from the baby room.',
    'zh': '宝宝房传来类似哭声。',
    'hi': 'बच्चे के कमरे से रोने जैसी आवाज़ आई।',
    'es': 'Llegó un sonido parecido al llanto desde la habitación.',
    'fr': 'Un son proche de pleurs vient de la chambre.',
  },
  'motionDetectedTitle': {
    'tr': 'Hareket notu',
    'en': 'Motion note',
    'zh': '活动提示',
    'hi': 'हलचल नोट',
    'es': 'Nota de movimiento',
    'fr': 'Note de mouvement',
  },
  'motionDetectedText': {
    'tr': 'Bebek odasında hafif bir hareket fark edildi.',
    'en': 'Gentle movement was noticed in the baby room.',
    'zh': '宝宝房里注意到轻微活动。',
    'hi': 'बच्चे के कमरे में हल्की हलचल दिखी।',
    'es': 'Se notó un movimiento suave en la habitación.',
    'fr': 'Un léger mouvement a été remarqué dans la chambre.',
  },
  'temperatureWarningTitle': {
    'tr': 'Sıcaklık kontrolü',
    'en': 'Temperature check',
    'zh': '温度检查',
    'hi': 'तापमान जाँच',
    'es': 'Revisión de temperatura',
    'fr': 'Contrôle température',
  },
  'temperatureWarningText': {
    'tr': 'Oda sıcaklığı biraz yükseldi; konforu kontrol edin.',
    'en': 'Room temperature is a little higher; check comfort.',
    'zh': '房间温度略高；请确认舒适度。',
    'hi': 'कमरे का तापमान थोड़ा बढ़ा है; आराम जाँचें।',
    'es': 'La temperatura subió un poco; revisa la comodidad.',
    'fr': 'La température a un peu monté ; vérifiez le confort.',
  },
  'connectionRenewedTitle': {
    'tr': 'Bağlantı iyi',
    'en': 'Connection is good',
    'zh': '连接正常',
    'hi': 'कनेक्शन ठीक है',
    'es': 'Conexión correcta',
    'fr': 'Connexion correcte',
  },
  'connectionRenewedText': {
    'tr': 'Bebek odası cihazı yeniden düzenli görünüyor.',
    'en': 'The baby room device looks steady again.',
    'zh': '宝宝房设备看起来已恢复稳定。',
    'hi': 'बच्चे के कमरे का डिवाइस फिर स्थिर दिख रहा है।',
    'es': 'El dispositivo de la habitación vuelve a verse estable.',
    'fr': 'L’appareil de la chambre semble stable à nouveau.',
  },
  'humidityNormalTitle': {
    'tr': 'Nem dengede',
    'en': 'Humidity is steady',
    'zh': '湿度稳定',
    'hi': 'नमी स्थिर है',
    'es': 'Humedad estable',
    'fr': 'Humidité stable',
  },
  'humidityNormalText': {
    'tr': 'Oda havası beklenen aralıkta görünüyor.',
    'en': 'Room air looks within the expected range.',
    'zh': '房间空气看起来在预期范围内。',
    'hi': 'कमरे की हवा अपेक्षित सीमा में दिख रही है।',
    'es': 'El aire de la habitación está dentro de lo esperado.',
    'fr': 'L’air de la chambre semble dans la plage attendue.',
  },
  'notificationsManageText': {
    'tr': 'Bildirimlerin ne zaman ve nasıl görüneceğini ayarlayın.',
    'en': 'Choose when and how notifications appear.',
    'zh': '选择通知何时以及如何显示。',
    'hi': 'सूचनाएँ कब और कैसे दिखें, यह चुनें।',
    'es': 'Elige cuándo y cómo aparecen las notificaciones.',
    'fr': 'Choisissez quand et comment les notifications apparaissent.',
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
        'Sunucu ayarları bu cihazda gösterilmez. Sunucu yönetimi için bebek odası cihazını kullanın.',
    'en':
        'Server settings are not shown on this device. Use the server device to manage them.',
    'zh': '此设备不显示服务器设置。请使用服务器设备进行管理。',
    'hi':
        'इस डिवाइस पर सर्वर सेटिंग्स नहीं दिखतीं। प्रबंधन के लिए सर्वर डिवाइस इस्तेमाल करें।',
    'es':
        'Los ajustes del servidor no se muestran en este dispositivo. Usa el dispositivo servidor para gestionarlos.',
    'fr':
        'Les réglages du serveur ne sont pas affichés sur cet appareil. Utilisez l’appareil serveur pour les gérer.',
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
