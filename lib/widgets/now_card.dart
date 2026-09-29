import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/routine_match.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/ring_painter.dart';

/// Carte MAINTENANT (handoff iOS Aujourd'hui 2026-09, § 3.2) : en tête de
/// l'onglet Aujourd'hui, même lecture que la carte du web — bloc focal
/// (`focusBlock`), anneau de progression (session ouverte, sinon créneau),
/// boutons selon l'état, checklists dépliables pendant une session.
/// Aucune logique métier propre : `today_logic.dart` + `checklist_logic.dart`.
class NowCard extends StatefulWidget {
  final AppLogic logic;
  // Blocs du jour (hors supprimés) et clé du programme, fournis par TodayView
  // qui porte l'unique abonnement au programme.
  final List<ScheduleBlock> blocks;
  final String date;
  final Project? focusProject;
  final ProjectTask? focusTask;
  final DateTime? countdownEndsAt;
  final int? countdownTotalSec;
  final void Function(ScheduleBlock block) onLaunch;
  final void Function(ScheduleBlock block)? onOpenSource;
  final VoidCallback onStopTimer;
  final VoidCallback onStopCountdown;
  final VoidCallback? onOpenRoutines;
  final VoidCallback? onOpenActivities;
  final VoidCallback? onChallenge;

  const NowCard({
    super.key,
    required this.logic,
    required this.blocks,
    required this.date,
    required this.onLaunch,
    required this.onStopTimer,
    required this.onStopCountdown,
    this.focusProject,
    this.focusTask,
    this.countdownEndsAt,
    this.countdownTotalSec,
    this.onOpenSource,
    this.onOpenRoutines,
    this.onOpenActivities,
    this.onChallenge,
  });

  @override
  State<NowCard> createState() => _NowCardState();
}

class _NowCardState extends State<NowCard> {
  final _sync = FirestoreSync();
  Timer? _tick;
  bool _expanded = false;
  // Routine liée déjà validée pour ce bloc (1 incrément max par bloc).
  final Set<String> _routineHit = {};

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(NowCard old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) _routineHit.clear();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  List<ScheduleBlock> get _blocks => widget.blocks;
  String get _date => widget.date;

  // ── Données ─────────────────────────────────────────────────────────────────

  Session? get _openSession {
    Session? last;
    for (final s in widget.logic.state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  Project? _project(String? id) {
    if (id == null) return null;
    for (final p in widget.logic.currentProjects) {
      if (p.id == id) return p;
    }
    return null;
  }

  Activity? _activity(String? id) {
    if (id == null) return null;
    for (final a in widget.logic.state.activities) {
      if (a.id == id) return a;
    }
    return null;
  }

  String _clock(int min) =>
      '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

  String _mmss(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _fmtMin(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60, m = min % 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  /// Menu du bloc en cours quand on fait autre chose : reprendre (chrono sur
  /// sa source), décaler après la parenthèse, fait, passer.
  Future<void> _blockMenu(BuildContext anchor, ScheduleBlock b) async {
    final box = anchor.findRenderObject() as RenderBox;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(
        box.localToGlobal(Offset.zero, ancestor: overlay) & box.size, Offset.zero & overlay.size);
    final launchable = b.projectId != null || b.activityId != null;
    final choice = await showMenu<String>(
      context: anchor,
      position: pos,
      items: [
        PopupMenuItem(
            enabled: false,
            child: Text(b.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600))),
        if (launchable) const PopupMenuItem(value: 'resume', child: Text('Reprendre ce bloc')),
        const PopupMenuItem(value: 'shift', child: Text('Décaler après ma parenthèse')),
        const PopupMenuItem(value: 'done', child: Text('Marquer fait')),
        const PopupMenuItem(value: 'skip', child: Text('Passer')),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'resume':
        widget.onLaunch(b);
      case 'shift':
        await _shiftToNow(b);
      case 'done':
        await _markDone(b);
      case 'skip':
        b.status = 'skipped';
        setState(() {});
        await _sync.updateBlockStatus(_date, b.id, 'skipped');
    }
  }

  /// Décale le bloc au prochain quart d'heure : la parenthèse (vaisselle,
  /// appel…) ne mange pas le créneau, elle le pousse.
  Future<void> _shiftToNow(ScheduleBlock b) async {
    final n = DateTime.now();
    final start = (((n.hour * 60 + n.minute) + 14) ~/ 15) * 15;
    if (start + b.durationMin > 24 * 60) return;
    b.startTime = _clock(start);
    setState(() {});
    await _sync.upsertScheduleBlock(_date, b);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${b.title} décalé à ${_clock(start)}'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _markDone(ScheduleBlock b) async {
    b.status = 'done';
    setState(() {});
    await _sync.updateBlockStatus(_date, b.id, 'done');
    _completeLinkedRoutine(b);
  }

  Future<void> _finish(ScheduleBlock b) async {
    widget.onStopTimer();
    await _markDone(b);
  }

  /// Même règle que `daily_schedule_view.dart` : 1 incrément, sans dépasser
  /// la cible, une seule fois par bloc.
  void _completeLinkedRoutine(ScheduleBlock b) {
    if (_routineHit.contains(b.id)) return;
    var act = _activity(b.activityId);
    act ??= routineForBlockTitle(b.title, widget.logic.state.activities);
    if (act == null || !act.isHabit) return;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    _routineHit.add(b.id);
    final tgt = widget.logic.activeHabitTarget(act);
    if (tgt > 0 && widget.logic.habitValueOn(act.id, day) >= tgt) return;
    widget.logic.incHabit(act.id, 1, day);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Routine validée : ${act.name}'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Rendu ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pal = _Palette.of(context);
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final focus = focusBlock(_blocks, nowMin);
    final session = _openSession;
    final running = session == null ? null : widget.logic.runningActivity();

    if (focus == null && session == null) {
      return _frame(
        pal,
        header: _header(pal, null),
        child: NowEmptyPanel(
          logic: widget.logic,
          onOpenRoutines: widget.onOpenRoutines,
          onOpenActivities: widget.onOpenActivities,
          onChallenge: widget.onChallenge,
        ),
      );
    }

    final b = focus?.block;
    final current = focus?.current ?? false;
    final endsAt = widget.countdownEndsAt;
    final remaining = endsAt?.difference(now);
    final countdown = remaining != null && remaining > Duration.zero;

    // Anneau : décompte > session ouverte > créneau du bloc en cours.
    double progress;
    String center;
    if (countdown) {
      final total = widget.countdownTotalSec ?? remaining.inSeconds;
      progress = total > 0 ? 1 - remaining.inSeconds / total : 0;
      center = _mmss(remaining);
    } else if (session != null) {
      final elapsed = now.difference(session.startAt);
      final onBlock = b != null &&
          current &&
          sessionMatchesBlock(session, b,
              projectLinkedActivityId: _project(b.projectId)?.linkedActivityId);
      final totalMin = onBlock ? b.durationMin : 0;
      progress = totalMin > 0 ? elapsed.inSeconds / (totalMin * 60) : 0;
      center = _mmss(elapsed);
    } else if (b != null && current) {
      final elapsedMin = nowMin - blockStartMin(b);
      progress = elapsedMin / b.durationMin;
      center = '${elapsedMin}′';
    } else {
      progress = 0;
      center = b != null ? _clock(blockStartMin(b)) : '--:--';
    }
    progress = progress.clamp(0.0, 1.0);

    final project = _project(b?.projectId);
    // Session ouverte sur AUTRE CHOSE que la source du bloc en cours : la
    // carte montre ce qu'on fait (session) ET ce qui était prévu (bloc), avec
    // des commandes séparées — « Terminer » ne cocherait pas le bon bloc.
    final aside = session != null &&
        b != null &&
        current &&
        !sessionMatchesBlock(session, b, projectLinkedActivityId: project?.linkedActivityId);
    final runningName = running?.name.isNotEmpty == true ? running!.name : 'Chrono libre';
    final origin = aside
        ? null
        : project?.title ??
            _activity(b?.activityId)?.name ??
            (b == null ? _activity(running?.id)?.name : null);
    final title = b != null && (current || session == null) && !aside ? b.title : runningName;
    final next = b != null ? nextBlockAfter(_blocks, b) : null;
    final ensuite = aside
        ? 'Prévu : ${b.title} · ${_fmtMin(b.durationMin)}'
        : b != null && !current && session != null
            ? 'Ensuite · ${b.title}' // session hors bloc : le bloc à venir est « ensuite »
            : next != null
                ? 'Ensuite · ${next.title}'
                : null;
    final catColor = kBCategoryColor[b?.category] ?? pal.primary;

    String? right;
    if (b != null && current) {
      right = 'jusqu\'à ${_clock(blockEndMin(b))}';
    } else if (session != null) {
      right = 'depuis ${_clock(session.startAt.hour * 60 + session.startAt.minute)}';
    } else if (b != null) {
      right = 'à ${_clock(blockStartMin(b))}';
    }

    final hasSource = b != null &&
        widget.onOpenSource != null &&
        (b.projectId != null || b.activityId != null);
    final launchable = b != null && (b.projectId != null || b.activityId != null);

    final buttons = <Widget>[];
    if (aside) {
      buttons.add(Expanded(
          child: _btn(pal, countdown ? 'Arrêter le minuteur' : 'Arrêter',
              primary: true, onTap: countdown ? widget.onStopCountdown : widget.onStopTimer)));
      buttons.add(const SizedBox(width: 8));
      buttons.add(Builder(
          builder: (bctx) => _btn(pal, 'Bloc ▾', onTap: () => _blockMenu(bctx, b))));
    } else if (session != null) {
      if (b != null && current) {
        buttons.add(Expanded(child: _btn(pal, 'Terminer', primary: true, onTap: () => _finish(b))));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_btn(pal, 'Pause', onTap: widget.onStopTimer));
      } else {
        buttons.add(Expanded(
            child: _btn(pal, countdown ? 'Arrêter le minuteur' : 'Arrêter',
                primary: true, onTap: countdown ? widget.onStopCountdown : widget.onStopTimer)));
      }
    } else if (b != null) {
      if (launchable) {
        buttons.add(Expanded(
            child: _btn(pal, current ? 'Lancer' : 'Commencer', primary: true, onTap: () => widget.onLaunch(b))));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_btn(pal, 'Fait', onTap: () => _markDone(b)));
      } else {
        buttons.add(Expanded(child: _btn(pal, 'Marquer fait', primary: true, onTap: () => _markDone(b))));
      }
    }
    if (hasSource) {
      buttons.add(const SizedBox(width: 8));
      buttons.add(_iconBtn(pal, Icons.chevron_right, 'Voir la source', () => widget.onOpenSource!(b)));
    }

    return _frame(
      pal,
      header: _header(pal, right),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(alignment: Alignment.center, children: [
              CustomPaint(
                size: const Size(96, 96),
                painter: RingPainter(
                    progress: progress,
                    color: pal.primary,
                    stroke: 9,
                    trackColor: pal.track,
                    cap: StrokeCap.round),
              ),
              Text(center,
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                      color: pal.text,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (origin != null)
                Row(children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: catColor, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(origin,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: pal.text2)),
                  ),
                ]),
              const SizedBox(height: 4),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, height: 1.25, color: pal.text)),
              if (ensuite != null) ...[
                const SizedBox(height: 4),
                Text(ensuite,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: pal.text3)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: buttons),
        if (session != null) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_expanded ? 'Masquer les étapes' : 'Étapes de la session',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.text3)),
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: pal.text3),
              ]),
            ),
          ),
          if (_expanded)
            NowSessionPanel(
              logic: widget.logic,
              project: widget.focusProject,
              task: widget.focusTask,
              activity: running,
              palette: pal,
            ),
        ],
      ]),
    );
  }

  Widget _header(_Palette pal, String? right) => Row(children: [
        Container(
            width: 7, height: 7, decoration: BoxDecoration(color: pal.primary, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('MAINTENANT',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: pal.text3)),
        ),
        if (right != null)
          Text(right,
              style: TextStyle(
                  fontSize: 12, color: pal.text3, fontFeatures: const [FontFeature.tabularFigures()])),
      ]);

  Widget _frame(_Palette pal, {required Widget header, required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: pal.primary.withOpacity(.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          const SizedBox(height: 14),
          child,
        ]),
      );

  Widget _btn(_Palette pal, String label, {bool primary = false, required VoidCallback onTap}) =>
      SizedBox(
        height: 48,
        child: Material(
          color: primary ? pal.primary : pal.chip,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                        color: primary ? pal.onPrimary : pal.text)),
              ),
            ),
          ),
        ),
      );

  Widget _iconBtn(_Palette pal, IconData icon, String tooltip, VoidCallback onTap) => SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: pal.chip,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Tooltip(message: tooltip, child: Icon(icon, size: 20, color: pal.text2)),
          ),
        ),
      );
}

/// Contenu déplié pendant une session : sous-actions de la tâche focus (avec
/// leurs checklists — dernier item coché = action faite) et actions propres
/// de l'activité en cours. Ex-état 1 de `FocusView`, réduit aux checklists.
class NowSessionPanel extends StatefulWidget {
  final AppLogic logic;
  final Project? project;
  final ProjectTask? task;
  final Activity? activity;
  final _Palette palette;

  const NowSessionPanel({
    super.key,
    required this.logic,
    required this.palette,
    this.project,
    this.task,
    this.activity,
  });

  @override
  State<NowSessionPanel> createState() => _NowSessionPanelState();
}

class _NowSessionPanelState extends State<NowSessionPanel> {
  final _sync = FirestoreSync();

  Future<void> _saveTask() async {
    final p = widget.project;
    if (p == null) return;
    widget.logic.onChange();
    await _sync.saveProjectTasks(p.id, p.tasks);
  }

  Future<void> _saveOwn() async {
    final a = widget.activity;
    if (a == null) return;
    widget.logic.onChange();
    await _sync.updateOwnActions(a.id, a.ownActions);
  }

  void _toggleAction(TaskAction a, bool v, Future<void> Function() save) {
    a.done = v;
    a.doneAt = v ? DateTime.now() : null;
    if (v) {
      for (final c in a.checklist) {
        c.done = true;
        c.doneAt ??= a.doneAt;
      }
    }
    setState(() {});
    save();
  }

  void _toggleItem(TaskAction a, ChecklistItem c, bool v, Future<void> Function() save) {
    final changed = setChecklistItem(a, c.id, v);
    setState(() {});
    save();
    if (changed && a.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Action faite : ${a.title}'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.palette;
    final task = widget.task;
    final own = widget.activity?.ownActions.where((a) => !a.done).toList() ?? const [];
    if ((task == null || task.actions.isEmpty) && own.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text('Aucune étape rattachée à cette session.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: pal.text3)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (task != null && task.actions.isNotEmpty) ...[
        _label(pal, task.title),
        for (final a in task.actions)
          _actionRows(pal, a,
              onToggle: (v) => _toggleAction(a, v, _saveTask),
              onItem: (c, v) => _toggleItem(a, c, v, _saveTask)),
      ],
      if (own.isNotEmpty) ...[
        _label(pal, widget.activity!.name),
        for (final a in own)
          _actionRows(pal, a,
              onToggle: (v) => _toggleAction(a, v, _saveOwn),
              onItem: (c, v) => _toggleItem(a, c, v, _saveOwn)),
      ],
    ]);
  }

  Widget _label(_Palette pal, String text) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .8, color: pal.text4)),
      );

  Widget _actionRows(_Palette pal, TaskAction a,
      {required ValueChanged<bool> onToggle,
      required void Function(ChecklistItem, bool) onItem}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _checkRow(pal, a.title, a.done, size: 22, fontSize: 14,
          trailing: a.checklist.isEmpty ? null : '${a.checklistDone}/${a.checklistTotal}',
          onTap: () => onToggle(!a.done)),
      for (final c in a.checklist)
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: _checkRow(pal, c.title, c.done,
              size: 18, fontSize: 13, onTap: () => onItem(c, !c.done)),
        ),
    ]);
  }

  Widget _checkRow(_Palette pal, String title, bool done,
      {required double size,
      required double fontSize,
      String? trailing,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(children: [
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: size, color: done ? pal.primary : pal.text4),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: fontSize,
                    color: done ? pal.text4 : pal.text,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: pal.text4)),
          ),
          if (trailing != null)
            Text(trailing,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: pal.text3,
                    fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

/// État vide de la carte (ex-état 3 de `FocusView`) : rien en cours, plus de
/// bloc à venir — on propose les sources réelles.
class NowEmptyPanel extends StatelessWidget {
  final AppLogic logic;
  final VoidCallback? onOpenRoutines;
  final VoidCallback? onOpenActivities;
  final VoidCallback? onChallenge;

  const NowEmptyPanel({
    super.key,
    required this.logic,
    this.onOpenRoutines,
    this.onOpenActivities,
    this.onChallenge,
  });

  @override
  Widget build(BuildContext context) {
    final pal = _Palette.of(context);
    final hasChallenge = onChallenge != null && logic.challengeActivity() != null;
    return Column(children: [
      Icon(Icons.self_improvement, size: 36, color: pal.text4),
      const SizedBox(height: 10),
      Text('Rien en cours — que souhaites-tu faire ?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text)),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          if (onOpenRoutines != null)
            _chip(pal, Icons.loop, 'Mes routines', onOpenRoutines!),
          if (onOpenActivities != null)
            _chip(pal, Icons.timer_outlined, 'Mes activités', onOpenActivities!),
          if (hasChallenge)
            _chip(pal, Icons.local_fire_department_rounded, 'Défi ORION', onChallenge!),
        ],
      ),
    ]);
  }

  Widget _chip(_Palette pal, IconData icon, String label, VoidCallback onTap) => Material(
        color: pal.chip,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: pal.primary),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text)),
            ]),
          ),
        ),
      );
}

/// Couleurs de la carte : jetons du web en sombre, `ColorScheme` en clair
/// (handoff § 4 — le mode clair n'est pas supprimé).
class _Palette {
  final Color surface, primary, onPrimary, track, chip, text, text2, text3, text4;
  const _Palette({
    required this.surface,
    required this.primary,
    required this.onPrimary,
    required this.track,
    required this.chip,
    required this.text,
    required this.text2,
    required this.text3,
    required this.text4,
  });

  static _Palette of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (cs.brightness == Brightness.dark) {
      return const _Palette(
        surface: kBSurface,
        primary: kBPrimary,
        onPrimary: kBBg,
        track: kBRaised,
        chip: Color(0x12FFFFFF),
        text: kBText,
        text2: kBText2,
        text3: kBText3,
        text4: kBText4,
      );
    }
    return _Palette(
      surface: cs.surfaceContainerLow,
      primary: cs.primary,
      onPrimary: cs.onPrimary,
      track: cs.surfaceContainerHighest,
      chip: cs.surfaceContainerHighest,
      text: cs.onSurface,
      text2: cs.onSurface.withOpacity(.85),
      text3: cs.onSurface.withOpacity(.6),
      text4: cs.onSurface.withOpacity(.45),
    );
  }
}
