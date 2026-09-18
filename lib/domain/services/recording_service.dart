import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:volleylive/core/services/video_storage_service.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/recording_result.dart';

abstract class IRecordingService {
  Stream<RecordingState> get recordingStateStream;
  Stream<Duration> get durationStream;
  Stream<MasterRecordingResult> get recordingFinishedStream;

  RecordingState get currentState;
  Duration get recordedDuration;
  MasterRecordingResult? get lastRecordingResult;
  String? get lastErrorMessage;

  Future<void> startMasterRecording({
    CameraController? cameraController,
    bool isSimulation = false,
    String? storageFolder,
    DeviceOrientation? deviceOrientation,
  });

  Future<MasterRecordingResult?> stopRecording({
    CameraController? cameraController,
    bool simulatedDelay = false,
    String? storageFolder,
  });

  void reset();
}

/// Serwis nagrywania wideo Master REC MP4 na Phone A
class RecordingService implements IRecordingService {
  final VideoStorageService _storageService;

  final _stateController = StreamController<RecordingState>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _finishedController = StreamController<MasterRecordingResult>.broadcast();

  RecordingState _currentState = RecordingState.idle;
  Duration _duration = Duration.zero;
  Timer? _timer;
  MasterRecordingResult? _lastRecordingResult;
  String? _lastErrorMessage;
  bool _isCurrentSessionSimulated = false;
  String? _activeStorageFolder;
  RecordedVideoOrientation _activeOrientation = RecordedVideoOrientation.landscape;

  RecordingService({VideoStorageService? storageService})
      : _storageService = storageService ?? VideoStorageService();

  @override
  Stream<RecordingState> get recordingStateStream => _stateController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<MasterRecordingResult> get recordingFinishedStream => _finishedController.stream;

  @override
  RecordingState get currentState => _currentState;

  @override
  Duration get recordedDuration => _duration;

  @override
  MasterRecordingResult? get lastRecordingResult => _lastRecordingResult;

  VideoStorageService get storageService => _storageService;

  void updateLastRecordingResult(MasterRecordingResult result) {
    _lastRecordingResult = result;
    _finishedController.add(result);
  }

  @override
  String? get lastErrorMessage => _lastErrorMessage;

  @override
  Future<void> startMasterRecording({
    CameraController? cameraController,
    bool isSimulation = false,
    String? storageFolder,
    DeviceOrientation? deviceOrientation,
  }) async {
    if (_currentState == RecordingState.recording) return;

    _lastErrorMessage = null;
    _activeStorageFolder = storageFolder;

    // Zapisz orientację widoku kamery w momencie startu nagrywania
    _activeOrientation = _resolveOrientation(deviceOrientation);

    // 1. Weryfikacja przestrzeni dyskowej i uprawnień zapisu przed startem nagrania
    final hasSpace = await _storageService.hasSufficientStorageSpace(subDirectory: storageFolder);
    if (!hasSpace) {
      _currentState = RecordingState.failed;
      _lastErrorMessage = 'Brak wystarczającej przestrzeni dyskowej lub brak uprawnień zapisu do wybranego folderu ($storageFolder).';
      _stateController.add(_currentState);
      return;
    }

    _isCurrentSessionSimulated = isSimulation || cameraController == null || !cameraController.value.isInitialized;

    // 2. Start nagrywania sprzętowego przez CameraController (jeśli podłączony)
    if (!_isCurrentSessionSimulated && cameraController != null) {
      try {
        // Zablokuj orientację nagrywania na aktualną orientację urządzenia,
        // aby plik MP4 zachował spójność z widokiem kamery
        if (deviceOrientation != null) {
          try {
            await cameraController.lockCaptureOrientation(deviceOrientation);
          } catch (_) {
            // Niektóre urządzenia mogą nie obsługiwać blokowania orientacji
          }
        }
        await cameraController.startVideoRecording();
      } on CameraException catch (e) {
        _currentState = RecordingState.failed;
        _lastErrorMessage = 'Błąd sprzętowy sensora kamery: ${e.description ?? e.code}';
        _stateController.add(_currentState);
        return;
      } catch (e) {
        _currentState = RecordingState.failed;
        _lastErrorMessage = 'Nieoczekiwany błąd kamery: $e';
        _stateController.add(_currentState);
        return;
      }
    }

    // 3. Rozpoczęcie sesji nagrywania i zliczania czasu trwania
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
  Future<MasterRecordingResult?> stopRecording({
    CameraController? cameraController,
    bool simulatedDelay = false,
    String? storageFolder,
  }) async {
    _timer?.cancel();
    _timer = null;

    if (_currentState != RecordingState.recording) {
      return _lastRecordingResult;
    }

    _currentState = RecordingState.stopping;
    _stateController.add(_currentState);

    String? recordedSourcePath;

    // 1. Zatrzymanie sprzętowego nagrywania wideo przez CameraController
    if (!_isCurrentSessionSimulated &&
        cameraController != null &&
        cameraController.value.isInitialized &&
        cameraController.value.isRecordingVideo) {
      try {
        final XFile videoFile = await cameraController.stopVideoRecording();
        recordedSourcePath = videoFile.path;

        // Odblokuj orientację nagrywania po zakończeniu zapisu,
        // aby kamera mogła swobodnie reagować na obroty urządzenia
        try {
          await cameraController.unlockCaptureOrientation();
        } catch (_) {
          // Ignoruj — niektóre urządzenia mogą nie obsługiwać odblokowania
        }
      } on CameraException catch (e) {
        _currentState = RecordingState.failed;
        _lastErrorMessage = 'Błąd zapisu pliku wideo przez kamerę: ${e.description ?? e.code}';
        _stateController.add(_currentState);
        return null;
      } catch (e) {
        _currentState = RecordingState.failed;
        _lastErrorMessage = 'Błąd zatrzymania nagrywania sprzętowego: $e';
        _stateController.add(_currentState);
        return null;
      }
    }

    if (simulatedDelay) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 2. Finalizacja pliku w dedykowanym katalogu aplikacji (path_provider)
    final targetFolder = storageFolder ?? _activeStorageFolder;
    try {
      final result = await _storageService.finalizeRecording(
        sourcePath: recordedSourcePath,
        duration: _duration,
        isSimulated: _isCurrentSessionSimulated,
        subDirectory: targetFolder,
        recordedOrientation: _activeOrientation,
      );

      _lastRecordingResult = result;
      _currentState = RecordingState.saved;
      _stateController.add(_currentState);
      _finishedController.add(result);
      return result;
    } catch (e) {
      _currentState = RecordingState.failed;
      _lastErrorMessage = 'Nie udało się przenieść pliku MP4 do dedykowanego katalogu: $e';
      _stateController.add(_currentState);
      return null;
    }
  }

  /// Rozpoznaje orientację wideo na podstawie DeviceOrientation z sensora urządzenia
  static RecordedVideoOrientation _resolveOrientation(DeviceOrientation? deviceOrientation) {
    if (deviceOrientation == null) return RecordedVideoOrientation.landscape;
    switch (deviceOrientation) {
      case DeviceOrientation.landscapeLeft:
      case DeviceOrientation.landscapeRight:
        return RecordedVideoOrientation.landscape;
      case DeviceOrientation.portraitUp:
      case DeviceOrientation.portraitDown:
        return RecordedVideoOrientation.portrait;
    }
  }

  /// Resetuje stan sesji nagrywania do trybu idle, umożliwiając natychmiastowe nagranie kolejnego klipu
  @override
  void reset() {
    _timer?.cancel();
    _timer = null;
    _currentState = RecordingState.idle;
    _duration = Duration.zero;
    _lastErrorMessage = null;
    _stateController.add(_currentState);
    _durationController.add(_duration);
  }

  void dispose() {
    _timer?.cancel();
    _stateController.close();
    _durationController.close();
    _finishedController.close();
  }
}
