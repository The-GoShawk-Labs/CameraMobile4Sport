import 'package:flutter/material.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/match_recording_metadata.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';
import 'package:volleylive/domain/models/streaming_config.dart';

/// Nowoczesna, telewizyjna tablica wyników (Scoreboard / Scorebug)
/// wzorowana na systemach komercyjnych (np. SportCam).
///
/// Obsługuje:
/// 1. Siatkę 6 pozycji kotwiczenia (ScoreboardAnchorPosition) wewnątrz aktywnego kadru 16:9.
/// 2. Skalowanie proporcjonalne względem rozdzielczości FullHD (1920x1080) i widoku wideo.
/// 3. Kompaktowy układ telewizyjny o proporcjach ~2.8:1 (430 x 154 px bazowo).
/// 4. Ochronę przed jankiem UI i zbędnymi przerysowaniami (RepaintBoundary).
class ScoreboardOverlay extends StatelessWidget {
  final MatchSession session;
  final ScoreboardThemeStyle style;
  final ScoreboardAnchorPosition anchorPosition;
  final double targetAspectRatio;
  final double? customScale;
  final bool isTimeoutActive;
  final int timeoutSeconds;
  final ServingTeam timeoutTeam;
  final bool showServeIndicator;
  final String? activeSpecialEvent;
  final Duration? matchDuration;
  final bool animate;
  final bool isStandaloneCard;

  const ScoreboardOverlay({
    super.key,
    required this.session,
    this.style = ScoreboardThemeStyle.tvProBroadcast,
    this.anchorPosition = ScoreboardAnchorPosition.topLeft,
    this.targetAspectRatio = 16.0 / 9.0,
    this.customScale,
    this.isTimeoutActive = false,
    this.timeoutSeconds = 0,
    this.timeoutTeam = ServingTeam.none,
    this.showServeIndicator = true,
    this.activeSpecialEvent,
    this.matchDuration,
    this.animate = true,
    this.isStandaloneCard = false,
  });

  String _formatMatchTime(Duration? duration) {
    if (duration != null) {
      final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      if (duration.inHours > 0) {
        final h = duration.inHours.toString().padLeft(2, '0');
        return '$h:$m:$s';
      }
      return '$m:$s';
    }
    return '00:00';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Jeśli rodzic jest nieograniczony lub wymagana jest sama karta:
        final hasInfiniteBounds =
            !constraints.maxWidth.isFinite ||
            !constraints.maxHeight.isFinite ||
            constraints.maxWidth <= 0 ||
            constraints.maxHeight <= 0;

        if (isStandaloneCard || hasInfiniteBounds) {
          final baseW =
              (constraints.maxWidth.isFinite && constraints.maxWidth > 0)
              ? constraints.maxWidth
              : 430.0;
          final rawScale = customScale ?? (baseW / 430.0);
          final scale = (rawScale.isFinite && rawScale > 0 ? rawScale : 1.0)
              .clamp(0.1, 2.5);
          return RepaintBoundary(
            child: SizedBox(
              width: 430.0 * scale,
              height: 154.0 * scale,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: 430.0,
                  height: 154.0,
                  child: _buildScoreboardCard(context, 1.0),
                ),
              ),
            ),
          );
        }

        // =====================================================================
        // ALGORYTM WERYFIKACJI VIEWPORTU WIDEO (16:9 ORAZ PIONOWEGO 9:16)
        // =====================================================================
        final parentW = constraints.maxWidth;
        final parentH = constraints.maxHeight;
        final safeAspect =
            (targetAspectRatio.isFinite && targetAspectRatio > 0)
            ? targetAspectRatio
            : (16.0 / 9.0);
        final isPortraitVideo = safeAspect < 1.0;

        double videoW;
        double videoH;
        double offsetX = 0.0;
        double offsetY = 0.0;

        if (parentW / parentH > safeAspect) {
          // Pillarbox: kontener jest szerszy niż strumień wideo (np. pionowe wideo 9:16 w oknie 16:9 lub ekran 20:9)
          videoH = parentH;
          videoW = videoH * safeAspect;
          offsetX = (parentW - videoW) / 2.0;
          offsetY = 0.0;
        } else {
          // Letterbox: kontener jest wyższy niż strumień wideo
          videoW = parentW;
          videoH = videoW / safeAspect;
          offsetX = 0.0;
          offsetY = (parentH - videoH) / 2.0;
        }

        // Dla strumienia poziomego (16:9) szerokość bazowa FullHD to 1920px (karta ~22.4% szerokości kadru).
        // Dla strumienia pionowego (9:16) szerokość bazowa FullHD to 1080px (karta ~39.8% szerokości pionowego kadru),
        // dzięki czemu tablica idealnie mieści się wewnątrz pionowego strumienia wideo.
        final referenceStreamWidth = isPortraitVideo ? 1080.0 : 1920.0;
        final rawScale = customScale ?? (videoW / referenceStreamWidth);
        final scale = (rawScale.isFinite && rawScale > 0 ? rawScale : 0.5)
            .clamp(0.05, 2.5);
        final cardW = (430.0 * scale).clamp(10.0, videoW * 0.92);
        final cardH = cardW * (154.0 / 430.0);

        // Bezpieczne marginesy telewizyjne (Broadcast Safe Margin) wewnątrz aktywnego kadru wideo
        final marginX = videoW * (isPortraitVideo ? 0.035 : ScoreboardAnchorPosition.safeMarginX);
        final marginY = videoH * ScoreboardAnchorPosition.safeMarginY;

        double left;
        double top;

        switch (anchorPosition) {
          case ScoreboardAnchorPosition.topLeft:
            left = offsetX + marginX;
            top = offsetY + marginY;
            break;
          case ScoreboardAnchorPosition.topCenter:
            left = offsetX + (videoW - cardW) / 2.0;
            top = offsetY + marginY;
            break;
          case ScoreboardAnchorPosition.topRight:
            left = offsetX + videoW - marginX - cardW;
            top = offsetY + marginY;
            break;
          case ScoreboardAnchorPosition.bottomLeft:
            left = offsetX + marginX;
            top = offsetY + videoH - marginY - cardH;
            break;
          case ScoreboardAnchorPosition.bottomCenter:
            left = offsetX + (videoW - cardW) / 2.0;
            top = offsetY + videoH - marginY - cardH;
            break;
          case ScoreboardAnchorPosition.bottomRight:
            left = offsetX + videoW - marginX - cardW;
            top = offsetY + videoH - marginY - cardH;
            break;
        }

        // Gwarancja, że widżet nigdy nie wyjdzie poza granice aktywnego strumienia wideo
        final minLeft = offsetX;
        final maxLeft = (offsetX + videoW - cardW) > minLeft
            ? (offsetX + videoW - cardW)
            : minLeft;
        final minTop = offsetY;
        final maxTop = (offsetY + videoH - cardH) > minTop
            ? (offsetY + videoH - cardH)
            : minTop;
        left = left.clamp(minLeft, maxLeft);
        top = top.clamp(minTop, maxTop);

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: left,
              top: top,
              width: cardW,
              height: cardH,
              child: RepaintBoundary(
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: 430.0,
                    height: 154.0,
                    child: _buildScoreboardCard(context, 1.0),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScoreboardCard(BuildContext context, double scale) {
    switch (style) {
      case ScoreboardThemeStyle.tvProBroadcast:
        return _buildSportCamTvBroadcast(scale);
      case ScoreboardThemeStyle.cyberGlow:
        return _buildCyberGlow(scale);
      case ScoreboardThemeStyle.minimalist:
        return _buildMinimalist(scale);
      case ScoreboardThemeStyle.beachVolley:
        return _buildBeachVolley(scale);
    }
  }

  // ===========================================================================
  // 1. STYL SPORTCAM TV PRO BROADCAST (Telewizyjna karta 2.8:1)
  // ===========================================================================
  Widget _buildSportCamTvBroadcast(double scale) {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;

    return Container(
      width: 430.0 * scale,
      height: 154.0 * scale,
      decoration: BoxDecoration(
        color: const Color(0xF2F4F6F9), // 95% opacity #F4F6F9
        borderRadius: BorderRadius.circular(10.0 * scale),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12.0 * scale,
            offset: Offset(0, 4.0 * scale),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10.0 * scale),
        child: Column(
          children: [
            // WIERSZ 1: GOSPODARZE (TEAM A)
            Expanded(
              child: _buildSportCamTeamRow(
                teamName: session.teamA,
                teamColor: session.teamAColor,
                score: session.currentSetPointsA,
                setsWon: session.setsA,
                isServing: isServingA,
                scale: scale,
                isTopRow: true,
              ),
            ),

            // SUBTELNY SEPARATOR
            Container(height: 1.0 * scale, color: const Color(0xFFE5E7EB)),

            // WIERSZ 2: GOŚCIE (TEAM B)
            Expanded(
              child: _buildSportCamTeamRow(
                teamName: session.teamB,
                teamColor: session.teamBColor,
                score: session.currentSetPointsB,
                setsWon: session.setsB,
                isServing: isServingB,
                scale: scale,
                isTopRow: false,
              ),
            ),

            // WIERSZ 3: DOLNY PASEK STATUSU / FOOTER (~26% WYSOKOŚCI)
            _buildSportCamFooter(scale),
          ],
        ),
      ),
    );
  }

  Widget _buildSportCamTeamRow({
    required String teamName,
    required Color teamColor,
    required int score,
    required int setsWon,
    required bool isServing,
    required double scale,
    required bool isTopRow,
  }) {
    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.only(right: 6.0 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Pasek koloru drużyny (szerokość 8 * scale)
          Container(
            width: 8.0 * scale,
            decoration: BoxDecoration(
              color: teamColor,
              borderRadius: BorderRadius.only(
                topLeft: isTopRow ? Radius.circular(10.0 * scale) : Radius.zero,
              ),
            ),
          ),
          SizedBox(width: 10.0 * scale),

          // Nazwa drużyny i wskaźnik serwisu
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    teamName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 16.0 * scale,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                if (showServeIndicator && isServing) ...[
                  SizedBox(width: 6.0 * scale),
                  _buildServeBallIndicator(teamColor, size: 8.5 * scale),
                ],
              ],
            ),
          ),

          // Wskaźniki wygranych setów
          _buildSetsDots(setsWon, teamColor, scale),
          SizedBox(width: 8.0 * scale),

          // Ciemny boks punktowy (#1E2229)
          Container(
            width: 58.0 * scale,
            height: 42.0 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF1E2229),
              borderRadius: BorderRadius.circular(6.0 * scale),
            ),
            alignment: Alignment.center,
            child: _AnimatedScoreDigit(
              score: score,
              color: Colors.white,
              fontSize: 24.0 * scale,
              animate: animate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSportCamFooter(double scale) {
    final footerHeight = 40.0 * scale;
    final displayTime = _formatMatchTime(matchDuration);
    final currentSetLabel = 'SET ${session.currentSetNumber}';
    final rawBanner = activeSpecialEvent;
    final hasBanner = ScoreTimelineEntry.isDisplayableSpecialBanner(rawBanner);

    return Container(
      height: footerHeight,
      padding: EdgeInsets.symmetric(horizontal: 10.0 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(10.0 * scale)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Lewa strona: logo / nazwa aplikacji lub specjalny banner
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: hasBanner
                  ? Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.0 * scale,
                        vertical: 2.0 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(4.0 * scale),
                      ),
                      child: Text(
                        rawBanner!.trim().toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5 * scale,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  : Text(
                      session.sport.shortName.isNotEmpty
                          ? '${session.sport.shortName} LIVE'
                          : 'VOLLEY LIVE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 10.0 * scale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: const Color(0xFF4B5563),
                      ),
                    ),
            ),
          ),

          // Środek: numer seta
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.0 * scale, vertical: 2.0 * scale),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(4.0 * scale),
            ),
            child: Text(
              currentSetLabel,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11.0 * scale,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1F2937),
              ),
            ),
          ),

          // Prawa strona: czas meczu MM:SS ze stałą szerokością cyfr (tabular figures)
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                displayTime,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 11.5 * scale,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetsDots(int setsWon, Color color, double scale) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (idx) {
        final isWon = idx < setsWon;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 1.5 * scale),
          width: 7.0 * scale,
          height: 7.0 * scale,
          decoration: BoxDecoration(
            color: isWon ? color : const Color(0xFFCBD5E1),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }

  // ===========================================================================
  // 2. STYL: CYBER GLOW NEON (Alternatywny styl)
  // ===========================================================================
  Widget _buildCyberGlow(double scale) {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;

    return Container(
      width: 430.0 * scale,
      height: 154.0 * scale,
      padding: EdgeInsets.all(10.0 * scale),
      decoration: BoxDecoration(
        color: const Color(0xEB0A0E17),
        borderRadius: BorderRadius.circular(14.0 * scale),
        border: Border.all(
          color: AppTheme.cyanAccent.withValues(alpha: 0.6),
          width: 1.5 * scale,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.cyanAccent.withValues(alpha: 0.2),
            blurRadius: 16.0 * scale,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                session.teamA.toUpperCase(),
                style: TextStyle(
                  fontSize: 15.0 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (isServingA) _buildServeBallIndicator(session.teamAColor, size: 8 * scale),
              Text(
                '${session.currentSetPointsA}',
                style: TextStyle(
                  fontSize: 26.0 * scale,
                  fontWeight: FontWeight.w900,
                  color: session.teamAColor,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                session.teamB.toUpperCase(),
                style: TextStyle(
                  fontSize: 15.0 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (isServingB) _buildServeBallIndicator(session.teamBColor, size: 8 * scale),
              Text(
                '${session.currentSetPointsB}',
                style: TextStyle(
                  fontSize: 26.0 * scale,
                  fontWeight: FontWeight.w900,
                  color: session.teamBColor,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SET ${session.currentSetNumber} (${session.setsA}:${session.setsB})',
                style: TextStyle(
                  fontSize: 10.0 * scale,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.cyanAccent,
                ),
              ),
              Text(
                _formatMatchTime(matchDuration),
                style: TextStyle(
                  fontSize: 10.0 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. STYL: MINIMALIST
  // ===========================================================================
  Widget _buildMinimalist(double scale) {
    return Container(
      width: 430.0 * scale,
      height: 154.0 * scale,
      padding: EdgeInsets.all(12.0 * scale),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10.0 * scale),
        border: Border.all(color: Colors.white24, width: 1.0 * scale),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                session.teamA.toUpperCase(),
                style: TextStyle(
                  fontSize: 16.0 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '${session.currentSetPointsA}',
                style: TextStyle(
                  fontSize: 26.0 * scale,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                session.teamB.toUpperCase(),
                style: TextStyle(
                  fontSize: 16.0 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '${session.currentSetPointsB}',
                style: TextStyle(
                  fontSize: 26.0 * scale,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SET ${session.currentSetNumber}',
                style: TextStyle(
                  fontSize: 11.0 * scale,
                  color: Colors.white70,
                ),
              ),
              Text(
                _formatMatchTime(matchDuration),
                style: TextStyle(
                  fontSize: 11.0 * scale,
                  color: Colors.white70,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 4. STYL: BEACH VOLLEY
  // ===========================================================================
  Widget _buildBeachVolley(double scale) {
    return Container(
      width: 430.0 * scale,
      height: 154.0 * scale,
      padding: EdgeInsets.all(10.0 * scale),
      decoration: BoxDecoration(
        color: const Color(0xE61A1409),
        borderRadius: BorderRadius.circular(12.0 * scale),
        border: Border.all(color: const Color(0xFFFACC15), width: 1.5 * scale),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                session.teamA.toUpperCase(),
                style: TextStyle(
                  fontSize: 15.0 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '${session.currentSetPointsA}',
                style: TextStyle(
                  fontSize: 24.0 * scale,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFFACC15),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                session.teamB.toUpperCase(),
                style: TextStyle(
                  fontSize: 15.0 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '${session.currentSetPointsB}',
                style: TextStyle(
                  fontSize: 24.0 * scale,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFFACC15),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BEACH SET ${session.currentSetNumber}',
                style: TextStyle(
                  fontSize: 10.0 * scale,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFACC15),
                ),
              ),
              Text(
                _formatMatchTime(matchDuration),
                style: TextStyle(
                  fontSize: 10.0 * scale,
                  color: Colors.white70,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // POMOCNICZE WIDGETY
  // ===========================================================================
  Widget _buildServeBallIndicator(Color color, {double size = 8}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.8),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// Widget animujący cyfry punktacji (slide transition)
class _AnimatedScoreDigit extends StatelessWidget {
  final int score;
  final Color color;
  final double fontSize;
  final bool animate;

  const _AnimatedScoreDigit({
    required this.score,
    required this.color,
    required this.fontSize,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      '$score',
      key: ValueKey<int>(score),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        color: color,
        height: 1.0,
      ),
    );

    if (!animate) {
      return textWidget;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (Widget child, Animation<double> animation) {
        final inAnimation = Tween<Offset>(
          begin: const Offset(0.0, -0.4),
          end: Offset.zero,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: inAnimation,
            child: child,
          ),
        );
      },
      child: textWidget,
    );
  }
}
