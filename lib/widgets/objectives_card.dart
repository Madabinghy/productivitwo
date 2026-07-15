import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/widgets/objective_edit_sheet.dart';

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

  List<StrategicObjective> _objectives = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.sync.fetchStrategicObjectives();
    if (!mounted) return;
    setState(() {
      _objectives = all.where((o) => o.status == 'active').toList();
      _loaded = true;
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

  Future<void> _setStatus(StrategicObjective o, String status) async {
    o.status = status;
    o.updatedAt = DateTime.now();
    await widget.sync.saveStrategicObjective(o);
    if (mounted) Navigator.pop(context); // ferme la sheet détail
    _load();
  }

  void _showDetail(StrategicObjective o) {
    final cs = Theme.of(context).colorScheme;
    final progress = _progressOf(o);
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, size: 18, color: _accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(o.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (o.kpiTarget != null && o.kpiTarget!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('🎯 ${o.kpiTarget}',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurface.withOpacity(.6))),
              ),
            if (o.horizonLabel != null || progress.daysLeft != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [
                    if (o.horizonLabel != null) o.horizonLabel!,
                    if (progress.daysLeft != null)
                      '${progress.daysLeft} j restants',
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 12.5, color: cs.onSurface.withOpacity(.5)),
                ),
              ),
            const SizedBox(height: 14),
            if (progress.items.isEmpty)
              Text('Aucun engagement — édite l\'objectif pour en ajouter.',
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurface.withOpacity(.5)))
            else
              for (final c in progress.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            c.type == 'time'
                                ? Icons.timer_outlined
                                : Icons.loop,
                            size: 14,
                            color: cs.onSurface.withOpacity(.5),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(c.name,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600)),
                          ),
                          Text(
                            c.type == 'time'
                                ? '${c.done}/${c.target} min'
                                : '${c.done}/${c.target} ×',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: c.onTrack
                                    ? const Color(0xFF43A047)
                                    : const Color(0xFFEF6C00)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: c.pct,
                          minHeight: 5,
                          backgroundColor: cs.onSurface.withOpacity(.08),
                          valueColor: AlwaysStoppedAnimation<Color>(c.onTrack
                              ? const Color(0xFF43A047)
                              : const Color(0xFFEF6C00)),
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => _setStatus(o, 'done'),
                  child: const Text('Atteint 🎉'),
                ),
                TextButton(
                  onPressed: () => _setStatus(o, 'archived'),
                  child: const Text('Archiver'),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _edit(o);
                  },
                  child: const Text('Éditer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
                              if (pct != null)
                                Text('${(pct * 100).round()}%',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _accent.withOpacity(.9))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (pct != null)
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
