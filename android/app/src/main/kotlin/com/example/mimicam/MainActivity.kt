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
                    val args = call.arguments as? Map<*, *>
                    val sampleRate = (args?.get("sampleRate") as? Number)?.toInt() ?: 16000
                    val channels = (args?.get("channels") as? Number)?.toInt() ?: 1
                    pcmAudioPlayer.start(sampleRate, channels)
                    result.success(null)
                }
                "write" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes != null) pcmAudioPlayer.write(bytes)
                    result.success(null)
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

    @Synchronized
    fun start(sampleRate: Int, channels: Int) {
        stop()
        generation += 1
        val channelMask = if (channels == 2) {
            AudioFormat.CHANNEL_OUT_STEREO
        } else {
            AudioFormat.CHANNEL_OUT_MONO
        }
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            channelMask,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(sampleRate * channels * 2 / 2)
        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(channelMask)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(minBuffer * 2)
            .build()
        audioTrack?.play()
    }

    @Synchronized
    fun write(bytes: ByteArray) {
        val track = audioTrack ?: return
        val currentGeneration = generation
        executor.execute {
            val shouldWrite = synchronized(this) {
                currentGeneration == generation && audioTrack === track
            }
            if (shouldWrite) {
                track.write(bytes, 0, bytes.size, AudioTrack.WRITE_BLOCKING)
            }
        }
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
