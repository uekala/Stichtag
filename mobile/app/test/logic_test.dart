import 'package:flutter_test/flutter_test.dart';
import 'package:stichtag_mobile/core/logic.dart';

Json protocol(Map<String, dynamic> extra) => <String, dynamic>{
  'id': 'p1',
  'name': 'Test',
  'dose': 250,
  'unit': 'mcg',
  'type': 'daily',
  'start': '2026-11-01',
  'weeks': 0,
  'active': true,
  ...extra,
};

void main() {
  group('isDue', () {
    test('täglich ab Startdatum', () {
      expect(isDue(protocol({}), '2026-10-31'), isFalse);
      expect(isDue(protocol({}), '2026-11-01'), isTrue);
      expect(isDue(protocol({}), '2026-11-13'), isTrue);
    });

    test('pausierte Protokolle sind nie fällig', () {
      expect(isDue(protocol({'active': false}), '2026-11-13'), isFalse);
    });

    test('Zyklus endet nach den angegebenen Wochen', () {
      final p = protocol({'weeks': 1});
      expect(isDue(p, '2026-11-07'), isTrue);
      expect(isDue(p, '2026-11-08'), isFalse);
    });

    test('alle N Tage', () {
      final p = protocol({'type': 'interval', 'n': 3});
      expect(isDue(p, '2026-11-01'), isTrue);
      expect(isDue(p, '2026-11-02'), isFalse);
      expect(isDue(p, '2026-11-04'), isTrue);
    });

    test('Wochentage zählen wie im Browser, Sonntag ist 0', () {
      // Der 13.11.2026 ist ein Freitag, der 15.11.2026 ein Sonntag.
      final p = protocol({
        'type': 'weekdays',
        'days': [5, 0],
      });
      expect(isDue(p, '2026-11-13'), isTrue);
      expect(isDue(p, '2026-11-14'), isFalse);
      expect(isDue(p, '2026-11-15'), isTrue);
    });

    test('ungültiges Startdatum ist nie fällig', () {
      expect(isDue(protocol({'start': 'kaputt'}), '2026-11-13'), isFalse);
    });
  });

  test('nextSite nimmt die am längsten nicht benutzte Stelle', () {
    final state = normalizeState(<String, dynamic>{
      'sites': ['A', 'B', 'C'],
      'logs': [
        {'ts': '2026-11-10T08:00', 'site': 'A'},
        {'ts': '2026-11-12T08:00', 'site': 'B'},
        {'ts': '2026-11-11T08:00', 'site': 'C'},
      ],
    });
    expect(nextSite(state), 'A');
    items(state, 'logs').add(<String, dynamic>{
      'ts': '2026-11-13T08:00',
      'site': 'A',
    });
    expect(nextSite(state), 'C');
  });

  test('nextSite beginnt mit der ersten unbenutzten Stelle', () {
    final state = normalizeState(<String, dynamic>{
      'sites': ['A', 'B'],
      'logs': [
        {'ts': '2026-11-10T08:00', 'site': 'A'},
      ],
    });
    expect(nextSite(state), 'B');
  });

  test('vialLevel zieht zugeordnete Dosen ab', () {
    final state = normalizeState(<String, dynamic>{
      'vials': [
        {'id': 'v1', 'mg': 5},
      ],
      'logs': [
        {'vialId': 'v1', 'dose': 250, 'unit': 'mcg'},
        {'vialId': 'v1', 'dose': 1, 'unit': 'mg'},
        {'vialId': 'x', 'dose': 1, 'unit': 'mg'},
        {'vialId': 'v1', 'dose': 10, 'unit': 'IE'},
      ],
    });
    final level = vialLevel(state, items(state, 'vials').first);
    expect(level.totalMcg, 5000);
    expect(level.leftMcg, 3750);
    expect(level.fraction, 0.75);
  });

  test('adherence zählt fällige und eingetragene Protokolle', () {
    final state = normalizeState(<String, dynamic>{
      'protocols': [
        protocol({}),
        protocol({'id': 'p2'}),
      ],
      'logs': [
        {'ts': '2026-11-13T08:00', 'pid': 'p1'},
      ],
    });
    final result = adherence(state, '2026-11-13');
    expect(result.due, 2);
    expect(result.done, 1);
  });

  test('calcMix rechnet Einheiten für eine U-100-Spritze', () {
    final result = calcMix(vialMg: 5, waterMl: 2, doseMcg: 250)!;
    expect(result.concentration, 2500);
    expect(result.volumeMl, closeTo(0.1, 1e-9));
    expect(result.units, closeTo(10, 1e-9));
    expect(result.dosesPerVial, 20);
    expect(calcMix(vialMg: 0, waterMl: 2, doseMcg: 250), isNull);
  });

  test('fmtNum schreibt deutsch und ohne überflüssige Nullen', () {
    expect(fmtNum(250, 3), '250');
    expect(fmtNum(2.5, 3), '2,5');
    expect(fmtNum(0.125, 3), '0,125');
    expect(fmtNum(83.14, 1), '83,1');
    expect(fmtNum(100, 0), '100');
  });

  test('Datumshelfer', () {
    expect(addDays('2026-11-13', -13), '2026-10-31');
    expect(dayDiff('2026-03-28', '2026-03-30'), 2);
    expect(deDate('2026-11-13'), 'Fr, 13.11.2026');
    expect(nowStamp(DateTime(2026, 1, 5, 7, 3)), '2026-01-05T07:03');
  });

  group('Auswertung', () {
    final state = normalizeState(<String, dynamic>{
      'sites': ['A', 'B'],
      'protocols': [
        protocol({'start': '2026-11-10'}),
      ],
      'logs': [
        {'ts': '2026-11-10T08:00', 'pid': 'p1', 'name': 'Test', 'dose': 250, 'unit': 'mcg', 'site': 'A', 'feel': 4},
        {'ts': '2026-11-11T08:00', 'pid': 'p1', 'name': 'Test', 'dose': 250, 'unit': 'mcg', 'site': 'B', 'feel': 2},
        {'ts': '2026-11-11T20:00', 'pid': '', 'name': 'Frei', 'dose': 1, 'unit': 'mg', 'site': 'A', 'feel': 4},
        {'ts': '2026-11-13T08:00', 'pid': 'p1', 'name': 'Test', 'dose': 600, 'unit': 'mcg', 'site': 'A'},
        {'ts': '2026-09-01T08:00', 'pid': 'p1', 'name': 'Test', 'dose': 250, 'unit': 'mcg', 'site': 'A'},
      ],
    });

    test('weekStats zählt 7-Tage-Fenster bis heute', () {
      final weeks = weekStats(state, '2026-11-13');
      expect(weeks, hasLength(8));
      expect(weeks.last.start, '2026-11-07');
      expect(weeks.last.due, 4);
      expect(weeks.last.done, 3);
      expect(weeks.last.rate, 0.75);
      expect(weeks.first.due, 0);
      expect(weeks.first.rate, isNull);
    });

    test('peptideStats fasst je Peptid zusammen', () {
      final stats = peptideStats(state, '2026-11-13');
      expect(stats.map((s) => s.name), ['Test', 'Frei']);
      final test = stats.first;
      expect(test.total, 4);
      expect(test.recent, 3);
      expect(amountLabel(test.sums), '1,1 mg');
      expect(test.due, 4);
      expect(test.done, 3);
      expect(amountLabel(stats.last.sums), '1 mg');
      expect(stats.last.due, 0);
    });

    test('feelSeries mittelt je Tag', () {
      final series = feelSeries(state, '2026-11-13');
      expect(series.map((e) => e.key), ['2026-11-10', '2026-11-11']);
      expect(series.last.value, 3);
    });

    test('siteCounts zählt die letzten 30 Tage', () {
      expect(siteCounts(state, '2026-11-13'), {'A': 3, 'B': 1});
    });

    test('upcoming nennt die nächsten fälligen Tage', () {
      final days = upcoming(state, '2026-11-13', 2);
      expect(days.map((e) => e.key), ['2026-11-14', '2026-11-15']);
      expect(days.first.value.single['id'], 'p1');
    });

    test('lowVials meldet Vials unter 20 Prozent', () {
      final vials = normalizeState(<String, dynamic>{
        'vials': [
          {'id': 'v1', 'name': 'Voll', 'mg': 5},
          {'id': 'v2', 'name': 'Knapp', 'mg': 1},
        ],
        'logs': [
          {'vialId': 'v2', 'dose': 900, 'unit': 'mcg'},
        ],
      });
      expect(lowVials(vials).map((v) => v['name']), ['Knapp']);
    });

    test('entriesLabel beugt richtig', () {
      expect(entriesLabel(1), '1 Eintrag');
      expect(entriesLabel(3), '3 Einträge');
    });
  });

  test('nameSuggestions nennt eigene Namen zuerst und filtert', () {
    final state = normalizeState(<String, dynamic>{
      'protocols': [
        protocol({'name': 'Mein Mix'}),
      ],
      'logs': [
        {'ts': '2026-11-10T08:00', 'name': 'Alt'},
        {'ts': '2026-11-11T08:00', 'name': 'mein mix'},
      ],
    });
    final all = nameSuggestions(state, '');
    expect(all.take(2), ['Mein Mix', 'Alt']);
    expect(all, hasLength(8));
    expect(nameSuggestions(state, 'GLUT'), ['Semaglutid']);
    expect(nameSuggestions(state, 'sema'), ['Semaglutid', 'Semax']);
    expect(nameSuggestions(state, 'Semax'), isEmpty);
  });

  test('normalizeState füllt fehlende Teile auf', () {
    final state = normalizeState(<String, dynamic>{'rev': 7});
    expect(state['rev'], 7);
    expect(items(state, 'logs'), isEmpty);
    expect(sitesOf(state), defaultSites);
    expect(normalizeState('kaputt')['rev'], 0);
  });
}
