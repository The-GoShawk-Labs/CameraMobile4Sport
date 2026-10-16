package com.goshawk.volleylive.volleylive

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import com.goshawk.volleylive.stream.StreamPackLiveStreamService
import com.goshawk.volleylive.stream.VolleyballScoreboardData
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val YUV_CHANNEL = "com.goshawk.volleylive/yuv_converter"
    private val LIVE_STREAM_CHANNEL = "com.goshawk.volleylive/live_stream_bridge"
    private val STREAM_EVENT_CHANNEL = "com.goshawk.volleylive/stream_events"

    private var streamService: StreamPackLiveStreamService? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Existing YUV converter channel (executed on Dispatchers.Default to prevent UI thread lockup)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, YUV_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "convertNv21ToJpeg" -> {
                        val nv21 = call.argument<ByteArray>("nv21") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing nv21", null)
                        val width = call.argument<Int>("width") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing width", null)
                        val height = call.argument<Int>("height") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing height", null)
                        val quality = call.argument<Int>("quality") ?: 60

                        CoroutineScope(Dispatchers.Default).launch {
                            try {
                                val expectedSize = width * height * 3 / 2
                                val finalNv21 = if (nv21.size >= expectedSize) {
                                    nv21
                                } else {
                                    ByteArray(expectedSize).also { System.arraycopy(nv21, 0, it, 0, nv21.size) }
                                }
                                val yuvImage = YuvImage(finalNv21, ImageFormat.NV21, width, height, null)
                                val out = ByteArrayOutputStream()
                                yuvImage.compressToJpeg(Rect(0, 0, width, height), quality, out)
                                val jpegBytes = out.toByteArray()
                                runOnUiThread {
                                    result.success(jpegBytes)
                                }
                            } catch (e: Exception) {
                                android.util.Log.e("MainActivity", "convertNv21ToJpeg failed: ${e.message}")
                                runOnUiThread {
                                    result.error("CONVERSION_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                    "convertNv21TwoPlanesToJpeg" -> {
                        val y = call.argument<ByteArray>("y") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing y", null)
                        val uv = call.argument<ByteArray>("uv") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing uv", null)
                        val width = call.argument<Int>("width") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing width", null)
                        val height = call.argument<Int>("height") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing height", null)
                        val yRowStride = call.argument<Int>("yRowStride") ?: width
                        val uvRowStride = call.argument<Int>("uvRowStride") ?: width
                        val quality = call.argument<Int>("quality") ?: 60

                        CoroutineScope(Dispatchers.Default).launch {
                            try {
                                val expectedSize = width * height * 3 / 2
                                val nv21 = ByteArray(expectedSize)
                                var pos = 0
                                for (row in 0 until height) {
                                    val srcPos = row * yRowStride
                                    if (srcPos < y.size) {
                                        val length = minOf(width, y.size - srcPos)
                                        if (length > 0) {
                                            System.arraycopy(y, srcPos, nv21, pos, length)
                                        }
                                    }
                                    pos += width
                                }
                                val uvHeight = height / 2
                                for (row in 0 until uvHeight) {
                                    val srcPos = row * uvRowStride
                                    if (srcPos < uv.size) {
                                        val length = minOf(width, uv.size - srcPos)
                                        if (length > 0) {
                                            System.arraycopy(uv, srcPos, nv21, pos, length)
                                        }
                                    }
                                    pos += width
                                }
                                val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
                                val out = ByteArrayOutputStream()
                                yuvImage.compressToJpeg(Rect(0, 0, width, height), quality, out)
                                val jpegBytes = out.toByteArray()
                                runOnUiThread {
                                    result.success(jpegBytes)
                                }
                            } catch (e: Exception) {
                                android.util.Log.e("MainActivity", "convertNv21TwoPlanesToJpeg failed: ${e.message}")
                                runOnUiThread {
                                    result.error("CONVERSION_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                    "convertYuvToJpeg" -> {
                        val directNv21 = call.argument<ByteArray>("nv21")
                        val width = call.argument<Int>("width") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing width", null)
                        val height = call.argument<Int>("height") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing height", null)
                        val quality = call.argument<Int>("quality") ?: 60

                        if (directNv21 != null) {
                            CoroutineScope(Dispatchers.Default).launch {
                                try {
                                    val expectedSize = width * height * 3 / 2
                                    val finalNv21 = if (directNv21.size >= expectedSize) {
                                        directNv21
                                    } else {
                                        ByteArray(expectedSize).also { System.arraycopy(directNv21, 0, it, 0, directNv21.size) }
                                    }
                                    val yuvImage = YuvImage(finalNv21, ImageFormat.NV21, width, height, null)
                                    val out = ByteArrayOutputStream()
                                    yuvImage.compressToJpeg(Rect(0, 0, width, height), quality, out)
                                    val jpegBytes = out.toByteArray()
                                    runOnUiThread {
                                        result.success(jpegBytes)
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.e("MainActivity", "convertYuvToJpeg (direct NV21) failed: ${e.message}")
                                    runOnUiThread {
                                        result.error("CONVERSION_FAILED", e.message, null)
                                    }
                                }
                            }
                            return@setMethodCallHandler
                        }

                        val y = call.argument<ByteArray>("y") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing y", null)
                        val u = call.argument<ByteArray>("u") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing u", null)
                        val v = call.argument<ByteArray>("v") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing v", null)
                        val yRowStride = call.argument<Int>("yRowStride") ?: width
                        val uvRowStride = call.argument<Int>("uvRowStride") ?: width
                        val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 2

                        CoroutineScope(Dispatchers.Default).launch {
                            try {
                                val expectedSize = width * height * 3 / 2
                                val nv21 = ByteArray(expectedSize)
                                var pos = 0
                                for (row in 0 until height) {
                                    val srcPos = row * yRowStride
                                    if (srcPos < y.size) {
                                        val length = minOf(width, y.size - srcPos)
                                        if (length > 0) {
                                            System.arraycopy(y, srcPos, nv21, pos, length)
                                        }
                                    }
                                    pos += width
                                }
                                val uvHeight = height / 2
                                val uvWidth = width / 2
                                for (row in 0 until uvHeight) {
                                    for (col in 0 until uvWidth) {
                                        val vIdx = row * uvRowStride + col * uvPixelStride
                                        val uIdx = row * uvRowStride + col * uvPixelStride
                                        nv21[pos++] = if (vIdx in 0 until v.size) v[vIdx] else 0
                                        nv21[pos++] = if (uIdx in 0 until u.size) u[uIdx] else 0
                                    }
                                }

                                val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
                                val out = ByteArrayOutputStream()
                                yuvImage.compressToJpeg(Rect(0, 0, width, height), quality, out)
                                val jpegBytes = out.toByteArray()
                                runOnUiThread {
                                    result.success(jpegBytes)
                                }
                            } catch (e: Exception) {
                                android.util.Log.e("MainActivity", "convertYuvToJpeg failed: ${e.message}")
                                runOnUiThread {
                                    result.error("CONVERSION_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // 2. StreamPack Live Stream Engine & Hardware Frame Burn-in
        streamService = StreamPackLiveStreamService(context = this).apply {
            onStatusEvent = { status, details ->
                runOnUiThread {
                    val payload = mutableMapOf<String, Any>("status" to status)
                    details?.let { payload.putAll(it) }
                    eventSink?.success(payload)
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LIVE_STREAM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initializeStream" -> {
                        val width = call.argument<Int>("width") ?: 1920
                        val height = call.argument<Int>("height") ?: 1080
                        val fps = call.argument<Int>("fps") ?: 30
                        val videoBitrate = call.argument<Int>("videoBitrate") ?: 4500000
                        val audioBitrate = call.argument<Int>("audioBitrate") ?: 128000
                        val gopSeconds = (call.argument<Double>("gopSeconds") ?: 2.0).toFloat()
                        val audioSampleRate = call.argument<Int>("audioSampleRate") ?: 48000
                        val audioChannels = call.argument<Int>("audioChannels") ?: 2

                        streamService?.initialize(
                            width = width,
                            height = height,
                            fps = fps,
                            videoBitrate = videoBitrate,
                            audioBitrate = audioBitrate,
                            gopSeconds = gopSeconds,
                            audioSampleRate = audioSampleRate,
                            audioChannels = audioChannels
                        )
                        result.success(true)
                    }
                    "initialize" -> {
                        val width = call.argument<Int>("width") ?: 1920
                        val height = call.argument<Int>("height") ?: 1080
                        val fps = call.argument<Int>("fps") ?: 30
                        val videoBitrate = call.argument<Int>("videoBitrate") ?: 4500000
                        val audioBitrate = call.argument<Int>("audioBitrate") ?: 128000
                        val gopSeconds = (call.argument<Double>("gopSeconds") ?: 2.0).toFloat()

                        streamService?.initialize(
                            width = width,
                            height = height,
                            fps = fps,
                            videoBitrate = videoBitrate,
                            audioBitrate = audioBitrate,
                            gopSeconds = gopSeconds
                        )
                        result.success(true)
                    }
                    "validateEncoderCapabilities" -> {
                        CoroutineScope(Dispatchers.IO).launch {
                            val caps = streamService?.validateEncoderCapabilities() ?: emptyMap<String, Any>()
                            runOnUiThread {
                                result.success(caps)
                            }
                        }
                    }
                    "startStream" -> {
                        val rtmpUrl = call.argument<String>("rtmpUrl") ?: ""
                        val streamKey = call.argument<String>("streamKey") ?: ""
                        val scoreboardMap = call.argument<Map<String, Any>>("scoreboard")
                        scoreboardMap?.let { updateScoreboardFromMap(it) }

                        // Check if config overrides width/height/fps/bitrate
                        val width = call.argument<Int>("width")
                        val height = call.argument<Int>("height")
                        val fps = call.argument<Int>("fps")
                        val videoBitrate = call.argument<Int>("videoBitrate")
                        val audioBitrate = call.argument<Int>("audioBitrate")
                        val gopSeconds = (call.argument<Double>("gopSeconds") ?: 2.0).toFloat()

                        if (width != null && height != null && fps != null && videoBitrate != null) {
                            streamService?.initialize(
                                width = width,
                                height = height,
                                fps = fps,
                                videoBitrate = videoBitrate,
                                audioBitrate = audioBitrate ?: 128000,
                                gopSeconds = gopSeconds
                            )
                        }

                        eventSink?.success(mapOf("status" to "CONNECTING", "details" to "Nawiązywanie połączenia..."))
                        streamService?.startStream(
                            rtmpUrl = rtmpUrl,
                            streamKey = streamKey,
                            onSuccess = {
                                result.success(true)
                            },
                            onError = { err ->
                                result.error("STREAM_FAILED", err, null)
                            }
                        )
                    }
                    "updateScoreboard" -> {
                        @Suppress("UNCHECKED_CAST")
                        val map = call.arguments as? Map<String, Any>
                        if (map != null) {
                            updateScoreboardFromMap(map)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGS", "Missing scoreboard map", null)
                        }
                    }
                    "updateScoreboardOverlayBitmap" -> {
                        val bytes = call.argument<ByteArray>("bitmapBytes")
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        val anchor = call.argument<String>("anchorPosition") ?: "topLeft"
                        if (bytes != null && bytes.isNotEmpty()) {
                            streamService?.updateScoreboardOverlayBitmap(bytes, width, height, anchor)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGS", "Missing bitmap bytes", null)
                        }
                    }
                    "stopStream" -> {
                        streamService?.stopStream()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun updateScoreboardFromMap(map: Map<String, Any>) {
        val toast = (map["toastMessage"] as? String) ?: (map["eventTag"] as? String) ?: ""
        val data = VolleyballScoreboardData(
            teamA = (map["teamA"] as? String) ?: (map["teamAName"] as? String) ?: "TEAM A",
            teamB = (map["teamB"] as? String) ?: (map["teamBName"] as? String) ?: "TEAM B",
            scoreA = (map["scoreA"] as? Number)?.toInt() ?: 0,
            scoreB = (map["scoreB"] as? Number)?.toInt() ?: 0,
            currentSet = (map["currentSet"] as? Number)?.toInt() ?: 1,
            setsA = (map["setsA"] as? Number)?.toInt() ?: 0,
            setsB = (map["setsB"] as? Number)?.toInt() ?: 0,
            servingTeam = map["servingTeam"] as? String ?: "NONE",
            eventTag = map["eventTag"] as? String ?: "",
            toastMessage = toast,
            anchorPosition = (map["anchorPosition"] as? String) ?: "topLeft"
        )
        streamService?.updateScoreboard(data)
    }

    override fun onDestroy() {
        super.onDestroy()
        streamService?.release()
    }
}
