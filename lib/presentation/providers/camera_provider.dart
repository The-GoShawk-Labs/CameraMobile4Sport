import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:volleylive/core/utils/camera_frame_converter.dart';
import 'package:volleylive/domain/models/camera_config.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/recording_result.dart';
import 'package:volleylive/domain/services/recording_service.dart';
import 'package:volleylive/domain/services/video_transport_service.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';

class CameraProvider extends ChangeNotifier {
  final RecordingService _recordingService;
  final VideoTransportService _transportService;

  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _isCameraInitialized = false;
  bool _isSimulationMode = false;
  String? _cameraErrorMessage;

  StreamSubscription<RecordingState>? _recordingStateSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<CameraConnectionState>? _transportSub;

  CameraSettings _settings = const CameraSettings();
  bool _isTripodLocked = false;
  double _audioLevel = 0.65; // 0.0 do 1.0 (VU Meter)
  final int _batteryLevel = 85;
  String _pairedHostCode = '';

  bool _isLiveTransmitting = false;
  bool _isStreamingFrames = false;
  int _lastFrameTimestamp = 0;
  bool _isConvertingFrame = false;

  Timer? _audioSimTimer;

  CameraProvider({
    bool? enableAudioSim,
    RecordingService? recordingService,
    VideoTransportService? transportService,
  })  : _recordingService = recordingService ?? RecordingService(),
        _transportService = transportService ?? VideoTransportService() {
    final bool shouldEnableAudioSim = enableAudioSim ?? !Platform.environment.containsKey('FLUTTER_TEST');
    _initListeners(enableAudioSim: shouldEnableAudioSim);
  }

  CameraController? get cameraController => _cameraController;
  List<CameraDescription> get availableCamerasList => _availableCameras;
  bool get isCameraInitialized => _isCameraInitialized;
  bool get isSimulationMode => _isSimulationMode;
  String? get cameraErrorMessage => _cameraErrorMessage;

  CameraSettings get settings => _settings;
  CameraConnectionState get connectionState => _transportService.currentState;
  RecordingState get recordingState => _recordingService.currentState;
  bool get isRecording => _recordingService.currentState == RecordingState.recording;
  bool get isLiveTransmitting => _isLiveTransmitting;
  Duration get masterRecDuration => _recordingService.recordedDuration;
  bool get isTripodLocked => _isTripodLocked;
  double get audioLevel => _audioLevel;
  int get batteryLevel => _batteryLevel;
  String get pairedHostCode => _pairedHostCode;

  MasterRecordingResult? get lastRecordingResult => _recordingService.lastRecordingResult;
  String? get recordingErrorMessage => _recordingService.lastErrorMessage;
  RecordingService get recordingService => _recordingService;
  VideoTransportService get transportService => _transportService;

  void _initListeners({bool enableAudioSim = true}) {
    _recordingStateSub = _recordingService.recordingStateStream.listen((state) {
      if (hasListeners) notifyListeners();
    });

    _durationSub = _recordingService.durationStream.listen((duration) {
      if (hasListeners) notifyListeners();
    });

    _transportSub = _transportService.connectionStateStream.listen((state) {
      // ŻELAZNA ZASADA WSAD.md:
      // Zmiana stanu połączenia P2P/WebRTC (rozłączenie, restart, błąd)
      // pod żadnym pozorem NIE może przerwać trwającego nagrywania Master REC na Phone A.
      if (hasListeners) notifyListeners();
    });

    if (enableAudioSim) {
      // Symulacja wysterowania mikrofonu
      _audioSimTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
        _audioLevel = 0.4 + (DateTime.now().millisecond % 50) / 100;
        if (hasListeners) notifyListeners();
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

  Future<void> startLiveTransmission({required P2PConnectionProvider p2pProvider}) async {
    _isLiveTransmitting = true;
    notifyListeners();

    // Uruchom jako host dla sesji P2P, aby sędzia mógł się podłączyć
    if (!p2pProvider.isHost && p2pProvider.connectionState != CameraConnectionState.connected) {
      await p2pProvider.hostSession(
        pairingCode: _pairedHostCode.isNotEmpty ? _pairedHostCode : 'VL-8492',
        role: DeviceRole.cameraPhoneA,
      );
    }

    _startImageStreamLoop(p2pProvider);
  }

  void _startImageStreamLoop(P2PConnectionProvider p2pProvider) {
    if (_cameraController != null &&
        _cameraController!.value.isInitialized &&
        !_isStreamingFrames &&
        !isRecording) {
      try {
        _isStreamingFrames = true;
        _cameraController!.startImageStream((CameraImage image) async {
          if (!_isLiveTransmitting) return;

          final now = DateTime.now().millisecondsSinceEpoch;
          // Ogranicz do ~18-20 FPS (min. 55 ms między klatkami)
          if (now - _lastFrameTimestamp < 55) return;
          if (_isConvertingFrame) return;

          _isConvertingFrame = true;
          _lastFrameTimestamp = now;

          try {
            final jpeg = await CameraFrameConverter.convertYuvToJpeg(image, quality: 50);
            if (jpeg != null && _isLiveTransmitting) {
              p2pProvider.broadcastVideoFrame(jpeg);
            }
          } catch (_) {
          } finally {
            _isConvertingFrame = false;
          }
        });
      } catch (e) {
        _isStreamingFrames = false;
        debugPrint('Błąd startImageStream: $e');
      }
    }
  }

  Future<void> stopLiveTransmission({required P2PConnectionProvider p2pProvider}) async {
    _isLiveTransmitting = false;
    if (_isStreamingFrames && _cameraController != null) {
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {}
      _isStreamingFrames = false;
    }
    notifyListeners();
  }

  Future<void> toggleLiveTransmission({required P2PConnectionProvider p2pProvider}) async {
    if (_isLiveTransmitting) {
      await stopLiveTransmission(p2pProvider: p2pProvider);
    } else {
      await startLiveTransmission(p2pProvider: p2pProvider);
    }
  }

  Future<void> toggleMasterRecording({P2PConnectionProvider? p2pProvider}) async {
    if (_recordingService.currentState == RecordingState.recording) {
      notifyListeners();
      await _recordingService.stopRecording(
        cameraController: _cameraController,
      );
      if (_isLiveTransmitting && p2pProvider != null) {
        _startImageStreamLoop(p2pProvider);
      }
    } else {
      if (_isStreamingFrames && _cameraController != null) {
        try {
          await _cameraController!.stopImageStream();
        } catch (_) {}
        _isStreamingFrames = false;
      }
      notifyListeners();
      await _recordingService.startMasterRecording(
        cameraController: _cameraController,
        isSimulation: _isSimulationMode || _cameraController == null,
      );
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
    _recordingStateSub?.cancel();
    _durationSub?.cancel();
    _transportSub?.cancel();
    _cameraController?.dispose();
    _recordingService.dispose();
    _transportService.dispose();
    super.dispose();
  }
}
