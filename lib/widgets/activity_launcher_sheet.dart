import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/budget_window.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/half_days.dart' show ActivityPace, minutesByActivityDay, paceOn;
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/week_stats.dart' show minutesByActivity;
import 'package:productivitwo_v1/widgets/activity_picker.dart' show ActivityDomainHeader;
import 'package:productivitwo_v1/widgets/status_row.dart' show ExpectedBar;

const _kChrono = Color(0xFF3FC7A0);
const _kLate = Color(0xFFE8A33D);
const _kOnTrack = Color(0xFF4CBF75);

/// Texte / icône lisible sur un fond de la couleur du domaine.
Color _onColor(Color c) => ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : const Color(0xFF0D1A12);

/// Une activité lue pour le lanceur : fait aujourd'hui, et sur la fenêtre de
/// budget face à son minimum (même lecture que la page domaine).
class LauncherRow {
  final Activity a;
  final int todayMin;
  final int windowMin;
  final int expectedMin;
  /// Minimum sur toute la fenêtre (fin de la barre).
  final int totalMin;
  final bool dormant;
  const LauncherRow(this.a,
      {required this.todayMin, required this.windowMin, required this.expectedMin, this.totalMin = 0, required this.dormant});
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
        totalMin: a.goalMin * days,
        dormant: (month[a.id] ?? 0) == 0);
    out.add(r.behind && r.dormant
        ? LauncherRow(a, todayMin: r.todayMin, windowMin: r.windowMin, expectedMin: r.expectedMin, totalMin: r.totalMin, dormant: false)
        : r);
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
  // Focus (défaut à chaque ouverture) = seulement les activités dont la cible
  // du jour n'est pas atteinte, toujours rangées par domaine. Une recherche
  // montre tout.
  bool _focus = true;
  Map<String, ActivityPace> _watch = const {};
  bool _focusing = false;
  Timer? _tick;

  /// Barre des 7 jours glissants : couleur = tout ce qui est fait, trait
  /// blanc = les 6 jours passés, du trait au bout = la cible du jour.
  Widget _rollingBar(ColorScheme cs, ActivityPace p, Color color) {
    final total = p.expectedMin <= 0 ? 1 : p.expectedMin;
    final past = (p.pastMin / total).clamp(0.0, 1.0).toDouble();
    final done = (p.doneMin / total).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 11,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: 3,
            height: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(children: [
                Positioned.fill(child: ColoredBox(color: cs.onSurface.withValues(alpha: .08))),
                Positioned(left: 0, top: 0, bottom: 0, width: w * done, child: ColoredBox(color: color)),
              ]),
            ),
          ),
          if (past > 0)
            Positioned(
              left: (w * past - 1).clamp(0.0, w - 2),
              top: 0,
              bottom: 0,
              width: 2,
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
            ),
        ]);
      }),
    );
  }

  Map<String, ActivityPace> _watchPace(DateTime now) {
    final st = logic.state;
    final resting = {for (final d in st.activeDomains) if (logic.isDomainResting(d.id)) d.id};
    final pace = paceOn(now,
        activities: st.activities.where((a) => !resting.contains(a.domainId)).toList(),
        minutes: minutesByActivityDay(st.sessions, now),
        frozenOf: (a) => logic.frozenOf(a.id));
    return {for (final p in pace) p.activity.id: p};
  }

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
    // Focus = les activités pas encore COUVERTES pour la Montre suisse (7 × le
    // minimum sur les 7 derniers jours glissants, retour user 2026-10-31) : ce
    // qui se joue vraiment ce soir, pas l'anneau du jour.
    _watch = _watchPace(now);
    final toReach = all.where((r) => _watch[r.a.id] != null && !_watch[r.a.id]!.onPace).toList();
    final focusing = _focus && q.isEmpty;
    _focusing = focusing;
    final active = focusing ? toReach : rows.where((r) => !r.dormant).toList();
    final dormant = focusing ? <LauncherRow>[] : rows.where((r) => r.dormant).toList()
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
          const Text('Activités', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const InfoDot(kRuleActivityPace),
          const Spacer(),
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
        const SizedBox(height: 10),
        _focusToggle(cs, toReach.length),
        if (focusing && toReach.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
            child: Column(children: [
              Icon(Icons.check_circle_rounded, size: 36, color: cs.primary),
              const SizedBox(height: 8),
              const Text('Tout est couvert pour la Montre suisse', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              TextButton(onPressed: () => setState(() => _focus = false), child: const Text('Voir toutes les activités')),
            ]),
          )
        else if (rows.isEmpty)
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

  Widget _focusToggle(ColorScheme cs, int toReach) {
    final searching = _search.text.trim().isNotEmpty;
    return Row(children: [
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: true, label: Text('Focus · $toReach'), icon: const Icon(Icons.center_focus_strong_rounded, size: 16)),
          const ButtonSegment(value: false, label: Text('Tout')),
        ],
        selected: {_focus},
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        onSelectionChanged: (s) => setState(() => _focus = s.first),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          searching ? 'recherche dans toutes' : (_focus ? 'pas encore couvertes sur 7 jours · Montre suisse' : 'toutes les activités'),
          maxLines: 2,
          style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .5), fontWeight: FontWeight.w600),
        ),
      ),
    ]);
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
    final dc = domainColor(running.domainId, logic.state.activeDomains) ?? _kChrono;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(colors: [dc.withValues(alpha: .22), dc.withValues(alpha: .06)]),
        border: Border.all(color: dc.withValues(alpha: .45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.circle, size: 8, color: dc),
          const SizedBox(width: 8),
          Text('EN COURS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: dc)),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text(running.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          Text(time,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: dc, fontFeatures: const [FontFeature.tabularFigures()])),
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
    final late = r.behind;
    final watch = _watch[a.id];
    // En Focus, la ligne parle le langage du filtre : 7 jours glissants,
    // fait / 7 × le minimum, sans repère (le but = le bout de la barre).
    final rolling = _focusing && watch != null;
    final String sub;
    if (rolling && !watch.onPace) {
      final target = watch.dayTargetMin;
      sub = r.todayMin == 0 && target > a.goalMin * 1.2
          ? 'cible du jour ${fmtMin(target)} · d\'habitude ${fmtMin(a.goalMin)}'
          : '${fmtMin(r.todayMin)} / ${fmtMin(target)} aujourd\'hui · reste ${fmtMin(watch.missingMin)}';
    } else {
      sub = [
        r.todayMin == 0 ? 'rien aujourd\'hui' : '${fmtMin(r.todayMin)} aujourd\'hui',
        if (watch != null && !watch.onPace) 'reste ${fmtMin(watch.missingMin)} pour la Montre suisse'
        else if (r.hasGoal) 'objectif ${fmtMin(a.goalMin)} / j',
      ].join(' · ');
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => widget.onOpenFiche(a),
      onLongPress: () => _openLaunchOptions(a, r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(children: [
          _dayRing(cs, r, color, watch: rolling ? watch : null),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(a.name,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.2)),
                ),
                if (rolling) ...[
                  const SizedBox(width: 8),
                  Text('${fmtMin(watch.doneMin)} / ${fmtMin(watch.expectedMin)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: watch.onPace ? _kOnTrack : _kLate,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ] else if (r.hasGoal) ...[
                  const SizedBox(width: 8),
                  Text('${fmtMin(r.windowMin)} / ${fmtMin(r.totalMin)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: late ? _kLate : _kOnTrack,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .5))),
              ),
              // Barre de la fiche objectif : fin = minimum de toute la
              // fenêtre, repère = attendu à ce jour.
              if (rolling)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 3),
                  child: _rollingBar(cs, watch, color),
                )
              else if (r.hasGoal)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: ExpectedBar(
                      done: r.windowMin, total: r.totalMin, expected: r.expectedMin, color: late ? _kLate : _kOnTrack, height: 5),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: isRunning ? 'En cours' : 'Lancer le chrono',
            child: Material(
              color: (isRunning ? const Color(0xFFE5675B) : color).withValues(alpha: .15),
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
                      size: 22, color: isRunning ? const Color(0xFFE5675B) : color),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// Icône dans un anneau = la cible du JOUR (fait aujourd'hui / minimum par
  /// jour), comme l'anneau des routines ; plein une fois atteinte. En Focus
  /// ([watch]), la cible du jour = du trait des 6 jours au bout de la barre.
  Widget _dayRing(ColorScheme cs, LauncherRow r, Color color, {ActivityPace? watch}) {
    final a = r.a;
    final icon = a.iconCode != null ? IconData(a.iconCode!, fontFamily: 'MaterialIcons') : Icons.timer_outlined;
    const size = 40.0;
    if (!r.hasGoal) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: .16), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: color),
      );
    }
    final target = watch?.dayTargetMin ?? a.goalMin;
    final reached = watch != null ? watch.onPace : r.todayMin >= a.goalMin;
    return Tooltip(
      message: '${fmtMin(r.todayMin)} / ${fmtMin(target)} aujourd\'hui',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          if (reached)
            Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle))
          else
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: (target <= 0 ? 1.0 : r.todayMin / target).clamp(0.0, 1.0).toDouble(),
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: cs.onSurface.withValues(alpha: .1),
              ),
            ),
          Icon(reached ? Icons.check_rounded : icon, size: 18, color: reached ? _onColor(color) : color),
        ]),
      ),
    );
  }

  /// Appui long : lancer sans limite, avec une durée, ou un Deep work.
  Future<void> _openLaunchOptions(Activity a, LauncherRow r) async {
    final domain = logic.state.domains.where((d) => d.id == a.domainId).firstOrNull;
    final dc = domainColor(a.domainId, logic.state.activeDomains) ?? _kChrono;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        Widget dur(String label, VoidCallback onTap, {bool deep = false}) => ActionChip(
              label: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: deep ? dc : null)),
              backgroundColor: deep ? dc.withValues(alpha: .14) : null,
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
                style: FilledButton.styleFrom(backgroundColor: dc, foregroundColor: _onColor(dc), minimumSize: const Size.fromHeight(46)),
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
