import 'dart:async';
import 'package:flutter/material.dart';
import 'package:volleylive/core/utils/pairing_scheme_helper.dart';
import 'package:volleylive/data/models/p2p_message.dart';
import 'package:volleylive/data/repositories/p2p_connection_repository.dart';
import 'package:volleylive/domain/models/connection_state.dart';

class P2PConnectionProvider extends ChangeNotifier {
  final IP2PConnectionRepository _repository;

  DeviceRole _currentRole = DeviceRole.none;
  CameraConnectionState _connectionState = CameraConnectionState.disconnected;
  StreamHealthMetrics _healthMetrics = const StreamHealthMetrics();

  String _pairingCode = '';
  String _hostAddress = '127.0.0.1';
  int _serverPort = 8080;
  bool _isHost = false;

  ScoreUpdatePayload? _lastReceivedScore;
  CameraControlPayload? _lastReceivedCameraControl;
  bool? _lastReceivedRecorderTrigger;

  StreamSubscription? _stateSub;
  StreamSubscription? _healthSub;
  StreamSubscription? _msgSub;

  P2PConnectionProvider({IP2PConnectionRepository? repository})
      : _repository = repository ?? P2PConnectionRepository() {
    _initListeners();
  }

  DeviceRole get currentRole => _currentRole;
  CameraConnectionState get connectionState => _connectionState;
  StreamHealthMetrics get healthMetrics => _healthMetrics;
  String get pairingCode => _pairingCode;
  String get hostAddress => _hostAddress;
  int get serverPort => _serverPort;
  String get pairingUri => PairingSchemeHelper.buildUri(host: _hostAddress, port: _serverPort, code: _pairingCode);
  bool get isHost => _isHost;
  ScoreUpdatePayload? get lastReceivedScore => _lastReceivedScore;
  CameraControlPayload? get lastReceivedCameraControl => _lastReceivedCameraControl;
  bool? get lastReceivedRecorderTrigger => _lastReceivedRecorderTrigger;
  bool get isSinglePhoneMode => _currentRole == DeviceRole.singlePhoneAllInOne;

  void selectRole(DeviceRole role) {
    _currentRole = role;
    notifyListeners();
  }

  void _initListeners() {
    _stateSub = _repository.connectionStateStream.listen((state) {
      _connectionState = state;
      notifyListeners();
    });

    _healthSub = _repository.healthMetricsStream.listen((metrics) {
      _healthMetrics = metrics;
      notifyListeners();
    });

    _msgSub = _repository.incomingMessagesStream.listen((msg) {
      _handleIncomingMessage(msg);
    });
  }

  void _handleIncomingMessage(P2PMessage msg) {
    switch (msg.type) {
      case P2PMessageType.scoreUpdate:
        _lastReceivedScore = ScoreUpdatePayload.fromMap(msg.payload);
        notifyListeners();
        break;
      case P2PMessageType.cameraControl:
        _lastReceivedCameraControl = CameraControlPayload.fromMap(msg.payload);
        notifyListeners();
        break;
      case P2PMessageType.recorderControl:
        _lastReceivedRecorderTrigger = msg.payload['isRecording'] as bool?;
        notifyListeners();
        break;
      default:
        break;
    }
  }

  /// Hostowanie sesji (np. Phone B / Reżyserka lub Phone A)
  Future<void> hostSession({required String pairingCode, int port = 8080}) async {
    _pairingCode = pairingCode;
    _serverPort = port;
    _isHost = true;
    _currentRole = DeviceRole.scorerPhoneB;
    await _repository.hostMatchSession(pairingCode: pairingCode, role: _currentRole.idName, port: port);
    _hostAddress = _repository.hostAddress ?? '127.0.0.1';
    notifyListeners();
  }

  /// Dołączanie do hosta (np. Phone A kamera podłącza się do Phone B)
  Future<void> joinSession({
    required String hostAddress,
    required String pairingCode,
    int port = 8080,
  }) async {
    _hostAddress = hostAddress;
    _pairingCode = pairingCode;
    _serverPort = port;
    _isHost = false;
    _currentRole = DeviceRole.cameraPhoneA;
    await _repository.joinMatchSession(
      hostAddress: hostAddress,
      pairingCode: pairingCode,
      role: _currentRole.idName,
      port: port,
    );
    notifyListeners();
  }

  /// Dołączanie na podstawie sparsowanych danych kodu QR
  Future<void> joinWithPairingData(PairingData data) {
    return joinSession(
      hostAddress: data.host,
      pairingCode: data.code,
      port: data.port,
    );
  }

  /// Wysłanie aktualizacji wyniku do sparowanego telefonu
  Future<void> broadcastScore(ScoreUpdatePayload scorePayload) async {
    await _repository.sendScoreUpdate(scorePayload, role: _currentRole.idName);
  }

  /// Wysłanie polecenia zmiany parametrów kamery do Phone A
  Future<void> sendCameraCommand(CameraControlPayload cameraPayload) async {
    await _repository.sendCameraControl(cameraPayload, role: _currentRole.idName);
  }

  /// Wysłanie polecenia start/stop nagrywania Master REC do Phone A
  Future<void> sendRecorderTrigger({required bool isRecording, String? matchId}) async {
    await _repository.sendRecorderControl(
      isRecording: isRecording,
      role: _currentRole.idName,
      matchId: matchId,
    );
  }

  Future<void> disconnect() async {
    await _repository.disconnect();
    _isHost = false;
    _connectionState = CameraConnectionState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _healthSub?.cancel();
    _msgSub?.cancel();
    _repository.disconnect();
    super.dispose();
  }
}
