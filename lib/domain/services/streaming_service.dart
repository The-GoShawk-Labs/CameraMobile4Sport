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
  });

  Future<bool> startLiveStreamWithConfig(
    StreamConfig config, {
    String? inputSource,
    bool inputIsComposedProgramFrames = false,
    List<ScoreTimelineEntry>? timeline,
    MatchSession? matchSession,
  });

  Future<void> stopLiveStream();
  void updateScoreboard(MatchSession matchSession, {String? eventTag, String? toastMessage});
}

/// Serwis nadawania RTMP/RTMPS (YouTube Live, Meta, Generic RTMP/RTMPS)
class StreamingService implements IStreamingService {
  final VideoOverlayBurnerService _burnerService;
  final NativeStreamBurnerBridge _nativeBridge = NativeStreamBurnerBridge();
  final _stateController = StreamController<StreamingState>.broadcast();
  StreamingState _currentState = StreamingState.idle;
  StreamConfig _activeConfig = const StreamConfig();
  bool _usingNativeHardwareStream = false;
  StreamSubscription? _bridgeEventSub;
  String? _lastErrorMessage;

  StreamingService({VideoOverlayBurnerService? burnerService})
    : _burnerService = burnerService ?? VideoOverlayBurnerService() {
    _initBridgeListeners();
    _burnerService.onStreamError = (error) {
      _lastErrorMessage = error;
      _setState(StreamingState.failed);
    };
  }

  void _initBridgeListeners() {
    _bridgeEventSub = _nativeBridge.eventStream.listen((event) {
      switch (event.type) {
        case StreamEventType.connecting:
          _setState(StreamingState.connecting);
          break;
        case StreamEventType.connected:
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
          _setState(StreamingState.failed);
          break;
        case StreamEventType.bitrateUpdate:
          // Keep current state, telemetry is emitted via telemetryStream
          break;
      }
    });
  }

  @override
  Stream<StreamingState> get streamingStateStream => _stateController.stream;

  @override
  StreamingState get currentState => _currentState;

  @override
  StreamingDestination get activeDestination => _activeConfig.toStreamingDestination();

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
  }) {
    return startLiveStreamWithConfig(
      destination.toStreamConfig(),
      inputSource: inputSource,
      inputIsComposedProgramFrames: inputIsComposedProgramFrames,
      timeline: timeline,
      matchSession: matchSession,
    );
  }

  @override
  Future<bool> startLiveStreamWithConfig(
    StreamConfig config, {
    String? inputSource,
    bool inputIsComposedProgramFrames = false,
    List<ScoreTimelineEntry>? timeline,
    MatchSession? matchSession,
  }) async {
    _activeConfig = config;
    _setState(StreamingState.preparing);

    if (config.serverUrl.trim().isEmpty) {
      debugPrint('[StreamingService] Server URL is empty');
      _lastErrorMessage = 'Brak adresu serwera RTMP. Skonfiguruj punkt końcowy w Ustawieniach RTMP.';
      _setState(StreamingState.failed);
      return false;
    }

    // Bezpieczne pobranie klucza streamingu z pamięci bezpiecznej Keystore / Keychain
    final resolvedStreamKey = await config.resolveEffectiveStreamKey();
    if (config.requiresStreamKey && resolvedStreamKey.isEmpty) {
      debugPrint('[StreamingService] Stream key required but could not be resolved');
      _lastErrorMessage =
          'Wymagany klucz transmisji dla platformy ${config.preset.label}. Wprowadź klucz w Ustawieniach RTMP przed rozpoczęciem LIVE.';
      _setState(StreamingState.failed);
      return false;
    }

    _setState(StreamingState.connecting);

    if (inputIsComposedProgramFrames &&
        inputSource != null &&
        inputSource.isNotEmpty) {
      final success = await _burnerService.startLiveBroadcastFromProgramFrames(
        inputUrl: inputSource,
        rtmpUrl: config.serverUrl,
        streamKey: resolvedStreamKey,
        width: config.width,
        height: config.height,
        bitrateKbps: config.videoBitrateKbps,
        fps: (config.fps > 0 ? config.fps : 24).clamp(15, 30),
        audioSampleRate: config.audioSampleRate,
      );
      if (!success) {
        _lastErrorMessage = _burnerService.lastErrorMessage ??
            'Nie udało się uruchomić procesu nadawania strumienia (FFmpeg). Sprawdź czy serwer docelowy RTMP jest osiągalny.';
        _setState(StreamingState.failed);
        return false;
      }
      _lastErrorMessage = null;
      _setState(StreamingState.live);
      return true;
    }

    // 1. Priorytet: Bezpośrednie, akcelerowane sprzętowo wypalanie klatek (StreamPack / HaishinKit)
    if (matchSession != null) {
      final nativeState =
          VolleyballScoreboardState.fromMatchSession(matchSession);

      // Inicjalizacja sprzętowego enkodera (MediaCodec CBR / VideoToolbox H.264 High Profile)
      await _nativeBridge.initializeStream(config);

      final hardwareStarted = await _nativeBridge.startLiveStream(
        rtmpUrl: config.serverUrl,
        streamKey: resolvedStreamKey,
        initialState: nativeState,
        config: config,
        width: config.width,
        height: config.height,
        fps: config.fps,
        videoBitrateBps: config.videoBitrate,
      );
      if (hardwareStarted) {
        _usingNativeHardwareStream = true;
        _setState(StreamingState.live);
        return true;
      }
    }

    // 2. Fallback: Jeśli podano źródło strumienia wideo (plik wideo, rtp, pipe),
    // uruchom streaming przez FFmpeg z filtrem programowym
    if (inputSource != null && inputSource.isNotEmpty && matchSession != null) {
      final success = await _burnerService.startLiveBroadcastWithOverlay(
        inputSource: inputSource,
        rtmpUrl: config.serverUrl,
        streamKey: resolvedStreamKey,
        timeline: timeline ?? const [],
        matchSession: matchSession,
        width: config.width,
        height: config.height,
        bitrateKbps: config.videoBitrateKbps,
        fps: (config.fps > 0 ? config.fps : 15).clamp(10, 30),
      );
      if (!success) {
        _setState(StreamingState.failed);
        return false;
      }
    } else {
      _setState(StreamingState.failed);
      return false;
    }

    _setState(StreamingState.live);
    return true;
  }

  @override
  void updateScoreboard(MatchSession matchSession, {String? eventTag, String? toastMessage}) {
    if (_currentState == StreamingState.live ||
        _currentState == StreamingState.connecting ||
        _currentState == StreamingState.preparing) {
      _nativeBridge.updateScoreboard(
        VolleyballScoreboardState.fromMatchSession(
          matchSession,
          eventTag: eventTag,
          toastMessage: toastMessage,
        ),
      );
    }
  }

  @override
  Future<void> stopLiveStream() async {
    if (_currentState != StreamingState.live &&
        _currentState != StreamingState.connecting &&
        _currentState != StreamingState.reconnecting) {
      return;
    }

    _setState(StreamingState.stopping);
    if (_usingNativeHardwareStream) {
      await _nativeBridge.stopLiveStream();
      _usingNativeHardwareStream = false;
    }
    await _burnerService.stopLiveBroadcast();
    await Future.delayed(const Duration(milliseconds: 300));
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
