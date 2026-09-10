import 'package:flutter_test/flutter_test.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/services/match_engine.dart';

void main() {
  group('Volleyball Rules Engine & Score Tests', () {
    late MatchEngine engine;
    late MatchSession session;

    setUp(() {
      engine = MatchEngine();
      session = MatchSession(
        id: 'test-session-1',
        createdAt: DateTime(2026, 1, 1),
        teamA: 'AZS KRAKÓW',
        teamB: 'LEGIA WARSZAWA',
        pairingCode: 'VL-8492',
      );
    });

    test('addPointA increments points and sets server to Team A', () {
      final s1 = engine.addPointA(session);
      expect(s1.currentSetPointsA, 1);
      expect(s1.currentSetPointsB, 0);
      expect(s1.currentServer, ServingTeam.teamA);
      expect(engine.history.length, 1);
    });

    test('addPointB increments points and sets server to Team B', () {
      final s1 = engine.addPointB(session);
      expect(s1.currentSetPointsA, 0);
      expect(s1.currentSetPointsB, 1);
      expect(s1.currentServer, ServingTeam.teamB);
      expect(engine.history.length, 1);
    });

    test('Winning a set requires 25 points with a 2-point margin', () {
      var s = session;
      // Symuluj 24:24
      for (int i = 0; i < 24; i++) {
        s = engine.addPointA(s);
        s = engine.addPointB(s);
      }
      expect(s.currentSetPointsA, 24);
      expect(s.currentSetPointsB, 24);
      expect(s.setsA, 0);

      // 25:24 - set nadal trwa
      s = engine.addPointA(s);
      expect(s.currentSetPointsA, 25);
      expect(s.currentSetPointsB, 24);
      expect(s.setsA, 0);

      // 26:24 - Team A wygrywa Set 1!
      s = engine.addPointA(s);
      expect(s.setsA, 1);
      expect(s.currentSetNumber, 2);
      expect(s.currentSetPointsA, 0);
      expect(s.currentSetPointsB, 0);
      expect(s.setsHistory.length, 1);
      expect(s.setsHistory.first.scoreA, 26);
      expect(s.setsHistory.first.scoreB, 24);
    });

    test('Tie-break (Set 5) requires 15 points with 2-point margin', () {
      var s = session.copyWith(
        setsA: 2,
        setsB: 2,
        currentSetNumber: 5,
      );

      // Symuluj 14:14
      for (int i = 0; i < 14; i++) {
        s = engine.addPointA(s);
        s = engine.addPointB(s);
      }
      expect(s.currentSetPointsA, 14);
      expect(s.currentSetPointsB, 14);
      expect(s.isMatchOver, false);

      // 15:14 - trwa dalej
      s = engine.addPointA(s);
      expect(s.isMatchOver, false);

      // 16:14 - Team A wygrywa mecz!
      s = engine.addPointA(s);
      expect(s.setsA, 3);
      expect(s.isMatchOver, true);
      expect(s.matchWinner, 'AZS KRAKÓW');
    });

    test('UNDO accurately rolls back points, sets and servers', () {
      var s = session;
      s = engine.addPointA(s); // 1:0
      s = engine.addPointB(s); // 1:1
      expect(s.currentSetPointsA, 1);
      expect(s.currentSetPointsB, 1);

      // Cofnięcie punktu Team B
      final undo1 = engine.undo(s);
      expect(undo1, isNotNull);
      expect(undo1!.currentSetPointsA, 1);
      expect(undo1.currentSetPointsB, 0);
      expect(undo1.currentServer, ServingTeam.teamA);

      // Cofnięcie punktu Team A
      final undo2 = engine.undo(undo1);
      expect(undo2, isNotNull);
      expect(undo2!.currentSetPointsA, 0);
      expect(undo2.currentSetPointsB, 0);
    });

    test('Timeouts are tracked and maxed out at 2 per set', () {
      var s = session;
      s = engine.requestTimeoutA(s);
      expect(s.timeoutsA, 1);

      s = engine.requestTimeoutA(s);
      expect(s.timeoutsA, 2);

      // 3. timeout odrzucony
      s = engine.requestTimeoutA(s);
      expect(s.timeoutsA, 2);
    });
  });
}
