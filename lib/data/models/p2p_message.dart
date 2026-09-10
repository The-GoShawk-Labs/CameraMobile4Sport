import 'dart:convert';

/// Typy komunikatów protokołu P2P
enum P2PMessageType {
  scoreUpdate,
  cameraControl,
  recorderControl,
  heartbeat,
  heartbeatAck,
  syncState,
  sdpOffer,
  sdpAnswer,
  iceCandidate,
  customCommand;

  String toJson() => name;

  static P2PMessageType fromJson(String value) {
    return P2PMessageType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => P2PMessageType.customCommand,
    );
  }
}

/// Niezmienny uniwersalny model komunikatu P2P
class P2PMessage {
  final String id;
  final P2PMessageType type;
  final String senderRole; // 'phone_a_camera' | 'phone_b_controller' | 'statistician'
  final int timestamp;
  final Map<String, dynamic> payload;

  const P2PMessage({
    required this.id,
    required this.type,
    required this.senderRole,
    required this.timestamp,
    required this.payload,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.toJson(),
      'senderRole': senderRole,
      'timestamp': timestamp,
      'payload': payload,
    };
  }

  factory P2PMessage.fromMap(Map<String, dynamic> map) {
    return P2PMessage(
      id: map['id'] as String? ?? '',
      type: P2PMessageType.fromJson(map['type'] as String? ?? ''),
      senderRole: map['senderRole'] as String? ?? 'unknown',
      timestamp: map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory P2PMessage.fromJson(String source) =>
      P2PMessage.fromMap(jsonDecode(source) as Map<String, dynamic>);

  // Fabryki ułatwiające tworzenie konkretnych komunikatów

  factory P2PMessage.scoreUpdate({
    required String senderRole,
    required ScoreUpdatePayload scorePayload,
  }) {
    return P2PMessage(
      id: 'score_${DateTime.now().millisecondsSinceEpoch}',
      type: P2PMessageType.scoreUpdate,
      senderRole: senderRole,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: scorePayload.toMap(),
    );
  }

  factory P2PMessage.cameraControl({
    required String senderRole,
    required CameraControlPayload cameraPayload,
  }) {
    return P2PMessage(
      id: 'cam_${DateTime.now().millisecondsSinceEpoch}',
      type: P2PMessageType.cameraControl,
      senderRole: senderRole,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: cameraPayload.toMap(),
    );
  }

  factory P2PMessage.recorderControl({
    required String senderRole,
    required bool isRecording,
    String? matchId,
  }) {
    return P2PMessage(
      id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
      type: P2PMessageType.recorderControl,
      senderRole: senderRole,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'isRecording': isRecording,
        'matchId': matchId,
      },
    );
  }

  factory P2PMessage.heartbeat({
    required String senderRole,
    int? batteryLevel,
    String? thermalState,
  }) {
    return P2PMessage(
      id: 'hb_${DateTime.now().millisecondsSinceEpoch}',
      type: P2PMessageType.heartbeat,
      senderRole: senderRole,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'clientTimestamp': DateTime.now().millisecondsSinceEpoch,
        'batteryLevel': batteryLevel,
        'thermalState': thermalState,
      },
    );
  }

  factory P2PMessage.sdpOffer({
    required String senderRole,
    required String sdp,
  }) {
    return P2PMessage(
      id: 'sdp_offer_${DateTime.now().millisecondsSinceEpoch}',
      type: P2PMessageType.sdpOffer,
      senderRole: senderRole,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: {'sdp': sdp, 'type': 'offer'},
    );
  }

  factory P2PMessage.sdpAnswer({
    required String senderRole,
    required String sdp,
  }) {
    return P2PMessage(
      id: 'sdp_answer_${DateTime.now().millisecondsSinceEpoch}',
      type: P2PMessageType.sdpAnswer,
      senderRole: senderRole,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: {'sdp': sdp, 'type': 'answer'},
    );
  }

  factory P2PMessage.iceCandidate({
    required String senderRole,
    required String candidate,
    required String? sdpMid,
    required int? sdpMLineIndex,
  }) {
    return P2PMessage(
      id: 'ice_${DateTime.now().millisecondsSinceEpoch}',
      type: P2PMessageType.iceCandidate,
      senderRole: senderRole,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      },
    );
  }
}

/// DTO ładunku stanu wyniku meczu
class ScoreUpdatePayload {
  final int pointsA;
  final int pointsB;
  final int setsA;
  final int setsB;
  final String teamA;
  final String teamB;
  final String servingTeam; // 'A' | 'B'
  final int setNumber;
  final int timeoutsA;
  final int timeoutsB;
  final bool isMatchFinished;

  const ScoreUpdatePayload({
    required this.pointsA,
    required this.pointsB,
    required this.setsA,
    required this.setsB,
    required this.teamA,
    required this.teamB,
    required this.servingTeam,
    required this.setNumber,
    this.timeoutsA = 0,
    this.timeoutsB = 0,
    this.isMatchFinished = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'pointsA': pointsA,
      'pointsB': pointsB,
      'setsA': setsA,
      'setsB': setsB,
      'teamA': teamA,
      'teamB': teamB,
      'servingTeam': servingTeam,
      'setNumber': setNumber,
      'timeoutsA': timeoutsA,
      'timeoutsB': timeoutsB,
      'isMatchFinished': isMatchFinished,
    };
  }

  factory ScoreUpdatePayload.fromMap(Map<String, dynamic> map) {
    return ScoreUpdatePayload(
      pointsA: map['pointsA'] as int? ?? 0,
      pointsB: map['pointsB'] as int? ?? 0,
      setsA: map['setsA'] as int? ?? 0,
      setsB: map['setsB'] as int? ?? 0,
      teamA: map['teamA'] as String? ?? 'DRUŻYNA A',
      teamB: map['teamB'] as String? ?? 'DRUŻYNA B',
      servingTeam: map['servingTeam'] as String? ?? 'A',
      setNumber: map['setNumber'] as int? ?? 1,
      timeoutsA: map['timeoutsA'] as int? ?? 0,
      timeoutsB: map['timeoutsB'] as int? ?? 0,
      isMatchFinished: map['isMatchFinished'] as bool? ?? false,
    );
  }
}

/// DTO ładunku sterowania kamerą
class CameraControlPayload {
  final double? zoomLevel;
  final bool? flashOn;
  final bool? lockAeAf;
  final double? exposureCompensation;
  final String? resolution; // '1080p' | '720p' | '4k'
  final int? fps; // 30 | 60

  const CameraControlPayload({
    this.zoomLevel,
    this.flashOn,
    this.lockAeAf,
    this.exposureCompensation,
    this.resolution,
    this.fps,
  });

  Map<String, dynamic> toMap() {
    return {
      if (zoomLevel != null) 'zoomLevel': zoomLevel,
      if (flashOn != null) 'flashOn': flashOn,
      if (lockAeAf != null) 'lockAeAf': lockAeAf,
      if (exposureCompensation != null) 'exposureCompensation': exposureCompensation,
      if (resolution != null) 'resolution': resolution,
      if (fps != null) 'fps': fps,
    };
  }

  factory CameraControlPayload.fromMap(Map<String, dynamic> map) {
    return CameraControlPayload(
      zoomLevel: (map['zoomLevel'] as num?)?.toDouble(),
      flashOn: map['flashOn'] as bool?,
      lockAeAf: map['lockAeAf'] as bool?,
      exposureCompensation: (map['exposureCompensation'] as num?)?.toDouble(),
      resolution: map['resolution'] as String?,
      fps: map['fps'] as int?,
    );
  }
}
