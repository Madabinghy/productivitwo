// Prototype gamification « Défense néon » — mini-tranche jouable (dessinée en code).
//
// La mécanique que tu kiffes (tes routines = des tourelles qui défendent),
// reskin néon/dark + juice, ZÉRO stratégie : ça se joue tout seul, tu regardes
// le spectacle. Données réelles : chaque domaine/routine = une tourelle (couleur
// du domaine, puissance = ta régularité). Les nuisibles arrivent, ça canarde,
// ça glow, ça explose.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

void main() => runApp(const DefenseProtoApp());

class DefenseProtoApp extends StatelessWidget {
  const DefenseProtoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Defense Proto',
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const DefenseScreen(),
    );
  }
}

class TurretSpec {
  const TurretSpec(this.color, this.charge, this.label);
  final Color color;
  final double charge; // 0..1 (régularité → cadence/puissance)
  final String label;
}

// ── Entités de simulation ───────────────────────────────────────────────────
class _Turret {
  _Turret(this.spec, this.pos);
  final TurretSpec spec;
  final Offset pos;
  double angle = -math.pi / 2;
  double cd = 0;
}

class _Enemy {
  _Enemy(this.pos, this.vel, this.hp, this.color, this.r);
  Offset pos;
  Offset vel;
  double hp;
  final double maxHp0 = 0;
  Color color;
  double r;
  double hit = 0; // flash récent
}

class _Proj {
  _Proj(this.pos, this.vel, this.color, this.target);
  Offset pos;
  Offset vel;
  final Color color;
  _Enemy? target;
  double life = 0;
  final List<Offset> trail = [];
}

class _Part {
  _Part(this.pos, this.vel, this.color, this.size);
  Offset pos;
  Offset vel;
  final Color color;
  double size;
  double life = 0;
}

class _Ring {
  _Ring(this.pos, this.color, this.max);
  final Offset pos;
  final Color color;
  final double max;
  double life = 0;
}

// ── Vue / simulation ────────────────────────────────────────────────────────
class DefenseView extends StatefulWidget {
  const DefenseView({super.key, required this.turrets});
  final List<TurretSpec> turrets;

  @override
  State<DefenseView> createState() => _DefenseViewState();
}

class _DefenseViewState extends State<DefenseView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _t = 0;
  Size _size = Size.zero;

  final List<_Turret> _turrets = [];
  final List<_Enemy> _enemies = [];
  final List<_Proj> _projs = [];
  final List<_Part> _parts = [];
  final List<_Ring> _rings = [];
  final _rnd = math.Random(11);
  double _spawnT = 0;
  double _baseFlash = 0;
  int _killed = 0;
  bool _laidOut = false;

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

  void _layout(Size s) {
    _size = s;
    _turrets.clear();
    final n = widget.turrets.length;
    if (n == 0) return;
    final y = s.height * 0.82;
    final margin = s.width * 0.12;
    for (var i = 0; i < n; i++) {
      final x = n == 1
          ? s.width / 2
          : margin + (s.width - 2 * margin) * (i / (n - 1));
      // léger arc
      final dy = -math.sin((i / math.max(1, n - 1)) * math.pi) * s.height * 0.05;
      _turrets.add(_Turret(widget.turrets[i], Offset(x, y + dy)));
    }
    _laidOut = true;
  }

  Offset get _base => Offset(_size.width / 2, _size.height * 0.92);

  void _tick(Duration e) {
    final dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (dt <= 0 || dt > 0.08) {
      setState(() {});
      return;
    }
    _t += dt;
    if (!_laidOut || _size == Size.zero) {
      setState(() {});
      return;
    }

    // spawn
    _spawnT -= dt;
    if (_spawnT <= 0 && _enemies.length < 16) {
      _spawnT = 0.55 + _rnd.nextDouble() * 0.5;
      final x = _size.width * (0.1 + 0.8 * _rnd.nextDouble());
      final hp = 2 + _rnd.nextInt(3).toDouble();
      const palette = [
        Color(0xFFFF4D6D),
        Color(0xFFFF7A2B),
        Color(0xFFB14DFF),
        Color(0xFFFF3DDA),
      ];
      _enemies.add(_Enemy(
        Offset(x, -30),
        Offset((_rnd.nextDouble() - 0.5) * 14, 34 + _rnd.nextDouble() * 26),
        hp,
        palette[_rnd.nextInt(palette.length)],
        15 + hp * 2,
      ));
    }

    // enemies move
    for (final en in _enemies) {
      en.pos += en.vel * dt;
      en.hit = (en.hit - dt * 3).clamp(0.0, 1.0);
      if (en.pos.dy >= _base.dy - 24) {
        _baseFlash = 1;
        _rings.add(_Ring(_base, const Color(0xFF35E0FF), 80));
        en.hp = 0; // disparaît (pas de game-over : juste du juice)
      }
    }

    // turrets aim + fire
    for (final tu in _turrets) {
      _Enemy? best;
      var bestD = 360.0;
      for (final en in _enemies) {
        if (en.hp <= 0) continue;
        final d = (en.pos - tu.pos).distance;
        if (d < bestD) {
          bestD = d;
          best = en;
        }
      }
      tu.cd -= dt;
      if (best != null) {
        final ta = math.atan2(best.pos.dy - tu.pos.dy, best.pos.dx - tu.pos.dx);
        tu.angle = _lerpAng(tu.angle, ta, math.min(1, dt * 9));
        final rate = 0.9 - tu.spec.charge * 0.5; // chargé → tire plus vite
        if (tu.cd <= 0) {
          tu.cd = rate;
          final tip = tu.pos +
              Offset(math.cos(tu.angle), math.sin(tu.angle)) * 26;
          final dir = (best.pos - tip);
          final v = dir.distance < 1
              ? const Offset(0, -1)
              : dir / dir.distance;
          _projs.add(_Proj(tip, v * 520, tu.spec.color, best));
          _parts.add(_Part(tip, Offset(math.cos(tu.angle), math.sin(tu.angle)) * 40,
              tu.spec.color, 3));
        }
      } else {
        tu.angle = _lerpAng(tu.angle, -math.pi / 2, math.min(1, dt * 3));
      }
    }

    // projectiles
    for (final p in _projs) {
      p.life += dt;
      final tgt = p.target;
      if (tgt != null && tgt.hp > 0) {
        final dir = tgt.pos - p.pos;
        final dist = dir.distance;
        if (dist < tgt.r + 6) {
          tgt.hp -= 1;
          tgt.hit = 1;
          _spark(p.pos, p.color, 5);
          if (tgt.hp <= 0) {
            _killed++;
            _burst(tgt.pos, tgt.color);
            _rings.add(_Ring(tgt.pos, tgt.color, tgt.r * 3.2));
          }
          p.life = 99; // marque pour suppression
          continue;
        }
        // homing léger
        final desired = dir / dist * 520;
        p.vel = Offset.lerp(p.vel, desired, math.min(1, dt * 6))!;
      }
      p.trail.insert(0, p.pos);
      if (p.trail.length > 6) p.trail.removeLast();
      p.pos += p.vel * dt;
    }
    _projs.removeWhere((p) =>
        p.life > 2.5 ||
        p.pos.dy < -40 ||
        p.pos.dx < -40 ||
        p.pos.dx > _size.width + 40);

    _enemies.removeWhere((en) => en.hp <= 0);

    for (final pa in _parts) {
      pa.life += dt * 1.6;
      pa.pos += pa.vel * dt;
      pa.vel = Offset(pa.vel.dx * 0.94, pa.vel.dy * 0.94 + 60 * dt);
    }
    _parts.removeWhere((p) => p.life >= 1);
    for (final r in _rings) {
      r.life += dt * 2.2;
    }
    _rings.removeWhere((r) => r.life >= 1);
    _baseFlash = (_baseFlash - dt * 2).clamp(0.0, 1.0);

    setState(() {});
  }

  void _spark(Offset o, Color c, int n) {
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final sp = 40 + _rnd.nextDouble() * 80;
      _parts.add(_Part(o, Offset(math.cos(a), math.sin(a)) * sp, c, 2.5));
    }
  }

  void _burst(Offset o, Color c) {
    for (var i = 0; i < 14; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final sp = 60 + _rnd.nextDouble() * 160;
      _parts.add(_Part(o, Offset(math.cos(a), math.sin(a)) * sp, c,
          2.5 + _rnd.nextDouble() * 2.5));
    }
  }

  double _lerpAng(double a, double b, double t) {
    var d = (b - a) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return a + d * t;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final s = Size(c.maxWidth, c.maxHeight);
      if (s != _size || !_laidOut) _layout(s);
      return CustomPaint(
        size: s,
        painter: _DefensePainter(
          _turrets,
          _enemies,
          _projs,
          _parts,
          _rings,
          _base,
          _baseFlash,
          _t,
          _killed,
        ),
      );
    });
  }
}

class _DefensePainter extends CustomPainter {
  _DefensePainter(this.turrets, this.enemies, this.projs, this.parts,
      this.rings, this.base, this.baseFlash, this.t, this.killed);
  final List<_Turret> turrets;
  final List<_Enemy> enemies;
  final List<_Proj> projs;
  final List<_Part> parts;
  final List<_Ring> rings;
  final Offset base;
  final double baseFlash;
  final double t;
  final int killed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // fond dark radial
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.6),
          radius: 1.1,
          colors: [Color(0xFF161A2E), Color(0xFF0A0C18), Color(0xFF06070F)],
        ).createShader(rect),
    );
    // grille néon discrète
    final grid = Paint()
      ..color = const Color(0xFF35E0FF).withOpacity(0.05)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // anneaux d'impact
    for (final r in rings) {
      final p = Curves.easeOut.transform(r.life);
      _stroke(canvas, r.pos, r.max * p, r.color.withOpacity((1 - r.life) * 0.9),
          3 * (1 - r.life) + 0.5);
    }

    // base (cœur défendu)
    final bf = 0.5 + baseFlash * 0.5;
    _glow(canvas, base, 60, const Color(0xFF35E0FF).withOpacity(0.25 + baseFlash * 0.4));
    canvas.drawCircle(base, 26,
        Paint()..color = const Color(0xFF0E2940).withOpacity(0.9));
    canvas.drawCircle(
        base, 26, _strokePaint(const Color(0xFF35E0FF).withOpacity(bf), 3));
    _text(canvas, 'AUJOURD\'HUI', base.translate(0, 44),
        const Color(0xFF6FA8C8), 11);

    // particules (sous les entités)
    for (final pa in parts) {
      final op = (1 - pa.life).clamp(0, 1).toDouble();
      canvas.drawCircle(pa.pos, pa.size * op + 0.5,
          Paint()..color = pa.color.withOpacity(op));
    }

    // projectiles + trails
    for (final p in projs) {
      for (var i = 0; i < p.trail.length; i++) {
        final op = (1 - i / p.trail.length) * 0.5;
        canvas.drawCircle(p.trail[i], 3.0 * (1 - i / p.trail.length) + 1,
            Paint()..color = p.color.withOpacity(op));
      }
      _glow(canvas, p.pos, 9, p.color.withOpacity(0.7));
      canvas.drawCircle(p.pos, 3.4, Paint()..color = Colors.white);
    }

    // ennemis
    for (final en in enemies) {
      _glow(canvas, en.pos, en.r * 1.5, en.color.withOpacity(0.45));
      final body = Paint()
        ..shader = RadialGradient(
          colors: [Color.lerp(Colors.white, en.color, 0.5)!, en.color],
        ).createShader(Rect.fromCircle(center: en.pos, radius: en.r));
      canvas.drawCircle(en.pos, en.r, body);
      canvas.drawCircle(en.pos, en.r,
          _strokePaint(Colors.white.withOpacity(0.6 + en.hit * 0.4), 1.5 + en.hit * 2));
      // petits yeux
      canvas.drawCircle(en.pos.translate(-en.r * 0.28, -en.r * 0.1), en.r * 0.12,
          Paint()..color = const Color(0xFF0A0C18));
      canvas.drawCircle(en.pos.translate(en.r * 0.28, -en.r * 0.1), en.r * 0.12,
          Paint()..color = const Color(0xFF0A0C18));
      if (en.hit > 0) {
        canvas.drawCircle(en.pos, en.r,
            Paint()..color = Colors.white.withOpacity(en.hit * 0.5));
      }
    }

    // tourelles
    for (final tu in turrets) {
      final c = tu.spec.color;
      _glow(canvas, tu.pos, 34, c.withOpacity(0.35 + tu.spec.charge * 0.25));
      // canon
      canvas.save();
      canvas.translate(tu.pos.dx, tu.pos.dy);
      canvas.rotate(tu.angle);
      final barrel = RRect.fromRectAndRadius(
          Rect.fromLTWH(0, -5, 30, 10), const Radius.circular(5));
      canvas.drawRRect(barrel, Paint()..color = c);
      canvas.drawRRect(barrel, _strokePaint(Colors.white.withOpacity(0.5), 1));
      canvas.restore();
      // socle
      canvas.drawCircle(tu.pos, 18, Paint()..color = const Color(0xFF111630));
      canvas.drawCircle(tu.pos, 18, _strokePaint(c, 2.5));
      canvas.drawCircle(tu.pos, 7, Paint()..color = c);
      // jauge de charge
      final ch = tu.spec.charge.clamp(0.0, 1.0);
      canvas.drawArc(Rect.fromCircle(center: tu.pos, radius: 23), -math.pi / 2,
          math.pi * 2 * ch, false, _strokePaint(c.withOpacity(0.9), 2.5));
      _text(canvas, tu.spec.label, tu.pos.translate(0, 34),
          c.withOpacity(0.9), 11);
    }

    // HUD
    _text(canvas, '⚡ $killed neutralisés', Offset(size.width / 2, 40),
        const Color(0xFF8FE9FF), 15, weight: FontWeight.w800);
  }

  void _glow(Canvas c, Offset o, double r, Color col) {
    c.drawCircle(
        o,
        r,
        Paint()
          ..color = col
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
  }

  void _stroke(Canvas c, Offset o, double r, Color col, double w) {
    c.drawCircle(o, r, _strokePaint(col, w));
  }

  Paint _strokePaint(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..color = c;

  void _text(Canvas c, String s, Offset at, Color color, double size,
      {FontWeight weight = FontWeight.w600}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(color: color, fontSize: size, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DefensePainter old) => true;
}

// ── Écran démo (tourelles néon simulées) ────────────────────────────────────
class DefenseScreen extends StatelessWidget {
  const DefenseScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const turrets = [
      TurretSpec(Color(0xFF35E0FF), 1.0, 'Sport'),
      TurretSpec(Color(0xFFB6FF3C), 0.7, 'Travail'),
      TurretSpec(Color(0xFFFF8A2B), 0.5, 'Lecture'),
      TurretSpec(Color(0xFFA86BFF), 0.85, 'Méditation'),
      TurretSpec(Color(0xFFFF3DDA), 0.6, 'Projet'),
    ];
    return const Scaffold(
      backgroundColor: Color(0xFF06070F),
      body: DefenseView(turrets: turrets),
    );
  }
}
