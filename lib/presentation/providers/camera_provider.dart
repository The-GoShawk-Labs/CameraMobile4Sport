import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:volleylive/domain/models/camera_config.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/services/recording_service.dart';
import 'package:volleylive/domain/services/video_transport_service.dart';

class CameraProvider extends ChangeNotifier {
  final RecordingService _recordingService = RecordingService();
  final VideoTransportService _transportService = VideoTransportService();

  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _isCameraInitialized = false;
  bool _isSimulationMode = false;
  String? _cameraErrorMessage;

  CameraSettings _settings = const CameraSettings();
  CameraConnectionState _connectionState = CameraConnectionState.disconnected;
  RecordingState _recordingState = RecordingState.idle;
  Duration _masterRecDuration = Duration.zero;
  bool _isTripodLocked = false;
  double _audioLevel = 0.65; // 0.0 do 1.0 (VU Meter)
  final int _batteryLevel = 85;
  String _pairedHostCode = '';

  Timer? _audioSimTimer;

  CameraProvider({bool enableAudioSim = true}) {
    _initListeners(enableAudioSim: enableAudioSim);
  }

  CameraController? get cameraController => _cameraController;
  List<CameraDescription> get availableCamerasList => _availableCameras;
  bool get isCameraInitialized => _isCameraInitialized;
  bool get isSimulationMode => _isSimulationMode;
  String? get cameraErrorMessage => _cameraErrorMessage;

  CameraSettings get settings => _settings;
  CameraConnectionState get connectionState => _connectionState;
  RecordingState get recordingState => _recordingState;
  bool get isRecording => _recordingState == RecordingState.recording;
  Duration get masterRecDuration => _masterRecDuration;
  bool get isTripodLocked => _isTripodLocked;
  double get audioLevel => _audioLevel;
  int get batteryLevel => _batteryLevel;
  String get pairedHostCode => _pairedHostCode;

  void _initListeners({bool enableAudioSim = true}) {
    _recordingService.recordingStateStream.listen((state) {
      _recordingState = state;
      notifyListeners();
    });

    _recordingService.durationStream.listen((duration) {
      _masterRecDuration = duration;
      notifyListeners();
    });

    _transportService.connectionStateStream.listen((state) {
      _connectionState = state;
      notifyListeners();
    });

    if (enableAudioSim) {
      // Symulacja wysterowania mikrofonu
      _audioSimTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
        _audioLevel = 0.4 + (DateTime.now().millisecond % 50) / 100;
        notifyListeners();
      });
    }
  }

  Future<void> initializeCamera() async {
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        _isSimulationMode = true;
        _isCameraInitialized = false;
        notifyListeners();
        return;
      }

      // Preferuj tylny aparat (kamera meczowa na statyw)
      final cameraDesc = _availableCameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _availableCameras.first,
      );

      final controller = CameraController(
        cameraDesc,
        ResolutionPreset.high,
        enableAudio: _settings.isMicrophoneEnabled,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      _cameraController = controller;
      _isCameraInitialized = true;
      _isSimulationMode = false;

      // Pobierz limity zoomu i kompensacji ekspozycji dla urządzenia
      double minZoom = 1.0;
      double maxZoom = 8.0;
      double minExp = -2.0;
      double maxExp = 2.0;
      double expStep = 0.1;

      try {
        minZoom = await controller.getMinZoomLevel();
        maxZoom = await controller.getMaxZoomLevel();
        minExp = await controller.getMinExposureOffset();
        maxExp = await controller.getMaxExposureOffset();
        expStep = await controller.getExposureOffsetStepSize();
        if (expStep <= 0) expStep = 0.1;
      } catch (_) {
        // Niektóre platformy mogą nie obsługiwać odczytu limitów
      }

      _settings = _settings.copyWith(
        minZoomLevel: minZoom,
        maxZoomLevel: maxZoom,
        minExposureOffset: minExp,
        maxExposureOffset: maxExp,
        exposureStep: expStep,
      );

      notifyListeners();
    } catch (e) {
      _isSimulationMode = true;
      _isCameraInitialized = false;
      _cameraErrorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> connectToScorer(String pairingCode) async {
    _pairedHostCode = pairingCode;
    await _transportService.connectToHost(pairingCode);
  }

  Future<void> toggleMasterRecording() async {
    if (_recordingState == RecordingState.recording) {
      _recordingState = RecordingState.stopping;
      notifyListeners();
      await _recordingService.stopRecording();
      _recordingState = RecordingState.saved;
    } else {
      _recordingState = RecordingState.recording;
      notifyListeners();
      await _recordingService.startMasterRecording();
    }
    notifyListeners();
  }

  Future<void> setZoom(double zoom) async {
    final clamped = zoom.clamp(_settings.minZoomLevel, _settings.maxZoomLevel);
    _settings = _settings.copyWith(zoom: clamped);
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setZoomLevel(clamped);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> setLens(CameraLens lens) async {
    _settings = _settings.copyWith(lens: lens);
    await setZoom(lens.zoomRatio);
  }

  Future<void> setExposureOffset(double offset) async {
    final clamped = offset.clamp(_settings.minExposureOffset, _settings.maxExposureOffset);
    _settings = _settings.copyWith(exposureOffset: clamped);
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setExposureOffset(clamped);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> setFocusAndExposurePoint(Offset point) async {
    _settings = _settings.copyWith(
      focusPoint: point,
      exposurePoint: point,
      isManualFocusMode: true,
    );
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setFocusPoint(point);
        await _cameraController!.setExposurePoint(point);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> toggleExposureLock() async {
    final nextState = !_settings.isExposureLocked;
    _settings = _settings.copyWith(isExposureLocked: nextState);
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setExposureMode(
          nextState ? ExposureMode.locked : ExposureMode.auto,
        );
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> toggleFocusLock() async {
    final nextState = !_settings.isFocusLocked;
    _settings = _settings.copyWith(isFocusLocked: nextState);
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setFocusMode(
          nextState ? FocusMode.locked : FocusMode.auto,
        );
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> resetFocusAndExposure() async {
    _settings = _settings.copyWith(
      exposureOffset: 0.0,
      isExposureLocked: false,
      isFocusLocked: false,
      isManualFocusMode: false,
      clearFocusPoint: true,
      clearExposurePoint: true,
    );
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
        await _cameraController!.setExposureMode(ExposureMode.auto);
        await _cameraController!.setExposureOffset(0.0);
      } catch (_) {}
    }
    notifyListeners();
  }

  void toggleHudVisibility() {
    _settings = _settings.copyWith(isHudVisible: !_settings.isHudVisible);
    notifyListeners();
  }

  void toggleTripodLock() {
    _isTripodLocked = !_isTripodLocked;
    notifyListeners();
  }

  void setResolution(VideoResolution resolution) {
    _settings = _settings.copyWith(resolution: resolution);
    notifyListeners();
  }

  void setFps(VideoFps fps) {
    _settings = _settings.copyWith(fps: fps);
    notifyListeners();
  }

  void setBitrate(double bitrateMbps) {
    _settings = _settings.copyWith(bitrateMbps: bitrateMbps);
    notifyListeners();
  }

  void toggleStabilization() {
    _settings = _settings.copyWith(isStabilizationEnabled: !_settings.isStabilizationEnabled);
    notifyListeners();
  }

  void toggleMicrophone() {
    _settings = _settings.copyWith(isMicrophoneEnabled: !_settings.isMicrophoneEnabled);
    notifyListeners();
  }

  void updateSettings(CameraSettings newSettings) {
    _settings = newSettings;
    notifyListeners();
  }

  @override
  void dispose() {
    _audioSimTimer?.cancel();
    _cameraController?.dispose();
    _recordingService.dispose();
    _transportService.dispose();
    super.dispose();
  }
}
