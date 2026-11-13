import 'package:flutter/material.dart';

/// Das Stichtag-Zeichen: ein Kalenderblatt mit einem Tropfen.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _LogoPainter()),
  );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 108, size.height / 108);
    const box = Rect.fromLTWH(0, 0, 108, 108);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(26)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12907E), Color(0xFF07453C)],
        ).createShader(box),
    );
    final white = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(30, 30, 48, 52),
        const Radius.circular(8),
      ),
      white,
    );
    final rings = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(42, 23), const Offset(42, 33), rings);
    canvas.drawLine(const Offset(66, 23), const Offset(66, 33), rings);
    final drop = Path()
      ..moveTo(54, 42)
      ..cubicTo(54, 42, 43, 54, 43, 62)
      ..arcToPoint(
        const Offset(65, 62),
        radius: const Radius.circular(11),
        clockwise: false,
      )
      ..cubicTo(65, 54, 54, 42, 54, 42)
      ..close();
    canvas.drawPath(drop, Paint()..color = const Color(0xFF0B6E60));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
