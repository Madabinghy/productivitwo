import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/web/help_sheet.dart';
import 'package:productivitwo_v1/web/assistant_engine.dart';
import 'package:productivitwo_v1/web/assistant_widget.dart';
import 'package:productivitwo_v1/web/coach_console_screen.dart';
import 'package:productivitwo_v1/web/views/actions_view.dart';
import 'package:productivitwo_v1/web/coaching_screen.dart';
import 'package:productivitwo_v1/widgets/coach_space_sheet.dart';
import 'package:productivitwo_v1/web/views/today_view.dart';
import 'package:productivitwo_v1/web/views/week_view.dart';
import 'package:productivitwo_v1/web/views/projects_view.dart';
import 'package:productivitwo_v1/web/views/project_plan_view.dart';
import 'package:productivitwo_v1/web/vision_dialog.dart';
import 'package:productivitwo_v1/web/views/library_view.dart';
import 'package:productivitwo_v1/web/views/archives_view.dart';
import 'package:productivitwo_v1/web/views/documents_view.dart';
import 'package:productivitwo_v1/web/views/orion_view.dart';
import 'package:productivitwo_v1/web/tokens_panel.dart';
import 'package:productivitwo_v1/web/web_shell.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/web/ui_scale.dart';
import 'package:productivitwo_v1/web/desktop_dialog.dart';
import 'package:productivitwo_v1/web/assistant_history_sheet.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/storage.dart';
import 'package:productivitwo_v1/widgets/onboarding_screen.dart';

class WebHomeScreen extends StatefulWidget {
  final bool isDemo;
  const WebHomeScreen({super.key, this.isDemo = false});

  @override
  State<WebHomeScreen> createState() => _WebHomeScreenState();
}

class _WebHomeScreenState extends State<WebHomeScreen> {
  final _sync = FirestoreSync();
  List<Project> _projects = [];
  List<Domain> _domains = [];
  List<StrategicObjective> _objectives = [];
  List<Activity> _activities = [];
  List<Session> _recentSessions = [];
  List<HabitHit> _recentHits = [];
  Map<String, List<Map<String, dynamic>>> _documentsByProject = {};
  bool _loading = true;
  // Refonte web 2026-09 : barre d'onglets en haut (`WebTab`), Aujourd'hui
  // est la vue d'arrivée.
  WebTab _tab = WebTab.today;
  // Gantt hébergé DANS le shell : recouvre la vue courante, la barre reste
  // utilisable — null = aucun projet ouvert.
  ({Project project, String? taskId})? _shellGantt;
  // Bibliothèque filtrée sur un projet (« Tout voir » de la fiche projet).
  String? _libraryProjectId;

  void _openLibraryFor(String projectId) => setState(() {
        _libraryProjectId = projectId;
        _tab = WebTab.library;
        _shellGantt = null;
      });

  void _openProjectInShell(Project project, {String? taskId}) =>
      setState(() => _shellGantt = (project: project, taskId: taskId));
  List<AssistantMessageData> _assistantMessages = [];
  StreamSubscription<List<Project>>? _projectsSub;
  // Console coaching : bouton 🎓 visible seulement si le compte est coach
  // (sonde coachApi — 403 pour tout le monde d'autre).
  bool _isCoach = false;
  // Onboarding auto-ouvert UNE fois par session quand le compte est vide.
  bool _onboardingPrompted = false;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Sonde coach accrochée à l'ÉTAT D'AUTH (pas one-shot) : au chargement,
    // Firebase restaure la session APRÈS initState — une sonde immédiate
    // répondait « non connecté » et le bouton 🎓 n'apparaissait jamais.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      if (u == null) {
        if (mounted) setState(() => _isCoach = false);
        return;
      }
      probeCoachAccess().then((ok) {
        if (mounted) setState(() => _isCoach = ok);
      });
    });
    // Sync temps réel des projets : les tâches/actions validées (ici, sur un
    // autre appareil, ou par Claude/MCP) se reflètent sans recharger la page.
    _projectsSub = _sync.streamProjects().listen((projects) {
      if (mounted) setState(() => _projects = projects);
    });
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _sync.fetchProjects(),
        _sync.fetchStrategicObjectives(),
        _sync.fetchApiTokens(),
        _sync.fetchDomains(),
        _sync.fetchDocuments(),
        _sync.fetchActivities(),
        _sync.fetchRecentSessions(7),
        _sync.fetchRecentHabitHits(7),
      ]);
      if (!mounted) return;
      final allDocs = results[4] as List<Map<String, dynamic>>;
      // Group documents by projectId (hors playbooks : ils ont leur vue dédiée
      // sous le Gantt — pas dans l'ancien viewer HTML « Voir le document »).
      final byProject = <String, List<Map<String, dynamic>>>{};
      for (final doc in allDocs) {
        if ((doc['category'] as String?) == 'playbook') continue;
        final pid = doc['projectId'] as String?;
        if (pid != null && pid.isNotEmpty) {
          byProject.putIfAbsent(pid, () => []).add(doc);
        }
      }
      final loadedProjects = results[0] as List<Project>;
      final loadedDomains = results[3] as List<Domain>;

      setState(() {
        _projects = loadedProjects;
        _domains = loadedDomains;
        _objectives = (results[1] as List<StrategicObjective>)
            .where((o) => o.status == 'active')
            .toList();
        _activities = results[5] as List<Activity>;
        _recentSessions = results[6] as List<Session>;
        _recentHits = results[7] as List<HabitHit>;
        _documentsByProject = byProject;
        _loading = false;
      });

      // Onboarding déterministe (catalogue domaines/activités/routines) :
      // un compte VIDE — créé directement sur le web, ex. un coaché invité —
      // démarre ici sans avoir besoin de l'app mobile. Même écran que le
      // mobile ; la persistance passe par un AppLogic dédié (save local web
      // + pushAll Firestore), et le mobile récupérera tout à la synchro.
      if (!_onboardingPrompted &&
          loadedDomains.isEmpty &&
          (results[5] as List<Activity>).isEmpty) {
        _onboardingPrompted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final store = FileStore();
          final st = AppState(
            domains: [],
            activities: [],
            sessions: [],
            habitProgress: [],
          );
          late final AppLogic onboardingLogic;
          onboardingLogic = AppLogic(st, () {
            store.save(onboardingLogic.state);
            _sync.pushAll(onboardingLogic.state);
          })
            ..sync = _sync;
          Navigator.of(context).push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => OnboardingScreen(
              logic: onboardingLogic,
              sync: _sync,
              onDone: () {
                Navigator.of(context).pop();
                _load();
              },
            ),
          ));
        });
      }

      // Évaluation de l'assistant après chargement
      final messages = await AssistantEngine.evaluate(
        projects: loadedProjects,
        domains: loadedDomains,
      );
      if (mounted && messages.isNotEmpty) {
        assistantActionHandler = _handleAssistantAction;
        assistantMessagesNotifier.value = messages;
        setState(() => _assistantMessages = messages);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _showTokensPanel(BuildContext context) {
    // Dialog desktop centrée (lot 1b) — plus de bottom sheet sur le web.
    showDesktopDialog(context, builder: (_) => TokensPanel(sync: _sync));
  }

  void _go(WebTab tab) => setState(() {
        _tab = tab;
        // Naviguer ferme aussi le Gantt hébergé — sinon l'overlay masquait
        // la vue choisie.
        _shellGantt = null;
      });

  // Agent ORION : plus un onglet, une route plein écran derrière le menu ⋯.
  void _openOrion() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: kBBg,
          appBar: AppBar(
            backgroundColor: kBBar,
            surfaceTintColor: Colors.transparent,
            title: const Text('Agent ORION'),
          ),
          body: OrionView(sync: _sync),
        ),
      ));

  void _onMenu(WebMenuItem item) {
    switch (item) {
      case WebMenuItem.orion:
        _openOrion();
      case WebMenuItem.messages:
        AssistantHistorySheet.show(context);
      case WebMenuItem.coachConsole:
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CoachConsoleScreen()));
      case WebMenuItem.vision:
        showVisionDialog(context);
      case WebMenuItem.claude:
        _showTokensPanel(context);
      case WebMenuItem.uiScale:
        showUiScaleDialog(context);
      case WebMenuItem.help:
        showHelpSheet(context);
      case WebMenuItem.logout:
        FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {}

    return Scaffold(
      backgroundColor: kBBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebTopBar(
            selected: _tab,
            onSelect: _go,
            sync: _sync,
            signedIn: user != null,
            userName: user?.displayName ?? user?.email ?? '',
            isCoach: _isCoach,
            isDemo: widget.isDemo,
            hasAssistantMessages: _assistantMessages.isNotEmpty,
            onMyCoach: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CoachSpaceScreen())),
            onMenu: _onMenu,
          ),
          if (widget.isDemo) const DemoBanner(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _viewsStack(),
          ),
        ],
      ),
    );
  }

  // Vues du shell — un enfant par `WebTab`, dans l'ordre de l'enum.
  // IndexedStack garde l'état (scroll, filtres) de chaque vue.
  Widget _viewsStack() {
    final activeProjects =
        _projects.where((p) => p.status != 'archived').toList();
    return Stack(
      children: [
        IndexedStack(
          index: _tab.index,
          children: [
            TodayView(
              projects: activeProjects,
              domains: _domains,
              activities: _activities,
              sync: _sync,
              objectives: _objectives,
              documentsByProject: _documentsByProject,
              onOpenProject: _openProjectInShell,
              onOpenProjects: () => _go(WebTab.projects),
              onOpenWeek: () => _go(WebTab.week),
            ),
            WeekView(
              projects: _projects,
              domains: _domains,
              sync: _sync,
              onOpenProject: _openProjectInShell,
            ),
            ProjectsView(
              projects: _projects,
              domains: _domains,
              activities: _activities,
              objectives: _objectives,
              recentSessions: _recentSessions,
              recentHits: _recentHits,
              sync: _sync,
              onRefresh: _load,
              onOpenProject: _openProjectInShell,
            ),
            ActionsView(
              projects: _projects,
              domains: _domains,
              activities: _activities,
              sync: _sync,
              onRefresh: _load,
              onOpenProject: _openProjectInShell,
            ),
            LibraryView(
              key: ValueKey('library/${_libraryProjectId ?? ''}'),
              documents: DocumentsView(
                projects: _projects,
                domains: _domains,
                documentsByProject: _documentsByProject,
                sync: _sync,
                onChanged: _load,
                projectId: _libraryProjectId,
                onClearFilter: () => setState(() => _libraryProjectId = null),
              ),
              organisation: ArchivesView(sync: _sync),
            ),
          ],
        ),
        // Fiche projet DANS le shell (Plan d'action · Gantt · Document) :
        // recouvre la vue active, la barre reste utilisable.
        if (_shellGantt != null)
          Positioned.fill(
            child: ProjectPlanView(
              key:
                  ValueKey('${_shellGantt!.project.id}/${_shellGantt!.taskId}'),
              project: _shellGantt!.project,
              targetTaskId: _shellGantt!.taskId,
              domains: _domains,
              activities: _activities,
              recentSessions: _recentSessions,
              documents:
                  _documentsByProject[_shellGantt!.project.id] ?? const [],
              sync: _sync,
              onClose: () {
                setState(() => _shellGantt = null);
                _load();
              },
              onChanged: _load,
              onOpenLibrary: _openLibraryFor,
            ),
          ),
      ],
    );
  }

  void _handleAssistantAction(AssistantActionData action) {
    switch (action.type) {
      case 'open_day_plan':
        _go(WebTab.today);
      case 'open_project':
        final projectId = action.payload?['projectId'] as String?;
        if (projectId == null) return;
        final p = _projects.where((p) => p.id == projectId).firstOrNull;
        if (p == null) return;
        _openProjectInShell(p);
      case 'open_gantt_task':
        final projectId = action.payload?['projectId'] as String?;
        final taskId = action.payload?['taskId'] as String?;
        if (projectId == null) return;
        final p = _projects.where((p) => p.id == projectId).firstOrNull;
        if (p == null) return;
        _openProjectInShell(p, taskId: taskId);
      case 'open_activity':
        _go(WebTab.today);
    }
  }
}
