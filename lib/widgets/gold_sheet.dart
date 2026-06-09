import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/gold_shop_sheet.dart';

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
class GoldSheetBody extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ScrollController? scrollController;
  const GoldSheetBody(
      {super.key,
      required this.logic,
      required this.sync,
      this.scrollController});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lvl = logic.userLevelData();
    final span = (lvl.xpNext - lvl.xpCurrent);
    final progress = span > 0 ? (lvl.xp - lvl.xpCurrent) / span : 0.0;
    final provisional = logic.provisionalGoldToday();
    final bleeding = logic.bleedingRoutines();
    final late = logic.lateTasks();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
          // ── Solde + niveau ────────────────────────────────────────────────
          Row(
            children: [
              const Text('🪙', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${logic.gold}',
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: _kGold)),
                  Text('pièces d\'or',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withOpacity(.5))),
                ],
              ),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (provisional > 0)
                  Text('+$provisional 🪙 aujourd\'hui',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700)),
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
          const SizedBox(height: 20),

          // ── Ce qui te coûte / risque ──────────────────────────────────────
          _SectionTitle('⚠️ Ce qui te coûte / risque', cs),
          if (bleeding.isEmpty && late.isEmpty)
            _Hint('Rien ne saigne — tout est sous contrôle. 👌', cs)
          else ...[
            for (final b in bleeding)
              _RiskRow(
                icon: Icons.local_fire_department_outlined,
                color: Colors.deepOrange,
                title: 'Routine « ${b.activity.name} » non faite',
                detail:
                    '−1 🪙/jour tant que tu ne la fais pas · a rapporté ${b.earned} 🪙',
                cs: cs,
              ),
            for (final l in late)
              _RiskRow(
                icon: Icons.schedule_outlined,
                color: Colors.red,
                title: '« ${l.task.title} » en retard',
                detail:
                    '${l.daysLate} j de retard · −1 🪙/jour (déjà −${l.daysLate} 🪙)',
                cs: cs,
              ),
          ],
          const SizedBox(height: 20),

          // ── Ce que tu devrais faire ───────────────────────────────────────
          if (bleeding.isNotEmpty || late.isNotEmpty) ...[
            _SectionTitle('💡 Pour stopper l\'hémorragie', cs),
            if (bleeding.isNotEmpty)
              _Hint(
                  'Fais ${bleeding.length == 1 ? 'ta routine' : 'tes ${bleeding.length} routines'} aujourd\'hui : +2 🪙 chacune et fin du −1 🪙/jour.',
                  cs),
            if (late.isNotEmpty)
              _Hint(
                  'Termine (ou replanifie) ${late.length == 1 ? 'ta tâche en retard' : 'tes ${late.length} tâches en retard'} pour arrêter le −1 🪙/jour.',
                  cs),
            const SizedBox(height: 8),
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

class _RiskRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final ColorScheme cs;
  const _RiskRow(
      {required this.icon,
      required this.color,
      required this.title,
      required this.detail,
      required this.cs});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(detail,
                    style: TextStyle(
                        fontSize: 11.5, color: cs.onSurface.withOpacity(.55))),
              ],
            ),
          ),
        ]),
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
        Text('${pos ? '+' : ''}${entry.delta} 🪙',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }
}
