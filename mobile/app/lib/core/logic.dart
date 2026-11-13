import 'dart:math';

/// Der Datenstand ist dasselbe JSON, das auch die Weboberfläche verwendet.
typedef Json = Map<String, dynamic>;

const defaultSites = <String>[
  'Bauch links',
  'Bauch rechts',
  'Oberschenkel links',
  'Oberschenkel rechts',
  'Flanke links',
  'Flanke rechts',
];
const weekdayShort = <String>['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
const doseUnits = <String>['mcg', 'mg', 'IE'];

final _random = Random();

String _two(int n) => n.toString().padLeft(2, '0');

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String todayYmd([DateTime? now]) => ymd(now ?? DateTime.now());

/// Zeitstempel wie im Browser: lokale Zeit, `JJJJ-MM-TTTHH:MM`.
String nowStamp([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${ymd(d)}T${_two(d.hour)}:${_two(d.minute)}';
}

DateTime? tryParseYmd(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) return null;
  return DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// Tage von [from] bis [to]; null, wenn eines der Daten ungültig ist.
int? dayDiff(String from, String to) {
  final a = tryParseYmd(from);
  final b = tryParseYmd(to);
  if (a == null || b == null) return null;
  return b.difference(a).inDays;
}

String addDays(String day, int count) {
  final d = tryParseYmd(day);
  if (d == null) return day;
  return ymd(d.add(Duration(days: count)));
}

/// Wochentag wie in JavaScript: Sonntag = 0.
int jsWeekday(DateTime d) => d.weekday % 7;

String deDate(String day) {
  final d = tryParseYmd(day);
  if (d == null) return day;
  return '${weekdayShort[jsWeekday(d)]}, ${_two(d.day)}.${_two(d.month)}.${d.year}';
}

double toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }
  return 0;
}

int toInt(Object? value) => toDouble(value).round();

String str(Object? value) => value == null ? '' : value.toString();

/// Zahl in deutscher Schreibweise ohne überflüssige Nullen.
String fmtNum(num value, [int digits = 2]) {
  var text = value.toStringAsFixed(digits);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text.replaceAll('.', ',');
}

String newId() =>
    '${_random.nextInt(0x7fffffff).toRadixString(36)}'
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

Json blankState() => <String, dynamic>{
  'v': 1,
  'rev': 0,
  'demo': false,
  'protocols': <Json>[],
  'logs': <Json>[],
  'vials': <Json>[],
  'body': <Json>[],
  'sites': List<String>.from(defaultSites),
  'settings': <String, dynamic>{'notify': '', 'followup': 0},
};

Json normalizeState(Object? raw) {
  final state = blankState();
  if (raw is! Map) return state;
  state['rev'] = toInt(raw['rev']);
  state['demo'] = raw['demo'] == true;
  for (final key in const ['protocols', 'logs', 'vials', 'body']) {
    final value = raw[key];
    if (value is List) {
      state[key] = value
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
  }
  final sites = raw['sites'];
  if (sites is List && sites.isNotEmpty) {
    state['sites'] = sites.map((entry) => entry.toString()).toList();
  }
  final settings = raw['settings'];
  if (settings is Map) {
    state['settings'] = Map<String, dynamic>.from(settings);
  }
  return state;
}

List<Json> items(Json state, String key) => state[key] as List<Json>;

List<String> sitesOf(Json state) => state['sites'] as List<String>;

Json? firstOrNull(Iterable<Json> entries, bool Function(Json entry) test) {
  for (final entry in entries) {
    if (test(entry)) return entry;
  }
  return null;
}

/// Ist das Protokoll an diesem Tag fällig? Gleiche Regeln wie im Server.
bool isDue(Json protocol, String day) {
  if (protocol['active'] != true) return false;
  final diff = dayDiff(str(protocol['start']), day);
  if (diff == null || diff < 0) return false;
  final weeks = toInt(protocol['weeks']);
  if (weeks > 0 && diff >= weeks * 7) return false;
  switch (str(protocol['type'])) {
    case 'daily':
      return true;
    case 'interval':
      return diff % max(1, toInt(protocol['n'])) == 0;
    default:
      final date = tryParseYmd(day);
      final days = protocol['days'];
      if (date == null || days is! List) return false;
      return days.map(toInt).contains(jsWeekday(date));
  }
}

List<Json> logsOn(Json state, String day) => items(
  state,
  'logs',
).where((log) => str(log['ts']).startsWith(day)).toList();

String freqLabel(Json protocol) {
  switch (str(protocol['type'])) {
    case 'daily':
      return 'täglich';
    case 'interval':
      return 'alle ${max(1, toInt(protocol['n']))} Tage';
    default:
      final days = protocol['days'];
      final chosen = days is List ? days.map(toInt).toSet() : <int>{};
      final labels = [
        for (final d in const [1, 2, 3, 4, 5, 6, 0])
          if (chosen.contains(d)) weekdayShort[d],
      ];
      return labels.isEmpty ? 'keine Tage gewählt' : labels.join(', ');
  }
}

/// Die Stelle, die am längsten nicht benutzt wurde.
String nextSite(Json state) {
  final sites = sitesOf(state);
  if (sites.isEmpty) return '';
  final last = <String, String>{};
  for (final log in items(state, 'logs')) {
    final site = str(log['site']);
    final stamp = str(log['ts']);
    if (site.isNotEmpty && stamp.compareTo(last[site] ?? '') > 0) {
      last[site] = stamp;
    }
  }
  var best = sites.first;
  for (final site in sites) {
    if ((last[site] ?? '').compareTo(last[best] ?? '') < 0) best = site;
  }
  return best;
}

class VialLevel {
  const VialLevel({required this.leftMcg, required this.totalMcg});

  final double leftMcg;
  final double totalMcg;

  double get fraction => totalMcg > 0 ? leftMcg / totalMcg : 0;
}

VialLevel vialLevel(Json state, Json vial) {
  var used = 0.0;
  for (final log in items(state, 'logs')) {
    if (log['vialId'] != vial['id']) continue;
    final dose = toDouble(log['dose']);
    if (log['unit'] == 'mcg') used += dose;
    if (log['unit'] == 'mg') used += dose * 1000;
  }
  final total = toDouble(vial['mg']) * 1000;
  return VialLevel(leftMcg: max(0.0, total - used), totalMcg: total);
}

class Adherence {
  const Adherence({required this.due, required this.done});

  final int due;
  final int done;
}

Adherence adherence(Json state, String day) {
  final due = items(state, 'protocols').where((p) => isDue(p, day)).toList();
  if (due.isEmpty) return const Adherence(due: 0, done: 0);
  final logged = logsOn(state, day).map((log) => log['pid']).toSet();
  return Adherence(
    due: due.length,
    done: due.where((p) => logged.contains(p['id'])).length,
  );
}

class MixResult {
  const MixResult({
    required this.concentration,
    required this.volumeMl,
    required this.units,
    required this.dosesPerVial,
  });

  /// mcg pro ml
  final double concentration;
  final double volumeMl;

  /// Einheiten auf einer U-100-Spritze (100 Einheiten = 1 ml)
  final double units;
  final double dosesPerVial;
}

MixResult? calcMix({
  required double vialMg,
  required double waterMl,
  required double doseMcg,
}) {
  if (vialMg <= 0 || waterMl <= 0 || doseMcg <= 0) return null;
  final concentration = vialMg * 1000 / waterMl;
  final volume = doseMcg / concentration;
  return MixResult(
    concentration: concentration,
    volumeMl: volume,
    units: volume * 100,
    dosesPerVial: vialMg * 1000 / doseMcg,
  );
}
