import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/domain/models/camera_config.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/screens/phone_a_camera/phone_a_camera_screen.dart';
import 'package:volleylive/presentation/screens/settings/video_settings_modal.dart';
import 'package:volleylive/presentation/widgets/camera_controls_overlay.dart';

void main() {
  group('CameraProvider Unit Tests', () {
    late CameraProvider cameraProvider;

    setUp(() {
      cameraProvider = CameraProvider();
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
      expect(find.textContaining('MASTER REC: GOTOWY'), findsOneWidget);
      expect(find.text('START TRANSMISJI / ZAPISU'), findsOneWidget);
      expect(find.text('CZYSTY KADR'), findsOneWidget);
      expect(find.text('STATYW'), findsOneWidget);
      expect(find.byType(CameraControlsOverlay), findsOneWidget);
    });

    testWidgets('Toggles HUD clean view mode when clicking CZYSTY KADR and POKAŻ HUD', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('CZYSTY KADR'), findsOneWidget);
      expect(find.text('START TRANSMISJI / ZAPISU'), findsOneWidget);

      // Kliknij "CZYSTY KADR"
      await tester.tap(find.text('CZYSTY KADR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Dolny i górny pasek powinny być ukryte
      expect(find.text('START TRANSMISJI / ZAPISU'), findsNothing);
      expect(find.text('POKAŻ HUD'), findsOneWidget);

      // Przywróć HUD
      await tester.tap(find.text('POKAŻ HUD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('START TRANSMISJI / ZAPISU'), findsOneWidget);
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
  });
}
