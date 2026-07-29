package com.miucam.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicLong

/**
 * Keeps the single UI isolate alive while the foreground service owns the
 * server media runtime or client alert connection. A sticky service is
 * deliberately not used: after process
 * death Android cannot silently reacquire while-in-use camera/microphone
 * access from the background.
 */
object MiuCamEngineOwner {
    const val ENGINE_CACHE_ID = "miucam.runtime.engine"

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
        MiuCamPlatformRuntime.emit(
            "engineOwnershipChanged",
            mapOf("activityAttached" to true, "serviceOwnsEngine" to serviceOwnsEngine)
        )
    }

    @Synchronized
    fun markActivityAttached(attached: Boolean) {
        activityAttached = attached
        MiuCamPlatformRuntime.emit(
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
        MiuCamPlatformRuntime.emit(
            "engineOwnershipChanged",
            mapOf("activityAttached" to activityAttached, "serviceOwnsEngine" to true)
        )
        return current
    }

    @Synchronized
    fun releaseService() {
        serviceOwnsEngine = false
        MiuCamPlatformRuntime.emit(
            "engineOwnershipChanged",
            mapOf("activityAttached" to activityAttached, "serviceOwnsEngine" to false)
        )
    }
}

object MiuCamPlatformRuntime : EventChannel.StreamHandler {
    const val METHOD_CHANNEL = "miucam/platform_runtime"
    const val EVENT_CHANNEL = "miucam/platform_runtime_events"

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
    private var playbackDemand = false

    @Volatile
    private var alertDemand = false

    @Volatile
    private var serverDemand = false

    @Volatile
    private var requestedNativeCameraCaptureDemand = false

    @Volatile
    private var requestedNativeMicrophoneCaptureDemand = false

    @Volatile
    private var serviceCameraDemand = false

    @Volatile
    private var serviceMicrophoneDemand = false

    @Volatile
    private var servicePlaybackDemand = false

    @Volatile
    private var serviceAlertDemand = false

    @Volatile
    private var serviceServerDemand = false

    @Volatile
    private var serviceNativeCameraCaptureDemand = false

    @Volatile
    private var serviceNativeMicrophoneCaptureDemand = false

    @Volatile
    private var audioOutputActive = false

    @Volatile
    private var nativeCameraRequested = false

    @Volatile
    private var nativeMicrophoneRequested = false

    @Volatile
    private var nativeCameraActive = false

    @Volatile
    private var nativeMicrophoneActive = false

    @Volatile
    private var nativeCameraError: String? = null

    @Volatile
    private var nativeMicrophoneError: String? = null

    @Volatile
    private var nativeCaptureDiagnostics: Map<String, Any?> = emptyMap()

    @Volatile
    private var lastServiceStopReason: String? = null

    val isForegroundServiceActive: Boolean
        get() = foregroundServiceActive

    val isCameraDemandRequested: Boolean
        get() = cameraDemand

    val isMicrophoneDemandRequested: Boolean
        get() = microphoneDemand

    val isPlaybackDemandRequested: Boolean
        get() = playbackDemand

    val isAlertDemandRequested: Boolean
        get() = alertDemand

    val isServerDemandRequested: Boolean
        get() = serverDemand

    val hasRequestedRuntimeDemand: Boolean
        get() = serverDemand || alertDemand || cameraDemand ||
            microphoneDemand || playbackDemand

    val isNativeCameraCaptureRequested: Boolean
        get() = requestedNativeCameraCaptureDemand

    val isNativeMicrophoneCaptureRequested: Boolean
        get() = requestedNativeMicrophoneCaptureDemand

    val canStartWhileInUseForegroundService: Boolean
        get() = MiuCamEngineOwner.activityAttached &&
            (applicationState == "foreground" || applicationState == "foregroundActive")

    private val externalCameraCaptureDemand: Boolean
        get() = foregroundServiceActive && serviceCameraDemand &&
            !serviceNativeCameraCaptureDemand

    private val externalMicrophoneCaptureDemand: Boolean
        get() = foregroundServiceActive && serviceMicrophoneDemand &&
            !serviceNativeMicrophoneCaptureDemand

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

    fun setRequestedMediaDemand(
        active: Boolean,
        camera: Boolean,
        microphone: Boolean,
        playback: Boolean,
        nativeCameraCapture: Boolean = camera,
        nativeMicrophoneCapture: Boolean = microphone
    ) {
        val hasDemand = active && (camera || microphone || playback)
        cameraDemand = hasDemand && camera
        microphoneDemand = hasDemand && microphone
        playbackDemand = hasDemand && playback
        requestedNativeCameraCaptureDemand =
            hasDemand && camera && nativeCameraCapture
        requestedNativeMicrophoneCaptureDemand =
            hasDemand && microphone && nativeMicrophoneCapture
        emit(
            "mediaDemandChanged",
            mapOf(
                "active" to hasDemand,
                "cameraDemand" to cameraDemand,
                "microphoneDemand" to microphoneDemand,
                "playbackDemand" to playbackDemand,
                "nativeCameraCapture" to requestedNativeCameraCaptureDemand,
                "nativeMicrophoneCapture" to requestedNativeMicrophoneCaptureDemand
            )
        )
    }

    fun setRequestedAlertDemand(active: Boolean) {
        if (alertDemand == active) return
        alertDemand = active
        emit("alertDemandChanged", mapOf("active" to active))
    }

    fun setRequestedServerDemand(active: Boolean) {
        if (serverDemand == active) return
        serverDemand = active
        emit("serverDemandChanged", mapOf("active" to active))
    }

    fun setForegroundServiceState(
        active: Boolean,
        camera: Boolean,
        microphone: Boolean,
        playback: Boolean = false,
        alert: Boolean = false,
        server: Boolean = false,
        nativeCameraCapture: Boolean = camera,
        nativeMicrophoneCapture: Boolean = microphone,
        stopReason: String? = null
    ) {
        foregroundServiceActive = active
        serviceCameraDemand = active && camera
        serviceMicrophoneDemand = active && microphone
        servicePlaybackDemand = active && playback
        serviceAlertDemand = active && alert
        serviceServerDemand = active && server
        serviceNativeCameraCaptureDemand = active && camera && nativeCameraCapture
        serviceNativeMicrophoneCaptureDemand =
            active && microphone && nativeMicrophoneCapture
        lastServiceStopReason = stopReason
        emit(
            "foregroundServiceState",
            mapOf(
                "active" to active,
                "cameraDemand" to camera,
                "microphoneDemand" to microphone,
                "playbackDemand" to playback,
                "alertDemand" to serviceAlertDemand,
                "serverDemand" to serviceServerDemand,
                "nativeCameraCapture" to serviceNativeCameraCaptureDemand,
                "nativeMicrophoneCapture" to serviceNativeMicrophoneCaptureDemand,
                "externalCameraCaptureDemand" to externalCameraCaptureDemand,
                "externalMicrophoneCaptureDemand" to externalMicrophoneCaptureDemand,
                "stopReason" to stopReason
            )
        )
    }

    fun setForegroundServiceFailure(reason: String) {
        foregroundServiceActive = false
        serviceCameraDemand = false
        serviceMicrophoneDemand = false
        servicePlaybackDemand = false
        serviceAlertDemand = false
        serviceServerDemand = false
        serviceNativeCameraCaptureDemand = false
        serviceNativeMicrophoneCaptureDemand = false
        lastServiceStopReason = reason
        emit(
            "foregroundServiceStartFailed",
            mapOf(
                "reason" to reason,
                "cameraDemand" to cameraDemand,
                "microphoneDemand" to microphoneDemand,
                "playbackDemand" to playbackDemand,
                "alertDemand" to alertDemand,
                "serverDemand" to serverDemand
            )
        )
    }

    fun setAudioOutputActive(active: Boolean, reason: String) {
        if (audioOutputActive == active) return
        audioOutputActive = active
        emit(
            "audioOutputStateChanged",
            mapOf("active" to active, "reason" to reason)
        )
    }

    fun setNativeMediaCaptureState(
        cameraRequested: Boolean,
        microphoneRequested: Boolean,
        cameraActive: Boolean,
        microphoneActive: Boolean,
        cameraError: String?,
        microphoneError: String?,
        diagnostics: Map<String, Any?>
    ) {
        nativeCameraRequested = cameraRequested
        nativeMicrophoneRequested = microphoneRequested
        nativeCameraActive = cameraActive
        nativeMicrophoneActive = microphoneActive
        nativeCameraError = cameraError
        nativeMicrophoneError = microphoneError
        nativeCaptureDiagnostics = diagnostics
        emit(
            "nativeMediaCaptureState",
            mapOf(
                "cameraRequested" to cameraRequested,
                "microphoneRequested" to microphoneRequested,
                "cameraActive" to cameraActive,
                "microphoneActive" to microphoneActive,
                "cameraError" to cameraError,
                "microphoneError" to microphoneError
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
        "supportsMicrophoneInBackground" to true,
        "nativeServiceMediaAvailable" to true,
        "cameraRequiresForegroundStart" to true,
        "backgroundRecoveryAfterProcessDeath" to false,
        "foregroundServiceActive" to foregroundServiceActive,
        "cameraDemand" to cameraDemand,
        "microphoneDemand" to microphoneDemand,
        "playbackDemand" to playbackDemand,
        "alertDemand" to alertDemand,
        "serverDemand" to serverDemand,
        "audioOutputActive" to audioOutputActive,
        "supportsServerInBackground" to
            (foregroundServiceActive && serviceServerDemand),
        "supportsAlertsInBackground" to
            (foregroundServiceActive && serviceAlertDemand),
        "supportsAudioOutputInBackground" to
            (foregroundServiceActive && servicePlaybackDemand),
        "serviceOwnsNativeMediaHardware" to
            (foregroundServiceActive && (nativeCameraActive || nativeMicrophoneActive)),
        "externalCameraCaptureDemand" to externalCameraCaptureDemand,
        "externalMicrophoneCaptureDemand" to externalMicrophoneCaptureDemand,
        "externalMediaCaptureDemand" to
            (externalCameraCaptureDemand || externalMicrophoneCaptureDemand),
        "serviceOwnsMediaHardware" to
            (
                foregroundServiceActive &&
                    (
                        nativeCameraActive ||
                            nativeMicrophoneActive ||
                            externalCameraCaptureDemand ||
                            externalMicrophoneCaptureDemand
                        )
                ),
        "nativeCameraRequested" to nativeCameraRequested,
        "nativeMicrophoneRequested" to nativeMicrophoneRequested,
        "nativeCameraActive" to nativeCameraActive,
        "nativeMicrophoneActive" to nativeMicrophoneActive,
        "nativeCameraError" to nativeCameraError,
        "nativeMicrophoneError" to nativeMicrophoneError,
        "nativeCaptureDiagnostics" to nativeCaptureDiagnostics,
        "serviceCameraDemand" to serviceCameraDemand,
        "serviceMicrophoneDemand" to serviceMicrophoneDemand,
        "servicePlaybackDemand" to servicePlaybackDemand,
        "serviceAlertDemand" to serviceAlertDemand,
        "serviceServerDemand" to serviceServerDemand,
        "serviceNativeCameraCaptureDemand" to serviceNativeCameraCaptureDemand,
        "serviceNativeMicrophoneCaptureDemand" to
            serviceNativeMicrophoneCaptureDemand,
        "activityAttached" to MiuCamEngineOwner.activityAttached,
        "serviceOwnsEngine" to MiuCamEngineOwner.serviceOwnsEngine,
        "engineAvailable" to (MiuCamEngineOwner.engine != null),
        "lastServiceStopReason" to lastServiceStopReason,
        "contractMessage" to if (
            externalCameraCaptureDemand || externalMicrophoneCaptureDemand
        ) {
            "Android foreground service WebRTC medya yakalayıcısı için motoru ve FGS tiplerini korur."
        } else if (nativeCameraActive || nativeMicrophoneActive) {
            "Android foreground service CameraX ve AudioRecord donanımının gerçek sahibidir."
        } else if (serviceServerDemand) {
            "Android foreground service yerel ağ sunucusunu ve Wi-Fi bağlantısını canlı tutar."
        } else if (serviceAlertDemand) {
            "Android foreground service istemci uyarı bağlantısını arka planda canlı tutar."
        } else {
            "Android kamera ve mikrofonu görünür başlangıçtan sonra foreground service devralır."
        }
    )
}
