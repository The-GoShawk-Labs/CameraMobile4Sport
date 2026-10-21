package com.goshawk.volleylive.stream

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CaptureRequest
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.util.Log
import android.util.Range
import android.view.OrientationEventListener
import android.view.Surface
import android.view.WindowManager
import com.pedro.common.AudioCodec
import com.pedro.common.ConnectChecker
import com.pedro.common.VideoCodec
import com.pedro.encoder.BaseEncoder
import com.pedro.encoder.input.gl.render.filters.`object`.ImageObjectFilterRender
import com.pedro.encoder.input.video.CameraCallbacks
import com.pedro.encoder.input.video.CameraHelper
import com.pedro.encoder.utils.CodecUtil
import com.pedro.encoder.utils.gl.AspectRatioMode
import com.pedro.encoder.video.FormatVideoEncoder
import com.pedro.encoder.video.GetVideoData
import com.pedro.encoder.video.VideoEncoder
import com.pedro.library.base.Camera2Base
import com.pedro.library.rtmp.RtmpCamera2
import com.pedro.library.view.GlStreamInterface
import com.pedro.library.view.OpenGlView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Własny VideoEncoder wymuszający przestrzeń barw BT.709 oraz ograniczony zakres YUV (Limited Range).
 * Zapobiega oznaczaniu klatek przez enkoder MediaCodec jako JPEG full range (yuvj420p)
 * i eliminuje ostrzeżenie FFmpeg: "deprecated pixel format used, make sure you did set range correctly (yuvj420p)".
 */
private class Bt709VideoEncoder(getVideoData: GetVideoData) : VideoEncoder(getVideoData) {
    override fun prepareVideoEncoder(
        width: Int,
        height: Int,
        fps: Int,
        bitRate: Int,
        rotation: Int,
        iFrameInterval: Int,
        formatVideoEncoder: FormatVideoEncoder,
        profile: Int,
        level: Int
    ): Boolean {
        return try {
            val fPrepared = BaseEncoder::class.java.getDeclaredField("prepared").apply { isAccessible = true }
            if (fPrepared.getBoolean(this)) {
                stop()
            }

            require(width % 2 == 0) { "Invalid width: $width, must be an even value" }
            require(height % 2 == 0) { "Invalid height: $height, must be an even value" }
            require(fps > 0) { "Invalid fps: $fps, must be higher than 0" }

            val fWidth = VideoEncoder::class.java.getDeclaredField("width").apply { isAccessible = true }
            val fHeight = VideoEncoder::class.java.getDeclaredField("height").apply { isAccessible = true }
            val fFps = VideoEncoder::class.java.getDeclaredField("fps").apply { isAccessible = true }
            val fBitRate = VideoEncoder::class.java.getDeclaredField("bitRate").apply { isAccessible = true }
            val fRotation = VideoEncoder::class.java.getDeclaredField("rotation").apply { isAccessible = true }
            val fIFrame = VideoEncoder::class.java.getDeclaredField("iFrameInterval").apply { isAccessible = true }
            val fFormat = VideoEncoder::class.java.getDeclaredField("formatVideoEncoder").apply { isAccessible = true }
            val fProfile = VideoEncoder::class.java.getDeclaredField("profile").apply { isAccessible = true }
            val fLevel = VideoEncoder::class.java.getDeclaredField("level").apply { isAccessible = true }
            val fCodec = BaseEncoder::class.java.getDeclaredField("codec").apply { isAccessible = true }
            val fInputSurface = VideoEncoder::class.java.getDeclaredField("inputSurface").apply { isAccessible = true }
            val fRunning = BaseEncoder::class.java.getDeclaredField("running").apply { isAccessible = true }
            val fIsBufferMode = BaseEncoder::class.java.getDeclaredField("isBufferMode").apply { isAccessible = true }

            fWidth.setInt(this, width)
            fHeight.setInt(this, height)
            fFps.setInt(this, fps)
            fBitRate.setInt(this, bitRate)
            fRotation.setInt(this, rotation)
            fIFrame.setInt(this, iFrameInterval)
            fFormat.set(this, formatVideoEncoder)
            fProfile.setInt(this, profile)
            fLevel.setInt(this, level)
            fIsBufferMode.setBoolean(this, true)

            val encoder = chooseEncoder(type) ?: run {
                Log.e("Bt709VideoEncoder", "Valid encoder not found for $type")
                return false
            }
            Log.i("Bt709VideoEncoder", "Encoder selected: ${encoder.name}")

            val codecInstance = MediaCodec.createByCodecName(encoder.name)
            fCodec.set(this, codecInstance)

            val formatW: Int
            val formatH: Int
            if (rotation == 90 || rotation == 270) {
                formatW = height
                formatH = width
            } else {
                formatW = width
                formatH = height
            }

            val mediaFormat = MediaFormat.createVideoFormat(type, formatW, formatH)
            Log.i("Bt709VideoEncoder", "Prepare video info: ${formatVideoEncoder.name}, ${formatW}x${formatH}")
            mediaFormat.setInteger("color-format", formatVideoEncoder.getFormatCodec())
            mediaFormat.setInteger("max-input-size", 0)
            mediaFormat.setInteger("bitrate", bitRate)
            mediaFormat.setInteger("frame-rate", fps)
            mediaFormat.setInteger("i-frame-interval", iFrameInterval)

            // 1. Wymuszenie stałego bitrate CBR (Constant Bitrate)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                mediaFormat.setInteger(
                    MediaFormat.KEY_BITRATE_MODE,
                    MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
                )
            } else {
                mediaFormat.setInteger("bitrate-mode", 2)
            }

            // 2. Całkowite wyłączenie klatek B-frames (Zero B-frames) - eliminuje buforowanie "pipelineFull"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                mediaFormat.setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
            } else {
                mediaFormat.setInteger("max-bframes", 0)
            }
            mediaFormat.setInteger("vendor.qti-ext-enc-b-frames.num-b-frames", 0)

            // 3. Ultra-niskie opóźnienie (Zero-Latency / Low-Latency mode) dla Android API 30+ (R)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                mediaFormat.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
                mediaFormat.setInteger(MediaFormat.KEY_LATENCY, 0)
            } else {
                mediaFormat.setInteger("low-latency", 1)
                mediaFormat.setInteger("latency", 0)
            }

            // 4. Priorytet czasu rzeczywistego (0 = Realtime, streaming na żywo)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                mediaFormat.setInteger(MediaFormat.KEY_PRIORITY, 0)
            } else {
                mediaFormat.setInteger("priority", 0)
            }

            if (profile > 0) mediaFormat.setInteger("profile", profile)
            if (level > 0) mediaFormat.setInteger("level", level)

            // 5. BT.709 ColorStandard & Limited ColorRange to avoid FFmpeg deprecated pixel format (yuvj420p)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                mediaFormat.setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
                mediaFormat.setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
                mediaFormat.setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
            }

            setCallback()

            try {
                codecInstance.configure(mediaFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            } catch (e: Exception) {
                Log.w("Bt709VideoEncoder", "Codec rejected BT.709 color keys: ${e.message}, retrying standard format")
                codecInstance.reset()
                val fallbackFormat = MediaFormat.createVideoFormat(type, formatW, formatH)
                fallbackFormat.setInteger("color-format", formatVideoEncoder.getFormatCodec())
                fallbackFormat.setInteger("max-input-size", 0)
                fallbackFormat.setInteger("bitrate", bitRate)
                fallbackFormat.setInteger("frame-rate", fps)
                fallbackFormat.setInteger("i-frame-interval", iFrameInterval)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    fallbackFormat.setInteger("bitrate-mode", 2)
                }
                fallbackFormat.setInteger("max-bframes", 0)
                fallbackFormat.setInteger("priority", 0)
                if (profile > 0) fallbackFormat.setInteger("profile", profile)
                if (level > 0) fallbackFormat.setInteger("level", level)
                codecInstance.configure(fallbackFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            }

            fRunning.setBoolean(this, false)

            if (formatVideoEncoder == FormatVideoEncoder.SURFACE && Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                fIsBufferMode.setBoolean(this, false)
                val surface = codecInstance.createInputSurface()
                fInputSurface.set(this, surface)
            }

            fPrepared.setBoolean(this, true)
            Log.i("Bt709VideoEncoder", "prepared with BT.709 limited color format")
            true
        } catch (e: Exception) {
            Log.e("Bt709VideoEncoder", "Create VideoEncoder failed: ${e.message}", e)
            stop()
            false
        }
    }
}

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
    private var sharedPreviewSurfaceTexture: SurfaceTexture? = null
    private var sharedPreviewSurface: Surface? = null

    private var orientationListener: OrientationEventListener? = null
    @Volatile
    private var deviceOrientationDegrees = -1
    @Volatile
    private var explicitPortraitOverride: Boolean? = null

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
    private var aeFpsJob: Job? = null
    @Volatile
    private var isReconfiguring = false
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

    /**
     * Binds a Flutter TextureRegistry SurfaceTexture so the hardware OpenGL pipeline
     * renders both to the MediaCodec GraphicBufferSource and the local PIP/preview widget.
     */
    @Synchronized
    fun setSharedPreviewSurfaceTexture(surfaceTexture: SurfaceTexture?) {
        sharedPreviewSurfaceTexture = surfaceTexture
        sharedPreviewSurface?.release()
        sharedPreviewSurface = surfaceTexture?.let { st ->
            st.setDefaultBufferSize(currentWidth.coerceAtLeast(1), currentHeight.coerceAtLeast(1))
            Surface(st)
        }
    }

    @Synchronized
    private fun attachSharedPreviewIfPossible(camera: RtmpCamera2) {
        val glStream = camera.glInterface as? GlStreamInterface ?: return
        val st = sharedPreviewSurfaceTexture ?: return
        try {
            glStream.deAttachPreview()
            st.setDefaultBufferSize(currentWidth.coerceAtLeast(1), currentHeight.coerceAtLeast(1))
            val surface = sharedPreviewSurface?.takeIf { it.isValid } ?: Surface(st).also {
                sharedPreviewSurface = it
            }
            val isPortrait = currentHeight > currentWidth
            val rotation = resolveDeviceRotation(currentWidth, currentHeight, isPortrait)
            val cameraOrientation = if (rotation == 0) 270 else rotation - 90
            glStream.setCameraOrientation(cameraOrientation)
            glStream.setAspectRatioMode(AspectRatioMode.Adjust)
            glStream.setIsPortrait(isPortrait)
            glStream.setPreviewResolution(currentWidth, currentHeight)
            glStream.attachPreview(surface)
        } catch (e: Exception) {
            Log.w(TAG, "attachSharedPreviewIfPossible warning: ${e.message}")
        }
    }

    @Synchronized
    private fun detachSharedPreviewIfAttached(camera: RtmpCamera2?) {
        val glStream = camera?.glInterface as? GlStreamInterface ?: return
        try {
            glStream.deAttachPreview()
        } catch (e: Exception) {
            Log.w(TAG, "detachSharedPreviewIfAttached warning: ${e.message}")
        }
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
        isExplicitPortrait: Boolean? = explicitPortraitOverride
    ): Int {
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        @Suppress("DEPRECATION")
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
            requestedWidth > 0 && requestedHeight > 0 -> requestedHeight > requestedWidth
            deviceOrientationDegrees != -1 -> deviceOrientationDegrees == 90 || deviceOrientationDegrees == 270
            displayDegrees == 90 || displayDegrees == 270 -> true
            else -> false
        }

        var rotation = if (isPortrait) {
            if (deviceOrientationDegrees == 270 || displayDegrees == 270) 270 else 90
        } else {
            if (deviceOrientationDegrees == 180 || displayDegrees == 180) 180 else 0
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
        (instance.glInterface as? GlStreamInterface)?.setAspectRatioMode(AspectRatioMode.Adjust)

        // Install BT.709 video encoder to avoid FFmpeg "deprecated pixel format used (yuvj420p)"
        try {
            val getVideoDataField = Camera2Base::class.java.getDeclaredField("getVideoData").apply { isAccessible = true }
            val getVideoData = getVideoDataField.get(instance) as GetVideoData
            val customVideoEncoder = Bt709VideoEncoder(getVideoData)
            val videoEncoderField = Camera2Base::class.java.getDeclaredField("videoEncoder").apply { isAccessible = true }
            videoEncoderField.set(instance, customVideoEncoder)
            Log.i(TAG, "Bt709VideoEncoder successfully installed on RtmpCamera2")
        } catch (e: Exception) {
            Log.w(TAG, "Could not install Bt709VideoEncoder, using default VideoEncoder: ${e.message}")
        }

        instance.setCameraCallbacks(object : CameraCallbacks {
            override fun onCameraChanged(facing: CameraHelper.Facing) {
                Log.d(TAG, "onCameraChanged: $facing")
                enforceFixedAeFpsRange(currentFps)
            }

            override fun onCameraError(error: String) {
                Log.e(TAG, "onCameraError: $error")
            }

            override fun onCameraOpened() {
                Log.d(TAG, "onCameraOpened -> enforcing AE FPS Range: $currentFps")
                enforceFixedAeFpsRange(currentFps)
            }

            override fun onCameraDisconnected() {
                Log.d(TAG, "onCameraDisconnected")
            }
        })

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
        if (isPortrait != null) {
            explicitPortraitOverride = isPortrait
        }
        val rawWidth = if (width > 0) width else 1920
        val rawHeight = if (height > 0) height else 1080
        val targetPortrait = isPortrait ?: explicitPortraitOverride ?: (rawHeight > rawWidth)
        val rotation = resolveDeviceRotation(rawWidth, rawHeight, targetPortrait)
        val portrait = (rotation == 90 || rotation == 270)

        // Landscape: 1920x1080 (16:9, rotation 0° or 180°)
        // Portrait: 1080x1920 (9:16, rotation 90° or 270°)
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
            sharedPreviewSurfaceTexture?.setDefaultBufferSize(safeWidth, safeHeight)
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
            mapOf(
                "details" to "Inicjalizacja MediaCodec + OpenGL ($currentWidth×$currentHeight @ ${currentFps}fps)...",
                "width" to currentWidth,
                "height" to currentHeight,
                "isPortrait" to (currentHeight > currentWidth)
            )
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
        detachSharedPreviewIfAttached(camera)
        if (camera.isStreaming) {
            try {
                camera.stopStream()
            } catch (_: Exception) {}
        }
        if (camera.isOnPreview) {
            try {
                camera.stopPreview()
            } catch (_: Exception) {}
        }
        try {
            camera.resetVideoEncoder()
        } catch (_: Exception) {}

        camera.forceCodecType(CodecUtil.CodecType.HARDWARE, CodecUtil.CodecType.HARDWARE)
        camera.setVideoCodec(VideoCodec.H264)
        camera.setAudioCodec(AudioCodec.AAC)
        (camera.glInterface as? GlStreamInterface)?.setAspectRatioMode(AspectRatioMode.Adjust)

        val isPortraitMode = currentHeight > currentWidth
        val rotation = resolveDeviceRotation(currentWidth, currentHeight, isPortraitMode)

        // RootEncoder VideoEncoder expects sensor base dimensions (1920x1080) and applies
        // rotation (0/180 for Landscape 1920x1080, 90/270 for Portrait 1080x1920) to both
        // MediaCodec and RTMP @setDataFrame (onMetaData: width=1080.0, height=1920.0 in Portrait).
        val baseWidth = maxOf(currentWidth, currentHeight)
        val baseHeight = minOf(currentWidth, currentHeight)

        // Przygotowanie enkodera wideo w trybie Zero-Latency (Baseline / no B-frames, CBR, krótki GOP 1-2s)
        val videoPrepared = prepareVideoEncoderWithZeroLatency(camera, baseWidth, baseHeight, rotation)

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

        // Lock OpenGL rendering to strict target FPS
        camera.forceFpsLimit(true)

        // Start physical camera preview session before RTMP streaming
        val facing = camera.cameraFacing
        if (!camera.isOnPreview) {
            try {
                camera.startPreview(facing, baseWidth, baseHeight, currentFps, rotation)
            } catch (e: Exception) {
                Log.w(TAG, "startPreview warning: ${e.message}")
            }
        }

        // Enforce constant AE FPS Range (e.g. [30, 30] or [60, 60]) preventing indoor light frame-drops
        enforceFixedAeFpsRange(currentFps)

        camera.startStream(endpoint)

        // Attach shared SurfaceTexture preview after glInterface is started so local PIP stays live
        attachSharedPreviewIfPossible(camera)

        // Attach OpenGL ES scoreboard filter and upload initial bitmap texture once
        attachAndRefreshScoreboardFilter(camera)
        Log.i(
            TAG,
            "RootEncoder hardware stream started: ${currentWidth}x${currentHeight}@${currentFps}fps (rot=$rotation), " +
                "bitrate=${currentVideoBitrate / 1000}kbps, anchor=$currentAnchorPosition"
        )
    }

    /**
     * Bezpieczna rekonfiguracja parametrów wideo i klatkażu FPS (30 <-> 60 fps):
     * 1. Zabezpiecza przed deadlockiem bufora OpenGL / SurfaceTexture (odpięcie powierzchni podglądu).
     * 2. Zatrzymuje aktywny strumień i podgląd kamery (reset sesji CaptureSession).
     * 3. Resetuje enkoder sprzętowy (resetVideoEncoder).
     * 4. Przygotowuje nowy enkoder z zadanym klatkażem i profilem bitrate.
     * 5. Wymusza stały limit FPS (forceFpsLimit) oraz stały zakres AE FPS range [fps, fps] w Camera2.
     * 6. Wznawia podgląd kamery (startPreview) i podłącza powierzchnię podglądu (attachSharedPreview).
     * 7. Jeśli transmisja była aktywna, wznawia nadawanie RTMP (startStream).
     */
    @Synchronized
    fun reconfigureStream(
        width: Int? = null,
        height: Int? = null,
        fps: Int? = null,
        bitrate: Int? = null,
        isPortrait: Boolean? = null
    ): Boolean {
        isReconfiguring = true
        try {
            val targetWidth = width ?: currentWidth
            val targetHeight = height ?: currentHeight
            val targetFps = (fps ?: currentFps).coerceIn(15, 60)
            val targetBitrate = if (bitrate != null) normalizeBitrateBps(bitrate) else currentVideoBitrate
            val effectivePortrait = isPortrait ?: (targetHeight > targetWidth)

            Log.i(TAG, "reconfigureStream requested: ${targetWidth}x${targetHeight}@${targetFps}fps, bitrate=$targetBitrate bps")

            val camera = ensureCameraInstance()
            val wasStreaming = camera.isStreaming
            val endpoint = lastEndpointUrl

            // 1. Odpięcie bufora podglądu, by uniknąć BufferQueue abandoned / deadlocka
            detachSharedPreviewIfAttached(camera)

            // 2. Bezpieczne zatrzymanie strumienia
            if (camera.isStreaming) {
                try {
                    camera.stopStream()
                } catch (e: Exception) {
                    Log.w(TAG, "stopStream during reconfigure warning: ${e.message}")
                }
            }

            // 3. Bezpieczne zatrzymanie podglądu kamery (zamknięcie CaptureSession)
            if (camera.isOnPreview) {
                try {
                    camera.stopPreview()
                } catch (e: Exception) {
                    Log.w(TAG, "stopPreview during reconfigure warning: ${e.message}")
                }
            }

            // 4. Zwolnienie i reset enkodera wideo
            try {
                camera.resetVideoEncoder()
            } catch (e: Exception) {
                Log.w(TAG, "resetVideoEncoder warning: ${e.message}")
            }

            // 5. Aktualizacja konfiguracji
            initialize(
                width = targetWidth,
                height = targetHeight,
                fps = targetFps,
                videoBitrate = targetBitrate,
                audioBitrate = currentAudioBitrate,
                gopSeconds = currentGopSeconds,
                audioSampleRate = currentAudioSampleRate,
                isPortrait = effectivePortrait
            )

            val isPortraitMode = (currentHeight > currentWidth)
            val rotation = resolveDeviceRotation(currentWidth, currentHeight, isPortraitMode)
            val baseWidth = maxOf(currentWidth, currentHeight)
            val baseHeight = minOf(currentWidth, currentHeight)

            // 6. Ponowne przygotowanie enkodera wideo w trybie Zero-Latency (Baseline / no B-frames, CBR, krótki GOP 1-2s)
            val videoPrepared = prepareVideoEncoderWithZeroLatency(camera, baseWidth, baseHeight, rotation)

            if (!videoPrepared) {
                Log.e(TAG, "reconfigureStream: prepareVideo failed for ${currentWidth}x${currentHeight}@${currentFps}fps")
                return false
            }

            // 7. ZAWSZE przygotuj enkoder audio AAC przed ewentualnym startStream
            // Zapobiega: IllegalStateException: AudioEncoder not prepared yet. You must call prepare method before start it
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
                Log.w(TAG, "reconfigureStream: prepareAudio returned false")
            }

            // Wymuszenie stałego limitu FPS w GL pipeline
            camera.forceFpsLimit(true)

            // 8. Ponowne otwarcie sesji kamery (startPreview)
            try {
                val facing = camera.cameraFacing
                camera.startPreview(facing, baseWidth, baseHeight, currentFps, rotation)
            } catch (e: Exception) {
                Log.e(TAG, "reconfigureStream: startPreview failed: ${e.message}", e)
            }

            // 9. Wymuszenie stałego zakresu AE FPS w Camera2 (np. [30, 30] lub [60, 60])
            enforceFixedAeFpsRange(currentFps)

            // 10. Ponowne podpięcie powierzchni podglądu (SurfaceTexture)
            attachSharedPreviewIfPossible(camera)

            // 11. Ponowne odświeżenie filtru scoreboardu
            attachAndRefreshScoreboardFilter(camera)

            // 12. Jeśli transmisja była aktywna, wznów nadawanie RTMP
            if (wasStreaming && !endpoint.isNullOrEmpty()) {
                try {
                    camera.startStream(endpoint)
                    isStreamingActive = true
                } catch (e: Exception) {
                    Log.e(TAG, "reconfigureStream: restart stream failed: ${e.message}", e)
                }
            }

            Log.i(TAG, "reconfigureStream completed successfully: ${currentWidth}x${currentHeight}@${currentFps}fps")
            onStatusEvent?.invoke(
                "BITRATE_UPDATE",
                mapOf(
                    "fps" to currentFps,
                    "bitrate" to currentVideoBitrate,
                    "width" to currentWidth,
                    "height" to currentHeight
                )
            )
            return true
        } finally {
            isReconfiguring = false
        }
    }

    fun reconfigureFps(newFps: Int): Boolean {
        return reconfigureStream(fps = newFps)
    }

    /**
     * Przygotowuje enkoder wideo w trybie ultra-niskiego opóźnienia (Zero-Latency / Realtime H.264):
     * 1. Krótki interwał klatek kluczowych GOP: iFrameInterval = 1 lub 2 sekundy (szybka odbudowa strumienia).
     * 2. Profil: preferowany AVCProfileBaseline (całkowity brak klatek B-frames w specyfikacji H.264,
     *    co eliminuje buforowanie reorder buffer 'pipelineFull' na układach Qualcomm c2.qti.avc.encoder),
     *    z fallbackiem do AVCProfileMain (z programowo wyłączonymi B-frames) oraz Baseline Level 3.1.
     * 3. Poziom: AVCLevel4 (1080p@30fps) lub AVCLevel42 (1080p@60fps).
     */
    private fun prepareVideoEncoderWithZeroLatency(
        camera: RtmpCamera2,
        baseWidth: Int,
        baseHeight: Int,
        rotation: Int
    ): Boolean {
        val iFrameInterval = currentGopSeconds.toInt().coerceIn(1, 2)
        val targetLevel = if (currentFps >= 60) {
            MediaCodecInfo.CodecProfileLevel.AVCLevel42
        } else {
            MediaCodecInfo.CodecProfileLevel.AVCLevel4
        }

        return camera.prepareVideo(
            baseWidth,
            baseHeight,
            currentFps,
            currentVideoBitrate,
            iFrameInterval,
            rotation,
            MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline,
            targetLevel
        ) || camera.prepareVideo(
            baseWidth,
            baseHeight,
            currentFps,
            currentVideoBitrate,
            iFrameInterval,
            rotation,
            MediaCodecInfo.CodecProfileLevel.AVCProfileMain,
            targetLevel
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
    }

    /**
     * Wymusza stały zakres FPS (np. [30, 30] lub [60, 60]) w Camera2 (CONTROL_AE_TARGET_FPS_RANGE).
     * Zapobiega klatkowaniu i gubieniu klatek w słabszym oświetleniu hali sportowej,
     * w którym auto-ekspozycja domyślnie obniża klatkaż do np. 10-15 fps.
     * Wykonywane asynchronicznie z pętlą retry oczekującą na gotowość asynchronicznej sesji CameraCaptureSession.
     */
    private fun enforceFixedAeFpsRange(targetFps: Int) {
        aeFpsJob?.cancel()
        aeFpsJob = scope.launch {
            try {
                val camera = rtmpCamera2 ?: return@launch
                val supportedFpsList = camera.supportedFps ?: emptyList()
                if (supportedFpsList.isEmpty()) {
                    Log.w(TAG, "enforceFixedAeFpsRange: supportedFps list is empty")
                    return@launch
                }

                val is1000Scale = supportedFpsList.any { it.upper > 1000 }
                val scaledTarget = if (is1000Scale) targetFps * 1000 else targetFps

                var bestRange: Range<Int>? = null

                // 1. Priorytet: idealnie stały zakres [targetFps, targetFps]
                for (r in supportedFpsList) {
                    if (r.upper == scaledTarget && r.lower == scaledTarget) {
                        bestRange = r
                        break
                    }
                }

                // 2. Jeśli brak idealnego, wybierz zakres o górnym limicie targetFps z najwyższym dolnym limitem
                if (bestRange == null) {
                    for (r in supportedFpsList) {
                        if (r.upper == scaledTarget) {
                            if (bestRange == null || r.lower > bestRange.lower) {
                                bestRange = r
                            }
                        }
                    }
                }

                // 3. Fallback: najwęższy zakres zawierający targetFps
                if (bestRange == null) {
                    var minDiff = Int.MAX_VALUE
                    for (r in supportedFpsList) {
                        if (r.lower <= scaledTarget && r.upper >= scaledTarget) {
                            val diff = (scaledTarget - r.lower) + (r.upper - scaledTarget)
                            if (diff < minDiff) {
                                minDiff = diff
                                bestRange = r
                            }
                        }
                    }
                }

                if (bestRange == null) {
                    Log.w(TAG, "enforceFixedAeFpsRange: no suitable AE range found for targetFps=$targetFps")
                    return@launch
                }

                Log.i(TAG, "Target AE FPS Range: $bestRange for targetFps=$targetFps (is1000Scale=$is1000Scale)")

                val baseClass = Camera2Base::class.java
                val cameraManagerField = baseClass.getDeclaredField("cameraManager").apply { isAccessible = true }
                val cameraManager = cameraManagerField.get(camera) ?: return@launch

                val mgrClass = cameraManager.javaClass
                val builderField = mgrClass.getDeclaredField("builderInputSurface").apply { isAccessible = true }
                val sessionField = mgrClass.getDeclaredField("cameraCaptureSession").apply { isAccessible = true }
                val handlerField = mgrClass.getDeclaredField("cameraHandler").apply { isAccessible = true }
                val cbField = mgrClass.getDeclaredField("cb").apply { isAccessible = true }

                // Pętla retry: oczekujemy aż asynchroniczna sesja CameraCaptureSession zostanie skompletowana (do 2.5s)
                var attempts = 0
                while (attempts < 50) {
                    val builder = builderField.get(cameraManager) as? CaptureRequest.Builder
                    val session = sessionField.get(cameraManager) as? CameraCaptureSession
                    val handler = handlerField.get(cameraManager) as? Handler
                    val cb = cbField.get(cameraManager) as? CameraCaptureSession.CaptureCallback

                    if (builder != null && session != null) {
                        try {
                            builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, bestRange)
                            session.setRepeatingRequest(builder.build(), cb, handler)
                            Log.i(TAG, "Successfully locked Camera2 to fixed AE FPS Range: $bestRange on attempt $attempts")
                            return@launch
                        } catch (e: Exception) {
                            Log.w(TAG, "setRepeatingRequest failed on attempt $attempts: ${e.message}")
                        }
                    }
                    delay(50)
                    attempts++
                }
                Log.w(TAG, "enforceFixedAeFpsRange timed out waiting for active CameraCaptureSession")
            } catch (e: Exception) {
                Log.w(TAG, "enforceFixedAeFpsRange ignored: ${e.message}")
            }
        }
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

    private var lastScoreboardUploadNs = 0L
    private val MIN_CLOCK_UPLOAD_INTERVAL_NS = 500_000_000L // Max 2x/s dla zegara, zapobiega przeciążeniu OpenGL
    private var lastOverlayBitmapHash = 0
    private var lastOverlayUploadNs = 0L

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
        val scoreChanged = data.scoreA != lastScoreboardData.scoreA ||
                           data.scoreB != lastScoreboardData.scoreB ||
                           data.setsA != lastScoreboardData.setsA ||
                           data.setsB != lastScoreboardData.setsB ||
                           data.servingTeam != lastScoreboardData.servingTeam ||
                           data.eventTag != lastScoreboardData.eventTag ||
                           data.toastMessage != lastScoreboardData.toastMessage ||
                           data.teamA != lastScoreboardData.teamA ||
                           data.teamB != lastScoreboardData.teamB ||
                           data.colorA != lastScoreboardData.colorA ||
                           data.colorB != lastScoreboardData.colorB

        val clockChanged = resolvedClock != lastScoreboardData.matchClock

        val normalizedData = data.copy(
            anchorPosition = currentAnchorPosition,
            style = currentScoreboardStyle,
            matchClock = resolvedClock
        )
        lastScoreboardData = normalizedData
        renderer.updateData(normalizedData)

        val filter = scoreboardFilter ?: return

        // Jeśli zmieniły się punkty, sety, serwujący lub styl - renderujemy i wrzucamy do GL natychmiast.
        // Jeśli zmienił się tylko zegar meczowy - ograniczamy taktowanie do max 2x/s, eliminując "pipelineFull: too many frames".
        val now = System.nanoTime()
        val shouldUpload = scoreChanged || styleChanged || (clockChanged && (now - lastScoreboardUploadNs >= MIN_CLOCK_UPLOAD_INTERVAL_NS))

        if (shouldUpload) {
            val dirtySnapshot = if (styleChanged) renderer.forceRenderAndSnapshot() else renderer.renderAndSnapshotIfDirty()
            if (dirtySnapshot != null) {
                lastScoreboardUploadNs = now
                filter.setImage(dirtySnapshot)
                applyAnchorPositionAndScale(filter, currentAnchorPosition)
            }
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
        explicitPortraitOverride = isPortrait
        val newW = if (isPortrait) minOf(currentWidth, currentHeight) else maxOf(currentWidth, currentHeight)
        val newH = if (isPortrait) maxOf(currentWidth, currentHeight) else minOf(currentWidth, currentHeight)
        val rotation = resolveDeviceRotation(newW, newH, isPortrait)
        val cameraOrientation = if (rotation == 0) 270 else rotation - 90
        (rtmpCamera2?.glInterface as? GlStreamInterface)?.let { glStream ->
            glStream.setCameraOrientation(cameraOrientation)
            glStream.setAspectRatioMode(AspectRatioMode.Adjust)
            glStream.setIsPortrait(isPortrait)
            glStream.setPreviewResolution(newW, newH)
        }
        if (newW != currentWidth || newH != currentHeight) {
            currentWidth = newW
            currentHeight = newH
            renderer = VolleyballScoreboardBitmapRenderer(currentWidth, currentHeight)
            renderer.updateData(lastScoreboardData)
            sharedPreviewSurfaceTexture?.setDefaultBufferSize(currentWidth, currentHeight)
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
        val now = System.nanoTime()
        val bytesHash = bytes.contentHashCode()
        // Throttling: unikamy wielokrotnego wysyłania identycznej bitmapy w odstępie mniejszym niż 250ms
        if (bytesHash == lastOverlayBitmapHash && (now - lastOverlayUploadNs < 250_000_000L)) {
            return
        }
        lastOverlayBitmapHash = bytesHash
        lastOverlayUploadNs = now

        try {
            val opts = BitmapFactory.Options().apply {
                inPreferredConfig = android.graphics.Bitmap.Config.ARGB_8888
            }
            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) ?: return
            filter.setImage(bmp)
            val w = if (width > 0) maxOf(width, renderer.overlayWidth) else maxOf(bmp.width, renderer.overlayWidth)
            val h = if (height > 0) maxOf(height, renderer.overlayHeight) else maxOf(bmp.height, renderer.overlayHeight)
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
                    detachSharedPreviewIfAttached(rtmpCamera2)
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
        synchronized(this) {
            sharedPreviewSurface?.release()
            sharedPreviewSurface = null
            sharedPreviewSurfaceTexture = null
        }
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
                "fps" to currentFps,
                "width" to currentWidth,
                "height" to currentHeight,
                "isPortrait" to (currentHeight > currentWidth)
            )
        )
    }

    override fun onConnectionFailed(reason: String) {
        Log.e(TAG, "RTMP connection failed: $reason")
        isStreamingActive = false
        if (isReconfiguring) {
            Log.i(TAG, "onConnectionFailed suppressed during reconfigureStream: $reason")
            return
        }

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
        if (isReconfiguring) {
            Log.i(TAG, "onDisconnect suppressed during reconfigureStream")
            return
        }
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
