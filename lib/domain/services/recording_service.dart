import 'dart:async';
import 'package:volleylive/domain/models/connection_state.dart';

abstract class IRecordingService {
  Stream<RecordingState> get recordingStateStream;
  Stream<Duration> get durationStream;
  RecordingState get currentState;
  Duration get recordedDuration;

  Future<void> startMasterRecording();
  Future<void> stopRecording({bool simulatedDelay = false});
}

/// Serwis nagrywania wideo
class RecordingService implements IRecordingService {
  final _stateController = StreamController<RecordingState>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  RecordingState _currentState = RecordingState.idle;
  Duration _duration = Duration.zero;
  Timer? _timer;

  @override
  Stream<RecordingState> get recordingStateStream => _stateController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  RecordingState get currentState => _currentState;

  @override
  Duration get recordedDuration => _duration;

  @override
  Future<void> startMasterRecording() async {
    if (_currentState == RecordingState.recording) return;

    _currentState = RecordingState.recording;
    _stateController.add(_currentState);
    _duration = Duration.zero;

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _duration += const Duration(seconds: 1);
      _durationController.add(_duration);
    });
  }

  @override
  Future<void> stopRecording({bool simulatedDelay = false}) async {
    _timer?.cancel();
    _timer = null;
    if (_currentState != RecordingState.recording) return;

    _currentState = RecordingState.stopping;
    _stateController.add(_currentState);

    if (simulatedDelay) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _currentState = RecordingState.saved;
    _stateController.add(_currentState);
  }

  void dispose() {
    _timer?.cancel();
    _stateController.close();
    _durationController.close();
  }
}
