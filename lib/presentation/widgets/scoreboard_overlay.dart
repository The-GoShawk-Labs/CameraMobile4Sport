import 'package:flutter/material.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/streaming_config.dart';

class ScoreboardOverlay extends StatelessWidget {
  final MatchSession session;
  final ScoreboardThemeStyle style;
  final bool isTimeoutActive;
  final int timeoutSeconds;
  final ServingTeam timeoutTeam;
  final bool showServeIndicator;
  final String? activeSpecialEvent; // np. 'ACE!', 'CHALLENGE'

  const ScoreboardOverlay({
    super.key,
    required this.session,
    this.style = ScoreboardThemeStyle.tvProBroadcast,
    this.isTimeoutActive = false,
    this.timeoutSeconds = 0,
    this.timeoutTeam = ServingTeam.none,
    this.showServeIndicator = true,
    this.activeSpecialEvent,
  });

  bool get _isDecidingSet {
    // 5. set w siatkówce halowej lub 3. set w plażowej / best-of-3
    return session.currentSetNumber >= 5 || (session.setsA == 1 && session.setsB == 1 && session.currentSetNumber == 3);
  }

  int get _targetPoints {
    if (style == ScoreboardThemeStyle.beachVolley) {
      return session.currentSetNumber >= 3 ? 15 : 21;
    }
    return _isDecidingSet ? 15 : 25;
  }

  bool _isSetPoint(int points, int oppPoints) {
    final target = _targetPoints;
    return points >= (target - 1) && (points - oppPoints) >= 1;
  }

  bool get _isSetPointA => _isSetPoint(session.currentSetPointsA, session.currentSetPointsB) && !session.isMatchOver;
  bool get _isSetPointB => _isSetPoint(session.currentSetPointsB, session.currentSetPointsA) && !session.isMatchOver;

  bool get _isMatchPointA => _isSetPointA && (session.setsA == 2 || (_isDecidingSet && session.setsA == session.setsB));
  bool get _isMatchPointB => _isSetPointB && (session.setsB == 2 || (_isDecidingSet && session.setsA == session.setsB));

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // GŁÓWNY WIDGET SCOREBOARDU W ZALEŻNOŚCI OD WYBRANEGO STYLU
          _buildScoreboardBody(context),

          // DYNAMICZNY BANER ZDARZEŃ (SET POINT / MATCH POINT / TIMEOUT / SPECIAL)
          _buildDynamicEventBanner(),
        ],
      ),
    );
  }

  Widget _buildScoreboardBody(BuildContext context) {
    switch (style) {
      case ScoreboardThemeStyle.tvProBroadcast:
        return _buildTvProBroadcast();
      case ScoreboardThemeStyle.cyberGlow:
        return _buildCyberGlow();
      case ScoreboardThemeStyle.minimalist:
        return _buildMinimalist();
      case ScoreboardThemeStyle.beachVolley:
        return _buildBeachVolley();
    }
  }

  // ===========================================================================
  // 1. STYL: TV PRO BROADCAST (Telewizyjna belka transmisyjna)
  // ===========================================================================
  Widget _buildTvProBroadcast() {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xF00D111A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E3A52), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // TEAM A: KOLOROWY PASEK AKCENTU
          Container(
            width: 5,
            decoration: BoxDecoration(
              color: session.teamAColor,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
            ),
          ),

          // TEAM A: NAZWA I SERWIS
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isServingA) ...[
                  _buildServeBallIndicator(session.teamAColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  session.teamA.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // TEAM A: WYNIK SETÓW (KROPKI / CYFRA)
          _buildSetsBadge(session.setsA, session.teamAColor),

          // TEAM A: WYNIK PUNKTÓW
          Container(
            width: 44,
            height: double.infinity,
            color: const Color(0xFF151C28),
            alignment: Alignment.center,
            child: _AnimatedScoreDigit(
              score: session.currentSetPointsA,
              color: session.teamAColor,
              fontSize: 22,
            ),
          ),

          // SEKCJA ŚRODKOWA: OKRES / SET & WYNIKI
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF090C12),
              border: Border.symmetric(
                vertical: BorderSide(color: Color(0xFF1F293D), width: 1),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  session.periodDisplay,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: Colors.white70,
                  ),
                ),
                if (session.sport == MatchSport.volleyball || session.sport == MatchSport.beachVolleyball)
                  Text(
                    '${session.setsA}-${session.setsB}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.amberAccent,
                    ),
                  )
                else if (session.foulsA > 0 || session.foulsB > 0)
                  Text(
                    'F: ${session.foulsA}-${session.foulsB}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.redLive,
                    ),
                  ),
              ],
            ),
          ),

          // TEAM B: WYNIK PUNKTÓW
          Container(
            width: 44,
            height: double.infinity,
            color: const Color(0xFF151C28),
            alignment: Alignment.center,
            child: _AnimatedScoreDigit(
              score: session.currentSetPointsB,
              color: session.teamBColor,
              fontSize: 22,
            ),
          ),

          // TEAM B: WYNIK SETÓW
          _buildSetsBadge(session.setsB, session.teamBColor),

          // TEAM B: NAZWA I SERWIS
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.teamB.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
                if (isServingB) ...[
                  const SizedBox(width: 6),
                  _buildServeBallIndicator(session.teamBColor),
                ],
              ],
            ),
          ),

          // TEAM B: KOLOROWY PASEK AKCENTU
          Container(
            width: 5,
            decoration: BoxDecoration(
              color: session.teamBColor,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. STYL: CYBER GLOW NEON (Nowoczesny esportowy styl glassmorphism)
  // ===========================================================================
  Widget _buildCyberGlow() {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xEB0A0E17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.cyanAccent.withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
          const BoxShadow(
            color: Colors.black87,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // NAZWY DRUŻYN
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  session.teamA.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'SET ${session.currentSetNumber}',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: Text(
                  session.teamB.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // PUNKTY I SETY
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // TEAM A KAFELEK
              Container(
                width: 88,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1A28),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isServingA ? session.teamAColor : const Color(0xFF1E334D),
                    width: 1.5,
                  ),
                  boxShadow: [
                    if (isServingA)
                      BoxShadow(
                        color: session.teamAColor.withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isServingA) ...[
                      _buildServeBallIndicator(session.teamAColor),
                      const SizedBox(width: 6),
                    ],
                    _AnimatedScoreDigit(
                      score: session.currentSetPointsA,
                      color: session.teamAColor,
                      fontSize: 26,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // SET SCORE ŚRODEK
              SizedBox(
                width: 50,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${session.setsA} : ${session.setsB}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const Text(
                      'SETS',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // TEAM B KAFELEK
              Container(
                width: 88,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF221A0F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isServingB ? session.teamBColor : const Color(0xFF4A3816),
                    width: 1.5,
                  ),
                  boxShadow: [
                    if (isServingB)
                      BoxShadow(
                        color: session.teamBColor.withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _AnimatedScoreDigit(
                      score: session.currentSetPointsB,
                      color: session.teamBColor,
                      fontSize: 26,
                    ),
                    if (isServingB) ...[
                      const SizedBox(width: 6),
                      _buildServeBallIndicator(session.teamBColor),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. STYL: MINIMALIST CLEAN (Dyskretna pigułka narożna)
  // ===========================================================================
  Widget _buildMinimalist() {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xD90A0D14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24, width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // TEAM A
          if (isServingA) ...[
            _buildServeBallIndicator(session.teamAColor, size: 6),
            const SizedBox(width: 4),
          ],
          Text(
            session.teamA.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: session.teamAColor,
            ),
          ),
          const SizedBox(width: 6),
          _AnimatedScoreDigit(
            score: session.currentSetPointsA,
            color: Colors.white,
            fontSize: 16,
          ),

          // ROZDZIELACZ & SETY
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '(${session.setsA}-${session.setsB})',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54),
            ),
          ),

          // TEAM B
          _AnimatedScoreDigit(
            score: session.currentSetPointsB,
            color: Colors.white,
            fontSize: 16,
          ),
          const SizedBox(width: 6),
          Text(
            session.teamB.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: session.teamBColor,
            ),
          ),
          if (isServingB) ...[
            const SizedBox(width: 4),
            _buildServeBallIndicator(session.teamBColor, size: 6),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // 4. STYL: BEACH VOLLEY 2V2 (Siatkówka Plażowa z historią setów)
  // ===========================================================================
  Widget _buildBeachVolley() {
    final isServingA = showServeIndicator && session.currentServer == ServingTeam.teamA;
    final isServingB = showServeIndicator && session.currentServer == ServingTeam.teamB;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xEE161F2E), Color(0xEE0B1019)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.5), width: 1.2),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // NAGŁÓWEK BEACH VOLLEY
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wb_sunny_rounded, color: Color(0xFFFFD54F), size: 12),
              const SizedBox(width: 4),
              const Text(
                'BEACH VOLLEYBALL',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFFD54F),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'SET ${session.currentSetNumber} (to $_targetPoints)',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // WYNIKI I DRUŻYNY
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // TEAM A
              SizedBox(
                width: 75,
                child: Row(
                  children: [
                    if (isServingA) ...[
                      _buildServeBallIndicator(const Color(0xFFFFD54F)),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        session.teamA.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

              // PUNKTY A
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _AnimatedScoreDigit(
                  score: session.currentSetPointsA,
                  color: const Color(0xFFFFD54F),
                  fontSize: 18,
                ),
              ),

              // SETS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${session.setsA} : ${session.setsB}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),

              // PUNKTY B
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _AnimatedScoreDigit(
                  score: session.currentSetPointsB,
                  color: const Color(0xFF00E5FF),
                  fontSize: 18,
                ),
              ),

              // TEAM B
              SizedBox(
                width: 75,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.teamB.toUpperCase(),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                    if (isServingB) ...[
                      const SizedBox(width: 4),
                      _buildServeBallIndicator(const Color(0xFF00E5FF)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // DYNAMICZNY BANER ZDARZEŃ (SET POINT / MATCH POINT / TIMEOUT / SPECIAL)
  // ===========================================================================
  Widget _buildDynamicEventBanner() {
    // 1. Przerwa na żądanie (Timeout)
    if (isTimeoutActive) {
      final teamName = timeoutTeam == ServingTeam.teamA ? session.teamA : session.teamB;
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xF0FFAB00),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Color(0x80FFAB00), blurRadius: 10, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_bottom_rounded, color: Colors.black, size: 14),
            const SizedBox(width: 5),
            Text(
              'TIMEOUT ${timeoutSeconds}s: ${teamName.toUpperCase()}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    // 2. Aktywne zdarzenie specjalne (np. Ace / Challenge)
    if (activeSpecialEvent != null && activeSpecialEvent!.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.purpleAccent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.purpleAccent.withValues(alpha: 0.6),
              blurRadius: 12,
            ),
          ],
        ),
        child: Text(
          activeSpecialEvent!.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
      );
    }

    // 3. Piłka Meczowa (Match Point)
    if (_isMatchPointA || _isMatchPointB) {
      final team = _isMatchPointA ? session.teamA : session.teamB;
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF1744), Color(0xFFFF5252)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Color(0x99FF1744), blurRadius: 12, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_volleyball, color: Colors.white, size: 13),
            const SizedBox(width: 5),
            Text(
              '🔥 MATCH POINT: ${team.toUpperCase()}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      );
    }

    // 4. Piłka Setowa (Set Point)
    if (_isSetPointA || _isSetPointB) {
      final team = _isSetPointA ? session.teamA : session.teamB;
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF9100), Color(0xFFFFB74D)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Color(0x66FF9100), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Text(
          '⚡ SET POINT: ${team.toUpperCase()}',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            letterSpacing: 0.6,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
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

  Widget _buildSetsBadge(int sets, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (idx) {
          final isWon = idx < sets;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: isWon ? color : Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

/// Widget animujący cyfry punktacji (slide transition)
class _AnimatedScoreDigit extends StatelessWidget {
  final int score;
  final Color color;
  final double fontSize;

  const _AnimatedScoreDigit({
    required this.score,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
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
      child: Text(
        '$score',
        key: ValueKey<int>(score),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: color,
          height: 1.0,
        ),
      ),
    );
  }
}
