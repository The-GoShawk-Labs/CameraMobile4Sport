/// Orientacja, w jakiej nagrany został plik wideo
enum RecordedVideoOrientation {
  landscape(
    label: 'Poziomo (16:9)',
    aspectRatioString: '16:9',
    aspectRatio: 16 / 9,
    description: 'Format 16:9 (zoptymalizowany pod platformy streamingowe: YouTube, Twitch, OBS)',
    isStreamingOptimized: true,
  ),
  portrait(
    label: 'Pionowo (9:16)',
    aspectRatioString: '9:16',
    aspectRatio: 9 / 16,
    description: 'Format 9:16 (zoptymalizowany pod formaty pionowe: Shorts, Reels, TikTok)',
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

  const MasterRecordingResult({
    required this.filePath,
    String? displayRelativePath,
    required this.fileSizeBytes,
    required this.duration,
    required this.recordedAt,
    this.isSimulated = false,
    this.recordedOrientation = RecordedVideoOrientation.landscape,
  }) : displayRelativePath = displayRelativePath ?? filePath;

  /// Czytelna ścieżka względna dla interfejsu użytkownika
  String get displayPath => displayRelativePath.isNotEmpty ? displayRelativePath : filePath;

  /// Etykieta proporcji wideo (np. 16:9 lub 9:16)
  String get aspectRatioString => recordedOrientation.aspectRatioString;

  /// Wartość numeryczna proporcji (np. 1.7777 lub 0.5625)
  double get aspectRatio => recordedOrientation.aspectRatio;

  /// Czy wideo nagrano w formacie zoptymalizowanym pod streaming wideo (16:9 poziomo)
  bool get isStreamingOptimized => recordedOrientation.isStreamingOptimized;

  /// Nazwa pliku wyodrębniona ze ścieżki
  String get fileName {
    final normalized = filePath.replaceAll('\\', '/');
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
  String get formattedSize {
    if (fileSizeBytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var bytes = fileSizeBytes.toDouble();
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

  @override
  String toString() {
    return 'MasterRecordingResult(file: $fileName, size: $formattedSize, duration: $formattedDuration, orientation: ${recordedOrientation.label}, format: $aspectRatioString, simulated: $isSimulated)';
  }
}
