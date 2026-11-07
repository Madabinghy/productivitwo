import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/claude_link.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/landing.dart' show sessionTaskIdsOf;
import 'package:productivitwo_v1/utils/half_days.dart' show paceOn, minutesByActivityDay, ActivityPace;
import 'package:productivitwo_v1/utils/week_stats.dart' show weekSummary, WeekSummary;
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/utils/week_capacity.dart';
import 'package:productivitwo_v1/utils/week_planner.dart';
import 'package:productivitwo_v1/web/gantt_screen.dart';
import 'package:productivitwo_v1/web/schedule_block_dialog.dart';
import 'package:productivitwo_v1/web/column_resizer.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/web/ui_scale.dart';
import 'package:productivitwo_v1/web/views/week_task_popover.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart';

// Vue « Cette semaine » (handoff cette-semaine-2026-09) : le Gantt 7 / 14 jours
// des tâches par domaine, en pleine page, où l'on organise la semaine sans
// quitter la grille — blocs du programme dans les barres, « à caser » en
// pointillé, clic sur un jour = caser, glisser = déplacer, tirer = étendre.

const _kDayShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _kDayLong = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _kMonthLong = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];
const _kMonthShort = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
];
const _tabular = [FontFeature.tabularFigures()];
const _kLeftColDefault = 400.0;
const _kPrefLeftCol = 'week_left_col';
/// Clé du groupe « En retard » (en tête de la grille, repliable comme un domaine).
const _kLateGroup = '_late';
const _kRowH = 40.0;
const _kDomainH = 24.0;
const _kBarH = 24.0;
const _kBarTop = 8.0;
const _kPrefHideDone = 'week_hide_done';
const _kPrefCollapsed = 'week_collapsed_domains';
const _kPrefDays = 'week_window_days';
// Fenêtre affichée (début YYYY-MM-DD), restaurée seulement le jour même : un
// rechargement garde la semaine qu'on regardait, le lendemain repart d'ici.
const _kPrefStart = 'week_window_start';
const _kPrefStartSavedOn = 'week_window_saved_on';

String _fmtHm(int min) {
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String _clock(int min) => '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';

/// « mar. 7 » — jour court + numéro, pour les infobulles.
String _dm(DateTime d) => '${_kDayShort[d.weekday - 1].toLowerCase()}. ${d.day}';

Color? _hex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final s = hex.replaceFirst('#', '').replaceFirst(RegExp(r'^0[xX]'), '');
  try {
    if (s.length == 6) return Color(int.parse('FF$s', radix: 16));
    if (s.length == 8) return Color(int.parse(s, radix: 16));
  } catch (_) {}
  return null;
}

String _toHex(Color c) =>
    '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class WeekView extends StatefulWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final FirestoreSync sync;
  final void Function(Project project, {String? taskId}) onOpenProject;
  final int dayStartMin;
  /// Pour le rail (lot 2) : contrat de la semaine et Montre suisse.
  final List<Activity> activities;
  final List<StrategicObjective> objectives;

  const WeekView({
    super.key,
    required this.projects,
    required this.domains,
    required this.sync,
    required this.onOpenProject,
    this.dayStartMin = kDefaultDayStartMin,
    this.activities = const [],
    this.objectives = const [],
  });

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  int _days = 7;
  late DateTime _start; // lundi (7 j) ou jour de départ (14 j)
  final Map<String, List<ScheduleBlock>> _byDay = {};
  final List<StreamSubscription<DailySchedule?>> _subs = [];
  Map<String, int> _capacity = defaultWeekCapacity();
  DayWindow _window = kDefaultDayWindow;
  bool _hideDone = false;
  // Largeur de la colonne des tâches (réglable à la souris, persistée).
  double _leftW = _kLeftColDefault;
  final Set<String> _collapsed = {};

  // Glisser une barre (déplacer) / tirer sa poignée (étendre), en pixels.
  String? _dragTaskId;
  bool _dragResize = false;
  double _dragDx = 0;

  DateTime get _today => livedDate(DateTime.now(), widget.dayStartMin);
  List<DateTime> get _dates => windowDates(_start, _days);
  List<ScheduleBlock> get _allBlocks => [for (final l in _byDay.values) ...l];

  @override
  void initState() {
    super.initState();
    _start = weekStart(livedDate(DateTime.now(), widget.dayStartMin));
    _loadPrefs();
    _subscribe();
    _sessionsSub = widget.sync.streamSessions().listen((v) {
      if (mounted) setState(() => _sessions = v);
    });
    _hitsSub = widget.sync.streamHabitHits().listen((v) {
      if (mounted) setState(() => _hits = v);
    });
    widget.sync.fetchWeekCapacity().then((c) {
      if (mounted) setState(() => _capacity = c);
    });
    widget.sync.fetchDayWindow().then((w) {
      if (mounted) setState(() => _window = w);
    });
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      final days = p.getInt(_kPrefDays);
      setState(() {
        _hideDone = p.getBool(_kPrefHideDone) ?? false;
        _leftW = clampColumnWidth(p.getDouble(_kPrefLeftCol) ?? _kLeftColDefault);
        _collapsed
          ..clear()
          ..addAll(p.getStringList(_kPrefCollapsed) ?? const []);
        if (days == 14) {
          _days = 14;
          _start = _today;
        }
        final savedOn = p.getString(_kPrefStartSavedOn);
        final savedStart = p.getString(_kPrefStart);
        if (savedOn == ymdOf(_today) && savedStart != null) {
          final d = DateTime.tryParse(savedStart);
          if (d != null) _start = dateOnly(d);
        }
      });
      _subscribe();
    } catch (_) {}
  }

  void _setHideDone(bool v) {
    setState(() => _hideDone = v);
    _savePrefs();
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kPrefHideDone, _hideDone);
      await p.setDouble(_kPrefLeftCol, _leftW);
      await p.setStringList(_kPrefCollapsed, _collapsed.toList());
      await p.setInt(_kPrefDays, _days);
      await p.setString(_kPrefStart, ymdOf(_start));
      await p.setString(_kPrefStartSavedOn, ymdOf(_today));
    } catch (_) {}
  }

  void _subscribe() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _byDay.clear();
    for (final d in _dates) {
      final key = ymdOf(d);
      _subs.add(widget.sync.streamDailySchedule(key).listen((s) {
        if (!mounted) return;
        setState(() {
          _byDay[key] = (s?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
            ..sort((a, b) => blockStartMin(a).compareTo(blockStartMin(b)));
        });
      }));
    }
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
    _hitsSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _setWindow({int? days, DateTime? start}) {
    setState(() {
      if (days != null) _days = days;
      _start = start ?? (_days == 7 ? weekStart(_today) : _today);
    });
    _subscribe();
    _savePrefs();
  }

  void _shift(int dir) => _setWindow(start: _start.add(Duration(days: _days * dir)));

  // ── Données dérivées ────────────────────────────────────────────────────────

  List<WeekTask> get _tasks => windowTasks(
        projects: widget.projects,
        start: _start,
        days: _days,
        scheduled: _allBlocks,
        today: _today,
      );

  List<ScheduleBlock> _blocksOfTask(String taskId) =>
      [for (final e in _byDay.entries) for (final b in e.value) if (b.taskId == taskId) b];

  String? _dateOfBlock(ScheduleBlock b) {
    for (final e in _byDay.entries) {
      if (e.value.contains(b)) return e.key;
    }
    return null;
  }

  Color _taskColor(WeekTask wt) {
    final own = _hex(wt.task.color);
    if (own != null) return own;
    final phase = wt.project.phases.where((p) => p.id == wt.task.phaseId).firstOrNull;
    final ph = _hex(phase?.color);
    if (ph != null) return ph;
    return domainColor(wt.project.domainId, widget.domains) ?? kBPrimary;
  }

  /// Colonnes [s, e] de la barre dans la fenêtre, null si hors fenêtre.
  ({int s, int e})? _span(ProjectTask t) {
    final first = _dates.first, last = _dates.last;
    final start = dateOnly(t.startDate);
    final end = dateOnly(t.endDate ?? t.startDate);
    if (start.isAfter(last) || end.isBefore(first)) return null;
    final s = start.isBefore(first) ? 0 : start.difference(first).inDays;
    final e = end.isAfter(last) ? _days - 1 : end.difference(first).inDays;
    return (s: s, e: e);
  }

  int? _dayIndex(DateTime d) {
    final i = dateOnly(d).difference(_dates.first).inDays;
    return i < 0 || i >= _days ? null : i;
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _snack(String msg, {String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showClosingSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: actionLabel == null ? 2000 : 5000),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, textColor: kBPrimary, onPressed: onAction!),
      ));
  }

  /// Écriture ciblée : les champs qu'on touche ici (statut, dates, estimation),
  /// sur la tâche relue côté serveur — jamais tout le projet depuis le cache.
  Future<void> _saveTask(WeekTask wt) => widget.sync
      .patchTaskFields(wt.project.id, wt.task, const ['status', 'startDate', 'endDate', 'estimatedMin']);

  /// Estimation de la tâche posée depuis le popover (durée sélectionnée).
  Future<void> _setEstimate(WeekTask wt, int min) async {
    final t = wt.task;
    final old = t.estimatedMin;
    setState(() => t.estimatedMin = min);
    await _saveTask(wt);
    _snack('Tâche estimée ${_fmtHm(min)}', actionLabel: 'Annuler', onAction: () async {
      setState(() => t.estimatedMin = old);
      await _saveTask(wt);
    });
  }

  Future<void> _placeAt(WeekTask wt, DateTime day, int startMin, int durationMin) async {
    final key = ymdOf(day);
    final block = taskBlock(wt, startMin, durationMin: durationMin);
    setState(() => (_byDay[key] ??= []).add(block));
    await widget.sync.addScheduleBlock(key, block);
    _snack('Bloc ajouté ${_kDayLong[day.weekday - 1]} ${_clock(startMin)}',
        actionLabel: 'Retirer', onAction: () => _removeBlock(key, block));
  }

  Future<void> _removeBlock(String date, ScheduleBlock b, {bool undoable = false}) async {
    setState(() => _byDay[date]?.remove(b));
    await widget.sync.updateBlockStatus(date, b.id, 'deleted');
    if (!undoable) return;
    _snack('Bloc retiré du programme', actionLabel: 'Annuler', onAction: () async {
      setState(() => (_byDay[date] ??= []).add(b));
      await widget.sync.updateBlockStatus(date, b.id, 'pending');
    });
  }

  /// Report EFFECTIF au lendemain : copie dans le doc de demain, puis
  /// l'original passe « sauté · reporté » — même règle que le mobile (avant,
  /// le web laissait l'original en attente côté serveur).
  Future<void> _blockToTomorrow(String date, ScheduleBlock b) async {
    setState(() => _byDay[date]?.remove(b));
    final placed = await widget.sync.reportBlockToTomorrow(date, b);
    await widget.sync.updateBlockStatus(date, b.id, 'skipped');
    await widget.sync.updateBlockSkipReason(date, b.id, 'reporte');
    _snack(carryMessage([placed]));
  }

  Future<void> _toggleDone(WeekTask wt) async {
    final t = wt.task;
    final before = t.status;
    final nowDone = before != 'done';
    setState(() => t.status = nowDone ? 'done' : 'pending');
    await _saveTask(wt);
    _snack(nowDone ? 'Tâche faite' : 'Tâche rouverte', actionLabel: 'Annuler',
        onAction: () async {
      setState(() => t.status = before);
      await _saveTask(wt);
    });
  }

  Future<void> _shiftTask(WeekTask wt, int deltaDays) async {
    if (deltaDays == 0) return;
    final t = wt.task;
    final oldStart = t.startDate, oldEnd = t.endDate;
    setState(() {
      t.startDate = t.startDate.add(Duration(days: deltaDays));
      if (t.endDate != null) t.endDate = t.endDate!.add(Duration(days: deltaDays));
    });
    await _saveTask(wt);
    final n = wt.plannedBlocks;
    _snack(
      'Tâche déplacée de ${deltaDays.abs()} jour${deltaDays.abs() > 1 ? 's' : ''}'
      '${n > 0 ? ' · $n bloc${n > 1 ? 's' : ''} reste${n > 1 ? 'nt' : ''} à ${n > 1 ? 'leur' : 'sa'} date' : ''}',
      actionLabel: 'Annuler',
      onAction: () async {
        setState(() {
          t.startDate = oldStart;
          t.endDate = oldEnd;
        });
        await _saveTask(wt);
      },
    );
  }

  /// Report volontaire de l'échéance d'une tâche en retard au jour [day]
  /// (le début est avancé si besoin). Annulable.
  Future<void> _rescheduleDeadline(WeekTask wt, DateTime day) async {
    final t = wt.task;
    final oldStart = t.startDate, oldEnd = t.endDate;
    setState(() {
      t.endDate = day;
      if (dateOnly(t.startDate).isAfter(day)) t.startDate = day;
    });
    await _saveTask(wt);
    _snack('Échéance reportée au ${_kDayLong[day.weekday - 1]} ${day.day}',
        actionLabel: 'Annuler', onAction: () async {
      setState(() {
        t.startDate = oldStart;
        t.endDate = oldEnd;
      });
      await _saveTask(wt);
    });
  }

  Future<void> _resizeTask(WeekTask wt, int deltaDays) async {
    if (deltaDays == 0) return;
    final t = wt.task;
    final oldEnd = t.endDate;
    final base = dateOnly(t.endDate ?? t.startDate);
    var end = base.add(Duration(days: deltaDays));
    if (end.isBefore(dateOnly(t.startDate))) end = dateOnly(t.startDate);
    setState(() => t.endDate = end);
    await _saveTask(wt);
    _snack('Échéance : ${_kDayLong[end.weekday - 1]} ${end.day}', actionLabel: 'Annuler',
        onAction: () async {
      setState(() => t.endDate = oldEnd);
      await _saveTask(wt);
    });
  }

  Future<void> _pickColor(WeekTask wt) async {
    final picked = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Couleur de la barre'),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in kColorPickerOptions)
              InkWell(
                onTap: () => Navigator.pop(ctx, _toHex(c)),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _hex(wt.task.color) == c ? Colors.white : Colors.transparent, width: 2),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Couleur du domaine (par défaut)')),
        ],
      ),
    );
    if (picked == null) return;
    final oldColor = wt.task.color;
    setState(() => wt.task.color = picked.isEmpty ? null : picked);
    await _saveTask(wt);
    _snack(picked.isEmpty ? 'Couleur du domaine rétablie' : 'Couleur de la barre modifiée',
        actionLabel: 'Annuler', onAction: () async {
      setState(() => wt.task.color = oldColor);
      await _saveTask(wt);
    });
  }

  void _openTask(WeekTask wt) => showGanttTaskDetailDialog(context,
      project: wt.project,
      task: wt.task,
      sync: widget.sync,
      onProjectUpdated: (_) => setState(() {}));

  void _openPopover(WeekTask wt, int dayIdx, Offset global) {
    final day = _dates[dayIdx];
    if (day.isBefore(_today)) {
      _snack('${_kDayLong[day.weekday - 1]} est passé — choisis un jour à venir.');
      return;
    }
    final dur = remainingToPlaceMin(wt.task, _allBlocks);
    final duration = dur == 0 ? wt.task.plannedMin : dur;
    final now = DateTime.now();
    showWeekTaskPopover(
      context,
      anchor: overlayLocal(context, global),
      title: wt.task.title,
      initialDay: day,
      propose: (dd, d) => proposedSlot(_byDay[ymdOf(dd)] ?? const [], d, window: _window,
          isToday: dd == _today, nowMin: now.hour * 60 + now.minute),
      load: (dd, d) =>
          dayLoad(dd, _byDay[ymdOf(dd)] ?? const [], _capacity, d, today: _today, window: _window),
      firstFitting: (d) => firstFittingDay(
          _dates.where((x) => !x.isBefore(_today)).toList(), _byDay, _capacity, d,
          today: _today, window: _window),
      durationMin: duration,
      estimatedMin: wt.task.estimatedMin,
      onEstimate: (m) => _setEstimate(wt, m),
      taskDone: wt.done,
      onPlace: (dd, startMin, d) => _placeAt(wt, dd, startMin, d),
      onOpen: () => _openTask(wt),
      onOpenProject: () => widget.onOpenProject(wt.project, taskId: wt.task.id),
      onDone: () => _toggleDone(wt),
      onRescheduleDeadline:
          wt.overdue && !wt.done ? (dd) => _rescheduleDeadline(wt, dd) : null,
    );
  }

  Future<void> _openDotMenu(ScheduleBlock b, Offset global) async {
    final date = _dateOfBlock(b);
    if (date == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlayLocal(context, global);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(local & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
            enabled: false,
            child: Text('${b.startTime} · ${_fmtHm(b.durationMin)}',
                style: const TextStyle(fontWeight: FontWeight.w600))),
        const PopupMenuItem(value: 'tomorrow', child: Text('Déplacer à demain')),
        const PopupMenuItem(value: 'remove', child: Text('Retirer du programme')),
      ],
    );
    if (choice == 'tomorrow') await _blockToTomorrow(date, b);
    if (choice == 'remove') await _removeBlock(date, b, undoable: true);
  }

  Future<void> _editCapacity() async {
    final result = await showDialog<({Map<String, int> capacity, DayWindow window})>(
      context: context,
      builder: (_) => _CapacityDialog(capacity: _capacity, window: _window),
    );
    if (result == null) return;
    final windowChanged = result.window != _window;
    setState(() {
      _capacity = result.capacity;
      _window = result.window;
    });
    await widget.sync.saveWeekCapacity(result.capacity);
    if (windowChanged) await widget.sync.saveDayWindow(result.window);
  }

  /// « Planifier la semaine avec Claude » : ouvre LE Claude de l'utilisateur
  /// avec la demande écrite (plan_week sur la fenêtre affichée, retards,
  /// capacité). Il valide dans la conversation ; rien ne passe par ORION.
  Future<void> _planWithClaude() async {
    final overdue = [
      for (final wt in _tasks)
        if (wt.overdue && !wt.done)
          (task: wt.task.title, project: wt.project.title, due: wt.due),
    ]..sort((a, b) => a.due.compareTo(b.due));
    final prompt = planWeekPrompt(
        start: _start, days: _days, overdue: overdue.take(8).toList(), capacityMin: _capacity);
    final ok = await launchUrl(claudeNewUri(prompt), mode: LaunchMode.externalApplication);
    if (!ok) _snack('Impossible d\'ouvrir Claude dans le navigateur.');
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    final active = tasks.where((t) => !t.task.isMilestone).toList();
    final done = active.where((t) => t.done).length;
    // Les compteurs suivent le filtre « Masquer le fait » : en retard et à
    // caser ne concernent que des tâches ouvertes, donc inchangés.
    final late = tasks.where((t) => t.overdue && !t.done).length;
    final toPlace = tasksToPlace(tasks).where((t) => !t.task.isMilestone).length;

    return Container(
      color: kBBg,
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pageHeader(active: active.length, done: done, late: late, toPlace: toPlace),
        const SizedBox(height: 14),
        _dayStrip(),
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _ganttCard(tasks)),
            if (_openDay != null) ...[
              const SizedBox(width: 20),
              SizedBox(width: 400, child: _dayPanel(_openDay!)),
            ] else if (_railKey != null) ...[
              const SizedBox(width: 20),
              SizedBox(width: 380, child: _railPanel(_railKey!)),
            ],
            const SizedBox(width: 16),
            _rail(),
          ]),
        ),
      ]),
    );
  }

  // ── La semaine en jours (2026-11-07, maquette « Cette semaine, remis en ordre », lot 1) ──
  // Une colonne par jour : charge sur capacité, ce qui a été fait, les blocs
  // principaux (rendez-vous et séances entourés d'or). Tap = le jour en entier.

  /// Jour ouvert dans le panneau de droite, null = fermé.
  DateTime? _openDay;

  /// Blocs visibles d'un jour (ni supprimés, ni déplacés / sautés hors lâchés), par heure.
  List<ScheduleBlock> _dayBlocks(DateTime d, {bool withAside = false}) {
    final list = [
      for (final b in _byDay[ymdOf(d)] ?? const <ScheduleBlock>[])
        if (b.status != 'deleted' && (withAside || b.status != 'skipped' || isLetGoBlock(b))) b,
    ]..sort((a, b) => a.startTime.compareTo(b.startTime));
    return list;
  }

  bool _isDated(ScheduleBlock b, Set<String> sessionIds) =>
      b.gcalEventId != null || (b.taskId != null && sessionIds.contains(b.taskId));

  Widget _dayStrip() {
    final sessionIds = sessionTaskIdsOf(widget.projects);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < _dates.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: _dayCard(_dates[i], sessionIds)),
      ],
    ]);
  }

  Widget _dayCard(DateTime d, Set<String> sessionIds) {
    final blocks = _dayBlocks(d);
    final isToday = d == _today;
    final past = d.isBefore(_today);
    final open = _openDay == d;
    final cap = capacityMinFor(_capacity, d);
    final planned = plannedMin(blocks, window: _window);
    final counted = blocks.where((b) => b.gcalEventId == null).toList();
    final doneN = counted.where((b) => b.status == 'done').length;
    final v = cap == 0 ? 0.0 : (planned / cap).clamp(0.0, 1.0);
    final behind = past && counted.isNotEmpty && doneN < counted.length;
    final right = isToday
        ? 'aujourd’hui'
        : blocks.isEmpty
            ? (past ? 'rien' : 'pas posé')
            : (past || counted.isEmpty ? '$doneN / ${counted.length} faits' : '${blocks.length} bloc${blocks.length > 1 ? 's' : ''}');
    // Les blocs à montrer : les datés d'abord, puis les plus longs.
    final shown = [...blocks]..sort((a, b) {
        final da = _isDated(a, sessionIds) ? 0 : 1, db = _isDated(b, sessionIds) ? 0 : 1;
        if (da != db) return da - db;
        return b.durationMin.compareTo(a.durationMin);
      });
    final top = shown.take(2).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
    final more = blocks.length - top.length;
    return Tooltip(
      message: '${_kDayLong[d.weekday - 1]} ${d.day} · ${_fmtHm(planned)} posées sur ${_fmtHm(cap)}',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        key: ValueKey('week-day-${ymdOf(d)}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() {
          _openDay = open ? null : d;
          _railKey = null;
        }),
        child: Opacity(
          opacity: past && !open ? .72 : 1,
          child: Container(
            height: 128,
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
            decoration: BoxDecoration(
              color: isToday || open ? const Color(0xFF10201A) : kBSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: open || isToday ? kBPrimary : kBLine, width: open || isToday ? 1.5 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('${_kDayShort[d.weekday - 1]} ${d.day}',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: isToday ? kBPrimary : kBText, fontFeatures: _tabular)),
                const Spacer(),
                Flexible(
                  child: Text(right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: isToday ? kBPrimary : (behind ? kBAttention : kBText3), fontFeatures: _tabular)),
                ),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 4,
                  child: Stack(children: [
                    Container(color: const Color(0x14FFFFFF)),
                    FractionallySizedBox(
                        widthFactor: v, child: Container(color: v >= 1 ? kBAlert : (behind ? kBAttention : kBPrimary))),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              Text(cap == 0 ? (blocks.isEmpty ? 'repos' : 'repos · ${_fmtHm(planned)}') : '${_fmtHm(planned)} / ${_fmtHm(cap)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: kBText4, fontFeatures: _tabular)),
              const SizedBox(height: 6),
              for (final b in top) ...[_blockChip(b, _isDated(b, sessionIds)), const SizedBox(height: 4)],
              if (more > 0)
                Text('+$more bloc${more > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11, color: kBText4))
              else if (blocks.isEmpty && !past)
                const Text('+ Poser la journée', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kBPrimary)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _blockChip(ScheduleBlock b, bool dated) {
    final done = b.status == 'done';
    final letGo = isLetGoBlock(b);
    final label = dated ? '${b.startTime} ${b.title}' : b.title;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: dated ? Colors.transparent : const Color(0x12FFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: dated ? Border.all(color: kBAttention) : null,
      ),
      child: Text('${done ? '✓ ' : letGo ? '✋ ' : ''}$label',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: dated ? kBAttention : (done ? kBText3 : kBText2))),
    );
  }

  String _blockState(ScheduleBlock b, DateTime d) {
    if (b.status == 'done') return 'fait';
    if (isLetGoBlock(b)) return 'lâché';
    if (b.status == 'skipped') {
      if (b.skipReason == kSkipUnavailable) return 'empêché';
      return b.movedTo != null ? 'déplacé' : 'sauté';
    }
    if (d.isBefore(_today)) return b.gcalEventId != null ? 'agenda' : 'pas fait';
    return b.gcalEventId != null ? 'agenda' : 'à faire';
  }

  /// Le panneau d'un jour : son programme, ce qui a avancé, ‹ › jours voisins.
  Widget _dayPanel(DateTime d) {
    final sessionIds = sessionTaskIdsOf(widget.projects);
    final blocks = _dayBlocks(d, withAside: true);
    final live = _dayBlocks(d);
    final cap = capacityMinFor(_capacity, d);
    final planned = plannedMin(live, window: _window);
    final counted = live.where((b) => b.gcalEventId == null).toList();
    final doneN = counted.where((b) => b.status == 'done').length;
    final past = d.isBefore(_today);
    final idx = _dayIndex(d);
    // Actions cochées ce jour-là, par tâche.
    final advanced = <String, int>{};
    for (final p in widget.projects) {
      for (final t in p.tasks) {
        for (final a in t.actions) {
          final at = a.doneAt;
          if (a.done && at != null && dateOnly(at) == d) {
            final k = '${p.title} — ${t.title}';
            advanced[k] = (advanced[k] ?? 0) + 1;
          }
        }
      }
    }
    final v = cap == 0 ? 0.0 : (planned / cap).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      decoration: BoxDecoration(
        color: kBSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3A5A4A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${_kDayLong[d.weekday - 1][0].toUpperCase()}${_kDayLong[d.weekday - 1].substring(1)} ${d.day} ${_kMonthLong[d.month - 1]}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kBText)),
          ),
          IconButton(
            key: const ValueKey('week-day-close'),
            tooltip: 'Fermer',
            icon: const Icon(Icons.close, size: 18, color: kBText3),
            onPressed: () => setState(() => _openDay = null),
          ),
        ]),
        Text(
            '${_fmtHm(planned)} posées sur ${_fmtHm(cap)}'
            '${counted.isEmpty ? '' : ' · $doneN bloc${doneN > 1 ? 's' : ''} fait${doneN > 1 ? 's' : ''} sur ${counted.length}'}',
            style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 6,
            child: Stack(children: [
              Container(color: const Color(0x14FFFFFF)),
              FractionallySizedBox(widthFactor: v, child: Container(color: v >= 1 ? kBAlert : kBPrimary)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(children: [
            const Text('LE PROGRAMME',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
            const SizedBox(height: 4),
            if (blocks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(past ? 'Rien n’était posé ce jour-là.' : 'Rien de posé pour l’instant.',
                    style: const TextStyle(fontSize: 13, color: kBText3)),
              ),
            for (final b in blocks) _dayRow(b, d, _isDated(b, sessionIds)),
            if (!past) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _textLink('+ Ajouter un bloc', () => _addBlockOn(d)),
              ),
            ],
            if (advanced.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('CE QUI A AVANCÉ',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
              const SizedBox(height: 4),
              for (final e in advanced.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text('${e.key} · ${e.value} action${e.value > 1 ? 's' : ''} cochée${e.value > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 13, color: kBText2)),
                ),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (idx != null && idx > 0) _pillButton('‹ ${_kDayShort[_dates[idx - 1].weekday - 1].toLowerCase()}.', onTap: () => setState(() => _openDay = _dates[idx - 1])),
          const SizedBox(width: 8),
          if (idx != null && idx < _days - 1) _pillButton('${_kDayShort[_dates[idx + 1].weekday - 1].toLowerCase()}. ›', onTap: () => setState(() => _openDay = _dates[idx + 1])),
          const Spacer(),
          if (!past) _pillButton('Préparer avec Claude', icon: Icons.auto_awesome, onTap: () => _prepareDay(d)),
        ]),
      ]),
    );
  }

  Widget _dayRow(ScheduleBlock b, DateTime d, bool dated) {
    final state = _blockState(b, d);
    final color = switch (state) {
      'fait' => kBPrimary,
      'lâché' || 'pas fait' => const Color(0xFFFF8F86),
      'agenda' => kBAttention,
      _ => kBText3,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBLine))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 46,
          child: Text(b.startTime, style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.title.isEmpty ? 'Bloc' : b.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: dated ? kBAttention : kBText,
                    decoration: b.status == 'skipped' && !isLetGoBlock(b) ? TextDecoration.lineThrough : null)),
            Text('$state · ${_fmtHm(b.durationMin)}', style: TextStyle(fontSize: 12, color: color)),
          ]),
        ),
      ]),
    );
  }

  Future<void> _addBlockOn(DateTime d) async {
    final created = await showScheduleBlockDialog(context,
        isNew: true, block: ScheduleBlock(startTime: '09:00', durationMin: 60, title: ''));
    if (created == null || !mounted) return;
    await widget.sync.upsertScheduleBlock(ymdOf(d), created);
  }

  Future<void> _prepareDay(DateTime d) async {
    final ok = await launchUrl(claudeNewUri(planDayPrompt(date: ymdOf(d), blocks: _dayBlocks(d))),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('Impossible d’ouvrir Claude');
  }

  // ── Rail (2026-11-07, lot 2) : Contrat · Montre suisse · Dates · Capacité ──

  StreamSubscription<List<Session>>? _sessionsSub;
  StreamSubscription<List<HabitHit>>? _hitsSub;
  List<Session> _sessions = [];
  List<HabitHit> _hits = [];
  String? _railKey;

  static const _kRail = [
    (key: 'contract', label: 'Contrat', icon: Icons.handshake_outlined),
    (key: 'watch', label: 'Montre', icon: Icons.watch_outlined),
    (key: 'dates', label: 'Dates', icon: Icons.event_outlined),
  ];

  bool get _isCurrentWeek => _days == 7 && _start == weekStart(_today);

  // Recalculés au plus une fois par minute ou quand une donnée change (le
  // glisser d'une barre redessine à chaque pixel).
  String _railMemoKey = '';
  WeekSummary? _contractMemo;
  List<ActivityPace> _watchMemo = const [];

  void _refreshRail() {
    final now = DateTime.now();
    final key = '${now.hour}:${now.minute}|${_sessions.length}|${_hits.length}|'
        '${identityHashCode(widget.activities)}|${identityHashCode(widget.objectives)}';
    if (key == _railMemoKey && _contractMemo != null) return;
    _railMemoKey = key;
    _contractMemo = weekSummary(
      activities: widget.activities.where((a) => !a.deleted).toList(),
      hits: _hits,
      sessions: _sessions,
      objectives: widget.objectives.where((o) => o.status == 'active'),
      now: now,
    );
    _watchMemo = paceOn(_today, activities: widget.activities, minutes: minutesByActivityDay(_sessions, now));
  }

  WeekSummary _contract() {
    _refreshRail();
    return _contractMemo!;
  }

  List<ActivityPace> _watch() {
    _refreshRail();
    return [..._watchMemo];
  }

  /// Ce qui ne bouge pas dans la fenêtre : rendez-vous d'agenda, séances, échéances de tâches ouvertes.
  List<({DateTime day, String time, String title, String kind})> _datedItems() {
    final sessionIds = sessionTaskIdsOf(widget.projects);
    final out = <({DateTime day, String time, String title, String kind})>[];
    for (final d in _dates) {
      for (final b in _dayBlocks(d)) {
        if (!_isDated(b, sessionIds)) continue;
        out.add((day: d, time: b.startTime, title: b.title, kind: b.gcalEventId != null ? 'agenda' : 'séance'));
      }
    }
    final first = _dates.first, last = _dates.last;
    for (final p in widget.projects) {
      if (p.status == 'archived' || p.status == 'done') continue;
      for (final t in p.tasks) {
        final e = t.endDate;
        if (e == null || t.status == 'done' || t.status == 'skipped') continue;
        final day = dateOnly(e);
        if (day.isBefore(first) || day.isAfter(last)) continue;
        out.add((day: day, time: '', title: '${t.title} · ${p.title}', kind: t.isMilestone ? 'jalon' : 'échéance'));
      }
    }
    out.sort((a, b) {
      final c = a.day.compareTo(b.day);
      return c != 0 ? c : a.time.compareTo(b.time);
    });
    return out;
  }

  ({String text, Color color})? _railBadge(String key) {
    switch (key) {
      case 'contract':
        if (!_isCurrentWeek) return null;
        final c = _contract();
        final behind = c.engagements.length - c.kept;
        return behind <= 0 ? null : (text: '$behind', color: kBAttention);
      case 'watch':
        final late = _watch().where((p) => !p.onPace).length;
        return late == 0 ? null : (text: '$late', color: kBAttention);
      case 'dates':
        final n = _datedItems().where((x) => !x.day.isBefore(_today)).length;
        return n == 0 ? null : (text: '$n', color: kBAttention);
    }
    return null;
  }

  Widget _rail() => Column(children: [
        for (final r in _kRail) ...[
          _railButton(r.label, r.icon, on: _railKey == r.key, badge: _railBadge(r.key), onTap: () {
            setState(() {
              _railKey = _railKey == r.key ? null : r.key;
              _openDay = null;
            });
          }, key: ValueKey('week-rail-${r.key}')),
          const SizedBox(height: 8),
        ],
        _railButton('Capacité', Icons.tune_outlined, on: false, onTap: _editCapacity, key: const ValueKey('week-rail-capacity')),
      ]);

  Widget _railButton(String label, IconData icon,
      {required bool on, ({String text, Color color})? badge, required VoidCallback onTap, Key? key}) {
    return Tooltip(
      message: label,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 60,
          height: 58,
          decoration: BoxDecoration(
            color: on ? const Color(0xFF1C3A2C) : kBSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? kBPrimary : kBLine, width: on ? 1.5 : 1),
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 19, color: on ? kBText : kBText2),
                const SizedBox(height: 4),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: on ? kBText : kBText2)),
              ]),
            ),
            if (badge != null)
              Positioned(
                top: 4,
                right: 5,
                child: Text(badge.text,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: badge.color, fontFeatures: _tabular)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _railPanel(String key) {
    final title = _kRail.firstWhere((r) => r.key == key).label;
    final List<Widget> body = switch (key) {
      'contract' => _contractBody(),
      'watch' => _watchBody(),
      _ => _datesBody(),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      decoration: BoxDecoration(
        color: kBSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3A5A4A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(key == 'watch' ? 'Montre suisse' : title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kBText))),
          IconButton(
            key: const ValueKey('week-rail-close'),
            tooltip: 'Fermer',
            icon: const Icon(Icons.close, size: 18, color: kBText3),
            onPressed: () => setState(() => _railKey = null),
          ),
        ]),
        Expanded(child: ListView(children: body)),
      ]),
    );
  }

  Widget _meter(String name, String value, double ratio, Color color, {String? sub}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBLine))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kBText)),
            ),
            Text(value, style: TextStyle(fontSize: 12.5, color: color, fontFeatures: _tabular)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 5,
              child: Stack(children: [
                Container(color: const Color(0x14FFFFFF)),
                FractionallySizedBox(widthFactor: ratio.clamp(0.0, 1.0), child: Container(color: color)),
              ]),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(fontSize: 11.5, color: kBText3)),
          ],
        ]),
      );

  List<Widget> _contractBody() {
    if (!_isCurrentWeek) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Le contrat se lit sur la semaine en cours.', style: TextStyle(fontSize: 13, color: kBText3)),
        ),
      ];
    }
    final c = _contract();
    if (c.engagements.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Aucun engagement de routine cette semaine.', style: TextStyle(fontSize: 13, color: kBText3)),
        ),
      ];
    }
    return [
      Text('${c.kept} / ${c.engagements.length} au rythme · attendu à ce jour',
          style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular)),
      Text(c.fromObjectives ? 'les routines de tes objectifs en cours' : 'toutes tes routines',
          style: const TextStyle(fontSize: 12, color: kBText4)),
      const SizedBox(height: 8),
      for (final e in c.engagements)
        _meter(
          e.label,
          '${e.done} / ${e.target}',
          e.target == 0 ? 1 : e.done / e.target,
          c.onTrack(e) ? kBPrimary : kBAttention,
          sub: c.onTrack(e) ? null : 'en retard sur le rythme du jour',
        ),
    ];
  }

  List<Widget> _watchBody() {
    final list = _watch()..sort((a, b) => b.missingMin.compareTo(a.missingMin));
    if (list.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Aucune activité avec un minimum.', style: TextStyle(fontSize: 13, color: kBText3)),
        ),
      ];
    }
    final ok = list.where((p) => p.onPace).length;
    return [
      Text('$ok / ${list.length} couvertes sur les 7 derniers jours',
          style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular)),
      const SizedBox(height: 8),
      for (final p in list)
        _meter(
          p.activity.name,
          '${_fmtHm(p.doneMin)} / ${_fmtHm(p.expectedMin)}',
          p.expectedMin == 0 ? 1 : p.doneMin / p.expectedMin,
          p.onPace ? kBPrimary : kBAttention,
          sub: p.onPace ? '✓ couverte' : 'reste ${_fmtHm(p.missingMin)} · aujourd’hui ${_fmtHm(p.todayMin)}',
        ),
    ];
  }

  List<Widget> _datesBody() {
    final items = _datedItems();
    if (items.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Rien de daté sur cette période.', style: TextStyle(fontSize: 13, color: kBText3)),
        ),
      ];
    }
    final out = <Widget>[];
    DateTime? cur;
    for (final x in items) {
      if (x.day != cur) {
        cur = x.day;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text('${_kDayLong[x.day.weekday - 1].toUpperCase()} ${x.day.day}',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: x.day == _today ? kBPrimary : kBText3)),
        ));
      }
      final past = x.day.isBefore(_today);
      out.add(Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBLine))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 46,
              child: Text(x.time, style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: past ? kBText3 : kBText)),
              Text(x.kind, style: TextStyle(fontSize: 11.5, color: x.kind == 'échéance' || x.kind == 'jalon' ? kBAlert : kBAttention)),
            ]),
          ),
        ]),
      ));
    }
    return out;
  }

  Widget _pageHeader({required int active, required int done, required int late, required int toPlace}) {
    final title = _days == 7
        ? 'Semaine du ${_start.day} ${_kMonthLong[_start.month - 1]}'
        : '14 jours à partir du ${_start.day} ${_kMonthShort[_start.month - 1]}';
    final isCurrent = _days == 7 ? _start == weekStart(_today) : _start == _today;
    final planned = [for (final d in _dates) plannedMin(_dayBlocks(d), window: _window)].fold<int>(0, (a, b) => a + b);
    final cap = [for (final d in _dates) capacityMinFor(_capacity, d)].fold<int>(0, (a, b) => a + b);
    final sessionIds = sessionTaskIdsOf(widget.projects);
    final dated = [for (final d in _dates) ..._dayBlocks(d).where((b) => _isDated(b, sessionIds))].length;
    final contract = _isCurrentWeek ? _contract() : null;
    final summary = [
      '${_fmtHm(planned)} posées sur ${_fmtHm(cap)}',
      if (dated > 0) '$dated rendez-vous et séance${dated > 1 ? 's' : ''}',
      if (late > 0) '$late tâche${late > 1 ? 's' : ''} en retard',
      if (toPlace > 0) '$toPlace à caser',
      if (contract != null && contract.engagements.isNotEmpty)
        'contrat ${contract.kept} / ${contract.engagements.length} au rythme',
    ].join(' · ');
    final titleBlock = Row(children: [
      _iconBtn(Icons.chevron_left, _days == 7 ? 'Semaine précédente' : '14 jours avant', () => _shift(-1)),
      _iconBtn(Icons.chevron_right, _days == 7 ? 'Semaine suivante' : '14 jours après', () => _shift(1)),
      const SizedBox(width: 6),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600, color: kBText, letterSpacing: -.2)),
            ),
            if (!isCurrent) ...[
              const SizedBox(width: 8),
              _textLink(_days == 7 ? 'Cette semaine' : "Aujourd'hui", () => _setWindow()),
            ],
          ]),
          const SizedBox(height: 2),
          Text(summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular)),
        ]),
      ),
    ]);
    final controls = <Widget>[
      _segmented(),
      _pillButton('Planifier avec Claude', primary: true, icon: Icons.auto_awesome, onTap: _planWithClaude),
    ];
    // Sous ~1100 px, les commandes passent sous le titre au lieu de l'écraser.
    return LayoutBuilder(builder: (ctx, box) {
      if (box.maxWidth < 1100) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          titleBlock,
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: controls),
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 12),
        for (final c in controls) ...[c, const SizedBox(width: 8)],
      ]);
    });
  }

  Widget _segmented() {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0x12FFFFFF), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (n, lbl) in const [(7, '7 jours'), (14, '14 jours')])
          InkWell(
            onTap: () => _setWindow(days: n),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _days == n ? kBActive : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _days == n ? kBPrimary.withOpacity(.35) : Colors.transparent),
              ),
              child: Text(lbl,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _days == n ? kBText : kBText2)),
            ),
          ),
      ]),
    );
  }

  // ── Carte Gantt ─────────────────────────────────────────────────────────────

  Widget _ganttCard(List<WeekTask> tasks) {
    // Groupes par domaine (ordre des domaines, puis sans domaine), tâches par
    // date de début.
    // Les tâches en retard sortent de leur domaine pour un groupe « En
    // retard » en tête, trié par échéance (lot 3 de l'audit).
    final byDomain = <String?, List<WeekTask>>{};
    for (final t in tasks) {
      if (_hideDone && t.done) continue;
      final key = t.overdue && !t.done ? _kLateGroup : t.project.domainId;
      byDomain.putIfAbsent(key, () => []).add(t);
    }
    for (final e in byDomain.entries) {
      e.value.sort((a, b) {
        final c = e.key == _kLateGroup
            ? a.due.compareTo(b.due)
            : a.task.startDate.compareTo(b.task.startDate);
        return c != 0 ? c : a.task.title.compareTo(b.task.title);
      });
    }
    final order = <String?>[
      if (byDomain.containsKey(_kLateGroup)) _kLateGroup,
      for (final d in widget.domains)
        if (byDomain.containsKey(d.id)) d.id,
      for (final k in byDomain.keys)
        if (k != null && k != _kLateGroup && !widget.domains.any((d) => d.id == k)) k,
      if (byDomain.containsKey(null)) null,
    ];

    return Container(
      decoration: BoxDecoration(
        color: kBSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _dayHeaderRow(),
        const Divider(height: 1, color: kBLine),
        Expanded(
          child: tasks.isEmpty
              ? const Center(
                  child: Text('Aucune tâche sur cette période.',
                      style: TextStyle(fontSize: 13, color: kBText3)))
              : order.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Tout est fait sur cette période.',
                        style: TextStyle(fontSize: 13, color: kBText3)),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: () => _setHideDone(false),
                        child: const Text('Afficher le fait')),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final did in order) ...[
                      _domainHeader(did, byDomain[did]!),
                      if (!_collapsed.contains(did ?? '_none'))
                        for (final wt in byDomain[did]!) _taskRow(wt),
                    ],
                  ],
                ),
        ),
        const Divider(height: 1, color: kBLine),
        _legend(),
        ]),
        ColumnResizeHandle(
          left: _leftW,
          onDrag: (dx) => setState(() => _leftW = clampColumnWidth(_leftW + dx)),
          onEnd: _savePrefs,
          onReset: () {
            setState(() => _leftW = _kLeftColDefault);
            _savePrefs();
          },
        ),
      ]),
    );
  }

  Widget _dayHeaderRow() {
    return SizedBox(
      height: 36,
      child: Row(children: [
        SizedBox(
          width: _leftW,
          child: Padding(
            padding: const EdgeInsets.only(left: 18, right: 8),
            child: Row(children: [
              const Expanded(
                child: Text('LES TÂCHES DE LA SEMAINE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
              ),
              Tooltip(
                message: _hideDone ? 'Afficher les tâches faites' : 'Masquer les tâches faites',
                child: InkWell(
                  key: const ValueKey('week-hide-done'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _setHideDone(!_hideDone),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_hideDone ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 14, color: kBText3),
                      const SizedBox(width: 4),
                      Text(_hideDone ? 'fait masqué' : 'fait visible',
                          style: const TextStyle(fontSize: 11.5, color: kBText3)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
        for (final d in _dates) Expanded(child: _dayHeader(d)),
      ]),
    );
  }

  /// En-tête de colonne du Gantt : le jour seul (la charge vit dans LA SEMAINE).
  Widget _dayHeader(DateTime d) {
    final isToday = d == _today;
    final weekend = d.weekday >= 6;
    return Container(
      color: isToday ? kBPrimary.withOpacity(.10) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Text('${_kDayShort[d.weekday - 1]} ${d.day}',
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isToday ? kBPrimary : (weekend ? kBText4 : kBText2),
              fontFeatures: _tabular)),
    );
  }

  Widget _domainHeader(String? domainId, List<WeekTask> tasks) {
    final late = domainId == _kLateGroup;
    final d = late ? null : widget.domains.where((x) => x.id == domainId).firstOrNull;
    final color = late ? kBAlert : (domainColor(domainId, widget.domains) ?? kBText4);
    final key = domainId ?? '_none';
    final collapsed = _collapsed.contains(key);
    final real = tasks.where((t) => !t.task.isMilestone).toList();
    final done = real.where((t) => t.done).length;
    var planned = 0;
    for (final t in tasks) {
      planned += plannedMinForTask(t.task, _allBlocks);
    }
    final oldest = late && tasks.isNotEmpty
        ? tasks.first.due
        : null;
    final name = late ? 'En retard' : (d?.name ?? 'Sans domaine');
    final meta = late
        ? ' · ${tasks.length} tâche${tasks.length > 1 ? 's' : ''}'
            '${oldest != null ? ' · la plus ancienne : ${_dm(oldest)}' : ''}'
            '${planned > 0 ? ' · ${_fmtHm(planned)} planifiées' : ''}'
        : ' · $done / ${real.length} faite${done > 1 ? 's' : ''}'
            '${planned > 0 ? ' · ${_fmtHm(planned)} planifiées' : ''}';
    return InkWell(
      onTap: () {
        setState(() => collapsed ? _collapsed.remove(key) : _collapsed.add(key));
        _savePrefs();
      },
      child: Container(
        height: _kDomainH,
        color: color.withOpacity(.10),
        padding: const EdgeInsets.only(left: 18),
        child: Row(children: [
          Icon(collapsed ? Icons.chevron_right : Icons.expand_more, size: 15, color: kBText3),
          const SizedBox(width: 6),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(name.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: color)),
          const SizedBox(width: 6),
          Text(meta, style: const TextStyle(fontSize: 11, color: kBText3, fontFeatures: _tabular)),
        ]),
      ),
    );
  }

  Widget _taskRow(WeekTask wt) {
    final t = wt.task;
    final color = _taskColor(wt);
    final blocks = _blocksOfTask(t.id);
    final remaining = remainingToPlaceMin(t, _allBlocks);
    final openActions = t.actions.where((a) => !a.done).length;
    final overdueDays = wt.overdue ? _today.difference(wt.due).inDays : 0;

    return SizedBox(
      height: _kRowH,
      child: Row(children: [
        SizedBox(
          width: _leftW,
          child: Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
            child: Row(children: [
              if (wt.done) ...[
                const Icon(Icons.check_circle, size: 15, color: kBPrimaryDark),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Tooltip(
                  message: wt.project.title,
                  waitDuration: const Duration(milliseconds: 600),
                  child: InkWell(
                    onTap: () => _openTask(wt),
                    child: Text(t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.15,
                            fontWeight: FontWeight.w500,
                            color: wt.done ? kBText3 : kBText,
                            decoration: wt.done ? TextDecoration.lineThrough : null,
                            decorationColor: kBText3)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Marqueur (jalon / retard / actions) + dates et estimation en
              // clair : « 3 j · 2 h » (≈ = estimation par défaut, non saisie).
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                if (t.isMilestone)
                  _badge('jalon', kBAttention)
                else if (wt.overdue && !wt.done)
                  _badge('−$overdueDays j', kBAlert)
                else if (t.actions.isNotEmpty)
                  Text('${t.actions.length - openActions}/${t.actions.length}',
                      style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
                const SizedBox(height: 2),
                // « ⚑ 2 » = actions à échéance propre dans la fenêtre.
                Text('${_taskMeta(t)}${wt.actionsDueInWindow > 0 && !wt.done ? ' · ⚑ ${wt.actionsDueInWindow}' : ''}',
                    style: const TextStyle(fontSize: 10.5, color: kBText4, fontFeatures: _tabular)),
              ]),
            ]),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (ctx, box) {
            final colW = box.maxWidth / _days;
            return Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(
                    days: _days,
                    todayIdx: _dayIndex(_today),
                    weekend: [for (var i = 0; i < _days; i++) _dates[i].weekday >= 6],
                  ),
                ),
              ),
              // Cellules : clic = popover « caser » ; « + » au survol.
              Positioned.fill(
                child: Row(children: [
                  for (var i = 0; i < _days; i++) Expanded(child: _cell(wt, i)),
                ]),
              ),
              if (t.isMilestone)
                ..._milestone(wt, colW)
              else if (blocks.isEmpty && !wt.done)
                _toPlaceBar(wt, colW, color, remaining)
              else
                ..._bar(wt, colW, color, blocks, remaining),
            ]);
          }),
        ),
      ]),
    );
  }

  /// « 3 j · 2 h » : étendue en jours, puis estimation (≈ = défaut 45 min,
  /// non saisie) ; un jalon n'a qu'une date.
  String _taskMeta(ProjectTask t) {
    final end = dateOnly(t.endDate ?? t.startDate);
    if (t.isMilestone) return _dm(end);
    final days = end.difference(dateOnly(t.startDate)).inDays + 1;
    final est = t.estimatedMin == null ? '≈${_fmtHm(t.plannedMin)}' : _fmtHm(t.plannedMin);
    return '$days j · $est';
  }

  Widget _cell(WeekTask wt, int i) {
    final past = _dates[i].isBefore(_today);
    return _HoverCell(
      enabled: !past && !wt.done && !wt.task.isMilestone,
      onTapUp: (d) => _openPopover(wt, i, d.globalPosition),
    );
  }

  List<Widget> _milestone(WeekTask wt, double colW) {
    final span = _span(wt.task);
    if (span == null) return const [];
    final c = wt.done ? kBPrimaryDark : kBAttention;
    return [
      Positioned(
        left: colW * span.e + colW / 2 - 6,
        top: _kRowH / 2 - 6,
        child: GestureDetector(
          onTap: () => _openTask(wt),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(2), border: Border.all(color: c, width: 1.5)),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _toPlaceBar(WeekTask wt, double colW, Color color, int remaining) {
    var start = dateOnly(wt.task.startDate);
    if (start.isBefore(_today)) start = _today;
    // Aujourd'hui hors fenêtre : à droite si on regarde le passé, à gauche
    // si on regarde l'avenir — et l'échéance réelle est écrite sur la barre.
    final idx = _dayIndex(start) ?? (_today.isAfter(_dates.last) ? _days - 1 : 0);
    final c = wt.overdue ? kBAlert : color;
    final due = dateOnly(wt.task.endDate ?? wt.task.startDate);
    final label = wt.overdue
        ? 'à caser · ${_fmtHm(remaining == 0 ? wt.task.plannedMin : remaining)} · éch. ${_dm(due)}'
        : 'à caser · ${_fmtHm(remaining == 0 ? wt.task.plannedMin : remaining)}';
    return Positioned(
      left: colW * idx + 3,
      width: colW - 6,
      top: _kBarTop,
      height: _kBarH,
      child: GestureDetector(
        onTapUp: (d) => _openPopover(wt, idx, d.globalPosition),
        onSecondaryTapUp: (_) => _pickColor(wt),
        child: CustomPaint(
          painter: _DashedRectPainter(color: c, radius: 6, strokeWidth: 1.5),
          child: Center(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c, fontFeatures: _tabular)),
          ),
        ),
      ),
    );
  }

  /// Colonne du jour d'un bloc de la fenêtre (null si introuvable).
  int? _blockDayIdx(ScheduleBlock b) {
    final date = _dateOfBlock(b);
    return date == null ? null : _dayIndex(DateTime.parse(date));
  }

  List<Widget> _bar(WeekTask wt, double colW, Color color, List<ScheduleBlock> blocks, int remaining) {
    // La barre couvre les dates de la tâche ET les jours de ses blocs : une
    // tâche en retard (dates avant la fenêtre) planifiée mardi reste visible,
    // avec son point, sur mardi.
    var span = _span(wt.task);
    final idx = blocks.map(_blockDayIdx).whereType<int>().toList();
    if (idx.isNotEmpty) {
      final mn = idx.reduce(math.min), mx = idx.reduce(math.max);
      span = span == null ? (s: mn, e: mx) : (s: math.min(span.s, mn), e: math.max(span.e, mx));
    }
    if (span == null) return const [];
    final dragging = _dragTaskId == wt.task.id;
    final deltaDays = dragging ? (_dragDx / colW).round() : 0;
    final s = span.s + (dragging && !_dragResize ? deltaDays : 0);
    final e = span.e + (dragging ? deltaDays : 0);
    final left = colW * s + 3;
    final width = math.max(colW * (e - s + 1) - 6, 18.0);
    final fill = color.withOpacity(wt.done ? .35 : .75);
    final t = wt.task;
    final doneBlocks = blocks.where((b) => b.status == 'done').length;
    final barTip = [
      '${_dm(t.startDate)}${t.endDate != null ? ' → ${_dm(t.endDate!)}' : ''}'
          ' · estimé ${_fmtHm(t.plannedMin)}',
      '${blocks.length} bloc${blocks.length > 1 ? 's' : ''}'
          '${doneBlocks > 0 ? ' · $doneBlocks fait${doneBlocks > 1 ? 's' : ''}' : ''}'
          '${remaining > 0 && !wt.done ? ' · reste ${_fmtHm(remaining)} à caser' : ''}',
      'Glisser = déplacer · bord droit = échéance · clic droit = couleur',
    ].join('\n');
    // Points visibles : ~48 px chacun ; au-delà, « +N » plutôt qu'un
    // rognage silencieux.
    final maxDots = math.max(1, ((width - 18) / 48).floor());
    final shownBlocks = blocks.length > maxDots ? blocks.take(maxDots - 1).toList() : blocks;
    final hiddenDots = blocks.length - shownBlocks.length;
    return [
      Positioned(
        left: left,
        width: width,
        top: _kBarTop,
        height: _kBarH,
        child: MouseRegion(
          cursor: dragging && !_dragResize ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
          child: Tooltip(
          message: barTip,
          waitDuration: const Duration(milliseconds: 700),
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _openPopover(
              wt, (s + (d.localPosition.dx / colW).floor()).clamp(0, _days - 1), d.globalPosition),
          onSecondaryTapUp: (_) => _pickColor(wt),
          onHorizontalDragStart: (_) => setState(() {
            _dragTaskId = wt.task.id;
            _dragResize = false;
            _dragDx = 0;
          }),
          onHorizontalDragUpdate: (d) => setState(() => _dragDx += d.delta.dx),
          onHorizontalDragEnd: (_) {
            final delta = (_dragDx / colW).round();
            setState(() => _dragTaskId = null);
            _shiftTask(wt, delta);
          },
          onHorizontalDragCancel: () => setState(() => _dragTaskId = null),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
              border: dragging ? Border.all(color: Colors.white.withOpacity(.6)) : null,
            ),
            padding: const EdgeInsets.only(left: 8, right: 10),
            child: ClipRect(
              child: Row(children: [
                for (final b in shownBlocks) ...[
                  _dot(b),
                  const SizedBox(width: 6),
                ],
                if (hiddenDots > 0) ...[
                  Text('+$hiddenDots',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: kBBg, fontFeatures: _tabular)),
                  const SizedBox(width: 6),
                ],
                if (remaining > 0 && !wt.done)
                  Flexible(
                    child: Text('reste ${_fmtHm(remaining)} à caser',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: kBBg.withOpacity(.6), fontFeatures: _tabular)),
                  ),
              ]),
            ),
          ),
          ),
          ),
        ),
      ),
      // Poignée droite : étendre / réduire l'échéance.
      Positioned(
        left: left + width - 6,
        width: 8,
        top: _kBarTop,
        height: _kBarH,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: Tooltip(
          message: 'Tirer pour changer l\'échéance',
          waitDuration: const Duration(milliseconds: 500),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => setState(() {
              _dragTaskId = wt.task.id;
              _dragResize = true;
              _dragDx = 0;
            }),
            onHorizontalDragUpdate: (d) => setState(() => _dragDx += d.delta.dx),
            onHorizontalDragEnd: (_) {
              final delta = (_dragDx / colW).round();
              setState(() => _dragTaskId = null);
              _resizeTask(wt, delta);
            },
            onHorizontalDragCancel: () => setState(() => _dragTaskId = null),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.55), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          ),
        ),
      ),
    ];
  }

  /// Point d'un bloc dans la barre : plein = fait, anneau = à venir, barré =
  /// sauté. Infobulle avec le jour, l'heure, la durée et l'état ; le clic
  /// ouvre le menu (reporter à demain / retirer).
  Widget _dot(ScheduleBlock b) {
    final done = b.status == 'done';
    final skipped = b.status == 'skipped';
    final date = _dateOfBlock(b);
    final day = date == null ? '' : _dm(DateTime.parse(date));
    final state = done ? 'fait' : skipped ? 'sauté' : 'à venir';
    return Tooltip(
      message: '$day · ${b.startTime} · ${_fmtHm(b.durationMin)} · $state\nClic : reporter à demain ou retirer',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTapDown: (d) => _openDotMenu(b, d.globalPosition),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: done ? kBBg : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: kBBg.withOpacity(skipped ? .45 : 1), width: 1.5))),
            const SizedBox(width: 4),
            Text(_fmtHm(b.durationMin),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kBBg.withOpacity(skipped ? .45 : 1),
                    decoration: skipped ? TextDecoration.lineThrough : null,
                    decorationColor: kBBg,
                    fontFeatures: _tabular)),
          ]),
        ),
      ),
    );
  }

  Widget _legend() {
    Widget item(Widget swatch, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          swatch,
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11.5, color: kBText3)),
        ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Row(children: [
        item(
            Container(
                width: 18,
                height: 8,
                decoration: BoxDecoration(
                    color: kBPrimary.withOpacity(.75), borderRadius: BorderRadius.circular(3))),
            'tâche prévue'),
        const SizedBox(width: 16),
        item(Container(width: 6, height: 6, decoration: const BoxDecoration(color: kBText, shape: BoxShape.circle)),
            'bloc dans le programme'),
        const SizedBox(width: 16),
        item(
            SizedBox(
                width: 18,
                height: 8,
                child: CustomPaint(painter: _DashedRectPainter(color: kBText3, radius: 3, strokeWidth: 1.2))),
            'à caser'),
        const SizedBox(width: 16),
        item(
            Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: kBAttention, borderRadius: BorderRadius.circular(1)))),
            'jalon'),
        const Spacer(),
        const Tooltip(
          message: 'Clic sur un jour = caser · glisser = déplacer · bord droit = échéance\nclic droit = couleur · point = bloc (menu)',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.info_outline, size: 14, color: kBText4),
            SizedBox(width: 4),
            Text('Les gestes', style: TextStyle(fontSize: 11, color: kBText4)),
          ]),
        ),
      ]),
    );
  }

  // ── Briques ─────────────────────────────────────────────────────────────────

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(.18), borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color, fontFeatures: _tabular)),
      );

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) => IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20, color: kBText2),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      );

  Widget _textLink(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kBPrimary)),
        ),
      );

  Widget _pillButton(String label, {bool primary = false, IconData? icon, VoidCallback? onTap}) {
    final fg = primary ? kBBg : kBText;
    return SizedBox(
      height: 36,
      child: TextButton.icon(
        onPressed: onTap,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 15, color: fg),
        label: Text(label),
        style: TextButton.styleFrom(
          backgroundColor: primary ? kBPrimary : const Color(0x12FFFFFF),
          disabledBackgroundColor: primary ? kBPrimary.withOpacity(.4) : const Color(0x0AFFFFFF),
          foregroundColor: fg,
          disabledForegroundColor: fg.withOpacity(.5),
          shape: const StadiumBorder(),
          padding: EdgeInsets.symmetric(horizontal: icon == null ? 14 : 12),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Cellule survolable (« + » discret) ───────────────────────────────────────

class _HoverCell extends StatefulWidget {
  final bool enabled;
  final void Function(TapUpDetails) onTapUp;
  const _HoverCell({required this.enabled, required this.onTapUp});

  @override
  State<_HoverCell> createState() => _HoverCellState();
}

class _HoverCellState extends State<_HoverCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.expand();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.onTapUp,
        child: Center(
          child: _hover ? const Icon(Icons.add, size: 14, color: kBText4) : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

// ── Peintres ─────────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final int days;
  final int? todayIdx;
  final List<bool> weekend;
  const _GridPainter({required this.days, required this.todayIdx, required this.weekend});

  @override
  void paint(Canvas canvas, Size size) {
    final colW = size.width / days;
    final sep = Paint()..color = const Color(0x0FFFFFFF);
    final we = Paint()..color = const Color(0x04FFFFFF);
    for (var i = 0; i < days; i++) {
      final x = colW * i;
      if (weekend[i]) canvas.drawRect(Rect.fromLTWH(x, 0, colW, size.height), we);
      if (i > 0) canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), sep);
    }
    if (todayIdx != null) {
      final r = Rect.fromLTWH(colW * todayIdx!, 0, colW, size.height);
      canvas.drawRect(
          r,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kBPrimary.withOpacity(.13), kBPrimary.withOpacity(.05)],
            ).createShader(r));
      final border = Paint()..color = kBPrimary.withOpacity(.25);
      canvas.drawRect(Rect.fromLTWH(r.left, 0, 1, size.height), border);
      canvas.drawRect(Rect.fromLTWH(r.right - 1, 0, 1, size.height), border);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.days != days || old.todayIdx != todayIdx || old.weekend != weekend;
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  const _DashedRectPainter({required this.color, required this.radius, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
        Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    const dash = 4.0, gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.radius != radius || old.strokeWidth != strokeWidth;
}

// ── Dialog « Capacité » ───────────────────────────────────────────────────────

class _CapacityDialog extends StatefulWidget {
  final Map<String, int> capacity;
  final DayWindow window;
  const _CapacityDialog({required this.capacity, required this.window});

  @override
  State<_CapacityDialog> createState() => _CapacityDialogState();
}

class _CapacityDialogState extends State<_CapacityDialog> {
  late final Map<String, TextEditingController> _ctrl;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;

  @override
  void initState() {
    super.initState();
    _ctrl = {
      for (final k in kWeekDayKeys) k: TextEditingController(text: _fmtHours(widget.capacity[k] ?? 0)),
    };
    _startCtrl = TextEditingController(text: _fmtHours(widget.window.startMin));
    _endCtrl = TextEditingController(text: _fmtHours(widget.window.endMin));
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  // Heure de la journée active : « 4 », « 4,5 » ou « 4:30 » → minutes.
  int? _parseClock(String s) {
    final t = s.trim().replaceAll(',', '.');
    if (t.contains(':')) {
      final p = t.split(':');
      final h = int.tryParse(p[0]), m = p.length > 1 ? int.tryParse(p[1]) : 0;
      if (h == null || m == null || h < 0 || h > 24 || m < 0 || m > 59) return null;
      return h * 60 + m;
    }
    final v = double.tryParse(t);
    if (v == null || v < 0 || v > 24) return null;
    return (v * 60).round();
  }

  DayWindow? get _window {
    final s = _parseClock(_startCtrl.text), e = _parseClock(_endCtrl.text);
    if (s == null || e == null || !isValidDayWindow(s, e)) return null;
    return DayWindow(s, e);
  }

  static String _fmtHours(int min) {
    if (min % 60 == 0) return '${min ~/ 60}';
    return (min / 60).toStringAsFixed(1).replaceAll('.', ',');
  }

  int? _parse(String s) {
    final v = double.tryParse(s.trim().replaceAll(',', '.'));
    if (v == null || v < 0 || v > 16) return null;
    return (v * 60).round();
  }

  bool get _valid => _ctrl.values.every((c) => _parse(c.text) != null) && _window != null;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kBSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Capacité par jour',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kBText)),
            const SizedBox(height: 4),
            const Text('Heures que tu peux consacrer au programme chaque jour. 0 = repos.',
                style: TextStyle(fontSize: 12.5, color: kBText3, height: 1.4)),
            const SizedBox(height: 16),
            for (var i = 0; i < 7; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(
                    width: 110,
                    child: Text(_kDayLong[i][0].toUpperCase() + _kDayLong[i].substring(1),
                        style: const TextStyle(fontSize: 13.5, color: kBText)),
                  ),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _ctrl[kWeekDayKeys[i]],
                      onChanged: (_) => setState(() {}),
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: kBText, fontFeatures: _tabular),
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: 'h',
                        errorText: _parse(_ctrl[kWeekDayKeys[i]]!.text) == null ? '0–16' : null,
                      ),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: kBLine),
            const SizedBox(height: 12),
            const Text('Journée active',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kBText)),
            const SizedBox(height: 4),
            const Text(
                'Plage où tes blocs comptent (charge, journée bloquée, créneaux proposés). '
                'En dehors, un bloc de sommeil ne compte pas. Lève-tôt ? Mets 4 h → 20 h.',
                style: TextStyle(fontSize: 12.5, color: kBText3, height: 1.4)),
            const SizedBox(height: 10),
            Row(children: [
              const SizedBox(width: 110, child: Text('De', style: TextStyle(fontSize: 13.5, color: kBText))),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _startCtrl,
                  onChanged: (_) => setState(() {}),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: kBText, fontFeatures: _tabular),
                  decoration: InputDecoration(
                      isDense: true, suffixText: 'h', errorText: _window == null ? ' ' : null),
                ),
              ),
              const SizedBox(width: 16),
              const Text('à', style: TextStyle(fontSize: 13.5, color: kBText)),
              const SizedBox(width: 16),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _endCtrl,
                  onChanged: (_) => setState(() {}),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: kBText, fontFeatures: _tabular),
                  decoration: InputDecoration(
                      isDense: true, suffixText: 'h', errorText: _window == null ? ' ' : null),
                ),
              ),
            ]),
            if (_window == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Au moins 4 h d\'écart, entre 0 h et 24 h (ex. 4 ou 4:30).',
                    style: TextStyle(fontSize: 11.5, color: kBAlert)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              TextButton(
                onPressed: () => Navigator.of(context)
                    .pop((capacity: defaultWeekCapacity(), window: kDefaultDayWindow)),
                child: const Text('Par défaut'),
              ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _valid
                    ? () => Navigator.of(context).pop((
                          capacity: {for (final k in kWeekDayKeys) k: _parse(_ctrl[k]!.text)!},
                          window: _window!,
                        ))
                    : null,
                style: FilledButton.styleFrom(backgroundColor: kBPrimary, foregroundColor: kBBg),
                child: const Text('Enregistrer'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
