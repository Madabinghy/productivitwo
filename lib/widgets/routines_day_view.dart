import 'package:productivitwo_v1/utils/long_haul.dart' show kRoutineCountTiers;
import 'package:productivitwo_v1/utils/badges_logic.dart' show fmtInt;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/widgets/moments_editor_sheet.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/utils/routines_today.dart' show todayMark;
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;
import 'package:productivitwo_v1/widgets/moment_card.dart';
import 'package:productivitwo_v1/widgets/moment_item.dart';
import 'package:productivitwo_v1/widgets/ring_painter.dart';
import 'package:productivitwo_v1/widgets/routine_chrono_pill.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart' show showRoutineSheet;
import 'package:productivitwo_v1/utils/badges_logic.dart' show routineBadge;
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart' show showBadgeSheet;
import 'package:productivitwo_v1/widgets/badge_painter.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart';
import 'package:productivitwo_v1/widgets/acquired_view.dart' show AcquiredSection;

/// Orange des routines (handoff « Segment Routines », 2026-10).
const kRoutineAccent = Color(0xFFE07B39);

/// Occurrences d'aujourd'hui (depuis le début de la journée VÉCUE : 5 h par
/// défaut, réglable) d'une routine.
int routineTodayCount(AppLogic logic, Activity a) {
  final start = livedDayStart(DateTime.now(), logic.dayStartMin);
  return logic.state.habitHits.where((h) => h.habitId == a.id && !h.ts.isBefore(start)).length;
}

/// −1 : même règle que « Le meilleur à faire » — le dernier incrément
/// enregistré saute (compteur ET hit), sur la journée vécue de ce hit.
/// Retourne false s'il n'y avait rien à retirer.
bool routineMinus(AppLogic logic, Activity a) {
  final hits = logic.state.habitHits.where((h) => h.habitId == a.id).toList()..sort((x, y) => x.ts.compareTo(y.ts));
  if (hits.isEmpty) return false;
  logic.incHabit(a.id, -1, livedDate(hits.last.ts, logic.dayStartMin));
  return true;
}

/// +1 : incrémente et sort la routine des « Pas maintenant » du jour.
void routinePlus(AppLogic logic, Activity a) {
  logic.incHabit(a.id, 1, livedDate(DateTime.now(), logic.dayStartMin));
  final ymd = logic.livedYmdNow;
  if (logic.nowSkippedSet(ymd).contains(a.id)) {
    logic.setNowSkipped(ymd, logic.nowSkippedSet(ymd)..remove(a.id));
  }
}

/// Ce que vaut UNE occurrence de plus : « Footing +1 · 2 / 3 cette semaine »
/// (compte sur la fenêtre de la routine : jour, 7 j ou 30 j), avec l'état
/// atteint le cas échéant. Logique d'affichage partagée.
String routinePlusLabel(AppLogic logic, Activity a) {
  final done = logic.activeHabitDone(a);
  final target = logic.activeHabitTarget(a);
  final period = switch (a.habitFreq) { HabitFreq.weekly => 'cette semaine', HabitFreq.monthly => 'ce mois', _ => 'aujourd\u2019hui' };
  final reached = target > 0 && done >= target;
  // Au-delà de la cible : le +1 compte quand même pour la carte au long cours.
  if (target > 0 && done > target) {
    final total = logic.state.habitHits.where((h) => h.habitId == a.id).length;
    final next = kRoutineCountTiers.where((t) => t > total).firstOrNull;
    return '${a.name} · +1 bonus · ${fmtInt(total)} fois au total${next == null ? '' : ' · palier $next dans ${next - total}'}';
  }
  return '${a.name} +1 · $done / $target $period${reached ? ' · atteinte' : ''}';
}

/// +1 depuis un geste HORS des listes de routines (carte Objectif du moment,
/// Badges visés, fiche badge, lignes d'un objectif) : le compte change sans
/// qu'on le voie, donc un SnackBar dit ce qui a changé et « Annuler » retire
/// l'occurrence (`routineMinus`). 2026-10, à la suite d'un « +1 · Footing »
/// qui ne disait rien.
void routinePlusWithUndo(BuildContext context, AppLogic logic, Activity a) {
  routinePlus(logic, a);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showClosingSnackBar(SnackBar(
      content: Text(routinePlusLabel(logic, a)),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () {
          routineMinus(logic, a);
          messenger
            ..hideCurrentSnackBar()
            ..showClosingSnackBar(SnackBar(content: Text('${a.name} : +1 annulé'), duration: const Duration(seconds: 2)));
        },
      ),
    ));
}

/// Segment « Routines » d'Aujourd'hui : la journée vue par les routines —
/// carte « Routine du moment » (+1 / −1 / Pas maintenant ▾), puis la journée
/// par moments (moment courant ouvert, les autres repliés, « Toute la
/// journée » toujours ouverte). Les comptes passent par `AppLogic.incHabit` ;
/// « Pas maintenant » = fin de file (`nowSkippedSet`), « Pas aujourd'hui » =
/// écartée (`nowDoneSet`), « Cet après-midi » = report du jour
/// (`routinePushed`). Le moment de la routine n'est jamais modifié d'ici.
class RoutinesDayView extends StatefulWidget {
  final AppLogic logic;
  final VoidCallback? onOrganize;
  final void Function(RoutineDay day)? onChain;
  /// ⏱ de la carte du moment : chrono ciblé + décompte, routine cochée à la
  /// fin (même branchement que l'ancien « Le meilleur à faire »).
  final void Function(Activity routine, int minutes)? onStartTimed;
  /// Journée parfaite : seulement les routines quotidiennes pas encore
  /// atteintes, par moment (sections vides masquées, toutes dépliées).
  final bool onlyMissing;
  /// Appelé après chaque changement (+1, −1, report…) : l'hôte se recalcule.
  final VoidCallback? onChanged;
  const RoutinesDayView({super.key, required this.logic, this.onOrganize, this.onChain, this.onStartTimed, this.onlyMissing = false, this.onChanged});

  @override
  State<RoutinesDayView> createState() => _RoutinesDayViewState();
}

class _RoutinesDayViewState extends State<RoutinesDayView> {
  // Sections dépliées à la main (null = défaut : le moment courant).
  final Map<String, bool> _open = {};
  // Routine gardée dans la carte une fois sa cible atteinte (série de +1 :
  // « Pompes » cible 1, dix pompes d'affilée), jusqu'à « Suivante ».
  String? _held;

  AppLogic get logic => widget.logic;
  String get _ymd => logic.livedYmdNow;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onChanged?.call();
  }

  /// Lignes d'un moment (filtrées en mode Journée parfaite).
  List<RoutineSlot> _rowsOf(RoutineDay day, String key) => widget.onlyMissing
      ? day.of(key).where((s) => !s.reached && s.activity.habitFreq == HabitFreq.daily).toList()
      : day.of(key).where((s) => !_isDone(day, s)).toList();

  /// Faite = atteinte ou « pas aujourd'hui » (2026-10-30, comme le lanceur) :
  /// rangée dans « Faites · n » en bas. La routine gardée en carte après son
  /// dernier +1 reste à sa place jusqu'à « Suivante ».
  bool _isDone(RoutineDay day, RoutineSlot s) =>
      (s.reached || day.dismissed.contains(s.id)) && s.id != _heldSlot(day)?.id;

  bool _doneOpen = false;

  RoutineDay _day() => buildRoutineDay(
        activities: logic.state.activeActivities,
        hits: logic.state.habitHits,
        now: DateTime.now(),
        pushed: logic.routinePushed(_ymd),
        deferred: logic.state.nowSkippedByYmd[_ymd] ?? const [],
        dismissed: logic.nowDoneSet(_ymd),
        dayStartMin: logic.dayStartMin,
        moments: logic.moments,
        exclude: logic.acquiredIds,
      );

  // ── Gestes ──────────────────────────────────────────────────────────────────

  void _plus(Activity a, {bool hold = false}) {
    HapticFeedback.lightImpact();
    routinePlus(logic, a);
    setState(() {
      if (hold) _held = a.id;
    });
  }

  /// La routine gardée reste en carte tant qu'elle a au moins une occurrence
  /// aujourd'hui (nouveau jour, −1 jusqu'à zéro ou écartée = relâchée).
  RoutineSlot? _heldSlot(RoutineDay day) {
    final id = _held;
    if (id == null) return null;
    final s = day.slots.where((x) => x.id == id).firstOrNull;
    if (s == null || day.dismissed.contains(id) || _todayCount(s.activity) == 0) return null;
    return s;
  }

  void _minus(Activity a) {
    if (!routineMinus(logic, a)) return;
    HapticFeedback.selectionClick();
    setState(() {});
  }

  int _todayCount(Activity a) => routineTodayCount(logic, a);

  // ── Activité liée : chrono et liaison sans quitter Aujourd'hui ─────────────

  Activity? _linkedOf(Activity a) {
    final id = (a.linkedActivityId ?? '').trim();
    if (id.isEmpty) return null;
    return logic.state.activeActivities.where((x) => x.id == id).firstOrNull;
  }

  bool _isRunning(Activity linked) => logic.runningActivity()?.id == linked.id;

  /// ▶ = chrono libre sur l'activité liée (arrête l'éventuel chrono en cours) ;
  /// déjà dessus = stop.
  void _toggleChrono(Activity linked) {
    HapticFeedback.lightImpact();
    if (_isRunning(linked)) {
      logic.stopActive();
    } else {
      if (logic.runningActivity() != null) logic.stopActive();
      logic.start(linked.id);
    }
    logic.onChange();
    setState(() {});
  }

  /// ⏱ : durée réglée → décompte tout de suite ; sinon on choisit une durée,
  /// mémorisée comme minuteur préféré de la routine (réglable dans sa fiche).
  Future<void> _timer(Activity a) async {
    final cb = widget.onStartTimed;
    if (cb == null) return;
    final set = a.timerMin ?? 0;
    if (set > 0) {
      cb(a, set);
      return;
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Minuteur pour « ${a.name} »', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('La routine se coche toute seule à la fin. Durée mémorisée pour la prochaine fois.',
                style: TextStyle(fontSize: 12.5, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const [1, 2, 5, 10, 15, 20, 30, 45])
                ActionChip(label: Text('$m min'), onPressed: () => Navigator.pop(ctx, m)),
            ]),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    logic.setActivityTimerMin(a.id, picked);
    cb(a, picked);
  }

  Future<void> _openSheet(Activity a) async {
    await showRoutineSheet(context, logic: logic, habitId: a.id, day: DateTime.now(),
        onSaved: () {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  /// Coche : atteint la cible d'un coup ; déjà atteinte : remet à zéro.
  void _toggleReach(RoutineSlot s) {
    final a = s.activity;
    if (s.reached) {
      final n = s.todo.dayTarget != null ? _todayCount(a) : 1;
      for (var i = 0; i < n; i++) {
        _minus(a);
      }
      return;
    }
    final missing = s.todo.dayTarget != null ? s.todo.dayTarget! - s.todo.dayDone : s.todo.weekTarget - s.todo.weekDone;
    HapticFeedback.lightImpact();
    for (var i = 0; i < (missing < 1 ? 1 : missing); i++) {
      logic.incHabit(a.id, 1, livedDate(DateTime.now(), logic.dayStartMin));
    }
    setState(() {});
  }

  void _defer(Activity a) {
    final ymd = _ymd;
    final list = [...(logic.state.nowSkippedByYmd[ymd] ?? const <String>[])]..remove(a.id);
    list.add(a.id);
    logic.setNowSkipped(ymd, list.toSet());
    logic.state.nowSkippedByYmd[ymd] = list; // l'ordre du report compte
    // Restée d'un moment passé (« restée du midi ») : « plus tard ce soir »
    // la rattache aussi au moment courant, sinon elle resterait listée dans
    // Midi alors qu'on vient de décider de la faire ce soir.
    final day = _day();
    final slot = day.slots.where((s) => s.id == a.id).firstOrNull;
    final moved = slot != null && momentOf(slot.moment).timed && slot.moment != day.current.key;
    if (moved) logic.setRoutinePushed(ymd, logic.routinePushed(ymd)..[a.id] = day.current.key);
    setState(() {
      _held = null;
    });
    _toast(moved ? 'Reculée à ${day.current.thisOne} : ${a.name}' : 'Reculée en fin de file : ${a.name}');
  }

  /// Reporte la routine à un moment plus tard de la journée, après
  /// confirmation (retour user 2026-10-30 : la flèche seule ne disait pas ce
  /// qu'elle faisait) ; « Annuler » la remet dans son moment.
  Future<void> _pushTo(Activity a, Moment m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Reporter à ${m.thisOne} ?'),
        content: Text('« ${a.name} » quitte ce moment et revient ${m.thisOne} (${m.window}). Le compte du jour ne change pas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Reporter à ${m.thisOne}')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ymd = _ymd;
    final pushed = logic.routinePushed(ymd)..[a.id] = m.key;
    logic.setRoutinePushed(ymd, pushed);
    setState(() {
      _held = null;
    });
    showUndoSnackBar(context, 'Reportée à ${m.thisOne} : ${a.name}', () => _clearPush(a));
  }

  void _clearPush(Activity a) {
    logic.clearRoutinePushed(_ymd, a.id);
    if (mounted) setState(() => _held = null);
  }

  void _dismiss(Activity a) {
    final ymd = _ymd;
    logic.setNowDone(ymd, logic.nowDoneSet(ymd)..add(a.id));
    setState(() {
      _held = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showClosingSnackBar(SnackBar(
        content: Text('Pas aujourd\'hui : ${a.name}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () {
            logic.setNowDone(ymd, logic.nowDoneSet(ymd)..remove(a.id));
            if (mounted) setState(() {});
          },
        ),
      ));
  }

  void _toast(String t) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showClosingSnackBar(SnackBar(content: Text(t), duration: const Duration(milliseconds: 2600)));
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    final day = _day();
    _defaultId = (_heldSlot(day) ?? day.queue.firstOrNull)?.id;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.onlyMissing) Row(children: [
        Expanded(
          child: Text('LA JOURNÉE PAR MOMENTS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: pal.text3)),
        ),
        if (widget.onOrganize != null)
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: widget.onOrganize,
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  foregroundColor: pal.text2,
                  side: BorderSide(color: pal.track),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              child: const Text('Organiser'),
            ),
          ),
      ]),
      if (!widget.onlyMissing) const SizedBox(height: 10),
      for (final m in logic.allMoments)
        if (_rowsOf(day, m.key).isNotEmpty || (!widget.onlyMissing && m.key == day.current.key)) ...[
          _momentSection(pal, day, m),
          const SizedBox(height: 10),
        ],
      if (!widget.onlyMissing) _doneSection(pal, day),
      // Routines acquises (2026-10-30) : cochables, hors journée parfaite.
      if (!widget.onlyMissing) AcquiredSection(logic: logic, onPlus: (a) => _plus(a)),
    ]);
  }

  String _domainName(Activity a) =>
      logic.state.domains.where((d) => d.id == a.domainId).map((d) => d.name).firstOrNull ?? '';

  Widget _icon(Activity a, {double size = 26, Color? color}) => Icon(
        a.iconCode != null ? IconData(a.iconCode!, fontFamily: 'MaterialIcons') : Icons.repeat_rounded,
        size: size,
        color: color ?? kRoutineAccent,
      );

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: kBAttention.withOpacity(.14), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: kBAttention)),
      );

  /// « Une liste, un seul bloc ouvert » : la routine en avant (file du moment)
  /// est l'item ouvert par défaut ; chaque ligne s'ouvre à sa place.
  final _openItem = OpenItem();
  String? _defaultId;

  /// Bloc ouvert d'une routine ([slot]) : ne parle QUE de cette routine
  /// (retour user 2026-10-30) — le moment, sa fenêtre, son compte et
  /// « Enchaîner » vivent dans l'en-tête de la section.
  Widget _momentCard(NowPalette pal, RoutineDay day, RoutineSlot slot) {
    final cur = day.current;
    final q = day.queue;
    final heldSlot = _heldSlot(day);
    final isMoment = slot.id == (heldSlot ?? q.firstOrNull)?.id;
    final RoutineSlot? first = slot;
    final held = heldSlot != null && heldSlot.id == slot.id && heldSlot.reached;
    final todayN = _todayCount(slot.activity);
    final restee = slot.moment != cur.key && !slot.reached ? 'restée ${momentOf(slot.moment).of}' : null;
    final linked = RoutineChronoPill.linkedOf(logic, slot.activity);
    final chronoRunning = linked != null && RoutineChronoPill.isRunning(logic, linked);
    // Anneau = la progression de CETTE routine : sa part du moment si elle est
    // répartie, sinon le jour (quotidienne) ou les 7 jours.
    final t = slot.todo;
    final share = slot.reached ? null : slot.share;
    final int ringDone, ringTarget;
    final String ringWhen;
    if (share != null) {
      ringDone = share.done;
      ringTarget = share.target;
      ringWhen = momentOf(share.moment).thisOne;
    } else if (t.dayTarget != null) {
      ringDone = t.dayDone;
      ringTarget = t.dayTarget!;
      ringWhen = 'aujourd\'hui';
    } else {
      ringDone = t.weekDone;
      ringTarget = t.weekTarget;
      ringWhen = 'sur 7 j';
    }
    final ring = ringTarget <= 0 ? 0.0 : (ringDone / ringTarget).clamp(0.0, 1.0).toDouble();
    return MomentCard(
      accent: kRoutineAccent,
      eyebrow: isMoment ? 'ROUTINE DU MOMENT' : 'ROUTINE',
      pill: slot.reached ? 'atteinte' : null,
      ring: ring,
      ringBig: '${slot.reached ? '✓ ' : ''}$ringDone / $ringTarget',
      ringSmall: ringWhen,
      context_: [_domainName(slot.activity), if (restee != null) restee].where((x) => x.isNotEmpty).join(' · '),
      contextIcon: slot.activity.iconCode != null ? IconData(slot.activity.iconCode!, fontFamily: 'MaterialIcons') : Icons.repeat_rounded,
      title: slot.activity.name,
      sub: [
        if (share != null && t.dayTarget != null) '${t.dayDone} / ${t.dayTarget} aujourd\'hui',
        if (todayMark(slot.activity.habitFreq, todayN) case final mark?) mark,
      ].join(' · '),
      detail: chronoRunning ? RoutineChronoPill(logic: logic, routine: slot.activity, onChanged: () => setState(() {})) : null,
      primaryLabel: first == null ? 'Tout est fait' : (held ? 'Suivante' : '+1'),
      primaryIcon: first == null ? Icons.check_rounded : (held ? Icons.skip_next_rounded : null),
      onPrimary: first == null
          ? null
          : held
              ? () => setState(() {
                    _held = null;
                  })
              : () => _plus(first.activity, hold: true),
      moreTitle: slot.activity.name,
      moreActions: first == null
          ? const []
          : [
              if (held) MomentAction('+1 encore', icon: Icons.add, onTap: () => _plus(first.activity, hold: true)),
              if (todayN > 0) MomentAction('−1', icon: Icons.remove, hint: 'retirer la dernière occurrence', onTap: () => _minus(first.activity)),
              if (linked != null)
                MomentAction(chronoRunning ? 'Arrêter le chrono' : 'Chrono',
                    icon: chronoRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    hint: linked.name,
                    onTap: () {
                      RoutineChronoPill.toggleChrono(logic, linked);
                      setState(() {});
                    }),
              if (widget.onStartTimed != null)
                MomentAction((first.activity.timerMin ?? 0) > 0 ? 'Minuteur ${first.activity.timerMin} min' : 'Minuteur',
                    icon: Icons.timer_outlined, onTap: () => _timer(first.activity)),
              MomentAction('Plus tard ${cur.thisOne}', icon: Icons.schedule_rounded, onTap: () => _defer(first.activity)),
              if (slot.pushed)
                MomentAction('Annuler le report', icon: Icons.undo_rounded, hint: 'revient ${momentOf(slot.home).of}', onTap: () => _clearPush(first.activity)),
              for (final m in day.laterMoments)
                MomentAction('Reporter à ${m.thisOne}', icon: Icons.arrow_forward_rounded, hint: m.window, onTap: () => _pushTo(first.activity, m)),
              MomentAction('Pas aujourd\'hui', icon: Icons.block_rounded, onTap: () => _dismiss(first.activity)),
              MomentAction('Réglages de la routine', icon: Icons.tune_rounded, onTap: () => _openSheet(first.activity)),
            ],
    );
  }

  Widget _round(NowPalette pal, String label, VoidCallback? onTap,
          {double size = 44, Color? bg, Color? fg}) =>
      SizedBox(
        width: size,
        height: size,
        child: Material(
          color: bg ?? pal.chip,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: onTap == null ? Colors.white.withOpacity(.18) : (fg ?? pal.text2))),
            ),
          ),
        ),
      );

  /// « Faites · n » replié : les routines atteintes ou écartées du jour,
  /// toujours corrigeables (− / +, ouvrir).
  Widget _doneSection(NowPalette pal, RoutineDay day) {
    final done = day.slots.where((s) => _isDone(day, s)).toList();
    if (done.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _doneOpen = !_doneOpen),
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: Color(0xFF4CBF75), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 15, color: Color(0xFF0D1A12)),
                ),
                const SizedBox(width: 10),
                Text('Faites · ${done.length}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: pal.text2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(done.map((s) => s.activity.name).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.text4)),
                ),
                Icon(_doneOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18, color: pal.text4),
              ]),
            ),
          ),
        ),
        if (_doneOpen)
          for (final s in done) _row(pal, day, s),
      ]),
    );
  }

  Widget _momentSection(NowPalette pal, RoutineDay day, Moment m) {
    final isCur = m.key == day.current.key;
    final always = m.key == kMomentAllDay;
    final open = always || (_open[m.key] ?? (isCur || widget.onlyMissing));
    final c = day.countOf(m.key);
    final left = day.leftoverCountOf(m.key);
    final rows = _rowsOf(day, m.key);
    return Container(
      decoration: BoxDecoration(
        color: isCur ? pal.track : pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCur ? kRoutineAccent.withOpacity(.45) : kBLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: always ? null : () => setState(() => _open[m.key] = !open),
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Text(m.label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: isCur ? kRoutineAccent : pal.text3)),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      // Tap sur les horaires = régler les bornes des moments.
                      onTap: always ? null : () => showMomentsEditor(context, logic: logic, sync: logic.sync ?? FirestoreSync()),
                      child: Text(m.window, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: pal.text4)),
                    ),
                  ),
                ),
                if (left > 0) ...[_tag('$left restée${left > 1 ? 's' : ''}'), const SizedBox(width: 10)],

                Text(widget.onlyMissing ? '${rows.length} à faire' : '${c.done} / ${c.total}',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: pal.text2, fontFeatures: const [FontFeature.tabularFigures()])),
                if (!always) ...[
                  const SizedBox(width: 6),
                  Icon(open ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18, color: pal.text4),
                ],
              ]),
            ),
          ),
        ),
        // « Enchaîner » sur sa propre ligne : dans l'en-tête, il écrasait la
        // fenêtre du moment (« 14 h → 1… »).
        if (isCur && open && !widget.onlyMissing && widget.onChain != null && day.queue.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => widget.onChain!(day),
                style: TextButton.styleFrom(
                  foregroundColor: kRoutineAccent,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                icon: const Icon(Icons.playlist_play_rounded, size: 20),
                label: Text(day.queue.length == 1 ? 'Enchaîner la routine ${m.of}' : 'Enchaîner les ${day.queue.length} routines ${m.of}'),
              ),
            ),
          ),
        if (open)
          for (final s in rows) _row(pal, day, s),
      ]),
    );
  }

  Widget _row(NowPalette pal, RoutineDay day, RoutineSlot s) {
    final key = '${s.moment}/${s.id}';
    return MomentItem(
      key: _openItem.keyFor(key),
      padding: EdgeInsets.zero,
      open: _openItem.isOpen(key, _defaultKey(day)),
      collapsed: _line(pal, day, s),
      expanded: Padding(padding: const EdgeInsets.all(6), child: _momentCard(pal, day, s)),
      onToggle: () => _openItem.settle(key, () => setState(() => _openItem.toggle(key, _defaultKey(day)))),
      onLongPress: () => _openSheet(s.activity),
    );
  }

  String? _defaultKey(RoutineDay day) {
    final id = _defaultId;
    if (id == null) return null;
    for (final x in day.slots) {
      if (x.id == id) return '${x.moment}/${x.id}';
    }
    return null;
  }

  Widget _line(NowPalette pal, RoutineDay day, RoutineSlot s) {
    final a = s.activity;
    final done = s.reached;
    final dismissed = day.dismissed.contains(a.id);
    final n = _todayCount(a);
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(.05)))),
      child: Opacity(
        opacity: dismissed ? .45 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          child: Row(children: [
            SizedBox(
              width: 44,
              height: 44,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _toggleReach(s),
                child: Center(child: _ringCheck(pal, s, done: done)),
              ),
            ),
            _rowLauncher(pal, a, done: done),
            if (a.habitFreq == HabitFreq.daily) ...[
              const SizedBox(width: 6),
              _seriesBadge(a),
            ],
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    // Nom sur trois lignes au plus : le compte vit dans l'anneau
                    // et le ▶ dans l'icône, la ligne ne porte que − / + à droite.
                    Text(a.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: done ? pal.text3 : pal.text,
                            decoration: done ? TextDecoration.lineThrough : null,
                            decorationColor: pal.text3)),
                    if (todayMark(a.habitFreq, n) case final mark?)
                      Text('$mark · ${s.todo.progressLabel}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kRoutineAccent)),
                    if (s.share case final share? when !done)
                      Text(share.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kRoutineAccent)),
                    if (s.pushed)
                      GestureDetector(
                        onTap: () => _clearPush(a),
                        child: Text('reportée · revenir ${momentOf(s.home).of}',
                            style: const TextStyle(fontSize: 11, color: kBAttention, decoration: TextDecoration.underline, decorationColor: kBAttention)),
                      ),
                    if (dismissed) Text('pas aujourd\'hui', style: TextStyle(fontSize: 11, color: pal.text4)),
                  ]),
              ),
            ),
            _round(pal, '−', n > 0 || (s.todo.dayTarget == null && s.todo.weekDone > 0) ? () => _minus(a) : null),
            const SizedBox(width: 6),
            _round(pal, '+', () => _plus(a), bg: kRoutineAccent.withOpacity(.14), fg: kRoutineAccent),
          ]),
        ),
      ),
    );
  }

  /// Coche d'une ligne = anneau de progression (comme la carte du moment) :
  /// se remplit avec les occurrences, « 2/3 » au centre quand la cible dépasse
  /// 1 ; atteinte = disque plein avec ✓, ou le compte « 7/1 » quand on a
  /// dépassé (la série de pompes reste lisible).
  Widget _ringCheck(NowPalette pal, RoutineSlot s, {required bool done}) {
    final target = s.todo.dayTarget ?? s.todo.weekTarget;
    final count = s.todo.dayTarget != null ? s.todo.dayDone : s.todo.weekDone;
    final progress = target <= 0 ? 0.0 : (count / target).clamp(0.0, 1.0).toDouble();
    final over = count > target;
    final String? center = done ? (over ? '$count/$target' : null) : (target > 1 && count > 0 ? '$count/$target' : null);
    const size = 30.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        if (done)
          Container(decoration: const BoxDecoration(color: kRoutineAccent, shape: BoxShape.circle))
        else
          CustomPaint(
            size: const Size(size, size),
            painter: RingPainter(
                progress: progress, color: kRoutineAccent, stroke: 2.5, trackColor: pal.track, cap: StrokeCap.round),
          ),
        if (center != null)
          Text(center,
              style: TextStyle(
                  fontSize: center.length > 3 ? 8 : 9.5,
                  fontWeight: FontWeight.w800,
                  color: done ? kBBg : pal.text2,
                  fontFeatures: const [FontFeature.tabularFigures()]))
        else if (done)
          const Icon(Icons.check_rounded, size: 16, color: kBBg),
      ]),
    );
  }

  /// Icône de la routine ; avec une activité liée, elle devient le lanceur :
  /// ▶ dans un rond orange (■ rouge si le chrono tourne dessus), appui long =
  /// changer l'activité via la fiche.
  /// Le badge de série de la routine (36 px) ; tap = sa fiche (paliers, bande
  /// des 30 derniers jours, comment l'obtenir).
  Widget _seriesBadge(Activity a) {
    final b = routineBadge(a, logic.state.habitHits, DateTime.now(), dayStartMin: logic.dayStartMin, bridged: logic.bridgedOf(a.id), frozen: logic.frozenOf(a.id));
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => showBadgeSheet(context, b, logic: logic),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Opacity(opacity: b.acquired ? 1 : .6, child: BadgeView(state: b, size: 36)),
      ),
    );
  }

  Widget _rowLauncher(NowPalette pal, Activity a, {required bool done}) {
    final linked = _linkedOf(a);
    if (linked == null) {
      return SizedBox(width: 32, child: Center(child: _icon(a, size: 20, color: done ? pal.text4 : kRoutineAccent)));
    }
    final running = _isRunning(linked);
    final color = running ? kBAttention : kRoutineAccent;
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: color.withOpacity(running ? .18 : .14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _toggleChrono(linked),
          onLongPress: () => _openSheet(a),
          child: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 19, color: color),
        ),
      ),
    );
  }
}
