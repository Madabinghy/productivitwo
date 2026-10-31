import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart' show ActivityDomainHeader;
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart' show showRoutineSheet;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show kRoutineAccent;
import 'package:productivitwo_v1/widgets/task_schedule.dart' show toggleRoutineTodayAndSchedule;

/// Lanceur de routines du FAB (maquette validée 2026-10-30) : rangé par
/// domaine, ce qui reste à faire d'abord, « Faites · n » replié en bas.
/// Une ligne = l'anneau (compte) qui ouvre le compteur, le nom (fiche), et
/// au plus UN lanceur (▶ activité liée, sinon ⏱ minuteur). Le reste (−, +,
/// chrono, minuteur, programme, réglages) vit dans le compteur.
Future<void> showRoutineLauncher(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  required VoidCallback onNew,
  required void Function(Activity linked) onChrono,
  required void Function(Activity routine) onTimer,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: .7,
      maxChildSize: .94,
      minChildSize: .3,
      expand: false,
      builder: (_, scroll) => RoutineLauncher(
        logic: logic,
        sync: sync,
        scroll: scroll,
        onNew: () {
          Navigator.pop(ctx);
          onNew();
        },
        onChrono: (a) {
          Navigator.pop(ctx);
          onChrono(a);
        },
        onTimer: (r) {
          Navigator.pop(ctx);
          onTimer(r);
        },
        onChanged: onChanged,
      ),
    ),
  );
}

class RoutineLauncher extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ScrollController? scroll;
  final VoidCallback onNew;
  final void Function(Activity linked) onChrono;
  final void Function(Activity routine) onTimer;
  final VoidCallback? onChanged;
  const RoutineLauncher({
    super.key,
    required this.logic,
    required this.sync,
    this.scroll,
    required this.onNew,
    required this.onChrono,
    required this.onTimer,
    this.onChanged,
  });

  @override
  State<RoutineLauncher> createState() => _RoutineLauncherState();
}

class _RoutineLauncherState extends State<RoutineLauncher> {
  final _search = TextEditingController();
  bool _doneOpen = false;

  AppLogic get logic => widget.logic;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  RoutineDay _day() {
    final ymd = logic.livedYmdNow;
    return buildRoutineDay(
      activities: logic.state.activeActivities,
      hits: logic.state.habitHits,
      now: DateTime.now(),
      pushed: logic.routinePushed(ymd),
      deferred: logic.state.nowSkippedByYmd[ymd] ?? const [],
      dismissed: logic.nowDoneSet(ymd),
      dayStartMin: logic.dayStartMin,
      moments: logic.moments,
    );
  }

  void _changed() {
    logic.onChange();
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  Activity? _linkedOf(Activity r) {
    final id = (r.linkedActivityId ?? '').trim();
    if (id.isEmpty) return null;
    return logic.state.activities.where((a) => a.id == id && !a.deleted).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final day = _day();
    final all = day.countAll;
    final q = _search.text.trim().toLowerCase();
    bool match(RoutineSlot s) => q.isEmpty || s.activity.name.toLowerCase().contains(q);
    final slots = day.slots.where(match).toList();
    final todo = slots.where((s) => !s.reached && !day.dismissed.contains(s.id)).toList();
    final done = slots.where((s) => s.reached || day.dismissed.contains(s.id)).toList();
    final nowLeft = day.of(day.current.key).where((s) => !s.reached && !day.dismissed.contains(s.id)).length;
    final series = day.slots.where((s) => s.activity.habitFreq == HabitFreq.daily && logic.habitCurrentStreak(s.id) > 0).length;
    final domains = logic.state.activeDomains;

    // Domaines dans leur ordre, « Sans domaine » à la fin.
    List<({Domain? domain, List<RoutineSlot> slots})> byDomain(List<RoutineSlot> list) {
      final out = <({Domain? domain, List<RoutineSlot> slots})>[];
      for (final d in domains) {
        final l = list.where((s) => s.activity.domainId == d.id).toList();
        if (l.isNotEmpty) out.add((domain: d, slots: l));
      }
      final known = domains.map((d) => d.id).toSet();
      final rest = list.where((s) => !known.contains(s.activity.domainId)).toList();
      if (rest.isNotEmpty) out.add((domain: null, slots: rest));
      return out;
    }

    ({int done, int total}) domainCount(Domain? d) {
      final l = day.slots.where((s) => (d == null ? !domains.any((x) => x.id == s.activity.domainId) : s.activity.domainId == d.id) && !day.dismissed.contains(s.id));
      return (done: l.where((s) => s.reached).length, total: l.length);
    }

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Row(children: [
          const Expanded(child: Text('Routines', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
          TextButton.icon(
            onPressed: widget.onNew,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nouvelle'),
            style: TextButton.styleFrom(foregroundColor: kRoutineAccent, visualDensity: VisualDensity.compact),
          ),
        ]),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${all.done} / ${all.total}', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
            TextSpan(text: ' aujourd\'hui · $nowLeft à faire ${day.current.thisOne}${series > 0 ? ' · 🔥 $series série${series > 1 ? 's' : ''} en cours' : ''}'),
          ]),
          style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .65)),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: all.total == 0 ? 0 : all.done / all.total,
            minHeight: 6,
            color: kRoutineAccent,
            backgroundColor: cs.onSurface.withValues(alpha: .08),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Chercher une routine…',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
            filled: true,
            fillColor: cs.onSurface.withValues(alpha: .05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _search.clear()),
                  ),
          ),
        ),
        if (todo.isEmpty && done.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(q.isEmpty ? 'Aucune routine configurée.' : 'Aucune routine ne correspond.',
                style: TextStyle(color: cs.onSurface.withValues(alpha: .5), fontStyle: FontStyle.italic)),
          ),
        if (todo.isEmpty && done.isNotEmpty && q.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 4),
            child: Text('Tout est fait pour aujourd\'hui.', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface.withValues(alpha: .7))),
          ),
        for (final g in byDomain(todo)) ...[
          Row(children: [
            Expanded(
              child: ActivityDomainHeader(
                  name: g.domain?.name ?? 'Sans domaine',
                  color: g.domain == null ? null : domainColor(g.domain!.id, domains),
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 4)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${domainCount(g.domain).done} / ${domainCount(g.domain).total}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onSurface.withValues(alpha: .45))),
            ),
          ]),
          for (final s in g.slots) _row(cs, day, s),
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: 14),
          Material(
            color: cs.onSurface.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _doneOpen = !_doneOpen),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: Color(0xFF4CBF75), shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 15, color: Color(0xFF0D1A12)),
                  ),
                  const SizedBox(width: 10),
                  Text('Faites · ${done.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      done.map((s) => s.activity.name).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .45), fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(_doneOpen ? Icons.expand_less : Icons.expand_more, size: 20, color: cs.onSurface.withValues(alpha: .5)),
                ]),
              ),
            ),
          ),
          if (_doneOpen)
            for (final g in byDomain(done)) ...[
              ActivityDomainHeader(
                  name: g.domain?.name ?? 'Sans domaine',
                  color: g.domain == null ? null : domainColor(g.domain!.id, domains),
                  padding: const EdgeInsets.fromLTRB(4, 14, 4, 4)),
              for (final s in g.slots) _row(cs, day, s),
            ],
        ],
      ],
    );
  }

  /// Ligne : anneau (compteur) · nom + une ligne d'infos (fiche) · un lanceur.
  Widget _row(ColorScheme cs, RoutineDay day, RoutineSlot s) {
    final a = s.activity;
    final t = s.todo;
    final dismissed = day.dismissed.contains(a.id);
    final linked = _linkedOf(a);
    final hasTimer = (a.timerMin ?? 0) > 0;
    final streak = a.habitFreq == HabitFreq.daily ? logic.habitCurrentStreak(a.id) : 0;
    final dc = _colorOf(a);
    final meta = <InlineSpan>[];
    void add(String text, {Color? color}) {
      if (meta.isNotEmpty) meta.add(const TextSpan(text: ' · '));
      meta.add(TextSpan(text: text, style: color == null ? null : TextStyle(color: color)));
    }

    if (dismissed) {
      add('pas aujourd\'hui');
    } else if (t.dayTarget != null) {
      if (t.dayTarget! > 1 || t.dayDone > 1) add('${t.dayDone} / ${t.dayTarget} aujourd\'hui');
      if (!s.reached) {
        final share = s.share;
        add(share != null ? share.label : momentOf(s.moment).thisOne, color: dc);
      }
    } else {
      add(t.progressLabel);
      if (!s.reached && s.moment != kMomentAllDay && s.moment != kMomentAny) add(momentOf(s.moment).thisOne, color: dc);
    }
    if (streak > 0) add('🔥 $streak j', color: dc);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openFiche(a),
      onLongPress: () => _openCounter(a),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _openCounter(a),
            child: _ring(cs, s, dc, dismissed: dismissed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Opacity(
              opacity: dismissed ? .5 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.2)),
                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text.rich(TextSpan(children: meta),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .5))),
                  ),
              ]),
            ),
          ),
          // Routine faite (retour user 2026-10-30) : − / + sur la ligne pour
          // corriger ou en ajouter sans ouvrir la fiche ni le compteur.
          if (s.reached && !dismissed) ...[
            const SizedBox(width: 6),
            _miniBtn(cs, dc, Icons.remove_rounded, t.dayDone > 0 ? () => _bump(a, -1) : null),
            const SizedBox(width: 6),
            _miniBtn(cs, dc, Icons.add_rounded, () => _bump(a, 1), accent: true),
          ],
          if (!s.reached && !dismissed && (linked != null || hasTimer)) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: linked != null ? 'Chrono sur « ${linked.name} »' : 'Minuteur ${a.timerMin} min',
              child: Material(
                color: dc.withValues(alpha: .14),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => linked != null ? widget.onChrono(linked) : widget.onTimer(a),
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(linked != null ? Icons.play_arrow_rounded : Icons.timer_outlined, size: 20, color: dc),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  void _bump(Activity a, int d) {
    logic.incHabitWithAssocEvent(a.id, d, logic.livedToday);
    _changed();
  }

  /// Couleur du domaine de la routine (essai 2026-10-31, comme le lanceur d'activités) ; orange sans domaine.
  Color _colorOf(Activity a) => domainColor(a.domainId, logic.state.activeDomains) ?? kRoutineAccent;

  Widget _miniBtn(ColorScheme cs, Color dc, IconData icon, VoidCallback? onTap, {bool accent = false}) => Material(
        color: accent ? dc.withValues(alpha: .14) : cs.onSurface.withValues(alpha: .07),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 19, color: onTap == null ? cs.onSurface.withValues(alpha: .2) : (accent ? dc : cs.onSurface.withValues(alpha: .7))),
          ),
        ),
      );

  Widget _ring(ColorScheme cs, RoutineSlot s, Color dc, {required bool dismissed}) {
    final on = ThemeData.estimateBrightnessForColor(dc) == Brightness.dark ? Colors.white : const Color(0xFF0D1A12);
    final t = s.todo;
    final target = t.dayTarget ?? t.weekTarget;
    final count = t.dayTarget != null ? t.dayDone : t.weekDone;
    final progress = target <= 0 ? 0.0 : (count / target).clamp(0.0, 1.0).toDouble();
    const size = 40.0;
    final label = s.reached
        ? (count > target ? '$count' : null)
        : count == 0
            ? null
            : (target <= 9 ? '$count/$target' : '$count');
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        if (s.reached)
          Container(decoration: BoxDecoration(color: dc, shape: BoxShape.circle))
        else
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 4,
              strokeCap: StrokeCap.round,
              color: dc,
              backgroundColor: cs.onSurface.withValues(alpha: .1),
            ),
          ),
        if (label != null)
          Text(label,
              style: TextStyle(
                  fontSize: label.length > 3 ? 9.5 : 11,
                  fontWeight: FontWeight.w900,
                  color: s.reached ? on : cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()]))
        else if (s.reached)
          Icon(Icons.check_rounded, size: 20, color: on)
        else
          Icon(Icons.add_rounded, size: 20, color: dismissed ? cs.onSurface.withValues(alpha: .3) : dc),
      ]),
    );
  }

  Future<void> _openFiche(Activity a) async {
    await showRoutineSheet(context, logic: logic, habitId: a.id, day: logic.livedToday, onSaved: _changed);
    if (mounted) setState(() {});
  }

  /// Compteur d'une routine : − compte +, puis les gestes rares.
  Future<void> _openCounter(Activity a) async {
    final linked = _linkedOf(a);
    final domain = logic.state.domains.where((d) => d.id == a.domainId).firstOrNull;
    final dc = _colorOf(a);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final cs = Theme.of(ctx).colorScheme;
        final day = _day();
        final s = day.slots.where((x) => x.id == a.id).firstOrNull;
        final t = s?.todo;
        final daily = t?.dayTarget != null;
        final count = t == null ? 0 : (daily ? t.dayDone : t.weekDone);
        final target = t == null ? 1 : (daily ? t.dayTarget! : t.weekTarget);
        final todayN = t?.dayDone ?? 0;
        final streak = a.habitFreq == HabitFreq.daily ? logic.habitCurrentStreak(a.id) : 0;
        final splits = splitMomentsOf(a);
        void bump(int d) {
          logic.incHabitWithAssocEvent(a.id, d, logic.livedToday);
          _changed();
          setS(() {});
        }

        Widget roundBtn(IconData icon, VoidCallback? onTap, {bool accent = false}) => Material(
              color: accent ? dc.withValues(alpha: .18) : cs.onSurface.withValues(alpha: .08),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: Icon(icon, size: 26, color: onTap == null ? cs.onSurface.withValues(alpha: .2) : (accent ? dc : cs.onSurface.withValues(alpha: .7))),
                ),
              ),
            );
        Widget opt(IconData icon, String label, String? hint, VoidCallback onTap) => ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(icon, size: 20),
              title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              trailing: hint == null ? null : Text(hint, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .5))),
              onTap: onTap,
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
                  if (splits.length >= 2) 'répartie ${splits.map((k) => momentOf(k).label.toLowerCase()).join(' · ')}',
                  if (streak > 0) '🔥 série de $streak j',
                ].join(' · '),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .5)),
              ),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                roundBtn(Icons.remove_rounded, todayN > 0 ? () => bump(-1) : null),
                SizedBox(
                  width: 120,
                  child: Column(children: [
                    Text('$count / $target',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
                    Text(daily ? 'aujourd\'hui' : 'sur 7 j',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onSurface.withValues(alpha: .5))),
                  ]),
                ),
                roundBtn(Icons.add_rounded, () => bump(1), accent: true),
              ]),
              if (s?.share case final share? when !(s!.reached))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(share.label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: dc)),
                ),
              const SizedBox(height: 10),
              if (linked != null)
                opt(Icons.play_arrow_rounded, 'Chrono sur ${linked.name}', 'activité liée', () {
                  Navigator.pop(ctx);
                  widget.onChrono(linked);
                }),
              opt(Icons.timer_outlined, 'Minuteur', (a.timerMin ?? 0) > 0 ? '${a.timerMin} min' : null, () {
                Navigator.pop(ctx);
                widget.onTimer(a);
              }),
              opt(a.todayFlag ? Icons.star_rounded : Icons.star_outline_rounded, a.todayFlag ? 'Retirer du programme' : 'Mettre au programme',
                  a.todayFlag ? null : 'heure + durée', () async {
                final changed = await toggleRoutineTodayAndSchedule(ctx, widget.sync, logic, a);
                if (changed) _changed();
                setS(() {});
              }),
              opt(Icons.tune_rounded, 'Réglages de la routine', 'moments, cible…', () {
                Navigator.pop(ctx);
                _openFiche(a);
              }),
            ]),
          ),
        );
      }),
    );
    if (mounted) setState(() {});
  }
}
