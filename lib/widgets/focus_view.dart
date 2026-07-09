import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/widgets/coach_moment_card.dart';
import 'package:productivitwo_v1/widgets/plan_day_screen.dart';
import 'package:productivitwo_v1/widgets/renegotiate_sheet.dart';
import 'package:productivitwo_v1/widgets/weekly_report_screen.dart';

/// Onglet « Maintenant » : focus pur sur CE qu'on fait sur le moment.
/// 3 états exclusifs :
///  1. Session en cours → chrono/minuteur + checklists (sous-actions, actions
///     propres, checklist de la routine liée) — sans le programme du jour.
///  2. Rien en cours mais des blocs restent → UNE carte focus (bloc en cours,
///     sinon prochain bloc) avec ▶, ✓ et la checklist de sa source.
///  3. Plus rien de prévu → « Que souhaites-tu faire maintenant ? »
///     (Mes routines / Mes activités).
/// Le programme complet vit dans l'onglet Aujourd'hui.
class FocusView extends StatefulWidget {
  final AppLogic logic;
  final AppState state;
  final Project? focusProject;
  final ProjectTask? focusTask;
  final void Function(Activity activity, Project? project, ProjectTask? task)
      onStartTimer;
  final VoidCallback onStopTimer;
  // Décompte du minuteur en cours (null = pas de minuteur → chrono normal).
  final DateTime? countdownEndsAt;
  final int? countdownTotalSec;
  // Coupe le minuteur SANS arrêter la session (bascule en chrono).
  final VoidCallback onStopCountdown;
  final void Function(Project project, ProjectTask task) onClearFocusTask;
  final void Function(Project project, ProjectTask task)? onTaskTap;
  // Lancer un bloc du programme (▶) → chrono + focus de la tâche/activité liée.
  final void Function(ScheduleBlock block)? onLaunchScheduledBlock;
  // Tap sur un bloc issu d'une source → ouvre sa fiche (tâche/routine/activité).
  final void Function(ScheduleBlock block)? onOpenScheduledBlockSource;
  // État vide : ouvre les sheets « Mes routines » / « Mes activités ».
  final VoidCallback? onOpenRoutines;
  final VoidCallback? onOpenActivities;
  // Carte coach « Maintenant » : « Faire le point » du soir → day review.
  final VoidCallback? onOpenDayReview;

  const FocusView({
    super.key,
    required this.logic,
    required this.state,
    required this.onStartTimer,
    required this.onStopTimer,
    required this.onStopCountdown,
    this.countdownEndsAt,
    this.countdownTotalSec,
    required this.onClearFocusTask,
    this.focusProject,
    this.focusTask,
    this.onTaskTap,
    this.onLaunchScheduledBlock,
    this.onOpenScheduledBlockSource,
    this.onOpenRoutines,
    this.onOpenActivities,
    this.onOpenDayReview,
  });

  @override
  State<FocusView> createState() => _FocusViewState();
}

class _FocusViewState extends State<FocusView> {
  Timer? _ticker;
  final _sync = FirestoreSync();
  StreamSubscription<DailySchedule?>? _schedSub;
  DailySchedule? _schedule;
  // Programme de la veille — nécessaire à la carte coach (« affaires prêtes
  // depuis hier »). Rarement modifié → simple fetch one-shot à l'init/minuit.
  DailySchedule? _yesterday;
  // Avance manuelle de la carte coach (CTA « Attaquer la journée »…) — vaut
  // pour la journée en cours seulement, remise à zéro à minuit.
  CoachMomentType? _coachAdvancedTo;
  // « À la volée » sur la carte « journée non planifiée » — masquée jusqu'à
  // demain (le lancement ad hoc de l'onglet reste dessous).
  bool _unplannedDismissed = false;
  // Artefacts (menu…) : la carte midi affiche le repas du jour (15c).
  List<Artifact> _artifacts = const [];
  StreamSubscription<List<Artifact>>? _artifactsSub;
  // Rapport hebdo de la semaine courante — teaser du dimanche soir (16a).
  WeeklyReport? _weeklyReport;
  String _schedDate = '';
  // Blocs-routine déjà validés via ✓ — évite le double incrément avant le
  // retour du stream (même garde que dans DailyScheduleView).
  final Set<String> _routineHit = {};

  // Champ libre « Que souhaites-tu faire maintenant ? »
  final _assistCtrl = TextEditingController();
  bool _assistBusy = false;
  String? _assistReply;
  List<Activity> _suggestions = const [];
  static const String _kNowAssistUrl =
      'https://nowassist-dzos75b65q-uc.a.run.app';

  AppLogic get logic => widget.logic;
  AppState get st => widget.state;

  @override
  void initState() {
    super.initState();
    _subscribeSchedule();
    _artifactsSub = _sync.streamArtifacts().listen((a) {
      if (mounted) setState(() => _artifacts = a);
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Passage de minuit → on bascule le stream sur le nouveau jour.
      if (_ymd(DateTime.now()) != _schedDate) _subscribeSchedule();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _schedSub?.cancel();
    _artifactsSub?.cancel();
    _assistCtrl.dispose();
    super.dispose();
  }

  // ── Champ libre : match local d'abord (0 appel IA), assistant sinon ─────────

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .trim();

  // Mots vides exclus du match (sinon « faire ma séance sport » matcherait
  // « Faire la vaisselle » via « faire »).
  static const _stopWords = {
    'faire', 'avec', 'pour', 'dans', 'les', 'des', 'une', 'mon', 'mes',
    'veux', 'envie', 'aller', 'voudrais', 'aimerais', 'maintenant',
    'seance', 'session', 'petit', 'petite', 'heure', 'minutes',
  };

  /// Routines/activités existantes qui matchent le texte tapé — pour éviter un
  /// appel IA (et un doublon) quand « faire ma séance sport » = la routine
  /// Sport qui existe déjà.
  List<Activity> _localMatches(String query) {
    final q = _norm(query);
    if (q.length < 3) return const [];
    final words = q
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !_stopWords.contains(w))
        .toList();
    return st.activities.where((a) {
      if (a.deleted) return false;
      final name = _norm(a.name);
      if (name.isEmpty) return false;
      return q.contains(name) ||
          name.contains(q) ||
          words.any((w) => name.contains(w));
    }).toList();
  }

  Future<void> _submitAssist({bool forceAi = false}) async {
    final text = _assistCtrl.text.trim();
    if (text.isEmpty || _assistBusy) return;

    // 1) Interception locale : une routine/activité existante correspond →
    //    on la propose direct, sans appel IA.
    if (!forceAi) {
      final matches = _localMatches(text);
      if (matches.isNotEmpty) {
        setState(() {
          _suggestions = matches.take(4).toList();
          _assistReply = null;
        });
        return;
      }
    }

    // 2) Appel assistant (Sonnet côté serveur, plafonné).
    setState(() {
      _assistBusy = true;
      _suggestions = const [];
      _assistReply = null;
    });
    try {
      final token = await _sync.ensureWidgetToken();
      final raw = token.rawToken;
      final uid = _sync.uid;
      if (raw == null || raw.isEmpty || uid == null) {
        setState(() => _assistReply =
            'Assistant indisponible sur cet appareil (token API manquant).');
        return;
      }
      final resp = await http
          .post(
            Uri.parse(_kNowAssistUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $raw',
            },
            body: jsonEncode({'uid': uid, 'message': text}),
          )
          .timeout(const Duration(seconds: 60));
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() {
        _assistReply = resp.statusCode == 200
            ? (body['message'] as String? ?? 'C\'est noté.')
            : (body['error'] as String? ?? 'Erreur — réessaie.');
        if (resp.statusCode == 200) _assistCtrl.clear();
      });
      // Les blocs créés arrivent tout seuls via le stream du programme.
    } catch (_) {
      if (mounted) {
        setState(() => _assistReply = 'Connexion impossible — réessaie.');
      }
    } finally {
      if (mounted) setState(() => _assistBusy = false);
    }
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _subscribeSchedule() {
    _schedSub?.cancel();
    final now = DateTime.now();
    _schedDate = _ymd(now);
    _coachAdvancedTo = null; // nouvelle journée → l'horloge reprend la main
    _unplannedDismissed = false;
    _schedSub = _sync.streamDailySchedule(_schedDate).listen((s) {
      if (!mounted) return;
      setState(() => _schedule = s);
      // Garde todayBlocks frais même si l'onglet Aujourd'hui affiche « Demain ».
      logic.todayBlocks = s?.blocks ?? [];
    });
    // Programme de la veille (one-shot) pour la carte coach du réveil.
    final yesterday = _ymd(now.subtract(const Duration(days: 1)));
    _sync.streamDailySchedule(yesterday).first.then((s) {
      if (mounted) setState(() => _yesterday = s);
    }).catchError((_) {});
    // Rapport hebdo de la semaine courante (16a) — one-shot, léger.
    final monday = _ymd(DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1)));
    _sync.fetchWeeklyReport(monday).then((r) {
      if (mounted) setState(() => _weeklyReport = r);
    }).catchError((_) {});
  }

  // ── Carte coach « Maintenant » ───────────────────────────────────────────────

  Widget _coachCard(DateTime now) {
    final moment = computeCoachMoment(
        now, st, _schedule, _yesterday, st.sessions,
        advancedTo: _coachAdvancedTo,
        unplannedDismissed: _unplannedDismissed,
        artifacts: _artifacts,
        weeklyReport: _weeklyReport);
    return CoachMomentCard(
      moment: moment,
      onLaunch: widget.onLaunchScheduledBlock,
      // Renégocier (12a) : trois issues générées depuis le réel — réduire /
      // déplacer / reporter. Remplace l'ouverture de fiche v1.
      onRenegotiate: (block) => showRenegotiateSheet(
        context,
        logic: logic,
        block: block,
        date: _schedDate,
        onLaunch: widget.onLaunchScheduledBlock,
      ),
      onOpenDayReview: widget.onOpenDayReview,
      onAdvance: (target) => setState(() => _coachAdvancedTo = target),
      onPlanDay: _openPlanToday,
      onDismiss: () => setState(() => _unplannedDismissed = true),
      onMealEaten: (id) => _logMeal(id, eaten: true),
      onMealShift: (id) => _logMeal(id, eaten: false),
      onOpenWeeklyReport: _weeklyReport == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WeeklyReportScreen(
                    logic: logic, report: _weeklyReport!),
              )),
    );
  }

  /// Carte midi menu (15c) : ✓ Mangé incrémente le fait tracké ; « Autre
  /// chose » logge 'other' ET fait glisser le menu d'un jour — sans pénalité.
  Future<void> _logMeal(String artifactId, {required bool eaten}) async {
    final a = _artifacts.where((x) => x.id == artifactId).firstOrNull;
    if (a == null) return;
    a.mealLog[_schedDate] = eaten ? 'eaten' : 'other';
    if (!eaten) shiftMenuOneDay(a, _schedDate);
    await _sync.saveArtifact(a);
    if (mounted) {
      setState(() {});
      if (!eaten) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Le menu glisse d\'un jour — sans pénalité.'),
          duration: Duration(seconds: 2),
        ));
      }
    }
  }

  /// « Planifier · 2 min » → écran de planification en mode rattrapage express
  /// (cible aujourd'hui). Au retour : toast « Journée posée — N blocs » ; la
  /// carte coach se recalcule d'elle-même via le stream du programme (9b).
  Future<void> _openPlanToday() async {
    final count = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => PlanDayScreen(
        logic: logic,
        targetDate: _schedDate,
        rattrapage: true,
        onLaunchBlock: widget.onLaunchScheduledBlock,
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

  // ── Données session en cours ─────────────────────────────────────────────────

  Session? get _runningSession {
    Session? last;
    for (final s in st.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  Activity? get _runningActivity => logic.runningActivity();

  Duration get _elapsedDuration {
    final s = _runningSession;
    if (s == null) return Duration.zero;
    return DateTime.now().difference(s.startAt);
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Sélection du bloc focus ──────────────────────────────────────────────────

  DateTime _blockStart(ScheduleBlock b, DateTime now) {
    final parts = b.startTime.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(now.year, now.month, now.day, h, m);
  }

  List<ScheduleBlock> get _pendingBlocks =>
      (_schedule?.blocks ?? const <ScheduleBlock>[])
          .where((b) => b.status == 'pending')
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  /// Le bloc à afficher : celui dont la fenêtre couvre l'heure actuelle,
  /// sinon le prochain à venir. Les blocs passés non faits ne squattent pas le
  /// focus (ils restent visibles dans Aujourd'hui + ligne « en retard » ici).
  ScheduleBlock? _focusBlock(DateTime now) {
    for (final b in _pendingBlocks) {
      final start = _blockStart(b, now);
      final end = start.add(Duration(minutes: b.durationMin));
      final current = !now.isBefore(start) && now.isBefore(end);
      final upcoming = now.isBefore(start);
      if (current || upcoming) return b;
    }
    return null;
  }

  bool _isCurrent(ScheduleBlock b, DateTime now) {
    final start = _blockStart(b, now);
    return !now.isBefore(start) &&
        now.isBefore(start.add(Duration(minutes: b.durationMin)));
  }

  int _overdueCount(DateTime now) => _pendingBlocks
      .where((b) => now.isAfter(
          _blockStart(b, now).add(Duration(minutes: b.durationMin))))
      .length;

  ScheduleBlock? _nextAfter(ScheduleBlock? current, DateTime now) {
    for (final b in _pendingBlocks) {
      if (b.id == current?.id) continue;
      if (now.isBefore(_blockStart(b, now))) return b;
    }
    return null;
  }

  // ── Actions sur le bloc focus ────────────────────────────────────────────────

  /// ✓ sur la carte : marque le bloc done + valide la routine liée du jour
  /// (même règle que DailyScheduleView : pas de double incrément si la cible
  /// est déjà atteinte ou si ce bloc a déjà validé).
  Future<void> _markBlockDone(ScheduleBlock b) async {
    final id = b.activityId;
    if (id != null && !_routineHit.contains(b.id)) {
      final act = st.activities.where((a) => a.id == id).firstOrNull;
      if (act != null && act.isHabit) {
        final day = DateTime.now();
        final tgt = logic.activeHabitTarget(act);
        _routineHit.add(b.id);
        if (!(tgt > 0 && logic.habitValueOn(id, day) >= tgt)) {
          logic.incHabit(id, 1, DateTime(day.year, day.month, day.day));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ Routine validée : ${act.name}'),
              duration: const Duration(seconds: 2),
            ));
          }
        }
      }
    }
    await _sync.updateBlockStatus(_schedDate, b.id, 'done');
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = _runningActivity;
    if (running != null) return _buildActive(context, cs, running);

    final now = DateTime.now();
    final focus = _focusBlock(now);
    return focus != null
        ? _buildFocusIdle(context, cs, focus, now)
        : _buildEmpty(context, cs, now);
  }

  // ── État 2 : carte focus (rien en cours, programme restant) ─────────────────

  Widget _buildFocusIdle(
      BuildContext context, ColorScheme cs, ScheduleBlock b, DateTime now) {
    final next = _nextAfter(b, now);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Maintenant',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            const SizedBox(height: 20),
            _coachCard(now),
            _focusCard(context, cs, b, now),
            if (next != null) ...[
              const SizedBox(height: 14),
              _nextHint(cs, next),
            ],
            _overdueHint(cs, now),
          ],
        ),
      ),
    );
  }

  Widget _focusCard(
      BuildContext context, ColorScheme cs, ScheduleBlock b, DateTime now) {
    final color = _categoryColor(b.category, cs);
    final current = _isCurrent(b, now);
    final start = _blockStart(b, now);
    final end = start.add(Duration(minutes: b.durationMin));
    final launchable = widget.onLaunchScheduledBlock != null &&
        (b.projectId != null || b.activityId != null);
    final hasSource = b.projectId != null || b.activityId != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: color.withOpacity(.15),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(
                current
                    ? 'EN COURS · jusqu\'à ${_hm(end)}'
                    : 'À ${_hm(start)}',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                    color: color),
              ),
            ),
            const Spacer(),
            Icon(_categoryIcon(b.category), size: 15, color: color),
            const SizedBox(width: 4),
            Text(fmtMin(b.durationMin),
                style: TextStyle(
                    fontSize: 11.5, color: cs.onSurface.withOpacity(.5))),
          ]),
          const SizedBox(height: 10),
          InkWell(
            onTap: hasSource && widget.onOpenScheduledBlockSource != null
                ? () => widget.onOpenScheduledBlockSource!(b)
                : null,
            child: Text(b.title,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          // Checklist de la source (sous-actions tâche / actions propres /
          // checklist routine), cochable directement.
          ..._sourceChecklist(cs, b),
          const SizedBox(height: 14),
          Row(children: [
            if (launchable)
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Lancer'),
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => widget.onLaunchScheduledBlock!(b),
                ),
              ),
            if (launchable) const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Fait'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withOpacity(.5)),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _markBlockDone(b),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// Checklist selon la source du bloc. Liste vide si pas de source détaillée.
  List<Widget> _sourceChecklist(ColorScheme cs, ScheduleBlock b) {
    final color = _categoryColor(b.category, cs);
    final tiles = <Widget>[];

    // Tâche Gantt → sous-actions.
    if (b.projectId != null && b.taskId != null) {
      for (final p in logic.currentProjects) {
        if (p.id != b.projectId) continue;
        for (final t in p.tasks) {
          if (t.id != b.taskId || t.actions.isEmpty) continue;
          tiles.addAll(t.actions.map((a) => _ActionCheckTile(
                action: a,
                color: color,
                onToggle: (v) async {
                  setState(() {
                    a.done = v;
                    a.doneAt = v ? DateTime.now() : null;
                  });
                  await _sync.saveProjectTasks(p.id, p.tasks);
                },
              )));
        }
      }
    } else if (b.activityId != null) {
      final act =
          st.activities.where((a) => a.id == b.activityId).firstOrNull;
      if (act != null && act.isHabit) {
        // Routine → sa checklist du jour.
        final items = logic.checklistForHabit(act.id);
        final done = logic.checklistDoneSet(act.id, DateTime.now());
        for (var i = 0; i < items.length; i++) {
          tiles.add(_checkRow(cs, color, items[i], done.contains(i), () {
            logic.toggleChecklistItem(act.id, DateTime.now(), i);
            setState(() {});
          }));
        }
      } else if (act != null) {
        // Activité-temps → ses actions propres.
        tiles.addAll(logic.ownActionsOf(act.id).map((a) => _ActionCheckTile(
              action: a,
              color: color,
              onToggle: (v) {
                logic.toggleOwnAction(act.id, a.id, v);
                setState(() {});
              },
            )));
      }
    }

    if (tiles.isEmpty) return const [];
    return [const SizedBox(height: 10), ...tiles];
  }

  Widget _checkRow(ColorScheme cs, Color color, String label, bool done,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 22,
            color: done ? color : cs.onSurface.withOpacity(.3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                  fontSize: 14,
                  color:
                      done ? cs.onSurface.withOpacity(.35) : cs.onSurface,
                  decoration: done ? TextDecoration.lineThrough : null,
                )),
          ),
        ]),
      ),
    );
  }

  Widget _nextHint(ColorScheme cs, ScheduleBlock next) {
    return Row(children: [
      Icon(Icons.schedule, size: 14, color: cs.onSurface.withOpacity(.35)),
      const SizedBox(width: 6),
      Text('À suivre : ${next.startTime} · ${next.title}',
          style:
              TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.5))),
    ]);
  }

  Widget _overdueHint(ColorScheme cs, DateTime now) {
    final n = _overdueCount(now);
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        '$n bloc${n > 1 ? 's' : ''} plus tôt non fait${n > 1 ? 's' : ''} — à retrouver dans Aujourd\'hui',
        style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: cs.onSurface.withOpacity(.4)),
      ),
    );
  }

  // ── État 3 : plus rien de prévu ──────────────────────────────────────────────

  Widget _buildEmpty(BuildContext context, ColorScheme cs, DateTime now) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Maintenant',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            const SizedBox(height: 20),
            _coachCard(now),
            const SizedBox(height: 8),
            Center(
              child: Column(children: [
                Icon(Icons.self_improvement,
                    size: 44, color: cs.onSurface.withOpacity(.25)),
                const SizedBox(height: 12),
                Text('Que souhaites-tu faire maintenant ?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(.75))),
              ]),
            ),
            const SizedBox(height: 24),
            if (widget.onOpenRoutines != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.loop, size: 18),
                label: const Text('Mes routines'),
                onPressed: widget.onOpenRoutines,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            const SizedBox(height: 10),
            if (widget.onOpenActivities != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.timer_outlined, size: 18),
                label: const Text('Mes activités'),
                onPressed: widget.onOpenActivities,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            const SizedBox(height: 18),

            // Champ libre : match local d'abord (0 token), assistant sinon.
            TextField(
              controller: _assistCtrl,
              enabled: !_assistBusy,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitAssist(),
              decoration: InputDecoration(
                hintText: 'Décris ce que tu veux faire…',
                hintStyle: TextStyle(
                    fontSize: 13.5, color: cs.onSurface.withOpacity(.35)),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: _assistBusy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: Icon(Icons.send_rounded,
                            size: 19, color: cs.primary),
                        onPressed: () => _submitAssist(),
                      ),
              ),
            ),

            // Suggestions locales : « tu veux dire … ? » — évite l'appel IA
            // (et un doublon) quand la routine/activité existe déjà.
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Ça existe déjà — lance-le direct :',
                  style: TextStyle(
                      fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in _suggestions)
                    ActionChip(
                      avatar: Icon(
                          a.isHabit ? Icons.loop : Icons.play_arrow_rounded,
                          size: 16,
                          color: cs.primary),
                      label: Text(a.name),
                      onPressed: () {
                        setState(() => _suggestions = const []);
                        if (a.isHabit) {
                          widget.onOpenRoutines?.call();
                        } else {
                          widget.onStartTimer(a, null, null);
                        }
                      },
                    ),
                  ActionChip(
                    avatar: Icon(Icons.auto_awesome,
                        size: 15, color: cs.onSurface.withOpacity(.5)),
                    label: const Text('Non, demander à l\'assistant'),
                    onPressed: () => _submitAssist(forceAi: true),
                  ),
                ],
              ),
            ],

            // Réponse de l'assistant.
            if (_assistReply != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_assistReply!,
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: cs.onSurface.withOpacity(.85))),
                    ),
                  ],
                ),
              ),
            ],
            _overdueHint(cs, now),
          ],
        ),
      ),
    );
  }

  // ── État 1 : session active ──────────────────────────────────────────────────

  Widget _buildActive(BuildContext context, ColorScheme cs, Activity running) {
    final domain =
        st.activeDomains.where((d) => d.id == running.domainId).firstOrNull;
    final color = domainColor(running.domainId, st.activeDomains) ?? cs.primary;
    final elapsed = _elapsedDuration;
    final task = widget.focusTask;
    final project = widget.focusProject;
    final now = DateTime.now();

    final endsAt = widget.countdownEndsAt;
    final remaining = endsAt != null ? endsAt.difference(now) : null;
    final isCountdown = remaining != null && remaining > Duration.zero;

    // Routine liée à l'activité en cours → sa checklist s'affiche pendant la
    // session (ex. routine « Sport » minutée sur l'activité « Sport »).
    final linkedRoutine = st.activities
        .where((a) =>
            a.isHabit && !a.deleted && a.linkedActivityId == running.id)
        .firstOrNull;
    final next = _focusBlock(now);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header domaine + activité
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  '${domain?.name.toUpperCase() ?? ''} · ${running.name}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: cs.onSurface.withOpacity(.5)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Carte tâche Gantt (si liée)
            if (task != null && project != null) ...[
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onTaskTap?.call(project, task),
                onLongPress: () => widget.onClearFocusTask(project, task),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.title,
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        task.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Minuteur (anneau de décompte) OU chrono (temps écoulé)
            if (isCountdown) ...[
              Center(
                child: _CountdownRing(
                  remaining: remaining,
                  totalSec: widget.countdownTotalSec ?? remaining.inSeconds,
                  color: color,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.timer_off_outlined, size: 18),
                  label: const Text('Arrêter le minuteur'),
                  onPressed: widget.onStopCountdown,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(200, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ] else ...[
              Center(
                child: Text(
                  _fmtDuration(elapsed),
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 2,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: FilledButton.icon(
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  label: const Text('Arrêter'),
                  onPressed: widget.onStopTimer,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                    minimumSize: const Size(160, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],

            // Sous-actions de la tâche
            if (task != null && task.actions.isNotEmpty) ...[
              const SizedBox(height: 32),
              _sectionLabel(cs, 'SOUS-ACTIONS'),
              const SizedBox(height: 8),
              ...task.actions.map((a) => _ActionCheckTile(
                    action: a,
                    color: color,
                    onToggle: (value) => _toggleAction(a, value),
                  )),
            ],

            // Actions PROPRES de l'activité en cours.
            if (logic.ownActionsOf(running.id).isNotEmpty) ...[
              const SizedBox(height: 24),
              _sectionLabel(cs, 'ACTIONS DE L\'ACTIVITÉ'),
              const SizedBox(height: 8),
              ...logic.ownActionsOf(running.id).map((a) => _ActionCheckTile(
                    action: a,
                    color: color,
                    onToggle: (value) {
                      logic.toggleOwnAction(running.id, a.id, value);
                      setState(() {});
                    },
                  )),
            ],

            // Checklist de la routine liée à l'activité en cours.
            if (linkedRoutine != null &&
                logic.checklistForHabit(linkedRoutine.id).isNotEmpty) ...[
              const SizedBox(height: 24),
              _sectionLabel(cs, 'CHECKLIST · ${linkedRoutine.name.toUpperCase()}'),
              const SizedBox(height: 8),
              ...() {
                final items = logic.checklistForHabit(linkedRoutine.id);
                final done =
                    logic.checklistDoneSet(linkedRoutine.id, DateTime.now());
                return [
                  for (var i = 0; i < items.length; i++)
                    _checkRow(cs, color, items[i], done.contains(i), () {
                      logic.toggleChecklistItem(
                          linkedRoutine.id, DateTime.now(), i);
                      setState(() {});
                    }),
                ];
              }(),
            ],

            if (task == null) ...[
              const SizedBox(height: 24),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.account_tree_outlined, size: 16),
                  label: const Text('Lier à une tâche'),
                  onPressed: () => _showTaskPicker(context, running),
                ),
              ),
            ],

            // Rappel discret du prochain bloc — pas de programme complet ici
            // (mode focus pur ; le programme vit dans Aujourd'hui).
            if (!isCountdown && next != null) ...[
              const SizedBox(height: 28),
              _nextHint(cs, next),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ColorScheme cs, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: cs.onSurface.withOpacity(.4),
        ),
      );

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Color _categoryColor(String category, ColorScheme cs) => switch (category) {
        'project' => cs.primary,
        'routine' => const Color(0xFF1a9e6e),
        'personal' => cs.secondary,
        'break' => cs.outline,
        _ => cs.tertiary,
      };

  IconData _categoryIcon(String category) => switch (category) {
        'project' => Icons.rocket_launch_outlined,
        'routine' => Icons.loop,
        'personal' => Icons.home_outlined,
        'break' => Icons.coffee_outlined,
        _ => Icons.circle_outlined,
      };

  Future<void> _toggleAction(TaskAction action, bool value) async {
    final task = widget.focusTask;
    final project = widget.focusProject;
    if (task == null || project == null) return;
    setState(() {
      action.done = value;
      action.doneAt = value ? DateTime.now() : null;
    });
    await _sync.saveProjectTasks(project.id, project.tasks);
  }

  // ── Flow démarrage ───────────────────────────────────────────────────────────

  Future<void> _showTaskPicker(BuildContext context, Activity activity) async {
    final result = await _pickTask(context, activity);
    if (result == null || !mounted) return;
    widget.onStartTimer(activity, result.$1, result.$2);
  }

  Future<(Project, ProjectTask)?> _pickTask(
      BuildContext context, Activity activity) async {
    // Tâches actives aujourd'hui du même domaine
    List<Project> projects = [];
    try {
      projects = await _sync.fetchProjects();
    } catch (_) {}

    final today = DateTime.now();
    final todayD = DateTime(today.year, today.month, today.day);

    final pairs = <(Project, ProjectTask)>[];
    for (final p in projects) {
      if (p.status == 'archived') continue;
      if (p.domainId != activity.domainId) continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        if (t.startDate.isAfter(todayD)) continue;
        pairs.add((p, t));
      }
    }

    if (!mounted) return null;

    return showModalBottomSheet<(Project, ProjectTask)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Sur quelle tâche ?',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            if (pairs.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Aucune tâche active aujourd\'hui dans ce domaine.',
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          Theme.of(ctx).colorScheme.onSurface.withOpacity(.4)),
                ),
              ),
            for (final pair in pairs)
              ListTile(
                title: Text(pair.$2.title),
                subtitle: Text(pair.$1.title,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withOpacity(.45))),
                onTap: () => Navigator.pop(ctx, pair),
              ),
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: const Text('Passer — sans tâche'),
              onTap: () => Navigator.pop(ctx, null),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Anneau de décompte (mode minuteur) ───────────────────────────────────────

class _CountdownRing extends StatelessWidget {
  final Duration remaining;
  final int totalSec;
  final Color color;
  const _CountdownRing(
      {required this.remaining, required this.totalSec, required this.color});

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress =
        totalSec > 0 ? (remaining.inSeconds / totalSec).clamp(0.0, 1.0) : 0.0;
    final urgent = remaining.inSeconds <= 60;
    final ringColor = urgent ? Colors.red.shade400 : color;
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 240,
            height: 240,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              backgroundColor: cs.surfaceContainerHighest.withOpacity(.4),
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmt(remaining),
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1,
                  color: cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text('restant',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(.45))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Tuile sous-action cochable ────────────────────────────────────────────────

class _ActionCheckTile extends StatelessWidget {
  final TaskAction action;
  final Color color;
  final ValueChanged<bool> onToggle;

  const _ActionCheckTile({
    required this.action,
    required this.color,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onToggle(!action.done),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              action.done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 22,
              color: action.done ? color : cs.onSurface.withOpacity(.3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                action.title,
                style: TextStyle(
                  fontSize: 14,
                  color: action.done
                      ? cs.onSurface.withOpacity(.35)
                      : cs.onSurface,
                  decoration:
                      action.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
