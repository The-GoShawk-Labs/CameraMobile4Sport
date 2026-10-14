import 'dart:async';
import 'dart:typed_data';
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
  int _clientCount = 0;

  Uint8List? _currentVideoFrame;
  DateTime? _lastVideoFrameAt;
  bool _isCameraConnected = false;
  bool _isCameraStreaming = false;
  String _remoteDeviceName = 'Realme';
  DateTime? _streamStartedAt;
  String? _streamStatusError;
  bool _hasStreamTimeout = false;

  ScoreUpdatePayload? _lastReceivedScore;
  CameraControlPayload? _lastReceivedCameraControl;
  bool? _lastReceivedRecorderTrigger;

  StreamSubscription? _stateSub;
  StreamSubscription? _healthSub;
  StreamSubscription? _msgSub;
  StreamSubscription? _videoSub;
  StreamSubscription? _clientCountSub;

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
  String get pairingUri => PairingSchemeHelper.buildUri(
    host: _hostAddress,
    port: _serverPort,
    code: _pairingCode,
  );
  bool get isHost => _isHost;
  int get clientCount => _clientCount;
  Uint8List? get currentVideoFrame => _currentVideoFrame;
  bool get isCameraConnected => _isCameraConnected;
  bool get isCameraStreaming => _isCameraStreaming;
  String get remoteDeviceName => _remoteDeviceName;
  DateTime? get streamStartedAt => _streamStartedAt;
  String? get streamStatusError => _streamStatusError;
  bool get hasStreamTimeout => _hasStreamTimeout;
  bool get hasFreshVideoFrame =>
      _currentVideoFrame != null &&
      _lastVideoFrameAt != null &&
      DateTime.now().difference(_lastVideoFrameAt!) <=
          const Duration(seconds: 2);
  Stream<Uint8List> get incomingVideoFrames => _repository.incomingVideoFrames;
  bool get hasActiveVideoStream =>
      _currentVideoFrame != null &&
      _connectionState == CameraConnectionState.connected;
  ScoreUpdatePayload? get lastReceivedScore => _lastReceivedScore;
  CameraControlPayload? get lastReceivedCameraControl =>
      _lastReceivedCameraControl;
  bool? get lastReceivedRecorderTrigger => _lastReceivedRecorderTrigger;
  bool get isSinglePhoneMode => _currentRole == DeviceRole.singlePhoneAllInOne;

  void selectRole(DeviceRole role) {
    _currentRole = role;
    notifyListeners();
  }

  void setRemoteDeviceName(String name) {
    _remoteDeviceName = name;
    notifyListeners();
  }

  void _initListeners() {
    _stateSub = _repository.connectionStateStream.listen((state) {
      _connectionState = state;
      if (state != CameraConnectionState.connected) {
        _currentVideoFrame = null;
        _lastVideoFrameAt = null;
        _isCameraConnected = false;
        _isCameraStreaming = false;
      }
      notifyListeners();
    });

    _healthSub = _repository.healthMetricsStream.listen((metrics) {
      _healthMetrics = metrics;
      notifyListeners();
    });

    _msgSub = _repository.incomingMessagesStream.listen((msg) {
      _handleIncomingMessage(msg);
    });

    _videoSub = _repository.incomingVideoFrames.listen((frame) {
      _currentVideoFrame = frame;
      _lastVideoFrameAt = DateTime.now();
      _isCameraConnected = true;
      _isCameraStreaming = true;
      _hasStreamTimeout = false;
      _streamStatusError = null;
      notifyListeners();
    });

    _clientCountSub = _repository.clientCountStream.listen((count) {
      _clientCount = count;
      notifyListeners();
    });
  }

  void _handleIncomingMessage(P2PMessage msg) {
    switch (msg.type) {
      case P2PMessageType.syncState:
        final status = msg.payload['status'] as String? ?? '';
        if (status == 'connected' || status == 'ready' || status == 'streaming') {
          _isCameraConnected = true;
          if (status == 'streaming') _isCameraStreaming = true;
          final dev = msg.payload['deviceName'] as String?;
          if (dev != null && dev.isNotEmpty) _remoteDeviceName = dev;
          debugPrint('[P2P Handshake] syncState acknowledged from ${msg.senderRole} (device: $_remoteDeviceName, status: $status)');
          notifyListeners();
        }
        break;
      case P2PMessageType.cameraConnected:
        _isCameraConnected = true;
        final dev = msg.payload['deviceName'] as String?;
        if (dev != null && dev.isNotEmpty) _remoteDeviceName = dev;
        debugPrint('[P2P Handshake] cameraConnected received from ${msg.senderRole} (device: $_remoteDeviceName)');
        notifyListeners();
        break;
      case P2PMessageType.streamStarted:
        _isCameraConnected = true;
        _isCameraStreaming = true;
        _streamStartedAt = DateTime.now();
        _hasStreamTimeout = false;
        _streamStatusError = null;
        final dev = msg.payload['deviceName'] as String?;
        if (dev != null && dev.isNotEmpty) _remoteDeviceName = dev;
        debugPrint('[P2P Handshake] streamStarted acknowledged from $_remoteDeviceName (${msg.payload['width']}x${msg.payload['height']} @ ${msg.payload['fps']}fps)');
        notifyListeners();
        break;
      case P2PMessageType.streamStopped:
        _isCameraStreaming = false;
        debugPrint('[P2P Handshake] streamStopped from $_remoteDeviceName: ${msg.payload['reason']}');
        notifyListeners();
        break;
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

  /// Hostowanie sesji (np. Phone A jako kamera nadająca lub Phone B)
  Future<void> hostSession({
    required String pairingCode,
    DeviceRole role = DeviceRole.scorerPhoneB,
    int port = 8080,
  }) async {
    _pairingCode = pairingCode;
    _serverPort = port;
    _isHost = true;
    _currentRole = role;
    await _repository.hostMatchSession(
      pairingCode: pairingCode,
      role: _currentRole.idName,
      port: port,
    );
    _hostAddress = _repository.hostAddress ?? '127.0.0.1';
    notifyListeners();
  }

  /// Dołączanie do hosta (np. Phone B łączy się z kamerą Phone A lub odwrotnie)
  Future<void> joinSession({
    required String hostAddress,
    required String pairingCode,
    DeviceRole role = DeviceRole.cameraPhoneA,
    int port = 8080,
  }) async {
    _hostAddress = hostAddress;
    _pairingCode = pairingCode;
    _serverPort = port;
    _isHost = false;
    _currentRole = role;
    await _repository.joinMatchSession(
      hostAddress: hostAddress,
      pairingCode: pairingCode,
      role: _currentRole.idName,
      port: port,
    );
    notifyListeners();
  }

  /// Dołączanie na podstawie sparsowanych danych kodu QR
  Future<void> joinWithPairingData(
    PairingData data, {
    DeviceRole role = DeviceRole.cameraPhoneA,
  }) {
    return joinSession(
      hostAddress: data.host,
      pairingCode: data.code,
      role: role,
      port: data.port,
    );
  }

  /// Rozsyłanie klatki wideo na żywo (z Phone A)
  void broadcastVideoFrame(Uint8List frameBytes) {
    _repository.sendVideoFrame(frameBytes);
  }

  /// Wysłanie aktualizacji wyniku do sparowanego telefonu
  Future<void> broadcastScore(ScoreUpdatePayload scorePayload) async {
    await _repository.sendScoreUpdate(scorePayload, role: _currentRole.idName);
  }

  /// Wysłanie polecenia zmiany parametrów kamery do Phone A
  Future<void> sendCameraCommand(CameraControlPayload cameraPayload) async {
    await _repository.sendCameraControl(
      cameraPayload,
      role: _currentRole.idName,
    );
  }

  /// Wysłanie polecenia start/stop nagrywania Master REC do Phone A
  Future<void> sendRecorderTrigger({
    required bool isRecording,
    String? matchId,
  }) async {
    await _repository.sendRecorderControl(
      isRecording: isRecording,
      role: _currentRole.idName,
      matchId: matchId,
    );
  }

  /// Wysłanie żądania synchronizacji stanu sesji (lub odświeżenia połączenia)
  Future<void> sendSyncState([Map<String, dynamic>? statePayload]) async {
    final msg = P2PMessage.syncState(
      senderRole: _currentRole.idName,
      state: statePayload ?? {'timestamp': DateTime.now().millisecondsSinceEpoch},
    );
    await _repository.sendCustomCommand(msg);
  }

  /// Wysłanie powiadomienia o połączeniu kamery (handshake z Phone A do Phone B)
  Future<void> notifyCameraConnected({
    required String deviceName,
    Map<String, dynamic>? metadata,
  }) async {
    _isCameraConnected = true;
    _remoteDeviceName = deviceName;
    final msg = P2PMessage.cameraConnected(
      senderRole: _currentRole.idName,
      deviceName: deviceName,
      metadata: metadata,
    );
    await _repository.sendCustomCommand(msg);
    notifyListeners();
  }

  /// Wysłanie powiadomienia o rozpoczęciu publikowania strumienia wideo (Phone A -> Phone B)
  Future<void> notifyStreamStarted({
    required String deviceName,
    int? width,
    int? height,
    int? fps,
  }) async {
    _isCameraConnected = true;
    _isCameraStreaming = true;
    _streamStartedAt = DateTime.now();
    _remoteDeviceName = deviceName;
    _hasStreamTimeout = false;
    _streamStatusError = null;
    final msg = P2PMessage.streamStarted(
      senderRole: _currentRole.idName,
      deviceName: deviceName,
      width: width,
      height: height,
      fps: fps,
    );
    await _repository.sendCustomCommand(msg);
    notifyListeners();
  }

  /// Wysłanie powiadomienia o zatrzymaniu strumienia
  Future<void> notifyStreamStopped({String? reason}) async {
    _isCameraStreaming = false;
    final msg = P2PMessage.streamStopped(
      senderRole: _currentRole.idName,
      reason: reason,
    );
    await _repository.sendCustomCommand(msg);
    notifyListeners();
  }

  /// Oznacza timeout oczekiwania na strumień z kamery
  void setStreamTimeout(bool timedOut, [String? errorMessage]) {
    _hasStreamTimeout = timedOut;
    _streamStatusError = errorMessage;
    notifyListeners();
  }

  /// Resetuje flagę timeoutu
  void clearStreamTimeout() {
    _hasStreamTimeout = false;
    _streamStatusError = null;
    notifyListeners();
  }

  @visibleForTesting
  void setConnectionStateForTesting(CameraConnectionState state) {
    _connectionState = state;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _repository.disconnect();
    _isHost = false;
    _currentVideoFrame = null;
    _lastVideoFrameAt = null;
    _isCameraConnected = false;
    _isCameraStreaming = false;
    _hasStreamTimeout = false;
    _streamStatusError = null;
    _clientCount = 0;
    _connectionState = CameraConnectionState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _healthSub?.cancel();
    _msgSub?.cancel();
    _videoSub?.cancel();
    _clientCountSub?.cancel();
    _repository.disconnect();
    super.dispose();
  }
}
