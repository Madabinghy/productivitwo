import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_svg/flame_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// PROTOTYPE Flame n°2 (isolé) — version REPRÉSENTATIVE du « Monde » : une bande de
// domaine (village + jardin + château), tes SVG (maisons, décor, tourelle base+tête),
// nuisibles, avatar + caméra. Tap sur la tourelle → la tête se LÈVE en douceur (effet
// natif Flame) avec la flamme. localhost:8080/?flame=2. Ne touche à rien d'existant.
class FlameProto2Screen extends StatelessWidget {
  const FlameProto2Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: GameWidget(game: _MondeProto2())),
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
              'Flame n°2 (SVG) · flèches/WASD pour bouger · tap la tourelle = la tête '
              'se lève + flamme · caméra qui suit',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ]),
    );
  }
}

const double _tile = 44;
const int _cols = 30, _rows = 11; // une bande de domaine + extérieur

class _MondeProto2 extends FlameGame with KeyboardEvents {
  late final PositionComponent _avatar;
  final Set<LogicalKeyboardKey> _pressed = {};

  @override
  Color backgroundColor() => const Color(0xFF0A0A0A);

  @override
  Future<void> onLoad() async {
    // ── Tuiles : murs (haut/bas), village (bleu), jardin (vert), château (or) ──
    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < _cols; x++) {
        world.add(RectangleComponent(
          position: Vector2(x * _tile, y * _tile),
          size: Vector2(_tile - 2, _tile - 2),
          paint: Paint()..color = _tileColor(x, y),
        ));
      }
    }

    // ── SVG décor + structures (tes assets existants) ──
    final house = await Svg.load('icons/house.svg');
    final rock = await Svg.load('icons/rock.svg');
    final tree = await Svg.load('icons/pine-tree.svg');
    final base = await Svg.load('icons/aa-base.svg');
    final head = await Svg.load('icons/aa-head.svg');
    final fire = await Svg.load('icons/fireball.svg');

    _svgAt(house, 2, 4, scale: .7);
    _svgAt(house, 3, 6, scale: .7);
    _svgAt(rock, 26, 2, scale: .6, color: const Color(0xFF8A8A8A));
    _svgAt(tree, 27, 8, scale: .85, color: const Color(0xFF4E7A48));
    _svgAt(rock, 28, 5, scale: .55, color: const Color(0xFF8A8A8A));

    // ── Tourelle (base FIXE + tête PIVOT) sur une ligne du château ──
    final turret = _Turret(base: base, head: head, fire: fire)
      ..position = Vector2(22 * _tile, 5 * _tile);
    world.add(turret);

    // ── Nuisibles (emoji) dans le jardin ──
    _pestAt('🦂', 10, 3);
    _pestAt('🐍', 14, 7);
    _pestAt('🕷️', 12, 5);

    // ── Avatar + caméra ──
    _avatar = CircleComponent(
      radius: _tile * 0.32,
      anchor: Anchor.center,
      position: Vector2(7 * _tile, 5 * _tile),
      paint: Paint()..color = const Color(0xFFFFC83D),
    );
    world.add(_avatar);
    camera.follow(_avatar);
  }

  void _svgAt(Svg svg, int x, int y, {double scale = 1, Color? color}) {
    world.add(SvgComponent(
      svg: svg,
      position: Vector2((x + .5) * _tile, (y + .5) * _tile),
      size: Vector2.all(_tile * scale),
      anchor: Anchor.center,
    ));
  }

  void _pestAt(String emoji, int x, int y) {
    world.add(TextComponent(
      text: emoji,
      anchor: Anchor.center,
      position: Vector2((x + .5) * _tile, (y + .5) * _tile),
      textRenderer: TextPaint(style: const TextStyle(fontSize: 22)),
    ));
  }

  Color _tileColor(int x, int y) {
    if (y == 0 || y == _rows - 1) return const Color(0xFF2C2C2C); // murs (pierre)
    if (x < 6) return const Color(0xFF22324A); // village
    if (x < 19) return const Color(0xFF1E5E36); // jardin
    if (x < 27) return const Color(0x33D4A017); // château / calendrier
    return Colors.black.withOpacity(.28); // extérieur
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
    if (!dir.isZero()) {
      _avatar.position += dir.normalized() * 220 * dt;
      _avatar.position.x = _avatar.position.x.clamp(0, (_cols - 1) * _tile);
      _avatar.position.y = _avatar.position.y.clamp(0, (_rows - 1) * _tile);
    }
  }
}

// Tourelle = base fixe + tête qui pivote. Tap → la tête se lève (RotateEffect) et une
// flamme apparaît brièvement. Montre l'animation du canon, faite NATIVEMENT par Flame.
class _Turret extends PositionComponent with TapCallbacks {
  _Turret({required this.base, required this.head, required this.fire})
      : super(size: Vector2.all(_tile), anchor: Anchor.center);

  final Svg base, head, fire;
  late final SvgComponent _head;
  bool _raised = false;

  @override
  Future<void> onLoad() async {
    add(SvgComponent(svg: base, size: Vector2.all(_tile * .95), anchor: Anchor.center, position: size / 2));
    _head = SvgComponent(
      svg: head,
      size: Vector2.all(_tile * .95),
      anchor: Anchor.bottomCenter,
      position: Vector2(size.x / 2, size.y * .9),
      angle: 0.6, // baissé au repos
    );
    add(_head);
  }

  @override
  void onTapDown(TapDownEvent event) {
    _raised = !_raised;
    _head.add(RotateEffect.to(
      _raised ? 0.0 : 0.6,
      EffectController(duration: .5, curve: Curves.easeOut),
    ));
    if (_raised) {
      final flame = SvgComponent(
        svg: fire,
        size: Vector2.all(_tile * .5),
        anchor: Anchor.center,
        position: Vector2(size.x / 2, -_tile * .2),
      );
      add(flame);
      flame.add(RemoveEffect(delay: 1.2));
    }
  }
}
