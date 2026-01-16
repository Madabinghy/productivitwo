import 'dart:math' as math;
import 'package:flutter/material.dart';

class RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final double stroke;
  final Color trackColor;
  final double startAngle; // radians
  final StrokeCap cap; // NEW

  RingPainter({
    required this.progress,
    required this.color,
    required this.stroke,
    required this.trackColor,
    this.startAngle = -math.pi / 2, // en haut
    this.cap = StrokeCap.butt, // NEW
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
      ..strokeCap = cap;

    final progPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = cap;

    final rRect = Rect.fromCircle(center: center, radius: radius);

    // track
    if (trackColor.opacity > 0) {
      canvas.drawArc(rRect, 0, math.pi * 2, false, trackPaint);
    }

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
        old.startAngle != startAngle ||
        old.cap != cap;
  }
}

class NestedGauge extends StatelessWidget {
  final double bigProgress; // 0..1 (ta jauge principale)
  final double smallProgress; // 0..1 (90j)

  // ✅ NEW : halo extérieur 24h brut = trackedHours24 / 24
  final double? outerProgress; // 0..1
  final Color? outerColor; // couleur du halo
  final double outerSizeFactor; // taille relative (halo plus grand)
  final double outerStroke; // épaisseur du halo

  final Color bigColor;
  final Color smallColor;
  final double size;

  final String centerText;
  final String label;

  final VoidCallback? onTap;

  const NestedGauge({
    super.key,
    required this.bigProgress,
    required this.smallProgress,
    required this.bigColor,
    required this.smallColor,
    required this.centerText,
    required this.label,
    this.size = 160,
    this.onTap,

    // ✅ defaults halo
    this.outerProgress,
    this.outerColor,
    this.outerSizeFactor = 1.12,
    this.outerStroke = 10,
  });

  @override
  Widget build(BuildContext context) {
    final track = Colors.white.withValues(alpha: 0.08);

    final content = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ✅ HALO EXTERIEUR (24h brut)
          if (outerProgress != null)
            CustomPaint(
              size: Size.square(size * outerSizeFactor),
              painter: RingPainter(
                progress: outerProgress!.clamp(0.0, 1.0),
                color:
                    (outerColor ?? Colors.cyanAccent).withValues(alpha: 0.45),
                stroke: outerStroke,
                trackColor: Colors.transparent,
              ),
            ),

          // Grand anneau
          CustomPaint(
            size: Size.square(size * 0.90),
            painter: RingPainter(
              progress: bigProgress.clamp(0.0, 1.0),
              color: bigColor,
              stroke: 35,
              trackColor: track,
            ),
          ),

          // Petit anneau (90j)
          CustomPaint(
            size: Size.square(size * 0.45),
            painter: RingPainter(
              progress: smallProgress.clamp(0.0, 1.0),
              color: smallColor,
              stroke: 25,
              trackColor: track,
            ),
          ),

          // Texte
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerText,
                style:
                    const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 15),
              Text(
                "${(smallProgress * 100).round()}%",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 25),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return onTap == null
        ? content
        : InkWell(
            borderRadius: BorderRadius.circular(size),
            onTap: onTap,
            child: content,
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

