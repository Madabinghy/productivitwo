import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/time_scope.dart';
import 'package:productivitwo_v1/widgets/session_template_editor.dart';

/// Sheet d'une activité-temps, calqué sur le sheet du FAB mobile (stats semaine
/// + progression, aujourd'hui/mois, courbe 60 j, heatmap 12 sem). Réutilisable
/// hors main.dart (web + mobile). Le lancement de minuteur (alarme) reste mobile
/// → pas de CTA ici. `showHeatmap` masque la heatmap quand le château la montre.
Future<void> showActivitySheet(
    BuildContext context, AppLogic logic, String activityId,
    {bool showHeatmap = true}) async {
  Activity? found;
  for (final x in logic.state.activeActivities) {
    if (x.id == activityId) {
      found = x;
      break;
    }
  }
  if (found == null) return;
  final a = found;
  final color =
      domainColor(a.domainId, logic.state.activeDomains) ?? const Color(0xFF4FA3FF);
  final domain =
      logic.state.activeDomains.where((d) => d.id == a.domainId).firstOrNull;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final monthStart = DateTime(now.year, now.month, 1);
  final durDay = logic.totalForRangeByActivity(a.id, today, now);
  final durWeek = logic.totalForRangeByActivity(a.id, weekStart, now);
  final durMonth = logic.totalForRangeByActivity(a.id, monthStart, now);

  final weeklyTargetH = logic.timeSliding(a.id, 7).targetMin / 60.0;
  final weekProgress = weeklyTargetH > 0
      ? (durWeek.inMinutes / 60.0 / weeklyTargetH).clamp(0.0, 1.0)
      : 0.0;

  String fmt(Duration d) {
    if (d.inMinutes == 0) return '—';
    if (d.inHours == 0) return '${d.inMinutes}min';
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h${m.toString().padLeft(2, '0')}';
  }

  // Courbe 60 j (moyennes glissantes 7 j / 30 j).
  final start = today.subtract(const Duration(days: 59));
  final end = today.add(const Duration(days: 1));
  final mbd = timeByDayForActivity(
      sessions: logic.state.sessions,
      activityId: a.id,
      start: start,
      end: end,
      now: now);
  final s7 = movingAvgHoursSeries(
      minutesByDay: mbd, today: now, windowDays: 7, points: 30);
  final s30 = movingAvgHoursSeries(
      minutesByDay: mbd, today: now, windowDays: 30, points: 30);
  final goalH = (logic.timeSliding(a.id, 7).targetMin / 7.0) / 60.0;

  // Heatmap DÉTAIL par jour sur 12 semaines (7 lignes × 12 colonnes), unités =
  // 30 min. Référence = 90e percentile des jours actifs (intensité relative).
  const cellSize = 12.0, gap = 2.0, weeks = 12;
  final thisMonday = today.subtract(Duration(days: today.weekday - 1));
  final startMonday = thisMonday.subtract(const Duration(days: 77));
  final Map<String, int> countByYmd = {};
  for (final s in logic.state.sessions.where((s) => s.activityId == a.id)) {
    final sEnd = s.endAt ?? now;
    if (s.startAt.isAfter(now) || sEnd.isBefore(startMonday)) continue;
    var cursor = DateTime(s.startAt.year, s.startAt.month, s.startAt.day);
    while (!cursor.isAfter(today)) {
      final dayEnd = cursor.add(const Duration(days: 1));
      final segStart = cursor.isBefore(s.startAt) ? s.startAt : cursor;
      final segEnd = dayEnd.isAfter(sEnd) ? sEnd : dayEnd;
      final mins = segEnd.difference(segStart).inMinutes;
      if (mins > 0) {
        final ymd =
            '${cursor.year}${cursor.month.toString().padLeft(2, '0')}${cursor.day.toString().padLeft(2, '0')}';
        countByYmd[ymd] = (countByYmd[ymd] ?? 0) + (mins / 30).ceil();
      }
      cursor = dayEnd;
    }
  }
  final referenceCount =
      percentileOf(countByYmd.values.toList(), 0.90).clamp(1.0, double.infinity);

  // Déroulés réutilisables de cette activité (séances) — lus une fois,
  // rafraîchis après création/édition via le StatefulBuilder.
  final sync = FirestoreSync();
  var templates = await sync.fetchSessionTemplates(activityId: a.id);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (bctx) => StatefulBuilder(builder: (ctx, setSheet) {
      final cs = Theme.of(ctx).colorScheme;
      Widget miniStat(String label, String value) => Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(.4))),
              Text(value,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withOpacity(.85))),
            ],
          );
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header.
                Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 10),
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 20)),
                        if (domain != null)
                          Text(domain.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: color,
                                  fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                // ── Déroulés (séances réutilisables de cette activité) ────────
                // ▶ = chrono sur l'activité + player d'étapes dans Maintenant.
                Row(children: [
                  Text('DÉROULÉS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: cs.onSurface.withOpacity(.4))),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Nouveau',
                        style: TextStyle(fontSize: 12.5)),
                    onPressed: () async {
                      final t = await Navigator.of(ctx).push<SessionTemplate>(
                          MaterialPageRoute(
                              builder: (_) => SessionTemplateEditor(
                                  logic: logic, activity: a)));
                      if (t != null) {
                        templates =
                            await sync.fetchSessionTemplates(activityId: a.id);
                        setSheet(() {});
                      }
                    },
                  ),
                ]),
                if (templates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Une séance réutilisable : les étapes s\'égrènent dans '
                      'Maintenant, le temps se trace ici.',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withOpacity(.45)),
                    ),
                  ),
                for (final t in templates)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final r = await Navigator.of(ctx)
                          .push<SessionTemplate>(MaterialPageRoute(
                              builder: (_) => SessionTemplateEditor(
                                  logic: logic,
                                  activity: a,
                                  existing: t)));
                      if (r != null) {
                        templates =
                            await sync.fetchSessionTemplates(activityId: a.id);
                        setSheet(() {});
                      }
                    },
                    onLongPress: () async {
                      await sync.archiveSessionTemplate(t.id);
                      templates =
                          await sync.fetchSessionTemplates(activityId: a.id);
                      setSheet(() {});
                    },
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withOpacity(.3)),
                      ),
                      child: Row(children: [
                        Icon(Icons.playlist_play_rounded,
                            size: 20, color: color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              Text('${t.steps.length} étape(s)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurface.withOpacity(.5))),
                            ],
                          ),
                        ),
                        // ▶ chrono + player — le déroulé attend dans Maintenant.
                        IconButton(
                          icon: Icon(Icons.play_circle_fill_rounded,
                              size: 30, color: color),
                          tooltip: 'Lancer la séance',
                          onPressed: () {
                            logic.startTemplate(t);
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                  '▶ « ${t.title} » lancée — le déroulé t\'attend dans Maintenant.'),
                              duration: const Duration(seconds: 3),
                            ));
                          },
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 10),
                // Hero semaine + progression, stats secondaires.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SEMAINE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: cs.onSurface.withOpacity(.4))),
                          Text(fmt(durWeek),
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  height: 1.0)),
                          if (weeklyTargetH > 0) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: weekProgress,
                                minHeight: 6,
                                backgroundColor: color.withOpacity(.12),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    weekProgress >= 1.0
                                        ? Colors.green
                                        : color),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text('${(weekProgress * 100).round()}% de l\'objectif',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurface.withOpacity(.4))),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        miniStat("AUJOURD'HUI", fmt(durDay)),
                        const SizedBox(height: 6),
                        miniStat('CE MOIS', fmt(durMonth)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Courbe 60 j.
                SizedBox(
                  height: 80,
                  child: MiniAvgLineChart(
                      series7: s7,
                      series30: s30,
                      goalHoursPerDay: goalH,
                      color: color),
                ),
                if (showHeatmap) ...[
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(
                                weeks,
                                (col) => Padding(
                                      padding: const EdgeInsets.only(right: gap),
                                      child: Column(
                                        children: List.generate(7, (row) {
                                          final d = startMonday.add(
                                              Duration(days: col * 7 + row));
                                          if (d.isAfter(today)) {
                                            return const SizedBox(
                                                height: cellSize + gap,
                                                width: cellSize);
                                          }
                                          final ymd =
                                              '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
                                          final count = countByYmd[ymd] ?? 0;
                                          final intensity = count == 0
                                              ? 0.0
                                              : (count / referenceCount)
                                                  .clamp(0.15, 1.0);
                                          final emptyColor =
                                              cs.onSurface.withOpacity(.10);
                                          final cellColor = count == 0
                                              ? emptyColor
                                              : Color.lerp(emptyColor, color,
                                                  intensity)!;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: gap),
                                            child: Container(
                                              width: cellSize,
                                              height: cellSize,
                                              decoration: BoxDecoration(
                                                color: cellColor,
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                          );
                                        }),
                                      ),
                                    )),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('12 sem.',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withOpacity(.35))),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                // Désactiver l'action jusqu'à une date (snooze) : plus de nuisible
                // tant que la date n'est pas atteinte.
                Builder(builder: (_) {
                  final until = logic.snoozedUntilOf(a.id);
                  final snoozed =
                      until != null && until.isAfter(DateTime.now());
                  if (snoozed) {
                    return SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          logic.clearSnooze(a.id);
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.alarm_on, size: 18),
                        label: Text(
                            'Réactiver (off → ${until.day}/${until.month})'),
                      ),
                    );
                  }
                  return SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final n = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: n.add(const Duration(days: 7)),
                          firstDate: n.add(const Duration(days: 1)),
                          lastDate: DateTime(n.year + 2),
                          helpText: 'Désactiver « ${a.name} » jusqu\'au',
                        );
                        if (picked == null) return;
                        logic.snoozeActivityUntil(a.id, picked);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.snooze, size: 18),
                      label: const Text('Désactiver jusqu\'à…'),
                    ),
                  );
                }),
                // Actions de projet liées à CETTE activité (chrono ciblé).
                if (!a.isHabit) ...[
                  const SizedBox(height: 18),
                  StatefulBuilder(builder: (ctx2, setLocal) {
                    final own = logic.ownActionsOf(a.id);
                    final linked = logic.actionsLinkedTo(a.id);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text('✅ Actions',
                                style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await _pickUnlinkedAction(
                                  ctx2, logic, a.domainId);
                              if (picked == null) return;
                              picked.action.linkedActivityId = a.id;
                              logic.onChange();
                              await FirestoreSync().saveProjectTasks(
                                  picked.project.id, picked.project.tasks);
                              setLocal(() {});
                            },
                            icon: const Icon(Icons.add_link, size: 16),
                            label: const Text('Lier'),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.add, size: 20, color: color),
                            tooltip: 'Créer une action',
                            onPressed: () async {
                              final title = await _promptActionTitle(
                                  ctx2, 'Nouvelle action', '');
                              if (title == null) return;
                              logic.addOwnAction(a.id, title);
                              setLocal(() {});
                            },
                          ),
                        ]),
                        if (own.isEmpty && linked.isEmpty)
                          Text('Aucune action — ＋ pour en créer, 🔗 pour en lier.',
                              style: TextStyle(
                                  color: cs.onSurface.withOpacity(.4),
                                  fontSize: 12)),
                        // Actions PROPRES de l'activité (créées sur place, sans tâche).
                        for (final act in own)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              InkWell(
                                onTap: () {
                                  logic.toggleOwnAction(a.id, act.id);
                                  setLocal(() {});
                                },
                                child: Icon(
                                    act.done
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 15,
                                    color: act.done
                                        ? const Color(0xFF4CD787)
                                        : cs.onSurface.withOpacity(.3)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final title = await _promptActionTitle(
                                        ctx2, 'Renommer l\'action', act.title);
                                    if (title == null) return;
                                    logic.renameOwnAction(a.id, act.id, title);
                                    setLocal(() {});
                                  },
                                  child: Text(act.title,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          decoration: act.done
                                              ? TextDecoration.lineThrough
                                              : null,
                                          color: act.done
                                              ? cs.onSurface.withOpacity(.4)
                                              : cs.onSurface)),
                                ),
                              ),
                              if (!act.done)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(Icons.play_circle_fill,
                                      color: color, size: 22),
                                  tooltip: 'Lancer le chrono',
                                  onPressed: () {
                                    logic.start(a.id, actionId: act.id);
                                    Navigator.pop(ctx);
                                  },
                                ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.close,
                                    size: 16,
                                    color: cs.onSurface.withOpacity(.3)),
                                tooltip: 'Supprimer',
                                onPressed: () {
                                  logic.removeOwnAction(a.id, act.id);
                                  setLocal(() {});
                                },
                              ),
                            ]),
                          ),
                        // Actions de projet LIÉES (TaskAction.linkedActivityId).
                        for (final e in linked)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(children: [
                                Icon(
                                    e.action.done
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 15,
                                    color: e.action.done
                                        ? const Color(0xFF4CD787)
                                        : cs.onSurface.withOpacity(.3)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(e.action.title,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          decoration: e.action.done
                                              ? TextDecoration.lineThrough
                                              : null,
                                          color: e.action.done
                                              ? cs.onSurface.withOpacity(.4)
                                              : cs.onSurface)),
                                ),
                                if (!e.action.done)
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.play_circle_fill,
                                        color: color, size: 22),
                                    tooltip: 'Lancer le chrono',
                                    onPressed: () {
                                      logic.start(a.id,
                                          taskId: e.task.id,
                                          actionId: e.action.id);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(Icons.link_off,
                                      size: 16,
                                      color: cs.onSurface.withOpacity(.3)),
                                  tooltip: 'Délier',
                                  onPressed: () async {
                                    e.action.linkedActivityId = null;
                                    logic.onChange();
                                    await FirestoreSync().saveProjectTasks(
                                        e.project.id, e.project.tasks);
                                    setLocal(() {});
                                  },
                                ),
                              ]),
                            ),
                      ],
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      );
    }),
  );
}

// Picker des actions NON liées du domaine → pour lier à une activité depuis sa fiche.
Future<({Project project, TaskAction action})?> _pickUnlinkedAction(
    BuildContext context, AppLogic logic, String domainId) async {
  final candidates = <({Project project, TaskAction action})>[];
  for (final p in logic.currentProjects) {
    if (p.domainId != domainId || p.status == 'archived') continue;
    for (final t in p.tasks) {
      if (t.status == 'done' || t.status == 'skipped') continue;
      for (final act in t.actions) {
        if (!act.done && (act.linkedActivityId ?? '').isEmpty) {
          candidates.add((project: p, action: act));
        }
      }
    }
  }
  if (candidates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucune action disponible à lier dans ce domaine.')));
    return null;
  }
  return showModalBottomSheet<({Project project, TaskAction action})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Lier une action',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          for (final e in candidates)
            ListTile(
              dense: true,
              title: Text(e.action.title),
              subtitle: Text(e.project.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(sheetCtx, e),
            ),
        ],
      ),
    ),
  );
}

// Saisie du titre d'une action propre (création / renommage).
Future<String?> _promptActionTitle(
    BuildContext context, String title, String initial) async {
  final ctrl = TextEditingController(text: initial);
  ctrl.selection =
      TextSelection(baseOffset: 0, extentOffset: initial.length);
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Décris l\'action…'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
  final v = res?.trim();
  return (v == null || v.isEmpty) ? null : v;
}
