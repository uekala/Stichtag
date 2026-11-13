import 'dart:math';

import 'package:flutter/material.dart';

import '../core/logic.dart';

class ChartPoint {
  const ChartPoint(this.day, this.value);

  /// `JJJJ-MM-TT`
  final String day;
  final double value;
}

/// Verlaufskurve mit Hilfslinien am kleinsten und größten Wert.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.points, required this.emptyText});

  final List<ChartPoint> points;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final valid = points.where((p) => tryParseYmd(p.day) != null).toList();
    if (valid.length < 2) return Text(emptyText);
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 190,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ChartPainter(
          points: valid,
          line: colors.primary,
          grid: colors.outlineVariant,
          text: colors.onSurfaceVariant,
          surface: colors.surface,
        ),
      ),
    );
  }
}

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
