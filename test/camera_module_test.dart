import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/services/video_storage_service.dart';
import 'package:volleylive/domain/models/camera_config.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/services/recording_service.dart';
import 'package:volleylive/domain/services/video_transport_service.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/screens/phone_a_camera/phone_a_camera_screen.dart';
import 'package:volleylive/presentation/screens/settings/video_settings_modal.dart';
import 'package:volleylive/presentation/widgets/camera_controls_overlay.dart';

class FakeLowStorageService extends VideoStorageService {
  @override
  Future<bool> hasSufficientStorageSpace({int requiredMegabytes = 100}) async {
    return false;
  }
}

void main() {
  group('CameraProvider Unit Tests', () {
    late CameraProvider cameraProvider;

    setUp(() {
      cameraProvider = CameraProvider(enableAudioSim: false);
    });

    tearDown(() {
      cameraProvider.dispose();
    });

    test('Initializes with standard broadcast defaults', () {
      expect(cameraProvider.settings.resolution, VideoResolution.res1080p);
      expect(cameraProvider.settings.fps, VideoFps.fps60);
      expect(cameraProvider.settings.bitrateMbps, 8.0);
      expect(cameraProvider.settings.zoom, 1.0);
      expect(cameraProvider.settings.exposureOffset, 0.0);
      expect(cameraProvider.settings.isHudVisible, true);
      expect(cameraProvider.settings.isExposureLocked, false);
      expect(cameraProvider.settings.isFocusLocked, false);
    });

    test('Sets and clamps zoom levels properly', () async {
      await cameraProvider.setZoom(2.5);
      expect(cameraProvider.settings.zoom, 2.5);

      // Clamped to max
      await cameraProvider.setZoom(10.0);
      expect(cameraProvider.settings.zoom, cameraProvider.settings.maxZoomLevel);

      // Clamped to min
      await cameraProvider.setZoom(0.2);
      expect(cameraProvider.settings.zoom, cameraProvider.settings.minZoomLevel);
    });

    test('Sets and clamps exposure offset EV values', () async {
      await cameraProvider.setExposureOffset(1.2);
      expect(cameraProvider.settings.exposureOffset, 1.2);

      await cameraProvider.setExposureOffset(-1.5);
      expect(cameraProvider.settings.exposureOffset, -1.5);

      // Clamping
      await cameraProvider.setExposureOffset(4.0);
      expect(cameraProvider.settings.exposureOffset, cameraProvider.settings.maxExposureOffset);
    });

    test('Handles focus and exposure locking and reset', () async {
      await cameraProvider.toggleExposureLock();
      expect(cameraProvider.settings.isExposureLocked, true);

      await cameraProvider.toggleFocusLock();
      expect(cameraProvider.settings.isFocusLocked, true);

      await cameraProvider.setFocusAndExposurePoint(const Offset(0.5, 0.5));
      expect(cameraProvider.settings.isManualFocusMode, true);
      expect(cameraProvider.settings.focusPoint, const Offset(0.5, 0.5));

      await cameraProvider.resetFocusAndExposure();
      expect(cameraProvider.settings.exposureOffset, 0.0);
      expect(cameraProvider.settings.isExposureLocked, false);
      expect(cameraProvider.settings.isFocusLocked, false);
      expect(cameraProvider.settings.isManualFocusMode, false);
      expect(cameraProvider.settings.focusPoint, isNull);
    });

    test('Toggles HUD visibility for clean viewfinder', () {
      expect(cameraProvider.settings.isHudVisible, true);
      cameraProvider.toggleHudVisibility();
      expect(cameraProvider.settings.isHudVisible, false);
      cameraProvider.toggleHudVisibility();
      expect(cameraProvider.settings.isHudVisible, true);
    });

    test('Updates video resolution, fps and bitrate', () {
      cameraProvider.setResolution(VideoResolution.res4k);
      expect(cameraProvider.settings.resolution, VideoResolution.res4k);

      cameraProvider.setFps(VideoFps.fps30);
      expect(cameraProvider.settings.fps, VideoFps.fps30);

      cameraProvider.setBitrate(12.0);
      expect(cameraProvider.settings.bitrateMbps, 12.0);
    });
  });

  group('Master REC & RecordingService Unit Tests', () {
    test('RecordingService starts, tracks duration, and creates MasterRecordingResult on stop', () async {
      final recordingService = RecordingService();
      expect(recordingService.currentState, RecordingState.idle);

      await recordingService.startMasterRecording(isSimulation: true);
      expect(recordingService.currentState, RecordingState.recording);

      // Symulacja upływu czasu nagrania
      await Future.delayed(const Duration(milliseconds: 1050));
      expect(recordingService.recordedDuration.inSeconds >= 1, isTrue);

      final result = await recordingService.stopRecording();
      expect(recordingService.currentState, RecordingState.saved);
      expect(result, isNotNull);
      expect(result!.filePath, isNotEmpty);
      expect(result.fileSizeBytes, greaterThan(0));
      expect(result.formattedSize, isNotEmpty);
      expect(result.formattedDuration, isNotEmpty);
      expect(result.fileName, contains('MASTER_REC_'));
      expect(result.isSimulated, isTrue);

      recordingService.dispose();
    });

    test('Żelazna zasada WSAD.md: Master REC trwa nieprzerwanie mimo utraty i restartu połączenia P2P', () async {
      final transportService = VideoTransportService();
      final recordingService = RecordingService();
      final cameraProvider = CameraProvider(
        enableAudioSim: false,
        recordingService: recordingService,
        transportService: transportService,
      );

      // Połącz z Phone B
      await cameraProvider.connectToScorer('HOST-888');
      expect(cameraProvider.connectionState, CameraConnectionState.connected);

      // Rozpocznij Master REC
      await cameraProvider.toggleMasterRecording();
      expect(cameraProvider.isRecording, isTrue);
      expect(cameraProvider.recordingState, RecordingState.recording);

      // Zerwij połączenie WebRTC/P2P
      transportService.simulateConnectionDrop();
      expect(cameraProvider.connectionState, CameraConnectionState.reconnecting);

      // Żelazna zasada: Master REC nadal trwa!
      expect(cameraProvider.isRecording, isTrue);
      expect(cameraProvider.recordingState, RecordingState.recording);

      // Całkowite rozłączenie sieci
      await transportService.disconnect();
      expect(cameraProvider.connectionState, CameraConnectionState.disconnected);

      // Master REC nadal trwa!
      expect(cameraProvider.isRecording, isTrue);
      expect(cameraProvider.recordingState, RecordingState.recording);

      // Zakończenie nagrania
      await cameraProvider.toggleMasterRecording();
      expect(cameraProvider.recordingState, RecordingState.saved);
      expect(cameraProvider.lastRecordingResult, isNotNull);

      cameraProvider.dispose();
    });

    test('Zabezpieczenie braku miejsca na dysku: zgłasza błąd i stan failed', () async {
      final recordingService = RecordingService(storageService: FakeLowStorageService());
      final cameraProvider = CameraProvider(
        enableAudioSim: false,
        recordingService: recordingService,
      );

      await cameraProvider.toggleMasterRecording();
      expect(cameraProvider.recordingState, RecordingState.failed);
      expect(cameraProvider.recordingErrorMessage, contains('przestrzeni dyskowej'));

      cameraProvider.dispose();
    });
  });

  group('PhoneACameraScreen Widget Tests', () {
    Widget buildTestApp({CameraProvider? customCamera}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CameraProvider>(
            create: (_) => customCamera ?? CameraProvider(enableAudioSim: false),
          ),
          ChangeNotifierProvider<MatchProvider>(
            create: (_) => MatchProvider(),
          ),
          ChangeNotifierProvider<StreamerProvider>(
            create: (_) => StreamerProvider(),
          ),
          ChangeNotifierProvider<P2PConnectionProvider>(
            create: (_) => P2PConnectionProvider(),
          ),
        ],
        child: const MaterialApp(
          home: PhoneACameraScreen(),
        ),
      );
    }

    testWidgets('Renders full camera UI with telemetry, controls, and Start button', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 100));

      // Podgląd i HUD
      expect(find.byType(PhoneACameraScreen), findsOneWidget);
      expect(find.textContaining('REC: GOTOWY'), findsOneWidget);
      expect(find.text('START TRANSMISJI'), findsOneWidget);
      expect(find.text('REC'), findsOneWidget);
      expect(find.text('CZYSTY KADR'), findsOneWidget);
      expect(find.text('STATYW'), findsOneWidget);
      expect(find.byType(CameraControlsOverlay), findsOneWidget);
    });

    testWidgets('Toggles HUD clean view mode when clicking CZYSTY KADR and POKAŻ HUD', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('CZYSTY KADR'), findsOneWidget);
      expect(find.text('START TRANSMISJI'), findsOneWidget);

      // Kliknij "CZYSTY KADR"
      await tester.tap(find.text('CZYSTY KADR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Dolny i górny pasek powinny być ukryte
      expect(find.text('START TRANSMISJI'), findsNothing);
      expect(find.text('POKAŻ HUD'), findsOneWidget);

      // Przywróć HUD
      await tester.tap(find.text('POKAŻ HUD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('START TRANSMISJI'), findsOneWidget);
      expect(find.text('CZYSTY KADR'), findsOneWidget);
    });

    testWidgets('Opens VideoSettingsModal and adjusts resolution & bitrate', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 100));

      // Kliknij ikonkę parametrów wideo (tune)
      final tuneButton = find.byIcon(Icons.tune);
      expect(tuneButton, findsOneWidget);
      await tester.tap(tuneButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(VideoSettingsModal), findsOneWidget);
      expect(find.text('Konfiguracja Wideo i Transmisji'), findsOneWidget);
      expect(find.text('4K Ultra HD'), findsOneWidget);
      expect(find.text('720p HD'), findsOneWidget);

      // Wybierz 720p
      await tester.tap(find.text('720p HD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Zastosuj ustawienia
      await tester.ensureVisible(find.text('ZASTOSUJ USTAWIENIA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('ZASTOSUJ USTAWIENIA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(VideoSettingsModal), findsNothing);
    });

    testWidgets('Starts and stops Master REC, displaying completion dialog with file path, size, and duration', (tester) async {
      final camera = CameraProvider(enableAudioSim: false);
      await tester.pumpWidget(buildTestApp(customCamera: camera));
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Stan początkowy
      expect(find.text('REC'), findsOneWidget);

      // 2. Start nagrywania
      await tester.tap(find.text('REC'));
      await tester.pump();
      for (int i = 0; i < 10 && !camera.isRecording; i++) {
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }

      expect(camera.isRecording, isTrue);
      expect(find.text('REC STOP'), findsOneWidget);

      // 3. Zatrzymanie nagrywania
      await tester.tap(find.text('REC STOP'));
      await tester.pump();
      for (int i = 0; i < 20 && camera.recordingState != RecordingState.saved; i++) {
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // 4. Wyświetlenie okna dialogowego z podsumowaniem zapisanego pliku
      expect(find.text('Master REC Zapisany'), findsOneWidget);
      expect(find.text('Plik'), findsOneWidget);
      expect(find.text('Czas nagrania'), findsOneWidget);
      expect(find.text('Rozmiar'), findsOneWidget);
      expect(find.text('Ścieżka zapisu'), findsOneWidget);

      // 5. Zamknięcie dialogu
      await tester.tap(find.text('ZAMKNIJ'));
      await tester.pumpAndSettle();
      expect(find.text('Master REC Zapisany'), findsNothing);

      // 6. Odznaka w telemetrii pokazuje stan zapisania
      expect(find.textContaining('REC: ZAPISANO'), findsOneWidget);

      // 7. Ponowne kliknięcie w odznakę otwiera podsumowanie
      await tester.tap(find.textContaining('REC: ZAPISANO'));
      await tester.pumpAndSettle();
      expect(find.text('Master REC Zapisany'), findsOneWidget);
    });
  });
}
