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

class MainActivity : FlutterActivity() {
    private val YUV_CHANNEL = "com.goshawk.volleylive/yuv_converter"
    private val LIVE_STREAM_CHANNEL = "com.goshawk.volleylive/live_stream_bridge"
    private val STREAM_EVENT_CHANNEL = "com.goshawk.volleylive/stream_events"

    private var streamService: StreamPackLiveStreamService? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Existing YUV converter channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, YUV_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "convertYuvToJpeg") {
                    try {
                        val y = call.argument<ByteArray>("y") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing y", null)
                        val u = call.argument<ByteArray>("u") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing u", null)
                        val v = call.argument<ByteArray>("v") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing v", null)
                        val width = call.argument<Int>("width") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing width", null)
                        val height = call.argument<Int>("height") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing height", null)
                        val yRowStride = call.argument<Int>("yRowStride") ?: width
                        val uvRowStride = call.argument<Int>("uvRowStride") ?: width
                        val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 2
                        val quality = call.argument<Int>("quality") ?: 60

                        val nv21 = ByteArray(width * height * 3 / 2)
                        var pos = 0
                        for (row in 0 until height) {
                            val srcPos = row * yRowStride
                            val length = minOf(width, y.size - srcPos)
                            if (length > 0) {
                                System.arraycopy(y, srcPos, nv21, pos, length)
                            }
                            pos += width
                        }
                        val uvHeight = height / 2
                        val uvWidth = width / 2
                        for (row in 0 until uvHeight) {
                            for (col in 0 until uvWidth) {
                                val vIdx = row * uvRowStride + col * uvPixelStride
                                val uIdx = row * uvRowStride + col * uvPixelStride
                                nv21[pos++] = if (vIdx < v.size) v[vIdx] else 0
                                nv21[pos++] = if (uIdx < u.size) u[uIdx] else 0
                            }
                        }

                        val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
                        val out = ByteArrayOutputStream()
                        yuvImage.compressToJpeg(Rect(0, 0, width, height), quality, out)
                        result.success(out.toByteArray())
                    } catch (e: Exception) {
                        result.error("CONVERSION_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        // 2. StreamPack Live Stream Engine & Hardware Frame Burn-in
        streamService = StreamPackLiveStreamService(context = this)

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
                    "initialize" -> {
                        val width = call.argument<Int>("width") ?: 1920
                        val height = call.argument<Int>("height") ?: 1080
                        val fps = call.argument<Int>("fps") ?: 30
                        val videoBitrate = call.argument<Int>("videoBitrate") ?: 4500000
                        val audioBitrate = call.argument<Int>("audioBitrate") ?: 128000
                        streamService?.initialize(width, height, fps, videoBitrate, audioBitrate)
                        result.success(true)
                    }
                    "startStream" -> {
                        val rtmpUrl = call.argument<String>("rtmpUrl") ?: ""
                        val streamKey = call.argument<String>("streamKey") ?: ""
                        val scoreboardMap = call.argument<Map<String, Any>>("scoreboard")
                        scoreboardMap?.let { updateScoreboardFromMap(it) }

                        eventSink?.success(mapOf("status" to "CONNECTING"))
                        streamService?.startStream(
                            rtmpUrl = rtmpUrl,
                            streamKey = streamKey,
                            onSuccess = {
                                eventSink?.success(mapOf("status" to "STREAMING"))
                                result.success(true)
                            },
                            onError = { err ->
                                eventSink?.success(mapOf("status" to "ERROR", "error" to err))
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
                        if (bytes != null && bytes.isNotEmpty()) {
                            streamService?.updateScoreboardOverlayBitmap(bytes, width, height)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGS", "Missing bitmap bytes", null)
                        }
                    }
                    "stopStream" -> {
                        streamService?.stopStream()
                        eventSink?.success(mapOf("status" to "STOPPED"))
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
            toastMessage = toast
        )
        streamService?.updateScoreboard(data)
    }

    override fun onDestroy() {
        super.onDestroy()
        streamService?.release()
    }
}
