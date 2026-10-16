import 'dart:async';
import 'dart:typed_data';

/// Neutralized legacy HTTP PNG frame server.
/// Live RTMP streaming now uses native hardware MediaCodec + OpenGL ES via RootEncoder
/// (NativeStreamBurnerBridge) with zero HTTP loopback or CPU PNG piping overhead.
class ProgramFrameServer {
  String? get inputUrl => null;

  Future<String> start(Stream<Uint8List> frames, Uint8List initialFrame) async {
    // No-op: HTTP loopback frame piping is permanently disabled in favor of RootEncoder OpenGL ES.
    return '';
  }

  Future<void> stop() async {
    // No-op
  }
}
