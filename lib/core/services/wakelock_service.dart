import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Serwis zarządzający blokadą wygaszania ekranu urządzenia (Wakelock).
/// Zabezpiecza:
/// 1. Phone A: tryb statywu ("ustaw i zostaw"), gwarantując ciągły podgląd i transmisję bez uśpienia urządzenia.
/// 2. Phone B: pracę sędziego / operatora punktacji podczas aktywnego meczu lub nagrywania.
class WakelockService {
  static bool _lastState = false;
  static bool? _mockEnabledForTesting;

  /// Czy blokada wygaszania ekranu jest obecnie aktywna.
  static Future<bool> isEnabled() async {
    if (_mockEnabledForTesting != null) {
      return _mockEnabledForTesting!;
    }
    try {
      return await WakelockPlus.enabled;
    } catch (e) {
      developer.log('WakelockService.isEnabled error: $e', name: 'WakelockService');
      return _lastState;
    }
  }

  /// Włącza blokadę wygaszania ekranu (ekran pozostaje stale włączony).
  static Future<void> enable() async {
    if (_mockEnabledForTesting != null) {
      _mockEnabledForTesting = true;
      _lastState = true;
      return;
    }
    try {
      await WakelockPlus.enable();
      _lastState = true;
    } catch (e) {
      developer.log('WakelockService.enable failed: $e', name: 'WakelockService');
    }
  }

  /// Wyłącza blokadę wygaszania ekranu (przywraca domyślne zachowanie systemu).
  static Future<void> disable() async {
    if (_mockEnabledForTesting != null) {
      _mockEnabledForTesting = false;
      _lastState = false;
      return;
    }
    try {
      await WakelockPlus.disable();
      _lastState = false;
    } catch (e) {
      developer.log('WakelockService.disable failed: $e', name: 'WakelockService');
    }
  }

  /// Przełącza stan blokady w zależności od parametru [enableLock].
  static Future<void> setEnabled(bool enableLock) async {
    if (enableLock) {
      await enable();
    } else {
      await disable();
    }
  }

  /// Pomocnicza metoda dla testów jednostkowych.
  @visibleForTesting
  static void setMockForTesting(bool? isEnabled) {
    _mockEnabledForTesting = isEnabled;
    if (isEnabled != null) {
      _lastState = isEnabled;
    }
  }
}
