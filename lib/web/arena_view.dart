import 'dart:async';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/backlog_combat.dart' show showBacklogCombat;
import 'package:productivitwo_v1/widgets/daily_schedule_view.dart';
import 'package:productivitwo_v1/widgets/expedition_map_game.dart';
import 'package:productivitwo_v1/widgets/expedition_sheet.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';
import 'package:productivitwo_v1/widgets/gold_sheet.dart';

const _kGold = Color(0xFFD4A017);
const _kCardBg = Color(0xFF120A0A);
const _kRed = Color(0xFFFF2B2B);

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

  // ── Chronomètre ─────────────────────────────────────────────────────────────
  DateTime? _timerStart;
  String? _timerActivityId;
  String? _timerActivityName;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

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

      final projects = await sync.fetchProjects();
      logic.updateGanttCounts(projects);

      if (!mounted) return;
      setState(() { _logic = logic; _loading = false; });

      _projectsSub = sync.streamProjects().listen((p) {
        _logic?.updateGanttCounts(p);
        if (mounted) setState(() {});
      });

      _metaSub = sync.streamMetaDoc().listen((_) async {
        final fresh = await sync.pull();
        if (fresh == null || !mounted) return;
        final saved = _logic?.currentProjects ?? [];
        _logic?.state = fresh;
        _logic?.currentProjects = saved;
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _startTimer(ScheduleBlock block) {
    final actId = block.activityId;
    if (actId == null || actId.isEmpty) return;
    final name = block.title;
    _ticker?.cancel();
    setState(() {
      _timerStart = DateTime.now();
      _timerActivityId = actId;
      _timerActivityName = name;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = DateTime.now().difference(_timerStart!));
    });
  }

  Future<void> _stopTimer() async {
    _ticker?.cancel();
    _ticker = null;
    final start = _timerStart;
    final actId = _timerActivityId;
    if (start == null || actId == null) return;
    final end = DateTime.now();
    final session = Session(activityId: actId, startAt: start, endAt: end);
    // Persiste en Firestore
    await sync.saveSession(session);
    // Met à jour l'état local pour que l'or se recalcule
    _logic?.state.sessions.add(session);
    _logic?.onChange();
    if (mounted) {
      setState(() {
        _timerStart = null;
        _timerActivityId = null;
        _timerActivityName = null;
        _elapsed = Duration.zero;
      });
    }
  }

  void _cancelTimer() {
    _ticker?.cancel();
    _ticker = null;
    if (mounted) setState(() {
      _timerStart = null;
      _timerActivityId = null;
      _timerActivityName = null;
      _elapsed = Duration.zero;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _metaSub?.cancel();
    _projectsSub?.cancel();
    super.dispose();
  }

  String _ymd() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String _fmtElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _logic == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          Text(_error ?? 'Erreur inconnue'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () { setState(() { _loading = true; _error = null; }); _load(); },
            child: const Text('Réessayer'),
          ),
        ]),
      );
    }

    final logic = _logic!;
    final cs = Theme.of(context).colorScheme;
    final ymd = _ymd();
    final timerActive = _timerStart != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatsBar(logic: logic, cs: cs),
        // ── Bandeau chrono ────────────────────────────────────────────────────
        if (timerActive)
          _TimerBanner(
            label: _timerActivityName ?? 'Activité',
            elapsed: _fmtElapsed(_elapsed),
            onStop: _stopTimer,
            onCancel: _cancelTimer,
          ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CombatsColumn(logic: logic, sync: sync, cs: cs,
                        onChanged: () => setState(() {})),
                    const SizedBox(height: 16),
                    _AujourdhuiColumn(logic: logic, ymd: ymd, cs: cs,
                        onLaunch: _startTimer),
                    const SizedBox(height: 16),
                    _ExplorationColumn(logic: logic, sync: sync, cs: cs),
                  ],
                ),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Col gauche : Combats (cartes héro) — flex 3
                Flexible(
                  flex: 3,
                  child: _CombatsColumn(logic: logic, sync: sync, cs: cs,
                      onChanged: () => setState(() {})),
                ),
                const VerticalDivider(width: 1),
                // Col centre : Aujourd'hui — flex 4
                Flexible(
                  flex: 4,
                  child: _AujourdhuiColumn(logic: logic, ymd: ymd, cs: cs,
                      onLaunch: _startTimer),
                ),
                const VerticalDivider(width: 1),
                // Col droite : Exploration — flex 3
                Flexible(
                  flex: 3,
                  child: _ExplorationColumn(logic: logic, sync: sync, cs: cs),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

// ── Bandeau chronomètre ───────────────────────────────────────────────────────

class _TimerBanner extends StatelessWidget {
  final String label, elapsed;
  final Future<void> Function() onStop;
  final VoidCallback onCancel;
  const _TimerBanner({
    required this.label,
    required this.elapsed,
    required this.onStop,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D2010),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(children: [
        const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF4ADE80)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '⏱ $label',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: Color(0xFF4ADE80),
                decoration: TextDecoration.none),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          elapsed,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
              color: Color(0xFF4ADE80),
              decoration: TextDecoration.none),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded, size: 15),
          label: const Text('Terminer', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close, size: 16, color: Color(0xFF4ADE80)),
          tooltip: 'Annuler',
          onPressed: onCancel,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }
}

// ── Stats bar ─────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final AppLogic logic;
  final ColorScheme cs;
  const _StatsBar({required this.logic, required this.cs});

  @override
  Widget build(BuildContext context) {
    final d = logic.userLevelData();
    final range = d.xpNext - d.xpCurrent;
    final frac = range > 0 ? ((d.xp - d.xpCurrent) / range).clamp(0.0, 1.0) : 0.0;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(children: [
        goldAmount('${logic.state.gold}', fontSize: 16, weight: FontWeight.w800),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Niv. ${d.level} · ${d.title}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: frac, minHeight: 5,
                  backgroundColor: cs.onSurface.withOpacity(.1),
                  color: _kGold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Text(
          '🩴×${logic.weaponsAvailable('sandale')}  '
          '🏹×${logic.weaponsAvailable('arc')}  '
          '🗡️×${logic.weaponsAvailable('epee')}',
          style: const TextStyle(fontSize: 13),
        ),
      ]),
    );
  }
}

// ── Colonne Combats (cartes héro) ─────────────────────────────────────────────

class _CombatsColumn extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ColorScheme cs;
  final VoidCallback onChanged;
  const _CombatsColumn({
    required this.logic,
    required this.sync,
    required this.cs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final combats = logic.combatsInProgress();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('⚔️ Combats en cours',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            if (combats.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _kRed.withOpacity(.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${combats.length}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800,
                        color: _kRed)),
              ),
          ]),
          const SizedBox(height: 12),
          if (combats.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Aucun combat engagé.\nVa sur la carte → engage un nuisible.',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.45)),
              ),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: .72,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final c in combats)
                  _HeroCombatCard(
                    logic: logic,
                    sync: sync,
                    type: c.type,
                    itemId: c.id,
                    hp: c.hp,
                    maxHp: c.maxHp,
                    onChanged: onChanged,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// Carte héro mini pour un combat engagé
class _HeroCombatCard extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final String type, itemId;
  final int hp, maxHp;
  final VoidCallback onChanged;
  const _HeroCombatCard({
    required this.logic,
    required this.sync,
    required this.type,
    required this.itemId,
    required this.hp,
    required this.maxHp,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final name = logic.enemyItemName(type, itemId);
    final domainId = logic.enemyDomainId(type, itemId);
    final domColor = domainColor(domainId, logic.state.activeDomains) ??
        _kRed;
    final hpFrac = maxHp > 0 ? (hp / maxHp).clamp(0.0, 1.0) : 0.0;
    final role = switch (type) {
      'snake' => 'Tâche',
      'scorpion' => 'En retard',
      _ => 'Routine',
    };

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showBacklogCombat(context, logic, sync, type, itemId,
            onChanged: onChanged),
        child: Ink(
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: _kRed.withOpacity(.25), blurRadius: 12, spreadRadius: 1),
              BoxShadow(color: Colors.black.withOpacity(.6), blurRadius: 6, offset: const Offset(0, 3)),
            ],
            border: Border.all(color: domColor.withOpacity(.4), width: 1),
          ),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barre domaine couleur en haut
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: domColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(entityEmoji(type),
                        style: const TextStyle(
                            fontSize: 22, decoration: TextDecoration.none)),
                    const Spacer(),
                    Text(role,
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: _kRed.withOpacity(.8),
                            letterSpacing: .4,
                            decoration: TextDecoration.none)),
                  ]),
                  const SizedBox(height: 6),
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          decoration: TextDecoration.none)),
                  const SizedBox(height: 8),
                  // Barre PV
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: hpFrac,
                      minHeight: 4,
                      backgroundColor: Colors.white.withOpacity(.08),
                      color: _kRed.withOpacity(.75),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Cœurs
                  Wrap(
                    spacing: 1,
                    children: [
                      for (int i = 0; i < maxHp; i++)
                        Text(i < maxHp - hp ? '✅' : '❤️',
                            style: const TextStyle(
                                fontSize: 10, decoration: TextDecoration.none)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Bouton ouvrir
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: _kRed.withOpacity(.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kRed.withOpacity(.4)),
                    ),
                    child: const Text('⚔️ Combattre',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _kRed,
                            decoration: TextDecoration.none)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}

// ── Colonne Aujourd'hui ───────────────────────────────────────────────────────

class _AujourdhuiColumn extends StatelessWidget {
  final AppLogic logic;
  final String ymd;
  final ColorScheme cs;
  final void Function(ScheduleBlock block) onLaunch;
  const _AujourdhuiColumn({
    required this.logic,
    required this.ymd,
    required this.cs,
    required this.onLaunch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text("Aujourd'hui",
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DailyScheduleView(date: ymd, logic: logic, onLaunch: onLaunch),
          ),
        ),
      ],
    );
  }
}

// ── Colonne Exploration ───────────────────────────────────────────────────────

class _ExplorationColumn extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ColorScheme cs;
  const _ExplorationColumn(
      {required this.logic, required this.sync, required this.cs});

  @override
  Widget build(BuildContext context) {
    final level = logic.effectiveLevel();
    final biome = expeditionBiome(level + 1);
    final inDungeon = logic.state.expeditionDonjonLevel > 0;

    // GoldSheetBody retourne un ListView qui requiert une hauteur bornée.
    // On le met dans Expanded, et la section Exploration sous la divider.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Magasin ─────────────────────────────────────────────────────────
        Expanded(
          child: GoldSheetBody(logic: logic, sync: sync),
        ),
        const Divider(height: 1),
        // ── Exploration ─────────────────────────────────────────────────────
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Exploration',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Niveau : $level',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.55))),
              const SizedBox(height: 16),
              _ExploreBtn(
                emoji: biome.emoji,
                title: 'Carte overworld',
                subtitle: '${biome.label} · niveau ${level + 1}',
                color: _kGold,
                onTap: () => showExpeditionGame(context, logic, sync),
              ),
              const SizedBox(height: 10),
              _ExploreBtn(
                emoji: inDungeon ? '🏰' : '🔒',
                title: inDungeon ? 'Reprendre le donjon' : 'Donjon',
                subtitle: inDungeon
                    ? 'Reprends où tu t\'es arrêté'
                    : 'Atteins le château sur la carte d\'abord',
                color: const Color(0xFF8B5CF6),
                onTap: inDungeon ? () => showExpeditionSheet(context, logic, sync) : null,
              ),
              const SizedBox(height: 10),
              _ExploreBtn(
                emoji: '🏹',
                title: 'Chasse',
                subtitle: 'Farm les nuisibles pour leur butin',
                color: const Color(0xFF0EA5E9),
                onTap: () => showExpeditionGame(context, logic, sync, huntLevel: level),
              ),
            ],
          ),
        ),
      ],
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
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11.5, color: cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(.35), size: 18),
          ]),
        ),
      ),
    );
  }
}
