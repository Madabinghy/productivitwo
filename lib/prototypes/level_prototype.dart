// Prototype « Carte de niveau » — un niveau Fluo Adventure explorable (dessiné en code).
//
// Un niveau = une carte d'une planète. Vue top-down néon. La map démarre **dans le
// noir** (ambiance inquiétante : on devine des choses tapies dans l'ombre). On
// explore LIBREMENT (tap-to-move) et on **récolte des Lumens** (orbes lumineuses)
// laissés par ton activité réelle. On dépense les Lumens en **lumière + couleur** :
// la map sort de l'ombre et devient de plus en plus GAIE (plancher de luminosité
// qui monte, couleurs qui saturent, lucioles, plantes qui fleurissent…).
//   • court terme  → + de lumière
//   • moyen terme  → des items à poser (à venir)
//   • long terme   → + d'espace (à venir)
// Le noir ne bloque jamais l'accès : c'est l'antagoniste d'ambiance, pas un mur.
// Standalone (sans données ni login). Accès : ?proto=level

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

void main() => runApp(const LevelProtoApp());

class LevelProtoApp extends StatelessWidget {
  const LevelProtoApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: LevelScreen(),
      );
}

// Une pièce (ou un couloir) walkable, définie en fractions de l'écran.
class _Room {
  const _Room(this.frac, this.color, this.label, {this.corridor = false});
  final Rect frac; // x,y,w,h en fractions
  final Color color;
  final String label;
  final bool corridor;
}

enum DecorKind { crate, plant, lamp, barrel, rug, table }

class _Decor {
  const _Decor(this.frac, this.kind);
  final Offset frac;
  final DecorKind kind;
}

class _Firefly {
  _Firefly(this.bx, this.by, this.phase, this.speed, this.color);
  final double bx, by, phase, speed;
  final Color color;
}

class LevelScreen extends StatefulWidget {
  const LevelScreen({super.key});
  @override
  State<LevelScreen> createState() => _LevelScreenState();
}

class _LevelScreenState extends State<LevelScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _t = 0;
  Size _size = Size.zero;
  bool _setup = false;
  final math.Random _rng = math.Random(7);

  // Couloir-épine (spine) horizontal + pièces qui le chevauchent → union connexe.
  static const _rooms = <_Room>[
    _Room(Rect.fromLTWH(0.05, 0.46, 0.86, 0.10), Color(0xFF35E0FF), '',
        corridor: true),
    _Room(Rect.fromLTWH(0.05, 0.38, 0.15, 0.26), Color(0xFF7DFFCE), 'Entrée'),
    _Room(Rect.fromLTWH(0.22, 0.13, 0.18, 0.39), Color(0xFFFF3DDA), 'Cuisine'),
    _Room(Rect.fromLTWH(0.50, 0.15, 0.16, 0.37), Color(0xFF35E0FF), 'Stockage'),
    _Room(Rect.fromLTWH(0.70, 0.12, 0.21, 0.40), Color(0xFF5BD0A0), 'Dortoirs'),
    _Room(Rect.fromLTWH(0.26, 0.50, 0.22, 0.36), Color(0xFFFF5A8A), 'Salon'),
    _Room(Rect.fromLTWH(0.66, 0.50, 0.20, 0.34), Color(0xFFFFB35A), 'Atelier'),
  ];

  static const _decor = <_Decor>[
    _Decor(Offset(0.35, 0.42), DecorKind.table),
    _Decor(Offset(0.26, 0.40), DecorKind.crate),
    _Decor(Offset(0.54, 0.44), DecorKind.barrel),
    _Decor(Offset(0.62, 0.30), DecorKind.crate),
    _Decor(Offset(0.74, 0.40), DecorKind.lamp),
    _Decor(Offset(0.86, 0.42), DecorKind.plant),
    _Decor(Offset(0.31, 0.78), DecorKind.rug),
    _Decor(Offset(0.44, 0.66), DecorKind.plant),
    _Decor(Offset(0.70, 0.74), DecorKind.barrel),
    _Decor(Offset(0.82, 0.60), DecorKind.crate),
    _Decor(Offset(0.10, 0.44), DecorKind.lamp),
  ];

  // Yeux qui rôdent dans le noir (ambiance) — fractions ; se retirent quand la
  // map s'éclaire.
  static const _eyes = <Offset>[
    Offset(0.30, 0.30),
    Offset(0.58, 0.30),
    Offset(0.80, 0.28),
    Offset(0.36, 0.70),
    Offset(0.78, 0.66),
  ];

  // rects / points en pixels (calculés au build)
  late List<Rect> _px;
  late List<Offset> _decorPx;
  late List<Offset> _eyesPx;
  final List<_Firefly> _flies = [];

  // héros + exploration
  Offset _hero = Offset.zero;
  Offset _target = Offset.zero;
  final List<Offset> _trail = [];
  static const double _heroR = 13;
  static const double _speed = 240; // px/s
  static const double _heroLight = 120;

  // économie
  int _lumens = 40;
  double _lux = 0.0; // 0 = noir inquiétant, 1 = lumineux joyeux
  static const int _lightCost = 20;
  static const double _luxStep = 0.10;

  // orbes de lumens à récolter
  final List<Offset> _orbs = [];
  static const int _orbCount = 5;

  String? _flash;
  double _flashT = 0;

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

  Rect _toPx(Rect f, Size s) => Rect.fromLTWH(
      f.left * s.width, f.top * s.height, f.width * s.width, f.height * s.height);

  Offset _randWalkable() {
    // un point au hasard dans une pièce (hors couloir), un peu en retrait des murs
    for (var tries = 0; tries < 40; tries++) {
      final i = 1 + _rng.nextInt(_rooms.length - 1);
      final r = _px[i].deflate(24);
      if (r.width <= 0 || r.height <= 0) continue;
      final p = Offset(r.left + _rng.nextDouble() * r.width,
          r.top + _rng.nextDouble() * r.height);
      if ((p - _hero).distance > 60) return p;
    }
    return _px[2].center;
  }

  void _build(Size s) {
    _size = s;
    _px = _rooms.map((r) => _toPx(r.frac, s)).toList();
    _decorPx = _decor
        .map((d) => Offset(d.frac.dx * s.width, d.frac.dy * s.height))
        .toList();
    _eyesPx =
        _eyes.map((e) => Offset(e.dx * s.width, e.dy * s.height)).toList();
    _hero = _px[1].center;
    _target = _hero;
    _flies.clear();
    const warm = [
      Color(0xFFFFE08A),
      Color(0xFFB6FF3C),
      Color(0xFFFF9EC4),
      Color(0xFF8FE9FF),
    ];
    for (var i = 0; i < 30; i++) {
      _flies.add(_Firefly(
          _rng.nextDouble(),
          0.12 + _rng.nextDouble() * 0.76,
          _rng.nextDouble() * math.pi * 2,
          0.4 + _rng.nextDouble() * 0.9,
          warm[i % warm.length]));
    }
    _orbs.clear();
    for (var i = 0; i < _orbCount; i++) {
      _orbs.add(_randWalkable());
    }
    _setup = true;
  }

  bool _walkable(Offset p) {
    for (final r in _px) {
      if (r.inflate(-_heroR * 0.4).contains(p)) return true;
    }
    return false;
  }

  void _earnSession() {
    setState(() {
      _lumens += 30;
      _flash = '+30 lm — session loggée';
      _flashT = 2.0;
    });
  }

  void _spendLight() {
    if (_lumens < _lightCost || _lux >= 1.0) {
      setState(() {
        _flash = _lux >= 1.0 ? 'Niveau au maximum de lumière ✨' : 'Pas assez de Lumens';
        _flashT = 1.6;
      });
      return;
    }
    setState(() {
      _lumens -= _lightCost;
      _lux = (_lux + _luxStep).clamp(0.0, 1.0);
      _flash = '+ Lumière · ${(_lux * 100).round()} %';
      _flashT = 1.6;
    });
  }

  void _tick(Duration e) {
    final dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (!_setup || dt <= 0 || dt > 0.08) {
      setState(() {});
      return;
    }
    _t += dt;
    if (_flashT > 0) _flashT -= dt;

    final to = _target - _hero;
    final dist = to.distance;
    if (dist > 1) {
      final dir = to / dist;
      final stepLen = math.min(_speed * dt, dist);
      final step = dir * stepLen;
      if (_walkable(_hero + step)) {
        _hero += step;
      } else if (_walkable(_hero + Offset(step.dx, 0))) {
        _hero += Offset(step.dx, 0);
      } else if (_walkable(_hero + Offset(0, step.dy))) {
        _hero += Offset(0, step.dy);
      } else {
        _target = _hero;
      }
      _trail.insert(0, _hero);
      if (_trail.length > 12) _trail.removeLast();
    } else if (_trail.isNotEmpty) {
      _trail.removeLast();
    }

    // récolte des orbes de lumens
    for (var i = 0; i < _orbs.length; i++) {
      if ((_orbs[i] - _hero).distance < 24) {
        _lumens += 12;
        _flash = '+12 Lumens récoltés';
        _flashT = 1.6;
        _orbs[i] = _randWalkable();
      }
    }
    setState(() {});
  }

  void _onTap(Offset p) {
    if (_walkable(p)) {
      _target = p;
      return;
    }
    Offset? best;
    double bestD = double.infinity;
    for (final r in _px) {
      final c = Offset(
        p.dx.clamp(r.left + _heroR, r.right - _heroR),
        p.dy.clamp(r.top + _heroR, r.bottom - _heroR),
      );
      final d = (c - p).distance;
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    if (best != null) _target = best;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF04050B),
      body: LayoutBuilder(builder: (context, c) {
        final s = Size(c.maxWidth, c.maxHeight);
        if (!_setup || s != _size) _build(s);
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTapDown: (d) => _onTap(d.localPosition),
              child: CustomPaint(size: s, painter: _LevelPainter(this)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(child: _hud()),
          ),
        ]);
      }),
    );
  }

  Widget _hud() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1422).withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2EF2B0).withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.bolt, color: Color(0xFFFFE08A), size: 18),
        const SizedBox(width: 4),
        SizedBox(
          width: 64,
          child: Text('$_lumens lm',
              style: const TextStyle(
                  color: Color(0xFFFFE08A),
                  fontWeight: FontWeight.w800,
                  fontSize: 14)),
        ),
        const SizedBox(width: 14),
        // jauge de luminosité
        Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Luminosité',
              style: TextStyle(color: Color(0xFF8FA0C8), fontSize: 10)),
          const SizedBox(height: 3),
          Container(
            width: 120,
            height: 7,
            decoration: BoxDecoration(
              color: const Color(0xFF142033),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _lux.clamp(0.02, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFFB35A), Color(0xFFB6FF3C)]),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 16),
        _pill('Session', const Color(0xFF35E0FF), Icons.add, _earnSession),
        const SizedBox(width: 8),
        _pill('Lumière', const Color(0xFFB6FF3C), Icons.light_mode, _spendLight),
      ]),
    );
  }

  Widget _pill(String label, Color c, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withOpacity(0.8)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: c, size: 15),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: c, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  _LevelPainter(this.g);
  final _LevelScreenState g;

  double get lux => g._lux;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // fond : se réchauffe / se colore quand la luminosité monte
    final c0 = Color.lerp(const Color(0xFF0A0E1E), const Color(0xFF2C2350), lux)!;
    final c1 = Color.lerp(const Color(0xFF05070F), const Color(0xFF140C24), lux)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.3,
          colors: [c0, c1, const Color(0xFF04050B)],
          stops: const [0.0, 0.7, 1.0],
        ).createShader(rect),
    );
    if (lux > 0.01) {
      _glow(canvas, Offset(size.width * 0.5, size.height * 0.45),
          size.width * 0.5, const Color(0xFFFF6FB0).withOpacity(0.06 * lux));
      _glow(canvas, Offset(size.width * 0.7, size.height * 0.6),
          size.width * 0.4, const Color(0xFFFFB35A).withOpacity(0.05 * lux));
    }

    // pièces (teinte + murs qui s'intensifient avec lux)
    for (var i = 0; i < _LevelScreenState._rooms.length; i++) {
      _drawRoom(canvas, g._px[i], _LevelScreenState._rooms[i]);
    }
    for (var i = 0; i < g._decorPx.length; i++) {
      _drawDecor(canvas, g._decorPx[i], _LevelScreenState._decor[i].kind);
    }
    // orbes de lumens (petites sources qui scintillent)
    for (var i = 0; i < g._orbs.length; i++) {
      final o = g._orbs[i];
      final p = 0.6 + 0.4 * math.sin(g._t * 4 + i);
      _glow(canvas, o, 14 * p, const Color(0xFFFFE08A).withOpacity(0.6));
      canvas.drawCircle(o, 5.5, Paint()..color = const Color(0xFFFFF3C0));
      canvas.drawCircle(o, 5.5, _stroke(const Color(0xFFFFB35A), 1.4));
      _text(canvas, 'lm', o.translate(0, 0.5),
          const Color(0xFF8A6A2B), 6, weight: FontWeight.w900);
    }

    // yeux qui rôdent dans le noir (s'effacent quand ça s'éclaire)
    final eyeOp = (1 - lux) * (1 - lux);
    if (eyeOp > 0.04) {
      for (var i = 0; i < g._eyesPx.length; i++) {
        final e = g._eyesPx[i];
        final blink = 0.5 + 0.5 * math.sin(g._t * 1.3 + i * 1.7);
        if (blink < 0.25) continue;
        final op = (eyeOp * blink).clamp(0.0, 0.7);
        for (final dx in const [-5.0, 5.0]) {
          canvas.drawCircle(e.translate(dx, 0), 2.4,
              Paint()..color = const Color(0xFFFF4D5E).withOpacity(op));
        }
      }
    }

    // ── voile d'obscurité : son opacité BAISSE quand la luminosité monte ──────
    final veilA = (0.93 * (1 - lux * 0.82)).clamp(0.10, 0.93);
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(
        rect, Paint()..color = const Color(0xFF0A0C16).withOpacity(veilA));
    _punch(canvas, g._hero, _LevelScreenState._heroLight);
    for (final o in g._orbs) {
      _punch(canvas, o, 34);
    }
    canvas.restore();

    // lucioles joyeuses (apparaissent avec la luminosité, AU-DESSUS du voile)
    final n = (g._flies.length * lux);
    for (var i = 0; i < g._flies.length; i++) {
      final f = g._flies[i];
      final op = (n - i).clamp(0.0, 1.0);
      if (op <= 0) continue;
      final x = (f.bx + math.sin(g._t * f.speed + f.phase) * 0.04) * size.width;
      final y = (f.by + math.cos(g._t * f.speed * 0.8 + f.phase) * 0.03) *
          size.height;
      final tw = 0.5 + 0.5 * math.sin(g._t * 3 + f.phase);
      _glow(canvas, Offset(x, y), 6, f.color.withOpacity(0.5 * op * tw));
      canvas.drawCircle(Offset(x, y), 1.8,
          Paint()..color = f.color.withOpacity(op));
    }

    // traînée + marqueur + héros
    for (var i = 0; i < g._trail.length; i++) {
      final o = (1 - i / g._trail.length) * 0.4;
      canvas.drawCircle(g._trail[i], 4.0 * (1 - i / g._trail.length) + 1,
          Paint()..color = const Color(0xFFB6FF3C).withOpacity(o));
    }
    if ((g._target - g._hero).distance > 4) {
      final pr = 6 + (0.5 + 0.5 * math.sin(g._t * 6)) * 4;
      canvas.drawCircle(g._target, pr,
          _stroke(const Color(0xFFB6FF3C).withOpacity(0.6), 1.6));
    }
    _drawHero(canvas, g._hero);

    // ── HUD haut ───────────────────────────────────────────────────────────
    _glow(canvas, Offset(size.width / 2, 30), 60,
        const Color(0xFFFF3DDA).withOpacity(0.18));
    _text(canvas, 'FLUO ADVENTURE', Offset(size.width / 2, 26),
        const Color(0xFFB6FF3C), 22, weight: FontWeight.w900);
    _text(canvas, 'Niveau · Repaire des Contrebandiers',
        Offset(size.width / 2, 50), const Color(0xFF7FD0C0), 12);
    _text(canvas, 'Ambiance : ${_mood()}', Offset(size.width / 2, 72),
        _moodColor(), 13, weight: FontWeight.w700);

    _text(canvas, 'Explore librement · récolte les Lumens · dépense-les en lumière',
        Offset(size.width / 2, size.height - 64),
        const Color(0xFF8FA0C8), 12);

    if (g._flashT > 0 && g._flash != null) {
      final a = (g._flashT / 2.0).clamp(0.0, 1.0);
      final box = Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.16),
          width: 340,
          height: 40);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)),
          Paint()..color = const Color(0xFF0B1422).withOpacity(0.9 * a));
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)),
          _stroke(const Color(0xFFFFB35A).withOpacity(a), 1.5));
      _text(canvas, g._flash!, box.center,
          const Color(0xFFFFE08A).withOpacity(a), 14, weight: FontWeight.w700);
    }
  }

  String _mood() {
    if (lux < 0.15) return 'Inquiétante';
    if (lux < 0.35) return 'Pesante';
    if (lux < 0.55) return 'Calme';
    if (lux < 0.78) return 'Vivante';
    return 'Joyeuse ✨';
  }

  Color _moodColor() => Color.lerp(
      const Color(0xFF7E97A8), const Color(0xFFB6FF3C), lux)!;

  // Perce le voile : retire l'alpha en pool radial doux (BlendMode.dstOut).
  void _punch(Canvas canvas, Offset c, double r) {
    final flicker = 0.96 + 0.04 * math.sin(g._t * 7 + c.dx);
    canvas.drawCircle(
        c,
        r * flicker,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = RadialGradient(
            colors: const [Colors.white, Colors.white, Color(0x00FFFFFF)],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r * flicker)));
  }

  void _drawRoom(Canvas canvas, Rect px, _Room r) {
    final rr = RRect.fromRectAndRadius(px, const Radius.circular(6));
    canvas.drawRRect(rr, Paint()..color = const Color(0xFF0B1422));
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF1A2740).withOpacity(0.5);
    canvas.save();
    canvas.clipRRect(rr);
    const cell = 26.0;
    for (double x = px.left; x < px.right; x += cell) {
      canvas.drawLine(Offset(x, px.top), Offset(x, px.bottom), grid);
    }
    for (double y = px.top; y < px.bottom; y += cell) {
      canvas.drawLine(Offset(px.left, y), Offset(px.right, y), grid);
    }
    final tint = (0.07 + 0.26 * lux) * (r.corridor ? 0.5 : 1.0);
    canvas.drawRRect(rr, Paint()..color = r.color.withOpacity(tint));
    if (!r.corridor) {
      _glow(canvas, px.center, math.min(px.width, px.height) * 0.55,
          r.color.withOpacity(0.10 + 0.18 * lux));
    }
    canvas.restore();
    final wallOp = r.corridor
        ? (0.3 + 0.3 * lux)
        : (0.55 + 0.4 * lux);
    canvas.drawRRect(
        rr, _stroke(r.color.withOpacity(wallOp), r.corridor ? 1.5 : 2.5));
    if (r.label.isNotEmpty) {
      _text(canvas, r.label, Offset(px.center.dx, px.top + 16),
          Colors.white.withOpacity(0.6 + 0.35 * lux), 14,
          weight: FontWeight.w700);
    }
  }

  void _drawDecor(Canvas canvas, Offset p, DecorKind k) {
    switch (k) {
      case DecorKind.crate:
        final r = Rect.fromCenter(center: p, width: 22, height: 22);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
            Paint()..color = const Color(0xFF8A5A2B).withOpacity(0.55));
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
            _stroke(const Color(0xFFC8923C), 1.4));
        canvas.drawLine(r.topLeft, r.bottomRight,
            _stroke(const Color(0xFFC8923C).withOpacity(0.6), 1));
        canvas.drawLine(r.topRight, r.bottomLeft,
            _stroke(const Color(0xFFC8923C).withOpacity(0.6), 1));
        break;
      case DecorKind.barrel:
        canvas.drawCircle(
            p, 11, Paint()..color = const Color(0xFF5BD0A0).withOpacity(0.45));
        canvas.drawCircle(p, 11, _stroke(const Color(0xFF5BD0A0), 1.4));
        canvas.drawCircle(
            p, 5, _stroke(const Color(0xFF5BD0A0).withOpacity(0.7), 1));
        break;
      case DecorKind.plant:
        canvas.drawCircle(p.translate(0, 6), 6,
            Paint()..color = const Color(0xFF3A2A1A).withOpacity(0.7));
        for (final a in [-0.6, 0.0, 0.6]) {
          final tip = p.translate(math.sin(a) * 9, -10 - math.cos(a) * 3);
          canvas.drawLine(p.translate(0, 4), tip,
              _stroke(const Color(0xFFB6FF3C).withOpacity(0.8), 2.2));
        }
        _glow(canvas, p.translate(0, -6), 10,
            const Color(0xFFB6FF3C).withOpacity(0.25));
        // fleurs qui éclosent quand la map est gaie
        if (lux > 0.5) {
          final f = ((lux - 0.5) / 0.5).clamp(0.0, 1.0);
          for (final a in const [-0.6, 0.0, 0.6]) {
            final tip = p.translate(math.sin(a) * 9, -10 - math.cos(a) * 3);
            canvas.drawCircle(tip, 2.4 * f,
                Paint()..color = const Color(0xFFFF9EC4).withOpacity(f));
          }
        }
        break;
      case DecorKind.lamp:
        canvas.drawLine(
            p, p.translate(0, 12), _stroke(const Color(0xFF6A7A90), 2));
        canvas.drawCircle(p, 6, Paint()..color = const Color(0xFFFFE08A));
        _glow(canvas, p, 16 + 8 * lux,
            const Color(0xFFFFE08A).withOpacity(0.3 + 0.4 * lux));
        break;
      case DecorKind.rug:
        final r = Rect.fromCenter(center: p, width: 54, height: 30);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)),
            Paint()..color = const Color(0xFFFF5A8A).withOpacity(0.18));
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)),
            _stroke(const Color(0xFFFF5A8A).withOpacity(0.6), 1.4));
        canvas.drawRRect(
            RRect.fromRectAndRadius(r.deflate(6), const Radius.circular(4)),
            _stroke(const Color(0xFFFFB35A).withOpacity(0.5), 1));
        break;
      case DecorKind.table:
        final r = Rect.fromCenter(center: p, width: 40, height: 24);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
            Paint()..color = const Color(0xFFA86BFF).withOpacity(0.4));
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
            _stroke(const Color(0xFFA86BFF), 1.4));
        break;
    }
  }

  void _drawHero(Canvas canvas, Offset p) {
    const c = Color(0xFFB6FF3C);
    _glow(canvas, p, 24, c.withOpacity(0.5));
    canvas.drawLine(p.translate(0, -12), p.translate(0, -21), _stroke(c, 2.5));
    _glow(canvas, p.translate(0, -22), 5, c.withOpacity(0.8));
    canvas.drawCircle(p.translate(0, -22), 2.6, Paint()..color = Colors.white);
    canvas.drawCircle(
        p,
        13,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.4),
            colors: [Color(0xFFE8FFC0), c],
          ).createShader(Rect.fromCircle(center: p, radius: 13)));
    canvas.drawCircle(p, 13, _stroke(Colors.white.withOpacity(0.6), 1.5));
    // joues qui rosissent quand c'est joyeux
    if (lux > 0.5) {
      final f = ((lux - 0.5) / 0.5).clamp(0.0, 1.0);
      canvas.drawCircle(p.translate(-8, 3), 2.6,
          Paint()..color = const Color(0xFFFF9EC4).withOpacity(0.5 * f));
      canvas.drawCircle(p.translate(8, 3), 2.6,
          Paint()..color = const Color(0xFFFF9EC4).withOpacity(0.5 * f));
    }
    canvas.drawCircle(p.translate(-4.5, -2), 3, Paint()..color = Colors.white);
    canvas.drawCircle(p.translate(4.5, -2), 3, Paint()..color = Colors.white);
    canvas.drawCircle(
        p.translate(-4, -2), 1.5, Paint()..color = const Color(0xFF12211F));
    canvas.drawCircle(
        p.translate(5, -2), 1.5, Paint()..color = const Color(0xFF12211F));
    // sourire : plus la map est gaie, plus il sourit
    final sm = 2.0 + 6.0 * lux;
    final smile = Path()
      ..moveTo(p.dx - 4.5, p.dy + 4)
      ..quadraticBezierTo(p.dx, p.dy + 4 + sm, p.dx + 4.5, p.dy + 4);
    canvas.drawPath(smile, _stroke(const Color(0xFF12211F), 2));
  }

  void _glow(Canvas c, Offset o, double r, Color col) {
    c.drawCircle(
        o,
        r,
        Paint()
          ..color = col
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
  }

  Paint _stroke(Color c, double w) => Paint()
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
  bool shouldRepaint(covariant _LevelPainter old) => true;
}
