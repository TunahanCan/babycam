package com.example.babycam


import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.PowerManager
import android.util.Log
import android.hardware.camera2.CameraCharacteristics
import androidx.annotation.OptIn
import androidx.annotation.RequiresPermission
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import okhttp3.*
import java.io.IOException
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.util.Collections
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt

class BabyMonitorService : LifecycleService() {

    companion object {
        private const val TAG = "BabyMonitorService"
        private const val CHANNEL_ID = "baby_monitor_channel"
        private const val NOTIFICATION_ID = 1
        private const val PREFERRED_HOSTNAME = "localbabaycam.com"
    }

    private lateinit var cameraExecutor: ExecutorService
    private lateinit var audioExecutor: ExecutorService
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioRecord: AudioRecord? = null
    private val isAudioRecording = AtomicBoolean(false)
    private var liveStreamServer: LiveStreamServer? = null
    private var streamAddress: String? = null
    @Volatile private var lastFrameSentAt = 0L
    private val frameIntervalMs = 100L

    // HttpClient with proper timeout configuration
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .build()

    // Telegram Configuration from gradle.properties (BuildConfig)
    private val botToken: String
        get() = ConfigurationHelper.getTelegramBotToken(this)
    private val chatId: String
        get() = ConfigurationHelper.getTelegramChatId(this)

    // Hareket (görüntü) parametreleri - can be overridden from preferences
    private val motionThreshold: Double
        get() = ConfigurationHelper.getMotionThreshold(this)
    private val motionWindowMs: Long
        get() = ConfigurationHelper.getMotionWindowMs(this)
    private val motionMinDurationMs: Long
        get() = ConfigurationHelper.getMotionMinDurationMs(this)

    // Ses (ağlama benzeri) parametreleri
    private val sampleRate = 16000
    private val cryScoreThreshold: Double
        get() = ConfigurationHelper.getCryScoreThreshold(this)
    private val cryMinDurationMs: Long
        get() = ConfigurationHelper.getCryMinDurationMs(this)
    private val cryWindowMs: Long
        get() = ConfigurationHelper.getCryWindowMs(this)
    private val audioBitsPerSample = 16
    private val audioChannelCount = 1
    private val streamPort = 8080
    private val audioAnalyzer = AudioPatternAnalyzer(sampleRate)
    @Volatile private var cryScoreAboveThresholdSince = 0L
    @Volatile private var lastAudioDebugLog = 0L
    private val audioDebugIntervalMs = 5_000L

    @Volatile private var lastHighMotionTime = 0L
    @Volatile private var motionAboveThresholdSince = 0L
    @Volatile private var lastCryEventTime = 0L
    @Volatile private var lastNotifyTime = 0L
    private val notifyCooldownMs = 60_000L  // iki alarm arası min süre

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        AppLogBuffer.log("Baby monitor servisi başlatıldı.")

        cameraExecutor = Executors.newSingleThreadExecutor()
        audioExecutor = Executors.newSingleThreadExecutor()

        acquireWakeLock()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Başlatılıyor..."))

        startLiveStreamServer()
        try {
            startAudioCapture()
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission denied for audio capture", e)
            AppLogBuffer.log("Mikrofon izni reddedildi: ${e.message}")
        }
        startCameraAnalysis()

        sendTelegramMessage("👋 Merhaba! Baby monitor servisi başlatıldı.")
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy")
        AppLogBuffer.log("Baby monitor servisi durduruldu.")

        // Properly shutdown executors
        cameraExecutor.shutdownNow()
        audioExecutor.shutdownNow()
        try {
            if (!cameraExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                Log.w(TAG, "Camera executor did not terminate within timeout")
            }
            if (!audioExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                Log.w(TAG, "Audio executor did not terminate within timeout")
            }
        } catch (e: InterruptedException) {
            Log.e(TAG, "Error waiting for executor termination", e)
            Thread.currentThread().interrupt()
        }

        stopAudioCapture()
        stopLiveStreamServer()
        releaseWakeLock()

        // Close HttpClient dispatcher executor service
        try {
            httpClient.dispatcher.executorService.shutdown()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing HttpClient", e)
        }
    }

    // ---------------- KAMERA / HAREKET ----------------

    @OptIn(ExperimentalCamera2Interop::class)
    private fun startCameraAnalysis() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)

        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()

                val analysis = ImageAnalysis.Builder()
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also { useCase ->
                        useCase.setAnalyzer(
                            cameraExecutor,
                            MotionAnalyzer(
                                onMotionScore = { score -> handleMotionScore(score) },
                                onFrameEncoded = { jpeg -> handleVideoFrame(jpeg) }
                            )
                        )
                    }

                val cameraSelector = CameraSelector.Builder()
                    .requireLensFacing(CameraSelector.LENS_FACING_BACK)
                    .addCameraFilter { cameraInfos ->
                        val sortedCameras = cameraInfos
                            .filter {
                                try {
                                    val cameraInfo = Camera2CameraInfo.from(it)
                                    cameraInfo.getCameraCharacteristic(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK &&
                                            cameraInfo.getCameraCharacteristic(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS) != null
                                } catch (e: Exception) {
                                    Log.w(TAG, "Error filtering camera", e)
                                    false
                                }
                            }
                            .sortedBy {
                                try {
                                    Camera2CameraInfo.from(it)
                                        .getCameraCharacteristic(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                                        ?.minOrNull() ?: Float.MAX_VALUE
                                } catch (_: Exception) {
                                    Float.MAX_VALUE
                                }
                            }

                        val wideAngleCamera = sortedCameras.firstOrNull()

                        if (wideAngleCamera != null) {
                            Log.i(TAG, "En geniş açılı arka kamera başarıyla seçildi.")
                            listOf(wideAngleCamera)
                        } else {
                            Log.w(TAG, "Geniş açı lens bulunamadı, varsayılan arka kamera kullanılacak.")
                            val defaultBack = cameraInfos.firstOrNull {
                                try {
                                    Camera2CameraInfo.from(it).getCameraCharacteristic(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
                                } catch (_: Exception) {
                                    false
                                }
                            }
                            if (defaultBack != null) listOf(defaultBack) else emptyList()
                        }
                    }
                    .build()

                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(this, cameraSelector, analysis)
                AppLogBuffer.log("Hareket analizi için kamera akışı başlatıldı.")
            } catch (e: IllegalStateException) {
                Log.e(TAG, "Camera binding error - lifecycle state issue", e)
                AppLogBuffer.log("Kamera başlatılırken hata: Yaşam döngüsü sorunu")
            } catch (e: IOException) {
                Log.e(TAG, "Camera binding error - IO error", e)
                AppLogBuffer.log("Kamera başlatılırken hata: ${e.message}")
            } catch (_: Exception) {
                Log.e(TAG, "Camera binding failed with unexpected error")
                AppLogBuffer.log("Kamera başlatılırken beklenmeyen hata")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun handleMotionScore(score: Double) {
        val percent = (score * 100).coerceIn(0.0, 100.0)
        Log.d(TAG, "Hareket skoru: ${percent.roundToInt()}%")

        val now = System.currentTimeMillis()
        if (score > motionThreshold) {
            lastHighMotionTime = now
            if (motionAboveThresholdSince == 0L) {
                motionAboveThresholdSince = now
            }

            // Çok yüksek hareket varsa fuse'i tetikleyebilirsin (opsiyonel)
            if (score > motionThreshold * 2) {
                // Hem hareket hem de ses tarafındaki son durumlara hızlıca bakmak için
                // fuse mekanizmasını elle çağırıyoruz. Bu, kameradaki ani hareketleri
                // kaçırmamak adına hızlı tepki verir.
                smartDecisionFuse()
            } else if (now - motionAboveThresholdSince >= motionMinDurationMs) {
                // Ses tarafı sessiz olsa bile belirgin bir süre boyunca hareket varsa
                // bunu fuse mekanizmasına ileterek yalnızca video tabanlı bir uyarı üretiriz.
                smartDecisionFuse()
                motionAboveThresholdSince = now
            }
        } else {
            motionAboveThresholdSince = 0L
        }
    }

    private fun handleVideoFrame(jpeg: ByteArray) {
        val now = System.currentTimeMillis()
        if (now - lastFrameSentAt < frameIntervalMs) return
        lastFrameSentAt = now
        liveStreamServer?.pushVideoFrame(jpeg)
    }


    // ---------------- AKILLI KARAR FUSE (HAREKET + SES) ----------------

    @Synchronized
    private fun smartDecisionFuse() {
        val now = System.currentTimeMillis()

        // Bildirim spamini engelle
        if (now - lastNotifyTime < notifyCooldownMs) return

        // Hareket ve ağlama skorlarını belirli bir pencere içinde değerlendiriyoruz.
        // Böylece algoritma hem görsel hem işitsel ipuçlarını birleştirerek daha güvenilir
        // bir alarm üretir.
        val motionRecent = (now - lastHighMotionTime) <= motionWindowMs
        val cryRecent    = (now - lastCryEventTime)   <= cryWindowMs

        val reason: String? = when {
            motionRecent && cryRecent ->
                "Hem belirgin hareket hem de ağlama benzeri ses algılandı. Bebek muhtemelen uyandı/ağlıyor."
            motionRecent ->
                "Belirgin hareket algılandı (ses düşük)."
            cryRecent ->
                "Ağlama benzeri ses algılandı (hareket düşük)."
            else -> null
        }

        if (reason != null) {
            lastNotifyTime = now
            val msg = "👶 Baby monitor uyarısı: $reason"
            Log.d(TAG, "Telegram bildirimi: $msg")
            AppLogBuffer.log(msg)
            sendTelegramMessage(msg)
        }
    }

    private fun sendTelegramMessage(text: String) {
        if (botToken.isBlank() || chatId.isBlank()) {
            Log.w(TAG, "Bot token/chat id ayarlı değil, mesaj atılmıyor.")
            AppLogBuffer.log("Telegram bilgileri eksik. Bildirim gönderilemedi.")
            return
        }

        val url = "https://api.telegram.org/bot$botToken/sendMessage"
        val body = FormBody.Builder()
            .add("chat_id", chatId)
            .add("text", text)
            .build()

        val req = Request.Builder()
            .url(url)
            .post(body)
            .build()

        httpClient.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "Telegram hata: ${e.message}", e)
                AppLogBuffer.log("Telegram bildirimi gönderilemedi: ${e.message}")
            }

            override fun onResponse(call: Call, response: Response) {
                try {
                    response.use { resp ->
                        if (!resp.isSuccessful) {
                            val errorBody = resp.body?.string()
                            Log.e(
                                TAG,
                                "Telegram bildirimi gönderilemedi. code=${resp.code} body=${errorBody ?: "<empty>"}"
                            )
                            AppLogBuffer.log("Telegram bildirimi başarısız oldu. Kod: ${resp.code}")
                        } else {
                            Log.d(TAG, "Telegram bildirimi gönderildi. code=${resp.code}")
                            AppLogBuffer.log("Telegram bildirimi gönderildi.")
                        }
                    }
                } catch (e: IOException) {
                    Log.e(TAG, "Error reading telegram response", e)
                    AppLogBuffer.log("Telegram yanıtı okunamadı: ${e.message}")
                }
            }
        })
    }

    // ---------------- WAKELOCK + NOTIFICATION ----------------

    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "BabyCam::Wakelock"
        ).apply { acquire(10 * 60 * 1000L) }  // 10 minutes timeout
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
    }

    // ---------------- SES YAKALAMA ----------------

    @RequiresPermission(Manifest.permission.RECORD_AUDIO)
    private fun startAudioCapture() {
        val minBufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
            Log.e(TAG, "AudioRecord buffer hesaplanamadı")
            AppLogBuffer.log("Mikrofon tamponu hesaplanamadı.")
            return
        }

        val bufferSize = minBufferSize * 2
        val record = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord başlatılamadı")
            record.release()
            AppLogBuffer.log("Mikrofon başlatılamadı.")
            return
        }

        try {
            record.startRecording()
        } catch (e: IllegalStateException) {
            Log.e(TAG, "Failed to start audio recording", e)
            record.release()
            AppLogBuffer.log("Mikrofon kaydına başlanırken hata: ${e.message}")
            return
        }

        isAudioRecording.set(true)
        audioRecord = record
        AppLogBuffer.log("Mikrofon dinlemesi başlatıldı.")

        audioExecutor.execute {
            val shortBuffer = ShortArray(bufferSize / 2)
            while (isAudioRecording.get()) {
                val audioRecordRef = audioRecord ?: break
                val read = try {
                    audioRecordRef.read(shortBuffer, 0, shortBuffer.size)
                } catch (e: IllegalStateException) {
                    Log.e(TAG, "AudioRecord read error", e)
                    break
                }

                when {
                    read > 0 -> handleAudioChunk(shortBuffer, read)
                    read == AudioRecord.ERROR_INVALID_OPERATION -> {
                        Log.e(TAG, "AudioRecord ERROR_INVALID_OPERATION")
                        break
                    }
                }
            }
        }
    }

    private fun stopAudioCapture() {
        isAudioRecording.set(false)
        audioRecord?.let { record ->
            try {
                record.stop()
            } catch (e: IllegalStateException) {
                Log.w(TAG, "Error stopping audio record", e)
            }
            try {
                record.release()
            } catch (e: Exception) {
                Log.w(TAG, "Error releasing audio record", e)
            }
        }
        audioRecord = null
        AppLogBuffer.log("Mikrofon dinlemesi durduruldu.")
    }

    private fun handleAudioChunk(samples: ShortArray, length: Int) {
        // PCM kısa dizisini byte dizisine çevirip ağ üzerinden yayınlıyoruz. Ardından aynı
        // veriyi ses analizi pipeline'ına göndererek gerçek zamanlı değerlendirme yapıyoruz.
        val pcmBytes = samples.toPcmByteArray(length)
        liveStreamServer?.pushAudioChunk(pcmBytes)
        analyzeAudioLevels(samples, length)
    }

    private fun analyzeAudioLevels(samples: ShortArray, length: Int) {
        if (length <= 0) return
        val analysis = audioAnalyzer.analyze(samples, length)
        val now = System.currentTimeMillis()

        if (now - lastAudioDebugLog >= audioDebugIntervalMs) {
            lastAudioDebugLog = now
            val rmsDb = String.format(Locale.US, "%.1f", analysis.rmsDb)
            val bandBalance = String.format(Locale.US, "%.1f", analysis.bandBalanceDb)
            val score = String.format(Locale.US, "%.2f", analysis.smoothedScore)
            AppLogBuffer.log(
                "Ses analizi dB=$rmsDb cryBand=$bandBalance skor=$score"
            )
        }

        // ...existing code...
        if (analysis.smoothedScore >= cryScoreThreshold) {
            if (cryScoreAboveThresholdSince == 0L) {
                cryScoreAboveThresholdSince = now
            }
            if (now - cryScoreAboveThresholdSince >= cryMinDurationMs) {
                lastCryEventTime = now
                cryScoreAboveThresholdSince = now
                smartDecisionFuse()
            }
        } else {
            cryScoreAboveThresholdSince = 0L
        }
    }

    private fun ShortArray.toPcmByteArray(length: Int): ByteArray {
        val out = ByteArray(length * 2)
        var index = 0
        for (i in 0 until length) {
            val sample = this[i].toInt()
            out[index++] = (sample and 0xFF).toByte()
            out[index++] = ((sample shr 8) and 0xFF).toByte()
        }
        return out
    }

    // ---------------- CANLI YAYIN SUNUCUSU ----------------

    private fun startLiveStreamServer() {
        val server = LiveStreamServer(streamPort, sampleRate, audioChannelCount, audioBitsPerSample)
        liveStreamServer = server
        try {
            server.startServer()
            streamAddress = determineServerAddress()
            val addressText = streamAddress?.let { "Canlı yayın: http://$it" } ?: "Canlı yayın hazırlanıyor..."
            updateNotification(addressText)
            Log.i(TAG, "Canlı yayın sunucusu http://${streamAddress ?: "127.0.0.1:$streamPort"} adresinde hazır")
            streamAddress?.let { AppLogBuffer.log("Canlı yayın sunucusu hazır: http://$it") }
                ?: AppLogBuffer.log("Canlı yayın sunucusu hazırlanıyor...")
        } catch (e: IOException) {
            Log.e(TAG, "Canlı yayın sunucusu başlatılamadı", e)
            updateNotification("Canlı yayın sunucusu başlatılamadı")
            AppLogBuffer.log("Canlı yayın sunucusu başlatılamadı: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error starting live stream server", e)
            AppLogBuffer.log("Canlı yayın sunucusunda beklenmeyen hata: ${e.message}")
        }
    }

    private fun stopLiveStreamServer() {
        liveStreamServer?.stopServer()
        liveStreamServer = null
        AppLogBuffer.log("Canlı yayın sunucusu durduruldu.")
    }

    private fun determineServerAddress(): String? {
        return try {
            val localIpv4Addresses = mutableListOf<String>()
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return null
            val list = Collections.list(interfaces)
            list.forEach { networkInterface ->
                if (!networkInterface.isUp || networkInterface.isLoopback) return@forEach
                val addresses = Collections.list(networkInterface.inetAddresses)
                addresses.forEach { address ->
                    if (!address.isLoopbackAddress && address is Inet4Address) {
                        val hostAddress = address.hostAddress
                        if (hostAddress != null) {
                            localIpv4Addresses.add(hostAddress)
                        }
                    }
                }
            }
            if (localIpv4Addresses.isEmpty()) {
                return null
            }

            resolvePreferredHostname(localIpv4Addresses)?.let {
                AppLogBuffer.log("Özel alan adı bulundu: http://$it:$streamPort")
                return "$it:$streamPort"
            }

            val address = "${localIpv4Addresses.first()}:$streamPort"
            AppLogBuffer.log("Yerel IP kullanılıyor: http://$address")
            address
        } catch (e: IOException) {
            Log.e(TAG, "IO error getting server address", e)
            AppLogBuffer.log("IP adresi alınamadı: ${e.message}")
            null
        } catch (_: Exception) {
            Log.e(TAG, "Unexpected error determining server address")
            AppLogBuffer.log("IP adresi alınamadı")
            null
        }
    }

    private fun resolvePreferredHostname(localIps: List<String>): String? {
        val hostname = PREFERRED_HOSTNAME.trim()
        if (hostname.isEmpty()) return null
        return try {
            val resolved = InetAddress.getAllByName(hostname).mapNotNull { it.hostAddress }
            if (resolved.any { localIps.contains(it) }) hostname else null
        } catch (e: java.net.UnknownHostException) {
            Log.d(TAG, "Preferred hostname could not be resolved: $hostname", e)
            null
        } catch (e: Exception) {
            Log.w(TAG, "Unexpected error resolving preferred hostname", e)
            null
        }
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun createNotificationChannel() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val ch = NotificationChannel(
            CHANNEL_ID,
            "Baby Monitor",
            NotificationManager.IMPORTANCE_LOW
        )
        nm.createNotificationChannel(ch)
    }

    private fun buildNotification(text: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Baby Monitor Çalışıyor")
            .setContentText(text)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

}
