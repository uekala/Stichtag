import 'dart:convert';

/// Prüft die Serveradresse: nur HTTPS, ohne Pfad, Abfrage oder Zugangsdaten.
String normalizeServerUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException(
      'Die Serveradresse muss eine HTTPS-Adresse ohne Pfad sein.',
    );
  }
  return uri.origin;
}

/// Einmaliger Kopplungscode aus der Stichtag-Oberfläche in Home Assistant.
class PairingPayload {
  const PairingPayload({required this.serverUrl, required this.pairingSecret});

  static const type = 'stichtag-pairing';
  static const version = 1;

  final String serverUrl;
  final String pairingSecret;

  factory PairingPayload.fromRawValue(String rawValue) {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawValue.trim());
    } on FormatException {
      throw const FormatException('Das ist kein Stichtag-Kopplungscode.');
    }
    if (decoded is! Map ||
        decoded['type'] != type ||
        decoded['version'] != version) {
      throw const FormatException(
        'Dieser Code wird von Stichtag nicht unterstützt.',
      );
    }
    final serverUrl = decoded['server_url'];
    final secret = decoded['pairing_secret'];
    if (serverUrl is! String ||
        secret is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(secret)) {
      throw const FormatException(
        'Der Kopplungscode ist unvollständig oder ungültig.',
      );
    }
    return PairingPayload(
      serverUrl: normalizeServerUrl(serverUrl),
      pairingSecret: secret,
    );
  }
}
