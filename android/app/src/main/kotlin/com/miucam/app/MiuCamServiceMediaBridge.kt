package com.miucam.app

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicLong

/**
 * Bounded platform-channel boundary for media captured by
 * [MiuCamForegroundService]. Camera and microphone ownership never moves to
 * the Flutter Activity; Dart only attaches as a consumer of already-owned
 * service media.
 */
object MiuCamServiceMediaBridge : EventChannel.StreamHandler {
    const val METHOD_CHANNEL = "miucam/android_service_media"
    const val EVENT_CHANNEL = "miucam/android_service_media_events"

    private const val MAX_QUEUED_EVENTS = 8
    private const val DEFAULT_READY_TIMEOUT_MS = 8_000L
    private const val MIN_READY_TIMEOUT_MS = 500L
    private const val MAX_READY_TIMEOUT_MS = 15_000L

    private val mainHandler = Handler(Looper.getMainLooper())
    private val eventSequence = AtomicLong(0)
    private val audioEventSequence = AtomicLong(0)
    private val waiterSequence = AtomicLong(0)
    private val eventQueue = ArrayDeque<QueuedEvent>()
    private val readyWaiters = mutableListOf<ReadyWaiter>()
    private var captureEngine: MiuCamServiceMediaCapture? = null

    internal fun registerCaptureEngine(capture: MiuCamServiceMediaCapture) {
        captureEngine = capture
    }

    internal fun unregisterCaptureEngine(capture: MiuCamServiceMediaCapture) {
        if (captureEngine === capture) captureEngine = null
    }

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var consumerAttached = false

    @Volatile
    private var consumerVideo = false

    @Volatile
    private var consumerVideoEncoding = false

    @Volatile
    private var consumerAudio = false

    @Volatile
    private var cameraRequested = false

    @Volatile
    private var microphoneRequested = false

    @Volatile
    private var cameraActive = false

    @Volatile
    private var microphoneActive = false

    @Volatile
    private var cameraError: String? = null

    @Volatile
    private var microphoneError: String? = null

    @Volatile
    private var jpegQuality = 68

    @Volatile
    private var maxVideoFps = 8

    private var drainScheduled = false
    private var videoFrames = 0L
    private var audioChunks = 0L
    private var videoEventsDropped = 0L
    private var audioEventsDropped = 0L
    private var lastVideoAtMs = 0L
    private var lastAudioAtMs = 0L
    private var lastVideoBytes = 0
    private var lastAudioBytes = 0

    val wantsVideo: Boolean
        get() = consumerAttached && consumerVideo && eventSink != null

    val wantsVideoEncoding: Boolean
        get() = wantsVideo && consumerVideoEncoding

    val wantsAudio: Boolean
        get() = consumerAttached && consumerAudio && eventSink != null

    val configuredJpegQuality: Int
        get() = jpegQuality

    val configuredMaxVideoFps: Int
        get() = maxVideoFps

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        synchronized(this) {
            eventSink = events
            eventQueue.clear()
            drainScheduled = false
        }
        enqueueControl("snapshot", snapshot())
    }

    override fun onCancel(arguments: Any?) {
        synchronized(this) {
            eventSink = null
            eventQueue.clear()
            drainScheduled = false
        }
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "attach" -> {
                val arguments = call.arguments as? Map<*, *>
                jpegQuality = ((arguments?.get("jpegQuality") as? Number)?.toInt() ?: 68)
                    .coerceIn(35, 90)
                maxVideoFps = ((arguments?.get("maxVideoFps") as? Number)?.toInt() ?: 8)
                    .coerceIn(1, 15)
                consumerAttached = true
                enqueueControl("consumerAttached", snapshot())
                result.success(snapshot())
            }
            "setConsumerDemand" -> {
                val arguments = call.arguments as? Map<*, *>
                val video = arguments?.get("video") as? Boolean ?: false
                val audio = arguments?.get("audio") as? Boolean ?: false
                val encodeVideo = arguments?.get("encodeVideo") as? Boolean ?: video
                if ((video || audio) && !consumerAttached) {
                    result.error(
                        "NATIVE_MEDIA_CONSUMER_NOT_ATTACHED",
                        "Attach the Dart consumer before requesting native media.",
                        snapshot()
                    )
                    return
                }
                synchronized(this) {
                    consumerVideo = consumerAttached && video
                    consumerVideoEncoding = consumerAttached && video && encodeVideo
                    consumerAudio = consumerAttached && audio
                    discardUndemandedEventsLocked()
                }
                enqueueControl("consumerDemandChanged", snapshot())
                result.success(snapshot())
            }
            "setMediaPolicy" -> {
                val arguments = call.arguments as? Map<*, *>
                jpegQuality =
                    ((arguments?.get("jpegQuality") as? Number)?.toInt() ?: jpegQuality)
                        .coerceIn(35, 90)
                maxVideoFps =
                    ((arguments?.get("maxVideoFps") as? Number)?.toInt() ?: maxVideoFps)
                        .coerceIn(1, 15)
                enqueueControl("mediaPolicyChanged", snapshot())
                result.success(snapshot())
            }
            "setTorchEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val capture = captureEngine
                if (capture == null) {
                    result.success(false)
                } else {
                    capture.setTorchEnabled(enabled) { applied -> result.success(applied) }
                }
            }
            "awaitReady" -> {
                val arguments = call.arguments as? Map<*, *>
                val video = arguments?.get("video") as? Boolean ?: false
                val audio = arguments?.get("audio") as? Boolean ?: false
                val timeoutMs = (
                    (arguments?.get("timeoutMs") as? Number)?.toLong()
                        ?: DEFAULT_READY_TIMEOUT_MS
                    ).coerceIn(MIN_READY_TIMEOUT_MS, MAX_READY_TIMEOUT_MS)
                awaitReady(video, audio, timeoutMs, result)
            }
            "detach" -> {
                detachConsumer("dart_detach")
                result.success(snapshot())
            }
            "snapshot" -> result.success(snapshot())
            "resetDiagnostics" -> {
                resetDiagnostics()
                result.success(snapshot())
            }
            else -> result.notImplemented()
        }
    }

    fun updateCaptureState(
        cameraRequested: Boolean,
        microphoneRequested: Boolean,
        cameraActive: Boolean,
        microphoneActive: Boolean,
        cameraError: String? = null,
        microphoneError: String? = null
    ) {
        this.cameraRequested = cameraRequested
        this.microphoneRequested = microphoneRequested
        this.cameraActive = cameraActive
        this.microphoneActive = microphoneActive
        this.cameraError = cameraError
        this.microphoneError = microphoneError
        val details = snapshot()
        enqueueControl("captureState", details)
        MiuCamPlatformRuntime.setNativeMediaCaptureState(
            cameraRequested = cameraRequested,
            microphoneRequested = microphoneRequested,
            cameraActive = cameraActive,
            microphoneActive = microphoneActive,
            cameraError = cameraError,
            microphoneError = microphoneError,
            diagnostics = details
        )
        mainHandler.post { completeReadyWaiters() }
    }

    fun publishVideo(
        jpeg: ByteArray,
        timestampMs: Long,
        capturedAtMonoUs: Long,
        width: Int,
        height: Int,
        rotationDegrees: Int,
        lumaBytes: ByteArray,
        lumaWidth: Int,
        lumaHeight: Int
    ) {
        if (!wantsVideo) return
        synchronized(this) {
            videoFrames += 1
            lastVideoAtMs = timestampMs
            lastVideoBytes = jpeg.size
        }
        enqueueMedia(
            kind = MediaKind.VIDEO,
            payload = mapOf(
                "type" to "video",
                "sequence" to eventSequence.incrementAndGet(),
                "timestampMs" to timestampMs,
                "capturedAtMonoUs" to capturedAtMonoUs,
                "width" to width,
                "height" to height,
                "rotationDegrees" to rotationDegrees,
                "format" to "jpeg",
                "lumaBytes" to lumaBytes,
                "lumaWidth" to lumaWidth,
                "lumaHeight" to lumaHeight,
                "bytes" to jpeg
            )
        )
    }

    fun publishAudio(
        pcm16le: ByteArray,
        timestampMs: Long,
        capturedAtMonoUs: Long,
        sampleRate: Int,
        channels: Int
    ) {
        if (!wantsAudio || pcm16le.isEmpty()) return
        synchronized(this) {
            audioChunks += 1
            lastAudioAtMs = timestampMs
            lastAudioBytes = pcm16le.size
        }
        enqueueMedia(
            kind = MediaKind.AUDIO,
            payload = mapOf(
                "type" to "audio",
                "sequence" to eventSequence.incrementAndGet(),
                // Dedicated to audio because the global sequence also contains
                // video/control events and therefore cannot prove that no PCM
                // chunk was dropped by the bounded platform-channel queue.
                "audioSequence" to audioEventSequence.incrementAndGet(),
                "timestampMs" to timestampMs,
                "capturedAtMonoUs" to capturedAtMonoUs,
                "sampleRate" to sampleRate,
                "channels" to channels,
                "encoding" to "pcm16le",
                "bytes" to pcm16le
            )
        )
    }

    fun publishCaptureError(resource: String, message: String) {
        enqueueControl(
            "error",
            mapOf("resource" to resource, "message" to message)
        )
    }

    @Synchronized
    fun snapshot(): Map<String, Any?> = mapOf(
        "consumerAttached" to consumerAttached,
        "eventListenerAttached" to (eventSink != null),
        "consumerVideo" to consumerVideo,
        "consumerVideoEncoding" to consumerVideoEncoding,
        "consumerAudio" to consumerAudio,
        "cameraRequested" to cameraRequested,
        "microphoneRequested" to microphoneRequested,
        "cameraActive" to cameraActive,
        "microphoneActive" to microphoneActive,
        "cameraError" to cameraError,
        "microphoneError" to microphoneError,
        "jpegQuality" to jpegQuality,
        "maxVideoFps" to maxVideoFps,
        "queuedEvents" to eventQueue.size,
        "maxQueuedEvents" to MAX_QUEUED_EVENTS,
        "videoFrames" to videoFrames,
        "audioChunks" to audioChunks,
        "videoEventsDropped" to videoEventsDropped,
        "audioEventsDropped" to audioEventsDropped,
        "lastVideoAtMs" to lastVideoAtMs.takeIf { it > 0 },
        "lastAudioAtMs" to lastAudioAtMs.takeIf { it > 0 },
        "lastVideoBytes" to lastVideoBytes,
        "lastAudioBytes" to lastAudioBytes
    )

    @Synchronized
    private fun resetDiagnostics() {
        videoFrames = 0
        audioChunks = 0
        videoEventsDropped = 0
        audioEventsDropped = 0
        lastVideoAtMs = 0
        lastAudioAtMs = 0
        lastVideoBytes = 0
        lastAudioBytes = 0
    }

    private fun detachConsumer(reason: String) {
        captureEngine?.setTorchEnabled(false) {}
        val waiters: List<ReadyWaiter>
        synchronized(this) {
            consumerAttached = false
            consumerVideo = false
            consumerVideoEncoding = false
            consumerAudio = false
            eventQueue.clear()
            waiters = readyWaiters.toList()
            readyWaiters.clear()
        }
        waiters.forEach { waiter ->
            waiter.result.error(
                "NATIVE_MEDIA_CONSUMER_DETACHED",
                "Native media consumer detached before capture became ready.",
                mapOf("reason" to reason)
            )
        }
    }

    private fun awaitReady(
        video: Boolean,
        audio: Boolean,
        timeoutMs: Long,
        result: MethodChannel.Result
    ) {
        val immediate = readiness(video, audio)
        if (immediate != null) {
            completeResult(result, immediate)
            return
        }
        val waiter = ReadyWaiter(
            id = waiterSequence.incrementAndGet(),
            video = video,
            audio = audio,
            result = result
        )
        synchronized(this) { readyWaiters += waiter }
        mainHandler.postDelayed({ timeoutReadyWaiter(waiter.id) }, timeoutMs)
    }

    private fun timeoutReadyWaiter(id: Long) {
        val waiter = synchronized(this) {
            val index = readyWaiters.indexOfFirst { it.id == id }
            if (index < 0) null else readyWaiters.removeAt(index)
        } ?: return
        waiter.result.error(
            "NATIVE_MEDIA_CAPTURE_TIMEOUT",
            "Service-owned media capture did not become ready in time.",
            snapshot()
        )
    }

    private fun completeReadyWaiters() {
        val completions = mutableListOf<Pair<ReadyWaiter, Readiness>>()
        synchronized(this) {
            val iterator = readyWaiters.iterator()
            while (iterator.hasNext()) {
                val waiter = iterator.next()
                val readiness = readiness(waiter.video, waiter.audio) ?: continue
                iterator.remove()
                completions += waiter to readiness
            }
        }
        completions.forEach { (waiter, readiness) ->
            completeResult(waiter.result, readiness)
        }
    }

    private fun readiness(video: Boolean, audio: Boolean): Readiness? {
        val cameraFailure = cameraError
        if (video && cameraFailure != null) {
            return Readiness.Failure("camera", cameraFailure)
        }
        val microphoneFailure = microphoneError
        if (audio && microphoneFailure != null) {
            return Readiness.Failure("microphone", microphoneFailure)
        }
        if ((!video || cameraActive) && (!audio || microphoneActive)) {
            return Readiness.Ready
        }
        return null
    }

    private fun completeResult(result: MethodChannel.Result, readiness: Readiness) {
        when (readiness) {
            Readiness.Ready -> result.success(snapshot())
            is Readiness.Failure -> result.error(
                "NATIVE_MEDIA_CAPTURE_FAILED",
                "${readiness.resource}: ${readiness.message}",
                snapshot()
            )
        }
    }

    private fun enqueueControl(type: String, details: Map<String, Any?>) {
        val payload = HashMap<String, Any?>()
        payload.putAll(details)
        payload["type"] = type
        payload["sequence"] = eventSequence.incrementAndGet()
        payload["timestampMs"] = System.currentTimeMillis()
        enqueueMedia(MediaKind.CONTROL, payload)
    }

    private fun enqueueMedia(kind: MediaKind, payload: Map<String, Any?>) {
        var scheduleDrain = false
        synchronized(this) {
            if (eventSink == null) return
            if (kind == MediaKind.VIDEO && (!consumerAttached || !consumerVideo)) return
            if (kind == MediaKind.AUDIO && (!consumerAttached || !consumerAudio)) return

            if (kind == MediaKind.VIDEO) {
                val iterator = eventQueue.iterator()
                while (iterator.hasNext()) {
                    if (iterator.next().kind == MediaKind.VIDEO) {
                        iterator.remove()
                        videoEventsDropped += 1
                        break
                    }
                }
            }
            while (eventQueue.size >= MAX_QUEUED_EVENTS) {
                val dropIndex = eventQueue.indexOfFirst { queued ->
                    queued.kind == MediaKind.AUDIO || queued.kind == kind
                }
                if (dropIndex < 0) {
                    if (kind == MediaKind.AUDIO) audioEventsDropped += 1
                    if (kind == MediaKind.VIDEO) videoEventsDropped += 1
                    return
                }
                val dropped = eventQueue.removeAtCompat(dropIndex)
                if (dropped.kind == MediaKind.AUDIO) audioEventsDropped += 1
                if (dropped.kind == MediaKind.VIDEO) videoEventsDropped += 1
            }
            eventQueue.addLast(QueuedEvent(kind, payload))
            if (!drainScheduled) {
                drainScheduled = true
                scheduleDrain = true
            }
        }
        if (scheduleDrain) mainHandler.post(::drainOne)
    }

    private fun drainOne() {
        val queued: QueuedEvent
        val sink: EventChannel.EventSink
        synchronized(this) {
            val currentSink = eventSink
            val current = eventQueue.pollFirst()
            if (currentSink == null || current == null) {
                eventQueue.clear()
                drainScheduled = false
                return
            }
            sink = currentSink
            queued = current
        }
        try {
            sink.success(queued.payload)
        } catch (_: RuntimeException) {
            // Flutter can detach while a main-thread delivery is already queued.
        }
        val hasMore = synchronized(this) {
            if (eventSink == null || eventQueue.isEmpty()) {
                drainScheduled = false
                false
            } else {
                true
            }
        }
        if (hasMore) mainHandler.post(::drainOne)
    }

    private fun discardUndemandedEventsLocked() {
        val iterator = eventQueue.iterator()
        while (iterator.hasNext()) {
            val event = iterator.next()
            val discard = (event.kind == MediaKind.VIDEO && !consumerVideo) ||
                (event.kind == MediaKind.AUDIO && !consumerAudio)
            if (discard) iterator.remove()
        }
    }

    private fun <T> ArrayDeque<T>.removeAtCompat(index: Int): T {
        val iterator = iterator()
        var currentIndex = 0
        while (iterator.hasNext()) {
            val value = iterator.next()
            if (currentIndex == index) {
                iterator.remove()
                return value
            }
            currentIndex += 1
        }
        throw IndexOutOfBoundsException("Queue index $index")
    }

    private data class QueuedEvent(
        val kind: MediaKind,
        val payload: Map<String, Any?>
    )

    private data class ReadyWaiter(
        val id: Long,
        val video: Boolean,
        val audio: Boolean,
        val result: MethodChannel.Result
    )

    private enum class MediaKind { VIDEO, AUDIO, CONTROL }

    private sealed interface Readiness {
        data object Ready : Readiness
        data class Failure(val resource: String, val message: String) : Readiness
    }
}
