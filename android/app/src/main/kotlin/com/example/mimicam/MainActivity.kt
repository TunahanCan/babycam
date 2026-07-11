package com.example.mimicam

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        MimiCamEngineOwner.engine

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MimiCamEngineOwner.attachActivity(flutterEngine)
        val appContext = applicationContext
        fun pcmAudioPlayer() = MimiCamNativeRuntime.audioPlayer(appContext)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MimiCamPlatformRuntime.EVENT_CHANNEL
        ).setStreamHandler(MimiCamPlatformRuntime)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MimiCamServiceMediaBridge.EVENT_CHANNEL
        ).setStreamHandler(MimiCamServiceMediaBridge)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MimiCamServiceMediaBridge.METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            MimiCamServiceMediaBridge.handleMethodCall(call, result)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MimiCamPlatformRuntime.METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "snapshot" -> result.success(
                    MimiCamPlatformRuntime.snapshot(appContext)
                )
                "setMediaDemand" -> {
                    val args = call.arguments as? Map<*, *>
                    val camera = args?.get("camera") as? Boolean ?: false
                    val microphone = args?.get("microphone") as? Boolean ?: false
                    applyMediaDemand(
                        context = appContext,
                        camera = camera,
                        microphone = microphone,
                        playback = args?.get("playback") as? Boolean ?: false,
                        nativeCameraCapture =
                            args?.get("nativeCameraCapture") as? Boolean ?: camera,
                        nativeMicrophoneCapture =
                            args?.get("nativeMicrophoneCapture") as? Boolean ?: microphone,
                        active = args?.get("active") as? Boolean ?: false,
                        result = result
                    )
                }
                "setAlertDemand" -> {
                    val args = call.arguments as? Map<*, *>
                    applyAlertDemand(
                        context = appContext,
                        active = args?.get("active") as? Boolean ?: false,
                        result = result
                    )
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mimicam/device_resources"
        ).setMethodCallHandler { call, result ->
            if (call.method == "snapshot") {
                result.success(deviceResourceSnapshot(appContext))
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mimicam/background_service"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startServer" -> {
                    val args = call.arguments as? Map<*, *>
                    val camera = args?.get("camera") as? Boolean ?: false
                    val microphone = args?.get("microphone") as? Boolean ?: false
                    val playback = args?.get("playback") as? Boolean ?: false
                    applyMediaDemand(
                        context = appContext,
                        camera = camera,
                        microphone = microphone,
                        playback = playback,
                        nativeCameraCapture =
                            args?.get("nativeCameraCapture") as? Boolean ?: camera,
                        nativeMicrophoneCapture =
                            args?.get("nativeMicrophoneCapture") as? Boolean ?: microphone,
                        active = camera || microphone || playback,
                        result = result
                    )
                }
                "stopServer" -> {
                    applyMediaDemand(
                        context = appContext,
                        camera = false,
                        microphone = false,
                        playback = false,
                        nativeCameraCapture = false,
                        nativeMicrophoneCapture = false,
                        active = false,
                        result = result
                    )
                }
                "status" -> result.success(
                    MimiCamPlatformRuntime.snapshot(appContext)
                )
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
                        val sampleRate =
                            (args?.get("sampleRate") as? Number)?.toInt() ?: 16000
                        val channels =
                            (args?.get("channels") as? Number)?.toInt() ?: 1
                        pcmAudioPlayer().start(sampleRate, channels)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "PCM_AUDIO_START_FAILED",
                            error.message,
                            pcmAudioPlayer().status()
                        )
                    }
                }
                "write" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null) {
                        result.success(false)
                    } else {
                        pcmAudioPlayer().write(bytes) { accepted ->
                            result.success(accepted)
                        }
                    }
                }
                "status" -> result.success(pcmAudioPlayer().status())
                "playTestTone" -> {
                    try {
                        val args = call.arguments as? Map<*, *>
                        pcmAudioPlayer().playTestTone(
                            sampleRate =
                                (args?.get("sampleRate") as? Number)?.toInt() ?: 16000,
                            channels =
                                (args?.get("channels") as? Number)?.toInt() ?: 1,
                            durationMs =
                                (args?.get("durationMs") as? Number)?.toInt() ?: 1200,
                            frequencyHz =
                                (args?.get("frequencyHz") as? Number)?.toInt() ?: 440,
                            amplitude =
                                (args?.get("amplitude") as? Number)?.toDouble() ?: 0.35
                        )
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "PCM_AUDIO_TEST_TONE_FAILED",
                            error.message,
                            pcmAudioPlayer().status()
                        )
                    }
                }
                "stop" -> {
                    pcmAudioPlayer().stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onStart() {
        super.onStart()
        MimiCamEngineOwner.markActivityAttached(true)
        MimiCamPlatformRuntime.setApplicationState("foreground")
    }

    override fun onResume() {
        super.onResume()
        MimiCamPlatformRuntime.setApplicationState("foregroundActive")
    }

    override fun onPause() {
        MimiCamPlatformRuntime.setApplicationState("inactive")
        super.onPause()
    }

    override fun onStop() {
        MimiCamPlatformRuntime.setApplicationState("background")
        MimiCamEngineOwner.markActivityAttached(false)
        super.onStop()
    }

    private companion object {
        fun applyMediaDemand(
            context: Context,
            camera: Boolean,
            microphone: Boolean,
            playback: Boolean,
            nativeCameraCapture: Boolean,
            nativeMicrophoneCapture: Boolean,
            active: Boolean,
            result: MethodChannel.Result
        ) {
            val hasDemand = active && (camera || microphone || playback)
            val effectiveCameraDemand = hasDemand && camera
            val effectiveMicrophoneDemand = hasDemand && microphone
            val effectivePlaybackDemand = hasDemand && playback
            val serviceCameraCapture = effectiveCameraDemand && nativeCameraCapture
            val serviceMicrophoneCapture =
                effectiveMicrophoneDemand && nativeMicrophoneCapture
            MimiCamPlatformRuntime.setRequestedMediaDemand(
                active = hasDemand,
                camera = camera,
                microphone = microphone,
                playback = playback,
                nativeCameraCapture = serviceCameraCapture,
                nativeMicrophoneCapture = serviceMicrophoneCapture
            )
            val alertDemand = MimiCamPlatformRuntime.isAlertDemandRequested
            if (!hasDemand && !alertDemand) {
                context.stopService(Intent(context, MimiCamForegroundService::class.java))
                result.success(null)
                return
            }

            try {
                if (MimiCamPlatformRuntime.isForegroundServiceActive) {
                    context.startService(
                        MimiCamForegroundService.updateIntent(
                            context,
                            camera = effectiveCameraDemand,
                            microphone = effectiveMicrophoneDemand,
                            playback = effectivePlaybackDemand,
                            alert = alertDemand,
                            nativeCameraCapture = serviceCameraCapture,
                            nativeMicrophoneCapture = serviceMicrophoneCapture
                        )
                    )
                } else {
                    if (
                        hasDemand &&
                        !MimiCamPlatformRuntime.canStartWhileInUseForegroundService
                    ) {
                        val reason = "visible_activity_required"
                        MimiCamPlatformRuntime.setForegroundServiceFailure(reason)
                        result.error(
                            "FOREGROUND_SERVICE_VISIBLE_START_REQUIRED",
                            "Camera, microphone, or playback service must be armed while MimiCam is visible.",
                            MimiCamPlatformRuntime.snapshot(context)
                        )
                        return
                    }
                    val intent = MimiCamForegroundService.startIntent(
                        context,
                        camera = effectiveCameraDemand,
                        microphone = effectiveMicrophoneDemand,
                        playback = effectivePlaybackDemand,
                        alert = alertDemand,
                        nativeCameraCapture = serviceCameraCapture,
                        nativeMicrophoneCapture = serviceMicrophoneCapture
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                }
                result.success(null)
            } catch (error: Exception) {
                MimiCamPlatformRuntime.setForegroundServiceFailure(
                    "${error.javaClass.simpleName}: ${error.message}"
                )
                result.error(
                    "FOREGROUND_SERVICE_START_FAILED",
                    error.message,
                    MimiCamPlatformRuntime.snapshot(context)
                )
            }
        }

        fun applyAlertDemand(
            context: Context,
            active: Boolean,
            result: MethodChannel.Result
        ) {
            MimiCamPlatformRuntime.setRequestedAlertDemand(active)
            val camera = MimiCamPlatformRuntime.isCameraDemandRequested
            val microphone = MimiCamPlatformRuntime.isMicrophoneDemandRequested
            val playback = MimiCamPlatformRuntime.isPlaybackDemandRequested
            val hasMediaDemand = camera || microphone || playback

            if (!active && !hasMediaDemand) {
                context.stopService(Intent(context, MimiCamForegroundService::class.java))
                result.success(null)
                return
            }

            try {
                val intent = if (MimiCamPlatformRuntime.isForegroundServiceActive) {
                    MimiCamForegroundService.updateIntent(
                        context,
                        camera = camera,
                        microphone = microphone,
                        playback = playback,
                        alert = active,
                        nativeCameraCapture =
                            MimiCamPlatformRuntime.isNativeCameraCaptureRequested,
                        nativeMicrophoneCapture =
                            MimiCamPlatformRuntime.isNativeMicrophoneCaptureRequested
                    )
                } else {
                    MimiCamForegroundService.startIntent(
                        context,
                        camera = camera,
                        microphone = microphone,
                        playback = playback,
                        alert = active,
                        nativeCameraCapture =
                            MimiCamPlatformRuntime.isNativeCameraCaptureRequested,
                        nativeMicrophoneCapture =
                            MimiCamPlatformRuntime.isNativeMicrophoneCaptureRequested
                    )
                }
                if (
                    !MimiCamPlatformRuntime.isForegroundServiceActive &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                result.success(null)
            } catch (error: Exception) {
                MimiCamPlatformRuntime.setForegroundServiceFailure(
                    "${error.javaClass.simpleName}: ${error.message}"
                )
                result.error(
                    "ALERT_FOREGROUND_SERVICE_START_FAILED",
                    error.message,
                    MimiCamPlatformRuntime.snapshot(context)
                )
            }
        }

        fun deviceResourceSnapshot(context: Context): Map<String, Any?> {
            val powerManager =
                context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val batteryManager =
                context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val batteryIntent = context.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
            val batteryStatus = batteryIntent?.getIntExtra(
                BatteryManager.EXTRA_STATUS,
                BatteryManager.BATTERY_STATUS_UNKNOWN
            ) ?: BatteryManager.BATTERY_STATUS_UNKNOWN
            val rawLevel =
                batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale =
                batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
            val batteryLevel = if (rawLevel >= 0 && scale > 0) {
                rawLevel * 100 / scale
            } else {
                batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            }
            val thermalState = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                when (powerManager.currentThermalStatus) {
                    PowerManager.THERMAL_STATUS_NONE -> "nominal"
                    PowerManager.THERMAL_STATUS_LIGHT -> "fair"
                    PowerManager.THERMAL_STATUS_MODERATE,
                    PowerManager.THERMAL_STATUS_SEVERE -> "serious"
                    PowerManager.THERMAL_STATUS_CRITICAL,
                    PowerManager.THERMAL_STATUS_EMERGENCY,
                    PowerManager.THERMAL_STATUS_SHUTDOWN -> "critical"
                    else -> "unknown"
                }
            } else {
                "unknown"
            }
            return mapOf(
                "thermalState" to thermalState,
                "lowPowerMode" to powerManager.isPowerSaveMode,
                "charging" to (
                    batteryStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
                        batteryStatus == BatteryManager.BATTERY_STATUS_FULL
                    ),
                "batteryLevelPercent" to batteryLevel.takeIf { it in 0..100 }
            )
        }
    }
}
