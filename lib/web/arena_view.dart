import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/pulse.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/backlog_combat.dart' show showBacklogCombat;
import 'package:productivitwo_v1/widgets/expedition_map_game.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';
import 'package:productivitwo_v1/widgets/gold_sheet.dart';
import 'package:productivitwo_v1/web/labs_view.dart';
import 'package:productivitwo_v1/web/province_card.dart';
import 'package:productivitwo_v1/web/daily_stake_card.dart';
import 'package:productivitwo_v1/web/unified_world_sheet.dart';

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
  // Basé sur la SESSION OUVERTE de `logic` (logic.start ouvre une session ;
  // le combat la déclenche). On l'affiche, et au stop on la ferme + sauvegarde.
  Timer? _ticker;
  int? _targetMin; // objectif affiché (null = chrono libre)

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
      // Branche le minuteur du combat sur le chrono de l'Arène : le combat a
      // déjà ouvert la session (logic.start) ; le hook ne fait qu'enregistrer
      // l'objectif d'affichage + rafraîchir (sinon les boutons « 25 min » sont
      // no-op sur le web).
      logic.launchTimerHook = (min, name,
          {String? routineId, String? expeditionNodeId, int expeditionBonus = 0}) {
        _targetMin = min;
        if (mounted) setState(() {});
      };

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
        // Préserve les sessions ouvertes non encore sauvegardées (chrono en
        // cours) — sinon le re-pull les effacerait et perdrait le minuteur.
        final openSessions =
            _logic?.state.sessions.where((s) => s.endAt == null).toList() ??
                const [];
        _logic?.state = fresh;
        _logic?.currentProjects = saved;
        for (final s in openSessions) {
          if (!fresh.sessions.any((x) => x.id == s.id)) fresh.sessions.add(s);
        }
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  /// Session de temps en cours (ouverte par le combat via logic.start).
  Session? get _openSession {
    final l = _logic;
    if (l == null) return null;
    Session? last;
    for (final s in l.state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  String _runningActivityName() {
    final s = _openSession;
    if (s == null) return 'Activité';
    for (final a in _logic!.state.activities) {
      if (a.id == s.activityId) return a.name;
    }
    return 'Activité';
  }

  // Démarre/arrête le ticker selon qu'une session est ouverte (appelé en build).
  void _syncTicker() {
    final running = _openSession != null;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  Future<void> _stopTimer() async {
    final s = _openSession;
    if (s == null) return;
    s.endAt = DateTime.now(); // ferme la session
    await sync.saveSession(s); // persiste → le temps réduit les ennemis
    _targetMin = null;
    _ticker?.cancel();
    _ticker = null;
    _logic?.reconcileLiveGold(sync); // l'or du jour intègre le temps loggué
    _logic?.onChange();
    if (mounted) setState(() {});
  }

  void _cancelTimer() {
    // Annule : retire la session ouverte sans la sauvegarder.
    _logic?.state.sessions.removeWhere((s) => s.endAt == null);
    _targetMin = null;
    _ticker?.cancel();
    _ticker = null;
    _logic?.onChange();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _metaSub?.cancel();
    _projectsSub?.cancel();
    super.dispose();
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
    _syncTicker();
    final open = _openSession;
    final elapsed = open == null
        ? Duration.zero
        : DateTime.now().difference(open.startAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatsBar(logic: logic, cs: cs),
        // ── Mise du jour (déplacée depuis l'onglet Focus) ─────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFC9A84C).withOpacity(.35)),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: const [
                  Icon(Icons.casino_outlined,
                      size: 16, color: Color(0xFFC9A84C)),
                  SizedBox(width: 6),
                  Text('Mise du jour',
                      style: TextStyle(
                          color: Color(0xFFC9A84C),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
                const SizedBox(height: 8),
                DailyStakeCard(sync: sync),
              ],
            ),
          ),
        ),
        // ── Bandeau chrono (session de temps en cours) ────────────────────────
        if (open != null)
          _TimerBanner(
            label: _runningActivityName() +
                (_targetMin != null ? '  · objectif ${_targetMin!} min' : ''),
            elapsed: _fmtElapsed(elapsed),
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
                    _ExplorationColumn(logic: logic, sync: sync, cs: cs),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 520,
                      child: _BoutiqueColumn(logic: logic, sync: sync),
                    ),
                  ],
                ),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Col gauche : Combats (cœur de l'action) — flex 5
                Flexible(
                  flex: 5,
                  child: _CombatsColumn(logic: logic, sync: sync, cs: cs,
                      onChanged: () => setState(() {})),
                ),
                const VerticalDivider(width: 1),
                // Col centre : Exploration (promue) — flex 4
                Flexible(
                  flex: 4,
                  child: _ExplorationColumn(logic: logic, sync: sync, cs: cs),
                ),
                const VerticalDivider(width: 1),
                // Col droite : Or & Boutique — flex 4
                Flexible(
                  flex: 4,
                  child: _BoutiqueColumn(logic: logic, sync: sync),
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
        for (final w in const ['couteau', 'arc', 'epee']) ...[
          _WeaponChip(
              emoji: logic.weaponEmoji(w), n: logic.weaponsAvailable(w), cs: cs),
          if (w != 'epee') const SizedBox(width: 6),
        ],
      ]),
    );
  }
}

// Petite puce d'arme (compteur réel) — cohérente avec les chips du dialogue.
class _WeaponChip extends StatelessWidget {
  final String emoji;
  final int n;
  final ColorScheme cs;
  const _WeaponChip(
      {required this.emoji, required this.n, required this.cs});

  @override
  Widget build(BuildContext context) {
    final empty = n <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: empty
            ? cs.onSurface.withOpacity(.04)
            : _kGold.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: empty
                ? cs.outline.withOpacity(.15)
                : _kGold.withOpacity(.35)),
      ),
      child: Text('$emoji $n',
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: empty ? cs.onSurface.withOpacity(.4) : _kGold)),
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outline.withOpacity(.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Aucun combat engagé',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface.withOpacity(.7))),
                  const SizedBox(height: 4),
                  Text(
                      'Tes routines en retard, activités et tâches deviennent des nuisibles sur la carte. Engage-en un pour le suivre ici.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withOpacity(.45))),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => showExpeditionGame(context, logic, sync),
                    icon: const Text('🗺️', style: TextStyle(fontSize: 14)),
                    label: const Text('Aller à la carte'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kRed,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              // Cartes plus riches (récompense + sbires + CTA de phase) →
              // ratio abaissé pour leur donner de la hauteur (anti-overflow).
              childAspectRatio: .58,
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
    final sbires = logic.sbiresLeft(type, itemId);
    final exposed = sbires <= 0;
    final minionW = GoldEconomy.minionWeaponForPest(type);
    final wEmoji = logic.weaponEmoji(minionW);
    final myWeapons = logic.weaponsAvailable(minionW);
    final loot = GoldEconomy.pestLootBase(type, false);
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
              BoxShadow(
                  color: _kRed.withOpacity(exposed ? .5 : .25),
                  blurRadius: exposed ? 22 : 12,
                  spreadRadius: exposed ? 2 : 1),
              BoxShadow(color: Colors.black.withOpacity(.6), blurRadius: 6, offset: const Offset(0, 3)),
            ],
            border: Border.all(
                color: exposed
                    ? _kRed.withOpacity(.6)
                    : domColor.withOpacity(.4),
                width: exposed ? 1.5 : 1),
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
                    const SizedBox(width: 4),
                    // Ta tourelle fait feu sur le nuisible.
                    SvgPicture.asset('assets/icons/turret.svg',
                        width: 16,
                        height: 16,
                        colorFilter: ColorFilter.mode(
                            _kRed.withOpacity(.85), BlendMode.srcIn)),
                    SvgPicture.asset('assets/icons/gunshot.svg',
                        width: 12,
                        height: 12,
                        colorFilter: const ColorFilter.mode(
                            Color(0xFFFFC83D), BlendMode.srcIn)),
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
                  const SizedBox(height: 4),
                  Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '🏆 +$loot'),
                        goldIconSpan(size: 11),
                      ]),
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE8C24A),
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
                  // Cœurs (plafonnés à 8 cellules — au-delà, compteur seul pour
                  // ne pas faire déborder la carte ; la barre PV donne le détail)
                  if (maxHp <= 8)
                    Wrap(
                      spacing: 1,
                      children: [
                        for (int i = 0; i < maxHp; i++)
                          Text(i < maxHp - hp ? '✅' : '❤️',
                              style: const TextStyle(
                                  fontSize: 10,
                                  decoration: TextDecoration.none)),
                      ],
                    )
                  else
                    Text('❤️ $hp/$maxHp',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            decoration: TextDecoration.none)),
                  const SizedBox(height: 4),
                  // Sbires (gardes du cœur) — mini-emojis + arme à dépenser
                  if (sbires > 0)
                    Wrap(
                      spacing: 1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (int i = 0; i < sbires.clamp(0, 5); i++)
                          Text(entityEmoji(type),
                              style: const TextStyle(
                                  fontSize: 9,
                                  decoration: TextDecoration.none)),
                        Text('  $sbires · −1 $wEmoji ',
                            style: TextStyle(
                                fontSize: 8.5,
                                color: Colors.white.withOpacity(.4),
                                decoration: TextDecoration.none)),
                        // Munitions restantes.
                        SvgPicture.asset('assets/icons/rifle.svg',
                            width: 9,
                            height: 9,
                            colorFilter: ColorFilter.mode(
                                myWeapons >= 1
                                    ? const Color(0xFFE8C24A)
                                    : _kRed.withOpacity(.85),
                                BlendMode.srcIn)),
                        const SizedBox(width: 1),
                        Text('($myWeapons)',
                            style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: myWeapons >= 1
                                    ? const Color(0xFFE8C24A)
                                    : _kRed.withOpacity(.85),
                                decoration: TextDecoration.none)),
                      ],
                    )
                  else
                    Text('💓 cœur exposé',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _kRed.withOpacity(.85),
                            decoration: TextDecoration.none)),
                  const SizedBox(height: 8),
                  // Bouton ouvrir — CTA de phase, pulse quand on peut achever
                  PulseScale(
                    active: exposed,
                    maxScale: 1.05,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: exposed ? _kRed : _kRed.withOpacity(.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _kRed.withOpacity(exposed ? 1 : .4)),
                      ),
                      child: Text(exposed ? '💓 Achever le cœur' : '⚔️ Combattre',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: exposed ? Colors.white : _kRed,
                              decoration: TextDecoration.none)),
                    ),
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

// ── Colonne Exploration (promue : « où jouer ») ───────────────────────────────

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

    final domains = logic.state.activeDomains;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Dashboard ROYAUME : tes domaines de vie en PROVINCES ──────────
          Row(children: const [
            Text('🏰 ', style: TextStyle(fontSize: 16)),
            Text('Royaume',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text('Tes domaines de vie, en provinces — niveau, prospérité, menaces.',
              style:
                  TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.55))),
          const SizedBox(height: 12),
          if (domains.isEmpty)
            Text('Aucun domaine — crée-en pour bâtir ton royaume.',
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurface.withOpacity(.45)))
          else
            for (final d in domains) ...[
              ProvinceCard(
                logic: logic,
                domain: d,
                onTap: () => showUnifiedWorldSheet(context, logic, sync),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 8),
          // CTA principal : entrer dans le Monde (la grande carte unifiée).
          _ExploreBtn(
            emoji: '⚔️',
            title: 'Entrer dans le Monde',
            subtitle: 'Une seule grande carte : farm · château · grottes (avatar)',
            color: const Color(0xFF14B8A6),
            onTap: () => showUnifiedWorldSheet(context, logic, sync),
          ),
          const SizedBox(height: 18),
          const Text('EXPLORATION',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 10),
          // Bandeau biome courant
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_kGold.withOpacity(.18), _kGold.withOpacity(.04)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kGold.withOpacity(.3)),
            ),
            child: Row(children: [
              Text(biome.emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(biome.label,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    Text('Niveau ${level + 1} à explorer',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurface.withOpacity(.6))),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          _ExploreBtn(
            emoji: biome.emoji,
            title: 'Carte overworld',
            subtitle: 'Explore, ramasse des armes, engage les nuisibles',
            color: _kGold,
            onTap: () => showExpeditionGame(context, logic, sync),
          ),
          // Modes expérimentaux (Donjon, Mes cartes, Docks, Invasion) déplacés
          // dans « Labs » pour redonner de la cohérence à la boucle principale.
          if (kLabsEnabled) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showLabsSheet(context, logic, sync),
                icon: const Icon(Icons.science_outlined, size: 16),
                label: const Text('Labs (expérimental)'),
                style: TextButton.styleFrom(
                    foregroundColor: cs.onSurface.withOpacity(.55)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Colonne Or & Boutique ─────────────────────────────────────────────────────

class _BoutiqueColumn extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _BoutiqueColumn({required this.logic, required this.sync});

  @override
  Widget build(BuildContext context) {
    // GoldSheetBody = solde, butin du jour, boutique, collection, historique.
    // Combats masqués (déjà dans la colonne gauche).
    return GoldSheetBody(logic: logic, sync: sync, showCombatSection: false);
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
