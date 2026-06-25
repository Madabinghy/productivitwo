// Prototype « Tower Defense » jouable — test du feeling (dessiné en code).
//
// Roster de tourelles à comportements distincts + plusieurs cartes.
// • Placement LIBRE sur grille (chemin fixe ; on pose où on veut, hors chemin).
// • Carburant IRL → puissance des tourelles : plus tu as été régulier (jauge
//   « Régularité IRL », simulée par le bouton « +séance »), plus tes tourelles
//   tapent fort (multiplicateur de dégâts). C'est le lien réel ↔ mini-jeu.
// Style néon/dark + juice. Standalone (sans données ni login).
// Accès : ?proto=td (route sans auth dans web_app).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

void main() => runApp(const TdProtoApp());

class TdProtoApp extends StatelessWidget {
  const TdProtoApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TdGameScreen(),
      );
}

// ── Comportements ───────────────────────────────────────────────────────────
enum Beh { gun, sniper, frost, mortar, flame, rail }

class TurretType {
  const TurretType(this.key, this.name, this.color, this.cost, this.range,
      this.dmg, this.rate, this.beh,
      {this.splash = 0, this.role = ''});
  final String key;
  final String name;
  final Color color;
  final int cost;
  final double range;
  final double dmg;
  final double rate; // s entre deux tirs
  final Beh beh;
  final double splash; // rayon AoE (mortier)
  final String role;
}

const _kTypes = [
  TurretType('gun', 'Blaster', Color(0xFF35E0FF), 40, 120, 1.0, 0.45, Beh.gun,
      role: 'rapide, polyvalent'),
  TurretType('sniper', 'Sniper', Color(0xFF7FE0FF), 95, 260, 8.0, 1.8,
      Beh.sniper,
      role: 'longue portée, gros dégâts'),
  TurretType('frost', 'Givre', Color(0xFF8FE8FF), 70, 120, 0.6, 0.7, Beh.frost,
      role: 'ralentit'),
  TurretType('mortar', 'Mortier', Color(0xFFFFD36B), 95, 150, 2.4, 1.4,
      Beh.mortar,
      splash: 55, role: 'zone (AoE)'),
  TurretType('flame', 'Flamme', Color(0xFFFF8A2B), 80, 82, 0.7, 0.16, Beh.flame,
      role: 'anti-essaim'),
  TurretType('rail', 'Railgun', Color(0xFFFF3DDA), 115, 240, 2.2, 1.3, Beh.rail,
      role: 'perce en ligne'),
];

class _Turret {
  _Turret(this.type, this.pos);
  TurretType type;
  final Offset pos;
  int tier = 1;
  double angle = -math.pi / 2;
  double cd = 0;
  double get range => type.range * (1 + (tier - 1) * 0.18);
  double get dmg => type.dmg * (1 + (tier - 1) * 0.6);
  double get rate => type.rate * (1 - (tier - 1) * 0.18);
  int get upCost => type.cost + tier * 35;
}

// Placement libre : plus de _Slot imposé — les tourelles se posent sur n'importe
// quelle case de grille constructible (hors chemin, non occupée).

class _Enemy {
  _Enemy(this.hp, this.maxHp, this.speed, this.color, this.r, this.reward,
      this.leak, this.boss);
  double d = 0;
  double hp;
  final double maxHp;
  final double speed;
  final Color color;
  final double r;
  final int reward;
  final int leak;
  final bool boss;
  double hit = 0;
  double slowT = 0;
  Offset pos = Offset.zero;
}

class _Proj {
  _Proj(this.pos, this.color, this.target, this.dmg, this.beh, this.splash);
  Offset pos;
  final Color color;
  _Enemy? target;
  final double dmg;
  final Beh beh;
  final double splash;
  final List<Offset> trail = [];
  bool dead = false;
}

class _Beam {
  _Beam(this.a, this.b, this.color);
  final Offset a, b;
  final Color color;
  double life = 0;
}

class _Part {
  _Part(this.pos, this.vel, this.color, this.size);
  Offset pos;
  Offset vel;
  final Color color;
  final double size;
  double life = 0;
}

class _Ring {
  _Ring(this.pos, this.color, this.max);
  final Offset pos;
  final Color color;
  final double max;
  double life = 0;
}

// ── Cartes (fractions de l'écran) ───────────────────────────────────────────
class _MapDef {
  const _MapDef(this.name, this.path);
  final String name;
  final List<Offset> path;
}

const _maps = [
  _MapDef('Serpent', [
    Offset(-0.05, 0.20),
    Offset(0.78, 0.20),
    Offset(0.78, 0.40),
    Offset(0.18, 0.40),
    Offset(0.18, 0.60),
    Offset(0.82, 0.60),
    Offset(1.05, 0.60),
  ]),
  _MapDef('Spirale', [
    Offset(0.5, -0.05),
    Offset(0.5, 0.30),
    Offset(0.20, 0.30),
    Offset(0.20, 0.66),
    Offset(0.80, 0.66),
    Offset(0.80, 0.18),
    Offset(0.62, 0.18),
    Offset(0.62, 0.50),
    Offset(0.38, 0.50),
    Offset(0.38, 1.05),
  ]),
  _MapDef('Zigzag', [
    Offset(-0.05, 0.15),
    Offset(0.85, 0.15),
    Offset(0.15, 0.38),
    Offset(0.85, 0.61),
    Offset(0.15, 0.84),
    Offset(1.05, 0.84),
  ]),
];

class TdGameScreen extends StatefulWidget {
  const TdGameScreen({super.key, this.initialFuel, this.combatLabel});
  // Carburant initial (0..1) injecté par l'appelant (= ta régularité réelle sur
  // l'activité). null → valeur de démo + bouton « +séance ».
  final double? initialFuel;
  final String? combatLabel; // ex. « Combat · Course »
  @override
  State<TdGameScreen> createState() => _TdGameScreenState();
}

class _TdGameScreenState extends State<TdGameScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Size _size = Size.zero;
  bool _setup = false;
  int _mapIndex = 0;

  final List<Offset> _path = [];
  final List<double> _cum = [];
  double _pathLen = 0;
  final List<_Turret> _turrets = [];

  // placement libre sur grille
  static const double _cell = 40;

  // carburant IRL → puissance des tourelles. Simulé ici par le bouton « +séance ».
  // (Plus tu as été régulier IRL, plus tes tourelles tapent fort.)
  double _fuel = 0.3; // régularité 0..1
  double get _powerMult => 1 + _fuel * 1.5; // ×1.0 → ×2.5

  final List<_Enemy> _enemies = [];
  final List<_Proj> _projs = [];
  final List<_Beam> _beams = [];
  final List<_Part> _parts = [];
  final List<_Ring> _rings = [];
  final _rnd = math.Random(5);

  int _gold = 140;
  int _lives = 20;
  int _wave = 0;
  bool _waveActive = false;
  int _toSpawn = 0;
  double _spawnCd = 0;
  double _waveHp = 0;
  double _waveSpeed = 0;
  bool _bossWave = false;
  bool _bossSpawned = false;

  TurretType? _dragType;
  Offset? _dragPos;

  Rect _waveBtn = Rect.zero;
  Rect _mapBtn = Rect.zero;
  Rect _fuelBtn = Rect.zero;
  final List<Rect> _trayRects = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialFuel != null) {
      _fuel = widget.initialFuel!.clamp(0.0, 1.0);
    }
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _build(Size s) {
    _size = s;
    final w = s.width, h = s.height;
    final m = _maps[_mapIndex];
    _path
      ..clear()
      ..addAll(m.path.map((p) => Offset(p.dx * w, p.dy * h)));
    _cum
      ..clear()
      ..add(0);
    _pathLen = 0;
    for (var i = 1; i < _path.length; i++) {
      _pathLen += (_path[i] - _path[i - 1]).distance;
      _cum.add(_pathLen);
    }
    _setup = true;
  }

  // centre de case de grille le plus proche d'un point
  Offset _snap(Offset p) =>
      Offset((p.dx / _cell).floor() * _cell + _cell / 2,
          (p.dy / _cell).floor() * _cell + _cell / 2);

  double _distToPath(Offset p) {
    var best = double.infinity;
    for (var i = 1; i < _path.length; i++) {
      final d = _distToSeg(p, _path[i - 1], _path[i]);
      if (d < best) best = d;
    }
    return best;
  }

  // une case est-elle constructible ? (dans l'aire, hors chemin, libre)
  bool _canPlace(Offset c) {
    if (c.dx < _cell / 2 || c.dx > _size.width - _cell / 2) return false;
    if (c.dy < 78 || c.dy > _size.height - 170) return false;
    if (_distToPath(c) < 30) return false;
    for (final t in _turrets) {
      if ((t.pos - c).distance < _cell * 0.7) return false;
    }
    return true;
  }

  void _resetGame() {
    _enemies.clear();
    _projs.clear();
    _beams.clear();
    _parts.clear();
    _rings.clear();
    _turrets.clear();
    _gold = 140;
    _lives = 20;
    _wave = 0;
    _waveActive = false;
    _toSpawn = 0;
    _setup = false; // force rebuild de la carte
  }

  Offset _posAt(double d) {
    if (d <= 0) return _path.first;
    if (d >= _pathLen) return _path.last;
    for (var i = 1; i < _path.length; i++) {
      if (d <= _cum[i]) {
        final t = (d - _cum[i - 1]) / (_cum[i] - _cum[i - 1]);
        return Offset.lerp(_path[i - 1], _path[i], t)!;
      }
    }
    return _path.last;
  }

  void _startWave() {
    if (_waveActive) return;
    _wave++;
    _waveActive = true;
    _toSpawn = 6 + _wave * 3;
    _spawnCd = 0;
    _waveHp = 4 + math.pow(_wave, 1.85).toDouble();
    _waveSpeed = 42 + _wave * 4.0;
    _bossWave = _wave % 5 == 0;
    _bossSpawned = false;
  }

  void _damage(_Enemy en, double dmg) {
    if (en.hp <= 0) return;
    en.hp -= dmg;
    en.hit = 1;
    if (en.hp <= 0) {
      _gold += en.reward;
      _burst(en.pos, en.color);
      _rings.add(_Ring(en.pos, en.color, en.r * 3));
    }
  }

  void _tick(Duration e) {
    final dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (!_setup || dt <= 0 || dt > 0.08) {
      setState(() {});
      return;
    }

    // spawn
    if (_waveActive && _toSpawn > 0) {
      _spawnCd -= dt;
      if (_spawnCd <= 0) {
        _spawnCd = math.max(0.28, 0.62 - _wave * 0.015);
        _toSpawn--;
        if (_bossWave && !_bossSpawned) {
          _bossSpawned = true;
          _enemies.add(_Enemy(_waveHp * 10, _waveHp * 10, _waveSpeed * 0.5,
              const Color(0xFFFF2D7A), 30, 60, 3, true));
        } else {
          final roll = _rnd.nextDouble();
          double hp = _waveHp, sp = _waveSpeed, r = 13;
          int reward = 4;
          Color c;
          if (roll < 0.28) {
            hp *= 0.45;
            sp *= 1.75;
            r = 11;
            c = const Color(0xFF35E0FF);
          } else if (roll < 0.5) {
            hp *= 2.4;
            sp *= 0.6;
            r = 20;
            reward = 9;
            c = const Color(0xFFFF7A2B);
          } else {
            c = const Color(0xFFFF4D6D);
          }
          _enemies.add(_Enemy(hp, hp, sp, c, r, reward, 1, false));
        }
      }
    }
    if (_waveActive && _toSpawn == 0 && _enemies.isEmpty) {
      _waveActive = false;
      _gold += 18 + _wave * 3;
    }

    // ennemis
    for (final en in _enemies) {
      en.slowT = (en.slowT - dt).clamp(0.0, 99.0);
      final spd = en.slowT > 0 ? en.speed * 0.45 : en.speed;
      en.d += spd * dt;
      en.pos = _posAt(en.d);
      en.hit = (en.hit - dt * 3).clamp(0.0, 1.0);
      if (en.d >= _pathLen) {
        en.hp = -999;
        _lives = (_lives - en.leak).clamp(0, 999);
        _rings.add(_Ring(_path.last, const Color(0xFFFF4D6D), 60));
      }
    }

    // tourelles
    for (final tu in _turrets) {
      tu.cd -= dt;
      // cible la plus avancée dans la portée
      _Enemy? best;
      var bestProg = -1.0;
      final inRange = <_Enemy>[];
      for (final en in _enemies) {
        if (en.hp <= 0) continue;
        if ((en.pos - tu.pos).distance <= tu.range) {
          inRange.add(en);
          if (en.d > bestProg) {
            bestProg = en.d;
            best = en;
          }
        }
      }
      if (best != null) {
        final ta = math.atan2(best.pos.dy - tu.pos.dy, best.pos.dx - tu.pos.dx);
        tu.angle = _lerpA(tu.angle, ta, math.min(1, dt * 10));
      }
      if (tu.cd > 0 || inRange.isEmpty) continue;
      tu.cd = tu.rate;
      final dmg = tu.dmg * _powerMult; // carburant IRL → puissance
      final dir = Offset(math.cos(tu.angle), math.sin(tu.angle));
      final tip = tu.pos + dir * 22;
      switch (tu.type.beh) {
        case Beh.flame:
          for (final en in inRange) {
            _damage(en, dmg);
          }
          for (var i = 0; i < 6; i++) {
            final a = tu.angle + (_rnd.nextDouble() - 0.5) * 0.7;
            _parts.add(_Part(
                tip,
                Offset(math.cos(a), math.sin(a)) * (60 + _rnd.nextDouble() * 60),
                i.isEven ? const Color(0xFFFF8A2B) : const Color(0xFFFFD36B),
                3));
          }
          break;
        case Beh.rail:
          final end = tu.pos + dir * tu.range;
          _beams.add(_Beam(tip, end, tu.type.color));
          for (final en in _enemies) {
            if (en.hp <= 0) continue;
            if (_distToSeg(en.pos, tip, end) < en.r + 9) _damage(en, dmg);
          }
          break;
        default:
          if (best != null) {
            _projs.add(_Proj(tip, tu.type.color, best, dmg, tu.type.beh,
                tu.type.splash));
            _parts.add(_Part(tip, dir * 40, tu.type.color, 3));
          }
      }
    }

    // projectiles
    for (final p in _projs) {
      final tg = p.target;
      if (tg == null || tg.hp <= 0) {
        p.dead = true;
        continue;
      }
      final delta = tg.pos - p.pos;
      final dist = delta.distance;
      if (dist < tg.r + 6) {
        _damage(tg, p.dmg);
        if (p.beh == Beh.frost) tg.slowT = 1.4;
        if (p.splash > 0) {
          _rings.add(_Ring(p.pos, p.color, p.splash));
          for (final en in _enemies) {
            if (en != tg &&
                en.hp > 0 &&
                (en.pos - p.pos).distance < p.splash) {
              _damage(en, p.dmg * 0.6);
            }
          }
        }
        _spark(p.pos, p.color, 4);
        p.dead = true;
        continue;
      }
      p.trail.insert(0, p.pos);
      if (p.trail.length > 5) p.trail.removeLast();
      p.pos += delta / dist * 600 * dt;
    }
    _projs.removeWhere((p) => p.dead);
    _enemies.removeWhere((en) => en.hp <= 0);

    for (final b in _beams) {
      b.life += dt * 6;
    }
    _beams.removeWhere((b) => b.life >= 1);
    for (final pa in _parts) {
      pa.life += dt * 1.7;
      pa.pos += pa.vel * dt;
      pa.vel = Offset(pa.vel.dx * 0.94, pa.vel.dy * 0.94 + 50 * dt);
    }
    _parts.removeWhere((p) => p.life >= 1);
    for (final r in _rings) {
      r.life += dt * 2.4;
    }
    _rings.removeWhere((r) => r.life >= 1);

    setState(() {});
  }

  void _spark(Offset o, Color c, int n) {
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final sp = 40 + _rnd.nextDouble() * 70;
      _parts.add(_Part(o, Offset(math.cos(a), math.sin(a)) * sp, c, 2.5));
    }
  }

  void _burst(Offset o, Color c) {
    for (var i = 0; i < 12; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final sp = 50 + _rnd.nextDouble() * 140;
      _parts.add(_Part(o, Offset(math.cos(a), math.sin(a)) * sp, c,
          2 + _rnd.nextDouble() * 3));
    }
  }

  double _lerpA(double a, double b, double t) {
    var d = (b - a) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return a + d * t;
  }

  double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final t =
        ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / (ab.distanceSquared + 1e-6);
    final tc = t.clamp(0.0, 1.0);
    return (p - (a + ab * tc)).distance;
  }

  void _onTap(Offset p) {
    if (_waveBtn.contains(p)) {
      _startWave();
      return;
    }
    if (_mapBtn.contains(p)) {
      _mapIndex = (_mapIndex + 1) % _maps.length;
      _resetGame();
      return;
    }
    if (_fuelBtn.contains(p)) {
      _fuel = (_fuel + 0.15).clamp(0.0, 1.0);
      return;
    }
    for (final tu in _turrets) {
      if ((tu.pos - p).distance <= 22 && tu.tier < 3 && _gold >= tu.upCost) {
        _gold -= tu.upCost;
        tu.tier++;
        _rings.add(_Ring(tu.pos, tu.type.color, 50));
        return;
      }
    }
  }

  void _onPanStart(Offset p) {
    for (var i = 0; i < _trayRects.length; i++) {
      if (_trayRects[i].contains(p)) {
        final t = _kTypes[i];
        if (_gold >= t.cost) {
          _dragType = t;
          _dragPos = p;
        }
        return;
      }
    }
  }

  void _onPanEnd() {
    final dt = _dragType;
    final dp = _dragPos;
    if (dt != null && dp != null) {
      final cell = _snap(dp);
      if (_canPlace(cell) && _gold >= dt.cost) {
        _turrets.add(_Turret(dt, cell));
        _gold -= dt.cost;
        _rings.add(_Ring(cell, dt.color, 46));
      }
    }
    _dragType = null;
    _dragPos = null;
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: const Color(0xFF06070F),
      body: Stack(children: [
        Positioned.fill(
          child: LayoutBuilder(builder: (context, c) {
            final s = Size(c.maxWidth, c.maxHeight);
            if (!_setup || s != _size) _build(s);
            return GestureDetector(
              onTapUp: (d) => _onTap(d.localPosition),
              onPanStart: (d) => _onPanStart(d.localPosition),
              onPanUpdate: (d) {
                if (_dragType != null) setState(() => _dragPos = d.localPosition);
              },
              onPanEnd: (_) => _onPanEnd(),
              child: CustomPaint(size: s, painter: _TdPainter(this)),
            );
          }),
        ),
        // bouton retour (quand lancé depuis la carte à nœuds)
        if (canPop)
          Positioned(
            left: 10,
            top: 8,
            child: SafeArea(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1422).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF35E0FF).withOpacity(0.7)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.arrow_back,
                          color: Color(0xFF35E0FF), size: 16),
                      const SizedBox(width: 6),
                      Text(widget.combatLabel ?? 'Retour',
                          style: const TextStyle(
                              color: Color(0xFF35E0FF),
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _TdPainter extends CustomPainter {
  _TdPainter(this.g);
  final _TdGameScreenState g;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.1),
          radius: 1.2,
          colors: [Color(0xFF141830), Color(0xFF08090F)],
        ).createShader(rect),
    );
    final grid = Paint()..color = const Color(0xFF35E0FF).withOpacity(0.05);
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // circuit
    if (g._path.length > 1) {
      final path = Path()..moveTo(g._path.first.dx, g._path.first.dy);
      for (var i = 1; i < g._path.length; i++) {
        path.lineTo(g._path[i].dx, g._path[i].dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 28
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF1A2340));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 28
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF35E0FF).withOpacity(0.10));
      _glow(canvas, g._path.last, 16, const Color(0xFFFF4D6D).withOpacity(0.4));
    }

    // pendant un drag : surligne les cases constructibles autour du curseur
    if (g._dragType != null && g._dragPos != null) {
      final dp = g._dragPos!;
      final fill = Paint()..color = const Color(0xFF35E0FF).withOpacity(0.05);
      final ok = Paint()..color = const Color(0xFF6FE08A).withOpacity(0.12);
      for (var gx = dp.dx - 2 * _TdGameScreenState._cell;
          gx <= dp.dx + 2 * _TdGameScreenState._cell;
          gx += _TdGameScreenState._cell) {
        for (var gy = dp.dy - 2 * _TdGameScreenState._cell;
            gy <= dp.dy + 2 * _TdGameScreenState._cell;
            gy += _TdGameScreenState._cell) {
          final c = g._snap(Offset(gx, gy));
          final cellRect = Rect.fromCenter(
              center: c,
              width: _TdGameScreenState._cell - 3,
              height: _TdGameScreenState._cell - 3);
          final canPlace = g._canPlace(c);
          canvas.drawRRect(
              RRect.fromRectAndRadius(cellRect, const Radius.circular(4)),
              canPlace ? ok : fill);
        }
      }
    }

    // beams (railgun)
    for (final b in g._beams) {
      final op = (1 - b.life);
      canvas.drawLine(b.a, b.b, _stroke(b.color.withOpacity(op * 0.4), 8));
      canvas.drawLine(b.a, b.b, _stroke(Colors.white.withOpacity(op), 2.5));
    }

    // rings
    for (final r in g._rings) {
      final p = Curves.easeOut.transform(r.life);
      canvas.drawCircle(
          r.pos,
          r.max * p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - r.life) + 0.5
            ..color = r.color.withOpacity(1 - r.life));
    }

    for (final pa in g._parts) {
      final op = (1 - pa.life).clamp(0, 1).toDouble();
      canvas.drawCircle(
          pa.pos, pa.size * op + 0.5, Paint()..color = pa.color.withOpacity(op));
    }

    for (final p in g._projs) {
      for (var i = 0; i < p.trail.length; i++) {
        final op = (1 - i / p.trail.length) * 0.5;
        canvas.drawCircle(p.trail[i], 2.5 * (1 - i / p.trail.length) + 1,
            Paint()..color = p.color.withOpacity(op));
      }
      _glow(canvas, p.pos, 8, p.color.withOpacity(0.7));
      canvas.drawCircle(p.pos, 3, Paint()..color = Colors.white);
    }

    // ennemis
    for (final en in g._enemies) {
      _glow(canvas, en.pos, en.r * 1.5, en.color.withOpacity(0.45));
      if (en.boss) {
        final pulse = 0.5 + 0.5 * math.sin(g._last.inMilliseconds / 140.0);
        canvas.drawCircle(en.pos, en.r + 6 + pulse * 4,
            _stroke(en.color.withOpacity(0.5 + pulse * 0.4), 2.5));
      }
      canvas.drawCircle(
          en.pos,
          en.r,
          Paint()
            ..shader = RadialGradient(colors: [
              Color.lerp(Colors.white, en.color, 0.5)!,
              en.color
            ]).createShader(Rect.fromCircle(center: en.pos, radius: en.r)));
      canvas.drawCircle(en.pos, en.r,
          _stroke(Colors.white.withOpacity(0.5 + en.hit * 0.4), 1.5));
      if (en.slowT > 0) {
        canvas.drawCircle(en.pos, en.r,
            Paint()..color = const Color(0xFF8FE8FF).withOpacity(0.35));
      }
      final hpf = (en.hp / en.maxHp).clamp(0.0, 1.0);
      canvas.drawRect(
          Rect.fromLTWH(en.pos.dx - en.r, en.pos.dy - en.r - 8.5, en.r * 2, 3),
          Paint()..color = Colors.black54);
      canvas.drawRect(
          Rect.fromLTWH(
              en.pos.dx - en.r, en.pos.dy - en.r - 8.5, en.r * 2 * hpf, 3),
          Paint()..color = const Color(0xFF6FE08A));
      if (en.hit > 0) {
        canvas.drawCircle(en.pos, en.r,
            Paint()..color = Colors.white.withOpacity(en.hit * 0.5));
      }
    }

    for (final tu in g._turrets) {
      _drawTurret(canvas, tu);
    }

    // ghost : la tourelle se cale sur la case de grille la plus proche
    if (g._dragType != null && g._dragPos != null) {
      final c = g._dragType!.color;
      final cell = g._snap(g._dragPos!);
      final valid = g._canPlace(cell);
      final col = valid ? c : const Color(0xFFFF4D6D);
      _glow(canvas, cell, 30, col.withOpacity(0.4));
      canvas.drawCircle(
          cell, g._dragType!.range, Paint()..color = col.withOpacity(0.06));
      canvas.drawCircle(cell, g._dragType!.range, _stroke(col.withOpacity(0.4), 1.5));
      canvas.drawCircle(cell, 16, Paint()..color = const Color(0xFF111630));
      canvas.drawCircle(cell, 16, _stroke(col, 2.5));
      canvas.drawCircle(cell, 6, Paint()..color = col);
      if (!valid) {
        canvas.drawLine(cell.translate(-9, -9), cell.translate(9, 9),
            _stroke(const Color(0xFFFF4D6D), 2.5));
        canvas.drawLine(cell.translate(9, -9), cell.translate(-9, 9),
            _stroke(const Color(0xFFFF4D6D), 2.5));
      }
    }

    _hud(canvas, size);
  }

  void _drawTurret(Canvas canvas, _Turret tu) {
    final c = tu.type.color;
    final pos = tu.pos;
    _glow(canvas, pos, 26, c.withOpacity(0.35));
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(tu.angle);
    switch (tu.type.beh) {
      case Beh.sniper:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(0, -2.5, 30 + tu.tier * 4, 5),
                const Radius.circular(2.5)),
            Paint()..color = c);
        break;
      case Beh.gun:
        for (var k = 0; k < tu.tier; k++) {
          final off = (k - (tu.tier - 1) / 2) * 6.0;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(0, off - 3, 22, 6), const Radius.circular(3)),
              Paint()..color = c);
        }
        break;
      case Beh.rail:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(0, -7, 24, 4), const Radius.circular(2)),
            Paint()..color = c);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(0, 3, 24, 4), const Radius.circular(2)),
            Paint()..color = c);
        break;
      case Beh.mortar:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(0, -7, 18, 14), const Radius.circular(5)),
            Paint()..color = c);
        break;
      case Beh.flame:
        canvas.drawPath(
            Path()
              ..moveTo(0, -7)
              ..lineTo(20, -10)
              ..lineTo(20, 10)
              ..lineTo(0, 7)
              ..close(),
            Paint()..color = c);
        break;
      case Beh.frost:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(0, -4, 16, 8), const Radius.circular(4)),
            Paint()..color = c);
        break;
    }
    canvas.restore();
    canvas.drawCircle(pos, 16, Paint()..color = const Color(0xFF111630));
    canvas.drawCircle(pos, 16, _stroke(c, 2.5));
    canvas.drawCircle(pos, 6, Paint()..color = c);
    for (var k = 0; k < 3; k++) {
      canvas.drawCircle(pos.translate(-8.0 + k * 8, 22), 2.4,
          Paint()..color = k < tu.tier ? c : const Color(0xFF3A4570));
    }
  }

  void _hud(Canvas canvas, Size size) {
    _text(canvas, '💰 ${g._gold}', const Offset(58, 34), const Color(0xFFFFD36B),
        18, weight: FontWeight.w800);
    _text(canvas, '❤ ${g._lives}', Offset(size.width / 2, 34),
        const Color(0xFFFF6F8A), 18, weight: FontWeight.w800);
    _text(canvas, 'Vague ${g._wave}', Offset(size.width - 64, 34),
        const Color(0xFF8FE9FF), 18, weight: FontWeight.w800);
    if (g._waveActive && g._bossWave) {
      _text(canvas, '⚠ BOSS', Offset(size.width - 64, 54),
          const Color(0xFFFF2D7A), 13, weight: FontWeight.w800);
    }

    // bouton carte
    g._mapBtn = const Rect.fromLTWH(16, 50, 150, 30);
    canvas.drawRRect(
        RRect.fromRectAndRadius(g._mapBtn, const Radius.circular(15)),
        Paint()..color = const Color(0xFF1A2340));
    _text(canvas, '🗺 ${_maps[g._mapIndex].name} ▶', g._mapBtn.center,
        const Color(0xFF8FE9FF), 12, weight: FontWeight.w700);

    // ── carburant IRL → puissance des tourelles ──────────────────────────────
    // bouton « +séance » (simule une activité réelle loggée)
    g._fuelBtn = Rect.fromLTWH(size.width - 150, 50, 134, 30);
    canvas.drawRRect(
        RRect.fromRectAndRadius(g._fuelBtn, const Radius.circular(15)),
        Paint()..color = const Color(0xFF15324A));
    canvas.drawRRect(
        RRect.fromRectAndRadius(g._fuelBtn, const Radius.circular(15)),
        _stroke(const Color(0xFF35E0FF).withOpacity(0.7), 1.4));
    _text(canvas, '⚡ +séance IRL', g._fuelBtn.center, const Color(0xFF8FE9FF), 12,
        weight: FontWeight.w800);
    // jauge de régularité + multiplicateur de puissance (centré en haut)
    final barW = 190.0;
    final bar = Rect.fromLTWH(size.width / 2 - barW / 2, 56, barW, 9);
    _text(canvas, 'Régularité IRL', Offset(size.width / 2, 49),
        const Color(0xFF8FA0C8), 10);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(5)),
        Paint()..color = const Color(0xFF142033));
    final fillW = (barW * g._fuel).clamp(2.0, barW);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(bar.left, bar.top, fillW, bar.height),
            const Radius.circular(5)),
        Paint()
          ..color = Color.lerp(const Color(0xFFFF8A2B), const Color(0xFFB6FF3C),
              g._fuel)!);
    _text(
        canvas,
        'Puissance des tourelles ×${g._powerMult.toStringAsFixed(1)}',
        Offset(size.width / 2, 76),
        const Color(0xFFB6FF3C),
        12,
        weight: FontWeight.w800);

    // bouton vague
    const bw = 210.0, bh = 46.0;
    g._waveBtn =
        Rect.fromLTWH(size.width / 2 - bw / 2, size.height - 152, bw, bh);
    final active = g._waveActive;
    canvas.drawRRect(
        RRect.fromRectAndRadius(g._waveBtn, const Radius.circular(23)),
        Paint()
          ..color =
              active ? const Color(0xFF1A2340) : const Color(0xFF1D9E75));
    _text(
        canvas,
        active ? 'Vague en cours…' : '▶ Lancer la vague ${g._wave + 1}',
        g._waveBtn.center,
        active ? const Color(0xFF6f7aa0) : Colors.white,
        15,
        weight: FontWeight.w800);

    // palette
    g._trayRects.clear();
    final n = _kTypes.length;
    const gap = 7.0;
    final avail = size.width - 16;
    final cw = ((avail - gap * (n - 1)) / n).clamp(48.0, 92.0);
    final ch = 70.0;
    final totalW = n * cw + (n - 1) * gap;
    final startX = size.width / 2 - totalW / 2;
    final y = size.height - 84;
    for (var i = 0; i < n; i++) {
      final t = _kTypes[i];
      final r = Rect.fromLTWH(startX + i * (cw + gap), y, cw, ch);
      g._trayRects.add(r);
      final afford = g._gold >= t.cost;
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(12)),
          Paint()
            ..color =
                const Color(0xFF111630).withOpacity(afford ? 0.95 : 0.5));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)),
          _stroke(t.color.withOpacity(afford ? 0.9 : 0.3), 2));
      _glow(canvas, Offset(r.center.dx, r.top + 22), 13,
          t.color.withOpacity(afford ? 0.4 : 0.15));
      canvas.drawCircle(Offset(r.center.dx, r.top + 22), 9,
          Paint()..color = t.color.withOpacity(afford ? 1 : 0.4));
      _text(canvas, t.name, Offset(r.center.dx, r.bottom - 22),
          Colors.white.withOpacity(afford ? 0.95 : 0.4), 11,
          weight: FontWeight.w700);
      _text(canvas, '💰${t.cost}', Offset(r.center.dx, r.bottom - 8),
          const Color(0xFFFFD36B).withOpacity(afford ? 1 : 0.4), 11);
    }
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
  bool shouldRepaint(covariant _TdPainter old) => true;
}
