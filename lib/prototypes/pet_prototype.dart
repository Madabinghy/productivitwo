// Prototype gamification « Compagnon » — piste d'évaluation (dessiné en code).
//
// Deux usages :
//  • Démo isolée : PetProtoApp (données simulées).
//  • Données réelles : lib/web/pet_data_screen.dart réutilise PetView.
//
// Mécanique mainstream (modèle Finch) : un petit être dont l'HUMEUR et la
// CROISSANCE suivent ta régularité. Logguer une routine/session le nourrit →
// il est content et grandit. Le négliger → il s'endort/se morfond. Le streak
// fait pousser sa petite tige. On revient pour LUI (ancrage émotionnel) +
// aversion à la perte (ne pas casser le streak).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

void main() => runApp(const PetProtoApp());

class PetProtoApp extends StatelessWidget {
  const PetProtoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pet Proto',
      theme: ThemeData(useMaterial3: true),
      home: const PetScreen(),
    );
  }
}

enum PetMood { happy, content, sad, asleep }

class PetData {
  const PetData({
    required this.streak,
    required this.energy, // 0..1 progression du jour
    required this.mood,
    required this.doneToday,
    required this.dueToday,
    required this.statusText,
    this.name = 'Pousse',
  });
  final int streak;
  final double energy;
  final PetMood mood;
  final int doneToday;
  final int dueToday;
  final String statusText;
  final String name;

  int get level => 1 + streak ~/ 3;
}

// ── Vue compagnon animée réutilisable ───────────────────────────────────────
class PetView extends StatefulWidget {
  const PetView({super.key, required this.data, this.onPet});
  final PetData data;
  final VoidCallback? onPet; // appelé au tap (réaction de caresse)

  @override
  State<PetView> createState() => _PetViewState();
}

class _Spark {
  _Spark(this.pos, this.vel, this.color);
  Offset pos;
  Offset vel;
  final Color color;
  double life = 0;
}

class _PetViewState extends State<PetView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _t = 0;
  double _bounce = 0; // pic de rebond au tap, décroît
  final List<_Spark> _sparks = [];
  final _rnd = math.Random(7);

  PetData get _d => widget.data;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration e) {
    final dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (dt <= 0 || dt > 0.1) {
      setState(() {});
      return;
    }
    _t += dt;
    _bounce = (_bounce - dt * 2.6).clamp(0.0, 1.0);
    for (final s in _sparks) {
      s.life += dt * 1.1;
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * 0.96, s.vel.dy + 220 * dt); // gravité douce
    }
    _sparks.removeWhere((s) => s.life >= 1);
    setState(() {});
  }

  void _pet(Offset center) {
    _bounce = 1;
    final happy = _d.mood != PetMood.asleep;
    final n = happy ? 14 : 5;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.2;
      final sp = 90 + _rnd.nextDouble() * 120;
      _sparks.add(_Spark(
        center.translate(0, -30),
        Offset(math.cos(a) * sp, math.sin(a) * sp),
        happy
            ? const Color(0xFFFFD36B)
            : Colors.white.withOpacity(0.8),
      ));
    }
    widget.onPet?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final center = Offset(size.width / 2, size.height * 0.46);
      return GestureDetector(
        onTapDown: (_) => _pet(center),
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          size: size,
          painter: _PetPainter(_d, _t, _bounce, _sparks),
        ),
      );
    });
  }
}

class _PetPainter extends CustomPainter {
  _PetPainter(this.d, this.t, this.bounce, this.sparks);
  final PetData d;
  final double t;
  final double bounce;
  final List<_Spark> sparks;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final mood = d.mood;

    // ── fond selon l'humeur (jour chaud → nuit) ──────────────────────────
    final List<Color> bg = switch (mood) {
      PetMood.happy => const [Color(0xFFFFF3D6), Color(0xFFFFE0C2), Color(0xFFFFD0C8)],
      PetMood.content => const [Color(0xFFEAF6E8), Color(0xFFD7EEDE), Color(0xFFCDE6E6)],
      PetMood.sad => const [Color(0xFFDFE3E8), Color(0xFFC9D0D9), Color(0xFFB7C0CC)],
      PetMood.asleep => const [Color(0xFF2A2350), Color(0xFF1A1640), Color(0xFF12102E)],
    };
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: bg)
            .createShader(rect),
    );

    // soleil / lune
    final isNight = mood == PetMood.asleep;
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.16),
      30,
      Paint()
        ..color = (isNight ? const Color(0xFFE8E3FF) : const Color(0xFFFFE9A8))
            .withOpacity(isNight ? 0.5 : 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    if (isNight) {
      for (final p in const [
        [0.2, 0.12],
        [0.5, 0.2],
        [0.35, 0.08],
        [0.68, 0.28]
      ]) {
        canvas.drawCircle(Offset(size.width * p[0], size.height * p[1]), 2,
            Paint()..color = Colors.white.withOpacity(0.7));
      }
    }

    final center = Offset(size.width / 2, size.height * 0.46);

    // ── corps (blob) ─────────────────────────────────────────────────────
    final level = d.level;
    final baseR = 70.0 + math.min(level, 8) * 4.0;
    final breathe = 1 + 0.03 * math.sin(t * 1.6);
    final bob = mood == PetMood.happy ? 4 * math.sin(t * 1.5) : 0.0;
    final pop = Curves.easeOut.transform(bounce); // 0..1
    final sx = 1 + 0.10 * pop; // étirement horizontal au rebond
    final sy = breathe - 0.10 * pop + (mood == PetMood.happy ? 0.0 : 0.0);
    final cy = center.dy + bob - 10 * pop;
    final r = baseR;

    final Color body = switch (mood) {
      PetMood.happy => const Color(0xFF5BD0A0),
      PetMood.content => const Color(0xFF6FC9A6),
      PetMood.sad => const Color(0xFF9DB8AC),
      PetMood.asleep => const Color(0xFF6E8FA0),
    };

    // ombre au sol
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(center.dx, center.dy + r * 0.92),
          width: r * 1.7 * sx,
          height: r * 0.4),
      Paint()..color = Colors.black.withOpacity(isNight ? 0.22 : 0.10),
    );

    canvas.save();
    canvas.translate(center.dx, cy);
    canvas.scale(sx, sy);

    // tige de croissance (hauteur ∝ streak) — derrière le corps
    final sprout = math.min(d.streak, 30) / 30.0; // 0..1
    if (sprout > 0.02) {
      final h = 16 + sprout * 46;
      final stem = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF4Fa86a);
      canvas.drawLine(Offset(0, -r * 0.9), Offset(0, -r * 0.9 - h), stem);
      final leaf = Paint()..color = const Color(0xFF6Fd08a);
      _leaf(canvas, Offset(-2, -r * 0.9 - h * 0.6), 14 + sprout * 8, -0.6, leaf);
      _leaf(canvas, Offset(2, -r * 0.9 - h * 0.85), 16 + sprout * 10, 0.6, leaf);
    }

    // corps
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Color.lerp(Colors.white, body, 0.35)!, body],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );

    // joues (si content/heureux)
    if (mood == PetMood.happy || mood == PetMood.content) {
      final blush = Paint()
        ..color = const Color(0xFFFF9EC4)
            .withOpacity(mood == PetMood.happy ? 0.55 : 0.3);
      canvas.drawCircle(Offset(-r * 0.5, r * 0.18), r * 0.14, blush);
      canvas.drawCircle(Offset(r * 0.5, r * 0.18), r * 0.14, blush);
    }

    // yeux
    final eyeY = -r * 0.12;
    final eyeDx = r * 0.34;
    final blink = (t % 3.6) < 0.13; // clignement
    _eyes(canvas, mood, Offset(-eyeDx, eyeY), Offset(eyeDx, eyeY), r, blink);

    // bouche
    _mouth(canvas, mood, Offset(0, r * 0.34), r);

    canvas.restore();

    // ZZZ si endormi
    if (mood == PetMood.asleep) {
      final zp = Offset(center.dx + r * 0.7, cy - r * 0.7);
      for (var i = 0; i < 3; i++) {
        final ph = (t * 0.6 + i * 0.33) % 1;
        final o = (1 - ph);
        _text(canvas, 'z', zp.translate(i * 16.0, -ph * 40),
            const Color(0xFFB9B2E0).withOpacity(o), 16 + i * 6.0);
      }
    }

    // étincelles
    for (final s in sparks) {
      final op = (1 - s.life).clamp(0, 1).toDouble();
      canvas.drawCircle(s.pos, 3.2 * op + 1,
          Paint()..color = s.color.withOpacity(op));
    }
  }

  void _eyes(Canvas c, PetMood m, Offset l, Offset rt, double r, bool blink) {
    if (m == PetMood.asleep || blink) {
      // yeux fermés : arc vers le bas
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF2A3340);
      for (final e in [l, rt]) {
        final path = Path()
          ..moveTo(e.dx - 9, e.dy)
          ..quadraticBezierTo(e.dx, e.dy + 7, e.dx + 9, e.dy);
        c.drawPath(path, p);
      }
      return;
    }
    final white = Paint()..color = Colors.white;
    final pupil = Paint()..color = const Color(0xFF2A3340);
    final droop = m == PetMood.sad ? 0.5 : 1.0; // yeux mi-clos si triste
    for (final e in [l, rt]) {
      c.drawOval(
          Rect.fromCenter(
              center: e, width: r * 0.30, height: r * 0.36 * droop + r * 0.12),
          white);
      final look = m == PetMood.sad ? 4.0 : 0.0;
      c.drawCircle(e.translate(0, look), r * 0.10, pupil);
      c.drawCircle(e.translate(-r * 0.03, -r * 0.04 + look), r * 0.03,
          Paint()..color = Colors.white);
    }
  }

  void _mouth(Canvas c, PetMood m, Offset o, double r) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF2A3340);
    final w = r * 0.34;
    final path = Path();
    switch (m) {
      case PetMood.happy:
        path.moveTo(o.dx - w, o.dy - 2);
        path.quadraticBezierTo(o.dx, o.dy + 16, o.dx + w, o.dy - 2);
      case PetMood.content:
        path.moveTo(o.dx - w * 0.7, o.dy);
        path.quadraticBezierTo(o.dx, o.dy + 8, o.dx + w * 0.7, o.dy);
      case PetMood.sad:
        path.moveTo(o.dx - w * 0.7, o.dy + 6);
        path.quadraticBezierTo(o.dx, o.dy - 6, o.dx + w * 0.7, o.dy + 6);
      case PetMood.asleep:
        path.moveTo(o.dx - w * 0.3, o.dy);
        path.quadraticBezierTo(o.dx, o.dy + 5, o.dx + w * 0.3, o.dy);
    }
    c.drawPath(path, p);
    // larme si triste
    if (m == PetMood.sad) {
      c.drawCircle(Offset(o.dx - r * 0.34, o.dy - r * 0.5), 4,
          Paint()..color = const Color(0xFF7FB7E8));
    }
  }

  void _leaf(Canvas c, Offset o, double s, double rot, Paint p) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(rot);
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(s * 0.6, -s * 0.5, s, 0)
      ..quadraticBezierTo(s * 0.6, s * 0.5, 0, 0);
    c.drawPath(path, p);
    c.restore();
  }

  void _text(Canvas c, String s, Offset at, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color, fontSize: size, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
  }

  @override
  bool shouldRepaint(covariant _PetPainter old) => true;
}

// ── Écran démo (données simulées + contrôles) ───────────────────────────────
class PetScreen extends StatefulWidget {
  const PetScreen({super.key});
  @override
  State<PetScreen> createState() => _PetScreenState();
}

class _PetScreenState extends State<PetScreen> {
  int _streak = 14;
  int _done = 1;
  final int _due = 4;
  double _daysSince = 0.2;

  PetMood get _mood {
    if (_daysSince >= 3) return PetMood.asleep;
    if (_daysSince >= 1.5) return PetMood.sad;
    if (_done / _due >= 0.6) return PetMood.happy;
    return PetMood.content;
  }

  PetData get _data => PetData(
        streak: _streak,
        energy: (_done / _due).clamp(0.0, 1.0),
        mood: _mood,
        doneToday: _done,
        dueToday: _due,
        statusText: switch (_mood) {
          PetMood.happy => 'Pousse est ravie ! 🌱',
          PetMood.content => 'Encore une routine et elle rayonne',
          PetMood.sad => 'Pousse s\'ennuie… reviens la voir',
          PetMood.asleep => 'Pousse s\'est endormie 😴',
        },
      );

  void _feed() => setState(() {
        _done = (_done + 1).clamp(0, _due);
        _daysSince = 0.1;
      });

  void _skipDay() => setState(() {
        _daysSince += 1;
        _done = 0;
        if (_daysSince <= 1.2) _streak += 0; else _streak = 0;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: PetView(data: _data, onPet: () {})),
        _PetHud(data: _data, onFeed: _feed, onSkip: _skipDay, demo: true),
      ]),
    );
  }
}

// HUD partagé (chip streak + statut + énergie + boutons démo)
class _PetHud extends StatelessWidget {
  const _PetHud(
      {required this.data, this.onFeed, this.onSkip, this.demo = false});
  final PetData data;
  final VoidCallback? onFeed;
  final VoidCallback? onSkip;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final dark = data.mood == PetMood.asleep;
    final fg = dark ? Colors.white : const Color(0xFF2A3340);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(dark ? 0.14 : 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('🔥 ${data.streak} j',
                      style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                ),
                const Spacer(),
                Text('${data.name} · niv. ${data.level}',
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              children: [
                Text(data.statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                _energyBar(fg),
                const SizedBox(height: 6),
                Text('Énergie du jour · ${data.doneToday}/${data.dueToday}',
                    style: TextStyle(color: fg.withOpacity(0.7), fontSize: 13)),
                if (demo) ...[
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                        child: _btn('Nourrir 🌱', const Color(0xFF1D9E75),
                            Colors.white, onFeed)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _btn('Passer un jour',
                            Colors.white.withOpacity(0.5), fg, onSkip)),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _energyBar(Color fg) {
    return LayoutBuilder(builder: (context, c) {
      return Stack(children: [
        Container(
          height: 14,
          decoration: BoxDecoration(
              color: fg.withOpacity(0.15),
              borderRadius: BorderRadius.circular(7)),
        ),
        Container(
          height: 14,
          width: c.maxWidth * data.energy.clamp(0.0, 1.0),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF7BE0B0), Color(0xFF1D9E75)]),
              borderRadius: BorderRadius.circular(7)),
        ),
      ]);
    });
  }

  Widget _btn(String label, Color bg, Color fg, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(26)),
        child: Text(label,
            style: TextStyle(
                color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }
}

// exposé pour la vue données réelles
class PetHud extends StatelessWidget {
  const PetHud({super.key, required this.data});
  final PetData data;
  @override
  Widget build(BuildContext context) => _PetHud(data: data);
}
