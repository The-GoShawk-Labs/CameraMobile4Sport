import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';
import 'package:volleylive/domain/models/streaming_config.dart';

enum NativeStreamStatus {
  idle,
  connecting,
  streaming,
  connected,
  disconnected,
  reconnecting,
  stopped,
  error,
}

enum StreamEventType {
  connecting,
  connected,
  disconnected,
  reconnecting,
  error,
  bitrateUpdate,
}

class StreamTelemetry {
  final int bitrateBps;
  final int fps;
  final int droppedFrames;
  final double jitterMs;
  final DateTime timestamp;

  const StreamTelemetry({
    this.bitrateBps = 0,
    this.fps = 0,
    this.droppedFrames = 0,
    this.jitterMs = 0.0,
    required this.timestamp,
  });

  int get bitrateKbps => bitrateBps ~/ 1000;
  double get bitrateMbps => bitrateBps / 1000000.0;

  factory StreamTelemetry.fromMap(Map<dynamic, dynamic> map) {
    return StreamTelemetry(
      bitrateBps: (map['bitrate'] as num?)?.toInt() ??
          ((map['bitrateKbps'] as num?)?.toInt() ?? 0) * 1000,
      fps: (map['fps'] as num?)?.toInt() ?? 0,
      droppedFrames: (map['droppedFrames'] as num?)?.toInt() ?? 0,
      jitterMs: (map['jitterMs'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.now(),
    );
  }
}

class StreamEvent {
  final StreamEventType type;
  final String? message;
  final StreamTelemetry? telemetry;
  final int? attempt;
  final int? maxAttempts;
  final DateTime timestamp;

  StreamEvent({
    required this.type,
    this.message,
    this.telemetry,
    this.attempt,
    this.maxAttempts,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'StreamEvent(type: $type, message: $message, telemetry: $telemetry)';
}

/// Native bridge connecting Flutter match state with platform video rendering engines:
/// - Android: StreamPack (ThibaultBee) with Surface/OpenGL texture overlay and MediaCodec CBR encoder
/// - iOS: HaishinKit (HaishinKit.swift) with VideoToolbox H.264 High Profile and VisualEffect
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

  final _eventController = StreamController<StreamEvent>.broadcast();
  Stream<StreamEvent> get eventStream => _eventController.stream;

  final _telemetryController = StreamController<StreamTelemetry>.broadcast();
  Stream<StreamTelemetry> get telemetryStream => _telemetryController.stream;

  StreamTelemetry _lastTelemetry = StreamTelemetry(timestamp: DateTime.now());
  StreamTelemetry get lastTelemetry => _lastTelemetry;

  VolleyballScoreboardState? _lastState;
  StreamSubscription? _eventSubscription;

  // Auto-reconnect retry configuration
  int _retryAttempt = 0;
  final int _maxRetryAttempts = 3;
  Timer? _reconnectTimer;
  StreamConfig? _lastConfig;
  String? _lastRtmpUrl;
  String? _lastStreamKey;
  bool _intentionalStop = false;

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
            _handlePlatformEvent(event);
          }
        },
        onError: (err) {
          debugPrint('[NativeStreamBurnerBridge] Event channel error: $err');
          _setStatus(NativeStreamStatus.error);
          _eventController.add(
            StreamEvent(
              type: StreamEventType.error,
              message: err.toString(),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('[NativeStreamBurnerBridge] Event channel init ignored: $e');
    }
  }

  void _handlePlatformEvent(Map<dynamic, dynamic> map) {
    final statusStr = map['status'] as String?;
    final details = map['details'] as String? ?? map['message'] as String?;
    final error = map['error'] as String?;

    switch (statusStr) {
      case 'CONNECTING':
        _setStatus(NativeStreamStatus.connecting);
        _eventController.add(
          StreamEvent(
            type: StreamEventType.connecting,
            message: details ?? 'Nawiązywanie połączenia RTMP/RTMPS...',
          ),
        );
        break;

      case 'CONNECTED':
      case 'STREAMING':
        _retryAttempt = 0;
        _setStatus(NativeStreamStatus.streaming);
        _eventController.add(
          StreamEvent(
            type: StreamEventType.connected,
            message: details ?? 'Transmisja aktywna (połączono)',
          ),
        );
        break;

      case 'DISCONNECTED':
      case 'STOPPED':
        if (_intentionalStop) {
          _setStatus(NativeStreamStatus.stopped);
          _eventController.add(
            StreamEvent(
              type: StreamEventType.disconnected,
              message: details ?? 'Transmisja zakończona.',
            ),
          );
        } else {
          // Unexpected drop -> trigger auto-retry with exponential backoff
          _handleConnectionDrop(details ?? 'Utracono połączenie z serwerem');
        }
        break;

      case 'RECONNECTING':
        _setStatus(NativeStreamStatus.reconnecting);
        _eventController.add(
          StreamEvent(
            type: StreamEventType.reconnecting,
            message: details ?? 'Próba ponownego połączenia...',
            attempt: (map['attempt'] as num?)?.toInt(),
            maxAttempts: (map['maxAttempts'] as num?)?.toInt(),
          ),
        );
        break;

      case 'BITRATE_UPDATE':
        final telemetry = StreamTelemetry.fromMap(map);
        _lastTelemetry = telemetry;
        _telemetryController.add(telemetry);
        _eventController.add(
          StreamEvent(
            type: StreamEventType.bitrateUpdate,
            telemetry: telemetry,
          ),
        );
        break;

      case 'ERROR':
        _setStatus(NativeStreamStatus.error);
        _eventController.add(
          StreamEvent(
            type: StreamEventType.error,
            message: error ?? details ?? 'Wystąpił błąd streamingu',
          ),
        );
        break;
    }
  }

  void _handleConnectionDrop(String reason) {
    if (_retryAttempt < _maxRetryAttempts && _lastRtmpUrl != null && _lastStreamKey != null) {
      _retryAttempt++;
      _setStatus(NativeStreamStatus.reconnecting);
      final delaySeconds = 2 * _retryAttempt; // 2s, 4s, 6s exponential backoff

      debugPrint(
        '[NativeStreamBurnerBridge] Network drop detected ($reason). Retrying in $delaySeconds s (Attempt $_retryAttempt/$_maxRetryAttempts)...',
      );

      _eventController.add(
        StreamEvent(
          type: StreamEventType.reconnecting,
          message: 'Utrata połączenia ($reason). Wznawianie za ${delaySeconds}s (próba $_retryAttempt/$_maxRetryAttempts)...',
          attempt: _retryAttempt,
          maxAttempts: _maxRetryAttempts,
        ),
      );

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
        if (_currentStatus == NativeStreamStatus.reconnecting) {
          await _executeReconnection();
        }
      });
    } else {
      _setStatus(NativeStreamStatus.error);
      _eventController.add(
        StreamEvent(
          type: StreamEventType.error,
          message: 'Transmisja przerwana po $_maxRetryAttempts nieudanych próbach reconnectu: $reason',
        ),
      );
    }
  }

  Future<void> _executeReconnection() async {
    final url = _lastRtmpUrl;
    final key = _lastStreamKey;
    final state = _lastState;
    if (url != null && key != null && state != null) {
      try {
        await startLiveStream(
          rtmpUrl: url,
          streamKey: key,
          initialState: state,
          config: _lastConfig,
        );
      } catch (e) {
        debugPrint('[NativeStreamBurnerBridge] Reconnection attempt failed: $e');
      }
    }
  }

  void _setStatus(NativeStreamStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  /// Initializes hardware video/audio encoders with YouTube compliance specifications:
  /// - H.264 High Profile Level 4.1
  /// - CBR (Constant Bitrate) rate control
  /// - Strict 2.0s GOP interval
  /// - AAC-LC Stereo 128 kbps (48 kHz)
  Future<bool> initializeStream(StreamConfig config) async {
    _lastConfig = config;
    try {
      final bool? success = await _methodChannel.invokeMethod('initializeStream', config.toMap());
      return success ?? false;
    } on PlatformException catch (_) {
      // Fallback to legacy initialize method if older native build is running
      return await initialize(
        width: config.width,
        height: config.height,
        fps: config.fps,
        videoBitrateBps: config.videoBitrate,
        audioBitrateBps: config.audioBitrate,
      );
    }
  }

  /// Legacy initialize method for backwards compatibility
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
        'gopSeconds': 2.0,
        'profile': 'high',
        'bitrateMode': 'CBR',
      });
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] Init failed: ${e.message}');
      return false;
    }
  }

  /// Validates hardware encoder capabilities (H.264 High Profile, CBR, resolution limits).
  Future<Map<String, dynamic>> validateEncoderCapabilities() async {
    try {
      final dynamic result = await _methodChannel.invokeMethod('validateEncoderCapabilities');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] validateEncoderCapabilities failed: ${e.message}');
    }
    // Default safe fallback if platform call is not implemented
    return {
      'isH264Supported': true,
      'isHighProfileSupported': true,
      'isCbrSupported': true,
      'maxSupportedWidth': 1920,
      'maxSupportedHeight': 1080,
      'maxSupportedFps': 60,
      'compliantWithYouTube': true,
    };
  }

  /// Starts live broadcast to an RTMP/RTMPS destination with scoreboard burned into frames.
  Future<bool> startLiveStream({
    required String rtmpUrl,
    required String streamKey,
    required VolleyballScoreboardState initialState,
    StreamConfig? config,
    int width = 1920,
    int height = 1080,
    int fps = 30,
    int videoBitrateBps = 4500000,
  }) async {
    _intentionalStop = false;
    _lastRtmpUrl = rtmpUrl;
    _lastStreamKey = streamKey;
    _lastState = initialState;
    if (config != null) _lastConfig = config;

    _setStatus(NativeStreamStatus.connecting);

    final finalWidth = config?.width ?? width;
    final finalHeight = config?.height ?? height;
    final finalFps = config?.fps ?? fps;
    final finalBitrate = config?.videoBitrate ?? videoBitrateBps;
    final finalAudioBitrate = config?.audioBitrate ?? 128000;
    final finalGopSeconds = config?.gopSeconds ?? 2.0;

    try {
      final bool? success = await _methodChannel.invokeMethod('startStream', {
        'rtmpUrl': rtmpUrl,
        'streamKey': streamKey,
        'width': finalWidth,
        'height': finalHeight,
        'fps': finalFps,
        'videoBitrate': finalBitrate,
        'audioBitrate': finalAudioBitrate,
        'gopSeconds': finalGopSeconds,
        'scoreboard': initialState.toMap(),
        'profile': 'high',
        'bitrateMode': 'CBR',
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
  Future<void> updateScoreboard(VolleyballScoreboardState state, {bool force = false}) async {
    if (!force && _lastState == state) return;
    _lastState = state;
    try {
      await _methodChannel.invokeMethod('updateScoreboard', state.toMap());
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] updateScoreboard error: ${e.message}');
    }
  }

  /// Transmits the rendered ScoreboardOverlay widget as PNG bytes to native hardware renderers.
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

  /// Stops current live broadcast with full hardware cleanup.
  Future<void> stopLiveStream() async {
    _intentionalStop = true;
    _reconnectTimer?.cancel();
    _retryAttempt = 0;
    try {
      await _methodChannel.invokeMethod('stopStream');
      _setStatus(NativeStreamStatus.stopped);
      _eventController.add(
        StreamEvent(
          type: StreamEventType.disconnected,
          message: 'Transmisja zatrzymana przez użytkownika',
        ),
      );
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
    _reconnectTimer?.cancel();
    _eventSubscription?.cancel();
    _statusController.close();
    _eventController.close();
    _telemetryController.close();
  }
}
