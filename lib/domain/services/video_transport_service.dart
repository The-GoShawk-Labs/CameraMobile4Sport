import 'dart:async';
import 'package:volleylive/domain/models/connection_state.dart';

abstract class IVideoTransportService {
  Stream<CameraConnectionState> get connectionStateStream;
  Stream<StreamHealthMetrics> get healthMetricsStream;
  CameraConnectionState get currentState;
  
  Future<void> startHostSignaling(String pairingCode);
  Future<void> connectToHost(String pairingCode);
  Future<void> disconnect();
  void sendHeartbeat();
}

/// Implementacja transportu wideo WebRTC P2P / Sieci Lokalnej
class VideoTransportService implements IVideoTransportService {
  final _stateController = StreamController<CameraConnectionState>.broadcast();
  final _healthController = StreamController<StreamHealthMetrics>.broadcast();

  CameraConnectionState _currentState = CameraConnectionState.disconnected;
  Timer? _heartbeatTimer;
  int _simulatedLatencyMs = 35;
  final int _droppedFrames = 0;

  @override
  Stream<CameraConnectionState> get connectionStateStream => _stateController.stream;

  @override
  Stream<StreamHealthMetrics> get healthMetricsStream => _healthController.stream;

  @override
  CameraConnectionState get currentState => _currentState;

  @override
  Future<void> startHostSignaling(String pairingCode) async {
    _setState(CameraConnectionState.pairing);
    // Symulacja nasłuchu P2P w sieci lokalnej
  }

  @override
  Future<void> connectToHost(String pairingCode) async {
    _setState(CameraConnectionState.connecting);
    await Future.delayed(const Duration(milliseconds: 600));
    _setState(CameraConnectionState.connected);
    _startMetricsEmitting();
  }

  @override
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _setState(CameraConnectionState.disconnected);
  }

  @override
  void sendHeartbeat() {
    _simulatedLatencyMs = 28 + (DateTime.now().millisecond % 15);
  }

  void simulateConnectionDrop() {
    _setState(CameraConnectionState.reconnecting);
    // Automatyczna próba wznowienia po 3 sekundach
    Future.delayed(const Duration(seconds: 3), () {
      if (_currentState == CameraConnectionState.reconnecting) {
        _setState(CameraConnectionState.connected);
      }
    });
  }

  void _setState(CameraConnectionState state) {
    _currentState = state;
    _stateController.add(state);
  }

  void _startMetricsEmitting() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentState == CameraConnectionState.connected) {
        _healthController.add(
          StreamHealthMetrics(
            fps: 60,
            bitrateMbps: 8.2 + (DateTime.now().millisecond % 50) / 100,
            latencyMs: _simulatedLatencyMs,
            droppedFrames: _droppedFrames,
            networkQuality: _simulatedLatencyMs < 60 ? 'Doskonała' : 'Niestabilna',
            isAudioActive: true,
          ),
        );
      }
    });
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _stateController.close();
    _healthController.close();
  }
}
