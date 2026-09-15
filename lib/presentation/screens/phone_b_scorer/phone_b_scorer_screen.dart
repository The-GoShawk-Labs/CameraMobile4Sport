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
              // STRUKTURA GŁÓWNA: PIONOWA (PORTRAIT) LUB POZIOMA (LANDSCAPE)
              // =============================================================
              if (isPortrait)
                Column(
                  children: [
                    // 1. GÓRNY PASEK STATUSU HUD (MENU, LIVE/REC, STATUS PHONE A)
                    _buildTopBroadcastHUD(context, streamer, match, camera, p2p, true),

                    // 2. AWARYJNY BANER PRZYWRACANIA POŁĄCZENIA
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

                    // 3. WIDOK STRUMIENIA WIDEO (16:9 DOPASOWANY DO SZEROKOŚCI Z NAŁOŻONĄ TABLICĄ WYNIKÓW)
                    _buildBroadcastStreamView(
                      context: context,
                      match: match,
                      camera: camera,
                      streamer: streamer,
                      p2p: p2p,
                      isOutdoor: isOutdoor,
                      isPortrait: true,
                    ),

                    // 4. OBSZAR KOKPITU SĘDZIEGO (PŁYNNIE CHOWANY / ROZWIJANY)
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedSlide(
                            offset: _isControlsHidden ? const Offset(0, 1.05) : Offset.zero,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOutCubic,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildTactileScorePadWidget(context, match, isOutdoor),
                                    _buildBottomModernNavBar(context, streamer),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // PRZYCISK PRZYWRÓCENIA KOKPITU
                          if (_isControlsHidden)
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: _buildFloatingRestoreControlsButton(),
                            ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                // =============================================================
                // UKŁAD POZIOMY (LANDSCAPE)
                // =============================================================
                Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. STRUMIEŃ WIDEO 16:9 WYŚRODKOWANY / DOPASOWANY DO SZEROKOŚCI Z NAŁOŻONYM SCOREBOARDEM
                    Center(
                      child: _buildBroadcastStreamView(
                        context: context,
                        match: match,
                        camera: camera,
                        streamer: streamer,
                        p2p: p2p,
                        isOutdoor: isOutdoor,
                        isPortrait: false,
                      ),
                    ),

                    // 2. GÓRNY PASEK STATUSU HUD W POZIOMIE
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildTopBroadcastHUD(context, streamer, match, camera, p2p, false),
                    ),

                    // 3. AWARYJNY BANER W POZIOMIE (TYLKO PODCZAS AKTYWNEGO WZNAWIANIA, PONIŻEJ TABLICY)
                    if (p2p.currentRole != DeviceRole.singlePhoneAllInOne &&
                        p2p.connectionState == CameraConnectionState.reconnecting)
                      Positioned(
                        top: 108,
                        left: 40,
                        right: 40,
                        child: Center(
                          child: RecoveryBanner(
                            connectionState: p2p.connectionState,
                            onManualReconnect: () async {
                              await p2p.joinSession(
                                hostAddress: p2p.hostAddress.isNotEmpty ? p2p.hostAddress : '192.168.68.51',
                                pairingCode: 'VL-8492',
                                role: DeviceRole.scorerPhoneB,
                              );
                            },
                          ),
                        ),
                      ),

                    // 4. ERGONOMICZNY KOKPIT SĘDZIEGO W POZIOMIE (KCIUKOWY OVERLAY PO BOKACH)
                    _buildLandscapeErgonomicCockpit(context, match, isOutdoor),

                    // 5. PRZYCISK PRZYWRÓCENIA STEROWANIA W POZIOMIE GDY SCHOWANE
                    if (_isControlsHidden)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: _buildFloatingRestoreControlsButton(),
                      ),
                  ],
                ),

              // =============================================================
              // EKRAN ZWYCIĘSTWA W MECZU
              // =============================================================
              if (match.session.isMatchOver)
                _buildVictoryOverlay(match),

              // =============================================================
              // OVERLAY BLOKADY DOTYKU SĘDZIEGO (GHOST TOUCH LOCK)
              // =============================================================
              if (match.isScreenLocked)
                _buildScreenLockOverlay(match),
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

  // ===========================================================================
  // WIDOK STRUMIENIA WIDEO (16:9) Z TABLICĄ WYNIKÓW OVERLAY I TELEMETRIĄ
  // ===========================================================================
  Widget _buildBroadcastStreamView({
    required BuildContext context,
    required MatchProvider match,
    required CameraProvider camera,
    required StreamerProvider streamer,
    required P2PConnectionProvider p2p,
    required bool isOutdoor,
    required bool isPortrait,
  }) {
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
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. ZASADNICZY STRUMIEŃ WIDEO (KAMERA P2P / KAMERA LOKALNA / MAKIETA BOISKA)
              _buildStreamMediaLayer(match, camera, p2p, isOutdoor, isPortrait),

              // 2. TABLICA WYNIKÓW (SCOREBOARD OVERLAY) NAŁOŻONA BEZPOŚREDNIO NA STRUMIEŃ WIDEO
              Positioned(
                top: isPortrait ? 8 : 52,
                left: 8,
                right: 8,
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

              // 3. TELEMETRIA STRUMIENIA I PRZEŁĄCZNIK WIDOKU W DOLNYM ROGU STRUMIENIA
              if (isPortrait || _isControlsHidden)
                Positioned(
                  bottom: 6,
                  left: isPortrait ? 10 : 16,
                  right: isPortrait ? 10 : null,
                  child: _buildStreamStatusAndControlsRow(context, camera, p2p, isPortrait: isPortrait),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreamMediaLayer(
    MatchProvider match,
    CameraProvider camera,
    P2PConnectionProvider p2p,
    bool isOutdoor,
    bool isPortrait,
  ) {
    // 1. BEZPRZEWODOWY OBRAZ Z KAMERY PHONE A (P2P REALME)
    if (p2p.currentVideoFrame != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: Image.memory(
          p2p.currentVideoFrame!,
          gaplessPlayback: true,
        ),
      );
    }

    // 2. LOKALNA KAMERA W TRYBIE POJEDYNCZEGO TELEFONU (ALL-IN-ONE)
    if (_showLocalCameraPreview &&
        camera.isCameraInitialized &&
        camera.cameraController != null &&
        camera.cameraController!.value.isInitialized) {
      final controller = camera.cameraController!;
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.width ?? 1920.0,
          height: controller.value.previewSize?.height ?? 1080.0,
          child: CameraPreview(controller),
        ),
      );
    }

    // 3. MAKIETA BOISKA JEŚLI BRAK AKTYWNEGO OBRAZU Z KAMERY
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: SportCourtPainter(
            sport: match.session.sport,
            isHighContrast: isOutdoor,
          ),
        ),
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
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppTheme.cyanAccent, width: 2),
                        left: BorderSide(color: AppTheme.cyanAccent, width: 2),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppTheme.cyanAccent, width: 2),
                        right: BorderSide(color: AppTheme.cyanAccent, width: 2),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppTheme.cyanAccent, width: 2),
                        left: BorderSide(color: AppTheme.cyanAccent, width: 2),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppTheme.cyanAccent, width: 2),
                        right: BorderSide(color: AppTheme.cyanAccent, width: 2),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Icon(match.session.sport.icon, size: 28, color: Colors.white.withValues(alpha: 0.15)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStreamStatusAndControlsRow(
    BuildContext context,
    CameraProvider camera,
    P2PConnectionProvider p2p, {
    bool isPortrait = true,
  }) {
    return Align(
      alignment: isPortrait ? Alignment.bottomCenter : Alignment.bottomLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // PODPIS STATUSU STRUMIENIA WIDEO I PARAMETRÓW KODERA
              InkWell(
                onTap: () => _openVideoSettings(context),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                        isPortrait
                            ? (p2p.currentVideoFrame != null
                                ? 'LIVE FEED • REALME (${p2p.healthMetrics.latencyMs}ms • P2P)'
                                : (camera.isCameraInitialized
                                    ? 'LOKALNA KAMERA (${camera.settings.resolution.label} ${camera.settings.fps.label})'
                                    : 'OCZEKIWANIE NA KAMERĘ REALME...'))
                            : (p2p.currentVideoFrame != null
                                ? 'P2P ${p2p.healthMetrics.latencyMs}ms'
                                : (camera.isCameraInitialized
                                    ? 'KAMERA ${camera.settings.fps.label}'
                                    : 'BRAK ŹRÓDŁA')),
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white10,
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
    );
  }

  Widget _buildTactileScorePadWidget(
    BuildContext context,
    MatchProvider match,
    bool isOutdoor,
  ) {
    return TactileScorePad(
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
    );
  }

  Widget _buildFloatingRestoreControlsButton() {
    return Center(
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
    );
  }

  // ===========================================================================
  // ERGONOMICZNY KOKPIT SĘDZIEGO W POZIOMIE (LANDSCAPE HUD)
  // Przeznaczony do obsługi kciukami bez zasłaniania środka boiska ani tablicy
  // ===========================================================================
  Widget _buildLandscapeErgonomicCockpit(
    BuildContext context,
    MatchProvider match,
    bool isOutdoor,
  ) {
    final session = match.session;
    final isServingA = session.currentServer == ServingTeam.teamA;
    final isServingB = session.currentServer == ServingTeam.teamB;

    return AnimatedSlide(
      offset: _isControlsHidden ? const Offset(0, 1.25) : Offset.zero,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // LEWY PANEL: DRUŻYNA A (OBSŁUGA LEWYM KCIUKIEM)
          Positioned(
            left: 12,
            bottom: 12,
            child: _buildLandscapeTeamScoreCard(
              teamName: session.teamA,
              teamColor: session.teamAColor,
              points: session.currentSetPointsA,
              isServing: isServingA,
              timeoutsUsed: session.timeoutsA,
              subsUsed: session.substitutionsA,
              onAddPoint: () {
                match.addPointA(points: 1);
                context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
              },
              onSubtractPoint: () {
                match.subtractPointA();
                context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
              },
              tag1Label: 'AS!',
              tag1Color: AppTheme.amberAccent,
              onTag1: () => match.triggerSpecialEvent('AS!'),
              tag2Label: 'BLOK',
              tag2Color: AppTheme.cyanAccent,
              onTag2: () => match.triggerSpecialEvent('BLOK'),
              isOutdoor: isOutdoor,
            ),
          ),

          // PRAWY PANEL: DRUŻYNA B (OBSŁUGA PRAWYM KCIUKIEM)
          Positioned(
            right: 12,
            bottom: 12,
            child: _buildLandscapeTeamScoreCard(
              teamName: session.teamB,
              teamColor: session.teamBColor,
              points: session.currentSetPointsB,
              isServing: isServingB,
              timeoutsUsed: session.timeoutsB,
              subsUsed: session.substitutionsB,
              onAddPoint: () {
                match.addPointB(points: 1);
                context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
              },
              onSubtractPoint: () {
                match.subtractPointB();
                context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
              },
              tag1Label: 'ATAK',
              tag1Color: AppTheme.amberAccent,
              onTag1: () => match.triggerSpecialEvent('ATAK'),
              tag2Label: 'CHALLENGE',
              tag2Color: const Color(0xFFAB47BC),
              onTag2: () => match.triggerSpecialEvent('CHALLENGE'),
              isOutdoor: isOutdoor,
            ),
          ),

          // DOLNY PASEK NAWIGACJI I KONTROLI MECZU: ROTACJA, UNDO, TIMEOUT, ZWIŃ
          Positioned(
            bottom: 12,
            left: 235,
            right: 235,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isOutdoor ? Colors.black : const Color(0xF20A0E17),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
                boxShadow: const [
                  BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // ROTACJA
                  InkWell(
                    onTap: () {
                      match.toggleRotation();
                      context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.amberAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.amberAccent.withValues(alpha: 0.6)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync_alt, size: 13, color: AppTheme.amberAccent),
                          SizedBox(width: 4),
                          Text('ROTACJA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.amberAccent)),
                        ],
                      ),
                    ),
                  ),

                  // UNDO (COFNIJ)
                  InkWell(
                    onTap: match.canUndo
                        ? () {
                            match.undo();
                            context.read<P2PConnectionProvider>().broadcastScore(match.toScorePayload);
                          }
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: match.canUndo ? Colors.white12 : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: match.canUndo ? Colors.white24 : Colors.white10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.undo, size: 13, color: match.canUndo ? Colors.white : Colors.white30),
                          const SizedBox(width: 4),
                          Text(
                            'COFNIJ',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: match.canUndo ? Colors.white : Colors.white30),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // PRZYCISK UKRYCIA KOKPITU
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _isControlsHidden = true;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: Colors.white70),
                          SizedBox(width: 2),
                          Text('UKRYJ', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeTeamScoreCard({
    required String teamName,
    required Color teamColor,
    required int points,
    required bool isServing,
    required int timeoutsUsed,
    required int subsUsed,
    required VoidCallback onAddPoint,
    required VoidCallback onSubtractPoint,
    required String tag1Label,
    required Color tag1Color,
    required VoidCallback onTag1,
    required String tag2Label,
    required Color tag2Color,
    required VoidCallback onTag2,
    required bool isOutdoor,
  }) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isOutdoor ? Colors.black : const Color(0xF20A0E17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isServing ? teamColor : teamColor.withValues(alpha: 0.35),
          width: isServing ? 2.0 : 1.2,
        ),
        boxShadow: [
          if (isServing)
            BoxShadow(
              color: teamColor.withValues(alpha: 0.25),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          const BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // NAZWA DRUŻYNY I ZNACZNIK SERWISU
          Row(
            children: [
              Container(width: 4, height: 14, decoration: BoxDecoration(color: teamColor, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  teamName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: teamColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (isServing)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: teamColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: teamColor, width: 1),
                  ),
                  child: const Text('SERW', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
            ],
          ),

          const SizedBox(height: 6),

          // DUŻY PRZYCISK PUNKTU (+1 TAP, SWIPE DO DOŁU -1)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onAddPoint();
            },
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 100) {
                HapticFeedback.mediumImpact();
                onSubtractPoint();
              }
            },
            child: Container(
              height: 72,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isOutdoor ? const Color(0xFF101622) : const Color(0xFF141D2D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isServing ? teamColor.withValues(alpha: 0.5) : Colors.white12,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 4,
                    left: 8,
                    child: Text('TAP: +1', style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.4), fontWeight: FontWeight.bold)),
                  ),
                  Positioned(
                    top: 4,
                    right: 8,
                    child: Text('SWIPE: -1', style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.4), fontWeight: FontWeight.bold)),
                  ),
                  Text(
                    points.toString(),
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: teamColor,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          // SZYBKIE TAGI ZDARZEŃ (AS, BLOK / ATAK, CHALLENGE)
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    onTag1();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 26,
                    decoration: BoxDecoration(
                      color: tag1Color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tag1Color.withValues(alpha: 0.4)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tag1Label,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: tag1Color),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    onTag2();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 26,
                    decoration: BoxDecoration(
                      color: tag2Color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tag2Color.withValues(alpha: 0.4)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tag2Label,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: tag2Color),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVictoryOverlay(MatchProvider match) {
    return Positioned.fill(
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
    );
  }

  Widget _buildScreenLockOverlay(MatchProvider match) {
    return Positioned.fill(
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
                _openStreamSettings(context);
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
