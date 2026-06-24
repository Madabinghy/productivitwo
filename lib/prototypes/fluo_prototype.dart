// Prototype « Fluo Adventure — navigation » : les 3 échelles reliées par la fusée.
//
//   🌌 COSMOS   planètes = domaines de vie. 🚀 → entrer dans un domaine.
//   🏠 MAP      1 map / domaine ; pièces = activités. 🚀 (case Entrée) → cosmos.
//               chaque pièce a un terminal ⌗ cliquable → la grille.
//   ⌗  GRILLE   un niveau : amène le jeton au but → débloque un item. 🚀 → map.
//
// Démontre l'assemblage / la navigation (zoom out/in via la fusée). Look fluo,
// dessiné en code. Standalone (sans données ni login). Accès : ?proto=fluo

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

void main() => runApp(const FluoNavApp());

class FluoNavApp extends StatelessWidget {
  const FluoNavApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: FluoNavScreen(),
      );
}

enum _View { cosmos, map, grid }

class _Planet {
  const _Planet(this.frac, this.r, this.color, this.name, this.activities);
  final Offset frac;
  final double r;
  final Color color;
  final String name;
  final List<String> activities;
}

class _Room {
  const _Room(this.frac, this.label, {this.corridor = false, this.entry = false});
  final Rect frac;
  final String label;
  final bool corridor;
  final bool entry;
}

class FluoNavScreen extends StatefulWidget {
  const FluoNavScreen({super.key});
  @override
  State<FluoNavScreen> createState() => _FluoNavScreenState();
}

class _FluoNavScreenState extends State<FluoNavScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _t = 0;
  Size _size = Size.zero;
  bool _setup = false;
  final math.Random _rng = math.Random(11);

  _View _view = _View.cosmos;
  double _trans = 1.0; // 1 = posé, monte de 0→1 à chaque changement de vue
  int _domain = 0; // domaine sélectionné
  int _activity = 0; // activité (pièce) sélectionnée
  int _itemsUnlocked = 0;
  String? _flash;
  double _flashT = 0;

  static const _planets = <_Planet>[
    _Planet(Offset(0.28, 0.40), 38, Color(0xFF5BD0A0), 'Santé',
        ['Course', 'Muscu', 'Sommeil', 'Repas', 'Étirement']),
    _Planet(Offset(0.66, 0.32), 46, Color(0xFF35E0FF), 'Travail',
        ['Focus', 'Réunions', 'Mails', 'Projets', 'Veille']),
    _Planet(Offset(0.40, 0.68), 34, Color(0xFFFF5A8A), 'Perso',
        ['Lecture', 'Musique', 'Amis', 'Jeux', 'Sorties']),
    _Planet(Offset(0.74, 0.70), 40, Color(0xFFA86BFF), 'Esprit',
        ['Médit.', 'Journal', 'Respire', 'Gratitude', 'Pause']),
  ];

  // pièces : [0]=couloir, [1]=Entrée (launchpad), [2..6]=activités
  static const _rooms = <_Room>[
    _Room(Rect.fromLTWH(0.05, 0.46, 0.86, 0.10), '', corridor: true),
    _Room(Rect.fromLTWH(0.05, 0.38, 0.15, 0.26), 'Entrée', entry: true),
    _Room(Rect.fromLTWH(0.22, 0.13, 0.18, 0.39), ''),
    _Room(Rect.fromLTWH(0.50, 0.15, 0.16, 0.37), ''),
    _Room(Rect.fromLTWH(0.70, 0.12, 0.21, 0.40), ''),
    _Room(Rect.fromLTWH(0.26, 0.50, 0.22, 0.36), ''),
    _Room(Rect.fromLTWH(0.66, 0.50, 0.20, 0.34), ''),
  ];

  late List<Rect> _px;
  late List<Offset> _planetPx;

  // héros (vue map)
  Offset _hero = Offset.zero;
  Offset _target = Offset.zero;
  static const double _heroR = 13;
  static const double _speed = 240;
  static const double _heroLight = 130;

  // grille (vue grid)
  static const int _gN = 5;
  late List<List<bool>> _blocked;
  Point<int> _tok = const Point(0, 2);
  Point<int> _goal = const Point(4, 2);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _genGrid();
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
    _planetPx = _planets
        .map((p) => Offset(p.frac.dx * s.width, p.frac.dy * s.height))
        .toList();
    _hero = _px[1].center;
    _target = _hero;
    _setup = true;
  }

  void _genGrid() {
    _blocked =
        List.generate(_gN, (_) => List.generate(_gN, (_) => false));
    _tok = const Point(0, 2);
    _goal = Point(_gN - 1, _rng.nextInt(_gN));
    // quelques cases bloquées (jamais sur départ/arrivée)
    var placed = 0;
    while (placed < 5) {
      final x = _rng.nextInt(_gN), y = _rng.nextInt(_gN);
      final p = Point(x, y);
      if (p == _tok || p == _goal || _blocked[y][x]) continue;
      _blocked[y][x] = true;
      placed++;
    }
  }

  void _go(_View v) {
    setState(() {
      _view = v;
      _trans = 0;
    });
  }

  void _moveTok(int dx, int dy) {
    final nx = _tok.x + dx, ny = _tok.y + dy;
    if (nx < 0 || ny < 0 || nx >= _gN || ny >= _gN) return;
    if (_blocked[ny][nx]) return;
    setState(() => _tok = Point(nx, ny));
    if (_tok == _goal) {
      _itemsUnlocked++;
      _flash = 'Item débloqué ! ✦ (${_planets[_domain].activities[_activity]})';
      _flashT = 2.4;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(_genGrid);
      });
    }
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
    if (_trans < 1) _trans = (_trans + dt * 2.4).clamp(0.0, 1.0);

    if (_view == _View.map) {
      final to = _target - _hero;
      final dist = to.distance;
      if (dist > 1) {
        final dir = to / dist;
        final step = dir * math.min(_speed * dt, dist);
        if (_walkable(_hero + step)) {
          _hero += step;
        } else if (_walkable(_hero + Offset(step.dx, 0))) {
          _hero += Offset(step.dx, 0);
        } else if (_walkable(_hero + Offset(0, step.dy))) {
          _hero += Offset(0, step.dy);
        } else {
          _target = _hero;
        }
      }
    }
    setState(() {});
  }

  void _onTapCanvas(Offset p) {
    if (_trans < 0.6) return;
    switch (_view) {
      case _View.cosmos:
        for (var i = 0; i < _planetPx.length; i++) {
          if ((_planetPx[i] - p).distance <= _planets[i].r + 16) {
            _domain = i;
            _go(_View.map);
            return;
          }
        }
        break;
      case _View.map:
        // fusée sur la case Entrée → cosmos
        final rocket = _px[1].topCenter.translate(0, 30);
        if ((rocket - p).distance < 28) {
          _go(_View.cosmos);
          return;
        }
        // terminal d'une pièce-activité → grille
        for (var i = 2; i < _px.length; i++) {
          final term = _px[i].center.translate(0, 26);
          if ((term - p).distance < 24) {
            _activity = i - 2;
            _genGrid();
            _go(_View.grid);
            return;
          }
        }
        // sinon : déplacer le héros
        if (_walkable(p)) {
          _target = p;
        } else {
          Offset? best;
          double bd = double.infinity;
          for (final r in _px) {
            final c = Offset(p.dx.clamp(r.left + _heroR, r.right - _heroR),
                p.dy.clamp(r.top + _heroR, r.bottom - _heroR));
            final d = (c - p).distance;
            if (d < bd) {
              bd = d;
              best = c;
            }
          }
          if (best != null) _target = best;
        }
        break;
      case _View.grid:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070F),
      body: LayoutBuilder(builder: (context, c) {
        final s = Size(c.maxWidth, c.maxHeight);
        if (!_setup || s != _size) _build(s);
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTapDown: (d) => _onTapCanvas(d.localPosition),
              child: CustomPaint(size: s, painter: _NavPainter(this)),
            ),
          ),
          // bouton retour fusée (sauf cosmos)
          if (_view != _View.cosmos)
            Positioned(
              left: 14,
              top: 14,
              child: _rocketBtn(() => _go(_view == _View.grid ? _View.map : _View.cosmos)),
            ),
          // pad directionnel (grille)
          if (_view == _View.grid)
            Positioned(
              right: 18,
              bottom: 18,
              child: _dpad(),
            ),
        ]);
      }),
    );
  }

  Widget _rocketBtn(VoidCallback onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF35E0FF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF35E0FF).withOpacity(0.8)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('🚀', style: TextStyle(fontSize: 16)),
              SizedBox(width: 6),
              Text('Retour',
                  style: TextStyle(
                      color: Color(0xFF35E0FF),
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ]),
          ),
        ),
      );

  Widget _dpad() {
    Widget btn(IconData ic, int dx, int dy) => Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _moveTok(dx, dy),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFB6FF3C).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFB6FF3C).withOpacity(0.7)),
              ),
              child: Icon(ic, color: const Color(0xFFB6FF3C), size: 24),
            ),
          ),
        );
    const gap = SizedBox(width: 6, height: 6);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.keyboard_arrow_up, 0, -1),
      gap,
      Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.keyboard_arrow_left, -1, 0),
        const SizedBox(width: 52),
        btn(Icons.keyboard_arrow_right, 1, 0),
      ]),
      gap,
      btn(Icons.keyboard_arrow_down, 0, 1),
    ]);
  }
}

class _NavPainter extends CustomPainter {
  _NavPainter(this.g);
  final _FluoNavScreenState g;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ease = Curves.easeOut.transform(g._trans);
    // transition : fade + léger zoom
    canvas.saveLayer(rect, Paint()..color = Colors.white.withOpacity(ease));
    final sc = 1.06 - 0.06 * ease;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(sc);
    canvas.translate(-size.width / 2, -size.height / 2);

    switch (g._view) {
      case _View.cosmos:
        _paintCosmos(canvas, size);
        break;
      case _View.map:
        _paintMap(canvas, size);
        break;
      case _View.grid:
        _paintGrid(canvas, size);
        break;
    }
    canvas.restore();
    canvas.restore();

    _paintFlash(canvas, size);
  }

  // ── COSMOS ────────────────────────────────────────────────────────────────
  void _paintCosmos(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [Color(0xFF231C52), Color(0xFF120F35), Color(0xFF07061A)],
          ).createShader(rect));
    final rnd = math.Random(3);
    for (var i = 0; i < 80; i++) {
      final x = rnd.nextDouble() * size.width, y = rnd.nextDouble() * size.height;
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(g._t * 1.5 + i));
      canvas.drawCircle(Offset(x, y), rnd.nextDouble() * 1.4 + 0.4,
          Paint()..color = Colors.white.withOpacity(0.5 * tw));
    }
    for (var i = 0; i < g._planetPx.length; i++) {
      final p = g._planetPx[i];
      final pl = _FluoNavScreenState._planets[i];
      final pulse = 1 + 0.03 * math.sin(g._t * 2 + i);
      _glow(canvas, p, pl.r * 1.7, pl.color.withOpacity(0.35));
      canvas.drawCircle(
          p,
          pl.r * pulse,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.4, -0.4),
              colors: [Colors.white.withOpacity(0.9), pl.color, pl.color],
              stops: const [0.0, 0.4, 1.0],
            ).createShader(Rect.fromCircle(center: p, radius: pl.r)));
      // anneau
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(-0.4);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: pl.r * 3, height: pl.r),
          _stroke(pl.color.withOpacity(0.5), 2));
      canvas.restore();
      _text(canvas, pl.name, p.translate(0, pl.r + 18), Colors.white, 15,
          weight: FontWeight.w800);
      // mini-fusée d'invite
      _text(canvas, '🚀', p.translate(pl.r * 0.7, -pl.r * 0.7), Colors.white, 16);
    }
    _text(canvas, 'COSMOS', Offset(size.width / 2, 30),
        const Color(0xFFB6FF3C), 22, weight: FontWeight.w900);
    _text(canvas, 'Tes domaines de vie · touche une planète pour y voyager 🚀',
        Offset(size.width / 2, 54), const Color(0xFF8FA0C8), 12);
    _text(canvas, 'Items débloqués : ${g._itemsUnlocked}',
        Offset(size.width / 2, size.height - 24), const Color(0xFFFFD36B), 12,
        weight: FontWeight.w700);
  }

  // ── MAP ─────────────────────────────────────────────────────────────────
  void _paintMap(Canvas canvas, Size size) {
    final dom = _FluoNavScreenState._planets[g._domain];
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF05070F));
    for (var i = 0; i < _FluoNavScreenState._rooms.length; i++) {
      _drawRoom(canvas, g._px[i], _FluoNavScreenState._rooms[i], dom, i);
    }
    // voile + lumière du héros
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0A0C16).withOpacity(0.55));
    _punch(canvas, g._hero, _FluoNavScreenState._heroLight);
    canvas.restore();

    // fusée de la case Entrée → cosmos
    final rocket = g._px[1].topCenter.translate(0, 30);
    _glow(canvas, rocket, 18, const Color(0xFF35E0FF).withOpacity(0.5));
    canvas.drawCircle(rocket, 15, Paint()..color = const Color(0xFF0B1422));
    canvas.drawCircle(rocket, 15, _stroke(const Color(0xFF35E0FF), 1.8));
    _text(canvas, '🚀', rocket, Colors.white, 16);
    _text(canvas, 'Décoller', rocket.translate(0, 26),
        const Color(0xFF7FD0C0), 10);

    _drawHero(canvas, g._hero, dom.color);

    _text(canvas, dom.name.toUpperCase(), Offset(size.width / 2, 28),
        dom.color, 22, weight: FontWeight.w900);
    _text(canvas, 'Map du domaine · les pièces sont tes activités',
        Offset(size.width / 2, 52), const Color(0xFF8FA0C8), 12);
    _text(canvas, 'Touche un terminal ⌗ d\'activité pour entrer dans son niveau',
        Offset(size.width / 2, size.height - 24),
        const Color(0xFF8FA0C8), 12);
  }

  void _drawRoom(Canvas canvas, Rect px, _Room r, _Planet dom, int idx) {
    final rr = RRect.fromRectAndRadius(px, const Radius.circular(6));
    canvas.drawRRect(rr, Paint()..color = const Color(0xFF0B1422));
    canvas.drawRRect(rr, Paint()..color = dom.color.withOpacity(r.corridor ? 0.05 : 0.12));
    if (!r.corridor) {
      _glow(canvas, px.center, math.min(px.width, px.height) * 0.5,
          dom.color.withOpacity(0.14));
    }
    canvas.drawRRect(
        rr, _stroke(dom.color.withOpacity(r.corridor ? 0.4 : 0.85), r.corridor ? 1.5 : 2.5));
    if (r.entry) {
      _text(canvas, 'Entrée', Offset(px.center.dx, px.top + 16),
          Colors.white.withOpacity(0.9), 13, weight: FontWeight.w700);
    } else if (!r.corridor) {
      final name = dom.activities[idx - 2];
      _text(canvas, name, Offset(px.center.dx, px.top + 16),
          Colors.white.withOpacity(0.9), 13, weight: FontWeight.w700);
      // terminal cliquable
      final term = px.center.translate(0, 26);
      final pulse = 0.6 + 0.4 * math.sin(g._t * 3 + idx);
      _glow(canvas, term, 14 * pulse, const Color(0xFFFFD36B).withOpacity(0.5));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: term, width: 22, height: 22),
              const Radius.circular(4)),
          Paint()..color = const Color(0xFF0B1422));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: term, width: 22, height: 22),
              const Radius.circular(4)),
          _stroke(const Color(0xFFFFD36B), 1.6));
      _text(canvas, '⌗', term, const Color(0xFFFFD36B), 15, weight: FontWeight.w900);
    }
  }

  // ── GRILLE ───────────────────────────────────────────────────────────────
  void _paintGrid(Canvas canvas, Size size) {
    final dom = _FluoNavScreenState._planets[g._domain];
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -0.1),
            radius: 1.1,
            colors: [Color(0xFF141034), Color(0xFF07061A)],
          ).createShader(rect));
    final n = _FluoNavScreenState._gN;
    final cell = math.min(size.width, size.height) * 0.62 / n;
    final gw = cell * n;
    final ox = (size.width - gw) / 2, oy = (size.height - gw) / 2 + 14;
    // cases
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final cr = Rect.fromLTWH(ox + x * cell, oy + y * cell, cell - 4, cell - 4);
        final rr = RRect.fromRectAndRadius(cr, const Radius.circular(6));
        final blocked = g._blocked[y][x];
        canvas.drawRRect(
            rr,
            Paint()
              ..color = blocked
                  ? const Color(0xFF15171F)
                  : const Color(0xFF101A2B));
        canvas.drawRRect(rr,
            _stroke(dom.color.withOpacity(blocked ? 0.12 : 0.3), 1.2));
      }
    }
    // but
    final goalC = Offset(ox + g._goal.x * cell + (cell - 4) / 2,
        oy + g._goal.y * cell + (cell - 4) / 2);
    final gp = 0.6 + 0.4 * math.sin(g._t * 4);
    _glow(canvas, goalC, 22 * gp, const Color(0xFFFFD36B).withOpacity(0.6));
    _text(canvas, '✦', goalC, const Color(0xFFFFD36B), 24, weight: FontWeight.w900);
    // jeton
    final tokC = Offset(ox + g._tok.x * cell + (cell - 4) / 2,
        oy + g._tok.y * cell + (cell - 4) / 2);
    _drawHero(canvas, tokC, const Color(0xFFB6FF3C));

    _text(canvas, 'NIVEAU · ${dom.activities[g._activity]}',
        Offset(size.width / 2, 30), const Color(0xFFB6FF3C), 20,
        weight: FontWeight.w900);
    _text(canvas, 'Amène le héros jusqu\'au ✦ pour débloquer un item',
        Offset(size.width / 2, 54), const Color(0xFF8FA0C8), 12);
    _text(canvas, 'Flèches → · murs sombres bloquent',
        Offset(size.width / 2, size.height - 24), const Color(0xFF8FA0C8), 12);
  }

  void _paintFlash(Canvas canvas, Size size) {
    if (g._flashT <= 0 || g._flash == null) return;
    final a = (g._flashT / 2.4).clamp(0.0, 1.0);
    final box = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.18),
        width: 360,
        height: 42);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)),
        Paint()..color = const Color(0xFF0B1422).withOpacity(0.92 * a));
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)),
        _stroke(const Color(0xFFFFD36B).withOpacity(a), 1.5));
    _text(canvas, g._flash!, box.center,
        const Color(0xFFFFE08A).withOpacity(a), 14, weight: FontWeight.w800);
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  void _punch(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = RadialGradient(
            colors: const [Colors.white, Colors.white, Color(0x00FFFFFF)],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)));
  }

  void _drawHero(Canvas canvas, Offset p, Color c) {
    _glow(canvas, p, 22, c.withOpacity(0.5));
    canvas.drawLine(p.translate(0, -11), p.translate(0, -19), _stroke(c, 2.4));
    canvas.drawCircle(p.translate(0, -20), 2.4, Paint()..color = Colors.white);
    canvas.drawCircle(
        p,
        12,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: [Colors.white, c],
          ).createShader(Rect.fromCircle(center: p, radius: 12)));
    canvas.drawCircle(p, 12, _stroke(Colors.white.withOpacity(0.6), 1.4));
    canvas.drawCircle(p.translate(-4, -2), 2.6, Paint()..color = Colors.white);
    canvas.drawCircle(p.translate(4, -2), 2.6, Paint()..color = Colors.white);
    canvas.drawCircle(
        p.translate(-3.6, -2), 1.3, Paint()..color = const Color(0xFF12211F));
    canvas.drawCircle(
        p.translate(4.4, -2), 1.3, Paint()..color = const Color(0xFF12211F));
    final smile = Path()
      ..moveTo(p.dx - 4, p.dy + 4)
      ..quadraticBezierTo(p.dx, p.dy + 8, p.dx + 4, p.dy + 4);
    canvas.drawPath(smile, _stroke(const Color(0xFF12211F), 1.8));
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
  bool shouldRepaint(covariant _NavPainter old) => true;
}

class Point<T extends num> {
  const Point(this.x, this.y);
  final T x, y;
  @override
  bool operator ==(Object o) => o is Point && o.x == x && o.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}
