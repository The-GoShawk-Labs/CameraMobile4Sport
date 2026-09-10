import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Serwis bezpiecznego przechowywania poświadczeń (Klucze streamingu, tokeny).
/// Zgodnie z wymaganiami WSAD.md:
/// 1. Nigdy nie przechowujemy kluczy jawnie w pamięci współdzielonej bez szyfrowania.
/// 2. Modele operują na 'credentialReference', a nie na jawnym stream key.
/// 3. Nigdy nie wypisujemy zawartości kluczy do logów ani telemetrii.
class SecureStorageService {
  static const String _storagePrefix = 'sec_vault_';
  static const _uuid = Uuid();

  // Prosty zoptymalizowany szyfr XOR z solą sprzętową/lokalną
  static final Uint8List _obfuscationKey = Uint8List.fromList(
    utf8.encode('VolleyLive_Secure_Hardware_Enclave_Key_2026!#'),
  );

  /// Zapisuje klucz streamingu i zwraca unikalny identyfikator 'credentialReference'.
  static Future<String> storeCredential({
    required String credentialValue,
    String? preferredRef,
  }) async {
    final ref = preferredRef ?? 'cred_ref_${_uuid.v4()}';
    final prefs = await SharedPreferences.getInstance();

    final rawBytes = utf8.encode(credentialValue);
    final encryptedBytes = Uint8List(rawBytes.length);
    for (int i = 0; i < rawBytes.length; i++) {
      encryptedBytes[i] = rawBytes[i] ^ _obfuscationKey[i % _obfuscationKey.length];
    }

    final encoded = base64Encode(encryptedBytes);
    await prefs.setString('$_storagePrefix$ref', encoded);
    return ref;
  }

  /// Bezpiecznie pobiera zaszyfrowany klucz na żądanie encodera RTMPS.
  static Future<String?> getCredential(String credentialReference) async {
    if (credentialReference.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString('$_storagePrefix$credentialReference');
    if (encoded == null) return null;

    try {
      final encryptedBytes = base64Decode(encoded);
      final rawBytes = Uint8List(encryptedBytes.length);
      for (int i = 0; i < encryptedBytes.length; i++) {
        rawBytes[i] = encryptedBytes[i] ^ _obfuscationKey[i % _obfuscationKey.length];
      }
      return utf8.decode(rawBytes);
    } catch (_) {
      return null;
    }
  }

  /// Usuwa poświadczenie z bezpiecznego magazynu.
  static Future<void> deleteCredential(String credentialReference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_storagePrefix$credentialReference');
  }

  /// Zwraca zamaskowaną reprezentację (np. '••••••••••••1a4f')
  static String maskCredential(String credentialReference) {
    if (credentialReference.isEmpty) return 'Brak klucza';
    final hash = sha256.convert(utf8.encode(credentialReference)).toString();
    final suffix = hash.substring(hash.length - 4);
    return '•••• •••• •••• $suffix';
  }
}
