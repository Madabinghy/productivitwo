import 'package:productivitwo_v1/utils/long_haul.dart' show kRoutineCountTiers;
import 'package:productivitwo_v1/utils/linked_routines.dart' show isPlanRoutine;
import 'package:productivitwo_v1/utils/badges_logic.dart' show fmtInt;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/widgets/moments_editor_sheet.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart' show domainColor;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;
import 'package:productivitwo_v1/widgets/moment_card.dart';
import 'package:productivitwo_v1/widgets/ring_painter.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart' show showRoutineSheet;
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
  /// « Planifier ma journée » (2026-11-04) : ouvre l'écran de planification.
  final VoidCallback? onPlan;
  const RoutinesDayView({super.key, required this.logic, this.onOrganize, this.onChain, this.onStartTimed, this.onlyMissing = false, this.onChanged, this.onPlan});

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
        content: Text(logic.notTodayMessage(a)),
        duration: const Duration(seconds: 6),
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
    // Journée parfaite (maquette validée 2026-11-03 « Journée parfaite, revue ») :
    // une liste courte, une ligne par routine, saisie directe − / +.
    if (widget.onlyMissing) return _missingList(pal, day);
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
      // Fiche Routines (2026-11-03) : mêmes lignes courtes que la feuille Journée parfaite.
      _missingList(pal, day),
      const SizedBox(height: 10),
      if (!widget.onlyMissing) _doneSection(pal, day),
      // Routines acquises (2026-10-30) : cochables, hors journée parfaite.
      if (!widget.onlyMissing) AcquiredSection(logic: logic, onPlus: (a) => _plus(a)),
    ]);
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
          for (final s in done) _missingLine(pal, day, s, first: false),
      ]),
    );
  }

  Color _domainColorOf(Activity a) => domainColor(a.domainId, logic.state.domains) ?? kRoutineAccent;

  Widget _missingList(NowPalette pal, RoutineDay day) {
    final cur = day.current;
    final out = <Widget>[];
    for (final m in logic.allMoments) {
      final rows = _rowsOf(day, m.key);
      if (rows.isEmpty && (widget.onlyMissing || m.key != cur.key)) continue;
      final past = m.timed && cur.timed && m.endMin <= cur.startMin;
      final isCur = m.key == cur.key;
      final always = m.key == kMomentAllDay;
      final open = _open[m.key] ?? (past || isCur || always);
      final label = past
          ? 'Restées ${m.of}'
          : isCur
              ? m.label
              : (m.timed ? '${m.thisOne[0].toUpperCase()}${m.thisOne.substring(1)}' : m.label);
      final hot = past || isCur;
      out.add(InkWell(
        onTap: () => setState(() => _open[m.key] = !open),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
          child: Row(children: [
            if (hot) ...[
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: kRoutineAccent, shape: BoxShape.circle)),
              const SizedBox(width: 7),
            ],
            Text(label.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: hot ? kRoutineAccent : pal.text3)),
            const SizedBox(width: 8),
            Expanded(
              child: widget.onlyMissing || !m.timed
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        // Tap sur les horaires = régler les bornes des moments.
                        onTap: () => showMomentsEditor(context, logic: logic, sync: logic.sync ?? FirestoreSync()),
                        child: Text(m.window, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: pal.text4)),
                      ),
                    ),
            ),
            Text('${rows.length}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: pal.text3)),
            const SizedBox(width: 4),
            Icon(open ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 18, color: pal.text4),
          ]),
        ),
      ));
      if (isCur && widget.onChain != null && day.queue.isNotEmpty)
        out.add(Align(
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
        ));
      if (rows.isEmpty) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
          child: Text('Rien à faire ${m.thisOne}.', style: TextStyle(fontSize: 13, color: pal.text3)),
        ));
        continue;
      }
      out.add(Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBLine)),
        child: open
            ? Column(children: [
                for (var i = 0; i < rows.length; i++) _missingLine(pal, day, rows[i], first: i == 0),
              ])
            : InkWell(
                onTap: () => setState(() => _open[m.key] = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Text(rows.map((r) => r.activity.name).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.text3)),
                ),
              ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  /// Appui long sur une ligne : les gestes rares (reporter, pas aujourd'hui,
  /// réglages), qui vivaient dans l'ancienne carte « Routine du moment ».
  void _rowActions(RoutineDay day, RoutineSlot s) {
    final a = s.activity;
    final cur = day.current;
    showMomentActions(context, title: a.name, actions: [
      MomentAction('Fiche de la routine', icon: Icons.tune_rounded, onTap: () => _openSheet(a)),
      if (!s.reached) MomentAction('Plus tard ${cur.thisOne}', icon: Icons.schedule_rounded, onTap: () => _defer(a)),
      if (s.pushed) MomentAction('Annuler le report', icon: Icons.undo_rounded, hint: 'revient ${momentOf(s.home).of}', onTap: () => _clearPush(a)),
      if (!s.reached)
        for (final m in day.laterMoments)
          MomentAction('Reporter à ${m.thisOne}', icon: Icons.arrow_forward_rounded, hint: m.window, onTap: () => _pushTo(a, m)),
      if (!day.dismissed.contains(a.id) && !s.reached)
        MomentAction('Pas aujourd\'hui', icon: Icons.block_rounded, onTap: () => _dismiss(a)),
    ]);
  }

  /// Une routine qui manque : anneau à la couleur du domaine, nom, UNE ligne
  /// d'infos, lanceur seulement s'il lance quelque chose, puis − / +.
  Widget _missingLine(NowPalette pal, RoutineDay day, RoutineSlot s, {required bool first}) {
    final a = s.activity;
    final c = _domainColorOf(a);
    final t = s.todo;
    final target = t.dayTarget ?? t.weekTarget;
    final count = t.dayTarget != null ? t.dayDone : t.weekDone;
    final progress = target <= 0 ? 0.0 : (count / target).clamp(0.0, 1.0).toDouble();
    final streak = a.habitFreq == HabitFreq.daily ? logic.habitCurrentStreak(a.id) : 0;
    final linked = _linkedOf(a);
    final running = linked != null && _isRunning(linked);
    final timed = (a.timerMin ?? 0) > 0 && widget.onStartTimed != null;
    final done = s.reached;
    final dismissed = day.dismissed.contains(a.id);
    final infos = <InlineSpan>[
      if (dismissed) TextSpan(text: 'pas aujourd\'hui · ', style: TextStyle(color: pal.text4)),
      TextSpan(text: done ? '✓ $count / $target' : (s.share?.label ?? (timed ? '${a.timerMin} min' : '$count / $target')), style: TextStyle(color: c)),
      if (streak >= 2) TextSpan(text: ' · 🔥 $streak j', style: const TextStyle(color: Color(0xFFFF8A3D))),
      if (linked != null) TextSpan(text: ' · ${linked.name}'),
    ];
    Widget btn(IconData icon, VoidCallback onTap, {Color? color}) => SizedBox(
          width: 34,
          height: 34,
          child: Material(
            color: (color ?? c).withOpacity(.18),
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Icon(icon, size: 18, color: color ?? c)),
          ),
        );
    return InkWell(
      onLongPress: () => _rowActions(day, s),
      child: Container(
        decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: Colors.white.withOpacity(.05)))),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Stack(alignment: Alignment.center, children: [
              if (done)
                Container(decoration: BoxDecoration(color: c, shape: BoxShape.circle))
              else
                CustomPaint(
                  size: const Size(36, 36),
                  painter: RingPainter(progress: progress, color: c, stroke: 3.5, trackColor: pal.track, cap: StrokeCap.round),
                ),
              if (done)
                Icon(Icons.check_rounded, size: 20, color: pal.surface)
              else
                Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(a.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: done || dismissed ? pal.text3 : pal.text)),
              const SizedBox(height: 1),
              Text.rich(TextSpan(children: infos),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.text3)),
              if (s.pushed)
                GestureDetector(
                  onTap: () => _clearPush(a),
                  child: Text('reportée · revenir ${momentOf(s.home).of}', style: const TextStyle(fontSize: 11, color: kBAttention)),
                ),
            ]),
          ),
          if (!done && widget.onPlan != null && isPlanRoutine(a)) ...[
            Tooltip(message: 'Planifier maintenant', child: btn(Icons.explore_outlined, widget.onPlan!)),
            const SizedBox(width: 6),
          ] else if (linked != null) ...[
            btn(running ? Icons.stop_rounded : Icons.play_arrow_rounded, () => _toggleChrono(linked), color: running ? kBAttention : null),
            const SizedBox(width: 6),
          ] else if (timed) ...[
            btn(Icons.timer_outlined, () => _timer(a)),
            const SizedBox(width: 6),
          ],
          _round(pal, '−', count > 0 ? () => _minus(a) : null, size: 40),
          const SizedBox(width: 6),
          _round(pal, '+', () => _plus(a), size: 40, bg: c.withOpacity(.2), fg: c),
        ]),
      ),
    );
  }

}
