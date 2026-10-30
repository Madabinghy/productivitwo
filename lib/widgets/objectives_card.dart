import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:productivitwo_v1/utils/fiche_cache.dart';
import 'package:productivitwo_v1/utils/coups.dart';
import 'package:productivitwo_v1/utils/mode.dart' show activeRests;
import 'package:productivitwo_v1/widgets/coup_sheet.dart';
import 'package:productivitwo_v1/widgets/rest_sheet.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart';
import 'package:productivitwo_v1/widgets/objective_edit_sheet.dart';
import 'package:productivitwo_v1/widgets/moment_item.dart';
import 'package:productivitwo_v1/widgets/objective_moment_card.dart';
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart';
import 'package:productivitwo_v1/widgets/status_row.dart';

/// Onglet Objectifs « une carte, une fiche » (lot 5, 2026-10) : la carte
/// OBJECTIF DU MOMENT (partagée avec Aujourd'hui), puis une ligne par objectif
/// actif — barre « temps investi » depuis le début avec le repère « attendu
/// aujourd'hui » (sinon la jauge hebdo), écart à droite — et la section
/// repliée « Archivés · n » (Réactiver). Tap = fiche trajectoire.
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
  // Cache mémoire PARTAGÉ entre les recréations du State : la ListView de
  // l'onglet détruit les enfants sortis du viewport — sans cache, chaque
  // retour en haut de page refaisait le fetch → saccade au scroll.
  static List<StrategicObjective>? _cache;
  // Sessions depuis le début le plus ancien des objectifs (le temps investi
  // cumule depuis le début, pas depuis lundi) ; l'état local sert d'abord.
  static List<Session>? _sessionsCache;

  List<StrategicObjective> _all = [];
  bool _loaded = false;
  bool _showArchived = false;

  List<StrategicObjective> get _active => _all.where((o) => o.status == 'active').toList();
  List<StrategicObjective> get _coups => _active.where((o) => o.isTactical).toList()..sort((a, b) => comparePct(_pctOf(a), _pctOf(b)));
  List<StrategicObjective> get _strategic => _active.where((o) => !o.isTactical).toList()..sort((a, b) => comparePct(_pctOf(a), _pctOf(b)));

  /// Pourcentage d'une ligne (même lecture que `_row`) : temps investi sur
  /// l'attendu à ce jour, sinon la jauge hebdo, sinon 100.
  int _pctOf(StrategicObjective o) {
    if (o.timeCommitments.isNotEmpty) {
      final means = _trajectoryOf(o).means;
      return means.expectedMin <= 0 ? 100 : (means.doneMin / means.expectedMin * 100).round();
    }
    final pct = _progressOf(o).weekPercent;
    return pct == null ? 100 : (pct * 100).round();
  }
  List<StrategicObjective> get _archived => _all.where((o) => o.status == 'archived').toList();
  List<StrategicObjective> get _done => _all.where((o) => o.status == 'done').toList();

  @override
  void initState() {
    super.initState();
    final cached = _cache;
    if (cached != null) {
      _all = cached;
      _loaded = true;
    }
    _load();
  }

  Future<void> _load() async {
    final all = await widget.sync.fetchStrategicObjectives();
    if (!mounted) return;
    _cache = all;
    FicheCache.objectives = all;
    setState(() {
      _all = all;
      _loaded = true;
    });
    final active = _active;
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

  ObjectiveProgress _progressOf(StrategicObjective o) {
    final st = widget.logic.state;
    return computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, DateTime.now());
  }

  Future<void> _edit(StrategicObjective? o) async {
    final st = widget.logic.state;
    final saved = await showObjectiveEditSheet(
      context,
      existing: o,
      domains: st.activeDomains,
      activities: st.activities,
      projects: widget.projects.where((p) => p.status != 'archived').toList(),
      sync: widget.sync,
    );
    if (saved != null) _load();
  }

  Future<void> _newCoup() async {
    final saved = await showCoupSheet(context, logic: widget.logic, sync: widget.sync, projects: widget.projects.where((p) => p.status != 'archived').toList());
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

  Future<void> _reactivate(StrategicObjective o) async {
    o.status = 'active';
    o.updatedAt = DateTime.now();
    await widget.sync.saveStrategicObjective(o);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_loaded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Coups tactiques (Modes et coups lot 3) : 3 à 10 jours, une cible, au-dessus des stratégiques.
        ListSectionTitle('RUSHS · ${_coups.length}', action: '+ Lancer un rush', onAction: _newCoup),
        if (_coups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('Un rush = 3 à 10 jours à fond sur une chose, le reste en pause.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .5))),
          )
        else
          for (final o in _coups) _row(cs, o),
        if (_restRows(cs) case final rows when rows.isNotEmpty) ...rows,
        ListSectionTitle('OBJECTIFS · ${_strategic.length}', action: '+ Nouveau', onAction: () => _edit(null)),
        if (_strategic.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Définis un objectif : un résultat visé, relié à du temps hebdo et des routines.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .5))),
          )
        else
          for (final o in _strategic) _row(cs, o),
        if (_done.isNotEmpty || _archived.isNotEmpty) ...[
          ListSectionTitle(
            'ARCHIVÉS · ${_done.length + _archived.length}',
            onAction: () => setState(() => _showArchived = !_showArchived),
            expanded: _showArchived,
          ),
          if (_showArchived) ...[
            for (final o in _done) _plainRow(o, 'atteint'),
            for (final o in _archived) _plainRow(o, 'archivé'),
          ],
        ],
      ]),
    );
  }

  /// Domaines en veille : une ligne chacun, « Lever » d'un tap.
  List<Widget> _restRows(ColorScheme cs) {
    final rest = activeRests(widget.logic.restDomains, DateTime.now());
    if (rest.isEmpty) return const [];
    final domains = widget.logic.state.activeDomains;
    return [
      for (final e in rest.entries)
        if (domains.where((d) => d.id == e.key).firstOrNull case final d?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusRow(
              leading: const Icon(Icons.bedtime_outlined),
              title: '${d.name} · en veille',
              sub: DateTime.tryParse(e.value) == null ? null : 'jusqu\'au ${dayMonthFr(DateTime.parse(e.value))} · minimums suspendus',
              muted: true,
              trailing: TextButton(
                onPressed: () async {
                  await liftRest(widget.logic, widget.sync, d.id);
                  if (mounted) setState(() {});
                },
                child: const Text('Lever'),
              ),
            ),
          ),
    ];
  }

  /// « Une liste, un seul bloc ouvert » : l'objectif du moment est ouvert par défaut.
  final _open = OpenItem();

  Widget _row(ColorScheme cs, StrategicObjective o) {
    final progress = _progressOf(o);
    final pct = progress.weekPercent;
    final means = o.timeCommitments.isEmpty ? null : _trajectoryOf(o).means;
    final diff = means == null ? 0 : means.doneMin - means.expectedMin;
    final int pctInt;
    final String delta;
    ({num done, num total, num expected})? bar;
    if (means != null) {
      final total = means.totalMin > 0 ? means.totalMin : math.max(means.expectedMin, means.doneMin);
      bar = (done: means.doneMin, total: total, expected: means.expectedMin);
      pctInt = means.expectedMin <= 0 ? 100 : (means.doneMin / means.expectedMin * 100).round();
      delta = means.expectedMin <= 0 ? fmtMin(means.doneMin) : (diff >= 0 ? '+${fmtMin(diff)}' : '−${fmtMin(-diff)}');
    } else if (pct != null) {
      bar = (done: pct, total: 1, expected: progress.weekElapsed);
      pctInt = (pct * 100).round();
      delta = '$pctInt %';
    } else {
      pctInt = 100;
      delta = '';
    }
    final sub = <String>[
      if (o.isTactical) coupLabel(o, DateTime.now()),
      if (means != null) '${fmtMin(means.doneMin)} investies · attendu ${fmtMin(means.expectedMin)}',
      if (means == null && o.kpiTarget != null && o.kpiTarget!.isNotEmpty) o.kpiTarget!,
      if (!o.isTactical && progress.daysLeft != null) '${progress.daysLeft} j restants',
      if (isReadingDue(o, DateTime.now())) 'relevé à noter',
    ].join(' · ');
    return MomentItem(
      key: _open.keyFor(o.id),
      open: false,
      collapsed: StatusRow(
        leading: Icon(o.isTactical ? Icons.bolt_rounded : Icons.flag_rounded, color: kObjectiveAccent),
        title: o.title,
        sub: sub.isEmpty ? null : sub,
        bar: bar,
        pct: pctInt,
        delta: delta.isEmpty ? null : delta,
      ),
      expanded: ObjectiveMomentCard(
        logic: widget.logic,
        sync: widget.sync,
        objectives: _active,
        objectiveId: o.id,
        onChanged: _load,
      ),
      // Une liste, une fiche (2026-10-30) : tap = fiche de l'objectif, comme Projets / Actions.
      onToggle: () => _showDetail(o),
      onLongPress: () => _edit(o),
    );
  }

  Widget _plainRow(StrategicObjective o, String chip) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: StatusRow(
          leading: Icon(chip == 'atteint' ? Icons.check_rounded : Icons.inventory_2_outlined),
          title: o.title,
          sub: o.kpiTarget,
          muted: chip == 'atteint',
          trailing: TextButton(
            onPressed: () => _reactivate(o),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: kObjectiveAccent),
            child: const Text('Réactiver'),
          ),
          onTap: () => _showDetail(o),
        ),
      );
}
