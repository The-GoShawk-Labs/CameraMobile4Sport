import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volleylive/core/security/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SecureStorageService Tests', () {
    test('Encrypts and stores stream key, returns safe reference', () async {
      const sampleKey = 'live_yt_123456_super_secret_stream_key';
      final ref = await SecureStorageService.storeCredential(credentialValue: sampleKey);

      expect(ref.startsWith('cred_ref_'), isTrue);

      // Upewnij się, że w surowym SharedPreferences NIE MA jawnego tekstu klucza
      final prefs = await SharedPreferences.getInstance();
      final storedRaw = prefs.getString('sec_vault_$ref');
      expect(storedRaw, isNotNull);
      expect(storedRaw!.contains(sampleKey), isFalse); // Brak plaintextu!

      // Odszyfrowanie z referencji
      final decrypted = await SecureStorageService.getCredential(ref);
      expect(decrypted, equals(sampleKey));
    });

    test('Masks credential reference safely for UI display', () {
      final masked = SecureStorageService.maskCredential('cred_ref_sample_id_99');
      expect(masked.startsWith('•••• •••• •••• '), isTrue);
    });
  });
}
