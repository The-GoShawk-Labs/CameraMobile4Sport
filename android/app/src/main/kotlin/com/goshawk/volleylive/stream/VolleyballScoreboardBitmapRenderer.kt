package com.goshawk.volleylive.stream

import android.graphics.*
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Broadcast-grade, zero-allocation 2D Canvas renderer for Volleyball scoreboard (Scorebug).
 * Follows professional TV broadcast standards (PlusLiga / Polish 2. Liga / FIVB / CEV / SportCam).
 *
 * Features:
 * - 3-Letter Acronym (TLA) support (e.g. JAS vs KET) or full team names.
 * - Vertical thick tally bars (pionowe grube kreski) instead of dots for sets won.
 * - High-contrast TV cell layout: dark sets box (white text) & white points box (black text).
 * - Mobile-optimized, high-visibility stopwatch badge (no clipping/overlap).
 * - Allocates Bitmaps, Paints, and geometry ONCE during construction for 60 FPS zero-GC.
 */
class VolleyballScoreboardBitmapRenderer(
    val frameWidth: Int = 1920,
    val frameHeight: Int = 1080
) {
    val isPortrait: Boolean = frameHeight > frameWidth

    // Adaptive scale:
    // - Landscape (16:9): scale = frameWidth / 1920.0 (card width ~22.4% of frame width: 430/1920)
    // - Portrait (9:16): scale = frameWidth / 1080.0 (card width ~39.8% of frame width: 430/1080)
    val scale: Float = if (isPortrait) {
        frameWidth / 1080f
    } else {
        frameWidth / 1920f
    }

    // Proportional TV card (430x154 for Full HD, ratio ~2.8:1)
    val overlayWidth = ((430f * scale).toInt() and 1.inv()).coerceAtLeast(160)
    val overlayHeight = ((154f * scale).toInt() and 1.inv()).coerceAtLeast(60)

    val bitmap: Bitmap = Bitmap.createBitmap(overlayWidth, overlayHeight, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(bitmap)

    private val isDirty = AtomicBoolean(true)
    private val currentState = AtomicReference(VolleyballScoreboardData())

    // =========================================================================
    // PAINTS & STYLES (Professional TV Broadcast Palette)
    // =========================================================================

    // Card background: Crisp Slate-50 broadcast white (#F8FAFC, 97% opacity)
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(248, 248, 250, 252)
        style = Paint.Style.FILL
    }

    // Card outer border: Slate-300 (#CBD5E1)
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(203, 213, 225)
        style = Paint.Style.STROKE
        strokeWidth = 1.2f * scale
    }

    // Team Accent Strips (Default Cyan & Red, updated dynamically from data)
    private val accentStripAPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(0, 180, 216) // #00B4D8 Cyan
        style = Paint.Style.FILL
    }

    private val accentStripBPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(239, 68, 68) // #EF4444 Red
        style = Paint.Style.FILL
    }

    // Points Box: Pure White Box (#FFFFFF) with Slate-300 border for maximum pop
    private val scoreBoxBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }

    private val scoreBoxBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(203, 213, 225)
        style = Paint.Style.STROKE
        strokeWidth = 1.2f * scale
    }

    // Points Digits: Deep Slate-900 (#0F172A)
    private val scoreTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(15, 23, 42)
        textSize = 25f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    // Sets Box Background: Dark Slate-800 (#1E293B)
    private val setsBoxBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(30, 41, 59)
        style = Paint.Style.FILL
    }

    // Sets Micro-label "SET": Slate-400 (#94A3B8)
    private val setsLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(148, 163, 184)
        textSize = 7.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    // Sets Won Digits: Pure White
    private val setsCountPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 17f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    // Set Tally Vertical Bars (Best of 5): Pionowe grube kreski
    private val setBarInactivePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(203, 213, 225) // Slate-300
        style = Paint.Style.FILL
    }

    private val setBarActivePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private val setBarBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(148, 163, 184) // Slate-400
        style = Paint.Style.STROKE
        strokeWidth = 0.75f * scale
    }

    // Team Full Name: Slate-900 (#0F172A), heavy bold typography
    private val teamNamePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(15, 23, 42)
        textSize = 16.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }

    // Team 3-Letter Acronym (TLA): Larger bold font
    private val teamShortNamePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(15, 23, 42)
        textSize = 21f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }

    // Serve Indicator: Illuminated Gold Volleyball Ball
    private val serveBallFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(245, 158, 11) // Amber-500 Gold #F59E0B
        style = Paint.Style.FILL
    }

    private val serveBallBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * scale
    }

    // Dividers: Subtle Slate-200 lines
    private val rowDividerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(226, 232, 240)
        strokeWidth = 1f * scale
    }

    // Footer Background: Slate-200 (#E2E8F0)
    private val footerBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(226, 232, 240)
        style = Paint.Style.FILL
    }

    private val footerBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(203, 213, 225)
        strokeWidth = 1f * scale
    }

    // Footer Left Brand: Slate-600 (#475569)
    private val footerBrandPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(71, 85, 105)
        textSize = 10.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }

    // Footer Center Set Badge (White Pill)
    private val footerSetPillBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }

    private val footerSetPillBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(203, 213, 225)
        style = Paint.Style.STROKE
        strokeWidth = 1f * scale
    }

    private val footerSetTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(15, 23, 42)
        textSize = 11.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    // Mobile-optimized Stopwatch Badge
    private val footerClockPillBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }

    private val footerClockPillBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(203, 213, 225)
        style = Paint.Style.STROKE
        strokeWidth = 1f * scale
    }

    private val footerClockTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(15, 23, 42)
        textSize = 13.0f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    // Special Event Banner (Red/Crimson #DC2626)
    private val bannerPillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(220, 38, 38)
        style = Paint.Style.FILL
    }

    private val bannerTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 9.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    // Geometry Rects (Pre-allocated for Zero GC)
    private val cardRect = RectF(0f, 0f, overlayWidth.toFloat(), overlayHeight.toFloat())
    private val footerRect = RectF()
    private val scoreBoxRect = RectF()
    private val setsBoxRect = RectF()
    private val bannerPillRect = RectF()
    private val setPillRect = RectF()
    private val clockPillRect = RectF()
    private val setBarRect = RectF()

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
        val footerHeight = 38f * scale
        val footerTop = overlayHeight - footerHeight
        val rowHeight = footerTop / 2f // e.g. 58f * scale

        // Update dynamic team colors
        accentStripAPaint.color = data.colorA
        accentStripBPaint.color = data.colorB

        // 1. Draw Outer Card Background & Border
        canvas.drawRoundRect(cardRect, cr, cr, bgPaint)
        canvas.drawRoundRect(cardRect, cr, cr, borderPaint)

        // 2. Footer Background (Clipped to preserve bottom rounded corners)
        footerRect.set(0f, footerTop, overlayWidth.toFloat(), overlayHeight.toFloat())
        canvas.save()
        canvas.clipRect(footerRect)
        canvas.drawRoundRect(cardRect, cr, cr, footerBgPaint)
        canvas.restore()
        canvas.drawLine(0f, footerTop, overlayWidth.toFloat(), footerTop, footerBorderPaint)

        // 3. Row Dividers
        val stripW = 8f * scale
        canvas.drawLine(stripW, rowHeight, overlayWidth.toFloat(), rowHeight, rowDividerPaint)

        // =====================================================================
        // ROW 1: TEAM A (GOSPODARZE)
        // =====================================================================
        _renderTeamRow(
            rowTop = 0f,
            rowHeight = rowHeight,
            teamName = data.teamA,
            shortName = data.teamAShort,
            useShortNames = data.useShortNames,
            teamColor = data.colorA,
            accentPaint = accentStripAPaint,
            score = data.scoreA,
            setsWon = data.setsA,
            isServing = data.servingTeam == "A",
            isTopRow = true,
            cr = cr,
            stripW = stripW
        )

        // =====================================================================
        // ROW 2: TEAM B (GOŚCIE)
        // =====================================================================
        _renderTeamRow(
            rowTop = rowHeight,
            rowHeight = rowHeight,
            teamName = data.teamB,
            shortName = data.teamBShort,
            useShortNames = data.useShortNames,
            teamColor = data.colorB,
            accentPaint = accentStripBPaint,
            score = data.scoreB,
            setsWon = data.setsB,
            isServing = data.servingTeam == "B",
            isTopRow = false,
            cr = cr,
            stripW = stripW
        )

        // =====================================================================
        // FOOTER: 3 NON-OVERLAPPING STRICT ZONES
        // Zone 1 (Left 0..135): Brand or Special Event Banner
        // Zone 2 (Center 145..285): Current Set Pill Badge
        // Zone 3 (Right 295..420): Mobile-optimized Match Stopwatch Clock
        // =====================================================================
        val footerCenterY = footerTop + (footerHeight / 2f)

        // Zone 1: Left
        val banner = if (data.toastMessage.isNotBlank()) data.toastMessage else data.eventTag
        val hasBanner = banner.isNotBlank() && isDisplayableBanner(banner)
        if (hasBanner) {
            val cleanBanner = banner.trim().uppercase()
            val textW = bannerTextPaint.measureText(cleanBanner)
            val pillW = (textW + 16f * scale).coerceIn(40f * scale, 120f * scale)
            bannerPillRect.set(
                12f * scale,
                footerCenterY - 10f * scale,
                12f * scale + pillW,
                footerCenterY + 10f * scale
            )
            canvas.drawRoundRect(bannerPillRect, 4f * scale, 4f * scale, bannerPillPaint)
            canvas.drawText(
                cleanBanner,
                bannerPillRect.centerX(),
                footerCenterY + 3.5f * scale,
                bannerTextPaint
            )
        } else {
            canvas.drawText(
                "VOLLEY LIVE",
                12f * scale,
                footerCenterY + 4f * scale,
                footerBrandPaint
            )
        }

        // Zone 2: Center (Set Badge)
        val centerX = overlayWidth / 2f
        val pillW = 88f * scale
        val pillH = 24f * scale
        setPillRect.set(
            centerX - pillW / 2f,
            footerCenterY - pillH / 2f,
            centerX + pillW / 2f,
            footerCenterY + pillH / 2f
        )
        canvas.drawRoundRect(setPillRect, 5f * scale, 5f * scale, footerSetPillBgPaint)
        canvas.drawRoundRect(setPillRect, 5f * scale, 5f * scale, footerSetPillBorderPaint)

        val setLabel = if (data.currentSet >= 5) "SET 5 • TB" else "SET ${data.currentSet}"
        canvas.drawText(
            setLabel,
            centerX,
            footerCenterY + 4f * scale,
            footerSetTextPaint
        )

        // Zone 3: Right (Stopwatch Clock - Mobile High Visibility Badge)
        val clockText = if (data.matchClock.isNotBlank()) data.matchClock else "00:00"
        val displayTime = "⏱ $clockText"
        val clockW = (footerClockTextPaint.measureText(displayTime) + 16f * scale).coerceAtLeast(80f * scale)
        val clockRight = overlayWidth - 10f * scale
        clockPillRect.set(
            clockRight - clockW,
            footerCenterY - 12f * scale,
            clockRight,
            footerCenterY + 12f * scale
        )
        canvas.drawRoundRect(clockPillRect, 5f * scale, 5f * scale, footerClockPillBgPaint)
        canvas.drawRoundRect(clockPillRect, 5f * scale, 5f * scale, footerClockPillBorderPaint)
        canvas.drawText(
            displayTime,
            clockPillRect.centerX(),
            footerCenterY + 4.5f * scale,
            footerClockTextPaint
        )

        return true
    }

    private fun _renderTeamRow(
        rowTop: Float,
        rowHeight: Float,
        teamName: String,
        shortName: String,
        useShortNames: Boolean,
        teamColor: Int,
        accentPaint: Paint,
        score: Int,
        setsWon: Int,
        isServing: Boolean,
        isTopRow: Boolean,
        cr: Float,
        stripW: Float
    ) {
        // 1. Accent Strip
        if (isTopRow) {
            canvas.save()
            canvas.clipRect(0f, rowTop, stripW, rowTop + rowHeight)
            canvas.drawRoundRect(cardRect, cr, cr, accentPaint)
            canvas.restore()
        } else {
            canvas.drawRect(0f, rowTop, stripW, rowTop + rowHeight, accentPaint)
        }

        // 2. Geometry for Right-side Columns
        val boxH = 38f * scale
        val boxTop = rowTop + (rowHeight - boxH) / 2f

        // Points Box (54 x 38 px) - High-contrast White box with Black text
        val scoreBoxW = 54f * scale
        val scoreBoxRight = overlayWidth - 8f * scale
        val scoreBoxLeft = scoreBoxRight - scoreBoxW
        scoreBoxRect.set(scoreBoxLeft, boxTop, scoreBoxRight, boxTop + boxH)
        canvas.drawRoundRect(scoreBoxRect, 6f * scale, 6f * scale, scoreBoxBgPaint)
        canvas.drawRoundRect(scoreBoxRect, 6f * scale, 6f * scale, scoreBoxBorderPaint)
        canvas.drawText(
            score.toString(),
            scoreBoxRect.centerX(),
            boxTop + 27.5f * scale,
            scoreTextPaint
        )

        // Sets Box (36 x 38 px) - High-contrast Dark box with White text
        val setsBoxW = 36f * scale
        val setsBoxRight = scoreBoxLeft - 5f * scale
        val setsBoxLeft = setsBoxRight - setsBoxW
        setsBoxRect.set(setsBoxLeft, boxTop, setsBoxRight, boxTop + boxH)
        canvas.drawRoundRect(setsBoxRect, 6f * scale, 6f * scale, setsBoxBgPaint)
        canvas.drawText(
            "SET",
            setsBoxRect.centerX(),
            boxTop + 11.5f * scale,
            setsLabelPaint
        )
        canvas.drawText(
            setsWon.toString(),
            setsBoxRect.centerX(),
            boxTop + 30f * scale,
            setsCountPaint
        )

        // 3. Best-of-5 Set Tally Vertical Bars (Pionowe grube kreski - Huge space saving & Mobile clarity)
        val barW = 4.5f * scale
        val barH = 20.0f * scale
        val barGap = 3.5f * scale
        val barR = 2.0f * scale
        val barTop = rowTop + (rowHeight - barH) / 2f
        val rightBarRight = setsBoxLeft - 8f * scale
        val rightBarLeft = rightBarRight - barW
        val midBarLeft = rightBarLeft - barGap - barW
        val leftBarLeft = midBarLeft - barGap - barW
        val barLefts = floatArrayOf(leftBarLeft, midBarLeft, rightBarLeft)

        setBarActivePaint.color = teamColor

        for (i in 0 until 3) {
            val bx = barLefts[i]
            setBarRect.set(bx, barTop, bx + barW, barTop + barH)
            if (i < setsWon) {
                canvas.drawRoundRect(setBarRect, barR, barR, setBarActivePaint)
                canvas.drawRoundRect(setBarRect, barR, barR, setBarBorderPaint)
            } else {
                canvas.drawRoundRect(setBarRect, barR, barR, setBarInactivePaint)
                canvas.drawRoundRect(setBarRect, barR, barR, setBarBorderPaint)
            }
        }

        // 4. Team Name (3-Letter Acronym or Full Name) & Serve Indicator
        val nameLeft = stripW + 10f * scale
        val nameRightLimit = leftBarLeft - 8f * scale
        val availableW = nameRightLimit - nameLeft - (if (isServing) 22f * scale else 0f)

        val isUsingShort = useShortNames && shortName.isNotBlank()
        val textPaint = if (isUsingShort) teamShortNamePaint else teamNamePaint

        var displayName = (if (isUsingShort) shortName else teamName).trim().uppercase()
        if (textPaint.measureText(displayName) > availableW) {
            while (displayName.isNotEmpty() && textPaint.measureText("$displayName…") > availableW) {
                displayName = displayName.dropLast(1)
            }
            displayName = "$displayName…"
        }

        val textY = rowTop + rowHeight / 2f + (if (isUsingShort) 7.0f * scale else 5.5f * scale)
        canvas.drawText(displayName, nameLeft, textY, textPaint)

        // Serve Indicator: Illuminated Gold Volleyball Ball
        if (isServing) {
            val nameW = textPaint.measureText(displayName)
            val ballX = nameLeft + nameW + 11f * scale
            val ballY = rowTop + rowHeight / 2f
            canvas.drawCircle(ballX, ballY, 5.5f * scale, serveBallBorderPaint)
            canvas.drawCircle(ballX, ballY, 4.2f * scale, serveBallFillPaint)
        }
    }

    /**
     * Redraws the backing Canvas ONLY if scoreboard state or 1s clock changed,
     * and returns an immutable copy safe for RootEncoder's TextureLoader
     * (which recycles the passed Bitmap after uploading to GLES20 texture).
     */
    @Synchronized
    fun renderAndSnapshotIfDirty(): Bitmap? {
        if (!renderIfDirty()) return null
        return bitmap.copy(Bitmap.Config.ARGB_8888, false)
    }

    /**
     * Forces a fresh render of the current state and returns a Bitmap snapshot for initial GL filter binding.
     */
    @Synchronized
    fun forceRenderAndSnapshot(): Bitmap {
        isDirty.set(true)
        renderIfDirty()
        return bitmap.copy(Bitmap.Config.ARGB_8888, false)
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
