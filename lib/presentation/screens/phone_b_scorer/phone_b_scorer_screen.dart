import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/router/app_router.dart';
import 'package:volleylive/core/services/wakelock_service.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/recording_result.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/domain/services/native_stream_burner_bridge.dart';
import 'package:volleylive/domain/services/video_overlay_burner_service.dart';
import 'package:volleylive/presentation/services/program_widget_capture.dart';
import 'package:volleylive/presentation/screens/settings/camera_connection_modal.dart';
import 'package:volleylive/presentation/screens/settings/scoreboard_customizer_modal.dart';
import 'package:volleylive/presentation/screens/settings/storage_folder_picker_modal.dart';
import 'package:volleylive/presentation/screens/settings/stream_settings_modal.dart';
import 'package:volleylive/presentation/screens/settings/video_settings_modal.dart';
import 'package:volleylive/presentation/widgets/adaptive_camera_preview.dart';
import 'package:volleylive/presentation/widgets/recording_summary_dialog.dart';
import 'package:volleylive/presentation/widgets/recovery_banner.dart';
import 'package:volleylive/presentation/widgets/sports_ui_components.dart';
import 'package:volleylive/presentation/widgets/scoreboard_overlay.dart';
import 'package:volleylive/presentation/widgets/tactile_score_pad.dart';

class PhoneBScorerScreen extends StatefulWidget {
  const PhoneBScorerScreen({super.key});

  @override
  State<PhoneBScorerScreen> createState() => _PhoneBScorerScreenState();
}

class _PhoneBScorerScreenState extends State<PhoneBScorerScreen>
    with SingleTickerProviderStateMixin {
  int _selectedNavIndex = 0;
  AnimationController? _unlockHoldController;
  bool _showLocalCameraPreview = true;
  bool _isControlsHidden = false;
  bool _isLandscapeFullScreenPreview = false;
  Timer? _streamTimeoutTimer;
  StreamerProvider? _streamerRef;
  StreamingState _previousStreamingState = StreamingState.idle;
  bool? _lastKeepAwakeState;
  bool? _lastOrientationIsPortrait;
  final GlobalKey _broadcastStreamSurfaceKey = GlobalKey(
    debugLabel: 'broadcast_stream_surface_key',
  );
  late final ProgramWidgetCapture _programCapture = ProgramWidgetCapture(
    boundaryKey: GlobalKey(),
    isSourceAvailable: _isProgramVideoSourceAvailable,
  );

  bool _isCameraToggling = false;

  /// Płynne, bezpieczne przejście na Tryb Solo (Kamera Lokalna) z bezwzględnym zachowaniem stanu meczu
  Future<void> _switchToSoloMode() async {
    if (_isCameraToggling) return;
    _isCameraToggling = true;
    try {
      final p2p = context.read<P2PConnectionProvider>();
      final camera = context.read<CameraProvider>();
      final isStreamingLive = NativeStreamBurnerBridge().isStreaming || NativeStreamBurnerBridge().isRecording;

      HapticFeedback.mediumImpact();
      await p2p.switchToSoloMode();
      setState(() {
        _showLocalCameraPreview = true;
      });

      if (!isStreamingLive && !camera.isCameraInitialized && !camera.isSimulationMode) {
        await camera.initializeCamera();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.phone_android, color: Colors.black, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aktywowano Tryb Solo (Kamera Lokalna). Wynik meczu zachowany!',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.cyanAccent,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCameraToggling = false);
      }
    }
  }

  /// Płynne przejście na Tryb Dwóch Smartfonów (Dual - Phone B Scorer + Phone A Kamera)
  Future<void> _switchToDualMode() async {
    if (_isCameraToggling) return;
    _isCameraToggling = true;
    try {
      final p2p = context.read<P2PConnectionProvider>();
      final camera = context.read<CameraProvider>();

      HapticFeedback.mediumImpact();
      if (camera.isCameraInitialized) {
        await camera.releaseCameraForExternalStreamer();
      }
      p2p.switchToDualMode(role: DeviceRole.scorerPhoneB);
      setState(() {
        _showLocalCameraPreview = true;
      });

      if (mounted) {
        _openCameraConnectionModal(context);
      }
    } finally {
      if (mounted) {
        setState(() => _isCameraToggling = false);
      }
    }
  }

  /// Dialog potwierdzenia awaryjnego przełączenia na Tryb Solo (np. gdy Phone A się rozładuje)
  Future<void> _showEmergencySwitchToSoloDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.amberAccent, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.amberAccent, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Awaryjne przełączenie na Solo',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Telefon A (kamera na statywie) utracił łączność lub rozładowała się bateria.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            SizedBox(height: 12),
            Text(
              '• Przełączenie aktywuje lokalną kamerę w tym telefonie.\n'
              '• Aktualny wynik meczu, sety i zegar zostaną w 100% zachowane.\n'
              '• Po powrocie zasilania w Phone A możesz w każdej chwili wrócić do trybu Dual.',
              style: TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ANULUJ', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.videocam, size: 16),
            label: const Text('PRZEŁĄCZ NA SOLO'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amberAccent,
              foregroundColor: Colors.black,
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _switchToSoloMode();
    }
  }

  /// Dialog potwierdzenia zmiany trybu (z Solo na Dual lub odwrotnie)
  Future<void> _showModeSwitchConfirmationDialog({required bool toSolo}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: toSolo ? AppTheme.cyanAccent : AppTheme.greenLive,
            width: 1.5,
          ),
        ),
        title: Row(
          children: [
            Icon(
              toSolo ? Icons.phone_android : Icons.phonelink,
              color: toSolo ? AppTheme.cyanAccent : AppTheme.greenLive,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                toSolo ? 'Przełącz na Tryb Solo' : 'Przełącz na Tryb Dual',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              toSolo
                  ? 'Czy na pewno chcesz przełączyć się na Tryb Jednego Telefonu (Solo)? Transmisja będzie prowadzona z kamery tego telefonu.'
                  : 'Czy na pewno chcesz połączyć z kamerą Phone A na statywie (Tryb Dwóch Telefonów)?',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: AppTheme.greenLive, size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Wynik meczu, czas gry i sety pozostaną bez zmian.',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ANULUJ', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: toSolo ? AppTheme.cyanAccent : AppTheme.greenLive,
              foregroundColor: Colors.black,
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            child: Text(toSolo ? 'WŁĄCZ TRYB SOLO' : 'WŁĄCZ TRYB DUAL'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (toSolo) {
        await _switchToSoloMode();
      } else {
        await _switchToDualMode();
      }
    }
  }

  /// Informacyjny BottomSheet ze szczegółami aktywnego trybu i możliwością bezpiecznej zmiany
  void _showModeDetailsModal(
    BuildContext context,
    bool isSingleMode,
    P2PConnectionProvider p2p,
    StreamerProvider streamer,
    CameraProvider camera,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101726),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Colors.white12),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isSingleMode
                            ? AppTheme.cyanAccent
                            : (p2p.connectionState == CameraConnectionState.connected
                                ? AppTheme.greenLive
                                : Colors.redAccent),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isSingleMode ? 'TRYB SOLO (1 SMARTFON)' : 'TRYB DUAL (2 SMARTFONY)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF162133),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSingleMode
                        ? 'Wszystko w jednym: ten telefon nagrywa / transmituje przez kamerę wbudowaną oraz steruje tablicą wyników.'
                        : 'Podział ról: ten telefon to Panel Sędziego (Phone B), a obraz pobierany jest bezprzewodowo z Phone A na statywie.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 10),
                  if (isSingleMode) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Kamera lokalna:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        Text(
                          '${camera.settings.resolution.label} • ${camera.settings.fps.label}',
                          style: const TextStyle(color: AppTheme.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Enkoder sprzętowy:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        Text(
                          NativeStreamBurnerBridge().isStreaming || NativeStreamBurnerBridge().isRecording
                              ? 'AKTYWNY (RootEncoder)'
                              : 'GOTOWY',
                          style: const TextStyle(color: AppTheme.greenLive, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Stan połączenia z Phone A:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        Text(
                          p2p.connectionState == CameraConnectionState.connected
                              ? 'POŁĄCZONO (${p2p.healthMetrics.latencyMs} ms)'
                              : 'ROZŁĄCZONO',
                          style: TextStyle(
                            color: p2p.connectionState == CameraConnectionState.connected
                                ? AppTheme.greenLive
                                : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Adres nadajnika Phone A:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        Text(
                          p2p.hostAddress.isNotEmpty ? p2p.hostAddress : 'Brak',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _showModeSwitchConfirmationDialog(toSolo: !isSingleMode);
                },
                icon: Icon(isSingleMode ? Icons.phonelink : Icons.phone_android, size: 18),
                label: Text(
                  isSingleMode
                      ? 'PRZEŁĄCZ NA TRYB DWÓCH TELEFONÓW (DUAL)'
                      : 'PRZEŁĄCZ NA TRYB JEDNEGO TELEFONU (SOLO)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSingleMode ? AppTheme.greenLive : AppTheme.cyanAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onStreamerStateChanged() {
    if (!mounted || _streamerRef == null) return;
    final current = _streamerRef!.streamingState;
    if (_previousStreamingState != current) {
      if (current == StreamingState.failed &&
          _previousStreamingState != StreamingState.failed) {
        if (_streamerRef!.programRecState != RecordingState.recording) {
          _programCapture.stop();
        }
        final errorMsg = _streamerRef!.streamingErrorMessage ??
            'Transmisja na żywo została przerwana. Sprawdź połączenie z serwerem RTMP i sieć Wi-Fi.';
        _showRecordingErrorNotice(context, errorMsg);
      }
      _previousStreamingState = current;
    }
  }

  void _evaluateStreamTimeout(P2PConnectionProvider p2p) {
    final shouldMonitor = !p2p.isSinglePhoneMode &&
        p2p.connectionState == CameraConnectionState.connected &&
        p2p.currentVideoFrame == null;

    if (!shouldMonitor) {
      if (_streamTimeoutTimer != null) {
        _streamTimeoutTimer?.cancel();
        _streamTimeoutTimer = null;
      }
      if (p2p.hasStreamTimeout) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.read<P2PConnectionProvider>().clearStreamTimeout();
          }
        });
      }
      return;
    }

    if (_streamTimeoutTimer == null && !p2p.hasStreamTimeout) {
      _streamTimeoutTimer = Timer(const Duration(seconds: 12), () {
        if (!mounted) return;
        final currentP2p = context.read<P2PConnectionProvider>();
        if (currentP2p.connectionState == CameraConnectionState.connected &&
            currentP2p.currentVideoFrame == null) {
          currentP2p.setStreamTimeout(true);
        }
      });
    }
  }

  bool _isProgramVideoSourceAvailable() {
    if (!mounted) return false;
    final p2p = context.read<P2PConnectionProvider>();
    if (p2p.currentRole == DeviceRole.singlePhoneAllInOne) {
      return true;
    }
    return (p2p.connectionState == CameraConnectionState.connected &&
            p2p.hasFreshVideoFrame) ||
        context.read<CameraProvider>().isCameraInitialized;
  }

  Future<Uint8List?> _ensureProgramCapture({
    int framesPerSecond = 10,
    int targetWidth = 1920,
    int targetHeight = 1080,
  }) async {
    if (_programCapture.isCapturing) {
      return _programCapture.captureFrame(reuseLastIfBusy: true);
    }
    return _programCapture.start(
      framesPerSecond: framesPerSecond,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
  }

  Future<void> _onToggleLiveStream(
    BuildContext context,
    StreamerProvider streamer,
    MatchProvider match,
  ) async {
    final p2p = context.read<P2PConnectionProvider>();
    final camera = context.read<CameraProvider>();
    final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;

    final isLive =
        streamer.streamingState == StreamingState.live ||
        streamer.streamingState == StreamingState.connecting ||
        streamer.streamingState == StreamingState.reconnecting;
    if (isLive) {
      await streamer.toggleLiveStream(
        matchSession: match.session,
        isPortrait: isPortrait,
      );
      _programCapture.stop();
      if (p2p.currentRole == DeviceRole.singlePhoneAllInOne &&
          !camera.isCameraInitialized &&
          !camera.isSimulationMode) {
        await camera.initializeCamera();
      }
      return;
    }

    // JEŚLI TRANSMISJA NIE JEST SKONFIGUROWANA, NATYCHMIAST OTWÓRZ OKNO KONFIGURACJI RTMP
    final config = streamer.config;
    final streamKey = await config.resolveEffectiveStreamKey();
    if (config.serverUrl.trim().isEmpty || (config.requiresStreamKey && streamKey.isEmpty)) {
      if (context.mounted) {
        _openStreamSettings(context);
      }
      return;
    }

    if (!context.mounted) return;

    // Pobierz identyfikator współdzielonej tekstury OpenGL przed zwolnieniem lokalnego kontrolera CameraX/Camera2
    await streamer.ensurePreviewTextureId();
    await streamer.updateStreamOrientation(isPortrait: isPortrait);

    // Zatrzymaj całkowicie przechwytywanie PNG na CPU oraz zwolnij sensor Camera2 dla natywnego RootEncoder
    _programCapture.stop();
    if (camera.isCameraInitialized) {
      await camera.releaseCameraForExternalStreamer();
    }

    // Prześlij aktualny stan wyniku i pozycję tablicy do natywnego mostka przed startem
    await NativeStreamBurnerBridge().setScoreboardPosition(
      streamer.scoreboardAnchorPosition.name,
    );
    streamer.updateMatchSession(match.session);

    final started = await streamer.toggleLiveStream(
      matchSession: match.session,
      isPortrait: isPortrait,
    );
    if (!started && context.mounted) {
      if (p2p.currentRole == DeviceRole.singlePhoneAllInOne &&
          !camera.isCameraInitialized &&
          !camera.isSimulationMode) {
        await camera.initializeCamera();
      }
      if (!context.mounted) return;
      final errorMsg = streamer.streamingErrorMessage ??
          'Nie udało się uruchomić sprzętowego strumieniowania RTMP (RootEncoder). Sprawdź ustawienia RTMP i klucz transmisji.';
      _showRecordingErrorNotice(
        context,
        errorMsg,
      );
      if (errorMsg.toLowerCase().contains('klucz') ||
          errorMsg.toLowerCase().contains('rtmp') ||
          errorMsg.toLowerCase().contains('ustawieniach') ||
          errorMsg.toLowerCase().contains('brak adresu')) {
        _openStreamSettings(context);
      }
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '${d.inHours > 0 ? '${twoDigits(d.inHours)}:' : ''}$minutes:$seconds';
  }

  void _showRecordingSummaryDialog(
    BuildContext context,
    MasterRecordingResult result,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecordingSummaryDialog(
        initialResult: result,
        onMoveFolder: (newFolder) async {
          final p2p = context.read<P2PConnectionProvider>();
          final isSingleMode =
              p2p.currentRole == DeviceRole.singlePhoneAllInOne;
          if (isSingleMode) {
            return await context.read<CameraProvider>().moveLastRecording(
              newFolder,
            );
          } else {
            return await context
                .read<StreamerProvider>()
                .moveLastProgramRecording(newFolder);
          }
        },
        onRecordNext: () {
          // Gotowy na następne nagranie
        },
      ),
    );
  }

  void _showRecordingErrorNotice(BuildContext context, String rawError) {
    if (rawError.toLowerCase().contains('przestrzeni') ||
        rawError.toLowerCase().contains('folderu') ||
        rawError.toLowerCase().contains('uprawnień')) {
      _showStorageIssueDialog(context, rawError);
      return;
    }

    final isStreamIssue = rawError.toLowerCase().contains('klucz') ||
        rawError.toLowerCase().contains('rtmp') ||
        rawError.toLowerCase().contains('transmisj') ||
        rawError.toLowerCase().contains('połączeni') ||
        rawError.toLowerCase().contains('odrzucono') ||
        rawError.toLowerCase().contains('serwer');

    // Oczyszczamy nagłówki kompilatora FFmpeg jeśli trafiły do błędu
    final displayError = VideoOverlayBurnerService.extractCleanFfmpegError(rawError);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 6),
        action: isStreamIssue
            ? SnackBarAction(
                label: 'USTAWIENIA',
                textColor: Colors.white,
                onPressed: () => _openStreamSettings(context),
              )
            : null,
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayError,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStorageIssueDialog(BuildContext context, String error) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF141A26),
        title: const Row(
          children: [
            Icon(
              Icons.folder_off_outlined,
              color: AppTheme.amberAccent,
              size: 24,
            ),
            SizedBox(width: 8),
            Text(
              'Wymagany Folder Zapisu',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Aplikacja spróbuje zapisać plik w bezpiecznym folderze tymczasowym. '
              'Możesz też wskazać inny folder w pamięci telefonu.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(
              'ANULUJ',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await showModalBottomSheet<String>(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const StorageFolderPickerModal(),
              );
            },
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('WYBIERZ FOLDER'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amberAccent,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleToggleRecording(BuildContext context) async {
    final p2p = context.read<P2PConnectionProvider>();
    final match = context.read<MatchProvider>();
    final camera = context.read<CameraProvider>();
    final streamer = context.read<StreamerProvider>();

    final isSingleMode = p2p.currentRole == DeviceRole.singlePhoneAllInOne;

    if (isSingleMode) {
      // W trybie All-in-One nagrywamy przez CameraProvider (RAW / PROGRAM / DUAL wg wybranego camera.recordingType)
      final wasRecording = camera.recordingState == RecordingState.recording;
      if (camera.recordingState == RecordingState.stopping) return;

      final selectedType = wasRecording
          ? camera.activeRecordingType ?? camera.recordingType
          : camera.recordingType;
      final isLandscape =
          MediaQuery.of(context).orientation == Orientation.landscape;
      final currentOrientation = isLandscape
          ? DeviceOrientation.landscapeLeft
          : DeviceOrientation.portraitUp;

      if (!wasRecording) {
        final isNativeActive =
            NativeStreamBurnerBridge().isStreaming ||
            NativeStreamBurnerBridge().isRecording;
        if (!isNativeActive &&
            !camera.isCameraInitialized &&
            !camera.isSimulationMode) {
          setState(() {
            _showLocalCameraPreview = true;
          });
          await camera.initializeCamera();
        }
      }

      await camera.toggleMasterRecording(
        p2pProvider: p2p,
        deviceOrientation: currentOrientation,
        matchSession: match.session,
        recordingType: selectedType,
      );

      if (!context.mounted) return;

      if (wasRecording) {
        if (camera.recordingState == RecordingState.saved &&
            camera.lastRecordingResult != null) {
          _showRecordingSummaryDialog(context, camera.lastRecordingResult!);
        } else if (camera.recordingState == RecordingState.failed) {
          _showRecordingErrorNotice(
            context,
            camera.recordingErrorMessage ??
                'Nie udało się zapisać pliku wideo.',
          );
        }
      } else {
        if (camera.recordingState == RecordingState.failed) {
          _showRecordingErrorNotice(
            context,
            camera.recordingErrorMessage ??
                'Nie udało się rozpocząć nagrywania.',
          );
        }
      }
    } else {
      // W trybie Phone B (sędzia / komentator z tablicą wyników)
      final wasRecording = streamer.programRecState == RecordingState.recording;
      if (streamer.programRecState == RecordingState.stopping) return;

      final isConnected =
          p2p.connectionState == CameraConnectionState.connected;
      final hasFrames = p2p.hasFreshVideoFrame;

      // Blokuj start nagrywania jeśli brak obrazu z Phone A
      if (!wasRecording && (!isConnected || !hasFrames)) {
        _showRecordingErrorNotice(
          context,
          'Brak aktywnego połączenia z kamerą Phone A lub brak odebranego obrazu wideo. Połącz urządzenia przed rozpoczęciem nagrywania.',
        );
        return;
      }

      final isLandscape =
          MediaQuery.of(context).orientation == Orientation.landscape;
      final targetWidth = isLandscape
          ? camera.settings.resolution.width
          : camera.settings.resolution.height;
      final targetHeight = isLandscape
          ? camera.settings.resolution.height
          : camera.settings.resolution.width;

      Uint8List? initialProgramFrame;
      if (!wasRecording) {
        initialProgramFrame = await _ensureProgramCapture(
          framesPerSecond: camera.settings.fps.fps,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
      }
      await streamer.toggleProgramRecording(
        matchSession: match.session,
        frameStream: _programCapture.frameStream,
        initialFrame: initialProgramFrame,
        isConnected: isConnected,
        framesContainProgramComposition: true,
        encodingBitrateMbps: camera.settings.bitrateMbps,
        encodingFps: camera.settings.fps.fps,
        encodingWidth: targetWidth,
        encodingHeight: targetHeight,
      );
      if (wasRecording && streamer.streamingState != StreamingState.live) {
        _programCapture.stop();
      }
      if (!wasRecording &&
          streamer.programRecState == RecordingState.failed &&
          streamer.streamingState != StreamingState.live) {
        _programCapture.stop();
      }

      if (!context.mounted) return;

      if (wasRecording) {
        if (streamer.programRecState == RecordingState.saved &&
            streamer.lastProgramRecordingResult != null) {
          _showRecordingSummaryDialog(
            context,
            streamer.lastProgramRecordingResult!,
          );
        } else if (streamer.programRecState == RecordingState.failed) {
          _showRecordingErrorNotice(
            context,
            streamer.programRecordingErrorMessage ??
                'Nie udało się zapisać wideo z tablicą.',
          );
        }
      } else {
        if (streamer.programRecState == RecordingState.failed) {
          _showRecordingErrorNotice(
            context,
            streamer.programRecordingErrorMessage ??
                'Nie udało się rozpocząć nagrywania z tablicą.',
          );
        }
      }
    }
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
      final match = context.read<MatchProvider>();
      final streamer = context.read<StreamerProvider>();

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
      unawaited(streamer.ensurePreviewTextureId());

      if (p2p.currentRole == DeviceRole.singlePhoneAllInOne &&
          !camera.isCameraInitialized &&
          !camera.isSimulationMode) {
        camera.initializeCamera();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final streamer = context.read<StreamerProvider>();
    if (_streamerRef != streamer) {
      _streamerRef?.removeListener(_onStreamerStateChanged);
      _streamerRef = streamer;
      _previousStreamingState = streamer.streamingState;
      _streamerRef?.addListener(_onStreamerStateChanged);
    }
  }

  @override
  void dispose() {
    _streamerRef?.removeListener(_onStreamerStateChanged);
    _streamerRef = null;
    _streamTimeoutTimer?.cancel();
    _streamTimeoutTimer = null;
    WakelockService.disable();
    _unlockHoldController?.dispose();
    unawaited(_programCapture.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = context.watch<MatchProvider>();
    final streamer = context.watch<StreamerProvider>();
    final camera = context.watch<CameraProvider>();
    final p2p = context.watch<P2PConnectionProvider>();
    _evaluateStreamTimeout(p2p);
    final isOutdoor = match.isOutdoorModeEnabled;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    if (_lastOrientationIsPortrait != isPortrait) {
      _lastOrientationIsPortrait = isPortrait;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(streamer.updateStreamOrientation(isPortrait: isPortrait));
        }
      });
    }

    // Phone B: blokada wygaszania ekranu podczas trwania meczu i nagrywania/streamingu
    final isStreamingOrRecording =
        camera.isRecording ||
        streamer.programRecState == RecordingState.recording ||
        streamer.streamingState == StreamingState.live;
    final shouldKeepAwake =
        !match.session.isMatchOver || isStreamingOrRecording;
    if (_lastKeepAwakeState != shouldKeepAwake) {
      _lastKeepAwakeState = shouldKeepAwake;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          WakelockService.setEnabled(shouldKeepAwake);
        }
      });
    }

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
                    _buildTopBroadcastHUD(
                      context,
                      streamer,
                      match,
                      camera,
                      p2p,
                      true,
                    ),

                    // 2. AWARYJNY BANER PRZYWRACANIA POŁĄCZENIA I SZYBKIE PRZEŁĄCZENIE NA TRYB SOLO
                    if (p2p.currentRole != DeviceRole.singlePhoneAllInOne &&
                        p2p.connectionState != CameraConnectionState.connected) ...[
                      RecoveryBanner(
                        connectionState: p2p.connectionState,
                        onManualReconnect: () async {
                          await p2p.joinSession(
                            hostAddress: p2p.hostAddress.isNotEmpty
                                ? p2p.hostAddress
                                : '192.168.68.51',
                            pairingCode: 'VL-8492',
                            role: DeviceRole.scorerPhoneB,
                          );
                        },
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161F2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.amberAccent.withValues(alpha: 0.8), width: 1.2),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone_android, size: 16, color: AppTheme.amberAccent),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Brak sygnału z Phone A (rozładowany / rozłączony)?',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                _showEmergencySwitchToSoloDialog();
                              },
                              icon: const Icon(Icons.swap_horiz, size: 14),
                              label: const Text('PRZEŁĄCZ NA SOLO'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.cyanAccent,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

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
                            offset: _isControlsHidden
                                ? const Offset(0, 1.05)
                                : Offset.zero,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOutCubic,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildTactileScorePadWidget(
                                      context,
                                      match,
                                      isOutdoor,
                                    ),
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

                    // 5. STAŁY DOK DOLNY (ZAWSZE DOSTĘPNY W PORTRAIT, NIEZALEŻNIE OD SCROLLA)
                    _buildBottomModernNavBar(context, streamer, p2p),
                  ],
                )
              else
                // =============================================================
                // UKŁAD POZIOMY (LANDSCAPE)
                // =============================================================
                if (_isLandscapeFullScreenPreview)
                  Stack(
                    fit: StackFit.expand,
                    children: [
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
                      Positioned(
                        top: 12,
                        right: 12,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _isLandscapeFullScreenPreview = false;
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white30, width: 1),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fullscreen_exit, size: 16, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'ZAMKNIJ PEŁNY EKRAN',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  _buildLandscapeSplitView(
                    context,
                    match,
                    streamer,
                    camera,
                    p2p,
                    isOutdoor,
                  ),

              // =============================================================
              // EKRAN ZWYCIĘSTWA W MECZU
              // =============================================================
              if (match.session.isMatchOver) _buildVictoryOverlay(match),

              // =============================================================
              // OVERLAY BLOKADY DOTYKU SĘDZIEGO (GHOST TOUCH LOCK)
              // =============================================================
              if (match.isScreenLocked) _buildScreenLockOverlay(match),
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
    final isOutdoor = match.isOutdoorModeEnabled;
    final isSingleMode = p2p.currentRole == DeviceRole.singlePhoneAllInOne;

    final isRecActive = isSingleMode
        ? camera.isRecording
        : streamer.programRecState == RecordingState.recording;
    final isRecStopping = isSingleMode
        ? camera.recordingState == RecordingState.stopping
        : streamer.programRecState == RecordingState.stopping;
    final recDuration = isSingleMode
        ? camera.masterRecDuration
        : streamer.programRecDuration;

    String recLabel;
    if (isRecStopping) {
      recLabel = 'ZAPIS...';
    } else if (isRecActive) {
      recLabel = 'REC ${_formatDuration(recDuration)}';
    } else {
      recLabel = isSingleMode
          ? 'START REC (${camera.recordingType.shortLabel})'
          : 'START REC';
    }

    if (isPortrait) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isOutdoor ? Colors.black : const Color(0xF20A0E17),
          border: const Border(bottom: BorderSide(color: Colors.white12)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // RZĄD 1: MENU, TRYB STRUMIENIA / KOKPIT, SZYBKIE PRZEŁĄCZNIKI (ZABEZPIECZONE PRZED OVERFLOW)
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.arrow_back_ios_new,
                                    color: Colors.white,
                                    size: 11,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'MENU',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 6),

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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _isControlsHidden
                                    ? AppTheme.amberAccent
                                    : Colors.white12,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isControlsHidden
                                      ? AppTheme.amberAccent
                                      : Colors.white24,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isControlsHidden
                                        ? Icons.sports_volleyball
                                        : Icons.visibility_outlined,
                                    size: 13,
                                    color: _isControlsHidden
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _isControlsHidden ? 'KOKPIT' : 'PODGLĄD',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: _isControlsHidden
                                          ? Colors.black
                                          : Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(width: 8),

                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // PRZYCISK USTAWIENIA TRANSMISJI RTMP / YOUTUBE
                          IconButton(
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 28,
                            ),
                            icon: const Icon(
                              Icons.stream,
                              size: 16,
                              color: AppTheme.amberAccent,
                            ),
                            tooltip: 'Ustawienia Transmisji RTMP / YouTube Live',
                            onPressed: () => _openStreamSettings(context),
                          ),

                          // PRZYCISK PARAMETRY WIDEO
                          IconButton(
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 28,
                            ),
                            icon: const Icon(
                              Icons.tune,
                              size: 16,
                              color: AppTheme.cyanAccent,
                            ),
                            tooltip: 'Parametry Zapisu Wideo i Kodera',
                            onPressed: () => _openVideoSettings(context),
                          ),

                          // TOGGLE OUTDOOR HIGH CONTRAST
                          IconButton(
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 28,
                            ),
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
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 28,
                            ),
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
                          const Icon(
                            Icons.battery_5_bar,
                            size: 13,
                            color: AppTheme.greenLive,
                          ),
                          const SizedBox(width: 2),
                          const Text(
                            '88%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),

            // RZĄD 2: DUŻE PRZYCISKI START LIVE, START REC, TELEMETRIA PHONE A I REC W TLE (ZABEZPIECZONE PRZED OVERFLOW)
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // PRZYCISK START / STOP LIVE BROADCAST
                      InkWell(
                        onTap: () async {
                          HapticFeedback.heavyImpact();
                          await _onToggleLiveStream(
                            context,
                            streamer,
                            context.read<MatchProvider>(),
                          );
                        },
                        onLongPress: () {
                          HapticFeedback.mediumImpact();
                          _openStreamSettings(context);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isLive
                                ? AppTheme.redLive.withValues(alpha: 0.25)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isLive ? AppTheme.redLive : Colors.white24,
                              width: isLive ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: isLive
                                      ? AppTheme.redLive
                                      : const Color(0xFF757575),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    if (isLive)
                                      const BoxShadow(
                                        color: AppTheme.redLive,
                                        blurRadius: 6,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isLive ? 'LIVE' : 'START LIVE',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: isLive
                                      ? AppTheme.redLive
                                      : Colors.white,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // PRZYCISK START / STOP REC
                      InkWell(
                        onTap: isRecStopping
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                _handleToggleRecording(context);
                              },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isRecActive
                                ? AppTheme.redLive.withValues(alpha: 0.25)
                                : (isRecStopping
                                      ? Colors.amber.withValues(alpha: 0.2)
                                      : Colors.white10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isRecActive
                                  ? AppTheme.redLive
                                  : (isRecStopping
                                        ? AppTheme.amberAccent
                                        : Colors.white24),
                              width: isRecActive ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isRecActive
                                      ? AppTheme.redLive
                                      : (isRecStopping
                                            ? AppTheme.amberAccent
                                            : Colors.white38),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    if (isRecActive)
                                      const BoxShadow(
                                        color: AppTheme.redLive,
                                        blurRadius: 4,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                recLabel,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: isRecActive
                                      ? AppTheme.redLive
                                      : (isRecStopping
                                            ? AppTheme.amberAccent
                                            : Colors.white),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // =======================================================
                      // WSKAŹNIK TRYBU PRACY (SOLO / DUAL) ORAZ TELEMETRIA ŁĄCZA
                      // =======================================================
                      if (!isSingleMode) ...[
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _showModeDetailsModal(context, isSingleMode, p2p, streamer, camera);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: p2p.connectionState == CameraConnectionState.connected
                                  ? const Color(0xFF0A2219)
                                  : const Color(0xFF2B1316),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: p2p.connectionState == CameraConnectionState.connected
                                    ? AppTheme.greenLive.withValues(alpha: 0.7)
                                    : Colors.redAccent.withValues(alpha: 0.8),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PulseDot(
                                  color: p2p.connectionState == CameraConnectionState.connected
                                      ? AppTheme.greenLive
                                      : Colors.redAccent,
                                  size: 7,
                                ),
                                const SizedBox(width: 6),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'TRYB DUAL',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    Text(
                                      p2p.connectionState == CameraConnectionState.connected
                                          ? 'PHONE A (${p2p.healthMetrics.latencyMs}ms)'
                                          : 'ROZŁĄCZONO',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: p2p.connectionState == CameraConnectionState.connected
                                            ? AppTheme.greenLive
                                            : Colors.red.shade300,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (p2p.connectionState != CameraConnectionState.connected) ...[
                          const SizedBox(width: 5),
                          ElevatedButton(
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              _showEmergencySwitchToSoloDialog();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.amberAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: const Size(48, 38),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('SOLO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ] else
                        // W TRYBIE SINGLE PHONE: TRYB SOLO HUD PILL
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _showModeDetailsModal(context, isSingleMode, p2p, streamer, camera);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F2332),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.cyanAccent.withValues(alpha: 0.7),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const PulseDot(color: AppTheme.cyanAccent, size: 7),
                                const SizedBox(width: 6),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'TRYB SOLO',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.cyanAccent,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    Text(
                                      'KAMERA ${camera.settings.resolution.label}',
                                      style: const TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                      // WSKAŹNIK PRACY LOKALNEJ KAMERY W TLE (JEŚLI NAGRYWA NA PHONE B)
                      if (camera.isRecording && !isSingleMode) ...[
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
                                const Icon(
                                  Icons.fiber_manual_record,
                                  color: AppTheme.redLive,
                                  size: 10,
                                ),
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
                ),
              ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_back_ios_new,
                              color: Colors.white,
                              size: 11,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'MENU',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // WSKAŹNIK PRACY LOKALNEJ KAMERY W TLE
                    if (camera.isRecording) ...[
                      InkWell(
                        onTap: isSingleMode
                            ? () => setState(() => _isControlsHidden = !_isControlsHidden)
                            : () => context.push(AppRouter.cameraRoute),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.redLive.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.redLive),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.fiber_manual_record,
                                color: AppTheme.redLive,
                                size: 9,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'REC W TLE: ${_formatDuration(camera.masterRecDuration)}',
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
                      const SizedBox(width: 8),
                    ],

                    // PRZYCISK START / STOP LIVE BROADCAST
                    InkWell(
                      onTap: () async {
                        HapticFeedback.heavyImpact();
                        await _onToggleLiveStream(
                          context,
                          streamer,
                          context.read<MatchProvider>(),
                        );
                      },
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        _openStreamSettings(context);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isLive
                              ? AppTheme.redLive.withValues(alpha: 0.2)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isLive ? AppTheme.redLive : Colors.white24,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isLive
                                    ? AppTheme.redLive
                                    : const Color(0xFF616161),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  if (isLive)
                                    const BoxShadow(
                                      color: AppTheme.redLive,
                                      blurRadius: 6,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isLive ? 'LIVE' : 'START LIVE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: isLive
                                    ? AppTheme.redLive
                                    : Colors.white70,
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
                      onTap: isRecStopping
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              _handleToggleRecording(context);
                            },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isRecActive
                              ? AppTheme.redLive.withValues(alpha: 0.25)
                              : (isRecStopping
                                    ? Colors.amber.withValues(alpha: 0.2)
                                    : Colors.white10),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isRecActive
                                ? AppTheme.redLive
                                : (isRecStopping
                                      ? AppTheme.amberAccent
                                      : Colors.white24),
                            width: isRecActive ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: isRecActive
                                    ? AppTheme.redLive
                                    : (isRecStopping
                                          ? AppTheme.amberAccent
                                          : Colors.white38),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  if (isRecActive)
                                    const BoxShadow(
                                      color: AppTheme.redLive,
                                      blurRadius: 4,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              recLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: isRecActive
                                    ? AppTheme.redLive
                                    : (isRecStopping
                                          ? AppTheme.amberAccent
                                          : Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),
                    const Text(
                      '|',
                      style: TextStyle(color: Colors.white24, fontSize: 12),
                    ),
                    const SizedBox(width: 8),

                    // =======================================================
                    // WSKAŹNIK TRYBU PRACY (SOLO / DUAL) W POZIOMIE
                    // =======================================================
                    if (p2p.currentRole != DeviceRole.singlePhoneAllInOne) ...[
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _showModeDetailsModal(context, false, p2p, streamer, camera);
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: p2p.connectionState == CameraConnectionState.connected
                                ? AppTheme.greenLive.withValues(alpha: 0.15)
                                : Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: p2p.connectionState == CameraConnectionState.connected
                                  ? AppTheme.greenLive
                                  : Colors.redAccent,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PulseDot(
                                color: p2p.connectionState == CameraConnectionState.connected
                                    ? AppTheme.greenLive
                                    : Colors.redAccent,
                                size: 6,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                p2p.connectionState == CameraConnectionState.connected
                                    ? 'TRYB DUAL • PHONE A (${p2p.healthMetrics.latencyMs}ms)'
                                    : 'TRYB DUAL • ROZŁĄCZONO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: p2p.connectionState == CameraConnectionState.connected
                                      ? AppTheme.greenLive
                                      : Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (p2p.connectionState != CameraConnectionState.connected) ...[
                        const SizedBox(width: 6),
                        ElevatedButton(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _showEmergencySwitchToSoloDialog();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.amberAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            minimumSize: const Size(48, 26),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Text('SOLO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ] else
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _showModeDetailsModal(context, true, p2p, streamer, camera);
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.cyanAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.6), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const PulseDot(color: AppTheme.cyanAccent, size: 6),
                              const SizedBox(width: 5),
                              Text(
                                'TRYB SOLO • LOKALNA (${camera.settings.resolution.label})',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.cyanAccent,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _isControlsHidden
                              ? AppTheme.amberAccent
                              : Colors.white12,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _isControlsHidden
                                ? AppTheme.amberAccent
                                : Colors.white24,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isControlsHidden
                                  ? Icons.sports_volleyball
                                  : Icons.visibility_outlined,
                              size: 13,
                              color: _isControlsHidden
                                  ? Colors.black
                                  : Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isControlsHidden ? 'KOKPIT' : 'WIDOK STRUMIENIA',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: _isControlsHidden
                                    ? Colors.black
                                    : Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // PRZYCISK USTAWIENIA TRANSMISJI RTMP / YOUTUBE
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: const Icon(
                        Icons.stream,
                        size: 16,
                        color: AppTheme.amberAccent,
                      ),
                      tooltip: 'Ustawienia Transmisji RTMP / YouTube Live',
                      onPressed: () => _openStreamSettings(context),
                    ),

                    // PRZYCISK PARAMETRY WIDEO
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: const Icon(
                        Icons.tune,
                        size: 16,
                        color: AppTheme.cyanAccent,
                      ),
                      tooltip: 'Parametry Zapisu Wideo i Kodera',
                      onPressed: () => _openVideoSettings(context),
                    ),

                    // TOGGLE OUTDOOR HIGH CONTRAST
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: Icon(
                        isOutdoor ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                        size: 16,
                        color: isOutdoor
                            ? AppTheme.amberAccent
                            : Colors.white54,
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
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
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
                    const Icon(
                      Icons.battery_5_bar,
                      size: 14,
                      color: AppTheme.greenLive,
                    ),
                    const SizedBox(width: 2),
                    const Text(
                      '88%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
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
  // WIDOK STRUMIENIA WIDEO (16:9 / 9:16) Z TABLICĄ WYNIKÓW OVERLAY I TELEMETRIĄ
  // ===========================================================================
  double _resolveActiveStreamAspectRatio(
    CameraProvider camera,
    P2PConnectionProvider p2p,
    bool isPortrait,
  ) {
    if (_showLocalCameraPreview &&
        camera.isCameraInitialized &&
        camera.cameraController != null &&
        camera.cameraController!.value.isInitialized) {
      final previewSize = camera.cameraController!.value.previewSize;
      final double pWidth = previewSize?.width ?? 1920.0;
      final double pHeight = previewSize?.height ?? 1080.0;
      final double sensorLong = pWidth > pHeight ? pWidth : pHeight;
      final double sensorShort = pWidth > pHeight ? pHeight : pWidth;
      return sensorLong / sensorShort;
    }
    return 16.0 / 9.0;
  }

  Widget _buildBroadcastStreamView({
    required BuildContext context,
    required MatchProvider match,
    required CameraProvider camera,
    required StreamerProvider streamer,
    required P2PConnectionProvider p2p,
    required bool isOutdoor,
    required bool isPortrait,
  }) {
    final activeStreamAspectRatio = _resolveActiveStreamAspectRatio(
      camera,
      p2p,
      isPortrait,
    );
    final isStreamingLive =
        streamer.streamingState == StreamingState.live ||
        streamer.streamingState == StreamingState.connecting ||
        streamer.streamingState == StreamingState.reconnecting;
    final hasActiveSinglePhoneCameraOrStream =
        p2p.currentRole == DeviceRole.singlePhoneAllInOne &&
        (camera.isCameraInitialized || isStreamingLive);

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
        key: _broadcastStreamSurfaceKey,
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Only this isolated program layer is captured; referee controls,
              // LIVE/REC buttons, status HUD and dialogs remain outside it.
              RepaintBoundary(
                key: _programCapture.boundaryKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildStreamMediaLayer(
                      match,
                      camera,
                      streamer,
                      p2p,
                      isOutdoor,
                      isPortrait,
                    ),
                    // Gdy natywny RootEncoder strumieniuje z własną teksturą OpenGL,
                    // tablica wyników jest już wpalona sprzętowo w teksturę podglądu,
                    // więc unikamy podwójnego nakładania w tym samym kadrze.
                    Positioned.fill(
                      child: Visibility(
                        visible: !(isStreamingLive &&
                            p2p.isSinglePhoneMode &&
                            streamer.previewTextureId != null &&
                            _showLocalCameraPreview),
                        maintainState: true,
                        maintainAnimation: true,
                        maintainSize: false,
                        child: ScoreboardOverlay(
                          session: match.session,
                          style: streamer.scoreboardStyle,
                          anchorPosition: streamer.scoreboardAnchorPosition,
                          targetAspectRatio: activeStreamAspectRatio,
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
                  ],
                ),
              ),

              // Telemetry is intentionally outside the encoded program frame.
              if (isPortrait || _isControlsHidden)
                Positioned(
                  bottom: 6,
                  left: isPortrait ? 10 : 16,
                  right: isPortrait ? 10 : null,
                  child: _buildStreamStatusAndControlsRow(
                    context,
                    camera,
                    streamer,
                    p2p,
                    isPortrait: isPortrait,
                  ),
                ),

              // Pływający pasek sterowania kamerą w trybie Single Mode (Obiektyw, Latarka, Tryb REC)
              if (hasActiveSinglePhoneCameraOrStream)
                Positioned(
                  top: isPortrait ? 8 : 12,
                  right: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Przełącznik kamery Tył / Przód (obsługuje zarówno lokalny CameraX, jak i natywny RootEncoder)
                      if (camera.availableCamerasList.length > 1 || isStreamingLive)
                        InkWell(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            if (isStreamingLive) {
                              await NativeStreamBurnerBridge().switchCamera();
                            } else {
                              await camera.switchCamera();
                            }
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(
                              Icons.flip_camera_android,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                      const SizedBox(width: 5),

                      // Włącznik latarki / doświetlenia
                      if (camera.isCameraInitialized) ...[
                        InkWell(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await camera.toggleTorch();
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: camera.isTorchOn
                                  ? AppTheme.amberAccent
                                  : Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: camera.isTorchOn
                                    ? AppTheme.amberAccent
                                    : Colors.white24,
                              ),
                            ),
                            child: Icon(
                              camera.isTorchOn ? Icons.flash_on : Icons.flash_off,
                              color: camera.isTorchOn
                                  ? Colors.black
                                  : Colors.white70,
                              size: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],

                      // Szybki wybór trybu nagrywania (RAW / PROG / DUAL)
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          final current = camera.recordingType;
                          final next =
                              current == RecordingType.programWithScoreboard
                              ? RecordingType.rawCamera
                              : (current == RecordingType.rawCamera
                                    ? RecordingType.dual
                                    : RecordingType.programWithScoreboard);
                          camera.setRecordingType(next);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.amberAccent,
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            camera.recordingType.shortLabel,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.amberAccent,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Paski szybkiego zoomu w trybie Single Mode
              if (p2p.currentRole == DeviceRole.singlePhoneAllInOne &&
                  camera.isCameraInitialized)
                Positioned(
                  top: isPortrait ? 40 : 48,
                  right: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (camera.settings.minZoomLevel < 1.0)
                        _buildQuickZoomPill(camera, 0.6, '0.6x'),
                      _buildQuickZoomPill(camera, 1.0, '1x'),
                      if (camera.settings.maxZoomLevel >= 2.0)
                        _buildQuickZoomPill(camera, 2.0, '2x'),
                    ],
                  ),
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
    StreamerProvider streamer,
    P2PConnectionProvider p2p,
    bool isOutdoor,
    bool isPortrait,
  ) {
    final bool isStreamingLive =
        streamer.streamingState == StreamingState.live ||
        streamer.streamingState == StreamingState.connecting ||
        streamer.streamingState == StreamingState.reconnecting;
    final isNativeActive =
        isStreamingLive || NativeStreamBurnerBridge().isRecording;
    final int? nativePreviewTexId = streamer.previewTextureId;
    final bool hasLocalCamera =
        camera.isCameraInitialized &&
        camera.cameraController != null &&
        camera.cameraController!.value.isInitialized;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 0. TŁO MAKIETY BOISKA (ZAWSZE ZAMONTOWANE POD SPODEM)
        _buildCourtFallbackStack(match, p2p, isOutdoor),

        // 1. WSPÓŁDZIELONA TEKSTURA OPENGL PODCZAS NADAWANIA RTMP LUB NAGRYWANIA MP4 W TRYBIE SOLO (ZACHOWUJE PODGLĄD LIVE)
        Visibility(
          key: const ValueKey('solo_hardware_stream_preview_visibility'),
          visible: _showLocalCameraPreview &&
              p2p.isSinglePhoneMode &&
              isNativeActive &&
              nativePreviewTexId != null,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: false,
          child: nativePreviewTexId != null
              ? Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: isPortrait ? 1080.0 : 1920.0,
                      height: isPortrait ? 1920.0 : 1080.0,
                      child: Texture(
                        key: ValueKey('solo_native_tex_$nativePreviewTexId'),
                        textureId: nativePreviewTexId,
                      ),
                    ),
                  ),
                )
              : const SizedBox.expand(),
        ),

        // 2. LOKALNA KAMERA W TRYBIE POJEDYNCZEGO TELEFONU PRZED STARTEM RTMP / REC (ZACHOWUJE STAN PRZEZ VISIBILITY)
        Visibility(
          key: const ValueKey('solo_local_camera_preview_visibility'),
          visible: _showLocalCameraPreview && hasLocalCamera && !isNativeActive,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: false,
          child: hasLocalCamera
              ? Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: SizedBox.expand(
                    child: AdaptiveCameraPreview(
                      controller: camera.cameraController!,
                      isPortrait: isPortrait,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              : const SizedBox.expand(),
        ),

        // 3. BEZPRZEWODOWY OBRAZ Z KAMERY PHONE A (TRYB DUAL P2P)
        if (!p2p.isSinglePhoneMode)
          ValueListenableBuilder<Uint8List?>(
            key: const ValueKey('dual_p2p_stream_media_layer'),
            valueListenable: p2p.videoFrameNotifier,
            builder: (context, frame, _) {
              if (frame != null) {
                return Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: AspectRatio(
                    aspectRatio: isPortrait ? (9.0 / 16.0) : (16.0 / 9.0),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: Image.memory(frame, gaplessPlayback: true),
                    ),
                  ),
                );
              }
              if (camera.programPreviewFrame != null && !camera.isCameraInitialized) {
                return FittedBox(
                  fit: BoxFit.cover,
                  child: Image.memory(
                    camera.programPreviewFrame!,
                    gaplessPlayback: true,
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

        // 4. AWARYJNY OBRAZ PROGRAM PREVIEW (GDY KAMERA JEST W TRAKCIE PRZEŁĄCZANIA)
        if (p2p.isSinglePhoneMode &&
            _showLocalCameraPreview &&
            !hasLocalCamera &&
            !(isNativeActive && nativePreviewTexId != null) &&
            camera.programPreviewFrame != null)
          FittedBox(
            fit: BoxFit.contain,
            child: Image.memory(
              camera.programPreviewFrame!,
              gaplessPlayback: true,
            ),
          ),
      ],
    );
  }

  Widget _buildCourtFallbackStack(
    MatchProvider match,
    P2PConnectionProvider p2p,
    bool isOutdoor,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: SportCourtPainter(
            sport: match.session.sport,
            isHighContrast: isOutdoor,
          ),
        ),
        if (p2p.hasStreamTimeout)
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xF0141A26),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.amberAccent,
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black87,
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppTheme.amberAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'TIMEOUT STRUMIENIA (${p2p.remoteDeviceName.toUpperCase()})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.amberAccent,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kamera ${p2p.remoteDeviceName} jest połączona, lecz nie przesyła obrazu (>12s).\n'
                    'Sprawdź, czy na telefonie kamery jest włączony podgląd meczu.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _streamTimeoutTimer?.cancel();
                          _streamTimeoutTimer = null;
                          p2p.clearStreamTimeout();
                          p2p.sendSyncState();
                        },
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('PONÓW'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.amberAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _openCameraConnectionModal(context),
                        icon: const Icon(
                          Icons.settings_remote,
                          size: 14,
                          color: AppTheme.cyanAccent,
                        ),
                        label: const Text(
                          'PAROWANIE',
                          style: TextStyle(
                            color: AppTheme.cyanAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.cyanAccent),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ))
        else
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
                          bottom: BorderSide(
                            color: AppTheme.cyanAccent,
                            width: 2,
                          ),
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
                          bottom: BorderSide(
                            color: AppTheme.cyanAccent,
                            width: 2,
                          ),
                          right: BorderSide(color: AppTheme.cyanAccent, width: 2),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          match.session.sport.icon,
                          size: 24,
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        if (p2p.connectionState ==
                                CameraConnectionState.connected &&
                            !p2p.isSinglePhoneMode) ...[
                          const SizedBox(height: 4),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppTheme.cyanAccent,
                            ),
                          ),
                        ],
                      ],
                    ),
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
    StreamerProvider streamer,
    P2PConnectionProvider p2p, {
    bool isPortrait = true,
  }) {
    final bool isStreamingLive =
        streamer.streamingState == StreamingState.live ||
        streamer.streamingState == StreamingState.connecting ||
        streamer.streamingState == StreamingState.reconnecting;
    final String formatBadge = isPortrait ? '9:16 (1080×1920)' : '16:9 (1920×1080)';

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
                onTap: () {
                  if (p2p.hasStreamTimeout) {
                    _openCameraConnectionModal(context);
                  } else {
                    _openVideoSettings(context);
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: (camera.isRecording || isStreamingLive)
                              ? AppTheme.redLive
                              : (p2p.hasStreamTimeout
                                    ? AppTheme.amberAccent
                                    : (p2p.currentVideoFrame != null
                                          ? AppTheme.greenLive
                                          : (p2p.connectionState ==
                                                    CameraConnectionState
                                                        .connected
                                                ? AppTheme.cyanAccent
                                                : Colors.white30))),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isStreamingLive
                            ? 'LIVE RTMP • $formatBadge • ${streamer.config.fps} FPS'
                            : (isPortrait
                                  ? (p2p.currentVideoFrame != null
                                        ? 'LIVE FEED • ${p2p.remoteDeviceName.toUpperCase()} (${p2p.healthMetrics.latencyMs}ms • P2P)'
                                        : (p2p.hasStreamTimeout
                                              ? 'TIMEOUT STRUMIENIA (${p2p.remoteDeviceName.toUpperCase()})'
                                              : (camera.isCameraInitialized
                                                    ? 'LOKALNA KAMERA ($formatBadge • ${camera.settings.fps.label})'
                                                    : (p2p.connectionState ==
                                                              CameraConnectionState
                                                                  .connected
                                                          ? 'OCZEKIWANIE NA STRUMIEŃ ${p2p.remoteDeviceName.toUpperCase()}...'
                                                          : 'OCZEKIWANIE NA KAMERĘ ${p2p.remoteDeviceName.toUpperCase()}...'))))
                                  : (p2p.currentVideoFrame != null
                                        ? 'P2P ${p2p.healthMetrics.latencyMs}ms'
                                        : (p2p.hasStreamTimeout
                                              ? 'TIMEOUT'
                                              : (camera.isCameraInitialized
                                                    ? 'KAMERA $formatBadge'
                                                    : 'BRAK ŹRÓDŁA')))),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: p2p.hasStreamTimeout
                              ? AppTheme.amberAccent
                              : Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        p2p.hasStreamTimeout
                            ? Icons.warning_amber_rounded
                            : Icons.settings,
                        size: 10,
                        color: p2p.hasStreamTimeout
                            ? AppTheme.amberAccent
                            : AppTheme.cyanAccent,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // PRZEŁĄCZNIK WIDOKU KAMERA LIVE / MAKIETA (DEBOUNCED & SAFE INIT)
              InkWell(
                onTap: () async {
                  if (_isCameraToggling) return;
                  _isCameraToggling = true;
                  try {
                    final nextPreview = !_showLocalCameraPreview;
                    setState(() {
                      _showLocalCameraPreview = nextPreview;
                    });
                    final isNativeActive =
                        NativeStreamBurnerBridge().isStreaming ||
                        NativeStreamBurnerBridge().isRecording ||
                        isStreamingLive;
                    if (nextPreview &&
                        !camera.isCameraInitialized &&
                        !isNativeActive &&
                        !camera.isSimulationMode) {
                      await camera.initializeCamera();
                    }
                  } finally {
                    _isCameraToggling = false;
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppTheme.cyanAccent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showLocalCameraPreview
                            ? Icons.sports_volleyball
                            : Icons.videocam,
                        size: 11,
                        color: AppTheme.cyanAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showLocalCameraPreview ? 'MAKIETA' : 'KAMERA LIVE',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
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
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
      },
      onAddPointB: (pts) {
        match.addPointB(points: pts);
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
      },
      onSubtractPointA: () {
        match.subtractPointA();
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
      },
      onSubtractPointB: () {
        match.subtractPointB();
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
      },
      onAddFoulA: () {
        match.addFoulA();
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
      },
      onAddFoulB: () {
        match.addFoulB();
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
      },
      onNextPeriod: () {
        match.nextPeriod();
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
      },
      onUndo: () {
        match.undo();
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
      },
      onToggleRotation: () {
        match.toggleRotation();
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
      },
      onRequestTimeoutA: () {
        match.startTimeout(ServingTeam.teamA);
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
      },
      onRequestTimeoutB: () {
        match.startTimeout(ServingTeam.teamB);
        context.read<P2PConnectionProvider>().broadcastScore(
          match.toScorePayload,
        );
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
              Icon(
                Icons.sports_volleyball,
                size: 16,
                color: AppTheme.amberAccent,
              ),
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
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: AppTheme.amberAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickZoomPill(
    CameraProvider camera,
    double targetZoom,
    String label,
  ) {
    final isSelected = (camera.settings.zoom - targetZoom).abs() < 0.2;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          camera.setZoom(targetZoom);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.amberAccent
                : Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.amberAccent : Colors.white24,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: isSelected ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ERGONOMICZNY SPLIT-VIEW SĘDZIEGO W POZIOMIE (LANDSCAPE SPLIT-VIEW)
  // Wzór komercyjnych systemów (SportCam): PiP 16:9, stoper, karty dotykowe, pasek transportowy
  // ===========================================================================
  Widget _buildLandscapeSplitView(
    BuildContext context,
    MatchProvider match,
    StreamerProvider streamer,
    CameraProvider camera,
    P2PConnectionProvider p2p,
    bool isOutdoor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        children: [
          // 1. GÓRNA SEKCJA: PiP 16:9 + < WRÓĆ, Status i Stoper (00:00)
          _buildLandscapeTopSplitSection(context, match, streamer, camera, p2p, isOutdoor),

          const SizedBox(height: 6),

          // 2. ŚRODKOWA SEKCJA: DUŻE KARTY PUNKTOWE (TACTILE SCORE CARDS)
          Expanded(
            child: _buildLandscapeTactileScoreCards(context, match, isOutdoor),
          ),

          const SizedBox(height: 6),

          // 3. DOLNY PASEK TRANSPORTOWY: START/STOP, HIGHLIGHT, SET, BATERIA
          _buildLandscapeBottomTransportBar(context, match, streamer, camera, p2p, isOutdoor),
        ],
      ),
    );
  }

  Widget _buildLandscapeTopSplitSection(
    BuildContext context,
    MatchProvider match,
    StreamerProvider streamer,
    CameraProvider camera,
    P2PConnectionProvider p2p,
    bool isOutdoor,
  ) {
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Górna lewa sekcja: PiP Live Preview 16:9 z nałożoną tablicą i przyciskiem powiększenia
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24, width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildBroadcastStreamView(
                    context: context,
                    match: match,
                    camera: camera,
                    streamer: streamer,
                    p2p: p2p,
                    isOutdoor: isOutdoor,
                    isPortrait: false,
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _isLandscapeFullScreenPreview = true;
                        });
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white30, width: 1),
                        ),
                        child: const Icon(
                          Icons.fullscreen,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Górna prawa sekcja: < WRÓĆ, przełącznik statusu połączenia oraz duży stoper
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isOutdoor ? Colors.black : const Color(0xFF0F1420),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Lewa część prawej sekcji: przycisk powrotu i status połączenia
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(AppRouter.initialRoute);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E2638),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back_ios_new, size: 12, color: Colors.white),
                              SizedBox(width: 5),
                              Text(
                                'WRÓĆ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _showModeDetailsModal(
                            context,
                            p2p.currentRole == DeviceRole.singlePhoneAllInOne,
                            p2p,
                            streamer,
                            camera,
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: p2p.connectionState == CameraConnectionState.connected
                                ? (p2p.currentRole == DeviceRole.singlePhoneAllInOne
                                    ? AppTheme.cyanAccent.withValues(alpha: 0.15)
                                    : AppTheme.greenLive.withValues(alpha: 0.15))
                                : Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: p2p.connectionState == CameraConnectionState.connected
                                  ? (p2p.currentRole == DeviceRole.singlePhoneAllInOne
                                      ? AppTheme.cyanAccent
                                      : AppTheme.greenLive)
                                  : Colors.redAccent,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: p2p.connectionState == CameraConnectionState.connected
                                      ? (p2p.currentRole == DeviceRole.singlePhoneAllInOne
                                          ? AppTheme.cyanAccent
                                          : AppTheme.greenLive)
                                      : Colors.redAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                p2p.connectionState == CameraConnectionState.connected
                                    ? (p2p.currentRole == DeviceRole.singlePhoneAllInOne
                                        ? 'TRYB SOLO (KAMERA)'
                                        : 'TRYB DUAL (PHONE A • ${p2p.healthMetrics.latencyMs}ms)')
                                    : 'TRYB DUAL (ROZŁĄCZONO)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: p2p.connectionState == CameraConnectionState.connected
                                      ? (p2p.currentRole == DeviceRole.singlePhoneAllInOne
                                          ? AppTheme.cyanAccent
                                          : AppTheme.greenLive)
                                      : Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (p2p.connectionState != CameraConnectionState.connected &&
                          p2p.currentRole != DeviceRole.singlePhoneAllInOne) ...[
                        const SizedBox(width: 6),
                        ElevatedButton(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _showEmergencySwitchToSoloDialog();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.amberAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            minimumSize: const Size(44, 24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Text('SOLO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ],
                  ),

                  // Prawa część: Stoper meczowy (00:00) z okrągłym przyciskiem Play/Pause
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090D14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CZAS MECZU',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            Text(
                              match.formattedMatchDuration,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            match.toggleMatchTimer();
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: match.isMatchTimerRunning
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (match.isMatchTimerRunning ? Colors.red : Colors.green)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(
                              match.isMatchTimerRunning ? Icons.pause : Icons.play_arrow,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildLandscapeTactileScoreCards(
    BuildContext context,
    MatchProvider match,
    bool isOutdoor,
  ) {
    final session = match.session;
    final isServingA = session.currentServer == ServingTeam.teamA;
    final isServingB = session.currentServer == ServingTeam.teamB;
    final p2p = context.read<P2PConnectionProvider>();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Karta Drużyny A (Gospodarze)
        Expanded(
          child: _buildTactileScoreCard(
            teamName: session.teamA,
            teamColor: session.teamAColor,
            points: session.currentSetPointsA,
            setsWon: session.setsA,
            isServing: isServingA,
            onSubtractPoint: () {
              match.subtractPointA();
              p2p.broadcastScore(match.toScorePayload);
            },
            onAddPoint: () {
              match.addPointA(points: 1);
              p2p.broadcastScore(match.toScorePayload);
            },
            tag1Label: 'AS!',
            onTag1: () => match.triggerSpecialEvent('AS!'),
            tag2Label: 'BLOK',
            onTag2: () => match.triggerSpecialEvent('BLOK'),
            isOutdoor: isOutdoor,
          ),
        ),

        const SizedBox(width: 10),

        // Karta Drużyny B (Goście)
        Expanded(
          child: _buildTactileScoreCard(
            teamName: session.teamB,
            teamColor: session.teamBColor,
            points: session.currentSetPointsB,
            setsWon: session.setsB,
            isServing: isServingB,
            onSubtractPoint: () {
              match.subtractPointB();
              p2p.broadcastScore(match.toScorePayload);
            },
            onAddPoint: () {
              match.addPointB(points: 1);
              p2p.broadcastScore(match.toScorePayload);
            },
            tag1Label: 'ATAK',
            onTag1: () => match.triggerSpecialEvent('ATAK'),
            tag2Label: 'CHALLENGE',
            onTag2: () => match.triggerSpecialEvent('CHALLENGE'),
            isOutdoor: isOutdoor,
          ),
        ),
      ],
    );
  }

  Widget _buildTactileScoreCard({
    required String teamName,
    required Color teamColor,
    required int points,
    required int setsWon,
    required bool isServing,
    required VoidCallback onAddPoint,
    required VoidCallback onSubtractPoint,
    required String tag1Label,
    required VoidCallback onTag1,
    required String tag2Label,
    required VoidCallback onTag2,
    required bool isOutdoor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isOutdoor ? Colors.black : const Color(0xFF101522),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isServing ? teamColor : teamColor.withValues(alpha: 0.35),
          width: isServing ? 2.0 : 1.2,
        ),
        boxShadow: [
          if (isServing)
            BoxShadow(
              color: teamColor.withValues(alpha: 0.2),
              blurRadius: 10,
            ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Góra karty: nazwa drużyny, serwis i wynik setów
          Row(
            children: [
              Container(
                width: 5,
                height: 14,
                decoration: BoxDecoration(
                  color: teamColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  teamName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (isServing) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: teamColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: teamColor, width: 1),
                  ),
                  child: const Text(
                    'SERWIS',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                'SETY: $setsWon',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.amberAccent,
                ),
              ),
            ],
          ),

          // Środek: Okrągły czarny przycisk (-) po lewej, wielka cyfra pośrodku, duży żółty przycisk (+) po prawej
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Okrągły czarny przycisk (-)
                InkWell(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onSubtractPoint();
                  },
                  borderRadius: BorderRadius.circular(26),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B202E),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.remove,
                      size: 26,
                      color: Colors.white,
                    ),
                  ),
                ),

                // Wielka cyfra wyniku w centrum
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$points',
                        style: TextStyle(
                          fontSize: 54,
                          fontWeight: FontWeight.w900,
                          color: teamColor,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),

                // Duży żółty przycisk (+) (#FACC15)
                InkWell(
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    onAddPoint();
                  },
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFACC15),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFACC15).withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add,
                      size: 30,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Dół karty: Szybkie tagi zdarzeń
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTag1();
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tag1Label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.amberAccent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTag2();
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tag2Label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.cyanAccent,
                      ),
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

  Widget _buildLandscapeBottomTransportBar(
    BuildContext context,
    MatchProvider match,
    StreamerProvider streamer,
    CameraProvider camera,
    P2PConnectionProvider p2p,
    bool isOutdoor,
  ) {
    final isSingleMode = p2p.currentRole == DeviceRole.singlePhoneAllInOne;
    final isRecActive = isSingleMode
        ? camera.isRecording
        : streamer.programRecState == RecordingState.recording;
    final recDuration = isSingleMode
        ? camera.masterRecDuration
        : streamer.programRecDuration;
    final isLive = streamer.streamingState == StreamingState.live;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isOutdoor ? Colors.black : const Color(0xFF0C101A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Przycisk Start/Stop strumienia/nagrywania z licznikiem czasu
          InkWell(
            onTap: () async {
              HapticFeedback.heavyImpact();
              await _handleToggleRecording(context);
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isRecActive ? const Color(0xFFDC2626) : const Color(0xFF1E2638),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isRecActive ? Colors.redAccent : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isRecActive ? Colors.white : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isRecActive
                        ? 'REC ${_formatDuration(recDuration)}'
                        : (isLive ? 'LIVE' : 'START REC'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Przycisk Zapisz Highlight
          InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              match.triggerSpecialEvent('HIGHLIGHT');
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF282012),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.amberAccent, width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 14, color: AppTheme.amberAccent),
                  SizedBox(width: 5),
                  Text(
                    'HIGHLIGHT',
                    style: TextStyle(
                      color: AppTheme.amberAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Selektor seta (- 1 + SET)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1A202E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    match.decrementSetNumber();
                    p2p.broadcastScore(match.toScorePayload);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Icon(Icons.remove, size: 13, color: Colors.white),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'SET ${match.session.currentSetNumber}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    match.incrementSetNumber();
                    p2p.broadcastScore(match.toScorePayload);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Icon(Icons.add, size: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),

          // 4. Przycisk TABLICA STUDIO (w układzie poziomym)
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              _openScoreboardStudio(context);
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.cyanAccent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.cyanAccent.withValues(alpha: 0.6)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.palette_outlined, size: 14, color: AppTheme.cyanAccent),
                  SizedBox(width: 5),
                  Text(
                    'TABLICA',
                    style: TextStyle(
                      color: AppTheme.cyanAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 5. Wskaźnik baterii i P2P Sync
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                p2p.connectionState == CameraConnectionState.connected
                    ? Icons.sync_rounded
                    : Icons.sync_disabled_rounded,
                size: 13,
                color: p2p.connectionState == CameraConnectionState.connected
                    ? AppTheme.cyanAccent
                    : Colors.white38,
              ),
              const SizedBox(width: 6),
              const Icon(Icons.battery_5_bar, size: 14, color: AppTheme.greenLive),
              const SizedBox(width: 3),
              const Text(
                '85%',
                style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
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
              const Icon(
                Icons.emoji_events,
                color: AppTheme.amberAccent,
                size: 64,
              ),
              const SizedBox(height: 12),
              const Text(
                'KONIEC MECZU!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Zwycięzca: ${match.session.matchWinner}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.cyanAccent,
                ),
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
              const Icon(
                Icons.lock_rounded,
                color: AppTheme.amberAccent,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'TRYB SĘDZIEGO ZABLOKOWANY',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
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
                        border: Border.all(
                          color: AppTheme.amberAccent,
                          width: 1.5,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            width: 220 * progress,
                            decoration: BoxDecoration(
                              color: AppTheme.amberAccent.withValues(
                                alpha: 0.4,
                              ),
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
      useRootNavigator: true,
      builder: (_) => const CameraConnectionModal(),
    );
  }

  void _openStreamSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => const StreamSettingsModal(),
    );
  }

  void _openVideoSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => const VideoSettingsModal(),
    );
  }

  void _openScoreboardStudio(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => const ScoreboardCustomizerModal(),
    );
  }

  Widget _buildBottomModernNavBar(
    BuildContext context,
    StreamerProvider streamer,
    P2PConnectionProvider p2p,
  ) {
    final items = [
      {'label': 'SCORER', 'icon': Icons.sports_score},
      {
        'label': p2p.isSinglePhoneMode ? 'KADR / PEŁNY' : 'KAMERA',
        'icon': Icons.camera_alt_outlined,
      },
      {'label': 'STATS', 'icon': Icons.analytics_outlined},
      {'label': 'WIDEO REC', 'icon': Icons.video_settings},
      {'label': 'STREAM', 'icon': Icons.stream},
      {'label': 'TABLICA', 'icon': Icons.palette_outlined},
    ];

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF090D15),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = _selectedNavIndex == index;

          return Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedNavIndex = index;
                });

                if (index == 1) {
                  // W TRYBIE SOLO: PRZEŁĄCZ PEŁNY KADR / UKRYJ KOKPIT ZAMIAST NIEBEZPIECZNEGO ROUTINGU
                  if (p2p.isSinglePhoneMode) {
                    setState(() {
                      _isControlsHidden = !_isControlsHidden;
                    });
                  } else {
                    // W TRYBIE DUAL: PRZEJDŹ DO EKRANU KAMERY PHONE A CZYSTYM GO
                    context.go(AppRouter.cameraRoute);
                  }
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
                  _openScoreboardStudio(context);
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item['icon'] as IconData,
                    size: 16,
                    color: isSelected ? AppTheme.cyanAccent : Colors.white54,
                  ),
                  const SizedBox(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item['label'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                          color: isSelected ? Colors.white : AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
      ..color = isHighContrast
          ? const Color(0xFF263A5C)
          : const Color(0xFF16253B)
      ..strokeWidth = isHighContrast ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;

    final accentPaint = Paint()
      ..color = AppTheme.cyanAccent.withValues(
        alpha: isHighContrast ? 0.8 : 0.4,
      )
      ..strokeWidth = isHighContrast ? 3.0 : 2.0
      ..style = PaintingStyle.stroke;

    final linePaint = Paint()
      ..color = isHighContrast ? Colors.white30 : Colors.white12
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(
      center: center,
      width: size.width * 0.9,
      height: size.height * 0.75,
    );

    // Główny obrys boiska
    canvas.drawRect(rect, courtPaint);

    switch (sport) {
      case MatchSport.volleyball:
      case MatchSport.beachVolleyball:
        // Siatka i linie ataku 3m
        canvas.drawLine(
          Offset(rect.left, center.dy),
          Offset(rect.right, center.dy),
          accentPaint,
        );
        canvas.drawLine(
          Offset(rect.left, center.dy - 40),
          Offset(rect.right, center.dy - 40),
          linePaint,
        );
        canvas.drawLine(
          Offset(rect.left, center.dy + 40),
          Offset(rect.right, center.dy + 40),
          linePaint,
        );
        break;

      case MatchSport.basketball:
        // Linia środkowa, koło środkowe, trumny podkoszowe
        canvas.drawLine(
          Offset(rect.left, center.dy),
          Offset(rect.right, center.dy),
          accentPaint,
        );
        canvas.drawCircle(center, 28, linePaint);
        // Trumny i kosze
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(center.dx, rect.top + 20),
            width: 60,
            height: 40,
          ),
          linePaint,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(center.dx, rect.bottom - 20),
            width: 60,
            height: 40,
          ),
          linePaint,
        );
        break;

      case MatchSport.football:
        // Linia środkowa, koło środkowe, pola karne
        canvas.drawLine(
          Offset(rect.left, center.dy),
          Offset(rect.right, center.dy),
          accentPaint,
        );
        canvas.drawCircle(center, 34, linePaint);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(center.dx, rect.top + 25),
            width: 100,
            height: 50,
          ),
          linePaint,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(center.dx, rect.bottom - 25),
            width: 100,
            height: 50,
          ),
          linePaint,
        );
        break;

      case MatchSport.generic:
        canvas.drawLine(
          Offset(rect.left, center.dy),
          Offset(rect.right, center.dy),
          accentPaint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant SportCourtPainter oldDelegate) =>
      oldDelegate.sport != sport ||
      oldDelegate.isHighContrast != isHighContrast;
}
