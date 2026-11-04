import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/workouts.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/sport_sheet.dart' show kSportAccent;
import 'package:productivitwo_v1/widgets/workout_screens.dart' show showExerciseEditor, showWorkoutPlayer;

// Séances de muscu, lot 3 (maquette validée « Séances de muscu », 2026-11-04) : Mes séances (semaine, mois),
// une séance passée, la fiche d'un exercice. Logique pure dans `utils/workouts.dart`.

const _ink = Color(0xFF1D0F08);
const _green = Color(0xFF4CAF7D);
const _amber = Color(0xFFE0A24A);
const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _daysLong = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _monthsLong = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _short(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : '${_days[d.weekday - 1]} ${d.day}';
}

String _hm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _dur(int min) => min < 60 ? '$min min' : '${min ~/ 60} h${min % 60 == 0 ? '' : ' ${(min % 60).toString().padLeft(2, '0')}'}';

Color _deltaColor(DeltaKind? k, Color mute) => switch (k) {
      DeltaKind.better => _green,
      DeltaKind.worse => _amber,
      _ => mute,
    };

Widget _label(String t, Color c) => Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: c));

Widget _stat(ColorScheme cs, String label, String value, String? sub, {Color? subColor}) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.onSurface.withValues(alpha: .6))),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          if (sub != null)
            Text(sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: subColor ?? cs.onSurface.withValues(alpha: .6))),
        ]),
      ),
    );

// ── Mes séances ──────────────────────────────────────────────────────────────

Future<void> showWorkoutsSheet(BuildContext context, {required AppLogic logic}) =>
    showFiche<void>(context, builder: (ctx, scroll) => WorkoutsView(logic: logic, scroll: scroll));

class WorkoutsView extends StatefulWidget {
  final AppLogic logic;
  final ScrollController? scroll;
  const WorkoutsView({super.key, required this.logic, this.scroll});

  @override
  State<WorkoutsView> createState() => _WorkoutsViewState();
}

class _WorkoutsViewState extends State<WorkoutsView> {
  AppLogic get logic => widget.logic;
  bool _month = false;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final today = DateTime.parse(logic.livedTodayYmd);
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final weekDays = [for (var i = 0; i < 7; i++) _ymd(DateTime(monday.year, monday.month, monday.day + i))];
    final all = liveWorkouts(logic.workouts);
    final week = workoutsBetween(all, weekDays.first, weekDays.last);
    final prevWeek = workoutsBetween(all, _ymd(DateTime(monday.year, monday.month, monday.day - 7)), _ymd(DateTime(monday.year, monday.month, monday.day - 1)));
    final monthFrom = _ymd(DateTime(today.year, today.month, 1));
    final monthTo = _ymd(DateTime(today.year, today.month + 1, 0));
    final month = workoutsBetween(all, monthFrom, monthTo);
    final prevMonth = workoutsBetween(all, _ymd(DateTime(today.year, today.month - 1, 1)), _ymd(DateTime(today.year, today.month, 0)));
    final cur = periodSummary(_month ? month : week);
    final prev = periodSummary(_month ? prevMonth : prevWeek);
    final title = '${cur.count} séance${cur.count > 1 ? 's' : ''} ${_month ? 'ce mois-ci' : 'cette semaine'}';
    final sub = [
      if (cur.minutes > 0) _dur(cur.minutes),
      if (cur.volume > 0) '${volumeLabel(cur.volume)} soulevés',
      '${_month ? 'mois dernier' : 'semaine dernière'} : ${prev.count} séance${prev.count > 1 ? 's' : ''}',
    ].join(' · ');
    final recent = all.reversed.take(12).toList();
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      _label('SPORT · MES SÉANCES', kSportAccent),
      Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      Text(sub, style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 12),
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('Semaine')), ButtonSegment(value: true, label: Text('Mois'))],
        selected: {_month},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _month = v.first),
      ),
      const SizedBox(height: 12),
      if (!_month) _weekGrid(cs, weekDays, week) else _monthView(cs, today, month),
      const SizedBox(height: 16),
      _label('DERNIÈRES SÉANCES', mute),
      const SizedBox(height: 6),
      if (recent.isEmpty) Text('Pas encore de séance enregistrée.', style: TextStyle(color: mute)),
      for (final w in recent) _workoutRow(cs, w, all),
    ]);
  }

  Widget _weekGrid(ColorScheme cs, List<String> days, List<Workout> week) {
    final mute = cs.onSurface.withValues(alpha: .6);
    final today = logic.livedTodayYmd;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, d) in days.indexed) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: Column(children: [
            Text('LMMJVSD'[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: d == today ? kSportAccent : mute)),
            const SizedBox(height: 4),
            Container(
              height: 64,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(10),
                border: d == today ? Border.all(color: kSportAccent, width: 1.5) : null,
              ),
              child: Column(children: [
                for (final w in week.where((w) => w.ymd == d).take(2))
                  Expanded(
                    child: InkWell(
                      onTap: () => showWorkoutDetail(context, logic: logic, workout: w),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: kSportAccent, borderRadius: BorderRadius.circular(6)),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(w.name.split(' ').first, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _ink)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ],
    ]);
  }

  Widget _monthView(ColorScheme cs, DateTime today, List<Workout> month) {
    final mute = cs.onSurface.withValues(alpha: .6);
    final first = DateTime(today.year, today.month, 1);
    final nDays = DateTime(today.year, today.month + 1, 0).day;
    final lead = first.weekday - 1;
    final byDay = <String, int>{};
    for (final w in month) {
      byDay[w.ymd] = (byDay[w.ymd] ?? 0) + 1;
    }
    final counts = countByName(month);
    final maxC = counts.isEmpty ? 1 : counts.first.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('CE MOIS-CI · ${_monthsLong[today.month - 1].toUpperCase()}', mute),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.4,
        children: [
          for (var i = 0; i < lead; i++) const SizedBox.shrink(),
          for (var d = 1; d <= nDays; d++)
            () {
              final y = _ymd(DateTime(today.year, today.month, d));
              final n = byDay[y] ?? 0;
              return Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: n > 0 ? kSportAccent : cs.surfaceContainerHighest.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(6),
                  border: y == logic.livedTodayYmd ? Border.all(color: cs.onSurface.withValues(alpha: .8), width: 1.2) : null,
                ),
                child: Text('$d', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: n > 0 ? _ink : mute)),
              );
            }(),
        ],
      ),
      const SizedBox(height: 10),
      for (final e in counts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
                width: 120,
                child: Text('${e.key} · ${e.value}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: e.value / maxC, minHeight: 8, color: kSportAccent, backgroundColor: cs.surfaceContainerHighest),
              ),
            ),
          ]),
        ),
    ]);
  }

  Widget _workoutRow(ColorScheme cs, Workout w, List<Workout> all) {
    final mute = cs.onSurface.withValues(alpha: .6);
    final sum = summarize(w, all);
    final exos = {for (final s in w.sets) s.exerciseId}.length;
    final pct = sum.volumeDeltaPct;
    return Card(
      key: ValueKey('workout-${w.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showWorkoutDetail(context, logic: logic, workout: w),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${w.name} · ${_short(w.ymd)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [_dur(sum.durationMin), '$exos exo${exos > 1 ? 's' : ''}', '${sum.sets} séries', if (sum.volume > 0) volumeLabel(sum.volume)].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: mute),
                ),
              ]),
            ),
            if (pct != null)
              Text(pct == 0 ? 'pareil' : '${pct > 0 ? '+' : ''}$pct %',
                  style: TextStyle(fontWeight: FontWeight.w800, color: pct > 0 ? _green : (pct < 0 ? _amber : mute))),
          ]),
        ),
      ),
    );
  }
}

// ── Une séance passée ────────────────────────────────────────────────────────

Future<void> showWorkoutDetail(BuildContext context, {required AppLogic logic, required Workout workout}) =>
    showFiche<void>(context, builder: (ctx, scroll) => WorkoutDetail(logic: logic, workout: workout, scroll: scroll));

class WorkoutDetail extends StatelessWidget {
  final AppLogic logic;
  final Workout workout;
  final ScrollController? scroll;
  const WorkoutDetail({super.key, required this.logic, required this.workout, this.scroll});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final w = workout;
    final all = liveWorkouts(logic.workouts);
    final sum = summarize(w, all);
    final prev = w.templateId == null ? null : lastWorkoutOf(w.templateId!, all, beforeMs: w.startAt);
    final d = DateTime.tryParse(w.ymd);
    final order = <String>[];
    for (final s in w.sets) {
      if (!order.contains(s.exerciseId)) order.add(s.exerciseId);
    }
    final recordNames = <String>[
      for (final id in order)
        if (bestSet(w.sets.where((s) => s.exerciseId == id)) case final b? when isRecord(b, all, beforeMs: w.startAt))
          (logic.gym.exercises[id]?.name ?? 'Exercice').split(' ').last.toLowerCase(),
    ];
    final repsDelta = prev == null ? null : sum.reps - repsOf(prev.sets);
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      _label(
          'SÉANCE · ${d == null ? w.ymd : '${_daysLong[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}'.toUpperCase()} · ${_hm(w.startAt)}${w.endAt == null ? '' : ' → ${_hm(w.endAt!)}'}',
          kSportAccent),
      Text(w.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      Text(
        [
          _dur(sum.durationMin),
          '${order.length} exercice${order.length > 1 ? 's' : ''}',
          '${sum.sets} séries',
          if (sum.avgRest != null) 'repos moyen ${restLabel(sum.avgRest!)}',
          if (w.place != null) w.place!,
        ].join(' · '),
        style: TextStyle(fontSize: 13, color: mute),
      ),
      const SizedBox(height: 12),
      Row(children: [
        _stat(cs, 'VOLUME', sum.volume > 0 ? volumeLabel(sum.volume) : '—',
            sum.volumeDeltaPct == null ? null : '${sum.volumeDeltaPct! >= 0 ? '+' : ''}${sum.volumeDeltaPct} % vs ${_short(prev!.ymd).split(' ').first}',
            subColor: (sum.volumeDeltaPct ?? 0) >= 0 ? _green : _amber),
        const SizedBox(width: 8),
        _stat(cs, 'RÉPÉTITIONS', '${sum.reps}', repsDelta == null ? null : (repsDelta == 0 ? 'pareil' : '${repsDelta > 0 ? '+' : ''}$repsDelta'),
            subColor: (repsDelta ?? 0) >= 0 ? _green : _amber),
        const SizedBox(width: 8),
        _stat(cs, 'RECORDS', '${sum.records}', recordNames.isEmpty ? null : recordNames.join(', '), subColor: kSportAccent),
      ]),
      const SizedBox(height: 14),
      _label('LE CONTENU · SÉRIE PAR SÉRIE', mute),
      const SizedBox(height: 6),
      for (final id in order)
        () {
          final sets = w.sets.where((s) => s.exerciseId == id).toList();
          final delta = sum.byExercise[id];
          final best = bestSet(sets);
          final rec = best != null && isRecord(best, all, beforeMs: w.startAt);
          final rest = avgRestSec(sets);
          final vol = volumeOf(sets);
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showExerciseFiche(context, logic: logic, exerciseId: id),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(logic.gym.exercises[id]?.name ?? 'Exercice', style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text(rec ? 'RECORD' : (delta?.kind == DeltaKind.first ? '' : (delta?.label ?? '')),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: rec ? kSportAccent : _deltaColor(delta?.kind, mute))),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in sets)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .6), borderRadius: BorderRadius.circular(8)),
                        child: Text(setLabel(s).replaceAll(' kg', ''), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  if (rest != null || vol > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text([if (rest != null) 'repos ${restLabel(rest)}', if (vol > 0) volumeLabel(vol)].join(' · '),
                          style: TextStyle(fontSize: 12, color: mute)),
                    ),
                ]),
              ),
            ),
          );
        }(),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('workout-redo'),
        style: FilledButton.styleFrom(backgroundColor: kSportAccent, foregroundColor: _ink, minimumSize: const Size.fromHeight(52)),
        onPressed: () async {
          final items =
              w.templateId != null && logic.gym.templates[w.templateId]?.deleted == false ? logic.gym.templates[w.templateId]!.items : itemsFromWorkout(w);
          final t = w.templateId == null ? null : logic.gym.templates[w.templateId];
          Navigator.of(context).pop();
          await showWorkoutPlayer(context,
              logic: logic, items: items.where((i) => logic.gym.exercises[i.exerciseId] != null).toList(), template: t?.deleted == false ? t : null);
        },
        child: const Text('Refaire cette séance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
    ]);
  }
}

// ── La fiche d'un exercice ───────────────────────────────────────────────────

Future<void> showExerciseFiche(BuildContext context, {required AppLogic logic, required String exerciseId}) =>
    showFiche<void>(context, builder: (ctx, scroll) => ExerciseFiche(logic: logic, exerciseId: exerciseId, scroll: scroll));

class ExerciseFiche extends StatefulWidget {
  final AppLogic logic;
  final String exerciseId;
  final ScrollController? scroll;
  const ExerciseFiche({super.key, required this.logic, required this.exerciseId, this.scroll});

  @override
  State<ExerciseFiche> createState() => _ExerciseFicheState();
}

class _ExerciseFicheState extends State<ExerciseFiche> {
  AppLogic get logic => widget.logic;
  ExerciseCurve? _curve;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final e = logic.gym.exercises[widget.exerciseId] ?? Exercise(id: widget.exerciseId, name: 'Exercice');
    final hist = exerciseHistory(e.id, logic.workouts);
    final all = [for (final x in hist) ...x.sets];
    final best = bestSet(all);
    final bestAt = best == null ? null : hist.lastWhere((x) => x.sets.contains(best));
    final kinds = switch (e.kind) {
      ExerciseKind.weight => const [ExerciseCurve.weight, ExerciseCurve.volume, ExerciseCurve.reps, ExerciseCurve.rest],
      _ => const [ExerciseCurve.reps, ExerciseCurve.rest],
    };
    final curve = _curve != null && kinds.contains(_curve) ? _curve! : kinds.first;
    final first = hist.isEmpty ? null : hist.first;
    final last = hist.isEmpty ? null : hist.last;
    final before = hist.length >= 2 ? hist[hist.length - 2] : null;
    String since() {
      final d = first == null ? null : DateTime.tryParse(first.workout.ymd);
      return d == null ? '' : ' depuis le ${d.day == 1 ? '1er' : d.day} ${_months[d.month - 1]}';
    }

    final kindLabel = switch (e.kind) {
      ExerciseKind.weight => 'avec poids',
      ExerciseKind.bodyweight => 'poids du corps',
      ExerciseKind.duration => 'durée',
    };
    final volPct =
        last != null && before != null && before.volume > 0 && last.volume > 0 ? ((last.volume - before.volume) / before.volume * 100).round() : null;
    final firstKg = first?.topKg, bestKg = hist.map((x) => x.topKg).whereType<double>().fold<double?>(null, (m, x) => m == null || x > m ? x : m);
    final firstReps = first == null ? null : (first.reps > 0 ? first.reps : first.seconds);
    final lastReps = last == null ? null : (last.reps > 0 ? last.reps : last.seconds);
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      _label(['EXERCICE', if (e.gear?.isNotEmpty == true) e.gear!.toUpperCase(), kindLabel.toUpperCase()].join(' · '), kSportAccent),
      Text(e.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      Text('${hist.length} séance${hist.length > 1 ? 's' : ''}${since()} · repos réglé ${restLabel(e.restSec)}', style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 12),
      if (hist.isEmpty)
        Text('Pas encore fait. Il apparaîtra ici dès ta première série.', style: TextStyle(color: mute))
      else ...[
        Row(children: [
          _stat(cs, 'RECORD', best == null ? '—' : setLabel(best).split(' × ').last,
              best == null ? null : [if (best.weightKg != null) '× ${best.reps}', _short(bestAt!.workout.ymd)].join(' · ')),
          const SizedBox(width: 8),
          if (e.kind == ExerciseKind.weight && firstKg != null && bestKg != null)
            _stat(cs, 'DEPUIS LE DÉBUT', '${bestKg >= firstKg ? '+' : '−'}${kgLabel((bestKg - firstKg).abs())} kg', '${kgLabel(firstKg)} → ${kgLabel(bestKg)}',
                subColor: bestKg > firstKg ? _green : mute)
          else
            _stat(cs, 'DEPUIS LE DÉBUT', lastReps != null && firstReps != null ? '${lastReps - firstReps >= 0 ? '+' : ''}${lastReps - firstReps}' : '—',
                firstReps == null ? null : '$firstReps → $lastReps',
                subColor: (lastReps ?? 0) > (firstReps ?? 0) ? _green : mute),
          const SizedBox(width: 8),
          _stat(cs, e.kind == ExerciseKind.weight ? 'VOLUME' : 'DERNIÈRE', e.kind == ExerciseKind.weight ? volumeLabel(last!.volume) : setsLine(last!.sets),
              volPct == null ? null : '${volPct >= 0 ? '+' : ''}$volPct %',
              subColor: (volPct ?? 0) >= 0 ? _green : _amber),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<ExerciseCurve>(
          segments: [
            for (final k in kinds)
              ButtonSegment(
                value: k,
                label: Text(switch (k) {
                  ExerciseCurve.weight => 'Poids',
                  ExerciseCurve.volume => 'Volume',
                  ExerciseCurve.reps => e.kind == ExerciseKind.duration ? 'Secondes' : 'Reps',
                  ExerciseCurve.rest => 'Repos',
                }),
              ),
          ],
          selected: {curve},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _curve = v.first),
        ),
        const SizedBox(height: 8),
        _curveChart(cs, hist, curve),
        const SizedBox(height: 14),
        _label('DERNIÈRES SÉANCES', mute),
        const SizedBox(height: 4),
        for (final x in hist.reversed.take(8))
          InkWell(
            onTap: () => showWorkoutDetail(context, logic: logic, workout: x.workout),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 64, child: Text(x.workout.ymd == logic.livedTodayYmd ? 'auj.' : _short(x.workout.ymd), style: TextStyle(color: mute))),
                Expanded(child: Text(setsLine(x.sets), style: const TextStyle(fontWeight: FontWeight.w700))),
                if (x.avgRest != null) Text(restLabel(x.avgRest!), style: TextStyle(color: mute)),
              ]),
            ),
          ),
        Text('la colonne de droite = repos moyen réellement pris entre deux séries', style: TextStyle(fontSize: 12, color: mute)),
      ],
      const SizedBox(height: 10),
      OutlinedButton(
        key: const ValueKey('exercise-settings'),
        onPressed: () => showExerciseEditor(context, logic: logic, exercise: e),
        child: const Text('Réglages · repos, pas de poids'),
      ),
    ]);
  }

  Widget _curveChart(ColorScheme cs, List<ExerciseSession> hist, ExerciseCurve curve) {
    final pts = [for (final x in hist) curveValue(x, curve)].whereType<double>().toList();
    final mute = cs.onSurface.withValues(alpha: .6);
    String fmt(double v) => switch (curve) {
          ExerciseCurve.weight => '${kgLabel(v)} kg',
          ExerciseCurve.volume => volumeLabel(v),
          ExerciseCurve.rest => restLabel(v.round()),
          ExerciseCurve.reps => '${v.round()}',
        };
    if (pts.length < 2) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: Text(pts.isEmpty ? 'Rien à tracer.' : 'La courbe apparaît dès la deuxième séance.', style: TextStyle(color: mute)),
      );
    }
    final lo = pts.reduce((a, b) => a < b ? a : b), hi = pts.reduce((a, b) => a > b ? a : b);
    final firstYmd = hist.first.workout.ymd;
    final d = DateTime.tryParse(firstYmd);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: SizedBox(height: 120, child: CustomPaint(painter: _CurvePainter(pts, kSportAccent, cs.onSurface)))),
        const SizedBox(width: 6),
        SizedBox(
          height: 120,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(fmt(hi), style: TextStyle(fontSize: 11, color: mute)),
            Text(fmt(lo), style: TextStyle(fontSize: 11, color: mute)),
          ]),
        ),
      ]),
      Row(children: [
        Text(d == null ? firstYmd : '${d.day == 1 ? '1er' : d.day} ${_months[d.month - 1]}', style: TextStyle(fontSize: 11, color: mute)),
        const Spacer(),
        Text('dernière', style: TextStyle(fontSize: 11, color: mute)),
      ]),
    ]);
  }
}

class _CurvePainter extends CustomPainter {
  final List<double> pts;
  final Color color;
  final Color ink;
  _CurvePainter(this.pts, this.color, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    var lo = pts.reduce((a, b) => a < b ? a : b), hi = pts.reduce((a, b) => a > b ? a : b);
    if ((hi - lo).abs() < 1e-6) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * .1;
    lo -= pad;
    hi += pad;
    double x(int i) => i / (pts.length - 1) * size.width;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    final grid = Paint()..color = ink.withValues(alpha: .08);
    for (var k = 0; k <= 2; k++) {
      canvas.drawLine(Offset(0, size.height * k / 2), Offset(size.width, size.height * k / 2), grid);
    }
    final path = Path()..moveTo(x(0), y(pts[0]));
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(x(i), y(pts[i]));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < pts.length; i++) {
      canvas.drawCircle(Offset(x(i), y(pts[i])), i == pts.length - 1 ? 4.5 : 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.pts != pts || old.color != color;
}
