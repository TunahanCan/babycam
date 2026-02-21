package com.example.babycam

import android.util.Base64
import java.io.BufferedOutputStream
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStream
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max

/**
 * Basit bir HTTP sunucusu üzerinden MJPEG video ve PCM ses akışı sağlar.
 *
 * Ek olarak, /ws/stream endpoint'i WebSocket üzerinden tek bağlantıda
 * hem JPEG video hem de PCM ses akışı gönderir. Böylece ağ tıkanmalarında
 * bile ses ve görüntü senkron bir şekilde aktarılır.
 */
class LiveStreamServer(
    private val port: Int,
    private val audioSampleRate: Int,
    private val audioChannelCount: Int,
    private val audioBitsPerSample: Int
) {

    private val videoClients = CopyOnWriteArrayList<StreamClient>()
    private val audioClients = CopyOnWriteArrayList<AudioClient>()
    private val avWebSocketClients = CopyOnWriteArrayList<AvWebSocketClient>()
    private val isRunning = AtomicBoolean(false)
    private val serverSocketRef = AtomicReference<ServerSocket?>()
    private val acceptThreadRef = AtomicReference<Thread?>()
    private val clientExecutorRef = AtomicReference<ExecutorService?>()
    private val broadcastExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "LiveStreamServer-Broadcast").apply { isDaemon = true }
    }
    private val frameDispatchLock = Any()
    @Volatile private var pendingVideoFrame: ByteArray? = null
    @Volatile private var videoDispatchScheduled = false

    private val audioDispatchLock = Any()
    private val pendingAudioChunks = ArrayDeque<ByteArray>()
    @Volatile private var audioDispatchScheduled = false
    private val maxQueuedAudioChunks = 8

    @Throws(IOException::class)
    fun startServer() {
        if (!isRunning.compareAndSet(false, true)) {
            return
        }

        val executor = Executors.newCachedThreadPool()
        clientExecutorRef.set(executor)

        val serverSocket = try {
            ServerSocket(port)
        } catch (ioe: IOException) {
            isRunning.set(false)
            clientExecutorRef.getAndSet(null)?.shutdownNow()
            throw ioe
        }
        serverSocketRef.set(serverSocket)

        val acceptThread = Thread {
            try {
                while (!serverSocket.isClosed && isRunning.get()) {
                    try {
                        val clientSocket = serverSocket.accept()
                        try {
                            executor.execute { handleClient(clientSocket) }
                        } catch (re: RejectedExecutionException) {
                            clientSocket.closeQuietly()
                        }
                    } catch (ioe: IOException) {
                        if (isRunning.get()) {
                            ioe.printStackTrace()
                        }
                    }
                }
            } finally {
                serverSocket.closeQuietly()
                clientExecutorRef.getAndSet(null)?.shutdownNow()
                isRunning.set(false)
            }
        }.apply { name = "LiveStreamServer-Acceptor" }

        acceptThreadRef.set(acceptThread)
        acceptThread.start()
    }

    fun stopServer() {
        isRunning.set(false)

        serverSocketRef.getAndSet(null)?.closeQuietly()
        clientExecutorRef.getAndSet(null)?.shutdownNow()

        acceptThreadRef.getAndSet(null)?.joinSafely()

        broadcastExecutor.shutdownNow()

        videoClients.forEach { it.close() }
        videoClients.clear()
        audioClients.forEach { it.close() }
        audioClients.clear()
        avWebSocketClients.forEach { it.close() }
        avWebSocketClients.clear()
    }

    private fun handleClient(socket: Socket) {
        try {
            socket.tcpNoDelay = true
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))
            val requestLine = reader.readLine() ?: return socket.closeQuietly()
            val requestParts = requestLine.split(' ')
            if (requestParts.size < 2) {
                return socket.closeQuietly()
            }

            val method = requestParts[0].uppercase(Locale.US)
            val rawPath = requestParts[1]
            val path = rawPath.substringBefore('?').substringBefore('#')

            val headers = readHeaders(reader)
            val output = BufferedOutputStream(socket.getOutputStream())

            if (isWebSocketUpgrade(headers)) {
                when (path) {
                    "/ws/stream" -> handleWebSocketRequest(socket, output, headers)
                    else -> sendFixedLengthResponse(
                        output,
                        socket,
                        404,
                        "text/plain; charset=utf-8",
                        "${method} ${rawPath} desteklenmiyor"
                    )
                }
                return
            }

            when (path) {
                "/video" -> handleVideoRequest(socket, output)
                "/audio" -> handleAudioRequest(socket, output)
                "/status" -> {
                    val body = "{\"videoClients\":${videoClients.size},\"audioClients\":${audioClients.size},\"webSocketClients\":${avWebSocketClients.size}}"
                    sendFixedLengthResponse(output, socket, 200, "application/json", body)
                }
                "/" -> {
                    val body = buildLandingPage()
                    sendFixedLengthResponse(output, socket, 200, "text/html; charset=utf-8", body)
                    AppLogBuffer.log("Tarayıcı arayüzü isteği geldi: ${socket.remoteAddressText()}")
                }
                else -> {
                    val message = "${method} ${rawPath} bulunamadı"
                    sendFixedLengthResponse(output, socket, 404, "text/plain; charset=utf-8", message)
                    AppLogBuffer.log("İstemci bilinmeyen yol istedi (${path}): ${socket.remoteAddressText()}")
                }
            }
        } catch (ioe: IOException) {
            socket.closeQuietly()
        }
    }

    fun pushVideoFrame(jpegData: ByteArray) {
        if (jpegData.isEmpty() || !isRunning.get()) return

        synchronized(frameDispatchLock) {
            pendingVideoFrame = jpegData
            if (videoDispatchScheduled) return
            videoDispatchScheduled = true
        }

        dispatchVideoFrames()
    }

    fun pushAudioChunk(pcmData: ByteArray) {
        if (pcmData.isEmpty() || !isRunning.get()) return

        synchronized(audioDispatchLock) {
            if (pendingAudioChunks.size >= maxQueuedAudioChunks) {
                val dropCount = max(1, pendingAudioChunks.size - maxQueuedAudioChunks + 1)
                repeat(dropCount) {
                    if (pendingAudioChunks.isNotEmpty()) pendingAudioChunks.removeFirst()
                }
            }
            pendingAudioChunks.addLast(pcmData)
            if (audioDispatchScheduled) return
            audioDispatchScheduled = true
        }

        dispatchAudioChunks()
    }

    private fun dispatchVideoFrames() {
        try {
            broadcastExecutor.execute {
                while (true) {
                    val frame = synchronized(frameDispatchLock) {
                        val next = pendingVideoFrame
                        pendingVideoFrame = null
                        if (next == null) {
                            videoDispatchScheduled = false
                            return@execute
                        }
                        next
                    }
                    broadcastVideoFrame(frame)
                }
            }
        } catch (_: RejectedExecutionException) {
            synchronized(frameDispatchLock) {
                videoDispatchScheduled = false
            }
        }
    }

    private fun dispatchAudioChunks() {
        try {
            broadcastExecutor.execute {
                while (true) {
                    val chunk = synchronized(audioDispatchLock) {
                        if (pendingAudioChunks.isEmpty()) {
                            audioDispatchScheduled = false
                            return@execute
                        }
                        pendingAudioChunks.removeFirst()
                    }
                    broadcastAudioChunk(chunk)
                }
            }
        } catch (_: RejectedExecutionException) {
            synchronized(audioDispatchLock) {
                audioDispatchScheduled = false
                pendingAudioChunks.clear()
            }
        }
    }

    private fun broadcastVideoFrame(jpegData: ByteArray) {
        if (videoClients.isNotEmpty()) {
            val header = ("\r\n--frame\r\n" +
                "Content-Type: image/jpeg\r\n" +
                "Content-Length: ${jpegData.size}\r\n\r\n").toByteArray()
            for (client in videoClients.toList()) {
                try {
                    client.output.write(header)
                    client.output.write(jpegData)
                    client.output.flush()
                } catch (_: IOException) {
                    videoClients.remove(client)
                    client.close()
                    AppLogBuffer.log("Video istemcisi bağlantısı kesildi: ${client.address}")
                }
            }
        }

        if (avWebSocketClients.isNotEmpty()) {
            for (client in avWebSocketClients.toList()) {
                try {
                    client.sendVideoFrame(jpegData)
                } catch (_: IOException) {
                    avWebSocketClients.remove(client)
                    client.close()
                    AppLogBuffer.log("WebSocket video istemcisi bağlantısı kesildi: ${client.address}")
                }
            }
        }
    }

    private fun broadcastAudioChunk(pcmData: ByteArray) {
        if (audioClients.isNotEmpty()) {
            for (client in audioClients.toList()) {
                try {
                    client.writePcmChunk(pcmData)
                } catch (_: IOException) {
                    audioClients.remove(client)
                    client.close()
                    AppLogBuffer.log("Ses istemcisi bağlantısı kesildi: ${client.address}")
                }
            }
        }

        if (avWebSocketClients.isNotEmpty()) {
            for (client in avWebSocketClients.toList()) {
                try {
                    client.sendAudioChunk(pcmData)
                } catch (_: IOException) {
                    avWebSocketClients.remove(client)
                    client.close()
                    AppLogBuffer.log("WebSocket ses istemcisi bağlantısı kesildi: ${client.address}")
                }
            }
        }
    }

    private fun readHeaders(reader: BufferedReader): Map<String, String> {
        val headers = mutableMapOf<String, String>()
        while (true) {
            val headerLine = reader.readLine() ?: break
            if (headerLine.isEmpty()) break
            val colonIndex = headerLine.indexOf(':')
            if (colonIndex > 0) {
                val name = headerLine.substring(0, colonIndex).trim().lowercase(Locale.US)
                val value = headerLine.substring(colonIndex + 1).trim()
                headers[name] = value
            }
        }
        return headers
    }

    private fun isWebSocketUpgrade(headers: Map<String, String>): Boolean {
        val upgrade = headers["upgrade"]?.lowercase(Locale.US)
        if (upgrade != "websocket") return false
        val connection = headers["connection"]?.lowercase(Locale.US) ?: return false
        return connection.split(',').any { it.trim() == "upgrade" }
    }

    private fun handleVideoRequest(socket: Socket, output: BufferedOutputStream) {
        try {
            output.write("HTTP/1.1 200 OK\r\n".toByteArray())
            output.write("Content-Type: multipart/x-mixed-replace; boundary=--frame\r\n".toByteArray())
            output.write("Cache-Control: no-cache\r\n".toByteArray())
            output.write("Connection: close\r\n\r\n".toByteArray())
            output.flush()

            val client = StreamClient(socket, output)
            videoClients += client
            AppLogBuffer.log("Video istemcisi bağlandı: ${socket.remoteAddressText()}")
        } catch (ioe: IOException) {
            socket.closeQuietly()
        }
    }

    private fun handleAudioRequest(socket: Socket, output: BufferedOutputStream) {
        var client: AudioClient? = null
        try {
            output.write("HTTP/1.1 200 OK\r\n".toByteArray())
            output.write("Content-Type: audio/wav\r\n".toByteArray())
            output.write("Cache-Control: no-cache\r\n".toByteArray())
            output.write("Transfer-Encoding: chunked\r\n".toByteArray())
            output.write("Connection: close\r\n\r\n".toByteArray())
            output.flush()

            client = AudioClient(socket, output, audioSampleRate, audioChannelCount, audioBitsPerSample)
            client.writeWavHeader()
            audioClients += client
            AppLogBuffer.log("Ses istemcisi bağlandı: ${socket.remoteAddressText()}")
        } catch (ioe: IOException) {
            client?.close()
            socket.closeQuietly()
        }
    }

    private fun handleWebSocketRequest(
        socket: Socket,
        output: BufferedOutputStream,
        headers: Map<String, String>
    ) {
        val clientKey = headers["sec-websocket-key"]
        if (clientKey.isNullOrBlank()) {
            sendFixedLengthResponse(output, socket, 400, "text/plain; charset=utf-8", "Sec-WebSocket-Key eksik")
            return
        }

        val acceptKey = buildWebSocketAccept(clientKey)
        val response = buildString {
            append("HTTP/1.1 101 Switching Protocols\r\n")
            append("Upgrade: websocket\r\n")
            append("Connection: Upgrade\r\n")
            append("Sec-WebSocket-Accept: $acceptKey\r\n\r\n")
        }.toByteArray(StandardCharsets.US_ASCII)

        try {
            output.write(response)
            output.flush()
        } catch (ioe: IOException) {
            socket.closeQuietly()
            return
        }

        val client = AvWebSocketClient(
            socket = socket,
            output = output,
            input = socket.getInputStream(),
            sampleRate = audioSampleRate,
            channelCount = audioChannelCount,
            bitsPerSample = audioBitsPerSample
        )

        avWebSocketClients += client
        AppLogBuffer.log("WebSocket AV istemcisi bağlandı: ${client.address}")

        try {
            client.sendMetadata()
        } catch (_: IOException) {
            avWebSocketClients.remove(client)
            client.close()
            return
        }

        val executor = clientExecutorRef.get()
        if (executor != null) {
            executor.execute {
                client.listenForControl {
                    avWebSocketClients.remove(client)
                    AppLogBuffer.log("WebSocket AV istemcisi bağlantısı kesildi: ${client.address}")
                }
            }
        } else {
            client.close()
            avWebSocketClients.remove(client)
        }
    }

    private fun buildWebSocketAccept(clientKey: String): String {
        val trimmed = clientKey.trim()
        val concatenated = trimmed + WEBSOCKET_GUID
        val digest = MessageDigest.getInstance("SHA-1").digest(concatenated.toByteArray(StandardCharsets.ISO_8859_1))
        return Base64.encodeToString(digest, Base64.NO_WRAP)
    }


    private fun buildLandingPage(): String {
        return """
        <!DOCTYPE html>
        <html lang='tr'>
        <head>
            <meta charset='utf-8' />
            <meta name='viewport' content='width=device-width, initial-scale=1, viewport-fit=cover' />
            <title>BabyCam Canlı Yayın</title>
            <style>
                :root {
                    color-scheme: dark;
                    font-family: 'Inter', 'Segoe UI', system-ui, -apple-system, sans-serif;
                }
        
                * {
                    box-sizing: border-box;
                }
        
                body {
                    margin: 0;
                    min-height: 100vh;
                    display: flex;
                    flex-direction: column;
                    background: radial-gradient(circle at 20% 0%, #1e293b, #020617 60%);
                    color: #f8fafc;
                }
        
                main {
                    width: min(1080px, 100%);
                    margin: 48px auto 32px auto;
                    padding: 0 24px;
                    display: flex;
                    flex-direction: column;
                    gap: 28px;
                }
        
                h1,
                h2,
                p {
                    margin: 0;
                }
        
                h1 {
                    font-size: clamp(1.75rem, 2.8vw + 1rem, 2.5rem);
                    letter-spacing: -0.01em;
                }
        
                h2 {
                    font-size: clamp(1.2rem, 0.6vw + 1.1rem, 1.4rem);
                    letter-spacing: 0.01em;
                    color: #e2e8f0;
                }
        
                .card {
                    background: rgba(15, 23, 42, 0.75);
                    border-radius: 20px;
                    border: 1px solid rgba(148, 163, 184, 0.18);
                    box-shadow: 0 24px 48px rgba(2, 6, 23, 0.45);
                    backdrop-filter: blur(12px);
                    padding: clamp(20px, 4vw, 32px);
                }
        
                .page-intro {
                    display: flex;
                    flex-wrap: wrap;
                    align-items: center;
                    justify-content: space-between;
                    gap: 24px;
                }
        
                .page-intro p {
                    max-width: 560px;
                    line-height: 1.6;
                    color: rgba(226, 232, 240, 0.82);
                }
        
                .status-panel {
                    display: flex;
                    align-items: center;
                    gap: 16px;
                    padding: 18px 20px;
                    border-radius: 16px;
                    background: rgba(30, 41, 59, 0.6);
                    border: 1px solid rgba(148, 163, 184, 0.22);
                    min-width: 240px;
                }
        
                .status-label {
                    font-weight: 600;
                }
        
                .status-sub {
                    margin-top: 4px;
                    font-size: 0.85rem;
                    color: rgba(226, 232, 240, 0.65);
                }
        
                .status-dot {
                    width: 14px;
                    height: 14px;
                    border-radius: 999px;
                    flex-shrink: 0;
                    background: #9ca3af;
                    box-shadow: 0 0 0 0 rgba(148, 163, 184, 0.3);
                    transition: background 0.3s ease, box-shadow 0.3s ease;
                }
        
                .status-dot--connecting {
                    background: #facc15;
                    animation: statusPulseYellow 1.9s ease-in-out infinite;
                }
        
                .status-dot--connected {
                    background: #34d399;
                    box-shadow: 0 0 0 6px rgba(52, 211, 153, 0.25);
                }
        
                .status-dot--reconnecting {
                    background: #fb923c;
                    animation: statusPulseOrange 1.9s ease-in-out infinite;
                }
        
                .status-dot--offline {
                    background: #ef4444;
                    box-shadow: 0 0 0 6px rgba(239, 68, 68, 0.25);
                }
        
                @keyframes statusPulseYellow {
                    0% {
                        box-shadow: 0 0 0 0 rgba(250, 204, 21, 0.45);
                    }
                    70% {
                        box-shadow: 0 0 0 12px rgba(250, 204, 21, 0);
                    }
                    100% {
                        box-shadow: 0 0 0 0 rgba(250, 204, 21, 0);
                    }
                }
        
                @keyframes statusPulseOrange {
                    0% {
                        box-shadow: 0 0 0 0 rgba(249, 115, 22, 0.45);
                    }
                    70% {
                        box-shadow: 0 0 0 12px rgba(249, 115, 22, 0);
                    }
                    100% {
                        box-shadow: 0 0 0 0 rgba(249, 115, 22, 0);
                    }
                }
        
                .stream-card {
                    display: grid;
                    gap: 20px;
                }
        
                .section-header {
                    display: flex;
                    flex-direction: column;
                    gap: 6px;
                }
        
                .section-header p {
                    color: rgba(226, 232, 240, 0.78);
                    line-height: 1.6;
                }
        
                .video-wrapper {
                    position: relative;
                    border-radius: 18px;
                    background: #000;
                    min-height: clamp(220px, 50vh, 520px);
                    overflow: hidden;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
        
                .video-wrapper img {
                    width: 100%;
                    height: 100%;
                    object-fit: contain;
                    display: block;
                }
        
                .audio-controls {
                    display: flex;
                    flex-wrap: wrap;
                    align-items: center;
                    gap: 16px;
                }
        
                .status-text {
                    font-size: 0.98rem;
                    color: rgba(226, 232, 240, 0.85);
                }
        
                .primary-button {
                    padding: 10px 20px;
                    border-radius: 999px;
                    border: none;
                    background: linear-gradient(115deg, #6366f1, #8b5cf6);
                    color: #fff;
                    font-weight: 600;
                    font-size: 0.95rem;
                    cursor: pointer;
                    box-shadow: 0 16px 30px rgba(99, 102, 241, 0.35);
                    transition: transform 0.2s ease, box-shadow 0.2s ease;
                }
        
                .primary-button:hover {
                    transform: translateY(-1px);
                    box-shadow: 0 22px 36px rgba(99, 102, 241, 0.45);
                }
        
                .primary-button:active {
                    transform: translateY(0);
                    box-shadow: 0 16px 30px rgba(99, 102, 241, 0.35);
                }
        
                .primary-button.hidden {
                    display: none;
                }
        
                ul {
                    margin: 12px 0 0 0;
                    padding-left: 18px;
                    display: grid;
                    gap: 6px;
                }
        
                a {
                    color: #93c5fd;
                    text-decoration: none;
                    transition: color 0.2s ease;
                }
        
                a:hover {
                    color: #bfdbfe;
                    text-decoration: underline;
                }
        
                footer {
                    margin: 0 auto 32px auto;
                    padding: 0 24px;
                    width: min(1080px, 100%);
                    text-align: center;
                    font-size: 0.85rem;
                    color: rgba(226, 232, 240, 0.6);
                }
        
                @media (max-width: 720px) {
                    main {
                        margin: 32px auto 24px auto;
                        padding: 0 18px;
                        gap: 20px;
                    }
        
                    .card {
                        padding: 20px;
                    }
        
                    .status-panel {
                        width: 100%;
                    }
        
                    .audio-controls {
                        flex-direction: column;
                        align-items: flex-start;
                    }
        
                    footer {
                        padding: 0 18px;
                    }
                }
            </style>
        </head>
        <body>
            <main>
                <section class='page-intro card'>
                    <div>
                        <h1>BabyCam canlı yayın merkezine hoş geldiniz</h1>
                        <p>Aynı ağ üzerindeki herhangi bir cihazdan bu sayfayı açarak Eylül'ün canlı görüntüsünü ve sesini tek bağlantı üzerinden anında izleyebilirsiniz.</p>
                    </div>
                    <div class='status-panel'>
                        <span id='connectionDot' class='status-dot status-dot--connecting' aria-hidden='true'></span>
                        <div>
                            <p id='connectionLabel' class='status-label'>Canlı yayın başlatılıyor…</p>
                            <p class='status-sub'>Son kare: <span id='frameTimestamp'>-</span></p>
                        </div>
                    </div>
                </section>
        
                <section class='stream-card card'>
                    <div class='section-header'>
                        <h2>Canlı görüntü ve ses</h2>
                        <p>Eylul live cam.</p>
                    </div>
                    <figure class='video-wrapper'>
                        <img id='videoStream' src='' alt='Canlı video akışı' />
                    </figure>
                    <div class='audio-controls'>
                        <p id='audioStatus' class='status-text' aria-live='polite'>Ses akışı hazırlanıyor…</p>
                        <button id='audioButton' type='button' class='primary-button hidden'>Sesi Başlat</button>
                    </div>
                </section>
        
                <section class='card'>
                    <h2>Alternatif bağlantılar</h2>
                    <ul>
                        <li><a href='/video'>Sadece MJPEG video akışı</a></li>
                        <li><a href='/audio'>Sadece WAV ses akışı</a></li>
                    </ul>
                </section>
            </main>
            <footer>En iyi deneyim için Safari veya Chrome'un güncel sürümünü kullanmanızı öneririz.</footer>
        
            <script>
                (function() {
                    'use strict';
        
                    const audioStatus = document.getElementById('audioStatus');
                    const audioButton = document.getElementById('audioButton');
                    const videoImage = document.getElementById('videoStream');
                    const connectionDot = document.getElementById('connectionDot');
                    const connectionLabel = document.getElementById('connectionLabel');
                    const frameTimestamp = document.getElementById('frameTimestamp');
                    const userGestureEvents = ['pointerdown', 'touchstart', 'touchend', 'mousedown', 'keydown'];
                    const textDecoder = new TextDecoder('utf-8');
                    const wsScheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
                    const wsUrl = wsScheme + '://' + window.location.host + '/ws/stream';
                    const connectionStates = ['connecting', 'connected', 'reconnecting', 'offline'];
                    const retryDelay = 1800;
        
                    const AudioCtx = window.AudioContext || window.webkitAudioContext;
                    const audioContext = AudioCtx ? new AudioCtx() : null;
                    let audioMetadata = null;
                    let pendingAudioBytes = new Uint8Array(0);
                    let nextAudioTime = 0;
                    let socket = null;
                    let reconnectTimer = null;
                    let lastFrameUrl = '';
        
                    function setStatus(text, showButton) {
                        audioStatus.textContent = text;
                        audioButton.classList.toggle('hidden', !showButton);
                    }
        
                    function setConnectionState(state, message) {
                        connectionLabel.textContent = message;
                        connectionStates.forEach((name) => connectionDot.classList.remove('status-dot--' + name));
                        connectionDot.classList.add('status-dot--' + state);
                        document.title = message + ' · BabyCam';
                    }
        
                    function updateFrameTimestamp() {
                        if (!frameTimestamp) {
                            return;
                        }
                        const now = new Date();
                        frameTimestamp.textContent = now.toLocaleTimeString('tr-TR', {
                            hour: '2-digit',
                            minute: '2-digit',
                            second: '2-digit'
                        });
                    }
        
                    function revokeFrameUrl() {
                        if (lastFrameUrl) {
                            URL.revokeObjectURL(lastFrameUrl);
                            lastFrameUrl = '';
                        }
                    }
        
                    function handleAudioStateChange() {
                        if (!audioContext) {
                            return;
                        }
                        if (audioContext.state === 'running') {
                            setStatus('Ses akışı aktif.', false);
                        } else if (socket) {
                            setStatus('Tarayıcı sesi otomatik başlatamadı. Lütfen "Sesi Başlat" düğmesine dokunun.', true);
                        }
                    }
        
                    function ensureAudioUnlocked(fromUser) {
                        if (!audioContext) {
                            setStatus('Tarayıcınız bu ses akışını desteklemiyor.', false);
                            return;
                        }
        
                        if (audioContext.state === 'running') {
                            handleAudioStateChange();
                            return;
                        }
        
                        audioContext.resume().then(() => {
                            handleAudioStateChange();
                        }).catch((error) => {
                            console.warn('AudioContext resume başarısız', error);
                            if (fromUser) {
                                setStatus('Tarayıcı sesi başlatamadı. Tekrar denemek için dokunun.', true);
                            }
                        });
                    }
        
                    function scheduleAudioBuffer(channelData, frameCount, sampleRate) {
                        if (!audioContext || !socket || audioContext.state !== 'running') {
                            return;
                        }
        
                        const channels = channelData.length;
                        const buffer = audioContext.createBuffer(channels, frameCount, sampleRate);
                        for (let ch = 0; ch < channels; ch += 1) {
                            buffer.copyToChannel(channelData[ch], ch);
                        }
        
                        const source = audioContext.createBufferSource();
                        source.buffer = buffer;
                        source.connect(audioContext.destination);
        
                        const startAt = Math.max(audioContext.currentTime + 0.03, nextAudioTime);
                        source.start(startAt);
                        nextAudioTime = startAt + buffer.duration;
                    }
        
                    function clampSample(value) {
                        return Math.max(-1, Math.min(1, value));
                    }

                    function convertSample(bytes, offset, bytesPerSample) {
                        if (bytesPerSample === 1) {
                            let sample = bytes[offset];
                            sample = sample >= 128 ? sample - 256 : sample;
                            return clampSample(sample / 128);
                        }
                        if (bytesPerSample === 2) {
                            let sample = bytes[offset] | (bytes[offset + 1] << 8);
                            if (sample & 0x8000) {
                                sample = sample - 0x10000;
                            }
                            return clampSample(sample / 32768);
                        }
                        if (bytesPerSample === 3) {
                            let sample = bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
                            if (sample & 0x800000) {
                                sample = sample | 0xFF000000;
                            }
                            return clampSample(sample / 8388608);
                        }
                        if (bytesPerSample === 4) {
                            let sample = (bytes[offset] | (bytes[offset + 1] << 8) |
                                (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24));
                            return clampSample(sample / 2147483648);
                        }

                        const view = new DataView(bytes.buffer, bytes.byteOffset + offset, bytesPerSample);
                        return clampSample(view.getInt16(0, true) / 32768);
                    }

                    function handleAudioPayload(view) {
                        if (!audioMetadata || !audioContext) {
                            pendingAudioBytes = new Uint8Array(0);
                            return;
                        }

                        const bytesPerSample = Math.max(1, Math.floor(audioMetadata.bitsPerSample / 8));
                        const channels = Math.max(1, audioMetadata.channels || 1);
                        const frameStride = bytesPerSample * channels;
                        if (frameStride <= 0) {
                            return;
                        }

                        const incoming = new Uint8Array(view.buffer, 1);
                        if (incoming.length === 0) {
                            return;
                        }

                        let combined;
                        if (pendingAudioBytes.length > 0) {
                            combined = new Uint8Array(pendingAudioBytes.length + incoming.length);
                            combined.set(pendingAudioBytes, 0);
                            combined.set(incoming, pendingAudioBytes.length);
                        } else {
                            combined = incoming;
                        }

                        const availableFrames = Math.floor(combined.length / frameStride);
                        if (availableFrames <= 0) {
                            pendingAudioBytes = combined;
                            return;
                        }

                        const usableBytes = availableFrames * frameStride;
                        const payload = combined.subarray(0, usableBytes);
                        pendingAudioBytes = combined.subarray(usableBytes);

                        const channelData = Array.from({ length: channels }, () => new Float32Array(availableFrames));
                        let offset = 0;

                        for (let frame = 0; frame < availableFrames; frame += 1) {
                            for (let ch = 0; ch < channels; ch += 1) {
                                channelData[ch][frame] = convertSample(payload, offset, bytesPerSample);
                                offset += bytesPerSample;
                            }
                        }

                        scheduleAudioBuffer(channelData, availableFrames, audioMetadata.sampleRate);
                    }
        
                    function handleVideoPayload(buffer) {
                        revokeFrameUrl();
                        const blob = new Blob([buffer], { type: 'image/jpeg' });
                        lastFrameUrl = URL.createObjectURL(blob);
                        videoImage.src = lastFrameUrl;
                        updateFrameTimestamp();
                    }
        
                    function handleMetadataPayload(payload) {
                        try {
                            const json = textDecoder.decode(payload);
                            const metadata = JSON.parse(json);
                            audioMetadata = metadata;
                            pendingAudioBytes = new Uint8Array(0);
                            nextAudioTime = audioContext ? audioContext.currentTime + 0.05 : 0;
                            handleAudioStateChange();
                        } catch (error) {
                            console.warn('Metadata parse hatası', error);
                        }
                    }
        
                    function closeSocket() {
                        if (socket) {
                            try { socket.close(); } catch (e) { /* noop */ }
                            socket = null;
                        }
                    }
        
                    function scheduleReconnect() {
                        if (reconnectTimer) {
                            clearTimeout(reconnectTimer);
                        }
                        reconnectTimer = setTimeout(() => connectSocket(true), retryDelay);
                    }
        
                    function connectSocket(isRetry) {
                        closeSocket();
                        if (reconnectTimer) {
                            clearTimeout(reconnectTimer);
                            reconnectTimer = null;
                        }
        
                        audioMetadata = null;
                        pendingAudioBytes = new Uint8Array(0);
                        nextAudioTime = audioContext ? audioContext.currentTime : 0;
                        revokeFrameUrl();
        
                        setStatus(isRetry ? 'Yayın bağlantısı kopmuştu, tekrar bağlanılıyor…' : 'Canlı yayın başlatılıyor…', false);
                        setConnectionState(isRetry ? 'reconnecting' : 'connecting', isRetry ? 'Bağlantı koptu. Tekrar deniyoruz…' : 'Canlı yayın başlatılıyor…');
        
                        try {
                            socket = new WebSocket(wsUrl);
                        } catch (error) {
                            console.error('WebSocket açılamadı', error);
                            setStatus('WebSocket bağlantısı kurulamadı.', true);
                            setConnectionState('offline', 'WebSocket bağlantısı kurulamadı.');
                            scheduleReconnect();
                            return;
                        }
        
                        socket.binaryType = 'arraybuffer';
        
                        socket.addEventListener('open', () => {
                            setConnectionState('connected', 'Canlı yayın aktif.');
                            handleAudioStateChange();
                            if (audioContext) {
                                ensureAudioUnlocked(false);
                            }
                        });
        
                        socket.addEventListener('message', (event) => {
                            if (!(event.data instanceof ArrayBuffer)) {
                                return;
                            }
        
                            const buffer = event.data;
                            const view = new DataView(buffer);
                            if (view.byteLength < 1) {
                                return;
                            }
        
                            const packetType = view.getUint8(0);
                            if (packetType === 0) {
                                const payload = new Uint8Array(buffer, 1);
                                handleMetadataPayload(payload);
                            } else if (packetType === 1) {
                                handleAudioPayload(view);
                            } else if (packetType === 2) {
                                const payload = buffer.slice(1);
                                handleVideoPayload(payload);
                            }
                        });
        
                        socket.addEventListener('close', () => {
                            socket = null;
                            setStatus('Canlı yayın bağlantısı koptu. Tekrar bağlanılıyor…', false);
                            setConnectionState('reconnecting', 'Bağlantı koptu. Tekrar bağlanılıyor…');
                            scheduleReconnect();
                        });
        
                        socket.addEventListener('error', (event) => {
                            console.warn('WebSocket hatası', event);
                            setConnectionState('offline', 'Yayın sırasında hata oluştu. Tekrar denenecek.');
                            if (socket) {
                                socket.close();
                            } else {
                                scheduleReconnect();
                            }
                        });
                    }
        
                    audioButton.addEventListener('click', () => ensureAudioUnlocked(true));
        
                    userGestureEvents.forEach((eventName) => {
                        window.addEventListener(eventName, () => ensureAudioUnlocked(true), { once: false });
                    });
        
                    if (audioContext) {
                        audioContext.onstatechange = handleAudioStateChange;
                    } else {
                        setStatus('Tarayıcı ses API\'sini desteklemiyor.', false);
                    }
        
                    window.addEventListener('beforeunload', () => {
                        closeSocket();
                        revokeFrameUrl();
                    });
        
                    connectSocket(false);
                })();
            </script>
        </body>
        </html>
        """.trimIndent()
    }
    private fun sendFixedLengthResponse(
        output: BufferedOutputStream,
        socket: Socket,
        statusCode: Int,
        contentType: String,
        body: String
    ) {
        try {
            val bodyBytes = body.toByteArray(StandardCharsets.UTF_8)
            output.write("HTTP/1.1 $statusCode ${statusMessage(statusCode)}\r\n".toByteArray())
            output.write("Content-Type: $contentType\r\n".toByteArray())
            output.write("Content-Length: ${bodyBytes.size}\r\n".toByteArray())
            output.write("Connection: close\r\n\r\n".toByteArray())
            output.write(bodyBytes)
            output.flush()
        } catch (_: IOException) {
        } finally {
            socket.closeQuietly()
        }
    }

    private data class StreamClient(
        val socket: Socket,
        val output: BufferedOutputStream,
        val address: String = socket.remoteAddressText()
    ) {
        fun close() {
            try {
                output.close()
            } catch (_: IOException) {
            }
            socket.closeQuietly()
        }
    }

    private class AudioClient(
        val socket: Socket,
        private val output: BufferedOutputStream,
        private val sampleRate: Int,
        private val channelCount: Int,
        private val bitsPerSample: Int,
        val address: String = socket.remoteAddressText()
    ) {
        private val crlf = "\r\n".toByteArray(StandardCharsets.US_ASCII)

        @Throws(IOException::class)
        fun writeWavHeader() {
            val header = buildWavHeader()
            writeChunk(header, header.size)
        }

        fun close() {
            try {
                output.close()
            } catch (_: IOException) {
            }
            socket.closeQuietly()
        }

        @Throws(IOException::class)
        fun writePcmChunk(pcmData: ByteArray) {
            if (pcmData.isEmpty()) return
            writeChunk(pcmData, pcmData.size)
        }

        @Throws(IOException::class)
        private fun writeChunk(data: ByteArray, length: Int) {
            val sizeHex = length.toString(16)
            output.write(sizeHex.toByteArray(StandardCharsets.US_ASCII))
            output.write(crlf)
            output.write(data, 0, length)
            output.write(crlf)
            output.flush()
        }

        private fun buildWavHeader(): ByteArray {
            val bytesPerSample = (bitsPerSample / 8).coerceAtLeast(1)
            val blockAlign = (channelCount * bytesPerSample).coerceAtLeast(1)
            val byteRate = sampleRate * blockAlign

            val maxDataSize = Int.MAX_VALUE - 36
            val alignedDataSize = maxDataSize - (maxDataSize % blockAlign)
            val riffChunkSize = alignedDataSize + 36

            val header = ByteArray(44)
            header.writeString(0, "RIFF")
            header.writeIntLE(4, riffChunkSize)
            header.writeString(8, "WAVE")
            header.writeString(12, "fmt ")
            header.writeIntLE(16, 16)
            header.writeShortLE(20, 1.toShort())
            header.writeShortLE(22, channelCount.toShort())
            header.writeIntLE(24, sampleRate)
            header.writeIntLE(28, byteRate)
            header.writeShortLE(32, blockAlign.toShort())
            header.writeShortLE(34, bitsPerSample.toShort())
            header.writeString(36, "data")
            header.writeIntLE(40, alignedDataSize)
            return header
        }

        private fun ByteArray.writeString(offset: Int, value: String) {
            val bytes = value.toByteArray()
            System.arraycopy(bytes, 0, this, offset, bytes.size)
        }

        private fun ByteArray.writeIntLE(offset: Int, value: Int) {
            this[offset] = (value and 0xFF).toByte()
            this[offset + 1] = ((value shr 8) and 0xFF).toByte()
            this[offset + 2] = ((value shr 16) and 0xFF).toByte()
            this[offset + 3] = ((value shr 24) and 0xFF).toByte()
        }

        private fun ByteArray.writeShortLE(offset: Int, value: Short) {
            this[offset] = (value.toInt() and 0xFF).toByte()
            this[offset + 1] = ((value.toInt() shr 8) and 0xFF).toByte()
        }
    }

    private class AvWebSocketClient(
        private val socket: Socket,
        private val output: BufferedOutputStream,
        private val input: InputStream,
        private val sampleRate: Int,
        private val channelCount: Int,
        private val bitsPerSample: Int,
        val address: String = socket.remoteAddressText()
    ) {
        private val closed = AtomicBoolean(false)

        fun sendMetadata() {
            val metadataJson = "{" +
                "\"sampleRate\":$sampleRate," +
                "\"channels\":$channelCount," +
                "\"bitsPerSample\":$bitsPerSample" +
                "}"
            val payload = metadataJson.toByteArray(StandardCharsets.UTF_8)
            sendFrame(TYPE_METADATA, payload)
        }

        @Throws(IOException::class)
        fun sendAudioChunk(pcmData: ByteArray) {
            if (pcmData.isEmpty()) return
            sendFrame(TYPE_AUDIO, pcmData)
        }

        @Throws(IOException::class)
        fun sendVideoFrame(jpegData: ByteArray) {
            if (jpegData.isEmpty()) return
            sendFrame(TYPE_VIDEO, jpegData)
        }

        fun listenForControl(onClosed: () -> Unit) {
            try {
                while (!closed.get()) {
                    val firstByte = input.read()
                    if (firstByte == -1) break
                    val secondByte = input.read()
                    if (secondByte == -1) break

                    val opcode = firstByte and 0x0F
                    val masked = (secondByte and 0x80) != 0
                    var payloadLength = (secondByte and 0x7F).toLong()

                    payloadLength = when (payloadLength) {
                        126L -> readUnsignedShort().toLong()
                        127L -> readLong()
                        else -> payloadLength
                    }

                    if (payloadLength < 0 || payloadLength > MAX_PAYLOAD_LENGTH) {
                        break
                    }

                    val maskingKey = if (masked) ByteArray(4) else null
                    if (masked) {
                        readFully(maskingKey!!)
                    }

                    val payload = ByteArray(payloadLength.toInt())
                    readFully(payload)

                    if (masked && maskingKey != null) {
                        for (i in payload.indices) {
                            payload[i] = (payload[i].toInt() xor maskingKey[i % 4].toInt()).toByte()
                        }
                    }

                    when (opcode) {
                        0x8 -> break // Close frame
                        0x9 -> sendControlFrame(0xA, payload) // Ping -> Pong
                        else -> { /* diğer mesajları yok say */ }
                    }
                }
            } catch (_: IOException) {
            } finally {
                close()
                onClosed()
            }
        }

        fun close() {
            if (!closed.compareAndSet(false, true)) {
                return
            }
            try {
                sendControlFrame(0x8, ByteArray(0))
            } catch (_: IOException) {
            }
            try {
                output.close()
            } catch (_: IOException) {
            }
            socket.closeQuietly()
        }

        @Throws(IOException::class)
        private fun sendFrame(type: Byte, payload: ByteArray) {
            if (closed.get()) return
            val opcode = 0x2 // binary frame
            val totalLength = payload.size + 1
            val buffer = ByteArray(totalLength)
            buffer[0] = type
            System.arraycopy(payload, 0, buffer, 1, payload.size)
            writeFrame(opcode, buffer)
        }

        @Throws(IOException::class)
        private fun sendControlFrame(opcode: Int, payload: ByteArray) {
            if (closed.get()) return
            writeFrame(opcode, payload)
        }

        @Throws(IOException::class)
        private fun writeFrame(opcode: Int, payload: ByteArray) {
            synchronized(output) {
                output.write(0x80 or opcode)
                val length = payload.size
                when {
                    length <= 125 -> {
                        output.write(length)
                    }
                    length <= 0xFFFF -> {
                        output.write(126)
                        output.write((length shr 8) and 0xFF)
                        output.write(length and 0xFF)
                    }
                    else -> {
                        output.write(127)
                        val len = length.toLong()
                        for (i in 7 downTo 0) {
                            output.write(((len shr (8 * i)) and 0xFF).toInt())
                        }
                    }
                }
                output.write(payload)
                output.flush()
            }
        }

        @Throws(IOException::class)
        private fun readUnsignedShort(): Int {
            val high = input.read()
            val low = input.read()
            if (high == -1 || low == -1) {
                throw IOException("Beklenmedik websocket sonu")
            }
            return (high shl 8) or low
        }

        @Throws(IOException::class)
        private fun readLong(): Long {
            val bytes = ByteArray(8)
            readFully(bytes)
            var value = 0L
            for (b in bytes) {
                value = (value shl 8) or (b.toInt() and 0xFF).toLong()
            }
            return value
        }

        @Throws(IOException::class)
        private fun readFully(buffer: ByteArray) {
            var read = 0
            while (read < buffer.size) {
                val result = input.read(buffer, read, buffer.size - read)
                if (result == -1) {
                    throw IOException("Veri okunamadı")
                }
                read += result
            }
        }

        companion object {
            private const val MAX_PAYLOAD_LENGTH = 8L * 1024 * 1024 // 8 MB
            private const val TYPE_METADATA: Byte = 0
            private const val TYPE_AUDIO: Byte = 1
            private const val TYPE_VIDEO: Byte = 2
        }
    }

    companion object {
        private const val WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    }
}

private fun statusMessage(statusCode: Int): String = when (statusCode) {
    200 -> "OK"
    404 -> "Not Found"
    400 -> "Bad Request"
    else -> ""
}

private fun ServerSocket.closeQuietly() {
    try {
        close()
    } catch (_: IOException) {
    }
}

private fun Socket.closeQuietly() {
    try {
        close()
    } catch (_: IOException) {
    }
}

private fun Socket.remoteAddressText(): String {
    return try {
        val inet = (remoteSocketAddress as? InetSocketAddress)?.address ?: inetAddress
        inet?.hostAddress ?: remoteSocketAddress?.toString() ?: "<bilinmiyor>"
    } catch (_: Exception) {
        "<bilinmiyor>"
    }
}

private fun Thread.joinSafely() {
    try {
        join(500)
    } catch (_: InterruptedException) {
        interrupt()
    }
}
