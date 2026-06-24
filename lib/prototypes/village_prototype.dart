// Prototype gamification « Village » — premier jouable (dessiné en code).
//
// Boucle (option A, auto) : chaque action réelle (séance loggée / routine
// cochée) dépose un élément PERMANENT dans ton monde. Une séance → une maison
// (couleur du domaine) ; une routine → un arbre. Le village s'accumule au fil
// de ton historique et « se bâtit » à l'écran au chargement ; la dernière
// action scintille. Tu reviens pour voir ton monde grandir.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

void main() => runApp(const VillageProtoApp());

class VillageProtoApp extends StatelessWidget {
  const VillageProtoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Village Proto',
      theme: ThemeData(useMaterial3: true),
      home: const VillageScreen(),
    );
  }
}

enum BuildKind { house, tree }

class VillageElement {
  const VillageElement(this.kind, this.color);
  final BuildKind kind;
  final Color color; // couleur du domaine (maison) ; vert (arbre)
}

const double _kGolden = 2.399963229728653;

// ── Vue village animée réutilisable ─────────────────────────────────────────
class VillageView extends StatefulWidget {
  const VillageView({
    super.key,
    required this.elements, // ordre chronologique (ancien → récent)
    required this.todayCount,
    this.cappedFrom = 0, // >0 = n'affiche que les plus récents (info UI)
  });
  final List<VillageElement> elements;
  final int todayCount;
  final int cappedFrom;

  @override
  State<VillageView> createState() => _VillageViewState();
}

class _VillageViewState extends State<VillageView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _t = 0;

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

  void _tick(Duration e) {
    final dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (dt > 0 && dt < 0.1) _t += dt;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.elements.length;
    return Stack(children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _VillagePainter(widget.elements, _t),
        ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ton village',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3B4A2E))),
              const SizedBox(height: 2),
              Text(
                '$total construction${total > 1 ? 's' : ''}'
                '${widget.todayCount > 0 ? ' · +${widget.todayCount} aujourd\'hui 🌱' : ''}'
                '${widget.cappedFrom > 0 ? ' (les ${total} plus récentes sur ${widget.cappedFrom})' : ''}',
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF5C6B45), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _VillagePainter extends CustomPainter {
  _VillagePainter(this.elements, this.t);
  final List<VillageElement> elements;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // herbe (dégradé chaud)
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFBFE39A), Color(0xFFA6D67F), Color(0xFF8FC86C)],
        ).createShader(rect),
    );
    // taches d'herbe plus claires (texture)
    final patch = Paint()..color = const Color(0xFFCDEBAA).withOpacity(0.5);
    for (var i = 0; i < 9; i++) {
      final a = i * 2.2, r = 60.0 + i * 47 % 240;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(size.width / 2 + math.cos(a) * r,
                size.height / 2 + math.sin(a) * r * 0.7),
            width: 120,
            height: 70),
        patch,
      );
    }

    final center = Offset(size.width / 2, size.height * 0.52);
    final total = elements.length;
    if (total == 0) {
      _text(canvas, 'Logue une séance ou une routine\npour poser ta première pierre 🌱',
          center, const Color(0xFF4C5B35), 16, center: true);
      return;
    }

    // rayon de la spirale (phyllotaxie) → auto-fit dans l'écran
    final spiralR = 14 + 13.5 * math.sqrt(total.toDouble());
    final target = math.min(size.width, size.height) * 0.40;
    final fit = (target / spiralR).clamp(0.25, 1.25);

    // positions + reveal échelonné
    final revealDur = 1.6;
    final items = <_Placed>[];
    for (var i = 0; i < total; i++) {
      final rr = (14 + 13.5 * math.sqrt(i.toDouble())) * fit;
      final ang = i * _kGolden;
      final pos = center +
          Offset(math.cos(ang) * rr, math.sin(ang) * rr * 0.72); // léger aplatis
      final appear = (i / total) * revealDur * 0.7;
      final sc =
          Curves.easeOutBack.transform(((t - appear) / 0.35).clamp(0.0, 1.0));
      items.add(_Placed(i, pos, sc, elements[i]));
    }
    // ordre peintre : du fond vers l'avant (y croissant)
    items.sort((a, b) => a.pos.dy.compareTo(b.pos.dy));

    for (final p in items) {
      if (p.scale <= 0.01) continue;
      final s = p.scale * fit;
      if (p.el.kind == BuildKind.house) {
        _house(canvas, p.pos, s, p.el.color);
      } else {
        _tree(canvas, p.pos, s, p.idx);
      }
    }

    // scintillement sur la dernière construction
    final lastIdx = total - 1;
    final last = items.firstWhere((p) => p.idx == lastIdx);
    if (last.scale > 0.6) {
      for (var k = 0; k < 4; k++) {
        final ph = (t * 1.2 + k * 0.25) % 1;
        final a = -math.pi / 2 + (k - 1.5) * 0.7;
        final d = ph * 26 * fit;
        canvas.drawCircle(
          last.pos.translate(math.cos(a) * d, -20 * fit - math.sin(a).abs() * d),
          (1 - ph) * 3 + 0.5,
          Paint()..color = const Color(0xFFFFE08A).withOpacity(1 - ph),
        );
      }
    }

    // vignette douce
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 1.0,
          colors: [Colors.transparent, const Color(0xFF3B4A2E).withOpacity(0.18)],
          stops: const [0.72, 1],
        ).createShader(rect),
    );
  }

  void _house(Canvas c, Offset o, double s, Color color) {
    final w = 30 * s, h = 24 * s;
    // ombre
    c.drawOval(
      Rect.fromCenter(center: o.translate(0, 2 * s), width: w * 1.25, height: h * 0.5),
      Paint()..color = Colors.black.withOpacity(0.12),
    );
    // corps
    final body = Rect.fromCenter(
        center: o.translate(0, -h * 0.35), width: w, height: h);
    c.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(4 * s)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(Colors.white, color, 0.45)!, color],
        ).createShader(body),
    );
    // toit
    final roof = Path()
      ..moveTo(o.dx - w * 0.62, o.dy - h * 0.85)
      ..lineTo(o.dx, o.dy - h * 1.55)
      ..lineTo(o.dx + w * 0.62, o.dy - h * 0.85)
      ..close();
    c.drawPath(roof, Paint()..color = _shade(color, 0.62));
    // porte
    final door = Rect.fromCenter(
        center: o.translate(0, -h * 0.18), width: w * 0.26, height: h * 0.5);
    c.drawRRect(RRect.fromRectAndRadius(door, Radius.circular(2 * s)),
        Paint()..color = _shade(color, 0.45));
    // fenêtre
    c.drawCircle(o.translate(w * 0.26, -h * 0.55), 2.4 * s,
        Paint()..color = const Color(0xFFFFF1C2));
  }

  void _tree(Canvas c, Offset o, double s, int idx) {
    final sway = math.sin(t * 1.4 + idx) * 1.4 * s;
    // ombre
    c.drawOval(
      Rect.fromCenter(center: o.translate(0, 2 * s), width: 26 * s, height: 9 * s),
      Paint()..color = Colors.black.withOpacity(0.12),
    );
    // tronc
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: o.translate(0, -8 * s), width: 5 * s, height: 16 * s),
          Radius.circular(2 * s)),
      Paint()..color = const Color(0xFF8A5A33),
    );
    // feuillage
    final top = o.translate(sway, -22 * s);
    for (final off in const [
      [0.0, 0.0, 13.0],
      [-9.0, 4.0, 9.0],
      [9.0, 4.0, 10.0],
      [0.0, -8.0, 9.0]
    ]) {
      c.drawCircle(top.translate(off[0] * s, off[1] * s), off[2] * s,
          Paint()..color = const Color(0xFF5BA94E));
    }
    c.drawCircle(top.translate(-3 * s, -3 * s), 4 * s,
        Paint()..color = const Color(0xFF74C162));
  }

  Color _shade(Color col, double f) => Color.fromARGB(
        col.alpha,
        (col.red * f).round().clamp(0, 255),
        (col.green * f).round().clamp(0, 255),
        (col.blue * f).round().clamp(0, 255),
      );

  void _text(Canvas c, String s, Offset at, Color color, double size,
      {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color, fontSize: size, fontWeight: FontWeight.w700, height: 1.3)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 280);
    tp.paint(c, at - Offset(center ? tp.width / 2 : 0, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _VillagePainter old) => true;
}

class _Placed {
  _Placed(this.idx, this.pos, this.scale, this.el);
  final int idx;
  final Offset pos;
  final double scale;
  final VillageElement el;
}

// ── Écran démo (données simulées + bouton bâtir) ────────────────────────────
class VillageScreen extends StatefulWidget {
  const VillageScreen({super.key});
  @override
  State<VillageScreen> createState() => _VillageScreenState();
}

class _VillageScreenState extends State<VillageScreen> {
  final _rnd = math.Random(3);
  final List<VillageElement> _els = [];
  int _today = 0;

  static const _palette = [
    Color(0xFFFFB347),
    Color(0xFF8A6EF0),
    Color(0xFF4FD17A),
    Color(0xFF36C9C9),
    Color(0xFFFF5A47),
    Color(0xFFD06DE0),
  ];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 28; i++) {
      _els.add(_make());
    }
  }

  VillageElement _make() {
    final house = _rnd.nextBool();
    return VillageElement(
      house ? BuildKind.house : BuildKind.tree,
      house ? _palette[_rnd.nextInt(_palette.length)] : const Color(0xFF5BA94E),
    );
  }

  void _build() => setState(() {
        _els.add(_make());
        _today++;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          // clé sur la longueur → rejoue le reveal quand on ajoute
          child: VillageView(
              key: ValueKey(_els.length), elements: _els, todayCount: _today),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 36),
            child: GestureDetector(
              onTap: _build,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                decoration: BoxDecoration(
                    color: const Color(0xFF3B7D3A),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ]),
                child: const Text('Bâtir (simuler une action) 🔨',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
