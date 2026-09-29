import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';

enum NativeStreamStatus { idle, connecting, streaming, stopped, error }

/// Native bridge connecting Flutter match state with platform video rendering engines:
/// - Android: StreamPack (ThibaultBee) with Surface/OpenGL texture overlay
/// - iOS: HaishinKit (HaishinKit.swift) with VisualEffect & CoreImage compositing
class NativeStreamBurnerBridge {
  static const MethodChannel _methodChannel =
      MethodChannel('com.goshawk.volleylive/live_stream_bridge');
  static const EventChannel _eventChannel =
      EventChannel('com.goshawk.volleylive/stream_events');

  static final NativeStreamBurnerBridge _instance =
      NativeStreamBurnerBridge._internal();
  factory NativeStreamBurnerBridge() => _instance;

  final _statusController = StreamController<NativeStreamStatus>.broadcast();
  Stream<NativeStreamStatus> get statusStream => _statusController.stream;
  NativeStreamStatus _currentStatus = NativeStreamStatus.idle;
  NativeStreamStatus get currentStatus => _currentStatus;

  VolleyballScoreboardState? _lastState;
  StreamSubscription? _eventSubscription;

  NativeStreamBurnerBridge._internal() {
    _initEventListener();
  }

  void _initEventListener() {
    _eventSubscription?.cancel();
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            final statusStr = event['status'] as String?;
            switch (statusStr) {
              case 'CONNECTING':
                _setStatus(NativeStreamStatus.connecting);
                break;
              case 'STREAMING':
                _setStatus(NativeStreamStatus.streaming);
                break;
              case 'STOPPED':
                _setStatus(NativeStreamStatus.stopped);
                break;
              case 'ERROR':
                _setStatus(NativeStreamStatus.error);
                break;
            }
          }
        },
        onError: (err) {
          debugPrint('[NativeStreamBurnerBridge] Event error: $err');
          _setStatus(NativeStreamStatus.error);
        },
      );
    } catch (e) {
      debugPrint('[NativeStreamBurnerBridge] Event channel init ignored: $e');
    }
  }

  void _setStatus(NativeStreamStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  /// Initializes the hardware encoders and frame modifiers.
  Future<bool> initialize({
    int width = 1920,
    int height = 1080,
    int fps = 30,
    int videoBitrateBps = 4500000,
    int audioBitrateBps = 128000,
  }) async {
    try {
      final bool? success = await _methodChannel.invokeMethod('initialize', {
        'width': width,
        'height': height,
        'fps': fps,
        'videoBitrate': videoBitrateBps,
        'audioBitrate': audioBitrateBps,
      });
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] Init failed: ${e.message}');
      return false;
    }
  }

  /// Starts live broadcast to an RTMP/SRT destination with scoreboard burned into frames.
  Future<bool> startLiveStream({
    required String rtmpUrl,
    required String streamKey,
    required VolleyballScoreboardState initialState,
    int width = 1920,
    int height = 1080,
    int fps = 30,
    int videoBitrateBps = 4500000,
  }) async {
    _setStatus(NativeStreamStatus.connecting);
    _lastState = initialState;
    try {
      final bool? success = await _methodChannel.invokeMethod('startStream', {
        'rtmpUrl': rtmpUrl,
        'streamKey': streamKey,
        'width': width,
        'height': height,
        'fps': fps,
        'videoBitrate': videoBitrateBps,
        'scoreboard': initialState.toMap(),
      });
      if (success == true) {
        _setStatus(NativeStreamStatus.streaming);
        return true;
      } else {
        _setStatus(NativeStreamStatus.error);
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] startLiveStream failed: ${e.message}');
      _setStatus(NativeStreamStatus.error);
      return false;
    }
  }

  /// Updates scoreboard burned into live video frames.
  /// Deduplicated to avoid unnecessary IPC overhead unless [force] is true.
  Future<void> updateScoreboard(VolleyballScoreboardState state, {bool force = false}) async {
    if (!force && _lastState == state) return;
    _lastState = state;
    try {
      debugPrint('[NativeStreamBurnerBridge] updateScoreboard: '
          '${state.teamA} ${state.scoreA}:${state.scoreB} ${state.teamB} '
          '(Set ${state.currentSet}, Sets: ${state.setsA}:${state.setsB}, Serve: ${state.servingTeam}, Toast: "${state.toastMessage}")');
      await _methodChannel.invokeMethod('updateScoreboard', state.toMap());
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] updateScoreboard error: ${e.message}');
    }
  }

  /// Transmits the exact rendered ScoreboardOverlay widget (with theme,
  /// colors, and live event banners) as PNG bytes to native hardware renderers.
  Future<void> updateScoreboardOverlayBitmap({
    required Uint8List bytes,
    required int width,
    required int height,
  }) async {
    try {
      await _methodChannel.invokeMethod('updateScoreboardOverlayBitmap', {
        'bitmapBytes': bytes,
        'width': width,
        'height': height,
      });
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] updateScoreboardOverlayBitmap error: ${e.message}');
    }
  }

  /// Stops current live broadcast.
  Future<void> stopLiveStream() async {
    try {
      await _methodChannel.invokeMethod('stopStream');
      _setStatus(NativeStreamStatus.stopped);
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] stopLiveStream error: ${e.message}');
    }
  }

  /// Switch front/rear camera.
  Future<void> switchCamera() async {
    try {
      await _methodChannel.invokeMethod('switchCamera');
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] switchCamera error: ${e.message}');
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _statusController.close();
  }
}
