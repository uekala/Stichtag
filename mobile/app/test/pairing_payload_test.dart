import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stichtag_mobile/core/pairing_payload.dart';

String payload(Map<String, dynamic> overrides) => jsonEncode(<String, dynamic>{
  'type': 'stichtag-pairing',
  'version': 1,
  'server_url': 'https://stichtag.example.ts.net',
  'pairing_secret': 'A' * 43,
  ...overrides,
});

void main() {
  test('liest einen gültigen Kopplungscode', () {
    final parsed = PairingPayload.fromRawValue(payload({}));
    expect(parsed.serverUrl, 'https://stichtag.example.ts.net');
    expect(parsed.pairingSecret, 'A' * 43);
  });

  test('entfernt den abschließenden Schrägstrich der Adresse', () {
    final parsed = PairingPayload.fromRawValue(
      payload({'server_url': 'https://stichtag.example.ts.net/'}),
    );
    expect(parsed.serverUrl, 'https://stichtag.example.ts.net');
  });

  test('lehnt Adressen ohne HTTPS ab', () {
    expect(
      () => PairingPayload.fromRawValue(
        payload({'server_url': 'http://192.168.1.10:8098'}),
      ),
      throwsFormatException,
    );
  });

  test('lehnt fremde und unvollständige Codes ab', () {
    expect(() => PairingPayload.fromRawValue('hallo'), throwsFormatException);
    expect(
      () => PairingPayload.fromRawValue(payload({'type': 'anderes'})),
      throwsFormatException,
    );
    expect(
      () => PairingPayload.fromRawValue(payload({'pairing_secret': 'kurz'})),
      throwsFormatException,
    );
  });
}
