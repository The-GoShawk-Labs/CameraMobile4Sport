/// Rodzaj nagrywania wideo
enum RecordingType {
  /// Czysty, bezstratny strumień prosto z sensora kamery bez żadnego UI (Phone A)
  rawCamera(
    label: 'Czysty RAW Kamery',
    shortLabel: 'RAW',
    description:
        'Czysty obraz z sensora w maksymalnej jakości bez nałożonych grafik i elementów sędziego.',
    filePrefix: 'RAW_REC',
  ),

  /// Wideo z trwale zintegrowaną/wypaloną tablicą wyników i grafikami (Phone B / Komentator)
  programWithScoreboard(
    label: 'Program + Tablica Wyników',
    shortLabel: 'PROGRAM',
    description:
        'Wideo z nałożoną tablicą wyników, serwującym, setami i czasem meczu. Gotowe do streamu lub uploadu.',
    filePrefix: 'PROGRAM_REC',
  ),

  /// Jednoczesny zapis czystego pliku RAW oraz programu z tablicą wyników
  dual(
    label: 'Dual REC (RAW + Program)',
    shortLabel: 'DUAL',
    description:
        'Zapisuje dwa pliki równolegle: czysty materiał źródłowy oraz wersję telewizyjną z tablicą wyników.',
    filePrefix: 'DUAL_REC',
  );

  final String label;
  final String shortLabel;
  final String description;
  final String filePrefix;

  const RecordingType({
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.filePrefix,
  });
}

/// Orientacja, w jakiej nagrany został plik wideo
enum RecordedVideoOrientation {
  landscape(
    label: 'Poziomo (16:9)',
    aspectRatioString: '16:9',
    aspectRatio: 16 / 9,
    description:
        'Format 16:9 (zoptymalizowany pod platformy streamingowe: YouTube, Twitch, OBS)',
    isStreamingOptimized: true,
  ),
  portrait(
    label: 'Pionowo (9:16)',
    aspectRatioString: '9:16',
    aspectRatio: 9 / 16,
    description:
        'Format 9:16 (zoptymalizowany pod formaty pionowe: Shorts, Reels, TikTok)',
    isStreamingOptimized: false,
  );

  final String label;
  final String aspectRatioString;
  final double aspectRatio;
  final String description;
  final bool isStreamingOptimized;

  const RecordedVideoOrientation({
    required this.label,
    required this.aspectRatioString,
    required this.aspectRatio,
    required this.description,
    required this.isStreamingOptimized,
  });
}

class MasterRecordingResult {
  final String filePath;
  final String displayRelativePath;
  final int fileSizeBytes;
  final Duration duration;
  final DateTime recordedAt;
  final bool isSimulated;
  final RecordedVideoOrientation recordedOrientation;
  final RecordingType recordingType;
  final String? metadataFilePath;
  final String? subtitlesFilePath;

  /// W trybie dual (RAW + Program) ścieżka do drugiego artefaktu (np. czystego RAW wideo)
  final String? secondaryFilePath;
  final String? secondaryDisplayRelativePath;
  final int? secondaryFileSizeBytes;
  final bool containsScoreboardOverlay;

  const MasterRecordingResult({
    required this.filePath,
    String? displayRelativePath,
    required this.fileSizeBytes,
    required this.duration,
    required this.recordedAt,
    this.isSimulated = false,
    this.recordedOrientation = RecordedVideoOrientation.landscape,
    this.recordingType = RecordingType.rawCamera,
    this.metadataFilePath,
    this.subtitlesFilePath,
    this.secondaryFilePath,
    String? secondaryDisplayRelativePath,
    this.secondaryFileSizeBytes,
    this.containsScoreboardOverlay = false,
  }) : displayRelativePath = displayRelativePath ?? filePath,
       secondaryDisplayRelativePath =
           secondaryDisplayRelativePath ?? secondaryFilePath;

  /// Czytelna ścieżka względna dla interfejsu użytkownika
  String get displayPath =>
      displayRelativePath.isNotEmpty ? displayRelativePath : filePath;

  /// Czytelna ścieżka drugiego pliku w trybie dual
  String? get secondaryDisplayPath =>
      (secondaryDisplayRelativePath != null &&
          secondaryDisplayRelativePath!.isNotEmpty)
      ? secondaryDisplayRelativePath
      : secondaryFilePath;

  /// Czy wynik zawiera dwa pliki wideo (np. RAW oraz Program z tablicą)
  bool get isDual =>
      recordingType == RecordingType.dual && secondaryFilePath != null;

  /// Etykieta proporcji wideo (np. 16:9 lub 9:16)
  String get aspectRatioString => recordedOrientation.aspectRatioString;

  /// Wartość numeryczna proporcji (np. 1.7777 lub 0.5625)
  double get aspectRatio => recordedOrientation.aspectRatio;

  /// Czy wideo nagrano w formacie zoptymalizowanym pod streaming wideo (16:9 poziomo)
  bool get isStreamingOptimized => recordedOrientation.isStreamingOptimized;

  /// Czy nagranie posiada towarzyszący plik metadanych JSON
  bool get hasMetadata =>
      metadataFilePath != null && metadataFilePath!.isNotEmpty;

  /// Czy nagranie posiada towarzyszący plik napisów z tablicą wyników
  bool get hasSubtitles =>
      subtitlesFilePath != null && subtitlesFilePath!.isNotEmpty;

  /// Nazwa pliku wyodrębniona ze ścieżki
  String get fileName {
    final normalized = filePath.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  /// Nazwa drugiego pliku (w trybie dual)
  String? get secondaryFileName {
    if (secondaryFilePath == null) return null;
    final normalized = secondaryFilePath!.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  /// Zwraca sformatowaną rozdzielczość uwzględniając orientację pliku
  String formattedResolution(int baseWidth, int baseHeight) {
    final longSide = baseWidth > baseHeight ? baseWidth : baseHeight;
    final shortSide = baseWidth > baseHeight ? baseHeight : baseWidth;
    if (recordedOrientation == RecordedVideoOrientation.landscape) {
      return '${longSide}x$shortSide (16:9)';
    } else {
      return '${shortSide}x$longSide (9:16)';
    }
  }

  /// Czytelny format rozmiaru pliku (B, KB, MB, GB)
  String get formattedSize => formatBytes(fileSizeBytes);

  /// Czytelny format rozmiaru drugiego pliku
  String get formattedSecondarySize => secondaryFileSizeBytes != null
      ? formatBytes(secondaryFileSizeBytes!)
      : '0 B';

  static String formatBytes(int bytesTotal) {
    if (bytesTotal <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var bytes = bytesTotal.toDouble();
    var suffixIndex = 0;
    while (bytes >= 1024 && suffixIndex < suffixes.length - 1) {
      bytes /= 1024;
      suffixIndex++;
    }
    return '${bytes.toStringAsFixed(suffixIndex == 0 ? 0 : 1)} ${suffixes[suffixIndex]}';
  }

  /// Czytelny format czasu trwania (hh:mm:ss lub mm:ss)
  String get formattedDuration {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (hours > 0) {
      return '${twoDigits(hours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  MasterRecordingResult copyWith({
    String? filePath,
    String? displayRelativePath,
    int? fileSizeBytes,
    Duration? duration,
    DateTime? recordedAt,
    bool? isSimulated,
    RecordedVideoOrientation? recordedOrientation,
    RecordingType? recordingType,
    String? metadataFilePath,
    String? subtitlesFilePath,
    String? secondaryFilePath,
    String? secondaryDisplayRelativePath,
    int? secondaryFileSizeBytes,
    bool? containsScoreboardOverlay,
  }) {
    return MasterRecordingResult(
      filePath: filePath ?? this.filePath,
      displayRelativePath: displayRelativePath ?? this.displayRelativePath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      duration: duration ?? this.duration,
      recordedAt: recordedAt ?? this.recordedAt,
      isSimulated: isSimulated ?? this.isSimulated,
      recordedOrientation: recordedOrientation ?? this.recordedOrientation,
      recordingType: recordingType ?? this.recordingType,
      metadataFilePath: metadataFilePath ?? this.metadataFilePath,
      subtitlesFilePath: subtitlesFilePath ?? this.subtitlesFilePath,
      secondaryFilePath: secondaryFilePath ?? this.secondaryFilePath,
      secondaryDisplayRelativePath:
          secondaryDisplayRelativePath ?? this.secondaryDisplayRelativePath,
      secondaryFileSizeBytes:
          secondaryFileSizeBytes ?? this.secondaryFileSizeBytes,
      containsScoreboardOverlay:
          containsScoreboardOverlay ?? this.containsScoreboardOverlay,
    );
  }

  @override
  String toString() {
    return 'MasterRecordingResult(file: $fileName, type: ${recordingType.shortLabel}, size: $formattedSize, duration: $formattedDuration, dual: $isDual, orientation: ${recordedOrientation.label}, simulated: $isSimulated)';
  }
}
