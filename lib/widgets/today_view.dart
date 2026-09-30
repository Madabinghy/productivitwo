import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/project_health.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/best_to_do_card.dart';
import 'package:productivitwo_v1/widgets/daily_schedule_view.dart';
import 'package:productivitwo_v1/widgets/day_timeline_view.dart';
import 'package:productivitwo_v1/widgets/gcal_settings_sheet.dart';
import 'package:productivitwo_v1/widgets/now_card.dart';
import 'package:productivitwo_v1/widgets/now_coach_zone.dart';
import 'package:productivitwo_v1/widgets/orion_screen.dart';
import 'package:productivitwo_v1/widgets/plan_day_screen.dart';
import 'package:productivitwo_v1/widgets/where_we_go_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onglet « Aujourd'hui » : carte MAINTENANT (bloc en cours + chrono) en tête,
/// puis le programme horaire du jour, avec bascule vers « Demain » pour
/// préparer la journée suivante (planif du lendemain).
class TodayView extends StatefulWidget {
  final AppLogic logic;
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
  final VoidCallback? onChallenge;
  // PR 2 : onglet unique — tâche en retard → fiche projet ; résumé du jour ;
  // défi ORION de la carte coach ; minuteur d'une routine (« Le meilleur à faire »).
  final void Function(Project project, ProjectTask task)? onOpenTask;
  final VoidCallback? onOpenDayReview;
  final void Function(Activity activity, int minutes)? onChallengeAccept;
  final Future<void> Function(Activity activity, int minutes)? onChallengeSchedule;
  final void Function(Activity activity, int minutes)? onStartTimed;

  const TodayView(
      {super.key,
      required this.logic,
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
      this.onChallenge,
      this.onOpenTask,
      this.onOpenDayReview,
      this.onChallengeAccept,
      this.onChallengeSchedule,
      this.onStartTimed});

  @override
  State<TodayView> createState() => TodayViewState();
}

class TodayViewState extends State<TodayView> {
  bool _showTomorrow = false;
  // Programme du jour : UNIQUE abonnement de l'onglet (carte MAINTENANT,
  // en-tête « n / N blocs · restantes », zone coach).
  StreamSubscription<DailySchedule?>? _schedSub;
  DailySchedule? _schedule;
  String _schedDate = '';
  // Ouvertures de l'onglet (déclencheur n° 1 de la question d'état, 24a).
  final List<DateTime> _tabOpens = [];
  // Timeline 24 h (façon Calendar) ⇄ liste compacte. La timeline est l'outil
  // de planification (drag, resize, ajout au créneau) ; la liste — vue par
  // DÉFAUT (demande user) — donne la journée d'un coup d'œil et se coche vite.
  // Le choix est persisté par appareil : l'app rouvre dans la dernière vue.
  static const _timelinePrefKey = 'today_view_timeline';
  bool _timeline = false;
  bool _syncing = false;
  // Scroll de la page — la jauge-minimap saute la timeline à l'heure tapée.
  final _scroll = ScrollController();
  Timer? _gaugeTick;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = p.getBool(_timelinePrefKey);
      if (saved != null && mounted && saved != _timeline) {
        setState(() => _timeline = saved);
      }
    });
    _subscribeSchedule();
    if (widget.visible) _tabOpens.add(DateTime.now());
    // La jauge suit le chrono en cours + le trait « maintenant » ; passage de
    // minuit → le stream bascule sur le nouveau jour.
    _gaugeTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (_ymd(DateTime.now()) != _schedDate) _subscribeSchedule();
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
    _scroll.dispose();
    super.dispose();
  }

  void _subscribeSchedule() {
    _schedSub?.cancel();
    _schedDate = _ymd(DateTime.now());
    _tabOpens.clear();
    _schedSub = FirestoreSync().streamDailySchedule(_schedDate).listen((s) {
      if (!mounted) return;
      setState(() => _schedule = s);
      widget.logic.todayBlocks = s?.blocks ?? [];
    });
  }

  List<ScheduleBlock> get _liveBlocks =>
      (_schedule?.blocks ?? const <ScheduleBlock>[])
          .where((b) => b.status != 'deleted')
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  /// Navigation programmée vers l'onglet (lancement, widget, Siri…) : la carte
  /// MAINTENANT est en tête, on y revient.
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
    final today = _ymd(DateTime.now());
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
    final now = DateTime.now();
    var ok = false;
    String? reason;
    for (final d in [now, now.add(const Duration(days: 1))]) {
      final r = await gcalSyncDay(sync, _ymd(d));
      if (r?['ok'] == true) ok = true;
      reason ??= r?['reason'] as String?;
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Journée posée — $count blocs'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final date =
        _showTomorrow ? _ymd(now.add(const Duration(days: 1))) : _ymd(now);
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
                if (!_showTomorrow) ...[
                  const SizedBox(height: 16),
                  NowCard(
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
                    onChallenge: widget.onChallenge,
                  ),
                  NowCoachZone(
                    logic: widget.logic,
                    schedule: _schedule,
                    date: _schedDate,
                    tabOpens: _tabOpens,
                    onLaunch: widget.onNowLaunch ?? widget.onLaunch,
                    onChallengeAccept: widget.onChallengeAccept,
                    onChallengeSchedule: widget.onChallengeSchedule,
                  ),
                ],
                const SizedBox(height: 22),
                _programHeader(cs, link, text3),
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
                    onLaunch: _showTomorrow ? null : widget.onLaunch,
                    onOpenSource: widget.onOpenSource,
                  )
                else
                  DailyScheduleView(
                    key: ValueKey(date),
                    date: date,
                    logic: widget.logic,
                    visible: widget.visible,
                    onLaunch: _showTomorrow ? null : widget.onLaunch,
                    onOpenSource: widget.onOpenSource,
                    // Saut minimap (jauge) en mode liste.
                    onRegisterScrollToMinute: (fn) => _listScrollToMinute = fn,
                    title: '',
                    // Placeholder 21a/22c : sans domaine, le programme ne peut pas
                    // exister — l'étape est juste au-dessus (nudge de Maintenant).
                    emptyText: _showTomorrow
                        ? 'Rien de prévu pour demain.\nTouche pour ajouter un bloc, ou demande à Claude/ORION de planifier ta journée.'
                        : _domainsPlaceholder(),
                  ),
                // Bascule liste ⇄ frise en fin de section (§ 3.3), persistée.
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: Icon(
                        _timeline ? Icons.view_list_outlined : Icons.calendar_view_day_outlined,
                        size: 16),
                    label: Text(_timeline ? 'Voir en liste' : 'Voir en frise'),
                    style: TextButton.styleFrom(
                        foregroundColor: link,
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      setState(() => _timeline = !_timeline);
                      SharedPreferences.getInstance()
                          .then((p) => p.setBool(_timelinePrefKey, _timeline));
                    },
                  ),
                ),
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
                ] else ...[
                  _overdueCard(cs, now, link, text3),
                  // « Le meilleur à faire » : les routines à rattraper,
                  // actionnables sur place (+1 / −1 / passer) — ex-Maintenant.
                  BestToDoCard(logic: widget.logic, onStartTimed: widget.onStartTimed),
                  const SizedBox(height: 14),
                  Row(children: [
                    if (widget.onOpenDayReview != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.bar_chart_rounded, size: 18),
                          label: const Text('Résumé du jour'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            side: BorderSide(color: link.withOpacity(.4)),
                            foregroundColor: link,
                          ),
                          onPressed: widget.onOpenDayReview,
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.explore_outlined, size: 18),
                        label: const Text('Où on va'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          side: BorderSide(color: cs.onSurface.withOpacity(.2)),
                          foregroundColor: cs.onSurface.withOpacity(.7),
                        ),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => WhereWeGoScreen(logic: widget.logic),
                        )),
                      ),
                    ),
                  ]),
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
    final day = _showTomorrow ? now.add(const Duration(days: 1)) : now;
    final name = _kDays[day.weekday - 1];
    final title = _showTomorrow
        ? 'Demain · ${name[0].toUpperCase()}${name.substring(1)} ${day.day}'
        : '${name[0].toUpperCase()}${name.substring(1)} ${day.day}';
    final live = _liveBlocks;
    final done = live.where((b) => b.status == 'done').length;
    final nowMin = now.hour * 60 + now.minute;
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
      if (widget.onOpenActivities != null)
        _roundBtn(cs, Icons.timer_outlined, 'Chrono libre', widget.onOpenActivities!),
      const SizedBox(width: 8),
      _roundBtn(cs, Icons.auto_awesome, 'ORION',
          () => OrionScreen.show(context, FirestoreSync()),
          accent: true),
    ]);
  }

  Widget _roundBtn(ColorScheme cs, IconData icon, String tooltip, VoidCallback onTap,
      {bool accent = false}) {
    final dark = cs.brightness == Brightness.dark;
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: accent
            ? (dark ? kBActive : cs.primaryContainer.withOpacity(.5))
            : cs.onSurface.withOpacity(.05),
        shape: CircleBorder(
            side: BorderSide(
                color: accent
                    ? (dark ? kBPrimary : cs.primary).withOpacity(.35)
                    : cs.onSurface.withOpacity(.1))),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon,
                size: 18, color: accent ? (dark ? kBPrimary : cs.primary) : cs.onSurface),
          ),
        ),
      ),
    );
  }

  /// Ligne « PROGRAMME DU JOUR » (§ 3.3) : liens Demain / Modifier + outils
  /// (sync agenda, liste ⇄ frise, reprogrammer) — plus de boutons épinglés.
  Widget _programHeader(ColorScheme cs, Color link, Color text3) {
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
        child: Text(_showTomorrow ? 'PROGRAMME DE DEMAIN' : 'PROGRAMME DU JOUR',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: text3)),
      ),
      tlink(_showTomorrow ? 'Aujourd\'hui' : 'Demain',
          () => setState(() => _showTomorrow = !_showTomorrow)),
      tlink('Modifier', () {
        final n = DateTime.now();
        _openPlan(_showTomorrow ? _ymd(n.add(const Duration(days: 1))) : _ymd(n));
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
      if (!_showTomorrow)
        IconButton(
          tooltip: 'Reprogrammer la journée',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.delete_sweep_outlined, size: 18, color: cs.error.withOpacity(.85)),
          onPressed: _replanToday,
        ),
    ]);
  }

  /// « À TRAITER · n » (§ 3.4) : tâches en retard des projets actifs non en
  /// pause, 3 max + « + n autres ». Masquée si vide.
  Widget _overdueCard(ColorScheme cs, DateTime now, Color link, Color text3) {
    final items = <({Project p, ProjectTask t})>[];
    for (final p in widget.logic.currentProjects) {
      if (p.status != 'active' || p.paused) continue;
      for (final t in overdueTasks(p, now)) {
        items.add((p: p, t: t));
      }
    }
    if (items.isEmpty) return const SizedBox.shrink();
    items.sort((a, b) => a.t.endDate!.compareTo(b.t.endDate!));
    final dark = cs.brightness == Brightness.dark;
    final alert = dark ? kBAlert : cs.error;
    String ddmm(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(
        color: dark ? kBSurface : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: alert.withOpacity(.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('À TRAITER · ${items.length}',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: text3)),
          ),
          InkWell(
            onTap: () => _openPlan(_ymd(now)),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('Replanifier',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: link)),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        for (final it in items.take(3))
          InkWell(
            onTap: widget.onOpenTask == null ? null : () => widget.onOpenTask!(it.p, it.t),
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    Text(it.p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: text3)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(ddmm(it.t.endDate!),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: alert,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 8),
              ]),
            ),
          ),
        if (items.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text('+ ${items.length - 3} autres',
                style: TextStyle(fontSize: 12, color: text3)),
          ),
      ]),
    );
  }
}
