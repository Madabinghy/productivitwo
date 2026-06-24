// Prototype « Overworld fluo » — carte-monde + héros déplaçable (dessiné en code).
//
// La brique qui relie l'univers : une carte de nœuds néon (combats ⚔ tourelles,
// planètes 🪐 à faire croître, trésors ◆) qu'on explore avec un petit héros fluo
// déplaçable de nœud en nœud (tap-to-move). On progresse « de plus en plus loin ».
// Standalone (sans données ni login). Accès : ?proto=world

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

void main() => runApp(const OverworldProtoApp());

class OverworldProtoApp extends StatelessWidget {
  const OverworldProtoApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OverworldScreen(),
      );
}

enum NodeKind { start, combat, planet, treasure, boss }

class _Node {
  _Node(this.frac, this.kind, this.links);
  final Offset frac; // position en fractions de l'écran
  final NodeKind kind;
  final List<int> links;
  Offset pos = Offset.zero;
  bool visited = false;
  bool unlocked = false;
  double pulse = 0;
}

class OverworldScreen extends StatefulWidget {
  const OverworldScreen({super.key});
  @override
  State<OverworldScreen> createState() => _OverworldScreenState();
}

class _OverworldScreenState extends State<OverworldScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _t = 0;
  Size _size = Size.zero;
  bool _setup = false;

  final List<_Star> _stars = _genStars(70);

  // Carte (du bas = départ, vers le haut = boss). links = arêtes.
  final List<_Node> _nodes = [
    _Node(const Offset(0.50, 0.90), NodeKind.start, [1, 2]),
    _Node(const Offset(0.34, 0.79), NodeKind.combat, [3]),
    _Node(const Offset(0.66, 0.77), NodeKind.planet, [3, 4]),
    _Node(const Offset(0.50, 0.66), NodeKind.combat, [5, 6]),
    _Node(const Offset(0.78, 0.62), NodeKind.treasure, [6]),
    _Node(const Offset(0.30, 0.54), NodeKind.planet, [7]),
    _Node(const Offset(0.58, 0.50), NodeKind.combat, [7, 8]),
    _Node(const Offset(0.42, 0.38), NodeKind.treasure, [9]),
    _Node(const Offset(0.70, 0.34), NodeKind.combat, [9]),
    _Node(const Offset(0.50, 0.20), NodeKind.boss, []),
  ];

  int _current = 0;
  // héros
  Offset _heroPos = Offset.zero;
  int? _movingTo;
  double _moveT = 0;
  final List<Offset> _trail = [];
  int _level = 1;

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

  void _build(Size s) {
    _size = s;
    for (final n in _nodes) {
      n.pos = Offset(n.frac.dx * s.width, n.frac.dy * s.height);
    }
    _nodes[0].visited = true;
    _nodes[0].unlocked = true;
    for (final l in _nodes[0].links) {
      _nodes[l].unlocked = true;
    }
    _heroPos = _nodes[0].pos.translate(0, -26);
    _setup = true;
  }

  void _tick(Duration e) {
    final dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (!_setup || dt <= 0 || dt > 0.08) {
      setState(() {});
      return;
    }
    _t += dt;
    for (final n in _nodes) {
      n.pulse += dt;
    }
    // déplacement du héros
    final mt = _movingTo;
    if (mt != null) {
      _moveT = (_moveT + dt * 1.7).clamp(0.0, 1.0);
      final from = _nodes[_current].pos.translate(0, -26);
      final to = _nodes[mt].pos.translate(0, -26);
      _heroPos = Offset.lerp(from, to, Curves.easeInOut.transform(_moveT))!;
      _trail.insert(0, _heroPos);
      if (_trail.length > 10) _trail.removeLast();
      if (_moveT >= 1) {
        _current = mt;
        _movingTo = null;
        final n = _nodes[mt];
        n.visited = true;
        for (final l in n.links) {
          _nodes[l].unlocked = true;
        }
        _level++;
      }
    } else {
      // bob léger
      final base = _nodes[_current].pos.translate(0, -26);
      _heroPos = base.translate(0, math.sin(_t * 2.2) * 2);
      if (_trail.isNotEmpty) _trail.removeLast();
    }
    setState(() {});
  }

  void _onTap(Offset p) {
    if (_movingTo != null) return;
    final cur = _nodes[_current];
    // cherche un nœud RELIÉ au courant, débloqué, proche du tap
    for (var i = 0; i < _nodes.length; i++) {
      final n = _nodes[i];
      final linked = cur.links.contains(i) || n.links.contains(_current);
      if (!linked || !n.unlocked) continue;
      if ((n.pos - p).distance <= 30) {
        _movingTo = i;
        _moveT = 0;
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07061A),
      body: LayoutBuilder(builder: (context, c) {
        final s = Size(c.maxWidth, c.maxHeight);
        if (!_setup || s != _size) _build(s);
        return GestureDetector(
          onTapUp: (d) => _onTap(d.localPosition),
          child: CustomPaint(size: s, painter: _OverworldPainter(this)),
        );
      }),
    );
  }
}

class _OverworldPainter extends CustomPainter {
  _OverworldPainter(this.g);
  final _OverworldScreenState g;

  static const _kindColor = {
    NodeKind.start: Color(0xFF7DFFCE),
    NodeKind.combat: Color(0xFFFF3DDA),
    NodeKind.planet: Color(0xFFA86BFF),
    NodeKind.treasure: Color(0xFFFFD36B),
    NodeKind.boss: Color(0xFFFF4D5E),
  };
  static const _kindIcon = {
    NodeKind.start: '⌂',
    NodeKind.combat: '⚔',
    NodeKind.planet: '🪐',
    NodeKind.treasure: '◆',
    NodeKind.boss: '☠',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.2,
          colors: [Color(0xFF231C52), Color(0xFF120F35), Color(0xFF07061A)],
        ).createShader(rect),
    );
    // nébuleuses
    _neb(canvas, Offset(size.width * 0.75, size.height * 0.25),
        size.width * 0.6, const Color(0xFF6C4FD6), 0.18);
    _neb(canvas, Offset(size.width * 0.2, size.height * 0.7),
        size.width * 0.5, const Color(0xFF3FA8D6), 0.13);
    for (final st in g._stars) {
      final tw =
          0.4 + 0.6 * (0.5 + 0.5 * math.sin(g._t * st.speed + st.phase));
      canvas.drawCircle(Offset(st.x * size.width, st.y * size.height), st.r,
          Paint()..color = Colors.white.withOpacity(0.5 * tw));
    }

    // arêtes
    for (var i = 0; i < g._nodes.length; i++) {
      final n = g._nodes[i];
      for (final l in n.links) {
        final m = g._nodes[l];
        final live = n.visited || m.visited || (n.unlocked && m.unlocked);
        canvas.drawLine(
            n.pos,
            m.pos,
            Paint()
              ..strokeWidth = live ? 3 : 1.5
              ..color = (live
                      ? const Color(0xFF8FE9FF)
                      : const Color(0xFF3A4570))
                  .withOpacity(live ? 0.5 : 0.25));
      }
    }

    // nœuds
    for (var i = 0; i < g._nodes.length; i++) {
      final n = g._nodes[i];
      final c = _kindColor[n.kind]!;
      final reachable = !n.visited &&
          n.unlocked &&
          (g._nodes[g._current].links.contains(i) ||
              n.links.contains(g._current)) &&
          g._movingTo == null;
      final op = n.unlocked ? 1.0 : 0.4;
      _glow(canvas, n.pos, 24, c.withOpacity((n.unlocked ? 0.45 : 0.15)));
      if (reachable) {
        final pr = 18 + (0.5 + 0.5 * math.sin(n.pulse * 4)) * 8;
        canvas.drawCircle(n.pos, pr, _stroke(c.withOpacity(0.7), 2));
      }
      canvas.drawCircle(n.pos, 18,
          Paint()..color = const Color(0xFF120F30).withOpacity(op));
      canvas.drawCircle(n.pos, 18, _stroke(c.withOpacity(op), 2.5));
      if (n.visited) {
        canvas.drawCircle(n.pos, 18,
            Paint()..color = c.withOpacity(0.18));
      }
      _text(canvas, _kindIcon[n.kind]!, n.pos, c.withOpacity(op), 16);
    }

    // traînée du héros
    for (var i = 0; i < g._trail.length; i++) {
      final o = (1 - i / g._trail.length) * 0.4;
      canvas.drawCircle(g._trail[i], 4.0 * (1 - i / g._trail.length) + 1,
          Paint()..color = const Color(0xFFB6FF3C).withOpacity(o));
    }

    // héros fluo
    _drawHero(canvas, g._heroPos);

    // HUD
    _text(canvas, '✦ Niveau ${g._level}', Offset(size.width / 2, 40),
        const Color(0xFFB6FF3C), 16, weight: FontWeight.w800);
    if (g._movingTo == null) {
      _text(canvas, 'Touche un nœud relié et brillant pour t\'y rendre',
          Offset(size.width / 2, size.height - 36),
          const Color(0xFF8FA0C8), 13);
    }
  }

  void _drawHero(Canvas canvas, Offset p) {
    const c = Color(0xFFB6FF3C);
    _glow(canvas, p, 26, c.withOpacity(0.5));
    // antenne
    canvas.drawLine(p.translate(0, -14), p.translate(0, -24), _stroke(c, 2.5));
    _glow(canvas, p.translate(0, -25), 6, c.withOpacity(0.8));
    canvas.drawCircle(p.translate(0, -25), 3, Paint()..color = Colors.white);
    // corps
    canvas.drawCircle(
        p,
        15,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.4),
            colors: [Color(0xFFE8FFC0), c],
          ).createShader(Rect.fromCircle(center: p, radius: 15)));
    canvas.drawCircle(p, 15, _stroke(Colors.white.withOpacity(0.6), 1.5));
    // yeux
    canvas.drawCircle(p.translate(-5, -2), 3.4, Paint()..color = Colors.white);
    canvas.drawCircle(p.translate(5, -2), 3.4, Paint()..color = Colors.white);
    canvas.drawCircle(
        p.translate(-4.5, -2), 1.7, Paint()..color = const Color(0xFF12211F));
    canvas.drawCircle(
        p.translate(5.5, -2), 1.7, Paint()..color = const Color(0xFF12211F));
    // sourire
    final smile = Path()
      ..moveTo(p.dx - 5, p.dy + 5)
      ..quadraticBezierTo(p.dx, p.dy + 9, p.dx + 5, p.dy + 5);
    canvas.drawPath(smile, _stroke(const Color(0xFF12211F), 2));
  }

  void _neb(Canvas c, Offset o, double r, Color col, double op) {
    c.drawCircle(
        o,
        r,
        Paint()
          ..shader =
              RadialGradient(colors: [col.withOpacity(op), col.withOpacity(0)])
                  .createShader(Rect.fromCircle(center: o, radius: r)));
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
  bool shouldRepaint(covariant _OverworldPainter old) => true;
}

class _Star {
  _Star(this.x, this.y, this.r, this.phase, this.speed);
  final double x, y, r, phase, speed;
}

List<_Star> _genStars(int n) {
  final rnd = math.Random(9);
  return List.generate(
      n,
      (_) => _Star(rnd.nextDouble(), rnd.nextDouble(), 0.6 + rnd.nextDouble() * 1.6,
          rnd.nextDouble() * math.pi * 2, 0.6 + rnd.nextDouble() * 1.6));
}
