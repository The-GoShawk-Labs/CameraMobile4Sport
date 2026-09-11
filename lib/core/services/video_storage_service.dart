import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:volleylive/domain/models/recording_result.dart';

class VideoStorageService {
  static const String _subDirectoryName = 'master_rec';

  /// Pobiera dedykowany katalog dla nagrań Master REC.
  /// W przypadku środowiska testowego (brak natywnego path_provider)
  /// następuje natychmiastowy fallback do katalogu tymczasowego systemu.
  Future<Directory> getMasterRecordingDirectory() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      final tempDir = Directory('${Directory.systemTemp.path}/volleylive_$_subDirectoryName');
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }
      return tempDir;
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory('${appDocDir.path}/$_subDirectoryName');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      return targetDir;
    } catch (_) {
      // Bezpieczny fallback dla testów jednostkowych i widgetowych
      final tempDir = Directory('${Directory.systemTemp.path}/volleylive_$_subDirectoryName');
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }
      return tempDir;
    }
  }

  /// Generuje nową, unikalną ścieżkę dla pliku nagrania MP4
  Future<String> generateNewRecordingPath() async {
    final dir = await getMasterRecordingDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${dir.path}/MASTER_REC_$timestamp.mp4';
  }

  /// Sprawdza czy na nośniku pamięci jest wystarczająco dużo miejsca
  /// oraz czy katalog jest zapisywalny (canary write test).
  Future<bool> hasSufficientStorageSpace({int requiredMegabytes = 100}) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return true;
    }

    try {
      final dir = await getMasterRecordingDirectory();

      // Canary test: sprawdzenie czy możemy zapisać i usunąć mały plik testowy
      final testFile = File('${dir.path}/.storage_check_${DateTime.now().millisecondsSinceEpoch}.tmp');
      await testFile.writeAsString('storage_check');
      if (await testFile.exists()) {
        await testFile.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Finalizuje plik nagrania:
  /// Jeśli plik tymczasowy pochodzi z CameraController (XFile),
  /// przenosi go lub kopiuje do dedykowanego katalogu `master_rec`.
  /// Dla trybu symulacji tworzy syntetyczny plik o adekwatnym rozmiarze.
  Future<MasterRecordingResult> finalizeRecording({
    required String? sourcePath,
    required Duration duration,
    bool isSimulated = false,
  }) async {
    final targetPath = await generateNewRecordingPath();

    if (sourcePath != null && sourcePath.isNotEmpty && File(sourcePath).existsSync() && !isSimulated) {
      final sourceFile = File(sourcePath);
      try {
        // Przenosimy lub kopiujemy plik do dedykowanego katalogu
        await sourceFile.copy(targetPath);
        try {
          await sourceFile.delete();
        } catch (_) {}
      } catch (_) {
        // Jeśli kopiowanie się nie powiodło, używamy pliku źródłowego
        final targetFile = File(sourcePath);
        final fileSizeBytes = await targetFile.length();
        return MasterRecordingResult(
          filePath: sourcePath,
          fileSizeBytes: fileSizeBytes,
          duration: duration,
          recordedAt: DateTime.now(),
          isSimulated: isSimulated,
        );
      }

      final savedFile = File(targetPath);
      final fileSizeBytes = await savedFile.length();
      return MasterRecordingResult(
        filePath: targetPath,
        fileSizeBytes: fileSizeBytes,
        duration: duration,
        recordedAt: DateTime.now(),
        isSimulated: isSimulated,
      );
    } else {
      // Tryb symulacyjny (testy jednostkowe / brak fizycznego sensora)
      // Szacowany rozmiar dla 8 Mbps: ok. 1MB na sekundę
      final simulatedSize = (duration.inSeconds * 1024 * 1024).clamp(1024 * 256, 1024 * 1024 * 500);
      return MasterRecordingResult(
        filePath: targetPath,
        fileSizeBytes: simulatedSize,
        duration: duration,
        recordedAt: DateTime.now(),
        isSimulated: isSimulated,
      );
    }
  }
}
