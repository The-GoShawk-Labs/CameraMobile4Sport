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
    // - Landscape (16:9): scale = frameWidth / 1920.0 (card width ~18.8% of frame width: 360/1920)
    // - Portrait (9:16): scale = frameWidth / 1080.0 (card width ~33.3% of frame width: 360/1080)
    val scale: Float = if (isPortrait) {
        frameWidth / 1080f
    } else {
        frameWidth / 1920f
    }

    // Proportional compact TV card (360x76 for Full HD, ratio ~4.74:1)
    val overlayWidth = ((360f * scale).toInt() and 1.inv()).coerceAtLeast(160)
    val overlayHeight = ((76f * scale).toInt() and 1.inv()).coerceAtLeast(40)

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
        textSize = 17f * scale
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
        textSize = 6.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    // Sets Won Digits: Pure White
    private val setsCountPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 12f * scale
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
        strokeWidth = 0.5f * scale
    }

    // Team Full Name: Slate-900 (#0F172A), heavy bold typography
    private val teamNamePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(15, 23, 42)
        textSize = 13f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }

    // Team 3-Letter Acronym (TLA): Larger bold font
    private val teamShortNamePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(15, 23, 42)
        textSize = 15f * scale
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
        strokeWidth = 1.0f * scale
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
        textSize = 8.5f * scale
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
        strokeWidth = 0.8f * scale
    }

    private val footerSetTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(15, 23, 42)
        textSize = 9.5f * scale
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
        strokeWidth = 0.8f * scale
    }

    private val footerClockTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(15, 23, 42)
        textSize = 9.5f * scale
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
        textSize = 8.5f * scale
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

    // =========================================================================
    // BROADCAST PRO COMPACT (3-LETTER) PAINTS & GEOMETRY (ZERO GC)
    // =========================================================================
    private val b3OuterBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(30, 41, 59) // #1E293B
        style = Paint.Style.STROKE
        strokeWidth = 1.2f * scale
    }
    private val b3LeagueBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(9, 13, 22) // #090D16 Dark Navy/Black
        style = Paint.Style.FILL
    }
    private val b3LeagueTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(0, 229, 255) // #00E5FF Cyan
        textSize = 7.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }
    private val b3TlaBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val b3TlaTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(15, 23, 42) // Slate-900 Black
        textSize = 15f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }
    private val b3SetsBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(26, 30, 46) // #1A1E2E Dark Navy
        style = Paint.Style.FILL
    }
    private val b3SetsTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 15f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }
    private val b3PointsBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(230, 0, 126) // #E6007E TV Magenta
        style = Paint.Style.FILL
    }
    private val b3PointsTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 18f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }
    private val b3ServeDotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val b3BannerBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(10, 14, 23) // #0A0E17 Solid Black/Navy
        style = Paint.Style.FILL
    }
    private val b3BannerTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 8.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }
    private val b3DividerDarkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(51, 65, 85) // #334155
        strokeWidth = 1f * scale
    }

    // Geometry Rects for broadcastCompact3Letter
    private val b3CardRect = RectF()
    private val b3ClipPath = Path()
    private val b3LeagueRect = RectF()
    private val b3Row1StripRect = RectF()
    private val b3Row1TlaRect = RectF()
    private val b3Row1SetsRect = RectF()
    private val b3Row1PtsRect = RectF()
    private val b3Row2StripRect = RectF()
    private val b3Row2TlaRect = RectF()
    private val b3Row2SetsRect = RectF()
    private val b3Row2PtsRect = RectF()
    private val b3BannerRect = RectF()

    // =========================================================================
    // CYBER GLOW NEON PAINTS & GEOMETRY (ZERO GC)
    // =========================================================================
    private val cgCardRect = RectF(0f, 0f, overlayWidth.toFloat(), overlayHeight.toFloat())
    private val cgBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(235, 10, 14, 23) // #0A0E17
        style = Paint.Style.FILL
    }
    private val cgBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(160, 0, 229, 255) // Cyan #00E5FF
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * scale
    }
    private val cgTeamTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 13f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }
    private val cgScoreTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = 17f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.RIGHT
    }
    private val cgFooterCyanPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(0, 229, 255)
        textSize = 9.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }
    private val cgFooterClockPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(180, 255, 255, 255)
        textSize = 9.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.RIGHT
    }
    private val cgDividerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(45, 0, 229, 255)
        strokeWidth = 1f * scale
    }

    // =========================================================================
    // MINIMALIST CLEAN PAINTS & GEOMETRY (ZERO GC)
    // =========================================================================
    private val miniCardRect = RectF(0f, 0f, overlayWidth.toFloat(), overlayHeight.toFloat())
    private val miniBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(220, 0, 0, 0)
        style = Paint.Style.FILL
    }
    private val miniBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(60, 255, 255, 255)
        style = Paint.Style.STROKE
        strokeWidth = 1f * scale
    }
    private val miniTeamTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 13f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }
    private val miniScoreTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 17f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.RIGHT
    }
    private val miniFooterTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(180, 255, 255, 255)
        textSize = 9.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        textAlign = Paint.Align.LEFT
    }
    private val miniClockTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(180, 255, 255, 255)
        textSize = 9.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        textAlign = Paint.Align.RIGHT
    }

    // =========================================================================
    // BEACH VOLLEY 2V2 PAINTS & GEOMETRY (ZERO GC)
    // =========================================================================
    private val bvCardRect = RectF(0f, 0f, overlayWidth.toFloat(), overlayHeight.toFloat())
    private val bvBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(230, 26, 20, 9) // #1A1409
        style = Paint.Style.FILL
    }
    private val bvBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(250, 204, 21) // #FACC15
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * scale
    }
    private val bvDividerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(45, 250, 204, 21)
        strokeWidth = 1f * scale
    }
    private val bvTeamTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 13f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }
    private val bvScoreTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(250, 204, 21) // Gold #FACC15
        textSize = 17f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.RIGHT
    }
    private val bvFooterGoldPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(250, 204, 21)
        textSize = 9.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.LEFT
    }
    private val bvFooterClockPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(190, 255, 255, 255)
        textSize = 9.5f * scale
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        textAlign = Paint.Align.RIGHT
    }

    private var lastValidMatchClock: String = "00:00"

    private fun resolveClockText(rawClock: String): String {
        val trimmed = rawClock.trim()
        if (trimmed.isNotEmpty() && trimmed != "00:00" && trimmed != "00:00:00") {
            lastValidMatchClock = trimmed
            return trimmed
        }
        return if (lastValidMatchClock.isNotEmpty()) lastValidMatchClock else "00:00"
    }

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

        when (data.style) {
            "broadcastCompact3Letter" -> _renderBroadcastCompact3Letter(data)
            "cyberGlow" -> _renderCyberGlow(data)
            "minimalist" -> _renderMinimalist(data)
            "beachVolley" -> _renderBeachVolley(data)
            else -> _renderTvProBroadcast(data)
        }

        return true
    }

    private fun _renderTvProBroadcast(data: VolleyballScoreboardData) {
        val cr = 6f * scale
        val footerHeight = 21f * scale
        val footerTop = overlayHeight - footerHeight
        val rowHeight = footerTop / 2f // e.g. 27.5f * scale

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
        val stripW = 5f * scale
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
        // Zone 1 (Left 0..110): Brand or Special Event Banner
        // Zone 2 (Center 115..245): Current Set Pill Badge
        // Zone 3 (Right 250..352): Mobile-optimized Match Stopwatch Clock
        // =====================================================================
        val footerCenterY = footerTop + (footerHeight / 2f)

        // Zone 1: Left
        val banner = if (data.toastMessage.isNotBlank()) data.toastMessage else data.eventTag
        val hasBanner = banner.isNotBlank() && isDisplayableBanner(banner)
        if (hasBanner) {
            val cleanBanner = banner.trim().uppercase()
            val textW = bannerTextPaint.measureText(cleanBanner)
            val pillW = (textW + 12f * scale).coerceIn(36f * scale, 100f * scale)
            bannerPillRect.set(
                8f * scale,
                footerCenterY - 8f * scale,
                8f * scale + pillW,
                footerCenterY + 8f * scale
            )
            canvas.drawRoundRect(bannerPillRect, 3f * scale, 3f * scale, bannerPillPaint)
            canvas.drawText(
                cleanBanner,
                bannerPillRect.centerX(),
                footerCenterY + 3f * scale,
                bannerTextPaint
            )
        } else {
            canvas.drawText(
                "VOLLEY LIVE",
                8f * scale,
                footerCenterY + 3f * scale,
                footerBrandPaint
            )
        }

        // Zone 2: Center (Set Badge)
        val centerX = overlayWidth / 2f
        val pillW = 68f * scale
        val pillH = 17f * scale
        setPillRect.set(
            centerX - pillW / 2f,
            footerCenterY - pillH / 2f,
            centerX + pillW / 2f,
            footerCenterY + pillH / 2f
        )
        canvas.drawRoundRect(setPillRect, 4f * scale, 4f * scale, footerSetPillBgPaint)
        canvas.drawRoundRect(setPillRect, 4f * scale, 4f * scale, footerSetPillBorderPaint)

        val setLabel = if (data.currentSet >= 5) "SET 5 • TB" else "SET ${data.currentSet}"
        canvas.drawText(
            setLabel,
            centerX,
            footerCenterY + 3.2f * scale,
            footerSetTextPaint
        )

        // Zone 3: Right (Stopwatch Clock - Mobile High Visibility Badge)
        val clockText = resolveClockText(data.matchClock)
        val displayTime = "⏱ $clockText"
        val clockW = (footerClockTextPaint.measureText(displayTime) + 12f * scale).coerceAtLeast(60f * scale)
        val clockRight = overlayWidth - 8f * scale
        clockPillRect.set(
            clockRight - clockW,
            footerCenterY - 8.5f * scale,
            clockRight,
            footerCenterY + 8.5f * scale
        )
        canvas.drawRoundRect(clockPillRect, 4f * scale, 4f * scale, footerClockPillBgPaint)
        canvas.drawRoundRect(clockPillRect, 4f * scale, 4f * scale, footerClockPillBorderPaint)
        canvas.drawText(
            displayTime,
            clockPillRect.centerX(),
            footerCenterY + 3.2f * scale,
            footerClockTextPaint
        )
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
        val boxH = 21f * scale
        val boxTop = rowTop + (rowHeight - boxH) / 2f

        // Points Box (40 x 21 px) - High-contrast White box with Black text
        val scoreBoxW = 40f * scale
        val scoreBoxRight = overlayWidth - 6f * scale
        val scoreBoxLeft = scoreBoxRight - scoreBoxW
        scoreBoxRect.set(scoreBoxLeft, boxTop, scoreBoxRight, boxTop + boxH)
        canvas.drawRoundRect(scoreBoxRect, 4f * scale, 4f * scale, scoreBoxBgPaint)
        canvas.drawRoundRect(scoreBoxRect, 4f * scale, 4f * scale, scoreBoxBorderPaint)
        canvas.drawText(
            score.toString(),
            scoreBoxRect.centerX(),
            boxTop + 15.5f * scale,
            scoreTextPaint
        )

        // Sets Box (26 x 21 px) - High-contrast Dark box with White text
        val setsBoxW = 26f * scale
        val setsBoxRight = scoreBoxLeft - 4f * scale
        val setsBoxLeft = setsBoxRight - setsBoxW
        setsBoxRect.set(setsBoxLeft, boxTop, setsBoxRight, boxTop + boxH)
        canvas.drawRoundRect(setsBoxRect, 4f * scale, 4f * scale, setsBoxBgPaint)
        canvas.drawText(
            "SET",
            setsBoxRect.centerX(),
            boxTop + 7f * scale,
            setsLabelPaint
        )
        canvas.drawText(
            setsWon.toString(),
            setsBoxRect.centerX(),
            boxTop + 17f * scale,
            setsCountPaint
        )

        // 3. Best-of-5 Set Tally Vertical Bars (Pionowe grube kreski - Huge space saving & Mobile clarity)
        val barW = 3f * scale
        val barH = 13f * scale
        val barGap = 2.5f * scale
        val barR = 1.5f * scale
        val barTop = rowTop + (rowHeight - barH) / 2f
        val rightBarRight = setsBoxLeft - 6f * scale
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
        val nameLeft = stripW + 8f * scale
        val nameRightLimit = leftBarLeft - 6f * scale
        val availableW = nameRightLimit - nameLeft - (if (isServing) 16f * scale else 0f)

        val isUsingShort = useShortNames && shortName.isNotBlank()
        val textPaint = if (isUsingShort) teamShortNamePaint else teamNamePaint

        var displayName = (if (isUsingShort) shortName else teamName).trim().uppercase()
        if (textPaint.measureText(displayName) > availableW) {
            while (displayName.isNotEmpty() && textPaint.measureText("$displayName…") > availableW) {
                displayName = displayName.dropLast(1)
            }
            displayName = "$displayName…"
        }

        val textY = rowTop + rowHeight / 2f + (if (isUsingShort) 5.5f * scale else 4.5f * scale)
        canvas.drawText(displayName, nameLeft, textY, textPaint)

        // Serve Indicator: Illuminated Gold Volleyball Ball
        if (isServing) {
            val nameW = textPaint.measureText(displayName)
            val ballX = nameLeft + nameW + 9f * scale
            val ballY = rowTop + rowHeight / 2f
            canvas.drawCircle(ballX, ballY, 4.5f * scale, serveBallBorderPaint)
            canvas.drawCircle(ballX, ballY, 3.5f * scale, serveBallFillPaint)
        }
    }

    private fun _renderBroadcastCompact3Letter(data: VolleyballScoreboardData) {
        val wLeague = 24f * scale
        val wStrip = 4f * scale
        val wTla = 68f * scale
        val wSets = 34f * scale
        val wPts = 48f * scale
        val cardW = wLeague + wStrip + wTla + wSets + wPts // 178f * scale
        val rowH = 27.5f * scale
        val bannerH = 21f * scale
        val cardH = rowH * 2f + bannerH // 76f * scale
        val cr = 6f * scale

        val cardLeft: Float = when (data.anchorPosition) {
            "topRight", "bottomRight" -> overlayWidth - cardW
            "topCenter", "bottomCenter" -> (overlayWidth - cardW) / 2f
            else -> 0f // topLeft, bottomLeft
        }
        val cardTop = 0f

        // Team Accent colors
        accentStripAPaint.color = data.colorA
        accentStripBPaint.color = data.colorB

        b3CardRect.set(cardLeft, cardTop, cardLeft + cardW, cardTop + cardH)

        // Rounded clipping path for card
        b3ClipPath.reset()
        b3ClipPath.addRoundRect(b3CardRect, cr, cr, Path.Direction.CW)
        canvas.save()
        canvas.clipPath(b3ClipPath)

        // 1. League block on the left (spans row 1 & row 2: height = 55f * scale)
        b3LeagueRect.set(cardLeft, cardTop, cardLeft + wLeague, cardTop + rowH * 2f)
        canvas.drawRect(b3LeagueRect, b3LeagueBgPaint)
        val leagueCenterX = b3LeagueRect.centerX()
        val startY = cardTop + 12f * scale
        val charSpacing = 11f * scale
        canvas.drawText("L", leagueCenterX, startY, b3LeagueTextPaint)
        canvas.drawText("I", leagueCenterX, startY + charSpacing, b3LeagueTextPaint)
        canvas.drawText("G", leagueCenterX, startY + charSpacing * 2f, b3LeagueTextPaint)
        canvas.drawText("A", leagueCenterX, startY + charSpacing * 3f, b3LeagueTextPaint)

        // =====================================================================
        // ROW 1: TEAM A (GOSPODARZE)
        // =====================================================================
        val strip1Left = cardLeft + wLeague
        b3Row1StripRect.set(strip1Left, cardTop, strip1Left + wStrip, cardTop + rowH)
        canvas.drawRect(b3Row1StripRect, accentStripAPaint)

        val tla1Left = strip1Left + wStrip
        b3Row1TlaRect.set(tla1Left, cardTop, tla1Left + wTla, cardTop + rowH)
        canvas.drawRect(b3Row1TlaRect, b3TlaBgPaint)
        val textY1 = cardTop + rowH / 2f + 5.5f * scale
        canvas.drawText(data.teamAShortCode, b3Row1TlaRect.centerX(), textY1, b3TlaTextPaint)

        val sets1Left = tla1Left + wTla
        b3Row1SetsRect.set(sets1Left, cardTop, sets1Left + wSets, cardTop + rowH)
        canvas.drawRect(b3Row1SetsRect, b3SetsBgPaint)
        val setsY1 = cardTop + rowH / 2f + 5.5f * scale
        canvas.drawText(data.setsA.toString(), b3Row1SetsRect.centerX(), setsY1, b3SetsTextPaint)

        val pts1Left = sets1Left + wSets
        b3Row1PtsRect.set(pts1Left, cardTop, pts1Left + wPts, cardTop + rowH)
        canvas.drawRect(b3Row1PtsRect, b3PointsBgPaint)
        val ptsY1 = cardTop + rowH / 2f + 6.5f * scale
        canvas.drawText(data.scoreA.toString(), b3Row1PtsRect.centerX(), ptsY1, b3PointsTextPaint)

        // Service dot
        if (data.servingTeam == "A") {
            val dotX = pts1Left + wPts - 5f * scale
            val dotY = cardTop + rowH / 2f
            canvas.drawCircle(dotX, dotY, 3f * scale, b3ServeDotPaint)
        }

        // =====================================================================
        // ROW 2: TEAM B (GOŚCIE)
        // =====================================================================
        val row2Top = cardTop + rowH
        b3Row2StripRect.set(strip1Left, row2Top, strip1Left + wStrip, row2Top + rowH)
        canvas.drawRect(b3Row2StripRect, accentStripBPaint)

        b3Row2TlaRect.set(tla1Left, row2Top, tla1Left + wTla, row2Top + rowH)
        canvas.drawRect(b3Row2TlaRect, b3TlaBgPaint)
        val textY2 = row2Top + rowH / 2f + 5.5f * scale
        canvas.drawText(data.teamBShortCode, b3Row2TlaRect.centerX(), textY2, b3TlaTextPaint)

        b3Row2SetsRect.set(sets1Left, row2Top, sets1Left + wSets, row2Top + rowH)
        canvas.drawRect(b3Row2SetsRect, b3SetsBgPaint)
        val setsY2 = row2Top + rowH / 2f + 5.5f * scale
        canvas.drawText(data.setsB.toString(), b3Row2SetsRect.centerX(), setsY2, b3SetsTextPaint)

        b3Row2PtsRect.set(pts1Left, row2Top, pts1Left + wPts, row2Top + rowH)
        canvas.drawRect(b3Row2PtsRect, b3PointsBgPaint)
        val ptsY2 = row2Top + rowH / 2f + 6.5f * scale
        canvas.drawText(data.scoreB.toString(), b3Row2PtsRect.centerX(), ptsY2, b3PointsTextPaint)

        // Service dot
        if (data.servingTeam == "B") {
            val dotX = pts1Left + wPts - 5f * scale
            val dotY = row2Top + rowH / 2f
            canvas.drawCircle(dotX, dotY, 3f * scale, b3ServeDotPaint)
        }

        // Dividers between Row 1 & Row 2
        canvas.drawLine(tla1Left, row2Top, pts1Left + wPts, row2Top, b3DividerDarkPaint)

        // =====================================================================
        // DYNAMIC ATTACHED BANNER (Below Row 2)
        // =====================================================================
        val bannerTop = cardTop + rowH * 2f
        b3BannerRect.set(cardLeft, bannerTop, cardLeft + cardW, bannerTop + bannerH)
        canvas.drawRect(b3BannerRect, b3BannerBgPaint)
        canvas.drawLine(cardLeft, bannerTop, cardLeft + cardW, bannerTop, b3DividerDarkPaint)

        val banner = if (data.toastMessage.isNotBlank()) data.toastMessage else data.eventTag
        val hasCustomBanner = banner.isNotBlank() && isDisplayableBanner(banner)
        val bannerCenterY = bannerTop + bannerH / 2f + 3f * scale
        val clockText = resolveClockText(data.matchClock)

        if (hasCustomBanner) {
            val cleanBanner = banner.trim().uppercase()
            canvas.drawText(cleanBanner, b3BannerRect.centerX(), bannerCenterY, b3BannerTextPaint)
        } else {
            val clockStr = if (clockText.isNotEmpty() && clockText != "00:00") "  •  $clockText" else ""
            val defaultBannerText = "SET ${data.currentSet}$clockStr"
            canvas.drawText(defaultBannerText, b3BannerRect.centerX(), bannerCenterY, b3BannerTextPaint)
        }

        canvas.restore()

        // Outer Card Border
        canvas.drawRoundRect(b3CardRect, cr, cr, b3OuterBorderPaint)
    }

    private fun _renderCyberGlow(data: VolleyballScoreboardData) {
        val cr = 6f * scale
        cgCardRect.set(0f, 0f, overlayWidth.toFloat(), overlayHeight.toFloat())
        canvas.drawRoundRect(cgCardRect, cr, cr, cgBgPaint)
        canvas.drawRoundRect(cgCardRect, cr, cr, cgBorderPaint)

        val footerH = 21f * scale
        val rowHeight = (overlayHeight - footerH) / 2f
        val padX = 8f * scale

        // Row 1: Team A
        val nameA = if (data.useShortNames && data.teamAShort.isNotBlank()) data.teamAShort.uppercase() else data.teamA.uppercase()
        val textY1 = rowHeight / 2f + 4.5f * scale
        canvas.drawText(nameA, padX, textY1, cgTeamTextPaint)

        if (data.servingTeam == "A") {
            val nameW = cgTeamTextPaint.measureText(nameA)
            canvas.drawCircle(padX + nameW + 9f * scale, rowHeight / 2f, 3.5f * scale, serveBallFillPaint)
        }

        cgScoreTextPaint.color = data.colorA
        canvas.drawText(data.scoreA.toString(), overlayWidth - padX, rowHeight / 2f + 6f * scale, cgScoreTextPaint)

        // Divider
        canvas.drawLine(padX, rowHeight, overlayWidth - padX, rowHeight, cgDividerPaint)

        // Row 2: Team B
        val row2Top = rowHeight
        val nameB = if (data.useShortNames && data.teamBShort.isNotBlank()) data.teamBShort.uppercase() else data.teamB.uppercase()
        val textY2 = row2Top + rowHeight / 2f + 4.5f * scale
        canvas.drawText(nameB, padX, textY2, cgTeamTextPaint)

        if (data.servingTeam == "B") {
            val nameW = cgTeamTextPaint.measureText(nameB)
            canvas.drawCircle(padX + nameW + 9f * scale, row2Top + rowHeight / 2f, 3.5f * scale, serveBallFillPaint)
        }

        cgScoreTextPaint.color = data.colorB
        canvas.drawText(data.scoreB.toString(), overlayWidth - padX, row2Top + rowHeight / 2f + 6f * scale, cgScoreTextPaint)

        // Divider
        val footerTop = rowHeight * 2f
        canvas.drawLine(padX, footerTop, overlayWidth - padX, footerTop, cgDividerPaint)

        // Footer
        val footerY = footerTop + (overlayHeight - footerTop) / 2f + 3f * scale
        val setTxt = "SET ${data.currentSet} (${data.setsA}:${data.setsB})"
        canvas.drawText(setTxt, padX, footerY, cgFooterCyanPaint)

        val clock = resolveClockText(data.matchClock)
        canvas.drawText(clock, overlayWidth - padX, footerY, cgFooterClockPaint)
    }

    private fun _renderMinimalist(data: VolleyballScoreboardData) {
        val cr = 6f * scale
        miniCardRect.set(0f, 0f, overlayWidth.toFloat(), overlayHeight.toFloat())
        canvas.drawRoundRect(miniCardRect, cr, cr, miniBgPaint)
        canvas.drawRoundRect(miniCardRect, cr, cr, miniBorderPaint)

        val footerH = 21f * scale
        val rowHeight = (overlayHeight - footerH) / 2f
        val padX = 8f * scale

        // Row 1
        val nameA = if (data.useShortNames && data.teamAShort.isNotBlank()) data.teamAShort.uppercase() else data.teamA.uppercase()
        canvas.drawText(nameA, padX, rowHeight / 2f + 4.5f * scale, miniTeamTextPaint)
        canvas.drawText(data.scoreA.toString(), overlayWidth - padX, rowHeight / 2f + 6f * scale, miniScoreTextPaint)

        // Row 2
        val row2Top = rowHeight
        val nameB = if (data.useShortNames && data.teamBShort.isNotBlank()) data.teamBShort.uppercase() else data.teamB.uppercase()
        canvas.drawText(nameB, padX, row2Top + rowHeight / 2f + 4.5f * scale, miniTeamTextPaint)
        canvas.drawText(data.scoreB.toString(), overlayWidth - padX, row2Top + rowHeight / 2f + 6f * scale, miniScoreTextPaint)

        // Footer
        val footerTop = rowHeight * 2f
        val footerY = footerTop + (overlayHeight - footerTop) / 2f + 3f * scale
        canvas.drawText("SET ${data.currentSet}", padX, footerY, miniFooterTextPaint)

        val clock = resolveClockText(data.matchClock)
        canvas.drawText(clock, overlayWidth - padX, footerY, miniClockTextPaint)
    }

    private fun _renderBeachVolley(data: VolleyballScoreboardData) {
        val cr = 6f * scale
        bvCardRect.set(0f, 0f, overlayWidth.toFloat(), overlayHeight.toFloat())
        canvas.drawRoundRect(bvCardRect, cr, cr, bvBgPaint)
        canvas.drawRoundRect(bvCardRect, cr, cr, bvBorderPaint)

        val footerH = 21f * scale
        val rowHeight = (overlayHeight - footerH) / 2f
        val padX = 8f * scale

        // Row 1
        val nameA = if (data.useShortNames && data.teamAShort.isNotBlank()) data.teamAShort.uppercase() else data.teamA.uppercase()
        canvas.drawText(nameA, padX, rowHeight / 2f + 4.5f * scale, bvTeamTextPaint)
        canvas.drawText(data.scoreA.toString(), overlayWidth - padX, rowHeight / 2f + 6f * scale, bvScoreTextPaint)

        // Divider
        canvas.drawLine(padX, rowHeight, overlayWidth - padX, rowHeight, bvDividerPaint)

        // Row 2
        val row2Top = rowHeight
        val nameB = if (data.useShortNames && data.teamBShort.isNotBlank()) data.teamBShort.uppercase() else data.teamB.uppercase()
        canvas.drawText(nameB, padX, row2Top + rowHeight / 2f + 4.5f * scale, bvTeamTextPaint)
        canvas.drawText(data.scoreB.toString(), overlayWidth - padX, row2Top + rowHeight / 2f + 6f * scale, bvScoreTextPaint)

        // Divider
        val footerTop = rowHeight * 2f
        canvas.drawLine(padX, footerTop, overlayWidth - padX, footerTop, bvDividerPaint)

        // Footer
        val footerY = footerTop + (overlayHeight - footerTop) / 2f + 3f * scale
        canvas.drawText("SET ${data.currentSet}", padX, footerY, bvFooterGoldPaint)

        val clock = resolveClockText(data.matchClock)
        canvas.drawText(clock, overlayWidth - padX, footerY, bvFooterClockPaint)
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
