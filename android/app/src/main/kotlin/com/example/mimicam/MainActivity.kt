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
        MimiCamNativeRuntime.initialize(appContext)
        val pcmAudioPlayer = MimiCamNativeRuntime.audioPlayer(appContext)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MimiCamPlatformRuntime.EVENT_CHANNEL
        ).setStreamHandler(MimiCamPlatformRuntime)
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
                    updateForegroundService(
                        context = appContext,
                        camera = args?.get("camera") as? Boolean ?: false,
                        microphone = args?.get("microphone") as? Boolean ?: false,
                        active = args?.get("active") as? Boolean ?: false
                    )
                    result.success(null)
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
                    try {
                        val args = call.arguments as? Map<*, *>
                        val camera = args?.get("camera") as? Boolean ?: true
                        val microphone = args?.get("microphone") as? Boolean ?: true
                        val intent = MimiCamForegroundService.startIntent(
                            appContext,
                            camera = camera,
                            microphone = microphone
                        )
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            appContext.startForegroundService(intent)
                        } else {
                            appContext.startService(intent)
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "FOREGROUND_SERVICE_START_FAILED",
                            error.message,
                            MimiCamPlatformRuntime.snapshot(appContext)
                        )
                    }
                }
                "stopServer" -> {
                    appContext.startService(
                        MimiCamForegroundService.stopIntent(appContext)
                    )
                    result.success(null)
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
                        pcmAudioPlayer.start(sampleRate, channels)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "PCM_AUDIO_START_FAILED",
                            error.message,
                            pcmAudioPlayer.status()
                        )
                    }
                }
                "write" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null) {
                        result.success(false)
                    } else {
                        pcmAudioPlayer.write(bytes) { accepted ->
                            result.success(accepted)
                        }
                    }
                }
                "status" -> result.success(pcmAudioPlayer.status())
                "playTestTone" -> {
                    try {
                        val args = call.arguments as? Map<*, *>
                        pcmAudioPlayer.playTestTone(
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
                            pcmAudioPlayer.status()
                        )
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
        fun updateForegroundService(
            context: Context,
            camera: Boolean,
            microphone: Boolean,
            active: Boolean
        ) {
            val intent = if (active) {
                MimiCamForegroundService.updateIntent(context, camera, microphone)
            } else {
                MimiCamForegroundService.stopIntent(context)
            }
            context.startService(intent)
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
