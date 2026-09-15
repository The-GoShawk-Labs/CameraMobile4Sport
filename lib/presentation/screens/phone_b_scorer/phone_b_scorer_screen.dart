import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/router/app_router.dart';
import 'package:volleylive/core/services/wakelock_service.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/screens/settings/camera_connection_modal.dart';
import 'package:volleylive/presentation/screens/settings/scoreboard_customizer_modal.dart';
import 'package:volleylive/presentation/screens/settings/stream_settings_modal.dart';
import 'package:volleylive/presentation/screens/settings/video_settings_modal.dart';
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
  bool _showLocalCameraPreview = true;
  bool _isControlsHidden = false;

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '${d.inHours > 0 ? '${twoDigits(d.inHours)}:' : ''}$minutes:$seconds';
  }

  @override
  void initState() {
    super.initState();
    _unlockHoldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p2p = context.read<P2PConnectionProvider>();
      final camera = context.read<CameraProvider>();
      if (p2p.currentRole == DeviceRole.singlePhoneAllInOne &&
          !camera.isCameraInitialized &&
          !camera.isSimulationMode) {
        camera.initializeCamera();
      }
    });
  }

  @override
  void dispose() {
    WakelockService.disable();
    _unlockHoldController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = context.watch<MatchProvider>();
    final streamer = context.watch<StreamerProvider>();
    final camera = context.watch<CameraProvider>();
    final p2p = context.watch<P2PConnectionProvider>();
    final isOutdoor = match.isOutdoorModeEnabled;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    // Phone B: blokada wygaszania ekranu podczas trwania meczu i nagrywania/streamingu
    final isStreamingOrRecording = camera.isRecording ||
        streamer.programRecState == RecordingState.recording ||
        streamer.streamingState == StreamingState.live;
    final shouldKeepAwake = !match.session.isMatchOver || isStreamingOrRecording;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        WakelockService.setEnabled(shouldKeepAwake);
      }
    });

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRouter.initialRoute);
        }
      },
      child: Scaffold(
        backgroundColor: isOutdoor ? Colors.black : const Color(0xFF070A10),
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // =============================================================
              // 1. PEŁNOEKRANOWA WARSTWA TŁA: KAMERA LIVE / MAKIETA BOISKA
              // =============================================================
              _buildFullCameraBackground(context, match, camera, streamer, p2p, isOutdoor, isPortrait),

              // =============================================================
              // 2. NAKŁADKA TELEWIZYJNA WYNIKÓW (SCOREBOARD OVERLAY)
              // =============================================================
              Positioned(
                top: isPortrait ? 98 : 52,
                left: 8,
                right: 8,
                child: SafeArea(
                  child: Center(
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
                ),
              ),

              // =============================================================
              // 3. EKRAN ZWYCIĘSTWA W MECZU
              // =============================================================
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

              // =============================================================
              // 4. GÓRNY PASEK STATUSU HUD & BANER AWARYJNY
              // =============================================================
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTopBroadcastHUD(context, streamer, match, camera, p2p, isPortrait),
                    if (p2p.currentRole != DeviceRole.singlePhoneAllInOne &&
                        p2p.connectionState != CameraConnectionState.connected)
                      RecoveryBanner(
                        connectionState: p2p.connectionState,
                        onManualReconnect: () async {
                          await p2p.joinSession(
                            hostAddress: p2p.hostAddress.isNotEmpty ? p2p.hostAddress : '192.168.68.51',
                            pairingCode: 'VL-8492',
                            role: DeviceRole.scorerPhoneB,
                          );
                        },
                      ),
                  ],
                ),
              ),

              // =============================================================
              // 5. DOLNY PANEL STEROWANIA SĘDZIEGO (Z PŁYNNYM UKRYWANIEM)
              // =============================================================
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSlide(
                  offset: _isControlsHidden ? const Offset(0, 1.05) : Offset.zero,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                        onToggleCollapse: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _isControlsHidden = true;
                          });
                        },
                      ),
                      _buildBottomModernNavBar(context, streamer),
                    ],
                  ),
                ),
              ),

              // =============================================================
              // 6. DYSKRETNY PŁYWAJĄCY PRZYCISK PRZYWRÓCENIA STEROWANIA
              // =============================================================
              if (_isControlsHidden)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _isControlsHidden = false;
                        });
                      },
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: AppTheme.amberAccent, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.amberAccent.withValues(alpha: 0.35),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sports_volleyball, size: 16, color: AppTheme.amberAccent),
                            SizedBox(width: 8),
                            Text(
                              'POKAŻ KOKPIT SĘDZIEGO',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.6,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: AppTheme.amberAccent),
                          ],
                        ),
                      ),
                    ),
                  ),
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
    ),
  );
}

  Widget _buildTopBroadcastHUD(
    BuildContext context,
    StreamerProvider streamer,
    MatchProvider match,
    CameraProvider camera,
    P2PConnectionProvider p2p,
    bool isPortrait,
  ) {
    final isLive = streamer.streamingState == StreamingState.live;
    final isRec = streamer.programRecState == RecordingState.recording;
    final isOutdoor = match.isOutdoorModeEnabled;

    if (isPortrait) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isOutdoor ? Colors.black : const Color(0xF20A0E17),
          border: const Border(bottom: BorderSide(color: Colors.white12)),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // RZĄD 1: MENU, TRYB STRUMIENIA / KOKPIT, SZYBKIE PRZEŁĄCZNIKI
            Row(
              children: [
                // PRZYCISK WYJŚCIA DO MENU GŁÓWNEGO - DUŻY, CZYTELNY
                InkWell(
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(AppRouter.initialRoute);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 12),
                        SizedBox(width: 5),
                        Text(
                          'MENU',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // PRZYCISK SZYBKIEGO UKRYWANIA / POKAZYWANIA STEROWANIA
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isControlsHidden = !_isControlsHidden;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isControlsHidden ? AppTheme.amberAccent : Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isControlsHidden ? AppTheme.amberAccent : Colors.white24,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isControlsHidden ? Icons.sports_volleyball : Icons.visibility_outlined,
                          size: 14,
                          color: _isControlsHidden ? Colors.black : Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isControlsHidden ? 'KOKPIT' : 'PODGLĄD',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: _isControlsHidden ? Colors.black : Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // PRZYCISK PARAMETRY WIDEO
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 28),
                  icon: const Icon(Icons.tune, size: 16, color: AppTheme.cyanAccent),
                  tooltip: 'Parametry Zapisu Wideo i Kodera',
                  onPressed: () => _openVideoSettings(context),
                ),

                // TOGGLE OUTDOOR HIGH CONTRAST
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 28),
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
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 28),
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

                const SizedBox(width: 4),
                const Icon(Icons.battery_5_bar, size: 13, color: AppTheme.greenLive),
                const SizedBox(width: 2),
                const Text(
                  '88%',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // RZĄD 2: DUŻE PRZYCISKI START LIVE, START REC, TELEMETRIA PHONE A I REC W TLE
            Row(
              children: [
                // PRZYCISK START / STOP LIVE BROADCAST
                Expanded(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      streamer.toggleLiveStream();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: isLive ? AppTheme.redLive.withValues(alpha: 0.25) : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isLive ? AppTheme.redLive : Colors.white24,
                          width: isLive ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: isLive ? AppTheme.redLive : const Color(0xFF757575),
                              shape: BoxShape.circle,
                              boxShadow: [
                                if (isLive)
                                  const BoxShadow(color: AppTheme.redLive, blurRadius: 6),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isLive ? 'LIVE' : 'START LIVE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: isLive ? AppTheme.redLive : Colors.white,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // PRZYCISK START / STOP REC
                Expanded(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      streamer.toggleProgramRecording();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: isRec ? AppTheme.redLive.withValues(alpha: 0.25) : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isRec ? AppTheme.redLive : Colors.white24,
                          width: isRec ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isRec ? AppTheme.redLive : Colors.white38,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isRec ? 'REC' : 'START REC',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: isRec ? AppTheme.redLive : Colors.white,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // WEBRTC CAMERA LINK TELEMETRY (PHONE A)
                InkWell(
                  onTap: () => _openCameraConnectionModal(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: p2p.connectionState == CameraConnectionState.connected
                          ? AppTheme.cyanAccent.withValues(alpha: 0.15)
                          : AppTheme.amberAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: p2p.connectionState == CameraConnectionState.connected
                            ? AppTheme.cyanAccent.withValues(alpha: 0.4)
                            : AppTheme.amberAccent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.videocam,
                          color: p2p.connectionState == CameraConnectionState.connected
                              ? AppTheme.cyanAccent
                              : AppTheme.amberAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          p2p.connectionState == CameraConnectionState.connected
                              ? 'Phone A\n${p2p.healthMetrics.latencyMs}ms'
                              : 'Phone A\nPOŁĄCZ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: p2p.connectionState == CameraConnectionState.connected
                                ? AppTheme.cyanAccent
                                : AppTheme.amberAccent,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // WSKAŹNIK PRACY LOKALNEJ KAMERY W TLE (JEŚLI NAGRYWA)
                if (camera.isRecording) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => context.push(AppRouter.cameraRoute),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.redLive.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.redLive),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fiber_manual_record, color: AppTheme.redLive, size: 10),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(camera.masterRecDuration),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.redLive,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    // WIDOK W POZIOMIE (LANDSCAPE): JEDNORZĘDOWY, DUŻE WYGODNE PRZYCISKI
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOutdoor ? Colors.black : const Color(0xE60A0E17),
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
          // LEWA SEKCJA
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // PRZYCISK WYJŚCIA DO MENU GŁÓWNEGO
              InkWell(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRouter.initialRoute);
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 11),
                      SizedBox(width: 4),
                      Text(
                        'MENU',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // WSKAŹNIK PRACY LOKALNEJ KAMERY W TLE
              if (camera.isRecording) ...[
                InkWell(
                  onTap: () => context.push(AppRouter.cameraRoute),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.redLive.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.redLive),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fiber_manual_record, color: AppTheme.redLive, size: 9),
                        const SizedBox(width: 4),
                        Text(
                          'REC W TLE: ${_formatDuration(camera.masterRecDuration)}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.redLive),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // PRZYCISK START / STOP LIVE BROADCAST
              InkWell(
                onTap: () {
                  HapticFeedback.heavyImpact();
                  streamer.toggleLiveStream();
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: isLive ? AppTheme.redLive : Colors.white70,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // PRZYCISK START / STOP REC
              InkWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  streamer.toggleProgramRecording();
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      const SizedBox(width: 5),
                      Text(
                        isRec ? 'REC' : 'START REC',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: isRec ? AppTheme.redLive : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),
              const Text('|', style: TextStyle(color: Colors.white24, fontSize: 12)),
              const SizedBox(width: 8),

              // WEBRTC CAMERA LINK TELEMETRY
              InkWell(
                onTap: () => _openCameraConnectionModal(context),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.videocam,
                        color: p2p.connectionState == CameraConnectionState.connected
                            ? AppTheme.cyanAccent
                            : AppTheme.amberAccent,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        p2p.connectionState == CameraConnectionState.connected
                            ? 'Phone A (${p2p.healthMetrics.latencyMs}ms)'
                            : 'Phone A (POŁĄCZ)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: p2p.connectionState == CameraConnectionState.connected
                              ? AppTheme.cyanAccent
                              : AppTheme.amberAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // PRAWA SEKCJA
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // PRZYCISK SZYBKIEGO UKRYWANIA / POKAZYWANIA STEROWANIA
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _isControlsHidden = !_isControlsHidden;
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isControlsHidden ? AppTheme.amberAccent : Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _isControlsHidden ? AppTheme.amberAccent : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isControlsHidden ? Icons.sports_volleyball : Icons.visibility_outlined,
                        size: 13,
                        color: _isControlsHidden ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isControlsHidden ? 'KOKPIT' : 'WIDOK STRUMIENIA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: _isControlsHidden ? Colors.black : Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 6),

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
    ),
  ),
),
);
  }

  Widget _buildFullCameraBackground(
    BuildContext context,
    MatchProvider match,
    CameraProvider camera,
    StreamerProvider streamer,
    P2PConnectionProvider p2p,
    bool isOutdoor,
    bool isPortrait,
  ) {
    return GestureDetector(
      onTap: () {
        if (_isControlsHidden) {
          HapticFeedback.selectionClick();
          setState(() {
            _isControlsHidden = false;
          });
        }
      },
      child: Container(
        color: isOutdoor ? Colors.black : const Color(0xFF070A10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. BEZPRZEWODOWY OBRAZ Z KAMERY PHONE A (P2P REALME)
            if (p2p.currentVideoFrame != null)
              Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Image.memory(
                    p2p.currentVideoFrame!,
                    gaplessPlayback: true,
                  ),
                ),
              )
            // 2. LOKALNA KAMERA W TRYBIE POJEDYNCZEGO TELEFONU (ALL-IN-ONE)
            else if (_showLocalCameraPreview &&
                camera.isCameraInitialized &&
                camera.cameraController != null &&
                camera.cameraController!.value.isInitialized)
              Builder(
                builder: (context) {
                  final controller = camera.cameraController!;
                  final pWidth = controller.value.previewSize?.width ?? 1920.0;
                  final pHeight = controller.value.previewSize?.height ?? 1080.0;
                  final sensorLong = pWidth > pHeight ? pWidth : pHeight;
                  final sensorShort = pWidth > pHeight ? pHeight : pWidth;
                  final targetWidth = isPortrait ? sensorShort : sensorLong;
                  final targetHeight = isPortrait ? sensorLong : sensorShort;
                  final targetAspectRatio = targetWidth / targetHeight;

                  return Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: AspectRatio(
                      aspectRatio: targetAspectRatio,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: targetWidth,
                          height: targetHeight,
                          child: CameraPreview(controller),
                        ),
                      ),
                    ),
                  );
                },
              )
            // 3. MAKIETA BOISKA JEŚLI BRAK AKTYWNEGO OBRAZU Z KAMERY
            else ...[
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
            ],

            // PODPIS STATUSU STRUMIENIA WIDEO I PRZEŁĄCZNIK KAMERA/MAKIETA (W JEDNYM RZĘDZIE, BEZ KOLIZJI)
            Positioned(
              top: isPortrait ? 154 : 50,
              left: 12,
              right: 12,
              child: Align(
                alignment: isPortrait ? Alignment.center : Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // PODPIS STATUSU STRUMIENIA WIDEO I PARAMETRÓW KODERA
                      InkWell(
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
                                decoration: BoxDecoration(
                                  color: camera.isRecording ? AppTheme.redLive : AppTheme.greenLive,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                p2p.currentVideoFrame != null
                                    ? 'LIVE FEED • REALME (${p2p.healthMetrics.latencyMs}ms • P2P)'
                                    : (camera.isCameraInitialized
                                        ? 'LOKALNA KAMERA (${camera.settings.resolution.label} ${camera.settings.fps.label})'
                                        : 'OCZEKIWANIE NA KAMERĘ REALME...'),
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

                      const SizedBox(width: 8),

                      // PRZEŁĄCZNIK WIDOKU KAMERA LIVE / MAKIETA
                      InkWell(
                        onTap: () {
                          setState(() {
                            _showLocalCameraPreview = !_showLocalCameraPreview;
                          });
                          if (_showLocalCameraPreview && !camera.isCameraInitialized) {
                            camera.initializeCamera();
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showLocalCameraPreview ? Icons.sports_volleyball : Icons.videocam,
                                size: 11,
                                color: AppTheme.cyanAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _showLocalCameraPreview ? 'MAKIETA' : 'KAMERA LIVE',
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
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

  void _openCameraConnectionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const CameraConnectionModal(),
    );
  }

  void _openStreamSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const StreamSettingsModal(),
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
      {'label': 'KAMERA', 'icon': Icons.camera_alt_outlined},
      {'label': 'STATS', 'icon': Icons.analytics_outlined},
      {'label': 'WIDEO REC', 'icon': Icons.video_settings},
      {'label': 'STREAM', 'icon': Icons.stream},
      {'label': 'TABLICA', 'icon': Icons.palette_outlined},
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
                // PRZEJDŹ DO PEŁNEJ KAMERY
                context.push(AppRouter.cameraRoute);
              } else if (index == 2) {
                // STATS
                context.push(AppRouter.statisticianRoute);
              } else if (index == 3) {
                // PARAMETRY WIDEO
                _openVideoSettings(context);
              } else if (index == 4) {
                // STREAM MODAL
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const StreamSettingsModal(),
                );
              } else if (index == 5) {
                // SCOREBOARD STUDIO
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const ScoreboardCustomizerModal(),
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
