import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/challenge_reminders.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/routine_match.dart';
import 'package:productivitwo_v1/utils/schedule_suggest.dart';
import 'package:productivitwo_v1/widgets/plan_day_screen.dart';
import 'package:productivitwo_v1/widgets/renegotiate_sheet.dart';

// ─── TIMELINE 24 H ÉDITABLE (façon Calendar) ─────────────────────────────────
//
// Le programme du jour comme un agenda : journée complète 00-24 h, trait rouge
// « maintenant », blocs positionnés à leur heure. Gestes :
//   · appui long dans le VIDE  → ajouter un bloc à ce créneau (snap 15 min) ;
//   · tap ou appui long sur un BLOC → mode édition : poignées haut/bas pour la
//     durée, glisser le corps pour déplacer l'heure (snap 15 min), barre
//     d'actions (heure · ✓ · ▶ · fiche · renégocier · 🗑) ;
//   · tap ailleurs → désélection. Heure/durée = LIBRES (jamais un report).
// Les MIROIRS Google Agenda sont en lecture seule (l'agenda est leur vérité) ;
// les blocs faits sont grisés. Toutes les écritures passent par les chemins
// existants (updateScheduleBlockTime/addScheduleBlock…) → la sync agenda suit
// via le trigger. La proposition (« ✨ Étoffer ») reste le moteur pour remplir
// une journée creuse.

class DayTimelineView extends StatefulWidget {
  final String date; // YYYY-MM-DD
  final AppLogic logic;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(ScheduleBlock block)? onOpenSource;

  const DayTimelineView({
    super.key,
    required this.date,
    required this.logic,
    this.onLaunch,
    this.onOpenSource,
  });

  @override
  State<DayTimelineView> createState() => _DayTimelineViewState();
}

class _DayTimelineViewState extends State<DayTimelineView> {
  // 1 h = 100 px : plus de profondeur = plus de précision d'affichage (un bloc
  // de 10 min reste distinct du suivant), quitte à scroller davantage.
  static const double _hourH = 100;
  static const double _leftGutter = 46; // colonne des heures
  // Hauteur plancher d'un bloc (lisibilité du titre). Le layout en tient
  // compte : deux blocs proches dans le temps mais dont les RENDUS se
  // chevaucheraient passent en colonnes au lieu de se repeindre l'un l'autre.
  static const double _minBlockH = 24;
  static const int _snapMin = 15;
  static const _red = Color(0xFFE53935);

  final _sync = FirestoreSync();
  DailySchedule? _schedule;
  StreamSubscription<DailySchedule?>? _sub;
  Timer? _nowTick;
  final _nowKey = GlobalKey();
  bool _scrolledToNow = false;

  String? _selectedId;
  // Pendant un drag : valeurs LOCALES (affichage fluide), écrites au relâcher.
  int? _dragStartMin;
  int? _dragDurationMin;
  double _dragAccum = 0;

  bool get _isToday {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return widget.date == today;
  }

  @override
  void initState() {
    super.initState();
    _sub = _sync.streamDailySchedule(widget.date).listen((s) {
      if (mounted) {
        setState(() => _schedule = s);
        if (_isToday) widget.logic.todayBlocks = s?.blocks ?? [];
      }
    });
    if (_isToday) {
      _nowTick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _nowTick?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  int _toMin(String hm) =>
      (int.tryParse(hm.substring(0, 2)) ?? 0) * 60 +
      (int.tryParse(hm.substring(3, 5)) ?? 0);

  String _toHm(int min) {
    final m = min.clamp(0, 24 * 60 - 1);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  int _snap(int min) =>
      ((min / _snapMin).round() * _snapMin).clamp(0, 24 * 60 - _snapMin);

  Color _categoryColor(String category, ColorScheme cs) => switch (category) {
        'project' => cs.primary,
        'routine' => Colors.teal,
        'break' => Colors.orange,
        _ => cs.tertiary,
      };

  bool _editable(ScheduleBlock b) =>
      b.gcalEventId == null && b.status != 'done' && !b.isPrep;

  ScheduleBlock? get _selected {
    if (_selectedId == null) return null;
    for (final b in _schedule?.blocks ?? const <ScheduleBlock>[]) {
      if (b.id == _selectedId) return b;
    }
    return null;
  }

  /// Heure/durée AFFICHÉES : celles du drag en cours pour le bloc sélectionné.
  int _startOf(ScheduleBlock b) => b.id == _selectedId && _dragStartMin != null
      ? _dragStartMin!
      : _toMin(b.startTime);

  int _durOf(ScheduleBlock b) =>
      b.id == _selectedId && _dragDurationMin != null
          ? _dragDurationMin!
          : b.durationMin;

  /// Accumulateur de drag → nombre de pas de 15 min consommés.
  int _dragSteps(double dy) {
    _dragAccum += dy;
    final deltaMin = _dragAccum / _hourH * 60;
    if (deltaMin.abs() < _snapMin) return 0;
    final steps = (deltaMin / _snapMin).truncate();
    _dragAccum -= steps * _snapMin / 60 * _hourH;
    return steps;
  }

  // ── Écritures (déplacement/durée = LIBRES, jamais un report) ────────────────

  Future<void> _commitDrag(ScheduleBlock b) async {
    final st = _dragStartMin;
    final dur = _dragDurationMin;
    _dragStartMin = null;
    _dragDurationMin = null;
    _dragAccum = 0;
    final newStart = st != null ? _toHm(st) : null;
    if ((newStart == null || newStart == b.startTime) &&
        (dur == null || dur == b.durationMin)) {
      setState(() {});
      return;
    }
    // Optimiste — le stream confirme.
    final oldStart = b.startTime;
    if (newStart != null) b.startTime = newStart;
    if (dur != null) b.durationMin = dur;
    setState(() {});
    try {
      await _sync.updateScheduleBlockTime(widget.date, b.id,
          startTime: newStart, durationMin: dur);
      // Bloc-défi : l'alarme et les rappels suivent la nouvelle heure/durée.
      await rescheduleChallengeNotifications(
          block: b,
          date: widget.date,
          oldStartTime: oldStart,
          alarmSoundKey: widget.logic.state.alarmSound);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — le bloc reprendra sa place.')));
      }
    }
  }

  Future<void> _toggleDone(ScheduleBlock b) async {
    final to = b.status == 'done' ? 'pending' : 'done';
    b.status = to;
    setState(() => _selectedId = null);
    await _sync.updateBlockStatus(widget.date, b.id, to);
    // Défi coché → plus rien à rappeler.
    if (to == 'done') await cancelChallengeNotifications(b);
  }

  Future<void> _deleteSelected(ScheduleBlock b) async {
    setState(() => _selectedId = null);
    await _sync.updateBlockStatus(widget.date, b.id, 'deleted');
    await cancelChallengeNotifications(b);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('« ${b.title} » retiré du programme.'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _rename(ScheduleBlock b) async {
    final ctrl = TextEditingController(text: b.title);
    ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: b.title.length);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Renommer le bloc'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => Navigator.pop(d, ctrl.text.trim())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    b.title = v;
    setState(() {});
    await _sync.updateBlockTitle(widget.date, b.id, v);
  }

  // ── Édition précise heure + durée (tap sur « HH:mm · X min ») ────────────────
  //
  // Les poignées snappent à 15 min — impossible d'obtenir 20 ou 25 min au
  // doigt. Le label de la barre d'actions ouvre l'édition EXACTE : heure
  // libre (time picker) + durée fine (chips + pas de 5 min).
  Future<void> _editTime(ScheduleBlock b) async {
    var startMin = _startOf(b);
    var dur = _durOf(b);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Heure et durée — ${b.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Row(children: [
                Text('Début',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(.7))),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(
                            hour: startMin ~/ 60, minute: startMin % 60));
                    if (t != null) {
                      setSheet(() => startMin = t.hour * 60 + t.minute);
                    }
                  },
                  child: Text(_toHm(startMin),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Text('Durée',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(.7))),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: dur > 5
                      ? () => setSheet(() => dur = dur - 5)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 68,
                  child: Text('$dur min',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setSheet(() => dur = dur + 5),
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in const [5, 10, 15, 20, 25, 30, 45, 60, 90])
                  ChoiceChip(
                    label: Text('$m'),
                    visualDensity: VisualDensity.compact,
                    selected: dur == m,
                    onSelected: (_) => setSheet(() => dur = m),
                  ),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Valider'),
                ),
              ),
            ],
          ),
        );
      }),
    );
    if (ok != true) return;
    final newStart = _toHm(startMin.clamp(0, 24 * 60 - 1));
    if (newStart == b.startTime && dur == b.durationMin) return;
    final oldStart = b.startTime;
    b.startTime = newStart;
    b.durationMin = dur;
    setState(() {});
    try {
      await _sync.updateScheduleBlockTime(widget.date, b.id,
          startTime: newStart, durationMin: dur);
      // Bloc-défi : l'alarme et les rappels suivent la nouvelle heure/durée.
      await rescheduleChallengeNotifications(
          block: b,
          date: widget.date,
          oldStartTime: oldStart,
          alarmSoundKey: widget.logic.state.alarmSound);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — le bloc reprendra sa place.')));
      }
    }
  }

  // ── Ajout au créneau (appui long dans le vide) ───────────────────────────────

  Future<void> _addAt(int minute) async {
    final startMin = _snap(minute);
    final ctrl = TextEditingController();
    var duration = 30;
    // Suggestion choisie au tap → le bloc naît LIÉ (activité/routine/tâche/
    // action Gantt) ; retaper dans le champ délie.
    ScheduleSuggestion? picked;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final cs = Theme.of(ctx).colorScheme;
        final suggestions = picked == null
            ? scheduleSuggestions(ctrl.text,
                activities: widget.logic.state.activities,
                projects: widget.logic.currentProjects,
                max: 5)
            : const <ScheduleSuggestion>[];
        IconData iconOf(String kind) => switch (kind) {
              'routine' => Icons.repeat_rounded,
              'activity' => Icons.av_timer_rounded,
              'task' => Icons.rocket_launch_outlined,
              _ => Icons.check_circle_outline,
            };
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 20,
              right: 20,
              top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nouveau bloc à ${_toHm(startMin)}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'Titre (tape pour lier une routine, tâche…)'),
                onChanged: (v) => setSheet(() {
                  if (picked != null && v.trim() != picked!.title) {
                    picked = null; // retaper = délier
                  }
                }),
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
              // Ce qui existe déjà et correspond à la saisie — un tap = lié.
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final s in suggestions)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setSheet(() {
                      picked = s;
                      ctrl.text = s.title;
                      ctrl.selection = TextSelection.collapsed(
                          offset: s.title.length);
                      if (s.durationMin != null) duration = s.durationMin!;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 7),
                      child: Row(children: [
                        Icon(iconOf(s.kind),
                            size: 16, color: cs.primary.withOpacity(.8)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        Text(s.sublabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(.5))),
                      ]),
                    ),
                  ),
              ],
              if (picked != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Icon(Icons.link_rounded, size: 15, color: cs.tertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Lié — ${picked!.sublabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.tertiary)),
                    ),
                    InkWell(
                      onTap: () => setSheet(() => picked = null),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: cs.onSurface.withOpacity(.5)),
                    ),
                  ]),
                ),
              const SizedBox(height: 12),
              Text('Durée',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(.7))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in const [5, 10, 15, 20, 25, 30, 45, 60, 90, 120])
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: duration == m,
                    onSelected: (_) => setSheet(() => duration = m),
                  ),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Ajouter'),
                ),
              ),
            ],
          ),
        );
      }),
    );
    final title = ctrl.text.trim();
    if (ok != true || title.isEmpty) return;
    if (picked != null && title == picked!.title) {
      // Suggestion choisie → lien EXPLICITE vers l'objet existant.
      await _sync.addScheduleBlock(
          widget.date,
          ScheduleBlock(
            startTime: _toHm(startMin),
            durationMin: duration,
            title: title,
            category: picked!.category,
            activityId: picked!.activityId,
            projectId: picked!.projectId,
            taskId: picked!.taskId,
            actionId: picked!.actionId,
          ));
      return;
    }
    // Lien routine par titre — même règle déterministe que partout : match
    // UNIQUE, sinon pas de lien deviné.
    final matched = routineForBlockTitle(title, widget.logic.state.activities);
    await _sync.addScheduleBlock(
        widget.date,
        ScheduleBlock(
          startTime: _toHm(startMin),
          durationMin: duration,
          title: title,
          category: matched != null ? 'routine' : 'personal',
          activityId: matched?.id,
        ));
  }

  // ── Couche « réalisé » : sessions loggées du jour ────────────────────────────

  /// Sessions du jour affiché (terminées + chrono en cours), bornées à la
  /// journée. Le réel MESURÉ, jamais estimé — une session sur une activité
  /// supprimée disparaît avec elle.
  List<({int start, int end, String title, Color color, bool running})>
      _daySessions(DateTime now) {
    final p = widget.date.split('-');
    final y = int.tryParse(p[0]);
    final mo = p.length > 1 ? int.tryParse(p[1]) : null;
    final da = p.length > 2 ? int.tryParse(p[2]) : null;
    if (y == null || mo == null || da == null) return const [];
    final day = DateTime(y, mo, da);
    final dayEnd = day.add(const Duration(days: 1));

    final out =
        <({int start, int end, String title, Color color, bool running})>[];
    for (final s in widget.logic.state.sessions) {
      final running = s.endAt == null;
      final end = s.endAt ?? now;
      if (running && !_isToday) continue;
      if (!end.isAfter(day) || !s.startAt.isBefore(dayEnd)) continue;
      Activity? a;
      for (final x in widget.logic.state.activities) {
        if (x.id == s.activityId) { a = x; break; }
      }
      if (a == null || a.deleted) continue;
      final startMin =
          s.startAt.isBefore(day) ? 0 : s.startAt.difference(day).inMinutes;
      final endMin =
          end.isAfter(dayEnd) ? 1440 : end.difference(day).inMinutes;
      if (endMin - startMin < 1) continue;
      out.add((
        start: startMin,
        end: endMin,
        title: a.name,
        color: domainColor(a.domainId, widget.logic.state.activeDomains) ??
            Colors.teal,
        running: running,
      ));
    }
    return out;
  }

  Widget _sessionWidget(
    ColorScheme cs,
    ({int start, int end, String title, Color color, bool running}) s,
  ) {
    final top = s.start / 60 * _hourH + 6;
    final height =
        ((s.end - s.start) / 60 * _hourH).clamp(3.0, 24 * _hourH);
    return Positioned(
      top: top,
      left: _leftGutter + 2,
      right: 2,
      height: height,
      child: IgnorePointer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: s.color.withOpacity(.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Container(
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 6, top: 1),
                decoration: BoxDecoration(
                  color: s.color.withOpacity(.09),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: height >= 15
                    ? Text(
                        '⏱ ${s.title}${s.running ? ' · en cours' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withOpacity(.45),
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Layout : clusters de blocs qui se chevauchent → colonnes ─────────────────

  /// Durée d'ENCOMBREMENT visuel : un bloc court est dessiné à la hauteur
  /// plancher (_minBlockH) — pour le layout il « occupe » donc au moins ces
  /// minutes-là, sinon il repeindrait le bloc suivant (Hygiène 20:00-20:10
  /// par-dessus Lecture 20:15).
  int _footprintOf(ScheduleBlock b) {
    final minMin = (_minBlockH / _hourH * 60).ceil();
    final d = _durOf(b);
    return d < minMin ? minMin : d;
  }

  List<({ScheduleBlock b, int col, int cols})> _layout(
      List<ScheduleBlock> blocks) {
    final sorted = [...blocks]
      ..sort((a, b) => _startOf(a).compareTo(_startOf(b)));
    final out = <({ScheduleBlock b, int col, int cols})>[];
    var i = 0;
    while (i < sorted.length) {
      final cluster = <ScheduleBlock>[sorted[i]];
      var clusterEnd = _startOf(sorted[i]) + _footprintOf(sorted[i]);
      var j = i + 1;
      while (j < sorted.length && _startOf(sorted[j]) < clusterEnd) {
        cluster.add(sorted[j]);
        final e = _startOf(sorted[j]) + _footprintOf(sorted[j]);
        if (e > clusterEnd) clusterEnd = e;
        j++;
      }
      final colEnds = <int>[];
      final cols = <ScheduleBlock, int>{};
      for (final b in cluster) {
        var placed = false;
        for (var c = 0; c < colEnds.length; c++) {
          if (_startOf(b) >= colEnds[c]) {
            cols[b] = c;
            colEnds[c] = _startOf(b) + _footprintOf(b);
            placed = true;
            break;
          }
        }
        if (!placed) {
          cols[b] = colEnds.length;
          colEnds.add(_startOf(b) + _footprintOf(b));
        }
      }
      for (final b in cluster) {
        out.add((b: b, col: cols[b]!, cols: colEnds.length));
      }
      i = j;
    }
    return out;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blocks = (_schedule?.blocks ?? const <ScheduleBlock>[])
        .where((b) => b.status != 'deleted' && b.status != 'skipped')
        .toList();
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    // Auto-scroll vers « maintenant » à la première ouverture du jour.
    if (_isToday && !_scrolledToNow && _schedule != null) {
      _scrolledToNow = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _nowKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              alignment: .35, duration: const Duration(milliseconds: 300));
        }
      });
    }

    final laid = _layout(blocks);
    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (blocks.length < 3)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ActionChip(
              avatar: const Icon(Icons.auto_awesome, size: 16),
              label: Text(blocks.isEmpty
                  ? '✨ Proposer un programme'
                  : '✨ Étoffer ma journée'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlanDayScreen(
                      logic: widget.logic,
                      targetDate: widget.date,
                      rattrapage: _isToday,
                      onLaunchBlock: widget.onLaunch))),
            ),
          ),
        Text(
          'Appui long dans le vide : ajouter · tap sur un bloc : ajuster',
          style: TextStyle(
              fontSize: 11, color: cs.onSurface.withOpacity(.4)),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, constraints) {
          final laneW = constraints.maxWidth - _leftGutter - 6;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selectedId = null),
            onLongPressStart: (d) {
              final min = ((d.localPosition.dy - 6) / _hourH * 60).round();
              _addAt(min.clamp(0, 24 * 60 - _snapMin));
            },
            child: SizedBox(
              height: 24 * _hourH + 12,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Grille des heures.
                  for (var h = 0; h < 24; h++) ...[
                    Positioned(
                      top: h * _hourH,
                      left: 0,
                      child: SizedBox(
                        width: _leftGutter - 8,
                        child: Text('${h.toString().padLeft(2, '0')}:00',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 10.5,
                                color: cs.onSurface.withOpacity(.35))),
                      ),
                    ),
                    Positioned(
                      top: h * _hourH + 6,
                      left: _leftGutter,
                      right: 0,
                      child: Container(
                          height: 1, color: cs.onSurface.withOpacity(.08)),
                    ),
                  ],
                  // ── Couche « réalisé » : les sessions LOGGUÉES du jour
                  // (dont le chrono en cours) en sous-couche translucide —
                  // le prévu se compare au réel d'un coup d'œil, même quand
                  // rien n'était programmé. Lecture seule, sous les blocs.
                  for (final s in _daySessions(now)) _sessionWidget(cs, s),
                  // Blocs (le sélectionné en dernier = au-dessus).
                  for (final e in laid.where((e) => e.b.id != _selectedId))
                    _blockWidget(cs, e, laneW),
                  for (final e in laid.where((e) => e.b.id == _selectedId))
                    _blockWidget(cs, e, laneW),
                  // Trait « maintenant ».
                  if (_isToday)
                    Positioned(
                      key: _nowKey,
                      top: nowMin / 60 * _hourH + 5,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                                color: _red,
                                borderRadius: BorderRadius.circular(999)),
                            child: Text(_toHm(nowMin),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                          Expanded(
                              child: Container(height: 2, color: _red)),
                        ]),
                      ),
                    ),
                  // Barre d'actions du bloc sélectionné — au niveau timeline
                  // (hors des limites du bloc, sinon intouchable).
                  if (selected != null) _actionBarPositioned(cs, selected),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _blockWidget(
      ColorScheme cs, ({ScheduleBlock b, int col, int cols}) e, double laneW) {
    final b = e.b;
    final isSel = b.id == _selectedId;
    final start = _startOf(b);
    final dur = _durOf(b);
    final isDone = b.status == 'done';
    final isMirror = b.gcalEventId != null;
    final color = isMirror
        ? Colors.blueGrey
        : b.challenge
            ? const Color(0xFFB8860B)
            : _categoryColor(b.category, cs);

    final top = start / 60 * _hourH + 6;
    final height = (dur / 60 * _hourH).clamp(_minBlockH, 24 * _hourH);
    final colW = laneW / e.cols;
    final left = _leftGutter + 2 + e.col * colW;

    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _selectedId = isSel ? null : b.id;
        _dragStartMin = null;
        _dragDurationMin = null;
        _dragAccum = 0;
      }),
      onLongPress: () => setState(() => _selectedId = b.id),
      // Glisser le corps = déplacer l'heure (bloc sélectionné éditable).
      onVerticalDragUpdate: isSel && _editable(b)
          ? (d) {
              final steps = _dragSteps(d.delta.dy);
              if (steps == 0) return;
              setState(() {
                _dragStartMin =
                    ((_dragStartMin ?? _toMin(b.startTime)) + steps * _snapMin)
                        .clamp(0, 24 * 60 - _durOf(b));
              });
            }
          : null,
      onVerticalDragEnd: isSel && _editable(b) ? (_) => _commitDrag(b) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(isDone
              ? .10
              : isSel
                  ? .38
                  : .20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: color.withOpacity(isSel ? 1 : .5),
              width: isSel ? 1.6 : 1),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            '${isDone ? '✓ ' : ''}${b.challenge ? '🔥 ' : ''}${b.title}'
            '${isMirror ? ' · Agenda' : ''}',
            maxLines: height > 40 ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              decoration: isDone ? TextDecoration.lineThrough : null,
              color: cs.onSurface.withOpacity(isDone ? .45 : .95),
            ),
          ),
        ),
      ),
    );

    return Positioned(
      top: top,
      left: left,
      width: colW - 4,
      height: height,
      child: !isSel || !_editable(b)
          ? body
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: body),
                // Poignée HAUT — change le début (la fin ne bouge pas).
                Positioned(top: -12, right: 10, child: _handle(color, (dy) {
                  final steps = _dragSteps(dy);
                  if (steps == 0) return;
                  setState(() {
                    final st0 = _dragStartMin ?? _toMin(b.startTime);
                    final dur0 = _dragDurationMin ?? b.durationMin;
                    final newSt = (st0 + steps * _snapMin)
                        .clamp(0, st0 + dur0 - _snapMin);
                    _dragDurationMin = dur0 + (st0 - newSt);
                    _dragStartMin = newSt;
                  });
                }, () => _commitDrag(b))),
                // Poignée BAS — change la durée.
                Positioned(bottom: -12, left: 10, child: _handle(color, (dy) {
                  final steps = _dragSteps(dy);
                  if (steps == 0) return;
                  setState(() {
                    _dragDurationMin =
                        ((_dragDurationMin ?? b.durationMin) +
                                steps * _snapMin)
                            .clamp(_snapMin, 24 * 60);
                  });
                }, () => _commitDrag(b))),
              ],
            ),
    );
  }

  Widget _handle(
          Color color, void Function(double dy) onDy, VoidCallback onEnd) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => onDy(d.delta.dy),
        onVerticalDragEnd: (_) => onEnd(),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 3),
              ),
            ),
          ),
        ),
      );

  /// Barre d'actions du bloc sélectionné, posée SOUS lui au niveau timeline
  /// (au-dessus si le bloc touche le bas de la journée).
  Widget _actionBarPositioned(ColorScheme cs, ScheduleBlock b) {
    final start = _startOf(b);
    final dur = _durOf(b);
    final blockH = (dur / 60 * _hourH).clamp(_minBlockH, 24 * _hourH);
    final below = start / 60 * _hourH + 6 + blockH + 16;
    final fitsBelow = below < 24 * _hourH - 44;
    final top = fitsBelow ? below : start / 60 * _hourH + 6 - 52;
    final isMirror = b.gcalEventId != null;

    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
          iconSize: 18,
          onPressed: onTap,
          icon: Icon(icon),
        );

    return Positioned(
      top: top,
      left: _leftGutter,
      right: 0,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: cs.surfaceContainerHighest,
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: isMirror
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('${_toHm(start)} · $dur min',
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                    btn(
                        b.status == 'done'
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        'Fait',
                        () => _toggleDone(b)),
                    const Padding(
                      padding: EdgeInsets.only(left: 2, right: 6),
                      child: Text('RDV Google — se modifie dans l\'agenda',
                          style: TextStyle(fontSize: 10.5)),
                    ),
                  ])
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    // Tap sur le label → édition EXACTE heure + durée (les
                    // poignées snappent à 15 min, ici tout est libre).
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _editable(b) ? () => _editTime(b) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('${_toHm(start)} · $dur min',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800)),
                          if (_editable(b)) ...[
                            const SizedBox(width: 3),
                            Icon(Icons.edit_outlined,
                                size: 12,
                                color: cs.onSurface.withOpacity(.55)),
                          ],
                        ]),
                      ),
                    ),
                    btn(
                        b.status == 'done'
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        'Fait',
                        () => _toggleDone(b)),
                    if (_isToday &&
                        widget.onLaunch != null &&
                        (b.activityId != null || b.projectId != null))
                      btn(Icons.play_arrow_rounded, 'Lancer', () {
                        setState(() => _selectedId = null);
                        widget.onLaunch!(b);
                      }),
                    if (widget.onOpenSource != null &&
                        (b.activityId != null || b.projectId != null))
                      btn(Icons.open_in_new_rounded, 'Fiche',
                          () => widget.onOpenSource!(b)),
                    btn(Icons.edit_outlined, 'Renommer', () => _rename(b)),
                    if (_isToday)
                      btn(Icons.tune_rounded, 'Renégocier', () {
                        setState(() => _selectedId = null);
                        showRenegotiateSheet(context,
                            logic: widget.logic,
                            block: b,
                            date: widget.date,
                            onLaunch: widget.onLaunch);
                      }),
                    btn(Icons.delete_outline, 'Retirer',
                        () => _deleteSelected(b)),
                  ]),
          ),
        ),
      ),
    );
  }
}
