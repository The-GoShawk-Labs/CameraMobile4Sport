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

  Future<Uint8List?> captureFrame({bool reuseLastIfBusy = false}) async {
    if (_disposed || (isSourceAvailable != null && !isSourceAvailable!())) {
      return null;
    }
    if (_capturing) return reuseLastIfBusy ? _lastFrame : null;
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty) {
      return null;
    }
    _capturing = true;
    ui.Image? image;
    try {
      image = await renderObject.toImage(pixelRatio: _capturePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      _lastFrame = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return _lastFrame;
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      _capturing = false;
    }
  }

  Future<Uint8List?> start({
    int? framesPerSecond,
    int targetWidth = 1920,
    int targetHeight = 1080,
  }) async {
    if (_disposed) return null;
    stop();
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is RenderRepaintBoundary && renderObject.hasSize) {
      final desiredRatio = math.max(
        targetWidth / renderObject.size.width,
        targetHeight / renderObject.size.height,
      );
      // Balanced pixel ratio: ensures crisp program resolution (up to Full HD)
      // while keeping async PNG readback smooth without stalling the UI thread.
      _capturePixelRatio = desiredRatio.clamp(1.0, 2.75);
    }
    final initialFrame = await captureFrame();
    if (initialFrame == null) return null;
    final captureFps = (framesPerSecond ?? this.framesPerSecond).clamp(1, 60);
    _timer = Timer.periodic(Duration(milliseconds: 1000 ~/ captureFps), (
      _,
    ) async {
      if (isSourceAvailable != null && !isSourceAvailable!()) return;
      final frame = await captureFrame();
      if (frame != null && !_frames.isClosed) _frames.add(frame);
    });
    return initialFrame;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    stop();
    await _frames.close();
  }
}
