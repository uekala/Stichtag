import 'package:flutter/material.dart';

import '../core/app_store.dart';
import '../core/logic.dart';
import 'widgets.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.store});

  final AppStore store;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _filter = '';

  Future<void> _delete(String id) async {
    final ok = await confirm(context, 'Diesen Eintrag löschen?');
    if (!ok) return;
    widget.store.change(
      (state) => items(state, 'logs').removeWhere((log) => log['id'] == id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = items(widget.store.state, 'logs');
    final names = all.map((log) => str(log['name'])).toSet().toList()..sort();
    if (!names.contains(_filter)) _filter = '';
    final logs =
        all.where((log) => _filter.isEmpty || log['name'] == _filter).toList()
          ..sort((a, b) => str(b['ts']).compareTo(str(a['ts'])));

    final children = <Widget>[
      dropdown<String>(
        label: 'Filter',
        value: _filter,
        options: <String, String>{
          '': 'Alle Peptide',
          for (final name in names) name: name,
        },
        onChanged: (value) => setState(() => _filter = value),
      ),
      const SizedBox(height: 12),
      if (logs.isEmpty) const InfoCard('Noch keine Einträge.'),
    ];
    var lastDay = '';
    for (final log in logs) {
      final stamp = str(log['ts']);
      final day = stamp.length >= 10 ? stamp.substring(0, 10) : stamp;
      if (day != lastDay) {
        lastDay = day;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text(deDate(day), style: theme.textTheme.labelLarge),
          ),
        );
      }
      final site = str(log['site']);
      final note = str(log['note']);
      final feel = toInt(log['feel']);
      final details = [
        if (stamp.length >= 16) '${stamp.substring(11, 16)} Uhr',
        if (site.isNotEmpty) site,
        if (feel > 0) 'Befinden $feel/5',
        if (note.isNotEmpty) note,
      ].join(' · ');
      children.add(
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            title: Text(
              '${str(log['name'])}  ${fmtNum(toDouble(log['dose']), 3)} ${str(log['unit'])}',
            ),
            subtitle: details.isEmpty ? null : Text(details),
            trailing: IconButton(
              tooltip: 'Eintrag löschen',
              onPressed: () => _delete(str(log['id'])),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        ),
      );
    }
    return ListView(
      key: ValueKey<String>('history-${names.join('|')}'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: children,
    );
  }
}
