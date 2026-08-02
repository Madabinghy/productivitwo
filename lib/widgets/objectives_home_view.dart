import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/widgets/objectives_card.dart';
import 'package:productivitwo_v1/widgets/week_dashboard_sheet.dart';

/// Onglet OBJECTIFS (remplace l'Accueil) — la pyramide des 3 horizons :
/// AUJOURD'HUI (intention du jour + programme) · CETTE SEMAINE (engagements
/// + objectifs stratégiques) · SUR 30 JOURS (tendance + jalons à venir).
/// Chaque étage répond à une question : qu'est-ce que je vise aujourd'hui ?
/// est-ce que je tiens mes engagements ? est-ce que je vais dans la bonne
/// direction ? L'ancien Accueil reste intact derrière l'icône Tableau de bord.
class ObjectivesHomeView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final List<Project> projects;
  final VoidCallback onOpenDashboard;
  final VoidCallback? onOpenNow; // tap sur le prochain bloc → Maintenant

  const ObjectivesHomeView({
    super.key,
    required this.logic,
    required this.sync,
    required this.projects,
    required this.onOpenDashboard,
    this.onOpenNow,
  });

  @override
  State<ObjectivesHomeView> createState() => _ObjectivesHomeViewState();
}

class _ObjectivesHomeViewState extends State<ObjectivesHomeView> {
  String? _intention;
  bool _intentionLoaded = false;
  // Stream créé UNE fois (leçon ArtifactShortcuts : un stream neuf par build
  // = StreamBuilder qui repart de zéro à chaque rebuild du parent).
  late final Stream<DailySchedule?> _scheduleStream =
      widget.sync.streamDailySchedule(_today);

  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    widget.sync.fetchDayIntention(_today).then((v) {
      if (mounted) {
        setState(() {
          _intention = v;
          _intentionLoaded = true;
        });
      }
    });
  }

  Future<void> _editIntention() async {
    final ctrl = TextEditingController(text: _intention ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('L\'intention du jour'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          decoration: const InputDecoration(
              hintText: 'Ex : boucler la maquette et l\'envoyer'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    ctrl.dispose();
    if (saved == null) return;
    setState(() => _intention = saved.isEmpty ? null : saved);
    await widget.sync.setDayIntention(_today, saved);
  }

  /// Détail des routines du jour — même geste que « Ma semaine » : le
  /// chiffre se tape, la liste s'ouvre.
  void _showTodayDetail(List<EngagementStat> stats) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            const Text('Routines du jour',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                'Les routines quotidiennes — les hebdomadaires se jugent '
                'sur 7 jours, pas sur une journée.',
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
            const SizedBox(height: 12),
            for (final e in stats)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Icon(
                      e.kept
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: e.kept
                          ? kPalierGreen
                          : cs.onSurface.withOpacity(.35)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(e.label,
                          style: const TextStyle(fontSize: 13.5))),
                  Text('${e.done} / ${e.target}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: e.kept
                              ? kPalierGreen
                              : cs.onSurface.withOpacity(.7))),
                ]),
              ),
          ],
        );
      },
    );
  }

  Widget _horizon(ColorScheme cs, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: cs.onSurface.withOpacity(.45))),
      );

  // ── AUJOURD'HUI ─────────────────────────────────────────────────────────────

  Widget _todayCard(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // L'intention : une phrase, un tap pour la poser/l'éditer.
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _editIntention,
              child: Row(children: [
                Icon(
                    _intention == null
                        ? Icons.flag_outlined
                        : Icons.flag_rounded,
                    size: 18,
                    color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: !_intentionLoaded
                      ? const SizedBox(height: 18)
                      : Text(
                          _intention ?? 'Définir l\'intention du jour…',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: _intention == null
                                ? FontWeight.w500
                                : FontWeight.w700,
                            fontStyle: _intention == null
                                ? FontStyle.italic
                                : null,
                            color: _intention == null
                                ? cs.onSurface.withOpacity(.55)
                                : cs.onSurface,
                          ),
                        ),
                ),
                Icon(Icons.edit_outlined,
                    size: 15, color: cs.onSurface.withOpacity(.35)),
              ]),
            ),
            const SizedBox(height: 10),
            // Engagements tenus AUJOURD'HUI (routines quotidiennes) — le
            // pendant journalier du « x/y » de la semaine, tap → détail.
            () {
              final st = widget.logic.state;
              final stats = todayEngagements(
                  activities: st.activities, hits: st.habitHits);
              if (stats.isEmpty) return const SizedBox.shrink();
              final kept = stats.where((e) => e.kept).length;
              final pct = ((kept / stats.length) * 100).round();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showTodayDetail(stats),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('$kept / ${stats.length}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                                color: palierColor(pct))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('engagements tenus aujourd\'hui',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurface.withOpacity(.6))),
                        ),
                        Icon(Icons.chevron_right,
                            size: 16, color: cs.onSurface.withOpacity(.35)),
                      ]),
                      const SizedBox(height: 8),
                      // Heatmap du jour : UNE case par coche attendue,
                      // groupées par routine — la journée est un tas de
                      // petits gestes, chacun allume sa case.
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final e in stats)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Plafond d'affichage par routine : au-delà,
                                // la rangée dirait moins que le détail.
                                for (var i = 0;
                                    i < e.target.clamp(1, 14);
                                    i++)
                                  Container(
                                    width: 9,
                                    height: 9,
                                    margin:
                                        const EdgeInsets.only(right: 2),
                                    decoration: BoxDecoration(
                                      color: i < e.done
                                          ? kPalierGreen
                                          : cs.onSurface
                                              .withOpacity(.08),
                                      borderRadius:
                                          BorderRadius.circular(2.5),
                                      border: i < e.done
                                          ? null
                                          : Border.all(
                                              color: cs.onSurface
                                                  .withOpacity(.14),
                                              width: .5),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }(),
            // La mesure automatique : le programme du jour, en un coup d'œil.
            StreamBuilder<DailySchedule?>(
              stream: _scheduleStream,
              builder: (ctx, snap) {
                final blocks = (snap.data?.blocks ?? [])
                    .where((b) => b.status != 'deleted')
                    .toList();
                if (blocks.isEmpty) {
                  return Text('Pas de programme aujourd\'hui.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurface.withOpacity(.5)));
                }
                final done =
                    blocks.where((b) => b.status == 'done').length;
                final next = blocks
                    .where((b) => b.status == 'pending')
                    .firstOrNull;
                final pctColor = palierColor(
                    ((done / blocks.length) * 100).round());
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onOpenNow,
                  child: Row(children: [
                    Text('$done / ${blocks.length} blocs',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                            color: pctColor)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          next == null
                              ? 'Tout est passé — journée déroulée.'
                              : 'Prochain : ${next.startTime} · ${next.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: cs.onSurface.withOpacity(.6))),
                    ),
                    if (widget.onOpenNow != null)
                      Icon(Icons.chevron_right,
                          size: 16, color: cs.onSurface.withOpacity(.35)),
                  ]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── SUR 30 JOURS ────────────────────────────────────────────────────────────

  List<({DateTime date, String title, String project})> _upcomingMilestones() {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 30));
    final out = <({DateTime date, String title, String project})>[];
    for (final p in widget.projects) {
      if (p.status != 'active') continue;
      for (final t in p.tasks) {
        if (!t.isMilestone || t.status == 'done' || t.status == 'skipped') {
          continue;
        }
        final d = t.endDate ?? t.startDate;
        if (d.isBefore(now) || d.isAfter(horizon)) continue;
        out.add((date: d, title: t.title, project: p.title));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  Widget _monthSection(ColorScheme cs) {
    final st = widget.logic.state;
    final weeks =
        fourWeekTrend(activities: st.activities, hits: st.habitHits);
    final milestones = _upcomingMilestones();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            for (var i = 0; i < weeks.length; i++) ...[
              Expanded(
                child: Column(children: [
                  Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palierColor(weeks[i].pct).withOpacity(.2),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: palierColor(weeks[i].pct)),
                    ),
                    child: Text('${weeks[i].pct} %',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                  const SizedBox(height: 3),
                  Text(weeks[i].label,
                      style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurface.withOpacity(.45))),
                ]),
              ),
              if (i < weeks.length - 1) const SizedBox(width: 6),
            ],
          ]),
          if (milestones.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('JALONS À VENIR',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.onSurface.withOpacity(.4))),
            const SizedBox(height: 6),
            for (final m in milestones.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(Icons.flag, size: 13, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                      '${m.date.day.toString().padLeft(2, '0')}/${m.date.month.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface.withOpacity(.7))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${m.title} — ${m.project}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(children: [
              Text('Objectifs',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface)),
              const Spacer(),
              // L'ancien Accueil, intact — discret mais à un tap.
              IconButton(
                tooltip: 'Tableau de bord complet',
                icon: Icon(Icons.dashboard_customize_outlined,
                    size: 22, color: cs.onSurface.withOpacity(.6)),
                onPressed: widget.onOpenDashboard,
              ),
            ]),
          ),
          _horizon(cs, 'AUJOURD\'HUI'),
          _todayCard(cs),
          _horizon(cs, 'CETTE SEMAINE'),
          // Engagements 7 j glissants (tap → détail par domaine).
          WeekDashboardCard(logic: widget.logic),
          // Objectifs stratégiques : progression hebdo mesurée — l'étage où
          // vivra le contrat coach-coaché.
          ObjectivesCard(
              logic: widget.logic,
              sync: widget.sync,
              projects: widget.projects),
          _horizon(cs, 'SUR 30 JOURS'),
          _monthSection(cs),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
