import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/screens/settings/scoreboard_customizer_modal.dart';
import 'package:volleylive/presentation/screens/settings/stream_settings_modal.dart';
import 'package:volleylive/presentation/screens/settings/video_settings_modal.dart';
import 'package:volleylive/presentation/screens/statistician/statistician_screen.dart';
import 'package:volleylive/presentation/widgets/recovery_banner.dart';
import 'package:volleylive/presentation/widgets/scoreboard_overlay.dart';
import 'package:volleylive/presentation/widgets/tactile_score_pad.dart';

class PhoneBScorerScreen extends StatefulWidget {
  const PhoneBScorerScreen({super.key});

  @override
  State<PhoneBScorerScreen> createState() => _PhoneBScorerScreenState();
}

class _PhoneBScorerScreenState extends State<PhoneBScorerScreen> with SingleTickerProviderStateMixin {
  int _selectedNavIndex = 0;
  AnimationController? _unlockHoldController;

  @override
  void initState() {
    super.initState();
    _unlockHoldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _unlockHoldController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = context.watch<MatchProvider>();
    final streamer = context.watch<StreamerProvider>();
    final camera = context.watch<CameraProvider>();
    final isOutdoor = match.isOutdoorModeEnabled;

    return Scaffold(
      backgroundColor: isOutdoor ? Colors.black : const Color(0xFF070A10),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // GÓRNY PASEK STATUSU HUD (TRANSMISJA, REC, WEBRTC, BATERIA, SŁOŃCE, KŁÓDKA, USTAWIENIA WIDEO)
                _buildTopBroadcastHUD(context, streamer, match, camera),

                // BANER AWARYJNY W PRZYPADKU UTRATY SYGNAŁU Z KAMERY
                RecoveryBanner(
                  connectionState: streamer.cameraLinkState,
                  onManualReconnect: () => streamer.startHostPairing(match.session.pairingCode),
                ),

                // OBSZAR PODGLĄDU WIDEO Z KAMERY PHONE A Z NAKŁADKĄ SCOREBOARDU
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // CYFROWY WIZJER KAMERY / BOISKO WEBRTC (DYNAMICZNY RENDER DYSCYPLINY)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isOutdoor
                                ? [Colors.black, const Color(0xFF0A0F1A)]
                                : [const Color(0xFF0F1726), const Color(0xFF0A0F1A)],
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // RYSOWANE LINIE BOISKA DOSTOSOWANE DO DYSCYPLINY
                            CustomPaint(
                              painter: SportCourtPainter(
                                sport: match.session.sport,
                                isHighContrast: isOutdoor,
                              ),
                            ),

                            // SIATKA CELOWNIKA KAMERY / FOCUS RETICLE
                            Center(
                              child: Container(
                                width: 140,
                                height: 90,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white10, width: 1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Stack(
                                  children: [
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: Container(width: 8, height: 8, decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.cyanAccent, width: 2), left: BorderSide(color: AppTheme.cyanAccent, width: 2)))),
                                    ),
                                    Align(
                                      alignment: Alignment.topRight,
                                      child: Container(width: 8, height: 8, decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.cyanAccent, width: 2), right: BorderSide(color: AppTheme.cyanAccent, width: 2)))),
                                    ),
                                    Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Container(width: 8, height: 8, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.cyanAccent, width: 2), left: BorderSide(color: AppTheme.cyanAccent, width: 2)))),
                                    ),
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: Container(width: 8, height: 8, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.cyanAccent, width: 2), right: BorderSide(color: AppTheme.cyanAccent, width: 2)))),
                                    ),
                                    Center(
                                      child: Icon(match.session.sport.icon, size: 28, color: Colors.white.withValues(alpha: 0.15)),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // PODPIS STATUSU STRUMIENIA WIDEO I PARAMETRÓW KODERA
                            Positioned(
                              bottom: 10,
                              left: 12,
                              child: InkWell(
                                onTap: () => _openVideoSettings(context),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.greenLive,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'LIVE FEED • PHONE A (${camera.settings.resolution.label} ${camera.settings.fps.label} • ${camera.settings.bitrateMbps.toStringAsFixed(1)} Mbps)',
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.settings, size: 10, color: AppTheme.cyanAccent),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // TELEWIZYJNA NAKŁADKA WYNIKOWA (TOP RIGHT)
                      Positioned(
                        top: 8,
                        right: 10,
                        child: ScoreboardOverlay(
                          session: match.session,
                          style: streamer.scoreboardStyle,
                          isTimeoutActive: match.isTimeoutActive,
                          timeoutSeconds: match.timeoutSecondsRemaining,
                          timeoutTeam: match.timeoutCallingTeam,
                          showServeIndicator: streamer.showServeIndicator,
                          activeSpecialEvent: match.activeSpecialEvent,
                        ),
                      ),

                      // ZWYCIĘSTWO W MECZU OVERLAY
                      if (match.session.isMatchOver)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black87,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.emoji_events, color: AppTheme.amberAccent, size: 64),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'KONIEC MECZU!',
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Zwycięzca: ${match.session.matchWinner}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Wynik końcowy: ${match.session.currentSetPointsA} - ${match.session.currentSetPointsB}',
                                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // DOLNY PULPIT SĘDZIEGO (TACTILE TOUCH DECK)
                TactileScorePad(
                  session: match.session,
                  onAddPointA: (pts) {
                    match.addPointA(points: pts);
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onAddPointB: (pts) {
                    match.addPointB(points: pts);
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onSubtractPointA: () {
                    match.subtractPointA();
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onSubtractPointB: () {
                    match.subtractPointB();
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onAddFoulA: () {
                    match.addFoulA();
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onAddFoulB: () {
                    match.addFoulB();
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onNextPeriod: () {
                    match.nextPeriod();
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onUndo: () {
                    match.undo();
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onToggleRotation: () {
                    match.toggleRotation();
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onRequestTimeoutA: () {
                    match.startTimeout(ServingTeam.teamA);
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onRequestTimeoutB: () {
                    match.startTimeout(ServingTeam.teamB);
                    context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                  },
                  onRequestSubA: () => match.requestSubstitutionA(),
                  onRequestSubB: () => match.requestSubstitutionB(),
                  onSpecialTag: (tag) => match.triggerSpecialEvent(tag),
                  canUndo: match.canUndo,
                  isTimeoutActive: match.isTimeoutActive,
                  isOutdoorMode: isOutdoor,
                ),

                // DOLNY PASEK NAWIGACJI (SCORER, STATS, WIDEO, STREAM, SETTINGS)
                _buildBottomModernNavBar(context, streamer),
              ],
            ),

            // OVERLAY BLOKADY DOTYKU SĘDZIEGO (GHOST TOUCH LOCK)
            if (match.isScreenLocked)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.94),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_rounded, color: AppTheme.amberAccent, size: 64),
                        const SizedBox(height: 16),
                        const Text(
                          'TRYB SĘDZIEGO ZABLOKOWANY',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Ochrona przed przypadkowym dotknięciem na słupku / ławce',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 24),

                        // PRZYTRZYMAJ, ABY ODBLOKOWAĆ (HOLD TO UNLOCK)
                        GestureDetector(
                          onLongPressStart: (_) {
                            _unlockHoldController?.forward();
                          },
                          onLongPressEnd: (_) {
                            if (_unlockHoldController?.isCompleted ?? false) {
                              HapticFeedback.heavyImpact();
                              match.toggleScreenLock();
                            }
                            _unlockHoldController?.reverse();
                          },
                          child: AnimatedBuilder(
                            animation: _unlockHoldController!,
                            builder: (context, child) {
                              final progress = _unlockHoldController!.value;
                              return Container(
                                width: 220,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceCard,
                                  borderRadius: BorderRadius.circular(25),
                                  border: Border.all(color: AppTheme.amberAccent, width: 1.5),
                                ),
                                child: Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    Container(
                                      width: 220 * progress,
                                      decoration: BoxDecoration(
                                        color: AppTheme.amberAccent.withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                    ),
                                    const Center(
                                      child: Text(
                                        'PRZYTRZYMAJ, BY ODBLOKOWAĆ',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBroadcastHUD(
    BuildContext context,
    StreamerProvider streamer,
    MatchProvider match,
    CameraProvider camera,
  ) {
    final isLive = streamer.streamingState == StreamingState.live;
    final isRec = streamer.programRecState == RecordingState.recording;
    final isOutdoor = match.isOutdoorModeEnabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isOutdoor ? Colors.black : const Color(0xE60A0E17),
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // LEWA SEKCJA: STATUS LIVE, REC, WEBRTC TELEMETRY
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  // PRZYCISK START / STOP LIVE BROADCAST
                  InkWell(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      streamer.toggleLiveStream();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isLive ? AppTheme.redLive.withValues(alpha: 0.2) : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isLive ? AppTheme.redLive : Colors.white24),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isLive ? AppTheme.redLive : const Color(0xFF616161),
                              shape: BoxShape.circle,
                              boxShadow: [
                                if (isLive)
                                  const BoxShadow(color: AppTheme.redLive, blurRadius: 6),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isLive ? 'LIVE' : 'START LIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isLive ? AppTheme.redLive : Colors.white70,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // PRZYCISK START / STOP REC
                  InkWell(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      streamer.toggleProgramRecording();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isRec ? AppTheme.redLive.withValues(alpha: 0.2) : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isRec ? AppTheme.redLive : Colors.white24),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: isRec ? AppTheme.redLive : Colors.white38,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isRec ? 'REC' : 'START REC',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isRec ? AppTheme.redLive : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),
                  const Text('|', style: TextStyle(color: Colors.white24, fontSize: 11)),
                  const SizedBox(width: 6),

                  // WEBRTC CAMERA LINK TELEMETRY
                  Row(
                    children: [
                      const Icon(Icons.videocam, color: AppTheme.cyanAccent, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Phone A (${streamer.healthMetrics.latencyMs}ms)',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.cyanAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 6),

          // PRAWA SEKCJA: SZYBKA KONFIGURACJA WIDEO / SŁOŃCE / KŁÓDKA / BATERIA
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // PRZYCISK PARAMETRY WIDEO
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.tune, size: 16, color: AppTheme.cyanAccent),
                tooltip: 'Parametry Zapisu Wideo i Kodera',
                onPressed: () => _openVideoSettings(context),
              ),

              // TOGGLE OUTDOOR HIGH CONTRAST
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  isOutdoor ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                  size: 16,
                  color: isOutdoor ? AppTheme.amberAccent : Colors.white54,
                ),
                tooltip: 'Tryb Pełne Słońce (High Contrast)',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  match.toggleOutdoorMode();
                },
              ),

              // TOGGLE SCREEN LOCK (GHOST TOUCH PREVENTION)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: Colors.white70,
                ),
                tooltip: 'Zablokuj Ekran Sędziego',
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  match.toggleScreenLock();
                },
              ),

              const SizedBox(width: 2),
              const Icon(Icons.battery_5_bar, size: 14, color: AppTheme.greenLive),
              const SizedBox(width: 2),
              const Text(
                '88%',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openVideoSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const VideoSettingsModal(),
    );
  }

  Widget _buildBottomModernNavBar(BuildContext context, StreamerProvider streamer) {
    final items = [
      {'label': 'SCORER', 'icon': Icons.sports_score},
      {'label': 'WIDEO REC', 'icon': Icons.video_settings},
      {'label': 'STREAM', 'icon': Icons.stream},
      {'label': 'TABLICA', 'icon': Icons.palette_outlined},
      {'label': 'STATS', 'icon': Icons.analytics_outlined},
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF090D15),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = _selectedNavIndex == index;

          return InkWell(
            onTap: () {
              setState(() {
                _selectedNavIndex = index;
              });

              if (index == 1) {
                // PARAMETRY WIDEO
                _openVideoSettings(context);
              } else if (index == 2) {
                // STREAM MODAL
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const StreamSettingsModal(),
                );
              } else if (index == 3) {
                // SCOREBOARD STUDIO
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const ScoreboardCustomizerModal(),
                );
              } else if (index == 4) {
                // STATS
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StatisticianScreen()),
                );
              }
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item['icon'] as IconData,
                  size: 16,
                  color: isSelected ? AppTheme.cyanAccent : Colors.white54,
                ),
                const SizedBox(height: 2),
                Text(
                  item['label'] as String,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: isSelected ? Colors.white : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class SportCourtPainter extends CustomPainter {
  final MatchSport sport;
  final bool isHighContrast;

  SportCourtPainter({
    this.sport = MatchSport.volleyball,
    this.isHighContrast = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final courtPaint = Paint()
      ..color = isHighContrast ? const Color(0xFF263A5C) : const Color(0xFF16253B)
      ..strokeWidth = isHighContrast ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;

    final accentPaint = Paint()
      ..color = AppTheme.cyanAccent.withValues(alpha: isHighContrast ? 0.8 : 0.4)
      ..strokeWidth = isHighContrast ? 3.0 : 2.0
      ..style = PaintingStyle.stroke;

    final linePaint = Paint()
      ..color = isHighContrast ? Colors.white30 : Colors.white12
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(center: center, width: size.width * 0.9, height: size.height * 0.75);

    // Główny obrys boiska
    canvas.drawRect(rect, courtPaint);

    switch (sport) {
      case MatchSport.volleyball:
      case MatchSport.beachVolleyball:
        // Siatka i linie ataku 3m
        canvas.drawLine(Offset(rect.left, center.dy), Offset(rect.right, center.dy), accentPaint);
        canvas.drawLine(Offset(rect.left, center.dy - 40), Offset(rect.right, center.dy - 40), linePaint);
        canvas.drawLine(Offset(rect.left, center.dy + 40), Offset(rect.right, center.dy + 40), linePaint);
        break;

      case MatchSport.basketball:
        // Linia środkowa, koło środkowe, trumny podkoszowe
        canvas.drawLine(Offset(rect.left, center.dy), Offset(rect.right, center.dy), accentPaint);
        canvas.drawCircle(center, 28, linePaint);
        // Trumny i kosze
        canvas.drawRect(Rect.fromCenter(center: Offset(center.dx, rect.top + 20), width: 60, height: 40), linePaint);
        canvas.drawRect(Rect.fromCenter(center: Offset(center.dx, rect.bottom - 20), width: 60, height: 40), linePaint);
        break;

      case MatchSport.football:
        // Linia środkowa, koło środkowe, pola karne
        canvas.drawLine(Offset(rect.left, center.dy), Offset(rect.right, center.dy), accentPaint);
        canvas.drawCircle(center, 34, linePaint);
        canvas.drawRect(Rect.fromCenter(center: Offset(center.dx, rect.top + 25), width: 100, height: 50), linePaint);
        canvas.drawRect(Rect.fromCenter(center: Offset(center.dx, rect.bottom - 25), width: 100, height: 50), linePaint);
        break;

      case MatchSport.generic:
        canvas.drawLine(Offset(rect.left, center.dy), Offset(rect.right, center.dy), accentPaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant SportCourtPainter oldDelegate) =>
      oldDelegate.sport != sport || oldDelegate.isHighContrast != isHighContrast;
}
