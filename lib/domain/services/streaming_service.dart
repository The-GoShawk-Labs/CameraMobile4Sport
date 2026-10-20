import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:volleylive/domain/models/connection_state.dart';
import 'package:volleylive/domain/models/streaming_config.dart';

import 'package:volleylive/domain/models/match_recording_metadata.dart';
import 'package:volleylive/domain/models/match_session.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';
import 'package:volleylive/domain/services/native_stream_burner_bridge.dart';
import 'package:volleylive/domain/services/video_overlay_burner_service.dart';

abstract class IStreamingService {
  Stream<StreamingState> get streamingStateStream;
  StreamingState get currentState;
  StreamingDestination get activeDestination;
  StreamConfig get activeConfig;

  Future<bool> startLiveStream(
    StreamingDestination destination, {
    String? inputSource,
    bool inputIsComposedProgramFrames = false,
    List<ScoreTimelineEntry>? timeline,
    MatchSession? matchSession,
    bool? isPortrait,
  });

  Future<bool> startLiveStreamWithConfig(
    StreamConfig config, {
    String? inputSource,
    bool inputIsComposedProgramFrames = false,
    List<ScoreTimelineEntry>? timeline,
    MatchSession? matchSession,
    bool? isPortrait,
  });

  Future<void> stopLiveStream();
  void updateScoreboard(
    MatchSession matchSession, {
    String? eventTag,
    String? toastMessage,
    ScoreboardAnchorPosition? anchorPosition,
    String matchClock = '',
    bool useShortNames = false,
    ScoreboardThemeStyle? style,
  });
  void setScoreboardPosition(ScoreboardAnchorPosition position);
  void setScoreboardStyle(ScoreboardThemeStyle style);
}

/// Serwis nadawania RTMP/RTMPS oparty wyłącznie o sprzętowy enkoder RootEncoder
/// (RtmpCamera2 + MediaCodec H.264/AAC + OpenGL ES ImageObjectFilterRender).
/// Całkowicie omija programowy enkoder FFmpeg (VideoOverlayBurnerService).
class StreamingService implements IStreamingService {
  final VideoOverlayBurnerService _burnerService;
  final NativeStreamBurnerBridge _nativeBridge = NativeStreamBurnerBridge();
  final _stateController = StreamController<StreamingState>.broadcast();
  StreamingState _currentState = StreamingState.idle;
  StreamConfig _activeConfig = const StreamConfig();
  StreamSubscription? _bridgeEventSub;
  String? _lastErrorMessage;

  StreamingService({VideoOverlayBurnerService? burnerService})
    : _burnerService = burnerService ?? VideoOverlayBurnerService() {
    _initBridgeListeners();
  }

  void _initBridgeListeners() {
    _bridgeEventSub = _nativeBridge.eventStream.listen((event) {
      switch (event.type) {
        case StreamEventType.connecting:
          _setState(StreamingState.connecting);
          break;
        case StreamEventType.connected:
          _lastErrorMessage = null;
          _setState(StreamingState.live);
          break;
        case StreamEventType.disconnected:
          if (_currentState == StreamingState.stopping) {
            _setState(StreamingState.stopped);
          } else {
            _setState(StreamingState.idle);
          }
          break;
        case StreamEventType.reconnecting:
          _setState(StreamingState.reconnecting);
          break;
        case StreamEventType.error:
          _lastErrorMessage = event.message;
          _setState(StreamingState.failed);
          break;
        case StreamEventType.bitrateUpdate:
          break;
      }
    });
  }

  @override
  Stream<StreamingState> get streamingStateStream => _stateController.stream;

  @override
  StreamingState get currentState => _currentState;

  @override
  StreamingDestination get activeDestination =>
      _activeConfig.toStreamingDestination();

  @override
  StreamConfig get activeConfig => _activeConfig;

  String? get lastErrorMessage => _lastErrorMessage;

  Stream<StreamTelemetry> get telemetryStream => _nativeBridge.telemetryStream;
  Stream<StreamEvent> get eventStream => _nativeBridge.eventStream;
  NativeStreamBurnerBridge get nativeBridge => _nativeBridge;
  VideoOverlayBurnerService get burnerService => _burnerService;

  @override
  Future<bool> startLiveStream(
    StreamingDestination destination, {
    String? inputSource,
    bool inputIsComposedProgramFrames = false,
    List<ScoreTimelineEntry>? timeline,
    MatchSession? matchSession,
    bool? isPortrait,
  }) {
    return startLiveStreamWithConfig(
      destination.toStreamConfig(),
      inputSource: inputSource,
      inputIsComposedProgramFrames: inputIsComposedProgramFrames,
      timeline: timeline,
      matchSession: matchSession,
      isPortrait: isPortrait,
    );
  }

  @override
  Future<bool> startLiveStreamWithConfig(
    StreamConfig config, {
    String? inputSource,
    bool inputIsComposedProgramFrames = false,
    List<ScoreTimelineEntry>? timeline,
    MatchSession? matchSession,
    bool? isPortrait,
  }) async {
    _activeConfig = config;
    _setState(StreamingState.preparing);

    if (config.serverUrl.trim().isEmpty) {
      debugPrint('[StreamingService] Server URL is empty');
      _lastErrorMessage =
          'Brak adresu serwera RTMP. Skonfiguruj punkt końcowy w Ustawieniach RTMP.';
      _setState(StreamingState.failed);
      return false;
    }

    final resolvedStreamKey = await config.resolveEffectiveStreamKey();
    if (config.requiresStreamKey && resolvedStreamKey.isEmpty) {
      debugPrint(
        '[StreamingService] Stream key required but could not be resolved',
      );
      _lastErrorMessage =
          'Wymagany klucz transmisji dla platformy ${config.preset.label}. Wprowadź klucz w Ustawieniach RTMP przed rozpoczęciem LIVE.';
      _setState(StreamingState.failed);
      return false;
    }

    _setState(StreamingState.connecting);

    // Bezpośrednie uruchomienie sprzętowego potoku RootEncoder (MediaCodec + OpenGL ES)
    final initialState = matchSession != null
        ? VolleyballScoreboardState.fromMatchSession(
            matchSession,
            anchorPosition: config.anchorPosition,
            style: config.scoreboardStyle,
          )
        : VolleyballScoreboardState(
            teamA: 'TEAM A',
            teamB: 'TEAM B',
            scoreA: 0,
            scoreB: 0,
            currentSet: 1,
            setsA: 0,
            setsB: 0,
            anchorPosition: config.anchorPosition,
            style: config.scoreboardStyle,
          );

    await _nativeBridge.setScoreboardPosition(config.anchorPosition.name);
    await _nativeBridge.setScoreboardStyle(config.scoreboardStyle.name);
    await _nativeBridge.ensurePreviewTextureId();

    final fullRtmpUrl = VideoOverlayBurnerService.buildRtmpEndpoint(
      config.serverUrl,
      resolvedStreamKey,
    );

    final hardwareStarted = await _nativeBridge.startStream(
      fullRtmpUrl,
      config.width,
      config.height,
      config.videoBitrate,
      config.fps,
      streamKey: resolvedStreamKey,
      scoreboardData: initialState.toMap(),
      isPortrait: isPortrait,
    );

    if (hardwareStarted) {
      _lastErrorMessage = null;
      _setState(StreamingState.live);
      return true;
    }

    _lastErrorMessage =
        'Nie udało się uruchomić sprzętowego enkodera RootEncoder (MediaCodec). Sprawdź punkt końcowy RTMP i uprawnienia kamery/mikrofonu.';
    _setState(StreamingState.failed);
    return false;
  }

  String _lastMatchClock = '';

  @override
  void updateScoreboard(
    MatchSession matchSession, {
    String? eventTag,
    String? toastMessage,
    ScoreboardAnchorPosition? anchorPosition,
    String matchClock = '',
    bool useShortNames = false,
    ScoreboardThemeStyle? style,
  }) {
    if (matchClock.isNotEmpty) {
      _lastMatchClock = matchClock;
    } else if (_lastMatchClock.isNotEmpty) {
      matchClock = _lastMatchClock;
    }
    final state = VolleyballScoreboardState.fromMatchSession(
      matchSession,
      eventTag: eventTag,
      toastMessage: toastMessage,
      anchorPosition: anchorPosition ?? _activeConfig.anchorPosition,
      matchClock: matchClock,
      useShortNames: useShortNames,
      style: style ?? _activeConfig.scoreboardStyle,
    );
    _nativeBridge.updateScoreboard(state);
  }

  @override
  void setScoreboardPosition(ScoreboardAnchorPosition position) {
    _activeConfig = _activeConfig.copyWith(anchorPosition: position);
    _nativeBridge.setScoreboardPosition(position.name);
  }

  @override
  void setScoreboardStyle(ScoreboardThemeStyle style) {
    _activeConfig = _activeConfig.copyWith(scoreboardStyle: style);
    _nativeBridge.setScoreboardStyle(style.name);
  }

  @override
  Future<void> stopLiveStream() async {
    if (_currentState != StreamingState.live &&
        _currentState != StreamingState.connecting &&
        _currentState != StreamingState.reconnecting) {
      return;
    }

    _setState(StreamingState.stopping);
    await _nativeBridge.stopStream();
    await Future.delayed(const Duration(milliseconds: 150));
    _setState(StreamingState.stopped);
  }

  void simulateInternetDrop() {
    if (_currentState == StreamingState.live) {
      _setState(StreamingState.reconnecting);
    }
  }

  void _setState(StreamingState state) {
    _currentState = state;
    _stateController.add(state);
  }

  void dispose() {
    _bridgeEventSub?.cancel();
    _stateController.close();
  }
}
