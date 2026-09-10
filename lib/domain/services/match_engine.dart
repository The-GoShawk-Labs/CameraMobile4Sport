import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/score_event.dart';
import 'package:uuid/uuid.dart';

/// Silnik reguł siatkarskich i zarządzania stanem meczu.
/// Spełnia wymagania:
/// - Sety do 25 punktów z przewagą min. 2 punktów
/// - Tie-break (5. set) do 15 punktów z przewagą min. 2 punktów
/// - Zliczanie setów (mecz wygrany po 3 wygranych setach)
/// - Deterministryczny mechanizm UNDO z pełną historią ScoreEvent
/// - Przełączanie prawa do zagrywki (Serve indicator)
class MatchEngine {
  static const _uuid = Uuid();
  final List<ScoreEvent> _history = [];

  List<ScoreEvent> get history => List.unmodifiable(_history);

  /// Tworzy nową instancję sesji meczowej z czyszczeniem historii
  MatchSession createNewMatch({
    required MatchSport sport,
    required String teamA,
    required String teamB,
    String? tournamentName,
    String? pairingCode,
  }) {
    _history.clear();
    return MatchSession(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      pairingCode: pairingCode ?? _uuid.v4().substring(0, 6).toUpperCase(),
      sport: sport,
      teamA: teamA,
      teamB: teamB,
      tournamentName: tournamentName,
    );
  }

  /// Dodaje punkty dla Drużyny A (domyślnie 1, dla koszykówki np. 2 lub 3)
  MatchSession addPointA(MatchSession current, {int points = 1}) {
    if (current.isMatchOver) return current;

    _recordHistory(current, ScoreEventType.pointAddedA);

    final newPointsA = current.currentSetPointsA + points;
    final updatedSession = current.copyWith(
      currentSetPointsA: newPointsA,
      currentServer: ServingTeam.teamA,
    );

    if (current.sport == MatchSport.volleyball || current.sport == MatchSport.beachVolleyball) {
      return _checkVolleyballSetCompletion(updatedSession);
    }
    return updatedSession;
  }

  /// Dodaje punkty dla Drużyny B (domyślnie 1, dla koszykówki np. 2 lub 3)
  MatchSession addPointB(MatchSession current, {int points = 1}) {
    if (current.isMatchOver) return current;

    _recordHistory(current, ScoreEventType.pointAddedB);

    final newPointsB = current.currentSetPointsB + points;
    final updatedSession = current.copyWith(
      currentSetPointsB: newPointsB,
      currentServer: ServingTeam.teamB,
    );

    if (current.sport == MatchSport.volleyball || current.sport == MatchSport.beachVolleyball) {
      return _checkVolleyballSetCompletion(updatedSession);
    }
    return updatedSession;
  }

  /// Odejmuje punkty Drużynie A (korekta ręczna)
  MatchSession subtractPointA(MatchSession current, {int points = 1}) {
    if (current.currentSetPointsA <= 0 || current.isMatchOver) return current;

    _recordHistory(current, ScoreEventType.pointSubtractedA);

    final newPoints = (current.currentSetPointsA - points).clamp(0, 999);
    return current.copyWith(
      currentSetPointsA: newPoints,
    );
  }

  /// Odejmuje punkty Drużynie B (korekta ręczna)
  MatchSession subtractPointB(MatchSession current, {int points = 1}) {
    if (current.currentSetPointsB <= 0 || current.isMatchOver) return current;

    _recordHistory(current, ScoreEventType.pointSubtractedB);

    final newPoints = (current.currentSetPointsB - points).clamp(0, 999);
    return current.copyWith(
      currentSetPointsB: newPoints,
    );
  }

  /// Dodaje faul drużynie A
  MatchSession addFoulA(MatchSession current) {
    _recordHistory(current, ScoreEventType.foulA);
    return current.copyWith(foulsA: current.foulsA + 1);
  }

  /// Dodaje faul drużynie B
  MatchSession addFoulB(MatchSession current) {
    _recordHistory(current, ScoreEventType.foulB);
    return current.copyWith(foulsB: current.foulsB + 1);
  }

  /// Przejście do następnego okresu (set, kwarta, połowa)
  MatchSession nextPeriod(MatchSession current) {
    _recordHistory(current, ScoreEventType.periodChanged);

    // Zapisujemy obecny wynik części jako wpis historii jeśli to sety
    final newHistory = [
      ...current.setsHistory,
      MatchSet(
        setNumber: current.currentSetNumber,
        scoreA: current.currentSetPointsA,
        scoreB: current.currentSetPointsB,
      ),
    ];

    int newSetsA = current.setsA;
    int newSetsB = current.setsB;

    if (current.sport == MatchSport.volleyball || current.sport == MatchSport.beachVolleyball) {
      if (current.currentSetPointsA > current.currentSetPointsB) {
        newSetsA++;
      } else if (current.currentSetPointsB > current.currentSetPointsA) {
        newSetsB++;
      }
    }

    return current.copyWith(
      currentSetNumber: current.currentSetNumber + 1,
      currentSetPointsA: (current.sport == MatchSport.basketball || current.sport == MatchSport.football)
          ? current.currentSetPointsA // W koszu i nodze wynik jest ciągły
          : 0,
      currentSetPointsB: (current.sport == MatchSport.basketball || current.sport == MatchSport.football)
          ? current.currentSetPointsB
          : 0,
      setsA: newSetsA,
      setsB: newSetsB,
      foulsA: 0,
      foulsB: 0,
      setsHistory: newHistory,
    );
  }

  /// Zmiana rotacji / serwującego / posiadania piłki
  MatchSession toggleServer(MatchSession current) {
    _recordHistory(current, ScoreEventType.serverChanged);
    final nextServer = current.currentServer == ServingTeam.teamA
        ? ServingTeam.teamB
        : ServingTeam.teamA;
    return current.copyWith(currentServer: nextServer);
  }

  /// Przerwa na żądanie (Timeout)
  MatchSession requestTimeoutA(MatchSession current) {
    final maxTimeouts = (current.sport == MatchSport.volleyball || current.sport == MatchSport.beachVolleyball) ? 2 : 5;
    if (current.timeoutsA >= maxTimeouts) return current;
    _recordHistory(current, ScoreEventType.timeoutA);
    return current.copyWith(timeoutsA: current.timeoutsA + 1);
  }

  MatchSession requestTimeoutB(MatchSession current) {
    final maxTimeouts = (current.sport == MatchSport.volleyball || current.sport == MatchSport.beachVolleyball) ? 2 : 5;
    if (current.timeoutsB >= maxTimeouts) return current;
    _recordHistory(current, ScoreEventType.timeoutB);
    return current.copyWith(timeoutsB: current.timeoutsB + 1);
  }

  /// Zmiana zawodnika (Substitutions, max 6 na set w siatkówce)
  MatchSession requestSubstitutionA(MatchSession current) {
    if (current.substitutionsA >= 6) return current;
    return current.copyWith(substitutionsA: current.substitutionsA + 1);
  }

  MatchSession requestSubstitutionB(MatchSession current) {
    if (current.substitutionsB >= 6) return current;
    return current.copyWith(substitutionsB: current.substitutionsB + 1);
  }

  /// UNDO — cofa stan do poprzedniego zdarzenia ze stosu
  MatchSession? undo(MatchSession current) {
    if (_history.isEmpty) return null;

    final lastEvent = _history.removeLast();

    return current.copyWith(
      currentSetPointsA: lastEvent.prevPointsA,
      currentSetPointsB: lastEvent.prevPointsB,
      setsA: lastEvent.prevSetsA,
      setsB: lastEvent.prevSetsB,
      currentSetNumber: lastEvent.setNumber,
      currentServer: lastEvent.prevServer,
      timeoutsA: lastEvent.prevTimeoutsA,
      timeoutsB: lastEvent.prevTimeoutsB,
      foulsA: lastEvent.prevFoulsA,
      foulsB: lastEvent.prevFoulsB,
      setsHistory: lastEvent.prevSetsHistory,
      isMatchOver: false,
      matchWinner: null,
    );
  }

  /// Sprawdza reguły wygrania seta w siatkówce (25 pkt lub 15 pkt w tiebreaku z przewagą 2 pkt)
  MatchSession _checkVolleyballSetCompletion(MatchSession session) {
    final pointsA = session.currentSetPointsA;
    final pointsB = session.currentSetPointsB;
    final isBeach = session.sport == MatchSport.beachVolleyball;
    final isTieBreak = isBeach ? session.currentSetNumber >= 3 : session.currentSetNumber == 5;
    final targetPoints = isBeach ? (isTieBreak ? 15 : 21) : (isTieBreak ? 15 : 25);
    final setsToWin = isBeach ? 2 : 3;

    final bool wonByA = pointsA >= targetPoints && (pointsA - pointsB) >= 2;
    final bool wonByB = pointsB >= targetPoints && (pointsB - pointsA) >= 2;

    if (wonByA || wonByB) {
      final winnerName = wonByA ? session.teamA : session.teamB;
      final completedSet = MatchSet(
        setNumber: session.currentSetNumber,
        scoreA: pointsA,
        scoreB: pointsB,
        winner: winnerName,
      );

      final newSetsA = wonByA ? session.setsA + 1 : session.setsA;
      final newSetsB = wonByB ? session.setsB + 1 : session.setsB;
      final newHistory = [...session.setsHistory, completedSet];

      final bool matchWonA = newSetsA >= setsToWin;
      final bool matchWonB = newSetsB >= setsToWin;

      if (matchWonA || matchWonB) {
        return session.copyWith(
          setsA: newSetsA,
          setsB: newSetsB,
          setsHistory: newHistory,
          isMatchOver: true,
          matchWinner: matchWonA ? session.teamA : session.teamB,
        );
      } else {
        // Nowy set
        return session.copyWith(
          setsA: newSetsA,
          setsB: newSetsB,
          currentSetNumber: session.currentSetNumber + 1,
          currentSetPointsA: 0,
          currentSetPointsB: 0,
          timeoutsA: 0,
          timeoutsB: 0,
          substitutionsA: 0,
          substitutionsB: 0,
          foulsA: 0,
          foulsB: 0,
          setsHistory: newHistory,
        );
      }
    }

    return session;
  }

  void _recordHistory(MatchSession current, ScoreEventType type) {
    _history.add(
      ScoreEvent(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        type: type,
        setNumber: current.currentSetNumber,
        prevPointsA: current.currentSetPointsA,
        prevPointsB: current.currentSetPointsB,
        prevSetsA: current.setsA,
        prevSetsB: current.setsB,
        prevServer: current.currentServer,
        prevTimeoutsA: current.timeoutsA,
        prevTimeoutsB: current.timeoutsB,
        prevFoulsA: current.foulsA,
        prevFoulsB: current.foulsB,
        prevSetsHistory: List.from(current.setsHistory),
      ),
    );
  }

  void clearHistory() {
    _history.clear();
  }
}
