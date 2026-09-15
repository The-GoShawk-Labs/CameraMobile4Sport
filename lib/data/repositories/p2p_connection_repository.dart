import 'dart:async';
import 'dart:typed_data';
import 'package:volleylive/data/models/p2p_message.dart';
import 'package:volleylive/data/services/webrtc_transport_service.dart';
import 'package:volleylive/domain/models/connection_state.dart';

abstract class IP2PConnectionRepository {
  Stream<CameraConnectionState> get connectionStateStream;
  Stream<StreamHealthMetrics> get healthMetricsStream;
  Stream<P2PMessage> get incomingMessagesStream;
  Stream<Uint8List> get incomingVideoFrames;
  CameraConnectionState get currentState;
  String? get hostAddress;
  int get clientCount;
  Stream<int> get clientCountStream;

  Future<void> hostMatchSession({required String pairingCode, required String role, int port = 8080});
  Future<void> joinMatchSession({required String hostAddress, required String pairingCode, required String role, int port = 8080});
  Future<void> sendScoreUpdate(ScoreUpdatePayload scorePayload, {required String role});
  Future<void> sendCameraControl(CameraControlPayload cameraPayload, {required String role});
  Future<void> sendRecorderControl({required bool isRecording, required String role, String? matchId});
  void sendVideoFrame(Uint8List frameBytes);
  Future<void> sendCustomCommand(P2PMessage message);
  Future<void> disconnect();
}

class P2PConnectionRepository implements IP2PConnectionRepository {
  final IWebRtcTransportService _transportService;

  P2PConnectionRepository({IWebRtcTransportService? transportService})
      : _transportService = transportService ?? WebRtcTransportService();

  @override
  Stream<CameraConnectionState> get connectionStateStream => _transportService.connectionStateStream;

  @override
  Stream<StreamHealthMetrics> get healthMetricsStream => _transportService.healthMetricsStream;

  @override
  Stream<P2PMessage> get incomingMessagesStream => _transportService.dataChannelMessages;

  @override
  Stream<Uint8List> get incomingVideoFrames => _transportService.incomingVideoFrames;

  @override
  CameraConnectionState get currentState => _transportService.currentState;

  @override
  String? get hostAddress => _transportService.hostAddress;

  @override
  int get clientCount => _transportService.clientCount;

  @override
  Stream<int> get clientCountStream => _transportService.clientCountStream;

  @override
  void sendVideoFrame(Uint8List frameBytes) {
    _transportService.sendVideoFrame(frameBytes);
  }

  @override
  Future<void> hostMatchSession({required String pairingCode, required String role, int port = 8080}) async {
    await _transportService.initializeAsHost(pairingCode: pairingCode, myRole: role, port: port);
  }

  @override
  Future<void> joinMatchSession({
    required String hostAddress,
    required String pairingCode,
    required String role,
    int port = 8080,
  }) async {
    await _transportService.initializeAsClient(
      hostAddress: hostAddress,
      pairingCode: pairingCode,
      myRole: role,
      port: port,
    );
  }

  @override
  Future<void> sendScoreUpdate(ScoreUpdatePayload scorePayload, {required String role}) async {
    final msg = P2PMessage.scoreUpdate(senderRole: role, scorePayload: scorePayload);
    await _transportService.sendDataMessage(msg);
  }

  @override
  Future<void> sendCameraControl(CameraControlPayload cameraPayload, {required String role}) async {
    final msg = P2PMessage.cameraControl(senderRole: role, cameraPayload: cameraPayload);
    await _transportService.sendDataMessage(msg);
  }

  @override
  Future<void> sendRecorderControl({
    required bool isRecording,
    required String role,
    String? matchId,
  }) async {
    final msg = P2PMessage.recorderControl(
      senderRole: role,
      isRecording: isRecording,
      matchId: matchId,
    );
    await _transportService.sendDataMessage(msg);
  }

  @override
  Future<void> sendCustomCommand(P2PMessage message) async {
    await _transportService.sendDataMessage(message);
  }

  @override
  Future<void> disconnect() async {
    await _transportService.close();
  }
}
