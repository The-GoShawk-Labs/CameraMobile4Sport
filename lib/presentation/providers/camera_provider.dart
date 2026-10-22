import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volleylive/core/services/video_storage_service.dart';
import 'package:volleylive/core/utils/camera_frame_converter.dart';
import 'package:volleylive/domain/models/camera_config.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/score_event.dart';
import 'package:volleylive/domain/models/recording_result.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/domain/services/native_stream_burner_bridge.dart';
import 'package:volleylive/domain/services/recording_service.dart';
import 'package:volleylive/domain/services/video_transport_service.dart';
import 'package:volleylive/presentation/providers/p2p_connection_provider.dart';
import 'package:volleylive/presentation/services/scoreboard_widget_burner.dart';

class CameraProvider extends ChangeNotifier {
  final RecordingService _recordingService;
  final VideoTransportService _transportService;

  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _isCameraInitialized = false;
  bool _isSimulationMode = false;
  String? _cameraErrorMessage;
  String? _appliedCameraSettingsKey;

  StreamSubscription<RecordingState>? _recordingStateSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<CameraConnectionState>? _transportSub;

  CameraSettings _settings = const CameraSettings();
  bool _isTripodLocked = false;
  double _audioLevel = 0.65; // 0.0 do 1.0 (VU Meter)
  final int _batteryLevel = 85;
  String _pairedHostCode = '';

  RecordingType _recordingType = RecordingType.programWithScoreboard;
  CameraDescription? _currentCameraDesc;
  bool _isTorchOn = false;
  RecordingType? _activeRecordingType;
  String? _recordingOverrideError;
  StreamSubscription? _scoreEventsSub;

  bool _isLiveTransmitting = false;
  bool _isStreamingFrames = false;
  int _lastFrameTimestamp = 0;
  bool _isConvertingFrame = false;
  P2PConnectionProvider? _activeP2pProvider;
  bool _isProgramPreviewCaptureEnabled = false;
  Uint8List? _programPreviewFrame;
  Completer<Uint8List?>? _firstProgramFrameCompleter;
  final StreamController<Uint8List> _programPreviewFrameController =
      StreamController<Uint8List>.broadcast();

  Timer? _audioSimTimer;

  CameraProvider({
    bool? enableAudioSim,
    RecordingService? recordingService,
    VideoTransportService? transportService,
  }) : _recordingService = recordingService ?? RecordingService(),
       _transportService = transportService ?? VideoTransportService() {
    final bool shouldEnableAudioSim =
        enableAudioSim ?? !Platform.environment.containsKey('FLUTTER_TEST');
    _initListeners(enableAudioSim: shouldEnableAudioSim);
    _loadSavedStorageFolder();
    _recordingService.storageService.ensureInitialDirectoriesCreated();
  }

  CameraController? get cameraController => _cameraController;
  CameraDescription? get currentCameraDescription => _currentCameraDesc;
  CameraLensDirection get currentLensDirection =>
      _currentCameraDesc?.lensDirection ?? CameraLensDirection.back;
  bool get isTorchOn => _isTorchOn;
  Uint8List? get programPreviewFrame => _programPreviewFrame;
  Stream<Uint8List> get programPreviewFrames =>
      _programPreviewFrameController.stream;
  List<CameraDescription> get availableCamerasList => _availableCameras;
  bool get isCameraInitialized => _isCameraInitialized;
  bool get isSimulationMode => _isSimulationMode;
  String? get cameraErrorMessage => _cameraErrorMessage;

  RecordingType get recordingType => _recordingType;
  RecordingType? get activeRecordingType => _activeRecordingType;

  void setRecordingType(RecordingType type) {
    if (isRecording) return;
    if (_recordingType != type) {
      _recordingType = type;
      notifyListeners();
    }
  }

  MatchSession? _currentSession;
  StreamSubscription? _matchSessionSub;

  MatchSession? get currentSession => _currentSession;

  /// Aktualizuje powiązaną sesję meczową
  void updateMatchSession(MatchSession session) {
    _currentSession = session;
  }

  /// Podłącza strumień zdarzeń punktowych z MatchProvider
  void attachMatchProvider(
    Stream<ScoreEvent> eventsStream, {
    MatchSession? currentSession,
    Stream<MatchSession>? sessionStream,
  }) {
    if (currentSession != null) {
      _currentSession = currentSession;
    }
    _matchSessionSub?.cancel();
    if (sessionStream != null) {
      _matchSessionSub = sessionStream.listen((session) {
        _currentSession = session;
        if (isRecording) {
          _recordingService.recordTimelineEvent(
            eventType: 'scoreUpdate',
            session: session,
          );
        }
      });
    }
    _scoreEventsSub?.cancel();
    _scoreEventsSub = eventsStream.listen((event) {
      if (sessionStream == null && isRecording && _currentSession != null) {
        _recordingService.recordTimelineEvent(
          eventType: event.type.name,
          session: _currentSession!,
        );
      }
    });
  }

  CameraSettings get settings => _settings;
  CameraConnectionState get connectionState => _transportService.currentState;
  RecordingState get recordingState => _recordingService.currentState;
  bool get isRecording =>
      _recordingService.currentState == RecordingState.recording;
  bool get isLiveTransmitting => _isLiveTransmitting;
  Duration get masterRecDuration => _recordingService.recordedDuration;
  bool get isTripodLocked => _isTripodLocked;
  double get audioLevel => _audioLevel;
  int get batteryLevel => _batteryLevel;
  String get pairedHostCode => _pairedHostCode;

  MasterRecordingResult? get lastRecordingResult =>
      _recordingService.lastRecordingResult;
  String? get recordingErrorMessage =>
      _recordingOverrideError ?? _recordingService.lastErrorMessage;
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
      // Symulacja wysterowania mikrofonu (wstrzymywana podczas strumieniowania/nagrywania klatek, by nie wywoływać przebudowy UI co 300ms)
      _audioSimTimer = Timer.periodic(const Duration(milliseconds: 300), (
        timer,
      ) {
        if (_isStreamingFrames || isRecording) return;
        _audioLevel = 0.4 + (DateTime.now().millisecond % 50) / 100;
        if (hasListeners) notifyListeners();
      });
    }
  }

  /// Zwalnia sesję Camera2/CameraX (CameraId-0) przed przejęciem jej przez natywny koder sprzętowy,
  /// eliminując deadlock na poziomie HAL w trybie pojedynczego smartfonu.
  Future<void> releaseCameraForExternalStreamer() async {
    final controller = _cameraController;
    _isCameraInitialized = false;
    _isStreamingFrames = false;
    _cameraController = null;
    notifyListeners();
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> initializeCamera() async {
    final nativeBridge = NativeStreamBurnerBridge();
    if (nativeBridge.isStreaming || nativeBridge.isRecording) {
      debugPrint('[CameraProvider] NativeStreamBurnerBridge is currently active (streaming or recording). Skipping CameraX initialization to prevent CameraDevice collision.');
      return;
    }
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
      _currentCameraDesc = cameraDesc;

      CameraController controller;
      try {
        controller = CameraController(
          cameraDesc,
          _resolutionPresetFor(_settings.resolution),
          enableAudio: _settings.isMicrophoneEnabled,
          imageFormatGroup: ImageFormatGroup.nv21,
        );
        await controller.initialize();
      } catch (e) {
        debugPrint('[CameraProvider] NV21 init failed ($e), falling back to yuv420...');
        controller = CameraController(
          cameraDesc,
          _resolutionPresetFor(_settings.resolution),
          enableAudio: _settings.isMicrophoneEnabled,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await controller.initialize();
      }

      _cameraController = controller;
      _isCameraInitialized = true;
      _isSimulationMode = false;
      _appliedCameraSettingsKey = _cameraSettingsKeyFor(
        _resolutionPresetFor(_settings.resolution),
      );

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

      if (_isLiveTransmitting || _isProgramPreviewCaptureEnabled) {
        _startImageStreamLoop(_activeP2pProvider);
      }

      notifyListeners();
    } catch (e) {
      _isSimulationMode = true;
      _isCameraInitialized = false;
      _cameraErrorMessage = e.toString();
      notifyListeners();
    }
  }

  static ResolutionPreset _resolutionPresetFor(VideoResolution resolution) {
    switch (resolution) {
      case VideoResolution.res720p:
        return ResolutionPreset.high;
      case VideoResolution.res1080p:
        return ResolutionPreset.veryHigh;
      case VideoResolution.res4k:
        return ResolutionPreset.ultraHigh;
    }
  }

  String _cameraSettingsKeyFor(ResolutionPreset preset) =>
      '${preset.name}:${_settings.fps.fps}:${(_settings.bitrateMbps * 1000000).round()}:${_settings.isMicrophoneEnabled}';

  /// Recreates the native camera session when quality settings have changed,
  /// so capture cadence and sensor resolution match the selected profile.
  Future<bool> prepareCameraForRecording({
    bool prioritizeSmoothFrameCapture = false,
    P2PConnectionProvider? p2pProvider,
  }) async {
    final previous = _cameraController;
    if (previous == null ||
        !previous.value.isInitialized ||
        _isSimulationMode) {
      return false;
    }
    // Flutter's image stream drops heavily at 1080p on many devices. Program
    // composition needs a steady sequence of frames for its widget capture.
    // Keep the encoded output resolution separately at the user's chosen size.
    final desiredPreset = _resolutionPresetFor(_settings.resolution);
    final desiredSettingsKey = _cameraSettingsKeyFor(desiredPreset);
    if (_appliedCameraSettingsKey == desiredSettingsKey) return true;

    final description = previous.description;
    final previousPreset = previous.resolutionPreset;
    _isCameraInitialized = false;
    _cameraController = null;
    notifyListeners();
    try {
      if (previous.value.isStreamingImages) {
        try {
          await previous.stopImageStream();
        } catch (_) {}
      }
      _isStreamingFrames = false;
      await previous.dispose();
      final controller = CameraController(
        description,
        desiredPreset,
        enableAudio: _settings.isMicrophoneEnabled,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (_settings.zoom > 1.0) {
        try {
          await controller.setZoomLevel(_settings.zoom);
        } catch (_) {}
      }
      if (_settings.exposureOffset != 0.0) {
        try {
          await controller.setExposureOffset(_settings.exposureOffset);
        } catch (_) {}
      }
      _currentCameraDesc = description;
      _cameraController = controller;
      _isCameraInitialized = true;
      _isSimulationMode = false;
      _appliedCameraSettingsKey = desiredSettingsKey;
      if (_isLiveTransmitting || _isProgramPreviewCaptureEnabled) {
        _startImageStreamLoop(p2pProvider);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _cameraErrorMessage = 'Nie udało się zastosować profilu kamery: $e';
      try {
        final fallback = CameraController(
          description,
          previousPreset,
          enableAudio: _settings.isMicrophoneEnabled,
          imageFormatGroup: ImageFormatGroup.nv21,
        );
        await fallback.initialize();
        _currentCameraDesc = description;
        _cameraController = fallback;
        _isCameraInitialized = true;
        _isSimulationMode = false;
      } catch (_) {
        _isSimulationMode = true;
      }
      notifyListeners();
      return false;
    }
  }

  Future<void> connectToScorer(String pairingCode) async {
    _pairedHostCode = pairingCode;
    await _transportService.connectToHost(pairingCode);
  }

  Future<void> startLiveTransmission({
    required P2PConnectionProvider p2pProvider,
  }) async {
    _activeP2pProvider = p2pProvider;
    _isLiveTransmitting = true;
    notifyListeners();

    debugPrint(
      '[CameraProvider] startLiveTransmission: role=${p2pProvider.currentRole.idName}, '
      'isHost=${p2pProvider.isHost}, connectionState=${p2pProvider.connectionState}',
    );

    if (_cameraController == null || !_isCameraInitialized) {
      debugPrint('[CameraProvider] Camera not initialized yet, initializing before stream...');
      await initializeCamera();
    }

    // Uruchom jako host dla sesji P2P TYLKO wtedy, gdy urządzenie nie łączy się ani nie jest już połączone jako klient
    if (!p2pProvider.isHost &&
        p2pProvider.currentRole != DeviceRole.cameraPhoneA &&
        p2pProvider.connectionState != CameraConnectionState.connected) {
      await p2pProvider.hostSession(
        pairingCode: _pairedHostCode.isNotEmpty ? _pairedHostCode : 'VL-8492',
        role: DeviceRole.cameraPhoneA,
      );
    }

    // Wyemituj handshake potwierdzający start strumienia kamery do operatora Phone B
    try {
      await p2pProvider.notifyStreamStarted(
        deviceName: 'Realme 12 Pro+',
        width: _settings.resolution.width,
        height: _settings.resolution.height,
        fps: _settings.fps.fps,
      );
    } catch (e) {
      debugPrint('[CameraProvider] notifyStreamStarted error: $e');
    }

    _startImageStreamLoop(p2pProvider);
  }

  Future<Uint8List?> startProgramPreviewFrameCapture() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isSimulationMode) {
      return null;
    }
    _isProgramPreviewCaptureEnabled = true;
    final completer = Completer<Uint8List?>();
    _firstProgramFrameCompleter = completer;
    if (!_isStreamingFrames) _startImageStreamLoop();
    try {
      return await completer.future.timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    } finally {
      if (identical(_firstProgramFrameCompleter, completer)) {
        _firstProgramFrameCompleter = null;
      }
    }
  }

  Future<void> stopProgramPreviewFrameCapture() async {
    _isProgramPreviewCaptureEnabled = false;
    _firstProgramFrameCompleter = null;
    if (!_isLiveTransmitting &&
        _isStreamingFrames &&
        _cameraController != null) {
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {}
      _isStreamingFrames = false;
    }
    _programPreviewFrame = null;
    notifyListeners();
  }

  void _startImageStreamLoop([P2PConnectionProvider? p2pProvider]) {
    final effectiveP2p = p2pProvider ?? _activeP2pProvider;
    if (p2pProvider != null) {
      _activeP2pProvider = p2pProvider;
    }

    final controller = _cameraController;
    if (controller != null &&
        controller.value.isInitialized &&
        !_isStreamingFrames &&
        !isRecording &&
        (_isLiveTransmitting || _isProgramPreviewCaptureEnabled)) {
      try {
        if (controller.value.isStreamingImages) {
          controller.stopImageStream().catchError((_) {});
        }
        _isStreamingFrames = true;
        int frameCounter = 0;
        debugPrint(
          '[CameraProvider] Image stream loop started (fps=${_settings.fps.fps}, '
          'quality=${_isLiveTransmitting ? 82 : 88})',
        );
        controller.startImageStream((CameraImage image) async {
          if (!_isLiveTransmitting && !_isProgramPreviewCaptureEnabled) return;

          final now = DateTime.now().millisecondsSinceEpoch;
          // Płynny interwał klatek ~20-22 FPS (min. 45 ms), chroniący kanał komunikacji przed zatkaniem bufora
          const minFrameIntervalMs = 45;
          if (now - _lastFrameTimestamp < minFrameIntervalMs) return;
          if (_isConvertingFrame) return;

          _isConvertingFrame = true;
          _lastFrameTimestamp = now;

          try {
            final jpeg = await CameraFrameConverter.convertYuvToJpeg(
              image,
              quality: _isLiveTransmitting ? 82 : 88,
            );
            if (jpeg != null) {
              frameCounter++;
              if (_isLiveTransmitting) {
                final targetP2p = _activeP2pProvider ?? p2pProvider ?? effectiveP2p;
                targetP2p?.broadcastVideoFrame(jpeg);
                if (frameCounter % 50 == 1) {
                  debugPrint(
                    '[CameraProvider] Live frame #$frameCounter transmitted '
                    '(${jpeg.lengthInBytes} bytes, planes=${image.planes.length})',
                  );
                }
              }
              if (_isProgramPreviewCaptureEnabled) {
                _programPreviewFrame = jpeg;
                if (!_programPreviewFrameController.isClosed) {
                  _programPreviewFrameController.add(jpeg);
                }
                final firstFrame = _firstProgramFrameCompleter;
                if (firstFrame != null && !firstFrame.isCompleted) {
                  firstFrame.complete(jpeg);
                }
                notifyListeners();
              }
            } else if (frameCounter == 0) {
              debugPrint(
                '[CameraProvider] Warning: Frame conversion returned null '
                '(planes=${image.planes.length}, format=${image.format.group})',
              );
            }
          } catch (e) {
            debugPrint('[CameraProvider] Frame conversion warning: $e');
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

  Future<void> stopLiveTransmission({
    required P2PConnectionProvider p2pProvider,
  }) async {
    _isLiveTransmitting = false;
    try {
      await p2pProvider.notifyStreamStopped(reason: 'User stopped transmission');
    } catch (_) {}
    if (_isStreamingFrames &&
        !_isProgramPreviewCaptureEnabled &&
        _cameraController != null) {
      try {
        await _cameraController!.stopImageStream();
      } catch (_) {}
      _isStreamingFrames = false;
    }
    notifyListeners();
  }

  Future<void> toggleLiveTransmission({
    required P2PConnectionProvider p2pProvider,
  }) async {
    if (_isLiveTransmitting) {
      await stopLiveTransmission(p2pProvider: p2pProvider);
    } else {
      await startLiveTransmission(p2pProvider: p2pProvider);
    }
  }

  /// Resetuje stan nagrywania do gotowości (idle), czyszcząc ewentualne komunikaty błędów
  void resetRecordingState() {
    _recordingOverrideError = null;
    _programPreviewFrame = null;
    _recordingService.reset();
    notifyListeners();
  }

  Future<void> toggleMasterRecording({
    P2PConnectionProvider? p2pProvider,
    DeviceOrientation? deviceOrientation,
    MatchSession? matchSession,
    RecordingType? recordingType,
    Stream<Uint8List>? programFrameStream,
    Uint8List? initialProgramFrame,
    Stream<Uint8List>? rawCameraFrameStream,
    Uint8List? initialRawCameraFrame,
    ScoreboardThemeStyle? scoreboardStyle,
  }) async {
    final typeToRecord = recordingType ?? _recordingType;
    _recordingOverrideError = null;

    if (matchSession != null) {
      _currentSession = matchSession;
    }

    final nativeBridge = NativeStreamBurnerBridge();
    final isNativeActive = nativeBridge.isStreaming || nativeBridge.isRecording;

    if (_recordingService.currentState == RecordingState.recording) {
      notifyListeners();
      await _recordingService.stopRecording(
        cameraController: isNativeActive ? null : _cameraController,
        nativeStreamBridge: isNativeActive ? nativeBridge : null,
        storageFolder: _settings.storageFolder,
        finalSession: matchSession ?? _currentSession,
        scoreboardStyle: scoreboardStyle ?? ScoreboardThemeStyle.tvProBroadcast,
        overlayImagePath: ScoreboardWidgetBurner.latestOverlayImagePath,
        overlayPngBytes: ScoreboardWidgetBurner.latestCapturedPngBytes,
      );
      _activeRecordingType = null;
      _programPreviewFrame = null;
      if (_isLiveTransmitting && p2pProvider != null) {
        _startImageStreamLoop(p2pProvider);
      }
    } else {
      // Jeśli poprzednie nagranie zakończyło się (saved) lub wystąpił błąd (failed),
      // zresetuj stan sesji przed rozpoczęciem kolejnego nagrania w tej samej sesji
      if (_recordingService.currentState != RecordingState.idle) {
        _recordingService.reset();
      }

      final isSimulation = !isNativeActive &&
          (_isSimulationMode ||
              _cameraController == null ||
              !_cameraController!.value.isInitialized ||
              Platform.environment.containsKey('FLUTTER_TEST'));

      if (!isNativeActive && _cameraController != null) {
        if (_cameraController!.value.isStreamingImages) {
          try {
            await _cameraController!.stopImageStream();
          } catch (_) {}
        }
        _isStreamingFrames = false;
        _programPreviewFrame = null;
        // Krótka pauza zapobiegająca race condition w Camera2 pipeline na urządzeniach z Androidem
        await Future.delayed(const Duration(milliseconds: 150));
      }
      notifyListeners();
      _activeRecordingType = typeToRecord;
      await _recordingService.startMasterRecording(
        cameraController: (isSimulation || isNativeActive) ? null : _cameraController,
        nativeStreamBridge: isNativeActive ? nativeBridge : null,
        remoteFrameStream: programFrameStream,
        initialFrame: initialProgramFrame,
        rawCameraFrameStream: rawCameraFrameStream,
        initialRawCameraFrame: initialRawCameraFrame,
        remoteFrameExtension: 'png',
        remoteFramesIncludeProgramOverlay: programFrameStream != null,
        encodingBitrateMbps: _settings.bitrateMbps,
        encodingFps: _settings.fps.fps,
        encodingWidth: _settings.resolution.width,
        encodingHeight: _settings.resolution.height,
        isSimulation: isSimulation,
        storageFolder: _settings.storageFolder,
        deviceOrientation: deviceOrientation,
        recordingType: typeToRecord,
        initialSession: matchSession ?? _currentSession,
      );
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (_availableCameras.length <= 1) return;
    final currentDirection =
        _currentCameraDesc?.lensDirection ?? CameraLensDirection.back;
    final targetDirection = currentDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final nextDesc = _availableCameras.firstWhere(
      (cam) => cam.lensDirection == targetDirection,
      orElse: () => _availableCameras.firstWhere(
        (cam) => cam != _currentCameraDesc,
        orElse: () => _availableCameras.first,
      ),
    );
    if (nextDesc == _currentCameraDesc) return;

    final prevController = _cameraController;
    _isCameraInitialized = false;
    _cameraController = null;
    notifyListeners();

    try {
      if (prevController != null) {
        if (prevController.value.isStreamingImages) {
          try {
            await prevController.stopImageStream();
          } catch (_) {}
        }
        await prevController.dispose();
      }
      final controller = CameraController(
        nextDesc,
        _resolutionPresetFor(_settings.resolution),
        enableAudio: _settings.isMicrophoneEnabled,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      _currentCameraDesc = nextDesc;
      _cameraController = controller;
      _isCameraInitialized = true;
      _isSimulationMode = false;
      _isTorchOn = false;
      if (_isLiveTransmitting || _isProgramPreviewCaptureEnabled) {
        _startImageStreamLoop(_activeP2pProvider);
      }
      notifyListeners();
    } catch (e) {
      _cameraErrorMessage = 'Błąd przełączania kamery: $e';
      notifyListeners();
    }
  }

  Future<void> toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final nextState = !_isTorchOn;
      await controller.setFlashMode(nextState ? FlashMode.torch : FlashMode.off);
      _isTorchOn = nextState;
      notifyListeners();
    } catch (_) {}
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
    final clamped = offset.clamp(
      _settings.minExposureOffset,
      _settings.maxExposureOffset,
    );
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
    _settings = _settings.copyWith(
      isStabilizationEnabled: !_settings.isStabilizationEnabled,
    );
    notifyListeners();
  }

  void toggleMicrophone() {
    _settings = _settings.copyWith(
      isMicrophoneEnabled: !_settings.isMicrophoneEnabled,
    );
    notifyListeners();
  }

  void updateSettings(CameraSettings newSettings) {
    _settings = newSettings;
    notifyListeners();
  }

  Future<void> setStorageFolder(String folder) async {
    final sanitized = VideoStorageService.sanitizeFolderName(folder);
    _settings = _settings.copyWith(storageFolder: sanitized);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('volleylive_camera_storage_folder', sanitized);
    } catch (_) {}
  }

  /// Przenosi ostatnio nagrany plik do nowego folderu i aktualizuje aktywną lokalizację
  Future<MasterRecordingResult?> moveLastRecording(String targetFolder) async {
    final last = _recordingService.lastRecordingResult;
    if (last == null) return null;
    final updated = await _recordingService.storageService.moveRecording(
      currentResult: last,
      targetSubDirectory: targetFolder,
    );
    _recordingService.updateLastRecordingResult(updated);
    await setStorageFolder(targetFolder);
    notifyListeners();
    return updated;
  }

  Future<void> _loadSavedStorageFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedFolder = prefs.getString('volleylive_camera_storage_folder');
      if (savedFolder != null && savedFolder.trim().isNotEmpty) {
        _settings = _settings.copyWith(
          storageFolder: VideoStorageService.sanitizeFolderName(savedFolder),
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _audioSimTimer?.cancel();
    _scoreEventsSub?.cancel();
    _matchSessionSub?.cancel();
    _recordingStateSub?.cancel();
    _durationSub?.cancel();
    _transportSub?.cancel();
    if (_isStreamingFrames) {
      unawaited(_cameraController?.stopImageStream() ?? Future<void>.value());
    }
    _programPreviewFrameController.close();
    _cameraController?.dispose();
    _recordingService.dispose();
    _transportService.dispose();
    super.dispose();
  }
}
