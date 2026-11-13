import 'package:flutter/material.dart';

import '../core/app_store.dart';
import '../core/logic.dart';
import 'editors.dart';
import 'widgets.dart';

class ProtocolsPage extends StatelessWidget {
  const ProtocolsPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = todayYmd();
    final protocols = items(store.state, 'protocols');
    if (protocols.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: InfoCard('Noch kein Protokoll angelegt.'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        for (final protocol in protocols)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          str(protocol['name']),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      _status(protocol, today, colors),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_summary(protocol)),
                  Text(_period(protocol), style: theme.textTheme.bodySmall),
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _toggle(str(protocol['id'])),
                        child: Text(
                          protocol['active'] == true
                              ? 'Pausieren'
                              : 'Fortsetzen',
                        ),
                      ),
                      TextButton(
                        onPressed: () => openPage(
                          context,
                          ProtocolEditor(store: store, existing: protocol),
                        ),
                        child: const Text('Bearbeiten'),
                      ),
                      TextButton(
                        onPressed: () => _delete(context, str(protocol['id'])),
                        child: Text(
                          'Löschen',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _status(Json protocol, String today, ColorScheme colors) {
    final diff = dayDiff(str(protocol['start']), today) ?? 0;
    final weeks = toInt(protocol['weeks']);
    if (protocol['active'] != true) {
      return Pill('Pausiert', color: colors.outline);
    }
    if (weeks > 0 && diff >= weeks * 7) {
      return Pill('Zyklus beendet', color: colors.outline);
    }
    if (diff < 0) return Pill('Startet bald', color: colors.outline);
    return Pill('Aktiv', color: colors.primary);
  }

  String _summary(Json protocol) {
    final time = str(protocol['time']);
    return [
      '${fmtNum(toDouble(protocol['dose']), 3)} ${str(protocol['unit'])}',
      freqLabel(protocol),
      if (time.isNotEmpty) '$time Uhr',
    ].join(' · ');
  }

  String _period(Json protocol) {
    final weeks = toInt(protocol['weeks']);
    final start = deDate(str(protocol['start']));
    return weeks > 0
        ? 'Start $start · $weeks Wochen'
        : 'Start $start · ohne Enddatum';
  }

  void _toggle(String id) => store.change((state) {
    final protocol = firstOrNull(items(state, 'protocols'), (p) => p['id'] == id);
    if (protocol != null) protocol['active'] = protocol['active'] != true;
  });

  Future<void> _delete(BuildContext context, String id) async {
    final ok = await confirm(
      context,
      'Dieses Protokoll löschen? Der Verlauf bleibt erhalten.',
    );
    if (!ok) return;
    store.change(
      (state) => items(state, 'protocols').removeWhere((p) => p['id'] == id),
    );
  }
}
