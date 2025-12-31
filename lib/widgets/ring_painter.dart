import 'dart:math' as math;
import 'package:flutter/material.dart';

class RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final double stroke;
  final Color trackColor;
  final double startAngle; // radians

  RingPainter({
    required this.progress,
    required this.color,
    required this.stroke,
    required this.trackColor,
    this.startAngle = -math.pi / 2, // en haut
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) / 2) - stroke / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final progPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final rRect = Rect.fromCircle(center: center, radius: radius);

    // track
    canvas.drawArc(rRect, 0, math.pi * 2, false, trackPaint);

    // progress
    final sweep = (math.pi * 2) * progress.clamp(0.0, 1.0);
    canvas.drawArc(rRect, startAngle, sweep, false, progPaint);
  }

  @override
  bool shouldRepaint(covariant RingPainter old) {
    return old.progress != progress ||
        old.color != color ||
        old.stroke != stroke ||
        old.trackColor != trackColor ||
        old.startAngle != startAngle;
  }
}

class NestedGauge extends StatelessWidget {
  final double bigProgress;   // ex: période actuelle (jour) 0..1
  final double smallProgress; // ex: moyenne 90j 0..1
  final Color bigColor;
  final Color smallColor;
  final double size;

  final String centerText; // "19h23m" ou "0h13m"
  final String label;      // "Jour — Temps"

  const NestedGauge({
    super.key,
    required this.bigProgress,
    required this.smallProgress,
    required this.bigColor,
    required this.smallColor,
    required this.centerText,
    required this.label,
    this.size = 160,
  });

  @override
  Widget build(BuildContext context) {
    final track = Colors.white.withValues(alpha: 0.08);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Grand anneau
          CustomPaint(
            size: Size.square(size *0.90),
            painter: RingPainter(
              progress: bigProgress,
              color: bigColor,
              stroke: 35,
              trackColor: track,
            ),
          ),

          // Petit anneau (à l'intérieur)
          CustomPaint(
            size: Size.square(size * 0.45),
            painter: RingPainter(
              progress: smallProgress,
              color: smallColor,
              stroke: 25,
              trackColor: track,
            ),
          ),

          // Texte au centre
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(centerText,
                  style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
              const SizedBox(height: 15),
              Text("${(smallProgress * 100).round()}%",
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.75))),
              const SizedBox(height: 25),
              Text(label,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.85))),
            ],
          ),
        ],
      ),
    );
  }
}


class GaugeRingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color fg;
  final Color bg;
  final double strokeWidth;
  final StrokeCap cap;

  GaugeRingPainter({
    required this.progress,
    required this.fg,
    required this.bg,
    required this.strokeWidth,
    this.cap = StrokeCap.round,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) / 2) - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = cap;

    final progPaint = Paint()
      ..color = fg
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = cap;

    // Track (full ring)
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    // Progress (start at top)
    final start = -math.pi / 2;
    final sweep = (math.pi * 2) * p;
    canvas.drawArc(rect, start, sweep, false, progPaint);
  }

  @override
  bool shouldRepaint(covariant GaugeRingPainter old) {
    return old.progress != progress ||
        old.fg != fg ||
        old.bg != bg ||
        old.strokeWidth != strokeWidth ||
        old.cap != cap;
  }
}

