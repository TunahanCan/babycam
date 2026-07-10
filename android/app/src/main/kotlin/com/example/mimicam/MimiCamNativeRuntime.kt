package com.example.mimicam

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.sin

object MimiCamNativeRuntime {
    @Volatile
    private var player: PcmAudioPlayer? = null

    fun initialize(context: Context) {
        audioPlayer(context)
    }

    @Synchronized
    fun audioPlayer(context: Context): PcmAudioPlayer {
        val current = player
        if (current != null) return current
        return PcmAudioPlayer(context.applicationContext).also { player = it }
    }
}

class PcmAudioPlayer(private val context: Context) {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var audioTrack: AudioTrack? = null
    private var generation = 0
    private val pendingWrites = AtomicInteger(0)
    private val maxPendingWrites = 6
    private var sampleRate = 0
    private var channels = 0
    private var bufferSizeBytes = 0
    private var starts = 0L
    private var writesAccepted = 0L
    private var writesDropped = 0L
    private var writeErrors = 0L
    private var bytesWritten = 0L
    private var sessionFramesWritten = 0L
    private var lastStartAtMs = 0L
    private var lastWriteAtMs = 0L
    private var lastError: String? = null
    private var underrunCount = 0
    private var interruptions = 0L
    private var focusLosses = 0L
    private var focusGranted = false
    private var focusRequest: Any? = null
    private var pausedForFocusLoss = false
    private var noisyReceiverRegistered = false
    private var deviceCallbackRegistered = false

    private val audioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> resumeAfterFocusGain()
            AudioManager.AUDIOFOCUS_LOSS -> stopForPermanentFocusLoss()
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> pauseForFocusLoss(change)
        }
    }

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != AudioManager.ACTION_AUDIO_BECOMING_NOISY) return
            synchronized(this@PcmAudioPlayer) {
                audioTrack?.pause()
                pausedForFocusLoss = true
                interruptions += 1
            }
            MimiCamPlatformRuntime.setAudioOutputActive(
                false,
                "audio_becoming_noisy"
            )
            MimiCamPlatformRuntime.emit("audioBecomingNoisy")
        }
    }

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            emitDeviceChange("added", addedDevices)
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            emitDeviceChange("removed", removedDevices)
        }
    }

    @Synchronized
    fun start(sampleRate: Int, channels: Int) {
        stop()
        generation += 1
        val safeSampleRate = sampleRate.coerceIn(8000, 48000)
        val safeChannels = channels.coerceIn(1, 2)
        requestAudioFocus()
        registerAudioObservers()
        try {
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
                maxOf(minBufferResult * 2, bytesPerSecond / 8)
            } else {
                bytesPerSecond / 4
            }
            var builder = AudioTrack.Builder()
                .setAudioAttributes(audioAttributes)
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
            sessionFramesWritten = 0L
            starts += 1
            lastStartAtMs = System.currentTimeMillis()
            pausedForFocusLoss = false
            lastError = if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                null
            } else {
                "AudioTrack playState ${track.playState}"
            }
            MimiCamPlatformRuntime.emit(
                "audioPlaybackStarted",
                mapOf("sampleRate" to safeSampleRate, "channels" to safeChannels)
            )
            MimiCamPlatformRuntime.setAudioOutputActive(true, "audio_playback_started")
        } catch (error: Exception) {
            MimiCamPlatformRuntime.setAudioOutputActive(false, "audio_playback_start_failed")
            abandonAudioFocus()
            unregisterAudioObservers()
            throw error
        }
    }

    fun write(bytes: ByteArray, completion: (Boolean) -> Unit) {
        val track: AudioTrack
        val currentGeneration: Int
        synchronized(this) {
            val activeTrack = audioTrack
            if (activeTrack == null || pausedForFocusLoss) {
                writesDropped += 1
                lastError = if (activeTrack == null) {
                    "write before start"
                } else {
                    "write while audio focus is interrupted"
                }
                completion(false)
                return
            }
            if (pendingWrites.incrementAndGet() > maxPendingWrites) {
                pendingWrites.decrementAndGet()
                writesDropped += 1
                completion(false)
                return
            }
            track = activeTrack
            currentGeneration = generation
        }
        val payload = bytes.copyOf()
        executor.execute {
            var accepted = false
            var totalWritten = 0
            try {
                val shouldWrite = synchronized(this) {
                    currentGeneration == generation &&
                        audioTrack === track &&
                        !pausedForFocusLoss
                }
                if (shouldWrite) {
                    while (totalWritten < payload.size) {
                        val stillCurrent = synchronized(this) {
                            currentGeneration == generation &&
                                audioTrack === track &&
                                !pausedForFocusLoss
                        }
                        if (!stillCurrent) break
                        val written = track.write(
                            payload,
                            totalWritten,
                            payload.size - totalWritten,
                            AudioTrack.WRITE_BLOCKING
                        )
                        if (written <= 0) {
                            throw IllegalStateException("AudioTrack.write returned $written")
                        }
                        totalWritten += written
                    }
                    synchronized(this) {
                        val isStillCurrent = currentGeneration == generation &&
                            audioTrack === track &&
                            !pausedForFocusLoss
                        if (totalWritten == payload.size && isStillCurrent) {
                            accepted = true
                            writesAccepted += 1
                            bytesWritten += totalWritten.toLong()
                            sessionFramesWritten +=
                                totalWritten.toLong() / maxOf(1, channels * 2)
                            lastWriteAtMs = System.currentTimeMillis()
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                underrunCount = track.underrunCount
                            }
                        } else {
                            recordPartialWrite(totalWritten, isStillCurrent)
                        }
                    }
                } else {
                    synchronized(this) { writesDropped += 1 }
                }
            } catch (error: Exception) {
                synchronized(this) {
                    recordPartialWrite(totalWritten, currentGeneration == generation)
                    writeErrors += 1
                    lastError = "${error.javaClass.simpleName}: ${error.message}"
                }
            } finally {
                pendingWrites.decrementAndGet()
                mainHandler.post { completion(accepted) }
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
        val amplitudeInt = (32767.0 * safeAmplitude).toInt()
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
        write(payload) { }
    }

    @Synchronized
    fun status(): Map<String, Any?> {
        val track = audioTrack
        val playbackFrames = if (track != null) {
            track.playbackHeadPosition.toLong() and 0xffffffffL
        } else {
            0L
        }
        val queuedFrames = maxOf(0L, sessionFramesWritten - playbackFrames)
        return mapOf(
            "started" to (track != null),
            "sampleRate" to sampleRate,
            "channels" to channels,
            "bufferSizeBytes" to bufferSizeBytes,
            "pendingWrites" to pendingWrites.get(),
            "queuedAudioMs" to if (sampleRate > 0) {
                queuedFrames * 1000L / sampleRate
            } else {
                0L
            },
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
            "interruptions" to interruptions,
            "focusLosses" to focusLosses,
            "focusGranted" to focusGranted,
            "pausedForFocusLoss" to pausedForFocusLoss,
            "playState" to (track?.playState ?: 0),
            "trackState" to (track?.state ?: 0)
        )
    }

    @Synchronized
    fun stop() {
        generation += 1
        val track = audioTrack
        audioTrack = null
        pausedForFocusLoss = false
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
        abandonAudioFocus()
        unregisterAudioObservers()
        MimiCamPlatformRuntime.emit("audioPlaybackStopped")
        MimiCamPlatformRuntime.setAudioOutputActive(false, "audio_playback_stopped")
    }

    @Synchronized
    private fun recordPartialWrite(totalWritten: Int, isStillCurrent: Boolean) {
        writesDropped += 1
        if (totalWritten <= 0) return
        bytesWritten += totalWritten.toLong()
        if (isStillCurrent) {
            sessionFramesWritten += totalWritten.toLong() / maxOf(1, channels * 2)
        }
        lastWriteAtMs = System.currentTimeMillis()
        lastError = "audio generation or focus changed during write"
    }

    private fun requestAudioFocus() {
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(audioAttributes)
                .setOnAudioFocusChangeListener(focusListener, mainHandler)
                .setWillPauseWhenDucked(true)
                .build()
            focusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
        }
        focusGranted = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (!focusGranted) {
            focusRequest = null
            throw IllegalStateException("Android audio focus request was denied")
        }
    }

    private fun abandonAudioFocus() {
        if (!focusGranted) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            (focusRequest as? AudioFocusRequest)?.let(
                audioManager::abandonAudioFocusRequest
            )
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
        focusGranted = false
    }

    @Synchronized
    private fun pauseForFocusLoss(change: Int) {
        focusLosses += 1
        interruptions += 1
        pausedForFocusLoss = true
        audioTrack?.pause()
        MimiCamPlatformRuntime.setAudioOutputActive(false, "audio_focus_lost")
        MimiCamPlatformRuntime.emit(
            "audioFocusLost",
            mapOf("focusChange" to change)
        )
    }

    @Synchronized
    private fun resumeAfterFocusGain() {
        focusGranted = true
        if (!pausedForFocusLoss) return
        pausedForFocusLoss = false
        audioTrack?.play()
        MimiCamPlatformRuntime.setAudioOutputActive(
            audioTrack != null,
            "audio_focus_gained"
        )
        MimiCamPlatformRuntime.emit("audioFocusGained")
    }

    private fun stopForPermanentFocusLoss() {
        synchronized(this) {
            focusLosses += 1
            interruptions += 1
            lastError = "permanent audio focus loss"
        }
        MimiCamPlatformRuntime.emit(
            "audioFocusLost",
            mapOf("focusChange" to AudioManager.AUDIOFOCUS_LOSS, "permanent" to true)
        )
        stop()
    }

    private fun registerAudioObservers() {
        if (!noisyReceiverRegistered) {
            val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                context.registerReceiver(noisyReceiver, filter)
            }
            noisyReceiverRegistered = true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !deviceCallbackRegistered) {
            audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)
            deviceCallbackRegistered = true
        }
    }

    private fun unregisterAudioObservers() {
        if (noisyReceiverRegistered) {
            try {
                context.unregisterReceiver(noisyReceiver)
            } catch (_: IllegalArgumentException) {
            }
            noisyReceiverRegistered = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && deviceCallbackRegistered) {
            audioManager.unregisterAudioDeviceCallback(deviceCallback)
            deviceCallbackRegistered = false
        }
    }

    private fun emitDeviceChange(action: String, devices: Array<out AudioDeviceInfo>) {
        MimiCamPlatformRuntime.emit(
            "audioDevicesChanged",
            mapOf(
                "action" to action,
                "devices" to devices.map {
                    mapOf("id" to it.id, "type" to it.type, "name" to it.productName.toString())
                }
            )
        )
    }
}
