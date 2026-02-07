import 'dart:math' as math;
import 'package:flutter/material.dart';

double expectedSinceMidnight(DateTime now) {
  final midnight = DateTime(now.year, now.month, now.day);
  final minutes = now.difference(midnight).inMinutes.clamp(0, 24 * 60);
  return minutes / 1440.0;
}

/// Dessine UNIQUEMENT le segment [actual -> expected] si expected > actual
class GapRingPainter extends CustomPainter {
  final double actual; // 0..1
  final double expected; // 0..1
  final double stroke;
  final Color color;
  final double startAngle; // -pi/2 => start en haut

  GapRingPainter({
    required this.actual,
    required this.expected,
    required this.stroke,
    required this.color,
    this.startAngle = -math.pi / 2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final a = actual.clamp(0.0, 1.0);
    final e = expected.clamp(0.0, 1.0);
    if (e <= a) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = stroke
      ..color = color;

    final from = 2 * math.pi * a;
    final sweep = 2 * math.pi * (e - a);

    canvas.drawArc(rect, startAngle + from, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant GapRingPainter old) {
    return old.actual != actual ||
        old.expected != expected ||
        old.stroke != stroke ||
        old.color != color ||
        old.startAngle != startAngle;
  }
}

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

  String progressLabel(double p) {
    if (p >= 1.0) return "🎯";
    return "${(p * 100).round()}%";
  }

  Widget buildCenter(double progress) {
    return Text(
      "${(progress * 100).round()}%",
      style: TextStyle(
        fontSize: 12, // 👈 petit et discret
        fontWeight: FontWeight.w700,
        color: Colors.white.withOpacity(0.85),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = Colors.white.withValues(alpha: 0.08);
    final expected = expectedSinceMidnight(DateTime.now());

    final content = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ✅ HALO EXTERIEUR (temps loggé aujourd’hui / objectif du jour)
          if (outerProgress != null) ...[
            // anneau normal (cyan)
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

            // ✅ RETARD (écart) en jaune SUR LE MÊME ANNEAU
            CustomPaint(
              size: Size.square(size * outerSizeFactor),
              painter: GapRingPainter(
                actual: outerProgress!.clamp(0.0, 1.0),
                expected: expected, // 0..1
                stroke: outerStroke,
                color: Colors.yellow.withValues(alpha: 0.85),
              ),
            ),
          ],

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

          // Texte...
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center, // 🔒 explicite
            children: [
              Text(
                centerText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 15),

              buildCenter(smallProgress), // pas besoin de Center ici

              const SizedBox(height: 23),

              Text(
                label,
                textAlign: TextAlign.center, // 🔑 important
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
