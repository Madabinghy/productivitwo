import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/gold_purchase.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/backlog_combat.dart';
import 'package:productivitwo_v1/widgets/expedition_map_game.dart';
import 'package:productivitwo_v1/widgets/expedition_sheet.dart';
import 'package:productivitwo_v1/widgets/collection_sheet.dart';
import 'package:productivitwo_v1/web/unified_world_sheet.dart';
import 'package:productivitwo_v1/widgets/confetti.dart';
import 'package:productivitwo_v1/widgets/gold_shop_sheet.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';
import 'package:productivitwo_v1/widgets/pulse.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

/// Tableau de bord d'Or (Phase C) : solde + niveau, ce qui rapporte, ce qui
/// coûte/risque (routines qui saignent, tâches en retard), et l'historique.
Future<void> showGoldSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GoldSheet(logic: logic, sync: sync),
  );
}

const _kGold = Color(0xFFD4A017);

/// Lance une routine depuis « Mon or » : [timer]=true → minuteur (défaut 5 min
/// si la routine n'a pas de durée), false → chrono libre. Câblé sur l'accueil.
typedef RoutineLaunch = void Function(Activity routine, {required bool timer});

class _GoldSheet extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _GoldSheet({required this.logic, required this.sync});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => GoldSheetBody(
          logic: logic,
          sync: sync,
          scrollController: scroll,
          embeddedInSheet: true),
    );
  }
}

/// Contenu embarquable du tableau d'Or (réutilisé par le hub gamification).
class GoldSheetBody extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ScrollController? scrollController;
  final RoutineLaunch? onLaunchRoutine;
  // true = intégré dans un modal bottom sheet (pop avant d'ouvrir la boutique)
  // false = intégré directement dans un layout (pas de pop navigation)
  final bool embeddedInSheet;
  // Sections affichables séparément (onglets du hub mobile / colonnes web) :
  // - showCombatSection : boutons « Affronter backlog »/« Mes cartes » + combats.
  // - showEconomySection : quête, solde, arsenal, niveau, boutique, retards, histo.
  final bool showCombatSection;
  final bool showEconomySection;
  const GoldSheetBody(
      {super.key,
      required this.logic,
      required this.sync,
      this.scrollController,
      this.onLaunchRoutine,
      this.embeddedInSheet = false,
      this.showCombatSection = true,
      this.showEconomySection = true});

  @override
  State<GoldSheetBody> createState() => _GoldSheetBodyState();
}

class _GoldSheetBodyState extends State<GoldSheetBody> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;
  ScrollController? get scrollController => widget.scrollController;

  // « Routines du jour » mises de côté dans Mon or (remplacées par « Combats en
  // cours »). Le code reste — repasser à true pour le réafficher.
  final bool _showRoutinesInGold = false;

  @override
  void initState() {
    super.initState();
    // Crédite les gains du jour sur le solde affiché (dépensables de suite).
    logic.reconcileLiveGold(widget.sync);
    logic.pruneEngaged(widget.sync); // nettoie les combats rattrapés
  }

  // AppLogic n'est pas un Listenable : `incHabit`/gel mutent l'état en place,
  // ce refresh local rebuild le sheet sans le rouvrir.
  void _refresh() {
    if (mounted) setState(() {});
  }

  // Après une action qui change les gains du jour (valider une routine…), on
  // recrédite le solde EN DIRECT puis on rebuild → plus besoin de rouvrir le sheet.
  void _onRoutineChanged() {
    logic.reconcileLiveGold(widget.sync);
    _refresh();
  }

  void _sellWeapon(String key) {
    if (logic.sellWeapon(key, sync) && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Vendu ${logic.weaponEmoji(key)} · +${GoldEconomy.weaponSellPrice} or'),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  Future<void> _claimChest() async {
    final reward = logic.claimDailyChest(widget.sync);
    if (!mounted) return;
    setState(() {});
    showConfetti(context);
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎁 Coffre du jour !', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GoldIcon(size: 48),
            const SizedBox(height: 8),
            Text('+${reward.gold} or',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: _kGold)),
            const SizedBox(height: 6),
            Text('🔥 Série : ${reward.streak} jour${reward.streak > 1 ? 's' : ''}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withOpacity(.75))),
            if (reward.milestone > 0)
              Text('🏆 Palier de série ! +${reward.milestone} or bonus',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D9E75))),
            if (reward.emoji != null) ...[
              const SizedBox(height: 12),
              Text(reward.emoji!, style: const TextStyle(fontSize: 40)),
              Text('${reward.name} ajouté à ta collection !',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurface.withOpacity(.7))),
            ],
          ],
        ),
        actions: [
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: _kGold,
                  foregroundColor: const Color(0xFF231900)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Génial !')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lvl = logic.userLevelData();
    final span = (lvl.xpNext - lvl.xpCurrent);
    final progress = span > 0 ? (lvl.xp - lvl.xpCurrent) / span : 0.0;
    final provisional = logic.provisionalGoldToday();
    final bleeding = logic.bleedingRoutines();
    final late = logic.lateTasks();
    final dailyRoutines = logic.state.activeActivities
        .where((a) =>
            a.isHabit && (a.habitFreq ?? HabitFreq.monthly) == HabitFreq.daily)
        .toList();
    final bleedingIds = bleeding.map((b) => b.activity.id).toSet();
    final reveal = logic.levelRevealInfo();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
          if (widget.showEconomySection) ...[
          // ── Quête du jour + coffre ────────────────────────────────────────
          _QuestCard(
            progress: logic.dailyQuestProgress(),
            target: logic.dailyQuestTarget,
            streak: logic.questStreak,
            claimable: logic.dailyChestClaimable(),
            claimedToday:
                logic.state.lastQuestClaimedYmd == yyyymmdd(DateTime.now()),
            onClaim: _claimChest,
            cs: cs,
          ),
          const SizedBox(height: 16),
          // ── Solde + niveau ────────────────────────────────────────────────
          Row(
            children: [
              const GoldIcon(size: 28),
              const SizedBox(width: 10),
              Text('${logic.gold}',
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: _kGold)),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (provisional > 0)
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '+$provisional'),
                      goldIconSpan(size: 12),
                      const TextSpan(text: ' aujourd\'hui'),
                    ]),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700),
                  ),
                const SizedBox(height: 4),
                FilledButton.icon(
                  icon: const Text('🛒', style: TextStyle(fontSize: 13)),
                  label: const Text('Boutique'),
                  style: FilledButton.styleFrom(
                      backgroundColor: _kGold,
                      foregroundColor: const Color(0xFF231900),
                      visualDensity: VisualDensity.compact),
                  onPressed: () {
                    if (widget.embeddedInSheet) Navigator.pop(context);
                    showGoldShopSheet(context, logic, sync);
                  },
                ),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          // ── Arsenal (armes dispo) — touche une arme pour la vendre ─────────
          Row(
            children: [
              Text('Arsenal',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: .5,
                      color: cs.onSurface.withOpacity(.5))),
              const Spacer(),
              for (final w in const ['couteau', 'arc', 'epee']) ...[
                Builder(builder: (_) {
                  final n = logic.weaponsAvailable(w);
                  final has = n > 0;
                  return GestureDetector(
                    onTap: has ? () => _sellWeapon(w) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: has
                            ? _kGold.withOpacity(.12)
                            : cs.onSurface.withOpacity(.04),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: has
                                ? _kGold.withOpacity(.35)
                                : cs.outline.withOpacity(.15)),
                      ),
                      child: Text('${logic.weaponEmoji(w)} $n',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: has
                                  ? _kGold
                                  : cs.onSurface.withOpacity(.4))),
                    ),
                  );
                }),
                if (w != 'epee') const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
              'Touche une arme pour la vendre (+${GoldEconomy.weaponSellPrice} or)',
              style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurface.withOpacity(.4))),
          const SizedBox(height: 16),
          // Niveau / rang
          Row(children: [
            Text(
                'Niveau ${lvl.level} · ${logic.state.activeTitle ?? lvl.title}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${lvl.xp} / ${lvl.xpNext}',
                style:
                    TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.5))),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: cs.onSurface.withOpacity(.08),
              color: _kGold,
            ),
          ),
          Text('Le rang ne descend jamais — il suit ton effort cumulé.',
              style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurface.withOpacity(.4))),
          if (reveal.pending) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: _kGold.withOpacity(.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kGold.withOpacity(.4)),
              ),
              child: Row(children: [
                const Text('🎁', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Niveau ${reveal.nextLevel} à explorer',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      Text('Titre secret — traverse la carte pour le débloquer',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(.6))),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () async {
                    if (logic.donjonAlreadyEntered) {
                      await showExpeditionSheet(context, logic, sync);
                    } else {
                      await showExpeditionGame(context, logic, sync);
                    }
                    if (context.mounted) setState(() {});
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: _kGold,
                      foregroundColor: const Color(0xFF231900),
                      visualDensity: VisualDensity.compact),
                  child: const Text('Explorer',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ],
          ], // fin section ÉCONOMIE (haut)
          if (widget.showCombatSection) ...[
          const SizedBox(height: 12),
          // Farm direct de la carte du niveau atteint (ton backlog).
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: _kGold,
                foregroundColor: const Color(0xFF231900),
                minimumSize: const Size.fromHeight(44)),
            icon: const Text('⚔️', style: TextStyle(fontSize: 15)),
            label: Text('Affronter mon backlog · niveau ${logic.effectiveLevel()}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            onPressed: () async {
              // Ne PAS fermer « Mon or » : la carte de chasse s'ouvre par-dessus
              // → en la quittant, l'user revient dans la gamification (boutique,
              // combats…) sans avoir à rouvrir le sheet.
              await showExpeditionGame(context, logic, sync,
                  huntLevel: logic.effectiveLevel());
              if (context.mounted) setState(() {});
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Text('🗺️', style: TextStyle(fontSize: 14)),
            label: const Text('Mes cartes'),
            onPressed: () => showCollectionSheet(context, logic, sync),
          ),
          const SizedBox(height: 8),
          // « Le Monde » unifié (farm + territoire + reconquête de grottes) —
          // même sheet que le web, réutilisé tel quel sur mobile.
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E8E7E),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44)),
            icon: const Text('🌍', style: TextStyle(fontSize: 15)),
            label: const Text('Le Monde',
                style: TextStyle(fontWeight: FontWeight.w800)),
            onPressed: () async {
              await showUnifiedWorldSheet(context, logic, sync);
              if (context.mounted) setState(() {});
            },
          ),
          const SizedBox(height: 20),

          // ── Combats en cours ──────────────────────────────────────────────
            Row(children: [
              Text('⚔️ Combats en cours',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: .5,
                      color: cs.onSurface.withOpacity(.6))),
              const SizedBox(width: 6),
              _InfoDot(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Combats en cours'),
                    content: const Text(
                      'Sur ta carte, « Engager » un nuisible (coût en armes 🔪🏹🗡️) '
                      'l\'épingle ici pour le retrouver sans re-fouiller la map. Pour '
                      'le vaincre, ouvre sa carte de combat et FAIS le vrai travail '
                      '(la routine, le temps sur l\'activité, ou cocher les actions).',
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Compris')),
                    ],
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final combats = logic.combatsInProgress();
              if (combats.isEmpty) {
                return _Hint(
                    'Aucun combat engagé. Sur ta carte, « Engager » un nuisible pour le suivre ici.',
                    cs);
              }
              return Column(
                children: [
                  for (final c in combats)
                    _CombatCard(
                        logic: logic,
                        sync: sync,
                        type: c.type,
                        itemId: c.id,
                        hp: c.hp,
                        maxHp: c.maxHp,
                        onChanged: _refresh,
                        cs: cs),
                ],
              );
            }),
            const SizedBox(height: 20),
          ], // fin section COMBAT
          if (widget.showEconomySection) ...[

          // ── Routines du jour (mis de côté — _showRoutinesInGold) ──────────
          if (_showRoutinesInGold) ...[
            Row(
              children: [
                Text('🔁 Routines du jour',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: .5,
                        color: cs.onSurface.withOpacity(.6))),
                const SizedBox(width: 6),
                _InfoDot(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Routines du jour'),
                      content: const Text(
                        'Coche tes routines quotidiennes ici. Chaque routine validée '
                        'rapporte de l\'or (le bonus grandit avec la série). Une routine '
                        'déjà lancée mais non faite te coûte −1 or par jour : valide-la '
                        'ou gèle-la pour stopper la perte.',
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Compris')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (dailyRoutines.isEmpty)
              _Hint('Aucune routine quotidienne pour l\'instant.', cs)
            else
              for (final a in dailyRoutines)
                _RoutineLine(
                  logic: logic,
                  sync: sync,
                  activity: a,
                  bleeding: bleedingIds.contains(a.id),
                  onChanged: _onRoutineChanged,
                  onLaunch: widget.onLaunchRoutine,
                  cs: cs,
                ),
            const SizedBox(height: 20),
          ],

          // ── Tâches en retard ──────────────────────────────────────────────
          if (late.isNotEmpty) ...[
            Text('⚠️ Tâches en retard',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: .5,
                    color: cs.onSurface.withOpacity(.6))),
            const SizedBox(height: 8),
            for (final l in late)
              _RiskRow(
                icon: Icons.schedule_outlined,
                color: Colors.red,
                title: '« ${l.task.title} »',
                subtitle: '${l.daysLate} j de retard',
                cs: cs,
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Demander conseil à ORION'),
              onPressed: () async {
                final ok = await sync.triggerOrionTask('gold_review');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? 'ORION analyse ton or — son conseil arrive dans tes messages.'
                        : 'Impossible de joindre ORION (réessaie plus tard).'),
                  ));
                }
              },
            ),
            const SizedBox(height: 20),
          ],

          // ── Historique ────────────────────────────────────────────────────
          _SectionTitle('Historique', cs),
          StreamBuilder<List<GoldLedgerEntry>>(
            stream: sync.streamGoldLedger(limit: 60),
            builder: (context, snap) {
              final items = snap.data ?? const <GoldLedgerEntry>[];
              if (items.isEmpty) {
                return _Hint('Aucun mouvement d\'or pour l\'instant.', cs);
              }
              return Column(
                children: [
                  for (final e in items) _LedgerRow(entry: e, cs: cs),
                ],
              );
            },
          ),
          ], // fin section ÉCONOMIE (bas)
        ],
      );
    }
}

/// Carte « Quête du jour » : objectif d'actions du jour → coffre à récompense
/// variable. Dégradé doré + bouton quand le coffre est prêt (effet d'appel).
class _QuestCard extends StatelessWidget {
  final int progress, target, streak;
  final bool claimable, claimedToday;
  final Future<void> Function() onClaim;
  final ColorScheme cs;
  const _QuestCard({
    required this.progress,
    required this.target,
    required this.streak,
    required this.claimable,
    required this.claimedToday,
    required this.onClaim,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final pct = target > 0 ? (progress / target).clamp(0.0, 1.0) : 0.0;
    final remaining = (target - progress).clamp(0, target);
    final dark = const Color(0xFF3A2D00);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: claimable
              ? [const Color(0xFFFFE08A), const Color(0xFFD4A017)]
              : [
                  cs.surfaceContainerHighest.withOpacity(.5),
                  cs.surfaceContainerHighest.withOpacity(.3)
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kGold.withOpacity(claimable ? .7 : .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🎯', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text('Quête du jour',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: claimable ? dark : cs.onSurface)),
            if (streak > 0) ...[
              const SizedBox(width: 8),
              Text('🔥$streak',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: claimable ? dark : cs.onSurface.withOpacity(.8))),
            ],
            const Spacer(),
            Text('$progress/$target',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: claimable ? dark : cs.onSurface.withOpacity(.6))),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 7,
              backgroundColor: claimable
                  ? Colors.black.withOpacity(.22)
                  : Colors.black.withOpacity(.12),
              color: claimable ? dark : _kGold,
            ),
          ),
          const SizedBox(height: 10),
          if (claimable)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: dark,
                    foregroundColor: const Color(0xFFFFE9A8)),
                icon: const Text('🎁', style: TextStyle(fontSize: 16)),
                label: const Text('Ouvrir le coffre',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                onPressed: () => onClaim(),
              ),
            )
          else if (claimedToday)
            Text('✅ Coffre récupéré — reviens demain',
                style:
                    TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.6)))
          else ...[
            Text(
                'Encore $remaining action${remaining > 1 ? 's' : ''} pour débloquer le coffre 🎁',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: claimable ? dark : cs.onSurface.withOpacity(.75))),
            const SizedBox(height: 3),
            Text(
                'Compte : routine validée · action de projet cochée · défi relevé.',
                style: TextStyle(
                    fontSize: 11,
                    color: (claimable ? dark : cs.onSurface).withOpacity(.6))),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  const _SectionTitle(this.label, this.cs);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: .5,
                color: cs.onSurface.withOpacity(.6))),
      );
}

class _Hint extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _Hint(this.text, this.cs);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5, color: cs.onSurface.withOpacity(.6))),
      );
}

/// Petite pastille « ⓘ » qui ouvre une explication (pour alléger le texte).
class _InfoDot extends StatelessWidget {
  final VoidCallback onTap;
  const _InfoDot({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 16,
      child: Icon(Icons.info_outline,
          size: 15, color: cs.onSurface.withOpacity(.4)),
    );
  }
}

class _RiskRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final ColorScheme cs;
  const _RiskRow(
      {required this.icon,
      required this.color,
      required this.title,
      this.subtitle,
      required this.cs});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurface.withOpacity(.5))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _LossPill(),
        ]),
      );
}

/// Pilule « perte −1 or/j » : dégradé rouge + flèche descendante + halo léger.
class _LossPill extends StatelessWidget {
  final bool compact;
  const _LossPill({this.compact = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF87171), Color(0xFFDC2626)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66DC2626),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_down_rounded,
              size: compact ? 11 : 12, color: Colors.white),
          const SizedBox(width: 3),
          Text('1 or',
              style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

/// Ligne d'une routine quotidienne dans « Mon or » : nom, gain projeté,
/// steppers +/−, chip −1/j si la routine saigne, encoche verte si validée,
/// et bouton « Geler » (achat-à-l'usage du gel) sur les routines à risque.
class _RoutineLine extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final Activity activity;
  final bool bleeding;
  final VoidCallback onChanged;
  final RoutineLaunch? onLaunch;
  final ColorScheme cs;
  const _RoutineLine({
    required this.logic,
    required this.sync,
    required this.activity,
    required this.bleeding,
    required this.onChanged,
    required this.onLaunch,
    required this.cs,
  });

  Widget _launchBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: _kGold.withOpacity(.14), shape: BoxShape.circle),
            child: Icon(icon, size: 15, color: _kGold),
          ),
        ),
      );

  Future<void> _freeze(BuildContext context) async {
    final ymd = yyyymmdd(DateTime.now());
    if ((logic.state.goldInventory['gel'] ?? 0) < 1) {
      final bought = await offerBuyConsumable(
        context,
        sync,
        itemKey: 'gel',
        price: GoldEconomy.shopGel,
        label: 'Gel de série',
        rationale:
            'Aucun gel en stock pour protéger « ${activity.name} » aujourd\'hui.',
        logic: logic,
      );
      if (!bought) return;
    }
    final ok = await sync.useGel(activity.id, ymd);
    if (ok) {
      logic.state.goldInventory['gel'] =
          (logic.state.goldInventory['gel'] ?? 1) - 1;
      logic.state.goldGelDays.add('${activity.id}_$ymd');
      logic.onChange();
      onChanged();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? '🧊 « ${activity.name} » gelée pour aujourd\'hui.'
            : 'Gel impossible.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final tgt = logic.activeHabitTarget(activity);
    final done = logic.habitValueOn(activity.id, today);
    final validated = tgt > 0 && done >= tgt;
    final gain = logic.routineGainToday(activity);
    final green = Colors.green.shade700;
    final frozen = logic.state.goldGelDays
        .contains('${activity.id}_${yyyymmdd(today)}');
    final hasLaunch = onLaunch != null &&
        (activity.linkedActivityId ?? '').trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: validated
              ? Colors.green.withOpacity(.06)
              : cs.surfaceContainerHighest.withOpacity(.35),
          borderRadius: BorderRadius.circular(14),
          border: frozen
              ? Border.all(color: Colors.lightBlue.withOpacity(.45))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                  validated
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: validated ? green : cs.onSurface.withOpacity(.3)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(activity.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: validated ? green : null)),
              ),
              _StepBtn(
                  icon: Icons.remove,
                  enabled: done > 0,
                  onTap: () {
                    logic.incHabit(activity.id, -1, today);
                    onChanged();
                  },
                  cs: cs),
              SizedBox(
                width: 24,
                child: Text('$done',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              _StepBtn(
                  icon: Icons.add,
                  enabled: true,
                  onTap: () {
                    final before = tgt > 0 && done >= tgt;
                    logic.incHabit(activity.id, 1, today);
                    final after = tgt > 0 &&
                        logic.habitValueOn(activity.id, today) >= tgt;
                    if (!before && after) showConfetti(context, count: 16);
                    onChanged();
                  },
                  cs: cs),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (frozen) const Text('🧊', style: TextStyle(fontSize: 13)),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '+$gain'),
                    goldIconSpan(size: 11),
                  ]),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: green),
                ),
                if (tgt > 1)
                  Text('$done/$tgt',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withOpacity(.5))),
                if (hasLaunch) ...[
                  _launchBtn(Icons.play_arrow_rounded, 'Démarrer le chrono',
                      () => onLaunch!(activity, timer: false)),
                  _launchBtn(
                      Icons.timer_outlined,
                      (activity.timerMin ?? 0) > 0
                          ? 'Démarrer le minuteur (${activity.timerMin} min)'
                          : 'Démarrer le minuteur (5 min)',
                      () => onLaunch!(activity, timer: true)),
                ],
                if (bleeding) ...[
                  const _LossPill(compact: true),
                  TextButton(
                    onPressed: () => _freeze(context),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6)),
                    child: const Text('Geler', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final ColorScheme cs;
  const _StepBtn(
      {required this.icon,
      required this.enabled,
      required this.onTap,
      required this.cs});
  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon, size: 18),
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        padding: EdgeInsets.zero,
        color: cs.onSurface.withOpacity(.7),
        onPressed: enabled ? onTap : null,
      );
}

class _LedgerRow extends StatelessWidget {
  final GoldLedgerEntry entry;
  final ColorScheme cs;
  const _LedgerRow({required this.entry, required this.cs});

  String _fmt(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final pos = entry.delta >= 0;
    final c = pos ? Colors.green.shade700 : cs.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5)),
              Text(_fmt(entry.ts),
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurface.withOpacity(.4))),
            ],
          ),
        ),
        const SizedBox(width: 8),
        goldAmount('${pos ? '+' : ''}${entry.delta}',
            fontSize: 13, weight: FontWeight.w700, color: c),
      ]),
    );
  }
}

/// Carte « Combat en cours » dans Mon or : tap → ouvre la carte de combat pour
/// frapper l'ennemi (sans re-fouiller la map).
class _CombatCard extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final String type, itemId;
  final int hp, maxHp;
  final VoidCallback onChanged;
  final ColorScheme cs;
  const _CombatCard(
      {required this.logic,
      required this.sync,
      required this.type,
      required this.itemId,
      required this.hp,
      required this.maxHp,
      required this.onChanged,
      required this.cs});

  /// Vrai si une session de temps est en cours sur la routine ou son activité liée.
  bool _isActivelyCombating() {
    final runId = logic.runningActivityId();
    if (runId == null) return false;
    if (type != 'spider') return false;
    if (runId == itemId) return true;
    for (final a in logic.state.activities) {
      if (a.id == itemId) {
        return (a.linkedActivityId ?? '').trim() == runId;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final name = logic.enemyItemName(type, itemId);
    final minionW = GoldEconomy.minionWeaponForPest(type);
    final wEmoji = logic.weaponEmoji(minionW);
    final myWeapons = logic.weaponsAvailable(minionW);
    final hpFrac = maxHp > 0 ? hp / maxHp : 0.0;
    final domainId = logic.enemyDomainId(type, itemId);
    final domColor = domainColor(domainId, logic.state.activeDomains) ??
        const Color(0xFFE24A4A);
    final frozen = type == 'spider' && logic.isRoutineFrozenToday(itemId);
    final fighting = _isActivelyCombating();
    final avatar = logic.state.activeAvatar ?? '🧍';
    final sbires = logic.sbiresLeft(type, itemId);
    final exposed = sbires <= 0;
    final loot = GoldEconomy.pestLootBase(type, false);
    const _kRed = Color(0xFFFF2B2B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showBacklogCombat(context, logic, sync, type, itemId,
            onChanged: onChanged),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: exposed
                  ? _kRed.withOpacity(.07)
                  : cs.surfaceContainerHighest.withOpacity(.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: exposed
                      ? _kRed.withOpacity(.5)
                      : cs.outline.withOpacity(fighting ? .5 : .18),
                  width: exposed ? 1.4 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Contenu principal ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 12, 8),
                  child: Row(children: [
                    // Barre couleur domaine à gauche (style cartes Gantt)
                    Container(
                      width: 4,
                      height: 40,
                      margin: const EdgeInsets.only(left: 8, right: 10),
                      decoration: BoxDecoration(
                        color: domColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Text(entityEmoji(type),
                        style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '❤️ $hp/$maxHp',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withOpacity(.6)),
                              ),
                              const SizedBox(width: 8),
                              Text.rich(
                                  TextSpan(children: [
                                    TextSpan(text: '🏆 +$loot'),
                                    goldIconSpan(size: 12),
                                  ]),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFD4A017))),
                              if (frozen) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.ac_unit_rounded,
                                    size: 13, color: Color(0xFF38BDF8)),
                              ],
                            ],
                          ),
                          // ── Sbires qui gardent le cœur (mêmes mini-emojis
                          // que sur la carte) + arme à dépenser ───────────────
                          if (sbires > 0) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                for (int i = 0;
                                    i < sbires.clamp(0, 5);
                                    i++)
                                  Text(entityEmoji(type),
                                      style: const TextStyle(fontSize: 11)),
                                const SizedBox(width: 5),
                                Text(
                                    '$sbires sbire${sbires > 1 ? 's' : ''}  ·  −1 $wEmoji',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color:
                                            cs.onSurface.withOpacity(.5))),
                                const SizedBox(width: 4),
                                Text('($myWeapons $wEmoji)',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: myWeapons >= 1
                                            ? const Color(0xFFD4A017)
                                            : _kRed.withOpacity(.8))),
                              ],
                            ),
                          ] else ...[
                            const SizedBox(height: 3),
                            Text('💓 cœur exposé — frappe pour achever',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _kRed.withOpacity(.9))),
                          ],
                        ],
                      ),
                    ),
                    // Pastille CTA de phase (+ avatar si combat en cours)
                    const SizedBox(width: 6),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (fighting)
                          Text(avatar, style: const TextStyle(fontSize: 18)),
                        if (fighting) const SizedBox(height: 2),
                        PulseScale(
                          active: exposed,
                          maxScale: 1.06,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: exposed
                                  ? _kRed
                                  : _kRed.withOpacity(.13),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: _kRed
                                      .withOpacity(exposed ? 1 : .35)),
                            ),
                            child: Text(
                                exposed ? '💓 Achever' : '⚔️ Combattre',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: exposed
                                        ? Colors.white
                                        : _kRed)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                  ]),
                ),
                // ── Barre de PV ──────────────────────────────────────────────
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12)),
                  child: LinearProgressIndicator(
                    value: hpFrac.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: cs.onSurface.withOpacity(.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        domColor.withOpacity(fighting ? .9 : .55)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
