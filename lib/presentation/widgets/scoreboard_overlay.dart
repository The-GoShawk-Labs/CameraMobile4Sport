import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
/// 3. Kompaktowy, nisko-profilowy układ telewizyjny (~4.74:1, 360 x 76 dp bazowo).
/// 4. Ochronę przed jankiem UI i zbędnymi przerysowaniami (RepaintBoundary).
class ScoreboardOverlay extends StatelessWidget {
  static const double baseWidth = 360.0;
  static const double baseHeight = 76.0;

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
  final bool useThreeLetterAcronyms;

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
    this.useThreeLetterAcronyms = false,
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
    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
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
              : baseWidth;
          final rawScale = customScale ?? (baseW / baseWidth);
          final scale = (rawScale.isFinite && rawScale > 0 ? rawScale : 1.0)
              .clamp(0.1, 2.5);
          return RepaintBoundary(
            child: SizedBox(
              width: baseWidth * scale,
              height: baseHeight * scale,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: baseWidth,
                  height: baseHeight,
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
        final isParentPortrait = parentH > parentW;
        
        // Automatyczne dopasowanie do orientacji kontenera (9:16 w pionie, 16:9 w poziomie)
        final effectiveAspect = (targetAspectRatio.isFinite && targetAspectRatio > 0)
            ? (targetAspectRatio == 16.0 / 9.0 && isParentPortrait
                ? (9.0 / 16.0)
                : targetAspectRatio)
            : (isParentPortrait ? (9.0 / 16.0) : (16.0 / 9.0));
        final safeAspect = effectiveAspect;
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

        // Dla strumienia poziomego (16:9) oraz pionowego (9:16) stosujemy powiększoną skalę telewizyjną,
        // aby tablica wyników była wyraźna i czytelna na ekranach smartfonów oraz w transmisji.
        final isCompact3Letter =
            style == ScoreboardThemeStyle.broadcastCompact3Letter;
        final effectiveBaseWidth = isCompact3Letter ? 220.0 : baseWidth;
        final referenceStreamWidth = isCompact3Letter
            ? (isPortraitVideo ? 520.0 : 880.0)
            : (isPortraitVideo ? 680.0 : 1120.0);
        final rawScale = customScale ?? (videoW / referenceStreamWidth);
        final scale = (rawScale.isFinite && rawScale > 0 ? rawScale : 0.5)
            .clamp(0.15, 2.5);
        final minCardFraction = isCompact3Letter
            ? (isPortraitVideo ? 0.38 : 0.24)
            : (isPortraitVideo ? 0.50 : 0.30);
        final cardW = (effectiveBaseWidth * scale).clamp(
          videoW * minCardFraction,
          videoW * 0.92,
        );
        final cardH = cardW * (baseHeight / effectiveBaseWidth);

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
                    width: effectiveBaseWidth,
                    height: baseHeight,
                    child: _buildScoreboardCard(context, 1.0),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      ),
    );
  }

  Widget _buildScoreboardCard(BuildContext context, double scale) {
    switch (style) {
      case ScoreboardThemeStyle.broadcastCompact3Letter:
        return _buildBroadcastCompact3Letter(scale);
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
  // STYL: BROADCAST PRO COMPACT (3-LETTER / TRIGRAM)
  // Modularny układ TV wzorowany na profesjonalnej grafice siatkarskiej (PlusLiga / CEV / FIVB)
  // ===========================================================================
  Widget _buildBroadcastCompact3Letter(double scale) {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;
    final rawBanner = activeSpecialEvent;
    final hasBanner = ScoreTimelineEntry.isDisplayableSpecialBanner(rawBanner);
    final displayClock = _formatMatchTime(matchDuration);

    final teamACode = session.teamAShortCode;
    final teamBCode = session.teamBShortCode;

    // Sztywna, zwarta siatka (rigid column widths: 28 + 5 + 85 + 44 + 58 = 220 dp)
    final wLeague = 28.0 * scale;
    final wStrip = 5.0 * scale;
    final wTla = 85.0 * scale;
    final wSets = 44.0 * scale;
    final wPts = 58.0 * scale;
    final totalWidth = wLeague + wStrip + wTla + wSets + wPts; // 220.0 * scale
    final rowHeight = 27.0 * scale;
    final bannerHeight = 21.0 * scale;
    final alignment = switch (anchorPosition) {
      ScoreboardAnchorPosition.topRight ||
      ScoreboardAnchorPosition.bottomRight => Alignment.topRight,
      ScoreboardAnchorPosition.topCenter ||
      ScoreboardAnchorPosition.bottomCenter => Alignment.topCenter,
      ScoreboardAnchorPosition.topLeft ||
      ScoreboardAnchorPosition.bottomLeft => Alignment.topLeft,
    };

    return Container(
      width: (isStandaloneCard ? baseWidth : 220.0) * scale,
      height: baseHeight * scale,
      color: Colors.transparent,
      alignment: alignment,
      child: Container(
        width: totalWidth,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5.0 * scale),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 6.0 * scale,
              offset: Offset(0, 2.0 * scale),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. ZWARTY BLOK WYNIKOWY (2 WIERSZE: GOSPODARZE I GOŚCIE)
            SizedBox(
              height: rowHeight * 2,
              child: Row(
                children: [
                  // BLOK LIGI / LOGO (PIONOWY BADGE TURNIEJOWY)
                  Container(
                    width: wLeague,
                    color: const Color(0xFF090D16),
                    alignment: Alignment.center,
                    child: Text(
                      'L\nI\nG\nA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 7.5 * scale,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.cyanAccent,
                        height: 1.05,
                      ),
                    ),
                  ),

                  // GŁÓWNA TABELA WIERSZY (GOSPODARZE I GOŚCIE)
                  Expanded(
                    child: Column(
                      children: [
                        // WIERSZ 1 - GOSPODARZ
                        SizedBox(
                          height: rowHeight,
                          child: Row(
                            children: [
                              // Pasek koloru drużyny A
                              Container(
                                width: wStrip,
                                color: session.teamAColor,
                              ),
                              // Trzyliterowy kod drużyny A (TLA)
                              Container(
                                width: wTla,
                                color: Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: 2.0 * scale),
                                alignment: Alignment.center,
                                child: Text(
                                  teamACode,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 15.0 * scale,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                    height: 1.1,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              // Wygrane sety gospodarzy (#1A1E2E)
                              Container(
                                width: wSets,
                                color: const Color(0xFF1A1E2E),
                                alignment: Alignment.center,
                                child: Text(
                                  '${session.setsA}',
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 15.0 * scale,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              // Punkty w secie gospodarzy (#E6007E) + zwarty wskaźnik zagrywki
                              Container(
                                width: wPts,
                                color: const Color(0xFFE6007E),
                                alignment: Alignment.center,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Text(
                                      '${session.currentSetPointsA}',
                                      style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 18.0 * scale,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        height: 1.1,
                                      ),
                                    ),
                                    if (isServingA)
                                      Positioned(
                                        right: 3.0 * scale,
                                        child: Container(
                                          width: 4.5 * scale,
                                          height: 4.5 * scale,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Poziomy separator
                        Container(height: 1.0 * scale, color: const Color(0xFF334155)),

                        // WIERSZ 2 - GOŚĆ
                        SizedBox(
                          height: rowHeight - (1.0 * scale),
                          child: Row(
                            children: [
                              // Pasek koloru drużyny B
                              Container(
                                width: wStrip,
                                color: session.teamBColor,
                              ),
                              // Trzyliterowy kod drużyny B (TLA)
                              Container(
                                width: wTla,
                                color: Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: 2.0 * scale),
                                alignment: Alignment.center,
                                child: Text(
                                  teamBCode,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 15.0 * scale,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                    height: 1.1,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              // Wygrane sety gości (#1A1E2E)
                              Container(
                                width: wSets,
                                color: const Color(0xFF1A1E2E),
                                alignment: Alignment.center,
                                child: Text(
                                  '${session.setsB}',
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 15.0 * scale,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              // Punkty w secie gości (#E6007E) + zwarty wskaźnik zagrywki
                              Container(
                                width: wPts,
                                color: const Color(0xFFE6007E),
                                alignment: Alignment.center,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Text(
                                      '${session.currentSetPointsB}',
                                      style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 18.0 * scale,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        height: 1.1,
                                      ),
                                    ),
                                    if (isServingB)
                                      Positioned(
                                        right: 3.0 * scale,
                                        child: Container(
                                          width: 4.5 * scale,
                                          height: 4.5 * scale,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. PRZYLEGAJĄCY BANER AKCJI / KOMUNIKATU (BEZ SZPAR I LUZÓW)
            Container(
              height: bannerHeight,
              padding: EdgeInsets.symmetric(horizontal: 4.0 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E17),
                border: Border(
                  top: BorderSide(
                    color: hasBanner ? const Color(0xFFE6007E) : const Color(0xFF334155),
                    width: 1.0 * scale,
                  ),
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasBanner) ...[
                    Container(
                      width: 4.0 * scale,
                      height: 4.0 * scale,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE6007E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 4.0 * scale),
                  ],
                  Flexible(
                    child: Text(
                      hasBanner
                          ? rawBanner!.trim().toUpperCase()
                          : (displayClock != '00:00'
                              ? 'SET ${session.currentSetNumber}  •  $displayClock'
                              : (session.tournamentName?.isNotEmpty == true
                                  ? session.tournamentName!.toUpperCase()
                                  : 'SET ${session.currentSetNumber}  •  LIVE')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: (hasBanner ? 9.0 : 8.5) * scale,
                        fontWeight: FontWeight.w800,
                        color: hasBanner ? Colors.white : Colors.white70,
                        height: 1.1,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. STYL SPORTCAM TV PRO BROADCAST (Kompaktowa karta telewizyjna ~4.74:1)
  // ===========================================================================
  Widget _buildSportCamTvBroadcast(double scale) {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;

    return Container(
      width: baseWidth * scale,
      height: baseHeight * scale,
      decoration: BoxDecoration(
        color: const Color(0xF8F8FAFC), // 97% opacity Slate-50 broadcast white
        borderRadius: BorderRadius.circular(6.0 * scale),
        border: Border.all(
          color: const Color(0xFFCBD5E1),
          width: 1.0 * scale,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 8.0 * scale,
            offset: Offset(0, 2.0 * scale),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6.0 * scale),
        child: Column(
          children: [
            // WIERSZ 1: GOSPODARZE (TEAM A)
            Expanded(
              child: _buildSportCamTeamRow(
                teamName: useThreeLetterAcronyms ? session.teamAShortCode : session.teamA,
                isShortName: useThreeLetterAcronyms,
                teamColor: session.teamAColor,
                score: session.currentSetPointsA,
                setsWon: session.setsA,
                isServing: isServingA,
                scale: scale,
                isTopRow: true,
              ),
            ),

            // SUBTELNY SEPARATOR
            Container(height: 1.0 * scale, color: const Color(0xFFE2E8F0)),

            // WIERSZ 2: GOŚCIE (TEAM B)
            Expanded(
              child: _buildSportCamTeamRow(
                teamName: useThreeLetterAcronyms ? session.teamBShortCode : session.teamB,
                isShortName: useThreeLetterAcronyms,
                teamColor: session.teamBColor,
                score: session.currentSetPointsB,
                setsWon: session.setsB,
                isServing: isServingB,
                scale: scale,
                isTopRow: false,
              ),
            ),

            // WIERSZ 3: DOLNY PASEK STATUSU / FOOTER
            _buildSportCamFooter(scale),
          ],
        ),
      ),
    );
  }

  Widget _buildSportCamTeamRow({
    required String teamName,
    bool isShortName = false,
    required Color teamColor,
    required int score,
    required int setsWon,
    required bool isServing,
    required double scale,
    required bool isTopRow,
  }) {
    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.only(right: 5.0 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Pasek koloru drużyny
          Container(
            width: 5.0 * scale,
            decoration: BoxDecoration(
              color: teamColor,
              borderRadius: BorderRadius.only(
                topLeft: isTopRow ? Radius.circular(6.0 * scale) : Radius.zero,
              ),
            ),
          ),
          SizedBox(width: 6.0 * scale),

          // Nazwa drużyny (lub 3-literowy skrót) i wskaźnik serwisu
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
                      fontSize: (isShortName ? 15.0 : 13.0) * scale,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: isShortName ? 0.6 : 0.3,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
                if (showServeIndicator && isServing) ...[
                  SizedBox(width: 5.0 * scale),
                  _buildServeBallIndicator(teamColor, size: 7.0 * scale),
                ],
              ],
            ),
          ),

          // Wskaźniki wygranych setów (pionowe kreski)
          _buildSetsTallyBars(setsWon, teamColor, scale),
          SizedBox(width: 5.0 * scale),

          // DEDYKOWANY CIEMNY BOKS WYGRANYCH SETÓW (#1E293B)
          Container(
            width: 26.0 * scale,
            height: 22.0 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(4.0 * scale),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SET',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 6.5 * scale,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                      color: const Color(0xFF94A3B8),
                      height: 1.0,
                    ),
                  ),
                  SizedBox(height: 0.5 * scale),
                  Text(
                    '$setsWon',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 11.5 * scale,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 4.0 * scale),

          // WYSOKOKONTRASTOWY JASNY BOKS PUNKTOWY
          Container(
            width: 40.0 * scale,
            height: 21.0 * scale,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4.0 * scale),
              border: Border.all(
                color: const Color(0xFFCBD5E1),
                width: 1.0 * scale,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 3.0 * scale,
                  offset: Offset(0, 1.0 * scale),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: _AnimatedScoreDigit(
              score: score,
              color: const Color(0xFF0F172A),
              fontSize: 17.0 * scale,
              animate: animate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSportCamFooter(double scale) {
    final footerHeight = 21.0 * scale;
    final displayTime = _formatMatchTime(matchDuration);
    final currentSetLabel = session.currentSetNumber >= 5
        ? 'SET 5 • TB'
        : 'SET ${session.currentSetNumber}';
    final rawBanner = activeSpecialEvent;
    final hasBanner = ScoreTimelineEntry.isDisplayableSpecialBanner(rawBanner);

    return Container(
      height: footerHeight,
      padding: EdgeInsets.symmetric(horizontal: 6.0 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(6.0 * scale)),
        border: Border(
          top: BorderSide(color: const Color(0xFFCBD5E1), width: 1.0 * scale),
        ),
      ),
      child: Row(
        children: [
          // STREFA 1 (LEWA, STAŁA SZEROKOŚĆ ~105px): BRANDING LUB BANER SPECJALNY
          SizedBox(
            width: 105.0 * scale,
            child: Align(
              alignment: Alignment.centerLeft,
              child: hasBanner
                  ? Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 5.0 * scale,
                        vertical: 2.0 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(3.0 * scale),
                      ),
                      child: Text(
                        rawBanner!.trim().toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8.5 * scale,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.1,
                          letterSpacing: 0.3,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2.5 * scale),
                          child: SvgPicture.asset(
                            'assets/icons/app_icon.svg',
                            width: 11.0 * scale,
                            height: 11.0 * scale,
                          ),
                        ),
                        SizedBox(width: 3.0 * scale),
                        Flexible(
                          child: Text(
                            session.sport.shortName.isNotEmpty
                                ? '${session.sport.shortName} • GOGOSHAWK'
                                : 'GOGOSHAWK LIVE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 8.5 * scale,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF334155),
                              height: 1.15,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          // STREFA 2 (ŚRODEK): NUMER SETA W BIAŁEJ KAPSULE
          Expanded(
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 6.0 * scale,
                  vertical: 1.5 * scale,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4.0 * scale),
                  border: Border.all(
                    color: const Color(0xFFCBD5E1),
                    width: 0.8 * scale,
                  ),
                ),
                child: Text(
                  currentSetLabel,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 9.5 * scale,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),

          // STREFA 3 (PRAWA, STAŁA SZEROKOŚĆ ~80px): CZAS MECZU W KAPSULE
          SizedBox(
            width: 80.0 * scale,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 5.0 * scale,
                  vertical: 1.5 * scale,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4.0 * scale),
                  border: Border.all(
                    color: const Color(0xFFCBD5E1),
                    width: 0.8 * scale,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 10.0 * scale,
                      color: const Color(0xFF0F172A),
                    ),
                    SizedBox(width: 3.0 * scale),
                    Text(
                      displayTime,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 9.5 * scale,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        height: 1.1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Wskaźnik wygranych setów w postaci pionowych kresek (Tally Bars)
  Widget _buildSetsTallyBars(int setsWon, Color color, double scale) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (idx) {
        final isWon = idx < setsWon;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 1.0 * scale),
          width: 3.0 * scale,
          height: 13.0 * scale,
          decoration: BoxDecoration(
            color: isWon ? color : const Color(0xFFCBD5E1),
            borderRadius: BorderRadius.circular(1.5 * scale),
            border: Border.all(
              color: isWon ? color.withValues(alpha: 0.8) : const Color(0xFF94A3B8),
              width: 0.5 * scale,
            ),
          ),
        );
      }),
    );
  }

  // ===========================================================================
  // 2. STYL: CYBER GLOW NEON (Kompaktowa karta neonowa ~4.74:1)
  // ===========================================================================
  Widget _buildCyberGlow(double scale) {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;
    final rawBanner = activeSpecialEvent;
    final hasBanner = ScoreTimelineEntry.isDisplayableSpecialBanner(rawBanner);
    final displayClock = _formatMatchTime(matchDuration);

    return Container(
      width: baseWidth * scale,
      height: baseHeight * scale,
      padding: EdgeInsets.symmetric(horizontal: 8.0 * scale, vertical: 5.0 * scale),
      decoration: BoxDecoration(
        color: const Color(0xEB0A0E17),
        borderRadius: BorderRadius.circular(8.0 * scale),
        border: Border.all(
          color: AppTheme.cyanAccent.withValues(alpha: 0.6),
          width: 1.2 * scale,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.cyanAccent.withValues(alpha: 0.2),
            blurRadius: 8.0 * scale,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        session.teamA.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.0 * scale,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isServingA) ...[
                      SizedBox(width: 4.0 * scale),
                      _buildServeBallIndicator(session.teamAColor, size: 7.0 * scale),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 5.0 * scale, vertical: 1.0 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0x3300E5FF),
                      borderRadius: BorderRadius.circular(3.0 * scale),
                    ),
                    child: Text(
                      '${session.setsA}',
                      style: TextStyle(
                        fontSize: 10.0 * scale,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.cyanAccent,
                        height: 1.1,
                      ),
                    ),
                  ),
                  SizedBox(width: 6.0 * scale),
                  Text(
                    '${session.currentSetPointsA}',
                    style: TextStyle(
                      fontSize: 17.0 * scale,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: session.teamAColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        session.teamB.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.0 * scale,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isServingB) ...[
                      SizedBox(width: 4.0 * scale),
                      _buildServeBallIndicator(session.teamBColor, size: 7.0 * scale),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 5.0 * scale, vertical: 1.0 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0x3300E5FF),
                      borderRadius: BorderRadius.circular(3.0 * scale),
                    ),
                    child: Text(
                      '${session.setsB}',
                      style: TextStyle(
                        fontSize: 10.0 * scale,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.cyanAccent,
                        height: 1.1,
                      ),
                    ),
                  ),
                  SizedBox(width: 6.0 * scale),
                  Text(
                    '${session.currentSetPointsB}',
                    style: TextStyle(
                      fontSize: 17.0 * scale,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: session.teamBColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  hasBanner
                      ? rawBanner!.trim().toUpperCase()
                      : 'SET ${session.currentSetNumber} (${session.setsA}:${session.setsB})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5 * scale,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: hasBanner ? const Color(0xFFEF4444) : AppTheme.cyanAccent,
                  ),
                ),
              ),
              Text(
                displayClock,
                style: TextStyle(
                  fontSize: 9.5 * scale,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
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
  // 3. STYL: MINIMALIST (Classic Dark ~4.74:1)
  // ===========================================================================
  Widget _buildMinimalist(double scale) {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;
    final rawBanner = activeSpecialEvent;
    final hasBanner = ScoreTimelineEntry.isDisplayableSpecialBanner(rawBanner);
    final displayClock = _formatMatchTime(matchDuration);

    return Container(
      width: baseWidth * scale,
      height: baseHeight * scale,
      padding: EdgeInsets.symmetric(horizontal: 8.0 * scale, vertical: 5.0 * scale),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(6.0 * scale),
        border: Border.all(color: Colors.white24, width: 1.0 * scale),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        session.teamA.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.0 * scale,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isServingA) ...[
                      SizedBox(width: 4.0 * scale),
                      _buildServeBallIndicator(session.teamAColor, size: 7.0 * scale),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 5.0 * scale, vertical: 1.0 * scale),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(3.0 * scale),
                    ),
                    child: Text(
                      '${session.setsA}',
                      style: TextStyle(
                        fontSize: 10.0 * scale,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                        height: 1.1,
                      ),
                    ),
                  ),
                  SizedBox(width: 6.0 * scale),
                  Text(
                    '${session.currentSetPointsA}',
                    style: TextStyle(
                      fontSize: 17.0 * scale,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        session.teamB.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.0 * scale,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isServingB) ...[
                      SizedBox(width: 4.0 * scale),
                      _buildServeBallIndicator(session.teamBColor, size: 7.0 * scale),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 5.0 * scale, vertical: 1.0 * scale),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(3.0 * scale),
                    ),
                    child: Text(
                      '${session.setsB}',
                      style: TextStyle(
                        fontSize: 10.0 * scale,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                        height: 1.1,
                      ),
                    ),
                  ),
                  SizedBox(width: 6.0 * scale),
                  Text(
                    '${session.currentSetPointsB}',
                    style: TextStyle(
                      fontSize: 17.0 * scale,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  hasBanner
                      ? rawBanner!.trim().toUpperCase()
                      : 'SET ${session.currentSetNumber} (${session.setsA}:${session.setsB})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5 * scale,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: hasBanner ? const Color(0xFFEF4444) : Colors.white70,
                  ),
                ),
              ),
              Text(
                displayClock,
                style: TextStyle(
                  fontSize: 9.5 * scale,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
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
  // 4. STYL: BEACH VOLLEY (~4.74:1)
  // ===========================================================================
  Widget _buildBeachVolley(double scale) {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;
    final rawBanner = activeSpecialEvent;
    final hasBanner = ScoreTimelineEntry.isDisplayableSpecialBanner(rawBanner);
    final displayClock = _formatMatchTime(matchDuration);

    return Container(
      width: baseWidth * scale,
      height: baseHeight * scale,
      padding: EdgeInsets.symmetric(horizontal: 8.0 * scale, vertical: 5.0 * scale),
      decoration: BoxDecoration(
        color: const Color(0xE61A1409),
        borderRadius: BorderRadius.circular(6.0 * scale),
        border: Border.all(color: const Color(0xFFFACC15), width: 1.2 * scale),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        session.teamA.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.0 * scale,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isServingA) ...[
                      SizedBox(width: 4.0 * scale),
                      _buildServeBallIndicator(session.teamAColor, size: 7.0 * scale),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 5.0 * scale, vertical: 1.0 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0x33FACC15),
                      borderRadius: BorderRadius.circular(3.0 * scale),
                    ),
                    child: Text(
                      '${session.setsA}',
                      style: TextStyle(
                        fontSize: 10.0 * scale,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFFACC15),
                        height: 1.1,
                      ),
                    ),
                  ),
                  SizedBox(width: 6.0 * scale),
                  Text(
                    '${session.currentSetPointsA}',
                    style: TextStyle(
                      fontSize: 17.0 * scale,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: const Color(0xFFFACC15),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        session.teamB.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.0 * scale,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isServingB) ...[
                      SizedBox(width: 4.0 * scale),
                      _buildServeBallIndicator(session.teamBColor, size: 7.0 * scale),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 5.0 * scale, vertical: 1.0 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0x33FACC15),
                      borderRadius: BorderRadius.circular(3.0 * scale),
                    ),
                    child: Text(
                      '${session.setsB}',
                      style: TextStyle(
                        fontSize: 10.0 * scale,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFFACC15),
                        height: 1.1,
                      ),
                    ),
                  ),
                  SizedBox(width: 6.0 * scale),
                  Text(
                    '${session.currentSetPointsB}',
                    style: TextStyle(
                      fontSize: 17.0 * scale,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: const Color(0xFFFACC15),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  hasBanner
                      ? rawBanner!.trim().toUpperCase()
                      : 'BEACH SET ${session.currentSetNumber} (${session.setsA}:${session.setsB})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5 * scale,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: hasBanner ? const Color(0xFFEF4444) : const Color(0xFFFACC15),
                  ),
                ),
              ),
              Text(
                displayClock,
                style: TextStyle(
                  fontSize: 9.5 * scale,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
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
  Widget _buildServeBallIndicator(Color color, {double size = 7.0}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B), // Illuminated Gold #F59E0B
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.7),
            blurRadius: 3,
            spreadRadius: 0.5,
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
        fontWeight: FontWeight.w800,
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
