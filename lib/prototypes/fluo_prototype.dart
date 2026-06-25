// Prototype « Fluo Adventure — navigation » : les 3 échelles reliées par la fusée.
//
//   🌌 COSMOS    planètes = domaines de vie. 🚀 → entrer dans un domaine.
//   🏠 MAP       1 map / domaine ; pièces = activités. 🚀 (case Entrée) → cosmos.
//                chaque pièce a un terminal ⌗ cliquable → la carte à nœuds.
//   🗺 NODE-MAP  la « grille » à nœuds, INFINIE : on monte de nœud en nœud
//                (combat ⚔ / trésor ◆ / planète 🪐 / boss ☠), de plus en plus
//                loin ; trésors & boss débloquent un item. 🚀 → map.
//
// Données : FluoNavScreen accepte une liste de FluoDomain (vrais domaines +
// activités). Sans données → jeu de démo. lib/web/fluo_data_screen.dart le
// branche sur AppState (?proto=fluo, après auth).
// Dessiné en code. Accès démo standalone : ?proto=fluo (sans données).

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

// ── Données injectables (vrais domaines / activités) ────────────────────────
class FluoDomain {
  const FluoDomain(
      {required this.name,
      required this.color,
      required this.activities,
      this.mass = 0.6});
  final String name;
  final Color color;
  final List<String> activities; // noms des activités du domaine
  final double mass; // 0..1 → taille de la planète (temps, réf. p90)
}

const _demoDoms = <FluoDomain>[
  FluoDomain(
      name: 'Santé',
      color: Color(0xFF5BD0A0),
      mass: 1.0,
      activities: ['Course', 'Muscu', 'Sommeil', 'Repas', 'Étirement']),
  FluoDomain(
      name: 'Travail',
      color: Color(0xFF35E0FF),
      mass: 0.8,
      activities: ['Focus', 'Réunions', 'Mails', 'Projets', 'Veille']),
  FluoDomain(
      name: 'Perso',
      color: Color(0xFFFF5A8A),
      mass: 0.45,
      activities: ['Lecture', 'Musique', 'Amis', 'Jeux', 'Sorties']),
  FluoDomain(
      name: 'Esprit',
      color: Color(0xFFA86BFF),
      mass: 0.6,
      activities: ['Médit.', 'Journal', 'Respire', 'Gratitude', 'Pause']),
];

enum _View { cosmos, map, run }

enum NodeKind { start, combat, treasure, planet, boss }

class _Room {
  const _Room(this.frac, this.label, {this.corridor = false, this.entry = false});
  final Rect frac;
  final String label;
  final bool corridor;
  final bool entry;
}

class _MNode {
  _MNode(this.row, this.xFrac, this.kind);
  final int row;
  final double xFrac;
  final NodeKind kind;
  final List<int> links = [];
  bool visited = false;
  bool unlocked = false;
  double worldY = 0;
  double pulse = 0;
}

class FluoNavScreen extends StatefulWidget {
  const FluoNavScreen({super.key, this.data});
  final List<FluoDomain>? data; // null → démo
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

  late final List<FluoDomain> _doms;

  _View _view = _View.cosmos;
  double _trans = 1.0;
  int _domain = 0;
  int _activity = 0;
  int _itemsUnlocked = 0;
  String? _flash;
  double _flashT = 0;

  // jusqu'à 5 pièces-activités (indices 2..6) + Entrée (1) + couloir (0)
  static const _rooms = <_Room>[
    _Room(Rect.fromLTWH(0.05, 0.46, 0.86, 0.10), '', corridor: true),
    _Room(Rect.fromLTWH(0.05, 0.38, 0.15, 0.26), 'Entrée', entry: true),
    _Room(Rect.fromLTWH(0.22, 0.13, 0.18, 0.39), ''),
    _Room(Rect.fromLTWH(0.50, 0.15, 0.16, 0.37), ''),
    _Room(Rect.fromLTWH(0.70, 0.12, 0.21, 0.40), ''),
    _Room(Rect.fromLTWH(0.26, 0.50, 0.22, 0.36), ''),
    _Room(Rect.fromLTWH(0.66, 0.50, 0.20, 0.34), ''),
  ];
  static const int _maxActivityRooms = 5;

  late List<Rect> _px;
  late List<Offset> _planetPx;
  late List<double> _planetR;

  // héros (vue map)
  Offset _hero = Offset.zero;
  Offset _target = Offset.zero;
  static const double _heroR = 13;
  static const double _speed = 240;
  static const double _heroLight = 130;

  // node-map (vue run) — carte infinie
  static const double _rowGap = 120;
  final List<_MNode> _nodes = [];
  int _rowCount = 0;
  int _cur = 0;
  int? _movingTo;
  double _moveT = 0;
  double _camY = 0;
  Offset _heroW = Offset.zero;
  int _depth = 0;
  math.Random _runRng = math.Random(1);

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _doms = (d == null || d.isEmpty) ? _demoDoms : d;
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  int _activityCount(int domain) =>
      math.min(_maxActivityRooms, _doms[domain].activities.length);

  // une pièce est-elle active pour le domaine courant ?
  bool _roomActive(int i) {
    if (i < 2) return true; // couloir + Entrée
    return (i - 2) < _activityCount(_domain);
  }

  Rect _toPx(Rect f, Size s) => Rect.fromLTWH(
      f.left * s.width, f.top * s.height, f.width * s.width, f.height * s.height);

  void _build(Size s) {
    _size = s;
    _px = _rooms.map((r) => _toPx(r.frac, s)).toList();
    // planètes : anneau autour du centre, taille selon le nb d'activités
    final n = _doms.length;
    final cx = s.width * 0.5, cy = s.height * 0.46;
    final rx = s.width * 0.30, ry = s.height * 0.30;
    _planetPx = [];
    _planetR = [];
    for (var i = 0; i < n; i++) {
      if (n == 1) {
        _planetPx.add(Offset(cx, cy));
      } else {
        final ang = -math.pi / 2 + i * 2 * math.pi / n;
        _planetPx.add(Offset(cx + math.cos(ang) * rx, cy + math.sin(ang) * ry));
      }
      // taille = temps (mass, réf. p90 comme les heatmaps) ; plancher visible
      _planetR.add(18 + _doms[i].mass.clamp(0.0, 1.0) * 30);
    }
    _hero = _px[1].center;
    _target = _hero;
    _setup = true;
  }

  // ── node-map ────────────────────────────────────────────────────────────
  NodeKind _pickKind() {
    final r = _runRng.nextDouble();
    if (r < 0.5) return NodeKind.combat;
    if (r < 0.8) return NodeKind.treasure;
    return NodeKind.planet;
  }

  void _genRow() {
    final r = _rowCount;
    final newIdx = <int>[];
    if (r == 0) {
      _nodes.add(_MNode(0, 0.5, NodeKind.start)..worldY = 0);
      newIdx.add(_nodes.length - 1);
    } else {
      final two = _runRng.nextDouble() < 0.5;
      final xs = two
          ? [0.26 + _runRng.nextDouble() * 0.12, 0.60 + _runRng.nextDouble() * 0.12]
          : [0.36 + _runRng.nextDouble() * 0.28];
      for (final x in xs) {
        final kind = (r % 6 == 0) ? NodeKind.boss : _pickKind();
        _nodes.add(_MNode(r, x, kind)..worldY = -r * _rowGap);
        newIdx.add(_nodes.length - 1);
      }
      final prev = <int>[];
      for (var i = 0; i < _nodes.length; i++) {
        if (_nodes[i].row == r - 1) prev.add(i);
      }
      for (final ni in newIdx) {
        prev.sort((a, b) => (_nodes[a].xFrac - _nodes[ni].xFrac)
            .abs()
            .compareTo((_nodes[b].xFrac - _nodes[ni].xFrac).abs()));
        _nodes[prev.first].links.add(ni);
      }
      for (final pi in prev) {
        if (!_nodes[pi].links.any((l) => _nodes[l].row == r)) {
          newIdx.sort((a, b) => (_nodes[a].xFrac - _nodes[pi].xFrac)
              .abs()
              .compareTo((_nodes[b].xFrac - _nodes[pi].xFrac).abs()));
          _nodes[pi].links.add(newIdx.first);
        }
      }
    }
    _rowCount++;
  }

  void _initRun() {
    _runRng = math.Random(_domain * 97 + _activity * 31 + 7);
    _nodes.clear();
    _rowCount = 0;
    for (var i = 0; i < 8; i++) {
      _genRow();
    }
    _nodes[0].visited = true;
    _nodes[0].unlocked = true;
    for (final l in _nodes[0].links) {
      _nodes[l].unlocked = true;
    }
    _cur = 0;
    _movingTo = null;
    _moveT = 0;
    _camY = 0;
    _depth = 0;
    _heroW = Offset(0.5 * _size.width, 0);
  }

  Offset _nodeWorld(int i) =>
      Offset(_nodes[i].xFrac * _size.width, _nodes[i].worldY);

  Offset _project(Offset world) =>
      Offset(world.dx, _size.height * 0.62 + (world.dy - _camY));

  String get _curActivity {
    final acts = _doms[_domain].activities;
    return _activity < acts.length ? acts[_activity] : 'Activité';
  }

  void _arrive(int i) {
    final n = _nodes[i];
    n.visited = true;
    _cur = i;
    _depth = math.max(_depth, n.row);
    for (final l in n.links) {
      _nodes[l].unlocked = true;
    }
    switch (n.kind) {
      case NodeKind.treasure:
        _itemsUnlocked++;
        _flash = 'Item débloqué ◆ ($_curActivity)';
        _flashT = 2.2;
        break;
      case NodeKind.boss:
        _itemsUnlocked++;
        _flash = 'Boss vaincu ☠ — item rare débloqué !';
        _flashT = 2.4;
        break;
      case NodeKind.combat:
        _flash = 'Combat ⚔ (tower-defense à venir)';
        _flashT = 1.6;
        break;
      case NodeKind.planet:
        _flash = 'Planète 🪐 — domaine nourri';
        _flashT = 1.6;
        break;
      case NodeKind.start:
        break;
    }
    while (_rowCount < n.row + 6) {
      _genRow();
    }
  }

  void _go(_View v) {
    setState(() {
      _view = v;
      _trans = 0;
    });
  }

  bool _walkable(Offset p) {
    for (var i = 0; i < _px.length; i++) {
      if (!_roomActive(i)) continue;
      if (_px[i].inflate(-_heroR * 0.4).contains(p)) return true;
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
    } else if (_view == _View.run && _nodes.isNotEmpty) {
      for (final n in _nodes) {
        n.pulse += dt;
      }
      _camY += (_nodes[_cur].worldY - _camY) * math.min(1.0, dt * 4);
      final mt = _movingTo;
      if (mt != null) {
        _moveT = (_moveT + dt * 1.8).clamp(0.0, 1.0);
        _heroW = Offset.lerp(_nodeWorld(_cur), _nodeWorld(mt),
            Curves.easeInOut.transform(_moveT))!;
        if (_moveT >= 1) {
          _arrive(mt);
          _movingTo = null;
        }
      } else {
        _heroW = _nodeWorld(_cur).translate(0, math.sin(_t * 2.2) * 2);
      }
    }
    setState(() {});
  }

  void _onTapCanvas(Offset p) {
    if (_trans < 0.6) return;
    switch (_view) {
      case _View.cosmos:
        for (var i = 0; i < _planetPx.length; i++) {
          if ((_planetPx[i] - p).distance <= _planetR[i] + 16) {
            _domain = i;
            _go(_View.map);
            return;
          }
        }
        break;
      case _View.map:
        final rocket = _px[1].topCenter.translate(0, 30);
        if ((rocket - p).distance < 28) {
          _go(_View.cosmos);
          return;
        }
        for (var i = 2; i < _px.length; i++) {
          if (!_roomActive(i)) continue;
          final term = _px[i].center.translate(0, 26);
          if ((term - p).distance < 24) {
            _activity = i - 2;
            _initRun();
            _go(_View.run);
            return;
          }
        }
        if (_walkable(p)) {
          _target = p;
        } else {
          Offset? best;
          double bd = double.infinity;
          for (var i = 0; i < _px.length; i++) {
            if (!_roomActive(i)) continue;
            final r = _px[i];
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
      case _View.run:
        if (_movingTo != null) return;
        for (var i = 0; i < _nodes.length; i++) {
          final n = _nodes[i];
          if (!n.unlocked || n.visited) continue;
          if (!_nodes[_cur].links.contains(i)) continue;
          if ((_project(_nodeWorld(i)) - p).distance <= 28) {
            _movingTo = i;
            _moveT = 0;
            return;
          }
        }
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
          if (_view != _View.cosmos)
            Positioned(
              left: 14,
              top: 14,
              child: _rocketBtn(
                  () => _go(_view == _View.run ? _View.map : _View.cosmos)),
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
}

class _NavPainter extends CustomPainter {
  _NavPainter(this.g);
  final _FluoNavScreenState g;

  static const _kindColor = {
    NodeKind.start: Color(0xFF7DFFCE),
    NodeKind.combat: Color(0xFFFF3DDA),
    NodeKind.treasure: Color(0xFFFFD36B),
    NodeKind.planet: Color(0xFFA86BFF),
    NodeKind.boss: Color(0xFFFF4D5E),
  };
  static const _kindIcon = {
    NodeKind.start: '⌂',
    NodeKind.combat: '⚔',
    NodeKind.treasure: '◆',
    NodeKind.planet: '🪐',
    NodeKind.boss: '☠',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ease = Curves.easeOut.transform(g._trans);
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
      case _View.run:
        _paintRun(canvas, size);
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
      final pr = g._planetR[i];
      final dom = g._doms[i];
      final pulse = 1 + 0.03 * math.sin(g._t * 2 + i);
      _glow(canvas, p, pr * 1.7, dom.color.withOpacity(0.35));
      canvas.drawCircle(
          p,
          pr * pulse,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.4, -0.4),
              colors: [Colors.white.withOpacity(0.9), dom.color, dom.color],
              stops: const [0.0, 0.4, 1.0],
            ).createShader(Rect.fromCircle(center: p, radius: pr)));
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(-0.4);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: pr * 3, height: pr),
          _stroke(dom.color.withOpacity(0.5), 2));
      canvas.restore();
      _text(canvas, dom.name, p.translate(0, pr + 18), Colors.white, 15,
          weight: FontWeight.w800);
      _text(canvas, '${dom.activities.length} act.', p.translate(0, pr + 36),
          Colors.white.withOpacity(0.45), 11);
      _text(canvas, '🚀', p.translate(pr * 0.7, -pr * 0.7), Colors.white, 16);
    }
    _text(canvas, 'COSMOS', Offset(size.width / 2, 30), const Color(0xFFB6FF3C),
        22, weight: FontWeight.w900);
    _text(canvas, 'Tes domaines de vie · touche une planète pour y voyager 🚀',
        Offset(size.width / 2, 54), const Color(0xFF8FA0C8), 12);
    _text(canvas, 'Items débloqués : ${g._itemsUnlocked}',
        Offset(size.width / 2, size.height - 24), const Color(0xFFFFD36B), 12,
        weight: FontWeight.w700);
  }

  // ── MAP ───────────────────────────────────────────────────────────────────
  void _paintMap(Canvas canvas, Size size) {
    final dom = g._doms[g._domain];
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF05070F));
    for (var i = 0; i < _FluoNavScreenState._rooms.length; i++) {
      if (!g._roomActive(i)) continue;
      _drawRoom(canvas, g._px[i], _FluoNavScreenState._rooms[i], dom, i);
    }
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0A0C16).withOpacity(0.55));
    _punch(canvas, g._hero, _FluoNavScreenState._heroLight);
    canvas.restore();

    final rocket = g._px[1].topCenter.translate(0, 30);
    _glow(canvas, rocket, 18, const Color(0xFF35E0FF).withOpacity(0.5));
    canvas.drawCircle(rocket, 15, Paint()..color = const Color(0xFF0B1422));
    canvas.drawCircle(rocket, 15, _stroke(const Color(0xFF35E0FF), 1.8));
    _text(canvas, '🚀', rocket, Colors.white, 16);
    _text(canvas, 'Décoller', rocket.translate(0, 26), const Color(0xFF7FD0C0), 10);

    _drawHero(canvas, g._hero, dom.color);

    _text(canvas, dom.name.toUpperCase(), Offset(size.width / 2, 28), dom.color,
        22, weight: FontWeight.w900);
    _text(canvas, 'Map du domaine · les pièces sont tes activités',
        Offset(size.width / 2, 52), const Color(0xFF8FA0C8), 12);
    if (g._activityCount(g._domain) == 0) {
      _text(canvas, 'Aucune activité dans ce domaine',
          Offset(size.width / 2, size.height / 2),
          Colors.white.withOpacity(0.5), 14);
    } else {
      _text(canvas, 'Touche un terminal ⌗ d\'activité pour explorer sa carte',
          Offset(size.width / 2, size.height - 24),
          const Color(0xFF8FA0C8), 12);
    }
  }

  void _drawRoom(Canvas canvas, Rect px, _Room r, FluoDomain dom, int idx) {
    final rr = RRect.fromRectAndRadius(px, const Radius.circular(6));
    canvas.drawRRect(rr, Paint()..color = const Color(0xFF0B1422));
    canvas.drawRRect(
        rr, Paint()..color = dom.color.withOpacity(r.corridor ? 0.05 : 0.12));
    if (!r.corridor) {
      _glow(canvas, px.center, math.min(px.width, px.height) * 0.5,
          dom.color.withOpacity(0.14));
    }
    canvas.drawRRect(
        rr,
        _stroke(dom.color.withOpacity(r.corridor ? 0.4 : 0.85),
            r.corridor ? 1.5 : 2.5));
    if (r.entry) {
      _text(canvas, 'Entrée', Offset(px.center.dx, px.top + 16),
          Colors.white.withOpacity(0.9), 13, weight: FontWeight.w700);
    } else if (!r.corridor) {
      final name = dom.activities[idx - 2];
      _text(canvas, name, Offset(px.center.dx, px.top + 16),
          Colors.white.withOpacity(0.9), 13, weight: FontWeight.w700);
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

  // ── NODE-MAP (carte infinie) ───────────────────────────────────────────────
  void _paintRun(Canvas canvas, Size size) {
    final dom = g._doms[g._domain];
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -0.1),
            radius: 1.2,
            colors: [Color(0xFF1A1440), Color(0xFF0B0A22), Color(0xFF05070F)],
          ).createShader(rect));
    final rnd = math.Random(5);
    for (var i = 0; i < 70; i++) {
      final sx = rnd.nextDouble() * size.width;
      final sy = (rnd.nextDouble() * size.height - g._camY * 0.2) % size.height;
      canvas.drawCircle(Offset(sx, sy < 0 ? sy + size.height : sy),
          rnd.nextDouble() * 1.3 + 0.3, Paint()..color = Colors.white.withOpacity(0.4));
    }

    if (g._nodes.isEmpty) return;

    for (var i = 0; i < g._nodes.length; i++) {
      final n = g._nodes[i];
      final a = g._project(g._nodeWorld(i));
      if (a.dy < -60 || a.dy > size.height + 60) continue;
      for (final l in n.links) {
        final b = g._project(g._nodeWorld(l));
        final live = n.visited || (n.unlocked && g._nodes[l].unlocked);
        canvas.drawLine(
            a,
            b,
            Paint()
              ..strokeWidth = live ? 3 : 1.5
              ..color = (live
                      ? const Color(0xFF8FE9FF)
                      : const Color(0xFF3A4570))
                  .withOpacity(live ? 0.5 : 0.25));
      }
    }
    for (var i = 0; i < g._nodes.length; i++) {
      final n = g._nodes[i];
      final pos = g._project(g._nodeWorld(i));
      if (pos.dy < -40 || pos.dy > size.height + 40) continue;
      final c = _kindColor[n.kind]!;
      final reachable = !n.visited &&
          n.unlocked &&
          g._nodes[g._cur].links.contains(i) &&
          g._movingTo == null;
      final op = n.unlocked ? 1.0 : 0.4;
      _glow(canvas, pos, 22, c.withOpacity(n.unlocked ? 0.4 : 0.12));
      if (reachable) {
        final pr = 17 + (0.5 + 0.5 * math.sin(n.pulse * 4)) * 8;
        canvas.drawCircle(pos, pr, _stroke(c.withOpacity(0.7), 2));
      }
      canvas.drawCircle(
          pos, 17, Paint()..color = const Color(0xFF120F30).withOpacity(op));
      canvas.drawCircle(pos, 17, _stroke(c.withOpacity(op), 2.4));
      if (n.visited) {
        canvas.drawCircle(pos, 17, Paint()..color = c.withOpacity(0.18));
      }
      _text(canvas, _kindIcon[n.kind]!, pos, c.withOpacity(op), 15);
    }
    _drawHero(canvas, g._project(g._heroW), const Color(0xFFB6FF3C));

    _text(canvas, '${dom.name} · ${g._curActivity}'.toUpperCase(),
        Offset(size.width / 2, 28), dom.color, 19, weight: FontWeight.w900);
    _text(canvas, 'Carte infinie · monte de nœud en nœud, de plus en plus loin',
        Offset(size.width / 2, 52), const Color(0xFF8FA0C8), 12);
    _text(canvas, '✦ Profondeur ${g._depth}   ·   ◆ Items ${g._itemsUnlocked}',
        Offset(size.width / 2, size.height - 24), const Color(0xFFB6FF3C), 13,
        weight: FontWeight.w700);
  }

  void _paintFlash(Canvas canvas, Size size) {
    if (g._flashT <= 0 || g._flash == null) return;
    final a = (g._flashT / 2.2).clamp(0.0, 1.0);
    final box = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.18),
        width: 360,
        height: 42);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)),
        Paint()..color = const Color(0xFF0B1422).withOpacity(0.92 * a));
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)),
        _stroke(const Color(0xFFFFD36B).withOpacity(a), 1.5));
    _text(canvas, g._flash!, box.center, const Color(0xFFFFE08A).withOpacity(a),
        14, weight: FontWeight.w800);
  }

  // ── helpers ────────────────────────────────────────────────────────────────
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
