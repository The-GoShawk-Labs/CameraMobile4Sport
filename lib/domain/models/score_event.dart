import 'package:volleylive/domain/models/match_session.dart';

enum ScoreEventType {
  pointAddedA,
  pointAddedB,
  pointSubtractedA,
  pointSubtractedB,
  timeoutA,
  timeoutB,
  rotationChanged,
  setFinalized,
  serverChanged,
  foulA,
  foulB,
  periodChanged,
}

/// Niezmienne zdarzenie scoringowe do obsługi historii i operacji UNDO.
class ScoreEvent {
  final String id;
  final DateTime timestamp;
  final ScoreEventType type;
  final int setNumber;
  final int prevPointsA;
  final int prevPointsB;
  final int prevSetsA;
  final int prevSetsB;
  final ServingTeam prevServer;
  final int prevTimeoutsA;
  final int prevTimeoutsB;
  final int prevFoulsA;
  final int prevFoulsB;
  final List<MatchSet> prevSetsHistory;
  final String sourceDevice; // 'PHONE_B' (jedyna instancja z prawem do modyfikacji)

  const ScoreEvent({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.setNumber,
    required this.prevPointsA,
    required this.prevPointsB,
    required this.prevSetsA,
    required this.prevSetsB,
    required this.prevServer,
    required this.prevTimeoutsA,
    required this.prevTimeoutsB,
    this.prevFoulsA = 0,
    this.prevFoulsB = 0,
    required this.prevSetsHistory,
    this.sourceDevice = 'PHONE_B',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'type': type.name,
    'setNumber': setNumber,
    'prevPointsA': prevPointsA,
    'prevPointsB': prevPointsB,
    'prevSetsA': prevSetsA,
    'prevSetsB': prevSetsB,
    'prevServer': prevServer.name,
    'prevTimeoutsA': prevTimeoutsA,
    'prevTimeoutsB': prevTimeoutsB,
    'prevFoulsA': prevFoulsA,
    'prevFoulsB': prevFoulsB,
    'prevSetsHistory': prevSetsHistory.map((s) => s.toJson()).toList(),
    'sourceDevice': sourceDevice,
  };
}
