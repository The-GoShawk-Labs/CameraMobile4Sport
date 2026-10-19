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
      bitrateBps:
          (map['bitrate'] as num?)?.toInt() ??
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
  String toString() =>
      'StreamEvent(type: $type, message: $message, telemetry: $telemetry)';
}

/// Native bridge connecting Flutter match state with hardware video rendering engines:
/// - Android: pedroSG94/RootEncoder (RtmpCamera2 + MediaCodec H.264/AAC + OpenGL ImageObjectFilterRender)
/// - iOS: HaishinKit (HaishinKit.swift) with VideoToolbox H.264 High Profile
class NativeStreamBurnerBridge {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.goshawk.volleylive/live_stream_bridge',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.goshawk.volleylive/stream_events',
  );

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
  Map<String, dynamic>? _lastDataMap;
  String _lastAnchorPosition = ScoreboardAnchorPosition.topLeft.name;
  String _lastStyle = ScoreboardThemeStyle.tvProBroadcast.name;
  String get lastStyle => _lastStyle;
  String _lastMatchClock = '';
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
            StreamEvent(type: StreamEventType.error, message: err.toString()),
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
    if (_retryAttempt < _maxRetryAttempts && _lastRtmpUrl != null) {
      _retryAttempt++;
      _setStatus(NativeStreamStatus.reconnecting);
      final delaySeconds = 2 * _retryAttempt;

      debugPrint(
        '[NativeStreamBurnerBridge] Network drop detected ($reason). Retrying in $delaySeconds s (Attempt $_retryAttempt/$_maxRetryAttempts)...',
      );

      _eventController.add(
        StreamEvent(
          type: StreamEventType.reconnecting,
          message:
              'Utrata połączenia ($reason). Wznawianie za ${delaySeconds}s (próba $_retryAttempt/$_maxRetryAttempts)...',
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
          message:
              'Transmisja przerwana po $_maxRetryAttempts nieudanych próbach reconnectu: $reason',
        ),
      );
    }
  }

  Future<void> _executeReconnection() async {
    final url = _lastRtmpUrl;
    final key = _lastStreamKey ?? '';
    final state = _lastState;
    if (url != null) {
      try {
        if (state != null) {
          await startLiveStream(
            rtmpUrl: url,
            streamKey: key,
            initialState: state,
            config: _lastConfig,
          );
        } else {
          final cfg = _lastConfig ?? const StreamConfig();
          await startStream(
            url,
            cfg.width,
            cfg.height,
            cfg.videoBitrate,
            cfg.fps,
            streamKey: key,
            scoreboardData: _lastDataMap,
          );
        }
      } catch (e) {
        debugPrint(
          '[NativeStreamBurnerBridge] Reconnection attempt failed: $e',
        );
      }
    }
  }

  void _setStatus(NativeStreamStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  // ===========================================================================
  // CORE ROOTENCODER METHOD CHANNEL API
  // ===========================================================================

  /// Starts hardware-encoded RTMP/RTMPS stream via RootEncoder (RtmpCamera2 + MediaCodec + OpenGL).
  Future<bool> startStream(
    String rtmpUrl,
    int width,
    int height,
    int bitrate,
    int fps, {
    String? streamKey,
    Map<String, dynamic>? scoreboardData,
    bool? isPortrait,
  }) async {
    _intentionalStop = false;
    _lastRtmpUrl = rtmpUrl;
    _lastStreamKey = streamKey ?? '';
    _setStatus(NativeStreamStatus.connecting);

    final bool portrait = isPortrait ?? (width < height);
    final safeWidth = portrait
        ? ((width > 0 && height > 0 ? (width < height ? width : height) : 1080) & ~1)
        : ((width > 0 && height > 0 ? (width > height ? width : height) : 1920) & ~1);
    final safeHeight = portrait
        ? ((width > 0 && height > 0 ? (width > height ? width : height) : 1920) & ~1)
        : ((width > 0 && height > 0 ? (width < height ? width : height) : 1080) & ~1);
    final safeFps = (fps > 0 ? fps : 30).clamp(15, 60);
    final safeBitrate = bitrate > 0 ? bitrate : 4000000;

    try {
      final bool? success = await _methodChannel.invokeMethod('startStream', {
        'rtmpUrl': rtmpUrl,
        'streamKey': streamKey ?? '',
        'width': safeWidth,
        'height': safeHeight,
        'bitrate': safeBitrate,
        'videoBitrate': safeBitrate,
        'fps': safeFps,
        'audioBitrate': 128000,
        'gopSeconds': 2.0,
        'profile': 'high',
        'bitrateMode': 'CBR',
        'isPortrait': portrait,
        'scoreboard': scoreboardData,
      });
      if (success == true) {
        _setStatus(NativeStreamStatus.streaming);
        return true;
      } else {
        _setStatus(NativeStreamStatus.error);
        return false;
      }
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] startStream failed: ${e.message}');
      _setStatus(NativeStreamStatus.error);
      return false;
    }
  }

  /// Stops active RootEncoder RTMP/RTMPS broadcast and releases hardware MediaCodec & Camera2.
  Future<void> stopStream() async {
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
      debugPrint('[NativeStreamBurnerBridge] stopStream error: ${e.message}');
    }
  }

  /// Pushes updated scoreboard data to native VolleyballScoreboardBitmapRenderer + ImageObjectFilterRender.
  /// Deduplicates identical payloads so OpenGL texture upload occurs ONLY when score or 1s clock changes.
  Future<void> updateScoreboardData(
    Map<String, dynamic> data, {
    bool force = false,
  }) async {
    final merged = Map<String, dynamic>.from(data);
    merged['anchorPosition'] ??= _lastAnchorPosition;
    merged['style'] ??= _lastStyle;
    merged['scoreboardStyle'] ??= _lastStyle;
    if (merged['matchClock'] != null && (merged['matchClock'] as String).isNotEmpty) {
      _lastMatchClock = merged['matchClock'] as String;
    } else if (_lastMatchClock.isNotEmpty) {
      merged['matchClock'] = _lastMatchClock;
    }

    if (!force && _lastDataMap != null && mapEquals(_lastDataMap, merged)) {
      return;
    }
    _lastDataMap = Map<String, dynamic>.from(merged);

    try {
      await _methodChannel.invokeMethod('updateScoreboardData', merged);
    } on PlatformException catch (e) {
      debugPrint(
        '[NativeStreamBurnerBridge] updateScoreboardData error: ${e.message}',
      );
    }
  }

  /// Sets one of the 6 scoreboard anchor positions in OpenGL space:
  /// topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight.
  Future<void> setScoreboardPosition(String position) async {
    final cleanPos = position.trim().isNotEmpty
        ? position.trim()
        : ScoreboardAnchorPosition.topLeft.name;
    _lastAnchorPosition = cleanPos;
    if (_lastState != null) {
      _lastState = _lastState!.copyWith(
        anchorPosition: ScoreboardAnchorPosition.fromName(cleanPos),
      );
    }
    try {
      await _methodChannel.invokeMethod('setScoreboardPosition', {
        'position': cleanPos,
      });
    } on PlatformException catch (e) {
      debugPrint(
        '[NativeStreamBurnerBridge] setScoreboardPosition error: ${e.message}',
      );
    }
  }

  /// Sets active scoreboard theme style in native OpenGL overlay without interrupting stream
  Future<void> setScoreboardStyle(String style) async {
    final cleanStyle = style.trim().isNotEmpty
        ? style.trim()
        : ScoreboardThemeStyle.tvProBroadcast.name;
    _lastStyle = cleanStyle;
    final resolvedEnum = ScoreboardThemeStyle.values.firstWhere(
      (e) => e.name == cleanStyle,
      orElse: () => ScoreboardThemeStyle.tvProBroadcast,
    );
    if (_lastState != null) {
      _lastState = _lastState!.copyWith(style: resolvedEnum);
      await updateScoreboard(_lastState!, force: true);
    } else if (_lastDataMap != null) {
      _lastDataMap!['style'] = cleanStyle;
      _lastDataMap!['scoreboardStyle'] = cleanStyle;
      await updateScoreboardData(_lastDataMap!, force: true);
    }
    try {
      await _methodChannel.invokeMethod('setScoreboardStyle', {
        'style': cleanStyle,
      });
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] setScoreboardStyle error: ${e.message}');
    }
  }

  /// Dynamically updates stream orientation (portrait vs landscape) in native encoder & OpenGL filters.
  Future<void> updateOrientation({required bool isPortrait}) async {
    try {
      await _methodChannel.invokeMethod('updateOrientation', {
        'isPortrait': isPortrait,
      });
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] updateOrientation error: ${e.message}');
    }
  }

  // ===========================================================================
  // COMPATIBILITY WRAPPERS
  // ===========================================================================

  Future<bool> initializeStream(StreamConfig config, {bool? isPortrait}) async {
    _lastConfig = config;
    _lastAnchorPosition = config.anchorPosition.name;
    try {
      final map = config.toMap();
      if (isPortrait != null) {
        map['isPortrait'] = isPortrait;
      }
      final bool? success = await _methodChannel.invokeMethod(
        'initializeStream',
        map,
      );
      return success ?? false;
    } on PlatformException catch (_) {
      return await initialize(
        width: config.width,
        height: config.height,
        fps: config.fps,
        videoBitrateBps: config.videoBitrate,
        audioBitrateBps: config.audioBitrate,
        isPortrait: isPortrait,
      );
    }
  }

  Future<bool> initialize({
    int width = 1920,
    int height = 1080,
    int fps = 30,
    int videoBitrateBps = 4500000,
    int audioBitrateBps = 128000,
    bool? isPortrait,
  }) async {
    final bool portrait = isPortrait ?? (width < height);
    final safeWidth = portrait
        ? ((width > 0 && height > 0 ? (width < height ? width : height) : 1080) & ~1)
        : ((width > 0 && height > 0 ? (width > height ? width : height) : 1920) & ~1);
    final safeHeight = portrait
        ? ((width > 0 && height > 0 ? (width > height ? width : height) : 1920) & ~1)
        : ((width > 0 && height > 0 ? (width < height ? width : height) : 1080) & ~1);

    try {
      final bool? success = await _methodChannel.invokeMethod('initialize', {
        'width': safeWidth,
        'height': safeHeight,
        'fps': fps,
        'videoBitrate': videoBitrateBps,
        'audioBitrate': audioBitrateBps,
        'gopSeconds': 2.0,
        'profile': 'high',
        'bitrateMode': 'CBR',
        'isPortrait': portrait,
      });
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('[NativeStreamBurnerBridge] Init failed: ${e.message}');
      return false;
    }
  }

  Future<Map<String, dynamic>> validateEncoderCapabilities() async {
    try {
      final dynamic result = await _methodChannel.invokeMethod(
        'validateEncoderCapabilities',
      );
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } on PlatformException catch (e) {
      debugPrint(
        '[NativeStreamBurnerBridge] validateEncoderCapabilities failed: ${e.message}',
      );
    }
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

  Future<bool> startLiveStream({
    required String rtmpUrl,
    required String streamKey,
    required VolleyballScoreboardState initialState,
    StreamConfig? config,
    int width = 1920,
    int height = 1080,
    int fps = 30,
    int videoBitrateBps = 4500000,
    bool? isPortrait,
  }) async {
    _lastState = initialState;
    if (config != null) {
      _lastConfig = config;
      _lastAnchorPosition = config.anchorPosition.name;
    }

    final rawW = config?.width ?? width;
    final rawH = config?.height ?? height;
    final bool portrait = isPortrait ?? (rawW < rawH);
    final finalWidth = portrait
        ? ((rawW > 0 && rawH > 0 ? (rawW < rawH ? rawW : rawH) : 1080) & ~1)
        : ((rawW > 0 && rawH > 0 ? (rawW > rawH ? rawW : rawH) : 1920) & ~1);
    final finalHeight = portrait
        ? ((rawW > 0 && rawH > 0 ? (rawW > rawH ? rawW : rawH) : 1920) & ~1)
        : ((rawW > 0 && rawH > 0 ? (rawW < rawH ? rawW : rawH) : 1080) & ~1);
    final finalFps = (config?.fps ?? fps).clamp(15, 60);
    final finalBitrate = config?.videoBitrate ?? videoBitrateBps;

    final effectiveStyle = initialState.style.name != ScoreboardThemeStyle.tvProBroadcast.name
        ? initialState.style
        : (config != null
            ? config.scoreboardStyle
            : ScoreboardThemeStyle.values.firstWhere(
                (s) => s.name == _lastStyle,
                orElse: () => ScoreboardThemeStyle.tvProBroadcast,
              ));
    _lastStyle = effectiveStyle.name;
    final map = initialState.toMap();
    map['anchorPosition'] = _lastAnchorPosition;
    map['style'] = effectiveStyle.name;
    map['scoreboardStyle'] = effectiveStyle.name;
    _lastDataMap = Map<String, dynamic>.from(map);

    return startStream(
      rtmpUrl,
      finalWidth,
      finalHeight,
      finalBitrate,
      finalFps,
      streamKey: streamKey,
      scoreboardData: map,
      isPortrait: portrait,
    );
  }

  Future<void> updateScoreboard(
    VolleyballScoreboardState state, {
    bool force = false,
  }) async {
    String effectiveClock = state.matchClock;
    if (effectiveClock.isNotEmpty) {
      _lastMatchClock = effectiveClock;
    } else if (_lastMatchClock.isNotEmpty) {
      effectiveClock = _lastMatchClock;
    }

    final effectiveStyle = state.style.name != ScoreboardThemeStyle.tvProBroadcast.name
        ? state.style
        : ScoreboardThemeStyle.values.firstWhere(
            (s) => s.name == _lastStyle,
            orElse: () => ScoreboardThemeStyle.tvProBroadcast,
          );
    var effectiveState = state.style == effectiveStyle
        ? state
        : state.copyWith(style: effectiveStyle);
    if (effectiveState.matchClock != effectiveClock) {
      effectiveState = effectiveState.copyWith(matchClock: effectiveClock);
    }

    if (!force && _lastState == effectiveState) return;
    _lastState = effectiveState;
    _lastStyle = effectiveStyle.name;
    final map = effectiveState.toMap();
    map['anchorPosition'] = effectiveState.anchorPosition.name;
    map['style'] = effectiveStyle.name;
    map['scoreboardStyle'] = effectiveStyle.name;
    await updateScoreboardData(map, force: force);
  }

  Future<void> updateScoreboardOverlayBitmap({
    required Uint8List bytes,
    required int width,
    required int height,
    String? anchorPosition,
  }) async {
    if (bytes.isEmpty) return;
    final safeWidth = width > 0 ? width : 360;
    final safeHeight = height > 0 ? height : 76;
    final safeAnchor =
        (anchorPosition != null && anchorPosition.trim().isNotEmpty)
        ? anchorPosition.trim()
        : _lastAnchorPosition;
    try {
      await _methodChannel.invokeMethod('updateScoreboardOverlayBitmap', {
        'bitmapBytes': bytes,
        'width': safeWidth,
        'height': safeHeight,
        'anchorPosition': safeAnchor,
      });
    } on PlatformException catch (e) {
      debugPrint(
        '[NativeStreamBurnerBridge] updateScoreboardOverlayBitmap error: ${e.message}',
      );
    }
  }

  Future<void> stopLiveStream() => stopStream();

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
