import 'package:flutter/material.dart';

import '../core/app_store.dart';
import '../core/logic.dart';
import 'editors.dart';
import 'widgets.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.store});

  final AppStore store;

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(deDate(today), style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatCard(
                label: 'Heute erledigt',
                value: '$done / ${due.length}',
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
            ),
          ),
      ],
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
  });

  final AppStore store;
  final Json protocol;
  final Json? log;
  final String today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entry = log;
    final time = str(protocol['time']);
    final weeks = toInt(protocol['weeks']);
    final day = (dayDiff(str(protocol['start']), today) ?? 0) + 1;
    final details = [
      '${fmtNum(toDouble(protocol['dose']), 3)} ${str(protocol['unit'])}',
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
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => openPage(
                    context,
                    LogEditor(store: store, protocol: protocol),
                  ),
                  child: const Text('Eintragen'),
                ),
              )
            else
              Text(doneText, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
