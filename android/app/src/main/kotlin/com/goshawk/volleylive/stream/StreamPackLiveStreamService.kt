package com.goshawk.volleylive.stream

import android.content.Context
import android.media.AudioFormat
import android.media.MediaFormat
import android.util.Size
import io.github.thibaultbee.streampack.data.AudioConfig
import io.github.thibaultbee.streampack.data.VideoConfig
import io.github.thibaultbee.streampack.ext.rtmp.streamers.CameraRtmpLiveStreamer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Service orchestrating ThibaultBee's StreamPack RTMP live streaming
 * with hardware-accelerated frame burn-in of the volleyball scoreboard.
 */
class StreamPackLiveStreamService(private val context: Context) {
    private var streamer: CameraRtmpLiveStreamer? = null
    private val scope = CoroutineScope(Dispatchers.Main)

    private val renderer = VolleyballScoreboardBitmapRenderer(1920, 1080)
    private val modifier = StreamPackScoreboardModifier(renderer, 1920, 1080)

    fun initialize(
        width: Int = 1920,
        height: Int = 1080,
        fps: Int = 30,
        videoBitrate: Int = 4500000,
        audioBitrate: Int = 128000
    ) {
        val audioConfig = AudioConfig(
            mimeType = MediaFormat.MIMETYPE_AUDIO_AAC,
            startBitrate = audioBitrate,
            sampleRate = 44100,
            channelConfig = AudioFormat.CHANNEL_IN_STEREO
        )
        val videoConfig = VideoConfig(
            mimeType = MediaFormat.MIMETYPE_VIDEO_AVC,
            startBitrate = videoBitrate,
            resolution = Size(width, height),
            fps = fps
        )

        streamer = CameraRtmpLiveStreamer(context = context).apply {
            configure(audioConfig, videoConfig)
        }
    }

    fun updateScoreboard(data: VolleyballScoreboardData) {
        modifier.invalidateCustomBitmap()
        renderer.updateData(data)
    }

    fun updateScoreboardOverlayBitmap(bytes: ByteArray, width: Int, height: Int) {
        modifier.updateOverlayBitmap(bytes, width, height)
    }

    fun startStream(
        rtmpUrl: String,
        streamKey: String,
        onSuccess: () -> Unit,
        onError: (String) -> Unit
    ) {
        val endpoint = if (rtmpUrl.endsWith("/")) "$rtmpUrl$streamKey" else "$rtmpUrl/$streamKey"
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    streamer?.startStream(endpoint)
                }
                onSuccess()
            } catch (e: Exception) {
                onError(e.message ?: "Failed to start live stream")
            }
        }
    }

    fun stopStream() {
        scope.launch {
            withContext(Dispatchers.IO) {
                try {
                    streamer?.stopStream()
                } catch (_: Exception) {}
            }
        }
    }

    fun release() {
        stopStream()
        modifier.release()
        streamer?.release()
        streamer = null
    }
}
