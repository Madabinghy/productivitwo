import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// PROTOTYPE Flame (isolé) pour évaluer un moteur de jeu sur « Le Monde » :
// carte de tuiles + avatar qui se déplace (flèches/WASD) + caméra qui suit + tap pour
// se déplacer vers un point. Accessible via localhost:8080/?flame=1. Ne touche à rien.
class FlameProtoScreen extends StatelessWidget {
  const FlameProtoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: GameWidget(game: _MondeProtoGame())),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Prototype Flame · clique la fenêtre puis flèches/WASD pour bouger · '
                'tap = aller au point · la caméra suit',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MondeProtoGame extends FlameGame with KeyboardEvents, TapCallbacks {
  static const double tile = 40;
  static const int cols = 52, rows = 34;

  late final PositionComponent _avatar;
  final Set<LogicalKeyboardKey> _pressed = {};
  Vector2? _moveTarget; // cible de déplacement au tap (null = aucune)

  @override
  Color backgroundColor() => const Color(0xFF0A0A0A);

  @override
  Future<void> onLoad() async {
    // Tuiles : bandes village / jardin / château empilées (façon « Le Monde »),
    // murs en pierre épars. Rendu sur Canvas → bien plus léger que des widgets.
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        world.add(RectangleComponent(
          position: Vector2(x * tile, y * tile),
          size: Vector2(tile - 2, tile - 2),
          paint: Paint()..color = _tileColor(x, y),
        ));
      }
    }

    // Quelques « nuisibles » (placeholders) qui errent un peu.
    for (var i = 0; i < 10; i++) {
      world.add(_Wanderer(
        position: Vector2((6 + i * 4) * tile, ((i.isEven ? 7 : 24)) * tile),
        color: i.isOdd ? const Color(0xFFE05858) : const Color(0xFFB58CFF),
      ));
    }

    // Avatar.
    _avatar = CircleComponent(
      radius: tile * 0.34,
      anchor: Anchor.center,
      position: Vector2(cols / 2 * tile, rows / 2 * tile),
      paint: Paint()..color = const Color(0xFFFFC83D),
    );
    world.add(_avatar);

    camera.follow(_avatar);
    camera.viewfinder.zoom = 1.0;
  }

  Color _tileColor(int x, int y) {
    final band = (y ~/ 9) % 2;
    if (x % 13 == 5 && y % 5 == 2) return const Color(0xFF2C2C2C); // mur (pierre)
    if (x < 8) {
      return band == 0 ? const Color(0xFF24344A) : const Color(0xFF1E2A3A); // village
    }
    if (x < 22) return const Color(0xFF1E5E36); // jardin
    return const Color(0x33D4A017); // château / calendrier
  }

  @override
  KeyEventResult onKeyEvent(
      KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    _pressed
      ..clear()
      ..addAll(keysPressed);
    if (keysPressed.isNotEmpty) _moveTarget = null; // clavier annule le tap-move
    return KeyEventResult.handled;
  }

  @override
  void onTapDown(TapDownEvent event) {
    _moveTarget = event.localPosition; // coords MONDE (la caméra gère la transfo)
  }

  @override
  void update(double dt) {
    super.update(dt);
    const speed = 230.0;
    var dir = Vector2.zero();

    if (_pressed.contains(LogicalKeyboardKey.arrowLeft) ||
        _pressed.contains(LogicalKeyboardKey.keyA)) dir.x -= 1;
    if (_pressed.contains(LogicalKeyboardKey.arrowRight) ||
        _pressed.contains(LogicalKeyboardKey.keyD)) dir.x += 1;
    if (_pressed.contains(LogicalKeyboardKey.arrowUp) ||
        _pressed.contains(LogicalKeyboardKey.keyW)) dir.y -= 1;
    if (_pressed.contains(LogicalKeyboardKey.arrowDown) ||
        _pressed.contains(LogicalKeyboardKey.keyS)) dir.y += 1;

    if (dir.isZero() && _moveTarget != null) {
      final to = _moveTarget! - _avatar.position;
      if (to.length < 4) {
        _moveTarget = null;
      } else {
        dir = to.normalized();
      }
    }

    if (!dir.isZero()) {
      _avatar.position += dir.normalized() * speed * dt;
      _avatar.position.x = _avatar.position.x.clamp(0, (cols - 1) * tile);
      _avatar.position.y = _avatar.position.y.clamp(0, (rows - 1) * tile);
    }
  }
}

// Petit nuisible qui erre (dérive aléatoire) — montre le game loop natif de Flame.
class _Wanderer extends CircleComponent {
  _Wanderer({required Vector2 position, required Color color})
      : super(
          radius: 9,
          anchor: Anchor.center,
          position: position,
          paint: Paint()..color = color,
        );

  Vector2 _vel = Vector2(40, 0);
  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t > 1.2) {
      _t = 0;
      _vel = Vector2(40, 0)..rotate((position.x + position.y) % 6.28);
    }
    position += _vel * dt;
  }
}
