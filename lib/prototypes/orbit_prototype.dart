// Prototype gamification « Système orbital » — piste d'évaluation.
//
// Deux usages :
//  • Démo isolée : OrbitProtoApp (données simulées) — voir OrbitScreen plus bas.
//  • Données réelles : lib/web/orbit_data_screen.dart réutilise OrbitView.
//
// Métaphore : « Aujourd'hui » = le soleil. Chaque domaine de vie est une planète
// qui gravite autour. Plus tu y consacres du temps récemment, plus elle est
// attirée en orbite proche, chaude et lumineuse, et tourne vite. Sans activité,
// elle dérive vers l'extérieur, refroidit et ralentit.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

void main() => runApp(const OrbitProtoApp());

class OrbitProtoApp extends StatelessWidget {
  const OrbitProtoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Orbit Proto',
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const OrbitScreen(),
    );
  }
}

// ── Modèle d'une planète/domaine ────────────────────────────────────────────
class OrbitBody {
  OrbitBody({
    required this.name,
    required this.hot,
    required this.cold,
    required this.mass,
    required this.angle,
    required double days,
    required this.streak,
    this.totalLabel,
    this.ringed = false,
  })  : displayDays = days,
        targetDays = days;

  final String name;
  final Color hot; // couleur « nourri aujourd'hui »
  final Color cold; // couleur « délaissé »
  final double mass; // 0..1 → taille dessinée
  double angle; // position angulaire courante (rad)
  double displayDays; // valeur affichée (animée)
  double targetDays; // cible vers laquelle on tend
  int streak;
  final String? totalLabel; // ex. "6h20 / 30 j" (données réelles)
  final bool ringed; // anneau type Saturne (domaine le + investi)

  // Fenêtre de récence : au-delà, la planète est en bordure froide.
  static const double maxDays = 14;
  // Exposant > 1 : aujourd'hui/hier collent au soleil, la dérive s'accélère ensuite.
  static const double _driftCurve = 1.4;

  double get orbitT {
    final t = displayDays.clamp(0, maxDays) / maxDays;
    return math.pow(t, _driftCurve).toDouble();
  }

  double get warmth => 1 - orbitT;
  Color get color => Color.lerp(cold, hot, Curves.easeOut.transform(warmth))!;
  double get planetRadius => 15 + mass * 27;

  String get subtitle {
    if (totalLabel != null) {
      final r = displayDays < 0.6
          ? 'aujourd\'hui'
          : displayDays < 1.6
              ? 'hier'
              : '${displayDays.round()} j';
      final s = streak > 0 ? ' · 🔥$streak' : '';
      return '$r$s';
    }
    return displayDays < 0.4
        ? 'aujourd\'hui · 🔥$streak'
        : displayDays < 1.4
            ? 'il y a 1 j'
            : '${displayDays.round()} j · dérive';
  }
}

// ── Récompense flottante (« +1 ✦ ») ─────────────────────────────────────────
class _FloatReward {
  _FloatReward(this.pos, this.text);
  Offset pos;
  final String text;
  double life = 0;
}

// ── Vue orbitale animée réutilisable ────────────────────────────────────────
class OrbitView extends StatefulWidget {
  const OrbitView({
    super.key,
    required this.bodies,
    this.interactive = true,
    this.onTapBody,
  });

  final List<OrbitBody> bodies;
  final bool interactive; // true = tap nourrit (démo) ; false = tap = onTapBody
  final void Function(OrbitBody body)? onTapBody;

  @override
  State<OrbitView> createState() => OrbitViewState();
}

class OrbitViewState extends State<OrbitView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _twinkle = 0;

  final List<_FloatReward> _rewards = [];
  final List<_Star> _stars = _genStars(80);
  final Map<OrbitBody, double> _pulses = {};

  List<OrbitBody> get _bodies => widget.bodies;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.1) {
      setState(() {});
      return;
    }
    _twinkle += dt;
    for (final b in _bodies) {
      final speed = 0.07 + (1 - b.orbitT) * 0.45;
      b.angle += dt * speed;
      b.displayDays += (b.targetDays - b.displayDays) * math.min(1, dt * 3.2);
      if ((b.targetDays - b.displayDays).abs() < 0.01) {
        b.displayDays = b.targetDays;
      }
    }
    _pulses.updateAll((_, v) => v + dt * 1.6);
    _pulses.removeWhere((_, v) => v >= 1);
    for (final r in _rewards) {
      r.life += dt * 0.9;
      r.pos = Offset(r.pos.dx, r.pos.dy - dt * 42);
    }
    _rewards.removeWhere((r) => r.life >= 1);
    setState(() {});
  }

  void feed(OrbitBody b, Offset at) {
    b.targetDays = 0;
    b.streak += 1;
    _pulses[b] = 0;
    _rewards.add(_FloatReward(at.translate(0, -50), '+1 ✦'));
  }

  void feedColdest(Size size, Offset center) {
    final c = _bodies.reduce((a, b) => a.displayDays >= b.displayDays ? a : b);
    final geom = _layout(_bodies, center, size);
    feed(c, geom[c] ?? center);
  }

  void advanceDay() {
    for (final b in _bodies) {
      b.targetDays = (b.targetDays + 1).clamp(0, OrbitBody.maxDays).toDouble();
      if (b.targetDays > 0.5) b.streak = 0;
    }
  }

  void _handleTap(Offset tap, Offset center, Size size) {
    final geom = _layout(_bodies, center, size);
    for (final entry in geom.entries) {
      if ((entry.value - tap).distance <= entry.key.planetRadius + 18) {
        if (widget.interactive) {
          feed(entry.key, entry.value);
        } else {
          widget.onTapBody?.call(entry.key);
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final center = Offset(size.width / 2, size.height * 0.46);
      return GestureDetector(
        onTapUp: (d) => _handleTap(d.localPosition, center, size),
        child: CustomPaint(
          size: size,
          painter: _OrbitPainter(
            bodies: _bodies,
            center: center,
            twinkle: _twinkle,
            stars: _stars,
            rewards: _rewards,
            pulses: _pulses,
          ),
        ),
      );
    });
  }
}

// ── Écran démo (données simulées) ───────────────────────────────────────────
class OrbitScreen extends StatefulWidget {
  const OrbitScreen({super.key});
  @override
  State<OrbitScreen> createState() => _OrbitScreenState();
}

class _OrbitScreenState extends State<OrbitScreen> {
  final _viewKey = GlobalKey<OrbitViewState>();

  final List<OrbitBody> _bodies = [
    OrbitBody(
        name: 'Santé',
        hot: const Color(0xFFFFD36B),
        cold: const Color(0xFF7E85A0),
        mass: 1.0,
        angle: 0.2,
        days: 0.3,
        streak: 14,
        ringed: true),
    OrbitBody(
        name: 'Travail',
        hot: const Color(0xFF9CC6F0),
        cold: const Color(0xFF6A749A),
        mass: 0.8,
        angle: 2.5,
        days: 3.5,
        streak: 4),
    OrbitBody(
        name: 'Créativité',
        hot: const Color(0xFFE0A6FF),
        cold: const Color(0xFF6A749A),
        mass: 0.45,
        angle: 4.3,
        days: 8.0,
        streak: 1),
    OrbitBody(
        name: 'Relations',
        hot: const Color(0xFFFF9EC4),
        cold: const Color(0xFF767C96),
        mass: 0.6,
        angle: 5.6,
        days: 13.0,
        streak: 0),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0820),
      body: Stack(
        children: [
          Positioned.fill(child: OrbitView(key: _viewKey, bodies: _bodies)),
          Positioned(
            left: 24,
            top: 64,
            right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Aujourd\'hui',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                SizedBox(height: 4),
                Text('Touche une planète pour la nourrir',
                    style: TextStyle(fontSize: 15, color: Color(0xFFA99FD6))),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 40,
            child: Row(
              children: [
                Expanded(
                  child: _PillButton(
                    icon: Icons.bolt,
                    label: 'Nourrir le + froid',
                    bg: const Color(0xFFA78BFF),
                    fg: const Color(0xFF1A1640),
                    onTap: () => _viewKey.currentState?.feedColdest(
                        size, Offset(size.width / 2, size.height * 0.46)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PillButton(
                    icon: Icons.fast_forward,
                    label: 'Passer un jour',
                    bg: Colors.white.withOpacity(0.08),
                    fg: Colors.white,
                    onTap: () => _viewKey.currentState?.advanceDay(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Géométrie partagée (paint + hit-test) ───────────────────────────────────
Map<OrbitBody, Offset> _layout(
    List<OrbitBody> bodies, Offset center, Size size) {
  final innerR = size.width * 0.16;
  final outerR = size.width * 0.42;
  final res = <OrbitBody, Offset>{};
  for (final b in bodies) {
    final r = innerR + b.orbitT * (outerR - innerR);
    res[b] = Offset(
      center.dx + math.cos(b.angle) * r,
      center.dy + math.sin(b.angle) * r * 0.82,
    );
  }
  return res;
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.bodies,
    required this.center,
    required this.twinkle,
    required this.stars,
    required this.rewards,
    required this.pulses,
  });

  final List<OrbitBody> bodies;
  final Offset center;
  final double twinkle;
  final List<_Star> stars;
  final List<_FloatReward> rewards;
  final Map<OrbitBody, double> pulses;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // fond radial
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.15,
          colors: [Color(0xFF241D4A), Color(0xFF15112F), Color(0xFF09071F)],
          stops: [0, 0.5, 1],
        ).createShader(rect),
    );

    // nébuleuses douces (profondeur)
    _nebula(canvas, Offset(size.width * 0.78, size.height * 0.22),
        size.width * 0.5, const Color(0xFF6C4FD6), 0.16);
    _nebula(canvas, Offset(size.width * 0.18, size.height * 0.6),
        size.width * 0.45, const Color(0xFF3F7FD6), 0.12);

    // étoiles scintillantes
    for (final s in stars) {
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(twinkle * s.speed + s.phase));
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.r,
        Paint()..color = Colors.white.withOpacity(0.5 * tw),
      );
    }

    final innerR = size.width * 0.16;
    final outerR = size.width * 0.42;

    // anneaux d'orbite
    for (final t in const [0.15, 0.5, 0.85, 1.0]) {
      final r = innerR + t * (outerR - innerR);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: r * 2, height: r * 2 * 0.82),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withOpacity(0.07),
      );
    }
    final rh = innerR + 0.15 * (outerR - innerR);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rh * 2, height: rh * 2 * 0.82),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFC861).withOpacity(0.3),
    );

    // soleil « Aujourd'hui » — couronne qui respire
    final breath = 1 + 0.04 * math.sin(twinkle * 1.4);
    canvas.drawCircle(
      center,
      96 * breath,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Colors.white,
            Color(0xFFFFF0C2),
            Color(0xFFFFC861),
            Color(0x00FF8F4A),
          ],
          stops: [0, 0.25, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: 96 * breath)),
    );
    _text(canvas, 'AUJOURD\'HUI', center.translate(0, -8),
        color: const Color(0xFF5A3A14), size: 13, weight: FontWeight.w800);

    // planètes
    final geom = _layout(bodies, center, size);
    for (final b in bodies) {
      final pos = geom[b]!;
      final pr = b.planetRadius;

      // traînée de dérive (planètes froides)
      if (b.orbitT > 0.55) {
        final r = (pos - center).distance;
        final back = b.angle - 0.5;
        final tailEnd = Offset(
          center.dx + math.cos(back) * r * 1.05,
          center.dy + math.sin(back) * r * 1.05 * 0.82,
        );
        canvas.drawLine(
          pos,
          tailEnd,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = pr * 0.5
            ..strokeCap = StrokeCap.round
            ..color = b.cold.withOpacity(0.22 * b.orbitT),
        );
      }

      // anneau de pulse
      final pulse = pulses[b];
      if (pulse != null) {
        canvas.drawCircle(
          pos,
          pr + 10 + pulse * 40,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - pulse)
            ..color = b.hot.withOpacity(0.6 * (1 - pulse)),
        );
      }

      // glow
      canvas.drawCircle(
        pos,
        pr * 1.9,
        Paint()
          ..color = b.color.withOpacity(0.18 + b.warmth * 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );

      // anneau type Saturne (domaine le + investi)
      if (b.ringed) {
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(-0.45);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: pr * 4.2, height: pr * 1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = pr * 0.28
            ..color = b.color.withOpacity(0.55),
        );
        canvas.restore();
      }

      // corps
      canvas.drawCircle(
        pos,
        pr,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: [Color.lerp(Colors.white, b.color, 0.35)!, b.color],
          ).createShader(Rect.fromCircle(center: pos, radius: pr)),
      );
      canvas.drawCircle(pos.translate(-pr * 0.3, -pr * 0.35), pr * 0.16,
          Paint()..color = Colors.white.withOpacity(0.7));

      // libellés
      _text(canvas, b.name, pos.translate(0, pr + 18),
          color: b.color.withOpacity(0.95), size: 15, weight: FontWeight.w700);
      _text(canvas, b.subtitle, pos.translate(0, pr + 38),
          color: Colors.white.withOpacity(0.45), size: 12);
    }

    // vignette
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Colors.transparent, Colors.black.withOpacity(0.35)],
          stops: const [0.7, 1.0],
        ).createShader(rect),
    );

    // récompenses flottantes
    for (final r in rewards) {
      final op = (1 - r.life).clamp(0, 1).toDouble();
      _text(canvas, r.text, r.pos,
          color: const Color(0xFFFFE9A8).withOpacity(op),
          size: 22,
          weight: FontWeight.w800);
    }
  }

  void _nebula(Canvas c, Offset at, double r, Color col, double op) {
    c.drawCircle(
      at,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [col.withOpacity(op), col.withOpacity(0)],
        ).createShader(Rect.fromCircle(center: at, radius: r)),
    );
  }

  void _text(Canvas canvas, String s, Offset at,
      {required Color color,
      required double size,
      FontWeight weight = FontWeight.w500}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style:
              TextStyle(color: color, fontSize: size, fontWeight: weight)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => true;
}

// ── Étoiles de fond ─────────────────────────────────────────────────────────
class _Star {
  _Star(this.x, this.y, this.r, this.phase, this.speed);
  final double x, y, r, phase, speed;
}

List<_Star> _genStars(int n) {
  final rnd = math.Random(42);
  return List.generate(
    n,
    (_) => _Star(
      rnd.nextDouble(),
      rnd.nextDouble(),
      0.6 + rnd.nextDouble() * 1.8,
      rnd.nextDouble() * math.pi * 2,
      0.6 + rnd.nextDouble() * 1.6,
    ),
  );
}

// ── Bouton pilule ───────────────────────────────────────────────────────────
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
