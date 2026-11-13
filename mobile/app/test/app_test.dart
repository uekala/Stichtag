import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stichtag_mobile/core/api.dart';
import 'package:stichtag_mobile/core/app_store.dart';
import 'package:stichtag_mobile/core/logic.dart';
import 'package:stichtag_mobile/core/session_store.dart';
import 'package:stichtag_mobile/main.dart';

/// Server im Speicher mit derselben Revisionsprüfung wie der echte.
class FakeApi implements StichtagApi {
  FakeApi(this.server);

  Json server;
  int puts = 0;

  @override
  Future<Json> getState() async => normalizeState(server);

  @override
  Future<Json> putState(Json state) async {
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

const session = Session(
  serverUrl: 'https://stichtag.example.ts.net',
  token: 'token',
  deviceName: 'Testhandy',
);

void main() {
  testWidgets('ohne Kopplung erscheint der Kopplungsbildschirm', (tester) async {
    final store = AppStore(sessionStore: InMemorySessionStore());
    await tester.pumpWidget(StichtagApp(store: store));
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
    await tester.pumpWidget(StichtagApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Beispiel A'), findsOneWidget);
    expect(find.text('Offen'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Eintragen'));
    await tester.pumpAndSettle();
    expect(find.text('Dosis eintragen'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(api.puts, 1);
    expect(items(api.server, 'logs'), hasLength(1));
    expect(items(api.server, 'logs').first['pid'], 'p1');
    expect(find.text('Erledigt'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
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
}
