import 'package:flutter/material.dart';

class BetControlLogo extends StatelessWidget {
  final double size;
  const BetControlLogo({super.key, this.size = 70});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  static const Color _dark = Color(0xFF1A1A2E);
  static const Color _accent = Color(0xFF00D4AA);
  static const Color _white = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Rounded square background
    final bgPaint = Paint()..color = _dark;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
      const Radius.circular(20),
    );
    canvas.drawRRect(bgRect, bgPaint);

    // Shield outline
    final shieldPaint = Paint()
      ..color = _accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final shieldPath = Path();
    shieldPath.moveTo(cx - 22, cy - 18);
    shieldPath.lineTo(cx, cy - 24);
    shieldPath.lineTo(cx + 22, cy - 18);
    shieldPath.lineTo(cx + 22, cy + 4);
    shieldPath.quadraticBezierTo(cx + 22, cy + 24, cx, cy + 32);
    shieldPath.quadraticBezierTo(cx - 22, cy + 24, cx - 22, cy + 4);
    shieldPath.close();
    canvas.drawPath(shieldPath, shieldPaint);

    // Lock shackle
    final shacklePaint = Paint()
      ..color = _white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final shacklePath = Path();
    shacklePath.moveTo(cx - 12, cy + 2);
    shacklePath.lineTo(cx - 12, cy - 8);
    shacklePath.arcToPoint(
      Offset(cx + 12, cy - 8),
      radius: const Radius.circular(12),
      clockwise: false,
    );
    shacklePath.lineTo(cx + 12, cy + 2);
    canvas.drawPath(shacklePath, shacklePaint);

    // Lock body
    final bodyPaint = Paint()..color = _white;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 12), width: 30, height: 22),
      const Radius.circular(5),
    );
    canvas.drawRRect(bodyRect, bodyPaint);

    // Keyhole circle
    final keyholePaint = Paint()..color = _dark;
    canvas.drawCircle(Offset(cx, cy + 10), 4.5, keyholePaint);

    // Keyhole slot
    final slotRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 17), width: 4, height: 7),
      const Radius.circular(2),
    );
    canvas.drawRRect(slotRect, keyholePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}