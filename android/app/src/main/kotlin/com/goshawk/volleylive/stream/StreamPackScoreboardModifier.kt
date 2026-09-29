package com.goshawk.volleylive.stream

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.opengl.GLES20
import android.opengl.GLUtils
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * OpenGL ES 2.0 processor for StreamPack.
 * Binds the authentic Flutter [ScoreboardOverlay] widget bitmap to an OpenGL texture
 * and alpha-blends it directly onto the camera stream surface before hardware H.264
 * encoding via MediaCodec.
 */
class StreamPackScoreboardModifier(
    private val renderer: VolleyballScoreboardBitmapRenderer,
    private val frameWidth: Int = 1920,
    private val frameHeight: Int = 1080
) {
    private var program = 0
    private var textureId = -1

    @Volatile
    private var customBitmap: Bitmap? = null
    private val isCustomBitmapDirty = AtomicBoolean(false)

    private val vertexShaderCode = """
        attribute vec4 aPosition;
        attribute vec2 aTexCoord;
        varying vec2 vTexCoord;
        void main() {
            gl_Position = aPosition;
            vTexCoord = aTexCoord;
        }
    """.trimIndent()

    private val fragmentShaderCode = """
        precision mediump float;
        varying vec2 vTexCoord;
        uniform sampler2D uTexture;
        void main() {
            gl_FragColor = texture2D(uTexture, vTexCoord);
        }
    """.trimIndent()

    // NDC coordinates for HUD banner: centered horizontally, near the top
    private val quadVertices = floatArrayOf(
        -0.58f,  0.74f, 0.0f,  // Bottom-Left
         0.58f,  0.74f, 0.0f,  // Bottom-Right
        -0.58f,  0.94f, 0.0f,  // Top-Left
         0.58f,  0.94f, 0.0f   // Top-Right
    )

    private val texCoords = floatArrayOf(
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 0.0f
    )

    private val vertexBuffer: FloatBuffer = ByteBuffer.allocateDirect(quadVertices.size * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply { put(quadVertices); position(0) }

    private val texBuffer: FloatBuffer = ByteBuffer.allocateDirect(texCoords.size * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply { put(texCoords); position(0) }

    fun initGL() {
        program = createProgram(vertexShaderCode, fragmentShaderCode)
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        textureId = textures[0]

        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        renderer.renderIfDirty()
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, renderer.bitmap, 0)
        updateQuadGeometry(renderer.overlayWidth.toFloat() / renderer.overlayHeight.toFloat(), halfW = 0.58f, top = 0.94f)
    }

    /**
     * Resets any cached custom bitmap so that native Canvas rendering takes over immediately.
     */
    fun invalidateCustomBitmap() {
        customBitmap = null
        isCustomBitmapDirty.set(false)
    }

    /**
     * Receives the authentic Flutter ScoreboardOverlay widget bitmap bytes
     */
    fun updateOverlayBitmap(bytes: ByteArray, width: Int, height: Int) {
        try {
            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            if (bmp != null) {
                customBitmap = bmp
                isCustomBitmapDirty.set(true)
            }
        } catch (e: Exception) {
            android.util.Log.e("ScoreboardModifier", "Failed to decode overlay bitmap", e)
        }
    }

    private fun updateQuadGeometry(aspectRatio: Float, halfW: Float = 0.58f, top: Float = 0.94f) {
        val frameAspect = frameWidth.toFloat() / frameHeight.toFloat()
        val ndcHeight = (halfW * 2.0f) * (1.0f / frameAspect) / aspectRatio
        val bottom = top - ndcHeight

        quadVertices[0] = -halfW; quadVertices[1] = bottom
        quadVertices[3] =  halfW; quadVertices[4] = bottom
        quadVertices[6] = -halfW; quadVertices[7] = top
        quadVertices[9] =  halfW; quadVertices[10] = top

        vertexBuffer.position(0)
        vertexBuffer.put(quadVertices)
        vertexBuffer.position(0)
    }

    /**
     * Executes on every camera frame right before the frame is sent to MediaCodec.
     */
    fun onDrawFrame() {
        if (textureId == -1) return

        // 1. If custom Flutter ScoreboardOverlay arrived, upload to GPU and scale quad
        if (isCustomBitmapDirty.compareAndSet(true, false) && customBitmap != null) {
            val bmp = customBitmap!!
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp, 0)
            updateQuadGeometry(bmp.width.toFloat() / bmp.height.toFloat(), halfW = 0.55f, top = 0.94f)
        } else if (renderer.renderIfDirty()) {
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, renderer.bitmap, 0)
            updateQuadGeometry(renderer.overlayWidth.toFloat() / renderer.overlayHeight.toFloat(), halfW = 0.58f, top = 0.94f)
        }

        // 2. Hardware Alpha Blending
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)

        // 3. Render Quad
        GLES20.glUseProgram(program)
        val posHandle = GLES20.glGetAttribLocation(program, "aPosition")
        val texHandle = GLES20.glGetAttribLocation(program, "aTexCoord")
        val samplerHandle = GLES20.glGetUniformLocation(program, "uTexture")

        GLES20.glEnableVertexAttribArray(posHandle)
        GLES20.glVertexAttribPointer(posHandle, 3, GLES20.GL_FLOAT, false, 0, vertexBuffer)

        GLES20.glEnableVertexAttribArray(texHandle)
        GLES20.glVertexAttribPointer(texHandle, 2, GLES20.GL_FLOAT, false, 0, texBuffer)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glUniform1i(samplerHandle, 0)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(posHandle)
        GLES20.glDisableVertexAttribArray(texHandle)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    fun release() {
        if (textureId != -1) {
            GLES20.glDeleteTextures(1, intArrayOf(textureId), 0)
            textureId = -1
        }
        if (program != 0) {
            GLES20.glDeleteProgram(program)
            program = 0
        }
        customBitmap?.recycle()
        customBitmap = null
    }

    private fun createProgram(vertexCode: String, fragmentCode: String): Int {
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexCode)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentCode)
        return GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, vertexShader)
            GLES20.glAttachShader(it, fragmentShader)
            GLES20.glLinkProgram(it)
        }
    }

    private fun loadShader(type: Int, code: String): Int {
        return GLES20.glCreateShader(type).also { shader ->
            GLES20.glShaderSource(shader, code)
            GLES20.glCompileShader(shader)
        }
    }
}
