package com.miucam.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Camera/microphone capture engine whose lifecycle owner is the foreground
 * service. It intentionally has no Activity, PreviewView, Flutter camera
 * plugin, or record plugin dependency.
 */
internal class MiuCamServiceMediaCapture(
    context: Context,
    private val lifecycleOwner: LifecycleOwner
) {
    private val applicationContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = ContextCompat.getMainExecutor(applicationContext)
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor(
        NamedThreadFactory("MiuCam-CameraAnalysis")
    )
    private val audioRunning = AtomicBoolean(false)
    private val audioLock = Any()

    @Volatile
    private var destroyed = false

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

    private var cameraGeneration = 0
    private var cameraStarting = false
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var lastEncodedFrameAtNs = 0L
    private var audioGeneration = 0
    private var audioRecord: AudioRecord? = null
    private var audioThread: Thread? = null
    @Volatile
    private var microphoneRetryAttempt = 0L
    private var microphoneRetryRunnable: Runnable? = null
    private var microphoneStartedAtElapsedMs = 0L
    private val microphoneRetryBackoff = ContinuousCappedBackoff(
        baseDelayMs = MICROPHONE_RETRY_BASE_DELAY_MS,
        maxDelayMs = MICROPHONE_RETRY_MAX_DELAY_MS
    )

    fun reconcile(camera: Boolean, microphone: Boolean) {
        check(Looper.myLooper() == Looper.getMainLooper()) {
            "Service media demand must be reconciled on the Android main thread."
        }
        if (destroyed) return
        val microphoneWasRequested = microphoneRequested
        cameraRequested = camera
        microphoneRequested = microphone

        if (camera) startCamera() else stopCamera(clearError = true)
        if (microphone) {
            if (!microphoneWasRequested) {
                cancelMicrophoneRetry()
                microphoneRetryAttempt = 0L
            }
            startMicrophone()
        } else {
            cancelMicrophoneRetry()
            microphoneRetryAttempt = 0L
            stopMicrophone(clearError = true)
        }
        publishState()
    }

    fun shutdown(reason: String) {
        if (destroyed) return
        destroyed = true
        cameraRequested = false
        microphoneRequested = false
        cancelMicrophoneRetry()
        microphoneRetryAttempt = 0L
        stopCamera(clearError = true)
        stopMicrophone(clearError = true)
        cameraExecutor.shutdownNow()
        MiuCamServiceMediaBridge.updateCaptureState(
            cameraRequested = false,
            microphoneRequested = false,
            cameraActive = false,
            microphoneActive = false
        )
        MiuCamPlatformRuntime.emit(
            "nativeMediaCaptureReleased",
            mapOf("reason" to reason)
        )
    }

    private fun startCamera() {
        if (cameraActive || cameraStarting) return
        cameraError = null
        if (!hasPermission(Manifest.permission.CAMERA)) {
            failCamera("camera_permission_denied")
            return
        }

        val generation = ++cameraGeneration
        cameraStarting = true
        publishState()
        val providerFuture = ProcessCameraProvider.getInstance(applicationContext)
        providerFuture.addListener(
            {
                if (destroyed || !cameraRequested || generation != cameraGeneration) {
                    return@addListener
                }
                try {
                    val provider = providerFuture.get()
                    val analysis = ImageAnalysis.Builder()
                        .setResolutionSelector(
                            ResolutionSelector.Builder()
                                .setResolutionStrategy(
                                    ResolutionStrategy(
                                        Size(CAMERA_WIDTH, CAMERA_HEIGHT),
                                        ResolutionStrategy
                                            .FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                                    )
                                )
                                .build()
                        )
                        // CameraX's 640x480 YUV rotation costs roughly one
                        // analysis-frame pass and avoids Bitmap decode + a
                        // second JPEG encode on the common 90-degree path.
                        .setOutputImageRotationEnabled(true)
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                    analysis.setAnalyzer(cameraExecutor, ::analyzeFrame)
                    val selector = when {
                        provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) ->
                            CameraSelector.DEFAULT_BACK_CAMERA
                        provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) ->
                            CameraSelector.DEFAULT_FRONT_CAMERA
                        else -> throw IllegalStateException("no_camera_available")
                    }

                    imageAnalysis?.let { previous ->
                        previous.clearAnalyzer()
                        provider.unbind(previous)
                    }
                    provider.bindToLifecycle(lifecycleOwner, selector, analysis)
                    cameraProvider = provider
                    imageAnalysis = analysis
                    cameraStarting = false
                    cameraActive = true
                    cameraError = null
                    lastEncodedFrameAtNs = 0L
                    publishState()
                } catch (error: Throwable) {
                    failCamera(error.describe("camera_start_failed"))
                }
            },
            mainExecutor
        )
    }

    private fun stopCamera(clearError: Boolean) {
        cameraGeneration += 1
        cameraStarting = false
        cameraActive = false
        lastEncodedFrameAtNs = 0L
        val analysis = imageAnalysis
        imageAnalysis = null
        analysis?.clearAnalyzer()
        if (analysis != null) {
            try {
                cameraProvider?.unbind(analysis)
            } catch (_: RuntimeException) {
                // The provider may already be tearing down with the lifecycle.
            }
        }
        if (clearError) cameraError = null
    }

    private fun failCamera(message: String) {
        cameraStarting = false
        cameraActive = false
        cameraError = message
        imageAnalysis?.clearAnalyzer()
        imageAnalysis = null
        MiuCamServiceMediaBridge.publishCaptureError("camera", message)
        publishState()
    }

    private fun analyzeFrame(image: ImageProxy) {
        try {
            if (destroyed || !cameraRequested || !MiuCamServiceMediaBridge.wantsVideo) {
                return
            }
            val nowNs = SystemClock.elapsedRealtimeNanos()
            val frameIntervalNs = 1_000_000_000L /
                MiuCamServiceMediaBridge.configuredMaxVideoFps.coerceAtLeast(1)
            if (lastEncodedFrameAtNs > 0 && nowNs - lastEncodedFrameAtNs < frameIntervalNs) {
                return
            }
            lastEncodedFrameAtNs = nowNs
            val rotation = normalizeRotation(image.imageInfo.rotationDegrees)
            val lumaSample = sampleLuma(
                image,
                targetWidth = LUMA_WIDTH,
                targetHeight = LUMA_HEIGHT
            )
            val encoded = if (MiuCamServiceMediaBridge.wantsVideoEncoding) {
                encodeJpeg(
                    image,
                    rotationDegrees = rotation,
                    quality = MiuCamServiceMediaBridge.configuredJpegQuality
                )
            } else {
                ByteArray(0)
            }
            val outputWidth = if (rotation == 90 || rotation == 270) image.height else image.width
            val outputHeight = if (rotation == 90 || rotation == 270) image.width else image.height
            MiuCamServiceMediaBridge.publishVideo(
                jpeg = encoded,
                timestampMs = System.currentTimeMillis(),
                capturedAtMonoUs = image.imageInfo.timestamp / 1_000L,
                width = outputWidth,
                height = outputHeight,
                rotationDegrees = 0,
                lumaBytes = lumaSample,
                lumaWidth = LUMA_WIDTH,
                lumaHeight = LUMA_HEIGHT
            )
        } catch (error: Throwable) {
            MiuCamServiceMediaBridge.publishCaptureError(
                "camera_frame",
                error.describe("camera_frame_failed")
            )
        } finally {
            image.close()
        }
    }

    private fun startMicrophone() {
        synchronized(audioLock) {
            if (microphoneActive || audioRunning.get()) return
        }
        microphoneError = null
        if (
            ContextCompat.checkSelfPermission(
                applicationContext,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            failMicrophone("microphone_permission_denied", retryable = false)
            return
        }

        var pendingRecorder: AudioRecord? = null
        try {
            val channelMask = AudioFormat.CHANNEL_IN_MONO
            val minBufferSize = AudioRecord.getMinBufferSize(
                AUDIO_SAMPLE_RATE,
                channelMask,
                AudioFormat.ENCODING_PCM_16BIT
            )
            if (minBufferSize <= 0) {
                throw IllegalStateException("AudioRecord.getMinBufferSize=$minBufferSize")
            }
            val bufferSize = maxOf(minBufferSize * 2, AUDIO_CHUNK_BYTES * 4)
            val recorder = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                AUDIO_SAMPLE_RATE,
                channelMask,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )
            pendingRecorder = recorder
            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                throw IllegalStateException("AudioRecord state=${recorder.state}")
            }
            recorder.startRecording()
            if (recorder.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                throw IllegalStateException(
                    "AudioRecord recordingState=${recorder.recordingState}"
                )
            }

            val generation = ++audioGeneration
            val thread = Thread(
                { captureAudio(generation, recorder) },
                "MiuCam-AudioRecord"
            ).apply { isDaemon = true }
            synchronized(audioLock) {
                audioRecord = recorder
                audioThread = thread
                audioRunning.set(true)
                microphoneActive = true
                microphoneError = null
                microphoneStartedAtElapsedMs = SystemClock.elapsedRealtime()
            }
            pendingRecorder = null
            thread.start()
            publishState()
        } catch (error: Throwable) {
            pendingRecorder?.let { recorder ->
                try {
                    if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                        recorder.stop()
                    }
                } catch (_: IllegalStateException) {}
                recorder.release()
            }
            failMicrophone(
                error.describe("microphone_start_failed"),
                retryable = true
            )
        }
    }

    private fun captureAudio(generation: Int, recorder: AudioRecord) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
        val buffer = ByteArray(AUDIO_CHUNK_BYTES)
        var stabilityReported = false
        while (audioRunning.get() && generation == audioGeneration && !destroyed) {
            val read = try {
                recorder.read(
                    buffer,
                    0,
                    buffer.size,
                    AudioRecord.READ_BLOCKING
                )
            } catch (error: Throwable) {
                if (audioRunning.get()) {
                    postMicrophoneFailure(generation, error.describe("microphone_read_failed"))
                }
                break
            }
            if (read > 0) {
                if (
                    !stabilityReported &&
                    microphoneRetryAttempt > 0L &&
                    SystemClock.elapsedRealtime() - microphoneStartedAtElapsedMs >=
                    MICROPHONE_RETRY_STABILITY_MS
                ) {
                    stabilityReported = true
                    mainHandler.post {
                        if (generation == audioGeneration && microphoneActive) {
                            microphoneRetryAttempt = 0L
                            MiuCamPlatformRuntime.emit(
                                "nativeMicrophoneRecoveryStable"
                            )
                        }
                    }
                }
                val evenByteCount = read - (read % 2)
                if (evenByteCount > 0 && MiuCamServiceMediaBridge.wantsAudio) {
                    MiuCamServiceMediaBridge.publishAudio(
                        pcm16le = buffer.copyOf(evenByteCount),
                        timestampMs = System.currentTimeMillis(),
                        capturedAtMonoUs = SystemClock.elapsedRealtimeNanos() / 1_000L,
                        sampleRate = AUDIO_SAMPLE_RATE,
                        channels = AUDIO_CHANNELS
                    )
                }
            } else if (read < 0 && audioRunning.get()) {
                postMicrophoneFailure(generation, "microphone_read_failed:$read")
                break
            }
        }
    }

    private fun postMicrophoneFailure(generation: Int, message: String) {
        mainHandler.post {
            if (destroyed || generation != audioGeneration || !microphoneRequested) return@post
            val stableBeforeFailure =
                SystemClock.elapsedRealtime() - microphoneStartedAtElapsedMs >=
                    MICROPHONE_RETRY_STABILITY_MS
            stopMicrophone(clearError = false)
            if (stableBeforeFailure) microphoneRetryAttempt = 0L
            microphoneError = message
            MiuCamServiceMediaBridge.publishCaptureError("microphone", message)
            publishState()
            scheduleMicrophoneRetry(message)
        }
    }

    private fun stopMicrophone(clearError: Boolean) {
        cancelMicrophoneRetry()
        val recorder: AudioRecord?
        val thread: Thread?
        synchronized(audioLock) {
            audioGeneration += 1
            audioRunning.set(false)
            recorder = audioRecord
            thread = audioThread
            audioRecord = null
            audioThread = null
            microphoneActive = false
        }
        if (recorder != null) {
            try {
                if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    recorder.stop()
                }
            } catch (_: IllegalStateException) {
                // stop() is best effort during service teardown.
            }
        }
        if (thread != null && thread !== Thread.currentThread()) {
            try {
                thread.join(AUDIO_STOP_JOIN_TIMEOUT_MS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
        recorder?.release()
        if (clearError) microphoneError = null
    }

    private fun failMicrophone(message: String, retryable: Boolean) {
        stopMicrophone(clearError = false)
        microphoneError = message
        MiuCamServiceMediaBridge.publishCaptureError("microphone", message)
        publishState()
        if (retryable) scheduleMicrophoneRetry(message)
    }

    private fun scheduleMicrophoneRetry(reason: String) {
        if (destroyed || !microphoneRequested || microphoneActive) return
        if (reason.contains("permission_denied")) return
        val attempt = microphoneRetryBackoff.nextAttempt(microphoneRetryAttempt)
        microphoneRetryAttempt = attempt
        val delayMs = microphoneRetryBackoff.delayMs(attempt)
        lateinit var retry: Runnable
        retry = Runnable {
            if (microphoneRetryRunnable !== retry) return@Runnable
            microphoneRetryRunnable = null
            if (destroyed || !microphoneRequested || microphoneActive) return@Runnable
            microphoneError = null
            publishState()
            startMicrophone()
        }
        microphoneRetryRunnable = retry
        mainHandler.postDelayed(retry, delayMs)
        MiuCamPlatformRuntime.emit(
            "nativeMicrophoneRetryScheduled",
            mapOf(
                "attempt" to attempt,
                "delayMs" to delayMs,
                "maxDelayMs" to microphoneRetryBackoff.maxDelayMs,
                "continuous" to true,
                "reason" to reason
            )
        )
    }

    private fun cancelMicrophoneRetry() {
        val retry = microphoneRetryRunnable ?: return
        mainHandler.removeCallbacks(retry)
        microphoneRetryRunnable = null
    }

    private fun publishState() {
        MiuCamServiceMediaBridge.updateCaptureState(
            cameraRequested = cameraRequested,
            microphoneRequested = microphoneRequested,
            cameraActive = cameraActive,
            microphoneActive = microphoneActive,
            cameraError = cameraError,
            microphoneError = microphoneError
        )
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(applicationContext, permission) ==
            PackageManager.PERMISSION_GRANTED

    private fun encodeJpeg(
        image: ImageProxy,
        rotationDegrees: Int,
        quality: Int
    ): ByteArray {
        val nv21 = yuv420ToNv21(image)
        val rawOutput = ByteArrayOutputStream(nv21.size / 2)
        val compressed = YuvImage(
            nv21,
            ImageFormat.NV21,
            image.width,
            image.height,
            null
        ).compressToJpeg(
            Rect(0, 0, image.width, image.height),
            quality,
            rawOutput
        )
        check(compressed) { "YuvImage.compressToJpeg returned false" }
        val rawJpeg = rawOutput.toByteArray()
        if (rotationDegrees == 0) return rawJpeg

        val source = BitmapFactory.decodeByteArray(rawJpeg, 0, rawJpeg.size)
            ?: throw IllegalStateException("JPEG rotation decode failed")
        val rotated = Bitmap.createBitmap(
            source,
            0,
            0,
            source.width,
            source.height,
            Matrix().apply { postRotate(rotationDegrees.toFloat()) },
            true
        )
        return try {
            ByteArrayOutputStream(rawJpeg.size).use { output ->
                check(rotated.compress(Bitmap.CompressFormat.JPEG, quality, output)) {
                    "Rotated JPEG compression failed"
                }
                output.toByteArray()
            }
        } finally {
            if (rotated !== source) rotated.recycle()
            source.recycle()
        }
    }

    private fun yuv420ToNv21(image: ImageProxy): ByteArray {
        require(image.format == ImageFormat.YUV_420_888) {
            "Unsupported ImageProxy format ${image.format}"
        }
        val width = image.width
        val height = image.height
        require(width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0) {
            "Invalid YUV dimensions ${width}x$height"
        }
        val planes = image.planes
        require(planes.size >= 3) { "YUV_420_888 requires three planes" }
        val output = ByteArray(width * height * 3 / 2)
        copyPlane(
            buffer = planes[0].buffer,
            rowStride = planes[0].rowStride,
            pixelStride = planes[0].pixelStride,
            width = width,
            height = height,
            output = output,
            outputOffset = 0,
            outputPixelStride = 1
        )

        val chromaWidth = width / 2
        val chromaHeight = height / 2
        val chromaOffset = width * height
        copyPlane(
            buffer = planes[2].buffer,
            rowStride = planes[2].rowStride,
            pixelStride = planes[2].pixelStride,
            width = chromaWidth,
            height = chromaHeight,
            output = output,
            outputOffset = chromaOffset,
            outputPixelStride = 2
        )
        copyPlane(
            buffer = planes[1].buffer,
            rowStride = planes[1].rowStride,
            pixelStride = planes[1].pixelStride,
            width = chromaWidth,
            height = chromaHeight,
            output = output,
            outputOffset = chromaOffset + 1,
            outputPixelStride = 2
        )
        return output
    }

    private fun sampleLuma(
        image: ImageProxy,
        targetWidth: Int,
        targetHeight: Int
    ): ByteArray {
        require(targetWidth > 0 && targetHeight > 0)
        val plane = image.planes.firstOrNull()
            ?: throw IllegalStateException("ImageProxy has no luma plane")
        val source = plane.buffer.duplicate()
        val baseOffset = source.position()
        val crop = image.cropRect
        require(crop.width() > 0 && crop.height() > 0) {
            "Invalid luma crop ${crop.width()}x${crop.height()}"
        }
        val output = ByteArray(targetWidth * targetHeight)
        var outputIndex = 0
        for (row in 0 until targetHeight) {
            val startY = crop.top + row * crop.height() / targetHeight
            val endY = crop.top + (row + 1) * crop.height() / targetHeight
            for (column in 0 until targetWidth) {
                val startX = crop.left + column * crop.width() / targetWidth
                val endX = crop.left + (column + 1) * crop.width() / targetWidth
                var sum = 0
                var samples = 0
                for (sourceY in startY until endY) {
                    val rowOffset = baseOffset + sourceY * plane.rowStride
                    for (sourceX in startX until endX) {
                        val sourceIndex = rowOffset + sourceX * plane.pixelStride
                        require(sourceIndex < source.limit()) {
                            "Luma plane buffer ended at $sourceIndex/${source.limit()}"
                        }
                        sum += source.get(sourceIndex).toInt() and 0xFF
                        samples += 1
                    }
                }
                require(samples > 0) { "Empty luma sampling cell" }
                output[outputIndex++] = (sum / samples).toByte()
            }
        }
        return output
    }

    private fun copyPlane(
        buffer: ByteBuffer,
        rowStride: Int,
        pixelStride: Int,
        width: Int,
        height: Int,
        output: ByteArray,
        outputOffset: Int,
        outputPixelStride: Int
    ) {
        val source = buffer.duplicate()
        val baseOffset = source.position()
        var outputIndex = outputOffset
        for (row in 0 until height) {
            val rowOffset = baseOffset + row * rowStride
            for (column in 0 until width) {
                val sourceIndex = rowOffset + column * pixelStride
                require(sourceIndex < source.limit()) {
                    "YUV plane buffer ended at $sourceIndex/${source.limit()}"
                }
                output[outputIndex] = source.get(sourceIndex)
                outputIndex += outputPixelStride
            }
        }
    }

    private fun normalizeRotation(value: Int): Int = when (((value % 360) + 360) % 360) {
        in 45..134 -> 90
        in 135..224 -> 180
        in 225..314 -> 270
        else -> 0
    }

    private fun Throwable.describe(prefix: String): String =
        "$prefix:${javaClass.simpleName}:${message ?: "unknown"}"

    private class NamedThreadFactory(private val threadName: String) : ThreadFactory {
        override fun newThread(runnable: Runnable): Thread =
            Thread(runnable, threadName).apply { isDaemon = true }
    }

    private companion object {
        const val CAMERA_WIDTH = 640
        const val CAMERA_HEIGHT = 480
        const val LUMA_WIDTH = 64
        const val LUMA_HEIGHT = 48
        const val AUDIO_SAMPLE_RATE = 16_000
        const val AUDIO_CHANNELS = 1
        const val AUDIO_CHUNK_DURATION_MS = 20
        const val AUDIO_CHUNK_BYTES =
            AUDIO_SAMPLE_RATE * AUDIO_CHANNELS * 2 * AUDIO_CHUNK_DURATION_MS / 1_000
        const val AUDIO_STOP_JOIN_TIMEOUT_MS = 400L
        const val MICROPHONE_RETRY_BASE_DELAY_MS = 250L
        const val MICROPHONE_RETRY_MAX_DELAY_MS = 30_000L
        const val MICROPHONE_RETRY_STABILITY_MS = 10_000L
    }
}
