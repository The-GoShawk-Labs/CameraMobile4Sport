import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/presentation/services/scoreboard_widget_burner.dart';
import 'package:volleylive/presentation/widgets/scoreboard_overlay.dart';

void main() {
  group('VolleyballScoreboardState Burn-in Serialization Tests', () {
    test('Maps MatchSession correctly to VolleyballScoreboardState', () {
      final session = MatchSession(
        id: 'test-session-1',
        createdAt: DateTime.now(),
        teamA: 'Projekt Warszawa',
        teamB: 'ZAKSA Kędzierzyn-Koźle',
        setsA: 2,
        setsB: 1,
        currentSetPointsA: 24,
        currentSetPointsB: 22,
        currentSetNumber: 4,
        currentServer: ServingTeam.teamA,
        pairingCode: '123456',
      );

      final state = VolleyballScoreboardState.fromMatchSession(
        session,
        eventTag: 'MATCH POINT',
      );

      expect(state.teamA, 'PROJEKT WARSZAWA');
      expect(state.teamB, 'ZAKSA KĘDZIERZYN-KOŹLE');
      expect(state.scoreA, 24);
      expect(state.scoreB, 22);
      expect(state.currentSet, 4);
      expect(state.setsA, 2);
      expect(state.setsB, 1);
      expect(state.servingTeam, 'A');
      expect(state.eventTag, 'MATCH POINT');

      final map = state.toMap();
      expect(map['teamA'], 'PROJEKT WARSZAWA');
      expect(map['teamB'], 'ZAKSA KĘDZIERZYN-KOŹLE');
      expect(map['scoreA'], 24);
      expect(map['scoreB'], 22);
      expect(map['currentSet'], 4);
      expect(map['setsA'], 2);
      expect(map['setsB'], 1);
      expect(map['servingTeam'], 'A');
      expect(map['eventTag'], 'MATCH POINT');
    });

    test('Serving indicator maps correctly for Team B and None', () {
      final sessionB = MatchSession(
        id: 'test-2',
        createdAt: DateTime.now(),
        teamA: 'Team 1',
        teamB: 'Team 2',
        currentServer: ServingTeam.teamB,
        pairingCode: '654321',
      );
      final stateB = VolleyballScoreboardState.fromMatchSession(sessionB);
      expect(stateB.servingTeam, 'B');

      final sessionNone = MatchSession(
        id: 'test-3',
        createdAt: DateTime.now(),
        teamA: 'Team 1',
        teamB: 'Team 2',
        currentServer: ServingTeam.none,
        pairingCode: '000000',
      );
      final stateNone = VolleyballScoreboardState.fromMatchSession(sessionNone);
      expect(stateNone.servingTeam, 'NONE');
    });
  });

  group('ScoreboardWidgetBurner Widget Tests', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel('com.goshawk.volleylive/live_stream_bridge'),
            (call) async {
              if (call.method == 'updateScoreboardOverlayBitmap') {
                return true;
              }
              return null;
            },
          );
    });

    testWidgets(
      'Renders and captures ScoreboardOverlay in all broadcast theme styles',
      (tester) async {
        final session = MatchSession(
          id: 'test-widget-capture',
          createdAt: DateTime.now(),
          teamA: 'Aluron CMC',
          teamB: 'Asseco Resovia',
          setsA: 1,
          setsB: 0,
          currentSetPointsA: 21,
          currentSetPointsB: 19,
          currentSetNumber: 2,
          currentServer: ServingTeam.teamA,
          pairingCode: '112233',
        );

        for (final style in ScoreboardThemeStyle.values) {
          final key = GlobalKey();
          final burner = ScoreboardWidgetBurner(boundaryKey: key);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: SizedBox(
                      width: 720,
                      child: ScoreboardOverlay(
                        session: session,
                        style: style,
                        isTimeoutActive: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Capture authentic widget rasterization inside real async zone
          await tester.runAsync(() async {
            final captured = await burner.captureAndPush();
            expect(captured, isA<bool>());
          });
        }
      },
    );

    test(
      'generateBroadcastOverlayPng produces valid PNG bytes for all broadcast theme styles',
      () async {
        final session = MatchSession(
          id: 'test-png-gen',
          createdAt: DateTime.now(),
          teamA: 'Jastrzębski Węgiel',
          teamB: 'PGE GiEK Skra Bełchatów',
          setsA: 2,
          setsB: 1,
          currentSetPointsA: 25,
          currentSetPointsB: 23,
          currentSetNumber: 4,
          currentServer: ServingTeam.teamB,
          pairingCode: '998877',
        );

        for (final style in ScoreboardThemeStyle.values) {
          final pngBytes =
              await ScoreboardWidgetBurner.generateBroadcastOverlayPng(
                session: session,
                style: style,
                isPortrait: false,
                activeSpecialEvent: 'MATCH POINT!',
              );
          expect(pngBytes, isNotEmpty);
          // Valid PNG magic signature: 0x89 'P' 'N' 'G'
          expect(pngBytes[0], 0x89);
          expect(pngBytes[1], 0x50);
          expect(pngBytes[2], 0x4E);
          expect(pngBytes[3], 0x47);
        }
      },
    );

    test(
      'saveOverlayPngToDisk and ensureOverlayImageOnDisk persist PNG to filesystem',
      () async {
        final session = MatchSession(
          id: 'test-disk-save',
          createdAt: DateTime.now(),
          teamA: 'Trefl Gdańsk',
          teamB: 'Bogdanka LUK Lublin',
          setsA: 0,
          setsB: 0,
          currentSetPointsA: 12,
          currentSetPointsB: 15,
          currentSetNumber: 1,
          currentServer: ServingTeam.teamA,
          pairingCode: '554433',
        );

        final path = await ScoreboardWidgetBurner.saveOverlayPngToDisk(
          session: session,
          style: ScoreboardThemeStyle.tvProBroadcast,
        );
        expect(path, isNotNull);
        expect(File(path!).existsSync(), isTrue);
        expect(File(path).lengthSync(), greaterThan(100));

        final ensured = await ScoreboardWidgetBurner.ensureOverlayImageOnDisk(
          session: session,
          style: ScoreboardThemeStyle.tvProBroadcast,
        );
        expect(ensured, isNotNull);
        expect(File(ensured!).existsSync(), isTrue);
      },
    );
  });
}
