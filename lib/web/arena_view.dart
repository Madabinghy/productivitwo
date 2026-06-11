import 'dart:async';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/widgets/daily_schedule_view.dart';
import 'package:productivitwo_v1/widgets/expedition_map_game.dart';
import 'package:productivitwo_v1/widgets/expedition_sheet.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';
import 'package:productivitwo_v1/widgets/gold_sheet.dart';

const _kGold = Color(0xFFD4A017);

class ArenaView extends StatefulWidget {
  final FirestoreSync sync;
  const ArenaView({required this.sync, super.key});

  @override
  State<ArenaView> createState() => _ArenaViewState();
}

class _ArenaViewState extends State<ArenaView> {
  AppLogic? _logic;
  bool _loading = true;
  String? _error;

  StreamSubscription? _metaSub;
  StreamSubscription? _projectsSub;

  FirestoreSync get sync => widget.sync;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await sync.pull();
      if (state == null) {
        if (mounted) setState(() { _loading = false; _error = 'Impossible de charger les données.'; });
        return;
      }
      final logic = AppLogic(state, () { if (mounted) setState(() {}); });
      logic.sync = sync;

      // Projets initiaux
      final projects = await sync.fetchProjects();
      logic.updateGanttCounts(projects);

      if (!mounted) return;
      setState(() { _logic = logic; _loading = false; });

      // Stream projets en live
      _projectsSub = sync.streamProjects().listen((p) {
        _logic?.updateGanttCounts(p);
        if (mounted) setState(() {});
      });

      // Stream meta en live (or, expédition, inventaire…)
      _metaSub = sync.streamMetaDoc().listen((_) async {
        final fresh = await sync.pull();
        if (fresh == null || !mounted) return;
        // Préserve les projets déjà chargés
        final savedProjects = _logic?.currentProjects ?? [];
        _logic?.state = fresh;
        _logic?.currentProjects = savedProjects;
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  void dispose() {
    _metaSub?.cancel();
    _projectsSub?.cancel();
    super.dispose();
  }

  String _ymd() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _logic == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          Text(_error ?? 'Erreur inconnue'),
          const SizedBox(height: 16),
          FilledButton(onPressed: () { setState(() { _loading = true; _error = null; }); _load(); },
              child: const Text('Réessayer')),
        ]),
      );
    }

    final logic = _logic!;
    final cs = Theme.of(context).colorScheme;
    final ymd = _ymd();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Barre de statuts ───────────────────────────────────────────────────
        _StatsBar(logic: logic, cs: cs),
        // ── 3 colonnes principales ─────────────────────────────────────────────
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 900;
            if (narrow) {
              // Petit écran → scroll vertical avec sections empilées
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ExplorationBar(logic: logic, sync: sync, ymd: ymd, cs: cs),
                    const SizedBox(height: 16),
                    _AujourdhuiColumn(logic: logic, ymd: ymd, cs: cs),
                    const SizedBox(height: 16),
                    _MonOrColumn(logic: logic, sync: sync),
                  ],
                ),
              );
            }
            // Grand écran → 3 colonnes
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Col gauche : Mon Or (combats + boutique + routines)
                SizedBox(
                  width: 340,
                  child: _MonOrColumn(logic: logic, sync: sync),
                ),
                const VerticalDivider(width: 1),
                // Col centre : Aujourd'hui (programme)
                Expanded(
                  child: _AujourdhuiColumn(logic: logic, ymd: ymd, cs: cs),
                ),
                const VerticalDivider(width: 1),
                // Col droite : Exploration (cartes, donjon, chasse)
                SizedBox(
                  width: 300,
                  child: _ExplorationBar(
                      logic: logic, sync: sync, ymd: ymd, cs: cs),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

// ── Barre de statuts ──────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final AppLogic logic;
  final ColorScheme cs;
  const _StatsBar({required this.logic, required this.cs});

  @override
  Widget build(BuildContext context) {
    final lvl = logic.userLevelData();
    final range = lvl.xpNext - lvl.xpCurrent;
    final xpFrac = range > 0
        ? ((lvl.xp - lvl.xpCurrent) / range).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          goldAmount('${logic.state.gold}', fontSize: 16, weight: FontWeight.w800),
          const SizedBox(width: 20),
          // Niveau + barre
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Niv. ${lvl.level} · ${lvl.title}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: xpFrac,
                    minHeight: 5,
                    backgroundColor: cs.onSurface.withOpacity(.1),
                    color: _kGold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Armes
          Text(
            '🩴×${logic.weaponsAvailable('sandale')}  '
            '🏹×${logic.weaponsAvailable('arc')}  '
            '🗡️×${logic.weaponsAvailable('epee')}',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Colonne Mon Or ────────────────────────────────────────────────────────────

class _MonOrColumn extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _MonOrColumn({required this.logic, required this.sync});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GoldSheetBody(
        logic: logic,
        sync: sync,
        scrollController: ScrollController(),
      ),
    );
  }
}

// ── Colonne Aujourd'hui ───────────────────────────────────────────────────────

class _AujourdhuiColumn extends StatelessWidget {
  final AppLogic logic;
  final String ymd;
  final ColorScheme cs;
  const _AujourdhuiColumn(
      {required this.logic, required this.ymd, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Aujourd\'hui',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: DailyScheduleView(
            logic: logic,
            date: ymd,
          ),
        ),
      ],
    );
  }
}

// ── Colonne Exploration ───────────────────────────────────────────────────────

class _ExplorationBar extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final String ymd;
  final ColorScheme cs;
  const _ExplorationBar(
      {required this.logic,
      required this.sync,
      required this.ymd,
      required this.cs});

  @override
  Widget build(BuildContext context) {
    final level = logic.effectiveLevel();
    final biome = expeditionBiome(level + 1);
    final inDungeon = logic.state.expeditionDonjonLevel > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Exploration',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Niveau actuel : $level',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withOpacity(.55))),
          const SizedBox(height: 16),

          // Overworld
          _ExploreBtn(
            emoji: biome.emoji,
            title: 'Carte overworld',
            subtitle: 'Explore ${biome.label} · niveau ${level + 1}',
            color: _kGold,
            onTap: () => showExpeditionGame(context, logic, sync),
          ),
          const SizedBox(height: 10),

          // Donjon
          _ExploreBtn(
            emoji: inDungeon ? '🏰' : '🔒',
            title: inDungeon ? 'Continuer le donjon' : 'Donjon',
            subtitle: inDungeon
                ? 'Reprends où tu t\'es arrêté'
                : 'Atteins le château sur la carte d\'abord',
            color: const Color(0xFF8B5CF6),
            onTap: inDungeon
                ? () => showExpeditionSheet(context, logic, sync)
                : null,
          ),
          const SizedBox(height: 10),

          // Chasse
          _ExploreBtn(
            emoji: '🏹',
            title: 'Chasse',
            subtitle: 'Farm les nuisibles pour leur butin',
            color: const Color(0xFF0EA5E9),
            onTap: () => showExpeditionGame(context, logic, sync, huntLevel: level),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),

          _PestSummary(logic: logic, cs: cs),
        ],
      ),
    );
  }
}

class _ExploreBtn extends StatelessWidget {
  final String emoji, title, subtitle;
  final Color color;
  final VoidCallback? onTap;
  const _ExploreBtn({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(.35)),
          ),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: cs.onSurface.withOpacity(.35), size: 18),
          ]),
        ),
      ),
    );
  }
}

// Résumé des combats engagés dans la colonne exploration
class _PestSummary extends StatelessWidget {
  final AppLogic logic;
  final ColorScheme cs;
  const _PestSummary({required this.logic, required this.cs});

  @override
  Widget build(BuildContext context) {
    final combats = logic.combatsInProgress();
    if (combats.isEmpty) {
      return Text('Aucun combat en cours.',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.45)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Combats en cours',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withOpacity(.5),
                letterSpacing: .5)),
        const SizedBox(height: 8),
        for (final c in combats.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Text(entityEmoji(c.type), style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(logic.enemyItemName(c.type, c.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: c.maxHp > 0
                            ? (c.hp / c.maxHp).clamp(0.0, 1.0)
                            : 0,
                        minHeight: 4,
                        backgroundColor: cs.onSurface.withOpacity(.08),
                        color: const Color(0xFFE24A4A).withOpacity(.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('❤️ ${c.hp}',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurface.withOpacity(.5))),
            ]),
          ),
      ],
    );
  }
}
