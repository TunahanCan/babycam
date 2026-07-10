package com.example.mimicam

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import androidx.lifecycle.LifecycleService
import io.flutter.embedding.engine.FlutterEngine

class MimiCamForegroundService : LifecycleService() {
    private var wifiLock: WifiManager.WifiLock? = null
    private var ownedEngine: FlutterEngine? = null
    private var mediaCapture: MimiCamServiceMediaCapture? = null
    private var cameraDemand = false
    private var microphoneDemand = false
    private var playbackDemand = false
    private var nativeCameraCaptureDemand = false
    private var nativeMicrophoneCaptureDemand = false
    private var foregroundStarted = false
    private var runtimeReleased = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // LifecycleService requires this call so CameraX observes a STARTED
        // service lifecycle even after FlutterActivity detaches.
        super.onStartCommand(intent, flags, startId)
        val action = intent?.action
        when (action) {
            ACTION_STOP -> {
                stopRuntime("requested")
                return START_NOT_STICKY
            }
            ACTION_UPDATE,
            ACTION_START -> Unit
            else -> {
                // A process-restarted sticky service cannot safely regain Android's
                // while-in-use camera/microphone permissions in the background.
                stopRuntime("process_recovery_requires_foreground")
                return START_NOT_STICKY
            }
        }

        if (
            action == ACTION_UPDATE &&
            !foregroundStarted &&
            !MimiCamPlatformRuntime.canStartWhileInUseForegroundService
        ) {
            MimiCamPlatformRuntime.setForegroundServiceFailure(
                "update_requires_visible_activity"
            )
            stopRuntime("update_requires_visible_activity")
            return START_NOT_STICKY
        }

        val engine = MimiCamEngineOwner.claimForService()
        if (engine == null || !engine.dartExecutor.isExecutingDart) {
            stopRuntime("dart_engine_unavailable")
            return START_NOT_STICKY
        }
        ownedEngine = engine
        runtimeReleased = false
        cameraDemand = intent.getBooleanExtra(EXTRA_CAMERA, cameraDemand)
        microphoneDemand = intent.getBooleanExtra(EXTRA_MICROPHONE, microphoneDemand)
        playbackDemand = intent.getBooleanExtra(EXTRA_PLAYBACK, playbackDemand)
        nativeCameraCaptureDemand = cameraDemand && intent.getBooleanExtra(
            EXTRA_NATIVE_CAMERA_CAPTURE,
            cameraDemand
        )
        nativeMicrophoneCaptureDemand = microphoneDemand && intent.getBooleanExtra(
            EXTRA_NATIVE_MICROPHONE_CAPTURE,
            microphoneDemand
        )
        if (!cameraDemand && !microphoneDemand && !playbackDemand) {
            stopRuntime("media_demand_empty")
            return START_NOT_STICKY
        }

        try {
            acquireWifiLock()
            publishForegroundNotification()
            MimiCamPlatformRuntime.setForegroundServiceState(
                active = true,
                camera = cameraDemand,
                microphone = microphoneDemand,
                playback = playbackDemand,
                nativeCameraCapture = nativeCameraCaptureDemand,
                nativeMicrophoneCapture = nativeMicrophoneCaptureDemand
            )
            reconcileNativeMediaCapture()
        } catch (error: Exception) {
            val reason = "foreground_promotion_failed:${error.javaClass.simpleName}"
            MimiCamPlatformRuntime.setForegroundServiceFailure(reason)
            stopRuntime(reason)
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        MimiCamPlatformRuntime.emit(
            "foregroundServiceTaskRemoved",
            mapOf("runtimeContinues" to foregroundStarted)
        )
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        releaseRuntime("service_destroyed")
        super.onDestroy()
    }

    private fun publishForegroundNotification() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            var serviceType = 0
            if (cameraDemand) {
                serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }
            if (microphoneDemand) {
                serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            if (playbackDemand) {
                serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            }
            startForeground(NOTIFICATION_ID, notification, serviceType)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        foregroundStarted = true
    }

    private fun stopRuntime(reason: String) {
        releaseRuntime(reason)
        stopSelf()
    }

    private fun releaseRuntime(reason: String) {
        if (runtimeReleased) return
        runtimeReleased = true
        mediaCapture?.shutdown(reason)
        mediaCapture = null
        if (foregroundStarted) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        }
        getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
        foregroundStarted = false
        releaseWifiLock()
        ownedEngine = null
        nativeCameraCaptureDemand = false
        nativeMicrophoneCaptureDemand = false
        MimiCamEngineOwner.releaseService()
        MimiCamPlatformRuntime.setForegroundServiceState(
            active = false,
            camera = false,
            microphone = false,
            playback = false,
            stopReason = reason
        )
    }

    private fun reconcileNativeMediaCapture() {
        if (!nativeCameraCaptureDemand && !nativeMicrophoneCaptureDemand) {
            mediaCapture?.reconcile(camera = false, microphone = false)
            MimiCamServiceMediaBridge.updateCaptureState(
                cameraRequested = false,
                microphoneRequested = false,
                cameraActive = false,
                microphoneActive = false
            )
            return
        }
        val capture = mediaCapture ?: MimiCamServiceMediaCapture(
            applicationContext,
            this
        ).also { mediaCapture = it }
        capture.reconcile(
            camera = nativeCameraCaptureDemand,
            microphone = nativeMicrophoneCaptureDemand
        )
    }

    private fun acquireWifiLock() {
        if (wifiLock?.isHeld == true) return
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            WifiManager.WIFI_MODE_FULL_LOW_LATENCY
        } else {
            @Suppress("DEPRECATION")
            WifiManager.WIFI_MODE_FULL_HIGH_PERF
        }
        wifiLock = wifiManager.createWifiLock(lockMode, "MimiCam:ServerWifiLock").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWifiLock() {
        wifiLock?.takeIf { it.isHeld }?.release()
        wifiLock = null
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "MimiCam Server",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "MimiCam kamera ve ses yayını çalışma durumu"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val text = when {
            cameraDemand && microphoneDemand && playbackDemand ->
                "Kamera, mikrofon ve oda sesi için arka plan koruması açık."
            cameraDemand && microphoneDemand ->
                "Kamera ve mikrofon için arka plan koruması açık."
            cameraDemand && playbackDemand ->
                "Kamera ve oda sesi için arka plan koruması açık."
            microphoneDemand && playbackDemand ->
                "Mikrofon ve oda sesi için arka plan koruması açık."
            cameraDemand -> "Kamera için arka plan koruması açık."
            microphoneDemand -> "Mikrofon için arka plan koruması açık."
            playbackDemand -> "Oda sesi için arka plan koruması açık."
            else -> "Medya servisi durduruluyor."
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle("MimiCam oda yayını korunuyor")
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        private const val ACTION_START = "com.example.mimicam.action.START_SERVER"
        private const val ACTION_UPDATE = "com.example.mimicam.action.UPDATE_SERVER"
        private const val ACTION_STOP = "com.example.mimicam.action.STOP_SERVER"
        private const val EXTRA_CAMERA = "camera"
        private const val EXTRA_MICROPHONE = "microphone"
        private const val EXTRA_PLAYBACK = "playback"
        private const val EXTRA_NATIVE_CAMERA_CAPTURE = "nativeCameraCapture"
        private const val EXTRA_NATIVE_MICROPHONE_CAPTURE = "nativeMicrophoneCapture"
        private const val CHANNEL_ID = "mimicam_server_runtime"
        private const val NOTIFICATION_ID = 4101

        fun startIntent(
            context: Context,
            camera: Boolean,
            microphone: Boolean,
            playback: Boolean,
            nativeCameraCapture: Boolean = camera,
            nativeMicrophoneCapture: Boolean = microphone
        ): Intent = Intent(context, MimiCamForegroundService::class.java).apply {
            action = ACTION_START
            putExtra(EXTRA_CAMERA, camera)
            putExtra(EXTRA_MICROPHONE, microphone)
            putExtra(EXTRA_PLAYBACK, playback)
            putExtra(EXTRA_NATIVE_CAMERA_CAPTURE, camera && nativeCameraCapture)
            putExtra(
                EXTRA_NATIVE_MICROPHONE_CAPTURE,
                microphone && nativeMicrophoneCapture
            )
        }

        fun updateIntent(
            context: Context,
            camera: Boolean,
            microphone: Boolean,
            playback: Boolean,
            nativeCameraCapture: Boolean = camera,
            nativeMicrophoneCapture: Boolean = microphone
        ): Intent = Intent(context, MimiCamForegroundService::class.java).apply {
            action = ACTION_UPDATE
            putExtra(EXTRA_CAMERA, camera)
            putExtra(EXTRA_MICROPHONE, microphone)
            putExtra(EXTRA_PLAYBACK, playback)
            putExtra(EXTRA_NATIVE_CAMERA_CAPTURE, camera && nativeCameraCapture)
            putExtra(
                EXTRA_NATIVE_MICROPHONE_CAPTURE,
                microphone && nativeMicrophoneCapture
            )
        }

        fun stopIntent(context: Context): Intent =
            Intent(context, MimiCamForegroundService::class.java).apply {
                action = ACTION_STOP
            }
    }
}
