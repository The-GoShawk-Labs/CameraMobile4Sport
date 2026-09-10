import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/services/match_engine.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/screens/pairing/phone_b_match_setup_screen.dart';
import 'package:volleylive/presentation/screens/phone_b_scorer/phone_b_scorer_screen.dart';
import 'package:volleylive/presentation/widgets/tactile_score_pad.dart';

void main() {
  group('Multi-Sport MatchEngine & Provider Tests', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine();
    });

    test('Initializes with default sport (Volleyball) and custom parameters', () {
      final session = engine.createNewMatch(
        sport: MatchSport.volleyball,
        teamA: 'TEAM A',
        teamB: 'TEAM B',
        tournamentName: 'PUCHAR POLSKI',
      );

      expect(session.sport, equals(MatchSport.volleyball));
      expect(session.tournamentName, equals('PUCHAR POLSKI'));
      expect(session.periodDisplay, equals('SET 1'));
      expect(session.sport.pointIncrements, equals([1]));
    });

    test('Basketball supports +1, +2, +3 increments, quarters and fouls', () {
      var session = engine.createNewMatch(
        sport: MatchSport.basketball,
        teamA: 'LAKERS',
        teamB: 'CELTICS',
      );

      expect(session.periodDisplay, equals('KWARTA 1'));
      expect(session.sport.pointIncrements, equals([1, 2, 3]));

      // Add 3-pointer for team A
      session = engine.addPointA(session, points: 3);
      expect(session.currentSetPointsA, equals(3));

      // Add 2-pointer for team B
      session = engine.addPointB(session, points: 2);
      expect(session.currentSetPointsB, equals(2));

      // Add fouls
      session = engine.addFoulA(session);
      session = engine.addFoulB(session);
      expect(session.foulsA, equals(1));
      expect(session.foulsB, equals(1));

      // Advance quarter (points continue in basketball)
      session = engine.nextPeriod(session);
      expect(session.currentSetNumber, equals(2));
      expect(session.periodDisplay, equals('KWARTA 2'));
      expect(session.currentSetPointsA, equals(3));
      expect(session.currentSetPointsB, equals(2));
      expect(session.foulsA, equals(0)); // Fouls reset per quarter
    });

    test('Deterministic Undo works correctly across multi-point additions and fouls', () {
      var session = engine.createNewMatch(
        sport: MatchSport.basketball,
        teamA: 'TEAM A',
        teamB: 'TEAM B',
      );

      session = engine.addPointA(session, points: 3);
      session = engine.addPointB(session, points: 2);
      session = engine.addFoulA(session);

      expect(session.currentSetPointsA, equals(3));
      expect(session.currentSetPointsB, equals(2));
      expect(session.foulsA, equals(1));

      // Undo foul
      session = engine.undo(session)!;
      expect(session.foulsA, equals(0));
      expect(session.currentSetPointsB, equals(2));

      // Undo 2 points for B
      session = engine.undo(session)!;
      expect(session.currentSetPointsB, equals(0));
      expect(session.currentSetPointsA, equals(3));

      // Undo 3 points for A
      session = engine.undo(session)!;
      expect(session.currentSetPointsA, equals(0));
    });
  });

  group('Multi-Sport Scoreboarding UI Widgets Tests', () {
    Widget buildTestHarness(Widget child) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MatchProvider()),
          ChangeNotifierProvider(create: (_) => StreamerProvider()),
          ChangeNotifierProvider(create: (_) => CameraProvider()),
          ChangeNotifierProvider(create: (_) => P2PConnectionProvider()),
        ],
        child: MaterialApp(
          home: child,
        ),
      );
    }

    testWidgets('PhoneBMatchSetupScreen renders all sports options and team fields', (tester) async {
      await tester.pumpWidget(buildTestHarness(const PhoneBMatchSetupScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('KONFIGURACJA PRZEDMECZOWA'), findsOneWidget);
      expect(find.text('WYBÓR RODZAJU TABLICY I DYSCYPLINY'), findsOneWidget);
      expect(find.text('SIATKÓWKA HALOWA'), findsOneWidget);
      expect(find.text('KOSZYKÓWKA'), findsOneWidget);
      expect(find.text('PIŁKA NOŻNA / FUTSAL'), findsOneWidget);
      expect(find.text('POŁĄCZ ZE SMARTFONEM KAMERĄ (PHONE A)'), findsOneWidget);
    });

    testWidgets('TactileScorePad renders basketball buttons (+1, +2, +3, -1) and fouls', (tester) async {
      final session = MatchSession(
        id: 'test-id',
        createdAt: DateTime.now(),
        pairingCode: 'TEST99',
        sport: MatchSport.basketball,
        teamA: 'WARRIORS',
        teamB: 'BULLS',
        currentSetPointsA: 10,
        currentSetPointsB: 8,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TactileScorePad(
              session: session,
              onAddPointA: (_) {},
              onAddPointB: (_) {},
              onSubtractPointA: () {},
              onSubtractPointB: () {},
              onUndo: () {},
              onToggleRotation: () {},
              onRequestTimeoutA: () {},
              onRequestTimeoutB: () {},
              onRequestSubA: () {},
              onRequestSubB: () {},
              onAddFoulA: () {},
              onAddFoulB: () {},
              onNextPeriod: () {},
              onSpecialTag: (_) {},
              canUndo: true,
              isTimeoutActive: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('+1'), findsWidgets);
      expect(find.text('+2'), findsWidgets);
      expect(find.text('+3'), findsWidgets);
      expect(find.text('-1'), findsWidgets);
      expect(find.text('KWARTA 1'), findsOneWidget);
      expect(find.text('FAULE: 0'), findsWidgets);
      expect(find.text('🏀 ZA 3 PKT'), findsOneWidget);
    });

    testWidgets('PhoneBScorerScreen renders live HUD, scoreboard, video settings button and court', (tester) async {
      await tester.pumpWidget(buildTestHarness(const PhoneBScorerScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('START LIVE'), findsOneWidget);
      expect(find.text('START REC'), findsOneWidget);
      expect(find.text('SCORER'), findsOneWidget);
      expect(find.text('WIDEO REC'), findsOneWidget);
      expect(find.text('TABLICA'), findsOneWidget);
    });
  });
}
