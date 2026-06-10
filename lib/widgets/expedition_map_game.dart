import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/widgets/confetti.dart';
import 'package:productivitwo_v1/widgets/expedition_sheet.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';

/// Overworld (Phase 1) : carte 2D explorable pour débloquer le prochain niveau.
/// Déplacement GRATUIT sur case éclairée ; brouillard = torche (révèle radius 2,
/// 1ʳᵉ du jour offerte) ; ≥2 chemins ; collectibles ; écosystème lié au % hebdo
/// (nuisibles si tendance ↓, bonus si ↑) ; château = déblocage (provisoire P1).

const _kGold = Color(0xFFD4A017);
const double _tile = 46;
const int _kTorchReveal = 2; // rayon éclairé par une torche (Chebyshev)

Future<void> showExpeditionGame(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExpeditionGame(logic: logic, sync: sync),
  );
}

class _ExpeditionGame extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _ExpeditionGame({required this.logic, required this.sync});
  @override
  State<_ExpeditionGame> createState() => _ExpeditionGameState();
}

class _ExpeditionGameState extends State<_ExpeditionGame> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;
  final _rng = Random();
  bool _busy = false;

  int get _level => logic.effectiveLevel() + 1;
  late final Overworld _map = generateOverworld(_level);

  Set<String> get _revealed => logic.state.expeditionRevealed.toSet();
  Set<String> get _picked => logic.state.expeditionPicked.toSet();
  Point<int> get _pos {
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

  bool get _freeStepAvailable => logic.state.lastFreeStepYmd != _ymd();

  @override
  void initState() {
    super.initState();
    // Solde à jour des gains du jour : on doit pouvoir financer la carte de suite.
    logic.reconcileLiveGold(sync);
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
            .any((e) => decodeEntity(e).meta == 'guardian')) {
      final gt = _guardianTile();
      if (gt != null) {
        logic.state.expeditionEntities.add(
            encodeEntity(GoldEconomy.pestTypeForLevel(_level), gt, 'guardian'));
        changed['ent'] = true;
      }
    }
    if (changed.isNotEmpty) {
      logic.onChange();
      sync.expeditionWrite(
          newPos: logic.state.expeditionPos,
          revealAdd: (changed['reveal'] as List<String>?) ?? const [],
          entities: logic.state.expeditionEntities);
    }
  }

  List<String> _prunedEntities() {
    final today = _parseYmd(_ymd());
    return logic.state.expeditionEntities.where((e) {
      final ent = decodeEntity(e);
      if (!isPestType(ent.type) || ent.meta.isEmpty) return true; // bonus persiste
      if (ent.meta == 'guardian') return true; // gardien permanent
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

  ({String raw, String type, String tile, String meta})? _entityAt(String id) {
    for (final e in logic.state.expeditionEntities) {
      final d = decodeEntity(e);
      if (d.tile == id) {
        return (raw: e, type: d.type, tile: d.tile, meta: d.meta);
      }
    }
    return null;
  }

  int get _livePests => logic.state.expeditionEntities
      .where((e) => isPestType(decodeEntity(e).type))
      .length;

  String? _maybeSpawn(List<String> newlyRevealed, String destId) {
    final w = logic.weeklyScoreData();
    if (w.previous <= 0) return null;
    final trendPct = ((w.current - w.previous) * 100).round();
    final p = trendPct.abs().clamp(0, GoldEconomy.trendSpawnCapPct);
    if (p == 0 || _rng.nextInt(100) >= p) return null;
    final eligible = newlyRevealed.where((id) {
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
    if (eligible.isEmpty) return null;
    final tile = eligible[_rng.nextInt(eligible.length)];
    if (trendPct < 0) {
      if (_livePests >= GoldEconomy.maxLivePests) return null;
      // L'ennemi dépend du NIVEAU (force croissante), pas du hasard.
      final type = GoldEconomy.pestTypeForLevel(_level);
      return encodeEntity(type, tile, _ymd());
    } else {
      final amount = GoldEconomy.bonusGoldMin +
          _rng.nextInt(GoldEconomy.bonusGoldMax - GoldEconomy.bonusGoldMin + 1);
      return encodeEntity('bonus', tile, '$amount');
    }
  }

  Future<void> _onTap(OwTile t) async {
    if (_busy) return;
    final p = _pos;
    final adjacent = (t.x - p.x).abs() + (t.y - p.y).abs() == 1;
    if (!adjacent) return;
    if (t.kind == OwTileKind.wall) {
      // Mur (parfois découvert en torchant une case sous brouillard).
      if (!_revealed.contains(t.id)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🧱 Un mur bloque ce passage.'),
            duration: Duration(seconds: 1)));
      }
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
    // Toujours ouvrir l'écran de combat : même arme prête, la mise à mort passe
    // par le bouton FRAPPER (sinon l'ennemi mourait « sans combat » au tap).
    await _showCombatSheet(raw, type, GoldEconomy.weaponForPest(type));
  }

  Future<void> _strike(String raw, String type) async {
    final isGuardian = decodeEntity(raw).meta == 'guardian';
    final loot = GoldEconomy.pestLootBase(type, isGuardian) + _rng.nextInt(5);
    final newEntities =
        logic.state.expeditionEntities.where((e) => e != raw).toList();
    setState(() => _busy = true);
    await sync.expeditionWrite(entities: newEntities, reasonCode: 'pest_kill');
    logic.state.expeditionEntities
      ..clear()
      ..addAll(newEntities);
    logic.applyGold(sync, loot,
        category: 'gain', reasonCode: 'pest_loot', label: 'Butin de combat');
    if (isGuardian) {
      logic.state.expeditionGuardianKilledLevel = _level;
      sync.setExpeditionGuardianKilled(_level);
    }
    logic.onChange();
    if (!mounted) return;
    setState(() => _busy = false);
    showConfetti(context, count: isGuardian ? 30 : 18);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '⚔️ ${isGuardian ? "Gardien " : ""}${pestName(type)} vaincu ! +$loot or'),
        duration: const Duration(seconds: 2)));
  }

  Future<void> _showCombatSheet(String raw, String type, String weapon) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Combat',
      barrierColor: Colors.black.withOpacity(.6),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, a1, a2) {
        final forge = logic.weaponForgeStatus(weapon);
        final pct = forge.target > 0
            ? (forge.progress / forge.target).clamp(0.0, 1.0)
            : 0.0;
        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A0E0E), Color(0xFF5A1A1A)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE24A4A), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66E24A4A), blurRadius: 24)
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('\u2694\uFE0F COMBAT',
                        style: TextStyle(
                            fontSize: 13,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFFC9C9))),
                    const SizedBox(height: 16),
                    Text(entityEmoji(type), style: const TextStyle(fontSize: 78)),
                    const SizedBox(height: 4),
                    Text(pestName(type),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(
                        'Il maudit tes routines (gain \u00f72) et te draine de l\'or \u00e0 l\'heure. Forge ton arme par l\'action pour le vaincre.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(.7))),
                    const SizedBox(height: 22),
                    Text(forge.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 9,
                        backgroundColor: Colors.white.withOpacity(.15),
                        color: const Color(0xFFFFC247),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${forge.progress} / ${forge.target}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.white.withOpacity(.6))),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: forge.ready
                              ? const Color(0xFFE24A4A)
                              : Colors.white.withOpacity(.18),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: Text(forge.ready ? '\u2694\uFE0F' : '\ud83d\udd12',
                            style: const TextStyle(fontSize: 16)),
                        label: Text(
                            forge.ready
                                ? 'FRAPPER !'
                                : 'Forge ton arme d\'abord',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        onPressed: forge.ready
                            ? () {
                                Navigator.pop(ctx);
                                _strike(raw, type);
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Fuir',
                          style:
                              TextStyle(color: Colors.white.withOpacity(.6))),
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

  Future<void> _move(OwTile t,
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

    var entities = List<String>.from(logic.state.expeditionEntities);
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
    final collId = t.collectibleId;
    if (collId != null && !_picked.contains(collId)) {
      final cat = collectibleById(collId);
      pickedAdd = collId;
      collectionAdd = collId;
      if (cat != null && cat.rare) {
        gain += GoldEconomy.lootGoldMin +
            _rng.nextInt(GoldEconomy.lootGoldMax - GoldEconomy.lootGoldMin + 1);
      }
      msg = '${cat?.emoji ?? '✨'} ${cat?.name ?? 'Trouvé'} ajouté à ta collection';
    }

    final goldDelta = gain - cost;
    final entitiesChanged =
        entities.length != logic.state.expeditionEntities.length;

    setState(() => _busy = true);
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
    if (collectionAdd != null &&
        !logic.state.collection.contains(collectionAdd)) {
      logic.state.collection.add(collectionAdd);
      logic.state.collectionMeta[collectionAdd] =
          '${_ymd()}|trouvé sur la carte (niv. $_level)';
      sync.setCollectionMeta(logic.state.collectionMeta);
    }
    if (free) logic.state.lastFreeStepYmd = _ymd();
    logic.onChange();
    if (!mounted) return;
    setState(() => _busy = false);

    final toast = spawnMsg ?? msg;
    if (toast != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(toast), duration: const Duration(seconds: 1)));
    }

    _maybeCompletionBonus();
    if (t.kind == OwTileKind.castle) await _castle();
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
        '${_ymd()}|exploration 100% (niv. $_level)';
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
                  Text('Niveau $_level · ???',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Explore ${biome.label} jusqu\'au 🏰',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
            goldAmount('${logic.state.gold}',
                fontSize: 15, weight: FontWeight.bold, color: _kGold),
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
                            _TileView(
                              tile: _map.at(x, y),
                              visible: _revealed.contains('${x}_$y'),
                              isAvatar: pos.x == x && pos.y == y,
                              avatarEmoji: logic.state.activeAvatar ?? '🧍',
                              reachable:
                                  (x - pos.x).abs() + (y - pos.y).abs() == 1,
                              entity: _entityAt('${x}_$y'),
                              picked: _picked,
                              cs: cs,
                              onTap: () => _onTap(_map.at(x, y)),
                            ),
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
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: reachable && tile.kind != OwTileKind.wall
              ? Border.all(color: _kGold, width: 2)
              : null,
        ),
        child: Text(content, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
