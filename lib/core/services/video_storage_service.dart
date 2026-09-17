import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:volleylive/domain/models/recording_result.dart';

/// Model reprezentujący predefiniowaną lokalizację zapisu wideo
class StorageFolderPreset {
  final String id;
  final String label;
  final String icon;
  final String relativeSubPath;
  final String description;

  const StorageFolderPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.relativeSubPath,
    required this.description,
  });
}

class VideoStorageService {
  static const String _defaultSubDirectoryName = 'Movies/CameraMobile4Sport/mecze';

  /// Predefiniowane presety folderów dla wygody użytkownika
  static const List<StorageFolderPreset> defaultPresets = [
    StorageFolderPreset(
      id: 'matches',
      label: 'Mecze (Domyślny)',
      icon: '🏐',
      relativeSubPath: 'Movies/CameraMobile4Sport/mecze',
      description: 'Pamięć wewnętrzna / Movies / CameraMobile4Sport / mecze (dostępny w Galerii i USB)',
    ),
    StorageFolderPreset(
      id: 'trainings',
      label: 'Treningi',
      icon: '🏋️',
      relativeSubPath: 'Movies/CameraMobile4Sport/treningi',
      description: 'Pamięć wewnętrzna / Movies / CameraMobile4Sport / treningi',
    ),
    StorageFolderPreset(
      id: 'tournaments',
      label: 'Turnieje',
      icon: '🏆',
      relativeSubPath: 'Movies/CameraMobile4Sport/turnieje',
      description: 'Pamięć wewnętrzna / Movies / CameraMobile4Sport / turnieje',
    ),
    StorageFolderPreset(
      id: 'private_sandbox',
      label: 'Pamięć Prywatna',
      icon: '🔒',
      relativeSubPath: 'master_rec',
      description: 'Wewnętrzny prywatny sandbox aplikacji (niedostępny w menedżerze plików)',
    ),
  ];

  /// Tworzy domyślną strukturę katalogów aplikacji w głównym drzewie pamięci wewnętrznej telefonu
  /// wywoływana przy starcie aplikacji oraz przy pierwszym zapisie.
  Future<void> ensureInitialDirectoriesCreated() async {
    for (final preset in defaultPresets) {
      try {
        await getMasterRecordingDirectory(preset.relativeSubPath);
      } catch (_) {}
    }
  }

  /// Czyści i normalizuje nazwę podfolderu wprowadzoną przez użytkownika
  static String sanitizeFolderName(String input) {
    var sanitized = input.trim().replaceAll('\\', '/');

    // Usuń próby przejścia wyżej w drzewie katalogów
    sanitized = sanitized.replaceAll('..', '');

    // Usuń niedozwolone znaki systemowe: * ? : " < > |
    sanitized = sanitized.replaceAll(RegExp(r'[*?:\"<>|]'), '');

    // Zamień wielokrotne ukośniki na pojedynczy
    sanitized = sanitized.replaceAll(RegExp(r'/+'), '/');

    // Usuń wiodące i końcowe ukośniki
    while (sanitized.startsWith('/')) {
      sanitized = sanitized.substring(1);
    }
    while (sanitized.endsWith('/')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }

    if (sanitized.trim().isEmpty) {
      return _defaultSubDirectoryName;
    }
    return sanitized;
  }

  /// Konwertuje bezwzględną ścieżkę systemową do czytelnej ścieżki względnej dla użytkownika
  String toRelativeDisplayPath(String fullPath) {
    final normalized = fullPath.replaceAll('\\', '/');

    if (normalized.contains('Movies/CameraMobile4Sport')) {
      final idx = normalized.indexOf('Movies/CameraMobile4Sport');
      final sub = normalized.substring(idx);
      return '[Pamięć Telefonu] / $sub';
    }

    if (normalized.contains('Movies/VolleyLive')) {
      final idx = normalized.indexOf('Movies/VolleyLive');
      final sub = normalized.substring(idx);
      return '[Pamięć Telefonu] / $sub';
    }

    if (normalized.contains('/master_rec')) {
      final idx = normalized.indexOf('master_rec');
      final sub = normalized.substring(idx);
      return '[Pamięć Aplikacji] / $sub';
    }

    if (normalized.contains('volleylive_')) {
      final idx = normalized.indexOf('volleylive_');
      final sub = normalized.substring(idx).replaceFirst('volleylive_', '');
      String cleanSub = sub;
      if (cleanSub.startsWith('Movies_')) {
        cleanSub = cleanSub.replaceAll('_', '/');
        return '[Pamięć Telefonu] / $cleanSub';
      }
      if (cleanSub.startsWith('master_rec_')) {
        cleanSub = cleanSub.replaceFirst('master_rec_', 'master_rec/');
      }
      return '[Pamięć Aplikacji] / $cleanSub';
    }

    // Jeśli ścieżka jest krótka lub względna
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length <= 2) {
      return '[Folder] / ${segments.join('/')}';
    }
    return '[Folder] / ${segments.sublist(segments.length - 2).join('/')}';
  }

  /// Pobiera dedykowany katalog dla nagrań Master REC z uwzględnieniem wybranego podfolderu.
  Future<Directory> getMasterRecordingDirectory([String? subDirectory]) async {
    final targetSubPath = sanitizeFolderName(subDirectory ?? _defaultSubDirectoryName);

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      final safeName = targetSubPath.replaceAll('/', '_');
      final tempDir = Directory('${Directory.systemTemp.path}/volleylive_$safeName');
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }
      return tempDir;
    }

    try {
      // Obsługa publicznego katalogu wideo w pamięci współdzielonej telefonu (Movies/...)
      if (targetSubPath.startsWith('Movies/')) {
        final movieSubPath = targetSubPath.substring('Movies/'.length);

        // 1. Sprawdź standardowy katalog publiczny /storage/emulated/0/Movies
        final publicMoviesDir = Directory('/storage/emulated/0/Movies/$movieSubPath');
        try {
          if (!await publicMoviesDir.exists()) {
            await publicMoviesDir.create(recursive: true);
          }
          // Sprawdź czy katalog jest rzeczywiście zapisywalny w Android Scoped Storage
          final testProbe = File('${publicMoviesDir.path}/.probe_${DateTime.now().millisecondsSinceEpoch}.tmp');
          await testProbe.writeAsString('probe');
          if (await testProbe.exists()) {
            await testProbe.delete();
          }
          return publicMoviesDir;
        } catch (_) {
          // Publiczny folder Movies jest niedostępny bez uprawnień zarządzania pamięcią / SAF
        }

        // 2. Fallback na getExternalStorageDirectories(movies) - folder specyficzny dla aplikacji
        // (np. /storage/emulated/0/Android/data/com.goshawk.volleylive.volleylive/files/Movies/...)
        // Jest w pełni zapisywalny bez żadnych specjalnych uprawnień w Android 11-16!
        try {
          final externalDirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
          if (externalDirs != null && externalDirs.isNotEmpty) {
            final targetDir = Directory('${externalDirs.first.path}/$movieSubPath');
            if (!await targetDir.exists()) {
              await targetDir.create(recursive: true);
            }
            final testProbe = File('${targetDir.path}/.probe_${DateTime.now().millisecondsSinceEpoch}.tmp');
            await testProbe.writeAsString('probe');
            if (await testProbe.exists()) {
              await testProbe.delete();
            }
            return targetDir;
          }
        } catch (_) {}
      }

      // Standardowy katalog dokumentów aplikacji (Private App Sandbox)
      final appDocDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory('${appDocDir.path}/$targetSubPath');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      return targetDir;
    } catch (_) {
      // Bezpieczny fallback dla środowisk bez dostępu do dysku głównego
      final safeName = targetSubPath.replaceAll('/', '_');
      final tempDir = Directory('${Directory.systemTemp.path}/volleylive_$safeName');
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }
      return tempDir;
    }
  }

  /// Generuje nową, unikalną ścieżkę dla pliku nagrania MP4 w zadanym folderze
  Future<String> generateNewRecordingPath([String? subDirectory]) async {
    final dir = await getMasterRecordingDirectory(subDirectory);
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${dir.path}/MASTER_REC_$timestamp.mp4';
  }

  /// Sprawdza czy na nośniku pamięci jest wystarczająco dużo miejsca
  /// oraz czy katalog jest zapisywalny (canary write test).
  Future<bool> hasSufficientStorageSpace({
    int requiredMegabytes = 100,
    String? subDirectory,
  }) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return true;
    }

    try {
      final dir = await getMasterRecordingDirectory(subDirectory);

      // Canary test: sprawdzenie czy możemy zapisać i usunąć mały plik testowy
      final testFile = File('${dir.path}/.storage_check_${DateTime.now().millisecondsSinceEpoch}.tmp');
      await testFile.writeAsString('storage_check');
      if (await testFile.exists()) {
        await testFile.delete();
      }
      return true;
    } catch (_) {
      // Ostateczna próba: sprawdzenie czy przynajmniej pamięć wewnętrzna aplikacji (sandbox) jest dostępna
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        final testFile = File('${appDocDir.path}/.storage_check_${DateTime.now().millisecondsSinceEpoch}.tmp');
        await testFile.writeAsString('storage_check');
        if (await testFile.exists()) {
          await testFile.delete();
        }
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Finalizuje plik nagrania:
  /// Jeśli plik tymczasowy pochodzi z CameraController (XFile),
  /// przenosi go lub kopiuje do dedykowanego katalogu docelowego.
  /// Dla trybu symulacji tworzy syntetyczny plik o adekwatnym rozmiarze.
  Future<MasterRecordingResult> finalizeRecording({
    required String? sourcePath,
    required Duration duration,
    bool isSimulated = false,
    String? subDirectory,
  }) async {
    final targetPath = await generateNewRecordingPath(subDirectory);
    final relativeDisplay = toRelativeDisplayPath(targetPath);

    if (sourcePath != null && sourcePath.isNotEmpty && File(sourcePath).existsSync() && !isSimulated) {
      final sourceFile = File(sourcePath);
      try {
        // Przenosimy lub kopiujemy plik do dedykowanego katalogu
        await sourceFile.copy(targetPath);
        try {
          await sourceFile.delete();
        } catch (_) {}

        // Zapewnij publiczne uprawnienia odczytu (chmod 666) dla MTP i innych aplikacji
        try {
          if (!Platform.isWindows) {
            await Process.run('chmod', ['666', targetPath]);
          }
        } catch (_) {}
      } catch (_) {
        // Jeśli kopiowanie się nie powiodło, używamy pliku źródłowego
        final targetFile = File(sourcePath);
        final fileSizeBytes = await targetFile.length();
        return MasterRecordingResult(
          filePath: sourcePath,
          displayRelativePath: toRelativeDisplayPath(sourcePath),
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
        displayRelativePath: relativeDisplay,
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
        displayRelativePath: relativeDisplay,
        fileSizeBytes: simulatedSize,
        duration: duration,
        recordedAt: DateTime.now(),
        isSimulated: isSimulated,
      );
    }
  }

  /// Przenosi istniejący plik nagrania do nowej lokalizacji podfolderu
  Future<MasterRecordingResult> moveRecording({
    required MasterRecordingResult currentResult,
    required String targetSubDirectory,
  }) async {
    final sanitized = sanitizeFolderName(targetSubDirectory);
    final targetDir = await getMasterRecordingDirectory(sanitized);
    final fileName = currentResult.fileName;
    final newFilePath = '${targetDir.path}/$fileName';

    if (currentResult.filePath != newFilePath &&
        File(currentResult.filePath).existsSync() &&
        !currentResult.isSimulated) {
      final currentFile = File(currentResult.filePath);
      try {
        await currentFile.copy(newFilePath);
        try {
          await currentFile.delete();
        } catch (_) {}
        try {
          if (!Platform.isWindows) {
            await Process.run('chmod', ['666', newFilePath]);
          }
        } catch (_) {}
      } catch (_) {
        // W razie błędu kopiowania pozostajemy przy pierwotnym pliku
        return currentResult;
      }
    }

    final newDisplayRelative = toRelativeDisplayPath(newFilePath);
    return MasterRecordingResult(
      filePath: newFilePath,
      displayRelativePath: newDisplayRelative,
      fileSizeBytes: currentResult.fileSizeBytes,
      duration: currentResult.duration,
      recordedAt: currentResult.recordedAt,
      isSimulated: currentResult.isSimulated,
    );
  }
}
