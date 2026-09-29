import 'dart:convert';

/// Pojedynczy punkt w osi czasu nagrania powiązany z offsetem wideo
class ScoreTimelineEntry {
  final int offsetMs;
  final String eventType;
  final int setNumber;
  final int scoreA;
  final int scoreB;
  final int setsA;
  final int setsB;
  final String servingTeam;
  final String? eventTag;

  const ScoreTimelineEntry({
    required this.offsetMs,
    required this.eventType,
    required this.setNumber,
    required this.scoreA,
    required this.scoreB,
    required this.setsA,
    required this.setsB,
    required this.servingTeam,
    this.eventTag,
  });

  bool get hasDisplayableBanner => isDisplayableSpecialBanner(eventTag);

  static bool isDisplayableSpecialBanner(String? tag) {
    if (tag == null) return false;
    final clean = tag.trim().toUpperCase();
    if (clean.isEmpty) return false;
    if (clean.startsWith('POINT') ||
        clean.contains('POCZĄTEK') ||
        clean.contains('POCZATEK') ||
        clean.contains('START MECZU') ||
        clean.contains('COFNIĘTO') ||
        clean.contains('COFNIETO') ||
        clean == 'SCOREUPDATE' ||
        clean == 'INIT' ||
        clean == 'START' ||
        clean == 'NONE') {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'offsetMs': offsetMs,
    'offsetSeconds': (offsetMs / 1000.0).toStringAsFixed(2),
    'eventType': eventType,
    'setNumber': setNumber,
    'scoreA': scoreA,
    'scoreB': scoreB,
    'setsA': setsA,
    'setsB': setsB,
    'servingTeam': servingTeam,
    if (eventTag != null) 'eventTag': eventTag,
  };

  factory ScoreTimelineEntry.fromJson(Map<String, dynamic> json) => ScoreTimelineEntry(
    offsetMs: json['offsetMs'] as int? ?? 0,
    eventType: json['eventType'] as String? ?? 'point',
    setNumber: json['setNumber'] as int? ?? 1,
    scoreA: json['scoreA'] as int? ?? 0,
    scoreB: json['scoreB'] as int? ?? 0,
    setsA: json['setsA'] as int? ?? 0,
    setsB: json['setsB'] as int? ?? 0,
    servingTeam: json['servingTeam'] as String? ?? 'A',
    eventTag: json['eventTag'] as String?,
  );
}

/// Pełny model metadanych meczowych zapisywany jako plik .meta.json obok pliku MP4
class MatchRecordingMetadata {
  final String recordingId;
  final String videoFileName;
  final String recordingType; // 'rawCamera' | 'programWithScoreboard' | 'dual'
  final DateTime recordedAt;
  final Duration duration;
  final String orientation; // '16:9' | '9:16'
  final int? fileSizeBytes;
  final String sport;
  final String teamA;
  final String teamB;
  final int finalSetsA;
  final int finalSetsB;
  final String? tournamentName;
  final List<ScoreTimelineEntry> timeline;

  const MatchRecordingMetadata({
    required this.recordingId,
    required this.videoFileName,
    required this.recordingType,
    required this.recordedAt,
    required this.duration,
    required this.orientation,
    this.fileSizeBytes,
    required this.sport,
    required this.teamA,
    required this.teamB,
    required this.finalSetsA,
    required this.finalSetsB,
    this.tournamentName,
    this.timeline = const [],
  });

  Map<String, dynamic> toJson() => {
    'version': '1.0.0',
    'recordingId': recordingId,
    'videoFileName': videoFileName,
    'recordingType': recordingType,
    'recordedAt': recordedAt.toIso8601String(),
    'durationSeconds': duration.inSeconds,
    'durationFormatted': _formatDuration(duration),
    'orientation': orientation,
    if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
    'match': {
      'sport': sport,
      'teamA': teamA,
      'teamB': teamB,
      'finalSetsA': finalSetsA,
      'finalSetsB': finalSetsB,
      if (tournamentName != null) 'tournamentName': tournamentName,
    },
    'timelineEventsCount': timeline.length,
    'timeline': timeline.map((e) => e.toJson()).toList(),
  };

  String toJsonString() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

  /// Generuje uniwersalny plik napisów SRT z nałożonym stanem tablicy wyników
  /// Dzięki temu każdy odtwarzacz wideo (VLC, Media Player, YouTube) może wyświetlić tablicę wyników
  String generateSrtSubtitles() {
    if (timeline.isEmpty) {
      // Jeśli brak zdarzeń w trakcie, stwórz jeden ciągły napis z wynikiem
      final endTime = _formatSrtTimestamp(duration.inMilliseconds);
      return '''1
00:00:00,000 --> $endTime
[ $teamA $finalSetsA : $finalSetsB $teamB ]
''';
    }

    final buffer = StringBuffer();
    for (int i = 0; i < timeline.length; i++) {
      final entry = timeline[i];
      final startMs = entry.offsetMs;
      final endMs = (i + 1 < timeline.length)
          ? timeline[i + 1].offsetMs
          : duration.inMilliseconds.clamp(startMs + 1000, 86400000);

      final startTimeStr = _formatSrtTimestamp(startMs);
      final endTimeStr = _formatSrtTimestamp(endMs);

      final serveIndicator = entry.servingTeam == 'A' ? '• ' : '';
      final serveIndicatorB = entry.servingTeam == 'B' ? ' •' : '';
      final tagText = entry.eventTag != null ? ' | ${entry.eventTag}' : '';

      buffer.writeln('${i + 1}');
      buffer.writeln('$startTimeStr --> $endTimeStr');
      buffer.writeln(
        'SET ${entry.setNumber} (${entry.setsA}:${entry.setsB}) | '
        '$serveIndicator${teamA.toUpperCase()} ${entry.scoreA} : ${entry.scoreB} ${teamB.toUpperCase()}$serveIndicatorB$tagText',
      );
      buffer.writeln();
    }
    return buffer.toString();
  }

  static String _formatSrtTimestamp(int totalMs) {
    final int hours = totalMs ~/ 3600000;
    final int minutes = (totalMs % 3600000) ~/ 60000;
    final int seconds = (totalMs % 60000) ~/ 1000;
    final int milliseconds = totalMs % 1000;

    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String threeDigits(int n) => n.toString().padLeft(3, '0');

    return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)},${threeDigits(milliseconds)}';
  }

  static String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
}
