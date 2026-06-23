import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/world_organic.dart';
import 'package:productivitwo_v1/world_map_gen.dart';

// CARTE ORGANIQUE CONTEMPLATIVE (?map=organic, après auth). Rendu « monde de jeu »
// type deepnight (Smugglers Hideout) : génère l'overworld depuis TES domaines
// (régions ∝ poids), adoucit les côtes + classe les biomes (world_organic.dart),
// puis rend un monde luxuriant — côtes LISSES (masque metaball flouté/re‑durci),
// eau en dégradé de profondeur, plages, ombres portées, lumières chaudes, vignette.
// Purement visuel (aucune fonction calendrier/combat) — cohabite avec la carte
// actuelle le temps de migrer. Pan + zoom via InteractiveViewer.
class OrganicMapScreen extends StatefulWidget {
  final FirestoreSync sync;
  const OrganicMapScreen({super.key, required this.sync});

  @override
  State<OrganicMapScreen> createState() => _OrganicMapScreenState();
}

class _OrganicMapScreenState extends State<OrganicMapScreen> {
  OrganicMap? _map;
  Map<String, String> _names = const {};
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
      final names = {for (final d in logic.state.activeDomains) d.id: d.name};
      final map = buildOrganicMap(weights);
      if (mounted) {
        setState(() {
          _map = map;
          _names = names;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: _kDeep,
        body: Center(
            child: Text('Erreur : $_error',
                style: const TextStyle(color: Color(0xFFCFE3DA)))),
      );
    }
    final map = _map;
    if (map == null) {
      return const Scaffold(
        backgroundColor: _kDeep,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF7FB8A8))),
      );
    }
    final w = map.cols * _kTile, h = map.rows * _kTile;
    return Scaffold(
      backgroundColor: _kDeep,
      body: Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(
            minScale: 0.4,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(400),
            constrained: false,
            child: SizedBox(
              width: w,
              height: h,
              child: CustomPaint(painter: _OrganicMapPainter(map, _names)),
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(.45),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Contrées · ${map.regions.length} domaines · '
              '${map.cols}×${map.rows} · pince/molette = zoom · glisser = déplacer',
              style: const TextStyle(color: Color(0xFFE7F0EA), fontSize: 12),
            ),
          ),
        ),
      ]),
    );
  }
}

const double _kTile = 20;

// Palette naturaliste « monde de jeu » (deepnight) — eau teal sombre, terres vertes.
const Color _kDeep = Color(0xFF173F39); // grand large
const Color _kShallow = Color(0xFF6FB2A0); // haut‑fond (halo de côte)
const Color _kSand = Color(0xFFD8C58C); // plage

const Map<OrganicBiome, Color> _kBiome = {
  OrganicBiome.water: _kDeep,
  OrganicBiome.shore: Color(0xFFCBB783),
  OrganicBiome.plain: Color(0xFF6E9E54),
  OrganicBiome.forest: Color(0xFF4C7A41),
  OrganicBiome.hills: Color(0xFF8B9A58),
  OrganicBiome.mountain: Color(0xFF9A958A),
};

class _OrganicMapPainter extends CustomPainter {
  _OrganicMapPainter(this.map, this.names);
  final OrganicMap map;
  final Map<String, String> names;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final tint = <String, Color>{
      for (final r in map.regions)
        r.domainId: r.colorValue != null
            ? Color(r.colorValue!)
            : const Color(0xFF6E9BD6)
    };

    // 1) GRAND LARGE — dégradé vertical sombre (profondeur).
    canvas.drawRect(
        bounds,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B473F), Color(0xFF123430)],
          ).createShader(bounds));
    _waves(canvas, size);

    // 2) HAUT‑FOND — halo turquoise diffus autour des terres (eau peu profonde).
    _softHalo(canvas, bounds,
        color: _kShallow, sigma: _kTile * 1.7, grow: _kTile * 2.4, alpha: .55);
    // 3) OMBRE PORTÉE des terres sur l'eau (légèrement décalée vers le bas).
    _softHalo(canvas, bounds,
        color: const Color(0xFF06201C),
        sigma: _kTile * 0.9,
        grow: _kTile * 0.35,
        alpha: .40,
        offset: Offset(0, _kTile * 0.30));
    // 4) PLAGE — silhouette lisse, légèrement plus large que la terre.
    _gooeyLand(canvas, bounds,
        solid: _kSand, grow: _kTile * 0.62, sigma: _kTile * 0.75);
    // 5) TERRES — silhouette lisse, couleur de biome fondue + teinte domaine.
    _gooeyLand(canvas, bounds,
        sigma: _kTile * 0.62,
        colorOf: (x, y) {
          final o = map.ownerAt(x, y);
          final base = _kBiome[map.biomeAt(x, y)] ?? _kBiome[OrganicBiome.plain]!;
          return _blend(base, tint[o] ?? base, 0.16);
        });

    // 6) DÉTAILS semés (déterministe par case) : forêts + reliefs, posés sur la terre.
    _scatter(canvas);

    // 7) LUMIÈRES chaudes au cœur des contrées (foyers) + noms en lettres glow.
    for (final r in map.regions) {
      if (r.size < 4) continue;
      final c = Offset(
          r.center.x * _kTile + _kTile / 2, r.center.y * _kTile + _kTile / 2);
      _warmGlow(canvas, c, _kTile * 2.2);
    }
    for (final r in map.regions) {
      if (r.size < 6) continue;
      final label = names[r.domainId] ?? r.domainId;
      final c = Offset(
          r.center.x * _kTile + _kTile / 2, r.center.y * _kTile + _kTile / 2);
      _label(canvas, label, c, r.size);
    }

    // 8) VIGNETTE — assombrit les bords, concentre le regard.
    canvas.drawRect(
        bounds,
        Paint()
          ..shader = RadialGradient(
            center: Alignment.center,
            radius: 0.95,
            colors: [Colors.transparent, Colors.black.withOpacity(.45)],
            stops: const [0.62, 1.0],
          ).createShader(bounds));
  }

  // ── Masque « metaball » : terres floutées puis alpha re‑durci → côtes LISSES. ──
  // On flou un masque binaire de cases (imageFilter) PUIS on re‑seuille l'alpha
  // (colorFilter) : la silhouette devient organique, les couleurs de biome restent
  // fondues à l'intérieur. `grow` élargit (plage), `colorOf`/`solid` = remplissage.
  void _gooeyLand(Canvas canvas, Rect bounds,
      {Color Function(int x, int y)? colorOf,
      Color? solid,
      double grow = 0,
      double sigma = 12,
      Offset offset = Offset.zero}) {
    canvas.saveLayer(
        bounds, Paint()..colorFilter = ColorFilter.matrix(_threshMatrix(16, 132)));
    canvas.saveLayer(
        bounds,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
    final p = Paint();
    final s = _kTile + grow + 2;
    for (var y = 0; y < map.rows; y++) {
      for (var x = 0; x < map.cols; x++) {
        if (!map.isLand(x, y)) continue;
        p.color = solid ?? colorOf!(x, y);
        final cx = x * _kTile + _kTile / 2 + offset.dx;
        final cy = y * _kTile + _kTile / 2 + offset.dy;
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: s, height: s), p);
      }
    }
    canvas.restore();
    canvas.restore();
  }

  // Halo diffus (eau peu profonde, ombre) : masque flouté SANS re‑durcissement.
  void _softHalo(Canvas canvas, Rect bounds,
      {required Color color,
      required double sigma,
      required double grow,
      required double alpha,
      Offset offset = Offset.zero}) {
    canvas.saveLayer(bounds, Paint()..color = Colors.white.withOpacity(alpha));
    canvas.saveLayer(
        bounds,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
    final p = Paint()..color = color;
    final s = _kTile + grow + 2;
    for (var y = 0; y < map.rows; y++) {
      for (var x = 0; x < map.cols; x++) {
        if (!map.isLand(x, y)) continue;
        final cx = x * _kTile + _kTile / 2 + offset.dx;
        final cy = y * _kTile + _kTile / 2 + offset.dy;
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: s, height: s), p);
      }
    }
    canvas.restore();
    canvas.restore();
  }

  List<double> _threshMatrix(double steep, double t) => <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, steep, -steep * t, //
      ];

  void _warmGlow(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFE0A0).withOpacity(.32),
              const Color(0xFFFFE0A0).withOpacity(0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r))
          ..blendMode = BlendMode.plus);
  }

  void _waves(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF2C5C53).withOpacity(.5)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    for (var gy = 0; gy < map.rows; gy += 2) {
      for (var gx = 0; gx < map.cols; gx += 2) {
        final h = ((gx * 73856093) ^ (gy * 19349663)) & 0x7fffffff;
        if (h % 100 >= 22) continue;
        final x = gx * _kTile, y = gy * _kTile + _kTile / 2;
        final path = Path()
          ..moveTo(x, y)
          ..relativeQuadraticBezierTo(_kTile * 0.25, -2.2, _kTile * 0.5, 0)
          ..relativeQuadraticBezierTo(_kTile * 0.25, 2.2, _kTile * 0.5, 0);
        canvas.drawPath(path, p);
      }
    }
  }

  void _scatter(Canvas canvas) {
    for (var y = 0; y < map.rows; y++) {
      for (var x = 0; x < map.cols; x++) {
        final cx = x * _kTile + _kTile / 2, cy = y * _kTile + _kTile / 2;
        final h = ((x * 73856093) ^ (y * 19349663)) & 0x7fffffff;
        final jx = (h % 7 - 3).toDouble(), jy = ((h >> 3) % 7 - 3).toDouble();
        switch (map.biomeAt(x, y)) {
          case OrganicBiome.mountain:
            _mountain(canvas, cx + jx, cy + jy);
            break;
          case OrganicBiome.forest:
            if (h % 100 < 68) _tree(canvas, cx + jx, cy + jy, 1 + (h % 5) * 0.06);
            break;
          case OrganicBiome.hills:
            if (h % 100 < 30) _bush(canvas, cx + jx, cy + jy);
            break;
          case OrganicBiome.plain:
            if (h % 100 < 10) _bush(canvas, cx + jx, cy + jy);
            break;
          default:
            break;
        }
      }
    }
  }

  void _tree(Canvas canvas, double cx, double cy, double scale) {
    final s = _kTile * 0.30 * scale;
    // ombre douce au sol
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx + 1.5, cy + s * 0.9), width: s * 1.4, height: s * 0.6),
        Paint()..color = Colors.black.withOpacity(.16));
    canvas.drawLine(Offset(cx, cy + s), Offset(cx, cy + s * 0.1),
        Paint()..color = const Color(0xFF5C4A30)..strokeWidth = 1.6);
    final canopy = Path()
      ..moveTo(cx - s * 0.85, cy + s * 0.35)
      ..lineTo(cx, cy - s)
      ..lineTo(cx + s * 0.85, cy + s * 0.35)
      ..close();
    canvas.drawPath(canopy, Paint()..color = const Color(0xFF3E6233));
    canvas.drawPath(
        canopy,
        Paint()
          ..color = const Color(0xFF2C4824)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
  }

  void _bush(Canvas canvas, double cx, double cy) {
    canvas.drawCircle(Offset(cx, cy), _kTile * 0.16,
        Paint()..color = const Color(0xFF4F7340));
  }

  void _mountain(Canvas canvas, double cx, double cy) {
    final s = _kTile * 0.42;
    final path = Path()
      ..moveTo(cx - s, cy + s * 0.7)
      ..lineTo(cx, cy - s)
      ..lineTo(cx + s, cy + s * 0.7)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF7C7468));
    canvas.drawLine(Offset(cx, cy - s), Offset(cx - s * 0.32, cy - s * 0.05),
        Paint()..color = const Color(0xFFE8E2D2)..strokeWidth = 1.5);
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF4A4339)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);
  }

  void _label(Canvas canvas, String text, Offset center, int regionSize) {
    final fontSize = (11 + sqrt(regionSize) * 0.5).clamp(12, 22).toDouble();
    final tp = TextPainter(
      text: TextSpan(
        text: text.toUpperCase(),
        style: TextStyle(
          color: const Color(0xFFF3ECD6),
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
          letterSpacing: 2.5,
          shadows: const [
            Shadow(blurRadius: 10, color: Colors.black87),
            Shadow(blurRadius: 3, color: Colors.black),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  Color _blend(Color a, Color b, double t) => Color.fromARGB(
        255,
        (a.red + (b.red - a.red) * t).round(),
        (a.green + (b.green - a.green) * t).round(),
        (a.blue + (b.blue - a.blue) * t).round(),
      );

  @override
  bool shouldRepaint(covariant _OrganicMapPainter old) =>
      old.map != map || old.names != names;
}
