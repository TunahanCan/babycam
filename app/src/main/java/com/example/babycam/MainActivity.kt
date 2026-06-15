package com.example.babycam

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.widget.NestedScrollView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.sample
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import okio.ByteString
import java.util.concurrent.TimeUnit

class MainActivity : ComponentActivity() {

    private val tvInfo: TextView by lazy { findViewById(R.id.tvInfo) }
    private val tvLogs: TextView by lazy { findViewById(R.id.tvLogs) }
    private val logScrollView: NestedScrollView by lazy { findViewById(R.id.logScrollView) }
    private val modeSelectionPanel: LinearLayout by lazy { findViewById(R.id.modeSelectionPanel) }
    private val clientPanel: LinearLayout by lazy { findViewById(R.id.clientPanel) }
    private val serverSharePanel: LinearLayout by lazy { findViewById(R.id.serverSharePanel) }
    private val btnServerMode: Button by lazy { findViewById(R.id.btnServerMode) }
    private val btnClientMode: Button by lazy { findViewById(R.id.btnClientMode) }
    private val btnResetMode: Button by lazy { findViewById(R.id.btnResetMode) }
    private val btnConnectClient: Button by lazy { findViewById(R.id.btnConnectClient) }
    private val etServerAddress: EditText by lazy { findViewById(R.id.etServerAddress) }
    private val streamWebView: WebView by lazy { findViewById(R.id.streamWebView) }
    private val tvDiscoveryStatus: TextView by lazy { findViewById(R.id.tvDiscoveryStatus) }
    private val tvServerUrl: TextView by lazy { findViewById(R.id.tvServerUrl) }
    private val imgServerQr: ImageView by lazy { findViewById(R.id.imgServerQr) }

    private val prefs by lazy { getSharedPreferences(PREFS_NAME, MODE_PRIVATE) }
    private val notificationManager by lazy { getSystemService(NotificationManager::class.java) }
    private val clientHttp = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()
    private var alertSocket: WebSocket? = null
    private var reconnectJob: Job? = null
    private var currentMode: AppMode? = null
    private val discovery by lazy { BabyCamDiscovery(lifecycleScope) }

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        if (currentMode == AppMode.CLIENT) {
            val notificationsGranted = permissions[Manifest.permission.POST_NOTIFICATIONS] == true
            updateStatus(if (notificationsGranted) "Client bildirim izni hazır." else "Client bildirim izni verilmedi; yayın yine izlenebilir.")
            return@registerForActivityResult
        }

        val allPermissionsGranted = permissions
            .filterKeys { it == Manifest.permission.CAMERA || it == Manifest.permission.RECORD_AUDIO }
            .values
            .all { it }

        if (allPermissionsGranted) {
            updateStatus("Tüm izinler verildi. Server servisi başlatılıyor...")
            startMonitorService()
        } else {
            updateStatus("Server modu için Kamera ve Mikrofon izinleri zorunludur. Lütfen uygulama ayarlarından izinleri verin.")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        createClientNotificationChannel()
        configureWebView()
        observeLogStream()
        setupActions()
        applySavedMode()
    }

    override fun onDestroy() {
        alertSocket?.close(1000, "Activity kapanıyor")
        reconnectJob?.cancel()
        discovery.stopAll()
        super.onDestroy()
    }

    private fun setupActions() {
        btnServerMode.setOnClickListener { selectMode(AppMode.SERVER) }
        btnClientMode.setOnClickListener { selectMode(AppMode.CLIENT) }
        btnResetMode.setOnClickListener { resetMode() }
        btnConnectClient.setOnClickListener { connectClient(etServerAddress.text.toString()) }
    }

    private fun applySavedMode() {
        when (prefs.getString(KEY_MODE, null)) {
            AppMode.SERVER.name -> selectMode(AppMode.SERVER, persist = false)
            AppMode.CLIENT.name -> selectMode(AppMode.CLIENT, persist = false)
            else -> showModeSelection()
        }
    }

    private fun selectMode(mode: AppMode, persist: Boolean = true) {
        currentMode = mode
        if (persist) prefs.edit().putString(KEY_MODE, mode.name).apply()
        modeSelectionPanel.visibility = View.GONE
        btnResetMode.visibility = View.VISIBLE
        when (mode) {
            AppMode.SERVER -> {
                discovery.stopListening()
                clientPanel.visibility = View.GONE
                serverSharePanel.visibility = View.VISIBLE
                streamWebView.visibility = View.GONE
                showServerShareCard()
                updateStatus("Server modu seçildi. Bu cihaz kamera/mikrofon yayını yapacak, LAN yayını açacak ve Telegram/client bildirimi gönderecek.")
                checkAndRequestServerPermissions()
            }
            AppMode.CLIENT -> {
                serverSharePanel.visibility = View.GONE
                clientPanel.visibility = View.VISIBLE
                streamWebView.visibility = View.VISIBLE
                stopService(Intent(this, BabyMonitorService::class.java))
                startDiscoveryListener()
                ensureNotificationPermissionForClient()
                updateStatus("Client modu seçildi. Server otomatik aranıyor; bulunamazsa adresi elle girip bağlanın.")
                prefs.getString(KEY_SERVER_ADDRESS, null)?.let { address ->
                    etServerAddress.setText(address)
                    connectClient(address)
                }
            }
        }
    }

    private fun showModeSelection() {
        currentMode = null
        modeSelectionPanel.visibility = View.VISIBLE
        clientPanel.visibility = View.GONE
        serverSharePanel.visibility = View.GONE
        streamWebView.visibility = View.GONE
        btnResetMode.visibility = View.GONE
        updateStatus("İlk kullanım için rol seçin: Server kamera/mikrofon yayını yapar, Client yayını izler ve uyarı alır.")
    }

    private fun resetMode() {
        prefs.edit().remove(KEY_MODE).apply()
        alertSocket?.close(1000, "Rol sıfırlandı")
        reconnectJob?.cancel()
        discovery.stopAll()
        stopService(Intent(this, BabyMonitorService::class.java))
        showModeSelection()
    }

    private fun observeLogStream() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                AppLogBuffer.logs.sample(300).collectLatest { logs ->
                    tvLogs.text = logs.takeLast(120).joinToString("\n")
                    logScrollView.post { logScrollView.fullScroll(View.FOCUS_DOWN) }
                }
            }
        }
    }

    private fun checkAndRequestServerPermissions() {
        val permissions = buildList {
            add(Manifest.permission.CAMERA)
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
        }.toTypedArray()

        if (hasServerPermissions()) {
            updateStatus("İzinler mevcut. Server servisi başlatılıyor...")
            startMonitorService()
        } else {
            updateStatus("Server modu için Kamera ve Mikrofon izinleri isteniyor...")
            requestPermissionLauncher.launch(permissions)
        }
    }

    private fun hasServerPermissions(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun startMonitorService() {
        ContextCompat.startForegroundService(this, Intent(this, BabyMonitorService::class.java))
        updateStatus("Server modu aktif. Yerel ağda sıkıştırılmış MJPEG video, PCM16LE ses ve bildirim yayını çalışıyor.")
        showServerShareCard()
    }

    private fun showServerShareCard() {
        val address = NetworkAddressProvider.localHttpAddress() ?: return
        val url = "http://$address/"
        tvServerUrl.text = "Client cihazlar otomatik bulamazsa bu adresi açın veya QR okutun:\n$url"
        imgServerQr.setImageBitmap(createQrBitmap(url))
    }

    private fun configureWebView() {
        streamWebView.webViewClient = WebViewClient()
        streamWebView.webChromeClient = WebChromeClient()
        streamWebView.settings.javaScriptEnabled = true
        streamWebView.settings.mediaPlaybackRequiresUserGesture = false
        streamWebView.settings.cacheMode = WebSettings.LOAD_NO_CACHE
        streamWebView.settings.domStorageEnabled = true
    }

    private fun connectClient(rawAddress: String) {
        val address = normalizeAddress(rawAddress)
        if (address.isBlank()) {
            updateStatus("Client bağlantısı için server IP/adres girin. Örn: 192.168.1.25:8080")
            return
        }
        prefs.edit().putString(KEY_SERVER_ADDRESS, address).apply()
        val httpUrl = "http://$address/"
        val wsUrl = "ws://$address/ws/stream"
        discovery.stopListening()
        streamWebView.loadUrl(httpUrl)
        connectAlertSocket(wsUrl)
        updateStatus("Client bağlanıyor: $httpUrl")
    }

    private fun connectAlertSocket(wsUrl: String) {
        alertSocket?.close(1000, "Yeni bağlantı")
        reconnectJob?.cancel()
        val request = Request.Builder().url(wsUrl).build()
        alertSocket = clientHttp.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                AppLogBuffer.log("Client uyarı bağlantısı açıldı.")
                runOnUiThread { updateStatus("Client bağlı. Video/ses WebView üzerinden, uyarılar uygulama bildirimi olarak alınacak.") }
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                if (bytes.size < 2 || bytes[0] != BabyCamProtocol.PACKET_ALERT_TEXT) return
                val message = bytes.substring(1).utf8()
                AppLogBuffer.log("Server uyarısı: $message")
                showClientNotification(message)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                AppLogBuffer.log("Client uyarı bağlantısı koptu: ${t.message}")
                scheduleClientReconnect(wsUrl)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                AppLogBuffer.log("Client uyarı bağlantısı kapandı: $reason")
            }
        })
    }

    private fun scheduleClientReconnect(wsUrl: String) {
        reconnectJob?.cancel()
        reconnectJob = lifecycleScope.launch(Dispatchers.Main) {
            delay(2_000L)
            if (isActive && currentMode == AppMode.CLIENT) connectAlertSocket(wsUrl)
        }
    }

    private fun startDiscoveryListener() {
        tvDiscoveryStatus.text = "Ağda BabyCam server aranıyor..."
        discovery.startListening { address ->
            runOnUiThread {
                if (currentMode == AppMode.CLIENT && etServerAddress.text.toString().isBlank()) {
                    tvDiscoveryStatus.text = "Server bulundu: $address"
                    etServerAddress.setText(address)
                    connectClient(address)
                }
            }
        }
    }

    private fun ensureNotificationPermissionForClient() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissionLauncher.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
        }
    }

    private fun showClientNotification(message: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(this, CLIENT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("BabyCam uyarısı")
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        notificationManager.notify(CLIENT_NOTIFICATION_ID, notification)
    }

    private fun createClientNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(
                NotificationChannel(CLIENT_CHANNEL_ID, "BabyCam Client Uyarıları", NotificationManager.IMPORTANCE_HIGH)
            )
        }
    }

    private fun createQrBitmap(content: String): Bitmap {
        val size = 512
        val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
        for (x in 0 until size) {
            for (y in 0 until size) {
                bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
            }
        }
        return bitmap
    }

    private fun normalizeAddress(rawAddress: String): String = rawAddress.trim()
        .removePrefix("http://")
        .removePrefix("https://")
        .removeSuffix("/")
        .let { if (it.isNotBlank() && ':' !in it) "$it:8080" else it }

    private fun updateStatus(message: String) {
        tvInfo.text = message
        AppLogBuffer.log(message)
    }

    private enum class AppMode { SERVER, CLIENT }

    companion object {
        private const val PREFS_NAME = "babycam_prefs"
        private const val KEY_MODE = "mode"
        private const val KEY_SERVER_ADDRESS = "server_address"
        private const val CLIENT_CHANNEL_ID = "babycam_client_alerts"
        private const val CLIENT_NOTIFICATION_ID = 2001
    }
}
