import 'dart:math';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/world_organic.dart';
import 'package:productivitwo_v1/world_map_gen.dart';

// CARTE ORGANIQUE CONTEMPLATIVE (?map=organic, après auth). Premier jet « vieille
// carte » type deepnight : génère l'overworld depuis TES domaines (régions ∝ poids),
// adoucit les côtes + classe les biomes (world_organic.dart), puis rend un parchemin
// (fond crème, littoral encré, reliefs/forêts semés, noms de contrées). Purement
// visuel — aucune fonction calendrier/combat ici (cohabite avec la carte actuelle,
// le temps de migrer). Pan + zoom via InteractiveViewer.
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
        backgroundColor: _kParchment,
        body: Center(
            child: Text('Erreur : $_error',
                style: const TextStyle(color: Color(0xFF5B4A30)))),
      );
    }
    final map = _map;
    if (map == null) {
      return const Scaffold(
        backgroundColor: _kParchment,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF5B4A30))),
      );
    }
    final w = map.cols * _kTile, h = map.rows * _kTile;
    return Scaffold(
      backgroundColor: _kSea,
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
                color: const Color(0xFF5B4A30).withOpacity(.85),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Contrées · ${map.regions.length} domaines · '
              '${map.cols}×${map.rows} · pince/molette = zoom · glisser = déplacer',
              style: const TextStyle(color: Color(0xFFF1E8D2), fontSize: 12),
            ),
          ),
        ),
      ]),
    );
  }
}

const double _kTile = 20;
const Color _kParchment = Color(0xFFE9DEC6);
const Color _kSea = Color(0xFF98B9C9);
const Color _kInk = Color(0xFF5B4A30);

const Map<OrganicBiome, Color> _kBiome = {
  OrganicBiome.water: _kSea,
  OrganicBiome.shore: Color(0xFFE2D2A6),
  OrganicBiome.plain: Color(0xFFC3CE9B),
  OrganicBiome.forest: Color(0xFF9DBA80),
  OrganicBiome.hills: Color(0xFFCBB98C),
  OrganicBiome.mountain: Color(0xFFC3B9A8),
};

class _OrganicMapPainter extends CustomPainter {
  _OrganicMapPainter(this.map, this.names);
  final OrganicMap map;
  final Map<String, String> names;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    // 1) Mer + parchemin de fond (la mer déborde, le parchemin n'est visible que
    //    là où il y aura de la terre — l'effet « carte posée sur l'océan »).
    p.color = _kSea;
    canvas.drawRect(Offset.zero & size, p);

    // 2) Terres par biome, teintées vers la couleur du domaine (identité de contrée).
    final tint = <String, Color>{
      for (final r in map.regions)
        r.domainId: r.colorValue != null ? Color(r.colorValue!) : const Color(0xFF6E9BD6)
    };
    for (var y = 0; y < map.rows; y++) {
      for (var x = 0; x < map.cols; x++) {
        final o = map.ownerAt(x, y);
        if (o == null) continue;
        final base = _kBiome[map.biomeAt(x, y)] ?? _kParchment;
        p.color = _blend(base, tint[o] ?? base, 0.22);
        canvas.drawRect(
            Rect.fromLTWH(x * _kTile, y * _kTile, _kTile + .6, _kTile + .6), p);
      }
    }

    // 3) Littoral encré : chaque arête terre↔eau (ou bord de map) tracée à l'encre.
    final coast = Paint()
      ..color = _kInk
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (var y = 0; y < map.rows; y++) {
      for (var x = 0; x < map.cols; x++) {
        if (!map.isLand(x, y)) continue;
        final l = x * _kTile, t = y * _kTile, r = l + _kTile, b = t + _kTile;
        if (!map.isLand(x - 1, y)) canvas.drawLine(Offset(l, t), Offset(l, b), coast);
        if (!map.isLand(x + 1, y)) canvas.drawLine(Offset(r, t), Offset(r, b), coast);
        if (!map.isLand(x, y - 1)) canvas.drawLine(Offset(l, t), Offset(r, t), coast);
        if (!map.isLand(x, y + 1)) canvas.drawLine(Offset(l, b), Offset(r, b), coast);
      }
    }

    // 4) Frontières internes entre contrées (terre↔terre d'owner différent) : trait
    //    fin et discret, façon délimitation à la plume.
    final border = Paint()
      ..color = _kInk.withOpacity(.30)
      ..strokeWidth = 1.0;
    for (var y = 0; y < map.rows; y++) {
      for (var x = 0; x < map.cols; x++) {
        final o = map.ownerAt(x, y);
        if (o == null) continue;
        final l = x * _kTile, t = y * _kTile, r = l + _kTile, b = t + _kTile;
        final or = map.ownerAt(x + 1, y);
        if (or != null && or != o) canvas.drawLine(Offset(r, t), Offset(r, b), border);
        final ob = map.ownerAt(x, y + 1);
        if (ob != null && ob != o) canvas.drawLine(Offset(l, b), Offset(r, b), border);
      }
    }

    // 5) Reliefs/forêts semés (déterministe par case) : montagnes, collines, arbres.
    for (var y = 0; y < map.rows; y++) {
      for (var x = 0; x < map.cols; x++) {
        final cx = x * _kTile + _kTile / 2, cy = y * _kTile + _kTile / 2;
        final hsh = ((x * 73856093) ^ (y * 19349663)) & 0x7fffffff;
        switch (map.biomeAt(x, y)) {
          case OrganicBiome.mountain:
            _mountain(canvas, cx, cy);
            break;
          case OrganicBiome.hills:
            if (hsh % 100 < 55) _hill(canvas, cx, cy);
            break;
          case OrganicBiome.forest:
            if (hsh % 100 < 60) {
              final jx = (hsh % 7 - 3).toDouble();
              final jy = ((hsh >> 3) % 7 - 3).toDouble();
              _tree(canvas, cx + jx, cy + jy);
            }
            break;
          default:
            break;
        }
      }
    }

    // 6) Noms des contrées au centre, plume sépia avec halo parchemin (lisibilité).
    for (final r in map.regions) {
      if (r.size < 6) continue;
      final label = names[r.domainId] ?? r.domainId;
      _label(canvas, label.toUpperCase(),
          Offset(r.center.x * _kTile + _kTile / 2, r.center.y * _kTile + _kTile / 2));
    }
  }

  void _mountain(Canvas canvas, double cx, double cy) {
    final s = _kTile * 0.42;
    final path = Path()
      ..moveTo(cx - s, cy + s * 0.7)
      ..lineTo(cx, cy - s)
      ..lineTo(cx + s, cy + s * 0.7)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF8B8273));
    canvas.drawPath(
        path,
        Paint()
          ..color = _kInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4);
    // arête neigeuse
    canvas.drawLine(Offset(cx, cy - s), Offset(cx - s * 0.3, cy - s * 0.1),
        Paint()..color = const Color(0xFFF1E8D2)..strokeWidth = 1.4);
  }

  void _hill(Canvas canvas, double cx, double cy) {
    final s = _kTile * 0.34;
    final rect = Rect.fromCircle(center: Offset(cx, cy + s * 0.3), radius: s);
    canvas.drawArc(rect, pi, pi, false,
        Paint()
          ..color = _kInk.withOpacity(.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3);
  }

  void _tree(Canvas canvas, double cx, double cy) {
    final s = _kTile * 0.28;
    canvas.drawLine(Offset(cx, cy + s), Offset(cx, cy + s * 0.2),
        Paint()..color = const Color(0xFF6B5436)..strokeWidth = 1.6);
    final canopy = Path()
      ..moveTo(cx - s * 0.8, cy + s * 0.3)
      ..lineTo(cx, cy - s)
      ..lineTo(cx + s * 0.8, cy + s * 0.3)
      ..close();
    canvas.drawPath(canopy, Paint()..color = const Color(0xFF5E7E4A));
    canvas.drawPath(
        canopy,
        Paint()
          ..color = _kInk.withOpacity(.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);
  }

  void _label(Canvas canvas, String text, Offset center) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: _kInk,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pos = center - Offset(tp.width / 2, tp.height / 2);
    // halo : cartouche parchemin translucide derrière le texte.
    final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: center, width: tp.width + 12, height: tp.height + 6),
        const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = _kParchment.withOpacity(.72));
    tp.paint(canvas, pos);
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
