import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:volleylive/core/security/secure_storage_service.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/recording_result.dart';
import 'package:volleylive/domain/models/score_event.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/domain/services/recording_service.dart';
import 'package:volleylive/domain/services/program_frame_server.dart';
import 'package:volleylive/domain/services/streaming_service.dart';
import 'package:volleylive/domain/services/video_transport_service.dart';

class StreamerProvider extends ChangeNotifier {
  final VideoTransportService _transportService = VideoTransportService();
  final StreamingService _streamingService = StreamingService();
  final RecordingService _recordingService = RecordingService();

  CameraConnectionState _cameraLinkState = CameraConnectionState.disconnected;
  StreamingState _streamingState = StreamingState.idle;
  RecordingState _programRecState = RecordingState.idle;
  Duration _programRecDuration = Duration.zero;
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
  Duration get programRecDuration => _programRecDuration;
  MasterRecordingResult? get lastProgramRecordingResult =>
      _recordingService.lastRecordingResult;
  String? get programRecordingErrorMessage =>
      _programRecordingOverrideError ?? _recordingService.lastErrorMessage;
  RecordingService get recordingService => _recordingService;
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

    _recordingService.durationStream.listen((duration) {
      _programRecDuration = duration;
      notifyListeners();
    });
  }

  Future<void> _loadSavedCredentials() async {
    if (_destination.credentialReference.isNotEmpty) {
      _maskedStreamKey = SecureStorageService.maskCredential(
        _destination.credentialReference,
      );
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
    final ref = await SecureStorageService.storeCredential(
      credentialValue: rawStreamKey.trim(),
    );
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

  MatchSession? _currentSession;
  StreamSubscription? _scoreEventsSub;
  StreamSubscription? _matchSessionSub;
  ProgramFrameServer? _liveFrameServer;

  MatchSession? get currentSession => _currentSession;

  /// Podłącza strumień zdarzeń z MatchProvider do rejestracji na osi czasu nagrania i streamingu
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
        updateMatchSession(session);
        if (_programRecState == RecordingState.recording) {
          _recordingService.recordTimelineEvent(
            eventType: 'scoreUpdate',
            session: session,
          );
        }
      });
    }
    _scoreEventsSub?.cancel();
    _scoreEventsSub = eventsStream.listen((event) {
      if (sessionStream == null) {
        if (_streamingState == StreamingState.live && _currentSession != null) {
          _streamingService.updateScoreboard(_currentSession!);
        }
        if (_programRecState == RecordingState.recording && _currentSession != null) {
          _recordingService.recordTimelineEvent(
            eventType: event.type.name,
            session: _currentSession!,
          );
        }
      }
    });
  }

  void updateMatchSession(MatchSession session, {String? eventTag}) {
    _currentSession = session;
    if (_streamingState == StreamingState.live || _streamingState == StreamingState.connecting) {
      _streamingService.updateScoreboard(
        session,
        eventTag: eventTag,
        toastMessage: eventTag,
      );
    }
  }

  Future<bool> toggleLiveStream({
    String? inputSource,
    MatchSession? matchSession,
    Stream<Uint8List>? composedFrameStream,
    Uint8List? initialProgramFrame,
  }) async {
    if (matchSession != null) {
      _currentSession = matchSession;
    }
    if (_streamingState == StreamingState.live ||
        _streamingState == StreamingState.connecting) {
      await _streamingService.stopLiveStream();
      await _liveFrameServer?.stop();
      _liveFrameServer = null;
      return false;
    } else {
      if (composedFrameStream == null || initialProgramFrame == null) {
        notifyListeners();
        return false;
      }
      final frameServer = ProgramFrameServer();
      _liveFrameServer = frameServer;
      final frameUrl = await frameServer.start(
        composedFrameStream,
        initialProgramFrame,
      );
      final started = await _streamingService.startLiveStream(
        _destination,
        inputSource: frameUrl,
        inputIsComposedProgramFrames: true,
        timeline: _recordingService.sessionTimeline,
        matchSession: matchSession ?? _currentSession,
      );
      if (!started) {
        await frameServer.stop();
        _liveFrameServer = null;
      }
      return started;
    }
  }

  String? _programRecordingOverrideError;

  Future<void> toggleProgramRecording({
    MatchSession? matchSession,
    Stream<Uint8List>? frameStream,
    Uint8List? initialFrame,
    bool isConnected = true,
    bool isSimulation = false,
    bool framesContainProgramComposition = false,
    double encodingBitrateMbps = 8.0,
    int encodingFps = 30,
    int encodingWidth = 1920,
    int encodingHeight = 1080,
  }) async {
    _programRecordingOverrideError = null;
    if (matchSession != null) {
      _currentSession = matchSession;
    }
    if (_programRecState == RecordingState.recording) {
      await _recordingService.stopRecording(
        finalSession: matchSession ?? _currentSession,
      );
      _programRecState = _recordingService.currentState;
      notifyListeners();
    } else {
      // Weryfikacja dostępności źródła wideo: w trybie Phone B wymagany jest aktywny strumień klatek z Phone A
      if (!isSimulation &&
          (!isConnected || (frameStream == null && initialFrame == null))) {
        _programRecordingOverrideError =
            'Brak aktywnego połączenia z kamerą Phone A lub brak odebranego obrazu wideo. Połącz urządzenia przed rozpoczęciem nagrywania.';
        _programRecState = RecordingState.failed;
        notifyListeners();
        return;
      }

      if (_programRecState != RecordingState.idle) {
        _recordingService.reset();
      }
      await _recordingService.startMasterRecording(
        isSimulation: isSimulation,
        remoteFrameStream: frameStream,
        initialFrame: initialFrame,
        remoteFrameExtension: framesContainProgramComposition ? 'png' : 'jpg',
        remoteFramesIncludeProgramOverlay: framesContainProgramComposition,
        encodingBitrateMbps: encodingBitrateMbps,
        encodingFps: encodingFps,
        encodingWidth: encodingWidth,
        encodingHeight: encodingHeight,
        recordingType: RecordingType.programWithScoreboard,
        initialSession: matchSession ?? _currentSession,
      );
      _programRecState = _recordingService.currentState;
      notifyListeners();
    }
  }

  Future<MasterRecordingResult?> moveLastProgramRecording(
    String targetFolder,
  ) async {
    final last = _recordingService.lastRecordingResult;
    if (last == null) return null;
    final updated = await _recordingService.storageService.moveRecording(
      currentResult: last,
      targetSubDirectory: targetFolder,
    );
    _recordingService.updateLastRecordingResult(updated);
    notifyListeners();
    return updated;
  }

  void simulateDisconnect() {
    _transportService.simulateConnectionDrop();
  }

  @override
  void dispose() {
    _scoreEventsSub?.cancel();
    _matchSessionSub?.cancel();
    _transportService.dispose();
    _streamingService.dispose();
    _recordingService.dispose();
    final server = _liveFrameServer;
    if (server != null) unawaited(server.stop());
    super.dispose();
  }
}
