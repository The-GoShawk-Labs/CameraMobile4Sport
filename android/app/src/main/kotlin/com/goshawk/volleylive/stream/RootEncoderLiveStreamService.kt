package com.goshawk.volleylive.stream

import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.util.Log
import android.view.OrientationEventListener
import android.view.Surface
import android.view.WindowManager
import com.pedro.common.AudioCodec
import com.pedro.common.ConnectChecker
import com.pedro.common.VideoCodec
import com.pedro.encoder.input.gl.render.filters.`object`.ImageObjectFilterRender
import com.pedro.encoder.input.video.CameraHelper
import com.pedro.encoder.utils.CodecUtil
import com.pedro.library.rtmp.RtmpCamera2
import com.pedro.library.view.OpenGlView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Hardware-accelerated RTMP/RTMPS streaming service powered by pedroSG94/RootEncoder (v2.5.4).
 * - Zero software CPU encoding (strictly hardware MediaCodec H.264 + AAC).
 * - Full dynamic orientation support (Landscape 16:9 / 1920x1080 and Portrait 9:16 / 1080x1920).
 * - Offscreen / SurfaceTexture OpenGL ES pipeline via RtmpCamera2 (GlStreamInterface).
 * - Hardware OpenGL scoreboard burn-in using ImageObjectFilterRender + VolleyballScoreboardBitmapRenderer.
 * - Texture upload (filter.setImage) triggered EXCLUSIVELY on score change or 1s match clock tick.
 * - 6 broadcast anchor positions (2 rows x 3 columns) relative to active video stream canvas.
 */
class RootEncoderLiveStreamService(
    private val context: Context,
    private val openGlView: OpenGlView? = null
) : ConnectChecker {

    companion object {
        private const val TAG = "RootEncoderStream"
        private const val SAFE_MARGIN_X_PERCENT = 3.0f
        private const val SAFE_MARGIN_Y_PERCENT = 3.0f
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var rtmpCamera2: RtmpCamera2? = null
    private var scoreboardFilter: ImageObjectFilterRender? = null

    private var orientationListener: OrientationEventListener? = null
    @Volatile
    private var deviceOrientationDegrees = -1

    @Volatile
    private var currentWidth = 1920
    @Volatile
    private var currentHeight = 1080
    @Volatile
    private var currentFps = 30
    @Volatile
    private var currentVideoBitrate = 4_000_000
    @Volatile
    private var currentAudioBitrate = 128_000
    @Volatile
    private var currentAudioSampleRate = 48_000
    @Volatile
    private var currentGopSeconds = 2.0f
    @Volatile
    private var currentAnchorPosition = "topLeft"
    @Volatile
    private var currentScoreboardStyle = "tvProBroadcast"

    private var renderer = VolleyballScoreboardBitmapRenderer(1920, 1080)
    private var lastScoreboardData = VolleyballScoreboardData()

    private var reconnectJob: Job? = null
    private var lastEndpointUrl: String? = null
    private var retryCount = 0
    private val maxRetries = 3

    @Volatile
    private var isUserStopped = false
    @Volatile
    private var isStreamingActive = false
    @Volatile
    private var cachedCapabilities: Map<String, Any>? = null

    var onStatusEvent: ((status: String, details: Map<String, Any>?) -> Unit)? = null

    init {
        ensureCameraInstance()
        initOrientationListener()
    }

    private fun initOrientationListener() {
        try {
            orientationListener = object : OrientationEventListener(context) {
                override fun onOrientationChanged(orientation: Int) {
                    if (orientation == ORIENTATION_UNKNOWN) return
                    val deg = when ((orientation + 45) / 90 * 90 % 360) {
                        0 -> 90 // Portrait
                        90 -> 180 // Reverse landscape
                        180 -> 270 // Reverse portrait
                        270 -> 0 // Landscape
                        else -> 90
                    }
                    deviceOrientationDegrees = deg
                }
            }
            if (orientationListener?.canDetectOrientation() == true) {
                orientationListener?.enable()
            }
        } catch (e: Exception) {
            Log.w(TAG, "OrientationEventListener init ignored: ${e.message}")
        }
    }

    fun resolveDeviceRotation(
        requestedWidth: Int = currentWidth,
        requestedHeight: Int = currentHeight,
        isExplicitPortrait: Boolean? = null
    ): Int {
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        val displayRotation = windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        val displayDegrees = when (displayRotation) {
            Surface.ROTATION_0 -> 90
            Surface.ROTATION_90 -> 0
            Surface.ROTATION_180 -> 270
            Surface.ROTATION_270 -> 180
            else -> 0
        }

        val isPortrait = when {
            isExplicitPortrait != null -> isExplicitPortrait
            requestedWidth > 0 && requestedHeight > 0 && requestedWidth != requestedHeight -> requestedWidth < requestedHeight
            deviceOrientationDegrees != -1 -> deviceOrientationDegrees == 90 || deviceOrientationDegrees == 270
            else -> displayDegrees == 90 || displayDegrees == 270
        }

        var rotation = if (deviceOrientationDegrees != -1) deviceOrientationDegrees else displayDegrees
        if (isPortrait && rotation != 90 && rotation != 270) {
            rotation = 90
        } else if (!isPortrait && (rotation == 90 || rotation == 270)) {
            rotation = 0
        }

        rtmpCamera2?.let { camera ->
            if (camera.isFrontCamera) {
                rotation = (360 - rotation) % 360
            }
        }

        return rotation
    }

    @Synchronized
    private fun ensureCameraInstance(): RtmpCamera2 {
        rtmpCamera2?.let { return it }
        val instance = if (openGlView != null) {
            RtmpCamera2(openGlView, this)
        } else {
            RtmpCamera2(context, this)
        }
        instance.forceCodecType(CodecUtil.CodecType.HARDWARE, CodecUtil.CodecType.HARDWARE)
        instance.setVideoCodec(VideoCodec.H264)
        instance.setAudioCodec(AudioCodec.AAC)
        rtmpCamera2 = instance
        return instance
    }

    @Synchronized
    fun initialize(
        width: Int = 1920,
        height: Int = 1080,
        fps: Int = 30,
        videoBitrate: Int = 4_000_000,
        audioBitrate: Int = 128_000,
        gopSeconds: Float = 2.0f,
        audioSampleRate: Int = 48_000,
        @Suppress("UNUSED_PARAMETER") audioChannels: Int = 2,
        isPortrait: Boolean? = null
    ) {
        val rawWidth = if (width > 0) width else 1920
        val rawHeight = if (height > 0) height else 1080
        val rotation = resolveDeviceRotation(rawWidth, rawHeight, isPortrait)
        val portrait = (rotation == 90 || rotation == 270)

        // Landscape: 1920x1080 (or 1280x720)
        // Portrait: 1080x1920 (or 720x1280)
        val safeWidth = (if (portrait) minOf(rawWidth, rawHeight) else maxOf(rawWidth, rawHeight)) and 1.inv()
        val safeHeight = (if (portrait) maxOf(rawWidth, rawHeight) else minOf(rawWidth, rawHeight)) and 1.inv()
        val safeFps = fps.coerceIn(15, 60)
        val normalizedBitrate = normalizeBitrateBps(videoBitrate)

        val dimensionsChanged = safeWidth != currentWidth || safeHeight != currentHeight
        currentWidth = safeWidth
        currentHeight = safeHeight
        currentFps = safeFps
        currentVideoBitrate = normalizedBitrate
        currentAudioBitrate = if (audioBitrate in 1..1000) audioBitrate * 1000 else audioBitrate
        currentGopSeconds = gopSeconds.coerceAtLeast(1.0f)
        currentAudioSampleRate = if (audioSampleRate > 0) audioSampleRate else 48_000

        if (dimensionsChanged) {
            renderer = VolleyballScoreboardBitmapRenderer(safeWidth, safeHeight)
            renderer.updateData(lastScoreboardData)
        }
        ensureCameraInstance()
    }

    private fun normalizeBitrateBps(bitrate: Int): Int {
        return when {
            bitrate in 500..50_000 -> bitrate * 1000 // Convert kbps (e.g. 3500-4500) to bps
            bitrate > 50_000 -> bitrate
            else -> 4_000_000
        }
    }

    /**
     * Starts hardware-encoded RTMP/RTMPS broadcast with OpenGL scoreboard filter.
     */
    fun startStream(
        rtmpUrl: String,
        streamKey: String = "",
        width: Int = currentWidth,
        height: Int = currentHeight,
        bitrate: Int = currentVideoBitrate,
        fps: Int = currentFps,
        isPortrait: Boolean? = null,
        onSuccess: () -> Unit = {},
        onError: (String) -> Unit = {}
    ) {
        isUserStopped = false
        retryCount = 0

        initialize(
            width = width,
            height = height,
            fps = fps,
            videoBitrate = bitrate,
            audioBitrate = currentAudioBitrate,
            gopSeconds = currentGopSeconds,
            audioSampleRate = currentAudioSampleRate,
            isPortrait = isPortrait
        )

        val endpoint = buildEndpointUrl(rtmpUrl, streamKey)
        if (endpoint.isEmpty()) {
            val err = "Brak poprawnego adresu docelowego RTMP/RTMPS"
            onStatusEvent?.invoke("ERROR", mapOf("error" to err))
            onError(err)
            return
        }
        lastEndpointUrl = endpoint

        onStatusEvent?.invoke(
            "CONNECTING",
            mapOf("details" to "Inicjalizacja MediaCodec + OpenGL ($currentWidth×$currentHeight @ ${currentFps}fps)...")
        )

        scope.launch {
            try {
                executeStartStreamInternal(endpoint)
                onSuccess()
            } catch (e: Exception) {
                Log.e(TAG, "startStream failed: ${e.message}", e)
                val msg = e.message ?: "Błąd uruchomienia enkodera sprzętowego RootEncoder"
                onStatusEvent?.invoke("ERROR", mapOf("error" to msg))
                onError(msg)
            }
        }
    }

    @Synchronized
    private fun executeStartStreamInternal(endpoint: String) {
        val camera = ensureCameraInstance()
        if (camera.isStreaming) {
            try {
                camera.stopStream()
            } catch (_: Exception) {}
        }

        camera.forceCodecType(CodecUtil.CodecType.HARDWARE, CodecUtil.CodecType.HARDWARE)
        camera.setVideoCodec(VideoCodec.H264)
        camera.setAudioCodec(AudioCodec.AAC)

        val rotation = resolveDeviceRotation(currentWidth, currentHeight)
        val iFrameInterval = currentGopSeconds.toInt().coerceAtLeast(1)

        // RootEncoder VideoEncoder expects base dimensions (longer x shorter).
        // When rotation is 90 or 270, it automatically creates a portrait MediaFormat (height x width)
        // and configures glInterface encoder size and portrait rendering mode.
        val baseWidth = maxOf(currentWidth, currentHeight)
        val baseHeight = minOf(currentWidth, currentHeight)

        // Try H.264 High Profile 4.1 first, fallback to Baseline / default hardware profile
        val videoPrepared = camera.prepareVideo(
            baseWidth,
            baseHeight,
            currentFps,
            currentVideoBitrate,
            iFrameInterval,
            rotation,
            MediaCodecInfo.CodecProfileLevel.AVCProfileHigh,
            MediaCodecInfo.CodecProfileLevel.AVCLevel41
        ) || camera.prepareVideo(
            baseWidth,
            baseHeight,
            currentFps,
            currentVideoBitrate,
            iFrameInterval,
            rotation,
            MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline,
            MediaCodecInfo.CodecProfileLevel.AVCLevel31
        ) || camera.prepareVideo(
            baseWidth,
            baseHeight,
            currentFps,
            currentVideoBitrate,
            iFrameInterval,
            rotation
        )

        if (!videoPrepared) {
            throw IllegalStateException("Sprzętowy enkoder MediaCodec H.264 odrzucił konfigurację ${currentWidth}x${currentHeight}@${currentFps}fps (rot=$rotation)")
        }

        // AAC 128 kbps, 48000 Hz stereo from device microphone (fallback to 44100 Hz if needed)
        val audioPrepared = camera.prepareAudio(
            currentAudioBitrate,
            currentAudioSampleRate,
            true,
            false,
            false
        ) || camera.prepareAudio(
            128_000,
            44_100,
            true,
            false,
            false
        )

        if (!audioPrepared) {
            Log.w(TAG, "Hardware AAC audio preparation returned false; proceeding with video stream")
        }

        camera.startStream(endpoint)

        // Attach OpenGL ES scoreboard filter and upload initial bitmap texture once
        attachAndRefreshScoreboardFilter(camera)
        Log.i(
            TAG,
            "RootEncoder hardware stream started: ${currentWidth}x${currentHeight}@${currentFps}fps (rot=$rotation), " +
                "bitrate=${currentVideoBitrate / 1000}kbps, anchor=$currentAnchorPosition"
        )
    }

    @Synchronized
    private fun attachAndRefreshScoreboardFilter(camera: RtmpCamera2) {
        val filter = ImageObjectFilterRender()
        scoreboardFilter = filter
        camera.glInterface.setFilter(filter)

        val snapshot = renderer.forceRenderAndSnapshot()
        filter.setImage(snapshot)
        applyAnchorPositionAndScale(filter, currentAnchorPosition)
    }

    /**
     * Updates scoreboard data and refreshes the OpenGL texture ONLY when score data
     * or the 1-second match clock actually changed.
     */
    @Synchronized
    fun updateScoreboard(data: VolleyballScoreboardData) {
        val resolvedAnchor = if (data.anchorPosition.isNotBlank()) data.anchorPosition else currentAnchorPosition
        val anchorChanged = resolvedAnchor != currentAnchorPosition
        if (anchorChanged) {
            currentAnchorPosition = resolvedAnchor
        }

        val resolvedStyle = if (data.style.isNotBlank()) data.style else currentScoreboardStyle
        val styleChanged = resolvedStyle != currentScoreboardStyle
        if (styleChanged) {
            currentScoreboardStyle = resolvedStyle
        }

        val resolvedClock = if (data.matchClock.isNotBlank()) data.matchClock else lastScoreboardData.matchClock
        val normalizedData = data.copy(
            anchorPosition = currentAnchorPosition,
            style = currentScoreboardStyle,
            matchClock = resolvedClock
        )
        lastScoreboardData = normalizedData
        renderer.updateData(normalizedData)

        val filter = scoreboardFilter ?: return
        val dirtySnapshot = if (styleChanged) renderer.forceRenderAndSnapshot() else renderer.renderAndSnapshotIfDirty()
        if (dirtySnapshot != null) {
            filter.setImage(dirtySnapshot)
            applyAnchorPositionAndScale(filter, currentAnchorPosition)
        } else if (anchorChanged) {
            applyAnchorPositionAndScale(filter, currentAnchorPosition)
        }
    }

    /**
     * Dynamically updates the scoreboard theme style and refreshes the OpenGL texture in-flight
     * without interrupting RTMP streaming.
     */
    @Synchronized
    fun setScoreboardStyle(style: String) {
        val cleanStyle = style.trim().ifEmpty { "tvProBroadcast" }
        if (cleanStyle != currentScoreboardStyle) {
            currentScoreboardStyle = cleanStyle
            lastScoreboardData = lastScoreboardData.copy(style = cleanStyle)
            renderer.updateData(lastScoreboardData)
            scoreboardFilter?.let { filter ->
                val snapshot = renderer.forceRenderAndSnapshot()
                filter.setImage(snapshot)
                applyAnchorPositionAndScale(filter, currentAnchorPosition)
            }
        }
    }

    /**
     * Sets one of the 6 scoreboard anchor positions (2 rows x 3 columns) in OpenGL space
     * with ~3% TV safe margins without re-rendering the bitmap.
     */
    @Synchronized
    fun setScoreboardPosition(position: String) {
        val cleanPos = position.trim().ifEmpty { "topLeft" }
        if (cleanPos != currentAnchorPosition) {
            currentAnchorPosition = cleanPos
            lastScoreboardData = lastScoreboardData.copy(anchorPosition = cleanPos)
        }
        scoreboardFilter?.let { filter ->
            applyAnchorPositionAndScale(filter, currentAnchorPosition)
        }
    }

    /**
     * Calculates OpenGL percentage scale and position (0..100%) for the 6 anchor points:
     * topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight.
     * Scale and position are relative to the active video stream canvas (W_stream x H_stream).
     * Note: setScale() MUST be called before setPosition() in RootEncoder's Sprite.
     */
    private fun applyAnchorPositionAndScale(
        filter: ImageObjectFilterRender,
        anchor: String,
        customWidth: Int = renderer.overlayWidth,
        customHeight: Int = renderer.overlayHeight
    ) {
        val frameW = currentWidth.coerceAtLeast(1).toFloat()
        val frameH = currentHeight.coerceAtLeast(1).toFloat()
        val isPortrait = frameH > frameW

        val marginX = if (isPortrait) 3.5f else SAFE_MARGIN_X_PERCENT
        val marginY = SAFE_MARGIN_Y_PERCENT

        val scaleX = ((customWidth.toFloat() / frameW) * 100f).coerceIn(5f, 90f)
        val scaleY = ((customHeight.toFloat() / frameH) * 100f).coerceIn(4f, 50f)

        // 1. Scale first (Sprite.scale adjusts existing translation)
        filter.setScale(scaleX, scaleY)

        // 2. Position in OpenGL screen percentage (0..100) with safe margins
        val posX: Float
        val posY: Float
        when (anchor) {
            "topCenter" -> {
                posX = (100f - scaleX) / 2f
                posY = marginY
            }
            "topRight" -> {
                posX = 100f - scaleX - marginX
                posY = marginY
            }
            "bottomLeft" -> {
                posX = marginX
                posY = 100f - scaleY - marginY
            }
            "bottomCenter" -> {
                posX = (100f - scaleX) / 2f
                posY = 100f - scaleY - marginY
            }
            "bottomRight" -> {
                posX = 100f - scaleX - marginX
                posY = 100f - scaleY - marginY
            }
            else -> { // "topLeft"
                posX = marginX
                posY = marginY
            }
        }
        filter.setPosition(posX, posY)
    }

    /**
     * Dynamically updates stream orientation & scoreboard geometry when rotating device.
     */
    @Synchronized
    fun updateOrientation(isPortrait: Boolean) {
        val newW = if (isPortrait) minOf(currentWidth, currentHeight) else maxOf(currentWidth, currentHeight)
        val newH = if (isPortrait) maxOf(currentWidth, currentHeight) else minOf(currentWidth, currentHeight)
        if (newW != currentWidth || newH != currentHeight) {
            currentWidth = newW
            currentHeight = newH
            renderer = VolleyballScoreboardBitmapRenderer(currentWidth, currentHeight)
            renderer.updateData(lastScoreboardData)
            scoreboardFilter?.let { filter ->
                val snapshot = renderer.forceRenderAndSnapshot()
                filter.setImage(snapshot)
                applyAnchorPositionAndScale(filter, currentAnchorPosition)
            }
        }
    }

    @Synchronized
    fun updateScoreboardOverlayBitmap(bytes: ByteArray, width: Int, height: Int, anchor: String = currentAnchorPosition) {
        if (anchor.isNotBlank()) {
            currentAnchorPosition = anchor
        }
        val filter = scoreboardFilter ?: return
        try {
            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return
            filter.setImage(bmp)
            val w = if (width > 0) width else bmp.width
            val h = if (height > 0) height else bmp.height
            applyAnchorPositionAndScale(filter, currentAnchorPosition, w, h)
        } catch (e: Exception) {
            Log.w(TAG, "updateScoreboardOverlayBitmap decode warning: ${e.message}")
        }
    }

    fun switchCamera() {
        scope.launch {
            try {
                rtmpCamera2?.switchCamera()
            } catch (e: Exception) {
                Log.w(TAG, "switchCamera error: ${e.message}")
            }
        }
    }

    fun stopStream() {
        isUserStopped = true
        isStreamingActive = false
        reconnectJob?.cancel()
        reconnectJob = null

        scope.launch {
            synchronized(this@RootEncoderLiveStreamService) {
                try {
                    rtmpCamera2?.glInterface?.clearFilters()
                } catch (_: Exception) {}
                scoreboardFilter = null
                try {
                    if (rtmpCamera2?.isStreaming == true) {
                        rtmpCamera2?.stopStream()
                    }
                    if (rtmpCamera2?.isOnPreview == true) {
                        rtmpCamera2?.stopPreview()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "stopStream warning: ${e.message}")
                }
            }
            onStatusEvent?.invoke("DISCONNECTED", mapOf("details" to "Transmisja zakończona"))
        }
    }

    fun release() {
        try {
            orientationListener?.disable()
            orientationListener = null
        } catch (_: Exception) {}
        stopStream()
    }

    private fun buildEndpointUrl(rtmpUrl: String, streamKey: String): String {
        val cleanUrl = rtmpUrl.trim().trimEnd('/')
        if (cleanUrl.isEmpty()) return ""
        val cleanKey = streamKey.trim().trimStart('/')
        return if (cleanKey.isEmpty() || cleanUrl.endsWith("/$cleanKey")) {
            cleanUrl
        } else {
            "$cleanUrl/$cleanKey"
        }
    }

    // =========================================================================
    // ConnectChecker (RootEncoder callbacks)
    // =========================================================================
    override fun onConnectionStarted(url: String) {
        Log.i(TAG, "RTMP connection started: $url")
        onStatusEvent?.invoke(
            "CONNECTING",
            mapOf("details" to "Łączenie z serwerem RTMP...")
        )
    }

    override fun onConnectionSuccess() {
        Log.i(TAG, "RTMP connection SUCCESS")
        retryCount = 0
        isStreamingActive = true
        onStatusEvent?.invoke(
            "CONNECTED",
            mapOf(
                "details" to "Połączono z serwerem nadawczym (MediaCodec + OpenGL)",
                "bitrate" to currentVideoBitrate,
                "fps" to currentFps
            )
        )
    }

    override fun onConnectionFailed(reason: String) {
        Log.e(TAG, "RTMP connection failed: $reason")
        isStreamingActive = false

        val endpoint = lastEndpointUrl
        if (!isUserStopped && retryCount < maxRetries && !endpoint.isNullOrEmpty()) {
            retryCount++
            val delayMs = 2000L * retryCount
            onStatusEvent?.invoke(
                "RECONNECTING",
                mapOf(
                    "attempt" to retryCount,
                    "maxAttempts" to maxRetries,
                    "delayMs" to delayMs,
                    "details" to "Błąd połączenia ($reason). Ponawianie $retryCount/$maxRetries..."
                )
            )
            reconnectJob?.cancel()
            reconnectJob = scope.launch {
                delay(delayMs)
                if (!isUserStopped) {
                    try {
                        executeStartStreamInternal(endpoint)
                    } catch (e: Exception) {
                        Log.e(TAG, "Reconnect attempt failed: ${e.message}")
                    }
                }
            }
        } else {
            try {
                rtmpCamera2?.stopStream()
            } catch (_: Exception) {}
            onStatusEvent?.invoke(
                "ERROR",
                mapOf("error" to "Błąd połączenia RTMP: $reason")
            )
        }
    }

    override fun onNewBitrate(bitrate: Long) {
        if (!isStreamingActive) return
        onStatusEvent?.invoke(
            "BITRATE_UPDATE",
            mapOf(
                "bitrate" to bitrate.toInt(),
                "fps" to currentFps,
                "droppedFrames" to 0,
                "jitterMs" to 0.5
            )
        )
    }

    override fun onDisconnect() {
        Log.i(TAG, "RTMP disconnected")
        isStreamingActive = false
        onStatusEvent?.invoke(
            "DISCONNECTED",
            mapOf("details" to "Rozłączono z serwerem RTMP")
        )
    }

    override fun onAuthError() {
        Log.e(TAG, "RTMP authentication error")
        isStreamingActive = false
        onStatusEvent?.invoke(
            "ERROR",
            mapOf("error" to "Błąd autoryzacji klucza strumienia RTMP")
        )
    }

    override fun onAuthSuccess() {
        Log.i(TAG, "RTMP authentication success")
    }

    /**
     * Inspects local hardware MediaCodec capabilities for H.264 / AVC.
     */
    fun validateEncoderCapabilities(): Map<String, Any> {
        cachedCapabilities?.let { return it }
        var isH264Supported = false
        var isHighProfileSupported = false
        var isCbrSupported = false
        var maxWidth = 0
        var maxHeight = 0
        var maxFps = 0

        try {
            val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            for (info in codecList.codecInfos) {
                if (!info.isEncoder) continue
                for (type in info.supportedTypes) {
                    if (type.equals(MediaFormat.MIMETYPE_VIDEO_AVC, ignoreCase = true)) {
                        isH264Supported = true
                        val caps = info.getCapabilitiesForType(type)

                        val encCaps = caps.encoderCapabilities
                        if (encCaps != null && encCaps.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)) {
                            isCbrSupported = true
                        }

                        for (pl in caps.profileLevels) {
                            if (pl.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileHigh) {
                                isHighProfileSupported = true
                            }
                        }

                        val vidCaps = caps.videoCapabilities
                        if (vidCaps != null) {
                            maxWidth = maxOf(maxWidth, vidCaps.supportedWidths.upper)
                            maxHeight = maxOf(maxHeight, vidCaps.supportedHeights.upper)
                            maxFps = maxOf(maxFps, vidCaps.supportedFrameRates.upper.toInt())
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "validateEncoderCapabilities exception: ${e.message}")
        }

        return mapOf(
            "isH264Supported" to isH264Supported,
            "isHighProfileSupported" to isHighProfileSupported,
            "isCbrSupported" to isCbrSupported,
            "maxSupportedWidth" to maxWidth,
            "maxSupportedHeight" to maxHeight,
            "maxSupportedFps" to maxFps,
            "compliantWithYouTube" to (isH264Supported && isHighProfileSupported && isCbrSupported)
        ).also { cachedCapabilities = it }
    }
}
