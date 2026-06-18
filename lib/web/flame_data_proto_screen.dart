import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/world_layout.dart';

// PROTO Flame AVEC TES DONNÉES (?flame=3, après auth) : charge ton état, construit
// TON vrai WorldLayout via buildWorld() (réutilise world_layout.dart, pur), et le
// rend en Flame (tuiles + avatar + caméra + collision murs). Évaluation « le moteur
// gère-t-il bien la vraie carte ? ». N'écrit rien, ne touche pas au Monde existant.
class FlameDataProtoScreen extends StatefulWidget {
  final FirestoreSync sync;
  const FlameDataProtoScreen({super.key, required this.sync});

  @override
  State<FlameDataProtoScreen> createState() => _FlameDataProtoScreenState();
}

class _FlameDataProtoScreenState extends State<FlameDataProtoScreen> {
  WorldLayout? _layout;
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
      try {
        final projects = await widget.sync.fetchProjects();
        logic.updateGanttCounts(projects);
      } catch (_) {}
      final specs = <DomainSpec>[];
      for (final d in logic.state.activeDomains) {
        final routines = <String>[];
        final acts = <String>[];
        for (final a in logic.state.activeActivities) {
          if (a.domainId != d.id) continue;
          (a.isHabit ? routines : acts).add(a.id);
        }
        if (routines.isEmpty && acts.isEmpty) continue;
        specs.add(DomainSpec(
          domainId: d.id,
          colorValue: d.colorValue,
          routineIds: routines,
          activityIds: acts,
        ));
      }
      final layout = buildWorld(specs);
      if (mounted) setState(() => _layout = layout);
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
              style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final layout = _layout;
    if (layout == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: GameWidget(game: _MondeDataGame(layout))),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Flame + TES données · ${layout.cols}×${layout.rows} tuiles · '
              'flèches/WASD · la caméra suit · murs bloquants',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ]),
    );
  }
}

const double _tile = 30;

class _MondeDataGame extends FlameGame with KeyboardEvents {
  _MondeDataGame(this.layout);
  final WorldLayout layout;

  late final PositionComponent _avatar;
  final Set<LogicalKeyboardKey> _pressed = {};

  @override
  Color backgroundColor() => const Color(0xFF050505);

  @override
  Future<void> onLoad() async {
    world.add(_TileMap(layout));
    _avatar = CircleComponent(
      radius: _tile * 0.34,
      anchor: Anchor.center,
      position: Vector2(
          (layout.start.x + .5) * _tile, (layout.start.y + .5) * _tile),
      paint: Paint()..color = const Color(0xFFFFC83D),
    );
    world.add(_avatar);
    camera.follow(_avatar);
  }

  @override
  KeyEventResult onKeyEvent(
      KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    _pressed
      ..clear()
      ..addAll(keysPressed);
    return KeyEventResult.handled;
  }

  @override
  void update(double dt) {
    super.update(dt);
    var dir = Vector2.zero();
    if (_pressed.contains(LogicalKeyboardKey.arrowLeft) ||
        _pressed.contains(LogicalKeyboardKey.keyA)) dir.x -= 1;
    if (_pressed.contains(LogicalKeyboardKey.arrowRight) ||
        _pressed.contains(LogicalKeyboardKey.keyD)) dir.x += 1;
    if (_pressed.contains(LogicalKeyboardKey.arrowUp) ||
        _pressed.contains(LogicalKeyboardKey.keyW)) dir.y -= 1;
    if (_pressed.contains(LogicalKeyboardKey.arrowDown) ||
        _pressed.contains(LogicalKeyboardKey.keyS)) dir.y += 1;
    if (dir.isZero()) return;
    final next = _avatar.position + dir.normalized() * 200 * dt;
    // Collision murs : on n'avance que vers une case praticable.
    final tx = (next.x / _tile).floor();
    final ty = (next.y / _tile).floor();
    if (layout.walkable(tx, ty)) _avatar.position = next;
  }
}

// Toute la carte dessinée en UN composant (canvas direct) → léger même en grand.
class _TileMap extends PositionComponent {
  _TileMap(this.layout);
  final WorldLayout layout;

  @override
  void render(Canvas canvas) {
    final p = Paint();
    for (var y = 0; y < layout.rows; y++) {
      for (var x = 0; x < layout.cols; x++) {
        p.color = _color(layout.at(x, y));
        canvas.drawRect(
            Rect.fromLTWH(x * _tile, y * _tile, _tile - 2, _tile - 2), p);
      }
    }
  }

  Color _color(WtTile t) {
    switch (t) {
      case WtTile.wall:
        return const Color(0xFF333333);
      case WtTile.terrain:
        return const Color(0xFF0F1A14);
      case WtTile.garden:
        return const Color(0xFF1E6B3A);
      case WtTile.village:
        return const Color(0xFF5A4630);
      case WtTile.bridge:
        return const Color(0xFF8A5E33);
      case WtTile.castle:
        return const Color(0x88D4A017);
      case WtTile.chest:
        return const Color(0xFFE0B84A);
    }
  }
}
