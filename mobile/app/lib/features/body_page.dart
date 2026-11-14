import 'package:flutter/material.dart';

import '../core/app_store.dart';
import '../core/logic.dart';
import 'editors.dart';
import 'line_chart.dart';
import 'widgets.dart';

const _metrics = <String, List<String>>{
  'weight': ['Gewicht', 'kg'],
  'waist': ['Bauchumfang', 'cm'],
  'fat': ['Körperfett', '%'],
};

class BodyPage extends StatefulWidget {
  const BodyPage({super.key, required this.store});

  final AppStore store;

  @override
  State<BodyPage> createState() => _BodyPageState();
}

class _BodyPageState extends State<BodyPage> {
  String _metric = 'weight';

  /// null: das am häufigsten eingetragene Peptid; leer: keine Markierungen.
  String? _markName;

  Future<void> _delete(String id) async {
    final ok = await confirm(context, 'Diese Messung löschen?');
    if (!ok) return;
    widget.store.change(
      (state) => items(state, 'body').removeWhere((b) => b['id'] == id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _metrics[_metric]![0];
    final unit = _metrics[_metric]![1];
    final entries = List<Json>.from(items(widget.store.state, 'body'))
      ..sort((a, b) => str(a['date']).compareTo(str(b['date'])));
    final points = [
      for (final entry in entries)
        if (toDouble(entry[_metric]) > 0 &&
            tryParseYmd(str(entry['date'])) != null)
          ChartPoint(str(entry['date']), toDouble(entry[_metric])),
    ];
    final names = namesByUse(widget.store.state);
    var markName = _markName ?? (names.isEmpty ? '' : names.first);
    if (!names.contains(markName)) markName = '';
    final marks = [
      if (markName.isNotEmpty)
        for (final change in doseChanges(widget.store.state, markName))
          ChartMark(change.key, change.value),
    ];
    final last = points.isEmpty ? null : points.last;
    final diff = points.length > 1 ? points.last.value - points.first.value : 0;
    final sign = diff > 0 ? '+' : '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(value: 'weight', label: Text('Gewicht')),
            ButtonSegment<String>(value: 'waist', label: Text('Bauch')),
            ButtonSegment<String>(value: 'fat', label: Text('Körperfett')),
          ],
          selected: <String>{_metric},
          onSelectionChanged: (selection) =>
              setState(() => _metric = selection.first),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatCard(
                label: '$label aktuell',
                value: last == null ? '–' : '${fmtNum(last.value, 1)} $unit',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'Seit erster Messung',
                value: points.length > 1
                    ? '$sign${fmtNum(diff, 1)} $unit'
                    : '–',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (names.isNotEmpty) ...[
                  KeyedSubtree(
                    key: ValueKey<String>('mark-$markName-${names.join('|')}'),
                    child: dropdown<String>(
                      label: 'Dosis einblenden',
                      value: markName,
                      options: <String, String>{
                        '': 'Keine',
                        for (final name in names) name: name,
                      },
                      onChanged: (value) => setState(() => _markName = value),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                LineChart(
                  points: points,
                  marks: marks,
                  emptyText: 'Ab zwei Messwerten erscheint hier die Kurve.',
                ),
                if (markName.isNotEmpty && points.length > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Gestrichelte Linien zeigen, ab wann eine andere Dosis von $markName eingetragen wurde.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Messungen', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (entries.isEmpty) const InfoCard('Noch keine Messung eingetragen.'),
        for (final entry in entries.reversed)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(deDate(str(entry['date']))),
              subtitle: Text(_values(entry)),
              onTap: () => openPage(
                context,
                BodyEditor(store: widget.store, existing: entry),
              ),
              trailing: IconButton(
                tooltip: 'Messung löschen',
                onPressed: () => _delete(str(entry['id'])),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
      ],
    );
  }

  String _values(Json entry) {
    final weight = toDouble(entry['weight']);
    final waist = toDouble(entry['waist']);
    final fat = toDouble(entry['fat']);
    final note = str(entry['note']);
    return [
      if (weight > 0) '${fmtNum(weight, 1)} kg',
      if (waist > 0) '${fmtNum(waist, 1)} cm',
      if (fat > 0) '${fmtNum(fat, 1)} %',
      if (note.isNotEmpty) note,
    ].join(' · ');
  }
}
