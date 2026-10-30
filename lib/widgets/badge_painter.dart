import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';

/// Gabarit de badge (design « Badges Productivitwo », section Gabarit) porté
/// en CustomPainter : grille 100 × 100 u (1 u = 1 % de la taille), trois
/// couches — écusson, symbole dans le cercle r 22 centré (50, 42), ruban
/// y 70 → 84 avec chevrons de niveau ou texte — et la jauge r 46 autour d'un
/// badge en progression (l'ensemble réduit à 84 %). Même tracé dans les deux
/// états : le verrouillé est la silhouette de l'acquis.

const kBadgeOlive100 = Color(0xFF8A9D5C);
const kBadgeOlive300 = Color(0xFF5E7040);
const kBadgeOlive500 = Color(0xFF4A5A2F);
const kBadgeKhaki = Color(0xFFC9B978);
const kBadgeKhakiDark = Color(0xFF8E8150);
/// Braises (rallumage d'une série cassée hier).
const kEmberColor = Color(0xFFFF8A3D);
/// Jour gelé par une veille (bandes de série) : gris-vert, ni tenu ni manqué.
const kFrozenColor = Color(0xFF86A093);
const kBadgeBrass = Color(0xFFD4B35A);
const kBadgeBrassDark = Color(0xFFA8863A);
const kBadgeRibbonInk = Color(0xFF1A1F12);
const kBadgeLockedShield = Color(0xFF0E1A14);
const kBadgeLockedRim = Color(0xFF27382D);
const kBadgeLockedSymbol = Color(0xFF3A4F41);
const kBadgeLockedBand = Color(0xFF16241B);
const kBadgeGaugeTrack = Color(0xFF1B2A20);
const kBadgeGaugeFill = Color(0xFF27C48F);
/// Segment provisoire de la jauge : ce qu'aujourd'hui ajoute une fois la journée close.
const kBadgeGaugeToday = Color(0xFFF2A93B);
// Chevrons de niveau atteints : rouge corail, choisi sur planche (2026-10-26)
// pour trancher sur le ruban khaki à 72 et 40 px ; les chevrons à venir
// restent un contour d'encre.
const kBadgeChevron = Color(0xFFE0523F);
const kBadgeChevronDark = Color(0xFF8C2E22);

/// Un badge dessiné depuis son état : `BadgeView(state: s, size: 72)`.
class BadgeView extends StatelessWidget {
  final BadgeState state;
  final double size;
  /// Impact du jour sur la jauge (2026-10) : [todayGain] = ce que la journée
  /// ajoutera à la mesure si elle tient (trait « atteignable ce soir »),
  /// [todaySecured] = la journée tient pour l'instant (segment jaune jusqu'au
  /// trait). Sans effet sur un badge sans jauge.
  final num todayGain;
  final bool todaySecured;
  /// Part du faisable du jour (0..1) : sur un badge SANS jauge de palier
  /// (Journée parfaite, Vent contraire, Plein jour), l'anneau la montre en
  /// orange, pour voir la journée avancer avant que le badge ne tombe.
  final double? todayRatio;
  const BadgeView({super.key, required this.state, this.size = 72, this.todayGain = 0, this.todaySecured = false, this.todayRatio});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final target = s.nextTarget;
    final tick = s.showGauge && todayGain > 0 && target != null && target > 0 ? ((s.value + todayGain) / target).clamp(0.0, 1.0).toDouble() : null;
    final dayRing = !s.showGauge && !s.complete && todayRatio != null;
    return Semantics(
      label: '${s.def.name}${s.acquired ? '' : ', pas encore obtenu'}',
      child: CustomPaint(
        size: Size.square(size),
        painter: BadgePainter(
          symbol: s.def.symbol,
          acquired: s.acquired,
          levels: s.def.levels,
          level: s.level,
          progress: s.showGauge ? s.progress : (dayRing ? 0.0 : null),
          label: s.ribbonLabel,
          tick: tick,
          provisional: dayRing ? todayRatio : (tick != null && todaySecured ? tick : null),
        ),
      ),
    );
  }
}

class BadgePainter extends CustomPainter {
  final String symbol;
  final bool acquired;
  final int levels; // 2–5 → chevrons ; 1 ou > 5 → texte du ruban
  final int level;
  final double? progress; // 0..1 → jauge ; null = pas de jauge
  final String label;
  /// Trait « atteignable aujourd'hui » (0..1) et fin du segment provisoire
  /// jaune (0..1, de [progress] à [provisional]) quand la journée tient.
  final double? tick;
  final double? provisional;
  const BadgePainter({
    required this.symbol,
    required this.acquired,
    this.levels = 1,
    this.level = 0,
    this.progress,
    this.label = '',
    this.tick,
    this.provisional,
  });

  static final Path _shield = Path()
    ..moveTo(16, 10)
    ..lineTo(84, 10)
    ..lineTo(84, 52)
    ..cubicTo(84, 72, 68, 86, 50, 92)
    ..cubicTo(32, 86, 16, 72, 16, 52)
    ..close();
  static final Path _shieldInner = Path()
    ..moveTo(21, 15)
    ..lineTo(79, 15)
    ..lineTo(79, 51)
    ..cubicTo(79, 68, 66, 80, 50, 86.5)
    ..cubicTo(34, 80, 21, 68, 21, 51)
    ..close();
  static final Path _ribbon = _poly([10, 70, 90, 70, 86, 77, 90, 84, 10, 84, 14, 77]);

  static Path _poly(List<double> xy) {
    final p = Path()..moveTo(xy[0], xy[1]);
    for (var i = 2; i < xy.length; i += 2) {
      p.lineTo(xy[i], xy[i + 1]);
    }
    return p..close();
  }

  static Path chevron(double x) =>
      _poly([x - 4.5, 78, x, 72.5, x + 4.5, 78, x + 4.5, 81.5, x, 76, x - 4.5, 81.5]);

  @override
  void paint(Canvas canvas, Size size) {
    final px = size.shortestSide;
    if (px <= 0) return;
    canvas.save();
    canvas.scale(px / 100);
    final pips = levels >= 2 && levels <= 5;
    final gauge = progress != null;
    if (gauge) {
      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = kBadgeGaugeTrack;
      canvas.drawCircle(const Offset(50, 50), 46, track);
      final ratio = progress!.clamp(0.0, 1.0);
      if (ratio > 0) {
        final fill = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = kBadgeGaugeFill;
        canvas.drawArc(Rect.fromCircle(center: const Offset(50, 50), radius: 46), -math.pi / 2, 2 * math.pi * ratio, false, fill);
      }
      final prov = provisional;
      if (prov != null && prov > ratio) {
        final today = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = kBadgeGaugeToday;
        canvas.drawArc(Rect.fromCircle(center: const Offset(50, 50), radius: 46), -math.pi / 2 + 2 * math.pi * ratio, 2 * math.pi * (prov.clamp(0.0, 1.0) - ratio), false, today);
      }
      final t = tick;
      if (t != null && t > ratio) {
        final a = -math.pi / 2 + 2 * math.pi * t.clamp(0.0, 1.0);
        final mark = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = kBadgeGaugeToday;
        canvas.drawLine(Offset(50 + 41.5 * math.cos(a), 50 + 41.5 * math.sin(a)), Offset(50 + 50.5 * math.cos(a), 50 + 50.5 * math.sin(a)), mark);
      }
      canvas.translate(50, 50);
      canvas.scale(.84);
      canvas.translate(-50, -50);
    }

    // Couche 1 : écusson.
    final shieldFill = Paint()..style = PaintingStyle.fill;
    if (acquired) {
      shieldFill.shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [kBadgeOlive100, kBadgeOlive500],
      ).createShader(const Rect.fromLTWH(16, 10, 68, 82));
    } else {
      shieldFill.color = kBadgeLockedShield;
    }
    canvas.drawPath(_shield, shieldFill);
    canvas.drawPath(
        _shield,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..color = acquired ? kBadgeKhaki : kBadgeLockedRim);
    if (acquired) {
      canvas.drawPath(
          _shieldInner,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = kBadgeBrass.withValues(alpha: .85));
    }

    // Couche 2 : symbole.
    paintSymbol(canvas, symbol, acquired ? kBadgeBrass : kBadgeLockedSymbol, acquired ? kBadgeOlive300 : kBadgeLockedShield);

    // Couche 3 : ruban.
    canvas.drawPath(_ribbon, Paint()..color = acquired ? kBadgeKhaki : kBadgeLockedBand);
    canvas.drawPath(
        _ribbon,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeJoin = StrokeJoin.round
          ..color = acquired ? kBadgeKhakiDark : kBadgeLockedRim);
    if (pips) {
      const reachedFill = kBadgeChevron;
      const reachedStroke = kBadgeChevronDark;
      final todoStroke = kBadgeRibbonInk.withValues(alpha: .45);
      const w = 9.0, gap = 3.0;
      final total = levels * w + (levels - 1) * gap;
      final x0 = 50 - total / 2 + w / 2;
      for (var i = 0; i < levels; i++) {
        final p = chevron(x0 + i * (w + gap));
        if (i < level) {
          canvas.drawPath(p, Paint()..color = reachedFill);
          canvas.drawPath(
              p,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4
                ..strokeJoin = StrokeJoin.round
                ..color = reachedStroke);
        } else {
          canvas.drawPath(
              p,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4
                ..strokeJoin = StrokeJoin.round
                ..color = acquired ? todoStroke : kBadgeLockedSymbol);
        }
      }
    } else if (acquired && label.isNotEmpty && px >= 96) {
      final tp = TextPainter(
        text: TextSpan(
          text: label.toUpperCase(),
          style: const TextStyle(
            color: kBadgeRibbonInk,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .6,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(50 - tp.width / 2, 77 - tp.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BadgePainter old) =>
      old.symbol != symbol || old.acquired != acquired || old.levels != levels || old.level != level || old.progress != progress || old.label != label || old.tick != tick || old.provisional != provisional;

  /// Les symboles, en unités de grille, dans le cercle r 22 centré (50, 42).
  /// Trait 6 u (anneaux 5 u), bouts ronds, rien sous 4 u ; `ink` = encre,
  /// `cut` = couleur des évidements.
  static void paintSymbol(Canvas c, String key, Color ink, Color cut) {
    Paint stroke(double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    final fill = Paint()..color = ink;
    void line(double x1, double y1, double x2, double y2, [double w = 5]) => c.drawLine(Offset(x1, y1), Offset(x2, y2), stroke(w));
    void polyline(List<double> xy, [double w = 6]) {
      final p = Path()..moveTo(xy[0], xy[1]);
      for (var i = 2; i < xy.length; i += 2) {
        p.lineTo(xy[i], xy[i + 1]);
      }
      c.drawPath(p, stroke(w));
    }

    switch (key) {
      case 'flame':
        final outer = Path()
          ..moveTo(50, 20)
          ..cubicTo(56, 28, 65, 36, 65, 46)
          ..arcToPoint(const Offset(35, 46), radius: const Radius.circular(15), clockwise: true)
          ..cubicTo(35, 37, 42, 33, 42, 26)
          ..cubicTo(44, 30, 47, 26, 50, 20)
          ..close();
        c.drawPath(outer, fill);
        final inner = Path()
          ..moveTo(50, 40)
          ..cubicTo(54, 44, 57, 47, 57, 51)
          ..arcToPoint(const Offset(43, 51), radius: const Radius.circular(7), clockwise: true)
          ..cubicTo(43, 47, 46, 44, 50, 40)
          ..close();
        c.drawPath(inner, Paint()..color = cut);
      case 'target':
        c.drawCircle(const Offset(50, 42), 19, stroke(5));
        c.drawCircle(const Offset(50, 42), 9, stroke(5));
        c.drawCircle(const Offset(50, 42), 3, fill);
      case 'hit':
        c.drawCircle(const Offset(46, 46), 17, stroke(5));
        c.drawCircle(const Offset(46, 46), 6, fill);
        line(46, 46, 68, 24, 6);
        polyline([58, 24, 68, 24, 68, 34]);
      case 'trajectory':
        polyline([30, 58, 43, 44, 52, 51, 69, 28]);
        polyline([58, 28, 69, 28, 69, 39]);
      case 'ledger':
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(33, 23, 34, 38), const Radius.circular(4)), stroke(5));
        line(41, 35, 59, 35);
        line(41, 43, 59, 43);
        line(41, 51, 52, 51);
      case 'sun':
        c.drawCircle(const Offset(50, 42), 9, fill);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line(50 + math.cos(a) * 15, 42 + math.sin(a) * 15, 50 + math.cos(a) * 22, 42 + math.sin(a) * 22);
        }
      case 'bricks2':
        for (final r in const [
          [29.0, 30.0, 20.0],
          [51.0, 30.0, 20.0],
          [29.0, 42.0, 9.0],
          [40.0, 42.0, 20.0],
          [62.0, 42.0, 9.0],
        ]) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r[0], r[1], r[2], 10), const Radius.circular(1.5)), fill);
        }
      case 'bricks3':
        for (final r in const [
          [29.0, 24.0, 20.0],
          [51.0, 24.0, 20.0],
          [29.0, 36.0, 9.0],
          [40.0, 36.0, 20.0],
          [62.0, 36.0, 9.0],
          [29.0, 48.0, 20.0],
          [51.0, 48.0, 20.0],
        ]) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r[0], r[1], r[2], 10), const Radius.circular(1.5)), fill);
        }
      case 'chain':
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(27, 34, 26, 16), const Radius.circular(8)), stroke(5));
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(47, 34, 26, 16), const Radius.circular(8)), stroke(5));
      case 'sunrise':
        final half = Path()
          ..moveTo(34, 50)
          ..arcToPoint(const Offset(66, 50), radius: const Radius.circular(16), clockwise: true)
          ..close();
        c.drawPath(half, fill);
        line(26, 57, 74, 57);
        line(50, 22, 50, 29);
        line(31, 32, 36, 37);
        line(69, 32, 64, 37);
      case 'check':
        c.drawCircle(const Offset(50, 42), 19, stroke(5));
        polyline([40, 43, 47, 50, 61, 34]);
      case 'hourglass':
        c.drawPath(_poly([36, 23, 64, 23, 52, 42, 64, 61, 36, 61, 48, 42]), stroke(5));
        c.drawPath(_poly([43, 57, 50, 48, 57, 57]), fill);
      case 'anvil':
        c.drawPath(_poly([26, 36, 32, 31, 70, 31, 70, 40, 58, 40, 58, 49, 62, 49, 62, 57, 38, 57, 38, 49, 42, 49, 42, 40, 34, 40]), fill);
      case 'tide':
        for (final dy in const [0.0, 12.0]) {
          final p = Path()
            ..moveTo(29, 48 + dy)
            ..cubicTo(34, 42 + dy, 40, 42 + dy, 45, 48 + dy)
            ..cubicTo(50, 54 + dy, 56, 54 + dy, 61, 48 + dy)
            ..cubicTo(64, 44 + dy, 68, 43 + dy, 71, 46 + dy);
          c.drawPath(p, stroke(5));
        }
        line(50, 36, 50, 22, 6);
        polyline([43, 29, 50, 22, 57, 29]);
      case 'wind':
        line(36, 22, 36, 63, 6);
        c.drawPath(_poly([40, 24, 70, 31, 40, 44]), fill);
        line(66, 50, 54, 50);
        line(70, 58, 50, 58);
      case 'barometer':
        c.drawCircle(const Offset(50, 44), 20, stroke(5));
        line(50, 44, 62, 32, 6);
        c.drawCircle(const Offset(50, 44), 4.5, fill);
        line(38, 56, 41, 53, 4);
        line(62, 56, 59, 53, 4);
      case 'rebound':
        // Reprise : trois quarts de cercle, tête pleine alignée sur l'arc (12 h).
        c.drawArc(Rect.fromCircle(center: const Offset(50, 42), radius: 14), 0, 1.5 * math.pi, false, stroke(6));
        c.drawPath(_poly([50, 19, 61, 28, 50, 37]), fill);
        c.drawPath(_poly([50, 19, 61, 28, 50, 37]), stroke(2));
      case 'focus':
        c.drawCircle(const Offset(50, 42), 20, stroke(5));
        c.drawCircle(const Offset(50, 42), 11, stroke(4));
        c.drawCircle(const Offset(50, 42), 4, fill);
      default:
        c.drawCircle(const Offset(50, 42), 12, fill);
    }
  }
}
