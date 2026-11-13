import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Session {
  const Session({
    required this.serverUrl,
    required this.token,
    required this.deviceName,
  });

  final String serverUrl;
  final String token;
  final String deviceName;

  String toStoredJson() => jsonEncode(<String, String>{
    'server_url': serverUrl,
    'token': token,
    'device_name': deviceName,
  });

  static Session? fromStoredJson(String encoded) {
    try {
      final data = jsonDecode(encoded);
      if (data is! Map) return null;
      final serverUrl = data['server_url'];
      final token = data['token'];
      if (serverUrl is! String || token is! String || token.isEmpty) {
        return null;
      }
      final name = data['device_name'];
      return Session(
        serverUrl: serverUrl,
        token: token,
        deviceName: name is String ? name : '',
      );
    } on FormatException {
      return null;
    }
  }
}

abstract interface class SessionStore {
  Future<Session?> read();

  Future<void> write(Session session);

  Future<void> clear();
}

/// Legt Serveradresse und Gerätetoken im Schlüsselspeicher des Handys ab.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'stichtag.mobile.session.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<Session?> read() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return null;
    return Session.fromStoredJson(encoded);
  }

  @override
  Future<void> write(Session session) =>
      _storage.write(key: _key, value: session.toStoredJson());

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Für Tests.
class InMemorySessionStore implements SessionStore {
  InMemorySessionStore([this._session]);

  Session? _session;

  @override
  Future<Session?> read() async => _session;

  @override
  Future<void> write(Session session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}

/// Hält den zuletzt geladenen Stand, damit die App ohne Verbindung etwas zeigt.
abstract interface class StateCache {
  Future<String?> read();

  Future<void> write(String encoded);

  Future<void> clear();
}

/// Legt den Stand verschlüsselt im Schlüsselspeicher des Handys ab.
class SecureStateCache implements StateCache {
  SecureStateCache({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'stichtag.mobile.state.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String encoded) =>
      _storage.write(key: _key, value: encoded);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Für Tests.
class InMemoryStateCache implements StateCache {
  InMemoryStateCache([this.encoded]);

  String? encoded;

  @override
  Future<String?> read() async => encoded;

  @override
  Future<void> write(String value) async {
    encoded = value;
  }

  @override
  Future<void> clear() async {
    encoded = null;
  }
}
