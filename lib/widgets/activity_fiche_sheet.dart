import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/budget_window.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart' show setActionDone;
import 'package:productivitwo_v1/utils/coups.dart' show coupLabel;
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/mode_colors.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/time_scope.dart' show timeByDayForActivity, movingAvgHoursSeries, MiniAvgLineChart;
import 'package:productivitwo_v1/utils/week_stats.dart' show minutesByActivity;
import 'package:productivitwo_v1/widgets/deep_work_sheet.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/mode_sheet.dart' show modeChipFor;
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart' show showObjectiveTrajectorySheet;
import 'package:productivitwo_v1/widgets/session_template_editor.dart';
import 'package:productivitwo_v1/widgets/status_row.dart';
import 'package:productivitwo_v1/widgets/confirm_done.dart';

/// Fiche d'une activité-temps (refonte 2026-10 « une carte, une fiche »,
/// remplace `_openActivitySheet` de main.dart) : en-tête d'état, UN geste piloté
/// par le mode (Chrono · « 10 min, malgré tout » · « Deep work 90 min »), la
/// semaine sur la fenêtre de budget, les engagements (objectifs, coups), les
/// actions propres et liées, puis Déroulés et Réglages repliés. Renvoie `true`
/// quand quelque chose a changé ou qu'un chrono a été lancé.
Future<bool> showActivityFiche(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  required Activity activity,
  void Function(Activity a, int minutes)? onLaunchTimed,
  void Function(ScheduleBlock block)? onLaunchBlock,
  /// « Modifier la session » (début, fin, activité, bloc, suppression) ; renvoie vrai si changé.
  Future<bool> Function(Session s)? onEditSession,
}) async {
  final r = await showFiche<bool>(
    context,
    builder: (ctx, scroll) => _ActivityFiche(
        logic: logic, sync: sync, activity: activity, scroll: scroll, onLaunchTimed: onLaunchTimed, onLaunchBlock: onLaunchBlock, onEditSession: onEditSession),
  );
  return r ?? _ActivityFicheState.lastChanged;
}

class _ActivityFiche extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final Activity activity;
  final ScrollController scroll;
  final void Function(Activity a, int minutes)? onLaunchTimed;
  final void Function(ScheduleBlock block)? onLaunchBlock;
  final Future<bool> Function(Session s)? onEditSession;
  const _ActivityFiche(
      {required this.logic, required this.sync, required this.activity, required this.scroll, this.onLaunchTimed, this.onLaunchBlock, this.onEditSession});
  @override
  State<_ActivityFiche> createState() => _ActivityFicheState();
}

class _ActivityFicheState extends State<_ActivityFiche> {
  /// Dernier « quelque chose a changé » : la feuille peut être fermée d'un glissement sans valeur de retour.
  static bool lastChanged = false;
  bool _timerOpen = false;
  bool _tplOpen = false;
  bool _setOpen = false;
  List<StrategicObjective> _objectives = const [];
  List<SessionTemplate>? _templates;

  AppLogic get logic => widget.logic;
  Activity get a => widget.activity;

  @override
  void initState() {
    super.initState();
    lastChanged = false;
    logic.addListener(_onLogic);
    _loadObjectives();
    _loadTemplates();
  }

  Future<void> _loadObjectives() async {
    try {
      final all = await widget.sync.fetchStrategicObjectives();
      if (mounted) setState(() => _objectives = all.where((o) => o.status == 'active').toList());
    } catch (_) {}
  }

  Future<void> _loadTemplates() async {
    try {
      final t = await widget.sync.fetchSessionTemplates(activityId: a.id);
      if (mounted) setState(() => _templates = t);
    } catch (_) {}
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  void _changed() {
    lastChanged = true;
    logic.onChange();
    if (mounted) setState(() {});
  }

  void _close(bool v) {
    lastChanged = v || lastChanged;
    Navigator.of(context).pop(lastChanged);
  }

  // ── Gestes ──────────────────────────────────────────────────────────────────

  void _start({String? actionId, String? taskId}) {
    logic.start(a.id, taskId: taskId, actionId: actionId);
    _close(true);
  }

  Future<void> _deepWork() async {
    final launch = widget.onLaunchBlock;
    if (launch == null) return _start();
    final ok = await showDeepWorkSheet(context,
        logic: logic, sync: widget.sync, date: logic.livedTodayYmd, onLaunch: launch, objectives: _objectives, preferActivityId: a.id);
    if (ok && mounted) _close(true);
  }

  // ── Lectures ────────────────────────────────────────────────────────────────

  ({StrategicObjective o, CommitmentProgress c})? _commitment(StrategicObjective o, DateTime now) {
    if (!o.timeCommitments.any((c) => c.activityId == a.id)) return null;
    final st = logic.state;
    final p = computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, now);
    final c = p.items.where((i) => i.type == 'time' && i.activityId == a.id).firstOrNull;
    return c == null ? null : (o: o, c: c);
  }

  List<({Project project, ProjectTask task, TaskAction action})> _linkedActions() => [
        for (final p in logic.currentProjects)
          if (p.status == 'active')
            for (final t in p.tasks)
              if (t.status != 'done' && t.status != 'skipped')
                for (final x in t.actions)
                  if (x.linkedActivityId == a.id) (project: p, task: t, action: x),
      ];

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final st = logic.state;
    final dark = cs.brightness == Brightness.dark;
    final mode = logic.mode;
    final domColor = domainColor(a.domainId, st.activeDomains) ?? cs.primary;
    final accent = modeAccentOverride(mode, dark: dark) ?? cs.primary;
    final running = logic.runningActivity()?.id == a.id;
    final paused = logic.isActivitySnoozed(a.id, now);
    final until = paused ? logic.snoozedUntilOf(a.id) : null;
    final resting = logic.isDomainResting(a.domainId);
    final domain = st.activeDomains.where((d) => d.id == a.domainId).firstOrNull;

    // Fenêtre de budget.
    final days = logic.budgetWindowDays;
    final start = budgetWindowStart(now, days);
    final idx = budgetDayIndex(now, days);
    final doneWin = minutesByActivity(st.sessions, start, now)[a.id] ?? 0;
    final expected = a.goalMin * idx;
    final total = a.goalMin * days;
    final pctInt = a.goalMin <= 0 ? 100 : (expected <= 0 ? 100 : (doneWin / expected * 100).round());
    final min7 = logic.timeSliding(a.id, 7).doneMin;
    final engaged = [for (final o in _objectives) if (_commitment(o, now) case final e?) e];

    final String chip;
    final Color chipColor;
    if (paused) {
      chip = until == null ? 'en pause' : 'en pause jusqu\'au ${until.day}/${until.month.toString().padLeft(2, '0')}';
      chipColor = kPalierMuted;
    } else if (resting) {
      chip = 'domaine en veille';
      chipColor = kPalierMuted;
    } else if (a.goalMin <= 0) {
      chip = 'sans objectif';
      chipColor = kPalierMuted;
    } else {
      chip = pctInt >= 85 ? 'au rythme' : (pctInt >= 60 ? 'à surveiller' : 'en retard');
      chipColor = palierColor(pctInt);
    }
    final kpi = [
      if (domain != null) domain.name,
      if (a.goalMin > 0) 'minimum ${fmtMin(a.goalMin)} / j',
      '${fmtMin(min7)} sur 7 jours',
      if (engaged.isNotEmpty) 'engagée dans « ${engaged.first.o.title} »${engaged.length > 1 ? ' +${engaged.length - 1}' : ''}',
    ].join(' · ');

    // Geste principal.
    final String primary;
    final IconData icon;
    final VoidCallback onPrimary;
    if (running) {
      primary = 'Arrêter';
      icon = Icons.stop_rounded;
      onPrimary = () => logic.stopActive();
    } else if (mode == DayMode.low && widget.onLaunchTimed != null) {
      primary = '10 min, malgré tout';
      icon = Icons.timer_outlined;
      onPrimary = () {
        widget.onLaunchTimed!(a, 10);
        _close(true);
      };
    } else if (mode == DayMode.high) {
      primary = 'Deep work 90 min · sur quoi ?';
      icon = Icons.bolt_rounded;
      onPrimary = _deepWork;
    } else {
      primary = 'Chrono';
      icon = Icons.play_arrow_rounded;
      onPrimary = () => _start();
    }

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        FicheHeader(
          leading: Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: domColor, shape: BoxShape.circle)),
          title: a.name,
          chip: chip,
          chipColor: chipColor,
          kpi: kpi,
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _primaryButton(primary, icon, onPrimary, accent, outlined: running)),
          if (!running && mode == DayMode.normal && widget.onLaunchTimed != null) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() => _timerOpen = !_timerOpen),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 14), foregroundColor: cs.onSurface.withValues(alpha: .8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.timer_outlined, size: 18), Icon(_timerOpen ? Icons.expand_less : Icons.expand_more, size: 18)]),
            ),
          ],
          ]),
        ),
        if (_timerOpen && !running && mode == DayMode.normal) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in const [5, 10, 15, 25, 45])
              ActionChip(
                label: Text('$m min'),
                avatar: a.timerMin == m ? const Icon(Icons.check, size: 14) : null,
                onPressed: () {
                  widget.onLaunchTimed!(a, m);
                  _close(true);
                },
              ),
          ]),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            running
                ? 'Le chrono tourne sur ${a.name}.'
                : switch (mode) {
                    DayMode.low => 'Chrono + minuteur de 10 min. Fait, ça portera le chip « malgré tout ».',
                    DayMode.high => 'Un bloc de 90 min à partir de maintenant, chrono lancé après ton tap.',
                    DayMode.normal => 'Chrono libre ; ⏱ lance un décompte qui sonne.',
                  },
            style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55)),
          ),
        ),

        // ── Semaine ────────────────────────────────────────────────────────
        FicheTitle(days == 14 ? 'SUR 14 JOURS' : 'CETTE SEMAINE',
            trailing: a.goalMin > 0 ? FicheDelta('$pctInt % de l\'attendu', color: palierColor(pctInt)) : FicheDelta(fmtMin(doneWin), color: cs.onSurface.withValues(alpha: .6))),
        _weekBox(cs, now, start, days, idx, doneWin, expected, total, pctInt),

        // ── Tendance (2026-10 : au-dessus des engagements, toujours visible) ──
        const FicheTitle('TENDANCE · 12 SEMAINES'),
        _trendBox(cs, now),

        // ── Engagements ────────────────────────────────────────────────────
        FicheTitle('ENGAGEMENTS', trailing: engaged.isEmpty ? null : FicheDelta('${engaged.length} objectif${engaged.length > 1 ? 's' : ''}', color: cs.onSurface.withValues(alpha: .6))),
        if (engaged.isEmpty)
          const FicheNote('Aucun objectif n\'engage cette activité. Édite un objectif (étape Mesurable) pour y rattacher un temps hebdo.')
        else
          for (final e in engaged) _engagementRow(e.o, e.c, now),

        // ── Actions ────────────────────────────────────────────────────────
        ..._actionsSection(cs, now),

        // ── Derniers chronos ───────────────────────────────────────────────
        ..._sessionsSection(cs, now),


        // ── Déroulés ───────────────────────────────────────────────────────
        FicheTitle('DÉROULÉS · ${_templates?.length ?? 0}', trailing: _foldButton(cs, _tplOpen, () => setState(() => _tplOpen = !_tplOpen))),
        if (_tplOpen) ..._templatesSection(cs),

        // ── Réglages ───────────────────────────────────────────────────────
        FicheTitle('RÉGLAGES', trailing: _foldButton(cs, _setOpen, () => setState(() => _setOpen = !_setOpen))),
        if (_setOpen) ..._settingsSection(cs, now, paused),
      ],
    );
  }

  Widget _primaryButton(String label, IconData icon, VoidCallback onTap, Color accent, {bool outlined = false}) {
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 20),
      const SizedBox(width: 6),
      Flexible(child: Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
    ]);
    const style = TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.2);
    if (outlined) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder(), foregroundColor: accent, side: BorderSide(color: accent.withValues(alpha: .5)), textStyle: style),
        child: child,
      );
    }
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder(), backgroundColor: accent, foregroundColor: Colors.white, textStyle: style),
      child: child,
    );
  }

  static final _smallBtn = TextButton.styleFrom(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700));

  Widget _foldButton(ColorScheme cs, bool open, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: _smallBtn.copyWith(foregroundColor: WidgetStatePropertyAll(cs.onSurface.withValues(alpha: .6))),
        child: Text(open ? 'replier ▴' : 'afficher ▾'),
      );

  Widget _weekBox(ColorScheme cs, DateTime now, DateTime start, int days, int idx, int doneWin, int expected, int total, int pctInt) {
    final byDay = timeByDayForActivity(sessions: logic.state.sessions, activityId: a.id, start: start, end: start.add(Duration(days: days)), now: now);
    final values = [for (var i = 0; i < days; i++) byDay[DateTime(start.year, start.month, start.day + i)] ?? 0];
    final max = values.fold(1, (m, v) => v > m ? v : m);
    final color = a.goalMin > 0 ? palierColor(pctInt) : cs.primary;
    const dayNames = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('fait ${fmtMin(doneWin)}', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .7), fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          if (a.goalMin > 0)
            Expanded(
              child: Text('attendu ${fmtMin(expected)} · minimum ${fmtMin(total)}',
                  textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55))),
            ),
        ]),
        if (a.goalMin > 0) ...[
          const SizedBox(height: 8),
          ExpectedBar(done: doneWin, total: total, expected: expected, color: color),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 30,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < days; i++) ...[
              Expanded(
                child: Container(
                  height: (4 + 26 * values[i] / max).clamp(4.0, 30.0),
                  decoration: BoxDecoration(
                    color: i >= idx ? Colors.transparent : color.withValues(alpha: values[i] == 0 ? .15 : (i == idx - 1 ? 1 : .7)),
                    borderRadius: BorderRadius.circular(2),
                    border: i >= idx ? Border.all(color: cs.onSurface.withValues(alpha: .08)) : null,
                  ),
                ),
              ),
              if (i < days - 1) const SizedBox(width: 2),
            ],
          ]),
        ),
        const SizedBox(height: 3),
        Row(children: [
          Text(dayNames[start.weekday - 1], style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: .45))),
          const Spacer(),
          Text('${dayNames[now.weekday - 1]} · aujourd\'hui', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: .45))),
          const Spacer(),
          Text(days == 14 ? 'jour 14' : 'dim.', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: .45))),
        ]),
      ]),
    );
  }

  Widget _engagementRow(StrategicObjective o, CommitmentProgress c, DateTime now) {
    final pct = c.target <= 0 ? 100 : (c.done / c.target * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StatusRow(
        leading: Icon(o.isTactical ? Icons.bolt_rounded : Icons.flag_rounded, color: const Color(0xFF00897B)),
        title: o.title,
        sub: [
          if (o.isTactical) 'coup · ${coupLabel(o, now)}',
          '${fmtMin(c.done)} / ${fmtMin(c.target)} cette semaine',
        ].join(' · '),
        bar: (done: c.done, total: c.target, expected: c.target * (now.weekday / 7)),
        pct: pct,
        chip: '$pct %',
        onTap: () async {
          final changed = await showObjectiveTrajectorySheet(context, logic: logic, sync: widget.sync, objective: o, projects: logic.currentProjects);
          if (changed && mounted) _changed();
        },
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  List<Widget> _actionsSection(ColorScheme cs, DateTime now) {
    final own = a.ownActions.where((x) => !x.done).toList();
    final ownDone = a.ownActions.where((x) => x.done).toList()
      ..sort((x, y) => (y.doneAt ?? DateTime(2000)).compareTo(x.doneAt ?? DateTime(2000)));
    final linked = _linkedActions();
    final n = own.length + linked.length;
    return [
      FicheTitle('ACTIONS · $n',
          trailing: Wrap(alignment: WrapAlignment.end, children: [
            TextButton(onPressed: _addOwn, style: _smallBtn, child: const Text('+ ajouter')),
            TextButton(onPressed: _linkAction, style: _smallBtn, child: const Text('lier')),
          ])),
      if (n == 0 && ownDone.isEmpty) const FicheNote('Aucune action. « + ajouter » crée une action propre à l\'activité ; « lier » rattache une action de projet du même domaine (le chrono y sera ciblé).'),
      for (final x in own)
        FicheStep(
          title: x.title,
          detail: [if (x.estimatedMin != null) '≈ ${fmtMin(x.estimatedMin!)}', ...x.allContexts].join(' · ').ifEmptyNull,
          onTap: () {
            logic.toggleOwnAction(a.id, x.id, true);
            _changed();
          },
          trailing: _playChip(() => _start(actionId: x.id)),
        ),
      for (final l in linked)
        FicheStep(
          title: l.action.title,
          detail: '${l.project.title} › ${l.task.title}',
          onTap: () async {
            if (!await confirmDone(context, title: l.action.title)) return;
            setActionDone(l.action, true);
            try {
              await widget.sync.patchActionOf(l.project, l.action);
            } catch (_) {}
            _changed();
          },
          trailing: _playChip(() => _start(taskId: l.task.id, actionId: l.action.id)),
        ),
      for (final x in ownDone.take(3))
        FicheStep(
          title: x.title,
          done: true,
          detail: x.doneAt == null ? null : 'faite le ${x.doneAt!.day}/${x.doneAt!.month.toString().padLeft(2, '0')}',
          onTap: () {
            logic.toggleOwnAction(a.id, x.id, false);
            _changed();
          },
          trailing: modeChipFor(context, logic, x.doneAt),
        ),
    ];
  }

  Widget _playChip(VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: cs.primary.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
        child: Icon(Icons.play_arrow_rounded, size: 18, color: cs.primary),
      ),
    );
  }

  Future<void> _addOwn() async {
    final title = await _promptTitle('Nouvelle action', '');
    if (title == null) return;
    logic.addOwnAction(a.id, title);
    try {
      await widget.sync.addOwnActionToActivity(a.id, title);
    } catch (_) {}
    _changed();
  }

  Future<void> _linkAction() async {
    final candidates = <({Project project, ProjectTask task, TaskAction action})>[];
    for (final p in logic.currentProjects) {
      if (p.status != 'active' || (a.domainId.isNotEmpty && p.domainId != null && p.domainId != a.domainId)) continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        for (final x in t.actions) {
          if (!x.done && (x.linkedActivityId ?? '').isEmpty) candidates.add((project: p, task: t, action: x));
        }
      }
    }
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune action de projet à lier dans ce domaine.')));
      return;
    }
    final picked = await showModalBottomSheet<({Project project, ProjectTask task, TaskAction action})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .7),
          child: ListView(shrinkWrap: true, children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Lier une action', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            for (final e in candidates)
              ListTile(dense: true, title: Text(e.action.title), subtitle: Text('${e.project.title} › ${e.task.title}', maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => Navigator.pop(c, e)),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    picked.action.linkedActivityId = a.id;
    try {
      await widget.sync.patchActionOf(picked.project, picked.action);
    } catch (_) {}
    _changed();
  }

  Future<String?> _promptTitle(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.sentences, onSubmitted: (v) => Navigator.pop(d, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    final v = res?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  // ── Derniers chronos ────────────────────────────────────────────────────────

  List<Widget> _sessionsSection(ColorScheme cs, DateTime now) {
    final all = logic.state.sessions.where((s) => s.activityId == a.id && !s.deleted).toList()..sort((x, y) => y.startAt.compareTo(x.startAt));
    final last = all.take(3).toList();
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    String day(DateTime d) {
      final t = DateTime(now.year, now.month, now.day);
      final x = DateTime(d.year, d.month, d.day);
      final diff = t.difference(x).inDays;
      if (diff == 0) return 'Aujourd\'hui';
      if (diff == 1) return 'Hier';
      const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
      return '${days[d.weekday - 1]} ${d.day}/${d.month.toString().padLeft(2, '0')}';
    }
    return [
      FicheTitle('DERNIERS CHRONOS', trailing: all.isEmpty ? null : FicheDelta('${all.length} au total', color: cs.onSurface.withValues(alpha: .6))),
      if (last.isEmpty)
        const FicheNote('Aucun chrono sur cette activité pour l\'instant.')
      else
        for (final s in last)
          FicheStep(
            title: '${day(s.startAt)} · ${hm(s.startAt)}${s.endAt == null ? ' → en cours' : ' → ${hm(s.endAt!)}'}',
            detail: [
              fmtMin((s.endAt ?? now).difference(s.startAt).inMinutes),
              if (s.taskId != null) 'sur une tâche',
              if (s.actionId != null) 'action ciblée',
            ].join(' · '),
            done: s.endAt != null,
            current: s.endAt == null,
            onTap: widget.onEditSession == null || s.endAt == null
                ? null
                : () async {
                    final changed = await widget.onEditSession!(s);
                    if (changed && mounted) _changed();
                  },
            trailing: widget.onEditSession == null || s.endAt == null ? null : Icon(Icons.more_horiz, color: cs.onSurface.withValues(alpha: .5)),
          ),
    ];
  }

  // ── Tendance ────────────────────────────────────────────────────────────────

  Widget _trendBox(ColorScheme cs, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final gridStart = monday.subtract(const Duration(days: 77)); // 12 semaines
    final start = today.subtract(const Duration(days: 89));
    final byDay = timeByDayForActivity(sessions: logic.state.sessions, activityId: a.id, start: start, end: today.add(const Duration(days: 1)), now: now);
    final s7 = movingAvgHoursSeries(minutesByDay: byDay, today: now, windowDays: 7, points: 30);
    final s30 = movingAvgHoursSeries(minutesByDay: byDay, today: now, windowDays: 30, points: 30);
    final goalH = a.goalMin > 0 ? a.goalMin / 60.0 : null;
    final avg7 = s7.isEmpty ? 0 : (s7.last * 60).round();
    final avg30 = s30.isEmpty ? 0 : (s30.last * 60).round();
    final color = domainColor(a.domainId, logic.state.activeDomains) ?? cs.primary;
    var max = 1;
    for (var i = 0; i < 84; i++) {
      final v = byDay[gridStart.add(Duration(days: i))] ?? 0;
      if (v > max) max = v;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('moyenne 7 j ${fmtMin(avg7)} / j',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: .75))),
          ),
          const SizedBox(width: 10),
          Text('30 j ${fmtMin(avg30)} / j', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55))),
        ]),
        const SizedBox(height: 8),
        SizedBox(height: 70, child: MiniAvgLineChart(series7: s7, series30: s30, goalHoursPerDay: goalH, color: color)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (_, box) {
          const gap = 2.0;
          final cell = ((box.maxWidth - gap * 11) / 12).clamp(6.0, 22.0);
          return Column(children: [
            for (var row = 0; row < 7; row++)
              Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: Row(children: [
                  for (var col = 0; col < 12; col++) ...[
                    Builder(builder: (_) {
                      final d = gridStart.add(Duration(days: col * 7 + row));
                      final v = byDay[d] ?? 0;
                      final future = d.isAfter(today);
                      return Container(
                        width: cell,
                        height: cell,
                        decoration: BoxDecoration(
                          color: future ? Colors.transparent : color.withValues(alpha: v == 0 ? .08 : (.25 + .75 * v / max)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                    if (col < 11) const SizedBox(width: gap),
                  ],
                ]),
              ),
          ]);
        }),
        const SizedBox(height: 4),
        Row(children: [
          Text('il y a 12 sem.', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: .45))),
          const Spacer(),
          Text('cette semaine', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: .45))),
        ]),
      ]),
    );
  }

  // ── Déroulés ────────────────────────────────────────────────────────────────

  List<Widget> _templatesSection(ColorScheme cs) {
    final tpls = _templates;
    Future<void> edit(SessionTemplate? t) async {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionTemplateEditor(logic: logic, activity: a, existing: t)));
      await _loadTemplates();
    }
    return [
      if (tpls == null)
        const FicheNote('Chargement…')
      else if (tpls.isEmpty)
        const FicheNote('Aucun déroulé. Un déroulé = une séance réutilisable en étapes minutées, lancée avec son chrono.')
      else
        for (final t in tpls)
          FicheStep(
            title: t.title,
            detail: '${t.steps.length} étape${t.steps.length > 1 ? 's' : ''}',
            onTap: () => edit(t),
            trailing: _playChip(() {
              logic.startTemplate(t);
              _close(true);
            }),
          ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: () => edit(null), icon: const Icon(Icons.add, size: 18), label: const Text('Nouveau déroulé')),
      ),
    ];
  }

  // ── Réglages ────────────────────────────────────────────────────────────────

  List<Widget> _settingsSection(ColorScheme cs, DateTime now, bool paused) {
    final st = logic.state;
    final domain = st.activeDomains.where((d) => d.id == a.domainId).firstOrNull;
    return [
      FicheStep(title: 'Domaine', detail: domain?.name ?? 'Sans domaine', onTap: _pickDomain, trailing: Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: .4))),
      FicheStep(
        title: 'Cible quotidienne',
        detail: a.goalMin > 0 ? '${fmtMin(a.goalMin)} / j · compte dans le minimum du domaine' : 'aucune',
        onTap: () async {
          final v = await pickDurationMin(context, initial: a.goalMin, title: 'Cible quotidienne', allowZero: true);
          if (v == null) return;
          a.goalMin = v.clamp(0, 720);
          a.targetSource = 'user';
          _changed();
        },
        trailing: Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: .4)),
      ),
      FicheStep(
        title: 'Minuteur par défaut',
        detail: (a.timerMin ?? 0) > 0 ? '${a.timerMin} min' : 'aucun',
        onTap: () async {
          final v = await pickDurationMin(context, initial: a.timerMin ?? 0, title: 'Minuteur par défaut', allowZero: true);
          if (v == null) return;
          logic.setActivityTimerMin(a.id, v == 0 ? null : v);
          _changed();
        },
        trailing: Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: .4)),
      ),
      FicheActions(
        primaryLabel: paused ? 'Reprendre' : 'Mettre en pause jusqu\'à…',
        primaryIcon: paused ? Icons.play_circle_outline : Icons.pause_circle_outline,
        onPrimary: () async {
          if (paused) {
            logic.clearSnooze(a.id);
            _changed();
            return;
          }
          final d = await showDatePicker(
              context: context, initialDate: now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 365)), locale: const Locale('fr', 'FR'));
          if (d == null) return;
          logic.snoozeActivityUntil(a.id, DateTime(d.year, d.month, d.day, 23, 59, 59));
          _changed();
        },
        secondary: [
          (
            label: 'Renommer',
            onTap: () async {
              final v = await _promptTitle('Renommer l\'activité', a.name);
              if (v == null) return;
              a.name = v;
              _changed();
            }
          ),
          (
            label: 'Supprimer',
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text('Supprimer « ${a.name} » ?'),
                  content: const Text('Cette activité sera supprimée et retirée des plans.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer')),
                  ],
                ),
              );
              if (ok != true) return;
              logic.deleteActivityCascade(a.id);
              if (mounted) _close(true);
            }
          ),
        ],
      ),
    ];
  }

  Future<void> _pickDomain() async {
    final domains = logic.state.activeDomains;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Choisir un domaine', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          for (final d in domains)
            ListTile(
              leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: domainColor(d.id, domains) ?? Colors.grey, shape: BoxShape.circle)),
              title: Text(d.name),
              trailing: d.id == a.domainId ? const Icon(Icons.check, size: 18) : null,
              onTap: () => Navigator.pop(c, d.id),
            ),
        ]),
      ),
    );
    if (picked == null || picked == a.domainId) return;
    a.domainId = picked;
    _changed();
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
