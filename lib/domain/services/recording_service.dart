import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:volleylive/core/services/video_storage_service.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/match_recording_metadata.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/recording_result.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/domain/services/native_stream_burner_bridge.dart';
import 'package:volleylive/domain/services/remote_frame_recorder.dart';
import 'package:volleylive/domain/services/video_overlay_burner_service.dart';

abstract class IRecordingService {
  Stream<RecordingState> get recordingStateStream;
  Stream<Duration> get durationStream;
  Stream<MasterRecordingResult> get recordingFinishedStream;

  RecordingState get currentState;
  Duration get recordedDuration;
  MasterRecordingResult? get lastRecordingResult;
  String? get lastErrorMessage;
  RecordingType get activeRecordingType;

  Future<void> startMasterRecording({
    CameraController? cameraController,
    IRemoteFrameRecorder? remoteFrameRecorder,
    NativeStreamBurnerBridge? nativeStreamBridge,
    Stream<Uint8List>? remoteFrameStream,
    Uint8List? initialFrame,
    String remoteFrameExtension = 'jpg',
    bool remoteFramesIncludeProgramOverlay = false,
    Stream<Uint8List>? rawCameraFrameStream,
    Uint8List? initialRawCameraFrame,
    String rawCameraFrameExtension = 'jpg',
    double encodingBitrateMbps = 8.0,
    int encodingFps = 30,
    int encodingWidth = 1920,
    int encodingHeight = 1080,
    bool isSimulation = false,
    String? storageFolder,
    DeviceOrientation? deviceOrientation,
    RecordingType recordingType = RecordingType.rawCamera,
    MatchSession? initialSession,
  });

  void recordTimelineEvent({
    required String eventType,
    required MatchSession session,
    String? eventTag,
  });

  Future<MasterRecordingResult?> stopRecording({
    CameraController? cameraController,
    IRemoteFrameRecorder? remoteFrameRecorder,
    NativeStreamBurnerBridge? nativeStreamBridge,
    bool simulatedDelay = false,
    String? storageFolder,
    MatchSession? finalSession,
    ScoreboardThemeStyle scoreboardStyle = ScoreboardThemeStyle.tvProBroadcast,
    String? overlayImagePath,
    Uint8List? overlayPngBytes,
  });

  void reset();
}

/// Serwis nagrywania wideo Master REC MP4 na Phone A oraz Program REC na Phone B
class RecordingService implements IRecordingService {
  final VideoStorageService _storageService;
  final VideoOverlayBurnerService _burnerService;

  final _stateController = StreamController<RecordingState>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _finishedController =
      StreamController<MasterRecordingResult>.broadcast();

  RecordingState _currentState = RecordingState.idle;
  Duration _duration = Duration.zero;
  Timer? _timer;
  MasterRecordingResult? _lastRecordingResult;
  String? _lastErrorMessage;
  bool _isCurrentSessionSimulated = false;
  String? _activeStorageFolder;
  RecordedVideoOrientation _activeOrientation =
      RecordedVideoOrientation.landscape;
  RecordingType _activeRecordingType = RecordingType.rawCamera;

  // Kolekcja zdarzeń punktowych ze znacznikami czasu dla danej sesji nagrywania
  final List<ScoreTimelineEntry> _sessionTimeline = [];
  MatchSession? _startSession;
  DateTime? _recordingStartTime;

  RecordingService({
    VideoStorageService? storageService,
    VideoOverlayBurnerService? burnerService,
  }) : _storageService = storageService ?? VideoStorageService(),
       _burnerService = burnerService ?? VideoOverlayBurnerService();

  @override
  Stream<RecordingState> get recordingStateStream => _stateController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<MasterRecordingResult> get recordingFinishedStream =>
      _finishedController.stream;

  @override
  RecordingState get currentState => _currentState;

  @override
  Duration get recordedDuration => _duration;

  @override
  MasterRecordingResult? get lastRecordingResult => _lastRecordingResult;

  @override
  RecordingType get activeRecordingType => _activeRecordingType;

  MatchSession? get startSession => _startSession;
  DateTime? get recordingStartTime => _recordingStartTime;
  List<ScoreTimelineEntry> get sessionTimeline =>
      List.unmodifiable(_sessionTimeline);

  VideoStorageService get storageService => _storageService;

  void updateLastRecordingResult(MasterRecordingResult result) {
    _lastRecordingResult = result;
    _finishedController.add(result);
  }

  @override
  String? get lastErrorMessage => _lastErrorMessage;

  IRemoteFrameRecorder? _activeRemoteRecorder;
  bool _ownsRemoteRecorder = false;
  IRemoteFrameRecorder? _activeRawFrameRecorder;
  bool _activeRemoteFramesIncludeProgramOverlay = false;
  bool _isNativeStreamRecordingActive = false;
  String? _activeNativeRecordPath;

  @override
  Future<void> startMasterRecording({
    CameraController? cameraController,
    IRemoteFrameRecorder? remoteFrameRecorder,
    NativeStreamBurnerBridge? nativeStreamBridge,
    Stream<Uint8List>? remoteFrameStream,
    Uint8List? initialFrame,
    String remoteFrameExtension = 'jpg',
    bool remoteFramesIncludeProgramOverlay = false,
    Stream<Uint8List>? rawCameraFrameStream,
    Uint8List? initialRawCameraFrame,
    String rawCameraFrameExtension = 'jpg',
    double encodingBitrateMbps = 8.0,
    int encodingFps = 30,
    int encodingWidth = 1920,
    int encodingHeight = 1080,
    bool isSimulation = false,
    String? storageFolder,
    DeviceOrientation? deviceOrientation,
    RecordingType recordingType = RecordingType.rawCamera,
    MatchSession? initialSession,
  }) async {
    if (_currentState == RecordingState.recording) return;

    _lastErrorMessage = null;
    _activeStorageFolder = storageFolder;
    _activeRecordingType = recordingType;
    _activeRemoteFramesIncludeProgramOverlay =
        remoteFramesIncludeProgramOverlay;
    _startSession = initialSession;
    _recordingStartTime = DateTime.now();
    _sessionTimeline.clear();
    _isNativeStreamRecordingActive = false;
    _activeNativeRecordPath = null;

    if (initialSession != null) {
      _sessionTimeline.add(
        ScoreTimelineEntry(
          offsetMs: 0,
          eventType: 'start',
          setNumber: initialSession.currentSetNumber,
          scoreA: initialSession.currentSetPointsA,
          scoreB: initialSession.currentSetPointsB,
          setsA: initialSession.setsA,
          setsB: initialSession.setsB,
          servingTeam: initialSession.currentServer == ServingTeam.teamA
              ? 'A'
              : (initialSession.currentServer == ServingTeam.teamB
                    ? 'B'
                    : 'NONE'),
          eventTag: null,
        ),
      );
    }

    // Zapisz orientację widoku kamery w momencie startu nagrywania
    _activeOrientation = _resolveOrientation(deviceOrientation);

    // 1. Weryfikacja przestrzeni dyskowej i uprawnień zapisu przed startem nagrania
    final hasSpace = await _storageService.hasSufficientStorageSpace(
      subDirectory: storageFolder,
    );
    if (!hasSpace) {
      _currentState = RecordingState.failed;
      _lastErrorMessage =
          'Brak wystarczającej przestrzeni dyskowej lub brak uprawnień zapisu do wybranego folderu ($storageFolder).';
      _stateController.add(_currentState);
      return;
    }

    // Single-Encode, Dual-Mux: Jeśli aktywny jest natywny mostek RootEncoder (RTMP stream lub Phone A native)
    final bool useNativeBridge = nativeStreamBridge != null &&
        (nativeStreamBridge.isStreaming ||
            nativeStreamBridge.isRecording ||
            cameraController == null);

    if (useNativeBridge) {
      _isCurrentSessionSimulated = false;
      try {
        final targetPath = await _storageService.generateNewRecordingPath(
          subDirectory: storageFolder,
          recordingType: recordingType,
        );
        final success = await nativeStreamBridge.startRecord(targetPath);
        if (success) {
          _isNativeStreamRecordingActive = true;
          _activeNativeRecordPath = targetPath;
        } else {
          _currentState = RecordingState.failed;
          _lastErrorMessage =
              'Nie udało się uruchomić sprzętowego nagrywania MP4 w RootEncoder.';
          _stateController.add(_currentState);
          return;
        }
      } catch (e) {
        _currentState = RecordingState.failed;
        _lastErrorMessage = 'Błąd sprzętowego nagrywania MP4: $e';
        _stateController.add(_currentState);
        return;
      }
    } else if (remoteFrameRecorder != null ||
        remoteFrameStream != null ||
        initialFrame != null) {
      _isCurrentSessionSimulated = isSimulation;
      try {
        if (remoteFrameRecorder != null) {
          _activeRemoteRecorder = remoteFrameRecorder;
          _ownsRemoteRecorder = false;
        } else {
          _activeRemoteRecorder = RemoteFrameRecorder();
          _ownsRemoteRecorder = true;
        }
        await _activeRemoteRecorder!.startRecording(
          frameStream: remoteFrameStream,
          initialFrame: initialFrame,
          imageExtension: remoteFrameExtension,
          bitrateMbps: encodingBitrateMbps,
          targetFps: encodingFps,
          targetWidth: encodingWidth,
          targetHeight: encodingHeight,
        );
      } catch (e) {
        _activeRemoteRecorder = null;
        _ownsRemoteRecorder = false;
        _currentState = RecordingState.failed;
        _lastErrorMessage =
            'Nie udało się rozpocząć przechwytywania programu: $e';
        _stateController.add(_currentState);
        return;
      }
    } else {
      _activeRemoteRecorder = null;
      _ownsRemoteRecorder = false;
      _isCurrentSessionSimulated =
          isSimulation ||
          cameraController == null ||
          !cameraController.value.isInitialized;
    }

    if (rawCameraFrameStream != null || initialRawCameraFrame != null) {
      if (recordingType != RecordingType.dual ||
          rawCameraFrameStream == null ||
          initialRawCameraFrame == null) {
        _currentState = RecordingState.failed;
        _lastErrorMessage =
            'Brak kompletnego, czystego źródła kamery dla trybu Dual.';
        _stateController.add(_currentState);
        await _activeRemoteRecorder?.cancel();
        _activeRemoteRecorder = null;
        _ownsRemoteRecorder = false;
        return;
      }
      try {
        _activeRawFrameRecorder = RemoteFrameRecorder();
        await _activeRawFrameRecorder!.startRecording(
          frameStream: rawCameraFrameStream,
          initialFrame: initialRawCameraFrame,
          imageExtension: rawCameraFrameExtension,
          bitrateMbps: encodingBitrateMbps,
          targetFps: encodingFps,
          targetWidth: encodingWidth,
          targetHeight: encodingHeight,
        );
        _isCurrentSessionSimulated = false;
      } catch (e) {
        _activeRawFrameRecorder = null;
        _currentState = RecordingState.failed;
        _lastErrorMessage =
            'Nie udało się rozpocząć zapisu czystego obrazu Dual: $e';
        _stateController.add(_currentState);
        await _activeRemoteRecorder?.cancel();
        _activeRemoteRecorder = null;
        _ownsRemoteRecorder = false;
        return;
      }
    }

    // 2. Start nagrywania sprzętowego przez CameraController (jeśli podłączony na Phone A i nie nagrywamy przez RootEncoder)
    if (!_isCurrentSessionSimulated &&
        !_isNativeStreamRecordingActive &&
        cameraController != null) {
      try {
        await cameraController.startVideoRecording();
      } on CameraException catch (e) {
        _currentState = RecordingState.failed;
        _lastErrorMessage =
            'Błąd sprzętowy sensora kamery: ${e.description ?? e.code}';
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

  /// Rejestruje zdarzenie punktowe w osi czasu nagrania z dokładnym offsetem milisekundowym
  @override
  void recordTimelineEvent({
    required String eventType,
    required MatchSession session,
    String? eventTag,
  }) {
    if (_currentState != RecordingState.recording) return;

    final now = DateTime.now();
    final rawOffsetMs = _recordingStartTime != null
        ? now.difference(_recordingStartTime!).inMilliseconds
        : _duration.inMilliseconds;

    // Ensure strictly monotonically increasing offsetMs with at least 150ms separation
    // so every rapid point gets distinct, visible display time in the video!
    final lastOffsetMs = _sessionTimeline.isNotEmpty
        ? _sessionTimeline.last.offsetMs
        : -1;
    final minOffsetMs = lastOffsetMs >= 0 ? lastOffsetMs + 150 : 0;
    final safeOffsetMs = rawOffsetMs < minOffsetMs
        ? minOffsetMs
        : rawOffsetMs;

    final cleanTag = ScoreTimelineEntry.isDisplayableSpecialBanner(eventTag)
        ? eventTag
        : null;

    _sessionTimeline.add(
      ScoreTimelineEntry(
        offsetMs: safeOffsetMs,
        eventType: eventType,
        setNumber: session.currentSetNumber,
        scoreA: session.currentSetPointsA,
        scoreB: session.currentSetPointsB,
        setsA: session.setsA,
        setsB: session.setsB,
        servingTeam: session.currentServer == ServingTeam.teamA
            ? 'A'
            : (session.currentServer == ServingTeam.teamB ? 'B' : 'NONE'),
        eventTag: cleanTag,
      ),
    );
  }

  @override
  Future<MasterRecordingResult?> stopRecording({
    CameraController? cameraController,
    IRemoteFrameRecorder? remoteFrameRecorder,
    NativeStreamBurnerBridge? nativeStreamBridge,
    bool simulatedDelay = false,
    String? storageFolder,
    MatchSession? finalSession,
    ScoreboardThemeStyle scoreboardStyle = ScoreboardThemeStyle.tvProBroadcast,
    String? overlayImagePath,
    Uint8List? overlayPngBytes,
  }) async {
    _timer?.cancel();
    _timer = null;

    if (_currentState != RecordingState.recording) {
      return _lastRecordingResult;
    }

    _currentState = RecordingState.stopping;
    _stateController.add(_currentState);

    String? recordedSourcePath;
    String? remoteProgramSourcePath;
    String? rawCameraFrameSourcePath;

    // 1. Zatrzymanie sprzętowego nagrywania wideo przez NativeStreamBurnerBridge (RootEncoder Single-Encode)
    if (_isNativeStreamRecordingActive && nativeStreamBridge != null) {
      try {
        final stoppedPath = await nativeStreamBridge.stopRecord();
        recordedSourcePath = stoppedPath ?? _activeNativeRecordPath;
      } catch (e) {
        debugPrint('Błąd zatrzymania nagrywania RootEncoder: $e');
        recordedSourcePath = _activeNativeRecordPath;
      }
    } else if (!_isCurrentSessionSimulated &&
        cameraController != null &&
        cameraController.value.isInitialized &&
        cameraController.value.isRecordingVideo) {
      try {
        // Android MediaRecorder wymaga minimum ~1.5s nagrania przed wywołaniem stop(),
        // inaczej natywny koder zwraca błąd -1007 (java.lang.RuntimeException: stop failed).
        if (_recordingStartTime != null) {
          final elapsed = DateTime.now().difference(_recordingStartTime!);
          if (elapsed.inMilliseconds < 1500) {
            await Future.delayed(
              Duration(milliseconds: 1500 - elapsed.inMilliseconds),
            );
          }
        }
        final XFile videoFile = await cameraController.stopVideoRecording();
        recordedSourcePath = videoFile.path;
      } on CameraException catch (e) {
        _currentState = RecordingState.failed;
        _lastErrorMessage =
            'Błąd zapisu pliku wideo przez kamerę: ${e.description ?? e.code}';
        _stateController.add(_currentState);
        return null;
      } catch (e) {
        _currentState = RecordingState.failed;
        _lastErrorMessage = 'Błąd zatrzymania nagrywania sprzętowego: $e';
        _stateController.add(_currentState);
        return null;
      }
    }

    // 1b. Zatrzymanie nagrywania klatek zdalnych (Phone B) i zakodowanie do pliku pośredniego
    final recorder = remoteFrameRecorder ?? _activeRemoteRecorder;
    if (recorder != null && recorder.isRecording) {
      try {
        final encodedPath = await recorder.stopRecordingAndEncode();
        if (encodedPath != null && File(encodedPath).existsSync()) {
          remoteProgramSourcePath = encodedPath;
        }
      } catch (e) {
        debugPrint('Błąd zatrzymania zdalnego nagrywacza: $e');
      } finally {
        if (_ownsRemoteRecorder) {
          _activeRemoteRecorder = null;
          _ownsRemoteRecorder = false;
        }
      }
    }

    final rawFrameRecorder = _activeRawFrameRecorder;
    if (rawFrameRecorder != null && rawFrameRecorder.isRecording) {
      try {
        rawCameraFrameSourcePath = await rawFrameRecorder
            .stopRecordingAndEncode();
      } catch (e) {
        debugPrint('Błąd zatrzymania czystego nagrania Dual: $e');
      }
      if (rawCameraFrameSourcePath == null ||
          !File(rawCameraFrameSourcePath).existsSync()) {
        _currentState = RecordingState.failed;
        _lastErrorMessage =
            'Nie udało się zakodować czystego pliku RAW w trybie Dual.';
        _stateController.add(_currentState);
        await rawFrameRecorder.cancel();
        await recorder?.cancel();
        _activeRawFrameRecorder = null;
        _activeRemoteRecorder = null;
        _ownsRemoteRecorder = false;
        return null;
      }
    }

    if (_activeRecordingType == RecordingType.dual &&
        rawCameraFrameSourcePath != null) {
      recordedSourcePath = rawCameraFrameSourcePath;
    }

    if (recorder != null && remoteProgramSourcePath == null) {
      _currentState = RecordingState.failed;
      _lastErrorMessage =
          'Nie udało się zakodować klatek programu do pliku MP4.'
          '${recorder.lastErrorMessage == null ? '' : ' ${recorder.lastErrorMessage}'}';
      _stateController.add(_currentState);
      await recorder.cancel();
      await rawFrameRecorder?.cancel();
      _activeRemoteRecorder = null;
      _ownsRemoteRecorder = false;
      _activeRawFrameRecorder = null;
      return null;
    }
    if (_activeRecordingType == RecordingType.dual &&
        remoteProgramSourcePath != null &&
        (recordedSourcePath == null ||
            recordedSourcePath == remoteProgramSourcePath)) {
      _currentState = RecordingState.failed;
      _lastErrorMessage =
          'Tryb Dual wymaga dwóch niezależnych źródeł: nagrania kamery RAW i skomponowanego obrazu Program.';
      _stateController.add(_currentState);
      await recorder?.cancel();
      await rawFrameRecorder?.cancel();
      _activeRemoteRecorder = null;
      _ownsRemoteRecorder = false;
      _activeRawFrameRecorder = null;
      return null;
    }
    if (remoteProgramSourcePath != null &&
        (_activeRecordingType != RecordingType.dual ||
            recordedSourcePath == null)) {
      recordedSourcePath = remoteProgramSourcePath;
    }

    if (simulatedDelay) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 2. Finalizacja pliku w dedykowanym katalogu aplikacji
    final targetFolder = storageFolder ?? _activeStorageFolder;
    try {
      final initialType = _activeRecordingType == RecordingType.dual
          ? RecordingType.rawCamera
          : _activeRecordingType;

      var result = await _storageService.finalizeRecording(
        sourcePath: recordedSourcePath,
        duration: _duration,
        isSimulated: _isCurrentSessionSimulated,
        subDirectory: targetFolder,
        recordedOrientation: _activeOrientation,
        recordingType: initialType,
      );
      var scoreboardIncluded = false;

      // In dual mode capture the clean camera master and the already composed
      // widget program independently. This avoids approximating the Flutter HUD.
      if (_activeRecordingType == RecordingType.dual &&
          remoteProgramSourcePath != null &&
          remoteProgramSourcePath != recordedSourcePath) {
        final rawResult = result;
        final programResult = await _storageService.finalizeRecording(
          sourcePath: remoteProgramSourcePath,
          duration: _duration,
          isSimulated: false,
          subDirectory: targetFolder,
          recordedOrientation: _activeOrientation,
          recordingType: RecordingType.programWithScoreboard,
        );
        final programFile = File(programResult.filePath);
        final rawFile = File(rawResult.filePath);
        if (!programFile.existsSync() ||
            programFile.lengthSync() == 0 ||
            !rawFile.existsSync() ||
            rawFile.lengthSync() == 0) {
          _currentState = RecordingState.failed;
          _lastErrorMessage =
              'Tryb Dual nie utworzył poprawnie obu plików RAW i Program.';
          _stateController.add(_currentState);
          return null;
        }
        result = programResult.copyWith(
          recordingType: RecordingType.dual,
          containsScoreboardOverlay: _activeRemoteFramesIncludeProgramOverlay,
          secondaryFilePath: rawResult.filePath,
          secondaryDisplayRelativePath: rawResult.displayPath,
          secondaryFileSizeBytes: rawFile.lengthSync(),
        );
      }

      // 3. Jeśli wybrano tryb z tablicą wyników (programWithScoreboard lub dual),
      // fizycznie wypalamy tablicę wyników i elementy sędziowskie do pliku MP4 przez FFmpeg.
      if (_activeRecordingType == RecordingType.programWithScoreboard ||
          _activeRecordingType == RecordingType.dual) {
        if (_isNativeStreamRecordingActive) {
          // Single-Encode, Dual-Mux: RootEncoder (RtmpCamera2) wstrzykuje i wypala
          // tablicę wyników w locie przez OpenGL ES (ImageObjectFilterRender).
          // Pomiń ciężkie procesorowo wypalanie FFmpeg!
          scoreboardIncluded = true;
        } else if (_activeRemoteFramesIncludeProgramOverlay &&
            remoteProgramSourcePath != null) {
          // The captured program frames already contain the visible scoreboard.
          // Do not paint a second, visually different FFmpeg HUD over them.
          scoreboardIncluded = true;
        } else {
          final sessionToUse = finalSession ?? _startSession;
          if (sessionToUse != null) {
            final tempBurnPath = '${result.filePath}.temp_burn.mp4';
            bool burnSuccess = false;
            try {
              burnSuccess = await _burnerService.burnScoreboardToMp4(
                sourceVideoPath: result.filePath,
                targetVideoPath: tempBurnPath,
                timeline: _sessionTimeline,
                matchSession: sessionToUse,
                duration: _duration,
                style: scoreboardStyle,
                overlayImagePath: overlayImagePath,
                overlayPngBytes: overlayPngBytes,
                isPortrait:
                    _activeOrientation == RecordedVideoOrientation.portrait,
              );

              final tempFile = File(tempBurnPath);
              if (burnSuccess &&
                  tempFile.existsSync() &&
                  tempFile.lengthSync() > 0) {
                scoreboardIncluded = true;
                if (_activeRecordingType == RecordingType.dual) {
                  // W TRYBIE DUAL:
                  // Zachowujemy plik źródłowy jako czysty RAW:
                  final rawPath = result.filePath;
                  final rawFile = File(rawPath);
                  final rawSizeBytes = rawFile.existsSync()
                      ? rawFile.lengthSync()
                      : result.fileSizeBytes;
                  final rawDisplay = result.displayPath;

                  // A plik z wypaloną tablicą zapisujemy jako PROGRAM:
                  final programPath = await _storageService
                      .generateNewRecordingPath(
                        subDirectory: targetFolder,
                        recordingType: RecordingType.programWithScoreboard,
                      );
                  final programDisplay = _storageService.toRelativeDisplayPath(
                    programPath,
                  );

                  try {
                    await tempFile.rename(programPath);
                  } catch (_) {
                    await tempFile.copy(programPath);
                    await tempFile.delete();
                  }

                  final programFile = File(programPath);
                  final programSizeBytes = programFile.existsSync()
                      ? programFile.lengthSync()
                      : 0;

                  // Główny plik to Program REC z tablicą, a plik dodatkowy to czysty RAW
                  result = result.copyWith(
                    filePath: programPath,
                    displayRelativePath: programDisplay,
                    fileSizeBytes: programSizeBytes,
                    recordingType: RecordingType.dual,
                    secondaryFilePath: rawPath,
                    secondaryDisplayRelativePath: rawDisplay,
                    secondaryFileSizeBytes: rawSizeBytes,
                  );
                } else {
                  // W TRYBIE PROGRAM WITH SCOREBOARD:
                  // Podmieniamy plik źródłowy na plik z wypaloną grafiką
                  final originalFile = File(result.filePath);
                  if (await originalFile.exists()) {
                    await originalFile.delete();
                  }
                  try {
                    await tempFile.rename(result.filePath);
                  } catch (_) {
                    await tempFile.copy(result.filePath);
                    await tempFile.delete();
                  }
                }
              } else {
                burnSuccess = false;
              }
            } catch (burnError) {
              debugPrint('VideoOverlayBurner failed: $burnError');
              burnSuccess = false;
            } finally {
              // Upewnij się, że żaden plik tymczasowy nie pozostanie na dysku
              final lingeringTemp = File(tempBurnPath);
              if (lingeringTemp.existsSync()) {
                try {
                  await lingeringTemp.delete();
                } catch (_) {}
              }
            }

            // ŚCISŁE WYMOGI BŁĘDU:
            // Jeśli użytkownik zażądał nagrania z tablicą wyników (Program REC lub Dual),
            // a wypalenie grafiki w FFmpeg się nie powiodło, NIE wolno przedstawiać czystego
            // wideo z plikami JSON/SRT jako sukcesu "Program + Tablica".
            // Oryginalne czyste wideo pozostaje bezpiecznie na dysku, ale stan sesji to failed.
            if (!burnSuccess) {
              await recorder?.cancel();
              _currentState = RecordingState.failed;
              final burnerDetails = _burnerService.lastErrorMessage;
              _lastErrorMessage =
                  (burnerDetails != null && burnerDetails.isNotEmpty)
                  ? 'Wypalanie tablicy wyników nie udało się: $burnerDetails. Czysty plik wideo został zachowany na dysku jako kopia zapasowa.'
                  : 'Wypalanie tablicy wyników do wideo MP4 nie powiodło się (błąd FFmpeg). Czysty plik wideo został zachowany na dysku jako kopia zapasowa.';
              _stateController.add(_currentState);
              await rawFrameRecorder?.cancel();
              _activeRawFrameRecorder = null;
              return null;
            }
          }
        }
      }

      // Zaktualizuj faktyczny rozmiar głównego pliku na dysku
      final finalFile = File(result.filePath);
      final actualSizeBytes = finalFile.existsSync()
          ? finalFile.lengthSync()
          : result.fileSizeBytes;
      final updatedResult = result.copyWith(
        fileSizeBytes: actualSizeBytes,
        containsScoreboardOverlay:
            scoreboardIncluded || result.containsScoreboardOverlay,
      );

      _lastRecordingResult = updatedResult;
      _currentState = RecordingState.saved;
      _stateController.add(_currentState);
      _finishedController.add(updatedResult);
      await recorder?.cancel();
      await rawFrameRecorder?.cancel();
      _activeRawFrameRecorder = null;
      return updatedResult;
    } catch (e) {
      _currentState = RecordingState.failed;
      _lastErrorMessage = 'Nie udało się zapisać lub wypalić pliku MP4: $e';
      _stateController.add(_currentState);
      return null;
    }
  }

  /// Rozpoznaje orientację wideo na podstawie DeviceOrientation z sensora urządzenia
  static RecordedVideoOrientation _resolveOrientation(
    DeviceOrientation? deviceOrientation,
  ) {
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
    _sessionTimeline.clear();
    _startSession = null;
    _recordingStartTime = null;
    _isNativeStreamRecordingActive = false;
    _activeNativeRecordPath = null;
    _stateController.add(_currentState);
    _durationController.add(_duration);
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_activeRemoteRecorder?.cancel());
    unawaited(_activeRawFrameRecorder?.cancel());
    _activeRemoteRecorder = null;
    _activeRawFrameRecorder = null;
    _stateController.close();
    _durationController.close();
    _finishedController.close();
  }
}
