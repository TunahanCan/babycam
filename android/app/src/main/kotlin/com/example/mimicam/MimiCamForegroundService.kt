package com.example.mimicam

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder

class MimiCamForegroundService : Service() {
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        acquireWifiLock()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWifiLock()
        super.onDestroy()
    }

    private fun acquireWifiLock() {
        if (wifiLock?.isHeld == true) return
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            WifiManager.WIFI_MODE_FULL_LOW_LATENCY
        } else {
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
        val channelId = "mimicam_server_runtime"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "MimiCam Server",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
            return Notification.Builder(this, channelId)
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle("MimiCam server çalışıyor")
                .setContentText("Kamera, mikrofon ve uyarı servisi aktif.")
                .setOngoing(true)
                .build()
        }

        return Notification.Builder(this)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle("MimiCam server çalışıyor")
            .setContentText("Kamera, mikrofon ve uyarı servisi aktif.")
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val NOTIFICATION_ID = 4101
    }
}
