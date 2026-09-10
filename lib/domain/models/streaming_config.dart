enum StreamingPlatformType {
  youtube('YouTube Live (RTMPS)', 'rtmps://a.rtmps.youtube.com/live2'),
  meta('Meta / Facebook Live (RTMPS)', 'rtmps://live-api-s.facebook.com:443/rtmp/'),
  genericRtmps('Generic RTMPS', 'rtmps://');

  final String displayName;
  final String defaultEndpoint;
  const StreamingPlatformType(this.displayName, this.defaultEndpoint);
}

enum ScoreboardThemeStyle {
  tvProBroadcast('TV Pro Broadcast'),
  cyberGlow('Cyber Glow Neon'),
  minimalist('Minimalist Clean'),
  beachVolley('Beach Volley 2v2');

  final String label;
  const ScoreboardThemeStyle(this.label);
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
    this.bitrateKbps = 8000,
    this.fps = 60,
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
      isLocalProgramRecordingEnabled: isLocalProgramRecordingEnabled ?? this.isLocalProgramRecordingEnabled,
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
}
