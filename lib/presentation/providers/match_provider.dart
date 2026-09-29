import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:volleylive/data/models/p2p_message.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/score_event.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';
import 'package:volleylive/domain/services/match_engine.dart';
import 'package:volleylive/domain/services/native_stream_burner_bridge.dart';

class MatchProvider extends ChangeNotifier {
  final MatchEngine _engine = MatchEngine();
  static const _uuid = Uuid();

  final _scoreEventsController = StreamController<ScoreEvent>.broadcast();
  Stream<ScoreEvent> get scoreEventsStream => _scoreEventsController.stream;

  final _sessionStreamController = StreamController<MatchSession>.broadcast();
  Stream<MatchSession> get sessionStream => _sessionStreamController.stream;

  late MatchSession _currentSession;
  Timer? _timeoutTimer;
  Timer? _specialEventTimer;
  int _timeoutSecondsRemaining = 0;
  bool _isTimeoutActive = false;
  ServingTeam _timeoutCallingTeam = ServingTeam.none;
  String? _activeSpecialEvent;
  bool _isOutdoorModeEnabled = false;
  bool _isScreenLocked = false;

  MatchProvider() {
    _initDefaultSession();
  }

  MatchSession get session => _currentSession;
  bool get canUndo => _engine.history.isNotEmpty;
  int get historyCount => _engine.history.length;
  List<ScoreEvent> get history => _engine.history;
  bool get isTimeoutActive => _isTimeoutActive;
  int get timeoutSecondsRemaining => _timeoutSecondsRemaining;
  ServingTeam get timeoutCallingTeam => _timeoutCallingTeam;
  String? get activeSpecialEvent => _activeSpecialEvent;
  bool get isOutdoorModeEnabled => _isOutdoorModeEnabled;
  bool get isScreenLocked => _isScreenLocked;

  ScoreUpdatePayload get toScorePayload {
    return ScoreUpdatePayload(
      pointsA: _currentSession.currentSetPointsA,
      pointsB: _currentSession.currentSetPointsB,
      setsA: _currentSession.setsA,
      setsB: _currentSession.setsB,
      teamA: _currentSession.teamA,
      teamB: _currentSession.teamB,
      servingTeam: _currentSession.currentServer == ServingTeam.teamA ? 'A' : (_currentSession.currentServer == ServingTeam.teamB ? 'B' : 'NONE'),
      setNumber: _currentSession.currentSetNumber,
      timeoutsA: _currentSession.timeoutsA,
      timeoutsB: _currentSession.timeoutsB,
      isMatchFinished: _currentSession.isMatchOver,
    );
  }

  void _notifyScoreboardBridge({String? toastOverride}) {
    final toast = toastOverride ?? _activeSpecialEvent ?? '';
    _sessionStreamController.add(_currentSession);
    NativeStreamBurnerBridge().updateScoreboard(
      VolleyballScoreboardState.fromMatchSession(
        _currentSession,
        eventTag: toast,
        toastMessage: toast,
      ),
    );
  }

  void syncFromScorePayload(ScoreUpdatePayload payload) {
    _currentSession = _currentSession.copyWith(
      teamA: payload.teamA,
      teamB: payload.teamB,
      currentSetPointsA: payload.pointsA,
      currentSetPointsB: payload.pointsB,
      setsA: payload.setsA,
      setsB: payload.setsB,
      currentSetNumber: payload.setNumber,
      timeoutsA: payload.timeoutsA,
      timeoutsB: payload.timeoutsB,
      currentServer: payload.servingTeam == 'A'
          ? ServingTeam.teamA
          : (payload.servingTeam == 'B' ? ServingTeam.teamB : ServingTeam.none),
      isMatchOver: payload.isMatchFinished,
    );
    _notifyScoreboardBridge();
    notifyListeners();
  }

  void _initDefaultSession() {
    _currentSession = MatchSession(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      teamA: 'AZS KRAKÓW',
      teamB: 'LEGIA WARSZAWA',
      teamAColor: const Color(0xFF00E5FF),
      teamBColor: const Color(0xFFFFAB00),
      pairingCode: 'VL-8492',
    );
  }

  void toggleOutdoorMode() {
    _isOutdoorModeEnabled = !_isOutdoorModeEnabled;
    notifyListeners();
  }

  void toggleScreenLock() {
    _isScreenLocked = !_isScreenLocked;
    notifyListeners();
  }

  void triggerSpecialEvent(String eventName) {
    _activeSpecialEvent = eventName;
    _notifyScoreboardBridge(toastOverride: eventName);
    notifyListeners();

    _specialEventTimer?.cancel();
    _specialEventTimer = Timer(const Duration(seconds: 4), () {
      _activeSpecialEvent = null;
      _notifyScoreboardBridge();
      notifyListeners();
    });
  }

  void startNewMatch({
    required String teamA,
    required String teamB,
    Color teamAColor = const Color(0xFF00E5FF),
    Color teamBColor = const Color(0xFFFFAB00),
    MatchSport sport = MatchSport.volleyball,
    String? pairingCode,
    String? tournamentName,
  }) {
    _engine.clearHistory();
    _currentSession = MatchSession(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      sport: sport,
      teamA: teamA.trim().isEmpty ? 'DRUŻYNA A' : teamA.trim().toUpperCase(),
      teamB: teamB.trim().isEmpty ? 'DRUŻYNA B' : teamB.trim().toUpperCase(),
      teamAColor: teamAColor,
      teamBColor: teamBColor,
      pairingCode: pairingCode ?? 'VL-${(1000 + DateTime.now().millisecond % 9000)}',
      tournamentName: tournamentName,
    );
    _notifyScoreboardBridge();
    notifyListeners();
  }

  void setSport(MatchSport sport) {
    if (_currentSession.sport != sport) {
      _currentSession = _currentSession.copyWith(sport: sport);
      _notifyScoreboardBridge();
      notifyListeners();
    }
  }

  void updateTeamColors({required Color colorA, required Color colorB}) {
    _currentSession = _currentSession.copyWith(
      teamAColor: colorA,
      teamBColor: colorB,
    );
    _notifyScoreboardBridge();
    notifyListeners();
  }

  void _emitLatestEvent() {
    if (_engine.history.isNotEmpty) {
      _scoreEventsController.add(_engine.history.last);
    }
  }

  void addPointA({String? tag, int points = 1}) {
    _currentSession = _engine.addPointA(_currentSession, points: points);
    _emitLatestEvent();
    if (tag != null) triggerSpecialEvent(tag);
    _notifyScoreboardBridge(toastOverride: tag);
    notifyListeners();
  }

  void addPointB({String? tag, int points = 1}) {
    _currentSession = _engine.addPointB(_currentSession, points: points);
    _emitLatestEvent();
    if (tag != null) triggerSpecialEvent(tag);
    _notifyScoreboardBridge(toastOverride: tag);
    notifyListeners();
  }

  void subtractPointA([int points = 1]) {
    _currentSession = _engine.subtractPointA(_currentSession, points: points);
    _emitLatestEvent();
    _notifyScoreboardBridge();
    notifyListeners();
  }

  void subtractPointB([int points = 1]) {
    _currentSession = _engine.subtractPointB(_currentSession, points: points);
    _emitLatestEvent();
    _notifyScoreboardBridge();
    notifyListeners();
  }

  void addFoulA() {
    _currentSession = _engine.addFoulA(_currentSession);
    _emitLatestEvent();
    final msg = 'FAUL: ${_currentSession.teamA} (Suma: ${_currentSession.foulsA})';
    triggerSpecialEvent(msg);
    _notifyScoreboardBridge(toastOverride: msg);
    notifyListeners();
  }

  void addFoulB() {
    _currentSession = _engine.addFoulB(_currentSession);
    _emitLatestEvent();
    final msg = 'FAUL: ${_currentSession.teamB} (Suma: ${_currentSession.foulsB})';
    triggerSpecialEvent(msg);
    _notifyScoreboardBridge(toastOverride: msg);
    notifyListeners();
  }

  void nextPeriod() {
    _currentSession = _engine.nextPeriod(_currentSession);
    _emitLatestEvent();
    final msg = 'ROZPOCZĘTO: ${_currentSession.periodDisplay}';
    triggerSpecialEvent(msg);
    _notifyScoreboardBridge(toastOverride: msg);
    notifyListeners();
  }

  void requestSubstitutionA() {
    _currentSession = _engine.requestSubstitutionA(_currentSession);
    _emitLatestEvent();
    final msg = 'ZMIANA: ${_currentSession.teamA} (${_currentSession.substitutionsA}/6)';
    triggerSpecialEvent(msg);
    _notifyScoreboardBridge(toastOverride: msg);
    notifyListeners();
  }

  void requestSubstitutionB() {
    _currentSession = _engine.requestSubstitutionB(_currentSession);
    _emitLatestEvent();
    final msg = 'ZMIANA: ${_currentSession.teamB} (${_currentSession.substitutionsB}/6)';
    triggerSpecialEvent(msg);
    _notifyScoreboardBridge(toastOverride: msg);
    notifyListeners();
  }

  void toggleRotation() {
    _currentSession = _engine.toggleServer(_currentSession);
    _emitLatestEvent();
    _notifyScoreboardBridge();
    notifyListeners();
  }

  void undo() {
    final prev = _engine.undo(_currentSession);
    if (prev != null) {
      _currentSession = prev;
      _emitLatestEvent();
      _notifyScoreboardBridge();
      notifyListeners();
    }
  }

  void startTimeout(ServingTeam team) {
    if (_isTimeoutActive) return;

    if (team == ServingTeam.teamA) {
      _currentSession = _engine.requestTimeoutA(_currentSession);
    } else {
      _currentSession = _engine.requestTimeoutB(_currentSession);
    }

    _isTimeoutActive = true;
    _timeoutCallingTeam = team;
    _timeoutSecondsRemaining = 30;
    _notifyScoreboardBridge(toastOverride: 'TIMEOUT');
    notifyListeners();

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeoutSecondsRemaining > 0) {
        _timeoutSecondsRemaining--;
        notifyListeners();
      } else {
        cancelTimeout();
      }
    });
  }

  void cancelTimeout() {
    _timeoutTimer?.cancel();
    _isTimeoutActive = false;
    _timeoutSecondsRemaining = 0;
    _timeoutCallingTeam = ServingTeam.none;
    _notifyScoreboardBridge();
    notifyListeners();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _specialEventTimer?.cancel();
    _scoreEventsController.close();
    _sessionStreamController.close();
    super.dispose();
  }
}
