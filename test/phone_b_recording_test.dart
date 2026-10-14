import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/recording_result.dart';
import 'package:volleylive/domain/models/match_recording_metadata.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/domain/services/recording_service.dart';
import 'package:volleylive/domain/services/remote_frame_recorder.dart';
import 'package:volleylive/domain/services/video_overlay_burner_service.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/screens/phone_b_scorer/phone_b_scorer_screen.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('RemoteFrameRecorder & Phone B Real Recording Tests', () {
    test(
      'RemoteFrameRecorder manifest preserves wall-clock gaps between frames',
      () {
        final manifest = RemoteFrameRecorder.buildConcatManifest(
          frameCount: 2,
          frameOffsetsSeconds: [0, 2],
          durationSeconds: 3,
          imageExtension: 'png',
        );

        expect(manifest, contains('duration 2.000000'));
        expect(manifest, contains('duration 1.000000'));
        expect(RegExp(r"file '").allMatches(manifest).length, 3);
      },
    );

    test('RemoteFrameRecorder writes frames and encodes to MP4', () async {
      final recorder = RemoteFrameRecorder();
      final controller = StreamController<Uint8List>();

      // Start recording with stream
      await recorder.startRecording(
        frameStream: controller.stream,
        initialFrame: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x01]),
      );
      expect(recorder.isRecording, isTrue);
      expect(recorder.recordedFrameCount, equals(1));

      // Add frames via stream
      controller.add(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x02]));
      controller.add(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x03]));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(recorder.recordedFrameCount, equals(3));

      // Stop recording
      final mp4Path = await recorder.stopRecordingAndEncode();
      expect(mp4Path, isNotNull);
      expect(File(mp4Path!).existsSync(), isTrue);

      await recorder.cancel();
      await controller.close();
    });

    test(
      'RecordingService integrates RemoteFrameRecorder for Program REC',
      () async {
        final recordingService = RecordingService();
        final remoteRecorder = RemoteFrameRecorder();
        final frameController = StreamController<Uint8List>.broadcast();

        final session = MatchSession(
          id: 'sess-phone-b',
          createdAt: DateTime.now(),
          pairingCode: 'PB-101',
          teamA: 'DRUŻYNA A',
          teamB: 'DRUŻYNA B',
          currentSetNumber: 1,
          currentSetPointsA: 10,
          currentSetPointsB: 8,
          setsA: 0,
          setsB: 0,
          currentServer: ServingTeam.teamA,
        );

        final dummyFrame = Uint8List.fromList([
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);

        // Start recording on Phone B
        await recordingService.startMasterRecording(
          remoteFrameRecorder: remoteRecorder,
          remoteFrameStream: frameController.stream,
          initialFrame: dummyFrame,
          remoteFrameExtension: 'png',
          remoteFramesIncludeProgramOverlay: true,
          recordingType: RecordingType.programWithScoreboard,
          initialSession: session,
        );

        expect(recordingService.currentState, equals(RecordingState.recording));
        frameController.add(dummyFrame);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Rejestracja zdarzeń na osi czasu
        recordingService.recordTimelineEvent(
          eventType: 'pointAddedA',
          session: session.copyWith(currentSetPointsA: 11),
          eventTag: 'POINT!',
        );

        // Stop recording
        final result = await recordingService.stopRecording(
          remoteFrameRecorder: remoteRecorder,
          finalSession: session.copyWith(currentSetPointsA: 11),
        );

        expect(result, isNotNull);
        expect(
          result!.recordingType,
          equals(RecordingType.programWithScoreboard),
        );
        expect(result.containsScoreboardOverlay, isTrue);
        expect(File(result.filePath).existsSync(), isTrue);

        recordingService.dispose();
        await frameController.close();
      },
    );

    test(
      'StreamerProvider blocks recording start when no camera stream is connected',
      () async {
        final streamer = StreamerProvider();

        // Próba startu bez połączenia i bez klatek
        await streamer.toggleProgramRecording(
          isConnected: false,
          frameStream: null,
        );

        expect(streamer.programRecState, equals(RecordingState.failed));
        expect(
          streamer.programRecordingErrorMessage,
          contains('Brak aktywnego połączenia'),
        );

        streamer.dispose();
      },
    );

    test(
      'StreamerProvider starts real recording when connected with frame stream',
      () async {
        final streamer = StreamerProvider();
        final frameController = StreamController<Uint8List>.broadcast();
        final initialFrame = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x01]);

        final session = MatchSession(
          id: 'sess-active',
          createdAt: DateTime.now(),
          pairingCode: 'AC-101',
          teamA: 'ALPHA',
          teamB: 'BETA',
          currentSetNumber: 1,
          currentSetPointsA: 1,
          currentSetPointsB: 0,
          setsA: 0,
          setsB: 0,
          currentServer: ServingTeam.teamA,
        );

        await streamer.toggleProgramRecording(
          matchSession: session,
          frameStream: frameController.stream,
          initialFrame: initialFrame,
          isConnected: true,
        );

        expect(streamer.programRecState, equals(RecordingState.recording));

        // Dodaj klatkę w trakcie meczu
        frameController.add(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x02]));
        await Future.delayed(const Duration(milliseconds: 50));

        // Zatrzymaj nagranie
        await streamer.toggleProgramRecording(matchSession: session);

        expect(streamer.programRecState, equals(RecordingState.saved));
        expect(streamer.lastProgramRecordingResult, isNotNull);
        expect(
          streamer.lastProgramRecordingResult!.filePath.endsWith('.mp4'),
          isTrue,
        );

        await frameController.close();
        streamer.dispose();
      },
    );

    test(
      'RecordingService rejects DUAL when only a composed program source is available',
      () async {
        final recordingService = RecordingService();
        final remoteRecorder = RemoteFrameRecorder();
        final frameController = StreamController<Uint8List>.broadcast();

        final session = MatchSession(
          id: 'sess-dual',
          createdAt: DateTime.now(),
          pairingCode: 'DL-999',
          teamA: 'TEAM RED',
          teamB: 'TEAM BLUE',
          currentSetNumber: 1,
          currentSetPointsA: 5,
          currentSetPointsB: 3,
          setsA: 0,
          setsB: 0,
          currentServer: ServingTeam.teamA,
        );

        final dummyFrame = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x55]);

        await recordingService.startMasterRecording(
          remoteFrameRecorder: remoteRecorder,
          remoteFrameStream: frameController.stream,
          initialFrame: dummyFrame,
          recordingType: RecordingType.dual,
          initialSession: session,
        );

        expect(recordingService.currentState, equals(RecordingState.recording));
        frameController.add(dummyFrame);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final result = await recordingService.stopRecording(
          remoteFrameRecorder: remoteRecorder,
          finalSession: session,
        );

        expect(result, isNull);
        expect(recordingService.currentState, equals(RecordingState.failed));
        expect(
          recordingService.lastErrorMessage,
          contains('dwóch niezależnych źródeł'),
        );

        recordingService.dispose();
        await frameController.close();
      },
    );

    test(
      'RecordingService saves distinct composed Program and clean RAW files for DUAL',
      () async {
        final recordingService = RecordingService();
        final programFrames = StreamController<Uint8List>.broadcast();
        final rawFrames = StreamController<Uint8List>.broadcast();
        final session = MatchSession(
          id: 'sess-dual-complete',
          createdAt: DateTime.now(),
          pairingCode: 'DL-100',
          teamA: 'TEAM RED',
          teamB: 'TEAM BLUE',
          currentSetNumber: 1,
          currentSetPointsA: 5,
          currentSetPointsB: 3,
          setsA: 0,
          setsB: 0,
          currentServer: ServingTeam.teamA,
        );
        final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
        final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x55]);

        await recordingService.startMasterRecording(
          remoteFrameStream: programFrames.stream,
          initialFrame: png,
          remoteFrameExtension: 'png',
          remoteFramesIncludeProgramOverlay: true,
          rawCameraFrameStream: rawFrames.stream,
          initialRawCameraFrame: jpg,
          recordingType: RecordingType.dual,
          initialSession: session,
        );
        expect(recordingService.currentState, RecordingState.recording);

        programFrames.add(png);
        rawFrames.add(jpg);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final result = await recordingService.stopRecording(
          finalSession: session,
        );
        expect(result, isNotNull);
        expect(result!.recordingType, RecordingType.dual);
        expect(result.containsScoreboardOverlay, isTrue);
        expect(result.secondaryFilePath, isNotNull);
        expect(File(result.filePath).existsSync(), isTrue);
        expect(File(result.secondaryFilePath!).existsSync(), isTrue);
        expect(result.filePath, isNot(result.secondaryFilePath));

        recordingService.dispose();
        await programFrames.close();
        await rawFrames.close();
      },
    );

    test(
      'RecordingService fails with error state when overlay burning fails for programWithScoreboard',
      () async {
        // Tworzymy serwis z mockiem burnerService, który zwraca false (błąd FFmpeg)
        final failingBurner = _MockFailingOverlayBurner();
        final recordingService = RecordingService(burnerService: failingBurner);
        final remoteRecorder = RemoteFrameRecorder();
        final frameController = StreamController<Uint8List>.broadcast();

        final session = MatchSession(
          id: 'sess-fail',
          createdAt: DateTime.now(),
          pairingCode: 'FL-000',
          teamA: 'TEAM A',
          teamB: 'TEAM B',
          currentSetNumber: 1,
          currentSetPointsA: 0,
          currentSetPointsB: 0,
          setsA: 0,
          setsB: 0,
          currentServer: ServingTeam.teamA,
        );

        await recordingService.startMasterRecording(
          remoteFrameRecorder: remoteRecorder,
          remoteFrameStream: frameController.stream,
          initialFrame: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x01]),
          recordingType: RecordingType.programWithScoreboard,
          initialSession: session,
        );

        frameController.add(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x02]));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final result = await recordingService.stopRecording(
          remoteFrameRecorder: remoteRecorder,
          finalSession: session,
        );

        // Wynik nie może udawać sukcesu
        expect(result, isNull);
        expect(recordingService.currentState, equals(RecordingState.failed));
        expect(
          recordingService.lastErrorMessage,
          contains('Wypalanie tablicy wyników'),
        );

        recordingService.dispose();
        await frameController.close();
      },
    );
  });

  group('PhoneBScorerScreen Recording UI Integration Tests', () {
    Widget buildScorerApp({
      required P2PConnectionProvider p2p,
      required StreamerProvider streamer,
      required MatchProvider match,
      required CameraProvider camera,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<P2PConnectionProvider>.value(value: p2p),
          ChangeNotifierProvider<StreamerProvider>.value(value: streamer),
          ChangeNotifierProvider<MatchProvider>.value(value: match),
          ChangeNotifierProvider<CameraProvider>.value(value: camera),
        ],
        child: const MaterialApp(home: PhoneBScorerScreen()),
      );
    }

    testWidgets(
      'Shows error notice when attempting to record without camera feed in Phone B mode',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final p2p = P2PConnectionProvider();
        p2p.selectRole(DeviceRole.scorerPhoneB);

        final streamer = StreamerProvider();
        final match = MatchProvider();
        final camera = CameraProvider(enableAudioSim: false);

        await tester.pumpWidget(
          buildScorerApp(
            p2p: p2p,
            streamer: streamer,
            match: match,
            camera: camera,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Find START REC button
        final recBtn = find.text('START REC');
        expect(recBtn, findsOneWidget);

        await tester.tap(recBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Powinien pojawić się komunikat o braku połączenia z kamerą Phone A
        expect(
          find.textContaining('Brak aktywnego połączenia z kamerą Phone A'),
          findsOneWidget,
        );

        p2p.dispose();
        streamer.dispose();
        match.dispose();
        camera.dispose();
      },
    );

    testWidgets(
      'Shows stream timeout UI overlay and retry button when camera stream times out',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final p2p = P2PConnectionProvider();
        p2p.selectRole(DeviceRole.scorerPhoneB);
        p2p.setConnectionStateForTesting(CameraConnectionState.connected);
        p2p.setStreamTimeout(true);

        final streamer = StreamerProvider();
        final match = MatchProvider();
        final camera = CameraProvider(enableAudioSim: false);

        await tester.pumpWidget(
          buildScorerApp(
            p2p: p2p,
            streamer: streamer,
            match: match,
            camera: camera,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Powinno pojawić się ostrzeżenie o timeoucie oraz przyciski PONÓW i PAROWANIE
        expect(find.textContaining('TIMEOUT STRUMIENIA'), findsWidgets);
        expect(find.text('PONÓW'), findsOneWidget);
        expect(find.text('PAROWANIE'), findsOneWidget);

        // Naciśnięcie 'PONÓW' powinno wyczyścić flagę hasStreamTimeout
        await tester.tap(find.text('PONÓW'));
        await tester.pump();
        expect(p2p.hasStreamTimeout, isFalse);

        p2p.dispose();
        streamer.dispose();
        match.dispose();
        camera.dispose();
      },
    );
  });
}

class _MockFailingOverlayBurner extends VideoOverlayBurnerService {
  @override
  Future<bool> burnScoreboardToMp4({
    required String sourceVideoPath,
    required String targetVideoPath,
    required List<ScoreTimelineEntry> timeline,
    required MatchSession matchSession,
    required Duration duration,
    ScoreboardThemeStyle style = ScoreboardThemeStyle.tvProBroadcast,
    bool isPortrait = false,
    String? overlayImagePath,
    Uint8List? overlayPngBytes,
  }) async {
    return false;
  }
}
