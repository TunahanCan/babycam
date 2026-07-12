package com.mimicam.app

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
    private data class RuntimeDemand(
        val camera: Boolean,
        val microphone: Boolean,
        val playback: Boolean,
        val alert: Boolean,
        val server: Boolean,
        val nativeCameraCapture: Boolean,
        val nativeMicrophoneCapture: Boolean
    ) {
        val isEmpty: Boolean
            get() = !camera && !microphone && !playback && !alert && !server
    }

    private var wifiLock: WifiManager.WifiLock? = null
    private var ownedEngine: FlutterEngine? = null
    private var mediaCapture: MimiCamServiceMediaCapture? = null
    private var cameraDemand = false
    private var microphoneDemand = false
    private var playbackDemand = false
    private var alertDemand = false
    private var serverDemand = false
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
                // Demand methods update their authoritative aggregate before
                // posting intents. Ignore a stale stop that was overtaken by a
                // newer media, alert, or server request.
                if (MimiCamPlatformRuntime.hasRequestedRuntimeDemand) {
                    return START_NOT_STICKY
                }
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

        val previousDemand = currentDemand()
        val wasForegroundStarted = foregroundStarted
        val requestedCameraDemand = intent.getBooleanExtra(EXTRA_CAMERA, cameraDemand)
        val requestedMicrophoneDemand =
            intent.getBooleanExtra(EXTRA_MICROPHONE, microphoneDemand)
        if (
            action == ACTION_UPDATE &&
            !foregroundStarted &&
            (requestedCameraDemand || requestedMicrophoneDemand) &&
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
        cameraDemand = requestedCameraDemand
        microphoneDemand = requestedMicrophoneDemand
        playbackDemand = intent.getBooleanExtra(EXTRA_PLAYBACK, playbackDemand)
        alertDemand = intent.getBooleanExtra(EXTRA_ALERT, alertDemand)
        serverDemand = intent.getBooleanExtra(EXTRA_SERVER, serverDemand)
        nativeCameraCaptureDemand = cameraDemand && intent.getBooleanExtra(
            EXTRA_NATIVE_CAMERA_CAPTURE,
            cameraDemand
        )
        nativeMicrophoneCaptureDemand = microphoneDemand && intent.getBooleanExtra(
            EXTRA_NATIVE_MICROPHONE_CAPTURE,
            microphoneDemand
        )
        if (currentDemand().isEmpty) {
            stopRuntime("runtime_demand_empty")
            return START_NOT_STICKY
        }

        try {
            acquireWifiLock()
            publishForegroundNotification()
            publishRuntimeState()
            reconcileNativeMediaCapture()
        } catch (error: Exception) {
            var reason = "foreground_promotion_failed:${error.javaClass.simpleName}"
            if (wasForegroundStarted && !previousDemand.isEmpty) {
                try {
                    applyDemand(previousDemand)
                    acquireWifiLock()
                    publishForegroundNotification()
                    publishRuntimeState()
                    reconcileNativeMediaCapture()
                    MimiCamPlatformRuntime.emit(
                        "foregroundServiceUpdateRejected",
                        mapOf(
                            "reason" to reason,
                            "serverRuntimePreserved" to serverDemand
                        )
                    )
                    return START_NOT_STICKY
                } catch (rollbackError: Exception) {
                    reason += ":rollback_failed:${rollbackError.javaClass.simpleName}"
                }
            }
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
            if (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                (alertDemand || serverDemand)
            ) {
                serviceType = serviceType or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            }
            // Pass NONE explicitly for alert-only service runs before API 34.
            // The two-argument overload would inherit every media type declared
            // in the manifest and could incorrectly require while-in-use access.
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
        alertDemand = false
        serverDemand = false
        MimiCamEngineOwner.releaseService()
        MimiCamPlatformRuntime.setForegroundServiceState(
            active = false,
            camera = false,
            microphone = false,
            playback = false,
            alert = false,
            server = false,
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

    private fun currentDemand(): RuntimeDemand = RuntimeDemand(
        camera = cameraDemand,
        microphone = microphoneDemand,
        playback = playbackDemand,
        alert = alertDemand,
        server = serverDemand,
        nativeCameraCapture = nativeCameraCaptureDemand,
        nativeMicrophoneCapture = nativeMicrophoneCaptureDemand
    )

    private fun applyDemand(demand: RuntimeDemand) {
        cameraDemand = demand.camera
        microphoneDemand = demand.microphone
        playbackDemand = demand.playback
        alertDemand = demand.alert
        serverDemand = demand.server
        nativeCameraCaptureDemand = demand.nativeCameraCapture
        nativeMicrophoneCaptureDemand = demand.nativeMicrophoneCapture
    }

    private fun publishRuntimeState() {
        MimiCamPlatformRuntime.setForegroundServiceState(
            active = true,
            camera = cameraDemand,
            microphone = microphoneDemand,
            playback = playbackDemand,
            alert = alertDemand,
            server = serverDemand,
            nativeCameraCapture = nativeCameraCaptureDemand,
            nativeMicrophoneCapture = nativeMicrophoneCaptureDemand
        )
    }

    private fun acquireWifiLock() {
        if (wifiLock?.isHeld == true) return
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lockMode = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            @Suppress("DEPRECATION")
            WifiManager.WIFI_MODE_FULL_HIGH_PERF
        } else {
            // API 34 aliases HIGH_PERF to LOW_LATENCY. The connected-device
            // foreground service remains the process/network owner; this lock
            // is only an additional best-effort latency hint on newer Android.
            WifiManager.WIFI_MODE_FULL_LOW_LATENCY
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
            val channelId = if (hasMediaDemand() || serverDemand) {
                SERVER_CHANNEL_ID
            } else {
                ALERT_CHANNEL_ID
            }
            val channel = NotificationChannel(
                channelId,
                if (hasMediaDemand() || serverDemand) {
                    "MimiCam Server"
                } else {
                    "MimiCam Bildirim Bağlantısı"
                },
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = if (hasMediaDemand() || serverDemand) {
                    "MimiCam yerel ağ sunucusu ve medya çalışma durumu"
                } else {
                    "Bebek odası uyarılarını arka planda dinlemek için bağlantı durumu"
                }
                setSound(null, null)
                enableVibration(false)
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
            serverDemand -> "Yerel ağ sunucusu ve Wi-Fi bağlantısı korunuyor."
            alertDemand -> "Bebek odası bildirimleri arka planda dinleniyor."
            else -> "Arka plan servisi durduruluyor."
        }
        val channelId = if (hasMediaDemand() || serverDemand) {
            SERVER_CHANNEL_ID
        } else {
            ALERT_CHANNEL_ID
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_LOW)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_mimicam)
            .setContentTitle(
                if (hasMediaDemand()) {
                    "MimiCam oda yayını korunuyor"
                } else if (serverDemand) {
                    "MimiCam yerel ağ sunucusu açık"
                } else {
                    "MimiCam uyarıları açık"
                }
            )
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun hasMediaDemand(): Boolean =
        cameraDemand || microphoneDemand || playbackDemand

    companion object {
        private const val ACTION_START = "com.mimicam.app.action.START_SERVER"
        private const val ACTION_UPDATE = "com.mimicam.app.action.UPDATE_SERVER"
        private const val ACTION_STOP = "com.mimicam.app.action.STOP_SERVER"
        private const val EXTRA_CAMERA = "camera"
        private const val EXTRA_MICROPHONE = "microphone"
        private const val EXTRA_PLAYBACK = "playback"
        private const val EXTRA_ALERT = "alert"
        private const val EXTRA_SERVER = "server"
        private const val EXTRA_NATIVE_CAMERA_CAPTURE = "nativeCameraCapture"
        private const val EXTRA_NATIVE_MICROPHONE_CAPTURE = "nativeMicrophoneCapture"
        private const val SERVER_CHANNEL_ID = "mimicam_server_runtime"
        private const val ALERT_CHANNEL_ID = "mimicam_client_alert_runtime"
        private const val NOTIFICATION_ID = 4101

        fun startIntent(
            context: Context,
            camera: Boolean,
            microphone: Boolean,
            playback: Boolean,
            alert: Boolean = false,
            server: Boolean = false,
            nativeCameraCapture: Boolean = camera,
            nativeMicrophoneCapture: Boolean = microphone
        ): Intent = Intent(context, MimiCamForegroundService::class.java).apply {
            action = ACTION_START
            putExtra(EXTRA_CAMERA, camera)
            putExtra(EXTRA_MICROPHONE, microphone)
            putExtra(EXTRA_PLAYBACK, playback)
            putExtra(EXTRA_ALERT, alert)
            putExtra(EXTRA_SERVER, server)
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
            alert: Boolean = false,
            server: Boolean = false,
            nativeCameraCapture: Boolean = camera,
            nativeMicrophoneCapture: Boolean = microphone
        ): Intent = Intent(context, MimiCamForegroundService::class.java).apply {
            action = ACTION_UPDATE
            putExtra(EXTRA_CAMERA, camera)
            putExtra(EXTRA_MICROPHONE, microphone)
            putExtra(EXTRA_PLAYBACK, playback)
            putExtra(EXTRA_ALERT, alert)
            putExtra(EXTRA_SERVER, server)
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
