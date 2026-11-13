import 'package:flutter/material.dart';

import '../core/app_store.dart';
import '../core/logic.dart';
import 'editors.dart';
import 'widgets.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.store});

  final AppStore store;

  /// Trägt die Dosis mit den Vorgaben des Protokolls ein und bietet Rückgängig an.
  void _quickLog(BuildContext context, Json protocol) {
    final id = newId();
    final name = str(protocol['name']);
    store.change((state) {
      items(state, 'logs').add(<String, dynamic>{
        'id': id,
        'ts': nowStamp(),
        'pid': protocol['id'],
        'name': name,
        'dose': doseOn(protocol, todayYmd()),
        'unit': protocol['unit'],
        'site': nextSite(state),
        'feel': 0,
        'note': '',
        'vialId': str(protocol['vialId']),
      });
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Eingetragen: $name'),
          action: SnackBarAction(
            label: 'Rückgängig',
            onPressed: () => store.change(
              (state) =>
                  items(state, 'logs').removeWhere((log) => log['id'] == id),
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = store.state;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = todayYmd();
    final due = items(
      state,
      'protocols',
    ).where((p) => isDue(p, today)).toList();
    final todays = logsOn(state, today);
    final done = due
        .where((p) => todays.any((log) => log['pid'] == p['id']))
        .length;
    final site = nextSite(state);
    final extra = todays
        .where((log) => !due.any((p) => p['id'] == log['pid']))
        .toList();
    final low = lowVials(state);
    final next = upcoming(state, today);

    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text(deDate(today), style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            value: due.isEmpty ? 0 : done / due.length,
                            strokeWidth: 6,
                            backgroundColor: colors.outlineVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Heute erledigt',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                '$done / ${due.length}',
                                style: theme.textTheme.headlineSmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Nächste Stelle',
                  value: site.isEmpty ? '–' : site,
                  small: true,
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
                  Text('Letzte 7 Tage', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var back = 6; back >= 0; back--)
                        Expanded(
                          child: _DayDot(
                            day: addDays(today, -back),
                            result: adherence(state, addDays(today, -back)),
                            isToday: back == 0,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          for (final vial in low)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Card(
                margin: EdgeInsets.zero,
                color: colors.tertiaryContainer,
                child: ListTile(
                  leading: Icon(
                    Icons.warning_amber,
                    color: colors.onTertiaryContainer,
                  ),
                  title: Text(
                    vialLevel(state, vial).leftMcg <= 0
                        ? '${str(vial['name'])} ist leer'
                        : '${str(vial['name'])} ist fast leer',
                    style: TextStyle(color: colors.onTertiaryContainer),
                  ),
                  subtitle: Text(
                    '${fmtNum(vialLevel(state, vial).leftMcg / 1000, 3)} mg übrig',
                    style: TextStyle(color: colors.onTertiaryContainer),
                  ),
                ),
              ),
            ),
          for (final vial in items(state, 'vials'))
            if ((vialDaysLeft(vial, today) ?? 0) < 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Card(
                  margin: EdgeInsets.zero,
                  color: colors.errorContainer,
                  child: ListTile(
                    leading: Icon(
                      Icons.event_busy,
                      color: colors.onErrorContainer,
                    ),
                    title: Text(
                      '${str(vial['name'])} ist nicht mehr haltbar',
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                    subtitle: Text(
                      'Frist abgelaufen am ${deDate(addDays(str(vial['mixed']), toInt(vial['days'])))}',
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 20),
          Text('Fällig heute', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (due.isEmpty)
            const InfoCard(
              'Heute ist nichts fällig. Lege unter Protokolle einen Plan an.',
            ),
          for (final protocol in due)
            _DueCard(
              store: store,
              protocol: protocol,
              log: firstOrNull(todays, (log) => log['pid'] == protocol['id']),
              today: today,
              onQuickLog: () => _quickLog(context, protocol),
            ),
          for (final log in extra)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(str(log['name'])),
                subtitle: Text(
                  '${fmtNum(toDouble(log['dose']), 3)} ${str(log['unit'])}',
                ),
                trailing: Pill('Eingetragen', color: colors.primary),
                onTap: () =>
                    openPage(context, LogEditor(store: store, existing: log)),
              ),
            ),
          const SizedBox(height: 20),
          Text('Die nächsten 7 Tage', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (next.isEmpty)
            const InfoCard('In den nächsten 7 Tagen ist nichts geplant.')
          else
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    for (final entry in next)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 92,
                              child: Text(
                                entry.key == addDays(today, 1)
                                    ? 'Morgen'
                                    : deDate(entry.key).substring(0, 10),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                entry.value
                                    .map(
                                      (p) =>
                                          '${str(p['name'])} ${fmtNum(doseOn(p, entry.key), 3)} ${str(p['unit'])}',
                                    )
                                    .join(', '),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.day,
    required this.result,
    required this.isToday,
  });

  final String day;
  final Adherence result;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Color color = colors.outlineVariant;
    if (result.due > 0) {
      if (result.done == result.due) {
        color = colors.primary;
      } else if (result.done > 0) {
        color = colors.tertiary;
      } else if (!isToday) {
        color = colors.error;
      }
    }
    final date = tryParseYmd(day);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            date == null ? '' : weekdayShort[jsWeekday(date)],
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({
    required this.store,
    required this.protocol,
    required this.log,
    required this.today,
    required this.onQuickLog,
  });

  final AppStore store;
  final Json protocol;
  final Json? log;
  final String today;
  final VoidCallback onQuickLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entry = log;
    final time = str(protocol['time']);
    final weeks = toInt(protocol['weeks']);
    final day = (dayDiff(str(protocol['start']), today) ?? 0) + 1;
    final details = [
      '${fmtNum(doseOn(protocol, today), 3)} ${str(protocol['unit'])}',
      if (time.isNotEmpty) '$time Uhr',
      if (weeks > 0) 'Tag $day von ${weeks * 7}',
    ].join(' · ');
    String doneText = '';
    if (entry != null) {
      final stamp = str(entry['ts']);
      final site = str(entry['site']);
      doneText = [
        if (stamp.length >= 16) '${stamp.substring(11, 16)} Uhr',
        if (site.isNotEmpty) site,
      ].join(' · ');
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                Pill(
                  entry == null ? 'Offen' : 'Erledigt',
                  color: entry == null ? colors.tertiary : colors.primary,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(details),
            const SizedBox(height: 8),
            if (entry == null)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => openPage(
                      context,
                      LogEditor(store: store, protocol: protocol),
                    ),
                    child: const Text('Anpassen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onQuickLog,
                    icon: const Icon(Icons.check),
                    label: const Text('Dosis erledigt'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(doneText, style: theme.textTheme.bodySmall),
                  ),
                  TextButton(
                    onPressed: () => openPage(
                      context,
                      LogEditor(store: store, existing: entry),
                    ),
                    child: const Text('Bearbeiten'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
