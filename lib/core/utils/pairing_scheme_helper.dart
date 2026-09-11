class PairingData {
  final String host;
  final int port;
  final String code;

  const PairingData({
    required this.host,
    required this.port,
    required this.code,
  });

  String get uri => PairingSchemeHelper.buildUri(host: host, port: port, code: code);

  @override
  String toString() => 'PairingData(host: $host, port: $port, code: $code)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PairingData &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          code == other.code;

  @override
  int get hashCode => Object.hash(host, port, code);
}

/// Narzędzie pomocnicze dla schematu parowania VolleyLive:
/// `volleylive://<HOST_IP>:<PORT>/<PAIRING_CODE>`
class PairingSchemeHelper {
  static const String defaultScheme = 'volleylive';
  static const int defaultPort = 8080;
  static const String fallbackHost = '127.0.0.1';

  /// Tworzy pełny URI parowania w formacie: `volleylive://<HOST_IP>:<PORT>/<PAIRING_CODE>`
  static String buildUri({
    required String host,
    int port = defaultPort,
    required String code,
  }) {
    final sanitizedHost = host.trim();
    final sanitizedCode = code.trim();
    return '$defaultScheme://$sanitizedHost:$port/$sanitizedCode';
  }

  /// Wyodrębnia dane parowania z odczytanego kodu QR lub tekstu.
  ///
  /// Obsługuje:
  /// - Pełny schemat: `volleylive://192.168.1.150:8080/VL-8492`
  /// - Schemat bez portu: `volleylive://192.168.1.150/VL-8492` (domyślny port 8080)
  /// - Starszy schemat: `volleylive://VL-8492` (domyślny localhost i port 8080)
  /// - Sam kod PIN: `VL-8492`
  static PairingData? parse(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == defaultScheme) {
      final host = uri.host.trim();
      final port = uri.hasPort ? uri.port : defaultPort;
      final pathSegments = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();

      if (pathSegments.isNotEmpty) {
        final code = pathSegments.first.trim();
        if (host.isNotEmpty && code.isNotEmpty) {
          return PairingData(host: host, port: port, code: code);
        }
      }

      // Przypadek: volleylive://VL-8492 (gdzie PIN trafił w uri.host)
      if (host.isNotEmpty && pathSegments.isEmpty) {
        final rawHost = trimmed.substring('$defaultScheme://'.length).split('/').first.split(':').first.trim();
        return PairingData(host: fallbackHost, port: defaultPort, code: rawHost);
      }
    }

    // Obsługa zwykłego wpisu tekstowego / samego kodu PIN
    if (trimmed.isNotEmpty) {
      return PairingData(host: fallbackHost, port: defaultPort, code: trimmed);
    }

    return null;
  }
}
