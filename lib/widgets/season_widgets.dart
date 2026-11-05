import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/seasons.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show objectiveStart;
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/utils/objective_progress.dart' show computeObjectiveProgress;
import 'package:productivitwo_v1/widgets/objective_edit_sheet.dart' show showObjectiveEditSheet;
import 'package:productivitwo_v1/widgets/objective_readings_card.dart' show noteReadingQuick;
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart' show showObjectiveTrajectorySheet;

// Saisons, refonte 2026-11-04 (maquette validée « Saisons et objectifs ») : le bandeau
// d'Organisation, « Poser le cap », la cible de saison sur un mini-graphique.

const kSeasonAccent = Color(0xFFB79CF2);
const _seasonInk = Color(0xFF1A1030);
const _green = Color(0xFF5CC79A);
const _amber = Color(0xFFE8A33D);

const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
String _long(String ymd) {
  final d = DateTime.parse(ymd);
  return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

Widget _chip(String t, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
    );

/// Bandeau en tête d'Organisation : la saison en cours (semaine, fin, objectifs
/// sur la trajectoire / en retard), sinon « Poser le cap ».
class SeasonBanner extends StatelessWidget {
  final AppLogic logic;
  final List<StrategicObjective> objectives;
  final VoidCallback onOpenCap;
  final void Function(Season s)? onOpenBilan;
  const SeasonBanner({super.key, required this.logic, required this.objectives, required this.onOpenCap, this.onOpenBilan});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = logic.livedTodayYmd;
    final s = currentSeason(logic.seasons, today);
    final bilan = s == null ? unseenBilan(logic.seasons, today) : null;
    final box = BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: const LinearGradient(colors: [Color(0xFF251E38), Color(0xFF17142A)]),
      border: Border.all(color: const Color(0xFF3A2F5A)),
    );
    if (bilan != null && onOpenBilan != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('season-banner'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => onOpenBilan!(bilan),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: box,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SAISON ${bilan.n} TERMINÉE', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kSeasonAccent)),
                  const SizedBox(height: 2),
                  const Text('Voir le bilan et lancer la suivante', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: kSeasonAccent),
            ]),
          ),
        ),
      );
    }
    if (s == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('season-banner'),
          borderRadius: BorderRadius.circular(16),
          onTap: onOpenCap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: box,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('PAS DE SAISON EN COURS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kSeasonAccent)),
                  const SizedBox(height: 2),
                  const Text('Poser le cap de tes objectifs', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  Text('quelques semaines, une cible par objectif', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6))),
                ]),
              ),
              const Icon(Icons.chevron_right, color: kSeasonAccent),
            ]),
          ),
        ),
      );
    }
    final views = seasonViews(s, objectives, todayYmd: today, activities: logic.state.activities, sessions: logic.state.sessions, hits: logic.state.habitHits);
    final ok = views.where((v) => v.ok).length;
    final late = views.where((v) => v.state == SeasonGoalState.behind).length;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('season-banner'),
        borderRadius: BorderRadius.circular(16),
        onTap: onOpenCap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: box,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('SAISON ${s.n} · SEMAINE ${s.weekOf(today)} / ${s.weeks}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kSeasonAccent)),
              ),
              const Text('Cap ›', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kSeasonAccent)),
            ]),
            const SizedBox(height: 3),
            Text('Jusqu\'au ${seasonEndLabel(s)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: s.elapsed(today), minHeight: 6, color: kSeasonAccent, backgroundColor: const Color(0xFF2C2545)),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (ok > 0) _chip('$ok sur la trajectoire', _green, const Color(0xFF173527)),
              if (late > 0) _chip('$late en retard', _amber, const Color(0xFF3A2A12)),
              if (ok == 0 && late == 0) _chip('${s.goals.length} objectif${s.goals.length > 1 ? 's' : ''} · rien à mesurer encore', cs.onSurface.withValues(alpha: .7), const Color(0xFF1C2A24)),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Poser le cap ─────────────────────────────────────────────────────────────

/// Début de saison (ou cap de la saison en cours : cibles réglables).
Future<void> showSeasonCapSheet(BuildContext context,
    {required AppLogic logic, required List<StrategicObjective> objectives, required FirestoreSync sync, required List<Project> projects}) {
  return showFiche<void>(context, builder: (ctx, scroll) => SeasonCapView(logic: logic, objectives: objectives, sync: sync, projects: projects, scroll: scroll));
}

class SeasonCapView extends StatefulWidget {
  final AppLogic logic;
  final List<StrategicObjective> objectives;
  final FirestoreSync? sync;
  final List<Project> projects;
  final ScrollController? scroll;
  const SeasonCapView({super.key, required this.logic, required this.objectives, this.sync, this.projects = const [], this.scroll});

  @override
  State<SeasonCapView> createState() => _SeasonCapViewState();
}

class _SeasonCapViewState extends State<SeasonCapView> {
  AppLogic get logic => widget.logic;
  late List<StrategicObjective> _objectives = widget.objectives.where((o) => o.status == 'active').toList();
  int _weeks = kSeasonWeeks;
  final Map<String, SeasonGoal> _picked = {};
  /// Cibles réglées à la main : elles ne suivent plus la durée de la saison.
  final Set<String> _manual = {};
  bool _renew = false;

  String get _end => seasonEndFor(logic.livedTodayYmd, weeks: _weeks);

  void _setWeeks(int w) {
    _weeks = w;
    for (final o in _objectives) {
      final g = _picked[o.id];
      if (g == null || g.kind != SeasonGoalKind.metric || _manual.contains(o.id)) continue;
      _picked[o.id] = g.copyWith(target: seasonMetricTarget(o, _end));
    }
  }

  @override
  void initState() {
    super.initState();
    final last = logic.seasons.where((s) => !s.legacy).lastOrNull;
    // Une nouvelle saison reprend ce que le dernier bilan a gardé ou ajusté.
    if (last != null && currentSeason(logic.seasons, logic.livedTodayYmd) == null) {
      for (final g in last.goals) {
        if (g.decision == SeasonDecision.drop) continue;
        final o = _objectives.where((x) => x.id == g.objectiveId).firstOrNull;
        if (o != null) {
          _picked[o.id] = goalFor(o, seasonEnd: _end).copyWith(target: g.decision == SeasonDecision.adjust ? g.target : null);
          if (g.decision == SeasonDecision.adjust) _manual.add(o.id);
        }
      }
    }
  }

  Future<double?> _askTarget(SeasonGoal g) async {
    final ctrl = TextEditingController(text: g.target == null ? '' : seasonNum(g.target!));
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cible à la fin de la saison', style: const TextStyle(fontSize: 17)),
        content: TextField(
          key: const ValueKey('season-target-field'),
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: g.unit, helperText: g.from == null ? null : 'au départ : ${seasonNum(g.from!)} ${g.unit ?? ''}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.').replaceAll(' ', ''));
              Navigator.pop(ctx, v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _newObjective() async {
    final sync = widget.sync;
    if (sync == null) return;
    final o = await showObjectiveEditSheet(context,
        domains: logic.state.activeDomains, activities: logic.state.activeActivities, projects: widget.projects, sync: sync);
    if (o == null || !mounted) return;
    setState(() {
      _objectives = [..._objectives, o];
      if (_picked.length < kSeasonMaxGoals) _picked[o.id] = goalFor(o, seasonEnd: _end);
    });
  }

  Future<void> _launch() async {
    final goals = [for (final o in _objectives) if (_picked[o.id] case final g?) g];
    if (goals.isEmpty) return;
    await logic.openSeason(goals, weeks: _weeks);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final today = logic.livedTodayYmd;
    final running = currentSeason(logic.seasons, today);
    if (running != null && !_renew) return _runningView(cs, running);
    final n = logic.seasons.isEmpty ? 1 : logic.seasons.map((s) => s.n).reduce((a, b) => a > b ? a : b) + 1;
    final end = seasonEndFor(today, weeks: _weeks);
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
      Text('NOUVELLE SAISON · LA $n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: kSeasonAccent)),
      const Text('Ton cap pour la suite', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      Text('Coche ce que tu vises jusqu\'au bout de la saison, et règle la cible. Le reste continue sans pression.', style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 14),
      Text('DURÉE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: mute)),
      const SizedBox(height: 6),
      Row(children: [
        for (final (i, w) in kSeasonDurations.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: ChoiceChip(
              key: ValueKey('season-weeks-$w'),
              label: SizedBox(width: double.infinity, child: Text('$w sem.', textAlign: TextAlign.center)),
              selected: _weeks == w,
              showCheckmark: false,
              selectedColor: kSeasonAccent,
              labelStyle: TextStyle(fontWeight: FontWeight.w800, color: _weeks == w ? _seasonInk : null),
              onSelected: (_) => setState(() => _setWeeks(w)),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 4),
      Text('Du ${_long(today)} au ${_long(end)}', style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 14),
      Text('TES OBJECTIFS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: mute)),
      const SizedBox(height: 6),
      if (_objectives.isEmpty) Text('Aucun objectif actif : crée le premier.', style: TextStyle(color: mute)),
      for (final o in _objectives) _goalRow(cs, o),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: widget.sync == null ? null : _newObjective, icon: const Icon(Icons.add), label: const Text('Nouvel objectif')),
      ),
      const SizedBox(height: 6),
      FilledButton(
        key: const ValueKey('season-launch'),
        style: FilledButton.styleFrom(backgroundColor: kSeasonAccent, foregroundColor: _seasonInk, minimumSize: const Size.fromHeight(52)),
        onPressed: _picked.isEmpty ? null : _launch,
        child: Text('Lancer la saison · ${_picked.length} objectif${_picked.length > 1 ? 's' : ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ),
      const SizedBox(height: 8),
      Text('Les objectifs non cochés restent dans leur tuile, sans trait de saison. 3 objectifs conseillés, $kSeasonMaxGoals au plus.',
          style: TextStyle(fontSize: 12, color: mute)),
    ]);
  }

  Widget _goalRow(ColorScheme cs, StrategicObjective o) {
    final mute = cs.onSurface.withValues(alpha: .6);
    final g = _picked[o.id];
    final on = g != null;
    final base = g ?? goalFor(o, seasonEnd: _end);
    final domain = logic.state.domains.where((d) => d.id == o.domainId).firstOrNull?.name;
    final sub = [
      if (domain != null) domain,
      if (base.kind == SeasonGoalKind.metric && base.from != null) '${o.metric!.label.toLowerCase()}, aujourd\'hui ${seasonNum(base.from!)} ${base.unit ?? ''}'.trim(),
      if (base.kind == SeasonGoalKind.rhythm) 'tenir le rythme de ses engagements',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: on ? 1 : .55,
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: ValueKey('season-goal-${o.id}'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() {
              if (on) {
                _picked.remove(o.id);
              } else if (_picked.length < kSeasonMaxGoals) {
                _picked[o.id] = goalFor(o, seasonEnd: _end);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: on ? kSeasonAccent : null,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kSeasonAccent, width: 2),
                  ),
                  child: on ? const Icon(Icons.check, size: 15, color: _seasonInk) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                    if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 12, color: mute)),
                  ]),
                ),
                if (base.kind == SeasonGoalKind.metric)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final v = await _askTarget(base);
                      if (v != null) {
                        setState(() {
                          _picked[o.id] = base.copyWith(target: v);
                          _manual.add(o.id);
                        });
                      }
                    },
                    child: _chip('${seasonNum(base.target ?? 0)} ${base.unit ?? ''}'.trim(), kSeasonAccent, const Color(0xFF241D38)),
                  )
                else
                  _chip('rythme', kSeasonAccent, const Color(0xFF241D38)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _runningView(ColorScheme cs, Season s) {
    final mute = cs.onSurface.withValues(alpha: .6);
    final today = logic.livedTodayYmd;
    final byId = {for (final o in widget.objectives) o.id: o};
    final views = seasonViews(s, widget.objectives, todayYmd: today, activities: logic.state.activities, sessions: logic.state.sessions, hits: logic.state.habitHits);
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
      Text('SAISON ${s.n} · SEMAINE ${s.weekOf(today)} / ${s.weeks}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: kSeasonAccent)),
      Text('Ton cap jusqu\'au ${seasonEndLabel(s)}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      Text('${s.daysLeft(today)} jours restants · touche une cible pour la changer', style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 12),
      for (final v in views)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .45), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(byId[v.goal.objectiveId]?.title ?? v.goal.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                  Text(v.label(), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: v.ok ? _green : (v.state == SeasonGoalState.behind ? _amber : mute))),
                ]),
              ),
              if (v.goal.kind == SeasonGoalKind.metric)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final t = await _askTarget(v.goal);
                    if (t != null) await logic.setSeasonTarget(v.goal.objectiveId, t);
                    if (mounted) setState(() {});
                  },
                  child: _chip('${seasonNum(v.goal.target ?? 0)} ${v.goal.unit ?? ''}'.trim(), kSeasonAccent, const Color(0xFF241D38)),
                )
              else
                _chip('rythme', kSeasonAccent, const Color(0xFF241D38)),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const ValueKey('season-renew'),
        onPressed: () => setState(() {
          _renew = true;
          for (final g in s.goals) {
            final o = byId[g.objectiveId];
            if (o != null && o.status == 'active') _picked[o.id] = g;
          }
        }),
        child: const Text('Reposer le cap · nouvelle saison'),
      ),
    ]);
  }
}

// ── Cible de saison sur un mini-graphique ────────────────────────────────────

/// Mini-graphique d'une métrique dans sa saison : la fenêtre de la saison en
/// violet clair, la trajectoire de la saison en pointillés jusqu'à la cible,
/// les relevés et le trait d'aujourd'hui.
class SeasonMetricPainter extends CustomPainter {
  final StrategicObjective o;
  final Season s;
  final SeasonGoal g;
  final Color line;
  final Color ink;
  final DateTime now;
  SeasonMetricPainter({required this.o, required this.s, required this.g, required this.line, required this.ink, required this.now});

  @override
  void paint(Canvas canvas, Size size) {
    final start = DateTime.parse(s.start), end = DateTime.parse(s.end).add(const Duration(days: 1));
    // Le plan d'origine : du départ de l'objectif (valeur de départ) à sa cible, pas depuis le début de la saison.
    final m = o.metric;
    final oStart = objectiveStart(o);
    final oEnd = o.endDate == null ? end : DateTime(o.endDate!.year, o.endDate!.month, o.endDate!.day).add(const Duration(days: 1));
    final lead = Duration(days: (end.difference(start).inDays * 0.45).round().clamp(7, 42));
    var from = start.subtract(lead);
    if (m != null && oStart.isBefore(from)) from = oStart;
    final to = m != null && oEnd.isAfter(end) ? oEnd : end;
    final span = to.difference(from).inHours.clamp(1, 1 << 30).toDouble();
    final readings = [
      for (final r in o.readings)
        if (DateTime.tryParse(r.date) case final d? when !d.isBefore(from) && d.isBefore(to)) (d, r.value),
    ];
    final planFrom = m?.startValue ?? g.from, planTarget = m?.targetValue ?? g.target;
    final planStart = m != null ? oStart : start, planEnd = m != null ? oEnd : end;
    final vals = [planFrom ?? 0, planTarget ?? 0, if (g.target != null) g.target!, for (final r in readings) r.$2];
    var lo = vals.reduce((a, b) => a < b ? a : b), hi = vals.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo).abs() < 1e-6 ? 1.0 : (hi - lo) * .15;
    lo -= pad;
    hi += pad;
    double x(DateTime d) => (d.difference(from).inHours / span).clamp(0.0, 1.0) * size.width;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    canvas.drawRect(Rect.fromLTRB(x(start), 0, x(end), size.height), Paint()..color = kSeasonAccent.withValues(alpha: .08));
    if (planFrom != null && planTarget != null) {
      final a = Offset(x(planStart), y(planFrom)), b = Offset(x(planEnd), y(planTarget));
      final dash = Paint()
        ..color = kSeasonAccent
        ..strokeWidth = 1.5;
      const n = 32;
      for (var i = 0; i < n; i += 2) {
        canvas.drawLine(Offset.lerp(a, b, i / n)!, Offset.lerp(a, b, (i + 1) / n)!, dash);
      }
      canvas.drawCircle(b - Offset(b.dx >= size.width - 3 ? 3 : 0, 0), 3, Paint()..color = kSeasonAccent);
    }
    if (readings.isNotEmpty) {
      // Le chemin parcouru part du même point que le plan.
      final path = m != null && !oStart.isBefore(from)
          ? (Path()..moveTo(x(oStart), y(m.startValue)))
          : (Path()..moveTo(x(readings.first.$1), y(readings.first.$2)));
      for (final r in m != null ? readings : readings.skip(1)) {
        path.lineTo(x(r.$1), y(r.$2));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = line
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round);
      final last = readings.last;
      canvas.drawCircle(Offset(x(last.$1), y(last.$2)), 2.5, Paint()..color = line);
    }
    final nx = x(now);
    canvas.drawLine(Offset(nx, 0), Offset(nx, size.height), Paint()
      ..color = ink.withValues(alpha: .45)
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant SeasonMetricPainter old) => true;
}

/// Ligne « objectif de saison » d'une tuile : nom · état (vert sur la trajectoire, ambre en retard).
class SeasonGoalLine extends StatelessWidget {
  final SeasonGoalView view;
  final String title;
  final VoidCallback onTap;
  const SeasonGoalLine({super.key, required this.view, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = view.ok ? _green : (view.state == SeasonGoalState.behind ? _amber : cs.onSurface.withValues(alpha: .6));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: kSeasonAccent, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5))),
          const SizedBox(width: 4),
          Text(view.label(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
        ]),
      ),
    );
  }
}


// ── Un objectif de saison ────────────────────────────────────────────────────

Future<void> showSeasonGoalSheet(BuildContext context,
    {required AppLogic logic, required Season season, required SeasonGoal goal, required StrategicObjective objective, required FirestoreSync sync, List<Project> projects = const []}) {
  return showFiche<void>(context,
      builder: (ctx, scroll) => SeasonGoalView2(logic: logic, season: season, goal: goal, objective: objective, sync: sync, projects: projects, scroll: scroll));
}

class SeasonGoalView2 extends StatefulWidget {
  final AppLogic logic;
  final Season season;
  final SeasonGoal goal;
  final StrategicObjective objective;
  final FirestoreSync? sync;
  final List<Project> projects;
  final ScrollController? scroll;
  const SeasonGoalView2({super.key, required this.logic, required this.season, required this.goal, required this.objective, this.sync, this.projects = const [], this.scroll});

  @override
  State<SeasonGoalView2> createState() => _SeasonGoalView2State();
}

class _SeasonGoalView2State extends State<SeasonGoalView2> {
  AppLogic get logic => widget.logic;
  late StrategicObjective _o = widget.objective;

  Season get _season => logic.seasons.where((x) => x.n == widget.season.n).firstOrNull ?? widget.season;
  SeasonGoal get _goal => effectiveSeasonGoal(_season, _season.goalOf(widget.goal.objectiveId) ?? widget.goal, _o);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final st = logic.state;
    final today = logic.livedTodayYmd;
    final s = _season, g = _goal, o = _o;
    final v = seasonGoalView(s, g, o, todayYmd: today, activities: st.activities, sessions: st.sessions, hits: st.habitHits);
    final domain = st.domains.where((d) => d.id == o.domainId).firstOrNull?.name;
    final closed = s.isOverOn(today);
    final stateChip = switch (v.state) {
      SeasonGoalState.onTrack => _chip(v.label(), _green, const Color(0xFF173527)),
      SeasonGoalState.reached => _chip(closed ? 'atteint' : 'cible atteinte', _green, const Color(0xFF173527)),
      SeasonGoalState.behind => _chip(g.kind == SeasonGoalKind.metric ? 'en retard de ${v.label().replaceFirst('−', '')}' : v.label(), _amber, const Color(0xFF3A2A12)),
      SeasonGoalState.missed => _chip(v.label(closed: true), _amber, const Color(0xFF3A2A12)),
      SeasonGoalState.none => _chip(v.label(), mute, const Color(0xFF1C2A24)),
    };
    final u = g.unit == null || g.unit!.isEmpty ? '' : ' ${g.unit}';
    final p = computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, DateTime.now());
    Widget stat(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
              Text(label, style: TextStyle(fontSize: 11, color: mute)),
            ]),
          ),
        );
    final weeks = g.kind == SeasonGoalKind.rhythm
        ? seasonRhythmWeeks(s, o, activities: st.activities, sessions: st.sessions, hits: st.habitHits, untilYmd: closed ? null : today)
        : const <double?>[];
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
      Text(['SAISON ${s.n}', if (domain != null) domain.toUpperCase()].join(' · '), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: kSeasonAccent)),
      Text(o.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        stateChip,
        _chip(closed ? 'saison terminée' : 'semaine ${s.weekOf(today)} / ${s.weeks}', cs.onSurface.withValues(alpha: .75), const Color(0xFF1C2A24)),
      ]),
      const SizedBox(height: 12),
      if (g.kind == SeasonGoalKind.metric) ...[
        SizedBox(
          height: 150,
          child: CustomPaint(painter: SeasonMetricPainter(o: o, s: s, g: g, line: _green, ink: cs.onSurface, now: DateTime.now()), size: Size.infinite),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Flexible(child: Text(o.metric == null ? 'début de saison' : 'départ · ${seasonNum(o.metric!.startValue)}$u', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: mute))),
          const SizedBox(width: 8),
          Expanded(
            child: Text('fin · ${seasonNum(g.target ?? 0)}$u le ${seasonEndLabel(s)}',
                textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kSeasonAccent)),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 12, children: [
          Text('— tes relevés', style: TextStyle(fontSize: 11.5, color: _green.withValues(alpha: .9))),
          const Text('– – trajectoire de la saison', style: TextStyle(fontSize: 11.5, color: kSeasonAccent)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          stat(v.latest == null ? '—' : seasonNum(v.latest!), 'dernier relevé'),
          const SizedBox(width: 6),
          stat(v.expected == null ? '—' : seasonNum(v.expected!), closed ? 'cible' : 'attendu aujourd\'hui'),
          const SizedBox(width: 6),
          stat(v.latest == null || g.target == null ? '—' : '${(g.target! - v.latest!) >= 0 ? '+' : '−'}${seasonNum((g.target! - v.latest!).abs())}',
              closed ? 'écart final' : 'reste en ${(s.daysLeft(today) / 7).ceil()} sem.'),
        ]),
      ] else ...[
        Text('LE RYTHME, SEMAINE PAR SEMAINE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: mute)),
        const SizedBox(height: 6),
        SizedBox(
          height: 90,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < s.weeks; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: i < weeks.length && weeks[i] != null ? (70 * weeks[i]!).clamp(4.0, 70.0) : 4,
                    decoration: BoxDecoration(
                      color: i < weeks.length && weeks[i] != null
                          ? (weeks[i]! >= kSeasonRhythmOk ? _green : _amber)
                          : cs.onSurface.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('S${i + 1}', style: TextStyle(fontSize: 10.5, color: mute)),
                ]),
              ),
            ],
          ]),
        ),
        Text('vert = rythme tenu (≥ 85 %)', style: TextStyle(fontSize: 11.5, color: mute)),
      ],
      if (p.items.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('CE QUI LE FAIT AVANCER · CETTE SEMAINE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: mute)),
        const SizedBox(height: 4),
        for (final it in p.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(it.name, style: const TextStyle(fontSize: 13.5))),
              Text(it.type == 'time' ? '${it.done} / ${it.target} min' : '${it.done} / ${it.target}',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: it.onTrack ? _green : _amber)),
            ]),
          ),
      ],
      const SizedBox(height: 14),
      Row(children: [
        if (g.kind == SeasonGoalKind.metric && widget.sync != null)
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kSeasonAccent, foregroundColor: _seasonInk, minimumSize: const Size.fromHeight(48)),
              onPressed: () async {
                if (await noteReadingQuick(context, sync: widget.sync!, objective: o)) {
                  final all = await widget.sync!.fetchStrategicObjectives();
                  final fresh = all.where((x) => x.id == o.id).firstOrNull;
                  if (mounted && fresh != null) setState(() => _o = fresh);
                }
              },
              child: const Text('Noter un relevé', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        if (g.kind == SeasonGoalKind.metric && !closed) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: kSeasonAccent, side: const BorderSide(color: Color(0xFF3A2F5A)), minimumSize: const Size.fromHeight(48)),
              onPressed: () async {
                final t = await askSeasonTarget(context, g);
                if (t != null) await logic.setSeasonTarget(g.objectiveId, t);
                if (mounted) setState(() {});
              },
              child: const Text('Changer la cible'),
            ),
          ),
        ],
      ]),
      if (widget.sync != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => showObjectiveTrajectorySheet(context, logic: logic, sync: widget.sync!, objective: o, projects: widget.projects),
            child: const Text('Fiche de l\'objectif ›'),
          ),
        ),
    ]);
  }
}

/// Cible à la fin de la saison (métrique).
Future<double?> askSeasonTarget(BuildContext context, SeasonGoal g) {
  final ctrl = TextEditingController(text: g.target == null ? '' : seasonNum(g.target!));
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cible à la fin de la saison', style: TextStyle(fontSize: 17)),
      content: TextField(
        key: const ValueKey('season-target-field'),
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(suffixText: g.unit, helperText: g.from == null ? null : 'au départ : ${seasonNum(g.from!)} ${g.unit ?? ''}'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim().replaceAll(',', '.').replaceAll(' ', ''))),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

// ── Bilan de fin de saison ───────────────────────────────────────────────────

/// Carte en tête d'Aujourd'hui tant que le bilan d'une saison close n'est pas fait.
class SeasonBilanCard extends StatelessWidget {
  final AppLogic logic;
  final void Function(Season s) onOpen;
  const SeasonBilanCard({super.key, required this.logic, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = currentSeason(logic.seasons, logic.livedTodayYmd) == null ? unseenBilan(logic.seasons, logic.livedTodayYmd) : null;
    if (s == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('season-bilan-card'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => onOpen(s),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [Color(0xFF251E38), Color(0xFF17142A)]),
              border: Border.all(color: const Color(0xFF3A2F5A)),
            ),
            child: Row(children: [
              const Icon(Icons.flag_rounded, color: kSeasonAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SAISON ${s.n} TERMINÉE', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: kSeasonAccent)),
                  const Text('Le bilan, puis la saison suivante', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: kSeasonAccent),
            ]),
          ),
        ),
      ),
    );
  }
}

Future<void> showSeasonBilanSheet(BuildContext context,
    {required AppLogic logic, required Season season, required List<StrategicObjective> objectives, required FirestoreSync sync, List<Project> projects = const []}) async {
  final next = await showFiche<bool>(context,
      builder: (ctx, scroll) => SeasonBilanView(logic: logic, season: season, objectives: objectives, scroll: scroll));
  if (next == true && context.mounted) {
    await showSeasonCapSheet(context, logic: logic, objectives: objectives, sync: sync, projects: projects);
  }
}

class SeasonBilanView extends StatefulWidget {
  final AppLogic logic;
  final Season season;
  final List<StrategicObjective> objectives;
  final ScrollController? scroll;
  const SeasonBilanView({super.key, required this.logic, required this.season, required this.objectives, this.scroll});

  @override
  State<SeasonBilanView> createState() => _SeasonBilanViewState();
}

class _SeasonBilanViewState extends State<SeasonBilanView> {
  late final Map<String, SeasonDecision> _decisions = {for (final g in widget.season.goals) g.objectiveId: g.decision ?? SeasonDecision.keep};
  late final Map<String, double?> _targets = {for (final g in widget.season.goals) g.objectiveId: g.target};

  Future<void> _close({required bool next}) async {
    final st = widget.logic.state;
    final views = seasonViews(widget.season, widget.objectives,
        todayYmd: widget.logic.livedTodayYmd, activities: st.activities, sessions: st.sessions, hits: st.habitHits);
    final held = views.where((v) => v.ok).length;
    final s = widget.season.copyWith(goals: [
      for (final g in widget.season.goals) _decisions[g.objectiveId] == SeasonDecision.adjust && _targets[g.objectiveId] != null ? g.copyWith(target: _targets[g.objectiveId]) : g,
    ]);
    await widget.logic.closeSeasonBilan(s, held: held, decisions: _decisions);
    if (mounted) Navigator.of(context).pop(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final s = widget.season;
    final st = widget.logic.state;
    final byId = {for (final o in widget.objectives) o.id: o};
    final views = seasonViews(s, widget.objectives, todayYmd: widget.logic.livedTodayYmd, activities: st.activities, sessions: st.sessions, hits: st.habitHits);
    final held = views.where((v) => v.ok).length;
    final won = held >= seasonHeldNeeded(s.goals.length) && s.goals.isNotEmpty;
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
      Text('SAISON ${s.n} TERMINÉE · ${s.weeks} SEMAINES', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: kSeasonAccent)),
      Text('$held objectif${held > 1 ? 's' : ''} sur ${s.goals.length} ${held > 1 ? 'tenus' : 'tenu'}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      Text(won ? 'Saison réussie : elle compte pour le badge Saisons.' : 'Il en fallait ${seasonHeldNeeded(s.goals.length)} pour réussir la saison.',
          style: TextStyle(fontSize: 13, color: won ? _green : mute)),
      const SizedBox(height: 4),
      Text('Pour chacun : tu le gardes pour la saison suivante, tu ajustes la cible, ou tu le laisses.', style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 12),
      for (final v in views)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .45), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(byId[v.goal.objectiveId]?.title ?? v.goal.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800))),
                v.ok ? _chip('atteint', _green, const Color(0xFF173527)) : _chip(v.state == SeasonGoalState.none ? 'rien de mesuré' : 'pas atteint', _amber, const Color(0xFF3A2A12)),
              ]),
              const SizedBox(height: 4),
              Text(v.label(closed: true), style: TextStyle(fontSize: 12.5, color: mute)),
              const SizedBox(height: 8),
              SegmentedButton<SeasonDecision>(
                segments: [
                  const ButtonSegment(value: SeasonDecision.keep, label: Text('Garder')),
                  ButtonSegment(
                    value: SeasonDecision.adjust,
                    label: Text(_decisions[v.goal.objectiveId] == SeasonDecision.adjust && _targets[v.goal.objectiveId] != null && v.goal.kind == SeasonGoalKind.metric
                        ? 'Ajuster · ${seasonNum(_targets[v.goal.objectiveId]!)}'
                        : 'Ajuster'),
                  ),
                  const ButtonSegment(value: SeasonDecision.drop, label: Text('Laisser')),
                ],
                selected: {_decisions[v.goal.objectiveId]!},
                showSelectedIcon: false,
                onSelectionChanged: (sel) async {
                  final d = sel.first;
                  if (d == SeasonDecision.adjust && v.goal.kind == SeasonGoalKind.metric) {
                    final t = await askSeasonTarget(context, v.goal);
                    if (t == null) return;
                    _targets[v.goal.objectiveId] = t;
                  }
                  setState(() => _decisions[v.goal.objectiveId] = d);
                },
              ),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      FilledButton(
        key: const ValueKey('season-bilan-next'),
        style: FilledButton.styleFrom(backgroundColor: kSeasonAccent, foregroundColor: _seasonInk, minimumSize: const Size.fromHeight(52)),
        onPressed: () => _close(next: true),
        child: Text('Lancer la saison ${s.n + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ),
      TextButton(onPressed: () => _close(next: false), child: const Text('Fermer le bilan, sans nouvelle saison')),
    ]);
  }
}
