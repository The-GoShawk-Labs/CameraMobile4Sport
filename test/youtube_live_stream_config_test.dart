import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';
import 'package:volleylive/domain/models/streaming_config.dart';
import 'package:volleylive/domain/services/native_stream_burner_bridge.dart';
import 'package:volleylive/domain/services/streaming_service.dart';
import 'package:volleylive/domain/services/video_overlay_burner_service.dart';
import 'package:volleylive/presentation/providers/streamer_provider.dart';
import 'package:volleylive/presentation/screens/settings/stream_settings_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('YouTube Live Presets & Technical Compliance Specifications', () {
    test('Preset 1080p60 strictly conforms to YouTube specifications', () {
      const preset = YouTubeLivePreset.youtube1080p60;
      expect(preset.width, 1920);
      expect(preset.height, 1080);
      expect(preset.fps, 60);
      expect(preset.videoBitrateKbps, 8000);
      expect(preset.minBitrateKbps, 6000);
      expect(preset.maxBitrateKbps, 9000);
      expect(preset.audioBitrateKbps, 128);
      expect(preset.gopSeconds, 2.0);

      final config = StreamConfig.fromPreset(preset);
      expect(config.videoBitrate, 8000000);
      expect(config.audioBitrate, 128000);
      expect(config.audioSampleRate, 48000);
      expect(config.audioChannels, 2);
      expect(config.isYouTubeCompliant, isTrue);
      expect(config.complianceIssues, isEmpty);
    });

    test('Preset 1080p30 strictly conforms to YouTube specifications', () {
      const preset = YouTubeLivePreset.youtube1080p30;
      expect(preset.width, 1920);
      expect(preset.height, 1080);
      expect(preset.fps, 30);
      expect(preset.videoBitrateKbps, 4500);
      expect(preset.minBitrateKbps, 3000);
      expect(preset.maxBitrateKbps, 6000);
      expect(preset.audioBitrateKbps, 128);
      expect(preset.gopSeconds, 2.0);

      final config = StreamConfig.fromPreset(preset);
      expect(config.videoBitrate, 4500000);
      expect(config.isYouTubeCompliant, isTrue);
      expect(config.complianceIssues, isEmpty);
    });

    test('Preset 720p60 strictly conforms to YouTube specifications', () {
      const preset = YouTubeLivePreset.youtube720p60;
      expect(preset.width, 1280);
      expect(preset.height, 720);
      expect(preset.fps, 60);
      expect(preset.videoBitrateKbps, 4000);
      expect(preset.minBitrateKbps, 3500);
      expect(preset.maxBitrateKbps, 4500);
      expect(preset.audioBitrateKbps, 128);
      expect(preset.gopSeconds, 2.0);

      final config = StreamConfig.fromPreset(preset);
      expect(config.videoBitrate, 4000000);
      expect(config.isYouTubeCompliant, isTrue);
      expect(config.complianceIssues, isEmpty);
    });

    test('Preset 720p30 strictly conforms to YouTube specifications', () {
      const preset = YouTubeLivePreset.youtube720p30;
      expect(preset.width, 1280);
      expect(preset.height, 720);
      expect(preset.fps, 30);
      expect(preset.videoBitrateKbps, 2500);
      expect(preset.minBitrateKbps, 1500);
      expect(preset.maxBitrateKbps, 3500);
      expect(preset.audioBitrateKbps, 128);
      expect(preset.gopSeconds, 2.0);

      final config = StreamConfig.fromPreset(preset);
      expect(config.videoBitrate, 2500000);
      expect(config.isYouTubeCompliant, isTrue);
      expect(config.complianceIssues, isEmpty);
    });

    test(
      'Compliance validator flags invalid GOP, audio bitrate, and protocol',
      () {
        const nonCompliantConfig = StreamConfig(
          serverUrl: 'http://invalid-url.com/stream',
          width: 1920,
          height: 1080,
          fps: 25, // Invalid YouTube FPS
          videoBitrate: 15000000, // Too high
          audioBitrate: 64000, // Non-compliant audio
          gopSeconds: 5.0, // Non-compliant GOP (must be strict 2.0s)
        );

        expect(nonCompliantConfig.isYouTubeCompliant, isFalse);
        expect(
          nonCompliantConfig.complianceIssues.length,
          greaterThanOrEqualTo(3),
        );
        expect(
          nonCompliantConfig.complianceIssues.any((msg) => msg.contains('GOP')),
          isTrue,
        );
        expect(
          nonCompliantConfig.complianceIssues.any(
            (msg) => msg.contains('Protokół'),
          ),
          isTrue,
        );
        expect(
          nonCompliantConfig.complianceIssues.any(
            (msg) => msg.contains('framerate'),
          ),
          isTrue,
        );
      },
    );
  });

  group('StreamConfig Serialization & SharedPreferences Persistence', () {
    test('Roundtrip serialization (toMap / fromMap / json)', () {
      final config = StreamConfig.fromPreset(
        YouTubeLivePreset.youtube1080p60,
        serverUrl: 'rtmps://a.rtmps.youtube.com/live2',
        streamKey: 'live_test_key_123',
      );

      final map = config.toMap();
      expect(map['preset'], 'youtube_1080p60');
      expect(map['profile'], 'high');
      expect(map['bitrateMode'], 'CBR');
      expect(map['gopSeconds'], 2.0);

      final restored = StreamConfig.fromMap(map);
      expect(restored.preset, YouTubeLivePreset.youtube1080p60);
      expect(restored.width, 1920);
      expect(restored.height, 1080);
      expect(restored.fps, 60);
      expect(restored.videoBitrate, 8000000);
      expect(restored.audioBitrate, 128000);
      expect(restored.gopSeconds, 2.0);

      final json = config.toJson();
      final fromJson = StreamConfig.fromJson(json);
      expect(fromJson.serverUrl, config.serverUrl);
      expect(fromJson.preset, config.preset);
    });

    test('Saves and loads from SharedPreferences', () async {
      final config = StreamConfig.fromPreset(
        YouTubeLivePreset.youtube720p60,
        serverUrl: 'rtmps://b.rtmps.youtube.com/live2?backup=1',
        credentialReference: 'sec_ref_456',
      );

      await config.saveToPreferences();

      final loaded = await StreamConfig.loadFromPreferences();
      expect(loaded.preset, YouTubeLivePreset.youtube720p60);
      expect(loaded.serverUrl, 'rtmps://b.rtmps.youtube.com/live2?backup=1');
      expect(loaded.credentialReference, 'sec_ref_456');
      expect(loaded.width, 1280);
      expect(loaded.height, 720);
      expect(loaded.fps, 60);
      expect(loaded.videoBitrateKbps, 4000);
      expect(loaded.gopSeconds, 2.0);
    });

    test(
      'Interoperability between StreamConfig and legacy StreamingDestination',
      () {
        const dest = StreamingDestination(
          serverUrl: 'rtmps://a.rtmps.youtube.com/live2',
          resolution: '1920x1080',
          fps: 60,
          bitrateKbps: 8000,
        );

        final config = dest.toStreamConfig();
        expect(config.preset, YouTubeLivePreset.youtube1080p60);
        expect(config.width, 1920);
        expect(config.height, 1080);
        expect(config.fps, 60);
        expect(config.videoBitrateKbps, 8000);

        final convertedBack = config.toStreamingDestination();
        expect(convertedBack.fps, 60);
        expect(convertedBack.bitrateKbps, 8000);
      },
    );
  });

  group('NativeStreamBurnerBridge MethodChannel & Validation Tests', () {
    late NativeStreamBurnerBridge bridge;
    final List<MethodCall> methodCalls = [];

    setUp(() {
      methodCalls.clear();
      bridge = NativeStreamBurnerBridge();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.goshawk.volleylive/live_stream_bridge'),
            (call) async {
              methodCalls.add(call);
              switch (call.method) {
                case 'initializeStream':
                case 'initialize':
                  return true;
                case 'startStream':
                  return true;
                case 'stopStream':
                  return true;
                case 'validateEncoderCapabilities':
                  return {
                    'isH264Supported': true,
                    'isHighProfileSupported': true,
                    'isCbrSupported': true,
                    'maxSupportedWidth': 1920,
                    'maxSupportedHeight': 1080,
                    'maxSupportedFps': 60,
                    'compliantWithYouTube': true,
                  };
                default:
                  return null;
              }
            },
          );
    });

    test(
      'initializeStream passes CBR, High Profile, and strict GOP to platform',
      () async {
        final config = StreamConfig.fromPreset(
          YouTubeLivePreset.youtube1080p60,
        );
        final success = await bridge.initializeStream(config);

        expect(success, isTrue);
        expect(methodCalls.any((c) => c.method == 'initializeStream'), isTrue);
        final call = methodCalls.firstWhere(
          (c) => c.method == 'initializeStream',
        );
        expect(call.arguments['profile'], 'high');
        expect(call.arguments['bitrateMode'], 'CBR');
        expect(call.arguments['gopSeconds'], 2.0);
        expect(call.arguments['fps'], 60);
        expect(call.arguments['videoBitrate'], 8000000);
      },
    );

    test(
      'validateEncoderCapabilities queries hardware platform support',
      () async {
        final validation = await bridge.validateEncoderCapabilities();
        expect(validation['isH264Supported'], isTrue);
        expect(validation['isHighProfileSupported'], isTrue);
        expect(validation['isCbrSupported'], isTrue);
        expect(validation['compliantWithYouTube'], isTrue);
      },
    );

    test('startStream and stopStream invoke native platform channel', () async {
      const state = VolleyballScoreboardState(
        teamA: 'TEAM A',
        teamB: 'TEAM B',
        scoreA: 10,
        scoreB: 8,
        currentSet: 1,
        setsA: 0,
        setsB: 0,
      );

      final started = await bridge.startLiveStream(
        rtmpUrl: 'rtmps://a.rtmps.youtube.com/live2',
        streamKey: 'live_test_123',
        initialState: state,
        config: StreamConfig.fromPreset(YouTubeLivePreset.youtube1080p30),
      );

      expect(started, isTrue);
      expect(bridge.currentStatus, NativeStreamStatus.streaming);
      expect(methodCalls.any((c) => c.method == 'startStream'), isTrue);

      await bridge.stopLiveStream();
      expect(bridge.currentStatus, NativeStreamStatus.stopped);
      expect(methodCalls.any((c) => c.method == 'stopStream'), isTrue);
    });
  });

  group('StreamSettingsModal UI & Preset Selector Widget Tests', () {
    testWidgets(
      'Renders YouTube Presets, compliance specs, and validation status',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider(
              create: (_) => StreamerProvider(),
              child: const Scaffold(body: StreamSettingsModal()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Konfiguracja RTMP / YouTube Live'), findsOneWidget);
        expect(
          find.text('Profil Transmisji (Preset Enkodera):'),
          findsOneWidget,
        );
        expect(find.text('Punkt końcowy (Ingest Server URL)'), findsOneWidget);
        expect(find.text('Klucz Transmisji (Stream Key)'), findsOneWidget);
        expect(
          find.textContaining('Zgodność z YouTube Live Ingestion'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Walidacja sprzętowa enkodera'),
          findsOneWidget,
        );
      },
    );

    test('VideoOverlayBurnerService formats RTMP endpoints correctly', () {
      // 1. With stream key
      final ep1 = VideoOverlayBurnerService.buildRtmpEndpoint(
        'rtmp://192.168.68.55:1935/live',
        'sport',
      );
      expect(ep1, 'rtmp://192.168.68.55:1935/live/sport');

      // 2. With stream key and trailing slash in serverUrl
      final ep2 = VideoOverlayBurnerService.buildRtmpEndpoint(
        'rtmp://192.168.68.55:1935/live/',
        'sport',
      );
      expect(ep2, 'rtmp://192.168.68.55:1935/live/sport');

      // 3. Without stream key (stream already embedded in URL)
      final ep3 = VideoOverlayBurnerService.buildRtmpEndpoint(
        'rtmp://192.168.68.55:1935/live/sport',
        '',
      );
      expect(ep3, 'rtmp://192.168.68.55:1935/live/sport');

      // 4. Without stream key but with trailing slash (must be stripped)
      final ep4 = VideoOverlayBurnerService.buildRtmpEndpoint(
        'rtmp://192.168.68.55:1935/live/sport///',
        '   ',
      );
      expect(ep4, 'rtmp://192.168.68.55:1935/live/sport');
    });

    test('StreamConfig distinguishes YouTube vs Custom RTMP stream key requirement', () {
      const ytConfig = StreamConfig(
        serverUrl: 'rtmps://a.rtmps.youtube.com/live2',
      );
      expect(ytConfig.requiresStreamKey, isTrue);

      const customFullUrl = StreamConfig(
        serverUrl: 'rtmp://192.168.68.55:1935/live/sport',
      );
      expect(customFullUrl.requiresStreamKey, isFalse);
      expect(customFullUrl.isCustomRtmp, isTrue);
    });

    test('StreamingService surfaces descriptive error when required key is missing', () async {
      final streamingService = StreamingService();
      const ytWithoutKey = StreamConfig(
        serverUrl: 'rtmps://a.rtmps.youtube.com/live2',
        streamKey: '',
        credentialReference: '',
      );

      final success = await streamingService.startLiveStreamWithConfig(ytWithoutKey);
      expect(success, isFalse);
      expect(streamingService.lastErrorMessage, contains('Wymagany klucz transmisji'));
    });

    test('VideoOverlayBurnerService.extractCleanFfmpegError cleans compilation headers and translates errors', () {
      const rawHeaderError = '''
ffmpeg version n6.0-28-g9642646d29 Copyright (c) 2000-2026 the FFmpeg developers
built with Android (13065274, +pgo, -bolt, +lto, -mlgo, based on r547379)
clang version 20.0.0 (https://android.googlesource.com/toolchain/llvm-project)
configuration: --cross-prefix=aarch64-linux-android- --sysroot=/Users/me/Library/Android/sdk/ndk/29.0.13113456/
libavutil      58.  2.100 / 58.  2.100
libavcodec     60.  3.100 / 60.  3.100
[rtmp @ 0x76b8c94000] Cannot open connection tcp://192.168.68.58:1935
rtmp://192.168.68.58:1935/live/sport: Connection refused
''';

      final cleanMsg = VideoOverlayBurnerService.extractCleanFfmpegError(rawHeaderError);
      expect(cleanMsg, contains('Connection refused'));
      expect(cleanMsg, contains('ffplay'));
      expect(cleanMsg.contains('clang version'), isFalse);
      expect(cleanMsg.contains('configuration:'), isFalse);

      const timeoutError = '''
ffmpeg version n6.0
[rtmp @ 0x123] Connection timed out
''';
      final timeoutMsg = VideoOverlayBurnerService.extractCleanFfmpegError(timeoutError);
      expect(timeoutMsg, contains('Timeout'));
      expect(timeoutMsg, contains('Zaporze Windows'));
    });

    test(
      'VideoOverlayBurnerService.buildProgramFramesBroadcastCommand scales to target resolution and sets YouTube parameters',
      () {
        final cmd1080p =
            VideoOverlayBurnerService.buildProgramFramesBroadcastCommand(
              inputUrl: 'http://127.0.0.1:8080/program.png',
              endpoint: 'rtmp://192.168.68.58:1935/live/sport',
              width: 1920,
              height: 1080,
              bitrateKbps: 4500,
              fps: 30,
              audioSampleRate: 48000,
            );

        expect(
          cmd1080p,
          contains(
            'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1',
          ),
        );
        expect(cmd1080p, contains('-framerate 30'));
        expect(cmd1080p, contains('-b:v 4500k'));
        expect(cmd1080p, contains('-maxrate 4500k'));
        expect(cmd1080p, contains('-g 60'));
        expect(cmd1080p, contains('sample_rate=48000'));
        expect(cmd1080p, contains('-f flv "rtmp://192.168.68.58:1935/live/sport"'));

        final cmd720p =
            VideoOverlayBurnerService.buildProgramFramesBroadcastCommand(
              inputUrl: 'http://127.0.0.1:8080/program.png',
              endpoint: 'rtmps://a.rtmps.youtube.com/live2/key123',
              width: 1280,
              height: 720,
              bitrateKbps: 2500,
              fps: 30,
            );

        expect(
          cmd720p,
          contains(
            'scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1',
          ),
        );
        expect(cmd720p, contains('-b:v 2500k'));
        expect(cmd720p, contains('-maxrate 2500k'));
      },
    );
  });
}
