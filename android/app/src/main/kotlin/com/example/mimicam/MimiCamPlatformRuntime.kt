package com.example.mimicam

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicLong

/**
 * Keeps the single UI isolate alive while the foreground service owns the
 * server runtime. A sticky service is deliberately not used: after process
 * death Android cannot silently reacquire while-in-use camera/microphone
 * access from the background.
 */
object MimiCamEngineOwner {
    const val ENGINE_CACHE_ID = "mimicam.runtime.engine"

    @Volatile
    var engine: FlutterEngine? = null
        private set

    @Volatile
    var activityAttached: Boolean = false
        private set

    @Volatile
    var serviceOwnsEngine: Boolean = false
        private set

    @Synchronized
    fun attachActivity(value: FlutterEngine) {
        engine = value
        activityAttached = true
        FlutterEngineCache.getInstance().put(ENGINE_CACHE_ID, value)
        MimiCamPlatformRuntime.emit(
            "engineOwnershipChanged",
            mapOf("activityAttached" to true, "serviceOwnsEngine" to serviceOwnsEngine)
        )
    }

    @Synchronized
    fun markActivityAttached(attached: Boolean) {
        activityAttached = attached
        MimiCamPlatformRuntime.emit(
            "engineOwnershipChanged",
            mapOf(
                "activityAttached" to attached,
                "serviceOwnsEngine" to serviceOwnsEngine
            )
        )
    }

    @Synchronized
    fun claimForService(): FlutterEngine? {
        val current = engine ?: return null
        serviceOwnsEngine = true
        FlutterEngineCache.getInstance().put(ENGINE_CACHE_ID, current)
        MimiCamPlatformRuntime.emit(
            "engineOwnershipChanged",
            mapOf("activityAttached" to activityAttached, "serviceOwnsEngine" to true)
        )
        return current
    }

    @Synchronized
    fun releaseService() {
        serviceOwnsEngine = false
        MimiCamPlatformRuntime.emit(
            "engineOwnershipChanged",
            mapOf("activityAttached" to activityAttached, "serviceOwnsEngine" to false)
        )
    }
}

object MimiCamPlatformRuntime : EventChannel.StreamHandler {
    const val METHOD_CHANNEL = "mimicam/platform_runtime"
    const val EVENT_CHANNEL = "mimicam/platform_runtime_events"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val sequence = AtomicLong(0)

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var applicationState = "foreground"

    @Volatile
    private var foregroundServiceActive = false

    @Volatile
    private var cameraDemand = false

    @Volatile
    private var microphoneDemand = false

    @Volatile
    private var lastServiceStopReason: String? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emit("snapshot", snapshotPayload())
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun snapshot(context: Context): Map<String, Any?> = snapshotPayload()

    fun setApplicationState(state: String) {
        if (applicationState == state) return
        applicationState = state
        emit("applicationLifecycle", mapOf("state" to state))
    }

    fun setForegroundServiceState(
        active: Boolean,
        camera: Boolean,
        microphone: Boolean,
        stopReason: String? = null
    ) {
        foregroundServiceActive = active
        cameraDemand = camera
        microphoneDemand = microphone
        lastServiceStopReason = stopReason
        emit(
            "foregroundServiceState",
            mapOf(
                "active" to active,
                "cameraDemand" to camera,
                "microphoneDemand" to microphone,
                "stopReason" to stopReason
            )
        )
    }

    fun emit(type: String, details: Map<String, Any?> = emptyMap()) {
        val event = HashMap<String, Any?>()
        event.putAll(details)
        event["type"] = type
        event["timestampMs"] = System.currentTimeMillis()
        event["sequence"] = sequence.incrementAndGet()
        mainHandler.post { eventSink?.success(event) }
    }

    private fun snapshotPayload(): Map<String, Any?> = mapOf(
        "platform" to "android",
        "applicationState" to applicationState,
        "supportsCameraInBackground" to true,
        "cameraRequiresForegroundStart" to true,
        "backgroundRecoveryAfterProcessDeath" to false,
        "foregroundServiceActive" to foregroundServiceActive,
        "cameraDemand" to cameraDemand,
        "microphoneDemand" to microphoneDemand,
        "activityAttached" to MimiCamEngineOwner.activityAttached,
        "serviceOwnsEngine" to MimiCamEngineOwner.serviceOwnsEngine,
        "engineAvailable" to (MimiCamEngineOwner.engine != null),
        "lastServiceStopReason" to lastServiceStopReason
    )
}
