// Prototype « Carte de niveau » — un niveau Fluo Adventure explorable (dessiné en code).
//
// Un niveau = une carte d'une planète. Vue top-down néon, **plongée dans le noir** :
// le héros fluo porte une petite lumière, on explore les pièces en tâtonnant pour
// trouver des TORCHES. Allumer une torche éclaire durablement la zone autour.
// But : rallumer tout le niveau. Des objets décoratifs (caisses, plantes, tapis…)
// rendent les pièces jolies une fois révélées.
// On itérera dessus (évolution de la carte, combats, loot…).
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

  // Torches à allumer (gameplay). Réparties dans les pièces.
  static const _torches = <Offset>[
    Offset(0.31, 0.20),
    Offset(0.58, 0.22),
    Offset(0.80, 0.20),
    Offset(0.37, 0.72),
    Offset(0.76, 0.66),
    Offset(0.12, 0.50),
  ];

  // Décor (révélé quand éclairé) — rend les pièces jolies.
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

  // rects / points en pixels (calculés au build)
  late List<Rect> _px;
  late List<Offset> _torchPx;
  late List<Offset> _decorPx;

  // héros
  Offset _hero = Offset.zero;
  Offset _target = Offset.zero;
  final List<Offset> _trail = [];
  static const double _heroR = 13;
  static const double _speed = 240; // px/s
  static const double _heroLight = 120; // rayon de lumière du héros
  static const double _torchLight = 165; // rayon d'une torche allumée

  // torches allumées
  final Set<int> _lit = {};
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

  void _build(Size s) {
    _size = s;
    _px = _rooms.map((r) => _toPx(r.frac, s)).toList();
    _torchPx =
        _torches.map((p) => Offset(p.dx * s.width, p.dy * s.height)).toList();
    _decorPx =
        _decor.map((d) => Offset(d.frac.dx * s.width, d.frac.dy * s.height)).toList();
    _hero = _px[1].center;
    _target = _hero;
    _setup = true;
  }

  bool _walkable(Offset p) {
    for (final r in _px) {
      if (r.inflate(-_heroR * 0.4).contains(p)) return true;
    }
    return false;
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

    // allumage des torches proches
    for (var i = 0; i < _torchPx.length; i++) {
      if (_lit.contains(i)) continue;
      if ((_torchPx[i] - _hero).distance < 30) {
        _lit.add(i);
        _flash = _lit.length == _torches.length
            ? 'Niveau entièrement éclairé ! ✨'
            : 'Torche allumée — ${_lit.length}/${_torches.length}';
        _flashT = 2.2;
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
        return GestureDetector(
          onTapDown: (d) => _onTap(d.localPosition),
          child: CustomPaint(size: s, painter: _LevelPainter(this)),
        );
      }),
    );
  }
}

class _LevelPainter extends CustomPainter {
  _LevelPainter(this.g);
  final _LevelScreenState g;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF04050B));

    // ── 1. La carte (pièces, décor, torches) dessinée en clair ────────────────
    for (var i = 0; i < _LevelScreenState._rooms.length; i++) {
      _drawRoom(canvas, g._px[i], _LevelScreenState._rooms[i]);
    }
    for (var i = 0; i < g._decorPx.length; i++) {
      _drawDecor(canvas, g._decorPx[i], _LevelScreenState._decor[i].kind);
    }
    for (var i = 0; i < g._torchPx.length; i++) {
      _drawTorch(canvas, g._torchPx[i], g._lit.contains(i), i);
    }

    // ── 2. Voile d'obscurité, percé par les lumières (héros + torches) ────────
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = const Color(0xF20A0C16));
    _punch(canvas, g._hero, _LevelScreenState._heroLight);
    for (final i in g._lit) {
      _punch(canvas, g._torchPx[i], _LevelScreenState._torchLight);
    }
    canvas.restore();

    // halo chaleureux additif au-dessus du voile, sur les torches allumées
    for (final i in g._lit) {
      _glow(canvas, g._torchPx[i], _LevelScreenState._torchLight * 0.5,
          const Color(0xFFFFB35A).withOpacity(0.10));
    }

    // ── 3. Traînée + marqueur + héros (toujours nets, au-dessus du voile) ─────
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

    // ── 4. HUD ────────────────────────────────────────────────────────────────
    _glow(canvas, Offset(size.width / 2, 30), 60,
        const Color(0xFFFF3DDA).withOpacity(0.18));
    _text(canvas, 'FLUO ADVENTURE', Offset(size.width / 2, 26),
        const Color(0xFFB6FF3C), 22, weight: FontWeight.w900);
    _text(canvas, 'Niveau · Repaire des Contrebandiers',
        Offset(size.width / 2, 50), const Color(0xFF7FD0C0), 12);
    final allLit = g._lit.length == _LevelScreenState._torches.length;
    _text(
        canvas,
        allLit
            ? '✨ Niveau éclairé'
            : '🔦 Torches : ${g._lit.length}/${_LevelScreenState._torches.length}',
        Offset(size.width / 2, size.height - 50),
        allLit ? const Color(0xFFB6FF3C) : const Color(0xFFFFB35A),
        13,
        weight: FontWeight.w700);
    _text(canvas, 'Explore dans le noir — trouve les torches pour éclairer',
        Offset(size.width / 2, size.height - 28),
        const Color(0xFF8FA0C8), 12);

    if (g._flashT > 0 && g._flash != null) {
      final a = (g._flashT / 2.2).clamp(0.0, 1.0);
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
    canvas.drawRRect(rr,
        Paint()..color = r.color.withOpacity(r.corridor ? 0.06 : 0.12));
    if (!r.corridor) {
      _glow(canvas, px.center, math.min(px.width, px.height) * 0.55,
          r.color.withOpacity(0.18));
    }
    canvas.restore();
    canvas.drawRRect(
        rr,
        _stroke(r.color.withOpacity(r.corridor ? 0.4 : 0.85),
            r.corridor ? 1.5 : 2.5));
    if (r.label.isNotEmpty) {
      _text(canvas, r.label, Offset(px.center.dx, px.top + 16),
          Colors.white.withOpacity(0.92), 14, weight: FontWeight.w700);
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
        canvas.drawCircle(p, 5, _stroke(const Color(0xFF5BD0A0).withOpacity(0.7), 1));
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
        break;
      case DecorKind.lamp:
        canvas.drawLine(p, p.translate(0, 12), _stroke(const Color(0xFF6A7A90), 2));
        canvas.drawCircle(p, 6, Paint()..color = const Color(0xFFFFE08A));
        _glow(canvas, p, 16, const Color(0xFFFFE08A).withOpacity(0.4));
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

  void _drawTorch(Canvas canvas, Offset p, bool lit, int i) {
    // socle
    canvas.drawLine(p.translate(0, 2), p.translate(0, 13),
        _stroke(const Color(0xFF6A5A40), 2.4));
    if (lit) {
      final f = 0.8 + 0.2 * math.sin(g._t * 9 + i);
      _glow(canvas, p.translate(0, -4), 18 * f, const Color(0xFFFFB35A));
      final flame = Path()
        ..moveTo(p.dx - 5, p.dy)
        ..quadraticBezierTo(p.dx - 4, p.dy - 12 * f, p.dx, p.dy - 16 * f)
        ..quadraticBezierTo(p.dx + 4, p.dy - 12 * f, p.dx + 5, p.dy)
        ..close();
      canvas.drawPath(flame, Paint()..color = const Color(0xFFFF8A2B));
      canvas.drawPath(
          Path()
            ..moveTo(p.dx - 2.5, p.dy - 1)
            ..quadraticBezierTo(p.dx, p.dy - 9 * f, p.dx + 2.5, p.dy - 1)
            ..close(),
          Paint()..color = const Color(0xFFFFE08A));
    } else {
      // torche éteinte : pastille sombre, visible seulement quand la lumière passe
      canvas.drawCircle(p.translate(0, -3), 5,
          Paint()..color = const Color(0xFF2A2230));
      canvas.drawCircle(
          p.translate(0, -3), 5, _stroke(const Color(0xFFFFB35A).withOpacity(0.5), 1.4));
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
    canvas.drawCircle(p.translate(-4.5, -2), 3, Paint()..color = Colors.white);
    canvas.drawCircle(p.translate(4.5, -2), 3, Paint()..color = Colors.white);
    canvas.drawCircle(
        p.translate(-4, -2), 1.5, Paint()..color = const Color(0xFF12211F));
    canvas.drawCircle(
        p.translate(5, -2), 1.5, Paint()..color = const Color(0xFF12211F));
    final smile = Path()
      ..moveTo(p.dx - 4.5, p.dy + 4)
      ..quadraticBezierTo(p.dx, p.dy + 8, p.dx + 4.5, p.dy + 4);
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
