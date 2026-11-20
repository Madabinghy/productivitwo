import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_font.dart';
import 'package:productivitwo_v1/utils/linked_routines.dart' show isPlanRoutine;
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/widgets/routines_organize_screen.dart' show showRoutinesOrganizeScreen;
import 'package:productivitwo_v1/launcher_tab_store.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/routine_cover.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart' show ActivityDomainHeader;
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart' show showRoutineSheet;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show kRoutineAccent;
import 'package:productivitwo_v1/widgets/task_schedule.dart' show toggleRoutineTodayAndSchedule;
import 'package:productivitwo_v1/widgets/moment_card.dart' show showMomentActions, MomentAction;
import 'package:productivitwo_v1/widgets/undo_snack.dart';

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
  VoidCallback? onPlan,
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
        onPlan: onPlan == null
            ? null
            : () {
                Navigator.pop(ctx);
                onPlan();
              },
      ),
    ),
  );
}

/// L'ambre des jours ratés qu'on rattrape.
const _kCatchUp = Color(0xFFFFB866);

class RoutineLauncher extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ScrollController? scroll;
  final VoidCallback onNew;
  final void Function(Activity linked) onChrono;
  final void Function(Activity routine) onTimer;
  final VoidCallback? onChanged;
  /// « Planifier ma journée » (2026-11-04) : son lanceur ouvre la planification.
  final VoidCallback? onPlan;
  const RoutineLauncher({
    super.key,
    required this.logic,
    required this.sync,
    this.scroll,
    required this.onNew,
    required this.onChrono,
    required this.onTimer,
    this.onChanged,
    this.onPlan,
  });

  @override
  State<RoutineLauncher> createState() => _RoutineLauncherState();
}

class _RoutineLauncherState extends State<RoutineLauncher> {
  final _search = TextEditingController();
  /// Focus (par défaut à chaque ouverture) = ce qui reste à faire ; Tout = les
  /// faites aussi, à leur place dans leur domaine (retour user 2026-10-31,
  /// comme le lanceur d'activités : plus de repli « Faites » tout en bas).
  // Rouvert sur le dernier onglet choisi (Focus par défaut la première fois).
  bool _focus = LauncherTabStore.peek(LauncherTabStore.kRoutines) ?? true;

  void _setFocus(bool v) {
    setState(() => _focus = v);
    LauncherTabStore.save(LauncherTabStore.kRoutines, v);
  }

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    if (LauncherTabStore.peek(LauncherTabStore.kRoutines) == null) {
      LauncherTabStore.load(LauncherTabStore.kRoutines).then((v) {
        if (mounted && v != _focus) setState(() => _focus = v);
      });
    }
  }

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
    // Une recherche cherche dans toutes, comme dans Tout.
    final focusing = _focus && q.isEmpty;
    final shown = focusing ? todo : [...todo, ...done];
    // Sur 7 jours (2026-11-19) : tenues ce soir mais demain demandera quelque chose (prendre de l'avance),
    // et celles que l'avance couvre encore (repliées sur une ligne).
    final live = done.where((s) => !day.dismissed.contains(s.id)).toList();
    // Rattrapables (2026-11-19) : tenues ce soir, un jour raté attend encore. Le rattrapage passe avant l'avance.
    final catching = live.where((s) => s.todo.cover?.canCatchUp ?? false).toList();
    final ahead = live.where((s) => (s.todo.cover?.canGetAhead ?? false) && !(s.todo.cover?.canCatchUp ?? false)).toList();
    final covered = [
      for (final s in live)
        if (_aheadDaysOf(s) case final n?) (s, n),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
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
          // Organiser (moments, ordre) : vivait dans la fiche Routines d'Aujourd'hui, retirée le 2026-11-03.
          IconButton(
            tooltip: 'Organiser les routines',
            icon: const Icon(Icons.low_priority_rounded, size: 20),
            color: kRoutineAccent,
            visualDensity: VisualDensity.compact,
            onPressed: () => showRoutinesOrganizeScreen(context, logic: logic),
          ),
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
        const SizedBox(height: 10),
        _focusToggle(cs, todo.length, searching: q.isNotEmpty),
        if (todo.isEmpty && done.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(q.isEmpty ? 'Aucune routine configurée.' : 'Aucune routine ne correspond.',
                style: TextStyle(color: cs.onSurface.withValues(alpha: .5), fontStyle: FontStyle.italic)),
          ),
        if (focusing && todo.isEmpty && done.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 4),
            child: Row(children: [
              Expanded(
                child: Text('Tout est fait pour aujourd\'hui.',
                    style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface.withValues(alpha: .7))),
              ),
              TextButton(onPressed: () => setState(() => _focus = false), child: const Text('Voir toutes les routines')),
            ]),
          ),
        for (final g in byDomain(shown)) ...[
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
        if (focusing && catching.isNotEmpty) ...[
          Padding(
            key: const ValueKey('launcher-catching'),
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 2),
            child: Row(children: [
              const Expanded(
                child: Text('À RATTRAPER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: _kCatchUp)),
              ),
              Text('${catching.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _kCatchUp)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
            child: Text('Tenues ce soir. Ce que tu fais en plus rattrape un jour raté : la série recolle.',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: .5))),
          ),
          for (final s in catching) _row(cs, day, s, catching: true),
        ],
        if (focusing && ahead.isNotEmpty) ...[
          Padding(
            key: const ValueKey('launcher-ahead'),
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 2),
            child: Row(children: [
              const Expanded(
                child: Text('PRENDRE DE L\'AVANCE',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: kRoutineAccent)),
              ),
              Text('${ahead.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kRoutineAccent)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
            child: Text('Tenues ce soir. Ce que tu fais en plus maintenant te libère demain.',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: .5))),
          ),
          for (final s in ahead) _row(cs, day, s, ahead: true),
        ],
        if (focusing && covered.isNotEmpty) _coveredLine(cs, covered),
      ],
    );
  }

  /// Jours à venir encore couverts : avance d'une routine « sur 7 jours », ou
  /// hebdomadaire atteinte dont les coches restent dans la fenêtre. Null = pas couverte.
  int? _aheadDaysOf(RoutineSlot s) {
    final c = s.todo.cover;
    if (c != null) return c.held && c.aheadDays > 0 ? c.aheadDays : null;
    if (!s.reached) return null;
    return weeklyAheadDays(s.activity, logic.state.habitHits, DateTime.now(), dayStartMin: logic.dayStartMin);
  }

  /// « 6 couvertes · Étirements jusqu'à samedi · … » : celles auxquelles on n'a plus à penser ; tap = Tout.
  Widget _coveredLine(ColorScheme cs, List<(RoutineSlot, int)> covered) {
    final today = logic.livedToday;
    final names = [for (final c in covered.take(3)) '${c.$1.activity.name} jusqu\'à ${coveredUntilLabel(today, c.$2)}'];
    final more = covered.length - names.length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        key: const ValueKey('launcher-covered'),
        color: cs.onSurface.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _focus = false),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '${covered.length} couverte${covered.length > 1 ? 's' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF3DDC84))),
                TextSpan(text: ' · ${names.join(' · ')}${more > 0 ? ' · +$more' : ''}'),
              ]),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35, color: cs.onSurface.withValues(alpha: .6)),
            ),
          ),
        ),
      ),
    );
  }

  /// Jauge du jour d'une routine « sur 7 jours » (2026-11-19, maquette validée « Jauge des routines
  /// 7 jours ») : une case par jour que les coches d'AUJOURD'HUI achètent — ce soir à la couleur du
  /// domaine, puis demain et les jours suivants en vert. La largeur d'une case = son prix en coches.
  /// Les jours ratés à rattraper s'intercalent en ambre, avant l'avance (« Routines rattrapables »).
  Widget _dayGauge(ColorScheme cs, RoutineCover c, Color color) {
    const green = Color(0xFF3DDC84);
    const gap = 3.0;
    final slots = coverSlots(c);
    // Largeur minimale d'une case = la place de son nom (« ce soir », « dem. + sam. »).
    final minOf = [for (final s in slots) s.to > s.from ? 66.0 : (s.hole != null ? 46.0 : 38.0)];
    return LayoutBuilder(builder: (context, box) {
      // Cases déjà acquises : largeur fixe ; les autres se partagent le reste au prorata du prix.
      final fixed = [for (final s in slots) s.cost > 0 ? 0.0 : (s.to > s.from ? 84.0 : 46.0)];
      // −0,5 px : jamais de débordement par arrondi.
      final room = (box.maxWidth - .5 - gap * (slots.length - 1) - fixed.fold<double>(0, (a, b) => a + b)).clamp(0.0, double.infinity).toDouble();
      final cost = slots.fold<int>(0, (a, s) => a + s.cost);
      var widths = [for (var i = 0; i < slots.length; i++) slots[i].cost > 0 ? room * slots[i].cost / cost : fixed[i]];
      // Une case trop étroite pour son nom prend sa largeur minimale sur les autres.
      final narrow = [for (var i = 0; i < slots.length; i++) slots[i].cost > 0 && widths[i] < minOf[i]];
      final taken = [for (var i = 0; i < slots.length; i++) if (narrow[i]) minOf[i]].fold<double>(0, (a, b) => a + b);
      final wideCost = [for (var i = 0; i < slots.length; i++) if (slots[i].cost > 0 && !narrow[i]) slots[i].cost].fold<int>(0, (a, b) => a + b);
      if (taken > 0 && wideCost > 0 && room > taken) {
        widths = [
          for (var i = 0; i < slots.length; i++)
            slots[i].cost <= 0 ? fixed[i] : (narrow[i] ? minOf[i] : (room - taken) * slots[i].cost / wideCost),
        ];
      }
      var nextSeen = false;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < slots.length; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          () {
            final s = slots[i];
            final next = !s.full && !nextSeen;
            if (next) nextSeen = true;
            final fillColor = s.hole != null ? _kCatchUp : (s.from == 0 && s.cost > 0 ? color : green);
            return SizedBox(
              width: widths[i],
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: double.infinity,
                    height: 7,
                    child: Stack(alignment: Alignment.centerLeft, children: [
                      Positioned.fill(child: ColoredBox(color: cs.onSurface.withValues(alpha: .16))),
                      FractionallySizedBox(
                        widthFactor: s.fill,
                        heightFactor: 1,
                        child: DecoratedBox(decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(4))),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 4),
                Text(coverSlotLabel(c.today, s),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: s.full ? (s.hole != null ? _kCatchUp : green) : cs.onSurface.withValues(alpha: next ? .95 : .45))),
              ]),
            );
          }(),
        ],
      ]);
    });
  }

  Widget _focusToggle(ColorScheme cs, int left, {required bool searching}) => Row(children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text('Focus · $left'), icon: const Icon(Icons.center_focus_strong_rounded, size: 16)),
            const ButtonSegment(value: false, label: Text('Tout')),
          ],
          selected: {_focus},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact, textStyle: TextStyle(fontFamily: kAppFont, fontWeight: FontWeight.w800, fontSize: 13)),
          onSelectionChanged: (v) => _setFocus(v.first),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            searching ? 'recherche dans toutes' : (_focus ? 'ce qui reste à faire aujourd\'hui' : 'les faites aussi, à leur place'),
            maxLines: 2,
            style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .5), fontWeight: FontWeight.w600),
          ),
        ),
      ]);

  /// Ligne (2026-11-03, même grammaire que Journée parfaite et la fiche
  /// Routines) : anneau à la couleur du domaine, nom, UNE ligne d'infos,
  /// lanceur seulement s'il lance quelque chose, puis − / + pour saisir
  /// directement. Tap = le compteur, appui long = les gestes rares.
  Widget _row(ColorScheme cs, RoutineDay day, RoutineSlot s, {bool ahead = false, bool catching = false}) {
    // Tenue ce soir, mais la ligne propose encore quelque chose (avance ou rattrapage).
    final more = ahead || catching;
    final a = s.activity;
    final t = s.todo;
    final dismissed = day.dismissed.contains(a.id);
    final linked = _linkedOf(a);
    final hasTimer = (a.timerMin ?? 0) > 0;
    final plan = widget.onPlan != null && isPlanRoutine(a);
    final streak = a.habitFreq == HabitFreq.daily ? logic.habitCurrentStreak(a.id) : 0;
    final dc = _colorOf(a);
    final target = t.dayTarget ?? t.weekTarget;
    final count = t.dayTarget != null ? t.dayDone : t.weekDone;
    final done = s.reached;
    final muted = cs.onSurface.withValues(alpha: .5);
    final cover = t.cover;
    // La ligne d'infos passe à la ligne ENTRE deux infos, jamais au milieu (retour user 2026-11-19 :
    // « ce matin », « cet après-midi » étaient coupés) : espaces insécables dans une info, coupure après « · ».
    String nb(String v) => v.replaceAll(' ', ' ');
    // Avec « le chrono coche », on parle en minutes : 10 min la fois, encore 10 min.
    String amount(int n) => hasTimeHits(a) ? '${n * a.minPerHit!} min' : '$n';
    const sep = ' · ';
    final infos = <InlineSpan>[
      if (dismissed) TextSpan(text: '${nb('pas aujourd\'hui')}$sep'),
      TextSpan(
          text: nb(catching && cover?.nextHole != null
              ? 'encore ${amount(cover!.toNextHole)} = ${holeDayLabel(cover.today, cover.nextHole!.day)} rattrapé'
              : ahead && cover != null
                  ? 'encore ${amount(cover.toFreeTomorrow)} = demain libre'
                  : done
                  ? (cover?.heldLabel == null ? '✓ $count / $target${t.dayTarget == null ? ' sur 7 j' : ''}' : '✓ ${cover!.heldLabel}')
                  : (s.share?.label ??
                      (hasTimer && (linked == null || target <= 1)
                          ? '${a.timerMin} min'
                          : '$count / $target${t.dayTarget == null ? ' sur 7 j' : (cover != null ? ' aujourd\'hui' : '')}'))),
          style: TextStyle(color: dc)),
      if (!done && s.share == null && s.moment != kMomentAllDay && s.moment != kMomentAny)
        TextSpan(text: '$sep${nb(momentOf(s.moment).thisOne)}'),
      // « Prendre de l'avance » : la ligne ne dit que ce que le geste rapporte.
      if (!more && streak >= 2) TextSpan(text: '$sep${nb('🔥 $streak j')}', style: const TextStyle(color: Color(0xFFFF8A3D))),
      if (!more && linked != null) TextSpan(text: '$sep${nb(linked.name)}'),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openCounter(a),
      onLongPress: () => _rowActions(day, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(children: [
          _ring(cs, s, dc),
          const SizedBox(width: 12),
          Expanded(
            child: Opacity(
              opacity: dismissed ? .5 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(a.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, height: 1.2, color: done && !more ? cs.onSurface.withValues(alpha: .6) : null)),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text.rich(TextSpan(children: infos),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.3, color: muted)),
                ),
                if (cover != null && !dismissed)
                  Padding(
                    key: ValueKey('launcher-cover-bar-${a.id}'),
                    // De l'air autour de la jauge (retour user 2026-11-19 : lignes trop serrées).
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: _dayGauge(cs, cover, dc),
                  ),
                if (s.pushed)
                  GestureDetector(
                    onTap: () => _clearPush(a),
                    child: Text('reportée · revenir ${momentOf(s.home).of}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE0A030))),
                  ),
              ]),
            ),
          ),
          if ((!done || more) && !dismissed && (plan || linked != null || hasTimer)) ...[
            const SizedBox(width: 6),
            Tooltip(
              // Une durée réglée passe devant le chrono sans fin : le minuteur à cette durée (2026-11-19).
              message: plan ? 'Planifier maintenant' : (hasTimer ? 'Minuteur ${a.timerMin} min' : 'Chrono sur « ${linked!.name} »'),
              child: SizedBox(
                width: 34,
                height: 34,
                child: Material(
                  color: dc.withValues(alpha: .16),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    key: ValueKey(hasTimer && !plan ? 'launcher-timer-${a.id}' : 'launcher-go-${a.id}'),
                    onTap: () => plan ? widget.onPlan!() : (hasTimer ? widget.onTimer(a) : widget.onChrono(linked!)),
                    child: Icon(plan ? Icons.explore_outlined : (hasTimer ? Icons.timer_outlined : Icons.play_arrow_rounded), size: 18, color: dc),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 6),
          _miniBtn(cs, dc, Icons.remove_rounded, t.dayDone > 0 ? () => _bump(a, -1) : null),
          const SizedBox(width: 6),
          _miniBtn(cs, dc, Icons.add_rounded, () {
            HapticFeedback.lightImpact();
            _bump(a, 1);
          }, accent: true),
        ]),
      ),
    );
  }

  /// Gestes rares (appui long), comme dans Journée parfaite.
  void _rowActions(RoutineDay day, RoutineSlot s) {
    final a = s.activity;
    final cur = day.current;
    showMomentActions(context, title: a.name, actions: [
      MomentAction('Fiche de la routine', icon: Icons.tune_rounded, onTap: () => _openFiche(a)),
      MomentAction('Compteur', icon: Icons.exposure_rounded, hint: 'chrono, minuteur, programme', onTap: () => _openCounter(a)),
      if (!s.reached) MomentAction('Plus tard ${cur.thisOne}', icon: Icons.schedule_rounded, onTap: () => _defer(a)),
      if (s.pushed) MomentAction('Annuler le report', icon: Icons.undo_rounded, hint: 'revient ${momentOf(s.home).of}', onTap: () => _clearPush(a)),
      if (!s.reached)
        for (final m in day.laterMoments)
          MomentAction('Reporter à ${m.thisOne}', icon: Icons.arrow_forward_rounded, hint: m.window, onTap: () => _pushTo(a, m)),
      if (!day.dismissed.contains(a.id) && !s.reached)
        MomentAction('Pas aujourd\'hui', icon: Icons.block_rounded, onTap: () => _dismiss(a)),
      if (day.dismissed.contains(a.id))
        MomentAction('Remettre aujourd\'hui', icon: Icons.undo_rounded, onTap: () => _undismiss(a)),
    ]);
  }

  String get _ymd => logic.livedYmdNow;

  void _defer(Activity a) {
    final ymd = _ymd;
    final list = [...(logic.state.nowSkippedByYmd[ymd] ?? const <String>[])]..remove(a.id);
    list.add(a.id);
    logic.setNowSkipped(ymd, list.toSet());
    logic.state.nowSkippedByYmd[ymd] = list;
    final day = _day();
    final slot = day.slots.where((s) => s.id == a.id).firstOrNull;
    if (slot != null && momentOf(slot.moment).timed && slot.moment != day.current.key) {
      logic.setRoutinePushed(ymd, logic.routinePushed(ymd)..[a.id] = day.current.key);
    }
    _changed();
  }

  void _pushTo(Activity a, Moment m) {
    final ymd = _ymd;
    logic.setRoutinePushed(ymd, logic.routinePushed(ymd)..[a.id] = m.key);
    _changed();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showClosingSnackBar(SnackBar(
        content: Text('${a.name} : ${m.thisOne}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Annuler', onPressed: () => _clearPush(a)),
      ));
  }

  void _clearPush(Activity a) {
    logic.clearRoutinePushed(_ymd, a.id);
    _changed();
  }

  void _dismiss(Activity a) {
    final ymd = _ymd;
    logic.setNowDone(ymd, logic.nowDoneSet(ymd)..add(a.id));
    _changed();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showClosingSnackBar(SnackBar(
        content: Text(logic.notTodayMessage(a)),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'Annuler', onPressed: () => _undismiss(a)),
      ));
  }

  void _undismiss(Activity a) {
    final ymd = _ymd;
    logic.setNowDone(ymd, logic.nowDoneSet(ymd)..remove(a.id));
    _changed();
  }

  void _bump(Activity a, int d) {
    logic.incHabitWithAssocEvent(a.id, d, logic.livedToday);
    _changed();
  }

  /// Couleur du domaine de la routine (essai 2026-10-31, comme le lanceur d'activités) ; orange sans domaine.
  Color _colorOf(Activity a) => domainColor(a.domainId, logic.state.activeDomains) ?? kRoutineAccent;

  Widget _miniBtn(ColorScheme cs, Color dc, IconData icon, VoidCallback? onTap, {bool accent = false}) => Material(
        color: accent ? dc.withValues(alpha: .18) : cs.onSurface.withValues(alpha: .07),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 19, color: onTap == null ? cs.onSurface.withValues(alpha: .2) : (accent ? dc : cs.onSurface.withValues(alpha: .7))),
          ),
        ),
      );

  Widget _ring(ColorScheme cs, RoutineSlot s, Color dc) {
    final on = ThemeData.estimateBrightnessForColor(dc) == Brightness.dark ? Colors.white : const Color(0xFF0D1A12);
    final t = s.todo;
    final target = t.dayTarget ?? t.weekTarget;
    final count = t.dayTarget != null ? t.dayDone : t.weekDone;
    final progress = target <= 0 ? 0.0 : (count / target).clamp(0.0, 1.0).toDouble();
    const size = 36.0;
    // Gelée aujourd'hui (le minimum, une veille, un gel, une journée difficile) : un flocon sous l'anneau (retour user 2026-11-06).
    final frozen = logic.frozenOf(t.activity.id).contains(logic.livedTodayYmd);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        if (s.reached)
          Container(decoration: BoxDecoration(color: dc, shape: BoxShape.circle))
        else
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3.5,
              strokeCap: StrokeCap.round,
              color: dc,
              backgroundColor: cs.onSurface.withValues(alpha: .1),
            ),
          ),
        if (s.reached)
          Icon(Icons.check_rounded, size: 20, color: on)
        else
          Text('$count',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: dc, fontFeatures: const [FontFeature.tabularFigures()])),
        if (frozen)
          Positioned(
            bottom: -5,
            child: Container(
              key: ValueKey('launcher-frozen-${t.activity.id}'),
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
              child: Semantics(label: 'gelée aujourd’hui', child: const Icon(Icons.ac_unit_rounded, size: 13, color: Color(0xFF8FB8FF))),
            ),
          ),
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
