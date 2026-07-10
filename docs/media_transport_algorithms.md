# MimiCam Low-Latency Media Algorithms

Bu not, mevcut yerel HTTP/MJPEG/WAV protokolünü değiştirmeden uygulanan
düşük-gecikme kararlarını ve dayandıkları birincil kaynakları kaydeder.

## Uygulanan video politikası

- Kamera cihaz sınıfının güvenli tavan FPS değeriyle açılır; aktif profil
  `MediaFrameBudget` ile aşağı doğru pace edilir. Böylece kalite iyileştiğinde
  yalnız FPS değişimi için kamera teardown/restart gerekmez.
- iOS YUV420/NV12 ve BGRA8888 plane/stride düzenleri ayrı dönüştürülür.
- JPEG dönüşümü ana Dart isolate'ından kalıcı bir worker isolate'a taşınır.
  Plane byte'ları owned `TransferableTypedData` snapshot olarak aktarılır.
  Encoder meşgulse bekleyen tek slot yeni kareyle değiştirilir; eski görüntü
  kuyruğu birikmez.
- Aktif profil genişlik/yüksekliği encoder aşamasında uygulanır, aspect ratio
  korunur, upscale yapılmaz ve JPEG 4:2:0 chroma ile üretilir.
- Her client writer en fazla bir güncel kare bekletir. Yeni kare eski pending
  kareyi ezer.
- MJPEG parçaları sequence, capture time ve send time taşır. Client aynı ağ
  burst'ündeki yalnızca en yeni kareyi render eder.
- Client, saat offsetini minimum transit süresiyle çıkarıp relative queue delay
  ve RFC 3550 tipi 1/16 EWMA jitter üretir. TCP'nin aynı read chunk'ında
  birleştirdiği kareler gerçek sequence gap sayılmaz.
- Client JPEG decode bir aktif + bir latest-pending iş ile sınırlıdır. Kareler
  global Flutter `ImageCache`'e girmez; değiştirilen `ui.Image` handle'ı dispose
  edilir.

Bu davranış Apple'ın geç video karelerini işlemek yerine atma ve serial queue
uzunluğunu bir tutma önerisiyle uyumludur:

- [Apple TN2445: Handling Frame Drops with AVCaptureVideoDataOutput](https://developer.apple.com/library/archive/technotes/tn2445/_index.html)
- [RFC 3550: RTP interarrival jitter estimator](https://www.rfc-editor.org/rfc/rfc3550.html)
- [RFC 8698: NADA relative delay and congestion feedback](https://www.rfc-editor.org/rfc/rfc8698.html)
- [RFC 8298: queue-aware real-time media rate adaptation](https://www.rfc-editor.org/rfc/rfc8298.html)

## Uygulanan ses politikası

- Recorder'ın değişken chunk'ları 20 ms PCM16 frame'lere çevrilir. 16 kHz mono
  için her frame 320 sample / 640 byte'tır.
- Her server-client ses kuyruğu 160 ms ile sınırlıdır. Taşma veya 300 ms flush
  timeout durumunda metadata'sız WAV içinde gizli bir zaman atlaması bırakmak
  yerine yavaş bağlantı kapatılır; client temiz buffer ile reconnect eder.
- Client en az 60 ms ile başlar. Interarrival variation değeri için
  `J = J + (abs(D) - J) / 16` uygulanır; hedef gecikme 20 ms adımlarla en fazla
  220 ms'ye çıkar.
- Client native oynatıcıyı yaklaşık 80-100 ms high-water seviyesine kadar
  doldurur ve timer gecikmesinde eksik frame'leri toplu telafi eder. Böylece
  Dart/UI jank'i doğrudan native underrun'a dönüşmez. Toplam Dart buffer sert
  üst sınırı 320 ms'dir.
- iOS native yazma sonucu artık gerçek serial-queue kararından sonra döner ve
  yaklaşık 240 ms'den fazla eski sesi kabul etmez. Android sonucu gerçek ve
  eksiksiz `AudioTrack.write` tamamlanınca döner; internal queue playback head
  ile ölçülür.
- Alert, video ve audio reconnect döngüleri aynı exponential-backoff strategy
  kullanır; cap ve testte deterministic jitter injection ortaktır.

## Kontrol düzlemi bütçesi

- Aktif watch status RTT ölçümü saniyelik kalır.
- Aynı kalite seviyesindeki quality POST en fazla dört saniyede birdir; tier
  kötüleşmesi beklemeden rapor edilir.
- Battery platform sorguları server'da 15 saniye, client'ta 30 saniye TTL ile
  cache edilir ve eşzamanlı sorgular tek in-flight future'da birleşir.

## WebRTC H.264 + Opus pilotu

Mevcut MJPEG/WAV hattı korunurken opt-in pilot şu kararları uygular:

- Server ve client runtime capability probe'unda H.264 video ve Opus audio
  codec'i birlikte bulunmadan WebRTC capability yayınlanmaz.
- Unified-plan peer connection, BUNDLE ve RTCP mux kullanılır; H.264/Opus codec
  tercih listesinin başına alınır.
- Pilot tek peer ile sınırlıdır ve `iceServers` boş olduğu için local-LAN host
  ICE davranışıdır; TURN/relay veya internet NAT traversal iddiası yoktur.
- Offer/answer ve trickle ICE local HTTP signaling endpointlerinden, trusted
  Bearer ile aynı client'a ait kısa ömürlü stream token birlikte doğrulanarak
  taşınır.
- Capability veya negotiation başarısız olursa pilot session kapatılır ve yeni
  `mjpeg_wav` session açılır. Böylece başarısız peer ile legacy capture aynı
  logical session'da karışmaz.

Bu pilotun codec/transport ilkeleri için birincil kaynaklar:

- [RFC 8834: WebRTC media transport and codec requirements](https://www.rfc-editor.org/rfc/rfc8834.html)
- [RFC 7742: WebRTC video processing and codec requirements](https://www.rfc-editor.org/rfc/rfc7742.html)
- [RFC 7587: Opus RTP payload format](https://www.rfc-editor.org/rfc/rfc7587.html)

## Resource governor ve ölçüm politikası

- Native `mimicam/device_resources` thermal, low-power, charging ve battery
  snapshot üretir; 10 saniye cache ve tek in-flight future aynı platform
  sorgusunu çoğaltmaz.
- `MediaResourceGovernor` bu snapshot'ı network tier, transport backpressure,
  encode p95, pre-encode drop, decoder coalescing, underrun ve client load ile
  birleştirir.
- Karar `normal`, `constrained`, `survival` veya audio-demand varsa
  `audioOnly` olur. Legacy video tam kapanmak yerine 1 fps liveness karesiyle
  bağlantıyı korur.
- `MediaSessionTelemetry` her metric için en fazla 1.024 örnek tutar. Hot path
  yalnız O(1) sample/counter yazar; p50/p95/p99 sıralaması snapshot anında
  yapılır.
- Monotonic timestamp aynı cihazdaki span'ler, wire capture/send timestamp'i
  ise client relative transit/queue estimate'i içindir. Bu yaklaşım iki cihaz
  saati arasında mutlak senkronizasyon iddiası taşımaz.

Kaynaklar:

- [RFC 3551: packetized audio için varsayılan 20 ms interval](https://www.rfc-editor.org/rfc/rfc3551.html)
- [Ramjee et al.: Adaptive Playout Mechanisms for Packetized Audio](https://www.microsoft.com/en-us/research/?p=328670)
- [WebRTC NetEq jitter-buffer design](https://webrtc.googlesource.com/src/+/refs/heads/main/modules/audio_coding/neteq/g3doc/index.md)
- [Apple AVAudioPlayerNode buffer scheduling](https://developer.apple.com/documentation/avfaudio/avaudioplayernode)
- [Android AudioTrack buffer and underrun guidance](https://developer.android.com/reference/android/media/AudioTrack)

## Bilinen sınırlar

MJPEG ve WAV iki bağımsız TCP bağlantısında taşınmaya devam eder. TCP
retransmission sırasında head-of-line blocking yapar ve gönderilmiş eski video
byte'ları iptal edilemez. Sequence/timestamp telemetrisi sorunu görünür ve
adaptif hale getirir, fakat UDP tabanlı RTP/WebRTC kadar ileri kayıp kurtarma ve
A/V sync sağlamaz. WebRTC pilotu bu sonraki adımın kontrollü deneyidir; tek peer,
host ICE ve opt-in kapsamı nedeniyle default MJPEG/WAV yolunun yerine geçmiş
sayılmaz.

Pilot `getUserMedia` track'lerini gateway içinde sahiplenir. Legacy
`MediaRuntimeController` camera/microphone demand ve platform background
sözleşmesinin pilot track'lerinde de aynı sonucu verdiği, fiziksel Android/iOS
cihazlarda background/foreground, call interruption, route change, thermal ve
network impairment matrisinde doğrulanmalıdır.
