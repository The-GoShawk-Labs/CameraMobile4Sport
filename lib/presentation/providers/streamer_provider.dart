import 'dart:async';
import 'package:flutter/material.dart';
import 'package:volleylive/core/security/secure_storage_service.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/domain/services/recording_service.dart';
import 'package:volleylive/domain/services/streaming_service.dart';
import 'package:volleylive/domain/services/video_transport_service.dart';

class StreamerProvider extends ChangeNotifier {
  final VideoTransportService _transportService = VideoTransportService();
  final StreamingService _streamingService = StreamingService();
  final RecordingService _recordingService = RecordingService();

  CameraConnectionState _cameraLinkState = CameraConnectionState.disconnected;
  StreamingState _streamingState = StreamingState.idle;
  RecordingState _programRecState = RecordingState.idle;
  StreamHealthMetrics _healthMetrics = const StreamHealthMetrics();

  StreamingDestination _destination = const StreamingDestination();
  ScoreboardThemeStyle _scoreboardStyle = ScoreboardThemeStyle.tvProBroadcast;
  bool _showServeIndicator = true;
  bool _showTimeoutCountdown = true;
  String _maskedStreamKey = 'Brak klucza';

  StreamerProvider() {
    _initListeners();
    _loadSavedCredentials();
  }

  CameraConnectionState get cameraLinkState => _cameraLinkState;
  StreamingState get streamingState => _streamingState;
  RecordingState get programRecState => _programRecState;
  StreamHealthMetrics get healthMetrics => _healthMetrics;
  StreamingDestination get destination => _destination;
  ScoreboardThemeStyle get scoreboardStyle => _scoreboardStyle;
  bool get showServeIndicator => _showServeIndicator;
  bool get showTimeoutCountdown => _showTimeoutCountdown;
  String get maskedStreamKey => _maskedStreamKey;

  void _initListeners() {
    _transportService.connectionStateStream.listen((state) {
      _cameraLinkState = state;
      notifyListeners();
    });

    _transportService.healthMetricsStream.listen((metrics) {
      _healthMetrics = metrics;
      notifyListeners();
    });

    _streamingService.streamingStateStream.listen((state) {
      _streamingState = state;
      notifyListeners();
    });

    _recordingService.recordingStateStream.listen((state) {
      _programRecState = state;
      notifyListeners();
    });
  }

  Future<void> _loadSavedCredentials() async {
    if (_destination.credentialReference.isNotEmpty) {
      _maskedStreamKey = SecureStorageService.maskCredential(_destination.credentialReference);
      notifyListeners();
    }
  }

  Future<void> startHostPairing(String pairingCode) async {
    await _transportService.startHostSignaling(pairingCode);
    // Symulacja połączenia po uścisku dłoni
    await _transportService.connectToHost(pairingCode);
  }

  Future<void> saveStreamKey(String rawStreamKey) async {
    if (rawStreamKey.trim().isEmpty) return;
    final ref = await SecureStorageService.storeCredential(credentialValue: rawStreamKey.trim());
    _destination = _destination.copyWith(credentialReference: ref);
    _maskedStreamKey = SecureStorageService.maskCredential(ref);
    notifyListeners();
  }

  void updateDestination(StreamingDestination destination) {
    _destination = destination;
    notifyListeners();
  }

  void setScoreboardStyle(ScoreboardThemeStyle style) {
    _scoreboardStyle = style;
    notifyListeners();
  }

  void toggleServeIndicator(bool value) {
    _showServeIndicator = value;
    notifyListeners();
  }

  void toggleTimeoutCountdown(bool value) {
    _showTimeoutCountdown = value;
    notifyListeners();
  }

  Future<bool> toggleLiveStream() async {
    if (_streamingState == StreamingState.live || _streamingState == StreamingState.connecting) {
      await _streamingService.stopLiveStream();
      return false;
    } else {
      return await _streamingService.startLiveStream(_destination);
    }
  }

  Future<void> toggleProgramRecording() async {
    if (_programRecState == RecordingState.recording) {
      await _recordingService.stopRecording();
    } else {
      await _recordingService.startMasterRecording();
    }
  }

  void simulateDisconnect() {
    _transportService.simulateConnectionDrop();
  }

  @override
  void dispose() {
    _transportService.dispose();
    _streamingService.dispose();
    _recordingService.dispose();
    super.dispose();
  }
}
