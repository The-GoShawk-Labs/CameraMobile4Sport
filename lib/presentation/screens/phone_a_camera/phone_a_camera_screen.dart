import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/router/app_router.dart';
import 'package:volleylive/core/services/wakelock_service.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/camera_config.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/recording_result.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/screens/settings/scoreboard_customizer_modal.dart';
import 'package:volleylive/presentation/screens/settings/stream_settings_modal.dart';
import 'package:volleylive/presentation/screens/settings/video_settings_modal.dart';
import 'package:volleylive/presentation/services/scoreboard_widget_burner.dart';
import 'package:volleylive/presentation/widgets/camera_controls_overlay.dart';
import 'package:volleylive/presentation/widgets/recovery_banner.dart';
import 'package:volleylive/presentation/widgets/recording_summary_dialog.dart';
import 'package:volleylive/presentation/widgets/scoreboard_overlay.dart';

class PhoneACameraScreen extends StatefulWidget {
  const PhoneACameraScreen({super.key});

  @override
  State<PhoneACameraScreen> createState() => _PhoneACameraScreenState();
}

class _PhoneACameraScreenState extends State<PhoneACameraScreen> {
  final GlobalKey _scoreboardBurnerKey = GlobalKey();
  late final ScoreboardWidgetBurner _scoreboardBurner;
  double _baseZoom = 1.0;
  Offset? _focusTapPosition;
  bool _isFocusIndicatorVisible = false;
  Timer? _focusIndicatorTimer;

  VoidCallback? _p2pListener;
  String? _lastBurnedSignature;

  @override
  void initState() {
    super.initState();
    _scoreboardBurner = ScoreboardWidgetBurner(boundaryKey: _scoreboardBurnerKey);
    // Phone A (tryb statywu "ustaw i zostaw"): zapobieganie wygaszaniu ekranu
    WakelockService.enable();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final camera = context.read<CameraProvider>();
      final match = context.read<MatchProvider>();
      final streamer = context.read<StreamerProvider>();
      final p2p = context.read<P2PConnectionProvider>();

      camera.attachMatchProvider(
        match.scoreEventsStream,
        currentSession: match.session,
        sessionStream: match.sessionStream,
      );
      streamer.attachMatchProvider(
        match.scoreEventsStream,
        currentSession: match.session,
        sessionStream: match.sessionStream,
      );
      if (!camera.isCameraInitialized && !camera.isSimulationMode) {
        await camera.initializeCamera();
      }
      ScoreboardWidgetBurner.ensureOverlayImageOnDisk(
        session: match.session,
        style: streamer.scoreboardStyle,
      );

      // Automatyczny start transmisji live po sparowaniu urządzenia Phone A
      if (p2p.currentRole == DeviceRole.cameraPhoneA || !p2p.isSinglePhoneMode) {
        if (!camera.isLiveTransmitting) {
          debugPrint('[PhoneACameraScreen] Auto-starting live transmission for paired scorer...');
          await camera.startLiveTransmission(p2pProvider: p2p);
        }
      }

      // Reaktywny nasłuch na wypadek późniejszego nawiązania połączenia przez P2P
      _p2pListener = () {
        if (!mounted) return;
        final currentP2p = context.read<P2PConnectionProvider>();
        final currentCamera = context.read<CameraProvider>();
        if (currentP2p.connectionState == CameraConnectionState.connected &&
            (currentP2p.currentRole == DeviceRole.cameraPhoneA || !currentP2p.isSinglePhoneMode) &&
            !currentCamera.isLiveTransmitting) {
          debugPrint('[PhoneACameraScreen] Dynamic P2P connection detected. Auto-starting live transmission...');
          currentCamera.startLiveTransmission(p2pProvider: currentP2p);
        }
      };
      p2p.addListener(_p2pListener!);
    });
  }

  @override
  void dispose() {
    WakelockService.disable();
    _focusIndicatorTimer?.cancel();
    if (_p2pListener != null) {
      try {
        context.read<P2PConnectionProvider>().removeListener(_p2pListener!);
      } catch (_) {}
    }
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

  Future<void> _onToggleLiveTransmission(BuildContext context, CameraProvider camera) async {
    final p2p = context.read<P2PConnectionProvider>();
    if (p2p.isSinglePhoneMode) {
      final streamer = context.read<StreamerProvider>();
      final match = context.read<MatchProvider>();
      final isLive =
          streamer.streamingState == StreamingState.live ||
          streamer.streamingState == StreamingState.connecting;
      if (isLive) {
        await streamer.toggleLiveStream(matchSession: match.session);
        return;
      }
      final streamKey = await streamer.config.resolveEffectiveStreamKey();
      if (streamer.config.serverUrl.trim().isEmpty ||
          (streamer.config.requiresStreamKey && streamKey.isEmpty)) {
        if (!context.mounted) return;
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          useRootNavigator: true,
          builder: (_) => const StreamSettingsModal(),
        );
        return;
      }
      await camera.toggleLiveTransmission(p2pProvider: p2p);
      return;
    }
    await camera.toggleLiveTransmission(p2pProvider: p2p);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: camera.isLiveTransmitting ? const Color(0xFF00B0FF) : Colors.black87,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            Icon(
              camera.isLiveTransmitting ? Icons.wifi_tethering : Icons.portable_wifi_off,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                camera.isLiveTransmitting
                    ? 'TRANSMISJA LIVE AKTYWNA (Telefon Sędziego widzi obraz kamery)'
                    : 'TRANSMISJA LIVE ZATRZYMANA',
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onToggleRecording(BuildContext context, CameraProvider camera) async {
    final wasRecording = camera.recordingState == RecordingState.recording;
    final p2p = context.read<P2PConnectionProvider>();
    final match = context.read<MatchProvider>();
    final streamer = context.read<StreamerProvider>();
    // Pobierz aktualną orientację urządzenia, aby plik MP4 zachował spójność z widokiem kamery
    final currentOrientation = MediaQuery.of(context).orientation == Orientation.landscape
        ? DeviceOrientation.landscapeLeft
        : DeviceOrientation.portraitUp;
    final recordingType = p2p.currentRole == DeviceRole.singlePhoneAllInOne
        ? camera.recordingType
        : RecordingType.rawCamera;
    await camera.toggleMasterRecording(
      p2pProvider: p2p,
      deviceOrientation: currentOrientation,
      matchSession: match.session,
      recordingType: recordingType,
      scoreboardStyle: streamer.scoreboardStyle,
    );
    if (!context.mounted) return;

    if (wasRecording) {
      if (camera.recordingState == RecordingState.saved && camera.lastRecordingResult != null) {
        _showRecordingSummaryDialog(context, camera.lastRecordingResult!);
      } else if (camera.recordingState == RecordingState.failed) {
        _showRecordingErrorNotice(context, camera.recordingErrorMessage ?? 'Nie udało się zapisać pliku wideo Master REC.');
      }
    } else {
      if (camera.recordingState == RecordingState.failed) {
        _showRecordingErrorNotice(context, camera.recordingErrorMessage ?? 'Nie udało się rozpocząć nagrywania.');
      }
    }
  }

  void _showRecordingErrorNotice(BuildContext context, String error) {
    if (error.toLowerCase().contains('przestrzeni') ||
        error.toLowerCase().contains('folderu') ||
        error.toLowerCase().contains('uprawnień')) {
      _showStorageIssueDialog(context, error);
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStorageIssueDialog(BuildContext context, String errorMessage) {
    final camera = context.read<CameraProvider>();
    final currentFolder = camera.settings.storageFolder;
    final bitrate = camera.settings.bitrateMbps;
    final gbPerHour = (bitrate * 3600) / (8 * 1024);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141923),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.amberAccent, width: 1.5)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Problem z przestrzenią lub folderem',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AKTUALNE PARAMETRY NAGRANIA',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                      ),
                      const SizedBox(height: 6),
                      Text('• Aktywny folder: $currentFolder', style: const TextStyle(color: Colors.white, fontSize: 11)),
                      Text('• Jakość wideo: ${camera.settings.resolution.label} @ ${camera.settings.fps.label}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                      Text('• Przepustowość: ${bitrate.toStringAsFixed(1)} Mbps (~${gbPerHour.toStringAsFixed(2)} GB / godzinę)', style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Dlaczego ten komunikat? Na nowszych wersjach systemu Android foldery współdzielone (Movies) mogą wymagać specjalnych uprawnień lub być zablokowane. Pamięć aplikacji (Sandbox) działa zawsze bez ograniczeń.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('ANULUJ', style: TextStyle(color: Colors.white60, fontSize: 12)),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune, size: 14, color: AppTheme.cyanAccent),
                  label: const Text('PARAMETRY WIDEO', style: TextStyle(color: AppTheme.cyanAccent, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.cyanAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => const VideoSettingsModal(),
                    );
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.shield_outlined, size: 14, color: Colors.black),
                  label: const Text('UŻYJ SANDBOX', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    Navigator.of(dialogCtx).pop();
                    await camera.setStorageFolder('master_rec');
                    if (context.mounted) {
                      final p2p = context.read<P2PConnectionProvider>();
                      final orientation = MediaQuery.of(context).orientation == Orientation.landscape
                          ? DeviceOrientation.landscapeLeft
                          : DeviceOrientation.portraitUp;
                      await camera.toggleMasterRecording(p2pProvider: p2p, deviceOrientation: orientation);
                    }
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showRecordingSummaryDialog(BuildContext context, MasterRecordingResult initialResult) {
    showDialog(
      context: context,
      builder: (ctx) => RecordingSummaryDialog(
        initialResult: initialResult,
        onMoveFolder: (newFolder) async {
          final camera = context.read<CameraProvider>();
          return await camera.moveLastRecording(newFolder);
        },
        onRecordNext: () {
          _onToggleRecording(context, context.read<CameraProvider>());
        },
      ),
    );
  }

  void _showBackgroundRecNotice(BuildContext context, CameraProvider camera) {
    if (camera.recordingState == RecordingState.recording) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10192A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(Icons.fiber_manual_record, color: AppTheme.redLive, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Kamera nagrywa Master REC w tle (${_formatDuration(camera.masterRecDuration)}). Możesz swobodnie sędziować lub analizować mecz.',
                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _handleSafeExit(BuildContext context, CameraProvider camera) {
    if (camera.recordingState == RecordingState.recording) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161F30),
          title: const Row(
            children: [
              Icon(Icons.fiber_manual_record, color: AppTheme.redLive, size: 18),
              SizedBox(width: 8),
              Text('Nagrywanie w toku', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Kamera aktualnie nagrywa Master REC. Czy chcesz kontynuować nagrywanie w tle i wyjść, czy zatrzymać nagrywanie?',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await camera.toggleMasterRecording();
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRouter.initialRoute);
                  }
                }
              },
              child: const Text('Zatrzymaj i wyjdź', style: TextStyle(color: AppTheme.redLive)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showBackgroundRecNotice(context, camera);
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRouter.initialRoute);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyanAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Kontynuuj w tle'),
            ),
          ],
        ),
      );
    } else {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRouter.initialRoute);
      }
    }
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
          streamer.updateMatchSession(match.session);
          _scoreboardBurner.captureAndPush(force: true);
        });
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSafeExit(context, camera);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxWidth > constraints.maxHeight;
          final burnSignature =
              '${match.session.teamA}:${match.session.teamB}:'
              '${match.session.currentSetPointsA}:${match.session.currentSetPointsB}:'
              '${match.session.setsA}:${match.session.setsB}:'
              '${match.session.currentSetNumber}:${match.session.currentServer.name}:'
              '${streamer.scoreboardStyle.name}:${streamer.config.anchorPosition.name}:$isLandscape';
          if (_lastBurnedSignature != burnSignature) {
            _lastBurnedSignature = burnSignature;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _scoreboardBurner.captureAndPush();
              }
            });
          }

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
                  child: _buildCameraPreviewContent(camera, isLandscape),
                ),
              ),

              // 2. WSKAŹNIK DOTKNIĘCIA DO USTAWIANIA OSTROŚCI (TAP-TO-FOCUS)
              if (_isFocusIndicatorVisible && _focusTapPosition != null)
                FocusTargetIndicator(
                  position: _focusTapPosition!,
                  isLocked: camera.settings.isFocusLocked,
                ),

              // 3. PASEK STANU AWARYJNEGO RECOVERY BANNER (TYLKO GDY PRÓBUJE WZNOWIĆ POŁĄCZENIE Z DRUGIM TELEFONEM)
              if (camera.connectionState == CameraConnectionState.reconnecting)
                Positioned(
                  top: isLandscape ? 48 : 84,
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
                    child: _buildTopTelemetryBar(camera, isLandscape),
                  ),
                ),

              // DEDYKOWANY WIDGET WYPALANIA DO STRUMIENIA WIDEO (NATIVE STREAM BURNER)
              // Karta tablicy wynikowej o proporcjach ~2.8:1 renderowana do tekstury OpenGL
              Positioned(
                left: 0,
                top: 0,
                child: Opacity(
                  opacity: 0.001,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      key: _scoreboardBurnerKey,
                      child: ScoreboardOverlay(
                        session: match.session,
                        style: streamer.scoreboardStyle,
                        isStandaloneCard: true,
                        isTimeoutActive: match.isTimeoutActive,
                        timeoutSeconds: match.timeoutSecondsRemaining,
                        timeoutTeam: match.timeoutCallingTeam,
                        showServeIndicator: streamer.showServeIndicator,
                        activeSpecialEvent: match.activeSpecialEvent,
                        matchDuration: match.matchDuration,
                        useThreeLetterAcronyms: streamer.useThreeLetterAcronyms,
                        animate: false,
                      ),
                    ),
                  ),
                ),
              ),

              // 5. TABLICA WYNIKOWA OVERLAY NA ŻYWO NA EKRANIE OPERATORA
              // Dokładnie dopasowana do aktywnego płótna wideo (16:9 lub 9:16)
              if (camera.settings.isHudVisible)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ScoreboardOverlay(
                      session: match.session,
                      style: streamer.scoreboardStyle,
                      anchorPosition: streamer.scoreboardAnchorPosition,
                      targetAspectRatio: _resolveCameraAspectRatio(
                        camera,
                        isLandscape,
                      ),
                      isTimeoutActive: match.isTimeoutActive,
                      timeoutSeconds: match.timeoutSecondsRemaining,
                      timeoutTeam: match.timeoutCallingTeam,
                      showServeIndicator: streamer.showServeIndicator,
                      activeSpecialEvent: match.activeSpecialEvent,
                      matchDuration: match.matchDuration,
                      useThreeLetterAcronyms: streamer.useThreeLetterAcronyms,
                    ),
                  ),
                ),

              // DYSKRETNY WATERMARK / BADGE MARKI (CameraMobile4Sport • GoGoShawk)
              Positioned(
                bottom: isLandscape ? 16 : 88,
                left: 16,
                child: SafeArea(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.82,
                      child: SvgPicture.asset(
                        'assets/icons/camera_overlay_badge.svg',
                        width: isLandscape ? 170 : 150,
                      ),
                    ),
                  ),
                ),
              ),

              // 6. KONTROLKI STEROWANIA KAMERĄ (ZOOM, EV, FOCUS, CZYSTY KADR)
              CameraControlsOverlay(
                camera: camera,
                isLandscape: isLandscape,
              ),

              // 6B. TRYB SOLO: MINIMALISTYCZNA NAKŁADKA HUD PUNKTACJI W STREFACH KCIUKA
              // (Swipe UP = +1 pkt, Swipe DOWN = -1 pkt, Tap = +1 pkt; środek kadru wolny dla Tap-to-Focus)
              if (camera.settings.isHudVisible &&
                  (p2p.currentRole == DeviceRole.singlePhoneAllInOne ||
                      camera.connectionState != CameraConnectionState.connected))
                _buildSoloScoreHudOverlay(context, match, isLandscape),

              // 6C. PŁYWAJĄCY PRZYCISK: EDYTUJ STYL TABLICY (NA WIERZCHU WARSTW KONTROLEK)
              if (camera.settings.isHudVisible)
                Positioned(
                  top: isLandscape ? 48 : 92,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            useRootNavigator: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const ScoreboardCustomizerModal(),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.5), width: 1),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.palette_outlined, size: 15, color: AppTheme.cyanAccent),
                              SizedBox(width: 6),
                              Text(
                                'Tablica Studio',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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
    ),
  );
}

  double _resolveCameraAspectRatio(CameraProvider camera, bool isLandscape) {
    if (camera.isCameraInitialized &&
        camera.cameraController != null &&
        camera.cameraController!.value.isInitialized) {
      final previewSize = camera.cameraController!.value.previewSize;
      final double pWidth = previewSize?.width ?? 1920.0;
      final double pHeight = previewSize?.height ?? 1080.0;
      final double sensorLong = pWidth > pHeight ? pWidth : pHeight;
      final double sensorShort = pWidth > pHeight ? pHeight : pWidth;
      return isLandscape
          ? (sensorLong / sensorShort)
          : (sensorShort / sensorLong);
    }
    return isLandscape ? (16.0 / 9.0) : (9.0 / 16.0);
  }

  Widget _buildCameraPreviewContent(CameraProvider camera, bool isLandscape) {
    if (camera.isCameraInitialized &&
        camera.cameraController != null &&
        camera.cameraController!.value.isInitialized) {
      final controller = camera.cameraController!;
      final previewSize = controller.value.previewSize;

      final double pWidth = previewSize?.width ?? 1920.0;
      final double pHeight = previewSize?.height ?? 1080.0;
      final double sensorLong = pWidth > pHeight ? pWidth : pHeight;
      final double sensorShort = pWidth > pHeight ? pHeight : pWidth;

      final double targetWidth = isLandscape ? sensorLong : sensorShort;
      final double targetHeight = isLandscape ? sensorShort : sensorLong;
      final double targetAspectRatio = targetWidth / targetHeight;

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
    }

    // Podgląd symulacyjny (dla emulatora, platform desktopowych i testów)
    return Container(
      color: const Color(0xFF161C2A),
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: isLandscape ? (16 / 9) : (9 / 16),
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
      ),
    );
  }

  Widget _buildTopTelemetryBar(CameraProvider camera, bool isLandscape) {
    final isRecording = camera.recordingState == RecordingState.recording;

    if (!isLandscape) {
      // UKŁAD PIONOWY (PORTRAIT) - DWIE ERGONOMICZNE LINIE Z DUŻYMI ELEMENTAMI DOTYKOWYMI
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // RZĄD 1: NAWIGACJA, TRYBY I UKRYWANIE KADRU
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  // PRZYCISK MENU GŁÓWNEGO
                  InkWell(
                    onTap: () => _handleSafeExit(context, camera),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 12),
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

                  // PRZEŁĄCZNIK: SĘDZIA
                  InkWell(
                    onTap: () {
                      _showBackgroundRecNotice(context, camera);
                      context.push(AppRouter.scorerRoute);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.amberAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.amberAccent.withValues(alpha: 0.6)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sports_volleyball, size: 13, color: AppTheme.amberAccent),
                          SizedBox(width: 4),
                          Text(
                            'SĘDZIA',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppTheme.amberAccent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // PRZEŁĄCZNIK: STATYSTYKI
                  InkWell(
                    onTap: () {
                      _showBackgroundRecNotice(context, camera);
                      context.push(AppRouter.statisticianRoute);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.6)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.analytics_outlined, size: 13, color: Color(0xFF00E676)),
                          SizedBox(width: 4),
                          Text(
                            'STATYSTYKI',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF00E676)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // PRZYCISK CZYSTY KADR (UKRYWANIE HUD)
                  InkWell(
                    onTap: () => camera.toggleHudVisibility(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fullscreen, color: Colors.white70, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'KADR',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // RZĄD 2: TELEMETRIA, MASTER REC I STATUS
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  // LIVE TRANSMISSION STATUS BADGE
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: camera.isLiveTransmitting
                          ? AppTheme.greenLive.withValues(alpha: 0.25)
                          : Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: camera.isLiveTransmitting ? AppTheme.greenLive : Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          camera.isLiveTransmitting ? Icons.wifi_tethering : Icons.portable_wifi_off,
                          color: camera.isLiveTransmitting ? AppTheme.greenLive : Colors.white60,
                          size: 11,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          camera.isLiveTransmitting ? 'LIVE ON' : 'LIVE OFF',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: camera.isLiveTransmitting ? AppTheme.greenLive : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // MASTER REC STATUS
                  InkWell(
                    onTap: () {
                      if (camera.recordingState == RecordingState.saved && camera.lastRecordingResult != null) {
                        _showRecordingSummaryDialog(context, camera.lastRecordingResult!);
                      } else if (camera.recordingState == RecordingState.failed && camera.recordingErrorMessage != null) {
                        _showRecordingErrorNotice(context, camera.recordingErrorMessage!);
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isRecording
                            ? AppTheme.redLive.withValues(alpha: 0.9)
                            : camera.recordingState == RecordingState.failed
                                ? Colors.red.shade900.withValues(alpha: 0.9)
                                : Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isRecording
                              ? Colors.white70
                              : camera.recordingState == RecordingState.saved
                                  ? AppTheme.greenLive
                                  : Colors.white24,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            camera.recordingState == RecordingState.saved
                                ? Icons.check_circle
                                : camera.recordingState == RecordingState.failed
                                    ? Icons.error_outline
                                    : Icons.fiber_manual_record,
                            color: isRecording
                                ? Colors.white
                                : camera.recordingState == RecordingState.saved
                                    ? AppTheme.greenLive
                                    : camera.recordingState == RecordingState.failed
                                        ? Colors.white
                                        : AppTheme.greenLive,
                            size: 10,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isRecording
                                ? 'REC: ${_formatDuration(camera.masterRecDuration)}'
                                : camera.recordingState == RecordingState.saved && camera.lastRecordingResult != null
                                    ? 'REC: ZAPISANO (${camera.lastRecordingResult!.formattedSize})'
                                    : camera.recordingState == RecordingState.failed
                                        ? 'REC: BŁĄD'
                                        : 'REC: GOTOWY',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // PARAMETRY TRANSMISJI I PROPORCJE KADRU
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${camera.settings.resolution.label.split(' ').first} | ${camera.settings.fps.label} | ${camera.settings.bitrateMbps.toStringAsFixed(0)}M',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.deepPurpleAccent.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '9:16',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.purpleAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // STATUS POŁĄCZENIA
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: camera.connectionState == CameraConnectionState.connected
                          ? AppTheme.cyanAccent.withValues(alpha: 0.2)
                          : AppTheme.amberAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_tethering,
                          size: 11,
                          color: camera.connectionState == CameraConnectionState.connected
                              ? AppTheme.cyanAccent
                              : AppTheme.amberAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          camera.connectionState == CameraConnectionState.connected
                              ? 'ONLINE'
                              : 'OFFLINE',
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
                  const SizedBox(width: 6),

                  // BATERIA
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.battery_charging_full, color: AppTheme.greenLive, size: 15),
                      const SizedBox(width: 2),
                      Text(
                        '${camera.batteryLevel}%',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // UKŁAD POZIOMY (LANDSCAPE)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            // PRZYCISK WYJŚCIA DO MENU GŁÓWNEGO
            InkWell(
              onTap: () => _handleSafeExit(context, camera),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 12),
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

            // SZYBKIE PRZEŁĄCZNIKI TRYBÓW (SĘDZIA / STATYSTYK) + KADR
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    _showBackgroundRecNotice(context, camera);
                    context.push(AppRouter.scorerRoute);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.amberAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.amberAccent.withValues(alpha: 0.6)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sports_volleyball, size: 13, color: AppTheme.amberAccent),
                        SizedBox(width: 4),
                        Text(
                          'SĘDZIA',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.amberAccent),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    _showBackgroundRecNotice(context, camera);
                    context.push(AppRouter.statisticianRoute);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.6)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.analytics_outlined, size: 13, color: Color(0xFF00E676)),
                        SizedBox(width: 4),
                        Text(
                          'STATYSTYKI',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF00E676)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => camera.toggleHudVisibility(),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fullscreen, color: Colors.white70, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'CZYSTY KADR',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),

            // MASTER REC WSKAŹNIK STANU
            InkWell(
              onTap: () {
                if (camera.recordingState == RecordingState.saved && camera.lastRecordingResult != null) {
                  _showRecordingSummaryDialog(context, camera.lastRecordingResult!);
                } else if (camera.recordingState == RecordingState.failed && camera.recordingErrorMessage != null) {
                  _showRecordingErrorNotice(context, camera.recordingErrorMessage!);
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isRecording
                      ? AppTheme.redLive.withValues(alpha: 0.9)
                      : camera.recordingState == RecordingState.failed
                          ? Colors.red.shade900.withValues(alpha: 0.9)
                          : Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isRecording
                        ? Colors.white70
                        : camera.recordingState == RecordingState.saved
                            ? AppTheme.greenLive
                            : Colors.white24,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      camera.recordingState == RecordingState.saved
                          ? Icons.check_circle
                          : camera.recordingState == RecordingState.failed
                              ? Icons.error_outline
                              : Icons.fiber_manual_record,
                      color: isRecording
                          ? Colors.white
                          : camera.recordingState == RecordingState.saved
                              ? AppTheme.greenLive
                              : camera.recordingState == RecordingState.failed
                                  ? Colors.white
                                  : AppTheme.greenLive,
                      size: 11,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isRecording
                          ? 'REC: ${_formatDuration(camera.masterRecDuration)}'
                          : camera.recordingState == RecordingState.saved && camera.lastRecordingResult != null
                              ? 'REC: ZAPISANO (${camera.lastRecordingResult!.formattedSize})'
                              : camera.recordingState == RecordingState.failed
                                  ? 'REC: BŁĄD'
                                  : 'MASTER REC: GOTOWY',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // PARAMETRY TRANSMISJI I KODOWANIA ORAZ PROPORCJE KADRU
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${camera.settings.resolution.label.split(' ').first} | ${camera.settings.fps.label} | ${camera.settings.bitrateMbps.toStringAsFixed(0)}M',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: AppTheme.cyanAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      '16:9 STREAM',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: AppTheme.cyanAccent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // STATUS POŁĄCZENIA Z PHONE B & BATERIA
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                        camera.connectionState == CameraConnectionState.connected
                            ? 'ONLINE'
                            : 'OFFLINE',
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
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
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

    if (!isLandscape) {
      // UKŁAD PIONOWY (PORTRAIT) - DWA RZĘDY: GŁÓWNY PRZYCISK REC (HERO) + KONTROLKI KAMERY
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: Color(0xEE141923),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // RZĄD 1: HERO ACTION - GŁÓWNY PRZYCISK NAGRYWANIA + VU METER + STATYW
            Row(
              children: [
                _buildVuMeter(camera.audioLevel),
                const SizedBox(width: 8),

                // GŁÓWNY PRZYCISK 1: "TRANSMISJA LIVE" (BEZ NAGRYWANIA)
                Expanded(
                  child: InkWell(
                    onTap: () => _onToggleLiveTransmission(context, camera),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: camera.isLiveTransmitting
                              ? [const Color(0xFF00E676), const Color(0xFF00B0FF)]
                              : [const Color(0xFF00E5FF), const Color(0xFF0091EA)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: (camera.isLiveTransmitting ? AppTheme.greenLive : AppTheme.cyanAccent).withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            camera.isLiveTransmitting ? Icons.wifi_tethering : Icons.cell_tower,
                            color: Colors.black,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              camera.isLiveTransmitting ? 'TRANSMISJA ON' : 'TRANSMISJA',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // GŁÓWNY PRZYCISK 2: MASTER REC (SPRZĘTOWY ZAPIS MP4)
                InkWell(
                  onTap: () => _onToggleRecording(context, camera),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isRecording ? AppTheme.redLive : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isRecording ? Colors.white : AppTheme.redLive,
                        width: 1.5,
                      ),
                      boxShadow: [
                        if (isRecording)
                          BoxShadow(
                            color: AppTheme.redLive.withValues(alpha: 0.5),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                          color: isRecording ? Colors.white : AppTheme.redLive,
                          size: 16,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isRecording ? 'STOP' : 'REC',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: isRecording ? Colors.white : AppTheme.redLive,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // PRZYCISK STATYWU
                InkWell(
                  onTap: () => camera.toggleTripodLock(),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.screen_lock_portrait, size: 16, color: AppTheme.cyanAccent),
                        SizedBox(height: 2),
                        Text(
                          'STATYW',
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // RZĄD 2: SZYBKI WYBÓR OBIEKTYWU + USTAWIENIA MODALNE
            Row(
              children: [
                // Szybki wybór obiektywu
                _buildLensSwitcher(context, camera),
                const Spacer(),

                // USTAWIENIA WIDEO (ROZDZIELCZOŚĆ, BITRATE, FPS)
                _buildQuickIconButton(
                  icon: Icons.tune,
                  color: AppTheme.cyanAccent,
                  tooltip: 'Parametry Wideo i Kodowania',
                  onTap: () => showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => const VideoSettingsModal(),
                  ),
                ),
                const SizedBox(width: 8),

                // SCOREBOARD STUDIO
                _buildQuickIconButton(
                  icon: Icons.palette_outlined,
                  color: AppTheme.cyanAccent,
                  tooltip: 'Scoreboard Studio',
                  onTap: () => showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    useRootNavigator: true,
                    builder: (_) => const ScoreboardCustomizerModal(),
                  ),
                ),
                const SizedBox(width: 8),

                // KLUCZE RTMP I PLATFORMY
                _buildQuickIconButton(
                  icon: Icons.stream,
                  color: AppTheme.amberAccent,
                  tooltip: 'Klucze RTMP i Platformy',
                  onTap: () => showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    useRootNavigator: true,
                    builder: (_) => const StreamSettingsModal(),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // UKŁAD POZIOMY (LANDSCAPE)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xEE141923),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          _buildVuMeter(camera.audioLevel),
          const SizedBox(width: 10),
          _buildLensSwitcher(context, camera),
          const SizedBox(width: 12),

          // GŁÓWNY PRZYCISK 1: "START TRANSMISJI" (BEZ NAGRYWANIA)
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () => _onToggleLiveTransmission(context, camera),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: camera.isLiveTransmitting
                        ? [const Color(0xFF00E676), const Color(0xFF00B0FF)]
                        : [const Color(0xFF00E5FF), const Color(0xFF0091EA)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: (camera.isLiveTransmitting ? AppTheme.greenLive : AppTheme.cyanAccent).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        camera.isLiveTransmitting ? Icons.wifi_tethering : Icons.cell_tower,
                        color: Colors.black,
                        size: 18,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        camera.isLiveTransmitting ? 'TRANSMISJA ON' : 'START TRANSMISJI',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // GŁÓWNY PRZYCISK 2: MASTER REC
          InkWell(
            onTap: () => _onToggleRecording(context, camera),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isRecording ? AppTheme.redLive : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isRecording ? Colors.white : AppTheme.redLive,
                  width: 1.5,
                ),
                boxShadow: [
                  if (isRecording)
                    BoxShadow(
                      color: AppTheme.redLive.withValues(alpha: 0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                    color: isRecording ? Colors.white : AppTheme.redLive,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isRecording ? 'REC STOP' : 'REC',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: isRecording ? Colors.white : AppTheme.redLive,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          _buildQuickIconButton(
            icon: Icons.tune,
            color: AppTheme.cyanAccent,
            tooltip: 'Parametry Wideo i Kodowania',
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              useRootNavigator: true,
              builder: (_) => const VideoSettingsModal(),
            ),
          ),
          const SizedBox(width: 6),

          _buildQuickIconButton(
            icon: Icons.palette_outlined,
            color: AppTheme.cyanAccent,
            tooltip: 'Scoreboard Studio',
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              useRootNavigator: true,
              builder: (_) => const ScoreboardCustomizerModal(),
            ),
          ),
          const SizedBox(width: 6),

          _buildQuickIconButton(
            icon: Icons.stream,
            color: AppTheme.amberAccent,
            tooltip: 'Klucze RTMP i Platformy',
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              useRootNavigator: true,
              builder: (_) => const StreamSettingsModal(),
            ),
          ),
          const SizedBox(width: 8),

          // PRZYCISK TRYBU STATYWU
          ElevatedButton.icon(
            onPressed: () => camera.toggleTripodLock(),
            icon: const Icon(Icons.screen_lock_portrait, size: 14),
            label: const Text('STATYW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.surfaceCard,
              foregroundColor: AppTheme.cyanAccent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(60, 36),
            ),
          ),
        ],
      ),
    );
  }

  /// Minimalistyczna nakładka HUD dla Trybu Solo (strefy kciuka na krawędziach kadru)
  Widget _buildSoloScoreHudOverlay(
    BuildContext context,
    MatchProvider match,
    bool isLandscape,
  ) {
    final session = match.session;
    return Positioned(
      bottom: isLandscape ? 78 : 148,
      left: 14,
      right: isLandscape ? 82 : 76, // Zostawia miejsce na boczny pasek CameraControlsOverlay po prawej
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Lewa strefa kciuka: Team A
            _buildSoloThumbZoneCard(
              label: session.teamAShortCode,
              points: session.currentSetPointsA,
              color: session.teamAColor,
              isServing: session.currentServer == ServingTeam.teamA,
              onAddPoint: () {
                HapticFeedback.lightImpact();
                match.addPointA(points: 1);
                _scoreboardBurner.captureAndPush(force: true);
              },
              onSubtractPoint: () {
                HapticFeedback.mediumImpact();
                match.subtractPointA();
                _scoreboardBurner.captureAndPush(force: true);
              },
              onToggleServe: () {
                HapticFeedback.selectionClick();
                match.toggleRotation();
                _scoreboardBurner.captureAndPush(force: true);
              },
            ),

            // Prawa strefa kciuka: Team B
            _buildSoloThumbZoneCard(
              label: session.teamBShortCode,
              points: session.currentSetPointsB,
              color: session.teamBColor,
              isServing: session.currentServer == ServingTeam.teamB,
              onAddPoint: () {
                HapticFeedback.lightImpact();
                match.addPointB(points: 1);
                _scoreboardBurner.captureAndPush(force: true);
              },
              onSubtractPoint: () {
                HapticFeedback.mediumImpact();
                match.subtractPointB();
                _scoreboardBurner.captureAndPush(force: true);
              },
              onToggleServe: () {
                HapticFeedback.selectionClick();
                match.toggleRotation();
                _scoreboardBurner.captureAndPush(force: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoloThumbZoneCard({
    required String label,
    required int points,
    required Color color,
    required bool isServing,
    required VoidCallback onAddPoint,
    required VoidCallback onSubtractPoint,
    required VoidCallback onToggleServe,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAddPoint,
      onLongPress: onToggleServe,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -150) {
          onAddPoint(); // Swipe UP = +1 pkt
        } else if (velocity > 150) {
          onSubtractPoint(); // Swipe DOWN = -1 pkt
        }
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 74, minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isServing ? color : color.withValues(alpha: 0.45),
            width: isServing ? 2.0 : 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isServing) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '$points',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              '▲+1  ▼-1',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 42,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Widget _buildVuMeter(double level) {
    return Container(
      width: 12,
      height: 48,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.cyanAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                lens == CameraLens.ultraWide ? '0.5x' : lens == CameraLens.wide ? '1x' : '2x',
                style: TextStyle(
                  fontSize: 11,
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
