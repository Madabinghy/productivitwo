import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/budget_window.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/week_stats.dart' show minutesByActivity;
import 'package:productivitwo_v1/widgets/activity_picker.dart' show ActivityDomainHeader;

const _kChrono = Color(0xFF3FC7A0);
const _kLate = Color(0xFFE8A33D);

/// Une activité lue pour le lanceur : fait aujourd'hui, et sur la fenêtre de
/// budget face à son minimum (même lecture que la page domaine).
class LauncherRow {
  final Activity a;
  final int todayMin;
  final int windowMin;
  final int expectedMin;
  final bool dormant;
  const LauncherRow(this.a, {required this.todayMin, required this.windowMin, required this.expectedMin, required this.dormant});
  /// Un minimum de 1 min / j n'en est pas un (valeur par défaut des activités).
  bool get hasGoal => a.goalMin >= 5;
  bool get behind => hasGoal && windowMin < expectedMin * .95;
}

/// Lit les activités-temps pour le lanceur. Dormante = aucun chrono sur 30 j
/// et pas en retard.
List<LauncherRow> launcherRows(AppLogic logic, DateTime now) {
  final days = logic.budgetWindowDays;
  final start = budgetWindowStart(now, days);
  final idx = budgetDayIndex(now, days);
  final sessions = logic.state.sessions;
  final window = minutesByActivity(sessions, start, now);
  final today = minutesByActivity(sessions, livedDayStart(now, logic.dayStartMin), now);
  final month = minutesByActivity(sessions, now.subtract(const Duration(days: 30)), now);
  final out = <LauncherRow>[];
  for (final a in logic.state.activities) {
    if (a.deleted || a.isHabit || a.role == ActivityRole.shopping) continue;
    if (logic.isActivitySnoozed(a.id, now)) continue;
    final r = LauncherRow(a,
        todayMin: today[a.id] ?? 0,
        windowMin: window[a.id] ?? 0,
        expectedMin: a.goalMin * idx,
        dormant: (month[a.id] ?? 0) == 0);
    out.add(r.behind && r.dormant ? LauncherRow(a, todayMin: r.todayMin, windowMin: r.windowMin, expectedMin: r.expectedMin, dormant: false) : r);
  }
  return out;
}

/// Lanceur d'activités du FAB (maquette validée 2026-10-30) : le chrono en
/// cours en carte hero, puis par domaine (une activité en retard le dit dans
/// sa ligne), « Peu utilisées » repliées. ▶ lance tout de suite ; le nom ouvre
/// la fiche ; l'appui long propose une durée ou un Deep work.
Future<void> showActivityLauncher(
  BuildContext context, {
  required AppLogic logic,
  required void Function(Activity a) onStart,
  required void Function(Activity a, int minutes) onStartTimed,
  required void Function(Activity a) onDeepWork,
  required Future<void> Function(Activity a) onOpenFiche,
  required Future<void> Function() onStop,
  required VoidCallback onNew,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: .75,
      maxChildSize: .94,
      minChildSize: .3,
      expand: false,
      builder: (_, scroll) => ActivityLauncher(
        logic: logic,
        scroll: scroll,
        onStart: (a) {
          Navigator.pop(ctx);
          onStart(a);
        },
        onStartTimed: (a, m) {
          Navigator.pop(ctx);
          onStartTimed(a, m);
        },
        onDeepWork: (a) {
          Navigator.pop(ctx);
          onDeepWork(a);
        },
        onOpenFiche: (a) async {
          Navigator.pop(ctx);
          await onOpenFiche(a);
        },
        onStop: onStop,
        onNew: () {
          Navigator.pop(ctx);
          onNew();
        },
      ),
    ),
  );
}

class ActivityLauncher extends StatefulWidget {
  final AppLogic logic;
  final ScrollController? scroll;
  final void Function(Activity a) onStart;
  final void Function(Activity a, int minutes) onStartTimed;
  final void Function(Activity a) onDeepWork;
  final Future<void> Function(Activity a) onOpenFiche;
  final Future<void> Function() onStop;
  final VoidCallback onNew;
  const ActivityLauncher({
    super.key,
    required this.logic,
    this.scroll,
    required this.onStart,
    required this.onStartTimed,
    required this.onDeepWork,
    required this.onOpenFiche,
    required this.onStop,
    required this.onNew,
  });

  @override
  State<ActivityLauncher> createState() => _ActivityLauncherState();
}

class _ActivityLauncherState extends State<ActivityLauncher> {
  final _search = TextEditingController();
  bool _dormantOpen = false;
  Timer? _tick;

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && logic.runningActivity() != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final q = _search.text.trim().toLowerCase();
    final all = launcherRows(logic, now);
    final rows = all.where((r) => q.isEmpty || r.a.name.toLowerCase().contains(q)).toList();
    final running = logic.runningActivity();
    final todayTotal = all.fold<int>(0, (s, r) => s + r.todayMin);
    // Pas de section « À rattraper » (retour user 2026-10-30) : on vient au
    // lanceur pour une activité déjà choisie, on la trouve par son domaine.
    final active = rows.where((r) => !r.dormant).toList();
    final dormant = rows.where((r) => r.dormant).toList()
      ..sort((x, y) => x.a.name.toLowerCase().compareTo(y.a.name.toLowerCase()));
    final domains = logic.state.activeDomains;

    List<({Domain? domain, List<LauncherRow> rows})> byDomain(List<LauncherRow> list) {
      final out = <({Domain? domain, List<LauncherRow> rows})>[];
      int byName(LauncherRow x, LauncherRow y) => x.a.name.toLowerCase().compareTo(y.a.name.toLowerCase());
      for (final d in domains) {
        final l = list.where((r) => r.a.domainId == d.id).toList()..sort(byName);
        if (l.isNotEmpty) out.add((domain: d, rows: l));
      }
      final known = domains.map((d) => d.id).toSet();
      final rest = list.where((r) => !known.contains(r.a.domainId)).toList()..sort(byName);
      if (rest.isNotEmpty) out.add((domain: null, rows: rest));
      return out;
    }

    int domainToday(Domain? d) => all
        .where((r) => d == null ? !domains.any((x) => x.id == r.a.domainId) : r.a.domainId == d.id)
        .fold(0, (s, r) => s + r.todayMin);

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Row(children: [
          const Expanded(child: Text('Activités', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
          TextButton.icon(
            onPressed: widget.onNew,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nouvelle'),
            style: TextButton.styleFrom(foregroundColor: _kChrono, visualDensity: VisualDensity.compact),
          ),
        ]),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: todayTotal == 0 ? 'Rien' : fmtMin(todayTotal), style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
            const TextSpan(text: ' chronométré aujourd\'hui'),
          ]),
          style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .65)),
        ),
        const SizedBox(height: 12),
        if (running != null) _liveCard(cs, running, now),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Chercher une activité…',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
            filled: true,
            fillColor: cs.onSurface.withValues(alpha: .05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _search.clear())),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(q.isEmpty ? 'Aucune activité.' : 'Aucune activité ne correspond.',
                style: TextStyle(color: cs.onSurface.withValues(alpha: .5), fontStyle: FontStyle.italic)),
          ),
        for (final g in byDomain(active)) ...[
          _sectionHeader(cs, g.domain?.name ?? 'Sans domaine', g.domain == null ? null : domainColor(g.domain!.id, domains),
              domainToday(g.domain) == 0 ? null : '${fmtMin(domainToday(g.domain))} aujourd\'hui'),
          for (final r in g.rows) _row(cs, r, running),
        ],
        if (dormant.isNotEmpty) ...[
          const SizedBox(height: 14),
          Material(
            color: cs.onSurface.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _dormantOpen = !_dormantOpen),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(children: [
                  Icon(Icons.bedtime_outlined, size: 18, color: cs.onSurface.withValues(alpha: .55)),
                  const SizedBox(width: 10),
                  Text('Peu utilisées · ${dormant.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(dormant.map((r) => r.a.name).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .45), fontWeight: FontWeight.w600)),
                  ),
                  Icon(_dormantOpen ? Icons.expand_less : Icons.expand_more, size: 20, color: cs.onSurface.withValues(alpha: .5)),
                ]),
              ),
            ),
          ),
          if (_dormantOpen) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
              child: Text('Aucun chrono depuis 30 jours.', style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .45))),
            ),
            for (final r in dormant) _row(cs, r, running),
          ],
        ],
      ],
    );
  }

  Widget _sectionHeader(ColorScheme cs, String name, Color? color, String? right, {Color? textColor}) => Row(children: [
        Expanded(child: ActivityDomainHeader(name: name, color: color, padding: const EdgeInsets.fromLTRB(4, 16, 4, 4))),
        if (right != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textColor ?? cs.onSurface.withValues(alpha: .45))),
          ),
      ]);

  /// Chrono en cours : le seul élément « hero » du lanceur.
  Widget _liveCard(ColorScheme cs, Activity running, DateTime now) {
    final open = logic.state.sessions.where((s) => s.endAt == null && !s.deleted && s.activityId == running.id).firstOrNull;
    final elapsed = open == null ? Duration.zero : now.difference(open.startAt);
    String two(int n) => n.toString().padLeft(2, '0');
    final time = elapsed.inHours > 0
        ? '${elapsed.inHours}:${two(elapsed.inMinutes % 60)}:${two(elapsed.inSeconds % 60)}'
        : '${two(elapsed.inMinutes)}:${two(elapsed.inSeconds % 60)}';
    final domain = logic.state.domains.where((d) => d.id == running.domainId).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(colors: [_kChrono.withValues(alpha: .22), _kChrono.withValues(alpha: .06)]),
        border: Border.all(color: _kChrono.withValues(alpha: .45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.circle, size: 8, color: _kChrono),
          SizedBox(width: 8),
          Text('EN COURS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: _kChrono)),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text(running.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          Text(time,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _kChrono, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        if (domain != null || open != null)
          Text(
            [
              if (domain != null) domain.name,
              if (open != null) 'depuis ${two(open.startAt.hour)} h ${two(open.startAt.minute)}',
            ].join(' · '),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .65)),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () async {
                await widget.onStop();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Arrêter'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5675B), foregroundColor: const Color(0xFF1D0E0C)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => widget.onOpenFiche(running),
              child: const Text('Fiche'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _row(ColorScheme cs, LauncherRow r, Activity? running) {
    final a = r.a;
    final isRunning = running?.id == a.id;
    final color = domainColor(a.domainId, logic.state.activeDomains) ?? cs.primary;
    final windowDays = logic.budgetWindowDays;
    final meta = <InlineSpan>[];
    void add(String t, {Color? c}) {
      if (meta.isNotEmpty) meta.add(const TextSpan(text: ' · '));
      meta.add(TextSpan(text: t, style: c == null ? null : TextStyle(color: c)));
    }

    if (r.behind) {
      add('${fmtMin(r.windowMin)} / ${fmtMin(r.expectedMin)} attendues ${windowDays == 7 ? 'depuis lundi' : 'sur la quinzaine'}', c: _kLate);
      add('objectif ${fmtMin(a.goalMin)} / j');
    } else {
      add(r.todayMin == 0 ? 'rien aujourd\'hui' : '${fmtMin(r.todayMin)} aujourd\'hui');
      if (r.hasGoal) add('au rythme', c: _kChrono);
    }
    final ratio = r.expectedMin <= 0 ? 1.0 : (r.windowMin / r.expectedMin).clamp(0.0, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => widget.onOpenFiche(a),
      onLongPress: () => _openLaunchOptions(a, r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(11)),
            child: Icon(a.iconCode != null ? IconData(a.iconCode!, fontFamily: 'MaterialIcons') : Icons.timer_outlined, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.2)),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(TextSpan(children: meta),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .5))),
              ),
              if (r.hasGoal)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: ratio.toDouble(),
                      minHeight: 4,
                      color: r.behind ? _kLate : color,
                      backgroundColor: cs.onSurface.withValues(alpha: .08),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: isRunning ? 'En cours' : 'Lancer le chrono',
            child: Material(
              color: (isRunning ? const Color(0xFFE5675B) : _kChrono).withValues(alpha: .15),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: isRunning
                    ? () async {
                        await widget.onStop();
                        if (mounted) setState(() {});
                      }
                    : () => widget.onStart(a),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      size: 22, color: isRunning ? const Color(0xFFE5675B) : _kChrono),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// Appui long : lancer sans limite, avec une durée, ou un Deep work.
  Future<void> _openLaunchOptions(Activity a, LauncherRow r) async {
    final domain = logic.state.domains.where((d) => d.id == a.domainId).firstOrNull;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        Widget dur(String label, VoidCallback onTap, {bool deep = false}) => ActionChip(
              label: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: deep ? _kLate : null)),
              backgroundColor: deep ? _kLate.withValues(alpha: .14) : null,
              onPressed: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(a.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                [
                  if (domain != null) domain.name,
                  r.todayMin == 0 ? 'rien aujourd\'hui' : '${fmtMin(r.todayMin)} aujourd\'hui',
                  if (r.hasGoal) 'min ${fmtMin(a.goalMin)} / j',
                ].join(' · '),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .5)),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onStart(a);
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Lancer le chrono'),
                style: FilledButton.styleFrom(backgroundColor: _kChrono, foregroundColor: const Color(0xFF08201A), minimumSize: const Size.fromHeight(46)),
              ),
              const SizedBox(height: 14),
              Text('AVEC UNE DURÉE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: cs.onSurface.withValues(alpha: .45))),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in const [10, 20, 30, 45]) dur('$m min', () => widget.onStartTimed(a, m)),
                dur('Deep work 90', () => widget.onDeepWork(a), deep: true),
              ]),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.description_outlined, size: 20),
                title: const Text('Fiche de l\'activité', style: TextStyle(fontWeight: FontWeight.w700)),
                trailing: Text('semaine, actions, réglages', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .5))),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onOpenFiche(a);
                },
              ),
            ]),
          ),
        );
      },
    );
  }
}
