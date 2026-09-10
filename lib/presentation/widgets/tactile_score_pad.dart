import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/match_session.dart';

class TactileScorePad extends StatelessWidget {
  final MatchSession session;
  final Function(int points) onAddPointA;
  final Function(int points) onAddPointB;
  final VoidCallback onSubtractPointA;
  final VoidCallback onSubtractPointB;
  final VoidCallback onUndo;
  final VoidCallback onToggleRotation;
  final VoidCallback onRequestTimeoutA;
  final VoidCallback onRequestTimeoutB;
  final VoidCallback onRequestSubA;
  final VoidCallback onRequestSubB;
  final VoidCallback onAddFoulA;
  final VoidCallback onAddFoulB;
  final VoidCallback onNextPeriod;
  final Function(String) onSpecialTag;
  final bool canUndo;
  final bool isTimeoutActive;
  final bool isOutdoorMode;

  const TactileScorePad({
    super.key,
    required this.session,
    required this.onAddPointA,
    required this.onAddPointB,
    required this.onSubtractPointA,
    required this.onSubtractPointB,
    required this.onUndo,
    required this.onToggleRotation,
    required this.onRequestTimeoutA,
    required this.onRequestTimeoutB,
    required this.onRequestSubA,
    required this.onRequestSubB,
    required this.onAddFoulA,
    required this.onAddFoulB,
    required this.onNextPeriod,
    required this.onSpecialTag,
    required this.canUndo,
    required this.isTimeoutActive,
    this.isOutdoorMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final isServingA = session.currentServer == ServingTeam.teamA;
    final isServingB = session.currentServer == ServingTeam.teamB;

    final bgColor = isOutdoorMode ? Colors.black : const Color(0xFF0D121F);
    final cardBorderWidth = isOutdoorMode ? 3.0 : 1.8;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: isOutdoorMode ? const Border(top: BorderSide(color: Colors.white, width: 2)) : null,
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // UCHWYT PANELU / GESTURE GUIDE
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isOutdoorMode ? Colors.white70 : Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),

            // GŁÓWNY MODUŁ PUNKTOWY
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // =============================================================
                // LEWY DUŻY PANEL: TEAM A
                // =============================================================
                Expanded(
                  flex: 11,
                  child: Column(
                    children: [
                      // NAZWA I WSKAŹNIK POSIADANIA / SERWU
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isServingA) ...[
                            _buildServeIndicator(session.teamAColor, session.sport.icon),
                            const SizedBox(width: 5),
                          ],
                          Flexible(
                            child: Text(
                              session.teamA.toUpperCase(),
                              style: TextStyle(
                                fontSize: isOutdoorMode ? 14 : 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: isServingA ? session.teamAColor : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),

                      // DUŻY PRZYCISK GESTOWY / MULTI-POINT DECK DLA TEAM A
                      _buildTeamScoreDeck(
                        isTeamA: true,
                        score: session.currentSetPointsA,
                        teamColor: session.teamAColor,
                        isServing: isServingA,
                        borderWidth: cardBorderWidth,
                      ),

                      const SizedBox(height: 6),

                      // WSKAŹNIKI STATUSU DLA TEAM A (TIMEOUTY, FAULE, ZMIANY)
                      _buildTeamStatusRow(
                        isTeamA: true,
                        teamName: session.teamA,
                        timeoutsUsed: session.timeoutsA,
                        foulsUsed: session.foulsA,
                        substitutionsUsed: session.substitutionsA,
                        teamColor: session.teamAColor,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // =============================================================
                // ŚRODEK: CZĘŚĆ GRY + NASTĘPNY OKRES + AKCJA SERWU/POSIADANIA + UNDO
                // =============================================================
                Expanded(
                  flex: 8,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 4),

                      // PIGUŁKA CZĘŚCI GRY (SET / KWARTA / POŁOWA)
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onNextPeriod();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isOutdoorMode ? Colors.white : const Color(0xFF192233),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isOutdoorMode ? Colors.black : Colors.white24,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                session.periodDisplay,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: isOutdoorMode ? Colors.black : Colors.white,
                                ),
                              ),
                              if (session.sport == MatchSport.volleyball || session.sport == MatchSport.beachVolleyball)
                                Text(
                                  '(${session.setsA}:${session.setsB})',
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.amberAccent),
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // PRZYCISK ZMIANY POSIADANIA / ROTACJI
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onToggleRotation();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E170A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.amberAccent, width: 1.2),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.sync_alt_rounded, color: AppTheme.amberAccent, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                session.sport == MatchSport.volleyball ? 'ROTACJA' : 'PIŁKA',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.amberAccent,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // PRZYCISK COFNIJ (UNDO)
                      InkWell(
                        onTap: canUndo
                            ? () {
                                HapticFeedback.mediumImpact();
                                onUndo();
                              }
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: canUndo ? const Color(0xFF261217) : Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: canUndo ? AppTheme.redLive : Colors.white12,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.undo_rounded,
                                color: canUndo ? AppTheme.redLive : Colors.white24,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'UNDO',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: canUndo ? AppTheme.redLive : Colors.white24,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // =============================================================
                // PRAWY DUŻY PANEL: TEAM B
                // =============================================================
                Expanded(
                  flex: 11,
                  child: Column(
                    children: [
                      // NAZWA I WSKAŹNIK POSIADANIA / SERWU
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              session.teamB.toUpperCase(),
                              style: TextStyle(
                                fontSize: isOutdoorMode ? 14 : 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: isServingB ? session.teamBColor : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isServingB) ...[
                            const SizedBox(width: 5),
                            _buildServeIndicator(session.teamBColor, session.sport.icon),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),

                      // DUŻY PRZYCISK GESTOWY / MULTI-POINT DECK DLA TEAM B
                      _buildTeamScoreDeck(
                        isTeamA: false,
                        score: session.currentSetPointsB,
                        teamColor: session.teamBColor,
                        isServing: isServingB,
                        borderWidth: cardBorderWidth,
                      ),

                      const SizedBox(height: 6),

                      // WSKAŹNIKI STATUSU DLA TEAM B (TIMEOUTY, FAULE, ZMIANY)
                      _buildTeamStatusRow(
                        isTeamA: false,
                        teamName: session.teamB,
                        timeoutsUsed: session.timeoutsB,
                        foulsUsed: session.foulsB,
                        substitutionsUsed: session.substitutionsB,
                        teamColor: session.teamBColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // =================================================================
            // PASEK SZYBKICH TAGÓW TRANSMISYJNYCH DLA DANEJ DYSCYPLINY
            // =================================================================
            _buildSportQuickTags(),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // WIDGET KARTY GESTOWEJ I PUNKTOWEJ
  // ===========================================================================
  Widget _buildTeamScoreDeck({
    required bool isTeamA,
    required int score,
    required Color teamColor,
    required bool isServing,
    required double borderWidth,
  }) {
    if (session.sport == MatchSport.basketball) {
      // Dla koszykówki: Duży kafelek wyniku + szybkie przyciski +1, +2, +3, -1
      return Column(
        children: [
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: isOutdoorMode ? const Color(0xFF000000) : const Color(0xFF101726),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isServing ? teamColor : teamColor.withValues(alpha: 0.5),
                width: isServing ? (borderWidth + 1.0) : borderWidth,
              ),
              boxShadow: [
                if (isServing)
                  BoxShadow(
                    color: teamColor.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
              ],
            ),
            child: Center(
              child: Text(
                '$score',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: isOutdoorMode ? Colors.white : teamColor,
                  height: 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _buildMiniPointButton('+1', () => isTeamA ? onAddPointA(1) : onAddPointB(1), teamColor),
              const SizedBox(width: 3),
              _buildMiniPointButton('+2', () => isTeamA ? onAddPointA(2) : onAddPointB(2), teamColor),
              const SizedBox(width: 3),
              _buildMiniPointButton('+3', () => isTeamA ? onAddPointA(3) : onAddPointB(3), teamColor),
              const SizedBox(width: 3),
              _buildMiniPointButton('-1', () => isTeamA ? onSubtractPointA() : onSubtractPointB(), Colors.white38),
            ],
          ),
        ],
      );
    }

    // Standardowy (Siatkówka, Piłka, Uniwersalna): Tap +1, Swipe Down -1
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        isTeamA ? onAddPointA(1) : onAddPointB(1);
      },
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 150) {
          HapticFeedback.mediumImpact();
          isTeamA ? onSubtractPointA() : onSubtractPointB();
        }
      },
      child: Container(
        height: 78,
        decoration: BoxDecoration(
          color: isOutdoorMode ? const Color(0xFF000000) : const Color(0xFF101726),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isServing ? teamColor : teamColor.withValues(alpha: 0.5),
            width: isServing ? (borderWidth + 1.0) : borderWidth,
          ),
          boxShadow: [
            if (isServing)
              BoxShadow(
                color: teamColor.withValues(alpha: 0.35),
                blurRadius: 14,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 4,
              left: 6,
              right: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TAP: +1',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: teamColor.withValues(alpha: 0.8),
                    ),
                  ),
                  const Text(
                    'SWIPE ⬇: -1',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: Text(
                '$score',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: isOutdoorMode ? Colors.white : teamColor,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPointButton(String label, VoidCallback onTap, Color color) {
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: color == Colors.white38 ? Colors.white70 : color,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // WIDGET STANU DRUŻYNY: TIMEOUTY / FAULE / ZMIANY
  // ===========================================================================
  Widget _buildTeamStatusRow({
    required bool isTeamA,
    required String teamName,
    required int timeoutsUsed,
    required int foulsUsed,
    required int substitutionsUsed,
    required Color teamColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // PIGUŁKA TIMEOUTÓW
        InkWell(
          onTap: () {
            if (timeoutsUsed < 5 && !isTimeoutActive) {
              HapticFeedback.selectionClick();
              isTeamA ? onRequestTimeoutA() : onRequestTimeoutB();
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF161E2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('TO: ', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white54)),
                ...List.generate(2, (idx) {
                  final isUsed = idx < timeoutsUsed;
                  return Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: isUsed ? teamColor : Colors.white24,
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        // FAULE (DLA KOSZYKÓWKI I PIŁKI) LUB ZMIANY (DLA SIATKÓWKI)
        if (session.sport == MatchSport.basketball || session.sport == MatchSport.football)
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              isTeamA ? onAddFoulA() : onAddFoulB();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF161E2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                'FAULE: $foulsUsed',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: foulsUsed >= 4 ? AppTheme.redLive : AppTheme.textSecondary,
                ),
              ),
            ),
          )
        else
          InkWell(
            onTap: () {
              if (substitutionsUsed < 6) {
                HapticFeedback.selectionClick();
                isTeamA ? onRequestSubA() : onRequestSubB();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF161E2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                'SUB: $substitutionsUsed/6',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: substitutionsUsed >= 5 ? AppTheme.redLive : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildServeIndicator(Color color, IconData icon) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.8),
            blurRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: Icon(icon, size: 9, color: Colors.black),
      ),
    );
  }

  Widget _buildSportQuickTags() {
    switch (session.sport) {
      case MatchSport.volleyball:
      case MatchSport.beachVolleyball:
        return Row(
          children: [
            _buildQuickTagPill('🔥 AS!', const Color(0xFFFF5252), () {
              HapticFeedback.heavyImpact();
              onSpecialTag('AS SERWISOWY!');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('🛡️ BLOK', const Color(0xFF00E5FF), () {
              HapticFeedback.mediumImpact();
              onSpecialTag('PUNKTOWY BLOK!');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('⚡ ATAK', const Color(0xFFFFAB00), () {
              HapticFeedback.mediumImpact();
              onSpecialTag('SKUTECZNY ATAK!');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('📹 CHALLENGE', const Color(0xFFB388FF), () {
              HapticFeedback.heavyImpact();
              onSpecialTag('WERYFIKACJA WIDEO');
            }),
          ],
        );
      case MatchSport.basketball:
        return Row(
          children: [
            _buildQuickTagPill('🏀 ZA 3 PKT', const Color(0xFFFF9100), () {
              HapticFeedback.heavyImpact();
              onSpecialTag('TRAFIENIE ZA 3 PKT!');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('💥 WSAD', const Color(0xFFFF5252), () {
              HapticFeedback.mediumImpact();
              onSpecialTag('POTĘŻNY WSAD!');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('🛡️ PRZECHWYT', const Color(0xFF00E5FF), () {
              HapticFeedback.mediumImpact();
              onSpecialTag('PRZECHWYT PIŁKI!');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('⏱️ TIMEOUT 60s', const Color(0xFFB388FF), () {
              HapticFeedback.heavyImpact();
              onSpecialTag('PRZERWA TAKTYCZNA 60s');
            }),
          ],
        );
      case MatchSport.football:
        return Row(
          children: [
            _buildQuickTagPill('⚽ GOL!', const Color(0xFF00E676), () {
              HapticFeedback.heavyImpact();
              onSpecialTag('GOOOOL!');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('🟨 KARTKA', const Color(0xFFFFD54F), () {
              HapticFeedback.mediumImpact();
              onSpecialTag('ŻÓŁTA KARTKA');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('🚩 ROŻNY', const Color(0xFF00E5FF), () {
              HapticFeedback.mediumImpact();
              onSpecialTag('RZUT ROŻNY');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('📹 VAR', const Color(0xFFB388FF), () {
              HapticFeedback.heavyImpact();
              onSpecialTag('ANALIZA VAR');
            }),
          ],
        );
      case MatchSport.generic:
        return Row(
          children: [
            _buildQuickTagPill('⚡ PUNKT', const Color(0xFF00E5FF), () {
              HapticFeedback.mediumImpact();
              onSpecialTag('PUNKT!');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('🛡️ OBRONA', const Color(0xFFFFAB00), () {
              HapticFeedback.mediumImpact();
              onSpecialTag('ŚWIETNA OBRONA!');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('⚠️ OSTRZEŻENIE', const Color(0xFFFF5252), () {
              HapticFeedback.mediumImpact();
              onSpecialTag('OSTRZEŻENIE SĘDZIEGO');
            }),
            const SizedBox(width: 5),
            _buildQuickTagPill('⏱️ PRZERWA', const Color(0xFFB388FF), () {
              HapticFeedback.heavyImpact();
              onSpecialTag('PRZERWA W GRZE');
            }),
          ],
        );
    }
  }

  Widget _buildQuickTagPill(String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
