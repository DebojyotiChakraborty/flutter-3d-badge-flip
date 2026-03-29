import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../core/theme/badge_colors.dart';

/// A CustomPainter-based metallic gradient thumbnail for badges.
///
/// Used in the grid (small) and as the heroine flight child (scales up).
/// Renders a circular metallic gradient with the badge's accent color,
/// simulating the look of a 3D metallic badge.
class BadgeThumbnail extends StatelessWidget {
  const BadgeThumbnail({
    super.key,
    required this.accentColor,
    this.size = 100,
  });

  final Color accentColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BadgeThumbnailPainter(accentColor: accentColor),
      ),
    );
  }
}

class _BadgeThumbnailPainter extends CustomPainter {
  final Color accentColor;

  _BadgeThumbnailPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    // Outer glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accentColor.withValues(alpha: 0.3),
          accentColor.withValues(alpha: 0.0),
        ],
        stops: const [0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.2));
    canvas.drawCircle(center, radius * 1.2, glowPaint);

    // Main metallic gradient
    final mainGradient = RadialGradient(
      center: const Alignment(-0.3, -0.3),
      radius: 1.0,
      colors: [
        BadgeColors.highlightFor(accentColor),
        accentColor,
        Color.lerp(accentColor, Colors.black, 0.4)!,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final mainPaint = Paint()
      ..shader = mainGradient
          .createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, mainPaint);

    // Inner ring for depth
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.06
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0.4),
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.2),
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.4),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.85));
    canvas.drawCircle(center, radius * 0.85, ringPaint);

    // Specular highlight
    final highlightPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.5),
        radius: 0.5,
        colors: [
          Colors.white.withValues(alpha: 0.5),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius * 0.7, highlightPaint);

    // Center emblem circle
    final emblemPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.2),
        radius: 0.8,
        colors: [
          Color.lerp(accentColor, Colors.white, 0.2)!,
          accentColor,
          Color.lerp(accentColor, Colors.black, 0.3)!,
        ],
      ).createShader(
          Rect.fromCircle(center: center, radius: radius * 0.55));
    canvas.drawCircle(center, radius * 0.55, emblemPaint);
  }

  @override
  bool shouldRepaint(covariant _BadgeThumbnailPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}
