import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Serves concatenated PNG frames to FFmpeg's image2pipe demuxer over loopback.
/// The HTTP stream is local to the device and carries only the program surface.
class ProgramFrameServer {
  HttpServer? _server;
  StreamSubscription<Uint8List>? _frameSubscription;
  HttpResponse? _client;
  Uint8List? _latestFrame;
  Uint8List? _pendingFrame;
  bool _isFlushing = false;

  String? get inputUrl =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}/program.png';

  Future<String> start(Stream<Uint8List> frames, Uint8List initialFrame) async {
    await stop();
    _latestFrame = initialFrame;
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server!.listen((request) async {
      if (request.uri.path != '/program.pam' &&
          request.uri.path != '/program.png' &&
          request.uri.path != '/program.bin') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final response = request.response;
      response.headers.contentType = ContentType('application', 'octet-stream');
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.bufferOutput = false;
      _client = response;
      _pendingFrame = null;
      _isFlushing = false;
      final first = _latestFrame;
      if (first != null) {
        _enqueueFrame(response, first);
      }
      _frameSubscription?.cancel();
      _frameSubscription = frames.listen(
        (frame) {
          _latestFrame = frame;
          if (!identical(_client, response)) return;
          _enqueueFrame(response, frame);
        },
        onError: (_) => _closeClient(response),
        onDone: () => _closeClient(response),
        cancelOnError: true,
      );
      request.response.done.whenComplete(() {
        if (identical(_client, response)) {
          _client = null;
          _pendingFrame = null;
          _isFlushing = false;
        }
      });
    });
    return inputUrl!;
  }

  void _enqueueFrame(HttpResponse response, Uint8List frame) {
    // Overwrite any un-flushed frame so stale frames never accumulate in socket buffers
    _pendingFrame = frame;
    if (!_isFlushing) {
      unawaited(_drainPendingFrames(response));
    }
  }

  Future<void> _drainPendingFrames(HttpResponse response) async {
    if (_isFlushing) return;
    _isFlushing = true;
    try {
      while (_pendingFrame != null && identical(_client, response)) {
        final next = _pendingFrame;
        if (next == null) break;
        _pendingFrame = null;
        response.add(next);
        await response.flush();
      }
    } catch (_) {
      if (identical(_client, response)) {
        _client = null;
        _pendingFrame = null;
      }
    } finally {
      _isFlushing = false;
    }
  }

  void _closeClient(HttpResponse response) {
    if (identical(_client, response)) {
      _client = null;
      _pendingFrame = null;
      _isFlushing = false;
    }
    response.close().catchError((_) {});
  }

  Future<void> stop() async {
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    final client = _client;
    _client = null;
    _pendingFrame = null;
    _isFlushing = false;
    if (client != null) await client.close().catchError((_) {});
    await _server?.close(force: true);
    _server = null;
    _latestFrame = null;
  }
}
