import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/claude_link.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/interventions.dart' show interventionsOf, stripLeadEmoji;
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject;
import 'package:productivitwo_v1/utils/project_moment.dart' show projectPlan;
import 'package:productivitwo_v1/utils/planning.dart' show deepWorkTitle;
import 'package:productivitwo_v1/utils/recharge.dart' show isBasicNeedName;
import 'package:productivitwo_v1/utils/landing.dart' show sessionTaskIdsOf;
import 'package:productivitwo_v1/utils/half_days.dart' show minutesByActivityDay;
import 'package:productivitwo_v1/utils/week_stats.dart' show weekSummary, WeekSummary;
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/utils/week_capacity.dart';
import 'package:productivitwo_v1/utils/week_planner.dart';
import 'package:productivitwo_v1/web/schedule_block_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/web/ui_scale.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart';

// Vue « Cette semaine » (2026-11-07, maquette « Cette semaine, à placer ») :
// la semaine comme un agenda — une colonne par jour, les blocs du programme à
// leur heure. Le Gantt des tâches vit dans la Vision de chaque projet.

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
// Fenêtre affichée (début YYYY-MM-DD), restaurée seulement le jour même : un
// rechargement garde la semaine qu'on regardait, le lendemain repart d'ici.
const _kPrefStart = 'week_window_start';
const _kPrefStartSavedOn = 'week_window_saved_on';

String _fmtHm(int min) {
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// « mar. 7 » — jour court + numéro, pour les infobulles.
String _dm(DateTime d) => '${_kDayShort[d.weekday - 1].toLowerCase()}. ${d.day}';

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

  DateTime get _today => livedDate(DateTime.now(), widget.dayStartMin);
  List<DateTime> get _dates => windowDates(_start, _days);
  List<ScheduleBlock> get _allBlocks => [for (final l in _byDay.values) ...l];

  @override
  void initState() {
    super.initState();
    _start = weekStart(livedDate(DateTime.now(), widget.dayStartMin));
    _loadPrefs();
    _subscribe();
    _clockTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
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
      setState(() {
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

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
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
    _clockTick?.cancel();
    _gridScroll.dispose();
    _sessionsSub?.cancel();
    _hitsSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _setWindow({int? days, DateTime? start}) {
    _gridScrolled = false;
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

  String? _dateOfBlock(ScheduleBlock b) {
    for (final e in _byDay.entries) {
      if (e.value.contains(b)) return e.key;
    }
    return null;
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
    final toPlace = _toPlace();
    final showPlace = MediaQuery.sizeOf(context).width >= 1100;
    return Container(
      color: kBBg,
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pageHeader(toPlace: toPlace.length),
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (showPlace) ...[
              SizedBox(width: 300, child: _placeColumn(toPlace)),
              const SizedBox(width: 16),
            ],
            Expanded(child: _weekGrid()),
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

  // ── La semaine comme un agenda (2026-11-07, maquette « Cette semaine, à placer », lot 1) ──
  // Une colonne par jour sur la journée active, les blocs du programme à leur
  // heure (rendez-vous et séances en or), glisser = déplacer (d'un jour à
  // l'autre aussi), bord bas = durée, clic sur un créneau vide = nouveau bloc.

  static const _kGutter = 44.0;
  static const _kGridHead = 52.0;
  static const _kSnap = 15;

  String? _gDragId;
  bool _gResize = false;
  double _gDx = 0, _gDy = 0;
  ({int day, int min})? _gHover;

  // Toute la journée, de minuit à minuit (comme la frise d'Aujourd'hui) ; la
  // journée active remplit la hauteur visible, le reste se découvre en défilant.
  ({int start, int end}) _gridRange() => (start: 0, end: 24 * 60);

  final ScrollController _gridScroll = ScrollController();
  bool _gridScrolled = false;
  Timer? _clockTick;

  int get _nowMin {
    final n = DateTime.now();
    return n.hour * 60 + n.minute;
  }

  bool _canGridDrag(ScheduleBlock b, DateTime d) =>
      b.gcalEventId == null && b.status == 'pending' && !d.isBefore(_today);

  String _hhmm(int min) => '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

  Widget _weekGrid() {
    final sessionIds = sessionTaskIdsOf(widget.projects);
    return Container(
      key: const ValueKey('week-grid'),
      decoration: BoxDecoration(
        color: kBSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: _kGridHead,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(width: _kGutter),
            for (final d in _dates) Expanded(child: _gridDayHeader(d)),
          ]),
        ),
        Container(height: 1, color: kBLine),
        Expanded(child: LayoutBuilder(builder: (ctx, box) => _gridBody(box.maxWidth, box.maxHeight, sessionIds))),
      ]),
    );
  }

  Widget _gridDayHeader(DateTime d) {
    final blocks = _dayBlocks(d);
    final isToday = d == _today;
    final past = d.isBefore(_today);
    final open = _openDay == d;
    final cap = capacityMinFor(_capacity, d);
    final planned = plannedMin(blocks, window: _window);
    final counted = blocks.where((b) => b.gcalEventId == null).toList();
    final doneN = counted.where((b) => b.status == 'done').length;
    final letGo = counted.where(isLetGoBlock).length;
    final v = cap == 0 ? 0.0 : (planned / cap).clamp(0.0, 1.0);
    final behind = past && counted.isNotEmpty && doneN < counted.length;
    final name = '${_kDayShort[d.weekday - 1].toLowerCase()}. ${d.day}${isToday ? ' · aujourd’hui' : ''}';
    final sub = past
        ? (counted.isEmpty
            ? 'rien de posé'
            : '$doneN / ${counted.length} faits${letGo > 0 ? ' · $letGo lâché${letGo > 1 ? 's' : ''}' : ''}')
        : cap == 0
            ? (planned == 0 ? 'repos' : 'repos · ${_fmtHm(planned)}')
            : '${_fmtHm(planned)} / ${_fmtHm(cap)}';
    return Tooltip(
      message: 'Ouvrir ${_kDayLong[d.weekday - 1]} ${d.day}',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        key: ValueKey('week-day-${ymdOf(d)}'),
        onTap: () => setState(() {
          _openDay = open ? null : d;
          _railKey = null;
        }),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
          decoration: BoxDecoration(
            color: open ? const Color(0xFF14281F) : (isToday ? kBPrimary.withOpacity(.07) : Colors.transparent),
            border: const Border(left: BorderSide(color: kBLine)),
          ),
          child: Opacity(
            opacity: past && !open ? .75 : 1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: isToday ? kBPrimary : kBText, fontFeatures: _tabular)),
              const SizedBox(height: 4),
              if (!past) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 4,
                    child: Stack(children: [
                      Container(color: const Color(0x14FFFFFF)),
                      FractionallySizedBox(widthFactor: v, child: Container(color: v >= 1 ? kBAlert : kBPrimary)),
                    ]),
                  ),
                ),
                const SizedBox(height: 3),
              ],
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color: past ? (behind ? kBAttention : kBPrimary) : kBText3,
                      fontFeatures: _tabular)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _gridBody(double width, double height, Set<String> sessionIds) {
    final (:start, :end) = _gridRange();
    final range = end - start;
    final ppm = math.max((height - 12) / math.max(_window.spanMin, 60), 0.7);
    final total = range * ppm + 12;
    final colW = math.max(0.0, (width - _kGutter) / _days);
    double y(int min) => (min - start) * ppm + 6;
    int slotAt(double dy) => ((((dy - 6) / ppm + start) ~/ _kSnap) * _kSnap).clamp(start, end - _kSnap).toInt();

    final children = <Widget>[
      for (var h = start ~/ 60; h <= end ~/ 60; h++) ...[
        Positioned(
          left: _kGutter,
          right: 0,
          top: y(h * 60),
          child: Container(height: 1, color: const Color(0x0DFFFFFF)),
        ),
        if (h * 60 < end)
          Positioned(
            left: 0,
            width: _kGutter - 8,
            top: y(h * 60) - 7,
            child: Text(h.toString().padLeft(2, '0'),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: kBText4, fontFeatures: _tabular)),
          ),
      ],
    ];

    for (var i = 0; i < _days; i++) {
      final d = _dates[i];
      final left = _kGutter + i * colW;
      final past = d.isBefore(_today);
      final isToday = d == _today;
      children.add(Positioned(
        left: left,
        width: colW,
        top: 0,
        bottom: 0,
        child: DragTarget<_PlaceItem>(
          onWillAcceptWithDetails: (_) => !past,
          onMove: (det) {
            final m = _slotFromGlobal(i, det.offset, start, end, ppm);
            if (m != null && (_drop?.day != i || _drop?.min != m)) setState(() => _drop = (day: i, min: m, item: det.data));
          },
          onLeave: (_) {
            if (_drop?.day == i) setState(() => _drop = null);
          },
          onAcceptWithDetails: (det) {
            final m = _slotFromGlobal(i, det.offset, start, end, ppm) ?? _drop?.min ?? start;
            _dropItem(det.data, d, m);
          },
          builder: (ctx, cand, rej) => MouseRegion(
          cursor: past ? MouseCursor.defer : SystemMouseCursors.click,
          onHover: past
              ? null
              : (e) {
                  final m = slotAt(e.localPosition.dy);
                  if (_gHover?.day != i || _gHover?.min != m) setState(() => _gHover = (day: i, min: m));
                },
          onExit: (_) {
            if (_gHover != null) setState(() => _gHover = null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: past ? null : (e) => _addBlockOn(d, at: slotAt(e.localPosition.dy)),
            child: Container(
              key: _colKeys[i],
              decoration: BoxDecoration(
                color: cand.isNotEmpty
                    ? const Color(0xFF6AA8FF).withOpacity(.06)
                    : (isToday ? kBPrimary.withOpacity(.03) : Colors.transparent),
                border: const Border(left: BorderSide(color: kBLine)),
              ),
            ),
          ),
        ),
        ),
      ));
      final drop = _drop;
      if (drop != null && drop.day == i) {
        final dur = drop.item.defaultMin;
        children.add(Positioned(
          left: left + 3,
          width: colW - 6,
          top: y(drop.min) + 1,
          height: math.max(math.min(dur, end - drop.min) * ppm - 2, 18),
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1A3355),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0xFF6AA8FF), width: 2),
              ),
              child: Text('${drop.item.title} · ${_hhmm(drop.min)} → ${_hhmm(drop.min + dur)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kBText, fontFeatures: _tabular)),
            ),
          ),
        ));
      }
      final hover = _gHover;
      if (hover != null && hover.day == i && _gDragId == null && _drop == null) {
        children.add(Positioned(
          left: left + 3,
          width: colW - 6,
          top: y(hover.min) + 1,
          height: math.max(30 * ppm - 2, 18),
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: kBPrimary.withOpacity(.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBPrimary.withOpacity(.35)),
              ),
              child: Text('+ ${_hhmm(hover.min)}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kBPrimary, fontFeatures: _tabular)),
            ),
          ),
        ));
      }

      final blocks = [
        for (final b in _dayBlocks(d))
          if (blockStartMin(b) < end && blockEndMin(b) > start) b,
      ];
      final lanes = overlapColumns(blocks);
      final laneW = math.max(0.0, colW - 6);
      for (final b in blocks) {
        final lane = lanes[b.id] ?? (col: 0, cols: 1);
        final dragging = _gDragId == b.id;
        final delta = dragging ? ((_gDy / ppm) / _kSnap).round() * _kSnap : 0;
        final shift = dragging && !_gResize ? (_gDx / math.max(colW, 1)).round().clamp(-i, _days - 1 - i).toInt() : 0;
        var s = blockStartMin(b), dur = b.durationMin;
        if (dragging && _gResize) {
          dur = (dur + delta).clamp(_kSnap, 24 * 60 - s).toInt();
        } else if (dragging) {
          s = (s + delta).clamp(0, 24 * 60 - dur).toInt();
        }
        final top = y(math.max(s, start));
        final h = math.max((math.min(s + dur, end) - math.max(s, start)) * ppm - 2, 16.0);
        final bx = left + shift * colW + 3 + laneW * lane.col / lane.cols;
        final bw = laneW / lane.cols - (lane.cols > 1 ? 2 : 0);
        final canDrag = _canGridDrag(b, d);
        children.add(Positioned(
          left: bx,
          width: bw,
          top: top,
          height: h,
          child: MouseRegion(
            cursor: canDrag ? SystemMouseCursors.grab : SystemMouseCursors.click,
            child: Stack(fit: StackFit.expand, children: [
              GestureDetector(
                key: ValueKey('week-block-${b.id}'),
                onTap: () => _onGridBlockTap(b, d),
                onSecondaryTapUp: b.gcalEventId == null && !past ? (e) => _openDotMenu(b, e.globalPosition) : null,
                onPanStart: canDrag ? (_) => _gridDragBegin(b, resize: false) : null,
                onPanUpdate: canDrag
                    ? (e) => setState(() {
                          _gDx += e.delta.dx;
                          _gDy += e.delta.dy;
                        })
                    : null,
                onPanEnd: canDrag ? (_) => _gridCommit(b, d, ppm, colW) : null,
                onPanCancel: canDrag ? () => setState(() => _gDragId = null) : null,
                child: _gridBlock(b, d, _isDated(b, sessionIds), h, dragging),
              ),
              if (canDrag)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 6,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) => _gridDragBegin(b, resize: true),
                      onVerticalDragUpdate: (e) => setState(() => _gDy += e.delta.dy),
                      onVerticalDragEnd: (_) => _gridCommit(b, d, ppm, colW),
                      onVerticalDragCancel: () => setState(() => _gDragId = null),
                    ),
                  ),
                ),
            ]),
          ),
        ));
        if (dragging) {
          final target = _dates[i + shift];
          children.add(Positioned(
            left: bx,
            top: math.max(0.0, top - 20),
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: kBPrimary, borderRadius: BorderRadius.circular(6)),
                child: Text(
                    '${shift != 0 ? '${_dm(target)} · ' : ''}${_hhmm(s)} → ${_hhmm(s + dur)}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kBBg, fontFeatures: _tabular)),
              ),
            ),
          ));
        }
      }
    }

    // Trait rouge « maintenant » sur toute la semaine, appuyé sur le jour même.
    final nowDay = _dayIndex(DateTime.now());
    final now = _nowMin;
    if (nowDay != null) {
      children.add(Positioned(
        left: _kGutter,
        right: 0,
        top: y(now) - .5,
        child: IgnorePointer(child: Container(height: 1, color: const Color(0x66FF6B5E))),
      ));
      children.add(Positioned(
        left: _kGutter + nowDay * colW - 4,
        width: colW + 4,
        top: y(now) - 4,
        child: IgnorePointer(
          child: Row(children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFFF6B5E), shape: BoxShape.circle)),
            Expanded(child: Container(height: 2, color: const Color(0xFFFF6B5E))),
          ]),
        ),
      ));
      children.add(Positioned(
        left: 2,
        width: _kGutter - 4,
        top: y(now) - 8,
        child: IgnorePointer(
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(color: const Color(0xFFFF6B5E), borderRadius: BorderRadius.circular(5)),
            child: Text(_hhmm(now),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, fontFeatures: _tabular)),
          ),
        ),
      ));
    }

    // À l'ouverture (et à chaque changement de semaine) : recentré sur
    // l'heure actuelle cette semaine, sinon sur le début de la journée active.
    if (!_gridScrolled) {
      _gridScrolled = true;
      final target = (nowDay != null ? y(now) - height * .3 : y(_window.startMin) - 6).clamp(0.0, math.max(0.0, total - height));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_gridScroll.hasClients) _gridScroll.jumpTo(target.toDouble());
      });
    }
    final stack = SizedBox(height: total, width: width, child: Stack(clipBehavior: Clip.none, children: children));
    return SingleChildScrollView(controller: _gridScroll, child: stack);
  }

  Widget _gridBlock(ScheduleBlock b, DateTime d, bool dated, double h, bool dragging) {
    final done = b.status == 'done';
    final letGo = isLetGoBlock(b);
    final skipped = b.status == 'skipped' && !letGo;
    final past = d.isBefore(_today);
    final now = _nowMin;
    final running = d == _today && b.status == 'pending' && blockStartMin(b) <= now && blockEndMin(b) > now;
    final missed = !done && !letGo && b.gcalEventId == null &&
        (past || (d == _today && blockEndMin(b) <= now)) && b.status == 'pending';
    final Color bg, border, fg;
    if (dated) {
      bg = const Color(0xFF33290F);
      border = const Color(0xFF7A5F24);
      fg = kBAttention;
    } else if (done) {
      bg = const Color(0xFF16302A);
      border = const Color(0xFF2C5A45);
      fg = const Color(0xFFCFE7DA);
    } else if (letGo || skipped) {
      bg = Colors.transparent;
      border = const Color(0xFF6A3A36);
      fg = const Color(0xFFFF8F86);
    } else {
      bg = const Color(0xFF10251C);
      border = running ? kBPrimary : const Color(0xFF2A4A3C);
      fg = missed ? kBText3 : kBText;
    }
    final sub = done
        ? 'fait · ${_fmtHm(b.durationMin)}'
        : letGo
            ? 'lâché'
            : skipped
                ? (b.skipReason == kSkipUnavailable ? 'empêché' : 'déplacé')
                : running
                    ? 'en cours'
                    : missed
                        ? 'pas fait'
                        : '${b.startTime} · ${_fmtHm(b.durationMin)}${b.gcalEventId != null ? ' · agenda' : ''}';
    final prefix = done ? '✓ ' : letGo ? '✋ ' : '';
    return Tooltip(
      message: '${b.title.isEmpty ? 'Bloc' : b.title} · ${b.startTime} · ${_fmtHm(b.durationMin)}'
          '${b.gcalEventId != null ? ' · agenda Google' : ''}',
      waitDuration: const Duration(milliseconds: 700),
      child: Opacity(
        opacity: past && !dragging ? .78 : 1,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: h >= 30 ? 4 : 1),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: border, width: running || dragging ? 2 : 1),
            boxShadow: dragging ? const [BoxShadow(color: Color(0x80000000), blurRadius: 18, offset: Offset(0, 8))] : null,
          ),
          child: ClipRect(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$prefix${b.title.isEmpty ? 'Bloc' : b.title}',
                  maxLines: h >= 52 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      decoration: skipped ? TextDecoration.lineThrough : null)),
              if (h >= 32)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, height: 1.2, color: fg.withOpacity(.75), fontFeatures: _tabular)),
            ]),
          ),
        ),
      ),
    );
  }

  void _gridDragBegin(ScheduleBlock b, {required bool resize}) => setState(() {
        _gDragId = b.id;
        _gResize = resize;
        _gDx = 0;
        _gDy = 0;
        _gHover = null;
      });

  Future<void> _onGridBlockTap(ScheduleBlock b, DateTime d) async {
    if (b.gcalEventId != null || d.isBefore(_today)) {
      setState(() {
        _openDay = d;
        _railKey = null;
      });
      return;
    }
    final key = ymdOf(d);
    final updated = await showScheduleBlockDialog(context, block: b);
    if (updated == null || !mounted) return;
    await widget.sync.upsertScheduleBlock(key, updated);
  }

  Future<void> _gridCommit(ScheduleBlock b, DateTime from, double ppm, double colW) async {
    final resize = _gResize;
    final delta = ((_gDy / ppm) / _kSnap).round() * _kSnap;
    final i = _dayIndex(from) ?? 0;
    final shift = resize ? 0 : (_gDx / math.max(colW, 1)).round().clamp(-i, _days - 1 - i).toInt();
    setState(() => _gDragId = null);
    final fromKey = ymdOf(from);
    final oldStart = b.startTime, oldDur = b.durationMin;
    if (resize) {
      final dur = (oldDur + delta).clamp(_kSnap, 24 * 60 - blockStartMin(b)).toInt();
      if (dur == oldDur) return;
      setState(() => b.durationMin = dur);
      await widget.sync.upsertScheduleBlock(fromKey, b);
      _snack('« ${b.title} » : ${_fmtHm(dur)}, fin ${_hhmm(blockStartMin(b) + dur)}',
          actionLabel: 'Annuler', onAction: () async {
        setState(() => b.durationMin = oldDur);
        await widget.sync.upsertScheduleBlock(fromKey, b);
      });
      return;
    }
    final start = (blockStartMin(b) + delta).clamp(0, 24 * 60 - oldDur).toInt();
    if (shift == 0 && start == blockStartMin(b)) return;
    final target = _dates[i + shift];
    if (target.isBefore(_today)) {
      _snack('On ne pose pas un bloc dans un jour passé.');
      return;
    }
    if (shift == 0) {
      setState(() => b.startTime = _hhmm(start));
      await widget.sync.upsertScheduleBlock(fromKey, b);
      _snack('« ${b.title} » déplacé à ${_hhmm(start)}', actionLabel: 'Annuler', onAction: () async {
        setState(() => b.startTime = oldStart);
        await widget.sync.upsertScheduleBlock(fromKey, b);
      });
      return;
    }
    // Vers un autre jour : copie à destination, l'origine passe « déplacée »
    // (comme le report au lendemain) — Claude ne la recrée pas.
    final toKey = ymdOf(target);
    final copy = ScheduleBlock.from({
      ...b.toJson(),
      'id': null,
      'startTime': _hhmm(start),
      'status': 'pending',
      'doneAt': null,
      'carriedFromDate': '$fromKey:${b.id}',
    });
    setState(() {
      _byDay[fromKey]?.remove(b);
      (_byDay[toKey] ??= []).add(copy);
    });
    await widget.sync.upsertScheduleBlock(toKey, copy);
    await widget.sync.updateBlockStatus(fromKey, b.id, 'skipped');
    await widget.sync.updateBlockSkipReason(fromKey, b.id, 'reporte');
    _snack('« ${b.title} » déplacé ${_kDayLong[target.weekday - 1]} ${target.day} à ${_hhmm(start)}',
        actionLabel: 'Annuler', onAction: () async {
      await widget.sync.updateBlockStatus(toKey, copy.id, 'deleted');
      await widget.sync.updateBlockStatus(fromKey, b.id, 'pending');
    });
  }

  // ── À placer cette semaine (2026-11-07, maquette « Cette semaine, à placer », lot 2) ──
  // Ce que la semaine demande encore et qui n'a pas de place : minimum de la
  // Montre suisse par activité, prépas de séance, projets en retard, échéances.
  // Une ligne se glisse sur la grille ; ce qui est posé se retire du reste.

  ({int day, int min, _PlaceItem item})? _drop;
  final List<GlobalKey> _colKeys = List.generate(14, (_) => GlobalKey());

  bool _isUpcoming(ScheduleBlock b, DateTime d) =>
      !d.isBefore(_today) && (d != _today || blockEndMin(b) > _nowMin);

  List<_PlaceItem> _toPlace() {
    final last = _dates.last;
    if (last.isBefore(_today)) return const [];
    final from = _dates.first.isBefore(_today) ? _today : _dates.first;
    final all = [for (final d in _dates) for (final b in _dayBlocks(d)) (d: d, b: b)];
    final upcoming = [for (final e in all) if (e.b.status == 'pending' && _isUpcoming(e.b, e.d)) e.b];
    final taskIds = {for (final e in all) if (e.b.taskId != null && (e.b.status != 'skipped' || isLetGoBlock(e.b))) e.b.taskId!};
    final out = <_PlaceItem>[];

    // Montre suisse : 7 × le minimum sur la semaine, moins le fait et le posé.
    final minutes = minutesByActivityDay(_sessions, DateTime.now());
    final ymds = {for (final d in _dates) ymdOf(d)};
    final watch = <_PlaceItem>[];
    for (final a in widget.activities) {
      if (a.deleted || a.isHabit || a.goalMin <= 0 || isBasicNeedName(a.name)) continue;
      final need = a.goalMin * _days;
      var done = 0;
      (minutes[a.id] ?? const <String, int>{}).forEach((k, v) {
        if (ymds.contains(k)) done += v;
      });
      final planned = upcoming.where((b) => b.activityId == a.id && b.taskId == null).fold<int>(0, (s, b) => s + b.durationMin);
      final left = need - done - planned;
      if (left < 10) continue;
      watch.add(_PlaceItem(
        key: 'watch:${a.id}',
        group: 'Montre suisse · reste',
        title: a.name,
        remainingMin: left,
        defaultMin: math.min(left, 45),
        color: domainColor(a.domainId, widget.domains) ?? kBPrimary,
        make: (s, dur) => ScheduleBlock(startTime: _hhmm(s), durationMin: dur, title: a.name, category: 'personal', activityId: a.id),
      ));
    }
    watch.sort((x, y) => y.remainingMin.compareTo(x.remainingMin));
    out.addAll(watch.take(6));

    // Séances de la fenêtre dont la prépa n'a pas encore de bloc.
    final live = widget.projects.where((p) => p.status == 'active').toList();
    for (final p in live) {
      for (final iv in interventionsOf(p)) {
        final prep = iv.prep;
        if (prep == null || prep.status == 'done' || prep.status == 'skipped') continue;
        if (iv.date.isBefore(from) || iv.date.isAfter(last.add(const Duration(days: 2)))) continue;
        if (taskIds.contains(prep.id)) continue;
        out.add(_PlaceItem(
          key: 'prep:${prep.id}',
          group: 'Séances à préparer',
          title: 'Préparer · ${iv.title}',
          sub: 'séance ${_dm(iv.date)}${iv.timeRange != null ? ' · ${iv.timeRange}' : ''}',
          defaultMin: prep.estimatedMin ?? 60,
          color: kBAttention,
          make: (s, dur) => ScheduleBlock(
            startTime: _hhmm(s),
            durationMin: dur,
            title: stripLeadEmoji(prep.title),
            category: 'project',
            projectId: p.id,
            taskId: prep.id,
            actionId: prep.actions.where((a) => !a.done).firstOrNull?.id,
          ),
        ));
      }
    }

    // Projets en retard sur leur plan, sans Deep work visé dans la fenêtre.
    final late = <(Project, int)>[];
    for (final p in live) {
      if (isFolderProject(p, widget.projects)) continue;
      final plan = projectPlan(p, _today);
      if (plan.delta >= 0) continue;
      if (upcoming.any((b) => b.projectId == p.id && b.taskId == null)) continue;
      late.add((p, -plan.delta));
    }
    late.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (p, n) in late.take(4)) {
      out.add(_PlaceItem(
        key: 'late:${p.id}',
        group: 'Projets en retard',
        title: p.title,
        sub: '$n tâche${n > 1 ? 's' : ''} de retard · un Deep work visé',
        defaultMin: 90,
        color: const Color(0xFFFF8F86),
        make: (s, dur) => ScheduleBlock(
            startTime: _hhmm(s),
            durationMin: dur,
            title: deepWorkTitle(p.title),
            category: 'project',
            projectId: p.id,
            timeBlock: 'deep'),
      ));
    }

    // Échéances de la fenêtre (tâches ouvertes hors séance) sans bloc.
    final due = <_PlaceItem>[];
    for (final p in live) {
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped' || t.isMilestone || t.interventionId != null) continue;
        if (t.id == 'gtd-flow' || taskIds.contains(t.id)) continue;
        final end = t.endDate;
        if (end == null) continue;
        final d = dateOnly(end);
        if (d.isBefore(from) || d.isAfter(last)) continue;
        due.add(_PlaceItem(
          key: 'due:${t.id}',
          group: 'Échéances',
          title: t.title,
          sub: 'pour ${_dm(d)} · ${p.title}',
          defaultMin: t.estimatedMin ?? 45,
          color: domainColor(p.domainId, widget.domains) ?? kBPrimary,
          sortKey: d,
          make: (s, dur) => ScheduleBlock(
            startTime: _hhmm(s),
            durationMin: dur,
            title: t.title,
            category: 'project',
            projectId: p.id,
            taskId: t.id,
            actionId: t.actions.where((a) => !a.done).firstOrNull?.id,
          ),
        ));
      }
    }
    due.sort((a, b) => a.sortKey!.compareTo(b.sortKey!));
    out.addAll(due.take(5));
    return out;
  }

  static final _timeItems = [
    _PlaceItem(
      key: 'time:deep',
      group: 'Poser du temps',
      title: 'Deep work',
      defaultMin: 90,
      color: const Color(0xFF6AA8FF),
      make: (s, dur) => ScheduleBlock(
          startTime: '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}',
          durationMin: dur,
          title: 'Deep work',
          category: 'project',
          timeBlock: 'deep'),
    ),
    _PlaceItem(
      key: 'time:small',
      group: 'Poser du temps',
      title: 'Petites choses',
      defaultMin: 45,
      color: const Color(0xFFFF9A5C),
      make: (s, dur) => ScheduleBlock(
          startTime: '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}',
          durationMin: dur,
          title: 'Petites choses',
          category: 'personal',
          timeBlock: 'small'),
    ),
  ];

  Widget _placeColumn(List<_PlaceItem> items) {
    final groups = <String, List<_PlaceItem>>{};
    for (final it in items) {
      (groups[it.group] ??= []).add(it);
    }
    final past = _dates.last.isBefore(_today);
    return Container(
      key: const ValueKey('week-place'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1F17),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2C5A45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(
            child: Text('À placer cette semaine',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kBText)),
          ),
          if (items.isNotEmpty)
            Text('${items.length}', style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
        ]),
        const SizedBox(height: 4),
        Text(
            past
                ? 'Cette semaine est passée.'
                : items.isEmpty
                    ? 'Tout ce que la semaine demande a sa place.'
                    : 'Ce que ta semaine demande et qui n’a pas encore de place. Glisse une ligne sur un jour.',
            style: const TextStyle(fontSize: 12, color: kBText3, height: 1.35)),
        const SizedBox(height: 6),
        Expanded(
          child: ListView(children: [
            for (final e in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text(e.key.toUpperCase(),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
              ),
              for (final it in e.value) Padding(padding: const EdgeInsets.only(bottom: 6), child: _placeRow(it)),
            ],
          ]),
        ),
        if (!past) ...[
          const SizedBox(height: 6),
          const Text('POSER DU TEMPS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
          const SizedBox(height: 6),
          Row(children: [
            for (final it in _timeItems) ...[
              if (it != _timeItems.first) const SizedBox(width: 8),
              Expanded(child: _draggable(it, _timeChip(it))),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _timeChip(_PlaceItem it) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: it.color.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
        child: Text(it.title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: it.color)),
      );

  Widget _placeRow(_PlaceItem it) => _draggable(
        it,
        Container(
          key: ValueKey('week-place-${it.key}'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x09FFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x0DFFFFFF)),
          ),
          child: Row(children: [
            const Icon(Icons.drag_indicator, size: 16, color: kBText4),
            const SizedBox(width: 6),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: it.color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kBText)),
                if (it.sub != null)
                  Text(it.sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: kBText3)),
              ]),
            ),
            if (it.remainingMin > 0) ...[
              const SizedBox(width: 6),
              Text(_fmtHm(it.remainingMin),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kBAttention, fontFeatures: _tabular)),
            ],
          ]),
        ),
      );

  Widget _draggable(_PlaceItem it, Widget child) => MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<_PlaceItem>(
          data: it,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragEnd: (_) {
            if (_drop != null) setState(() => _drop = null);
          },
          feedback: Material(
            color: Colors.transparent,
            child: Transform.translate(
              offset: const Offset(-20, -14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3355),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: it.color, width: 1.5),
                  boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 18, offset: Offset(0, 8))],
                ),
                child: Text(it.title,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kBText, decoration: TextDecoration.none)),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: .45, child: child),
          child: child,
        ),
      );

  int? _slotFromGlobal(int i, Offset global, int start, int end, double ppm) {
    final box = _colKeys[i].currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final dy = box.globalToLocal(global).dy;
    return ((((dy - 6) / ppm + start) ~/ _kSnap) * _kSnap).clamp(start, end - _kSnap).toInt();
  }

  Future<void> _dropItem(_PlaceItem it, DateTime d, int startMin) async {
    setState(() => _drop = null);
    if (d.isBefore(_today)) {
      _snack('On ne pose pas un bloc dans un jour passé.');
      return;
    }
    final dur = await showDialog<int>(
      context: context,
      builder: (_) => _PlaceDurationDialog(
        title: '${it.title} · ${_dm(d)} à ${_hhmm(startMin)}',
        initial: it.defaultMin,
        remaining: it.remainingMin,
      ),
    );
    if (dur == null || !mounted) return;
    final key = ymdOf(d);
    final block = it.make(startMin, dur);
    setState(() => (_byDay[key] ??= []).add(block));
    await widget.sync.upsertScheduleBlock(key, block);
    final left = it.remainingMin - dur;
    _snack(
        '« ${it.title} » posé ${_kDayLong[d.weekday - 1]} ${d.day} à ${_hhmm(startMin)}'
        '${it.remainingMin > 0 ? (left >= 10 ? ' · il reste ${_fmtHm(left)}' : ' · couvert') : ''}',
        actionLabel: 'Annuler', onAction: () async {
      setState(() => _byDay[key]?.remove(block));
      await widget.sync.updateBlockStatus(key, block.id, 'deleted');
    });
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

  Future<void> _addBlockOn(DateTime d, {int? at}) async {
    final created = await showScheduleBlockDialog(context,
        isNew: true, block: ScheduleBlock(startTime: at == null ? '09:00' : _hhmm(at), durationMin: 60, title: ''));
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
    (key: 'dates', label: 'Dates', icon: Icons.event_outlined),
  ];

  bool get _isCurrentWeek => _days == 7 && _start == weekStart(_today);

  // Recalculés au plus une fois par minute ou quand une donnée change (le
  // glisser d'une barre redessine à chaque pixel).
  String _railMemoKey = '';
  WeekSummary? _contractMemo;

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
  }

  WeekSummary _contract() {
    _refreshRail();
    return _contractMemo!;
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
          Expanded(child: Text(title,
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

  Widget _pageHeader({int toPlace = 0}) {
    final title = _days == 7
        ? 'Semaine du ${_start.day} ${_kMonthLong[_start.month - 1]}'
        : '14 jours à partir du ${_start.day} ${_kMonthShort[_start.month - 1]}';
    final isCurrent = _days == 7 ? _start == weekStart(_today) : _start == _today;
    final planned = [for (final d in _dates) plannedMin(_dayBlocks(d), window: _window)].fold<int>(0, (a, b) => a + b);
    final cap = [for (final d in _dates) capacityMinFor(_capacity, d)].fold<int>(0, (a, b) => a + b);
    final sessionIds = sessionTaskIdsOf(widget.projects);
    final dated = [for (final d in _dates) ..._dayBlocks(d).where((b) => _isDated(b, sessionIds))].length;
    final contract = _isCurrentWeek ? _contract() : null;
    final now = _nowMin;
    final toDo = [
      for (final d in _dates)
        if (!d.isBefore(_today))
          ..._dayBlocks(d).where((b) =>
              b.status == 'pending' && b.gcalEventId == null && (d != _today || blockEndMin(b) > now)),
    ].length;
    final summary = [
      '${_fmtHm(planned)} posées sur ${_fmtHm(cap)}',
      if (dated > 0) '$dated rendez-vous et séance${dated > 1 ? 's' : ''}',
      if (toDo > 0) '$toDo bloc${toDo > 1 ? 's' : ''} à faire',
      if (toPlace > 0) '$toPlace à placer',
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


/// Une chose « à placer » : glissée sur la grille, elle devient un bloc.
class _PlaceItem {
  final String key;
  final String group;
  final String title;
  final String? sub;
  /// Ce qu'il manque encore (Montre suisse), 0 = rien à compter.
  final int remainingMin;
  final int defaultMin;
  final Color color;
  final DateTime? sortKey;
  final ScheduleBlock Function(int startMin, int durationMin) make;
  const _PlaceItem({
    required this.key,
    required this.group,
    required this.title,
    this.sub,
    this.remainingMin = 0,
    required this.defaultMin,
    required this.color,
    this.sortKey,
    required this.make,
  });
}

/// Au lâcher : la durée du bloc (« tout le reste » pour la Montre suisse).
class _PlaceDurationDialog extends StatefulWidget {
  final String title;
  final int initial;
  final int remaining;
  const _PlaceDurationDialog({required this.title, required this.initial, required this.remaining});

  @override
  State<_PlaceDurationDialog> createState() => _PlaceDurationDialogState();
}

class _PlaceDurationDialogState extends State<_PlaceDurationDialog> {
  late int _min = widget.initial;

  @override
  Widget build(BuildContext context) {
    final choices = {30, 45, 60, 90, if (widget.remaining >= 10 && widget.remaining <= 4 * 60) widget.remaining, widget.initial}
        .toList()
      ..sort();
    final left = widget.remaining - _min;
    return Dialog(
      backgroundColor: const Color(0xFF10241B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF3A5A4A))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kBText)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in choices)
                InkWell(
                  key: ValueKey('place-dur-$m'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _min = m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: m == _min ? const Color(0xFF6AA8FF) : const Color(0x12FFFFFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_fmtHm(m),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: m == _min ? const Color(0xFF06142A) : kBText2)),
                  ),
                ),
            ]),
            if (widget.remaining > 0) ...[
              const SizedBox(height: 8),
              Text(left >= 10 ? 'il restera ${_fmtHm(left)} à placer' : 'couvert pour la semaine',
                  style: const TextStyle(fontSize: 12, color: kBText3)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
              const SizedBox(width: 6),
              FilledButton(
                key: const ValueKey('place-confirm'),
                style: FilledButton.styleFrom(backgroundColor: kBPrimary, foregroundColor: kBBg),
                onPressed: () => Navigator.pop(context, _min),
                child: const Text('Poser le bloc'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
