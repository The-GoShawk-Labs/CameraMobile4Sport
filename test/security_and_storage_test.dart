import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volleylive/core/security/secure_storage_service.dart';
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
}
