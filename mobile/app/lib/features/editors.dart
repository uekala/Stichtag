import 'dart:math';

import 'package:flutter/material.dart';

import '../core/app_store.dart';
import '../core/logic.dart';
import 'widgets.dart';

Map<String, String> _vialOptions(Json state) => <String, String>{
  '': 'Kein Vial',
  for (final vial in items(state, 'vials')) str(vial['id']): str(vial['name']),
};

/// Neue Einträge sind immer in mg. Alte in mcg rechnet das Formular beim
/// Bearbeiten um; andere Einheiten bleiben, wie sie sind.
String _formUnit(String stored) =>
    stored.isEmpty || stored == 'mcg' || stored == 'mg' ? 'mg' : stored;

double _formDose(Object? dose, String stored) =>
    stored == 'mcg' ? toDouble(dose) / 1000 : toDouble(dose);

String _numText(Object? value) {
  final number = toDouble(value);
  return number > 0 ? fmtNum(number, 6) : '';
}

/// Namensfeld mit Vorschlägen zum Antippen.
class PeptideNameField extends StatefulWidget {
  const PeptideNameField({
    super.key,
    required this.controller,
    required this.state,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final Json state;
  final String? errorText;
  final VoidCallback? onChanged;

  @override
  State<PeptideNameField> createState() => _PeptideNameFieldState();
}

class _PeptideNameFieldState extends State<PeptideNameField> {
  void _pick(String name) {
    widget.controller.text = name;
    widget.onChanged?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = nameSuggestions(widget.state, widget.controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) {
            widget.onChanged?.call();
            setState(() {});
          },
          decoration: InputDecoration(
            labelText: 'Peptid',
            hintText: 'Name eintippen oder unten wählen',
            errorText: widget.errorText,
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final name in suggestions)
                ActionChip(label: Text(name), onPressed: () => _pick(name)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Eine Dosis eintragen (optional vorbelegt aus einem Protokoll) oder einen
/// vorhandenen Eintrag bearbeiten.
class LogEditor extends StatefulWidget {
  const LogEditor({super.key, required this.store, this.protocol, this.existing});

  final AppStore store;
  final Json? protocol;
  final Json? existing;

  @override
  State<LogEditor> createState() => _LogEditorState();
}

class _LogEditorState extends State<LogEditor> {
  late final TextEditingController _name;
  late final TextEditingController _dose;
  final _note = TextEditingController();
  late String _unit;
  late String _site;
  late String _vial;
  late String _date;
  late String _time;
  int _feel = 0;
  String? _nameError;
  String? _doseError;

  void _clearErrors() {
    if (_nameError != null || _doseError != null) {
      setState(() {
        _nameError = null;
        _doseError = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final log = widget.existing;
    final source = log ?? widget.protocol;
    final state = widget.store.state;
    _name = TextEditingController(text: str(source?['name']));
    final protocol = widget.protocol;
    final stored = str(source?['unit']);
    _unit = _formUnit(stored);
    _dose = TextEditingController(
      text: _numText(
        _formDose(
          log == null && protocol != null
              ? doseOn(protocol, todayYmd())
              : source?['dose'],
          stored,
        ),
      ),
    );
    _site = log == null ? nextSite(state) : str(log['site']);
    final vial = str(source?['vialId']);
    _vial = _vialOptions(state).containsKey(vial) ? vial : '';
    final saved = str(log?['ts']);
    final stamp = saved.length >= 16 && tryParseYmd(saved) != null
        ? saved
        : nowStamp();
    _date = stamp.substring(0, 10);
    _time = stamp.substring(11, 16);
    if (log != null) {
      _feel = toInt(log['feel']).clamp(0, 5).toInt();
      _note.text = str(log['note']);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final dose = toDouble(_dose.text);
    if (name.isEmpty || dose <= 0) {
      setState(() {
        _nameError = name.isEmpty ? 'Bitte einen Namen eingeben' : null;
        _doseError = dose <= 0 ? 'Größer als 0' : null;
      });
      return;
    }
    widget.store.change((state) {
      final protocols = items(state, 'protocols');
      var pid = str(widget.existing?['pid'] ?? widget.protocol?['id']);
      final own = firstOrNull(protocols, (p) => p['id'] == pid);
      if (own == null || str(own['name']) != name) {
        final match = firstOrNull(
          protocols,
          (p) => str(p['name']).toLowerCase() == name.toLowerCase(),
        );
        pid = match == null ? '' : str(match['id']);
      }
      final data = <String, dynamic>{
        'ts': '${_date}T$_time',
        'pid': pid,
        'name': name,
        'dose': dose,
        'unit': _unit,
        'site': _site,
        'feel': _feel,
        'note': _note.text.trim(),
        'vialId': _vial,
      };
      final logs = items(state, 'logs');
      final id = str(widget.existing?['id']);
      final current = firstOrNull(logs, (log) => log['id'] == id);
      if (current != null) {
        current.addAll(data);
      } else {
        logs.add(<String, dynamic>{'id': newId(), ...data});
      }
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.store.state;
    return EditorScaffold(
      title: widget.existing == null ? 'Dosis eintragen' : 'Eintrag bearbeiten',
      onSave: _save,
      children: [
        PeptideNameField(
          controller: _name,
          state: state,
          errorText: _nameError,
          onChanged: _clearErrors,
        ),
        NumField(
          controller: _dose,
          label: 'Dosis ($_unit)',
          errorText: _doseError,
          onChanged: (_) => _clearErrors(),
        ),
        Row(
          children: [
            Expanded(
              child: DateField(
                label: 'Datum',
                value: _date,
                onChanged: (v) => setState(() => _date = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TimeField(
                label: 'Uhrzeit',
                value: _time,
                onChanged: (v) => setState(() => _time = v),
              ),
            ),
          ],
        ),
        dropdown<String>(
          label: 'Stelle',
          value: _site,
          options: <String, String>{
            '': 'Keine Angabe',
            for (final site in sitesOf(state)) site: site,
            if (_site.isNotEmpty && !sitesOf(state).contains(_site))
              _site: _site,
          },
          onChanged: (v) => setState(() => _site = v),
        ),
        dropdown<String>(
          label: 'Vial',
          value: _vial,
          options: _vialOptions(state),
          onChanged: (v) => setState(() => _vial = v),
        ),
        dropdown<int>(
          label: 'Befinden',
          value: _feel,
          options: const <int, String>{
            0: 'Keine Angabe',
            1: '1 · schlecht',
            2: '2',
            3: '3 · neutral',
            4: '4',
            5: '5 · sehr gut',
          },
          onChanged: (v) => setState(() => _feel = v),
        ),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Notiz'),
        ),
      ],
    );
  }
}

/// Protokoll anlegen oder bearbeiten.
class ProtocolEditor extends StatefulWidget {
  const ProtocolEditor({super.key, required this.store, this.existing});

  final AppStore store;
  final Json? existing;

  @override
  State<ProtocolEditor> createState() => _ProtocolEditorState();
}

class _ProtocolEditorState extends State<ProtocolEditor> {
  late final TextEditingController _name;
  late final TextEditingController _dose;
  late final TextEditingController _interval;
  late final TextEditingController _weeks;
  late String _unit;
  late String _type;
  late Set<int> _days;
  late String _start;
  late String _time;
  late String _vial;
  final _steps = <(TextEditingController, TextEditingController)>[];
  String? _error;
  String? _nameError;
  String? _doseError;

  void _clearErrors() {
    if (_nameError != null || _doseError != null) {
      setState(() {
        _nameError = null;
        _doseError = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: str(p?['name']));
    final stored = str(p?['unit']);
    _unit = _formUnit(stored);
    _dose = TextEditingController(text: _numText(_formDose(p?['dose'], stored)));
    _interval = TextEditingController(
      text: max(1, toInt(p?['n'] ?? 2)).toString(),
    );
    final weeks = toInt(p?['weeks']);
    _weeks = TextEditingController(text: weeks > 0 ? weeks.toString() : '');
    final type = str(p?['type']);
    _type = const ['daily', 'interval', 'weekdays'].contains(type)
        ? type
        : 'daily';
    final days = p?['days'];
    _days = days is List ? days.map(toInt).toSet() : <int>{};
    if (p != null) {
      for (final step in stepsOf(p)) {
        _steps.add((
          TextEditingController(text: step.key.toString()),
          TextEditingController(text: _numText(_formDose(step.value, stored))),
        ));
      }
    }
    final start = str(p?['start']);
    _start = tryParseYmd(start) == null ? todayYmd() : start;
    _time = str(p?['time']);
    final vial = str(p?['vialId']);
    _vial = _vialOptions(widget.store.state).containsKey(vial) ? vial : '';
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _interval.dispose();
    _weeks.dispose();
    for (final step in _steps) {
      step.$1.dispose();
      step.$2.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final dose = toDouble(_dose.text);
    if (name.isEmpty || dose <= 0) {
      setState(() {
        _nameError = name.isEmpty ? 'Bitte einen Namen eingeben' : null;
        _doseError = dose <= 0 ? 'Größer als 0' : null;
      });
      return;
    }
    if (_type == 'weekdays' && _days.isEmpty) {
      setState(() => _error = 'Bitte mindestens einen Wochentag wählen.');
      return;
    }
    final data = <String, dynamic>{
      'name': name,
      'dose': dose,
      'unit': _unit,
      'type': _type,
      'n': max(1, toInt(_interval.text)),
      'days': _days.toList()..sort(),
      'start': _start,
      'weeks': max(0, toInt(_weeks.text)),
      'time': _time,
      'vialId': _vial,
      'steps': [
        for (final step in _steps)
          if (toInt(step.$1.text) > 1 && toDouble(step.$2.text) > 0)
            <String, dynamic>{
              'week': toInt(step.$1.text),
              'dose': toDouble(step.$2.text),
            },
      ]..sort((a, b) => (a['week'] as int).compareTo(b['week'] as int)),
    };
    final id = str(widget.existing?['id']);
    widget.store.change((state) {
      final protocols = items(state, 'protocols');
      final current = firstOrNull(protocols, (p) => p['id'] == id);
      if (current != null) {
        current.addAll(data);
      } else {
        protocols.add(<String, dynamic>{
          'id': newId(),
          'active': true,
          ...data,
        });
      }
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => EditorScaffold(
    title: widget.existing == null ? 'Neues Protokoll' : 'Protokoll bearbeiten',
    onSave: _save,
    error: _error,
    children: [
      PeptideNameField(
        controller: _name,
        state: widget.store.state,
        errorText: _nameError,
        onChanged: _clearErrors,
      ),
      NumField(
          controller: _dose,
          label: 'Dosis ($_unit)',
          errorText: _doseError,
          onChanged: (_) => _clearErrors(),
        ),
      dropdown<String>(
        label: 'Rhythmus',
        value: _type,
        options: const <String, String>{
          'daily': 'Täglich',
          'interval': 'Alle N Tage',
          'weekdays': 'Bestimmte Wochentage',
        },
        onChanged: (v) => setState(() => _type = v),
      ),
      if (_type == 'interval')
        NumField(controller: _interval, label: 'Abstand in Tagen'),
      if (_type == 'weekdays')
        Wrap(
          spacing: 6,
          children: [
            for (final day in const [1, 2, 3, 4, 5, 6, 0])
              FilterChip(
                label: Text(weekdayShort[day]),
                selected: _days.contains(day),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _days.add(day);
                  } else {
                    _days.remove(day);
                  }
                }),
              ),
          ],
        ),
      DateField(
        label: 'Startdatum',
        value: _start,
        onChanged: (v) => setState(() => _start = v),
      ),
      TimeField(
        label: 'Uhrzeit für die Erinnerung',
        value: _time,
        clearable: true,
        onChanged: (v) => setState(() => _time = v),
      ),
      NumField(controller: _weeks, label: 'Zyklus in Wochen (leer = offen)'),
      dropdown<String>(
        label: 'Standard-Vial',
        value: _vial,
        options: _vialOptions(widget.store.state),
        onChanged: (v) => setState(() => _vial = v),
      ),
      Text(
        'Dosisstufen (optional): Ab der angegebenen Woche gilt die neue Dosis. Woche 1 beginnt am Startdatum.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      for (final step in _steps)
        Row(
          children: [
            Expanded(
              child: NumField(controller: step.$1, label: 'Ab Woche'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NumField(controller: step.$2, label: 'Dosis ($_unit)'),
            ),
            IconButton(
              tooltip: 'Stufe entfernen',
              onPressed: () => setState(() => _steps.remove(step)),
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(
            () => _steps.add((
              TextEditingController(),
              TextEditingController(),
            )),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Stufe hinzufügen'),
        ),
      ),
    ],
  );
}

/// Vial anlegen oder bearbeiten.
class VialEditor extends StatefulWidget {
  const VialEditor({super.key, required this.store, this.existing});

  final AppStore store;
  final Json? existing;

  @override
  State<VialEditor> createState() => _VialEditorState();
}

class _VialEditorState extends State<VialEditor> {
  late final TextEditingController _name;
  late final TextEditingController _mg;
  late final TextEditingController _ml;
  late final TextEditingController _days;
  late String _mixed;
  String? _error;

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    _name = TextEditingController(text: str(v?['name']));
    _mg = TextEditingController(text: _numText(v?['mg']));
    _ml = TextEditingController(text: _numText(v?['ml']));
    final days = toInt(v?['days']);
    _days = TextEditingController(text: days > 0 ? days.toString() : '');
    _mixed = v == null ? todayYmd() : str(v['mixed']);
  }

  @override
  void dispose() {
    _name.dispose();
    _mg.dispose();
    _ml.dispose();
    _days.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final mg = toDouble(_mg.text);
    if (name.isEmpty || mg <= 0) {
      setState(() => _error = 'Bitte Bezeichnung und Inhalt in mg angeben.');
      return;
    }
    final data = <String, dynamic>{
      'name': name,
      'mg': mg,
      'ml': max(0.0, toDouble(_ml.text)),
      'mixed': _mixed,
      'days': max(0, toInt(_days.text)),
    };
    final id = str(widget.existing?['id']);
    widget.store.change((state) {
      final vials = items(state, 'vials');
      final current = firstOrNull(vials, (v) => v['id'] == id);
      if (current != null) {
        current.addAll(data);
      } else {
        vials.add(<String, dynamic>{'id': newId(), ...data});
      }
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => EditorScaffold(
    title: widget.existing == null ? 'Neues Vial' : 'Vial bearbeiten',
    onSave: _save,
    error: _error,
    children: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Bezeichnung'),
      ),
      NumField(controller: _mg, label: 'Inhalt (mg)'),
      NumField(controller: _ml, label: 'Wasser (ml, optional)'),
      DateField(
        label: 'Angemischt am',
        value: _mixed,
        onChanged: (v) => setState(() => _mixed = v),
      ),
      NumField(controller: _days, label: 'Haltbar (Tage, optional)'),
    ],
  );
}

/// Körperwerte eines Tages eintragen oder bearbeiten.
class BodyEditor extends StatefulWidget {
  const BodyEditor({super.key, required this.store, this.existing});

  final AppStore store;
  final Json? existing;

  @override
  State<BodyEditor> createState() => _BodyEditorState();
}

class _BodyEditorState extends State<BodyEditor> {
  late final TextEditingController _weight;
  late final TextEditingController _waist;
  late final TextEditingController _fat;
  late final TextEditingController _note;
  late String _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _weight = TextEditingController(text: _numText(b?['weight']));
    _waist = TextEditingController(text: _numText(b?['waist']));
    _fat = TextEditingController(text: _numText(b?['fat']));
    _note = TextEditingController(text: str(b?['note']));
    final date = str(b?['date']);
    _date = tryParseYmd(date) == null ? todayYmd() : date;
  }

  @override
  void dispose() {
    _weight.dispose();
    _waist.dispose();
    _fat.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final weight = max(0.0, toDouble(_weight.text));
    final waist = max(0.0, toDouble(_waist.text));
    final fat = max(0.0, toDouble(_fat.text));
    if (weight <= 0 && waist <= 0 && fat <= 0) {
      setState(() => _error = 'Bitte mindestens einen Messwert angeben.');
      return;
    }
    final id = str(widget.existing?['id']);
    widget.store.change((state) {
      final body = items(state, 'body');
      // Pro Tag gibt es eine Messung: gleiche ID oder gleiches Datum ersetzen.
      body.removeWhere((b) => b['id'] == id || b['date'] == _date);
      body.add(<String, dynamic>{
        'id': id.isEmpty ? newId() : id,
        'date': _date,
        'weight': weight,
        'waist': waist,
        'fat': fat,
        'note': _note.text.trim(),
      });
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => EditorScaffold(
    title: widget.existing == null ? 'Messung eintragen' : 'Messung bearbeiten',
    onSave: _save,
    error: _error,
    children: [
      DateField(
        label: 'Datum',
        value: _date,
        onChanged: (v) => setState(() => _date = v),
      ),
      NumField(controller: _weight, label: 'Gewicht (kg)'),
      NumField(controller: _waist, label: 'Bauchumfang (cm)'),
      NumField(controller: _fat, label: 'Körperfett (%)'),
      TextField(
        controller: _note,
        decoration: const InputDecoration(labelText: 'Notiz'),
      ),
    ],
  );
}
