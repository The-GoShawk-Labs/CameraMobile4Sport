import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volleylive/core/security/secure_storage_service.dart';
import 'package:volleylive/core/services/video_storage_service.dart';
import 'package:volleylive/core/services/wakelock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SecureStorageService.setStorageForTesting(null);
    WakelockService.setMockForTesting(null);
  });

  group('SecureStorageService Tests (FlutterSecureStorage)', () {
    test('Stores and retrieves credential safely via secure storage', () async {
      const sampleKey = 'live_yt_123456_super_secret_stream_key';
      final ref = await SecureStorageService.storeCredential(credentialValue: sampleKey);

      expect(ref.startsWith('cred_ref_'), isTrue);

      // Potwierdź, że SharedPreferences NIE zawiera żadnego klucza ani plaintextu
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(prefs.getString('sec_vault_$ref'), isNull);

      // Bezpieczny odczyt z magazynu kluczy
      final retrieved = await SecureStorageService.getCredential(ref);
      expect(retrieved, equals(sampleKey));
    });

    test('Supports preferred reference identifier', () async {
      const preferred = 'cred_ref_custom_tripod_primary';
      const sampleKey = 'rtmps://live.twitch.tv/app/secret_pass';

      final ref = await SecureStorageService.storeCredential(
        credentialValue: sampleKey,
        preferredRef: preferred,
      );

      expect(ref, equals(preferred));
      final retrieved = await SecureStorageService.getCredential(ref);
      expect(retrieved, equals(sampleKey));
    });

    test('Deletes credential from secure storage', () async {
      const sampleKey = 'temp_token_to_delete';
      final ref = await SecureStorageService.storeCredential(credentialValue: sampleKey);

      final beforeDelete = await SecureStorageService.getCredential(ref);
      expect(beforeDelete, equals(sampleKey));

      await SecureStorageService.deleteCredential(ref);

      final afterDelete = await SecureStorageService.getCredential(ref);
      expect(afterDelete, isNull);
    });

    test('Returns null for empty or invalid reference', () async {
      expect(await SecureStorageService.getCredential(''), isNull);
      expect(await SecureStorageService.getCredential('cred_ref_non_existent_id'), isNull);
    });

    test('Masks credential reference safely for UI display', () {
      final masked = SecureStorageService.maskCredential('cred_ref_sample_id_99');
      expect(masked.startsWith('•••• •••• •••• '), isTrue);
      expect(masked.length, equals(19));

      final emptyMasked = SecureStorageService.maskCredential('');
      expect(emptyMasked, equals('Brak klucza'));
    });
  });

  group('WakelockService Tests', () {
    test('Enables and disables wakelock with mock fallback', () async {
      WakelockService.setMockForTesting(false);
      expect(await WakelockService.isEnabled(), isFalse);

      await WakelockService.enable();
      expect(await WakelockService.isEnabled(), isTrue);

      await WakelockService.disable();
      expect(await WakelockService.isEnabled(), isFalse);

      await WakelockService.setEnabled(true);
      expect(await WakelockService.isEnabled(), isTrue);

      await WakelockService.setEnabled(false);
      expect(await WakelockService.isEnabled(), isFalse);
    });
  });

  group('VideoStorageService Tests (Relative Paths & Folder Selection)', () {
    late VideoStorageService storageService;

    setUp(() {
      storageService = VideoStorageService();
    });

    test('Sanitizes folder names correctly', () {
      expect(VideoStorageService.sanitizeFolderName('  Movies/CameraMobile4Sport/mecze  '), equals('Movies/CameraMobile4Sport/mecze'));
      expect(VideoStorageService.sanitizeFolderName('/Movies/CameraMobile4Sport/mecze/'), equals('Movies/CameraMobile4Sport/mecze'));
      expect(VideoStorageService.sanitizeFolderName('Movies//CameraMobile4Sport//treningi'), equals('Movies/CameraMobile4Sport/treningi'));
      expect(VideoStorageService.sanitizeFolderName('invalid:name*with?chars'), equals('invalidnamewithchars'));
      expect(VideoStorageService.sanitizeFolderName('../traversal/attempt'), equals('traversal/attempt'));
      expect(VideoStorageService.sanitizeFolderName('   '), equals('Movies/CameraMobile4Sport/mecze'));
    });

    test('Contains standard default presets', () {
      final presets = VideoStorageService.defaultPresets;
      expect(presets.length, greaterThanOrEqualTo(4));
      expect(presets.any((p) => p.id == 'matches' && p.relativeSubPath == 'Movies/CameraMobile4Sport/mecze'), isTrue);
      expect(presets.any((p) => p.id == 'trainings' && p.relativeSubPath == 'Movies/CameraMobile4Sport/treningi'), isTrue);
      expect(presets.any((p) => p.id == 'tournaments' && p.relativeSubPath == 'Movies/CameraMobile4Sport/turnieje'), isTrue);
      expect(presets.any((p) => p.id == 'private_sandbox' && p.relativeSubPath == 'master_rec'), isTrue);
    });

    test('Converts full paths to user-friendly relative display paths', () {
      final appPath = '/data/user/0/com.volleylive.app/app_flutter/master_rec/mecze/MASTER_REC_20260917.mp4';
      expect(storageService.toRelativeDisplayPath(appPath), equals('[Pamięć Aplikacji] / master_rec/mecze/MASTER_REC_20260917.mp4'));

      final moviePath = '/storage/emulated/0/Movies/VolleyLive/MASTER_REC_20260917.mp4';
      expect(storageService.toRelativeDisplayPath(moviePath), equals('[Pamięć Telefonu] / Movies/VolleyLive/MASTER_REC_20260917.mp4'));

      final testPath = 'C:/Temp/volleylive_master_rec_turnieje/MASTER_REC_2026.mp4';
      expect(storageService.toRelativeDisplayPath(testPath), contains('[Pamięć Aplikacji]'));
    });

    test('Finalizes simulated recording with relative path in MasterRecordingResult', () async {
      final result = await storageService.finalizeRecording(
        sourcePath: null,
        duration: const Duration(minutes: 2),
        isSimulated: true,
        subDirectory: 'master_rec/mecze',
      );

      expect(result.isSimulated, isTrue);
      expect(result.duration, equals(const Duration(minutes: 2)));
      expect(result.displayPath, contains('[Pamięć Aplikacji]'));
      expect(result.fileName.startsWith('MASTER_REC_'), isTrue);
      expect(result.fileName.endsWith('.mp4'), isTrue);
    });
  });
}
