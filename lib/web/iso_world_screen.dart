import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/world_layout.dart';

// Prototype « Monde isométrique » (?world=iso, après auth) — PHASE 1 : terrain.
// Réutilise la VRAIE génération de carte (buildWorld) sur tes domaines, et rend
// la grille WtTile avec les blocs pixel-art du pack Devil's Workshop (50×50).
// Tourelles / araignées / brouillard = phases suivantes.

const String _kBlockDir = 'assets/iso/assets_pixel_50x50';

// Mapping WtTile → index de bloc (PROVISOIRE — ajustable d'une ligne).
const Map<WtTile, int> _kTileBlock = {
  WtTile.terrain: 0, // herbe
  WtTile.garden: 6, // jardin (vert/turquoise)
  WtTile.wall: 52, // pierre
  WtTile.castle: 73, // brique brune
  WtTile.bridge: 72, // dalles
  WtTile.village: 21, // terre
  WtTile.chest: 0,
};

// Géométrie du tuilage iso (mesurée sur les sprites 50×50).
const double _kBlock = 50;
const double _kStepX = 21; // demi-largeur du losange
const double _kStepY = 36; // pas vertical (hauteur de cube visible)
const double _kAnchorX = 24.5; // centre x du losange dans le sprite
const double _kAnchorY = 37; // y du losange dans le sprite
const double _kPad = 24;

class IsoWorldScreen extends StatefulWidget {
  final FirestoreSync sync;
  const IsoWorldScreen({super.key, required this.sync});

  @override
  State<IsoWorldScreen> createState() => _IsoWorldScreenState();
}

class _IsoWorldScreenState extends State<IsoWorldScreen> {
  WorldLayout? _world;
  final Map<int, ui.Image> _imgs = {};
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
      final world = buildWorld(_buildSpecs(logic));

      final needed = <int>{..._kTileBlock.values};
      for (final idx in needed) {
        _imgs[idx] = await _loadBlock(idx);
      }
      if (mounted) setState(() => _world = world);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  List<DomainSpec> _buildSpecs(AppLogic logic) {
    final out = <DomainSpec>[];
    for (final d in logic.state.activeDomains) {
      final routines = <String>[];
      final acts = <String>[];
      for (final a in logic.state.activeActivities) {
        if (a.domainId != d.id) continue;
        if (a.isHabit) {
          routines.add(a.id);
        } else {
          acts.add(a.id);
        }
      }
      out.add(DomainSpec(
        domainId: d.id,
        colorValue: d.colorValue,
        routineIds: routines,
        activityIds: acts,
      ));
    }
    return out;
  }

  Future<ui.Image> _loadBlock(int idx) async {
    final name = 'isometric_pixel_${idx.toString().padLeft(4, '0')}.png';
    final data = await rootBundle.load('$_kBlockDir/$name');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C1830),
        body: Center(
          child: Text('Erreur : $_error',
              style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final world = _world;
    if (world == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0C1830),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final w = (world.cols + world.rows - 2) * _kStepX + _kBlock + 2 * _kPad;
    final h = (world.cols + world.rows - 2) * _kStepY + _kBlock + 2 * _kPad;

    return Scaffold(
      backgroundColor: const Color(0xFF0C1830),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              constrained: false,
              minScale: 0.4,
              maxScale: 4,
              boundaryMargin: const EdgeInsets.all(400),
              child: SizedBox(
                width: w,
                height: h,
                child: CustomPaint(painter: _IsoPainter(world, _imgs)),
              ),
            ),
          ),
          Positioned(
            left: 20,
            top: 52,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Le Monde — iso · ${world.cols}×${world.rows} · pince pour zoomer',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IsoPainter extends CustomPainter {
  _IsoPainter(this.world, this.imgs);
  final WorldLayout world;
  final Map<int, ui.Image> imgs;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    final ox = (world.rows - 1) * _kStepX + _kAnchorX + _kPad;
    final oy = _kAnchorY + _kPad;

    // ordre peintre : par diagonale croissante (x + y)
    final maxSum = world.cols + world.rows - 2;
    for (var sum = 0; sum <= maxSum; sum++) {
      final xMin = (sum - (world.rows - 1)).clamp(0, world.cols - 1);
      final xMax = sum.clamp(0, world.cols - 1);
      for (var x = xMin; x <= xMax; x++) {
        final y = sum - x;
        if (y < 0 || y >= world.rows) continue;
        final idx = _kTileBlock[world.at(x, y)] ?? 0;
        final img = imgs[idx];
        if (img == null) continue;
        final sx = ox + (x - y) * _kStepX;
        final sy = oy + (x + y) * _kStepY;
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(sx - _kAnchorX, sy - _kAnchorY, _kBlock, _kBlock),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IsoPainter old) =>
      old.world != world || old.imgs != imgs;
}
