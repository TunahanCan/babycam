// Purchase and room activation are separate steps of one family license.
const appPurchaseTextCatalog = <String, Map<String, String>>{
  'familyLicenseRoom': {
    'tr': '{room} · Aile lisansı',
    'en': '{room} · Family license',
    'zh': '{room} · 家庭许可',
    'hi': '{room} · परिवार लाइसेंस',
    'es': '{room} · Licencia familiar',
    'fr': '{room} · Licence familiale',
    'de': '{room} · Familienlizenz',
    'ar': '{room} · ترخيص العائلة',
  },
  'familyPurchaseExplanation': {
    'tr':
        'Bu ebeveyn telefonundan bir kez satın al; aile lisansını eşleştirdiğin oda telefonlarında kullan. Abonelik yok. Oda başına en fazla 5 eşzamanlı izleyici.',
    'en':
        'Buy once on this parent phone and use your family license on paired room phones. No subscription. Up to 5 viewers per room at once.',
    'zh': '在此家长手机购买一次，即可在已配对的房间手机上使用家庭许可。无需订阅，每个房间最多同时支持5位观看者。',
    'hi':
        'इस अभिभावक फ़ोन पर एक बार खरीदें और जुड़े कमरे के फ़ोन पर परिवार लाइसेंस इस्तेमाल करें। कोई सदस्यता नहीं। हर कमरे में एक साथ अधिकतम 5 दर्शक।',
    'es':
        'Compra una vez desde este móvil y usa tu licencia familiar en los móviles de habitación vinculados. Sin suscripción. Hasta 5 espectadores por habitación a la vez.',
    'fr':
        'Achetez une fois sur ce téléphone parent et utilisez votre licence familiale sur les téléphones de chambre associés. Sans abonnement. Jusqu’à 5 spectateurs par chambre.',
    'de':
        'Einmal auf diesem Elterntelefon kaufen und die Familienlizenz auf gekoppelten Zimmertelefonen nutzen. Kein Abo. Bis zu 5 gleichzeitige Zuschauer pro Zimmer.',
    'ar':
        'اشترِ مرة واحدة من هاتف الوالدين واستخدم ترخيص العائلة على هواتف الغرف المقترنة. بلا اشتراك. حتى 5 مشاهدين لكل غرفة في الوقت نفسه.',
  },
  'familyPurchase': {
    'tr': 'Aile lisansını satın al',
    'en': 'Buy family license',
    'zh': '购买家庭许可',
    'hi': 'परिवार लाइसेंस खरीदें',
    'es': 'Comprar licencia familiar',
    'fr': 'Acheter la licence familiale',
    'de': 'Familienlizenz kaufen',
    'ar': 'شراء ترخيص العائلة',
  },
  'familyPurchasePrice': {
    'tr': 'Aile lisansı · {price}',
    'en': 'Family license · {price}',
    'zh': '家庭许可 · {price}',
    'hi': 'परिवार लाइसेंस · {price}',
    'es': 'Licencia familiar · {price}',
    'fr': 'Licence familiale · {price}',
    'de': 'Familienlizenz · {price}',
    'ar': 'ترخيص العائلة · {price}',
  },
  'familyPurchaseProcessing': {
    'tr':
        'Mağaza işlemi ve satın alma doğrulaması tamamlanıyor. Bu ekrandan ayrılsan da işlem seçilen odaya bağlı kalır.',
    'en':
        'Completing the store transaction and verifying your purchase. The selected room remains the destination if you leave this screen.',
    'zh': '正在完成商店交易并验证购买。即使离开此屏幕，所选房间仍是激活目标。',
    'hi':
        'स्टोर लेनदेन और खरीद सत्यापन जारी है। यह स्क्रीन छोड़ने पर भी चुना गया कमरा ही सक्रिय होगा।',
    'es':
        'Completando la transacción y verificando la compra. La habitación elegida seguirá siendo el destino aunque salgas de esta pantalla.',
    'fr':
        'Transaction et vérification en cours. La chambre sélectionnée reste la destination même si vous quittez cet écran.',
    'de':
        'Store-Transaktion und Kaufprüfung laufen. Das gewählte Zimmer bleibt das Ziel, auch wenn du diesen Bildschirm verlässt.',
    'ar':
        'جارٍ إكمال عملية المتجر والتحقق من الشراء. تبقى الغرفة المختارة هي الوجهة حتى عند مغادرة هذه الشاشة.',
  },
  'familyPurchasePending': {
    'tr':
        'Mağaza onayı bekleniyor. Yeniden ödeme yapma; onay gelince lisans bu odaya uygulanacak.',
    'en':
        'Waiting for store approval. Do not pay again; the license will be applied to this room after approval.',
    'zh': '等待商店批准。请勿再次付款；批准后将为此房间激活许可。',
    'hi':
        'स्टोर की मंज़ूरी का इंतज़ार है। फिर भुगतान न करें; मंज़ूरी के बाद इस कमरे में लाइसेंस सक्रिय होगा।',
    'es':
        'Esperando la aprobación de la tienda. No vuelvas a pagar; la licencia se aplicará a esta habitación tras la aprobación.',
    'fr':
        'En attente de l’accord de la boutique. Ne payez pas à nouveau ; la licence sera appliquée à cette chambre après validation.',
    'de':
        'Die Store-Freigabe steht aus. Nicht erneut bezahlen; danach wird die Lizenz auf dieses Zimmer angewendet.',
    'ar':
        'بانتظار موافقة المتجر. لا تدفع مجددًا؛ سيُفعّل الترخيص لهذه الغرفة بعد الموافقة.',
  },
  'familyVerificationPending': {
    'tr':
        'Satın alma henüz doğrulanamadı. Yeniden ödeme yapma. İnternet bağlantını kontrol edip satın almayı geri yükle.',
    'en':
        'Your purchase has not been verified yet. Do not pay again. Check your internet connection and restore the purchase.',
    'zh': '购买尚未验证。请勿再次付款。请检查互联网连接并恢复购买。',
    'hi':
        'खरीद अभी सत्यापित नहीं हुई है। फिर भुगतान न करें। इंटरनेट जाँचें और खरीदारी बहाल करें।',
    'es':
        'La compra aún no está verificada. No vuelvas a pagar. Comprueba internet y restaura la compra.',
    'fr':
        'L’achat n’est pas encore vérifié. Ne payez pas à nouveau. Vérifiez internet et restaurez l’achat.',
    'de':
        'Der Kauf ist noch nicht bestätigt. Nicht erneut bezahlen. Internetverbindung prüfen und Kauf wiederherstellen.',
    'ar':
        'لم يتم التحقق من الشراء بعد. لا تدفع مجددًا. تحقّق من اتصال الإنترنت واستعد عملية الشراء.',
  },
  'familyLicenseActivating': {
    'tr': 'Lisans oda telefonunda etkinleştiriliyor…',
    'en': 'Activating the license on the room phone…',
    'zh': '正在房间手机上激活许可…',
    'hi': 'कमरे के फ़ोन पर लाइसेंस सक्रिय हो रहा है…',
    'es': 'Activando la licencia en el móvil de la habitación…',
    'fr': 'Activation de la licence sur le téléphone de la chambre…',
    'de': 'Lizenz wird auf dem Zimmertelefon aktiviert…',
    'ar': 'جارٍ تفعيل الترخيص على هاتف الغرفة…',
  },
  'familyActivationPending': {
    'tr':
        'Satın alma kaydedildi; oda aktivasyonu bekliyor. Oda telefonu tekrar bağlandığında yeniden denenecek. Tekrar ödeme alınmaz.',
    'en':
        'Your purchase is saved; room activation is pending. We will retry when the room phone reconnects. You will not be charged again.',
    'zh': '购买已保存，等待房间激活。房间手机重新连接后会重试，不会再次收费。',
    'hi':
        'खरीद सुरक्षित है; कमरे का सक्रियण बाकी है। कमरे का फ़ोन फिर जुड़ने पर दोबारा कोशिश होगी। फिर शुल्क नहीं लिया जाएगा।',
    'es':
        'La compra está guardada; falta activar la habitación. Se reintentará al reconectar el móvil. No se cobrará de nuevo.',
    'fr':
        'L’achat est enregistré ; la chambre attend son activation. Nouvelle tentative à la reconnexion du téléphone, sans nouveau paiement.',
    'de':
        'Der Kauf ist gespeichert; die Zimmeraktivierung steht aus. Bei erneuter Verbindung wird es nochmals versucht. Ohne weitere Zahlung.',
    'ar':
        'تم حفظ الشراء؛ تفعيل الغرفة قيد الانتظار. سنعيد المحاولة عند اتصال هاتف الغرفة. لن تدفع مجددًا.',
  },
  'familyActivateRoom': {
    'tr': 'Lisansı bu odada kullan',
    'en': 'Use license in this room',
    'zh': '在此房间使用许可',
    'hi': 'इस कमरे में लाइसेंस इस्तेमाल करें',
    'es': 'Usar licencia en esta habitación',
    'fr': 'Utiliser la licence dans cette chambre',
    'de': 'Lizenz in diesem Zimmer nutzen',
    'ar': 'استخدام الترخيص في هذه الغرفة',
  },
  'familyLicenseActive': {
    'tr':
        'Bu odada ömür boyu yayın açık. Lisans eşleştirdiğin diğer oda telefonlarında da kullanılabilir. Oda başına en fazla 5 eşzamanlı izleyici.',
    'en':
        'Lifetime broadcasting is active in this room. Your license can also be used on other paired room phones. Up to 5 viewers per room at once.',
    'zh': '此房间已永久启用直播。许可也可用于其他已配对的房间手机。每个房间最多同时支持5位观看者。',
    'hi':
        'इस कमरे में आजीवन प्रसारण सक्रिय है। लाइसेंस अन्य जुड़े कमरे के फ़ोन पर भी इस्तेमाल हो सकता है। हर कमरे में एक साथ अधिकतम 5 दर्शक।',
    'es':
        'La emisión de por vida está activa aquí. La licencia también sirve para otros móviles de habitación vinculados. Hasta 5 espectadores por habitación.',
    'fr':
        'La diffusion à vie est active ici. La licence est aussi utilisable sur les autres téléphones de chambre associés. Jusqu’à 5 spectateurs par chambre.',
    'de':
        'Die Übertragung ist hier dauerhaft freigeschaltet. Die Lizenz gilt auch für weitere gekoppelte Zimmertelefone. Bis zu 5 Zuschauer pro Zimmer.',
    'ar':
        'البث مدى الحياة مفعّل في هذه الغرفة. يمكن استخدام الترخيص أيضًا على هواتف الغرف المقترنة الأخرى. حتى 5 مشاهدين لكل غرفة.',
  },
  'familyRestoreRequired': {
    'tr':
        'Bu telefonda önceki satın alma bulundu. Oda telefonunda kullanmak için satın almayı geri yükle; yeniden satın alma gerekmez.',
    'en':
        'A previous purchase was found on this phone. Restore it to use it on the room phone; you do not need to buy again.',
    'zh': '此手机上发现以前的购买。请恢复购买以在房间手机上使用，无需再次购买。',
    'hi':
        'इस फ़ोन पर पिछली खरीद मिली है। कमरे के फ़ोन पर उपयोग के लिए उसे बहाल करें; फिर खरीदने की ज़रूरत नहीं।',
    'es':
        'Se encontró una compra anterior en este móvil. Restáurala para usarla en la habitación; no necesitas comprar otra vez.',
    'fr':
        'Un achat précédent a été trouvé sur ce téléphone. Restaurez-le pour la chambre, sans racheter.',
    'de':
        'Ein früherer Kauf wurde gefunden. Stelle ihn für das Zimmertelefon wieder her; ein erneuter Kauf ist nicht nötig.',
    'ar':
        'عُثر على شراء سابق على هذا الهاتف. استعده لاستخدامه على هاتف الغرفة؛ لا حاجة للشراء مجددًا.',
  },
  'familyPurchaseUnavailable': {
    'tr':
        'Satın alma veya oda aktivasyonu şu anda kullanılamıyor. İnternet ve oda bağlantısını kontrol edip tekrar dene. Ödeme başlatılmadı.',
    'en':
        'Purchase or room activation is currently unavailable. Check the internet and room connection, then retry. Checkout has not started.',
    'zh': '目前无法购买或激活房间。请检查互联网及房间连接后重试。尚未开始付款。',
    'hi':
        'खरीद या कमरे का सक्रियण अभी उपलब्ध नहीं है। इंटरनेट और कमरे का कनेक्शन जाँचकर फिर कोशिश करें। भुगतान शुरू नहीं हुआ।',
    'es':
        'La compra o activación no está disponible. Comprueba internet y la conexión con la habitación e inténtalo de nuevo. No se ha iniciado el pago.',
    'fr':
        'Achat ou activation indisponible. Vérifiez internet et la connexion à la chambre, puis réessayez. Le paiement n’a pas commencé.',
    'de':
        'Kauf oder Zimmeraktivierung derzeit nicht verfügbar. Internet- und Zimmerverbindung prüfen und erneut versuchen. Die Zahlung wurde nicht gestartet.',
    'ar':
        'الشراء أو تفعيل الغرفة غير متاح حاليًا. تحقّق من الإنترنت واتصال الغرفة ثم أعد المحاولة. لم يبدأ الدفع.',
  },
  'familyLicenseRevoked': {
    'tr':
        'Mağaza satın almayı iade veya iptal etti; aile lisansı artık etkin değil. Bir hata olduğunu düşünüyorsan satın almayı geri yükle.',
    'en':
        'The store refunded or revoked the purchase; the family license is no longer active. Restore the purchase if this seems incorrect.',
    'zh': '商店已退款或撤销购买，家庭许可已失效。如有疑问，请恢复购买。',
    'hi':
        'स्टोर ने खरीद का धनवापसी या निरस्तीकरण किया है; परिवार लाइसेंस अब सक्रिय नहीं है। अगर यह गलत लगता है, तो खरीदारी बहाल करें।',
    'es':
        'La tienda reembolsó o revocó la compra; la licencia familiar ya no está activa. Restaura la compra si crees que es un error.',
    'fr':
        'La boutique a remboursé ou révoqué l’achat ; la licence familiale n’est plus active. Restaurez l’achat si cela semble incorrect.',
    'de':
        'Der Store hat den Kauf erstattet oder widerrufen; die Familienlizenz ist nicht mehr aktiv. Stelle den Kauf wieder her, falls dies ein Fehler ist.',
    'ar':
        'أعاد المتجر مبلغ الشراء أو ألغاه؛ ترخيص العائلة لم يعد مفعّلًا. استعد الشراء إذا كنت تعتقد أن هذا خطأ.',
  },
  'familyRoomUpdateRequired': {
    'tr':
        'Lisansı bu odada kullanmak için oda telefonundaki MiuCam uygulamasını güncelle ve tekrar dene. Ödeme başlatılmadı.',
    'en':
        'Update MiuCam on the room phone to use the license here, then try again. Checkout has not started.',
    'zh': '请更新房间手机上的MiuCam后重试，以在此使用许可。尚未开始付款。',
    'hi':
        'यहाँ लाइसेंस इस्तेमाल करने के लिए कमरे के फ़ोन पर MiuCam अपडेट करके फिर कोशिश करें। भुगतान शुरू नहीं हुआ।',
    'es':
        'Actualiza MiuCam en el móvil de la habitación para usar la licencia aquí y vuelve a intentarlo. No se ha iniciado el pago.',
    'fr':
        'Mettez à jour MiuCam sur le téléphone de la chambre pour y utiliser la licence, puis réessayez. Le paiement n’a pas commencé.',
    'de':
        'Aktualisiere MiuCam auf dem Zimmertelefon, um die Lizenz dort zu nutzen, und versuche es erneut. Die Zahlung wurde nicht gestartet.',
    'ar':
        'حدّث MiuCam على هاتف الغرفة لاستخدام الترخيص فيها، ثم حاول مجددًا. لم يبدأ الدفع.',
  },
  'familyNoPurchaseFound': {
    'tr':
        'Bu mağaza hesabında geri yüklenecek aile lisansı bulunamadı. Satın aldığın mağaza hesabıyla oturum açıp tekrar dene.',
    'en':
        'No family license was found in this store account. Sign in with the store account you used to purchase, then try again.',
    'zh': '此商店账户中未找到家庭许可。请登录购买时使用的商店账户后重试。',
    'hi':
        'इस स्टोर खाते में परिवार लाइसेंस नहीं मिला। जिस स्टोर खाते से खरीदारी की थी उससे साइन इन करके फिर कोशिश करें।',
    'es':
        'No se encontró una licencia familiar en esta cuenta de la tienda. Inicia sesión con la cuenta que usaste para comprar y vuelve a intentarlo.',
    'fr':
        'Aucune licence familiale trouvée sur ce compte de boutique. Connectez-vous au compte utilisé pour l’achat, puis réessayez.',
    'de':
        'In diesem Store-Konto wurde keine Familienlizenz gefunden. Melde dich mit dem beim Kauf verwendeten Konto an und versuche es erneut.',
    'ar':
        'لم يُعثر على ترخيص عائلة في حساب المتجر هذا. سجّل الدخول بحساب المتجر المستخدم للشراء ثم حاول مجددًا.',
  },
  'familyPurchaseFailed': {
    'tr':
        'İşlem tamamlanamadı. Mağazada ödeme yaptıysan yeniden satın alma; satın almayı geri yükle.',
    'en':
        'The operation could not be completed. If you paid in the store, restore the purchase instead of buying again.',
    'zh': '操作未完成。如果已在商店付款，请恢复购买，不要再次购买。',
    'hi':
        'प्रक्रिया पूरी नहीं हुई। अगर स्टोर में भुगतान हो गया है, फिर खरीदने के बजाय खरीदारी बहाल करें।',
    'es':
        'No se pudo completar. Si pagaste en la tienda, restaura la compra en vez de volver a comprar.',
    'fr':
        'L’opération n’a pas abouti. Si vous avez payé dans la boutique, restaurez l’achat au lieu de racheter.',
    'de':
        'Der Vorgang wurde nicht abgeschlossen. Falls du bezahlt hast, stelle den Kauf wieder her, statt erneut zu kaufen.',
    'ar':
        'تعذّر إكمال العملية. إذا دفعت في المتجر، استعد الشراء بدلًا من الشراء مجددًا.',
  },
};
