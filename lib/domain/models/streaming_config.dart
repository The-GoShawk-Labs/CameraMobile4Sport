import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volleylive/core/security/secure_storage_service.dart';
import 'package:volleylive/domain/models/scoreboard_burn_in_state.dart';

enum StreamingPlatformType {
  youtube('YouTube Live (RTMPS)', 'rtmps://a.rtmps.youtube.com/live2'),
  youtubeBackup('YouTube Live Backup (RTMPS)', 'rtmps://b.rtmps.youtube.com/live2?backup=1'),
  meta('Meta / Facebook Live (RTMPS)', 'rtmps://live-api-s.facebook.com:443/rtmp/'),
  genericRtmps('Generic RTMPS', 'rtmps://'),
  genericRtmp('Generic RTMP', 'rtmp://');

  final String displayName;
  final String defaultEndpoint;
  const StreamingPlatformType(this.displayName, this.defaultEndpoint);
}

enum ScoreboardThemeStyle {
  tvProBroadcast('TV Pro Broadcast'),
  broadcastCompact3Letter('Broadcast Pro Compact (3-letter)'),
  cyberGlow('Cyber Glow Neon'),
  minimalist('Minimalist Clean'),
  beachVolley('Beach Volley 2v2');

  final String label;
  const ScoreboardThemeStyle(this.label);
}

/// Official YouTube Live ingestion presets conforming strictly to:
/// - Codec: H.264 / AVC (High Profile Level 4.1 / 4.2)
/// - Rate Control: CBR (Constant Bitrate)
/// - Keyframe Interval (GOP): Strict 2.0 seconds
/// - Audio: AAC-LC Stereo @ 128 kbps (44.1 kHz / 48 kHz)
enum YouTubeLivePreset {
  youtube1080p60(
    id: 'youtube_1080p60',
    label: 'YouTube 1080p60',
    description: '1080p @ 60 fps | 8000 kbps CBR (Full HD High Frame Rate)',
    width: 1920,
    height: 1080,
    fps: 60,
    videoBitrateKbps: 8000,
    minBitrateKbps: 6000,
    maxBitrateKbps: 9000,
    audioBitrateKbps: 128,
    gopSeconds: 2.0,
  ),
  youtube1080p30(
    id: 'youtube_1080p30',
    label: 'YouTube 1080p30',
    description: '1080p @ 30 fps | 4500 kbps CBR (Full HD Standard)',
    width: 1920,
    height: 1080,
    fps: 30,
    videoBitrateKbps: 4500,
    minBitrateKbps: 3000,
    maxBitrateKbps: 6000,
    audioBitrateKbps: 128,
    gopSeconds: 2.0,
  ),
  youtube720p60(
    id: 'youtube_720p60',
    label: 'YouTube 720p60',
    description: '720p @ 60 fps | 4000 kbps CBR (HD High Frame Rate)',
    width: 1280,
    height: 720,
    fps: 60,
    videoBitrateKbps: 4000,
    minBitrateKbps: 3500,
    maxBitrateKbps: 4500,
    audioBitrateKbps: 128,
    gopSeconds: 2.0,
  ),
  youtube720p30(
    id: 'youtube_720p30',
    label: 'YouTube 720p30',
    description: '720p @ 30 fps | 2500 kbps CBR (HD Standard)',
    width: 1280,
    height: 720,
    fps: 30,
    videoBitrateKbps: 2500,
    minBitrateKbps: 1500,
    maxBitrateKbps: 3500,
    audioBitrateKbps: 128,
    gopSeconds: 2.0,
  ),
  custom(
    id: 'custom',
    label: 'Custom',
    description: 'Niestandardowe parametry strumieniowania i enkodera',
    width: 1920,
    height: 1080,
    fps: 30,
    videoBitrateKbps: 4500,
    minBitrateKbps: 500,
    maxBitrateKbps: 15000,
    audioBitrateKbps: 128,
    gopSeconds: 2.0,
  );

  final String id;
  final String label;
  final String description;
  final int width;
  final int height;
  final int fps;
  final int videoBitrateKbps;
  final int minBitrateKbps;
  final int maxBitrateKbps;
  final int audioBitrateKbps;
  final double gopSeconds;

  const YouTubeLivePreset({
    required this.id,
    required this.label,
    required this.description,
    required this.width,
    required this.height,
    required this.fps,
    required this.videoBitrateKbps,
    required this.minBitrateKbps,
    required this.maxBitrateKbps,
    required this.audioBitrateKbps,
    required this.gopSeconds,
  });

  static YouTubeLivePreset fromId(String? id) {
    if (id == null) return YouTubeLivePreset.youtube1080p30;
    return YouTubeLivePreset.values.firstWhere(
      (p) => p.id == id,
      orElse: () => YouTubeLivePreset.youtube1080p30,
    );
  }
}

/// Comprehensive streaming configuration compliant with YouTube Live ingestion standards.
class StreamConfig {
  static const String prefKeyServerUrl = 'stream_config_server_url';
  static const String prefKeyPreset = 'stream_config_preset';
  static const String prefKeyCredRef = 'stream_config_cred_ref';
  static const String prefKeyWidth = 'stream_config_width';
  static const String prefKeyHeight = 'stream_config_height';
  static const String prefKeyFps = 'stream_config_fps';
  static const String prefKeyVideoBitrate = 'stream_config_video_bitrate';
  static const String prefKeyAudioBitrate = 'stream_config_audio_bitrate';
  static const String prefKeyGopSeconds = 'stream_config_gop_seconds';
  static const String prefKeyAudioSampleRate = 'stream_config_audio_sample_rate';
  static const String prefKeyLocalRecording = 'stream_config_local_recording';
  static const String prefKeyDirectStreamKey = 'stream_config_direct_stream_key';
  static const String prefKeyScoreboardAnchor = 'stream_config_scoreboard_anchor';
  static const String prefKeyScoreboardStyle = 'stream_config_scoreboard_style';

  final String serverUrl;
  final String streamKey;
  final String credentialReference;
  final YouTubeLivePreset preset;
  final int width;
  final int height;
  final int fps;
  final int videoBitrate; // in bps
  final int audioBitrate; // in bps (typically 128000)
  final double gopSeconds; // 2.0 strict YouTube requirement
  final int audioSampleRate; // 48000 or 44100
  final int audioChannels; // 2 (Stereo)
  final bool isLocalProgramRecordingEnabled;
  final ScoreboardAnchorPosition anchorPosition;
  final ScoreboardThemeStyle scoreboardStyle;

  const StreamConfig({
    this.serverUrl = 'rtmps://a.rtmps.youtube.com/live2',
    this.streamKey = '',
    this.credentialReference = '',
    this.preset = YouTubeLivePreset.youtube1080p30,
    this.width = 1920,
    this.height = 1080,
    this.fps = 30,
    this.videoBitrate = 4500000,
    this.audioBitrate = 128000,
    this.gopSeconds = 2.0,
    this.audioSampleRate = 48000,
    this.audioChannels = 2,
    this.isLocalProgramRecordingEnabled = true,
    this.anchorPosition = ScoreboardAnchorPosition.topLeft,
    this.scoreboardStyle = ScoreboardThemeStyle.tvProBroadcast,
  });

  /// Factory creating configuration directly from preset defaults
  factory StreamConfig.fromPreset(
    YouTubeLivePreset preset, {
    String serverUrl = 'rtmps://a.rtmps.youtube.com/live2',
    String streamKey = '',
    String credentialReference = '',
    bool isLocalProgramRecordingEnabled = true,
    int? customVideoBitrateKbps,
    ScoreboardAnchorPosition anchorPosition = ScoreboardAnchorPosition.topLeft,
    ScoreboardThemeStyle scoreboardStyle = ScoreboardThemeStyle.tvProBroadcast,
  }) {
    final vBitrate = (customVideoBitrateKbps ?? preset.videoBitrateKbps) * 1000;
    return StreamConfig(
      serverUrl: serverUrl,
      streamKey: streamKey,
      credentialReference: credentialReference,
      preset: preset,
      width: preset.width,
      height: preset.height,
      fps: preset.fps,
      videoBitrate: vBitrate,
      audioBitrate: preset.audioBitrateKbps * 1000,
      gopSeconds: preset.gopSeconds,
      audioSampleRate: 48000,
      audioChannels: 2,
      isLocalProgramRecordingEnabled: isLocalProgramRecordingEnabled,
      anchorPosition: anchorPosition,
      scoreboardStyle: scoreboardStyle,
    );
  }

  int get videoBitrateKbps => videoBitrate ~/ 1000;
  int get audioBitrateKbps => audioBitrate ~/ 1000;
  String get resolution => '${width}x$height';
  bool get isRtmps => serverUrl.trim().toLowerCase().startsWith('rtmps://');
  bool get isYouTube => serverUrl.toLowerCase().contains('youtube.com');
  bool get isCustomRtmp =>
      !isYouTube && !serverUrl.toLowerCase().contains('facebook.com');

  /// Określa, czy klucz transmisji jest wymagany:
  /// - YouTube i Facebook bezwzględnie wymagają klucza transmisji.
  /// - Własny RTMP (np. lokalny serwer PC) z pełną ścieżką (/live/stream) nie wymaga oddzielnego klucza.
  bool get requiresStreamKey {
    final lower = serverUrl.trim().toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('facebook.com')) {
      return true;
    }
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri != null) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length >= 2) {
        return false;
      }
    }
    return false;
  }

  StreamConfig copyWith({
    String? serverUrl,
    String? streamKey,
    String? credentialReference,
    YouTubeLivePreset? preset,
    int? width,
    int? height,
    int? fps,
    int? videoBitrate,
    int? audioBitrate,
    double? gopSeconds,
    int? audioSampleRate,
    int? audioChannels,
    bool? isLocalProgramRecordingEnabled,
    ScoreboardAnchorPosition? anchorPosition,
    ScoreboardThemeStyle? scoreboardStyle,
  }) {
    return StreamConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      streamKey: streamKey ?? this.streamKey,
      credentialReference: credentialReference ?? this.credentialReference,
      preset: preset ?? this.preset,
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      videoBitrate: videoBitrate ?? this.videoBitrate,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      gopSeconds: gopSeconds ?? this.gopSeconds,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioChannels: audioChannels ?? this.audioChannels,
      isLocalProgramRecordingEnabled:
          isLocalProgramRecordingEnabled ?? this.isLocalProgramRecordingEnabled,
      anchorPosition: anchorPosition ?? this.anchorPosition,
      scoreboardStyle: scoreboardStyle ?? this.scoreboardStyle,
    );
  }

  /// Verifies strict YouTube Live technical compliance.
  List<String> get complianceIssues {
    final issues = <String>[];
    if (!serverUrl.trim().toLowerCase().startsWith('rtmp://') &&
        !serverUrl.trim().toLowerCase().startsWith('rtmps://')) {
      issues.add('Protokół musi być RTMP lub RTMPS');
    }
    if (gopSeconds < 1.9 || gopSeconds > 2.1) {
      issues.add('Interwał klatek kluczowych (GOP) musi wynosić ściśle 2.0 s (aktualnie ${gopSeconds.toStringAsFixed(1)} s)');
    }
    if (fps != 30 && fps != 60) {
      issues.add('Zalecany framerate YouTube Live to 30 lub 60 fps (aktualnie $fps fps)');
    }
    if (width == 1920 && height == 1080) {
      if (fps == 60 && (videoBitrateKbps < 6000 || videoBitrateKbps > 9000)) {
        issues.add('Dla 1080p60 zalecany bitrate YouTube to 6000–9000 kbps (aktualnie $videoBitrateKbps kbps)');
      } else if (fps == 30 && (videoBitrateKbps < 3000 || videoBitrateKbps > 6000)) {
        issues.add('Dla 1080p30 zalecany bitrate YouTube to 3000–6000 kbps (aktualnie $videoBitrateKbps kbps)');
      }
    } else if (width == 1280 && height == 720) {
      if (fps == 60 && (videoBitrateKbps < 3500 || videoBitrateKbps > 4500)) {
        issues.add('Dla 720p60 zalecany bitrate YouTube to 3500–4500 kbps (aktualnie $videoBitrateKbps kbps)');
      } else if (fps == 30 && (videoBitrateKbps < 1500 || videoBitrateKbps > 3500)) {
        issues.add('Dla 720p30 zalecany bitrate YouTube to 1500–3500 kbps (aktualnie $videoBitrateKbps kbps)');
      }
    }
    if (audioBitrateKbps != 128) {
      issues.add('Zalecany bitrate audio YouTube Live to 128 kbps CBR (aktualnie $audioBitrateKbps kbps)');
    }
    if (audioSampleRate != 44100 && audioSampleRate != 48000) {
      issues.add('Zalecana częstotliwość próbkowania to 44.1 kHz lub 48.0 kHz');
    }
    return issues;
  }

  bool get isYouTubeCompliant => complianceIssues.isEmpty;

  Map<String, dynamic> toMap() => {
    'serverUrl': serverUrl,
    'streamKey': streamKey,
    'credentialReference': credentialReference,
    'preset': preset.id,
    'width': width,
    'height': height,
    'fps': fps,
    'videoBitrate': videoBitrate,
    'audioBitrate': audioBitrate,
    'gopSeconds': gopSeconds,
    'audioSampleRate': audioSampleRate,
    'audioChannels': audioChannels,
    'isLocalProgramRecordingEnabled': isLocalProgramRecordingEnabled,
    'anchorPosition': anchorPosition.name,
    'scoreboardStyle': scoreboardStyle.name,
    'profile': 'high', // AVCProfileHigh
    'bitrateMode': 'CBR',
  };

  factory StreamConfig.fromMap(Map<String, dynamic> map) {
    ScoreboardThemeStyle style = ScoreboardThemeStyle.tvProBroadcast;
    final styleStr = (map['scoreboardStyle'] as String?) ?? (map['style'] as String?);
    if (styleStr != null) {
      for (final s in ScoreboardThemeStyle.values) {
        if (s.name == styleStr) {
          style = s;
          break;
        }
      }
    }

    return StreamConfig(
      serverUrl: (map['serverUrl'] as String?) ?? 'rtmps://a.rtmps.youtube.com/live2',
      streamKey: (map['streamKey'] as String?) ?? '',
      credentialReference: (map['credentialReference'] as String?) ?? '',
      preset: YouTubeLivePreset.fromId(map['preset'] as String?),
      width: (map['width'] as num?)?.toInt() ?? 1920,
      height: (map['height'] as num?)?.toInt() ?? 1080,
      fps: (map['fps'] as num?)?.toInt() ?? 30,
      videoBitrate: (map['videoBitrate'] as num?)?.toInt() ?? 4500000,
      audioBitrate: (map['audioBitrate'] as num?)?.toInt() ?? 128000,
      gopSeconds: (map['gopSeconds'] as num?)?.toDouble() ?? 2.0,
      audioSampleRate: (map['audioSampleRate'] as num?)?.toInt() ?? 48000,
      audioChannels: (map['audioChannels'] as num?)?.toInt() ?? 2,
      isLocalProgramRecordingEnabled:
          (map['isLocalProgramRecordingEnabled'] as bool?) ?? true,
      anchorPosition: ScoreboardAnchorPosition.fromName(map['anchorPosition'] as String?),
      scoreboardStyle: style,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory StreamConfig.fromJson(String source) =>
      StreamConfig.fromMap(jsonDecode(source) as Map<String, dynamic>);

  /// Persists settings to SharedPreferences
  Future<void> saveToPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKeyServerUrl, serverUrl);
    await prefs.setString(prefKeyPreset, preset.id);
    await prefs.setString(prefKeyCredRef, credentialReference);
    await prefs.setString(prefKeyDirectStreamKey, streamKey);
    await prefs.setInt(prefKeyWidth, width);
    await prefs.setInt(prefKeyHeight, height);
    await prefs.setInt(prefKeyFps, fps);
    await prefs.setInt(prefKeyVideoBitrate, videoBitrate);
    await prefs.setInt(prefKeyAudioBitrate, audioBitrate);
    await prefs.setDouble(prefKeyGopSeconds, gopSeconds);
    await prefs.setInt(prefKeyAudioSampleRate, audioSampleRate);
    await prefs.setBool(prefKeyLocalRecording, isLocalProgramRecordingEnabled);
    await prefs.setString(prefKeyScoreboardAnchor, anchorPosition.name);
    await prefs.setString(prefKeyScoreboardStyle, scoreboardStyle.name);
  }

  /// Restores configuration from SharedPreferences
  static Future<StreamConfig> loadFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final presetId = prefs.getString(prefKeyPreset);
    final preset = YouTubeLivePreset.fromId(presetId);

    final serverUrl = prefs.getString(prefKeyServerUrl) ?? 'rtmps://a.rtmps.youtube.com/live2';
    final credRef = prefs.getString(prefKeyCredRef) ?? '';
    final directKey = prefs.getString(prefKeyDirectStreamKey) ?? '';
    final width = prefs.getInt(prefKeyWidth) ?? preset.width;
    final height = prefs.getInt(prefKeyHeight) ?? preset.height;
    final fps = prefs.getInt(prefKeyFps) ?? preset.fps;
    final videoBitrate = prefs.getInt(prefKeyVideoBitrate) ?? (preset.videoBitrateKbps * 1000);
    final audioBitrate = prefs.getInt(prefKeyAudioBitrate) ?? (preset.audioBitrateKbps * 1000);
    final gopSeconds = prefs.getDouble(prefKeyGopSeconds) ?? preset.gopSeconds;
    final audioSampleRate = prefs.getInt(prefKeyAudioSampleRate) ?? 48000;
    final localRec = prefs.getBool(prefKeyLocalRecording) ?? true;
    final anchorStr = prefs.getString(prefKeyScoreboardAnchor);
    final anchorPos = ScoreboardAnchorPosition.fromName(anchorStr);
    final styleStr = prefs.getString(prefKeyScoreboardStyle);
    final style = styleStr != null
        ? ScoreboardThemeStyle.values.firstWhere(
            (s) => s.name == styleStr,
            orElse: () => ScoreboardThemeStyle.tvProBroadcast,
          )
        : ScoreboardThemeStyle.tvProBroadcast;

    return StreamConfig(
      serverUrl: serverUrl,
      streamKey: directKey,
      credentialReference: credRef,
      preset: preset,
      width: width,
      height: height,
      fps: fps,
      videoBitrate: videoBitrate,
      audioBitrate: audioBitrate,
      gopSeconds: gopSeconds,
      audioSampleRate: audioSampleRate,
      audioChannels: 2,
      isLocalProgramRecordingEnabled: localRec,
      anchorPosition: anchorPos,
      scoreboardStyle: style,
    );
  }

  /// Resolves the actual stream key:
  /// 1. If explicit [streamKey] is present, returns it.
  /// 2. If [credentialReference] is present, securely fetches it from Keystore/Keychain.
  Future<String> resolveEffectiveStreamKey() async {
    if (streamKey.trim().isNotEmpty) return streamKey.trim();
    if (credentialReference.isNotEmpty) {
      try {
        final key = await SecureStorageService.getCredential(credentialReference);
        if (key != null && key.trim().isNotEmpty) return key.trim();
      } catch (_) {}
    }
    return '';
  }

  /// Converts to legacy StreamingDestination for backward compatibility
  StreamingDestination toStreamingDestination() {
    StreamingPlatformType type = StreamingPlatformType.youtube;
    if (serverUrl.contains('facebook.com')) {
      type = StreamingPlatformType.meta;
    } else if (serverUrl.startsWith('rtmp://')) {
      type = StreamingPlatformType.genericRtmp;
    } else if (!serverUrl.contains('youtube.com')) {
      type = StreamingPlatformType.genericRtmps;
    }

    return StreamingDestination(
      type: type,
      name: preset.label,
      serverUrl: serverUrl,
      credentialReference: credentialReference,
      isEnabled: true,
      bitrateKbps: videoBitrateKbps,
      fps: fps,
      resolution: '${width}x$height',
      isLocalProgramRecordingEnabled: isLocalProgramRecordingEnabled,
    );
  }

  /// Creates StreamConfig from legacy StreamingDestination
  factory StreamConfig.fromStreamingDestination(StreamingDestination dest) {
    YouTubeLivePreset preset = YouTubeLivePreset.custom;
    if (dest.resolution.contains('1080') && dest.fps == 60) {
      preset = YouTubeLivePreset.youtube1080p60;
    } else if (dest.resolution.contains('1080') && dest.fps == 30) {
      preset = YouTubeLivePreset.youtube1080p30;
    } else if (dest.resolution.contains('720') && dest.fps == 60) {
      preset = YouTubeLivePreset.youtube720p60;
    } else if (dest.resolution.contains('720') && dest.fps == 30) {
      preset = YouTubeLivePreset.youtube720p30;
    }

    final is1080 = dest.resolution.contains('1080');
    final w = is1080 ? 1920 : 1280;
    final h = is1080 ? 1080 : 720;

    return StreamConfig(
      serverUrl: dest.serverUrl,
      credentialReference: dest.credentialReference,
      preset: preset,
      width: w,
      height: h,
      fps: dest.fps,
      videoBitrate: dest.bitrateKbps * 1000,
      audioBitrate: 128000,
      gopSeconds: 2.0,
      audioSampleRate: 48000,
      audioChannels: 2,
      isLocalProgramRecordingEnabled: dest.isLocalProgramRecordingEnabled,
    );
  }
}

class StreamingDestination {
  final StreamingPlatformType type;
  final String name;
  final String serverUrl;
  final String credentialReference; // Identyfikator w bezpiecznym magazynie
  final bool isEnabled;
  final int bitrateKbps;
  final int fps;
  final String resolution;
  final bool isLocalProgramRecordingEnabled;

  const StreamingDestination({
    this.type = StreamingPlatformType.youtube,
    this.name = 'Główna Transmisja',
    this.serverUrl = 'rtmps://a.rtmps.youtube.com/live2',
    this.credentialReference = '',
    this.isEnabled = true,
    this.bitrateKbps = 4500,
    this.fps = 30,
    this.resolution = '1080p',
    this.isLocalProgramRecordingEnabled = true,
  });

  StreamingDestination copyWith({
    StreamingPlatformType? type,
    String? name,
    String? serverUrl,
    String? credentialReference,
    bool? isEnabled,
    int? bitrateKbps,
    int? fps,
    String? resolution,
    bool? isLocalProgramRecordingEnabled,
  }) {
    return StreamingDestination(
      type: type ?? this.type,
      name: name ?? this.name,
      serverUrl: serverUrl ?? this.serverUrl,
      credentialReference: credentialReference ?? this.credentialReference,
      isEnabled: isEnabled ?? this.isEnabled,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      fps: fps ?? this.fps,
      resolution: resolution ?? this.resolution,
      isLocalProgramRecordingEnabled:
          isLocalProgramRecordingEnabled ?? this.isLocalProgramRecordingEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'name': name,
    'serverUrl': serverUrl,
    'credentialReference': credentialReference,
    'isEnabled': isEnabled,
    'bitrateKbps': bitrateKbps,
    'fps': fps,
    'resolution': resolution,
    'isLocalProgramRecordingEnabled': isLocalProgramRecordingEnabled,
  };

  StreamConfig toStreamConfig() => StreamConfig.fromStreamingDestination(this);
}
