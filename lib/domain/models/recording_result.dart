class MasterRecordingResult {
  final String filePath;
  final int fileSizeBytes;
  final Duration duration;
  final DateTime recordedAt;
  final bool isSimulated;

  const MasterRecordingResult({
    required this.filePath,
    required this.fileSizeBytes,
    required this.duration,
    required this.recordedAt,
    this.isSimulated = false,
  });

  /// Nazwa pliku wyodrębniona ze ścieżki
  String get fileName {
    final normalized = filePath.replaceAll('\\', '/');
    return normalized.split('/').last;
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
    return 'MasterRecordingResult(file: $fileName, size: $formattedSize, duration: $formattedDuration, simulated: $isSimulated)';
  }
}
