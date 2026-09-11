import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Serwis bezpiecznego przechowywania poświadczeń (Klucze streamingu, tokeny)
/// oparty o natywny magazyn kluczy (Android Keystore / iOS Keychain) poprzez flutter_secure_storage.
/// Zgodnie z wymaganiami WSAD.md:
/// 1. Nigdy nie przechowujemy kluczy jawnie w SharedPreferences.
/// 2. Modele operują na 'credentialReference', a nie na jawnym stream key.
/// 3. Nigdy nie wypisujemy zawartości kluczy do logów ani telemetrii.
class SecureStorageService {
  static const String _storagePrefix = 'sec_vault_';
  static const _uuid = Uuid();

  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  static FlutterSecureStorage? _customStorage;

  static FlutterSecureStorage get _storage =>
      _customStorage ??
      const FlutterSecureStorage(
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );

  /// Pozwala na wstrzyknięcie dedykowanego magazynu (np. w testach jednostkowych).
  static void setStorageForTesting(FlutterSecureStorage? storage) {
    _customStorage = storage;
  }

  /// Zapisuje klucz streamingu i zwraca unikalny identyfikator 'credentialReference'.
  static Future<String> storeCredential({
    required String credentialValue,
    String? preferredRef,
  }) async {
    final ref = preferredRef ?? 'cred_ref_${_uuid.v4()}';
    await _storage.write(
      key: '$_storagePrefix$ref',
      value: credentialValue,
      aOptions: _androidOptions,
      iOptions: _iosOptions,
    );
    return ref;
  }

  /// Bezpiecznie pobiera zaszyfrowany klucz z Keystore/Keychain na żądanie encodera RTMPS.
  static Future<String?> getCredential(String credentialReference) async {
    if (credentialReference.isEmpty) return null;
    try {
      return await _storage.read(
        key: '$_storagePrefix$credentialReference',
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
    } catch (_) {
      return null;
    }
  }

  /// Usuwa poświadczenie z bezpiecznego magazynu.
  static Future<void> deleteCredential(String credentialReference) async {
    if (credentialReference.isEmpty) return;
    try {
      await _storage.delete(
        key: '$_storagePrefix$credentialReference',
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
    } catch (_) {}
  }

  /// Zwraca zamaskowaną reprezentację (np. '•••• •••• •••• 1a4f')
  static String maskCredential(String credentialReference) {
    if (credentialReference.isEmpty) return 'Brak klucza';
    final hash = sha256.convert(utf8.encode(credentialReference)).toString();
    final suffix = hash.substring(hash.length - 4);
    return '•••• •••• •••• $suffix';
  }
}
