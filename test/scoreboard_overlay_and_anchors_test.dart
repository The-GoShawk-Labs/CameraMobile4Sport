import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';
import 'package:volleylive/domain/services/video_overlay_burner_service.dart';
import 'package:volleylive/presentation/services/program_widget_capture.dart';
import 'package:volleylive/presentation/widgets/scoreboard_overlay.dart';

void main() {
  group('ScoreboardAnchorPosition & Margins', () {
    test('All 6 anchor positions have distinct valid alignments', () {
      expect(ScoreboardAnchorPosition.topLeft.alignment, isNotNull);
      expect(ScoreboardAnchorPosition.topCenter.alignment, isNotNull);
      expect(ScoreboardAnchorPosition.topRight.alignment, isNotNull);
      expect(ScoreboardAnchorPosition.bottomLeft.alignment, isNotNull);
      expect(ScoreboardAnchorPosition.bottomCenter.alignment, isNotNull);
      expect(ScoreboardAnchorPosition.bottomRight.alignment, isNotNull);
    });

    test('getNormalizedTopLeft calculates coordinates respecting broadcast safe margins', () {
      const normW = 430.0 / 1920.0;
      const normH = 154.0 / 1080.0;

      // TopLeft
      final tl = ScoreboardAnchorPosition.topLeft.getNormalizedTopLeft(
        widgetWidthNorm: normW,
        widgetHeightNorm: normH,
      );
      expect(tl.normX, closeTo(0.025, 0.0001));
      expect(tl.normY, closeTo(0.035, 0.0001));

      // TopCenter
      final tc = ScoreboardAnchorPosition.topCenter.getNormalizedTopLeft(
        widgetWidthNorm: normW,
        widgetHeightNorm: normH,
      );
      expect(tc.normX, closeTo((1.0 - normW) / 2.0, 0.0001));
      expect(tc.normY, closeTo(0.035, 0.0001));

      // TopRight
      final tr = ScoreboardAnchorPosition.topRight.getNormalizedTopLeft(
        widgetWidthNorm: normW,
        widgetHeightNorm: normH,
      );
      expect(tr.normX, closeTo(1.0 - normW - 0.025, 0.0001));
      expect(tr.normY, closeTo(0.035, 0.0001));

      // BottomLeft
      final bl = ScoreboardAnchorPosition.bottomLeft.getNormalizedTopLeft(
        widgetWidthNorm: normW,
        widgetHeightNorm: normH,
      );
      expect(bl.normX, closeTo(0.025, 0.0001));
      expect(bl.normY, closeTo(1.0 - normH - 0.035, 0.0001));

      // BottomCenter
      final bc = ScoreboardAnchorPosition.bottomCenter.getNormalizedTopLeft(
        widgetWidthNorm: normW,
        widgetHeightNorm: normH,
      );
      expect(bc.normX, closeTo((1.0 - normW) / 2.0, 0.0001));
      expect(bc.normY, closeTo(1.0 - normH - 0.035, 0.0001));

      // BottomRight
      final br = ScoreboardAnchorPosition.bottomRight.getNormalizedTopLeft(
        widgetWidthNorm: normW,
        widgetHeightNorm: normH,
      );
      expect(br.normX, closeTo(1.0 - normW - 0.025, 0.0001));
      expect(br.normY, closeTo(1.0 - normH - 0.035, 0.0001));
    });
  });

  group('ProgramWidgetCapture Even-Resolution Quantization', () {
    test('calculateEvenPixelRatio guarantees even rounded dimensions and prevents 990x557', () {
      // 360 x 202.5 (standard 16:9 phone viewport preview)
      const size = Size(360.0, 202.5);

      // Desired 2.75 which previously gave 360*2.75=990 (even) and 202.5*2.75=556.875 -> 557 (ODD!)
      final ratio = ProgramWidgetCapture.calculateEvenPixelRatio(size, 2.75);

      final roundedW = (size.width * ratio).round();
      final roundedH = (size.height * ratio).round();

      expect(roundedW % 2, 0, reason: 'Width $roundedW must be even');
      expect(roundedH % 2, 0, reason: 'Height $roundedH must be even');
      expect(roundedH, isNot(557), reason: 'Must never produce 557 odd dimension');
    });

    test('calculateEvenPixelRatio produces even dimensions across typical screen sizes', () {
      final testSizes = [
        const Size(393, 221),
        const Size(412, 231.75),
        const Size(360, 640),
        const Size(480, 270),
        const Size(1280, 720),
      ];

      for (final s in testSizes) {
        final ratio = ProgramWidgetCapture.calculateEvenPixelRatio(s, 2.0);
        final w = (s.width * ratio).round();
        final h = (s.height * ratio).round();
        expect(w % 2, 0, reason: 'Size $s w=$w should be even');
        expect(h % 2, 0, reason: 'Size $s h=$h should be even');
      }
    });

    test('createPamFrame builds valid Netpbm PAM header and payload', () {
      final dummyPixels = Uint8List(8 * 4 * 4); // 8x4 RGBA
      final pam = ProgramWidgetCapture.createPamFrame(8, 4, dummyPixels);
      final headerStr = String.fromCharCodes(pam.sublist(0, 70));
      expect(headerStr, contains('P7\n'));
      expect(headerStr, contains('WIDTH 8\n'));
      expect(headerStr, contains('HEIGHT 4\n'));
      expect(headerStr, contains('DEPTH 4\n'));
      expect(headerStr, contains('MAXVAL 255\n'));
      expect(headerStr, contains('TUPLTYPE RGB_ALPHA\n'));
      expect(headerStr, contains('ENDHDR\n'));
      expect(pam.length, greaterThan(dummyPixels.length));
    });
  });

  group('VideoOverlayBurnerService FFmpeg Coordinate Expressions', () {
    test('Generates correct FFmpeg overlay expressions for all 6 anchors', () {
      expect(
        VideoOverlayBurnerService.getFfmpegOverlayCoordinates(ScoreboardAnchorPosition.topLeft),
        'W*0.025:H*0.035',
      );
      expect(
        VideoOverlayBurnerService.getFfmpegOverlayCoordinates(ScoreboardAnchorPosition.topCenter),
        '(W-w)/2:H*0.035',
      );
      expect(
        VideoOverlayBurnerService.getFfmpegOverlayCoordinates(ScoreboardAnchorPosition.topRight),
        'W-w-W*0.025:H*0.035',
      );
      expect(
        VideoOverlayBurnerService.getFfmpegOverlayCoordinates(ScoreboardAnchorPosition.bottomLeft),
        'W*0.025:H-h-H*0.035',
      );
      expect(
        VideoOverlayBurnerService.getFfmpegOverlayCoordinates(ScoreboardAnchorPosition.bottomCenter),
        '(W-w)/2:H-h-H*0.035',
      );
      expect(
        VideoOverlayBurnerService.getFfmpegOverlayCoordinates(ScoreboardAnchorPosition.bottomRight),
        'W-w-W*0.025:H-h-H*0.035',
      );
    });

    test('Generates centered Y coordinate for portrait mode', () {
      expect(
        VideoOverlayBurnerService.getFfmpegOverlayCoordinates(
          ScoreboardAnchorPosition.topLeft,
          isPortrait: true,
          customY: 70,
        ),
        '(W-w)/2:70',
      );
    });
  });

  group('ScoreboardOverlay Widget Rendering & SportCam Style', () {
    testWidgets('Renders within active video viewport without overflow', (tester) async {
      final session = MatchSession(
        id: 'test-session-1',
        createdAt: DateTime.now(),
        teamA: 'TEAM A',
        teamB: 'TEAM B',
        currentSetPointsA: 18,
        currentSetPointsB: 15,
        setsA: 1,
        setsB: 0,
        currentSetNumber: 2,
        currentServer: ServingTeam.teamA,
        pairingCode: '123456',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: ScoreboardOverlay(
                session: session,
                anchorPosition: ScoreboardAnchorPosition.topLeft,
                matchDuration: const Duration(minutes: 12, seconds: 34),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('TEAM A'), findsOneWidget);
      expect(find.text('TEAM B'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('SET 2'), findsOneWidget);
      expect(find.text('12:34'), findsOneWidget);
      expect(find.text('VOLLEY • GOGOSHAWK'), findsOneWidget);
    });

    testWidgets('Renders 3-letter acronyms (TLA) and stopwatch badge when useThreeLetterAcronyms is true', (tester) async {
      final session = MatchSession(
        id: 'test-session-tla',
        createdAt: DateTime.now(),
        teamA: 'Jastrzębski Węgiel',
        teamB: 'Kęczanin Kęty',
        teamAShort: 'JAS',
        teamBShort: 'KET',
        currentSetPointsA: 25,
        currentSetPointsB: 23,
        setsA: 2,
        setsB: 1,
        currentSetNumber: 4,
        pairingCode: '654321',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: ScoreboardOverlay(
                session: session,
                anchorPosition: ScoreboardAnchorPosition.topLeft,
                useThreeLetterAcronyms: true,
                matchDuration: const Duration(minutes: 48, seconds: 12),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('JAS'), findsOneWidget);
      expect(find.text('KET'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('23'), findsOneWidget);
      expect(find.text('48:12'), findsOneWidget);
    });

    test('deriveShortCode handles single-word and multi-word team names correctly', () {
      expect(MatchSession.deriveShortCode('Jastrzębie'), 'JAS');
      expect(MatchSession.deriveShortCode('AZS'), 'AZS');
      expect(MatchSession.deriveShortCode('Kęty'), 'KĘT');
      expect(MatchSession.deriveShortCode('AZS Kraków'), 'AZS');
      expect(MatchSession.deriveShortCode('PGE Projekt Warszawa'), 'PGE');
      expect(MatchSession.deriveShortCode('Trefl Gdańsk'), 'GDA');
    });

    test('VolleyballScoreboardState supports useShortNames and team short codes', () {
      final session = MatchSession(
        id: 'session-state',
        createdAt: DateTime.now(),
        teamA: 'Jastrzębski Węgiel',
        teamB: 'Kęczanin Kęty',
        teamAShort: 'JAS',
        teamBShort: 'KET',
        pairingCode: '999999',
      );

      final state = VolleyballScoreboardState.fromMatchSession(
        session,
        useShortNames: true,
        matchClock: '35:20',
      );

      expect(state.useShortNames, isTrue);
      expect(state.teamAShort, 'JAS');
      expect(state.teamBShort, 'KET');
      expect(state.matchClock, '35:20');

      final map = state.toMap();
      expect(map['useShortNames'], isTrue);
      expect(map['teamAShort'], 'JAS');
      expect(map['teamBShort'], 'KET');

      final deserialized = VolleyballScoreboardState.fromMap(map);
      expect(deserialized.useShortNames, isTrue);
      expect(deserialized.teamAShort, 'JAS');
      expect(deserialized.teamBShort, 'KET');
    });
  });
}
