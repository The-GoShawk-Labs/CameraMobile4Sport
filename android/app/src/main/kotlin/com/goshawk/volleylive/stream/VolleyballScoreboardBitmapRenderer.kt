package com.goshawk.volleylive.stream

import android.graphics.*
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Zero-allocation, high-performance 2D Canvas renderer for Volleyball scoreboard.
 * Allocates all Bitmaps, Paints, and geometry ONCE during construction.
 * Renders to the backing Bitmap ONLY when state updates (`isDirty == true`),
 * preventing garbage collection thrashing at 60 FPS.
 */
class VolleyballScoreboardBitmapRenderer(
    private val frameWidth: Int = 1920,
    private val frameHeight: Int = 1080
) {
    // Proportional HUD card at top of video stream (width ~58% of frame, height 160px for card + event banner)
    val overlayWidth = (frameWidth * 0.58f).toInt()
    val overlayHeight = 160
    val cardHeight = 110f

    val bitmap: Bitmap = Bitmap.createBitmap(overlayWidth, overlayHeight, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(bitmap)

    private val isDirty = AtomicBoolean(true)
    private val currentState = AtomicReference(VolleyballScoreboardData())

    // Pre-allocated Paints (Hardware antialiased)
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(240, 13, 17, 26) // Deep Navy/Dark Slate #0D111A
        style = Paint.Style.FILL
    }

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(200, 46, 58, 82) // #2E3A52
        style = Paint.Style.STROKE
        strokeWidth = 2.5f
    }

    private val accentStripAPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(0, 229, 255) // Cyan
        style = Paint.Style.FILL
    }

    private val accentStripBPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(250, 204, 21) // Gold
        style = Paint.Style.FILL
    }

    private val centerBoxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(9, 12, 18) // #090C12
        style = Paint.Style.FILL
    }

    private val pointsBoxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(21, 28, 40) // #151C28
        style = Paint.Style.FILL
    }

    private val separatorPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(31, 41, 61) // #1F293D
        strokeWidth = 2.0f
    }

    private val teamANamePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 26f
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }

    private val teamBNamePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 26f
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.RIGHT
    }

    private val scoreAPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(0, 229, 255)
        textSize = 40f
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    private val scoreBPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(250, 204, 21)
        textSize = 40f
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    private val periodLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(200, 255, 255, 255)
        textSize = 17f
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    private val setsScorePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(255, 179, 0) // Amber #FFB300
        textSize = 20f
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    private val serveDotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(250, 204, 21) // Gold
        style = Paint.Style.FILL
    }

    private val redBannerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(230, 229, 57, 53) // Red #E53935
        style = Paint.Style.FILL
    }

    private val redBannerTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 18f
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
        letterSpacing = 0.04f
    }

    private val cardRect = RectF(0f, 0f, overlayWidth.toFloat(), cardHeight)
    private val redBannerRect = RectF()
    private val centerBoxRect = RectF()
    private val pointsBoxARect = RectF()
    private val pointsBoxBRect = RectF()
    private val stripARect = RectF()
    private val stripBRect = RectF()

    fun updateData(newData: VolleyballScoreboardData) {
        currentState.set(newData)
        isDirty.set(true)
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

        // 1. Draw outer TV Broadcast Card
        canvas.drawRoundRect(cardRect, 18f, 18f, bgPaint)
        canvas.drawRoundRect(cardRect, 18f, 18f, borderPaint)

        val midX = overlayWidth / 2f
        val midY = cardHeight / 2f

        // 2. Team A & B Accent Strips (Left & Right edges)
        stripARect.set(0f, 0f, 12f, cardHeight)
        canvas.drawRoundRect(stripARect, 6f, 6f, accentStripAPaint)

        stripBRect.set(overlayWidth - 12f, 0f, overlayWidth.toFloat(), cardHeight)
        canvas.drawRoundRect(stripBRect, 6f, 6f, accentStripBPaint)

        // 3. Center Period Box ("SET X" & "setsA-setsB")
        val centerBoxWidth = 130f
        centerBoxRect.set(
            midX - centerBoxWidth / 2,
            0f,
            midX + centerBoxWidth / 2,
            cardHeight
        )
        canvas.drawRect(centerBoxRect, centerBoxPaint)
        canvas.drawLine(centerBoxRect.left, 0f, centerBoxRect.left, cardHeight, separatorPaint)
        canvas.drawLine(centerBoxRect.right, 0f, centerBoxRect.right, cardHeight, separatorPaint)

        canvas.drawText("SET ${data.currentSet}", midX, midY - 6f, periodLabelPaint)
        canvas.drawText("${data.setsA}-${data.setsB}", midX, midY + 24f, setsScorePaint)

        // 4. Team A Points Box (Dark Navy)
        val pointsBoxWidth = 90f
        pointsBoxARect.set(
            centerBoxRect.left - pointsBoxWidth,
            0f,
            centerBoxRect.left,
            cardHeight
        )
        canvas.drawRect(pointsBoxARect, pointsBoxPaint)
        canvas.drawText(
            data.scoreA.toString(),
            pointsBoxARect.centerX(),
            midY + 14f,
            scoreAPaint
        )

        // 5. Team B Points Box (Dark Navy)
        pointsBoxBRect.set(
            centerBoxRect.right,
            0f,
            centerBoxRect.right + pointsBoxWidth,
            cardHeight
        )
        canvas.drawRect(pointsBoxBRect, pointsBoxPaint)
        canvas.drawText(
            data.scoreB.toString(),
            pointsBoxBRect.centerX(),
            midY + 14f,
            scoreBPaint
        )

        // 6. Team A side (Left)
        val teamAX = 32f
        canvas.drawText(data.teamA.uppercase(), teamAX, midY + 9f, teamANamePaint)
        if (data.servingTeam == "A") {
            canvas.drawCircle(teamAX - 14f, midY, 6f, serveDotPaint)
        }

        // 7. Team B side (Right)
        val teamBX = overlayWidth - 32f
        canvas.drawText(data.teamB.uppercase(), teamBX, midY + 9f, teamBNamePaint)
        if (data.servingTeam == "B") {
            canvas.drawCircle(teamBX + 14f, midY, 6f, serveDotPaint)
        }

        // 8. Dynamic Red Event/Toast Banner directly below the scoreboard card
        val rawBanner = when {
            data.toastMessage.isNotBlank() -> data.toastMessage.trim()
            data.eventTag.isNotBlank() -> data.eventTag.trim()
            else -> ""
        }
        val bannerText = if (isDisplayableBanner(rawBanner)) rawBanner else ""
        if (bannerText.isNotEmpty()) {
            val bannerW = 280f
            val bannerH = 32f
            val bannerY = 118f
            redBannerRect.set(midX - bannerW / 2f, bannerY, midX + bannerW / 2f, bannerY + bannerH)
            canvas.drawRoundRect(redBannerRect, 12f, 12f, redBannerPaint)
            canvas.drawText(bannerText.uppercase(), midX, bannerY + 22f, redBannerTextPaint)
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
