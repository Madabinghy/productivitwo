import 'package:productivitwo_v1/utils/coups.dart' show coupLabel;
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// Module « OBJECTIFS DU JOUR » d'Aujourd'hui web (2026-10), pendant du segment
/// Objectifs du mobile : par objectif en cours, le temps engagé au rythme du
/// jour (▶ lance le chrono), les routines engagées (+1), les blocs du programme
/// qui le servent (▶ lance, clic = tâche) et la prochaine action de ses projets.
class WebObjectivesCard extends StatelessWidget {
  final List<StrategicObjective> objectives;
  final List<Activity> activities;
  final List<Session> sessions;
  final List<HabitHit> hits;
  final List<ScheduleBlock> blocks;
  final List<Project> projects;
  final int dayStartMin;
  final String? runningActivityId;
  final bool folded;
  final VoidCallback onToggleFold;
  final int Function(Activity a) todayCount;
  final void Function(Activity a) onRoutinePlus;
  final void Function(String activityId) onStartActivity;
  final void Function(ScheduleBlock b) onLaunchBlock;
  final void Function(Project p, {String? taskId}) onOpenProject;

  const WebObjectivesCard({
    super.key,
    required this.objectives,
    required this.activities,
    required this.sessions,
    required this.hits,
    required this.blocks,
    required this.projects,
    required this.dayStartMin,
    required this.runningActivityId,
    required this.folded,
    required this.onToggleFold,
    required this.todayCount,
    required this.onRoutinePlus,
    required this.onStartActivity,
    required this.onLaunchBlock,
    required this.onOpenProject,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = buildObjectiveDays(objectives: objectives, activities: activities, sessions: sessions, blocks: blocks, projects: projects, now: now, dayStartMin: dayStartMin)
      // Coups en cours d'abord (Modes et coups lot 5), ordre d'origine sinon.
      ..sort((a, b) => (a.objective.isTactical ? 0 : 1).compareTo(b.objective.isTactical ? 0 : 1));
    if (days.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: folded ? const EdgeInsets.fromLTRB(20, 14, 20, 14) : const EdgeInsets.fromLTRB(20, 18, 20, 12),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onToggleFold,
          child: Row(children: [
            const Icon(Icons.flag_rounded, size: 14, color: Color(0xFF00897B)),
            const SizedBox(width: 6),
            const Expanded(child: Text('OBJECTIFS DU JOUR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3))),
            Text('${days.length}', style: const TextStyle(fontSize: 12, color: kBText4)),
            const SizedBox(width: 6),
            Icon(folded ? Icons.expand_more : Icons.expand_less, size: 18, color: kBText4),
          ]),
        ),
        if (!folded) ...[
          const SizedBox(height: 6),
          const Text('Ce qui sert tes objectifs en cours, aujourd’hui.', style: TextStyle(fontSize: 12, color: kBText3)),
          for (final d in days) _objective(context, d, now),
        ],
      ]),
    );
  }

  Widget _objective(BuildContext context, ObjectiveDay d, DateTime now) {
    final progress = computeObjectiveProgress(d.objective, activities, sessions, hits, now);
    final pct = progress.weekPercent == null ? null : (progress.weekPercent! * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (d.objective.isTactical) ...[
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: kBAttention.withValues(alpha: .16), borderRadius: BorderRadius.circular(999)),
              child: Text('COUP · ${coupLabel(d.objective, now)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6, color: kBAttention)),
            ),
          ],
          Expanded(child: Text(d.objective.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText))),
          if (pct != null) Text('$pct % du rythme', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palierColor(pct))),
        ]),
        if (d.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 4), child: Text('Rien d’engagé pour aujourd’hui.', style: TextStyle(fontSize: 12, color: kBText3))),
        for (final t in d.times) _time(t),
        for (final a in d.routines) _routine(a),
        for (final b in d.blocks) _block(b),
        for (final n in d.nextActions) _next(n),
      ]),
    );
  }

  Widget _row({required Widget leading, required Widget body, Widget? trailing, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 22, child: leading),
            const SizedBox(width: 8),
            Expanded(child: body),
            if (trailing != null) trailing,
          ]),
        ),
      );

  Widget _time(ObjectiveTimeToday t) {
    final running = runningActivityId == t.activityId;
    final ok = t.doneTodayMin >= t.expectedTodayMin;
    return _row(
      leading: const Icon(Icons.timer_outlined, size: 16, color: kBText3),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kBText)),
        Text('${_min(t.doneTodayMin)} / ${_min(t.expectedTodayMin)} aujourd’hui · ${_min(t.doneWeekMin)} / ${_min(t.weeklyMin)} cette semaine',
            style: TextStyle(fontSize: 11.5, color: ok ? kPalierGreen : kBText3)),
      ]),
      trailing: running
          ? const Text('en cours', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kBPrimary))
          : IconButton(visualDensity: VisualDensity.compact, tooltip: 'Lancer le chrono', onPressed: t.activity == null ? null : () => onStartActivity(t.activityId), icon: const Icon(Icons.play_circle_outline, size: 20, color: kBPrimary)),
    );
  }

  Widget _routine(Activity a) {
    final count = todayCount(a);
    final target = a.habitFreq == HabitFreq.daily ? ((a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1)) : null;
    final reached = target != null && count >= target;
    return _row(
      leading: Icon(reached ? Icons.check_circle : Icons.loop_rounded, size: 16, color: reached ? kPalierGreen : kBText3),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kBText)),
        Text(target == null ? '$count aujourd’hui · cible sur la semaine' : '$count / $target aujourd’hui', style: TextStyle(fontSize: 11.5, color: reached ? kPalierGreen : kBText3)),
      ]),
      trailing: IconButton(visualDensity: VisualDensity.compact, tooltip: '+1', onPressed: () => onRoutinePlus(a), icon: const Icon(Icons.add_circle, size: 20, color: kBPrimary)),
    );
  }

  Widget _block(ScheduleBlock b) {
    final done = b.status == 'done';
    final skipped = b.status == 'skipped';
    final project = b.projectId == null ? null : projects.where((p) => p.id == b.projectId).firstOrNull;
    return _row(
      onTap: project == null ? null : () => onOpenProject(project, taskId: b.taskId),
      leading: Text(b.startTime, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: done ? kPalierGreen : kBText3)),
      body: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: skipped ? kBText3 : kBText, decoration: done ? TextDecoration.lineThrough : null)),
      trailing: done
          ? const Icon(Icons.check_circle, size: 18, color: kPalierGreen)
          : skipped
              ? const Text('sauté', style: TextStyle(fontSize: 11.5, color: kBText3))
              : IconButton(visualDensity: VisualDensity.compact, tooltip: 'Lancer', onPressed: () => onLaunchBlock(b), icon: const Icon(Icons.play_circle_outline, size: 20, color: kBPrimary)),
    );
  }

  Widget _next(({Project project, ProjectTask task, TaskAction action}) n) => _row(
        onTap: () => onOpenProject(n.project, taskId: n.task.id),
        leading: const Icon(Icons.arrow_forward_rounded, size: 16, color: kBText3),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n.action.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: kBText)),
          Text('${n.project.title} › ${n.task.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: kBText3)),
        ]),
        trailing: const Icon(Icons.chevron_right, size: 18, color: kBText4),
      );

  String _min(int m) => m >= 60 ? '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${(m % 60).toString().padLeft(2, '0')}'}' : '$m min';
}
