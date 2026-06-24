// Prototype « Tower Defense » jouable — test du feeling (dessiné en code).
//
// Vrai TD : circuit forcé pour les ennemis, emplacements de tourelles, palette
// à GLISSER-DÉPOSER, vagues qui montent en puissance, or gagné aux kills,
// évolution d'une tourelle au tap. Style néon/dark + juice. Standalone (sans
// données ni login) → on teste juste si le gameplay accroche.
//
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

// ── Types de tourelles ──────────────────────────────────────────────────────
class TurretType {
  const TurretType(this.key, this.name, this.color, this.cost, this.range,
      this.dmg, this.rate);
  final String key;
  final String name;
  final Color color;
  final int cost;
  final double range;
  final double dmg;
  final double rate; // s entre deux tirs
}

const _kTypes = [
  TurretType('blaster', 'Blaster', Color(0xFF35E0FF), 40, 120, 1.0, 0.5),
  TurretType('laser', 'Laser', Color(0xFFB6FF3C), 70, 150, 2.4, 1.0),
  TurretType('tesla', 'Tesla', Color(0xFFA86BFF), 100, 100, 1.6, 0.7),
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
  int get upCost => type.cost + (tier) * 35;
}

class _Slot {
  _Slot(this.pos);
  final Offset pos;
  _Turret? turret;
}

class _Enemy {
  _Enemy(this.d, this.hp, this.maxHp, this.speed, this.color, this.r);
  double d; // distance le long du circuit
  double hp;
  final double maxHp;
  final double speed;
  final Color color;
  final double r;
  double hit = 0;
  Offset pos = Offset.zero;
  static _Enemy make(double hp, double speed, Color c, double r) =>
      _Enemy(0, hp, hp, speed, c, r);
}

class _Proj {
  _Proj(this.pos, this.color, this.target, this.dmg);
  Offset pos;
  final Color color;
  _Enemy? target;
  final double dmg;
  final List<Offset> trail = [];
  bool dead = false;
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

class TdGameScreen extends StatefulWidget {
  const TdGameScreen({super.key});
  @override
  State<TdGameScreen> createState() => _TdGameScreenState();
}

class _TdGameScreenState extends State<TdGameScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Size _size = Size.zero;
  bool _setup = false;

  // circuit
  final List<Offset> _path = [];
  final List<double> _cum = [];
  double _pathLen = 0;

  final List<_Slot> _slots = [];
  final List<_Enemy> _enemies = [];
  final List<_Proj> _projs = [];
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

  // drag & drop
  TurretType? _dragType;
  Offset? _dragPos;

  // boutons (rects calculés au paint, lus au tap)
  Rect _waveBtn = Rect.zero;
  final List<Rect> _trayRects = [];

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
    _path.clear();
    final w = s.width, h = s.height;
    // circuit en S (fractions)
    final pts = [
      const Offset(-0.05, 0.18),
      const Offset(0.78, 0.18),
      const Offset(0.78, 0.40),
      const Offset(0.18, 0.40),
      const Offset(0.18, 0.62),
      const Offset(0.82, 0.62),
      const Offset(1.05, 0.62),
    ];
    for (final p in pts) {
      _path.add(Offset(p.dx * w, p.dy * h));
    }
    _cum
      ..clear()
      ..add(0);
    _pathLen = 0;
    for (var i = 1; i < _path.length; i++) {
      _pathLen += (_path[i] - _path[i - 1]).distance;
      _cum.add(_pathLen);
    }
    // emplacements (fractions), de part et d'autre du circuit
    _slots.clear();
    const sl = [
      Offset(0.30, 0.30),
      Offset(0.55, 0.30),
      Offset(0.66, 0.51),
      Offset(0.42, 0.51),
      Offset(0.30, 0.51),
      Offset(0.55, 0.74),
      Offset(0.72, 0.50),
      Offset(0.10, 0.30),
    ];
    for (final p in sl) {
      _slots.add(_Slot(Offset(p.dx * w, p.dy * h)));
    }
    _setup = true;
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
    _toSpawn = 5 + _wave * 2;
    _spawnCd = 0;
    _waveHp = 3 + _wave * 2.2;
    _waveSpeed = 46 + _wave * 3.5;
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
        _spawnCd = 0.7;
        _toSpawn--;
        const pal = [
          Color(0xFFFF4D6D),
          Color(0xFFFF7A2B),
          Color(0xFFB14DFF),
        ];
        _enemies.add(_Enemy.make(_waveHp, _waveSpeed,
            pal[_rnd.nextInt(pal.length)], 13 + _waveHp.clamp(0, 18) * 0.4));
      }
    }
    if (_waveActive && _toSpawn == 0 && _enemies.isEmpty) {
      _waveActive = false;
      _gold += 30 + _wave * 5; // bonus fin de vague
    }

    // ennemis
    for (final en in _enemies) {
      en.d += en.speed * dt;
      en.pos = _posAt(en.d);
      en.hit = (en.hit - dt * 3).clamp(0.0, 1.0);
      if (en.d >= _pathLen) {
        en.hp = -999;
        _lives = (_lives - 1).clamp(0, 999);
        _rings.add(_Ring(_path.last, const Color(0xFFFF4D6D), 60));
      }
    }

    // tourelles
    for (final sl in _slots) {
      final tu = sl.turret;
      if (tu == null) continue;
      tu.cd -= dt;
      _Enemy? best;
      var bestProg = -1.0;
      for (final en in _enemies) {
        if (en.hp <= 0) continue;
        if ((en.pos - tu.pos).distance <= tu.range && en.d > bestProg) {
          bestProg = en.d;
          best = en;
        }
      }
      if (best != null) {
        final ta = math.atan2(best.pos.dy - tu.pos.dy, best.pos.dx - tu.pos.dx);
        tu.angle = _lerpA(tu.angle, ta, math.min(1, dt * 10));
        if (tu.cd <= 0) {
          tu.cd = tu.rate;
          final tip =
              tu.pos + Offset(math.cos(tu.angle), math.sin(tu.angle)) * 22;
          _projs.add(_Proj(tip, tu.type.color, best, tu.dmg));
          _parts.add(_Part(
              tip,
              Offset(math.cos(tu.angle), math.sin(tu.angle)) * 40,
              tu.type.color,
              3));
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
      final dir = tg.pos - p.pos;
      final dist = dir.distance;
      if (dist < tg.r + 6) {
        tg.hp -= p.dmg;
        tg.hit = 1;
        _spark(p.pos, p.color, 4);
        if (tg.hp <= 0) {
          _gold += 6;
          _burst(tg.pos, tg.color);
          _rings.add(_Ring(tg.pos, tg.color, tg.r * 3));
        }
        p.dead = true;
        continue;
      }
      p.trail.insert(0, p.pos);
      if (p.trail.length > 5) p.trail.removeLast();
      p.pos += dir / dist * 560 * dt;
    }
    _projs.removeWhere((p) => p.dead);
    _enemies.removeWhere((en) => en.hp <= 0);

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
      _parts.add(_Part(
          o, Offset(math.cos(a), math.sin(a)) * sp, c, 2 + _rnd.nextDouble() * 3));
    }
  }

  double _lerpA(double a, double b, double t) {
    var d = (b - a) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return a + d * t;
  }

  // ── interactions ──
  void _onTap(Offset p) {
    if (_waveBtn.contains(p)) {
      _startWave();
      return;
    }
    // upgrade d'une tourelle posée
    for (final sl in _slots) {
      final tu = sl.turret;
      if (tu == null) continue;
      if ((sl.pos - p).distance <= 22 && tu.tier < 3 && _gold >= tu.upCost) {
        _gold -= tu.upCost;
        tu.tier++;
        _rings.add(_Ring(sl.pos, tu.type.color, 50));
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
      _Slot? best;
      var bd = 44.0;
      for (final sl in _slots) {
        if (sl.turret != null) continue;
        final d = (sl.pos - dp).distance;
        if (d < bd) {
          bd = d;
          best = sl;
        }
      }
      if (best != null && _gold >= dt.cost) {
        best.turret = _Turret(dt, best.pos);
        _gold -= dt.cost;
        _rings.add(_Ring(best.pos, dt.color, 46));
      }
    }
    _dragType = null;
    _dragPos = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06070F),
      body: LayoutBuilder(builder: (context, c) {
        final s = Size(c.maxWidth, c.maxHeight);
        if (!_setup || s != _size) _build(s);
        return GestureDetector(
          onTapUp: (d) => _onTap(d.localPosition),
          onPanStart: (d) => _onPanStart(d.localPosition),
          onPanUpdate: (d) {
            if (_dragType != null) setState(() => _dragPos = d.localPosition);
          },
          onPanEnd: (_) => _onPanEnd(),
          child: CustomPaint(
            size: s,
            painter: _TdPainter(this),
          ),
        );
      }),
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
            ..strokeWidth = 30
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF1A2340));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 30
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF35E0FF).withOpacity(0.10));
      // flèche de fin
      _glow(canvas, g._path.last, 16, const Color(0xFFFF4D6D).withOpacity(0.4));
    }

    // emplacements vides
    for (final sl in g._slots) {
      if (sl.turret != null) continue;
      final hl = g._dragType != null && (sl.pos - (g._dragPos ?? Offset.zero)).distance < 44;
      canvas.drawCircle(
          sl.pos,
          16,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = (hl ? const Color(0xFF8FE9FF) : const Color(0xFF3A4570))
                .withOpacity(hl ? 0.9 : 0.6));
      if (hl) {
        canvas.drawCircle(sl.pos, 16,
            Paint()..color = const Color(0xFF8FE9FF).withOpacity(0.12));
      }
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

    // particules
    for (final pa in g._parts) {
      final op = (1 - pa.life).clamp(0, 1).toDouble();
      canvas.drawCircle(
          pa.pos, pa.size * op + 0.5, Paint()..color = pa.color.withOpacity(op));
    }

    // projectiles
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
      // barre de vie
      final hpf = (en.hp / en.maxHp).clamp(0.0, 1.0);
      canvas.drawRect(
          Rect.fromCenter(
              center: en.pos.translate(0, -en.r - 7),
              width: en.r * 2,
              height: 3),
          Paint()..color = Colors.black54);
      canvas.drawRect(
          Rect.fromLTWH(en.pos.dx - en.r, en.pos.dy - en.r - 8.5, en.r * 2 * hpf, 3),
          Paint()..color = const Color(0xFF6FE08A));
      if (en.hit > 0) {
        canvas.drawCircle(en.pos, en.r,
            Paint()..color = Colors.white.withOpacity(en.hit * 0.5));
      }
    }

    // tourelles posées
    for (final sl in g._slots) {
      final tu = sl.turret;
      if (tu != null) _drawTurret(canvas, tu);
    }

    // ghost de drag
    if (g._dragType != null && g._dragPos != null) {
      final c = g._dragType!.color;
      _glow(canvas, g._dragPos!, 30, c.withOpacity(0.4));
      canvas.drawCircle(g._dragPos!, g._dragType!.range,
          Paint()..color = c.withOpacity(0.06));
      canvas.drawCircle(
          g._dragPos!, g._dragType!.range, _stroke(c.withOpacity(0.4), 1.5));
      canvas.drawCircle(g._dragPos!, 16, Paint()..color = const Color(0xFF111630));
      canvas.drawCircle(g._dragPos!, 16, _stroke(c, 2.5));
      canvas.drawCircle(g._dragPos!, 6, Paint()..color = c);
    }

    _hud(canvas, size);
  }

  void _drawTurret(Canvas canvas, _Turret tu) {
    final c = tu.type.color;
    final pos = tu.pos;
    _glow(canvas, pos, 28, c.withOpacity(0.35));
    // canon orienté
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(tu.angle);
    if (tu.type.key == 'blaster') {
      for (var k = 0; k < tu.tier; k++) {
        final off = (k - (tu.tier - 1) / 2) * 6.0;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(0, off - 3, 24, 6), const Radius.circular(3)),
            Paint()..color = c);
      }
    } else if (tu.type.key == 'laser') {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, -3, 22 + tu.tier * 3, 6),
              const Radius.circular(3)),
          Paint()..color = c);
    } else {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, -4, 18, 8), const Radius.circular(4)),
          Paint()..color = c);
    }
    canvas.restore();
    // socle
    canvas.drawCircle(pos, 16, Paint()..color = const Color(0xFF111630));
    canvas.drawCircle(pos, 16, _stroke(c, 2.5));
    canvas.drawCircle(pos, 6, Paint()..color = c);
    // pips de tier
    for (var k = 0; k < 3; k++) {
      canvas.drawCircle(pos.translate(-8.0 + k * 8, 22),
          2.4, Paint()..color = k < tu.tier ? c : const Color(0xFF3A4570));
    }
  }

  void _hud(Canvas canvas, Size size) {
    // bandeau haut
    _text(canvas, '💰 ${g._gold}', const Offset(58, 38), const Color(0xFFFFD36B),
        18, weight: FontWeight.w800);
    _text(canvas, '❤ ${g._lives}', Offset(size.width / 2, 38),
        const Color(0xFFFF6F8A), 18, weight: FontWeight.w800);
    _text(canvas, 'Vague ${g._wave}', Offset(size.width - 70, 38),
        const Color(0xFF8FE9FF), 18, weight: FontWeight.w800);

    // bouton vague
    final bw = 200.0, bh = 46.0;
    g._waveBtn = Rect.fromLTWH(
        size.width / 2 - bw / 2, size.height - 150, bw, bh);
    final active = g._waveActive;
    canvas.drawRRect(
        RRect.fromRectAndRadius(g._waveBtn, const Radius.circular(23)),
        Paint()
          ..color = active
              ? const Color(0xFF1A2340)
              : const Color(0xFF1D9E75));
    _text(
        canvas,
        active ? 'Vague en cours…' : '▶ Lancer la vague ${g._wave + 1}',
        g._waveBtn.center,
        active ? const Color(0xFF6f7aa0) : Colors.white,
        15,
        weight: FontWeight.w800);

    // palette (tray)
    g._trayRects.clear();
    final n = _kTypes.length;
    final cw = 104.0, ch = 78.0, gap = 12.0;
    final totalW = n * cw + (n - 1) * gap;
    final startX = size.width / 2 - totalW / 2;
    final y = size.height - 92;
    for (var i = 0; i < n; i++) {
      final t = _kTypes[i];
      final r = Rect.fromLTWH(startX + i * (cw + gap), y, cw, ch);
      g._trayRects.add(r);
      final afford = g._gold >= t.cost;
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(14)),
          Paint()..color = const Color(0xFF111630).withOpacity(afford ? 0.95 : 0.5));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(14)),
          _stroke(t.color.withOpacity(afford ? 0.9 : 0.3), 2));
      // mini icône
      _glow(canvas, Offset(r.center.dx, r.top + 26), 16,
          t.color.withOpacity(afford ? 0.4 : 0.15));
      canvas.drawCircle(Offset(r.center.dx, r.top + 26), 11,
          Paint()..color = t.color.withOpacity(afford ? 1 : 0.4));
      _text(canvas, t.name, Offset(r.center.dx, r.bottom - 24),
          Colors.white.withOpacity(afford ? 0.95 : 0.4), 12,
          weight: FontWeight.w700);
      _text(canvas, '💰${t.cost}', Offset(r.center.dx, r.bottom - 9),
          const Color(0xFFFFD36B).withOpacity(afford ? 1 : 0.4), 12);
    }

    // aide
    if (g._slots.every((s) => s.turret == null)) {
      _text(
          canvas,
          'Glisse une tourelle sur un emplacement ○ · tape-la pour l\'améliorer',
          Offset(size.width / 2, size.height - 120),
          const Color(0xFF8FA0C8),
          12);
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
