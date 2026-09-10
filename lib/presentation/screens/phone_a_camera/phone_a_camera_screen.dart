import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/camera_config.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/screens/settings/scoreboard_customizer_modal.dart';
import 'package:volleylive/presentation/screens/settings/stream_settings_modal.dart';
import 'package:volleylive/presentation/screens/settings/video_settings_modal.dart';
import 'package:volleylive/presentation/widgets/camera_controls_overlay.dart';
import 'package:volleylive/presentation/widgets/recovery_banner.dart';
import 'package:volleylive/presentation/widgets/scoreboard_overlay.dart';

class PhoneACameraScreen extends StatefulWidget {
  const PhoneACameraScreen({super.key});

  @override
  State<PhoneACameraScreen> createState() => _PhoneACameraScreenState();
}

class _PhoneACameraScreenState extends State<PhoneACameraScreen> {
  double _baseZoom = 1.0;
  Offset? _focusTapPosition;
  bool _isFocusIndicatorVisible = false;
  Timer? _focusIndicatorTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final camera = context.read<CameraProvider>();
      if (!camera.isCameraInitialized && !camera.isSimulationMode) {
        camera.initializeCamera();
      }
    });
  }

  @override
  void dispose() {
    _focusIndicatorTimer?.cancel();
    super.dispose();
  }

  void _handleTapToFocus(TapUpDetails details, Size screenSize, CameraProvider camera) {
    final localPos = details.localPosition;
    final relativeX = (localPos.dx / screenSize.width).clamp(0.0, 1.0);
    final relativeY = (localPos.dy / screenSize.height).clamp(0.0, 1.0);

    setState(() {
      _focusTapPosition = localPos;
      _isFocusIndicatorVisible = true;
    });

    camera.setFocusAndExposurePoint(Offset(relativeX, relativeY));

    _focusIndicatorTimer?.cancel();
    _focusIndicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isFocusIndicatorVisible = false;
        });
      }
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final camera = context.watch<CameraProvider>();
    final match = context.watch<MatchProvider>();
    final streamer = context.watch<StreamerProvider>();
    final p2p = context.watch<P2PConnectionProvider>();

    // Synchronizuj wynik odebrany po P2P z Phone B jeśli dostępny
    if (p2p.lastReceivedScore != null) {
      final s = p2p.lastReceivedScore!;
      if (s.pointsA != match.session.currentSetPointsA ||
          s.pointsB != match.session.currentSetPointsB ||
          s.setsA != match.session.setsA ||
          s.setsB != match.session.setsB) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          match.syncFromScorePayload(s);
        });
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // 1. PEŁNOEKRANOWY PODGLĄD KAMERY (LIVE LUB FALLBACK SIMULATION)
              Positioned.fill(
                child: GestureDetector(
                  onTapUp: (details) => _handleTapToFocus(
                    details,
                    Size(constraints.maxWidth, constraints.maxHeight),
                    camera,
                  ),
                  onScaleStart: (details) {
                    _baseZoom = camera.settings.zoom;
                  },
                  onScaleUpdate: (details) {
                    camera.setZoom(_baseZoom * details.scale);
                  },
                  child: _buildCameraPreviewContent(camera),
                ),
              ),

              // 2. WSKAŹNIK DOTKNIĘCIA DO USTAWIANIA OSTROŚCI (TAP-TO-FOCUS)
              if (_isFocusIndicatorVisible && _focusTapPosition != null)
                FocusTargetIndicator(
                  position: _focusTapPosition!,
                  isLocked: camera.settings.isFocusLocked,
                ),

              // 3. PASEK STANU AWARYJNEGO RECOVERY BANNER
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: RecoveryBanner(
                    connectionState: camera.connectionState,
                    isMasterRecordingActive: camera.recordingState == RecordingState.recording,
                    onManualReconnect: () => camera.connectToScorer(camera.pairedHostCode),
                  ),
                ),
              ),

              // 4. GÓRNY HUD TELEMETRII (WIDOCZNY GDY HUD JEST AKTYWNY)
              if (camera.settings.isHudVisible)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: _buildTopTelemetryBar(camera),
                  ),
                ),

              // 5. TABLICA WYNIKOWA OVERLAY NA ŻYWO (SCOREBOARD OVERLAY)
              if (camera.settings.isHudVisible)
                Positioned(
                  top: isLandscape ? 48 : 56,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Center(
                      child: ScoreboardOverlay(
                        session: match.session,
                        style: streamer.scoreboardStyle,
                        isTimeoutActive: match.isTimeoutActive,
                        timeoutSeconds: match.timeoutSecondsRemaining,
                        timeoutTeam: match.timeoutCallingTeam,
                        showServeIndicator: streamer.showServeIndicator,
                      ),
                    ),
                  ),
                ),

              // 6. KONTROLKI STEROWANIA KAMERĄ (ZOOM, EV, FOCUS, CZYSTY KADR)
              CameraControlsOverlay(
                camera: camera,
                isLandscape: isLandscape,
              ),

              // 7. DOLNY PASEK STEROWANIA I PRZYCISK TRANSMISJI
              if (camera.settings.isHudVisible)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: _buildBottomControlBar(context, camera, streamer, isLandscape),
                  ),
                ),

              // 8. TRYB STATYWU (OCHRONA PRZED DOTKNIĘCIEM / WYGASZANIE EKRANU)
              if (camera.isTripodLocked)
                Positioned.fill(
                  child: GestureDetector(
                    onLongPress: () => camera.toggleTripodLock(),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.92),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock, color: AppTheme.cyanAccent, size: 64),
                            const SizedBox(height: 16),
                            const Text(
                              'TRYB STATYWU AKTYWNY\n(„USTAW I ZOSTAW”)',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              camera.recordingState == RecordingState.recording
                                  ? 'Master REC trwa: ${_formatDuration(camera.masterRecDuration)}'
                                  : 'Kamera gotowa do meczu',
                              style: const TextStyle(fontSize: 13, color: AppTheme.greenLive),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceCard,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Przytrzymaj dłużej ekran, aby odblokować',
                                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCameraPreviewContent(CameraProvider camera) {
    if (camera.isCameraInitialized &&
        camera.cameraController != null &&
        camera.cameraController!.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: camera.cameraController!.value.previewSize?.height ?? 1920,
          height: camera.cameraController!.value.previewSize?.width ?? 1080,
          child: CameraPreview(camera.cameraController!),
        ),
      );
    }

    // Podgląd symulacyjny (dla emulatora, platform desktopowych i testów)
    return Container(
      color: const Color(0xFF161C2A),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: CourtPainter(zoomRatio: camera.settings.zoom),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.videocam_outlined,
                  size: 56,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 8),
                Text(
                  'PODGLĄD TRANSMISJI ${camera.settings.resolution.label.toUpperCase()} ${camera.settings.fps.label}\n${camera.settings.bitrateMbps.toStringAsFixed(1)} Mbps | ZOOM ${camera.settings.zoom.toStringAsFixed(1)}x',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withValues(alpha: 0.35),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTelemetryBar(CameraProvider camera) {
    final isRecording = camera.recordingState == RecordingState.recording;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // MASTER REC WSKAŹNIK STANU
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isRecording ? AppTheme.redLive.withValues(alpha: 0.9) : Colors.black54,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isRecording ? Colors.white70 : Colors.white24,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isRecording) ...[
                    const Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    isRecording
                        ? 'MASTER REC: ${_formatDuration(camera.masterRecDuration)}'
                        : 'MASTER REC: GOTOWY',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // PARAMETRY TRANSMISJI I KODOWANIA
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                '${camera.settings.resolution.label.split(' ').first} | ${camera.settings.fps.label} | ${camera.settings.bitrateMbps.toStringAsFixed(0)} Mbps',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
              ),
            ),
            const SizedBox(width: 8),

            // STATUS POŁĄCZENIA Z PHONE B & BATERIA
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: camera.connectionState == CameraConnectionState.connected
                        ? AppTheme.cyanAccent.withValues(alpha: 0.2)
                        : AppTheme.amberAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.wifi_tethering,
                        size: 12,
                        color: camera.connectionState == CameraConnectionState.connected
                            ? AppTheme.cyanAccent
                            : AppTheme.amberAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        camera.connectionState.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: camera.connectionState == CameraConnectionState.connected
                              ? AppTheme.cyanAccent
                              : AppTheme.amberAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    const Icon(Icons.battery_charging_full, color: AppTheme.greenLive, size: 16),
                    const SizedBox(width: 2),
                    Text(
                      '${camera.batteryLevel}%',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControlBar(
    BuildContext context,
    CameraProvider camera,
    StreamerProvider streamer,
    bool isLandscape,
  ) {
    final isRecording = camera.recordingState == RecordingState.recording;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 20 : 8,
        vertical: isLandscape ? 10 : 6,
      ),
      decoration: const BoxDecoration(
        color: Color(0xEE141923),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          // WSKAŹNIK AUDIO (VU METER)
          _buildVuMeter(camera.audioLevel),
          const SizedBox(width: 6),

          // SZYBKI WYBÓR OBIEKTYWU (0.5x, 1x, 2x)
          _buildLensSwitcher(context, camera),
          const SizedBox(width: 6),

          // GŁÓWNY PRZYCISK: "START TRANSMISJI / ZAPISU"
          Expanded(
            child: InkWell(
              onTap: () => camera.toggleMasterRecording(),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isRecording
                        ? [const Color(0xFFE53935), const Color(0xFFC62828)]
                        : [const Color(0xFF00E5FF), const Color(0xFF0091EA)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: (isRecording ? AppTheme.redLive : AppTheme.cyanAccent).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isRecording ? Icons.stop_circle : Icons.fiber_smart_record,
                      color: isRecording ? Colors.white : Colors.black,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        isRecording ? 'ZAKOŃCZ TRANSMISJĘ / ZAPIS' : 'START TRANSMISJI / ZAPISU',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isLandscape ? 12 : 10,
                          fontWeight: FontWeight.bold,
                          color: isRecording ? Colors.white : Colors.black,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // PRZYCISK USTAWIEŃ WIDEO (ROZDZIELCZOŚĆ, BITRATE, FPS)
          IconButton(
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.tune, color: AppTheme.cyanAccent, size: 20),
            tooltip: 'Parametry Wideo i Kodowania',
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => const VideoSettingsModal(),
            ),
          ),

          // PRZYCISK SCOREBOARD STUDIO
          IconButton(
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.style_outlined, color: Colors.white70, size: 19),
            tooltip: 'Scoreboard Studio',
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => const ScoreboardCustomizerModal(),
            ),
          ),

          // PRZYCISK CELE TRANSMISJI RTMP
          IconButton(
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.stream, color: AppTheme.amberAccent, size: 19),
            tooltip: 'Klucze RTMP i Platformy',
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => const StreamSettingsModal(),
            ),
          ),

          const SizedBox(width: 4),

          // PRZYCISK TRYBU STATYWU
          ElevatedButton.icon(
            onPressed: () => camera.toggleTripodLock(),
            icon: const Icon(Icons.screen_lock_portrait, size: 13),
            label: const Text('STATYW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.surfaceCard,
              foregroundColor: AppTheme.cyanAccent,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              minimumSize: const Size(50, 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVuMeter(double level) {
    return Container(
      width: 12,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: level.clamp(0.1, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [AppTheme.greenLive, AppTheme.amberAccent, AppTheme.redLive],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLensSwitcher(BuildContext context, CameraProvider camera) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: CameraLens.values.map((lens) {
          final isSelected = camera.settings.lens == lens &&
              (camera.settings.zoom - lens.zoomRatio).abs() < 0.2;
          return GestureDetector(
            onTap: () => camera.setLens(lens),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.cyanAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                lens == CameraLens.ultraWide ? '0.5x' : lens == CameraLens.wide ? '1x' : '2x',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.black : Colors.white70,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class CourtPainter extends CustomPainter {
  final double zoomRatio;
  CourtPainter({required this.zoomRatio});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final width = (size.width * 0.7) * (zoomRatio / 1.0);
    final height = (size.height * 0.5) * (zoomRatio / 1.0);

    final rect = Rect.fromCenter(center: center, width: width, height: height);
    canvas.drawRect(rect, paint);
    // Linia siatki
    canvas.drawLine(Offset(rect.left, center.dy), Offset(rect.right, center.dy), paint..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant CourtPainter oldDelegate) => oldDelegate.zoomRatio != zoomRatio;
}
