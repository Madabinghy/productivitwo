import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/seasons.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/objective_edit_sheet.dart' show showObjectiveEditSheet;

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
  const SeasonBanner({super.key, required this.logic, required this.objectives, required this.onOpenCap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = logic.livedTodayYmd;
    final s = currentSeason(logic.seasons, today);
    final box = BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: const LinearGradient(colors: [Color(0xFF251E38), Color(0xFF17142A)]),
      border: Border.all(color: const Color(0xFF3A2F5A)),
    );
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
  bool _renew = false;

  @override
  void initState() {
    super.initState();
    final last = logic.seasons.where((s) => !s.legacy).lastOrNull;
    // Une nouvelle saison reprend ce que le dernier bilan a gardé ou ajusté.
    if (last != null && currentSeason(logic.seasons, logic.livedTodayYmd) == null) {
      for (final g in last.goals) {
        if (g.decision == SeasonDecision.drop) continue;
        final o = _objectives.where((x) => x.id == g.objectiveId).firstOrNull;
        if (o != null) _picked[o.id] = goalFor(o).copyWith(target: g.decision == SeasonDecision.adjust ? g.target : null);
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
      if (_picked.length < kSeasonMaxGoals) _picked[o.id] = goalFor(o);
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
              onSelected: (_) => setState(() => _weeks = w),
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
    final base = g ?? goalFor(o);
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
                _picked[o.id] = goalFor(o);
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
                      if (v != null) setState(() => _picked[o.id] = base.copyWith(target: v));
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
    final lead = Duration(days: (end.difference(start).inDays * 0.45).round().clamp(7, 42));
    final from = start.subtract(lead);
    final span = end.difference(from).inHours.toDouble();
    final readings = [
      for (final r in o.readings)
        if (DateTime.tryParse(r.date) case final d? when !d.isBefore(from) && d.isBefore(end)) (d, r.value),
    ];
    final vals = [g.from ?? 0, g.target ?? 0, for (final r in readings) r.$2];
    var lo = vals.reduce((a, b) => a < b ? a : b), hi = vals.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo).abs() < 1e-6 ? 1.0 : (hi - lo) * .15;
    lo -= pad;
    hi += pad;
    double x(DateTime d) => (d.difference(from).inHours / span).clamp(0.0, 1.0) * size.width;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    canvas.drawRect(Rect.fromLTRB(x(start), 0, size.width, size.height), Paint()..color = kSeasonAccent.withValues(alpha: .08));
    if (g.from != null && g.target != null) {
      final a = Offset(x(start), y(g.from!)), b = Offset(size.width, y(g.target!));
      final dash = Paint()
        ..color = kSeasonAccent
        ..strokeWidth = 1.5;
      const n = 24;
      for (var i = 0; i < n; i += 2) {
        canvas.drawLine(Offset.lerp(a, b, i / n)!, Offset.lerp(a, b, (i + 1) / n)!, dash);
      }
      canvas.drawCircle(b - const Offset(3, 0), 3, Paint()..color = kSeasonAccent);
    }
    if (readings.isNotEmpty) {
      final path = Path()..moveTo(x(readings.first.$1), y(readings.first.$2));
      for (final r in readings.skip(1)) {
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
