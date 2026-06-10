import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/gold_purchase.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/expedition_map_game.dart';
import 'package:productivitwo_v1/widgets/expedition_sheet.dart';
import 'package:productivitwo_v1/widgets/collection_sheet.dart';
import 'package:productivitwo_v1/widgets/gold_shop_sheet.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';

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
      builder: (_, scroll) =>
          GoldSheetBody(logic: logic, sync: sync, scrollController: scroll),
    );
  }
}

/// Contenu embarquable du tableau d'Or (réutilisé par le hub gamification).
class GoldSheetBody extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ScrollController? scrollController;
  final RoutineLaunch? onLaunchRoutine;
  const GoldSheetBody(
      {super.key,
      required this.logic,
      required this.sync,
      this.scrollController,
      this.onLaunchRoutine});

  @override
  State<GoldSheetBody> createState() => _GoldSheetBodyState();
}

class _GoldSheetBodyState extends State<GoldSheetBody> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;
  ScrollController? get scrollController => widget.scrollController;

  @override
  void initState() {
    super.initState();
    // Crédite les gains du jour sur le solde affiché (dépensables de suite).
    logic.reconcileLiveGold(widget.sync);
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
                      visualDensity: VisualDensity.compact),
                  onPressed: () {
                    Navigator.pop(context);
                    showGoldShopSheet(context, logic, sync);
                  },
                ),
              ]),
            ],
          ),
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
                      visualDensity: VisualDensity.compact),
                  child: const Text('Explorer'),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Text('🗺️', style: TextStyle(fontSize: 14)),
            label: const Text('Ma collection'),
            onPressed: () => showCollectionSheet(context, logic),
          ),
          const SizedBox(height: 20),

          // ── Routines du jour ──────────────────────────────────────────────
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
        ],
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(validated ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20, color: validated ? green : cs.onSurface.withOpacity(.3)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(activity.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: validated ? green : null)),
              Row(children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '+$gain'),
                    goldIconSpan(size: 11),
                  ]),
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: green),
                ),
                if (tgt > 1) ...[
                  const SizedBox(width: 8),
                  Text('$done/$tgt',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurface.withOpacity(.5))),
                ],
              ]),
            ],
          ),
        ),
        if (onLaunch != null &&
            (activity.linkedActivityId ?? '').trim().isNotEmpty) ...[
          _launchBtn(Icons.play_arrow_rounded, 'Démarrer le chrono',
              () => onLaunch!(activity, timer: false)),
          _launchBtn(
              Icons.timer_outlined,
              (activity.timerMin ?? 0) > 0
                  ? 'Démarrer le minuteur (${activity.timerMin} min)'
                  : 'Démarrer le minuteur (5 min)',
              () => onLaunch!(activity, timer: true)),
        ],
        _StepBtn(
            icon: Icons.remove,
            enabled: done > 0,
            onTap: () {
              logic.incHabit(activity.id, -1, today);
              onChanged();
            },
            cs: cs),
        SizedBox(
          width: 22,
          child: Text('$done',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        _StepBtn(
            icon: Icons.add,
            enabled: true,
            onTap: () {
              logic.incHabit(activity.id, 1, today);
              onChanged();
            },
            cs: cs),
        if (bleeding) ...[
          const SizedBox(width: 6),
          const _LossPill(compact: true),
          TextButton(
            onPressed: () => _freeze(context),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4)),
            child: const Text('Geler', style: TextStyle(fontSize: 12)),
          ),
        ],
      ]),
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
