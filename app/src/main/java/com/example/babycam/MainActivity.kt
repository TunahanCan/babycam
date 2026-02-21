package com.example.babycam

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.widget.NestedScrollView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    // View'ları daha güvenli ve modern bir şekilde "by lazy" ile başlatıyoruz.
    // Bu, findViewById'ı sadece ihtiyaç duyulduğunda ve null olmayacak şekilde çağırır.
    private val tvInfo: TextView by lazy { findViewById(R.id.tvInfo) }
    private val tvLogs: TextView by lazy { findViewById(R.id.tvLogs) }
    private val logScrollView: NestedScrollView by lazy { findViewById(R.id.logScrollView) }

    // registerForActivityResult, onCreate'den önce veya içinde tanımlanmalıdır.
    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        // İzin sonucunda TÜM izinlerin verilip verilmediğini kontrol et
        val allPermissionsGranted = permissions.entries.all { it.value }

        if (allPermissionsGranted) {
            // İzinler şimdi verildi, servisi başlat ve kullanıcıyı bilgilendir.
            updateStatus("Tüm izinler verildi. Servis başlatılıyor...")
            startMonitorService()
        } else {
            // Bir veya daha fazla izin reddedildi, kullanıcıyı bilgilendir.
            updateStatus("Uygulamanın çalışması için Kamera ve Mikrofon izinleri zorunludur. Lütfen uygulama ayarlarından izinleri verin.")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main) // activity_main.xml dosyanız olmalı

        observeLogStream()

        // Uygulama başlar başlamaz izin durumunu kontrol et
        checkAndRequestPermissions()
    }

    private fun observeLogStream() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                // repeatOnLifecycle ile yalnızca ekran görünür durumdayken log akışını
                // toplayıp UI'yı güncelliyoruz; bu enerji tüketimini azaltır.
                AppLogBuffer.logs.collectLatest { logs ->
                    // Tüm logları tek bir metin halinde gösteriyoruz. Yeni kayıt geldiğinde
                    // otomatik kaydırma yaparak en son mesajın görünür kalmasını sağlıyoruz.
                    tvLogs.text = logs.joinToString("\n")
                    logScrollView.post { logScrollView.fullScroll(View.FOCUS_DOWN) }
                }
            }
        }
    }

    private fun checkAndRequestPermissions() {
        // İzinlerin ikisinin de verilip verilmediğini kontrol et
        if (hasRequiredPermissions()) {
            // İzinler zaten verilmiş, servisi doğrudan başlat
            updateStatus("İzinler mevcut. Servis başlatılıyor...")
            startMonitorService()
        } else {
            // İzinler eksik, kullanıcıdan istemek için diyalog göster
            // İzin isteği gönderilmeden önce kullanıcıya bilgi ver
            updateStatus("Kamera ve Mikrofon izinleri isteniyor...")
            requestPermissionLauncher.launch(
                arrayOf(
                    Manifest.permission.CAMERA,
                    Manifest.permission.RECORD_AUDIO
                )
            )
        }
    }

    /**
     * Gerekli tüm izinlerin verilip verilmediğini kontrol eder.
     */
    private fun hasRequiredPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED && ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * BabyMonitorService'i bir ön plan hizmeti olarak başlatır.
     */
    private fun startMonitorService() {
        val intent = Intent(this, BabyMonitorService::class.java)
        ContextCompat.startForegroundService(this, intent)
        // Servis başladıktan sonra durumu güncelle
        updateStatus("Bebek Monitörü arka planda çalışıyor.\nHareket ve ses analizi yapılıyor.")
        // finish() // Servis başladıktan sonra bu ekranın kapanmasını isterseniz bu satırı aktif edin.
    }

    /**
     * TextView'da gösterilen durum metnini günceller.
     */
    private fun updateStatus(message: String) {
        tvInfo.text = message
        AppLogBuffer.log(message)
    }
}
