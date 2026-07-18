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
import 'package:productivitwo_v1/utils/free_moment.dart';
import 'package:productivitwo_v1/utils/onboarding_slots.dart';
import 'package:productivitwo_v1/utils/routine_match.dart';
import 'package:productivitwo_v1/widgets/availability_sheet.dart';
import 'package:productivitwo_v1/widgets/coach_moment_card.dart';
import 'package:productivitwo_v1/widgets/domain_naming_sheet.dart';
import 'package:productivitwo_v1/widgets/domain_session_screen.dart';
import 'package:productivitwo_v1/widgets/habit_count_sheet.dart';
import 'package:productivitwo_v1/widgets/plan_day_screen.dart';
import 'package:productivitwo_v1/widgets/plan_next_sheet.dart';
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
  // Défi ORION : chip du guide → dialog « ORION te défie » existant ;
  // « Je relève 🔥 » de la carte → chrono + minuteur-alarme + streak ;
  // « Programmer 📅 » → sheet défi daté (mêmes flows que le bouton doré).
  final VoidCallback? onChallenge;
  final void Function(Activity activity, int minutes)? onChallengeAccept;
  // Future : la vue attend la fin de la pose pour rafraîchir la liste des
  // défis déjà programmés (sinon la carte repropose un défi qu'on vient de
  // poser pour demain).
  final Future<void> Function(Activity activity, int minutes)?
      onChallengeSchedule;

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
    this.onChallenge,
    this.onChallengeAccept,
    this.onChallengeSchedule,
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
  // Nudge domaines (Partie D) : faits calculés sur ±7 jours de programme.
  int _sessionSkipCount = 0; // sessions de définition sautées (déclenche 21c)
  String? _nextSessionLabel; // « demain 18 h 30 » — prochaine session posée
  bool _nudgeDismissed = false; // « Garder [créneau] » — silence pour le jour
  // Guide du moment libre : intention choisie (chips « Que souhaites-tu faire ? »).
  FreeIntent? _freeIntent;
  // Défi ORION : activités ayant déjà un défi 🔥 programmé (aujourd'hui/futur)
  // — exclues pour que le défi propose autre chose (même règle que le bouton).
  Set<String> _scheduledChallengeIds = const {};
  // GTD Gantt : tâches dont une étape est déjà programmée (aujourd'hui/futur)
  // — le moment est choisi, la carte n'insiste pas.
  Set<String> _scheduledStepTaskIds = const {};
  // « Plus tard » sur la question micro-cible — silence pour la session.
  bool _microTargetDismissed = false;
  // Renégociation faite → la carte dérive respire 45 min (pas de rafale).
  DateTime? _driftSnoozeUntil;
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
    _sync.fetchScheduledChallengeActivityIds().then((ids) {
      if (mounted) setState(() => _scheduledChallengeIds = ids);
    });
    _sync.fetchScheduledTaskIds().then((ids) {
      if (mounted) setState(() => _scheduledStepTaskIds = ids);
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
    _nudgeDismissed = false;
    _loadNudgeFacts(now);
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

  // ── Nudge domaines (Partie D) : faits sur ±7 jours de programme ─────────────

  /// Ne coûte rien tant qu'aucun domaine n'est seulement « nommé » (les
  /// variantes 21b/21c n'existent que pour eux ; 21a n'a besoin de rien).
  Future<void> _loadNudgeFacts(DateTime now) async {
    _sessionSkipCount = 0;
    _nextSessionLabel = null;
    if (!st.domains
        .any((d) => !d.deleted && d.definitionStatus == 'named')) {
      return;
    }
    try {
      final days = await Future.wait(List.generate(15, (i) {
        final d = now.add(Duration(days: i - 7)); // J-7 … J+7
        return _sync.fetchDailySchedule(_ymd(d)).catchError((_) => null);
      }));
      var skips = 0;
      String? nextLabel;
      const weekdays = [
        'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
      ];
      for (var i = 0; i < days.length; i++) {
        final offset = i - 7;
        for (final b in days[i]?.blocks ?? const <ScheduleBlock>[]) {
          if (b.kind != 'session' || b.status == 'deleted') continue;
          // Passé : une session non faite a sauté. Futur : la prochaine posée.
          if (offset < 0 && b.status != 'done') skips++;
          if (offset >= 0 && b.status == 'pending' && nextLabel == null) {
            final day = offset == 0
                ? 'aujourd\'hui'
                : offset == 1
                    ? 'demain'
                    : weekdays[now.add(Duration(days: offset)).weekday - 1];
            final p = b.startTime.split(':');
            final h = int.tryParse(p.first) ?? 0;
            final m = p.length > 1 && p[1] != '00' ? ' ${p[1]}' : '';
            nextLabel = '$day $h h$m';
          }
        }
      }
      if (mounted) {
        setState(() {
          _sessionSkipCount = skips;
          _nextSessionLabel = nextLabel;
        });
      }
    } catch (_) {}
  }

  /// « Nommer mes domaines — 2 min » (21a) → sheet in-place (22a/22b).
  Future<void> _openNamingSheet() async {
    final named = await showDomainNamingSheet(context, logic: logic);
    if (named != null && named.isNotEmpty && mounted) {
      setState(() {}); // le nudge recalcule : « Définir « X » — 15 min » (22c)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${named.length} domaine${named.length > 1 ? 's' : ''} nommé${named.length > 1 ? 's' : ''} — 2 min chrono'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// « Ce soir plutôt » (21a) — pose le nommage comme un vrai bloc ce soir.
  Future<void> _poseNamingTonight() async {
    final now = DateTime.now();
    final startMin = (now.hour * 60 + now.minute + 30).clamp(19 * 60, 21 * 60);
    final hm =
        '${(startMin ~/ 60).toString().padLeft(2, '0')}:${(startMin % 60).toString().padLeft(2, '0')}';
    await _sync.addScheduleBlock(
        _schedDate,
        ScheduleBlock(
          startTime: hm,
          durationMin: 5,
          title: 'Nommer mes domaines — 2 min',
          category: 'personal',
          kind: 'session',
        ));
    if (mounted) {
      setState(() => _nudgeDismissed = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Posé ce soir à ${hm.replaceFirst(':', ' h ')}.'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  /// « Faire la session maintenant » (21b) / « Version courte — 8 min » (21c).
  void _startDomainSession(String domain, {bool short = false}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DomainSessionScreen(
          logic: logic, domainName: domain, shortVersion: short),
    ));
  }

  /// « Plus tard — pose les N sessions dans ma semaine » (22c) /
  /// « Reposer un créneau » (21c) — mécanique 18b.
  Future<void> _poseRemainingSessions() async {
    final named = st.domains
        .where((d) => !d.deleted && d.definitionStatus == 'named')
        .toList();
    if (named.isEmpty) return;
    final now = DateTime.now();
    final slots = definitionSessionSlots(now, named.length);
    for (var i = 0; i < named.length; i++) {
      final slot = slots[i];
      await _sync.addScheduleBlock(
        _ymd(slot),
        ScheduleBlock(
          startTime:
              '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}',
          durationMin: 20,
          title: 'Définir « ${named[i].name} » avec Orion',
          category: 'personal',
          kind: 'session',
          domainId: named[i].id,
        ),
      );
    }
    if (mounted) {
      setState(() => _nudgeDismissed = true);
      _loadNudgeFacts(now);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${named.length} session${named.length > 1 ? 's' : ''} posée${named.length > 1 ? 's' : ''} dans ta semaine — engagements comme les autres.'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Guide du moment libre (« Que souhaites-tu faire ? ») ────────────────────

  /// Lance une proposition en un tap : bloc synthétique (non persisté) →
  /// même machinerie que le ▶ du programme (chrono ciblé + focus).
  void _launchProposalBlock({
    String? activityId,
    String? projectId,
    String? taskId,
    required String title,
  }) {
    final now = DateTime.now();
    widget.onLaunchScheduledBlock?.call(ScheduleBlock(
      startTime:
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      durationMin: 25,
      title: title,
      category: projectId != null ? 'project' : 'routine',
      activityId: activityId,
      projectId: projectId,
      taskId: taskId,
    ));
  }

  List<Widget> _freeMomentSection(ColorScheme cs, DateTime now) {
    final intents = freeIntentsFor(now);
    // Chip défi : uniquement si un vrai défi existe (une activité-temps en
    // retard sur sa cible du jour) — ouvre le dialog « ORION te défie ».
    final hasChallenge = widget.onChallenge != null &&
        logic.challengeActivity(exclude: _scheduledChallengeIds) != null;
    return [
      Center(
        child: Column(children: [
          Icon(Icons.self_improvement,
              size: 44, color: cs.onSurface.withOpacity(.25)),
          const SizedBox(height: 12),
          Text('Rien en cours — que souhaites-tu faire ?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withOpacity(.75))),
        ]),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final i in intents)
            ChoiceChip(
              avatar: Icon(_intentIcon(i),
                  size: 16,
                  color: _freeIntent == i ? cs.surface : cs.primary),
              label: Text(freeIntentLabel(i)),
              selected: _freeIntent == i,
              selectedColor: cs.primary,
              labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _freeIntent == i ? cs.surface : null),
              onSelected: (_) => setState(
                  () => _freeIntent = _freeIntent == i ? null : i),
            ),
          if (hasChallenge)
            ActionChip(
              avatar: Icon(Icons.local_fire_department_rounded,
                  size: 16, color: const Color(0xFFB8860B)),
              label: const Text('ORION me défie'),
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              onPressed: widget.onChallenge,
            ),
        ],
      ),
      if (_freeIntent != null) ...[
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Column(
            key: ValueKey('intent-$_freeIntent'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _intentProposals(cs, now, _freeIntent!),
          ),
        ),
      ],
    ];
  }

  IconData _intentIcon(FreeIntent i) => switch (i) {
        FreeIntent.sleep => Icons.bedtime_outlined,
        FreeIntent.rest => Icons.spa_outlined,
        FreeIntent.project => Icons.rocket_launch_outlined,
        FreeIntent.routines => Icons.loop,
        FreeIntent.plan => Icons.edit_calendar_outlined,
      };

  /// Les propositions d'une intention — toujours tirées du réel, jamais
  /// inventées ; une donnée absente = ligne absente.
  List<Widget> _intentProposals(ColorScheme cs, DateTime now, FreeIntent i) {
    switch (i) {
      case FreeIntent.project:
        final props = projectProposals(now, logic.currentProjects);
        if (props.isEmpty) {
          return [
            _freeHint(cs,
                'Aucune tâche ouverte dans tes projets — c\'est peut-être le moment d\'en poser un.'),
          ];
        }
        return [
          for (final p in props)
            _proposalRow(
              cs,
              p.task.title,
              p.subtitle,
              Icons.play_arrow_rounded,
              () => _launchProposalBlock(
                  projectId: p.project.id,
                  taskId: p.task.id,
                  title: p.task.title),
            ),
          _freeHint(cs, '▶ lance un chrono ciblé de 25 min — l\'essentiel vaut mieux que 0.'),
        ];

      case FreeIntent.routines:
        final props = routineProposals(st, logic.habitReached, now: now);
        if (props.isEmpty) {
          return [
            _freeHint(cs,
                'Toutes tes routines du jour sont tenues — rien à rattraper.'),
          ];
        }
        // Domaines non définis derrière ces routines : lien discret vers la
        // session de définition — sur place, sans quitter le guide.
        final toDefine = <String>{
          for (final p in props)
            if (p.undefinedDomain != null) p.undefinedDomain!
        };
        return [
          for (final p in props)
            _proposalRow(
              cs,
              p.routine.name,
              p.subtitle,
              Icons.play_arrow_rounded,
              () => _launchProposalBlock(
                  activityId: p.routine.id, title: p.routine.name),
              onLongPress: () => showPlanNextSheet(context,
                  logic: logic, routine: p.routine),
            ),
          _freeHint(cs, 'tap = lancer maintenant · appui long = planifier la prochaine exécution'),
          for (final name in toDefine)
            Center(
              child: TextButton.icon(
                onPressed: () => _startDomainSession(name),
                icon: const Icon(Icons.auto_awesome, size: 15),
                label: Text('Définir « $name » — 15 min',
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
          if (widget.onOpenRoutines != null)
            Center(
              child: TextButton(
                onPressed: widget.onOpenRoutines,
                child: const Text('Toutes mes routines',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ),
        ];

      case FreeIntent.rest:
        // « Me poser » peut aussi poser la fenêtre : le coach suit le flow.
        final next = (_schedule?.blocks ?? const <ScheduleBlock>[])
            .where((b) =>
                b.status == 'pending' &&
                !b.isPrep &&
                b.startTime.compareTo(
                        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}') >
                    0)
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        return [
          _freeHint(cs,
              'Se poser fait partie du système : la récup fait tenir le reste. Aucune culpabilité — le coach ne compte pas les pauses.'),
          if (next.isNotEmpty)
            _proposalRow(
              cs,
              'Prochain : ${next.first.title}',
              'à ${next.first.startTime.replaceFirst(':', ' h ')} — d\'ici là, c\'est ton temps',
              Icons.schedule,
              null,
            ),
          _proposalRow(
            cs,
            'Ne pas me relancer avant…',
            'je suis le flow : aucune relance, aucune dérive avant l\'heure dite',
            Icons.do_not_disturb_on_outlined,
            _declareUnavailable,
          ),
          if (now.hour >= 19 || now.hour < 5)
            _proposalRow(
              cs,
              'Clore la journée — check-in',
              '2 min, puis la soirée est à toi',
              Icons.nightlight_round,
              widget.onOpenDayReview,
            ),
        ];

      case FreeIntent.sleep:
        final preps = (_schedule?.blocks ?? const <ScheduleBlock>[])
            .where((b) => b.isPrep && b.status == 'pending')
            .toList();
        return [
          if (preps.isNotEmpty)
            _proposalRow(
              cs,
              'Préparer demain — ${preps.length} prep${preps.length > 1 ? 's' : ''} à cocher',
              'demain matin, les affaires seront prêtes depuis hier',
              Icons.checklist_rounded,
              widget.onOpenDayReview,
            ),
          _proposalRow(
            cs,
            'Clore la journée — check-in',
            '2 min : le constat, le pourquoi, demain',
            Icons.nightlight_round,
            widget.onOpenDayReview,
          ),
          _freeHint(cs,
              'Puis bonne nuit — la carte coach se tait jusqu\'à 5 h.'),
        ];

      case FreeIntent.plan:
        final evening = now.hour >= 20 || now.hour < 5;
        return [
          if (!evening)
            _proposalRow(
              cs,
              'Planifier le reste de la journée',
              '2 min — proposition pré-remplie, à ajuster',
              Icons.edit_calendar_outlined,
              _openPlanToday,
            ),
          _proposalRow(
            cs,
            evening ? 'Poser demain — 2 min' : 'Poser demain',
            'demain se gagne ce soir',
            Icons.event_outlined,
            () {
              final t = DateTime.now().add(const Duration(days: 1));
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlanDayScreen(
                    logic: logic,
                    targetDate: _ymd(t),
                    rattrapage: false),
              ));
            },
          ),
        ];
    }
  }

  Widget _proposalRow(ColorScheme cs, String title, String? subtitle,
      IconData icon, VoidCallback? onTap,
      {VoidCallback? onLongPress}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: onTap != null
                  ? cs.primary.withOpacity(.35)
                  : cs.onSurface.withOpacity(.12)),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: onTap != null
                    ? cs.primary
                    : cs.onSurface.withOpacity(.4)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: cs.onSurface.withOpacity(.55))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _freeHint(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                height: 1.4,
                fontStyle: FontStyle.italic,
                color: cs.onSurface.withOpacity(.5))),
      );

  /// « Ne pas me relancer avant… » (guide « Me poser ») — même fait tracké
  /// que le report : le coach suit le flow jusqu'à l'heure choisie.
  /// Déclare une fenêtre d'indispo (« pas dispo avant X ») — ou la lève si
  /// l'utilisateur répond « Oui — on enchaîne ». Utilisé par le guide (repos)
  /// et par le bouton pause discret de l'en-tête (toujours disponible).
  Future<void> _declareUnavailable({String reason = 'repos'}) async {
    final until = await showAvailabilitySheet(context,
        pause: true,
        paused: _schedule?.unavailableAt(DateTime.now()) == true);
    if (until == null || !mounted) return;
    if (until == kAvailableNow) {
      // « Oui — on enchaîne » : lève une éventuelle fenêtre en cours.
      final wasPaused = _schedule?.unavailableAt(DateTime.now()) == true;
      await _sync.setUnavailability(_schedDate, null);
      if (mounted && wasPaused) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Je suis dispo — le coach reprend.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    await _sync.setUnavailability(_schedDate, until, reason: reason);
    if (mounted) {
      setState(() => _freeIntent = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Noté — je suis le flow, aucune relance d\'ici là.'),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// En-tête commun : le bouton pause est TOUJOURS disponible, même quand des
  /// blocs restent — « je ne peux rien faire avant telle heure » ne doit pas
  /// dépendre de l'état du programme (le guide n'apparaît que tout vide).
  Widget _header(ColorScheme cs, DateTime now) {
    final until = _schedule?.unavailableAt(now) == true
        ? _schedule!.unavailableUntil
        : null;
    // Libellé explicite (constaté sur build : l'icône seule ressemble à un
    // « moins ») — et l'état visible : « Pause · 18 h » quand elle court.
    String label = 'Pause';
    if (until != null) {
      final sameDay = until.day == now.day && until.month == now.month;
      label = sameDay
          ? 'Pause · ${until.minute == 0 ? '${until.hour} h' : '${until.hour} h ${until.minute.toString().padLeft(2, '0')}'}'
          : 'Pause · demain';
    }
    return Row(
      children: [
        Text('Maintenant',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: cs.onSurface)),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _declareUnavailable(reason: 'pas_le_moment'),
          icon: Icon(
            until != null
                ? Icons.notifications_paused
                : Icons.notifications_paused_outlined,
            size: 18,
          ),
          label: Text(label,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          style: TextButton.styleFrom(
            foregroundColor:
                until != null ? cs.primary : cs.onSurface.withOpacity(.45),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999)),
          ),
        ),
      ],
    );
  }

  // ── Mode soirée réversible (23c) ─────────────────────────────────────────────

  /// « Terminer l'après-midi » : bascule système EXPLICITE — les blocs ne sont
  /// jamais touchés, snackbar « Annuler » à l'activation, bandeau permanent.
  Future<void> _endAfternoon() async {
    await _sync.setDayMode(_schedDate, 'evening');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Mode soirée activé'),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => _sync.setDayMode(_schedDate, 'normal'),
        ),
      ));
    }
  }

  /// Bandeau d'état permanent en tête de Maintenant tant que le mode est actif.
  Widget _eveningModeBanner(ColorScheme cs) {
    final at = _schedule?.dayModeActivatedAt;
    final atStr = at != null
        ? ' — activé à ${at.hour}:${at.minute.toString().padLeft(2, '0')}'
        : '';
    final amber = cs.brightness == Brightness.dark
        ? const Color(0xFFFFB74D)
        : const Color(0xFFEF8B1F);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withOpacity(.5)),
        color: amber.withOpacity(.08),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('Mode soirée$atStr',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: amber)),
          ),
          // « Revenir » restaure le programme tel quel (rien n'a été modifié).
          TextButton(
            onPressed: () => _sync.setDayMode(_schedDate, 'normal'),
            style: TextButton.styleFrom(
              foregroundColor: amber,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('↩ Revenir à l\'après-midi',
                style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  // ── Carte coach « Maintenant » ───────────────────────────────────────────────

  /// Défi ORION prêt pour la carte : l'activité-temps la plus en retard sur sa
  /// cible du jour (même sélection que le bouton doré), avec les faits réels.
  ChallengeProposal? _challengeProposal(DateTime now) {
    final a = logic.challengeActivity(exclude: _scheduledChallengeIds);
    if (a == null) return null;
    final todayStart = DateTime(now.year, now.month, now.day);
    final done = logic.totalForRangeByActivity(a.id, todayStart, now).inMinutes;
    return ChallengeProposal(
        activity: a,
        minutes: logic.challengeDurationFor(a),
        doneMin: done,
        targetMin: a.goalMin,
        streak: st.challengeStreak);
  }

  Widget _coachCard(DateTime now) {
    final moment = computeCoachMoment(
        now, st, _schedule, _yesterday, st.sessions,
        advancedTo: _coachAdvancedTo,
        unplannedDismissed: _unplannedDismissed,
        artifacts: _artifacts,
        weeklyReport: _weeklyReport,
        sessionSkipCount: _sessionSkipCount,
        nextSessionLabel: _nextSessionLabel,
        nudgeDismissed: _nudgeDismissed,
        microTargetDismissed: _microTargetDismissed,
        driftSnoozed:
            _driftSnoozeUntil != null && now.isBefore(_driftSnoozeUntil!),
        challenge: _challengeProposal(now),
        // Gantt invisible : micro-action du projet le plus urgent — la carte
        // ne la sort que quand rien d'autre n'a la priorité.
        ganttAction: ganttMicroAction(logic.currentProjects,
            blocks: _schedule?.blocks ?? const [],
            excludeTaskIds: _scheduledStepTaskIds));
    final isNudge = moment.type == CoachMomentType.defineNudge;
    return CoachMomentCard(
      moment: moment,
      onNameDomains: _openNamingSheet,
      onNameTonight: _poseNamingTonight,
      onStartSession: _startDomainSession,
      onPoseSessions: _poseRemainingSessions,
      onEndAfternoon: _endAfternoon,
      // « Je suis dispo » — efface la fenêtre, le coach reprend normalement.
      onAvailableNow: () => _sync.setUnavailability(_schedDate, null),
      // « Planifions — [routine] » : pose la prochaine exécution à date/heure
      // choisies (après la fenêtre d'indispo par défaut).
      onPlanNext: (block) {
        Activity? routine;
        for (final a in st.activities) {
          if (a.id == block.activityId) routine = a;
        }
        if (routine != null) {
          showPlanNextSheet(context,
              logic: logic,
              routine: routine,
              notBefore: _schedule?.unavailableUntil);
        }
      },
      // « Garder [créneau] » du nudge / « Plus tard » (micro-cible) /
      // « À la volée » : silence pour la journée seulement.
      onDismiss: isNudge
          ? () => setState(() => _nudgeDismissed = true)
          : moment.type == CoachMomentType.microTarget
              ? () => setState(() => _microTargetDismissed = true)
              : () => setState(() => _unplannedDismissed = true),
      onLaunch: widget.onLaunchScheduledBlock,
      // Renégocier (12a) : trois issues générées depuis le réel — réduire /
      // déplacer / reporter. Remplace l'ouverture de fiche v1. Au retour, la
      // carte dérive respire 45 min : on vient de trier, pas de rafale
      // « dérive suivante » (le check-in rattrape ce qui doit l'être).
      onRenegotiate: (block) async {
        await showRenegotiateSheet(
          context,
          logic: logic,
          block: block,
          date: _schedDate,
          onLaunch: widget.onLaunchScheduledBlock,
        );
        if (mounted) {
          setState(() => _driftSnoozeUntil =
              DateTime.now().add(const Duration(minutes: 45)));
        }
      },
      onOpenDayReview: widget.onOpenDayReview,
      onAdvance: (target) => setState(() => _coachAdvancedTo = target),
      onPlanDay: _openPlanToday,
      onMealEaten: (id) => _logMeal(id, eaten: true),
      onMealShift: (id) => _logMeal(id, eaten: false),
      onOpenWeeklyReport: _weeklyReport == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WeeklyReportScreen(
                    logic: logic, report: _weeklyReport!),
              )),
      // Défi ORION : le tap de carte ouvre TOUJOURS le dialog de confirmation
      // (constaté sur build : lancer le minuteur directement surprend) — le
      // chrono ne démarre qu'après « Je relève 🔥 », comme avec le bouton doré.
      onChallengeAccept: (block) {
        final a =
            st.activities.where((x) => x.id == block.activityId).firstOrNull;
        if (a != null) _confirmChallenge(a, block.durationMin);
      },
      onChallengeSchedule: (block) async {
        final a =
            st.activities.where((x) => x.id == block.activityId).firstOrNull;
        if (a == null) return;
        await widget.onChallengeSchedule?.call(a, block.durationMin);
        final ids = await _sync.fetchScheduledChallengeActivityIds();
        if (mounted) setState(() => _scheduledChallengeIds = ids);
      },
      // GTD minimaliste (Gantt) : définir la prochaine étape / la programmer.
      onDefineSteps: _defineGanttSteps,
      onScheduleStep: _scheduleGanttStep,
      // Réglage micro-cible : la réponse devient un FAIT (targetSource).
      onKeepMicroTarget: (block) {
        final a =
            st.activities.where((x) => x.id == block.activityId).firstOrNull;
        if (a == null) return;
        a.targetSource = 'user'; // déclencheur assumé — épinglé, plus touché
        logic.onChange();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '📌 Micro-cible gardée : ${a.name} — ${a.goalMin} min/j (épinglée, ORION n\'y touchera plus)'),
          duration: const Duration(seconds: 3),
        ));
      },
      onCalibrateTarget: (block) {
        final a =
            st.activities.where((x) => x.id == block.activityId).firstOrNull;
        if (a == null) return;
        final avg30 =
            (logic.timeSliding(a.id, 30).doneMin / 30.0).round();
        final old = a.goalMin;
        a.goalMin = ((avg30 / 5).round() * 5).clamp(5, 720);
        a.targetSource = 'orion'; // la calibration continue de la suivre
        a.lastTuneAt = DateTime.now();
        logic.onChange();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '📏 ${a.name} : cible $old → ${a.goalMin} min/j (mesuré ~$avg30 min/j sur 30 j)'),
          duration: const Duration(seconds: 3),
        ));
      },
      // ✓ d'une routine sans minuteur : coche directe (même garde anti-double
      // incrément que le ✓ des blocs) — pas de chrono pour boire un verre d'eau.
      onCheckRoutine: (block) async {
        final a =
            st.activities.where((x) => x.id == block.activityId).firstOrNull;
        if (a == null || !a.isHabit) return;
        final day = DateTime.now();
        final tgt = logic.activeHabitTarget(a);
        if (tgt > 0 && logic.habitValueOn(a.id, day) >= tgt) return;
        // Routine COMPTÉE (palier > 1 : pompes, tractions, verres d'eau…) →
        // le ✓ ne vaut pas +1 aveugle : compteur du jour + boutons − / +.
        if (tgt > 1) {
          final total = await showHabitCountSheet(context,
              logic: logic, activity: a);
          if (total == null || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('💪 ${a.name} : $total/$tgt aujourd\'hui'),
            duration: const Duration(seconds: 2),
          ));
          return;
        }
        logic.incHabit(a.id, 1, DateTime(day.year, day.month, day.day));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Routine validée : ${a.name}'),
          duration: const Duration(seconds: 2),
        ));
      },
    );
  }

  // ── GTD minimaliste sur la micro-action Gantt ────────────────────────────
  //
  // La tâche proposée n'a pas d'étape définie : le user pose la (les)
  // prochaine(s) petite(s) action(s) — FAIT structurel écrit sur le projet
  // (TaskAction), pas un souvenir de carte. Puis il choisit : faire la
  // première tout de suite, la PROGRAMMER au moment où il sait qu'il sera
  // dispo pour elle, ou plus tard (la carte la reproposera).

  Future<void> _defineGanttSteps(ScheduleBlock block) async {
    final project = logic.currentProjects
        .where((p) => p.id == block.projectId)
        .firstOrNull;
    final task =
        project?.tasks.where((t) => t.id == block.taskId).firstOrNull;
    if (project == null || task == null) return;

    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Prochaine étape'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('« ${task.title} » — quelle est la prochaine petite action '
                'concrète ? (une par ligne si tu en vois plusieurs)'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  hintText: 'ex : Appeler le fournisseur pour le devis'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctrl.text),
              child: const Text('Poser')),
        ],
      ),
    );
    final steps = (raw ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (steps.isEmpty) return;
    for (final t in steps) {
      task.actions.add(TaskAction(title: t));
    }
    await _sync.saveProjectTasks(project.id, project.tasks);
    if (!mounted) return;
    setState(() {}); // la carte reprend avec l'étape définie

    // L'étape existe — maintenant, QUAND ? (GTD : l'action + son moment.)
    final first = task.actions.firstWhere((a) => !a.done);
    final next = ScheduleBlock(
        startTime: block.startTime,
        durationMin: 15,
        title: first.title,
        category: 'project',
        projectId: project.id,
        taskId: task.id,
        actionId: first.id);
    final cs = Theme.of(context).colorScheme;
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Étape posée'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('« ${first.title} »',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Tu la fais maintenant, ou tu choisis le moment où tu seras '
                'dispo pour elle ?',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withOpacity(.6))),
          ],
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Plus tard')),
          TextButton(
              onPressed: () => Navigator.pop(d, 'schedule'),
              child: const Text('Programmer 📅')),
          FilledButton(
              onPressed: () => Navigator.pop(d, 'now'),
              child: const Text('Maintenant — 15 min')),
        ],
      ),
    );
    if (choice == 'now') widget.onLaunchScheduledBlock?.call(next);
    if (choice == 'schedule') await _scheduleGanttStep(next);
  }

  /// « Programmer l'étape » : le user SAIT quand il sera dispo pour cette
  /// action en particulier (chez lui, à la salle, en déplacement…) — il pose
  /// le jour et l'heure, le bloc daté porte projet/tâche/étape (chrono ciblé).
  Future<void> _scheduleGanttStep(ScheduleBlock block) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var day = today;
    var time = TimeOfDay(hour: (now.hour + 1).clamp(0, 23), minute: 0);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final cs = Theme.of(ctx).colorScheme;
        final tomorrow = today.add(const Duration(days: 1));
        final afterTomorrow = today.add(const Duration(days: 2));
        String dayLabel() {
          if (day == today) return 'aujourd\'hui';
          if (day == tomorrow) return 'demain';
          if (day == afterTomorrow) return 'après-demain';
          return 'le ${day.day}/${day.month}';
        }

        final at =
            DateTime(day.year, day.month, day.day, time.hour, time.minute);
        final past = !at.isAfter(now);
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 20,
              right: 20,
              top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Programmer l\'étape',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('📋 ${block.title} — 15 min',
                  style: TextStyle(color: cs.onSurface.withOpacity(.7))),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                    label: const Text('Aujourd\'hui'),
                    selected: day == today,
                    onSelected: (_) => setSheet(() => day = today)),
                ChoiceChip(
                    label: const Text('Demain'),
                    selected: day == tomorrow,
                    onSelected: (_) => setSheet(() => day = tomorrow)),
                ChoiceChip(
                    label: const Text('Après-demain'),
                    selected: day == afterTomorrow,
                    onSelected: (_) => setSheet(() => day = afterTomorrow)),
                ActionChip(
                  avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: const Text('Autre…'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                        context: ctx,
                        initialDate: day,
                        firstDate: today,
                        lastDate: today.add(const Duration(days: 365)));
                    if (picked != null) {
                      setSheet(() => day =
                          DateTime(picked.year, picked.month, picked.day));
                    }
                  },
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.schedule_rounded,
                    size: 18, color: cs.onSurface.withOpacity(.6)),
                const SizedBox(width: 8),
                Text('${dayLabel()} à ${time.format(ctx)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final t =
                        await showTimePicker(context: ctx, initialTime: time);
                    if (t != null) setSheet(() => time = t);
                  },
                  child: const Text('Modifier l\'heure'),
                ),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: past ? null : () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.event_available_rounded),
                  label:
                      Text(past ? 'Choisis un horaire futur' : 'Programmer'),
                ),
              ),
            ],
          ),
        );
      }),
    );
    if (confirmed != true || !mounted) return;

    final ymd =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final hhmm =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    await _sync.addScheduleBlock(
        ymd,
        ScheduleBlock(
            startTime: hhmm,
            durationMin: block.durationMin,
            title: block.title,
            category: 'project',
            projectId: block.projectId,
            taskId: block.taskId,
            actionId: block.actionId));
    final ids = await _sync.fetchScheduledTaskIds();
    if (!mounted) return;
    setState(() => _scheduledStepTaskIds = ids);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '📋 Étape programmée ${day == today ? 'aujourd\'hui' : day == today.add(const Duration(days: 1)) ? 'demain' : 'le ${day.day}/${day.month}'} à $hhmm'),
      duration: const Duration(seconds: 3),
    ));
  }

  /// Confirmation du défi (même dialog que le bouton doré) : le nom et la
  /// durée en grand, trois issues explicites — rien ne se lance sans ça.
  Future<void> _confirmChallenge(Activity a, int minutes) async {
    final cs = Theme.of(context).colorScheme;
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.smart_toy_rounded,
            color: Color(0xFFB8860B), size: 32),
        title: const Text('ORION te défie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$minutes min de « ${a.name} »',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                '« Je relève » lance le chrono et le minuteur-alarme tout de suite. « Programmer » le pose pour plus tard.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withOpacity(.6))),
          ],
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, null),
              child: const Text('Pas maintenant')),
          TextButton(
              onPressed: () => Navigator.pop(d, 'schedule'),
              child: const Text('Programmer 📅')),
          FilledButton(
              onPressed: () => Navigator.pop(d, 'now'),
              child: const Text('Je relève 🔥')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'now') widget.onChallengeAccept?.call(a, minutes);
    if (choice == 'schedule') {
      await widget.onChallengeSchedule?.call(a, minutes);
      // Le défi vient (peut-être) d'être posé : la liste d'exclusion se
      // recharge pour que la carte ne le repropose pas dans la foulée.
      final ids = await _sync.fetchScheduledChallengeActivityIds();
      if (mounted) setState(() => _scheduledChallengeIds = ids);
    }
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
  /// Horizon actionnable : un bloc qui démarre à plus de 90 min n'est pas
  /// « le moment » — il ne mérite pas la grande carte avec Lancer (constaté
  /// sur build : « Hygiène du soir, 21 h » proposée en plein 13 h 46). Il
  /// reste visible en hint discret (_laterBlock) et lançable explicitement.
  static const int _kActionHorizonMin = 90;

  ScheduleBlock? _focusBlock(DateTime now) {
    for (final b in _pendingBlocks) {
      final start = _blockStart(b, now);
      final end = start.add(Duration(minutes: b.durationMin));
      final current = !now.isBefore(start) && now.isBefore(end);
      final upcoming = now.isBefore(start) &&
          start.difference(now).inMinutes <= _kActionHorizonMin;
      if (current || upcoming) return b;
    }
    return null;
  }

  /// Premier bloc pending AU-DELÀ de l'horizon — l'affaire de plus tard.
  ScheduleBlock? _laterBlock(DateTime now) {
    for (final b in _pendingBlocks) {
      final start = _blockStart(b, now);
      if (now.isBefore(start) &&
          start.difference(now).inMinutes > _kActionHorizonMin) {
        return b;
      }
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
    Activity? matched = b.activityId != null
        ? st.activities.where((a) => a.id == b.activityId).firstOrNull
        : null;
    // Bloc sans lien : routine du même nom validée quand même (match unique).
    matched ??= routineForBlockTitle(b.title, st.activities);
    final id = matched?.id;
    if (id != null && !_routineHit.contains(b.id)) {
      final act = matched;
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
    // Pause active : aucune relance — ni carte coach ni carte focus. Le guide
    // « que souhaites-tu faire ? » prend la place (pull, pas push) ; l'état et
    // la sortie de pause vivent sur le bouton ⏸ de l'en-tête.
    if (_schedule?.unavailableAt(now) == true) {
      return _buildEmpty(context, cs, now);
    }
    final focus = _focusBlock(now);
    return focus != null
        ? _buildFocusIdle(context, cs, focus, now)
        : _buildEmpty(context, cs, now);
  }

  // ── « Je suis dans ce contexte » : actions GTD réalisables ici ─────────────
  // Chips des contextes ayant ≥1 action en attente ; sélection → liste des
  // actions du contexte (projets actifs + actions propres), chrono ciblé au ▶.

  List<({TaskAction action, String source, String? chronoActivityId, String? taskId, String? projectId})>
      _actionsForContext(String ctx) {
    final out = <({TaskAction action, String source, String? chronoActivityId, String? taskId, String? projectId})>[];
    for (final p in widget.logic.currentProjects) {
      if (p.status != 'active' || p.paused) continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        for (final a in t.actions) {
          if (a.done || !a.allContexts.contains(ctx)) continue;
          out.add((
            action: a,
            source: p.title,
            // Lien propre de l'action, sinon hérité du projet.
            chronoActivityId: a.linkedActivityId ?? p.linkedActivityId,
            taskId: t.id,
            projectId: p.id,
          ));
        }
      }
    }
    for (final act in widget.state.activeActivities) {
      for (final a in act.ownActions) {
        if (a.done || !a.allContexts.contains(ctx)) continue;
        out.add((
          action: a,
          source: act.name,
          chronoActivityId: act.id,
          taskId: null,
          projectId: null,
        ));
      }
    }
    return out;
  }

  Set<String> _contextsWithActions() {
    final s = <String>{};
    for (final p in widget.logic.currentProjects) {
      if (p.status != 'active' || p.paused) continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        for (final a in t.actions) {
          if (!a.done) s.addAll(a.allContexts);
        }
      }
    }
    for (final act in widget.state.activeActivities) {
      for (final a in act.ownActions) {
        if (!a.done) s.addAll(a.allContexts);
      }
    }
    return s;
  }

  Widget _contextSection(ColorScheme cs) {
    final contexts = _contextsWithActions().toList()..sort();
    if (contexts.isEmpty) return const SizedBox.shrink();
    // Multi : on peut être @maison ET @ordinateur — union des actions,
    // dédupliquée par id.
    final active =
        widget.state.nowContexts.where(contexts.contains).toSet();
    final seen = <String>{};
    final items = [
      for (final c in active.toList()..sort())
        for (final it in _actionsForContext(c))
          if (seen.add(it.action.id)) it,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.place_outlined,
                size: 14, color: cs.onSurface.withOpacity(.45)),
            const SizedBox(width: 6),
            Text('JE SUIS…',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                    color: cs.onSurface.withOpacity(.45))),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in contexts)
                ChoiceChip(
                  selected: active.contains(c),
                  onSelected: (_) {
                    active.contains(c)
                        ? widget.state.nowContexts.remove(c)
                        : widget.state.nowContexts.add(c);
                    widget.logic.onChange();
                    setState(() {});
                  },
                  showCheckmark: false,
                  label: Text(c),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active.contains(c)
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: active.contains(c)
                        ? cs.primary
                        : cs.onSurface.withOpacity(.65),
                  ),
                  selectedColor: cs.primary.withOpacity(.14),
                  backgroundColor: cs.surfaceVariant.withOpacity(.35),
                  side: BorderSide(
                      color: active.contains(c)
                          ? cs.primary.withOpacity(.5)
                          : Colors.transparent),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
            ],
          ),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (items.isEmpty)
              Text('Aucune action en attente dans ce contexte.',
                  style: TextStyle(
                      fontSize: 12.5, color: cs.onSurface.withOpacity(.5)))
            else
              for (final it in items.take(6))
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.action.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                          Text(it.source,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withOpacity(.5))),
                        ],
                      ),
                    ),
                    if (it.chronoActivityId != null)
                      IconButton(
                        tooltip: 'Lancer le chrono',
                        icon: Icon(Icons.play_circle_fill,
                            size: 26, color: cs.primary),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          widget.logic.start(it.chronoActivityId!,
                              taskId: it.taskId, actionId: it.action.id);
                          setState(() {});
                        },
                      ),
                  ]),
                ),
          ],
        ],
      ),
    );
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
            _header(cs, now),
            const SizedBox(height: 20),
            if (_schedule?.eveningMode == true) _eveningModeBanner(cs),
            _coachCard(now),
            _contextSection(cs),
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
            // 3ᵉ verbe : reporter (avec raison) / déplacer / réduire /
            // supprimer — le sheet du bloc (12a/23b), pas juste ▶ et ✓.
            const SizedBox(width: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface.withOpacity(.6),
                side: BorderSide(color: cs.onSurface.withOpacity(.25)),
                minimumSize: const Size(46, 46),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => showRenegotiateSheet(
                context,
                logic: logic,
                block: b,
                date: _schedDate,
                onLaunch: widget.onLaunchScheduledBlock,
              ),
              child: const Icon(Icons.more_horiz_rounded, size: 20),
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

  /// Hint discret du bloc au-delà de l'horizon (> 90 min) : visible, datable,
  /// lançable en avance d'un tap explicite (heure/durée = libres) — mais
  /// jamais présenté comme LE truc à faire maintenant.
  Widget _laterHint(ColorScheme cs, ScheduleBlock b) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withOpacity(.12)),
      ),
      child: Row(children: [
        Icon(Icons.schedule, size: 15, color: cs.onSurface.withOpacity(.4)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Plus tard · ${b.startTime} — ${b.title} (${fmtMin(b.durationMin)})',
            style: TextStyle(
                fontSize: 12.5, color: cs.onSurface.withOpacity(.55)),
          ),
        ),
        if (widget.onLaunchScheduledBlock != null &&
            (b.projectId != null || b.activityId != null))
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: cs.onSurface.withOpacity(.5),
            ),
            onPressed: () => widget.onLaunchScheduledBlock!(b),
            child: const Text('Lancer quand même',
                style: TextStyle(fontSize: 11.5)),
          ),
      ]),
    );
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
            _header(cs, now),
            const SizedBox(height: 20),
            if (_schedule?.eveningMode == true) _eveningModeBanner(cs),
            _coachCard(now),
            _contextSection(cs),
            // Bloc au-delà de l'horizon (ex : Hygiène du soir à 21 h vu à
            // 13 h 46) : l'affaire de PLUS TARD — hint discret, pas la grande
            // carte. Le moment présent revient au guide ci-dessous.
            if (_laterBlock(now) != null) _laterHint(cs, _laterBlock(now)!),
            const SizedBox(height: 8),
            // ── Guide du moment libre : intention → propositions réelles ──────
            ..._freeMomentSection(cs, now),
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

    final next = _focusBlock(now);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── CADRE HERO : l'activité qui tourne. Le reste de Maintenant
            // (carte ORION, contextes, bloc proposé) reste visible DESSOUS —
            // plus besoin d'arrêter le chrono pour voir les propositions,
            // ni de repasser par le widget d'app bar pour relancer.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              decoration: BoxDecoration(
                color: color.withOpacity(.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withOpacity(.35), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${domain?.name.toUpperCase() ?? ''} · ${running.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: cs.onSurface.withOpacity(.6)),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('EN COURS',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .8,
                                color: color)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Minuteur (anneau de décompte) OU chrono (temps écoulé)
                  if (isCountdown) ...[
                    Center(
                      child: _CountdownRing(
                        remaining: remaining,
                        totalSec:
                            widget.countdownTotalSec ?? remaining.inSeconds,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.timer_off_outlined, size: 18),
                        label: const Text('Arrêter le minuteur'),
                        onPressed: widget.onStopCountdown,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(200, 44),
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
                          fontSize: 48,
                          fontWeight: FontWeight.w200,
                          letterSpacing: 2,
                          color: cs.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.stop_rounded, size: 20),
                        label: const Text('Arrêter'),
                        onPressed: widget.onStopTimer,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.error,
                          foregroundColor: cs.onError,
                          minimumSize: const Size(160, 44),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
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

            // ── DÉROULÉ : toutes les étapes de la session en cours, unifiées —
            // sous-actions de la tâche + actions propres de l'activité +
            // routines LIÉES (Pompes, Tractions… avec leur compteur) + leurs
            // checklists. Le chrono parent trace le temps ; les étapes
            // s'égrènent librement, la première non faite est mise en avant.
            ..._derouleSection(cs, color, running),

            // ── POSSIBLE MAINTENANT : todo dynamique = actions des projets
            // liés à l'activité en cours (lien propre ou hérité du projet),
            // filtrées par les contextes actifs. Le chrono continue de
            // tourner sur l'activité pendant qu'on égrène.
            ..._possibleNowSection(cs, color, running),

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

            // ── Le reste de Maintenant, VISIBLE pendant le chrono : carte
            // ORION + bloc proposé — on consulte / on enchaîne sans arrêter.
            const SizedBox(height: 26),
            _coachCard(now),
            if (next != null) _focusCard(context, cs, next, now),
            _overdueHint(cs, now),
          ],
        ),
      ),
    );
  }

  // ── « Possible maintenant » : todo dynamique de l'activité en cours ─────────
  // Actions de projets actifs dont l'activité EFFECTIVE (lien propre de
  // l'action, sinon lien du projet) est celle du chrono, filtrées par les
  // contextes actifs (une action sans contexte reste visible). Les sous-
  // actions de la tâche focus sont exclues (déjà dans le déroulé).

  List<({TaskAction action, Project project, ProjectTask task})>
      _possibleNowItems(Activity running) {
    final active = widget.state.nowContexts.toSet();
    final focusTaskId = widget.focusTask?.id;
    final out = <({TaskAction action, Project project, ProjectTask task})>[];
    for (final p in widget.logic.currentProjects) {
      if (p.status != 'active' || p.paused) continue;
      for (final t in p.tasks) {
        if (t.isMilestone || t.status == 'done' || t.status == 'skipped') {
          continue;
        }
        if (t.id == focusTaskId) continue;
        for (final a in t.actions) {
          if (a.done) continue;
          final effective = a.linkedActivityId ?? p.linkedActivityId;
          if (effective != running.id) continue;
          if (active.isNotEmpty &&
              a.allContexts.isNotEmpty &&
              !a.allContexts.any(active.contains)) {
            continue;
          }
          out.add((action: a, project: p, task: t));
        }
      }
    }
    return out;
  }

  List<Widget> _possibleNowSection(
      ColorScheme cs, Color color, Activity running) {
    final items = _possibleNowItems(running);
    if (items.isEmpty) return const [];
    final active = widget.state.nowContexts.toList()..sort();
    return [
      const SizedBox(height: 26),
      Row(children: [
        Icon(Icons.checklist_rtl,
            size: 14, color: cs.onSurface.withOpacity(.45)),
        const SizedBox(width: 6),
        Text('POSSIBLE MAINTENANT',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
                color: cs.onSurface.withOpacity(.45))),
        if (active.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(active.join(' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary.withOpacity(.7))),
          ),
        ],
      ]),
      const SizedBox(height: 8),
      for (final it in items.take(8))
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Checkbox(
              value: false,
              shape: const CircleBorder(),
              onChanged: (_) async {
                it.action.done = true;
                it.action.doneAt = DateTime.now();
                await _sync.saveProjectTasks(
                    it.project.id, it.project.tasks);
                logic.onChange();
                if (mounted) setState(() {});
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.action.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Row(children: [
                      Flexible(
                        child: Text(it.project.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(.5))),
                      ),
                      if (it.action.allContexts.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                              (it.action.allContexts.toList()..sort())
                                  .join(' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary.withOpacity(.75))),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ]),
        ),
      if (items.length > 8)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('+ ${items.length - 8} autres dans l\'onglet Actions',
              style: TextStyle(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurface.withOpacity(.45))),
        ),
    ];
  }

  // ── Déroulé de la session en cours (player v1) ───────────────────────────────
  //
  // Une étape = { titre, sous-titre (compteur), fait, action au tap, lignes
  // imbriquées (checklist d'une routine) }. Sources dans l'ordre : sous-actions
  // de la tâche focus → actions propres de l'activité → routines liées à
  // l'activité en cours. 0 nouveau modèle : le déroulé est DÉRIVÉ de l'existant
  // (les templates réutilisables viendront s'y brancher).
  /// Étape-routine du déroulé (compteur − / + si comptée, coche gardée sinon,
  /// checklist imbriquée) — partagée entre le déroulé dérivé et les templates.
  ({
    String title,
    String? sub,
    bool done,
    Future<void> Function() onTap,
    List<Widget> nested,
  }) _routineStep(ColorScheme cs, Color color, Activity r, DateTime now) {
    final tgt = logic.activeHabitTarget(r);
    final val = logic.habitValueOn(r.id, now);
    final rDone = tgt > 0 ? val >= tgt : val > 0;
    final counted = tgt > 1;
    final items = logic.checklistForHabit(r.id);
    final doneSet =
        items.isEmpty ? const <int>{} : logic.checklistDoneSet(r.id, now);
    return (
      title: r.name,
      sub: counted ? '$val/$tgt aujourd\'hui' : null,
      done: rDone,
      onTap: () async {
        if (counted) {
          await showHabitCountSheet(context, logic: logic, activity: r);
          if (mounted) setState(() {});
          return;
        }
        if (rDone) return; // pas de double coche
        logic.incHabit(r.id, 1, DateTime(now.year, now.month, now.day));
        setState(() {});
      },
      nested: [
        for (var i = 0; i < items.length; i++)
          _checkRow(cs, color, items[i], doneSet.contains(i), () {
            logic.toggleChecklistItem(r.id, DateTime.now(), i);
            setState(() {});
          }),
      ],
    );
  }

  List<Widget> _derouleSection(ColorScheme cs, Color color, Activity running) {
    final task = widget.focusTask;
    final project = widget.focusProject;
    final now = DateTime.now();

    final steps = <({
      String title,
      String? sub,
      bool done,
      Future<void> Function() onTap,
      List<Widget> nested,
    })>[];

    // ── Template ACTIF (séance lancée depuis la fiche activité) : il prend le
    // contrôle total du déroulé — c'est SON ordre, celui que le user a posé.
    // Étapes simples : état éphémère de CETTE session (un déroulé se rejoue) ;
    // étapes-routines : l'état vit chez la routine (compteur, palier, streak).
    final tpl = logic.activeSessionTemplate;
    if (tpl != null && tpl.activityId == running.id) {
      for (final stp in tpl.steps) {
        if (stp.kind == 'routine') {
          Activity? r;
          for (final x in st.activities) {
            if (x.id == stp.routineId) { r = x; break; }
          }
          if (r != null && r.isHabit && !r.deleted) {
            steps.add(_routineStep(cs, color, r, now));
            continue;
          }
        }
        final sDone = logic.sessionStepDone.contains(stp.id);
        steps.add((
          title: stp.title,
          sub: null,
          done: sDone,
          onTap: () async {
            logic.toggleSessionStep(stp.id);
            setState(() {});
          },
          nested: [
            for (var i = 0; i < stp.checklist.length; i++)
              _checkRow(cs, color, stp.checklist[i],
                  logic.sessionStepDone.contains('${stp.id}:$i'), () {
                logic.toggleSessionStep('${stp.id}:$i');
                setState(() {});
              }),
          ],
        ));
      }
      return _renderDeroule(cs, color, steps,
          label: 'DÉROULÉ · ${tpl.title.toUpperCase()}');
    }

    if (task != null && project != null) {
      for (final a in task.actions) {
        steps.add((
          title: a.title,
          sub: null,
          done: a.done,
          onTap: () => _toggleAction(a, !a.done),
          nested: const <Widget>[],
        ));
      }
    }
    for (final a in logic.ownActionsOf(running.id)) {
      steps.add((
        title: a.title,
        sub: null,
        done: a.done,
        onTap: () async {
          logic.toggleOwnAction(running.id, a.id, !a.done);
          setState(() {});
        },
        nested: const <Widget>[],
      ));
    }
    // Routines liées à l'activité en cours : étapes à part entière — « 10
    // pompes puis 5 tractions », pendant que le temps reste sur Musculation.
    final linked = st.activities
        .where((a) =>
            a.isHabit &&
            !a.deleted &&
            (a.linkedActivityId ?? '') == running.id)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    for (final r in linked) {
      steps.add(_routineStep(cs, color, r, now));
    }

    return _renderDeroule(cs, color, steps, label: 'DÉROULÉ');
  }

  List<Widget> _renderDeroule(
    ColorScheme cs,
    Color color,
    List<
            ({
              String title,
              String? sub,
              bool done,
              Future<void> Function() onTap,
              List<Widget> nested,
            })>
        steps, {
    required String label,
  }) {
    if (steps.isEmpty) return const [];
    final doneCount = steps.where((s) => s.done).length;
    final currentIdx = steps.indexWhere((s) => !s.done);

    return [
      const SizedBox(height: 28),
      Row(children: [
        Expanded(child: _sectionLabel(cs, label)),
        Text('$doneCount/${steps.length}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: cs.onSurface.withOpacity(.45))),
      ]),
      const SizedBox(height: 8),
      for (var i = 0; i < steps.length; i++) ...[
        _stepTile(cs, color, steps[i], current: i == currentIdx),
        // Checklist imbriquée : visible tant que l'étape n'est pas faite.
        if (!steps[i].done && steps[i].nested.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 26, bottom: 4),
            child: Column(children: steps[i].nested),
          ),
      ],
    ];
  }

  Widget _stepTile(
    ColorScheme cs,
    Color color,
    ({
      String title,
      String? sub,
      bool done,
      Future<void> Function() onTap,
      List<Widget> nested,
    }) step, {
    required bool current,
  }) =>
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: step.onTap,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: current ? color.withOpacity(.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: current
                    ? color.withOpacity(.5)
                    : cs.onSurface.withOpacity(.10),
                width: current ? 1.4 : 1),
          ),
          child: Row(children: [
            Icon(
              step.done
                  ? Icons.check_circle_rounded
                  : current
                      ? Icons.play_circle_outline_rounded
                      : Icons.circle_outlined,
              size: 20,
              color: step.done || current
                  ? color
                  : cs.onSurface.withOpacity(.35),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: current ? FontWeight.w700 : FontWeight.w600,
                        decoration:
                            step.done ? TextDecoration.lineThrough : null,
                        color: cs.onSurface.withOpacity(step.done ? .45 : .95),
                      )),
                  if (step.sub != null)
                    Text(step.sub!,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
          ]),
        ),
      );

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
