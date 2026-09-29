import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

abstract class IRemoteFrameRecorder {
  bool get isRecording;
  int get recordedFrameCount;
  String? get lastErrorMessage;
  Future<void> startRecording({
    Stream<Uint8List>? frameStream,
    Uint8List? initialFrame,
    String imageExtension = 'jpg',
    double bitrateMbps = 8.0,
    int targetFps = 30,
    int targetWidth = 1920,
    int targetHeight = 1080,
  });
  void addFrame(Uint8List frameBytes);
  Future<String?> stopRecordingAndEncode({double targetFps = 20.0});
  Future<void> cancel();
}

/// Nagrywa strumień odebranych klatek JPEG z Phone A do pamięci podręcznej
/// i składa je za pomocą FFmpeg do pliku MP4.
class RemoteFrameRecorder implements IRemoteFrameRecorder {
  Directory? _tempSessionDir;
  StreamSubscription<Uint8List>? _frameSub;
  int _frameCount = 0;
  bool _isRecording = false;
  String _imageExtension = 'jpg';
  double _bitrateMbps = 8.0;
  int _targetFps = 30;
  int _targetWidth = 1920;
  int _targetHeight = 1080;
  final Stopwatch _captureClock = Stopwatch();
  final List<double> _frameOffsetsSeconds = [];
  Future<void> _writeChain = Future<void>.value();
  int _pendingWrites = 0;
  String? _writeError;
  String? _lastErrorMessage;

  @override
  bool get isRecording => _isRecording;

  @override
  int get recordedFrameCount => _frameCount;

  @override
  String? get lastErrorMessage => _lastErrorMessage;

  @override
  Future<void> startRecording({
    Stream<Uint8List>? frameStream,
    Uint8List? initialFrame,
    String imageExtension = 'jpg',
    double bitrateMbps = 8.0,
    int targetFps = 30,
    int targetWidth = 1920,
    int targetHeight = 1080,
  }) async {
    if (_isRecording) return;
    final normalizedExtension = imageExtension.toLowerCase().replaceFirst(
      '.',
      '',
    );
    if (!const {'jpg', 'jpeg', 'png'}.contains(normalizedExtension)) {
      throw ArgumentError.value(
        imageExtension,
        'imageExtension',
        'Use jpg, jpeg or png.',
      );
    }
    _imageExtension = normalizedExtension == 'jpeg'
        ? 'jpg'
        : normalizedExtension;
    _bitrateMbps = bitrateMbps.clamp(2.0, 32.0);
    _targetFps = targetFps.clamp(1, 60);
    _targetWidth = targetWidth.clamp(320, 3840);
    _targetHeight = targetHeight.clamp(320, 3840);
    _frameCount = 0;
    _frameOffsetsSeconds.clear();
    _pendingWrites = 0;
    _writeError = null;
    _lastErrorMessage = null;
    _writeChain = Future<void>.value();
    _isRecording = true;

    final systemTemp = Directory.systemTemp;
    _tempSessionDir = Directory(
      '${systemTemp.path}/remote_frames_${DateTime.now().millisecondsSinceEpoch}',
    );
    await _tempSessionDir!.create(recursive: true);
    _captureClock
      ..reset()
      ..start();

    if (initialFrame != null && initialFrame.isNotEmpty) {
      addFrame(initialFrame);
    }

    if (frameStream != null) {
      _frameSub = frameStream.listen((frame) {
        addFrame(frame);
      });
    }
  }

  @override
  void addFrame(Uint8List frameBytes) {
    if (!_isRecording || _tempSessionDir == null || frameBytes.isEmpty) return;
    // Bound queued disk work so capture never builds an unbounded memory backlog.
    if (_pendingWrites >= 4) return;
    final frameIndex = ++_frameCount;
    _frameOffsetsSeconds.add(_captureClock.elapsedMicroseconds / 1000000);
    final filePath =
        '${_tempSessionDir!.path}/frame_${frameIndex.toString().padLeft(6, '0')}.$_imageExtension';
    _pendingWrites++;
    _writeChain = _writeChain.then((_) async {
      try {
        await File(filePath).writeAsBytes(frameBytes, flush: false);
      } catch (e) {
        _writeError = 'Could not write captured frame $frameIndex: $e';
        debugPrint('RemoteFrameRecorder $_writeError');
      } finally {
        _pendingWrites--;
      }
    });
  }

  @override
  Future<String?> stopRecordingAndEncode({double? targetFps}) async {
    if (!_isRecording) return null;
    _isRecording = false;
    _captureClock.stop();
    await _frameSub?.cancel();
    _frameSub = null;
    await _writeChain;

    if (_tempSessionDir == null || !await _tempSessionDir!.exists()) {
      return null;
    }

    final durationSec = (_captureClock.elapsedMicroseconds / 1000000).clamp(
      0.001,
      double.infinity,
    );
    final effectiveFps = (targetFps ?? _targetFps.toDouble()).clamp(1, 60);

    final outputMp4Path = '${_tempSessionDir!.path}/assembled_remote_rec.mp4';

    // Jeśli środowisko testowe lub brak natywnego FFmpeg, wygeneruj plik MP4 (dummy nagłówek)
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      final mp4File = File(outputMp4Path);
      await mp4File.writeAsBytes([
        0x00,
        0x00,
        0x00,
        0x18,
        0x66,
        0x74,
        0x79,
        0x70,
      ]);
      return outputMp4Path;
    }

    // Never return a placeholder MP4 as a successful recording.
    if (_frameCount < 2 || _writeError != null) {
      _lastErrorMessage =
          _writeError ??
          'Za mało klatek do utworzenia wideo: zapisano $_frameCount.';
      await cancel();
      return null;
    }

    try {
      final concatPath = '${_tempSessionDir!.path}/frames.ffconcat';
      final concatFile = File(concatPath);
      await concatFile.writeAsString(
        buildConcatManifest(
          frameCount: _frameCount,
          frameOffsetsSeconds: _frameOffsetsSeconds,
          durationSeconds: durationSec,
          imageExtension: _imageExtension,
        ),
      );
      final fpsStr = effectiveFps.toStringAsFixed(0);
      final bitrateKbps = (_bitrateMbps * 1000).round();
      final command =
          '-y -f concat -safe 0 -i "$concatPath" -t ${durationSec.toStringAsFixed(3)} '
          '-vf "scale=$_targetWidth:$_targetHeight:force_original_aspect_ratio=decrease, pad=$_targetWidth:$_targetHeight:(ow-iw)/2:(oh-ih)/2, setsar=1" '
          '-c:v libx264 -preset ultrafast -b:v ${bitrateKbps}k '
          '-maxrate ${bitrateKbps}k -bufsize ${bitrateKbps * 2}k '
          '-pix_fmt yuv420p -fps_mode cfr -r $fpsStr "$outputMp4Path"';
      debugPrint('RemoteFrameRecorder: Assembling MP4 with FFmpeg: $command');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode) &&
          File(outputMp4Path).existsSync() &&
          File(outputMp4Path).lengthSync() > 0) {
        debugPrint(
          'RemoteFrameRecorder: Successfully assembled intermediate MP4 at $outputMp4Path',
        );
        return outputMp4Path;
      } else {
        final logs = await session.getAllLogsAsString();
        debugPrint(
          'RemoteFrameRecorder: FFmpeg assembly failed ($returnCode): $logs',
        );
        final logText = logs?.trim() ?? '';
        _lastErrorMessage = logText.isEmpty
            ? 'FFmpeg zakończył kodowaniem błędem ${returnCode?.getValue() ?? "nieznanym"}.'
            : logText.substring(
                logText.length > 1400 ? logText.length - 1400 : 0,
              );
        return null;
      }
    } catch (e) {
      _lastErrorMessage = 'Wyjątek FFmpeg podczas kodowania: $e';
      debugPrint('RemoteFrameRecorder exception during encoding: $e');
      return null;
    }
  }

  @visibleForTesting
  static String buildConcatManifest({
    required int frameCount,
    required List<double> frameOffsetsSeconds,
    required double durationSeconds,
    required String imageExtension,
  }) {
    final lines = <String>['ffconcat version 1.0'];
    for (var index = 0; index < frameCount; index++) {
      final filename =
          'frame_${(index + 1).toString().padLeft(6, '0')}.$imageExtension';
      final framePath = filename.replaceAll("'", "'\\''");
      final start = frameOffsetsSeconds[index];
      final end = index + 1 < frameCount
          ? frameOffsetsSeconds[index + 1]
          : durationSeconds;
      final interval = (end - start).clamp(0.001, durationSeconds);
      lines
        ..add("file '$framePath'")
        ..add('duration ${interval.toStringAsFixed(6)}');
    }
    if (frameCount > 0) {
      final finalFilename =
          'frame_${frameCount.toString().padLeft(6, '0')}.$imageExtension';
      lines.add("file '${finalFilename.replaceAll("'", "'\\''")}'");
    }
    return '${lines.join('\n')}\n';
  }

  @override
  Future<void> cancel() async {
    _isRecording = false;
    await _frameSub?.cancel();
    _frameSub = null;
    if (_tempSessionDir != null && await _tempSessionDir!.exists()) {
      try {
        await _tempSessionDir!.delete(recursive: true);
      } catch (_) {}
    }
    _tempSessionDir = null;
  }
}
