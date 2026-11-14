import 'package:flutter/material.dart';

import '../core/logic.dart';
import 'line_chart.dart';
import 'widgets.dart';

/// Auswertung: Einhaltung, Zahlen je Peptid, Befinden und Stellen.
class StatsView extends StatelessWidget {
  const StatsView({super.key, required this.state});

  final Json state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = todayYmd();
    final weeks = weekStats(state, today);
    final dueTotal = weeks.fold<int>(0, (sum, week) => sum + week.due);
    final doneTotal = weeks.fold<int>(0, (sum, week) => sum + week.done);
    final peptides = peptideStats(state, today);
    final feel = [
      for (final entry in feelSeries(state, today))
        ChartPoint(entry.key, entry.value),
    ];
    final tags = tagCounts(state, today);
    final maxTag = tags.isEmpty ? 1 : tags.first.value;
    final sites = siteCounts(state, today);
    final maxSite = sites.values.fold<int>(1, (a, b) => a > b ? a : b);

    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: theme.textTheme.titleMedium),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Einhaltung', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Letzte 8 Wochen, je 7 Tage ab dem Datum',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      dueTotal == 0
                          ? '–'
                          : '${(doneTotal / dueTotal * 100).round()} % gesamt',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final week in weeks)
                      Expanded(child: _WeekBar(week: week)),
                  ],
                ),
              ],
            ),
          ),
        ),
        title('Je Peptid'),
        if (peptides.isEmpty) const InfoCard('Noch keine Einträge.'),
        for (final stat in peptides)
          Card(
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
                          stat.name,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${entriesLabel(stat.total)} gesamt',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stat.recent == 0
                        ? 'Keine Einträge in den letzten 30 Tagen'
                        : '${entriesLabel(stat.recent)} in 30 Tagen · ${amountLabel(stat.sums)}',
                  ),
                  if (stat.last.length >= 10)
                    Text(
                      'Zuletzt ${deDate(stat.last.substring(0, 10))}',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (stat.due > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Einhaltung 30 Tage',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          '${stat.done} von ${stat.due} · ${(stat.done / stat.due * 100).round()} %',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: stat.done / stat.due,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                      color: stat.done / stat.due < 0.8
                          ? colors.tertiary
                          : colors.primary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        title('Befinden'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mittelwert je Tag, letzte 60 Tage (1 = schlecht, 5 = sehr gut)',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                LineChart(
                  points: feel,
                  emptyText:
                      'Ab zwei Tagen mit Angabe erscheint hier die Kurve.',
                ),
              ],
            ),
          ),
        ),
        title('Nebenwirkungen'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wie oft angekreuzt, letzte 30 Tage',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (tags.isEmpty) const Text('Keine Nebenwirkungen eingetragen.'),
                for (final entry in tags)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(flex: 5, child: Text(entry.key)),
                        Expanded(
                          flex: 5,
                          child: LinearProgressIndicator(
                            value: entry.value / maxTag,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                            color: colors.tertiary,
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${entry.value}',
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        title('Stellen'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Einträge je Stelle in den letzten 30 Tagen',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (sites.isEmpty) const Text('Keine Stellen angelegt.'),
                for (final entry in sites.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(flex: 5, child: Text(entry.key)),
                        Expanded(
                          flex: 5,
                          child: LinearProgressIndicator(
                            value: entry.value / maxSite,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${entry.value}',
                            textAlign: TextAlign.end,
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
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({required this.week});

  final WeekStat week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rate = week.rate;
    final start = week.start;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          Text(
            rate == null ? '–' : '${(rate * 100).round()}',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 90,
              width: double.infinity,
              child: ColoredBox(
                color: rate == null
                    ? colors.surfaceContainerHighest
                    : colors.outlineVariant,
                child: FractionallySizedBox(
                  alignment: Alignment.bottomCenter,
                  heightFactor: (rate ?? 0).clamp(0.0, 1.0).toDouble(),
                  child: ColoredBox(color: colors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            start.length >= 10
                ? '${start.substring(8, 10)}.${start.substring(5, 7)}.'
                : start,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
