import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/territory.dart';
import 'package:productivitwo_v1/unified_world.dart';

// MONDE UNIFIÉ — Tranche 0 : la grande carte traversable à l'avatar (farm gauche ·
// château centre · grottes droite). On marche, le brouillard se lève autour de soi,
// les 4 grottes affichent leur niveau lu depuis `territories/{uid}` (read-only ici ;
// défendre = T1, invasion spatiale = T2). État de marche LOCAL (la persistance est
// tranchée en T4) ; seules les grottes viennent du doc persisté.

const _kBg = Color(0xFF0E0A0A);
const _kBlue = Color(0xFF3B82F6); // grotte à moi
const _kGold = Color(0xFFD4A017); // château
const _kEnemy = Color(0xFFFF2B2B); // grotte prise
const _kFarm = Color(0xFF22C55E); // accent zone farm

const int _kReveal = 2; // rayon de brouillard levé autour de l'avatar (Chebyshev)

Future<void> showUnifiedWorldSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.65),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(10),
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: _UnifiedWorldView(logic: logic, sync: sync),
      ),
    ),
  );
}

class _UnifiedWorldView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _UnifiedWorldView({required this.logic, required this.sync});

  @override
  State<_UnifiedWorldView> createState() => _UnifiedWorldViewState();
}

class _UnifiedWorldViewState extends State<_UnifiedWorldView> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;

  Territory? _t;
  UnifiedWorld? _w;
  bool _loading = true;
  bool _busy = false;
  StreamSubscription<Territory?>? _sub;

  // État de marche LOCAL (éphémère en T0).
  late Point<int> _pos;
  final Set<String> _revealed = {};

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await sync.ensureTerritory('Toi');
    final me = sync.uid ?? '';
    _sub = sync.streamTerritory(me).listen((t) {
      if (!mounted) return;
      setState(() {
        _t = t;
        _loading = false;
        // Génère la map une fois (seed du territoire → déterministe/spectatable).
        if (_w == null && t != null) {
          _w = generateUnifiedWorld(t.seed);
          _pos = _w!.start;
          _revealAround(_pos);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _revealAround(Point<int> p) {
    final w = _w;
    if (w == null) return;
    for (var dy = -_kReveal; dy <= _kReveal; dy++) {
      for (var dx = -_kReveal; dx <= _kReveal; dx++) {
        final nx = p.x + dx, ny = p.y + dy;
        if (w.inBounds(nx, ny)) _revealed.add('${nx}_$ny');
      }
    }
  }

  List<Point<int>> _ortho(int x, int y) {
    final w = _w!;
    return [
      Point(x + 1, y),
      Point(x - 1, y),
      Point(x, y + 1),
      Point(x, y - 1),
    ].where((p) => w.walkable(p.x, p.y)).toList();
  }

  // BFS sur cases révélées + walkable (on ne traverse pas le brouillard).
  List<Point<int>> _bfsPath(Point<int> from, Point<int> to) {
    if (from == to) return const [];
    final startId = '${from.x}_${from.y}';
    final goalId = '${to.x}_${to.y}';
    final prev = <String, String?>{startId: null};
    final queue = <Point<int>>[from];
    var i = 0;
    while (i < queue.length) {
      final cur = queue[i++];
      if ('${cur.x}_${cur.y}' == goalId) break;
      for (final n in _ortho(cur.x, cur.y)) {
        final nid = '${n.x}_${n.y}';
        if (prev.containsKey(nid) || !_revealed.contains(nid)) continue;
        prev[nid] = '${cur.x}_${cur.y}';
        queue.add(n);
      }
    }
    if (!prev.containsKey(goalId)) return const [];
    final path = <Point<int>>[];
    var cur = goalId;
    while (cur != startId) {
      final s = cur.split('_');
      path.add(Point(int.parse(s[0]), int.parse(s[1])));
      cur = prev[cur]!;
    }
    return path.reversed.toList();
  }

  Future<void> _walkPath(List<Point<int>> path) async {
    setState(() => _busy = true);
    for (final p in path) {
      if (!mounted) break;
      _step(p);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (mounted) setState(() => _busy = false);
  }

  void _step(Point<int> to) {
    setState(() {
      _pos = to;
      _revealAround(to);
    });
    _announce(to);
  }

  // T0 = simples repères (la défense/le combat arrivent en T1/T2).
  void _announce(Point<int> to) {
    final w = _w, t = _t;
    if (w == null || t == null) return;
    if (to == w.castle) {
      _toast('🏰 Château — le cœur de ta map (à défendre).', _kGold);
      return;
    }
    final id = w.caveIdAt(to.x, to.y);
    if (id != null) {
      final c = t.caveById(id);
      final mine = c != null && c.ownerUid == t.uid;
      _toast(
          '🕳️ Grotte ${id.toUpperCase()} — ${mine ? 'à toi' : 'prise'} · niv ${c?.blueLevel ?? 0}'
          ' (défendre : bientôt).',
          mine ? _kBlue : _kEnemy);
    }
  }

  void _onTap(int x, int y) {
    final w = _w;
    if (_busy || w == null) return;
    final p = _pos;
    if (x == p.x && y == p.y) return;
    if (!w.walkable(x, y)) {
      _toast('🧱 Un mur bloque ce passage.', Colors.white38);
      return;
    }
    final id = '${x}_$y';
    final adjacent = (x - p.x).abs() + (y - p.y).abs() == 1;
    if (!adjacent) {
      if (!_revealed.contains(id)) return;
      final path = _bfsPath(p, Point(x, y));
      if (path.isEmpty) {
        _toast('🌫️ Chemin bloqué par le brouillard.', Colors.white38);
        return;
      }
      _walkPath(path);
      return;
    }
    _step(Point(x, y));
  }

  void _toast(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400)));
  }

  @override
  Widget build(BuildContext context) {
    final t = _t, w = _w;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
        child: Row(children: [
          const Text('🗺️ Monde',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(width: 8),
          Text('farm · château · territoire',
              style: TextStyle(color: Colors.white.withOpacity(.4), fontSize: 11)),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Flexible(
        child: (_loading || t == null || w == null)
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: _kBlue)))
            : _content(t, w),
      ),
    ]);
  }

  Widget _content(Territory t, UnifiedWorld w) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _zonesLegend(),
        const SizedBox(height: 12),
        _board(t, w),
        const SizedBox(height: 12),
        Text(
          'Déplace ton avatar : touche une case éclairée. Le brouillard se lève '
          'autour de toi. Va farmer à gauche, défendre tes grottes à droite '
          '(bientôt jouable), le château au centre.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(.45), fontSize: 11),
        ),
      ],
    );
  }

  Widget _zonesLegend() {
    Widget item(String emoji, String label, Color c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: c, fontSize: 11)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        item('🏹', 'Farm (gauche)', _kFarm),
        item('🏰', 'Château', _kGold),
        item('🕳️', 'Grottes (droite)', _kBlue),
      ],
    );
  }

  Widget _board(Territory t, UnifiedWorld w) {
    final avatar = logic.state.activeAvatar ?? '🧍';
    return LayoutBuilder(builder: (context, c) {
      final slot = (c.maxWidth / w.cols).clamp(20.0, 44.0);
      final inner = slot - 3;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int y = 0; y < w.rows; y++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (int x = 0; x < w.cols; x++)
                  _cell(t, w, x, y, inner, avatar),
              ]),
          ],
        ),
      );
    });
  }

  Widget _cell(
      Territory t, UnifiedWorld w, int x, int y, double inner, String avatar) {
    final id = '${x}_$y';
    final revealed = _revealed.contains(id);
    final isAvatar = _pos.x == x && _pos.y == y;

    // Hors vision : brouillard noir, non tappable.
    if (!revealed) {
      return Container(
        width: inner,
        height: inner,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.55),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white.withOpacity(.04)),
        ),
      );
    }

    final kind = w.at(x, y);
    Color bg = Colors.white.withOpacity(.03);
    Color border = Colors.white.withOpacity(.05);
    Widget? child;

    if (kind == UwTile.floor) {
      // Teinte la zone farm (gauche du château) en vert discret.
      final farmSide = x < w.castle.x - 1;
      bg = (farmSide ? _kFarm : Colors.white).withOpacity(.08);
      border = (farmSide ? _kFarm : Colors.white).withOpacity(.12);
    } else if (kind == UwTile.castle) {
      bg = _kGold.withOpacity(.22);
      border = _kGold.withOpacity(.7);
      child = Text('🏰', style: TextStyle(fontSize: inner * 0.5));
    }

    // Grotte (overlay depuis le doc territoire).
    final caveId = w.caveIdAt(x, y);
    if (caveId != null) {
      final cave = t.caveById(caveId);
      final mine = cave != null && cave.ownerUid == t.uid;
      final col = mine ? _kBlue : _kEnemy;
      bg = col.withOpacity(.22);
      border = col.withOpacity(.7);
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🕳️', style: TextStyle(fontSize: inner * 0.36)),
          Text('${cave?.blueLevel ?? 0}',
              style: TextStyle(
                  color: col,
                  fontSize: inner * 0.26,
                  fontWeight: FontWeight.w900,
                  height: 1)),
        ],
      );
    }

    final tile = Container(
      width: inner,
      height: inner,
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: isAvatar ? Colors.white.withOpacity(.16) : bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
            color: isAvatar ? Colors.white : border, width: isAvatar ? 2 : 1),
      ),
      alignment: Alignment.center,
      child: isAvatar
          ? Text(avatar, style: TextStyle(fontSize: inner * 0.55))
          : child,
    );

    return GestureDetector(onTap: () => _onTap(x, y), child: tile);
  }
}
