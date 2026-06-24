// Prototype gamification « RPG / Stats » — piste d'évaluation.
//
// Deux usages :
//  • Démo isolée : RpgProtoApp (données simulées).
//  • Données réelles : lib/web/rpg_data_screen.dart réutilise RpgView.
//
// Métaphore : chaque domaine de vie est un ATTRIBUT de personnage. Le temps
// loggué = de l'XP qui fait monter l'attribut de niveau. Le radar montre
// l'équilibre de vie d'un coup d'œil — une forme régulière = vie équilibrée.

import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() => runApp(const RpgProtoApp());

class RpgProtoApp extends StatelessWidget {
  const RpgProtoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RPG Proto',
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const RpgScreen(),
    );
  }
}

// ── Modèle d'un attribut/domaine ────────────────────────────────────────────
class RpgAttr {
  const RpgAttr({
    required this.name,
    required this.color,
    required this.level,
    required this.progress, // 0..1 vers le niveau suivant
    required this.radar, // 0..1 normalisé pour le radar
    required this.todayXp, // minutes loggées aujourd'hui
    this.totalLabel,
  });

  final String name;
  final Color color;
  final int level;
  final double progress;
  final double radar;
  final int todayXp;
  final String? totalLabel;
}

// ── Vue RPG animée réutilisable ─────────────────────────────────────────────
class RpgView extends StatefulWidget {
  const RpgView({
    super.key,
    required this.attrs,
    required this.globalLevel,
    required this.title,
    required this.globalProgress,
    required this.globalXpLabel,
    this.onTapAttr,
  });

  final List<RpgAttr> attrs;
  final int globalLevel;
  final String title;
  final double globalProgress;
  final String globalXpLabel;
  final void Function(RpgAttr attr)? onTapAttr;

  @override
  State<RpgView> createState() => _RpgViewState();
}

class _RpgViewState extends State<RpgView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _t = CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic);
    _ac.forward();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('FICHE PERSONNAGE',
                  style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 2,
                      color: Color(0xFF8A82AD),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _header(),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth;
                return SizedBox(
                  width: w,
                  height: w * 0.96,
                  child: CustomPaint(
                    painter: _RadarPainter(attrs: widget.attrs, t: t),
                  ),
                );
              }),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Attributs',
                      style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.w800)),
                  Text('XP aujourd\'hui',
                      style:
                          TextStyle(fontSize: 13, color: Color(0xFF8A82AD))),
                ],
              ),
              const SizedBox(height: 12),
              ...widget.attrs.map((a) => _attrRow(a, t)),
              const SizedBox(height: 12),
              _quest(),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment(-0.3, -0.3),
              colors: [Color(0xFFFFE9A8), Color(0xFFC98A2A)],
            ),
          ),
          child: const Center(
              child: Text('🛡', style: TextStyle(fontSize: 32))),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Niveau ${widget.globalLevel}',
                  style: const TextStyle(
                      fontSize: 28,
                      color: Colors.white,
                      fontWeight: FontWeight.w800)),
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 15, color: Color(0xFFFFD9A0))),
              const SizedBox(height: 10),
              _bar(widget.globalProgress, const Color(0xFFFFD36B), 8),
              const SizedBox(height: 6),
              Text(widget.globalXpLabel,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF8A82AD))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _attrRow(RpgAttr a, double t) {
    final active = a.todayXp > 0;
    return GestureDetector(
      onTap: () => widget.onTapAttr?.call(a),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: a.color.withOpacity(0.18)),
              child: Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: a.color),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Niveau ${a.level}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8A82AD))),
                ],
              ),
            ),
            SizedBox(
                width: 110, child: _bar(a.progress * t, a.color, 9)),
            const SizedBox(width: 12),
            SizedBox(
              width: 54,
              child: Text(
                active ? '+${a.todayXp}' : '+0',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? const Color(0xFF7BE07B)
                        : const Color(0xFF5A5570)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quest() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF6C4FD6).withOpacity(0.22),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFA78BFF).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('Quête du jour',
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('Logge ton attribut le plus faible → bonus d\'équilibre',
              style: TextStyle(fontSize: 13, color: Color(0xFFD6CFFA))),
        ],
      ),
    );
  }

  Widget _bar(double frac, Color color, double h) {
    return LayoutBuilder(builder: (context, c) {
      return Stack(children: [
        Container(
          height: h,
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(h / 2)),
        ),
        Container(
          height: h,
          width: c.maxWidth * frac.clamp(0, 1),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(h / 2)),
        ),
      ]);
    });
  }
}

// ── Radar painter ───────────────────────────────────────────────────────────
class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.attrs, required this.t});
  final List<RpgAttr> attrs;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final n = attrs.length;
    if (n < 3) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * 0.66;

    Offset vertex(int i, double r) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      return Offset(center.dx + math.cos(a) * r, center.dy + math.sin(a) * r);
    }

    // anneaux concentriques
    for (final ring in const [0.33, 0.66, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = vertex(i, radius * ring);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withOpacity(0.08),
      );
    }
    // rayons
    for (var i = 0; i < n; i++) {
      canvas.drawLine(
        center,
        vertex(i, radius),
        Paint()
          ..strokeWidth = 1
          ..color = Colors.white.withOpacity(0.06),
      );
    }

    // polygone des valeurs (animé par t)
    final valPath = Path();
    for (var i = 0; i < n; i++) {
      final p = vertex(i, radius * attrs[i].radar.clamp(0, 1) * t);
      i == 0 ? valPath.moveTo(p.dx, p.dy) : valPath.lineTo(p.dx, p.dy);
    }
    valPath.close();
    canvas.drawPath(
      valPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFA78BFF).withOpacity(0.28),
    );
    canvas.drawPath(
      valPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFFC9B8FF),
    );

    // sommets + libellés
    for (var i = 0; i < n; i++) {
      final a = attrs[i];
      final vp = vertex(i, radius * a.radar.clamp(0, 1) * t);
      canvas.drawCircle(vp, 4, Paint()..color = a.color);

      final ang = -math.pi / 2 + i * 2 * math.pi / n;
      final lp = vertex(i, radius + 20);
      final align = math.cos(ang).abs() < 0.3
          ? TextAlign.center
          : (math.cos(ang) > 0 ? TextAlign.left : TextAlign.right);
      _label(canvas, a.name, lp, a.color, align, size.width);
    }
  }

  void _label(Canvas canvas, String s, Offset at, Color color,
      TextAlign align, double maxW) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 110);
    double dx;
    switch (align) {
      case TextAlign.left:
        dx = at.dx;
        break;
      case TextAlign.right:
        dx = at.dx - tp.width;
        break;
      default:
        dx = at.dx - tp.width / 2;
    }
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.t != t || old.attrs != attrs;
}

// ── Écran démo (données simulées) ───────────────────────────────────────────
class RpgScreen extends StatelessWidget {
  const RpgScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const attrs = [
      RpgAttr(name: 'Business', color: Color(0xFFFFB347), level: 9, progress: 0.6, radar: 0.92, todayXp: 18),
      RpgAttr(name: 'Mindset', color: Color(0xFF8A6EF0), level: 6, progress: 0.4, radar: 0.62, todayXp: 8),
      RpgAttr(name: 'Organisation', color: Color(0xFF4FD17A), level: 7, progress: 0.7, radar: 0.74, todayXp: 12),
      RpgAttr(name: 'Développement', color: Color(0xFF36C9C9), level: 5, progress: 0.3, radar: 0.5, todayXp: 0),
      RpgAttr(name: 'Esprit', color: Color(0xFF5A8FD6), level: 4, progress: 0.5, radar: 0.42, todayXp: 5),
      RpgAttr(name: 'Finances', color: Color(0xFFFF5A47), level: 6, progress: 0.45, radar: 0.6, todayXp: 9),
      RpgAttr(name: 'Sport', color: Color(0xFFB06DF0), level: 5, progress: 0.55, radar: 0.55, todayXp: 0),
      RpgAttr(name: 'Spiritualité', color: Color(0xFFD06DE0), level: 3, progress: 0.35, radar: 0.35, todayXp: 4),
      RpgAttr(name: 'Lecture', color: Color(0xFFFFD36B), level: 4, progress: 0.4, radar: 0.4, todayXp: 6),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF0A0813),
      body: RpgView(
        attrs: attrs,
        globalLevel: 24,
        title: 'Architecte de vie',
        globalProgress: 0.66,
        globalXpLabel: '12 840 / 19 500 XP → Nv 25',
        onTapAttr: (a) {},
      ),
    );
  }
}
