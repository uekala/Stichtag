import 'dart:math';

import 'package:flutter/material.dart';

import '../core/app_store.dart';
import '../core/logic.dart';
import 'editors.dart';
import 'widgets.dart';

const _metrics = <String, List<String>>{
  'weight': ['Gewicht', 'kg'],
  'waist': ['Bauchumfang', 'cm'],
  'fat': ['Körperfett', '%'],
};

class ChartPoint {
  const ChartPoint(this.day, this.value);

  final String day;
  final double value;
}

class BodyPage extends StatefulWidget {
  const BodyPage({super.key, required this.store});

  final AppStore store;

  @override
  State<BodyPage> createState() => _BodyPageState();
}

class _BodyPageState extends State<BodyPage> {
  String _metric = 'weight';

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
    final colors = theme.colorScheme;
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
            child: points.length < 2
                ? const Text('Ab zwei Messwerten erscheint hier die Kurve.')
                : SizedBox(
                    height: 190,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _ChartPainter(
                        points: points,
                        line: colors.primary,
                        grid: colors.outlineVariant,
                        text: colors.onSurfaceVariant,
                        surface: colors.surface,
                      ),
                    ),
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

/// Verlaufskurve mit Hilfslinien am kleinsten und größten Messwert.
class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.line,
    required this.grid,
    required this.text,
    required this.surface,
  });

  final List<ChartPoint> points;
  final Color line;
  final Color grid;
  final Color text;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 46.0;
    const right = 10.0;
    const top = 12.0;
    const bottom = 24.0;
    final values = points.map((p) => p.value).toList();
    final minValue = values.reduce(min);
    final maxValue = values.reduce(max);
    var low = minValue;
    var high = maxValue;
    if (high - low < 1e-9) {
      low -= 1;
      high += 1;
    } else {
      final pad = (high - low) * 0.15;
      low -= pad;
      high += pad;
    }
    final first = tryParseYmd(points.first.day)!;
    final total = max(1, tryParseYmd(points.last.day)!.difference(first).inDays);
    double x(ChartPoint p) =>
        left +
        tryParseYmd(p.day)!.difference(first).inDays /
            total *
            (size.width - left - right);
    double y(double value) =>
        top + (high - value) / (high - low) * (size.height - top - bottom);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final ticks = maxValue - minValue < 1e-9
        ? <double>[minValue]
        : <double>[minValue, maxValue];
    for (final tick in ticks) {
      canvas.drawLine(
        Offset(left, y(tick)),
        Offset(size.width - right, y(tick)),
        gridPaint,
      );
      final label = _label(fmtNum(tick, 1));
      label.paint(
        canvas,
        Offset(left - 6 - label.width, y(tick) - label.height / 2),
      );
    }

    final path = Path()..moveTo(x(points.first), y(points.first.value));
    for (final point in points.skip(1)) {
      path.lineTo(x(point), y(point.value));
    }
    final area = Path.from(path)
      ..lineTo(x(points.last), size.height - bottom)
      ..lineTo(x(points.first), size.height - bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.12));
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      final center = Offset(x(point), y(point.value));
      if (identical(point, points.last)) {
        canvas.drawCircle(center, 5, Paint()..color = line);
      } else {
        canvas.drawCircle(center, 3.5, Paint()..color = line);
        canvas.drawCircle(center, 2, Paint()..color = surface);
      }
    }

    final start = _label(_shortDate(points.first.day));
    start.paint(canvas, Offset(left, size.height - start.height));
    final end = _label(_shortDate(points.last.day));
    end.paint(
      canvas,
      Offset(size.width - right - end.width, size.height - end.height),
    );
  }

  String _shortDate(String day) =>
      day.length >= 10 ? '${day.substring(8, 10)}.${day.substring(5, 7)}.' : day;

  TextPainter _label(String value) => TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(color: text, fontSize: 11),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.line != line ||
      oldDelegate.surface != surface;
}
