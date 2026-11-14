import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'local_api.dart';
import 'logic.dart';
import 'pairing_payload.dart';
import 'session_store.dart';

typedef ApiFactory = StichtagApi Function(String serverUrl, String? token);

/// Hält Kopplung und Datenstand und gleicht Änderungen mit dem Server ab.
class AppStore extends ChangeNotifier {
  AppStore({
    required this.sessionStore,
    StateCache? stateCache,
    StateCache? localStore,
    ApiFactory? apiFactory,
  }) : _cache = stateCache ?? InMemoryStateCache(),
       _local = localStore ?? InMemoryStateCache(),
       _apiFactory =
          apiFactory ??
          ((serverUrl, token) =>
              HttpStichtagApi(serverUrl: serverUrl, token: token));

  final SessionStore sessionStore;
  final StateCache _cache;

  /// Die Daten selbst, wenn die App ohne Server genutzt wird.
  final StateCache _local;
  final ApiFactory _apiFactory;

  Session? session;
  Json state = blankState();
  bool ready = false;
  bool loading = false;
  bool loadedOnce = false;
  String? error;

  StichtagApi? _api;
  bool _saving = false;
  bool _dirty = false;

  bool get paired => session != null;

  bool get hasUnsaved => _dirty;

  /// Wahr, wenn die App ohne Server genutzt wird.
  bool get isLocal => session?.isLocal ?? false;

  StichtagApi get _client {
    final current = session!;
    return _api ??= current.isLocal
        ? LocalStichtagApi(_local)
        : _apiFactory(current.serverUrl, current.token);
  }

  /// Startet die Nutzung ohne Server. Vorhandene Daten auf dem Handy bleiben.
  Future<void> startLocal() async {
    const created = Session(
      serverUrl: localServerUrl,
      token: 'local',
      deviceName: '',
    );
    await sessionStore.write(created);
    session = created;
    _api = null;
    notifyListeners();
    await refresh();
  }

  /// Verlässt die Nutzung ohne Server, zum Beispiel um mit einem Server zu
  /// koppeln. Die Daten auf dem Handy bleiben liegen.
  Future<void> leaveLocal() async {
    await _forget();
    notifyListeners();
  }

  /// Löscht bei Nutzung ohne Server alle Daten auf dem Handy.
  Future<void> eraseLocal() async {
    await _local.clear();
    await _forget();
    notifyListeners();
  }

  /// Der ganze Datenstand als lesbares JSON, für eine Sicherung.
  String exportJson() => const JsonEncoder.withIndent(' ').convert(state);

  /// Ersetzt den Datenstand durch eine Sicherung.
  void importJson(String text) {
    final dynamic data;
    try {
      data = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Die Datei ist keine Stichtag-Sicherung.');
    }
    if (data is! Map || data['logs'] is! List || data['protocols'] is! List) {
      throw const FormatException('Die Datei ist keine Stichtag-Sicherung.');
    }
    final rev = state['rev'];
    state = normalizeState(data)..['rev'] = rev;
    _dirty = true;
    notifyListeners();
    unawaited(_persist().then((_) => _flush()));
  }

  Future<void> init() async {
    try {
      session = await sessionStore.read();
    } on Object {
      session = null;
    }
    if (session != null) await _restore();
    ready = true;
    notifyListeners();
    if (session != null) await resume();
  }

  /// Zeigt sofort den zuletzt gespeicherten Stand, auch ohne Verbindung.
  Future<void> _restore() async {
    if (isLocal) return;
    try {
      final encoded = await _cache.read();
      if (encoded == null) return;
      final data = jsonDecode(encoded);
      if (data is! Map) return;
      state = normalizeState(data['state']);
      _dirty = data['dirty'] == true;
      loadedOnce = true;
    } on Object {
      // Ein unlesbarer Zwischenspeicher wird beim nächsten Laden ersetzt.
    }
  }

  Future<void> _persist() async {
    // Ohne Server sind die Daten selbst schon auf dem Handy.
    if (isLocal) return;
    try {
      await _cache.write(
        jsonEncode(<String, dynamic>{'state': state, 'dirty': _dirty}),
      );
    } on Object {
      // Ohne Zwischenspeicher läuft die App weiter, nur nicht ohne Verbindung.
    }
  }

  /// Beim Start und beim Zurückkehren in die App: erst Offenes senden, sonst neu laden.
  Future<void> resume() => _dirty ? _flush() : refresh();

  Future<void> pair(PairingPayload payload, String deviceName) async {
    final response = await _apiFactory(
      payload.serverUrl,
      null,
    ).pair(payload.pairingSecret, deviceName);
    final token = response['token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException('Ungültige Antwort vom Server.');
    }
    final created = Session(
      serverUrl: payload.serverUrl,
      token: token,
      deviceName: deviceName,
    );
    await sessionStore.write(created);
    session = created;
    _api = null;
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    if (session == null || _saving || _dirty || loading) return;
    loading = true;
    notifyListeners();
    try {
      state = normalizeState(await _client.getState());
      loadedOnce = true;
      error = null;
      await _persist();
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _forget();
      } else {
        error = loadedOnce
            ? '${e.message} Du siehst den zuletzt geladenen Stand.'
            : e.message;
      }
    }
    loading = false;
    notifyListeners();
  }

  /// Ändert den Stand und speichert ihn auf dem Server.
  void change(void Function(Json state) edit) {
    edit(state);
    _dirty = true;
    notifyListeners();
    unawaited(_persist().then((_) => _flush()));
  }

  Future<void> retry() => _flush();

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> _flush() async {
    if (_saving || !_dirty || session == null) return;
    _saving = true;
    _dirty = false;
    var failed = false;
    try {
      final response = await _client.putState(state);
      state['rev'] = toInt(response['rev']);
      error = null;
    } on ConflictException catch (e) {
      state = normalizeState(e.current);
      _dirty = false;
      failed = true;
      error =
          'Auf einem anderen Gerät geändert. Der Stand wurde neu geladen, bitte die letzte Eingabe wiederholen.';
    } on ApiException catch (e) {
      failed = true;
      if (e.status == 401) {
        await _forget();
      } else {
        _dirty = true;
        error =
            '${e.message} Die Änderung ist auf dem Handy gesichert und wird gesendet, sobald der Server erreichbar ist.';
      }
    }
    _saving = false;
    await _persist();
    notifyListeners();
    if (_dirty && !failed) unawaited(_flush());
  }

  Future<void> unpair() async {
    if (session != null) {
      try {
        await _client.logout();
      } on Object {
        // Auch ohne Verbindung wird das Handy lokal entkoppelt.
      }
    }
    await _forget();
    notifyListeners();
  }

  Future<void> _forget() async {
    session = null;
    _api = null;
    _dirty = false;
    loadedOnce = false;
    state = blankState();
    error = null;
    await _cache.clear();
    await sessionStore.clear();
  }
}
