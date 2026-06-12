import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/widgets/backlog_combat.dart';
import 'package:productivitwo_v1/widgets/confetti.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/expedition_sheet.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';

/// Overworld (Phase 1) : carte 2D explorable pour débloquer le prochain niveau.
/// Déplacement GRATUIT sur case éclairée ; brouillard = torche (révèle radius 2,
/// 1ʳᵉ du jour offerte) ; ≥2 chemins ; collectibles ; écosystème lié au % hebdo
/// (nuisibles si tendance ↓, bonus si ↑) ; château = déblocage (provisoire P1).

const _kGold = Color(0xFFD4A017);
const double _tile = 46;
const int _kTorchReveal = 2; // rayon éclairé par une torche (Chebyshev)

/// [huntLevel] non-null = MODE CHASSE : on (re)joue une carte débloquée comme
/// instance fraîche (brouillard plein, ennemis fiables, payante) pour farmer la
/// collection. L'état carte reste LOCAL/éphémère (pas de sync, pas d'impact sur
/// la progression ni sur le drain global) ; seuls l'or et la collection persistent.
Future<void> showExpeditionGame(
    BuildContext context, AppLogic logic, FirestoreSync sync,
    {int? huntLevel}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExpeditionGame(logic: logic, sync: sync, huntLevel: huntLevel),
  );
}

class _ExpeditionGame extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final int? huntLevel;
  const _ExpeditionGame(
      {required this.logic, required this.sync, this.huntLevel});
  @override
  State<_ExpeditionGame> createState() => _ExpeditionGameState();
}

class _ExpeditionGameState extends State<_ExpeditionGame> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;
  final _rng = Random();
  bool _busy = false;

  bool get _hunt => widget.huntLevel != null;

  // En chasse : niveau = la carte choisie. En progression : niveau visé = +1.
  int get _level =>
      _hunt ? widget.huntLevel! : logic.effectiveLevel() + 1;
  int get _mapLevel => _hunt ? widget.huntLevel! : logic.effectiveLevel();
  late final Overworld _map = generateOverworld(_level);

  // État LOCAL du mode chasse (éphémère, non synchronisé).
  final Set<String> _huntRevealed = {};
  final Set<String> _huntPicked = {};
  final List<String> _huntEntities = [];
  late Point<int> _huntPos = _map.start;

  /// Entités actives (nuisibles/bonus) de l'instance courante.
  List<String> get _ents =>
      _hunt ? _huntEntities : logic.state.expeditionEntities;

  Set<String> get _revealed =>
      _hunt ? _huntRevealed : logic.state.expeditionRevealed.toSet();
  Set<String> get _picked =>
      _hunt ? _huntPicked : logic.state.expeditionPicked.toSet();
  Point<int> get _pos {
    if (_hunt) return _huntPos;
    final p = logic.state.expeditionPos;
    if (p != null && p.contains('_')) {
      final s = p.split('_');
      return Point(int.parse(s[0]), int.parse(s[1]));
    }
    return _map.start;
  }

  String _ymd() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
  }

  // En chasse, pas de pas gratuit : chaque torche se paie (sink d'or assumé).
  bool get _freeStepAvailable =>
      !_hunt && logic.state.lastFreeStepYmd != _ymd();

  @override
  void initState() {
    super.initState();
    // Solde à jour des gains du jour : on doit pouvoir financer la carte de suite.
    logic.reconcileLiveGold(sync);

    if (_hunt) {
      // Chasse au backlog : carte fraîche peuplée d'un MAX de tes vrais items
      // (faciles près de l'entrée), en gardant un chemin praticable. Local/éphémère.
      _huntPos = _map.start;
      _huntRevealed.addAll(_neighbors(_map.start.x, _map.start.y,
              includeSelf: true, radius: _kTorchReveal)
          .map((p) => '${p.x}_${p.y}'));
      _huntEntities.addAll(_placeBacklogOnMap());
      return;
    }

    logic.drainPestsHourly(sync); // les nuisibles grignotent l'or à l'heure

    final changed = <String, dynamic>{};
    // Position absente ou périmée (hors carte courante) → repart du départ.
    final p = logic.state.expeditionPos;
    var validPos = false;
    if (p != null && p.contains('_')) {
      final s = p.split('_');
      final px = int.tryParse(s[0]) ?? -1, py = int.tryParse(s[1]) ?? -1;
      validPos = _map.inBounds(px, py);
    }
    if (!validPos) {
      logic.state.expeditionPos = '${_map.start.x}_${_map.start.y}';
      changed['pos'] = true;
    }
    if (logic.state.expeditionRevealed.isEmpty) {
      final r = _neighbors(_map.start.x, _map.start.y,
              includeSelf: true, radius: _kTorchReveal)
          .map((p) => '${p.x}_${p.y}')
          .toList();
      logic.state.expeditionRevealed.addAll(r);
      changed['reveal'] = r;
    }
    final pruned = _prunedEntities();
    if (pruned.length != logic.state.expeditionEntities.length) {
      logic.state.expeditionEntities
        ..clear()
        ..addAll(pruned);
      changed['ent'] = true;
    }
    // Gardien garanti du niveau (mini-boss permanent jusqu'à sa mort).
    if (logic.state.expeditionGuardianKilledLevel != _level &&
        !logic.state.expeditionEntities
            .any((e) => isGuardianMeta(decodeEntity(e).meta))) {
      final gt = _guardianTile();
      if (gt != null) {
        final gType = GoldEconomy.pestTypeForLevel(_level);
        final base = logic.weaponRawCount(GoldEconomy.weaponForPest(gType));
        logic.state.expeditionEntities
            .add(encodeEntity(gType, gt, 'guardian~${_ymd()}~$base'));
        changed['ent'] = true;
      }
    }
    // ── Backlog : ennemis = tes vrais items négligés (PV = travail restant) ──
    // Retire les ennemis rattrapés (PV 0), garde les vivants, complète avec les
    // plus nécessiteux jusqu'au plafond.
    final liveRefIds = <String>{};
    final kept = <String>[];
    var refChanged = false;
    for (final e in logic.state.expeditionEntities) {
      final d = decodeEntity(e);
      if (isBacklogMeta(d.meta)) {
        final id = backlogItemId(d.meta);
        if (logic.enemyHp(d.type, id) <= 0) {
          refChanged = true; // rattrapé hors combat → l'ennemi disparaît
          continue;
        }
        liveRefIds.add(id);
      }
      kept.add(e);
    }
    if (refChanged) {
      logic.state.expeditionEntities
        ..clear()
        ..addAll(kept);
      changed['ent'] = true;
    }
    final occupied =
        logic.state.expeditionEntities.map((e) => decodeEntity(e).tile).toSet();
    final freeTiles = _freeFloorTiles(occupied);
    var slot = liveRefIds.length;
    for (final b in logic.backlogEnemies()) {
      if (slot >= GoldEconomy.maxLivePests || freeTiles.isEmpty) break;
      if (liveRefIds.contains(b.id)) continue;
      final tile = freeTiles.removeAt(_rng.nextInt(freeTiles.length));
      logic.state.expeditionEntities
          .add(encodeEntity(b.type, tile, 'ref~${b.id}'));
      liveRefIds.add(b.id);
      slot++;
      changed['ent'] = true;
    }

    if (changed.isNotEmpty) {
      logic.onChange();
      sync.expeditionWrite(
          newPos: logic.state.expeditionPos,
          revealAdd: (changed['reveal'] as List<String>?) ?? const [],
          entities: logic.state.expeditionEntities);
    }

    // Routines déjà planifiées (30 j) → on les retire des ennemis. Lecture
    // Firestore async : on rafraîchit puis on élague les araignées concernées.
    unawaited(_refreshPlannedAndPrune());
  }

  /// Recharge les routines planifiées puis retire les araignées (spiders)
  /// devenues planifiées de la carte courante.
  Future<void> _refreshPlannedAndPrune() async {
    await logic.refreshPlannedActivityIds();
    if (!mounted) return;
    final planned = logic.plannedActivityIds;
    if (planned.isEmpty) return;
    final ents = _ents;
    final kept = ents.where((e) {
      final d = decodeEntity(e);
      if (!isBacklogMeta(d.meta) || d.type != 'spider') return true;
      return !planned.contains(backlogItemId(d.meta));
    }).toList();
    if (kept.length == ents.length) {
      setState(() {}); // rien à retirer, mais reflète la maj du set
      return;
    }
    if (_hunt) {
      _huntEntities
        ..clear()
        ..addAll(kept);
    } else {
      logic.state.expeditionEntities
        ..clear()
        ..addAll(kept);
      logic.onChange();
      sync.expeditionWrite(
          newPos: logic.state.expeditionPos,
          revealAdd: const [],
          entities: logic.state.expeditionEntities);
    }
    setState(() {});
  }

  /// Tuiles sol libres (sans entité ni collectible non ramassé) pour poser un
  /// ennemi de backlog.
  List<String> _freeFloorTiles(Set<String> occupied) {
    return _map.all
        .where((t) {
          if (t.kind != OwTileKind.floor) return false;
          final id = '${t.x}_${t.y}';
          if (occupied.contains(id)) return false;
          if (t.collectibleId != null && !_picked.contains(t.collectibleId)) {
            return false;
          }
          return true;
        })
        .map((t) => '${t.x}_${t.y}')
        .toList();
  }

  List<String> _prunedEntities() {
    final today = _parseYmd(_ymd());
    return _ents.where((e) {
      final ent = decodeEntity(e);
      if (!isPestType(ent.type) || ent.meta.isEmpty) return true; // bonus persiste
      if (isGuardianMeta(ent.meta)) return true; // gardien permanent
      if (isBacklogMeta(ent.meta)) return true; // ennemi backlog (vie = PV)
      final diff = today.difference(_parseYmd(ent.meta)).inDays;
      return diff < GoldEconomy.pestLifespanDays(ent.type);
    }).toList();
  }

  DateTime _parseYmd(String y) => DateTime(int.parse(y.substring(0, 4)),
      int.parse(y.substring(4, 6)), int.parse(y.substring(6, 8)));

  /// Tuile (déterministe par niveau) où poser le gardien : un floor sans
  /// collectible, vers le milieu du parcours.
  String? _guardianTile() {
    final floors = _map.all
        .where((t) => t.kind == OwTileKind.floor && t.collectibleId == null)
        .toList()
      ..sort((a, b) => (a.y * 100 + a.x).compareTo(b.y * 100 + b.x));
    if (floors.isEmpty) return null;
    final t = floors[(_level * 7 + floors.length ~/ 2) % floors.length];
    return '${t.x}_${t.y}';
  }

  List<Point<int>> _neighbors(int x, int y,
      {bool includeSelf = false, int radius = 1}) {
    final out = <Point<int>>[];
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        if (!includeSelf && dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (_map.inBounds(nx, ny)) out.add(Point(nx, ny));
      }
    }
    return out;
  }

  /// Construit une case : ajoute la jauge de vie (couleur domaine × % PV) si
  /// c'est un ennemi de backlog.
  Widget _buildTile(int x, int y, Point<int> pos, ColorScheme cs) {
    var ent = _entityAt('${x}_$y');
    Color? hpColor;
    double hpFrac = 0;
    bool engaged = false;
    int sbiresCount = 0;
    int heartsCount = 0;
    if (ent != null && isBacklogMeta(ent.meta)) {
      final id = backlogItemId(ent.meta);
      final max = logic.enemyMaxHp(ent.type, id);
      final cur = logic.enemyHp(ent.type, id);
      if (cur <= 0) {
        ent = null; // objectif atteint → la case est vide jusqu'au prochain init
      } else {
        hpFrac = max > 0 ? cur / max : 0.0;
        hpColor = domainColor(logic.enemyDomainId(ent.type, id),
                logic.state.activeDomains) ??
            cs.primary;
        engaged = logic.isEngaged(ent.type, id);
        heartsCount = min(5, max < 1 ? 1 : cur);
        sbiresCount = engaged ? logic.sbiresLeft(ent.type, id) : GoldEconomy.sbiresForHp(cur);
      }
    }
    final tileWidget = _TileView(
      tile: _map.at(x, y),
      visible: _revealed.contains('${x}_$y'),
      isAvatar: pos.x == x && pos.y == y,
      avatarEmoji: logic.state.activeAvatar ?? '🧍',
      reachable: (x - pos.x).abs() + (y - pos.y).abs() == 1,
      entity: ent,
      hpColor: hpColor,
      hpFrac: hpFrac,
      engaged: engaged,
      picked: _picked,
      cs: cs,
      onTap: () => _onTap(_map.at(x, y)),
      sbiresCount: sbiresCount,
    );

    if (ent == null || heartsCount == 0) return tileWidget;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(heartsCount,
              (_) => const Text('❤️', style: TextStyle(fontSize: 10))),
        ),
        tileWidget,
      ],
    );
  }

  bool _walkable(int x, int y) =>
      _map.inBounds(x, y) && _map.at(x, y).kind != OwTileKind.wall;

  List<({int x, int y})> _ortho(int x, int y) => [
        (x: x + 1, y: y),
        (x: x - 1, y: y),
        (x: x, y: y + 1),
        (x: x, y: y - 1),
      ].where((p) => _walkable(p.x, p.y)).toList();

  /// Tuiles sol (sans collectible) triées par distance au départ (proches d'abord).
  List<String> _floorTilesByDistanceFromStart() {
    final dist = <String, int>{'${_map.start.x}_${_map.start.y}': 0};
    final q = <Point<int>>[_map.start];
    var i = 0;
    while (i < q.length) {
      final c = q[i++];
      final cd = dist['${c.x}_${c.y}']!;
      for (final n in _ortho(c.x, c.y)) {
        final id = '${n.x}_${n.y}';
        if (dist.containsKey(id)) continue;
        dist[id] = cd + 1;
        q.add(Point(n.x, n.y));
      }
    }
    return _map.all
        .where((t) => t.kind == OwTileKind.floor && t.collectibleId == null)
        .map((t) => '${t.x}_${t.y}')
        .where(dist.containsKey)
        .toList()
      ..sort((a, b) => dist[a]!.compareTo(dist[b]!));
  }

  /// Vrai si, en bloquant [candidate] (+ les [blocked] déjà posés), toutes les
  /// cases praticables restantes restent connectées au départ (chemin garanti).
  bool _freeStaysConnected(Set<String> blocked, String candidate) {
    final block = {...blocked, candidate};
    final startId = '${_map.start.x}_${_map.start.y}';
    if (block.contains(startId)) return false;
    var total = 0;
    for (final t in _map.all) {
      if (t.kind == OwTileKind.wall) continue;
      if (block.contains('${t.x}_${t.y}')) continue;
      total++;
    }
    final seen = <String>{startId};
    final q = <Point<int>>[_map.start];
    var i = 0;
    while (i < q.length) {
      final c = q[i++];
      for (final n in _ortho(c.x, c.y)) {
        final id = '${n.x}_${n.y}';
        if (block.contains(id) || seen.contains(id)) continue;
        seen.add(id);
        q.add(Point(n.x, n.y));
      }
    }
    return seen.length == total;
  }

  /// Pose un MAX d'ennemis de backlog sur la carte de chasse : les plus faciles
  /// (PV bas) près de l'entrée, en préservant un chemin praticable.
  List<String> _placeBacklogOnMap() {
    final easyFirst = logic.backlogEnemies()
      ..sort((a, b) => a.hp.compareTo(b.hp));
    final ordered = _floorTilesByDistanceFromStart();
    final startId = '${_map.start.x}_${_map.start.y}';
    final blocked = <String>{};
    final placed = <String>[];
    for (final e in easyFirst) {
      for (final tile in ordered) {
        if (tile == startId || blocked.contains(tile)) continue;
        if (_freeStaysConnected(blocked, tile)) {
          blocked.add(tile);
          placed.add(encodeEntity(e.type, tile, 'ref~${e.id}'));
          break;
        }
      }
    }
    return placed;
  }

  ({String raw, String type, String tile, String meta})? _entityAt(String id) {
    for (final e in _ents) {
      final d = decodeEntity(e);
      if (d.tile == id) {
        return (raw: e, type: d.type, tile: d.tile, meta: d.meta);
      }
    }
    return null;
  }

  int get _livePests =>
      _ents.where((e) => isPestType(decodeEntity(e).type)).length;

  List<String> _eligibleSpawnTiles(List<String> newlyRevealed, String destId) {
    return newlyRevealed.where((id) {
      if (id == destId) return false;
      final s = id.split('_');
      final t = _map.at(int.parse(s[0]), int.parse(s[1]));
      if (t.kind != OwTileKind.floor) return false;
      if (_entityAt(id) != null) return false;
      if (t.collectibleId != null && !_picked.contains(t.collectibleId)) {
        return false;
      }
      return true;
    }).toList();
  }


  String? _maybeSpawn(List<String> newlyRevealed, String destId) {
    if (_hunt) {
      // Chasse au backlog : tous les ennemis sont posés à l'ouverture (tes vrais
      // items). Pas de spawn pendant l'exploration.
      return null;
    }
    final w = logic.weeklyScoreData();
    if (w.previous <= 0) return null;
    final trendPct = ((w.current - w.previous) * 100).round();
    final p = trendPct.abs().clamp(0, GoldEconomy.trendSpawnCapPct);
    if (p == 0 || _rng.nextInt(100) >= p) return null;
    final eligible = _eligibleSpawnTiles(newlyRevealed, destId);
    if (eligible.isEmpty) return null;
    final tile = eligible[_rng.nextInt(eligible.length)];
    if (trendPct < 0) {
      // Sur la map LIVE, les nuisibles sont tes vrais items (backlog), posés à
      // l'ouverture — pas de nuisible générique ici. Seuls les trésors spawnent.
      return null;
    } else {
      final amount = GoldEconomy.bonusGoldMin +
          _rng.nextInt(GoldEconomy.bonusGoldMax - GoldEconomy.bonusGoldMin + 1);
      return encodeEntity('bonus', tile, '$amount');
    }
  }

  /// BFS sur les cases révélées+praticables — chemin de [from] à [to] (exclu/inclus)
  /// ou liste vide si inaccessible via terrain révélé.
  List<OwTile> _bfsPath(Point<int> from, Point<int> to) {
    if (from == to) return const [];
    final startId = '${from.x}_${from.y}';
    final goalId = '${to.x}_${to.y}';
    final prev = <String, String?>{startId: null};
    final queue = <Point<int>>[from];
    int i = 0;
    while (i < queue.length) {
      final cur = queue[i++];
      final curId = '${cur.x}_${cur.y}';
      if (curId == goalId) break;
      for (final n in _ortho(cur.x, cur.y)) {
        final nid = '${n.x}_${n.y}';
        if (prev.containsKey(nid)) continue;
        if (!_revealed.contains(nid)) continue;
        prev[nid] = curId;
        queue.add(Point(n.x, n.y));
      }
    }
    if (!prev.containsKey(goalId)) return const [];
    final path = <OwTile>[];
    var cur = goalId;
    while (cur != startId) {
      final s = cur.split('_');
      path.add(_map.at(int.parse(s[0]), int.parse(s[1])));
      cur = prev[cur]!;
    }
    return path.reversed.toList();
  }

  /// Déplace l'avatar le long de [path] (~200 ms/case).
  /// S'arrête sur le premier nuisible rencontré et ouvre le combat.
  Future<void> _walkPath(List<OwTile> path) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      for (final tile in path) {
        if (!mounted) return;
        final ent = _entityAt(tile.id);
        if (ent != null && isPestType(ent.type)) {
          await _engageCombat(ent.raw, ent.type);
          return;
        }
        await _doMove(tile, ent);
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onTap(OwTile t) async {
    if (_busy) return;
    final p = _pos;
    if (t.x == p.x && t.y == p.y) return;
    final isRevealed = _revealed.contains(t.id);
    final adjacent = (t.x - p.x).abs() + (t.y - p.y).abs() == 1;

    if (!adjacent && !isRevealed) return;

    if (t.kind == OwTileKind.wall) {
      if (!isRevealed) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🧱 Un mur bloque ce passage.'),
            duration: Duration(seconds: 1)));
      }
      return;
    }

    if (!adjacent) {
      final path = _bfsPath(p, Point(t.x, t.y));
      if (path.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🌫️ Chemin bloqué par le brouillard.'),
            duration: Duration(seconds: 1)));
        return;
      }
      await _walkPath(path);
      return;
    }

    final ent = _entityAt(t.id);
    if (ent != null && isPestType(ent.type)) {
      await _engageCombat(ent.raw, ent.type);
      return;
    }
    await _move(t, ent);
  }

  /// Combat : on FORGE l'arme par l'action réelle (pas par l'or). Si l'arme est
  /// prête → on frappe ; sinon on ouvre la feuille de combat (progression).
  Future<void> _engageCombat(String raw, String type) async {
    final meta = decodeEntity(raw).meta;
    if (isBacklogMeta(meta)) {
      // Ennemi = vrai item : on le combat en FAISANT le travail (modèle PV).
      await _showBacklogCombat(raw, type, backlogItemId(meta));
      return;
    }
    // Ennemi générique (gardien / chasse) : modèle arme/munition.
    await _showCombatSheet(raw, type, GoldEconomy.weaponForPest(type));
  }

  Future<void> _strike(String raw, String type, {bool backlog = false}) async {
    final isGuardian = isGuardianMeta(decodeEntity(raw).meta);
    final loot = GoldEconomy.pestLootBase(type, isGuardian) + _rng.nextInt(5);
    setState(() => _busy = true);
    if (_hunt) {
      _huntEntities.removeWhere((e) => e == raw); // instance éphémère
    } else {
      final newEntities =
          logic.state.expeditionEntities.where((e) => e != raw).toList();
      await sync.expeditionWrite(entities: newEntities, reasonCode: 'pest_kill');
      logic.state.expeditionEntities
        ..clear()
        ..addAll(newEntities);
      if (isGuardian) {
        logic.state.expeditionGuardianKilledLevel = _level;
        sync.setExpeditionGuardianKilled(_level);
      }
    }
    // Capture (+ recettes). En backlog, le travail réel EST l'attaque → on ne
    // dépense pas d'arme.
    final unlocked = logic.recordKill(type, sync, spendWeapon: !backlog);
    logic.applyGold(sync, loot,
        category: 'gain',
        reasonCode: 'pest_loot',
        label: _hunt ? 'Butin de chasse' : 'Butin de combat');
    logic.onChange();
    if (!mounted) return;
    setState(() => _busy = false);
    showConfetti(context, count: isGuardian ? 30 : 18);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '⚔️ ${isGuardian ? "Gardien " : ""}${pestName(type)} vaincu ! +$loot or'),
        duration: const Duration(seconds: 2)));
    if (unlocked.isNotEmpty) {
      showConfetti(context, count: 28);
      final u = unlocked.first;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('${u.emoji} ${u.name} débloqué par recette de chasse !'),
          duration: const Duration(seconds: 3)));
    }
  }

  Future<void> _showCombatSheet(String raw, String type, String weapon) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Combat',
      barrierColor: Colors.black.withOpacity(.6),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, a1, a2) {
        // Modèle stock : il faut au moins 1 arme en réserve pour frapper.
        final isGuardian = isGuardianMeta(decodeEntity(raw).meta);
        final avail = logic.weaponsAvailable(weapon);
        final ready = avail >= 1;
        final wEmoji = logic.weaponEmoji(weapon);
        final wName = logic.weaponName(weapon);
        final force = GoldEconomy.pestCost(type);
        final lootEst = GoldEconomy.pestLootBase(type, isGuardian);
        final kills = logic.pestKillCount(type);
        final wHint = weapon == 'epee'
            ? 'Finis une tâche → 🗡️ épée'
            : weapon == 'arc'
                ? 'Logge ~1 h de temps → 🏹 flèche'
                : 'Fais une routine → 🔪 couteau';
        final accent =
            isGuardian ? const Color(0xFFFFC247) : const Color(0xFFE24A4A);

        Widget chip(String emoji, String label) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.09),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white.withOpacity(.10)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ]),
            );

        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isGuardian
                        ? const [Color(0xFF2A1A0E), Color(0xFF4A2A0E)]
                        : const [Color(0xFF2A0E0E), Color(0xFF5A1A1A)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: accent, width: 2),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(.4), blurRadius: 26)
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(isGuardian ? '👑 GARDIEN' : '⚔️ COMBAT',
                        style: TextStyle(
                            fontSize: 13,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w900,
                            color: isGuardian
                                ? const Color(0xFFFFE3A0)
                                : const Color(0xFFFFC9C9))),
                    const SizedBox(height: 12),
                    Container(
                      width: 116,
                      height: 116,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          accent.withOpacity(.30),
                          accent.withOpacity(0),
                        ]),
                      ),
                      child: Text(entityEmoji(type),
                          style: const TextStyle(fontSize: 74)),
                    ),
                    Text('${isGuardian ? "Gardien " : ""}${pestName(type)}',
                        style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 3),
                    Text('Niveau $_mapLevel · capturé ${kills}\u00d7',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withOpacity(.55))),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        chip('⚡', 'Force $force/h'),
                        chip('💰', 'Butin ~$lootEst or'),
                        chip(wEmoji, 'Arme : $wName'),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: (ready
                                ? const Color(0xFF1E7A4D)
                                : const Color(0xFF7A1E1E))
                            .withOpacity(.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(ready ? 'Réserve : ' : 'Réserve vide — ',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(.85))),
                          Flexible(
                            child: Text(ready ? '$wEmoji \u00d7$avail' : wHint,
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: ready
                                        ? const Color(0xFF7CF0AD)
                                        : const Color(0xFFFFB0B0))),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              ready ? accent : Colors.white.withOpacity(.16),
                          foregroundColor: ready
                              ? Colors.white
                              : Colors.white.withOpacity(.5),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        icon: Text(ready ? '⚔️' : '🔒',
                            style: const TextStyle(fontSize: 16)),
                        label: Text(
                            ready ? 'FRAPPER !  (-1 $wEmoji)' : 'Pas d\'arme',
                            style: const TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w900)),
                        onPressed: ready
                            ? () {
                                Navigator.pop(ctx);
                                _strike(raw, type);
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Fuir',
                          style: TextStyle(
                              color: Colors.white.withOpacity(.55))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Retire de la carte les ennemis backlog rattrapés (PV 0) après un combat.
  void _pruneDeadBacklog() {
    final survivors = _ents.where((e) {
      final d = decodeEntity(e);
      if (!isBacklogMeta(d.meta)) return true;
      return logic.enemyHp(d.type, backlogItemId(d.meta)) > 0;
    }).toList();
    if (survivors.length != _ents.length) {
      if (_hunt) {
        _huntEntities
          ..clear()
          ..addAll(survivors);
      } else {
        logic.state.expeditionEntities
          ..clear()
          ..addAll(survivors);
        sync.expeditionWrite(entities: survivors, reasonCode: 'pest_kill');
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _showBacklogCombat(
      String raw, String type, String itemId) async {
    await showBacklogCombat(context, logic, sync, type, itemId,
        onChanged: _pruneDeadBacklog, onLaunchedTimer: () {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _doMove(OwTile t,
      ({String raw, String type, String tile, String meta})? ent) async {
    final fogged = !_revealed.contains(t.id);
    // Déplacement gratuit sur case éclairée ; on ne paie que l'éclairage du
    // brouillard (torche). La 1ʳᵉ torche du jour est offerte.
    final free = fogged && _freeStepAvailable;
    var cost = fogged ? GoldEconomy.torchCost : 0;
    if (free) cost = 0;
    if (logic.state.gold < cost) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pas assez d\'or pour éclairer cette case.'),
          duration: Duration(seconds: 1)));
      return;
    }

    final revealAdd = <String>[];
    if (fogged) {
      for (final n in _neighbors(t.x, t.y,
          includeSelf: true, radius: _kTorchReveal)) {
        final id = '${n.x}_${n.y}';
        if (!_revealed.contains(id)) revealAdd.add(id);
      }
    }

    var entities = List<String>.from(_ents);
    String? spawnMsg;
    if (revealAdd.isNotEmpty) {
      final spawned = _maybeSpawn(revealAdd, t.id);
      if (spawned != null) {
        entities.add(spawned);
        final d = decodeEntity(spawned);
        spawnMsg = d.type == 'bonus'
            ? '💰 Un trésor apparaît !'
            : '${entityEmoji(d.type)} ${pestName(d.type)} rôde…';
      }
    }

    var gain = 0;
    String? msg;
    if (ent != null && ent.type == 'bonus') {
      gain += int.tryParse(ent.meta) ?? 0;
      entities = entities.where((e) => e != ent.raw).toList();
      msg = '💰 +$gain or';
    }
    String? pickedAdd, collectionAdd;
    String? weaponPickupKey;
    final collId = t.collectibleId;
    if (collId != null && !_picked.contains(collId)) {
      pickedAdd = collId;
      if (collId.startsWith('wpn_')) {
        // Pickup d'arme : ne va pas dans la collection
        weaponPickupKey = collId.substring(4); // 'arc' ou 'couteau'
        msg = '${logic.weaponEmoji(weaponPickupKey)} +1 ${logic.weaponName(weaponPickupKey)} ramassé !';
      } else {
        final cat = collectibleById(collId);
        collectionAdd = collId;
        if (cat != null && cat.rare) {
          gain += GoldEconomy.lootGoldMin +
              _rng.nextInt(GoldEconomy.lootGoldMax - GoldEconomy.lootGoldMin + 1);
        }
        msg = '${cat?.emoji ?? '✨'} ${cat?.name ?? 'Trouvé'} ajouté à ta collection';
      }
    }

    final goldDelta = gain - cost;
    final entitiesChanged = entities.length != _ents.length;

    if (_hunt) {
      // Chasse : état carte LOCAL (éphémère) ; seuls or + collection persistent.
      _huntPos = Point(t.x, t.y);
      _huntRevealed.addAll(revealAdd);
      if (entitiesChanged) {
        _huntEntities
          ..clear()
          ..addAll(entities);
      }
      if (pickedAdd != null) _huntPicked.add(pickedAdd);
      if (goldDelta != 0) {
        logic.applyGold(sync, goldDelta,
            category: goldDelta >= 0 ? 'gain' : 'loss',
            reasonCode: fogged ? 'hunt_torch' : 'hunt_step',
            label: 'Chasse');
      }
      if (weaponPickupKey != null) {
        logic.addWeaponPickup(weaponPickupKey, 1, sync);
      }
      if (collectionAdd != null &&
          !logic.state.collection.contains(collectionAdd)) {
        logic.state.collection.add(collectionAdd);
        logic.state.collectionMeta[collectionAdd] =
            '${_ymd()}|chassé sur la carte niv. $_mapLevel';
        sync.setCollectionMeta(logic.state.collectionMeta);
        sync.expeditionWrite(collectionAdd: collectionAdd);
      }
      logic.onChange();
    } else {
      await sync.expeditionWrite(
        newPos: t.id,
        revealAdd: revealAdd,
        entities: entitiesChanged ? entities : null,
        pickedAdd: pickedAdd,
        collectionAdd: collectionAdd,
        goldDelta: goldDelta,
        useFreeStep: free,
        reasonCode: fogged ? 'expedition_torch' : 'expedition_step',
        label: 'Exploration',
      );
      logic.state.gold += goldDelta;
      if (logic.state.gold < 0) logic.state.gold = 0;
      if (goldDelta > 0) logic.addLifetimeCapped(goldDelta);
      logic.state.expeditionPos = t.id;
      for (final r in revealAdd) {
        if (!logic.state.expeditionRevealed.contains(r)) {
          logic.state.expeditionRevealed.add(r);
        }
      }
      if (entitiesChanged) {
        logic.state.expeditionEntities
          ..clear()
          ..addAll(entities);
      }
      if (pickedAdd != null) logic.state.expeditionPicked.add(pickedAdd);
      if (weaponPickupKey != null) {
        logic.addWeaponPickup(weaponPickupKey, 1, sync);
      }
      if (collectionAdd != null &&
          !logic.state.collection.contains(collectionAdd)) {
        logic.state.collection.add(collectionAdd);
        logic.state.collectionMeta[collectionAdd] =
            '${_ymd()}|trouvé sur la carte (niv. $_mapLevel)';
        sync.setCollectionMeta(logic.state.collectionMeta);
      }
      if (free) logic.state.lastFreeStepYmd = _ymd();
      logic.onChange();
    }
    if (!mounted) return;
    setState(() {});

    final toast = spawnMsg ?? msg;
    if (toast != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(toast), duration: const Duration(seconds: 1)));
    }

    if (!_hunt) _maybeCompletionBonus();
    if (t.kind == OwTileKind.castle) await _castle();
  }

  Future<void> _move(OwTile t,
      ({String raw, String type, String tile, String meta})? ent) async {
    setState(() => _busy = true);
    await _doMove(t, ent);
    if (mounted) setState(() => _busy = false);
  }

  void _maybeCompletionBonus() {
    final flag = 'complete_$_level';
    if (logic.state.collection.contains(flag)) return;
    if (logic.state.expeditionRevealed.length < _map.walkableCount) return;
    final rares = overworldCollectibles.where((c) => c.rare).toList();
    final reward = rares[_rng.nextInt(rares.length)];
    logic.state.collection.add(flag);
    if (!logic.state.collection.contains(reward.id)) {
      logic.state.collection.add(reward.id);
    }
    logic.state.collectionMeta[reward.id] =
        '${_ymd()}|exploration 100% (niv. $_mapLevel)';
    sync.setCollectionMeta(logic.state.collectionMeta);
    logic.onChange();
    sync.expeditionWrite(collectionAdd: reward.id);
    sync.expeditionWrite(collectionAdd: flag);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '🗺️ Carte explorée à 100 % ! ${reward.emoji} ${reward.name} (rare) obtenu')));
    }
  }

  Future<void> _castle() async {
    if (_hunt) {
      // En chasse, pas de déblocage : le château n'est qu'un point de la carte.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🏰 Tu as atteint le château — continue à chasser !'),
          duration: Duration(seconds: 2)));
      return;
    }
    final target = _level; // niveau visé (figé avant le déblocage)
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🏰 Château atteint !'),
        content: Text(
            'Tu as trouvé le château ! Entre dans le donjon pour relever les '
            'défis et débloquer le niveau $target — ou continue d\'explorer la '
            'carte (trésors, collectibles) avant d\'entrer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Explorer encore')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kGold),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entrer dans le donjon')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    // Le donjon (V1) gère la traversée et le déblocage du niveau (au 🏁).
    await showExpeditionSheet(context, logic, sync);
    if (!mounted) return;
    // Donjon terminé → niveau débloqué → on referme aussi la carte overworld.
    if (logic.effectiveLevel() >= target) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final biome = expeditionBiome(_level);
    final pos = _pos;
    final pests = _livePests;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(children: [
            Text(biome.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_hunt ? '🏹 Chasse · Niveau $_mapLevel' : 'Niveau $_mapLevel · ???',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                      _hunt
                          ? 'Traque les nuisibles ${biome.label} pour leur butin'
                          : 'Explore ${biome.label} jusqu\'au 🏰',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                goldAmount('${logic.state.gold}',
                    fontSize: 15, weight: FontWeight.bold, color: _kGold),
                const SizedBox(height: 2),
                Text(
                    '🔪${logic.weaponsAvailable('couteau')}  🏹${logic.weaponsAvailable('arc')}  🗡️${logic.weaponsAvailable('epee')}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(
              child: Text(
                  'Déplacement gratuit · éclairer une case (🔦 ${GoldEconomy.torchCost} or, 1ʳᵉ du jour offerte).'
                  '${pests > 0 ? ' · $pests nuisible(s) actif(s)' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          pests > 0 ? cs.error : cs.onSurface.withOpacity(.5))),
            ),
            if (_map.all.any((t) =>
                t.collectibleId != null &&
                !_picked.contains(t.collectibleId))) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFFD4A017).withOpacity(.15),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('✨ Trésors',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8A6D00))),
              ),
              const SizedBox(width: 6),
            ],
            if (_freeStepAvailable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('1ʳᵉ torche offerte ✓',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade700)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            controller: scroll,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var y = 0; y < _map.rows; y++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var x = 0; x < _map.cols; x++)
                            _buildTile(x, y, pos, cs),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _TileView extends StatelessWidget {
  final OwTile tile;
  final bool visible, isAvatar, reachable;
  final String avatarEmoji;
  final ({String raw, String type, String tile, String meta})? entity;
  final Set<String> picked;
  final ColorScheme cs;
  final VoidCallback onTap;
  // Jauge de vie d'un ennemi backlog : couleur du domaine, hauteur = % PV restant.
  final Color? hpColor;
  final double hpFrac;
  // Vrai si un combat a déjà été engagé contre cet ennemi.
  final bool engaged;
  final int sbiresCount;
  const _TileView({
    required this.tile,
    required this.visible,
    required this.isAvatar,
    this.avatarEmoji = '🧍',
    required this.reachable,
    required this.entity,
    required this.picked,
    required this.cs,
    required this.onTap,
    this.hpColor,
    this.hpFrac = 0,
    this.engaged = false,
    this.sbiresCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      // Case sous brouillard. Si elle est adjacente à l'avatar, on la rend
      // cliquable (torche : 6 or) avec un indice 🔦 — sinon on ne peut jamais
      // sortir de l'anneau de départ.
      final fog = Container(
        width: _tile,
        height: _tile,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.onSurface.withOpacity(reachable ? .16 : .10),
          borderRadius: BorderRadius.circular(6),
          border: reachable ? Border.all(color: _kGold, width: 2) : null,
        ),
        child: reachable
            ? const Text('🔦', style: TextStyle(fontSize: 16))
            : null,
      );
      return reachable ? GestureDetector(onTap: onTap, child: fog) : fog;
    }

    String content = '';
    Color bg = cs.surfaceContainerHighest.withOpacity(.4);
    switch (tile.kind) {
      case OwTileKind.wall:
        bg = cs.onSurface.withOpacity(.22);
        break;
      case OwTileKind.start:
        content = '🏳️';
        bg = Colors.green.withOpacity(.15);
        break;
      case OwTileKind.castle:
        content = '🏰';
        bg = _kGold.withOpacity(.18);
        break;
      case OwTileKind.floor:
        break;
    }
    if (entity != null) {
      content = entityEmoji(entity!.type);
    } else if (tile.collectibleId != null &&
        !picked.contains(tile.collectibleId)) {
      content = collectibleById(tile.collectibleId!)?.emoji ?? '✨';
    }
    if (isAvatar) content = avatarEmoji;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _tile,
        height: _tile,
        margin: const EdgeInsets.all(1),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: engaged
              ? Border.all(color: Colors.red.shade500, width: 2)
              : (reachable && tile.kind != OwTileKind.wall
                  ? Border.all(color: _kGold, width: 2)
                  : null),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Jauge de vie : remplit la case (couleur du domaine) au % de PV.
            if (hpColor != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _tile * hpFrac.clamp(0.0, 1.0),
                child: Container(color: hpColor!.withOpacity(.5)),
              ),
            Text(content, style: const TextStyle(fontSize: 20)),
            if (entity != null && sbiresCount > 0)
              Positioned(
                left: 0, right: 0, bottom: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    sbiresCount.clamp(0, 5),
                    (_) => Text(entityEmoji(entity!.type),
                        style: const TextStyle(fontSize: 10)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
