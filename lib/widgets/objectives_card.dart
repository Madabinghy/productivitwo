import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart';
import 'package:productivitwo_v1/widgets/objective_edit_sheet.dart';
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart';

/// Carte « Objectifs » de l'onglet Accueil : un rang par objectif actif avec
/// sa jauge de progression hebdo (engagements temps + routines, données déjà
/// en mémoire dans AppState). Tap → détail par engagement + édition.
class ObjectivesCard extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final List<Project> projects;

  const ObjectivesCard({
    super.key,
    required this.logic,
    required this.sync,
    required this.projects,
  });

  @override
  State<ObjectivesCard> createState() => _ObjectivesCardState();
}

class _ObjectivesCardState extends State<ObjectivesCard> {
  static const _accent = Color(0xFF00897B);

  // Cache mémoire PARTAGÉ entre les recréations du State : la ListView de
  // l'Accueil détruit les enfants sortis du viewport — sans cache, chaque
  // retour en haut de page refaisait le fetch → carte vide → réapparition
  // d'un bloc entier = saccade au scroll (constaté sur build). Rendu
  // immédiat depuis le cache, rafraîchi silencieusement derrière.
  static List<StrategicObjective>? _cache;
  // Sessions depuis le début le plus ancien des objectifs (le temps investi
  // cumule depuis le début, pas depuis lundi) ; l'état local sert d'abord.
  static List<Session>? _sessionsCache;

  List<StrategicObjective> _objectives = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final cached = _cache;
    if (cached != null) {
      _objectives = cached.where((o) => o.status == 'active').toList();
      _loaded = true;
    }
    _load();
  }

  Future<void> _load() async {
    final all = await widget.sync.fetchStrategicObjectives();
    if (!mounted) return;
    _cache = all;
    setState(() {
      _objectives = all.where((o) => o.status == 'active').toList();
      _loaded = true;
    });
    final active = _objectives;
    if (active.isEmpty) return;
    final now = DateTime.now();
    final earliest = active.map(objectiveStart).reduce((a, b) => a.isBefore(b) ? a : b);
    final days = now.difference(earliest).inDays.clamp(1, 365);
    try {
      final list = await widget.sync.fetchRecentSessions(days + 1);
      if (!mounted || list.isEmpty) return;
      _sessionsCache = list;
      setState(() {});
    } catch (_) {}
  }

  ObjectiveTrajectory _trajectoryOf(StrategicObjective o) =>
      computeObjectiveTrajectory(o, _sessionsCache ?? widget.logic.state.sessions, DateTime.now());

  /// Barre « temps investi » : fait sur le total de l'horizon (sinon sur
  /// l'attendu du jour), repère vertical = attendu aujourd'hui.
  Widget _meansBar(ColorScheme cs, MeansTrajectory m) {
    final color = m.status == TrajectoryStatus.behind ? const Color(0xFFEF6C00) : _accent;
    final total = m.totalMin > 0 ? m.totalMin : math.max(m.expectedMin, m.doneMin);
    final donePct = total <= 0 ? 0.0 : (m.doneMin / total).clamp(0.0, 1.0);
    final expPct = total <= 0 ? 0.0 : (m.expectedMin / total).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (_, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: 16,
        child: Stack(children: [
          Positioned.fill(
            top: 5,
            bottom: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                  value: donePct,
                  minHeight: 6,
                  backgroundColor: cs.onSurface.withOpacity(.08),
                  valueColor: AlwaysStoppedAnimation<Color>(color)),
            ),
          ),
          Positioned(
            left: (w * expPct - 0.75).clamp(0.0, w - 1.5),
            top: 2,
            bottom: 2,
            child: Container(width: 1.5, color: cs.onSurface.withOpacity(.4)),
          ),
        ]),
      );
    });
  }

  ObjectiveProgress _progressOf(StrategicObjective o) {
    final st = widget.logic.state;
    return computeObjectiveProgress(
        o, st.activities, st.sessions, st.habitHits, DateTime.now());
  }

  Future<void> _edit(StrategicObjective? o) async {
    final st = widget.logic.state;
    final saved = await showObjectiveEditSheet(
      context,
      existing: o,
      domains: st.activeDomains,
      activities: st.activities,
      projects:
          widget.projects.where((p) => p.status != 'archived').toList(),
      sync: widget.sync,
    );
    if (saved != null) _load();
  }

  Future<void> _showDetail(StrategicObjective o) async {
    final changed = await showObjectiveTrajectorySheet(
      context,
      logic: widget.logic,
      sync: widget.sync,
      objective: o,
      projects: widget.projects,
    );
    if (changed) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_loaded) return const SizedBox.shrink();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag, size: 15, color: _accent.withOpacity(.9)),
                const SizedBox(width: 8),
                Text('OBJECTIFS',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                        color: cs.onSurface.withOpacity(.5))),
                const Spacer(),
                IconButton(
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add, size: 18),
                  color: _accent,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Définir un objectif',
                ),
              ],
            ),
            if (_objectives.isEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: InkWell(
                  onTap: () => _edit(null),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Définis un objectif : un résultat visé, relié à du temps hebdo et des routines.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurface.withOpacity(.5)),
                    ),
                  ),
                ),
              )
            else
              for (final o in _objectives) ...[
                InkWell(
                  onTap: () => _showDetail(o),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.only(
                        top: 6, bottom: 6, right: 8),
                    child: Builder(builder: (_) {
                      final progress = _progressOf(o);
                      final pct = progress.weekPercent;
                      // Temps investi depuis le début (repère = attendu
                      // aujourd'hui) quand il y a des engagements de temps ;
                      // sinon la jauge hebdo d'avant.
                      final means = o.timeCommitments.isEmpty ? null : _trajectoryOf(o).means;
                      final diff = means == null ? 0 : means.doneMin - means.expectedMin;
                      final warn = const Color(0xFFEF6C00);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(o.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (means != null)
                                Text(
                                    means.expectedMin <= 0
                                        ? fmtMin(means.doneMin)
                                        : diff >= 0
                                            ? '+${fmtMin(diff)}'
                                            : '−${fmtMin(-diff)}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: means.status == TrajectoryStatus.behind ? warn : _accent.withOpacity(.9)))
                              else if (pct != null)
                                Text('${(pct * 100).round()}%',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _accent.withOpacity(.9))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (means != null)
                            _meansBar(cs, means)
                          else if (pct != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 5,
                                backgroundColor:
                                    cs.onSurface.withOpacity(.08),
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        _accent),
                              ),
                            ),
                          if (means != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${fmtMin(means.doneMin)} investies · attendu ${fmtMin(means.expectedMin)}'
                                '${means.totalMin > 0 ? ' · ${fmtMin(means.totalMin)} au total' : ''}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.5)),
                              ),
                            ),
                          if (o.kpiTarget != null &&
                                  o.kpiTarget!.isNotEmpty ||
                              progress.daysLeft != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                [
                                  if (o.kpiTarget != null &&
                                      o.kpiTarget!.isNotEmpty)
                                    o.kpiTarget!,
                                  if (progress.daysLeft != null)
                                    '${progress.daysLeft} j restants',
                                ].join(' · '),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: cs.onSurface.withOpacity(.5)),
                              ),
                            ),
                        ],
                      );
                    }),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}
