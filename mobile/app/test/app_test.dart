import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stichtag_mobile/core/api.dart';
import 'package:stichtag_mobile/core/app_lock.dart';
import 'package:stichtag_mobile/core/app_store.dart';
import 'package:stichtag_mobile/core/logic.dart';
import 'package:stichtag_mobile/core/session_store.dart';
import 'package:stichtag_mobile/main.dart';

/// Server im Speicher mit derselben Revisionsprüfung wie der echte.
class FakeApi implements StichtagApi {
  FakeApi(this.server);

  Json server;
  int puts = 0;

  bool offline = false;

  void _check() {
    if (offline) throw const ApiException('Der Server ist nicht erreichbar.');
  }

  @override
  Future<Json> getState() async {
    _check();
    return normalizeState(server);
  }

  @override
  Future<Json> putState(Json state) async {
    _check();
    puts++;
    if (toInt(state['rev']) != toInt(server['rev'])) {
      throw ConflictException(normalizeState(server));
    }
    server = normalizeState(state)..['rev'] = toInt(server['rev']) + 1;
    return <String, dynamic>{'rev': server['rev']};
  }

  @override
  Future<Json> pair(String pairingSecret, String deviceName) async =>
      <String, dynamic>{'token': 'token'};

  @override
  Future<void> logout() async {}
}

AppLock noLock() => AppLock.inMemory(authenticate: (_) async => true);

const session = Session(
  serverUrl: 'https://stichtag.example.ts.net',
  token: 'token',
  deviceName: 'Testhandy',
);

void main() {
  testWidgets('ohne Kopplung erscheint der Kopplungsbildschirm', (tester) async {
    final store = AppStore(sessionStore: InMemorySessionStore());
    await tester.pumpWidget(StichtagApp(store: store, appLock: noLock()));
    await tester.pumpAndSettle();
    expect(find.text('QR-Code scannen'), findsOneWidget);
  });

  testWidgets('gekoppelt zeigt die Heute-Ansicht fällige Protokolle', (
    tester,
  ) async {
    final api = FakeApi(<String, dynamic>{
      'rev': 3,
      'protocols': [
        {
          'id': 'p1',
          'name': 'Beispiel A',
          'dose': 250,
          'unit': 'mcg',
          'type': 'daily',
          'start': '2020-01-01',
          'weeks': 0,
          'time': '08:00',
          'active': true,
        },
      ],
    });
    final store = AppStore(
      sessionStore: InMemorySessionStore(session),
      apiFactory: (_, _) => api,
    );
    await tester.pumpWidget(StichtagApp(store: store, appLock: noLock()));
    await tester.pumpAndSettle();
    expect(find.text('Beispiel A'), findsOneWidget);
    expect(find.text('Offen'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);

    // Ein Tipp trägt die Dosis ein.
    await tester.tap(find.text('Dosis erledigt'));
    await tester.pumpAndSettle();
    expect(api.puts, 1);
    expect(items(api.server, 'logs'), hasLength(1));
    expect(items(api.server, 'logs').first['pid'], 'p1');
    expect(items(api.server, 'logs').first['site'], 'Bauch links');
    expect(find.text('Erledigt'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);

    // Rückgängig nimmt sie wieder heraus.
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(api.puts, 2);
    expect(items(api.server, 'logs'), isEmpty);
    expect(find.text('0 / 1'), findsOneWidget);

    // Über „Anpassen“ geht es ins Formular.
    await tester.tap(find.text('Anpassen'));
    await tester.pumpAndSettle();
    expect(find.text('Dosis eintragen'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(api.puts, 3);
    expect(items(api.server, 'logs'), hasLength(1));
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('die Auswertung im Verlauf zeigt Zahlen je Peptid', (
    tester,
  ) async {
    final today = todayYmd();
    final api = FakeApi(<String, dynamic>{
      'rev': 1,
      'logs': [
        {
          'id': 'l1',
          'ts': '${today}T08:00',
          'pid': '',
          'name': 'Beispiel A',
          'dose': 250,
          'unit': 'mcg',
          'site': 'Bauch links',
          'feel': 4,
        },
      ],
    });
    final store = AppStore(
      sessionStore: InMemorySessionStore(session),
      apiFactory: (_, _) => api,
    );
    await tester.pumpWidget(StichtagApp(store: store, appLock: noLock()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auswertung'));
    await tester.pumpAndSettle();
    expect(find.text('Einhaltung'), findsOneWidget);
    expect(find.text('1 Eintrag gesamt'), findsOneWidget);
    expect(find.text('1 Eintrag in 30 Tagen · 250 mcg'), findsOneWidget);
  });

  test('ein Konflikt lädt den Stand des Servers', () async {
    final api = FakeApi(<String, dynamic>{'rev': 1});
    final store = AppStore(
      sessionStore: InMemorySessionStore(session),
      apiFactory: (_, _) => api,
    );
    await store.init();
    api.server = normalizeState(<String, dynamic>{
      'rev': 2,
      'sites': ['Nur diese'],
    });
    store.change((state) => state['sites'] = <String>['Meine']);
    await Future<void>.delayed(Duration.zero);
    expect(sitesOf(store.state), ['Nur diese']);
    expect(store.error, isNotNull);
    expect(store.hasUnsaved, isFalse);
  });

  testWidgets('die App-Sperre verdeckt die App, bis entsperrt wird', (
    tester,
  ) async {
    var allow = false;
    final lock = AppLock.inMemory(
      enabled: true,
      authenticate: (_) async => allow,
    );
    final store = AppStore(sessionStore: InMemorySessionStore());
    await tester.pumpWidget(StichtagApp(store: store, appLock: lock));
    await tester.pumpAndSettle();
    expect(find.text('Stichtag ist gesperrt'), findsOneWidget);

    allow = true;
    await tester.tap(find.text('Entsperren'));
    await tester.pumpAndSettle();
    expect(find.text('Stichtag ist gesperrt'), findsNothing);
    expect(find.text('QR-Code scannen'), findsOneWidget);
  });

  testWidgets('ohne Server lässt sich die App direkt nutzen', (tester) async {
    final store = AppStore(
      sessionStore: InMemorySessionStore(),
      localStore: InMemoryStateCache(),
    );
    await tester.pumpWidget(StichtagApp(store: store, appLock: noLock()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ohne Server nutzen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Ohne Server nutzen'));
    await tester.pumpAndSettle();
    expect(store.isLocal, isTrue);
    expect(find.text('Fällig heute'), findsOneWidget);
  });

  test('ohne Server bleiben die Daten auf dem Handy erhalten', () async {
    final sessions = InMemorySessionStore();
    final local = InMemoryStateCache();
    final store = AppStore(sessionStore: sessions, localStore: local);
    await store.init();
    await store.startLocal();
    store.change((state) => state['sites'] = <String>['Nur hier']);
    await Future<void>.delayed(Duration.zero);
    expect(store.hasUnsaved, isFalse);
    expect(store.error, isNull);

    // Ein neuer Start liest denselben Stand.
    final restarted = AppStore(sessionStore: sessions, localStore: local);
    await restarted.init();
    expect(restarted.isLocal, isTrue);
    expect(sitesOf(restarted.state), ['Nur hier']);
    expect(restarted.state['rev'], 1);

    // Wechsel zum Koppeln lässt die Daten liegen, Löschen entfernt sie.
    await restarted.leaveLocal();
    expect(restarted.paired, isFalse);
    expect(local.encoded, isNotNull);
    await restarted.startLocal();
    expect(sitesOf(restarted.state), ['Nur hier']);
    await restarted.eraseLocal();
    expect(local.encoded, isNull);
  });

  test('eine Sicherung lässt sich exportieren und wieder einspielen', () async {
    final source = AppStore(
      sessionStore: InMemorySessionStore(),
      localStore: InMemoryStateCache(),
    );
    await source.startLocal();
    source.change((state) {
      state['sites'] = <String>['Gesichert'];
      items(state, 'logs').add(<String, dynamic>{'id': 'l1', 'name': 'Test'});
    });
    await Future<void>.delayed(Duration.zero);
    final backup = source.exportJson();

    final target = AppStore(
      sessionStore: InMemorySessionStore(),
      localStore: InMemoryStateCache(),
    );
    await target.startLocal();
    target.importJson(backup);
    await Future<void>.delayed(Duration.zero);
    expect(sitesOf(target.state), ['Gesichert']);
    expect(items(target.state, 'logs').single['name'], 'Test');
    expect(target.hasUnsaved, isFalse);
    expect(() => target.importJson('kein json'), throwsFormatException);
    expect(() => target.importJson('{"x": 1}'), throwsFormatException);
  });

  test('ohne Verbindung zeigt die App den letzten Stand und sendet später', () async {
    final api = FakeApi(<String, dynamic>{'rev': 5})..offline = true;
    final cache = InMemoryStateCache(
      jsonEncode(<String, dynamic>{
        'state': <String, dynamic>{
          'rev': 5,
          'sites': ['Aus dem Speicher'],
        },
        'dirty': false,
      }),
    );
    final store = AppStore(
      sessionStore: InMemorySessionStore(session),
      stateCache: cache,
      apiFactory: (_, _) => api,
    );
    await store.init();
    expect(store.loadedOnce, isTrue);
    expect(sitesOf(store.state), ['Aus dem Speicher']);
    expect(store.error, contains('zuletzt geladenen Stand'));

    store.change((state) => state['sites'] = <String>['Unterwegs geändert']);
    await Future<void>.delayed(Duration.zero);
    expect(store.hasUnsaved, isTrue);
    expect(jsonDecode(cache.encoded!)['dirty'], isTrue);

    // Ein neuer Start ohne Verbindung behält die offene Änderung.
    final restarted = AppStore(
      sessionStore: InMemorySessionStore(session),
      stateCache: cache,
      apiFactory: (_, _) => api,
    );
    await restarted.init();
    expect(sitesOf(restarted.state), ['Unterwegs geändert']);
    expect(restarted.hasUnsaved, isTrue);

    api.offline = false;
    await restarted.resume();
    expect(restarted.hasUnsaved, isFalse);
    expect(sitesOf(api.server), ['Unterwegs geändert']);
    expect(jsonDecode(cache.encoded!)['dirty'], isFalse);
  });
}
