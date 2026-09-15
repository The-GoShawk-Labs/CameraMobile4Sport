package com.goshawk.volleylive.volleylive

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.goshawk.volleylive/yuv_converter"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
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
                        // Copy Y
                        var pos = 0
                        for (row in 0 until height) {
                            val srcPos = row * yRowStride
                            val length = minOf(width, y.size - srcPos)
                            if (length > 0) {
                                System.arraycopy(y, srcPos, nv21, pos, length)
                            }
                            pos += width
                        }
                        // Copy UV (NV21 format: V then U interleaved)
                        val uvHeight = height / 2
                        val uvWidth = width / 2
                        for (row in 0 until uvHeight) {
                            for (col in 0 until uvWidth) {
                                val vIdx = row * uvRowStride + col * uvPixelStride
                                val uIdx = row * uvRowStride + col * uvPixelStride
                                if (vIdx < v.size) {
                                    nv21[pos++] = v[vIdx]
                                } else {
                                    nv21[pos++] = 0
                                }
                                if (uIdx < u.size) {
                                    nv21[pos++] = u[uIdx]
                                } else {
                                    nv21[pos++] = 0
                                }
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
    }
}
