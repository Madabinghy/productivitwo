import 'dart:collection';
import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/world_map_gen.dart';

// OVERWORLD ORGANIQUE en Flame (?flame=3, après auth). Génère une vraie carte
// procédurale depuis TES domaines (régions dimensionnées par leur poids, cf.
// world_map_gen.dart), rendue en Flame : régions colorées par domaine, eau autour,
// avatar + tap-to-move (BFS) + clavier + caméra. Libéré de la contrainte « bandes ».
class FlameDataProtoScreen extends StatefulWidget {
  final FirestoreSync sync;
  const FlameDataProtoScreen({super.key, required this.sync});

  @override
  State<FlameDataProtoScreen> createState() => _FlameDataProtoScreenState();
}

class _FlameDataProtoScreenState extends State<FlameDataProtoScreen> {
  WorldMap? _map;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.sync.pull();
      if (state == null) throw Exception('Aucun état chargé');
      final logic = AppLogic(state, () {})..sync = widget.sync;
      // Poids d'un domaine = nb de routines + activités actives qui lui appartiennent.
      final byDom = <String, int>{};
      for (final a in logic.state.activeActivities) {
        byDom[a.domainId] = (byDom[a.domainId] ?? 0) + 1;
      }
      final weights = [
        for (final d in logic.state.activeDomains)
          DomainWeight(d.id, d.colorValue, byDom[d.id] ?? 1)
      ];
      final map = generateOverworld(weights);
      if (mounted) setState(() => _map = map);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: Text('Erreur : $_error',
                style: const TextStyle(color: Colors.white70))),
      );
    }
    final map = _map;
    if (map == null) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: GameWidget(game: _OverworldGame(map))),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(.55),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Overworld procédural · ${map.regions.length} régions · '
              '${map.cols}×${map.rows} · TAP = se déplacer · flèches/WASD',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ]),
    );
  }
}

const double _tile = 22;

class _OverworldGame extends FlameGame with KeyboardEvents {
  _OverworldGame(this.map);
  final WorldMap map;

  late final PositionComponent _avatar;
  late final Map<String, Color> _domColor;
  final Set<LogicalKeyboardKey> _pressed = {};
  List<Point<int>> _path = [];

  @override
  Color backgroundColor() => const Color(0xFF071019);

  @override
  Future<void> onLoad() async {
    _domColor = {
      for (final r in map.regions)
        r.domainId: r.colorValue != null
            ? Color(r.colorValue!)
            : const Color(0xFF4F8DF7)
    };
    world.add(_OverworldTiles(map, _domColor, _onTapTile));

    _avatar = CircleComponent(
      radius: _tile * 0.4,
      anchor: Anchor.center,
      position: Vector2((map.start.x + .5) * _tile, (map.start.y + .5) * _tile),
      paint: Paint()..color = Colors.white,
    );
    world.add(_avatar);
    camera.follow(_avatar);
    camera.viewfinder.zoom = 1.4;
  }

  Point<int> get _cur => Point(
      (_avatar.position.x / _tile).floor(), (_avatar.position.y / _tile).floor());

  void _onTapTile(int x, int y) {
    if (!map.walkable(x, y)) return;
    _path = _bfsMap(map, _cur, Point(x, y));
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent e, Set<LogicalKeyboardKey> keys) {
    _pressed
      ..clear()
      ..addAll(keys);
    if (keys.isNotEmpty) _path = [];
    return KeyEventResult.handled;
  }

  @override
  void update(double dt) {
    super.update(dt);
    const speed = 170.0;
    var dir = Vector2.zero();
    if (_pressed.contains(LogicalKeyboardKey.arrowLeft) ||
        _pressed.contains(LogicalKeyboardKey.keyA)) dir.x -= 1;
    if (_pressed.contains(LogicalKeyboardKey.arrowRight) ||
        _pressed.contains(LogicalKeyboardKey.keyD)) dir.x += 1;
    if (_pressed.contains(LogicalKeyboardKey.arrowUp) ||
        _pressed.contains(LogicalKeyboardKey.keyW)) dir.y -= 1;
    if (_pressed.contains(LogicalKeyboardKey.arrowDown) ||
        _pressed.contains(LogicalKeyboardKey.keyS)) dir.y += 1;
    if (!dir.isZero()) {
      final next = _avatar.position + dir.normalized() * speed * dt;
      if (map.walkable((next.x / _tile).floor(), (next.y / _tile).floor())) {
        _avatar.position = next;
      }
      return;
    }
    if (_path.isEmpty) return;
    final tgt =
        Vector2((_path.first.x + .5) * _tile, (_path.first.y + .5) * _tile);
    final to = tgt - _avatar.position;
    if (to.length < 2) {
      _avatar.position = tgt;
      _path.removeAt(0);
    } else {
      _avatar.position += to.normalized() * speed * dt;
    }
  }
}

// BFS 4-dir sur les cases TERRE (owner != null).
List<Point<int>> _bfsMap(WorldMap w, Point<int> from, Point<int> to) {
  if (from == to || !w.walkable(to.x, to.y)) return const [];
  final prev = <String, Point<int>?>{'${from.x}_${from.y}': null};
  final q = Queue<Point<int>>()..add(from);
  while (q.isNotEmpty) {
    final cur = q.removeFirst();
    if (cur == to) break;
    for (final n in [
      Point(cur.x + 1, cur.y),
      Point(cur.x - 1, cur.y),
      Point(cur.x, cur.y + 1),
      Point(cur.x, cur.y - 1),
    ]) {
      final id = '${n.x}_${n.y}';
      if (prev.containsKey(id) || !w.walkable(n.x, n.y)) continue;
      prev[id] = cur;
      q.add(n);
    }
  }
  if (!prev.containsKey('${to.x}_${to.y}')) return const [];
  final path = <Point<int>>[];
  Point<int>? cur = to;
  while (cur != null && cur != from) {
    path.add(cur);
    cur = prev['${cur.x}_${cur.y}'];
  }
  return path.reversed.toList();
}

// Toute la carte dessinée en UN composant (canvas direct) : régions colorées par
// domaine (légère variation par case), eau pour le vide. Reçoit les taps.
class _OverworldTiles extends PositionComponent with TapCallbacks {
  _OverworldTiles(this.map, this.domColor, this.onTapTile)
      : super(size: Vector2(map.cols * _tile, map.rows * _tile));
  final WorldMap map;
  final Map<String, Color> domColor;
  final void Function(int x, int y) onTapTile;

  static const _water = Color(0xFF0C2030);

  @override
  void onTapDown(TapDownEvent e) {
    onTapTile((e.localPosition.x / _tile).floor(),
        (e.localPosition.y / _tile).floor());
  }

  @override
  void render(Canvas canvas) {
    final p = Paint();
    for (var y = 0; y < map.rows; y++) {
      for (var x = 0; x < map.cols; x++) {
        final o = map.ownerAt(x, y);
        if (o == null) {
          p.color = _water;
        } else {
          final base = domColor[o] ?? const Color(0xFF4F8DF7);
          // légère variation déterministe par case (texture de biome).
          final n = ((x * 73 + y * 131) % 7) - 3; // -3..3
          p.color = _shade(base, n * 0.018);
        }
        canvas.drawRect(Rect.fromLTWH(x * _tile, y * _tile, _tile, _tile), p);
      }
    }
  }

  Color _shade(Color c, double d) {
    final f = (1 + d).clamp(0.6, 1.4);
    return Color.fromARGB(
      255,
      (c.red * f).clamp(0, 255).round(),
      (c.green * f).clamp(0, 255).round(),
      (c.blue * f).clamp(0, 255).round(),
    );
  }
}
