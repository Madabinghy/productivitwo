import 'package:flutter/material.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject;
import 'package:collection/collection.dart';
import 'package:productivitwo_v1/utils/coups.dart' show coupRestUntil;
import 'package:productivitwo_v1/utils/mode_moves.dart';
import 'package:productivitwo_v1/widgets/rest_sheet.dart';
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/project_health.dart' show nextAction;
import 'package:productivitwo_v1/utils/project_moment.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routineTodayCount;

/// « Deep work 90 min » (Modes et coups § 2.4, décision 2026-10-27) : il
/// PROPOSE, l'utilisateur dispose. Mini-fiche « Sur quoi ? » — le coup en
/// cours, sinon le projet le plus en retard, sinon l'objectif le plus en retard
/// sur son rythme, plus « Autre… » ; le premier est présélectionné, un tap
/// confirme. Confirmé : bloc de 90 min à partir de maintenant sur cette source,
/// chrono lancé dessus par [onLaunch]. Un chrono déjà en cours sur une autre
/// activité ⇒ on demande avant de le couper. Jamais lancé sans geste.
Future<bool> showDeepWorkSheet(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  required String date,
  required void Function(ScheduleBlock block) onLaunch,
  List<StrategicObjective>? objectives,
  String? preferObjectiveId,
  /// Page domaine / fiche activité : cette activité en tête des candidats.
  String? preferActivityId,
  int durationMin = 90,
}) async {
  final now = DateTime.now();
  final st = logic.state;
  List<StrategicObjective> objs = objectives ?? const [];
  if (objectives == null) {
    try {
      objs = await sync.fetchStrategicObjectives();
    } catch (_) {}
  }
  objs = objs.where((o) => o.status == 'active').toList();
  if (!context.mounted) return false;

  final projects = logic.currentProjects;
  NextPick? projectPick;
  for (final m in rankProjectMoments(projects, st.sessions, now)) {
    if (m.upcoming || m.next == null) continue;
    projectPick = (project: m.project, task: m.next!.task, action: m.next!.action);
    break;
  }
  ({StrategicObjective objective, String activityId})? objectivePick;
  if (objs.isNotEmpty) {
    final days = buildObjectiveDays(
        objectives: objs, activities: st.activeActivities, sessions: st.sessions, blocks: const [], projects: projects, now: now, dayStartMin: logic.dayStartMin);
    final ranked = rankObjectiveMoments(days,
        nowMin: logic.livedNowMinNow,
        now: now,
        routineCount: (a) => routineTodayCount(logic, a),
        weekPercent: (o) => computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, now).weekPercent);
    for (final m in ranked) {
      if (m.objective.isTactical || m.day.times.isEmpty) continue;
      final t = m.move.time ?? m.day.times.first;
      objectivePick = (objective: m.objective, activityId: t.activityId);
      break;
    }
  }
  var candidates = deepWorkCandidates(
    objectives: objs,
    projects: projects,
    activities: st.activities,
    today: now,
    nextOf: (p) {
      final n = nextAction(p);
      return n == null ? null : (project: p, task: n.task, action: n.action);
    },
    projectPick: projectPick,
    objectivePick: objectivePick,
  );
  if (preferObjectiveId != null) {
    final i = candidates.indexWhere((c) => c.objectiveId == preferObjectiveId);
    if (i > 0) candidates = [candidates[i], ...candidates.where((c) => c.objectiveId != preferObjectiveId)];
  }
  if (preferActivityId != null) {
    final a = st.activities.where((x) => x.id == preferActivityId).firstOrNull;
    if (a != null) {
      final i = candidates.indexWhere((c) => c.projectId == null && c.activityId == a.id);
      if (i >= 0) {
        candidates = [candidates[i], ...candidates.where((c) => c != candidates[i])];
      } else {
        candidates = [DeepWorkCandidate(kind: 'other', title: a.name, subtitle: 'Cette activité', activityId: a.id), ...candidates];
      }
    }
  }

  final picked = await showModalBottomSheet<DeepWorkCandidate>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => _DeepWorkPicker(candidates: candidates, logic: logic, durationMin: durationMin),
  );
  if (picked == null || !context.mounted) return false;

  final running = logic.runningActivity();
  if (running != null && running.id != picked.activityId) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Couper le chrono en cours ?'),
        content: Text('Le chrono « ${running.name} » tourne. Le deep work le remplace.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Couper et lancer')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
  }
  final block = deepWorkBlock(picked, now, durationMin: durationMin, dayStartMin: logic.dayStartMin);
  try {
    await sync.addScheduleBlock(date, block);
  } catch (_) {}
  onLaunch(block);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(persist: false, 
        content: Text('Deep work · ${picked.title} · $durationMin min à partir de ${block.startTime}'), duration: const Duration(seconds: 3)));
    // Veille des domaines non concernés (§ 2.4) : jusqu'à la fin du coup, sinon ce soir.
    final coup = picked.kind == 'coup' ? objs.where((o) => o.id == picked.objectiveId).firstOrNull : null;
    final until = coup != null && coup.endDate != null ? coupRestUntil(coup) : date;
    final sourceDomain = <String>{
      for (final p in projects)
        if (p.id == picked.projectId && p.domainId != null) p.domainId!,
      for (final a in st.activities)
        if (a.id == picked.activityId) a.domainId,
    };
    await showRestSheet(context, logic: logic, sync: sync, untilYmd: until, excludeDomainIds: sourceDomain,
        title: 'Deep work lancé · mettre le reste en veille ${coup != null ? 'jusqu\'à la fin du rush' : 'jusqu\'à ce soir'} ?');
  }
  return true;
}

class _DeepWorkPicker extends StatefulWidget {
  final List<DeepWorkCandidate> candidates;
  final AppLogic logic;
  final int durationMin;
  const _DeepWorkPicker({required this.candidates, required this.logic, required this.durationMin});
  @override
  State<_DeepWorkPicker> createState() => _DeepWorkPickerState();
}

class _DeepWorkPickerState extends State<_DeepWorkPicker> {
  int _selected = 0;
  bool _other = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cands = widget.candidates;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Deep work ${widget.durationMin} min · sur quoi ?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Un bloc à partir de maintenant, chrono dessus. Rien ne se lance sans toi.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6))),
          const SizedBox(height: 12),
          if (_other)
            _otherList(cs)
          else ...[
            if (cands.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Aucun rush, projet en retard ni objectif avec engagement de temps. Choisis librement.',
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .7))),
              ),
            for (var i = 0; i < cands.length; i++)
              RadioListTile<int>(
                value: i,
                groupValue: _selected,
                onChanged: (v) => setState(() => _selected = v ?? 0),
                contentPadding: EdgeInsets.zero,
                title: Text(cands[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(cands[i].subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                secondary: Icon(switch (cands[i].kind) { 'coup' => Icons.bolt_rounded, 'project' => Icons.account_tree_outlined, _ => Icons.flag_rounded }),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.more_horiz_rounded),
              title: const Text('Autre…'),
              subtitle: const Text('Un projet ou une activité, au choix'),
              onTap: () => setState(() => _other = true),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: cands.isEmpty ? null : () => Navigator.pop(context, cands[_selected]),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(cands.isEmpty ? 'Choisis une source' : 'Lancer · ${cands[_selected].title}', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _otherList(ColorScheme cs) {
    final all = widget.logic.currentProjects;
    final projects = all.where((p) => p.status == 'active' && !p.paused && !isFolderProject(p, all)).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final acts = widget.logic.state.activeActivities.where((a) => !a.isHabit).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .55),
      child: ListView(shrinkWrap: true, children: [
        TextButton.icon(
          onPressed: () => setState(() => _other = false),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Retour aux propositions'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        ),
        if (projects.isNotEmpty) _title(cs, 'PROJETS'),
        for (final p in projects)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_tree_outlined, size: 18),
            title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: nextAction(p) == null ? null : Text(nextAction(p)!.action.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              final n = nextAction(p);
              Navigator.pop(
                  context,
                  DeepWorkCandidate(
                      kind: 'other',
                      title: p.title,
                      subtitle: n?.action.title ?? '',
                      projectId: p.id,
                      taskId: n?.task.id,
                      actionId: n?.action.id,
                      activityId: p.linkedActivityId));
            },
          ),
        if (acts.isNotEmpty) _title(cs, 'ACTIVITÉS'),
        for (final g in groupActivitiesByDomain(acts, widget.logic.state.activeDomains)) ...[
          ActivityDomainHeader(name: g.name, color: g.color, padding: const EdgeInsets.fromLTRB(0, 10, 0, 2)),
          for (final a in g.activities)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.timer_outlined, size: 18, color: g.color),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context, DeepWorkCandidate(kind: 'other', title: a.name, subtitle: '', activityId: a.id)),
            ),
        ],
      ]),
    );
  }

  Widget _title(ColorScheme cs, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
        child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: cs.onSurface.withValues(alpha: .55))),
      );
}
