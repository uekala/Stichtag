import 'dart:convert';

import 'api.dart';
import 'logic.dart';
import 'session_store.dart';

/// Nutzung ohne Server: Der Datenstand liegt verschlüsselt auf dem Handy.
/// Es gibt nur dieses eine Gerät, also auch keine Konflikte.
class LocalStichtagApi implements StichtagApi {
  LocalStichtagApi(this._store);

  final StateCache _store;

  @override
  Future<Json> getState() async {
    final encoded = await _store.read();
    if (encoded == null) return blankState();
    try {
      final data = jsonDecode(encoded);
      return data is Map ? Map<String, dynamic>.from(data) : blankState();
    } on FormatException {
      throw const ApiException(
        'Die gespeicherten Daten sind nicht lesbar. Spiele eine Sicherung ein.',
      );
    }
  }

  @override
  Future<Json> putState(Json state) async {
    final rev = toInt(state['rev']) + 1;
    await _store.write(
      jsonEncode(Map<String, dynamic>.from(state)..['rev'] = rev),
    );
    return <String, dynamic>{'rev': rev};
  }

  @override
  Future<Json> pair(String pairingSecret, String deviceName) async =>
      throw const ApiException('Ohne Server gibt es keine Kopplung.');

  @override
  Future<void> logout() async {}
}
