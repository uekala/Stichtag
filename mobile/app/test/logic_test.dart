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

  test('normalizeState füllt fehlende Teile auf', () {
    final state = normalizeState(<String, dynamic>{'rev': 7});
    expect(state['rev'], 7);
    expect(items(state, 'logs'), isEmpty);
    expect(sitesOf(state), defaultSites);
    expect(normalizeState('kaputt')['rev'], 0);
  });
}
