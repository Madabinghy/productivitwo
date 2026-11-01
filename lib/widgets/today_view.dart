import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/parole.dart';
import 'package:productivitwo_v1/widget_service.dart';
import 'package:productivitwo_v1/widgets/objective_readings_card.dart' show noteReadingQuick;
import 'package:productivitwo_v1/widgets/acquired_view.dart' show AcquiredPrompts;
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/widgets/deep_work_sheet.dart' show showDeepWorkSheet;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart';
import 'package:productivitwo_v1/widgets/objectives_day_view.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/widgets/focused_action_create.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/project_fiche_sheet.dart' show showProjectFiche;
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFocusedOn, kFlowTaskId;
import 'package:productivitwo_v1/utils/day_win.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/morning_three.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show isReadingDue;
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/chain_screen.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate, livedDayStart, mergeLivedDay, nextYmd;
import 'package:productivitwo_v1/utils/evening_ledger.dart';
import 'package:productivitwo_v1/widgets/daily_schedule_view.dart';
import 'package:productivitwo_v1/widgets/day_timeline_view.dart';
import 'package:productivitwo_v1/widgets/gcal_settings_sheet.dart';
import 'package:productivitwo_v1/widgets/focus_screen.dart';
import 'package:productivitwo_v1/widgets/now_card.dart';
import 'package:productivitwo_v1/widgets/now_coach_zone.dart';
import 'package:productivitwo_v1/widgets/plan_day_screen.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart';
import 'package:productivitwo_v1/widgets/routine_chain_screen.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart';
import 'package:productivitwo_v1/widgets/routines_organize_screen.dart';
import 'package:productivitwo_v1/widgets/where_we_go_screen.dart';
import 'package:productivitwo_v1/widgets/stakes_section.dart';
import 'package:productivitwo_v1/run_session_store.dart' show RunSessionStore;
import 'package:productivitwo_v1/utils/guerilla.dart' show kGuerillaKind;
import 'package:productivitwo_v1/utils/offensive.dart' show kOffensiveKind;
import 'package:productivitwo_v1/widgets/guerilla_screen.dart' show kGuerillaAccent, showGuerillaScreen;
import 'package:productivitwo_v1/widgets/offensive_screen.dart' show kOffensiveAccent, showOffensiveScreen;
import 'package:productivitwo_v1/widgets/sniper_screen.dart' show kSniperAccent, showSniperScreen;
import 'package:productivitwo_v1/widgets/card_reveal.dart' show CardRevealPrompt;
import 'package:productivitwo_v1/utils/sniper.dart' show kSniperKind;
import 'package:productivitwo_v1/utils/mode.dart' show DayMode;
import 'package:productivitwo_v1/widgets/plan_screen.dart' show showPlanScreen, kPlanAccent;
import 'package:productivitwo_v1/widgets/mode_sheet.dart' show ModePill;
import 'package:productivitwo_v1/widgets/pending_run_card.dart';
import 'package:productivitwo_v1/widgets/recharge_card.dart';
import 'package:productivitwo_v1/utils/recharge.dart' show isSleepName, bedtimePrompt;
import 'package:productivitwo_v1/widgets/watch_minimums_sheet.dart';
import 'package:productivitwo_v1/widgets/embers_view.dart' show LostYesterdaySection, EmberDots, EmberLedgerPanel;
import 'package:productivitwo_v1/utils/embers.dart' show kEmberCap;
import 'package:productivitwo_v1/utils/palier_colors.dart' show kPalierGreen, kPalierAmber;
import 'package:productivitwo_v1/widgets/dashboard_tiles.dart';
import 'package:productivitwo_v1/utils/dashboard_tiles.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/widgets/action_focus_screen.dart' show showActionFocusScreen;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/utils/week_review.dart';
import 'package:productivitwo_v1/widgets/week_review_screen.dart' show showWeekReviewScreen, WeekReviewCard, WeekIntentionCard;

/// Onglet « Aujourd'hui » : carte MAINTENANT (bloc en cours + chrono) en tête,
/// puis le programme horaire du jour, avec bascule vers « Demain » pour
/// préparer la journée suivante (planif du lendemain).
class TodayView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync? sync; // segment Objectifs (2026-10) : lecture des objectifs
  final BadgeCenter? badges; // lot 3 : signal « Badge obtenu », une fois
  // Lancer un bloc (▶) : démarre le chrono de la tâche/activité liée + focus.
  final void Function(ScheduleBlock block)? onLaunch;
  // Tap sur un bloc issu d'une source → ouvre sa fiche (tâche/routine/activité).
  final void Function(ScheduleBlock block)? onOpenSource;
  // Onglet réellement affiché ? Transmis aux vues pour que l'auto-scroll
  // « maintenant » (one-shot) attende la première ouverture visible.
  final bool visible;
  // Carte MAINTENANT (handoff iOS 2026-09) : session/minuteur en cours et
  // callbacks de l'écran principal. `onNowLaunch` lance sans changer d'onglet.
  final Project? focusProject;
  final ProjectTask? focusTask;
  final DateTime? countdownEndsAt;
  final int? countdownTotalSec;
  final void Function(ScheduleBlock block)? onNowLaunch;
  final VoidCallback? onStopTimer;
  final VoidCallback? onStopCountdown;
  final VoidCallback? onOpenRoutines;
  final VoidCallback? onOpenActivities;
  // PR 2 : onglet unique — tâche en retard → fiche projet ; résumé du jour ;
  // défi ORION de la carte coach ; minuteur d'une routine (« Le meilleur à faire »).
  final void Function(Project project, ProjectTask task)? onOpenTask;
  final VoidCallback? onOpenDayReview;
  /// Tuiles du tableau de bord (lot 3) : ouvrir l'onglet Actions / Projets.
  final VoidCallback? onOpenActions;
  final VoidCallback? onOpenProjects;
  final void Function(Activity activity, int minutes)? onStartTimed;
  /// Modes et coups (lot 2) : lancer un bloc avec un minuteur (« 10 min, malgré tout »).
  final void Function(ScheduleBlock block, int minutes)? onNowLaunchTimed;

  const TodayView(
      {super.key,
      required this.logic,
    this.badges,
    this.sync,
      this.onLaunch,
      this.onOpenSource,
      this.visible = true,
      this.focusProject,
      this.focusTask,
      this.countdownEndsAt,
      this.countdownTotalSec,
      this.onNowLaunch,
      this.onStopTimer,
      this.onStopCountdown,
      this.onOpenRoutines,
      this.onOpenActivities,
      this.onOpenTask,
      this.onOpenDayReview,
      this.onOpenActions,
      this.onOpenProjects,
      this.onStartTimed,
      this.onNowLaunchTimed});

  @override
  State<TodayView> createState() => TodayViewState();
}

class TodayViewState extends State<TodayView> {
  bool _showTomorrow = false;
  // Programme du jour : UNIQUE abonnement de l'onglet (carte MAINTENANT,
  // en-tête « n / N blocs · restantes », zone coach).
  StreamSubscription<DailySchedule?>? _schedSub, _nextSub;
  DailySchedule? _schedule, _dayDoc, _nextDoc;
  String _schedDate = '';
  // Ouvertures de l'onglet (déclencheur n° 1 de la question d'état, 24a).
  final List<DateTime> _tabOpens = [];
  // Timeline 24 h (façon Calendar) ⇄ liste compacte. La timeline est l'outil
  // de planification (drag, resize, ajout au créneau) ; la liste — vue par
  // DÉFAUT (demande user) — donne la journée d'un coup d'œil et se coche vite.
  // Le choix est persisté par appareil : l'app rouvre dans la dernière vue.
  static const _timelinePrefKey = 'today_view_timeline';
  // « Une carte, une fiche » (lot 4, 2026-10) : plus de segment Actions ·
  // Routines · Objectifs — Routines et Objectifs sont deux lignes « en
  // parallèle » sous le programme, dont la fiche héberge la vue du moment.
  List<StrategicObjective> _objectives = const [];
  bool _timeline = false;
  bool _syncing = false;
  // Badges obtenus depuis la dernière ouverture (lot 3) : montrés une fois.
  List<BadgeState> _badgeSignals = const [];
  // Scroll de la page — la jauge-minimap saute la timeline à l'heure tapée.
  final _scroll = ScrollController();
  Timer? _gaugeTick;

  @override
  void initState() {
    super.initState();
    _loadBadgeSignals();
    widget.sync?.fetchStrategicObjectives().then((all) {
      if (mounted) setState(() => _objectives = all);
    }).catchError((_) {});
    SharedPreferences.getInstance().then((p) {
      final saved = p.getBool(_timelinePrefKey);
      if (saved != null && mounted && saved != _timeline) {
        setState(() => _timeline = saved);
      }
      final morning = p.getString(_kMorningDismissed);
      final skip = p.getString(_kProjectSkipped);
      if (skip != null && mounted) setState(() => _projectSkippedRaw = skip);
      if (mounted) setState(() => _morningDismissedYmd = morning);
    });
    _subscribeSchedule();
    if (widget.visible) _tabOpens.add(DateTime.now());
    // Journée gagnée : à l'ouverture, deux journées perdues d'affilée font
    // redescendre le seuil d'un cran (sans rien demander).
    widget.logic.adaptDayGoalOnOpen(DateTime.now());
    // La jauge suit le chrono en cours + le trait « maintenant » ; passage de
    // minuit → le stream bascule sur le nouveau jour.
    _gaugeTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (widget.logic.livedTodayYmd != _schedDate) _subscribeSchedule();
      if (!_showTomorrow) setState(() {});
    });
  }

  @override
  void didUpdateWidget(TodayView old) {
    super.didUpdateWidget(old);
    if (!old.visible && widget.visible) _tabOpens.add(DateTime.now());
  }

  @override
  void dispose() {
    _gaugeTick?.cancel();
    _schedSub?.cancel();
    _nextSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _subscribeSchedule() {
    _schedSub?.cancel();
    _schedDate = widget.logic.livedTodayYmd;
    _tabOpens.clear();
    _nextSub?.cancel();
    _dayDoc = null;
    _nextDoc = null;
    // Journée vécue : le doc du lendemain apporte les blocs de la nuit.
    void recompose() {
      final merged = mergeLivedDay(_schedDate, _dayDoc, _nextDoc, widget.logic.dayStartMin);
      setState(() => _schedule = merged);
      widget.logic.todayBlocks = merged?.blocks ?? [];
      widget.badges?.liveToday = merged;
      // Widgets iOS (Journée parfaite, Maintenant…) : un bloc coché se voit tout de suite.
      WidgetService.update(widget.logic);
    }
    _schedSub = FirestoreSync().streamDailySchedule(_schedDate).listen((s) {
      if (!mounted) return;
      _dayDoc = s;
      recompose();
    });
    _nextSub = FirestoreSync().streamDailySchedule(nextYmd(_schedDate)).listen((s) {
      if (!mounted) return;
      _nextDoc = s;
      recompose();
    });
  }

  // « Le matin en trois choses » fermé à la main → plus ce jour-là.
  static const _kMorningDismissed = 'morning_three_dismissed';
  // Tuile PROJETS : projets « passés » aujourd'hui (« ymd|id,id »), jour vécu.
  static const _kProjectSkipped = 'project_tile_skipped';
  String? _projectSkippedRaw;

  Set<String> get _projectSkipped {
    final raw = _projectSkippedRaw;
    if (raw == null) return const {};
    final parts = raw.split('|');
    if (parts.length != 2 || parts[0] != widget.logic.livedTodayYmd || parts[1].isEmpty) return const {};
    return parts[1].split(',').toSet();
  }

  Future<void> _skipProjectToday(String id) async {
    final raw = '${widget.logic.livedTodayYmd}|${{..._projectSkipped, id}.join(',')}';
    setState(() => _projectSkippedRaw = raw);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProjectSkipped, raw);
  }

  /// Tuile PROJETS : la fiche du projet du moment, avec ses DÉCISIONS ; à la
  /// fermeture la tuile se recalcule (un autre projet, ou le même s'il reste
  /// le plus pertinent).
  Future<void> _openProjectTile(String? id) async {
    final p = widget.logic.currentProjects.where((x) => x.id == id).firstOrNull;
    if (p == null) {
      widget.onOpenProjects?.call();
      return;
    }
    final st = widget.logic.state;
    await showProjectFiche(context,
        project: p,
        allProjects: widget.logic.currentProjects,
        domains: st.activeDomains,
        activities: st.activeActivities,
        sessions: st.sessions,
        sync: widget.sync,
        logic: widget.logic,
        onStartTimer: (act, project, task) => widget.logic.start(act.id, taskId: task.id),
        onSkipToday: () => _skipProjectToday(p.id),
        actionsOpenFocus: true);
    if (mounted) setState(() {});
  }
  String? _morningDismissedYmd;


  Future<void> _dismissMorning(DateTime now) async {
    final k = ymdKey(now);
    setState(() => _morningDismissedYmd = k);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMorningDismissed, k);
  }


  /// « Le matin en trois choses » : avant 9 h, bloc clé + routine en retard +
  /// action en retard la plus ancienne. Disparaît dès qu'une des trois est
  /// faite, à 9 h, ou d'un ✕ pour la journée.
  Widget? _morningCard(ColorScheme cs, DateTime now, Color text3) {
    if (!isMorningWindow(now) || _morningDismissedYmd == ymdKey(now)) return null;
    final logic = widget.logic;
    final st = logic.state;
    final blocks = _liveBlocks;
    bool reached(Activity a) {
      final q = logic.dayQuotaFor(a);
      return q > 0 && logic.habitValueOn(a.id, now) >= q;
    }
    final three = MorningThree(
      keyBlock: keyBlockOf(blocks),
      routine: laggingRoutineOf(st.activeActivities,
          weekDone: (a) => rollingStatFor(a, st.habitHits)?.done ?? 0,
          weekTarget: (a) => rollingStatFor(a, st.habitHits)?.target ?? 0,
          reachedToday: reached),
      overdue: oldestOverdueOf(logic.currentProjects, now),
    );
    if (three.count < 2) return null;
    // Une des trois faite → la carte a joué son rôle.
    if (blocks.any((b) => b.status == 'done')) return null;
    final dark = cs.brightness == Brightness.dark;
    final primary = dark ? kBPrimary : cs.primary;
    final surface = dark ? kBSurface : cs.surface;
    final alert = dark ? kBAlert : cs.error;
    String hm(int min) =>
        '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

    Widget row(IconData icon, Color color, String title, String sub, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: text3)),
                ]),
              ),
              if (onTap != null) Icon(Icons.chevron_right, size: 18, color: text3),
            ]),
          ),
        );

    final b = three.keyBlock;
    final r = three.routine;
    final o = three.overdue;
    final launch = widget.onNowLaunch ?? widget.onLaunch;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withOpacity(.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.wb_twilight_rounded, size: 14, color: text3),
          const SizedBox(width: 6),
          Expanded(
            child: Text('AUJOURD\'HUI, TROIS CHOSES',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: text3)),
          ),
          IconButton(
            tooltip: 'Pas aujourd\'hui',
            visualDensity: VisualDensity.compact,
            onPressed: () => _dismissMorning(now),
            icon: Icon(Icons.close, size: 16, color: text3),
          ),
        ]),
        if (b != null)
          row(Icons.play_circle_outline, primary, b.title,
              '${hm(blockStartMin(b))} → ${hm(blockEndMin(b))} · le bloc clé',
              launch == null || (b.projectId == null && b.activityId == null) ? null : () => launch(b)),
        if (r != null)
          row(Icons.repeat_rounded, dark ? kBAttention : Colors.orange.shade700, r.name,
              'la routine la plus en retard cette semaine',
              () => showRoutineSheet(context, logic: logic, habitId: r.id, day: now,
                  onSaved: () { if (mounted) setState(() {}); })),
        if (o != null)
          row(Icons.flag_outlined, alert, o.task.title,
              '${o.project.title} · en retard depuis le ${o.task.endDate!.day}/${o.task.endDate!.month.toString().padLeft(2, '0')}',
              widget.onOpenTask == null ? null : () => widget.onOpenTask!(o.project, o.task)),
      ]),
    );
  }


  List<ScheduleBlock> get _liveBlocks =>
      (_schedule?.blocks ?? const <ScheduleBlock>[])
          .where((b) => b.status != 'deleted')
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  /// Navigation programmée vers l'onglet (lancement, widget, Siri…) : la carte
  /// MAINTENANT est en tête, on y revient.
  /// Ouvertures depuis une notification (`main.dart`, `_onNotificationTap`).
  void openProgramSheet() => _openProgramSheet();
  void openPerfectDaySheet() => _openPerfectDaySheet();
  void openStakesSheet() => _openStakesSheet();

  void scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 🗑 « Reprogrammer la journée » (réveil tardif, maladie, imprévu) :
  /// retire les blocs RESTANTS d'aujourd'hui (soft-delete — le fait reste,
  /// les miroirs Google Agenda et ce qui est fait ne bougent pas), puis
  /// rouvre la planification depuis maintenant (étape « tes blocs d'abord »
  /// incluse, cache ignoré : les contraintes viennent de changer).
  Future<void> _replanToday() async {
    final today = widget.logic.livedTodayYmd;
    final sync = FirestoreSync();
    final sched = await sync.fetchDailySchedule(today);
    final pending = (sched?.blocks ?? const <ScheduleBlock>[])
        .where((b) => b.status == 'pending' && b.gcalEventId == null)
        .toList();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reprogrammer la journée ?'),
        content: Text(pending.isEmpty
            ? 'Rien à retirer — on repart directement sur une '
                'planification depuis maintenant.'
            : 'Les ${pending.length} blocs restants d\'aujourd\'hui seront '
                'retirés (ce qui est fait et tes rendez-vous Google Agenda '
                'ne bougent pas), puis tu replanifies depuis maintenant.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Vider et replanifier'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    for (final b in pending) {
      unawaited(sync.updateBlockStatus(today, b.id, 'deleted'));
    }
    final count = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => PlanDayScreen(
        logic: widget.logic,
        targetDate: today,
        rattrapage: true,
        onLaunchBlock: widget.onLaunch,
        forceRegenerate: true,
      ),
    ));
    if (count != null && mounted) {
      ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
        content: Text('Journée reposée — $count blocs'),
        duration: const Duration(seconds: 3),
      ));
    }
    if (mounted) setState(() {});
  }

  // ── Jauge verticale 00:00 → 23:59 (façon Waze) ────────────────────────────
  //
  // Le temps LOGGUÉ du jour (dont le chrono en cours), segmenté aux couleurs
  // des DOMAINES — la composition de la journée en un coup d'œil, toute la
  // journée visible sans scroller. Le vide reste neutre translucide (pas
  // noir : le vide n'est pas une faute, et le noir disparaît en thème
  // sombre). Tap/drag = minimap → la timeline saute à cette heure.

  /// Segments loggués d'un JOUR donné (minuit → minuit), bornés à la journée.
  List<({int start, int end, Color color})> _gaugeSegments(
      DateTime day, DateTime now) {
    final dayEnd = day.add(const Duration(days: 1));
    final out = <({int start, int end, Color color})>[];
    for (final s in widget.logic.state.sessions) {
      final end = s.endAt ?? now;
      if (!end.isAfter(day) || !s.startAt.isBefore(dayEnd)) continue;
      Activity? a;
      for (final x in widget.logic.state.activities) {
        if (x.id == s.activityId) { a = x; break; }
      }
      if (a == null || a.deleted) continue;
      final st = s.startAt.isBefore(day) ? 0 : s.startAt.difference(day).inMinutes;
      final en = end.isAfter(dayEnd) ? 1440 : end.difference(day).inMinutes;
      if (en - st < 1) continue;
      out.add((
        start: st,
        end: en,
        color: domainColor(a.domainId, widget.logic.state.activeDomains) ??
            Colors.teal,
      ));
    }
    return out;
  }

  // « Scroll vers HH:mm » exposé par la vue liste (les offsets d'une liste de
  // blocs ne sont pas linéaires en temps — seule la vue sait où vit chaque bloc).
  void Function(int minute)? _listScrollToMinute;

  /// Saut minimap : minute du jour → scroll de la vue active.
  /// Timeline : offset linéaire (1 h = 100 px, ~120 px d'en-tête avant 00:00).
  /// Liste (blocs) : délégué à DailyScheduleView (bloc le plus proche).
  void _jumpTo(int minute) {
    // Aujourd'hui : le programme vit dans sa feuille, la jauge l'ouvre.
    if (!_showTomorrow) {
      _openProgramSheet();
      return;
    }
    if (!_timeline) {
      _listScrollToMinute?.call(minute);
      return;
    }
    if (!_scroll.hasClients) return;
    final target = (120.0 + minute / 60.0 * 100.0 - 220.0)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// Une bande verticale 00:00 → 23:59 d'un jour. [thin] = jauge d'HIER :
  /// plus étroite, tamisée, sans trait ni interaction — le point de
  /// comparaison, pas l'objet du jour.
  Widget _gaugeStrip(
    ColorScheme cs,
    List<({int start, int end, Color color})> segments,
    double h, {
    int? nowMin,
    bool thin = false,
  }) {
    double y(int min) => min / 1440.0 * h;
    final opacity = thin ? .45 : .85;
    return Container(
      width: thin ? 7 : 14,
      height: h,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(thin ? .05 : .08),
        borderRadius: BorderRadius.circular(thin ? 4 : 7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        for (final s in segments)
          Positioned(
            top: y(s.start),
            left: thin ? 1 : 2,
            right: thin ? 1 : 2,
            height: (y(s.end) - y(s.start)).clamp(2.0, h),
            child: Container(
              decoration: BoxDecoration(
                color: s.color.withOpacity(opacity),
                borderRadius: BorderRadius.circular(thin ? 2 : 4),
              ),
            ),
          ),
        if (nowMin != null)
          Positioned(
            top: y(nowMin) - 1,
            left: 0,
            right: 0,
            height: 2,
            child: Container(color: const Color(0xFFE53935)),
          ),
      ]),
    );
  }

  Widget _dayGauge(ColorScheme cs, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final segments = _gaugeSegments(today, now);
    // Hier COLLÉ à aujourd'hui (bande fine et tamisée) : la comparaison des
    // deux journées d'un coup d'œil — le benchmark, pas l'objet du jour.
    final ySegments =
        _gaugeSegments(today.subtract(const Duration(days: 1)), now);
    final nowMin = now.hour * 60 + now.minute;
    // À GAUCHE, CENTRÉES verticalement (demande user) : les jauges occupent
    // la moitié de la hauteur, au milieu de la page — présentes d'un coup
    // d'œil sans dominer le bord.
    return Positioned(
      top: 0,
      bottom: 0,
      left: 3,
      width: 23,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          heightFactor: .5,
          child: LayoutBuilder(builder: (gctx, box) {
            final h = box.maxHeight;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _jumpTo(
                  (d.localPosition.dy / h * 1440).round().clamp(0, 1439)),
              onVerticalDragUpdate: (d) => _jumpTo(
                  (d.localPosition.dy / h * 1440).round().clamp(0, 1439)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _gaugeStrip(cs, ySegments, h, thin: true),
                  const SizedBox(width: 2),
                  _gaugeStrip(cs, segments, h, nowMin: nowMin),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Sync agenda À LA DEMANDE (aujourd'hui + demain) : un RDV modifié côté
  /// Google est repris immédiatement dans les miroirs — utile juste avant de
  /// planifier demain, sans attendre la sync d'ouverture.
  Future<void> _forceSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final sync = FirestoreSync();
    var ok = false;
    String? reason;
    for (final d in [widget.logic.livedToday, widget.logic.livedToday.add(const Duration(days: 1))]) {
      final r = await gcalSyncDay(sync, _ymd(d));
      if (r?['ok'] == true) ok = true;
      reason ??= r?['reason'] as String?;
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
      content: Text(ok
          ? '🗓️ Agenda synchronisé — aujourd\'hui et demain sont à jour.'
          : reason == 'not_connected'
              ? 'Google Agenda non connecté — Paramètres → Google Agenda.'
              : 'Synchronisation impossible — réessaie.'),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// État vide du jour selon les domaines (Partie D) : rien de nommé → le
  /// programme ne peut pas exister ; nommé mais rien de défini → il attend le
  /// rang 1. Sinon : état vide standard (null).
  String? _domainsPlaceholder() {
    final domains =
        widget.logic.state.domains.where((d) => !d.deleted).toList();
    final named = domains.where((d) => d.definitionStatus == 'named').toList();
    final started = domains.any((d) =>
        d.definitionStatus == 'active' || d.definitionStatus == 'draft');
    if (named.isEmpty && !started) {
      return 'Ton programme apparaîtra ici.\nIl se construit à partir de tes domaines — c\'est l\'étape juste au-dessus.';
    }
    if (!started && named.isNotEmpty) {
      return 'Le programme se remplit dès que ${named.first.name} est défini — ce soir si tu veux.';
    }
    return null;
  }

  static const _kDays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

  Future<void> _openPlan(String date) async {
    final count = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => PlanDayScreen(
        logic: widget.logic,
        targetDate: date,
        rattrapage: !_showTomorrow,
        onLaunchBlock: _showTomorrow ? null : widget.onLaunch,
      ),
    ));
    if (count != null && mounted) {
      ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
        content: Text('Journée posée — $count blocs'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stakes = _showTomorrow ? null : _stakeBoard();
    final now = DateTime.now();
    // Journée vécue : avant la bascule (5 h), « aujourd'hui » = la veille.
    final date = _showTomorrow
        ? _ymd(widget.logic.livedToday.add(const Duration(days: 1)))
        : widget.logic.livedTodayYmd;
    final dark = cs.brightness == Brightness.dark;
    final text3 = dark ? kBText3 : cs.onSurface.withOpacity(.6);
    final link = dark ? kBPrimary : cs.primary;

    return SafeArea(
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scroll,
            // Padding bas généreux : dégage la rangée du FAB pour que les
            // derniers items du programme restent cochables.
            // Gauche 30 px aujourd'hui : la jauge du jour (23 px, collée au
            // bord) ne doit pas mordre sur le contenu.
            padding: EdgeInsets.fromLTRB(_showTomorrow ? 16 : 30, 12, 16, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(cs, now, text3),
                ...[
                if (!_showTomorrow) ...[
                  if (_modeLauncher(cs) case final big?) big,
                  // Recharge : la nuit hors des modes (matin avant le premier geste, soir au sommeil).
                  RechargeCard(logic: widget.logic),
                  _bedtimeCard(),
                  PendingRunCard(logic: widget.logic, badges: widget.badges),
                  // Badges en cartes (2026-11-01) : les cartes gagnées se retournent.
                  CardRevealPrompt(badges: widget.badges, onOpenAlbum: _openBadgeGallery),
                  ..._weekReviewCards(),
                  // « Ta journée » (ou « Ce soir » après 19 h) en tête, à la place de
                  // l'ancienne carte « journée gagnée » (retour user 2026-10-30).
                  if (stakes case final board? when isEvening(widget.logic.livedNowMinNow)) ...[
                    if (_eveningLedger(board) case final ledger when !ledger.isEmpty) ...[
                      const SizedBox(height: 12),
                      EveningLedgerCard(ledger: ledger, compact: true, onTap: _openStakesSheet),
                    ],
                  ] else if (stakes case final board? when !board.isEmpty) ...[
                    const SizedBox(height: 12),
                    StakeScoreboard(board: board, elapsed: dayElapsed(widget.logic.livedNowMinNow), onTap: _openStakesSheet, lostYesterday: widget.logic.lostSeriesYesterday().length),
                  ],
                  // Braises : les séries cassées hier qu'on peut rallumer (ou en attente du +1).
                  LostYesterdaySection(logic: widget.logic, onChanged: _onEmbersChanged),
                  // Routine acquise : la proposition à 66 jours, l'alerte de décrochage.
                  AcquiredPrompts(logic: widget.logic, onChanged: () {
                    widget.badges?.load(refresh: true);
                    if (mounted) setState(() {});
                  }),
                  if (_morningCard(cs, now, text3) case final card?) card,
                  // Tableau de bord en tête, le tableau du jour (ou « Ce soir »)
                  // sous le programme (retour user 2026-10-30).
                  ..._parallelSection(cs, stakes),
                  const SizedBox(height: 16),
                  NowCard(
                    badges: widget.badges,
                    logic: widget.logic,
                    blocks: _liveBlocks,
                    date: _schedDate,
                    focusProject: widget.focusProject,
                    focusTask: widget.focusTask,
                    countdownEndsAt: widget.countdownEndsAt,
                    countdownTotalSec: widget.countdownTotalSec,
                    onLaunch: widget.onNowLaunch ?? widget.onLaunch ?? (_) {},
                    onOpenSource: widget.onOpenSource,
                    onStopTimer: widget.onStopTimer ?? () {},
                    onStopCountdown: widget.onStopCountdown ?? () {},
                    onOpenRoutines: widget.onOpenRoutines,
                    onOpenActivities: widget.onOpenActivities,
                    onChain: widget.onStopTimer == null
                        ? null
                        : () => showChainScreen(
                              context,
                              logic: widget.logic,
                              sync: FirestoreSync(),
                              date: _schedDate,
                              onLaunch: widget.onNowLaunch ?? widget.onLaunch ?? (_) {},
                              onStopTimer: widget.onStopTimer!,
                              onOpenSource: widget.onOpenSource,
                            ),
                    onChainSmall: widget.onStopTimer == null
                        ? null
                        : () => showChainScreen(
                              context,
                              logic: widget.logic,
                              sync: FirestoreSync(),
                              date: _schedDate,
                              onLaunch: widget.onNowLaunch ?? widget.onLaunch ?? (_) {},
                              onStopTimer: widget.onStopTimer!,
                              onOpenSource: widget.onOpenSource,
                              small: true,
                            ),
                    onLaunchTimed: widget.onNowLaunchTimed,
                    onDeepWork: (widget.onNowLaunch ?? widget.onLaunch) == null
                        ? null
                        : () => showDeepWorkSheet(
                              context,
                              logic: widget.logic,
                              sync: widget.sync ?? FirestoreSync(),
                              date: _schedDate,
                              onLaunch: widget.onNowLaunch ?? widget.onLaunch!,
                              objectives: _objectives,
                            ),
                    onOpenFocus: widget.onStopTimer == null
                        ? null
                        : () => showFocusScreen(
                              context,
                              logic: widget.logic,
                              blocks: _liveBlocks,
                              date: _schedDate,
                              onStopTimer: widget.onStopTimer!,
                              onLaunch: widget.onNowLaunch ?? widget.onLaunch,
                              onOpenSource: widget.onOpenSource,
                            ),
                  ),
                  NowCoachZone(
                    logic: widget.logic,
                    schedule: _schedule,
                    date: _schedDate,
                    tabOpens: _tabOpens,
                    onLaunch: widget.onNowLaunch ?? widget.onLaunch,
                  ),
                ],
                // Programme du jour : dans une feuille ouverte par la tuile
                // PROGRAMME (retour user 2026-10-30) ; Demain reste sur la page.
                if (_showTomorrow) ...[
                  const SizedBox(height: 22),
                  ..._programSection(cs, link, text3, date, refresh: () => setState(() {})),
                ],
                if (_showTomorrow) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Prépare demain ce soir : un plan posé la veille se suit '
                      'beaucoup mieux le matin.',
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: cs.onSurface.withOpacity(.55)),
                    ),
                  ),
                ],
                ],
              ],
            ),
          ),
          // Jauge 00:00 → 23:59 (façon Waze) : le loggué du jour aux couleurs
          // des domaines, minimap tappable — uniquement sur Aujourd'hui.
          if (!_showTomorrow) _dayGauge(cs, now),
        ],
      ),
    );
  }

  /// En-tête (§ 3.1) : « Lundi 28 » + « 3 / 9 blocs · 6 h 15 restantes », à
  /// droite Chrono libre et ORION (44 px).
  Widget _header(ColorScheme cs, DateTime now, Color text3) {
    final day = _showTomorrow ? widget.logic.livedToday.add(const Duration(days: 1)) : widget.logic.livedToday;
    final name = _kDays[day.weekday - 1];
    final title = _showTomorrow
        ? 'Demain · ${name[0].toUpperCase()}${name.substring(1)} ${day.day}'
        : '${name[0].toUpperCase()}${name.substring(1)} ${day.day}';
    final live = _liveBlocks;
    final done = live.where((b) => b.status == 'done').length;
    final nowMin = widget.logic.livedNowMinNow;
    final remaining = remainingPlannedMin(live, nowMin);
    final sub = _showTomorrow
        ? 'Prépare la journée de demain'
        : live.isEmpty
            ? 'Pas de programme aujourd\'hui'
            : '$done / ${live.length} blocs · ${fmtMin(remaining)} restantes';
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -.3, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(sub,
              style: TextStyle(
                  fontSize: 13, color: text3, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
      // Lanceurs Guérilla et Offensive (2026-10-30, à la place de Badges et ORION : les badges restent sur la
      // tuile BADGES et l'onglet Objectifs, ORION dans le menu ⋯). Point = une session à reprendre.
      // Le mode du jour centré au-dessus des deux lanceurs (2026-10-30).
      Column(mainAxisSize: MainAxisSize.min, children: [
        if (!_showTomorrow) ...[
          ModePill(logic: widget.logic, badges: widget.badges),
          const SizedBox(height: 8),
        ],
        Row(mainAxisSize: MainAxisSize.min, children: [
          // Le mode du moment a son gros bouton sous l'en-tête (2026-11-01) : ici, les autres.
          for (final l in _launchers)
            if (_showTomorrow || l.kind != _modeKind) ...[
              _launcherBtn(cs, l.kind, l.icon, l.tooltip, l.accent, l.light),
              const SizedBox(width: 8),
            ],
          _planBtn(cs),
        ]),
      ]),
    ]);
  }

  static const _launchers = [
    (kind: kGuerillaKind, icon: Icons.bolt, tooltip: 'Guérilla · la flemme ou moi', accent: kGuerillaAccent, light: Color(0xFF5E6B2A), name: 'Guérilla', line: 'la flemme ou moi'),
    (kind: kSniperKind, icon: Icons.gps_fixed, tooltip: 'Sniper · chaque minute, pile où elle compte', accent: kSniperAccent, light: Color(0xFF2A6F94), name: 'Sniper', line: 'chaque minute, pile où elle compte'),
    (kind: kOffensiveKind, icon: Icons.north_east, tooltip: 'Offensive · en forme, à fond', accent: kOffensiveAccent, light: Color(0xFFB4532A), name: 'Offensive', line: 'en forme, à fond'),
  ];

  /// Le mode qui va avec l'élan du moment : Flemme → Guérilla, Normal →
  /// Sniper, En forme → Offensive ; rien en recharge.
  String? get _modeKind {
    if (widget.logic.inRecharge) return null;
    return switch (widget.logic.mode) {
      DayMode.low => kGuerillaKind,
      DayMode.normal => kSniperKind,
      DayMode.high => kOffensiveKind,
    };
  }

  /// Un seul gros bouton, celui du mode actuel (retour user 2026-11-01 : pas
  /// quatre boutons alignés) ; les autres restent en petit en haut à droite.
  Widget? _modeLauncher(ColorScheme cs) {
    final kind = _modeKind;
    if (kind == null) return null;
    final l = _launchers.firstWhere((x) => x.kind == kind);
    final dark = cs.brightness == Brightness.dark;
    final c = dark ? l.accent : l.light;
    final p = RunSessionStore.current;
    final pending = p != null && p.kind == kind && p.isLive(DateTime.now(), widget.logic.livedTodayYmd) ? p : null;
    final unit = kind == kSniperKind ? 'cible' : 'coup';
    final title = pending != null ? 'Reprendre · ${l.name}' : l.name;
    final sub = pending != null ? '${pending.done} $unit${pending.done > 1 ? 's' : ''} déjà ${kind == kSniperKind ? 'touchée' : 'gagné'}${pending.done > 1 ? 's' : ''}' : l.line;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: c.withValues(alpha: dark ? .16 : .12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.withValues(alpha: .6), width: 1.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openRun(kind),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                child: Icon(l.icon, size: 22, color: dark ? const Color(0xFF0B130A) : Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .65))),
                ]),
              ),
              Icon(Icons.play_arrow_rounded, size: 30, color: c),
            ]),
          ),
        ),
      ),
    );
  }

  /// Lance (ou reprend) une Guérilla / une Offensive — boutons de l'en-tête
  /// et widget « Lanceurs » de l'écran d'accueil (lien `…://guerilla`).
  Future<void> openRun(String kind) async {
    final p = RunSessionStore.current;
    final pending = p != null && p.kind == kind && p.isLive(DateTime.now(), widget.logic.livedTodayYmd) ? p : null;
    if (kind == kGuerillaKind) {
      await showGuerillaScreen(context, widget.logic, resume: pending);
    } else if (kind == kSniperKind) {
      await showSniperScreen(context, widget.logic, badges: widget.badges, resume: pending);
    } else {
      await showOffensiveScreen(context, widget.logic, resume: pending);
    }
    if (mounted) setState(() {});
  }

  Widget _launcherBtn(ColorScheme cs, String kind, IconData icon, String tooltip, Color accent, Color lightAccent) {
    final p = RunSessionStore.current;
    final pending = p != null && p.kind == kind && p.isLive(DateTime.now(), widget.logic.livedTodayYmd) ? p : null;
    final c = cs.brightness == Brightness.dark ? accent : lightAccent;
    Future<void> open() => openRun(kind);

    return Stack(clipBehavior: Clip.none, children: [
      SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: c.withValues(alpha: .12),
          shape: CircleBorder(side: BorderSide(color: c.withValues(alpha: .55))),
          child: InkWell(
            onTap: open,
            customBorder: const CircleBorder(),
            child: Tooltip(message: pending != null ? 'Reprendre · ${pending.done} ${kind == kSniperKind ? 'cible' : 'coup'}${pending.done > 1 ? 's' : ''}' : tooltip, child: Icon(icon, size: 20, color: c)),
          ),
        ),
      ),
      if (pending != null)
        Positioned(
          right: -1,
          top: -1,
          child: Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: cs.surface, width: 2))),
        ),
    ]);
  }


  /// Lanceur du mode Planification (2026-10-31) : poser demain ou la fin de journée.
  DateTime? _bedSnooze;

  /// Carte « Je vais me coucher » avant le bloc Sommeil du soir (`bedtimePrompt`).
  Widget _bedtimeCard() {
    final logic = widget.logic;
    final byId = {for (final a in logic.state.activities) a.id: a};
    final sleep = (_schedule?.blocks ?? const <ScheduleBlock>[])
        .where((b) => b.status == 'pending' && blockStartMin(b) >= 18 * 60 && (isSleepName(b.title) || isSleepName(byId[b.activityId]?.name)))
        .toList()
      ..sort((a, b) => blockStartMin(a).compareTo(blockStartMin(b)));
    if (sleep.isEmpty) return const SizedBox.shrink();
    final d = logic.livedToday;
    final sleepAt = DateTime(d.year, d.month, d.day).add(Duration(minutes: blockStartMin(sleep.first)));
    final next = _nextDoc;
    final planned = next != null && next.generatedBy == 'plan' && next.plannedAt != null && !next.plannedSameDay;
    final step = bedtimePrompt(now: DateTime.now(), sleepAt: sleepAt, planned: planned, inRecharge: logic.inRecharge, snoozedUntil: _bedSnooze);
    if (step == null) return const SizedBox.shrink();
    return BedtimeCard(
      step: step,
      sleepAt: sleepAt,
      onPlan: openPlan,
      onBed: () => _goToBed(sleep.first),
      onSnooze: () => setState(() => _bedSnooze = DateTime.now().add(const Duration(minutes: 30))),
    );
  }

  /// Lance le chrono Sommeil (activité du bloc, sinon « Sommeil », créée au besoin).
  void _goToBed(ScheduleBlock block) {
    final logic = widget.logic;
    final acts = logic.state.activities.where((a) => !a.deleted && !a.isHabit).toList();
    var a = acts.where((a) => a.id == block.activityId && isSleepName(a.name)).firstOrNull ?? acts.where((a) => isSleepName(a.name)).firstOrNull;
    if (a == null) {
      final domains = logic.state.activeDomains;
      final dom = domains.where((d) => isSleepName(d.name) || d.name.toLowerCase().contains('santé')).firstOrNull ?? domains.firstOrNull;
      if (dom == null) return;
      a = Activity(domainId: dom.id, name: 'Sommeil', goalMin: 0);
      logic.state.activities.add(a);
      logic.onChange();
    }
    logic.start(a.id);
    setState(() {});
  }

  Future<void> openPlan() async {
    await showPlanScreen(context, widget.logic, badges: widget.badges);
    if (mounted) setState(() {});
  }

  Widget _planBtn(ColorScheme cs) {
    final c = cs.brightness == Brightness.dark ? kPlanAccent : const Color(0xFF3B5BB5);
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: c.withValues(alpha: .12),
        shape: CircleBorder(side: BorderSide(color: c.withValues(alpha: .55))),
        child: InkWell(
          onTap: openPlan,
          customBorder: const CircleBorder(),
          child: Tooltip(message: 'Planifier · prendre le cap', child: Icon(Icons.explore_outlined, size: 20, color: c)),
        ),
      ),
    );
  }

  // ── En parallèle : Routines · Objectifs (« une carte, une fiche », lot 4) ──

  RoutineDay _routineDay() {
    final ymd = widget.logic.livedYmdNow;
    return buildRoutineDay(
      activities: widget.logic.state.activeActivities,
      hits: widget.logic.state.habitHits,
      now: DateTime.now(),
      pushed: widget.logic.routinePushed(ymd),
      deferred: widget.logic.state.nowSkippedByYmd[ymd] ?? const [],
      dismissed: widget.logic.nowDoneSet(ymd),
      dayStartMin: widget.logic.dayStartMin,
      moments: widget.logic.moments,
      exclude: widget.logic.acquiredIds,
    );
  }

  List<Widget> _parallelSection(ColorScheme cs, StakeBoard? stakes) {
    final day = _routineDay();
    final all = day.countAll;
    final st = widget.logic.state;
    final now = DateTime.now();
    final days = buildObjectiveDays(
      objectives: _objectives,
      activities: st.activeActivities,
      sessions: st.sessions,
      blocks: _liveBlocks,
      projects: widget.logic.currentProjects,
      now: now,
      dayStartMin: widget.logic.dayStartMin,
    );
    final ranked = rankObjectiveMoments(
      days,
      nowMin: widget.logic.livedNowMinNow,
      now: now,
      routineCount: (a) => routineTodayCount(widget.logic, a),
      weekPercent: (o) => computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, now).weekPercent,
      runningActivityId: widget.logic.runningActivity()?.id,
      // Même classement que la carte OBJECTIF DU MOMENT de la fiche (qui
      // tient compte du mode) : la ligne montre l'objectif qu'on retrouve en
      // tête en l'ouvrant.
      mode: widget.logic.mode,
    );
    final current = day.of(day.current.key).where((x) => !x.reached && !day.dismissed.contains(x.id)).map((x) => x.activity.name).toList();
    final bc = widget.badges;
    final board = stakes ?? StakeBoard.empty;
    final today = DateTime(now.year, now.month, now.day);
    final projectTile = projectsTile(widget.logic.currentProjects, today, sessions: st.sessions, skipped: _projectSkipped);
    return [
      DashboardTiles(
        program: programTile(_liveBlocks, widget.logic.livedNowMinNow) ??
            const ProgramTile(value: 'Rien de prévu', sub: 'touche pour voir le programme et ajouter un bloc', strip: []),
        routines: day.slots.isEmpty
            ? null
            : routinesTile(done: all.done, total: all.total, toDoNow: current, momentLabel: day.current.thisOne, seriesRunning: bc?.deck?.seriesRunning ?? 0),
        objectives: widget.sync == null ? null : objectivesTile([for (final r in ranked) (r.objective.title, r.weekPercent)],
            readingsDue: _objectives.where((o) => o.status == 'active' && isReadingDue(o, now)).length),
        badges: badgesTile(bc?.deck, board),
        perfect: perfectDayTile(bc?.todayFacts(), widget.logic.emberLedgerNow()),
        actions: actionsTile(projects: widget.logic.currentProjects, activities: st.activeActivities, today: today, parole: _paroleToday()),
        projects: projectTile,
        onProgram: _openProgramSheet,
        onRoutines: _openRoutinesFiche,
        onObjectives: widget.sync == null ? null : _openObjectivesFiche,
        // La tuile Collection ouvre l'album (ce qui se joue ce soir y est en tête, 2026-11-01).
        onBadges: bc == null ? null : () => showBadgeGallerySheet(context, logic: widget.logic, sync: bc.sync, center: bc),
        onBadgesGallery: bc == null ? null : () => showBadgeGallerySheet(context, logic: widget.logic, sync: bc.sync, center: bc),
        onPerfect: bc == null ? null : _openPerfectDaySheet,
        onActions: _openFocusedActionsSheet,
        // Résumé du jour + Où on va : une tuile dans la case libre (retour
        // user 2026-10-30), à la place des deux boutons du bas de page.
        review: const DashTile(label: 'RECUL', value: 'Bilan · cap', sub: 'résumé du jour · où on va'),
        onReview: _openReviewChoice,
        onProjects: () => _openProjectTile(projectTile?.targetId),
      ),
    ];
  }

  // Revue du dimanche : carte d'entrée (samedi 18 h → lundi midi) et rappel
  // du cap de la semaine (posé le dimanche d'avant). « Plus tard » / ✕ sont
  // mémorisés par semaine.
  String? _reviewHidden;
  String? _intentionHidden;
  bool _reviewPrefsLoaded = false;

  bool _reviewPrefsReady = false;

  List<Widget> _weekReviewCards() {
    if (!_reviewPrefsLoaded) {
      _reviewPrefsLoaded = true;
      SharedPreferences.getInstance().then((p) {
        if (!mounted) return;
        setState(() {
          _reviewHidden = p.getString('week_review_later');
          _intentionHidden = p.getString('week_intention_hidden');
          _reviewPrefsReady = true;
        });
      }).catchError((_) {});
    }
    final logic = widget.logic;
    // Rien tant que les revues faites (doc meta) et « Plus tard » ne sont pas
    // lus : sinon la carte apparaît au démarrage puis disparaît (bug 2026-11-01).
    if (!_reviewPrefsReady || !logic.metaLoaded) return const [];
    final now = DateTime.now();
    final out = <Widget>[];
    final monday = reviewedMonday(now, logic.dayStartMin);
    if (reviewWindowOpen(now, logic.dayStartMin) && !logic.weekReviews.containsKey(monday) && _reviewHidden != monday) {
      out.addAll([
        const SizedBox(height: 12),
        WeekReviewCard(
          onOpen: _openWeekReview,
          onLater: () {
            setState(() => _reviewHidden = monday);
            SharedPreferences.getInstance().then((p) => p.setString('week_review_later', monday)).catchError((_) => false);
          },
        ),
      ]);
    }
    final intention = weekIntention(logic.weekReviews, now, logic.dayStartMin);
    final d = livedDate(now, logic.dayStartMin);
    final thisMonday = ymdOf(DateTime(d.year, d.month, d.day - (d.weekday - 1)));
    if (intention != null && _intentionHidden != thisMonday) {
      out.addAll([
        const SizedBox(height: 12),
        WeekIntentionCard(
          intention: intention,
          onDismiss: () {
            setState(() => _intentionHidden = thisMonday);
            SharedPreferences.getInstance().then((p) => p.setString('week_intention_hidden', thisMonday)).catchError((_) => false);
          },
        ),
      ]);
    }
    return out;
  }

  Future<void> _openWeekReview() async {
    await showWeekReviewScreen(context, widget.logic, badges: widget.badges);
    if (mounted) setState(() {});
  }

  void _openReviewChoice() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.onOpenDayReview != null)
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded),
              title: const Text('Résumé du jour'),
              subtitle: const Text('ce que la journée a donné'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onOpenDayReview!();
              },
            ),
          ListTile(
            leading: const Icon(Icons.event_repeat_rounded),
            title: const Text('Revue de la semaine'),
            subtitle: const Text('ce qui a tenu, ce qui a coûté, la suivante posée'),
            onTap: () {
              Navigator.pop(ctx);
              _openWeekReview();
            },
          ),
          ListTile(
            leading: const Icon(Icons.explore_outlined),
            title: const Text('Où on va'),
            subtitle: const Text('objectifs et cap à long terme'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => WhereWeGoScreen(logic: widget.logic)));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  /// Feuille de la tuile JOURNÉE PARFAITE : ce qui manque (routines à
  /// atteindre avec +1, blocs à faire) et les braises en réserve.
  void _openPerfectDaySheet() {
    final bc = widget.badges;
    if (bc == null) return;
    showFiche<void>(context, builder: (ctx, scroll) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        final facts = bc.todayFacts();
        final ledger = widget.logic.emberLedgerNow();
        final routines = [for (final r in facts.routines) if (!r.reached) r];
        final blocks = facts.pendingBlocks..sort((a, b) => a.startTime.compareTo(b.startTime));
        final missing = routines.length + blocks.length;
        final total = facts.routines.length + facts.countedBlocks.length;
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            FicheHeader(
              title: 'Journée parfaite',
              info: const InfoDot(kRulePerfectDay),
              chip: total == 0 ? 'rien à tenir' : (missing == 0 ? 'parfaite' : 'il manque $missing'),
              chipColor: missing == 0 && total > 0 ? kPalierGreen : kPalierAmber,
              kpi: 'routines ${facts.routinesReached} / ${facts.routines.length} · blocs ${facts.blocksDone} / ${facts.countedBlocks.length}',
            ),
            if (routines.isNotEmpty) ...[
              FicheTitle('ROUTINES À ATTEINDRE · ${routines.length}'),
              const SizedBox(height: 6),
              // Même vue que la fiche Routines, filtrée sur ce qui manque.
              RoutinesDayView(
                logic: widget.logic,
                onlyMissing: true,
                onStartTimed: widget.onStartTimed,
                onChanged: () {
                  if (ctx.mounted) setLocal(() {});
                },
              ),
            ],
            if (blocks.isNotEmpty) ...[
              FicheTitle('BLOCS À FAIRE · ${blocks.length}'),
              // Même liste que le programme du jour, sans les blocs faits.
              DailyScheduleView(
                key: ValueKey('perfect-${widget.logic.livedTodayYmd}'),
                date: widget.logic.livedTodayYmd,
                logic: widget.logic,
                visible: true,
                onlyToDo: true,
                title: '',
                onLaunch: widget.onLaunch,
                onLaunchTimed: widget.onNowLaunchTimed,
                onOpenSource: widget.onOpenSource,
              ),
            ],
            if (total > 0 && missing == 0)
              FicheNote(ledger.stock >= kEmberCap
                  ? 'Tout est tenu. La réserve est pleine : pas de braise de plus ce soir.'
                  : 'Tout est tenu : une braise s\'ajoute à la bascule de la journée.'),
            const FicheTitle('BRAISES'),
            Row(children: [
              EmberDots(stock: ledger.available),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${ledger.available} sur $kEmberCap en réserve${ledger.pending != null ? ' · une en attente' : ''}',
                    style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: .7))),
              ),
            ]),
            const SizedBox(height: 6),
            const FicheNote('Une journée parfaite forge une braise (3 au plus). Une braise rallume une série de routine cassée hier, si la routine est atteinte aujourd\'hui.'),
            const SizedBox(height: 8),
            EmberLedgerPanel(ledger: ledger, names: {for (final a in widget.logic.state.activities) a.id: a.name}),
          ],
        );
      });
    }).then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Tuile ACTIONS (2026-10-30, retour user) : une feuille des actions visées
  /// aujourd'hui au lieu de l'onglet Actions. Tap = page focus de l'action,
  /// appui long = viser demain / retirer le jour visé.
  /// La parole du jour vécu (Parole tenue) : gelée, sinon les candidates.
  ParoleDay? _paroleToday() {
    final l = widget.logic;
    final d = paroleOfDay(l.paroles, paroleIndex(l.currentProjects, l.state.activeActivities), l.livedTodayYmd, l.dayStartMin);
    return d == null || d.ids.length < kParoleMin ? null : d;
  }

  void _openFocusedActionsSheet() {
    showFiche<void>(context, builder: (ctx, scroll) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        bool focusedToday(TaskAction a) {
          final f = a.focusDate;
          return isFocusedOn(a, today) || (a.done && f != null && f.year == today.year && f.month == today.month && f.day == today.day);
        }

        final items = <_FocusedItem>[
          for (final p in widget.logic.currentProjects)
            if (p.status == 'active' && !p.paused)
              for (final t in p.tasks)
                if (t.status != 'skipped')
                  for (final a in t.actions)
                    if (focusedToday(a)) _FocusedItem(a, project: p, task: t),
          for (final act in widget.logic.state.activeActivities)
            for (final a in act.ownActions)
              if (focusedToday(a)) _FocusedItem(a, owner: act),
        ];
        final parole = _paroleToday();
        final pIds = parole?.ids.toSet() ?? const <String>{};
        if (parole != null) {
          // Une action de la parole visée ensuite ailleurs y reste.
          final idx = paroleIndex(widget.logic.currentProjects, widget.logic.state.activeActivities);
          for (final id in parole.ids) {
            if (items.any((e) => e.action.id == id)) continue;
            final x = idx[id];
            if (x != null) items.add(_FocusedItem(x.action, project: x.project, task: x.task, owner: x.activity));
          }
        }
        final open = items.where((e) => !e.action.done && !pIds.contains(e.action.id)).toList();
        final paroleOpen = items.where((e) => !e.action.done && pIds.contains(e.action.id)).toList();
        final paroleDone = items.where((e) => e.action.done && pIds.contains(e.action.id)).length;
        final done = items.where((e) => e.action.done).toList();
        String detail(_FocusedItem e) => [
              if (e.project != null) '${e.project!.title}${e.task != null && e.task!.id != kFlowTaskId ? ' › ${e.task!.title}' : ''}',
              if (e.owner != null) e.owner!.name,
              if (e.action.estimatedMin != null) '≈ ${fmtMin(e.action.estimatedMin!)}',
            ].join(' · ');
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            if (parole == null)
              FicheHeader(
                title: 'Visées aujourd\'hui',
                chip: '${done.length} / ${items.length} faite${done.length > 1 ? 's' : ''}',
                chipColor: open.isEmpty && items.isNotEmpty ? kPalierGreen : kPalierAmber,
                kpi: 'touche une action pour l\'ouvrir en focus · ⋯ ou appui long pour la gérer',
                info: const InfoDot(kRuleParole),
              )
            else
              FicheHeader(
                title: 'Ta parole aujourd\'hui',
                chip: '$paroleDone / ${parole.ids.length} tenue',
                chipColor: paroleOpen.isEmpty ? kPalierGreen : kPalierAmber,
                kpi: [
                  if (parole.givenAt != null) 'donnée ${_givenLabel(parole.givenAt!)}',
                  paroleOpen.isEmpty ? 'parole tenue' : (paroleOpen.length == 1 ? 'plus qu\'une pour tenir' : 'encore ${paroleOpen.length} pour tenir'),
                ].join(' · '),
                info: const InfoDot(kRuleParole),
              ),
            if (widget.sync != null)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final created = await showNewFocusedAction(context, logic: widget.logic, sync: widget.sync!);
                    if (created && ctx.mounted) setLocal(() {});
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter une action visée'),
                ),
              ),
            if (items.isEmpty) const FicheNote('Rien n\'est visé aujourd\'hui.'),
            if (paroleOpen.isNotEmpty) ...[
              FicheTitle('TA PAROLE · ${paroleOpen.length} À FAIRE'),
              for (final e in paroleOpen)
                FicheStep(
                  title: e.action.title,
                  detail: detail(e),
                  onTap: () async {
                    await _openFocusedItem(e);
                    if (ctx.mounted) setLocal(() {});
                  },
                  onLongPress: () async {
                    await _refocusItem(e);
                    if (ctx.mounted) setLocal(() {});
                  },
                ),
            ],
            if (open.isNotEmpty) ...[
              FicheTitle(parole == null ? 'À FAIRE · ${open.length}' : 'AJOUTÉES AUJOURD\'HUI · HORS PAROLE · ${open.length}'),
              for (final e in open)
                FicheStep(
                  title: e.action.title,
                  detail: detail(e),
                  onTap: () async {
                    await _openFocusedItem(e);
                    if (ctx.mounted) setLocal(() {});
                  },
                  onLongPress: () async {
                    await _refocusItem(e);
                    if (ctx.mounted) setLocal(() {});
                  },
                  trailing: IconButton(
                    tooltip: 'Gérer',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_horiz_rounded, size: 20),
                    onPressed: () async {
                      await _refocusItem(e);
                      if (ctx.mounted) setLocal(() {});
                    },
                  ),
                ),
            ],
            if (done.isNotEmpty) ...[
              FicheTitle('FAITES · ${done.length}'),
              for (final e in done) FicheStep(title: e.action.title, detail: detail(e), done: true),
            ],
            if (widget.onOpenActions != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    widget.onOpenActions!();
                  },
                  icon: const Icon(Icons.checklist_rounded, size: 18),
                  label: const Text('Ouvrir l\'onglet Actions'),
                ),
              ),
          ],
        );
      });
    }).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _openFocusedItem(_FocusedItem e) {
    final acts = widget.logic.state.activities;
    final chronoId = e.action.linkedActivityId ?? e.project?.linkedActivityId ?? e.owner?.id;
    return showActionFocusScreen(context,
        logic: widget.logic,
        action: e.action,
        project: e.project,
        task: e.task,
        ownerActivity: e.owner,
        chronoActivity: acts.where((a) => a.id == chronoId).firstOrNull,
        sync: widget.sync);
  }

  Future<void> _refocusItem(_FocusedItem e) async {
    final sync = widget.sync;
    if (sync == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(e.action.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          ListTile(leading: const Icon(Icons.wb_sunny_outlined), title: const Text('Viser demain'), onTap: () => Navigator.pop(c, 'tomorrow')),
          ListTile(leading: const Icon(Icons.event_busy_outlined), title: const Text('Ne plus viser'), subtitle: const Text('l\'action reste dans son projet ou son activité'), onTap: () => Navigator.pop(c, 'clear')),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Renommer'), onTap: () => Navigator.pop(c, 'rename')),
          ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
              title: Text('Supprimer l\'action', style: TextStyle(color: Theme.of(c).colorScheme.error)),
              onTap: () => Navigator.pop(c, 'delete')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'rename') {
      final ctrl = TextEditingController(text: e.action.title);
      final name = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Renommer'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (v) => Navigator.pop(d, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('Enregistrer')),
          ],
        ),
      );
      ctrl.dispose();
      final t = name?.trim() ?? '';
      if (t.isEmpty || t == e.action.title) return;
      e.action.title = t;
      await _saveFocusedItem(sync, e);
      return;
    }
    if (choice == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Supprimer l\'action ?'),
          content: Text('« ${e.action.title} » sera supprimée${e.project != null ? ' du projet ${e.project!.title}' : ''}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer')),
          ],
        ),
      );
      if (ok != true) return;
      if (e.project != null && e.task != null) {
        e.task!.actions.removeWhere((a) => a.id == e.action.id);
        await sync.saveProjectTasks(e.project!.id, e.project!.tasks);
      } else if (e.owner != null) {
        e.owner!.ownActions.removeWhere((a) => a.id == e.action.id);
        await sync.updateOwnActions(e.owner!.id, e.owner!.ownActions);
      }
      widget.logic.onChange();
      return;
    }
    final t = DateTime.now().add(const Duration(days: 1));
    e.action.focusDate = choice == 'tomorrow' ? DateTime(t.year, t.month, t.day) : null;
    await _saveFocusedItem(sync, e);
  }

  Future<void> _saveFocusedItem(FirestoreSync sync, _FocusedItem e) async {
    if (e.project != null) {
      await sync.patchActionOf(e.project!, e.action);
    } else if (e.owner != null) {
      await sync.updateOwnActions(e.owner!.id, e.owner!.ownActions);
    }
    widget.logic.onChange();
  }

  void _openRoutinesFiche() {
    showFiche<void>(context, builder: (ctx, scroll) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        final day = _routineDay();
        final all = day.countAll;
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            FicheHeader(
              title: 'Routines',
              info: const InfoDot(kRuleSeries),
              chip: '${all.done} / ${all.total}',
              chipColor: kRoutineAccent,
              kpi: day.shortLine,
            ),
            const SizedBox(height: 14),
            RoutinesDayView(
              logic: widget.logic,
              onChain: (_) => showRoutineChainScreen(context, logic: widget.logic),
              onOrganize: () => showRoutinesOrganizeScreen(context, logic: widget.logic),
              onStartTimed: widget.onStartTimed,
            ),
          ],
        );
      });
    }).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openObjectivesFiche() {
    final sync = widget.sync;
    if (sync == null) return;
    showFiche<void>(context, builder: (ctx, scroll) {
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          ObjectivesDayView(
            logic: widget.logic,
            sync: sync,
            blocks: _liveBlocks,
            onLaunch: widget.onNowLaunch ?? widget.onLaunch,
            onOpenSource: widget.onOpenSource,
            onOpenTask: widget.onOpenTask,
            badges: widget.badges,
            onChain: widget.onStopTimer == null
                ? null
                : () => showChainScreen(
                      context,
                      logic: widget.logic,
                      sync: sync,
                      date: _schedDate,
                      onLaunch: widget.onNowLaunch ?? widget.onLaunch ?? (_) {},
                      onStopTimer: widget.onStopTimer!,
                    ),
            onChainObjective: widget.onStopTimer == null
                ? null
                : (o) => showChainScreen(
                      context,
                      logic: widget.logic,
                      sync: sync,
                      date: _schedDate,
                      onLaunch: widget.onNowLaunch ?? widget.onLaunch ?? (_) {},
                      onStopTimer: widget.onStopTimer!,
                      onOpenSource: widget.onOpenSource,
                      objective: o,
                    ),
          ),
        ],
      );
    }).then((_) async {
      // La fiche peut avoir créé / archivé un objectif : la ligne relit la
      // même liste que la carte du moment.
      try {
        final all = await sync.fetchStrategicObjectives();
        if (mounted) setState(() => _objectives = all);
      } catch (_) {
        if (mounted) setState(() {});
      }
    });
  }

  /// Le tableau du jour (« Aujourd'hui en enjeux », lot 2) : recalculé à
  /// chaque build depuis le deck chargé et l'état local ; null sans deck.
  StakeBoard? _stakeBoard() {
    final bc = widget.badges;
    if (bc == null) return null;
    try {
      return buildStakeBoard(
        deck: bc.deck,
        facts: bc.todayFacts(),
        hunts: widget.logic.badgeHunts,
        projects: widget.logic.currentProjects,
        activities: widget.logic.state.activeActivities,
        dayStartMin: widget.logic.dayStartMin,
        parole: _paroleToday(),
      );
    } catch (_) {
      return null;
    }
  }

  String _givenLabel(DateTime at) {
    final hm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final d = DateTime(at.year, at.month, at.day);
    final t = widget.logic.livedToday;
    final diff = DateTime(t.year, t.month, t.day).difference(d).inDays;
    return diff == 1 ? 'hier à $hm' : diff == 0 ? 'à $hm' : 'le ${at.day}/${at.month} à $hm';
  }

  /// Un rallumage armé ou annulé, un +1 qui le rend effectif : le deck se
  /// recalcule (séries comblées, enjeux).
  void _onEmbersChanged() {
    widget.badges?.load();
    if (mounted) setState(() {});
  }

  /// Les enjeux du jour dans une feuille (tap sur « Ta journée » / « Ce soir »,
  /// retour user 2026-10-30) : le tableau (ou le bilan complet du soir) puis la
  /// liste EN JEU. Un +1 garde la feuille ouverte ; un chrono ou la page focus
  /// la ferment.
  void _openStakesSheet() {
    WatchKeepStore.load();
    showFiche<void>(context, builder: (ctx, scroll) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        final board = _stakeBoard() ?? StakeBoard.empty;
        final evening = isEvening(widget.logic.livedNowMinNow);
        final ledger = evening ? _eveningLedger(board) : null;
        final stakes = StakesList(
          board: board,
          evening: evening,
          watchBlocking: board.watchOutOfReach > 0 ? watchBlockersOf(widget.logic).length : 0,
          onWatchSettings: () async {
            await showWatchMinimumsSheet(ctx, widget.logic);
            setLocal(() {});
          },
          onOpenBadges: () {
            Navigator.of(ctx).pop();
            _openBadgeGallery();
          },
          onRun: (s) {
            if (s.gesture.kind == StakeGestureKind.routine) {
              _runStake(s);
              setLocal(() {});
            } else {
              Navigator.of(ctx).pop();
              _runStake(s);
            }
          },
        );
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            FicheHeader(
              title: evening ? 'Ce soir' : 'Ta journée',
              info: const InfoDot(kRuleStakes),
              chip: board.inPlay == 0 ? 'rien en jeu' : '${board.inPlay} en jeu',
              chipColor: kStakeHunt,
            ),
            const SizedBox(height: 12),
            // Le soir, ENCORE POSSIBLE CE SOIR passe en tête (retour user 2026-10-30) : le bilan après.
            if (evening) ...[stakes, const SizedBox(height: 12)],
            if (ledger != null && !ledger.isEmpty)
              EveningLedgerCard(ledger: ledger)
            else if (!evening)
              StakeScoreboard(board: board, elapsed: dayElapsed(widget.logic.livedNowMinNow), lostYesterday: widget.logic.lostSeriesYesterday().length),
            LostYesterdaySection(
              logic: widget.logic,
              all: true,
              onChanged: () {
                _onEmbersChanged();
                setLocal(() {});
              },
            ),
            if (!evening) stakes,
          ],
        );
      });
    }).then((_) {
      if (mounted) setState(() {});
    });
  }

  EveningLedger _eveningLedger(StakeBoard board) {
    final bc = widget.badges;
    final now = DateTime.now();
    final st = widget.logic.state;
    final facts = bc?.todayFacts();
    return buildEveningLedger(
      board: board,
      deck: bc?.deck,
      projects: widget.logic.currentProjects,
      activities: st.activeActivities,
      sessions: st.sessions,
      objectiveDays: facts?.objectiveDays ?? const [],
      dayStart: livedDayStart(now, widget.logic.dayStartMin),
      now: now,
      perfectToday: facts != null && isPerfectSoFar(facts),
      emberStock: widget.logic.emberLedgerNow().available,
    );
  }

  void _openBadgeGallery() {
    final bc = widget.badges;
    if (bc == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => BadgeGalleryScreen(logic: widget.logic, sync: bc.sync, center: bc, showSamples: false)))
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Fait le geste d'un enjeu : +1, chrono, bloc, page focus.
  void _runStake(Stake s) {
    final g = s.gesture;
    final logic = widget.logic;
    switch (g.kind) {
      case StakeGestureKind.routine:
        if (g.activity != null) routinePlusWithUndo(context, logic, g.activity!);
      case StakeGestureKind.activity:
        if (g.activity != null) logic.start(g.activity!.id);
      case StakeGestureKind.block:
        if (g.block != null) (widget.onNowLaunch ?? widget.onLaunch)?.call(g.block!);
      case StakeGestureKind.action:
        final a = g.action;
        if (a == null) break;
        final acts = logic.state.activeActivities;
        Activity? byId(String? id) => id == null ? null : acts.where((x) => x.id == id).firstOrNull;
        final chrono = byId(a.linkedActivityId) ?? byId(g.project?.linkedActivityId) ?? g.owner;
        showActionFocusScreen(context,
                logic: logic, action: a, project: g.project, task: g.task, ownerActivity: g.owner, chronoActivity: chrono, sync: widget.sync ?? FirestoreSync())
            .then((_) {
          if (mounted) setState(() {});
        });
        return;
      case StakeGestureKind.reading:
        final o = g.objective;
        if (o == null) break;
        noteReadingQuick(context, sync: widget.sync ?? FirestoreSync(), objective: o).then((ok) async {
          if (ok) await widget.badges?.load(refresh: true);
          if (mounted) setState(() {});
        });
        return;
    }
    if (mounted) setState(() {});
  }

  /// Déblocages à signaler : calculés à l'ouverture de l'onglet, marqués vus
  /// aussitôt (le signal ne revient jamais), affichés jusqu'au « × » / « Voir ».
  Future<void> _loadBadgeSignals() async {
    final bc = widget.badges;
    if (bc == null) return;
    try {
      final d = await bc.load();
      final s = await bc.takeSignals(d);
      // Le tableau des enjeux attend le deck : on redessine même sans signal.
      if (mounted) setState(() => _badgeSignals = s.isNotEmpty ? s : _badgeSignals);
    } catch (_) {}
  }


  /// Ligne « PROGRAMME DU JOUR » (§ 3.3) : liens Demain / Modifier + outils
  /// (sync agenda, liste ⇄ frise, reprogrammer) — plus de boutons épinglés.
  bool _programOpen = false;

  /// Le programme du jour dans une feuille (tuile PROGRAMME, jauge).
  void _openProgramSheet() {
    if (_programOpen || !mounted) return;
    _programOpen = true;
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final link = dark ? kBPrimary : cs.primary;
    final text3 = dark ? kBText3 : cs.onSurface.withOpacity(.55);
    // « Demain » bascule DANS la feuille (retour user 2026-10-30) : la page ne bouge pas.
    var tomorrow = false;
    showFiche<void>(context, builder: (ctx, scroll) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        final date = tomorrow ? _ymd(widget.logic.livedToday.add(const Duration(days: 1))) : widget.logic.livedTodayYmd;
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: _programSection(cs, link, text3, date,
              tomorrow: tomorrow,
              onToggleDay: () => setLocal(() => tomorrow = !tomorrow),
              refresh: () {
                setLocal(() {});
                if (mounted) setState(() {});
              }),
        );
      });
    }).whenComplete(() {
      _programOpen = false;
      if (mounted) setState(() {});
    });
  }

  /// En-tête, liste ou frise, bascule liste ⇄ frise. [tomorrow] / [onToggleDay] :
  /// la feuille bascule elle-même entre aujourd'hui et demain ; sans eux, la page.
  List<Widget> _programSection(ColorScheme cs, Color link, Color text3, String date,
      {bool? tomorrow, VoidCallback? onToggleDay, required VoidCallback refresh}) {
    final t = tomorrow ?? _showTomorrow;
    return [
      _programHeader(cs, link, text3, tomorrow: t, onToggleDay: onToggleDay),
      const SizedBox(height: 8),
      // key par date : force un nouveau state (nouveau stream Firestore)
      // quand on bascule aujourd'hui ↔ demain.
      if (_timeline)
        DayTimelineView(
          key: ValueKey('tl-$date'),
          date: date,
          logic: widget.logic,
          visible: widget.visible,
          // ▶ n'a de sens que pour le jour même (chrono maintenant).
          onLaunch: t ? null : widget.onLaunch,
          onOpenSource: widget.onOpenSource,
        )
      else
        DailyScheduleView(
          key: ValueKey(date),
          date: date,
          logic: widget.logic,
          visible: widget.visible,
          onLaunch: t ? null : widget.onLaunch,
          onLaunchTimed: t ? null : widget.onNowLaunchTimed,
          onOpenSource: widget.onOpenSource,
          onRegisterScrollToMinute: (fn) => _listScrollToMinute = fn,
          title: '',
          emptyText: t
              ? 'Rien de prévu pour demain.\nTouche pour ajouter un bloc, ou demande à Claude/ORION de planifier ta journée.'
              : _domainsPlaceholder(),
        ),
      // Bascule liste ⇄ frise en fin de section (§ 3.3), persistée.
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: Icon(_timeline ? Icons.view_list_outlined : Icons.calendar_view_day_outlined, size: 16),
          label: Text(_timeline ? 'Voir en liste' : 'Voir en frise'),
          style: TextButton.styleFrom(
              foregroundColor: link, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          onPressed: () {
            _timeline = !_timeline;
            refresh();
            SharedPreferences.getInstance().then((p) => p.setBool(_timelinePrefKey, _timeline));
          },
        ),
      ),
    ];
  }

  Widget _programHeader(ColorScheme cs, Color link, Color text3, {required bool tomorrow, VoidCallback? onToggleDay}) {
    Widget tlink(String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: link)),
          ),
        );
    return Row(children: [
      Expanded(
        child: Text(tomorrow ? 'PROGRAMME DE DEMAIN' : 'PROGRAMME DU JOUR',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: text3)),
      ),
      tlink(tomorrow ? 'Aujourd\'hui' : 'Demain', onToggleDay ?? () => setState(() => _showTomorrow = !_showTomorrow)),
      tlink('Modifier', () {
        final n = DateTime.now();
        _openPlan(tomorrow ? _ymd(n.add(const Duration(days: 1))) : _ymd(n));
      }),
      IconButton(
        tooltip: 'Synchroniser Google Agenda',
        visualDensity: VisualDensity.compact,
        icon: _syncing
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.sync_rounded, size: 18, color: text3),
        onPressed: _syncing ? null : _forceSync,
      ),
      if (!tomorrow)
        IconButton(
          tooltip: 'Reprogrammer la journée',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.delete_sweep_outlined, size: 18, color: cs.error.withOpacity(.85)),
          onPressed: _replanToday,
        ),
    ]);
  }

}

/// Action visée aujourd'hui, avec son porteur (projet › tâche ou activité).
class _FocusedItem {
  final TaskAction action;
  final Project? project;
  final ProjectTask? task;
  final Activity? owner;
  const _FocusedItem(this.action, {this.project, this.task, this.owner});
}
