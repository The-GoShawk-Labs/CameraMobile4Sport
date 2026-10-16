import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Captures only the isolated program surface (camera + scoreboard), never the
/// referee controls or the rest of the application window.
class ProgramWidgetCapture {
  ProgramWidgetCapture({
    required this.boundaryKey,
    this.framesPerSecond = 10,
    this.isSourceAvailable,
  }) : assert(framesPerSecond > 0 && framesPerSecond <= 60);

  final GlobalKey boundaryKey;
  final int framesPerSecond;
  final bool Function()? isSourceAvailable;
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();
  Timer? _timer;
  bool _capturing = false;
  bool _disposed = false;
  Uint8List? _lastFrame;
  double _capturePixelRatio = 1;

  Stream<Uint8List> get frameStream => _frames.stream;
  bool get isCapturing => _timer != null;


  /// Creates a Netpbm PAM (Portable Arbitrary Map) image from raw RGBA bytes.
  /// PAM is supported natively by FFmpeg image2pipe without CPU compression overhead (<0.5ms).
  static Uint8List createPamFrame(int width, int height, Uint8List rawRgba) {
    final headerStr =
        'P7\nWIDTH $width\nHEIGHT $height\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n';
    final headerBytes = Uint8List.fromList(headerStr.codeUnits);
    final totalLength = headerBytes.length + rawRgba.length;
    final pam = Uint8List(totalLength);
    pam.setRange(0, headerBytes.length, headerBytes);
    pam.setRange(headerBytes.length, totalLength, rawRgba);
    return pam;
  }

  Size? _lastCapturedSize;

  Future<Uint8List?> captureFrame({bool reuseLastIfBusy = false}) async {
    if (_disposed || (isSourceAvailable != null && !isSourceAvailable!())) {
      return null;
    }
    if (_capturing) return reuseLastIfBusy ? _lastFrame : null;
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty) {
      return reuseLastIfBusy ? _lastFrame : null;
    }
    if (renderObject.debugNeedsPaint) {
      return reuseLastIfBusy ? _lastFrame : null;
    }
    _capturing = true;
    ui.Image? image;
    try {
      final currentSize = renderObject.size;
      if (_lastCapturedSize == null ||
          _lastCapturedSize!.width != currentSize.width ||
          _lastCapturedSize!.height != currentSize.height ||
          _capturePixelRatio <= 0 ||
          _capturePixelRatio.isNaN) {
        _lastCapturedSize = currentSize;
        const maxIntermediateWidth = 854.0;
        const maxIntermediateHeight = 480.0;
        final desiredRatio = math.min(
          maxIntermediateWidth / currentSize.width,
          maxIntermediateHeight / currentSize.height,
        );
        _capturePixelRatio = calculateEvenPixelRatio(
          currentSize,
          desiredRatio.clamp(1.0, 4.5),
        );
      }

      image = await renderObject.toImage(pixelRatio: _capturePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return _lastFrame;
      _lastFrame = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return _lastFrame;
    } catch (_) {
      return _lastFrame;
    } finally {
      image?.dispose();
      _capturing = false;
    }
  }

  /// Calculates a pixel ratio near [desiredRatio] such that both width and
  /// height rounded to integers are strictly even numbers (divisible by 2).
  /// This eliminates odd dimensions (like 990x557) which cause YUV420p encoder errors.
  static double calculateEvenPixelRatio(Size size, double desiredRatio) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return 1.0;
    }
    final safeDesired = desiredRatio.isFinite && desiredRatio > 0
        ? desiredRatio
        : 1.0;
    double bestRatio = safeDesired;
    double minDiff = double.infinity;
    for (int i = -30; i <= 30; i++) {
      final candidate = safeDesired + (i * 0.002);
      if (candidate < 0.5) continue;
      final w = (size.width * candidate).round();
      final h = (size.height * candidate).round();
      if (w % 2 == 0 && h % 2 == 0 && w > 0 && h > 0) {
        final diff = (candidate - safeDesired).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestRatio = candidate;
        }
      }
    }
    return bestRatio;
  }

  Future<Uint8List?> start({
    int? framesPerSecond,
    int targetWidth = 1920,
    int targetHeight = 1080,
  }) async {
    if (_disposed) return null;
    stop();
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is RenderRepaintBoundary &&
        renderObject.hasSize &&
        !renderObject.size.isEmpty) {
      // Target ~854x480 (or 960x540 max) intermediate capture resolution:
      // crisp vector scoreboard text via FittedBox, <40ms PNG encode time,
      // and locked even dimensions across portrait/landscape/PiP transitions.
      const maxIntermediateWidth = 854.0;
      const maxIntermediateHeight = 480.0;
      final desiredRatio = math.min(
        maxIntermediateWidth / renderObject.size.width,
        maxIntermediateHeight / renderObject.size.height,
      );
      _capturePixelRatio = calculateEvenPixelRatio(
        renderObject.size,
        desiredRatio.clamp(1.0, 4.5),
      );
    }
    var initialFrame = await captureFrame(reuseLastIfBusy: true);
    if (initialFrame == null) {
      await Future<void>.delayed(const Duration(milliseconds: 32));
      initialFrame = await captureFrame(reuseLastIfBusy: true);
    }
    if (initialFrame == null) return null;

    final captureFps = (framesPerSecond ?? this.framesPerSecond).clamp(15, 30);
    final tickIntervalMs = 1000 ~/ captureFps;

    _timer = Timer.periodic(Duration(milliseconds: tickIntervalMs), (_) {
      if (_disposed || _timer == null) return;
      if (isSourceAvailable != null && !isSourceAvailable!()) return;

      if (!_capturing) {
        unawaited(
          captureFrame(reuseLastIfBusy: false).then((freshFrame) {
            if (_disposed || _timer == null || _frames.isClosed) return;
            if (freshFrame != null) {
              _frames.add(freshFrame);
            }
          }),
        );
      }
    });
    return initialFrame;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastCapturedSize = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    stop();
    await _frames.close();
  }
}
