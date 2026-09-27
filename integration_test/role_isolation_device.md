# Android cihazda mod izolasyonu testi

Bu test gerçek AppBootstrap, kamera, mikrofon, foreground service ve iki yönlü
ekran geçişlerini kullanır. İki Client → Server → Client döngüsünde kaynak
durumunu doğrular; görüntü veya sesi kaydetmez ve dışarı aktarmaz. Dart tarafındaki
ayar ve token yazıları bellekte tutulur. Mağaza akışı test derlemesinde kapalıdır.

## Runner ve kurulum

**Düz `flutter drive` komutunu kullanmayın.** Flutter'ın varsayılan driver
temizliği uygulamayı kaldırır ve kurulu uygulamanın verisini siler. Bellekteki
SharedPreferences/secure-storage test verisi buna karşı koruma sağlamaz.
`--keep-app-running` kapanıştaki kaldırmayı önler; Flutter'ın kurulum hatasında
uygulamayı kaldırıp tekrar kurma yolunu tek başına önlemez.

Bu nedenle mevcut uygulamaya bağlanın. Önemli kullanıcı verisi bulunan bir
cihazda önce cihazın uygun veri yedeği/geri yükleme yöntemini doğrulayın; test
cihazı veya emülatör tercih edin. APK kurulum başarısızlığını kaldırma veya veri
temizleme ile çözmeyin.

1. Test APK'sını cihazı değiştirmeden derleyin:

   ```sh
   flutter build apk --debug \
     --target=integration_test/role_isolation_device_test.dart \
     --dart-define=MIUCAM_BROADCAST_PAYWALL_ENABLED=false
   ```

2. Seçilen cihazda APK'yı yalnız güncelleme kurulumuyla yükleyin; komut başarısız
   olursa durun:

   ```sh
   adb -s DEVICE_SERIAL install -r -t build/app/outputs/flutter-apk/app-debug.apk
   ```

3. Kamera ve mikrofon izinlerini cihaz sahibinin onayı kapsamında hazırlayın.
   Test Flutter ekranlarını kullanır; Android'in izin diyaloğuna otomatik
   dokunmaz. Önceden izin verilmiş test cihazında bu iki izin şöyle kurulabilir:

   ```sh
   adb -s DEVICE_SERIAL shell pm grant com.miucam.app android.permission.CAMERA
   adb -s DEVICE_SERIAL shell pm grant com.miucam.app android.permission.RECORD_AUDIO
   adb -s DEVICE_SERIAL shell am start -n com.miucam.app/.MainActivity \
     --ez start-paused true --ez enable-dart-profiling true \
     --ez enable-checked-mode true --ez verify-entry-points true
   ```

4. Bu uygulama sürecinin logundan Dart VM service URI'sini bulun. URI içindeki
   cihaz portunu `adb forward tcp:0 tcp:DEVICE_VM_PORT` ile yönlendirin; dönen
   host portunu kullanın ve URI'nin oturum yolunu koruyun. Ardından yalnız
   mevcut uygulamaya bağlanın:

   ```sh
   flutter drive -d DEVICE_SERIAL \
     --driver=test_driver/role_isolation_device_driver.dart \
     --use-existing-app=http://127.0.0.1:HOST_PORT/VM_SESSION_PATH/ \
     --keep-app-running
   ```

   Bu komut uygulamayı derlemez, yeniden kurmaz veya test sonunda kaldırmaz.

5. Sonuç `build/device_validation/role_isolation_device.json` dosyasındadır.
   Her iki döngü `passed: true`, son native durum tamamen boş olmalıdır.
   Testten sonra normal `lib/main.dart` APK'sını varsayılan özelliklerle
   yeniden derleyip `adb install -r` ile geri yükleyin; test derlemesini günlük
   kullanım için cihazda bırakmayın. Açılan adb port yönlendirmesini kaldırın.

2026-09-27 doğrulamasında varsayılan driver temizliğinin kurulu uygulamayı
kaldırdığı gözlendi. Bu iş akışı, in-memory test ayarlarının cihaz verisini
koruduğu yönünde yanlış bir güvence vermemek için mevcut-app bağlantısını
zorunlu tutar.
