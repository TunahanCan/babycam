package com.example.mimicam

import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.sin

class MainActivity : FlutterActivity() {
    private val pcmAudioPlayer = PcmAudioPlayer()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mimicam/background_service"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startServer" -> {
                    val intent = Intent(this, MimiCamForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopServer" -> {
                    stopService(Intent(this, MimiCamForegroundService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mimicam/pcm_audio"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val args = call.arguments as? Map<*, *>
                        val sampleRate = (args?.get("sampleRate") as? Number)?.toInt() ?: 16000
                        val channels = (args?.get("channels") as? Number)?.toInt() ?: 1
                        pcmAudioPlayer.start(sampleRate, channels)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("PCM_AUDIO_START_FAILED", error.message, pcmAudioPlayer.status())
                    }
                }
                "write" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes != null) pcmAudioPlayer.write(bytes)
                    result.success(null)
                }
                "status" -> {
                    result.success(pcmAudioPlayer.status())
                }
                "playTestTone" -> {
                    try {
                        val args = call.arguments as? Map<*, *>
                        val sampleRate = (args?.get("sampleRate") as? Number)?.toInt() ?: 16000
                        val channels = (args?.get("channels") as? Number)?.toInt() ?: 1
                        val durationMs = (args?.get("durationMs") as? Number)?.toInt() ?: 1200
                        val frequencyHz = (args?.get("frequencyHz") as? Number)?.toInt() ?: 440
                        val amplitude = (args?.get("amplitude") as? Number)?.toDouble() ?: 0.35
                        pcmAudioPlayer.playTestTone(
                            sampleRate,
                            channels,
                            durationMs,
                            frequencyHz,
                            amplitude
                        )
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("PCM_AUDIO_TEST_TONE_FAILED", error.message, pcmAudioPlayer.status())
                    }
                }
                "stop" -> {
                    pcmAudioPlayer.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        pcmAudioPlayer.release()
        super.onDestroy()
    }
}

private class PcmAudioPlayer {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var audioTrack: AudioTrack? = null
    private var generation = 0
    private val pendingWrites = AtomicInteger(0)
    private val maxPendingWrites = 8
    private var sampleRate = 0
    private var channels = 0
    private var bufferSizeBytes = 0
    private var starts = 0L
    private var writesAccepted = 0L
    private var writesDropped = 0L
    private var writeErrors = 0L
    private var bytesWritten = 0L
    private var lastStartAtMs = 0L
    private var lastWriteAtMs = 0L
    private var lastError: String? = null
    private var underrunCount = 0

    @Synchronized
    fun start(sampleRate: Int, channels: Int) {
        stop()
        generation += 1
        val safeSampleRate = sampleRate.coerceIn(8000, 48000)
        val safeChannels = channels.coerceIn(1, 2)
        val channelMask = if (safeChannels == 2) {
            AudioFormat.CHANNEL_OUT_STEREO
        } else {
            AudioFormat.CHANNEL_OUT_MONO
        }
        val minBufferResult = AudioTrack.getMinBufferSize(
            safeSampleRate,
            channelMask,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bytesPerSecond = safeSampleRate * safeChannels * 2
        val bufferSize = if (minBufferResult > 0) {
            maxOf(minBufferResult * 4, bytesPerSecond / 2)
        } else {
            bytesPerSecond
        }
        var builder = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(safeSampleRate)
                    .setChannelMask(channelMask)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(bufferSize)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        }
        val track = builder.build()
        if (track.state != AudioTrack.STATE_INITIALIZED) {
            track.release()
            lastError = "AudioTrack state ${track.state}"
            throw IllegalStateException(lastError)
        }
        track.setVolume(AudioTrack.getMaxVolume())
        track.play()
        audioTrack = track
        this.sampleRate = safeSampleRate
        this.channels = safeChannels
        bufferSizeBytes = bufferSize
        starts += 1
        lastStartAtMs = System.currentTimeMillis()
        lastError = if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
            null
        } else {
            "AudioTrack playState ${track.playState}"
        }
    }

    @Synchronized
    fun write(bytes: ByteArray) {
        val track = audioTrack
        if (track == null) {
            writesDropped += 1
            lastError = "write before start"
            return
        }
        val payload = bytes.copyOf()
        val currentGeneration = generation
        if (pendingWrites.incrementAndGet() > maxPendingWrites) {
            pendingWrites.decrementAndGet()
            writesDropped += 1
            return
        }
        executor.execute {
            try {
                val shouldWrite = synchronized(this) {
                    currentGeneration == generation && audioTrack === track
                }
                if (shouldWrite) {
                    val written = track.write(payload, 0, payload.size, AudioTrack.WRITE_BLOCKING)
                    synchronized(this) {
                        if (written > 0) {
                            writesAccepted += 1
                            bytesWritten += written.toLong()
                            lastWriteAtMs = System.currentTimeMillis()
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                underrunCount = track.underrunCount
                            }
                        } else {
                            writesDropped += 1
                            writeErrors += 1
                            lastError = "AudioTrack.write returned $written"
                        }
                    }
                } else {
                    synchronized(this) {
                        writesDropped += 1
                    }
                }
            } catch (error: Exception) {
                synchronized(this) {
                    writeErrors += 1
                    lastError = "${error.javaClass.simpleName}: ${error.message}"
                }
            } finally {
                pendingWrites.decrementAndGet()
            }
        }
    }

    fun playTestTone(
        sampleRate: Int,
        channels: Int,
        durationMs: Int,
        frequencyHz: Int,
        amplitude: Double
    ) {
        val safeSampleRate = sampleRate.coerceIn(8000, 48000)
        val safeChannels = channels.coerceIn(1, 2)
        val safeDurationMs = durationMs.coerceIn(100, 5000)
        val safeFrequencyHz = frequencyHz.coerceIn(80, 2000)
        val safeAmplitude = amplitude.coerceIn(0.02, 0.80)
        val frameCount = safeSampleRate * safeDurationMs / 1000
        val payload = ByteArray(frameCount * safeChannels * 2)
        val amplitudeInt = (32767 * safeAmplitude).toInt()
        for (frame in 0 until frameCount) {
            val sample = (
                sin(2.0 * Math.PI * safeFrequencyHz * frame / safeSampleRate) *
                    amplitudeInt
                ).toInt()
            for (channel in 0 until safeChannels) {
                val offset = (frame * safeChannels + channel) * 2
                payload[offset] = (sample and 0xff).toByte()
                payload[offset + 1] = ((sample shr 8) and 0xff).toByte()
            }
        }
        start(safeSampleRate, safeChannels)
        write(payload)
    }

    @Synchronized
    fun status(): Map<String, Any?> {
        val track = audioTrack
        return mapOf(
            "started" to (track != null),
            "sampleRate" to sampleRate,
            "channels" to channels,
            "bufferSizeBytes" to bufferSizeBytes,
            "pendingWrites" to pendingWrites.get(),
            "maxPendingWrites" to maxPendingWrites,
            "starts" to starts,
            "writesAccepted" to writesAccepted,
            "writesDropped" to writesDropped,
            "writeErrors" to writeErrors,
            "bytesWritten" to bytesWritten,
            "lastStartAtMs" to lastStartAtMs,
            "lastWriteAtMs" to lastWriteAtMs,
            "lastError" to lastError,
            "underrunCount" to underrunCount,
            "playState" to (track?.playState ?: 0),
            "trackState" to (track?.state ?: 0)
        )
    }

    @Synchronized
    fun stop() {
        generation += 1
        val track = audioTrack
        audioTrack = null
        if (track != null) {
            executor.execute {
                try {
                    track.pause()
                    track.flush()
                    track.release()
                } catch (_: Exception) {
                }
            }
        }
    }

    @Synchronized
    fun release() {
        generation += 1
        val track = audioTrack
        audioTrack = null
        if (track != null) {
            try {
                track.pause()
                track.flush()
                track.release()
            } catch (_: Exception) {
            }
        }
        executor.shutdownNow()
    }
}
