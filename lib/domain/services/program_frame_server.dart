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
      if (request.uri.path != '/program.png') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final response = request.response;
      response.headers.contentType = ContentType('application', 'octet-stream');
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.bufferOutput = false;
      _client = response;
      final first = _latestFrame;
      if (first != null) response.add(first);
      _frameSubscription?.cancel();
      _frameSubscription = frames.listen(
        (frame) {
          _latestFrame = frame;
          if (!identical(_client, response)) return;
          try {
            response.add(frame);
          } catch (_) {
            _client = null;
          }
        },
        onError: (_) => _closeClient(response),
        onDone: () => _closeClient(response),
        cancelOnError: true,
      );
      request.response.done.whenComplete(() {
        if (identical(_client, response)) _client = null;
      });
    });
    return inputUrl!;
  }

  void _closeClient(HttpResponse response) {
    if (identical(_client, response)) _client = null;
    response.close().catchError((_) {});
  }

  Future<void> stop() async {
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    final client = _client;
    _client = null;
    if (client != null) await client.close().catchError((_) {});
    await _server?.close(force: true);
    _server = null;
    _latestFrame = null;
  }
}
