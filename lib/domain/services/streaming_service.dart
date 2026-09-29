import 'dart:async';
import 'package:volleylive/core/security/secure_storage_service.dart';
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

  Future<bool> startLiveStream(
    StreamingDestination destination, {
    String? inputSource,
    bool inputIsComposedProgramFrames = false,
    List<ScoreTimelineEntry>? timeline,
    MatchSession? matchSession,
  });
  Future<void> stopLiveStream();
  void updateScoreboard(MatchSession matchSession, {String? eventTag, String? toastMessage});
}

/// Serwis nadawania RTMPS (YouTube, Meta, Generic RTMPS)
class StreamingService implements IStreamingService {
  final VideoOverlayBurnerService _burnerService;
  final NativeStreamBurnerBridge _nativeBridge = NativeStreamBurnerBridge();
  final _stateController = StreamController<StreamingState>.broadcast();
  StreamingState _currentState = StreamingState.idle;
  StreamingDestination _activeDestination = const StreamingDestination();
  bool _usingNativeHardwareStream = false;

  StreamingService({VideoOverlayBurnerService? burnerService})
    : _burnerService = burnerService ?? VideoOverlayBurnerService();

  @override
  Stream<StreamingState> get streamingStateStream => _stateController.stream;

  @override
  StreamingState get currentState => _currentState;

  @override
  StreamingDestination get activeDestination => _activeDestination;

  VideoOverlayBurnerService get burnerService => _burnerService;

  @override
  Future<bool> startLiveStream(
    StreamingDestination destination, {
    String? inputSource,
    bool inputIsComposedProgramFrames = false,
    List<ScoreTimelineEntry>? timeline,
    MatchSession? matchSession,
  }) async {
    _activeDestination = destination;
    _setState(StreamingState.preparing);

    if (destination.serverUrl.trim().isEmpty ||
        destination.credentialReference.isEmpty) {
      _setState(StreamingState.failed);
      return false;
    }

    // Bezpieczna walidacja klucza streamingu w Secure Storage
    String resolvedStreamKey = '';
    if (destination.credentialReference.isNotEmpty) {
      final key = await SecureStorageService.getCredential(
        destination.credentialReference,
      );
      if (key == null || key.isEmpty) {
        _setState(StreamingState.failed);
        return false;
      }
      resolvedStreamKey = key;
    }

    _setState(StreamingState.connecting);

    if (inputIsComposedProgramFrames &&
        inputSource != null &&
        inputSource.isNotEmpty) {
      final success = await _burnerService.startLiveBroadcastFromProgramFrames(
        inputUrl: inputSource,
        rtmpUrl: destination.serverUrl,
        streamKey: resolvedStreamKey,
        bitrateKbps: destination.bitrateKbps,
      );
      if (!success) {
        _setState(StreamingState.failed);
        return false;
      }
      _setState(StreamingState.live);
      return true;
    }

    // 1. Priorytet: Bezpośrednie, akcelerowane sprzętowo wypalanie klatek (StreamPack / HaishinKit)
    if (matchSession != null) {
      final nativeState =
          VolleyballScoreboardState.fromMatchSession(matchSession);
      final hardwareStarted = await _nativeBridge.startLiveStream(
        rtmpUrl: destination.serverUrl,
        streamKey: resolvedStreamKey,
        initialState: nativeState,
        videoBitrateBps: destination.bitrateKbps * 1000,
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
        rtmpUrl: destination.serverUrl,
        streamKey: resolvedStreamKey,
        timeline: timeline ?? const [],
        matchSession: matchSession,
        bitrateKbps: destination.bitrateKbps,
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
    if (_currentState == StreamingState.live || _currentState == StreamingState.connecting || _currentState == StreamingState.preparing) {
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
        _currentState != StreamingState.connecting) {
      return;
    }

    _setState(StreamingState.stopping);
    if (_usingNativeHardwareStream) {
      await _nativeBridge.stopLiveStream();
      _usingNativeHardwareStream = false;
    }
    await _burnerService.stopLiveBroadcast();
    await Future.delayed(const Duration(milliseconds: 500));
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
    _stateController.close();
  }
}
