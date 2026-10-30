import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/coups.dart' show coupLabel;
import 'package:productivitwo_v1/widgets/status_row.dart' show StateChip;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/widgets/badge_lines.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show ymdDashOf;
import 'package:productivitwo_v1/utils/objective_trajectory.dart';
import 'package:productivitwo_v1/widgets/objective_edit_sheet.dart';

const _accent = Color(0xFF00897B);
const _good = Color(0xFF43A047);
const _warn = Color(0xFFEF6C00);

/// Fiche d'un objectif (mobile) : jauge hebdo des engagements, MOYENS
/// (temps cumulé vs attendu à ce jour) et RÉSULTAT (relevés de la métrique vs
/// ligne « où je devrais en être »), « Noter un relevé ». Retourne true si
/// l'objectif a changé (relevé, édition, statut).
Future<bool> showObjectiveTrajectorySheet(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  required StrategicObjective objective,
  required List<Project> projects,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TrajectorySheet(logic: logic, sync: sync, objective: objective, projects: projects),
  );
  return changed ?? false;
}

class _TrajectorySheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final StrategicObjective objective;
  final List<Project> projects;
  const _TrajectorySheet({required this.logic, required this.sync, required this.objective, required this.projects});

  @override
  State<_TrajectorySheet> createState() => _TrajectorySheetState();
}

class _TrajectorySheetState extends State<_TrajectorySheet> {
  late StrategicObjective o;
  List<Session>? _sessions; // historique depuis le début (sinon l'état local)
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    o = widget.objective;
    _loadSessions();
    _refreshObjective();
  }

  /// L'objectif reçu peut venir d'une liste en cache, alors qu'un relevé vient
  /// d'être noté ailleurs (Ta journée, fiche Objectifs) : on relit la version
  /// en base et on la prend si elle est plus récente (2026-10-30, retour user :
  /// le graphe ne montrait le relevé du jour qu'après une relance de l'app).
  Future<void> _refreshObjective() async {
    try {
      final all = await widget.sync.fetchStrategicObjectives();
      final fresh = all.where((x) => x.id == o.id).firstOrNull;
      if (fresh == null || !mounted) return;
      final newer = (fresh.updatedAt ?? fresh.createdAt).isAfter(o.updatedAt ?? o.createdAt) || fresh.readings.length != o.readings.length;
      if (newer) setState(() => o = fresh);
    } catch (_) {}
  }

  /// L'état local ne garde pas forcément tout l'historique : on relit les
  /// sessions depuis le début de l'objectif (borné à un an).
  Future<void> _loadSessions() async {
    final days = DateTime.now().difference(objectiveStart(o)).inDays.clamp(1, 365);
    List<Session> list;
    try {
      list = await widget.sync.fetchRecentSessions(days + 1);
    } catch (_) {
      return;
    }
    if (!mounted || list.isEmpty) return;
    setState(() => _sessions = list);
  }

  ObjectiveTrajectory get _traj =>
      computeObjectiveTrajectory(o, _sessions ?? widget.logic.state.sessions, DateTime.now());

  ObjectiveProgress get _week {
    final st = widget.logic.state;
    return computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, DateTime.now());
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  String _withUnit(double v) => '${_fmt(v)}${o.metric?.unit == null ? '' : ' ${o.metric!.unit}'}';

  /// Redessine AVANT l'écriture : le graphe montre le relevé tout de suite,
  /// même si la confirmation du serveur tarde (réseau lent, hors connexion).
  Future<void> _save() async {
    o.updatedAt = DateTime.now();
    _changed = true;
    if (mounted) setState(() {});
    await widget.sync.saveStrategicObjective(o);
  }

  Future<void> _edit() async {
    final st = widget.logic.state;
    final saved = await showObjectiveEditSheet(
      context,
      existing: o,
      domains: st.activeDomains,
      activities: st.activities,
      projects: widget.projects.where((p) => p.status != 'archived').toList(),
      sync: widget.sync,
    );
    if (saved != null && mounted) {
      setState(() {
        o = saved;
        _changed = true;
      });
    }
  }

  Future<void> _setStatus(String status) async {
    if (status == 'archived') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Archiver cet objectif ?'),
          content: const Text('Il quitte la liste et ne compte plus dans la semaine. « Archivés » en bas d\'Objectifs permet de le réactiver.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Archiver')),
          ],
        ),
      );
      if (ok != true) return;
    }
    o.status = status;
    await _save();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _addReading() async {
    final m = o.metric;
    if (m == null) return;
    final last = latestReading(o);
    final valueCtrl = TextEditingController(text: last == null ? '' : _fmt(last.value));
    final noteCtrl = TextEditingController();
    var date = DateTime.now();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final cs = Theme.of(ctx).colorScheme;
        final exp = expectedMetricAt(m, objectiveStart(o), o.endDate, date);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Relevé · ${m.label}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Attendu à cette date : ${_withUnit(exp)} · cible ${_withUnit(m.targetValue)}',
                style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
            const SizedBox(height: 14),
            TextField(
              controller: valueCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: 'Valeur${m.unit == null ? '' : ' (${m.unit})'}',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setS(() {}),
            ),
            const SizedBox(height: 10),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: objectiveStart(o).subtract(const Duration(days: 1)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setS(() => date = picked);
                },
                icon: const Icon(Icons.event, size: 18),
                label: Text(_sameDay(date, DateTime.now()) ? 'Aujourd\'hui' : _dateFr(date)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(hintText: 'Note (optionnel)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: double.tryParse(valueCtrl.text.trim().replaceAll(',', '.')) == null
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer le relevé'),
              ),
            ),
          ]),
        );
      }),
    );
    if (ok != true || !mounted) return;
    final value = double.parse(valueCtrl.text.trim().replaceAll(',', '.'));
    o.readings = upsertReading(
      o.readings,
      ObjectiveReading(date: todayYmd(date), value: value, note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim()),
    );
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: DraggableScrollableSheet(
        initialChildSize: .85,
        minChildSize: .5,
        maxChildSize: .96,
        expand: false,
        builder: (ctx, scroll) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(
                width: 36, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(.2), borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                children: [
                  _header(cs),
                  const SizedBox(height: 18),
                  // Le graphique d'abord (demande user 2026-10) : le résultat
                  // est ce qu'on vient voir, les jauges de moyens suivent.
                  _resultSection(cs),
                  const SizedBox(height: 18),
                  _meansSection(cs),
                  const SizedBox(height: 18),
                  _title(cs, 'BADGES DE L\'OBJECTIF'),
                  const SizedBox(height: 8),
                  ObjectiveBadgeLines(
                    objective: o,
                    sessions: _sessions ?? widget.logic.state.sessions,
                    marks: widget.logic.state.moodMarks,
                    accent: _accent,
                  ),
                  const SizedBox(height: 18),
                  _weekSection(cs),
                  const SizedBox(height: 18),
                  Row(children: [
                    TextButton(onPressed: () => _setStatus('done'), child: const Text('Atteint 🎉')),
                    TextButton(onPressed: () => _setStatus('archived'), child: const Text('Archiver')),
                    const Spacer(),
                    FilledButton.tonal(onPressed: _edit, child: const Text('Éditer')),
                  ]),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    final t = _traj;
    final week = _week;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.flag, size: 18, color: _accent),
        const SizedBox(width: 8),
        Expanded(child: Text(o.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        if (o.isTactical) ...[
          const SizedBox(width: 8),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: StateChip('rush · ${coupLabel(o, DateTime.now())}', color: _accent)),
        ],
      ]),
      if (o.kpiTarget != null && o.kpiTarget!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('🎯 ${o.kpiTarget}', style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.6))),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          [
            'depuis le ${_dateFr(t.start)}',
            if (t.end != null) 'échéance ${_dateFr(t.end!)}',
            if (week.daysLeft != null) '${week.daysLeft} j restants',
            if (t.timePct != null) '${(t.timePct! * 100).round()} % du temps écoulé',
          ].join(' · '),
          style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.5)),
        ),
      ),
    ]);
  }

  Widget _title(ColorScheme cs, String text, {Widget? trailing}) => Row(children: [
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: cs.onSurface.withOpacity(.5))),
        ),
        if (trailing != null) trailing,
      ]);

  Widget _statusChip(TrajectoryStatus s) {
    final (label, color) = switch (s) {
      TrajectoryStatus.ahead => ('En avance', _good),
      TrajectoryStatus.onTrack => ('Sur la trajectoire', _good),
      TrajectoryStatus.behind => ('En retard', _warn),
      TrajectoryStatus.unknown => ('Pas encore de relevé', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ── Semaine : les engagements, comme avant ─────────────────────────────────
  Widget _weekSection(ColorScheme cs) {
    final w = _week;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(cs, 'CETTE SEMAINE · LES MOYENS',
          trailing: w.weekPercent == null
              ? null
              : Text('${(w.weekPercent! * 100).round()} % du rythme',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _accent))),
      const SizedBox(height: 8),
      if (w.items.isEmpty)
        Text('Aucun engagement — édite l\'objectif pour en ajouter.', style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.5)))
      else
        for (final c in w.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(c.type == 'time' ? Icons.timer_outlined : Icons.loop, size: 14, color: cs.onSurface.withOpacity(.5)),
                const SizedBox(width: 6),
                Expanded(child: Text(c.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                Text(c.type == 'time' ? '${fmtMin(c.done)} / ${fmtMin(c.target)}' : '${c.done} / ${c.target} ×',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.onTrack ? _good : _warn)),
              ]),
              const SizedBox(height: 4),
              _weekBar(cs, c, w.weekElapsed),
            ]),
          ),
    ]);
  }

  /// Jauge hebdo d'un engagement, repère vertical = part de la semaine
  /// écoulée (l'attendu à ce jour), comme la barre de la liste.
  Widget _weekBar(ColorScheme cs, CommitmentProgress c, double weekElapsed) {
    return LayoutBuilder(builder: (_, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: 15,
        child: Stack(children: [
          Positioned.fill(
            top: 5,
            bottom: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                  value: c.pct,
                  minHeight: 5,
                  backgroundColor: cs.onSurface.withOpacity(.08),
                  valueColor: AlwaysStoppedAnimation<Color>(c.onTrack ? _good : _warn)),
            ),
          ),
          // Repère discret, pour ne pas charger la liste.
          Positioned(
            left: (w * weekElapsed.clamp(0.0, 1.0) - 0.75).clamp(0.0, w - 1.5),
            top: 2,
            bottom: 2,
            child: Container(width: 1.5, color: cs.onSurface.withOpacity(.4)),
          ),
        ]),
      );
    });
  }

  // ── Moyens cumulés : temps fait vs attendu à ce jour ───────────────────────
  Widget _meansSection(ColorScheme cs) {
    final t = _traj;
    final m = t.means;
    if (o.timeCommitments.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(cs, 'DEPUIS LE DÉBUT · TEMPS INVESTI'),
        const SizedBox(height: 6),
        Text('Pas d\'engagement de temps : ajoute des minutes/semaine sur une activité pour suivre le temps investi.',
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.5))),
      ]);
    }
    final color = m.status == TrajectoryStatus.behind ? _warn : _good;
    final total = m.totalMin > 0 ? m.totalMin : math.max(m.expectedMin, m.doneMin);
    final donePct = total <= 0 ? 0.0 : (m.doneMin / total).clamp(0.0, 1.0);
    final expPct = total <= 0 ? 0.0 : (m.expectedMin / total).clamp(0.0, 1.0);
    final diff = m.doneMin - m.expectedMin;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(cs, 'DEPUIS LE DÉBUT · TEMPS INVESTI', trailing: _statusChip(m.status)),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (_, box) {
        final w = box.maxWidth;
        return SizedBox(
          height: 26,
          child: Stack(children: [
            Positioned.fill(
              top: 8,
              bottom: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                    value: donePct,
                    minHeight: 10,
                    backgroundColor: cs.onSurface.withOpacity(.08),
                    valueColor: AlwaysStoppedAnimation<Color>(color)),
              ),
            ),
            // Repère « attendu aujourd'hui », même style discret que les jauges hebdo
            Positioned(
              left: (w * expPct - 0.75).clamp(0.0, w - 1.5),
              top: 3,
              bottom: 3,
              child: Container(width: 1.5, color: cs.onSurface.withOpacity(.4)),
            ),
          ]),
        );
      }),
      const SizedBox(height: 6),
      Text(
        '${fmtMin(m.doneMin)} investies · attendu aujourd\'hui ${fmtMin(m.expectedMin)}'
        '${m.totalMin > 0 ? ' · ${fmtMin(m.totalMin)} au total' : ''}',
        style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.6)),
      ),
      if (m.expectedMin > 0)
        Text(
          diff >= 0 ? '${fmtMin(diff)} d\'avance sur le plan' : '${fmtMin(-diff)} de retard sur le plan',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
        ),
    ]);
  }

  // ── Résultat : relevés vs ligne attendue ───────────────────────────────────
  Widget _resultSection(ColorScheme cs) {
    final m = o.metric;
    if (m == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(cs, 'RÉSULTAT'),
        const SizedBox(height: 6),
        Text('Pas de métrique chiffrée : donne la valeur d\'aujourd\'hui et la cible pour voir si le résultat suit.',
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.5))),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _edit, icon: const Icon(Icons.show_chart, size: 18), label: const Text('Définir une métrique chiffrée')),
      ]);
    }
    final t = _traj;
    final r = t.result!;
    final color = r.status == TrajectoryStatus.behind ? _warn : (r.status == TrajectoryStatus.unknown ? cs.onSurface.withOpacity(.5) : _good);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(cs, 'RÉSULTAT · ${m.label.toUpperCase()}', trailing: _statusChip(r.status)),
      const SizedBox(height: 10),
      SizedBox(height: 170, child: _chart(cs, m, t)),
      const SizedBox(height: 8),
      Text(
        r.latestValue == null
            ? 'Départ ${_withUnit(m.startValue)} le ${_dateFrYmd(ymdDashOf(t.start))} · attendu aujourd\'hui ${_withUnit(r.expectedValue)} · cible ${_withUnit(m.targetValue)}'
            : '${_withUnit(r.latestValue!)} le ${_dateFrYmd(r.latestDate!)} · attendu ${_withUnit(r.expectedValue)} · cible ${_withUnit(m.targetValue)}',
        style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.6)),
      ),
      if (r.latestValue != null && r.delta != 0)
        Text(
          r.delta > 0 ? '${_withUnit(r.delta)} d\'avance' : '${_withUnit(-r.delta)} de retard',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
        ),
      if (t.daysSinceReading != null)
        Text(
          () {
            final what = r.latestValue == null ? 'Départ' : 'Dernier relevé';
            return t.readingDue
                ? '$what il y a ${t.daysSinceReading} j — un relevé est attendu (tous les ${o.checkInEvery} j).'
                : '$what il y a ${t.daysSinceReading} j · prochain relevé dans ${o.checkInEvery - t.daysSinceReading!} j.';
          }(),
          style: TextStyle(fontSize: 12, color: t.readingDue ? _warn : cs.onSurface.withOpacity(.5)),
        ),
      const SizedBox(height: 10),
      // Orange = un relevé est dû (même code couleur que la ligne ci-dessus).
      SizedBox(
        height: 46,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: t.readingDue ? _warn : _accent),
          onPressed: _addReading,
          icon: const Icon(Icons.add_chart, size: 18),
          label: const Text('Noter un relevé'),
        ),
      ),
      const SizedBox(height: 10),
      // Saisies : les 5 derniers relevés, puis le départ (première saisie).
      for (final rd in o.readings.reversed.take(5))
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: [
            Text(_dateFrYmd(rd.date), style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
            const SizedBox(width: 10),
            Text(_withUnit(rd.value), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            if (rd.note != null) ...[
              const SizedBox(width: 8),
              Expanded(
                  child: Text(rd.note!,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5)))),
            ],
          ]),
        ),
      Row(children: [
        Text(_dateFrYmd(ymdDashOf(t.start)), style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
        const SizedBox(width: 10),
        Text(_withUnit(m.startValue), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _warn)),
        const SizedBox(width: 8),
        Text('départ', style: TextStyle(fontSize: 12, color: _warn.withOpacity(.8))),
      ]),
    ]);
  }

  Widget _chart(ColorScheme cs, ObjectiveMetric m, ObjectiveTrajectory t) {
    final start = t.start;
    final now = DateTime.now();
    final lastReadingDay = o.readings.isEmpty ? start : (DateTime.tryParse(o.readings.last.date) ?? start);
    var end = t.end ?? [now, lastReadingDay].reduce((a, b) => a.isAfter(b) ? a : b).add(const Duration(days: 7));
    if (!end.isAfter(start)) end = start.add(const Duration(days: 7));
    double x(DateTime d) => d.difference(start).inHours / 24.0;
    final maxX = x(end);
    final todayX = x(now).clamp(0.0, maxX);

    final expected = t.end == null
        ? [FlSpot(0, m.startValue), FlSpot(maxX, m.startValue)]
        : [FlSpot(0, m.startValue), FlSpot(maxX, m.targetValue)];
    // Le départ est la première saisie : la courbe du réel part de là.
    final actual = [
      FlSpot(0, m.startValue),
      for (final r in o.readings)
        if (DateTime.tryParse(r.date) case final d?) FlSpot(x(d).clamp(0.0, maxX), r.value),
    ];
    final values = [m.startValue, m.targetValue, ...actual.map((s) => s.y)];
    var minY = values.reduce(math.min), maxY = values.reduce(math.max);
    if (maxY - minY < 1e-9) {
      maxY += 1;
      minY -= 1;
    }
    final pad = (maxY - minY) * .12;
    minY -= pad;
    maxY += pad;
    final actualColor = t.result!.status == TrajectoryStatus.behind ? _warn : _accent;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (_) => FlLine(color: cs.onSurface.withOpacity(.07), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: (maxY - minY) / 4,
              getTitlesWidget: (v, _) => Text(_fmt(v), style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(.45))),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: math.max(1, maxX / 3),
              getTitlesWidget: (v, meta) {
                if (v < 0 || v > maxX + .01) return const SizedBox.shrink();
                final d = start.add(Duration(hours: (v * 24).round()));
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_shortDate(d), style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(.45))),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(y: m.targetValue, color: _good.withOpacity(.6), strokeWidth: 1, dashArray: [3, 4]),
          ],
          verticalLines: [
            if (todayX > 0 && todayX < maxX)
              VerticalLine(x: todayX, color: cs.onSurface.withOpacity(.35), strokeWidth: 1, dashArray: [2, 3]),
          ],
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${_shortDate(start.add(Duration(hours: (s.x * 24).round())))} · ${_withUnit(s.y)}',
                      TextStyle(fontSize: 11, color: cs.onSurface),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: expected,
            color: cs.onSurface.withOpacity(.4),
            barWidth: 1.5,
            dashArray: [6, 4],
            dotData: const FlDotData(show: false),
          ),
          if (actual.isNotEmpty)
            LineChartBarData(
              spots: actual,
              color: actualColor,
              barWidth: 2.5,
              isCurved: false,
              // Le point de départ (index 0) en orange, plus gros : c'est de
              // là qu'on part — les relevés suivent dans la couleur du réel.
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, index) => index == 0
                    ? FlDotCirclePainter(radius: 4, color: _warn, strokeWidth: 1.5, strokeColor: cs.surface)
                    : FlDotCirclePainter(radius: 3, color: actualColor, strokeWidth: 0),
              ),
              belowBarData: BarAreaData(show: true, color: actualColor.withOpacity(.08)),
            ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
String _dateFr(DateTime d) => '${d.day} ${_months[d.month - 1]}${d.year != DateTime.now().year ? ' ${d.year}' : ''}';
String _dateFrYmd(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : _dateFr(d);
}
String _shortDate(DateTime d) => '${d.day}/${d.month}';
