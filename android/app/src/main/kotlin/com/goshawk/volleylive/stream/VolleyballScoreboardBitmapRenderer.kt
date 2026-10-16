package com.goshawk.volleylive.stream

import android.graphics.*
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Zero-allocation, high-performance 2D Canvas renderer for Volleyball scoreboard.
 * Allocates all Bitmaps, Paints, and geometry ONCE during construction.
 * Renders to the backing Bitmap ONLY when state updates (`isDirty == true`),
 * preventing garbage collection thrashing at 60 FPS.
 * Proportional to stream resolution (SportCam style ~2.8:1 ratio).
 */
class VolleyballScoreboardBitmapRenderer(
    private val frameWidth: Int = 1920,
    private val frameHeight: Int = 1080
) {
    private val scale = frameWidth / 1920f

    // Proportional TV card (430x154 for Full HD, ratio ~2.8:1)
    val overlayWidth = ((430f * scale).toInt() and 1.inv()).coerceAtLeast(160)
    val overlayHeight = ((154f * scale).toInt() and 1.inv()).coerceAtLeast(60)

    val bitmap: Bitmap = Bitmap.createBitmap(overlayWidth, overlayHeight, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(bitmap)

    private val isDirty = AtomicBoolean(true)
    private val currentState = AtomicReference(VolleyballScoreboardData())

    // Paints
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(242, 244, 246, 249) // #F4F6F9 95% opacity
        style = Paint.Style.FILL
    }

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(160, 209, 213, 219) // #D1D5DB
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * scale
    }

    private val accentStripAPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(0, 180, 216) // Vibrant Blue / Cyan #00B4D8
        style = Paint.Style.FILL
    }

    private val accentStripBPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(239, 68, 68) // Vibrant Red #EF4444
        style = Paint.Style.FILL
    }

    private val scoreBoxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(30, 34, 41) // #1E2229
        style = Paint.Style.FILL
    }

    private val footerBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(229, 231, 235) // #E5E7EB
        style = Paint.Style.FILL
    }

    private val teamNamePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(17, 24, 39) // #111827
        textSize = 19f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }

    private val scoreTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 26f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    private val setsTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(107, 114, 128) // #6B7280
        textSize = 12f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.RIGHT
    }

    private val footerTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(55, 65, 81) // #374151
        textSize = 12f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
    }

    private val serveDotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(250, 204, 21) // Gold #FACC15
        style = Paint.Style.FILL
    }

    private val rowDividerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(80, 229, 231, 235)
        strokeWidth = 1f * scale
    }

    // Geometry rects
    private val cardRect = RectF(0f, 0f, overlayWidth.toFloat(), overlayHeight.toFloat())
    private val stripARect = RectF()
    private val stripBRect = RectF()
    private val scoreBoxARect = RectF()
    private val scoreBoxBRect = RectF()
    private val footerRect = RectF()

    fun updateData(newData: VolleyballScoreboardData) {
        val prev = currentState.get()
        if (prev != newData) {
            currentState.set(newData)
            isDirty.set(true)
        }
    }

    /**
     * Renders scoreboard if data has changed.
     * @return true if bitmap was redrawn, false if unchanged.
     */
    fun renderIfDirty(): Boolean {
        if (!isDirty.compareAndSet(true, false)) {
            return false
        }

        val data = currentState.get()
        bitmap.eraseColor(Color.TRANSPARENT)

        val cr = 10f * scale
        val rowHeight = (overlayHeight * 0.37f)
        val footerHeight = overlayHeight - (rowHeight * 2f)

        // 1. Draw outer Card
        canvas.drawRoundRect(cardRect, cr, cr, bgPaint)
        canvas.drawRoundRect(cardRect, cr, cr, borderPaint)

        // 2. Footer background
        footerRect.set(0f, overlayHeight - footerHeight, overlayWidth.toFloat(), overlayHeight.toFloat())
        canvas.drawRoundRect(footerRect, 0f, 0f, footerBgPaint)
        canvas.drawLine(0f, overlayHeight - footerHeight, overlayWidth.toFloat(), overlayHeight - footerHeight, borderPaint)

        // 3. Row 1: Team A
        val stripW = 8f * scale
        val scoreBoxW = 48f * scale
        val scoreBoxH = 28f * scale
        val scoreBoxRight = overlayWidth - 8f * scale

        // Strip A
        stripARect.set(0f, 0f, stripW, rowHeight)
        canvas.drawRoundRect(stripARect, 4f * scale, 4f * scale, accentStripAPaint)

        // Name A
        val teamAY = rowHeight * 0.62f
        canvas.drawText(data.teamA.take(10).uppercase(), stripW + 10f * scale, teamAY, teamNamePaint)

        // Serve dot A
        if (data.servingTeam == "A") {
            val textW = teamNamePaint.measureText(data.teamA.take(10).uppercase())
            canvas.drawCircle(stripW + 16f * scale + textW, teamAY - 6f * scale, 4f * scale, serveDotPaint)
        }

        // Sets A
        canvas.drawText("S:${data.setsA}", scoreBoxRight - scoreBoxW - 8f * scale, teamAY, setsTextPaint)

        // Score Box A
        val boxAY = (rowHeight - scoreBoxH) / 2f
        scoreBoxARect.set(scoreBoxRight - scoreBoxW, boxAY, scoreBoxRight, boxAY + scoreBoxH)
        canvas.drawRoundRect(scoreBoxARect, 4f * scale, 4f * scale, scoreBoxPaint)
        canvas.drawText(data.scoreA.toString(), scoreBoxARect.centerX(), scoreBoxARect.centerY() + 9f * scale, scoreTextPaint)

        // Divider between rows
        canvas.drawLine(stripW, rowHeight, overlayWidth.toFloat(), rowHeight, rowDividerPaint)

        // 4. Row 2: Team B
        val row2Top = rowHeight
        // Strip B
        stripBRect.set(0f, row2Top, stripW, row2Top + rowHeight)
        canvas.drawRoundRect(stripBRect, 4f * scale, 4f * scale, accentStripBPaint)

        // Name B
        val teamBY = row2Top + rowHeight * 0.62f
        canvas.drawText(data.teamB.take(10).uppercase(), stripW + 10f * scale, teamBY, teamNamePaint)

        // Serve dot B
        if (data.servingTeam == "B") {
            val textW = teamNamePaint.measureText(data.teamB.take(10).uppercase())
            canvas.drawCircle(stripW + 16f * scale + textW, teamBY - 6f * scale, 4f * scale, serveDotPaint)
        }

        // Sets B
        canvas.drawText("S:${data.setsB}", scoreBoxRight - scoreBoxW - 8f * scale, teamBY, setsTextPaint)

        // Score Box B
        val boxBY = row2Top + (rowHeight - scoreBoxH) / 2f
        scoreBoxBRect.set(scoreBoxRight - scoreBoxW, boxBY, scoreBoxRight, boxBY + scoreBoxH)
        canvas.drawRoundRect(scoreBoxBRect, 4f * scale, 4f * scale, scoreBoxPaint)
        canvas.drawText(data.scoreB.toString(), scoreBoxBRect.centerX(), scoreBoxBRect.centerY() + 9f * scale, scoreTextPaint)

        // 5. Footer info
        footerTextPaint.textAlign = Paint.Align.LEFT
        val footerY = overlayHeight - (footerHeight * 0.32f)
        canvas.drawText("VOLLEY LIVE", 10f * scale, footerY, footerTextPaint)

        footerTextPaint.textAlign = Paint.Align.CENTER
        canvas.drawText("SET ${data.currentSet}", overlayWidth / 2f, footerY, footerTextPaint)

        val banner = if (data.toastMessage.isNotBlank()) data.toastMessage else data.eventTag
        if (banner.isNotBlank() && isDisplayableBanner(banner)) {
            footerTextPaint.textAlign = Paint.Align.RIGHT
            canvas.drawText(banner.take(12).uppercase(), overlayWidth - 10f * scale, footerY, footerTextPaint)
        }

        return true
    }

    companion object {
        fun isDisplayableBanner(tag: String?): Boolean {
            if (tag.isNullOrBlank()) return false
            val clean = tag.trim().uppercase()
            if (clean.startsWith("POINT") ||
                clean.contains("POCZĄTEK") ||
                clean.contains("POCZATEK") ||
                clean.contains("START MECZU") ||
                clean.contains("COFNIĘTO") ||
                clean.contains("COFNIETO") ||
                clean == "SCOREUPDATE" ||
                clean == "INIT" ||
                clean == "START" ||
                clean == "NONE"
            ) {
                return false
            }
            return true
        }
    }
}
