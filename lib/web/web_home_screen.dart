import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/web/help_sheet.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
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
import 'package:productivitwo_v1/web/document_viewer_dialog.dart';
import 'package:productivitwo_v1/web/vision_dialog.dart';
import 'package:productivitwo_v1/web/views/library_view.dart';
import 'package:productivitwo_v1/web/web_shell.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
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
      final loadedDomains  = results[3] as List<Domain>;

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
          })..sync = _sync;
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
    showDesktopDialog(context, builder: (_) => _TokensPanel(sync: _sync));
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
          body: _OrionView(sync: _sync),
        ),
      ));

  void _onMenu(WebMenuItem item) {
    switch (item) {
      case WebMenuItem.orion:
        _openOrion();
      case WebMenuItem.messages:
        AssistantHistorySheet.show(context);
      case WebMenuItem.coachConsole:
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const CoachConsoleScreen()));
      case WebMenuItem.vision:
        showVisionDialog(context);
      case WebMenuItem.claude:
        _showTokensPanel(context);
      case WebMenuItem.help:
        showHelpSheet(context);
      case WebMenuItem.logout:
        FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    User? user;
    try { user = FirebaseAuth.instance.currentUser; } catch (_) {}

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
            onMyCoach: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CoachSpaceScreen())),
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
              documents: _DocumentsView(
                projects: _projects,
                domains: _domains,
                documentsByProject: _documentsByProject,
                sync: _sync,
                onChanged: _load,
                projectId: _libraryProjectId,
                onClearFilter: () => setState(() => _libraryProjectId = null),
              ),
              organisation: _ArchivesView(sync: _sync),
            ),
          ],
        ),
        // Fiche projet DANS le shell (Plan d'action · Gantt · Document) :
        // recouvre la vue active, la barre reste utilisable.
        if (_shellGantt != null)
          Positioned.fill(
            child: ProjectPlanView(
              key: ValueKey(
                  '${_shellGantt!.project.id}/${_shellGantt!.taskId}'),
              project: _shellGantt!.project,
              targetTaskId: _shellGantt!.taskId,
              domains: _domains,
              activities: _activities,
              recentSessions: _recentSessions,
              documents: _documentsByProject[_shellGantt!.project.id] ?? const [],
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
        final taskId   = action.payload?['taskId']   as String?;
        if (projectId == null) return;
        final p = _projects.where((p) => p.id == projectId).firstOrNull;
        if (p == null) return;
        _openProjectInShell(p, taskId: taskId);
      case 'open_activity':
        _go(WebTab.today);
    }
  }
}

// ── ORION Brief — Stratège quotidien ──────────────────────────────────────────

class _OrionBriefSection extends StatefulWidget {
  const _OrionBriefSection();
  @override
  State<_OrionBriefSection> createState() => _OrionBriefSectionState();
}

class _OrionBriefSectionState extends State<_OrionBriefSection> {
  static const _api = 'https://orionbrief-dzos75b65q-uc.a.run.app';
  static const _gold = Color(0xFFe8c94a);

  bool _loading = true;
  String _focus = '';
  Map<String, dynamic>? _brief;
  bool _editingFocus = false;
  bool _focusNotSet = false;
  String? _error;
  final _focusCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _focusCtrl.dispose();
    super.dispose();
  }

  Future<String?> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    final idToken = await _getIdToken();
    if (idToken == null) {
      setState(() { _loading = false; _error = 'Non connecté'; });
      return;
    }
    try {
      // Get focus
      final fRes = await http.post(
        Uri.parse(_api),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getFocus'}),
      );
      final focus = (jsonDecode(fRes.body) as Map)['focus'] as String? ?? '';
      _focus = focus;
      _focusCtrl.text = focus;

      if (focus.trim().isEmpty) {
        setState(() { _loading = false; _focusNotSet = true; _editingFocus = true; });
        return;
      }

      // Get brief
      final bRes = await http.post(
        Uri.parse(_api),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getBrief'}),
      );
      if (bRes.statusCode == 200) {
        _brief = jsonDecode(bRes.body) as Map<String, dynamic>;
        setState(() { _loading = false; _focusNotSet = false; });
      } else if (bRes.statusCode == 412) {
        setState(() { _loading = false; _focusNotSet = true; });
      } else {
        setState(() { _loading = false; _error = 'Erreur ${bRes.statusCode}'; });
      }
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _saveFocus() async {
    final newFocus = _focusCtrl.text.trim();
    if (newFocus.isEmpty) return;
    final idToken = await _getIdToken();
    if (idToken == null) return;
    setState(() => _loading = true);
    try {
      await http.post(
        Uri.parse(_api),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'setFocus', 'focus': newFocus}),
      );
      _focus = newFocus;
      _editingFocus = false;
      // Force régénération du brief avec le nouveau focus
      await _loadAll();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendFeedback(String value) async {
    final brief = _brief;
    if (brief == null) return;
    final idToken = await _getIdToken();
    if (idToken == null) return;
    final date = brief['date'] as String?;
    if (date == null) return;
    try {
      await http.post(
        Uri.parse(_api),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'setFeedback', 'date': date, 'feedback': value}),
      );
      setState(() { _brief = {...brief, 'feedback': value}; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _SidebarCard(
      title: 'ORION · Stratège',
      titleColor: _gold,
      icon: Icons.auto_awesome_outlined,
      cs: cs,
      child: _buildContent(cs),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.onSurface.withOpacity(.3))),
          const SizedBox(width: 8),
          Text('Chargement…', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.4))),
        ]),
      );
    }
    if (_error != null) {
      return Text(_error!, style: TextStyle(fontSize: 12, color: cs.error));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Focus
        _buildFocusBlock(cs),
        const SizedBox(height: 14),
        // Brief
        if (_focusNotSet)
          Text(
            'Définis ton focus au-dessus pour activer ton brief quotidien.',
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.45), height: 1.5, fontStyle: FontStyle.italic),
          )
        else if (_brief != null)
          _buildBriefBlock(cs),
      ],
    );
  }

  Widget _buildFocusBlock(ColorScheme cs) {
    if (_editingFocus) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TON FOCUS DU MOMENT',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: cs.onSurface.withOpacity(.4))),
          const SizedBox(height: 6),
          TextField(
            controller: _focusCtrl,
            maxLines: 3,
            minLines: 2,
            maxLength: 280,
            decoration: InputDecoration(
              hintText: 'Ex : "Je lance ma formation avant fin juin. Tout converge vers ça."',
              hintStyle: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.3)),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(
              onPressed: _saveFocus,
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Enregistrer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            if (_focus.isNotEmpty) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() { _editingFocus = false; _focusCtrl.text = _focus; }),
                child: Text('Annuler', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
              ),
            ],
          ]),
        ],
      );
    }

    return InkWell(
      onTap: () => setState(() => _editingFocus = true),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('TON FOCUS',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: cs.onSurface.withOpacity(.4))),
              const Spacer(),
              Icon(Icons.edit_outlined, size: 11, color: cs.onSurface.withOpacity(.3)),
            ]),
            const SizedBox(height: 6),
            Text(_focus,
                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.85), height: 1.5, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildBriefBlock(ColorScheme cs) {
    final b = _brief!;
    final priorityAction = b['priorityAction'] as String? ?? '';
    final risk = b['risk'] as String?;
    final question = b['question'] as String?;
    final feedback = b['feedback'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BRIEF DU JOUR',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: _gold)),
        const SizedBox(height: 10),
        _briefRow(cs, '→', 'Action prioritaire', priorityAction, _gold),
        if (risk != null && risk.isNotEmpty) ...[
          const SizedBox(height: 10),
          _briefRow(cs, '⚠', 'Risque', risk, const Color(0xFFE07B39)),
        ],
        if (question != null && question.isNotEmpty) ...[
          const SizedBox(height: 10),
          _briefRow(cs, '?', 'Question', question, const Color(0xFF7AB8E5)),
        ],
        const SizedBox(height: 14),
        // Feedback + historique
        Row(children: [
          if (feedback == null) ...[
            _feedbackBtn(cs, '✓ Utile', () => _sendFeedback('useful')),
            const SizedBox(width: 8),
            _feedbackBtn(cs, '✗ Passe', () => _sendFeedback('skip')),
          ] else
            Text(
              feedback == 'useful' ? '✓ Marqué utile' : '✗ Brief passé',
              style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.4)),
            ),
          const Spacer(),
          InkWell(
            onTap: _openHistory,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.history, size: 12, color: cs.onSurface.withOpacity(.5)),
                const SizedBox(width: 4),
                Text('Historique',
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.5), fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ]),
      ],
    );
  }

  Future<void> _openHistory() async {
    final idToken = await _getIdToken();
    if (idToken == null) return;
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
          child: _BriefHistoryView(idToken: idToken, api: _api),
        ),
      ),
    );
  }

  Widget _briefRow(ColorScheme cs, String icon, String label, String text, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withOpacity(.05),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color.withOpacity(.5), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icon, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(label.toUpperCase(),
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1, color: color)),
          ]),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.85), height: 1.45)),
        ],
      ),
    );
  }

  Widget _feedbackBtn(ColorScheme cs, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.65), fontWeight: FontWeight.w500)),
      ),
    );
  }
}

// ── ORION Brief — Historique ─────────────────────────────────────────────────

class _BriefHistoryView extends StatefulWidget {
  final String idToken;
  final String api;
  const _BriefHistoryView({required this.idToken, required this.api});
  @override
  State<_BriefHistoryView> createState() => _BriefHistoryViewState();
}

class _BriefHistoryViewState extends State<_BriefHistoryView> {
  bool _loading = true;
  List<Map<String, dynamic>> _briefs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.post(
        Uri.parse(widget.api),
        headers: {'Authorization': 'Bearer ${widget.idToken}', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'history', 'limit': 30}),
      );
      if (res.statusCode != 200) {
        setState(() { _loading = false; _error = 'Erreur ${res.statusCode}'; });
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _loading = false;
        _briefs = (data['briefs'] as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  String _fmtDate(String yyyymmdd) {
    try {
      final d = DateTime.parse(yyyymmdd);
      const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
      const w = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
      return '${w[d.weekday - 1]} ${d.day} ${m[d.month - 1]}';
    } catch (_) { return yyyymmdd; }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const gold = Color(0xFFe8c94a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
          child: Row(children: [
            Icon(Icons.auto_awesome_outlined, size: 16, color: gold),
            const SizedBox(width: 8),
            Text('Historique ORION', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Fermer',
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(.3)),
        Flexible(
          child: _loading
              ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              : _error != null
                  ? Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: TextStyle(color: cs.error)))
                  : _briefs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Text('Aucun brief sauvegardé pour le moment.',
                                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.4), fontStyle: FontStyle.italic)),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          itemCount: _briefs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 16),
                          itemBuilder: (_, i) => _briefCard(cs, gold, _briefs[i]),
                        ),
        ),
      ],
    );
  }

  Widget _briefCard(ColorScheme cs, Color gold, Map<String, dynamic> b) {
    final date = b['date'] as String? ?? '';
    final focus = b['focus'] as String?;
    final priorityAction = b['priorityAction'] as String? ?? '';
    final risk = b['risk'] as String?;
    final question = b['question'] as String?;
    final feedback = b['feedback'] as String?;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_fmtDate(date),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: gold, letterSpacing: 0.3)),
            const Spacer(),
            if (feedback != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (feedback == 'useful' ? Colors.green : cs.onSurface).withOpacity(.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  feedback == 'useful' ? '✓ utile' : '✗ passé',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: feedback == 'useful' ? Colors.green.shade700 : cs.onSurface.withOpacity(.4),
                  ),
                ),
              ),
          ]),
          if (focus != null && focus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Focus : "$focus"',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cs.onSurface.withOpacity(.45))),
          ],
          const SizedBox(height: 10),
          _briefLine(cs, gold, '→', 'Action', priorityAction),
          if (risk != null && risk.isNotEmpty) ...[
            const SizedBox(height: 6),
            _briefLine(cs, const Color(0xFFE07B39), '⚠', 'Risque', risk),
          ],
          if (question != null && question.isNotEmpty) ...[
            const SizedBox(height: 6),
            _briefLine(cs, const Color(0xFF7AB8E5), '?', 'Question', question),
          ],
        ],
      ),
    );
  }

  Widget _briefLine(ColorScheme cs, Color color, String icon, String label, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          alignment: Alignment.center,
          child: Text(icon, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.85), height: 1.5)),
        ),
      ],
    );
  }
}

// ── Peintre ligne pointillée ──────────────────────────────────────────────────

// ── Sidebar widgets ───────────────────────────────────────────────────────────

class _SidebarCard extends StatelessWidget {
  final String title;
  final Color? titleColor;
  final IconData icon;
  final ColorScheme cs;
  final Widget child;

  const _SidebarCard({
    required this.title,
    required this.icon,
    required this.cs,
    required this.child,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = titleColor ?? cs.onSurface.withOpacity(0.65);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ── Panel Connecter Claude / Tokens ──────────────────────────────────────────

class _TokensPanel extends StatefulWidget {
  final FirestoreSync sync;
  const _TokensPanel({required this.sync});

  @override
  State<_TokensPanel> createState() => _TokensPanelState();
}

class _TokensPanelState extends State<_TokensPanel>
    with SingleTickerProviderStateMixin {
  List<ApiToken> _tokens = [];
  bool _loading = true;
  String? _newTokenValue;
  late TabController _tabs;

  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tokens = await widget.sync.fetchApiTokens();
    if (!mounted) return;
    setState(() {
      _tokens = tokens;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final label = await _askLabel();
    if (label == null) return;
    final token = await widget.sync.createApiToken(label);
    if (!mounted) return;
    setState(() => _newTokenValue = token.rawToken ?? '');
    await _load();
  }

  Future<String?> _askLabel() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau token'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom',
            hintText: 'ex: Claude MCP',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  void _copy(String text, String msg) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _mcpUrl(String token) =>
      'https://mcphandler-dzos75b65q-uc.a.run.app/mcp/$_uid/$token';

  String _mcpConfig(String token) => '''{
  "mcpServers": {
    "productivitwo": {
      "url": "${_mcpUrl(token)}"
    }
  }
}''';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeTokens = _tokens.where((t) => t.active).toList();

    return Column(
        children: [
          // Titre
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Connecter Claude',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Connexion Claude Desktop'),
              Tab(text: 'Mes tokens'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                // ── Onglet 1 : Connexion ──────────────────────────────────
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          // Étapes
                          _Step(
                            number: '1',
                            title: 'Génère un token',
                            child: activeTokens.isEmpty
                                ? FilledButton.icon(
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Créer un token Claude'),
                                    onPressed: () async {
                                      await _create();
                                      _tabs.animateTo(0);
                                    },
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Token actif : ${activeTokens.first.label}',
                                          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7))),
                                      const SizedBox(height: 6),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.add, size: 14),
                                        label: const Text('Créer un autre token'),
                                        onPressed: _create,
                                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 16),
                          _Step(
                            number: '2',
                            title: 'Copie ton URL de connexion',
                            child: activeTokens.isEmpty
                                ? Text('Crée d\'abord un token (étape 1)',
                                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.45),
                                        fontStyle: FontStyle.italic))
                                : Builder(builder: (context) {
                                    final displayToken = _newTokenValue ?? activeTokens.first.rawToken;
                                    if (displayToken == null) {
                                      return Text(
                                        'Crée un nouveau token (étape 1) pour voir ton URL complète.',
                                        style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.55), fontStyle: FontStyle.italic),
                                      );
                                    }
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        // URL principale (simple)
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: cs.primaryContainer.withOpacity(0.4),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: cs.primary.withOpacity(0.25)),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: SelectableText(
                                                  _mcpUrl(displayToken),
                                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.copy_outlined, size: 16),
                                                onPressed: () => _copy(_mcpUrl(displayToken), 'URL copiée'),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        // Option A : Claude.ai web
                                        _ConnectOption(
                                          icon: Icons.language_outlined,
                                          title: 'Claude.ai web',
                                          description: 'Paramètres → Personnaliser → Connecteurs → colle l\'URL',
                                        ),
                                        const SizedBox(height: 8),
                                        // Option B : Claude Desktop
                                        _ConnectOption(
                                          icon: Icons.desktop_mac_outlined,
                                          title: 'Claude Desktop',
                                          description: 'Paramètres → Développeur → Modifier la config → colle le JSON ci-dessous',
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: cs.surfaceContainerHighest.withOpacity(0.6),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: SelectableText(
                                                  _mcpConfig(displayToken),
                                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.copy_outlined, size: 14),
                                                onPressed: () => _copy(_mcpConfig(displayToken), 'Config copiée'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                          ),
                          const SizedBox(height: 16),
                          _Step(
                            number: '3',
                            title: 'Parle à Claude',
                            child: Text(
                              'Dis à Claude : "Crée un Gantt pour [description de ton projet]" '
                              'et il le poussera directement dans Productivitwo.',
                              style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.65), height: 1.5),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Note token visible
                          if (_newTokenValue != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 14, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Token créé (visible une seule fois)',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
                                        SelectableText(_newTokenValue!,
                                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy_outlined, size: 14),
                                    onPressed: () => _copy(_newTokenValue!, 'Token copié'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                // ── Onglet 2 : Tokens ─────────────────────────────────────
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Tokens actifs',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withOpacity(0.6))),
                          ),
                          FilledButton.icon(
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('Nouveau'),
                            onPressed: _create,
                            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : activeTokens.isEmpty
                              ? Center(
                                  child: Text('Aucun token actif',
                                      style: TextStyle(color: cs.onSurface.withOpacity(0.4))))
                              : ListView.builder(
                                  itemCount: activeTokens.length,
                                  itemBuilder: (_, i) {
                                    final t = activeTokens[i];
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(Icons.key_outlined, size: 16, color: cs.primary),
                                      title: Text(t.label, style: const TextStyle(fontSize: 13)),
                                      subtitle: Text(
                                        t.lastUsedAt != null
                                            ? 'Utilisé le ${t.lastUsedAt!.day}/${t.lastUsedAt!.month}'
                                            : 'Jamais utilisé',
                                        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.4)),
                                      ),
                                      trailing: TextButton(
                                        child: Text('Révoquer', style: TextStyle(color: cs.error, fontSize: 12)),
                                        onPressed: () async {
                                          await widget.sync.revokeApiToken(t.id);
                                          _load();
                                        },
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
    );
  }
}

// ── Widget étape numérotée ────────────────────────────────────────────────────

class _ConnectOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _ConnectOption({required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.onSurface.withOpacity(0.5)),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.65), height: 1.4),
              children: [
                TextSpan(text: '$title — ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String title;
  final Widget child;
  const _Step({required this.number, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(number, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

// ── Vue Archives ─────────────────────────────────────────────────────────────

class _ArchivesView extends StatefulWidget {
  final FirestoreSync sync;
  const _ArchivesView({required this.sync});

  @override
  State<_ArchivesView> createState() => _ArchivesViewState();
}

class _ArchivesViewState extends State<_ArchivesView> {
  List<Domain> _domains = [];
  List<Activity> _activities = [];
  List<Project> _projects = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _search = '';
  // Filtre : 'all' | 'active' | 'archived'
  String _filter = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.sync.fetchAllDomains(),
        widget.sync.fetchActivities(),
        widget.sync.fetchProjects(),
      ]);
      if (!mounted) return;
      setState(() {
        _domains    = results[0] as List<Domain>;
        _activities = results[1] as List<Activity>;
        _projects   = results[2] as List<Project>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _archive(String col, String id) async {
    await widget.sync.archiveItem(col, id);
    _load();
  }

  Future<void> _restore(String col, String id) async {
    await widget.sync.restoreDeleted(col, id);
    _load();
  }

  Future<void> _confirmHardDelete(String col, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement ?'),
        content: const Text(
          'L\'élément sera masqué partout (app iOS + web).\n\n'
          'Note : si l\'élément existe encore localement sur iOS, '
          'il sera supprimé au prochain démarrage de l\'app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.sync.hardDelete(col, id);
      _load();
    }
  }

  Future<void> _editActivity(Activity activity) async {
    final nameCtrl = TextEditingController(text: activity.name);
    String? domainId = activity.domainId.isEmpty ? null : activity.domainId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(activity.isHabit ? 'Modifier la routine' : 'Modifier l\'activité'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nom',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Domaine', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    value: domainId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— Aucun domaine —')),
                      for (final d in ([..._domains.where((d) => !d.deleted)]
                          ..sort((a, b) => a.name.compareTo(b.name))))
                        DropdownMenuItem(value: d.id, child: Text(d.name)),
                    ],
                    onChanged: (v) => setLocal(() => domainId = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer'),
              ),
            ],
          );
        });
      },
    );

    if (confirmed == true) {
      activity.name = nameCtrl.text.trim();
      activity.domainId = domainId ?? '';
      await widget.sync.saveActivity(activity);
      _load();
    }
    nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());

    // ── Données avec filtres ─────────────────────────────────────────────────
    final q = _search.toLowerCase().trim();

    bool matchesSearch(String name) =>
        q.isEmpty || name.toLowerCase().contains(q);

    bool showActive(bool isArchived) =>
        _filter == 'all' || (_filter == 'active' && !isArchived) || (_filter == 'archived' && isArchived);

    final archivedProjects = _projects
        .where((p) => p.status == 'archived' && matchesSearch(p.title) && showActive(true))
        .toList()..sort((a, b) => a.title.compareTo(b.title));
    final activeProjects = _projects
        .where((p) => p.status != 'archived' && matchesSearch(p.title) && showActive(false))
        .toList()..sort((a, b) => a.title.compareTo(b.title));

    // Domaines actifs + archivés triés
    final activeDomains = _domains
        .where((d) => !d.deleted && showActive(false))
        .toList()..sort((a, b) => a.name.compareTo(b.name));
    final archivedDomains = _domains
        .where((d) => d.deleted && showActive(true))
        .toList()..sort((a, b) => a.name.compareTo(b.name));
    final allDomains = [...activeDomains, ...archivedDomains];

    // Activités filtrées et indexées par domaine
    final filteredActivities = _activities
        .where((a) => matchesSearch(a.name) && showActive(a.deleted))
        .toList();

    final activitiesByDomain = <String, List<Activity>>{};
    final activitiesWithoutDomain = <Activity>[];
    for (final a in filteredActivities) {
      if (a.domainId.isEmpty) {
        activitiesWithoutDomain.add(a);
      } else {
        activitiesByDomain.putIfAbsent(a.domainId, () => []).add(a);
      }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: cs.onSurface.withOpacity(0.45),
            ),
          ),
        );

    Widget domainHeader(Domain d) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: d.deleted ? cs.error.withOpacity(0.5) : cs.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              d.name.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: d.deleted ? cs.error.withOpacity(0.6) : cs.primary,
              ),
            ),
            if (d.deleted) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('archivé',
                    style: TextStyle(fontSize: 10, color: cs.error)),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.3))),
            IconButton(
              icon: Icon(d.deleted ? Icons.restore_outlined : Icons.archive_outlined,
                  size: 15, color: cs.onSurface.withOpacity(0.4)),
              tooltip: d.deleted ? 'Restaurer' : 'Archiver',
              visualDensity: VisualDensity.compact,
              onPressed: d.deleted
                  ? () => _restore('domains', d.id)
                  : () => _archive('domains', d.id),
            ),
          ]),
        );

    Widget actRow(Activity a) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _ArchiveItemRow(
        label: a.name,
        isArchived: a.deleted,
        onEdit: () => _editActivity(a),
        onArchive: () => _archive('activities', a.id),
        onRestore: () => _restore('activities', a.id),
        onDelete: () => _confirmHardDelete('activities', a.id),
        cs: cs,
      ),
    );

    Widget buildDomainSection(String? domainId) {
      final all = domainId == null
          ? activitiesWithoutDomain
          : (activitiesByDomain[domainId] ?? []);

      final timeActs = [...all.where((a) => !a.isHabit)]
        ..sort((x, y) => x.name.compareTo(y.name));
      final habitActs = [...all.where((a) => a.isHabit)]
        ..sort((x, y) => x.name.compareTo(y.name));

      if (timeActs.isEmpty && habitActs.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text('Aucun élément',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.35), fontStyle: FontStyle.italic)),
        );
      }

      Widget column(String label, IconData icon, List<Activity> items) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
              child: Row(
                children: [
                  Icon(icon, size: 12, color: cs.onSurface.withOpacity(0.35)),
                  const SizedBox(width: 5),
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      color: cs.onSurface.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('—', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.3))),
              )
            else
              for (final a in items) actRow(a),
          ],
        ),
      );

      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            column('Activités', Icons.timer_outlined, timeActs),
            const SizedBox(width: 16),
            column('Routines', Icons.repeat_rounded, habitActs),
          ],
        ),
      );
    }

    // ── Rendu (lot 5b) : recherche + filtres en tête, puis 2 colonnes ────────
    final searchField = TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Rechercher…',
                prefixIcon: const Icon(Icons.search_outlined, size: 18),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            );
    final filterChips = Row(mainAxisSize: MainAxisSize.min, children: [
      for (final (val, label) in [
        ('all',      'Tout'),
        ('active',   'Actifs'),
        ('archived', 'Archivés'),
      ]) ...[
        ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: _filter == val,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _filter = val),
        ),
        const SizedBox(width: 6),
      ],
    ]);

    final projectsSection = <Widget>[
            sectionLabel('PROJETS (${activeProjects.length + archivedProjects.length})'),
            if (activeProjects.isEmpty && archivedProjects.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('Aucun projet',
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.4), fontStyle: FontStyle.italic)),
              )
            else ...[
              if (activeProjects.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Actifs', style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
                ),
                for (final p in activeProjects) ...[
                  _ArchiveItemRow(
                    label: p.title,
                    isArchived: false,
                    subtitle: () {
                      final d = _domains.where((d) => d.id == p.domainId).firstOrNull;
                      return d != null ? d.name : null;
                    }(),
                    onArchive: () async {
                      await widget.sync.saveProject(p..status = 'archived');
                      _load();
                    },
                    onRestore: () async {},
                    cs: cs,
                  ),
                  const SizedBox(height: 6),
                ],
              ],
              if (archivedProjects.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Archivés', style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
                ),
                for (final p in archivedProjects) ...[
                  _ArchiveItemRow(
                    label: p.title,
                    isArchived: true,
                    subtitle: () {
                      final d = _domains.where((d) => d.id == p.domainId).firstOrNull;
                      return d != null ? d.name : null;
                    }(),
                    onArchive: () async {},
                    onRestore: () async {
                      await widget.sync.saveProject(p..status = 'active');
                      _load();
                    },
                    cs: cs,
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ],

    ];

    // Chaque domaine devient une CARTE (lot 5b) — lisible en colonne dense.
    Widget domainCard(Widget header, Widget body) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, body],
          ),
        );

    final domainsSection = <Widget>[
            sectionLabel('ACTIVITÉS & ROUTINES PAR DOMAINE'),

            for (final d in allDomains)
              domainCard(domainHeader(d), buildDomainSection(d.id)),

            // Sans domaine
            if (activitiesWithoutDomain.isNotEmpty)
              domainCard(
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
                  child: Row(children: [
                    Container(width: 8, height: 8,
                        decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.3), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text('SANS DOMAINE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8, color: cs.onSurface.withOpacity(0.4))),
                    const SizedBox(width: 8),
                    Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.3))),
                  ]),
                ),
                buildDomainSection(null),
              ),
    ];

    // ── Composition : ≥ 1100 px = PROJETS | DOMAINES côte à côte ─────────────
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1100;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 1360 : 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
            children: [
              if (wide)
                Row(children: [
                  sectionLabel('ORGANISATION'),
                  const SizedBox(width: 20),
                  Expanded(child: searchField),
                  const SizedBox(width: 14),
                  filterChips,
                ])
              else ...[
                sectionLabel('ORGANISATION'),
                searchField,
                const SizedBox(height: 8),
                filterChips,
              ],
              const SizedBox(height: 18),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: projectsSection),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      flex: 3,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: domainsSection),
                    ),
                  ],
                )
              else ...[
                ...projectsSection,
                const SizedBox(height: 20),
                ...domainsSection,
              ],
            ],
          ),
        ),
      );
    });
  }
}

// ── Vue Documents (lot 5) : accès direct aux documents par projet ────────────

class _DocumentsView extends StatelessWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final Map<String, List<Map<String, dynamic>>> documentsByProject;
  final FirestoreSync sync;
  final VoidCallback onChanged;
  // Filtre « Tout voir » de la fiche projet : n'affiche que ce projet.
  final String? projectId;
  final VoidCallback? onClearFilter;
  const _DocumentsView({
    required this.projects,
    required this.domains,
    required this.documentsByProject,
    required this.sync,
    required this.onChanged,
    this.projectId,
    this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Projets ayant au moins un document, dans l'ordre de la liste projets ;
    // documents orphelins (projet supprimé) regroupés à la fin.
    final known = <(Project, List<Map<String, dynamic>>)>[];
    final seen = <String>{};
    for (final p in projects) {
      if (projectId != null && p.id != projectId) continue;
      final docs = documentsByProject[p.id];
      if (docs != null && docs.isNotEmpty) {
        known.add((p, docs));
        seen.add(p.id);
      }
    }
    final orphans = <Map<String, dynamic>>[
      if (projectId == null)
        for (final e in documentsByProject.entries)
          if (!seen.contains(e.key)) ...e.value,
    ];
    final filteredProject =
        projectId == null ? null : projects.where((p) => p.id == projectId).firstOrNull;

    Widget docRow(String projectTitle, List<Map<String, dynamic>> group,
        Map<String, dynamic> doc) {
      final title = (doc['title'] as String?) ?? 'Document';
      final category = (doc['category'] as String?) ?? 'notes';
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => DocumentViewerDialog(
            projectTitle: projectTitle,
            documents: group,
            sync: sync,
            onDeleted: onChanged,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(Icons.description_outlined,
                size: 15, color: cs.onSurface.withOpacity(.45)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(category,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.primary.withOpacity(.8))),
            ),
          ]),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
          children: [
            Row(children: [
              Text(
                  filteredProject == null
                      ? 'DOCUMENTS'
                      : 'DOCUMENTS · ${filteredProject.title.toUpperCase()}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: cs.onSurface.withOpacity(0.45))),
              if (projectId != null && onClearFilter != null) ...[
                const SizedBox(width: 12),
                TextButton(
                    onPressed: onClearFilter,
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('Tous les projets')),
              ],
            ]),
            const SizedBox(height: 16),
            if (known.isEmpty && orphans.isEmpty)
              Text(
                  'Aucun document. Claude en crée via save_document '
                  '(programmes, briefs, livrables…) — ils apparaîtront ici, '
                  'groupés par projet.',
                  style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface.withOpacity(.45))),
            for (final (p, docs) in known) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: domainColor(p.domainId, domains) ?? cs.primary,
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface.withOpacity(.8))),
                  ),
                  Text('${docs.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface.withOpacity(.4))),
                ]),
              ),
              for (final doc in docs) docRow(p.title, docs, doc),
            ],
            if (orphans.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text('SANS PROJET',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: cs.onSurface.withOpacity(.4))),
              ),
              for (final doc in orphans) docRow('Sans projet', orphans, doc),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Vue ORION ─────────────────────────────────────────────────────────────────

class _OrionView extends StatefulWidget {
  final FirestoreSync sync;
  const _OrionView({required this.sync});

  @override
  State<_OrionView> createState() => _OrionViewState();
}

class _OrionViewState extends State<_OrionView> {
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _config;
  int _runCount = 0;
  bool _loading = true;
  bool _triggering = false;
  final _customCtrl = TextEditingController();

  static const _webhookUrl = 'https://orionsaveconfig-dzos75b65q-uc.a.run.app';

  // Actions pré-établies
  // taskId non vide = déterministe ($0), need non vide = LLM (coût API)
  static const _presets = [
    (icon: '📋', label: 'Analyser mes retards',       taskId: 'overdue_summary',  need: ''),
    (icon: '📅', label: 'Deadlines de la semaine',    taskId: 'weekly_deadlines', need: ''),
    (icon: '🗄', label: 'Archiver projets inactifs',  taskId: 'archive_inactive', need: ''),
    (icon: '📊', label: 'Rapport de progression',     taskId: 'progress_report',  need: ''),
    (icon: '🧹', label: 'Nettoyer messages expirés',  taskId: 'clean_expired',    need: ''),
    (icon: '🎯', label: 'Bilan de semaine',            taskId: '',  need: 'Fais un bilan de ma semaine et propose des ajustements pour la suivante'),
    (icon: '⚡', label: 'Optimiser plan du jour',     taskId: '',  need: 'Optimise mon plan du jour en fonction de mes priorités et deadlines'),
    (icon: '🔗', label: 'Lier objectifs et tâches',   taskId: '',  need: 'Lie mes objectifs GTD aux tâches Gantt correspondantes'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = widget.sync.uid;
      if (uid == null) return;

      final tokens = await widget.sync.fetchApiTokens();
      final token = tokens.where((t) => t.active).firstOrNull?.rawToken ?? '';

      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('users/$uid/orion_logs')
            .orderBy('cycleAt', descending: true)
            .limit(15)
            .get(),
        FirebaseFirestore.instance
            .collection('users/$uid/assistant_messages')
            .orderBy('targetDate', descending: true)
            .limit(30)
            .get(),
        FirebaseFirestore.instance
            .collection('users/$uid/orion_config')
            .doc('main')
            .get(),
        // Compteur via HTTP (orion_runs est hors users/{uid}, règles Firestore restrictives)
        if (token.isNotEmpty)
          http.get(Uri.parse('https://orionruncount-dzos75b65q-uc.a.run.app?uid=$uid&token=$token'))
        else
          Future.value(null),
      ]);

      final logsSnap = results[0] as QuerySnapshot;
      final msgsSnap = results[1] as QuerySnapshot;
      final configSnap = results[2] as DocumentSnapshot;
      final countResp = results[3];

      int runCount = 0;
      if (countResp is http.Response && countResp.statusCode == 200) {
        final data = jsonDecode(countResp.body) as Map<String, dynamic>;
        runCount = (data['count'] as int?) ?? 0;
      }

      if (mounted) {
        setState(() {
          _logs = logsSnap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
          _messages = msgsSnap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
          _config = configSnap.exists ? configSnap.data() as Map<String, dynamic> : null;
          _runCount = runCount;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _triggerWithPreset({required String taskId, required String need}) async {
    final uid = widget.sync.uid;
    final tokens = await widget.sync.fetchApiTokens();
    final token = tokens.where((t) => t.active).firstOrNull?.rawToken;
    if (uid == null || token == null) return;

    final isDeterministic = taskId.isNotEmpty;
    setState(() => _triggering = true);
    try {
      final body = isDeterministic
          ? {'uid': uid, 'token': token, 'taskId': taskId}
          : {'uid': uid, 'token': token, 'userNeeds': need};
      final url = isDeterministic
          ? 'https://orionwebhook-dzos75b65q-uc.a.run.app'
          : _webhookUrl;
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (resp.statusCode == 200 && mounted) {
        final label = isDeterministic ? taskId : need.substring(0, need.length.clamp(0, 40));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isDeterministic ? 'Tâche ORION exécutée : $label' : 'ORION activé (LLM) : $label…'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        _load();
      }
    } catch (_) {}
    if (mounted) setState(() => _triggering = false);
  }

  Future<void> _triggerNow() async {
    final uid = widget.sync.uid;
    final tokens = await widget.sync.fetchApiTokens();
    final token = tokens.where((t) => t.active).firstOrNull?.rawToken;
    if (uid == null || token == null) return;

    setState(() => _triggering = true);
    try {
      final resp = await http.post(
        Uri.parse('https://orionwebhook-dzos75b65q-uc.a.run.app'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'token': token}),
      );
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cycle ORION déclenché'), behavior: SnackBarBehavior.floating),
        );
        await Future.delayed(const Duration(seconds: 2));
        _load();
      }
    } catch (_) {}
    if (mounted) setState(() => _triggering = false);
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());

    final pendingMsgs = _messages.where((m) => m['status'] == 'pending').toList();
    final shownMsgs = _messages.where((m) => m['status'] == 'shown').toList();
    final otherMsgs = _messages.where((m) => m['status'] != 'pending' && m['status'] != 'shown').toList();

    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(text,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 1.1, color: cs.onSurface.withOpacity(0.45))),
        );

    Widget msgChip(String status) {
      final colors = {
        'pending': Colors.blue,
        'shown': Colors.green,
        'dismissed': Colors.orange,
        'expired': Colors.grey,
      };
      final c = colors[status] ?? Colors.grey;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
        child: Text(status, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600)),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
          children: [
            // ── Brief du stratège (ex-carte Focus — lot 5 : tout ORION ici) ─
            const _OrionBriefSection(),
            const SizedBox(height: 20),
            // ── En-tête ──────────────────────────────────────────────────
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.smart_toy_outlined, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Agent ORION', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text('$_runCount / 50 activations aujourd\'hui',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
              ]),
              const SizedBox(width: 12),
              // Badge plan tarifaire
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
                ),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Gratuit ', style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.7))),
                    TextSpan(text: '∞', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary)),
                    TextSpan(text: '  ·  Pro ', style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
                    TextSpan(text: '5/j', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7))),
                  ]),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_outlined, size: 14),
                label: const Text('Rafraîchir'),
                onPressed: _load,
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _triggering
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow_outlined, size: 16),
                label: const Text('Déclencher'),
                onPressed: _triggering ? null : _triggerNow,
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _runCount / 50,
                minHeight: 4,
                backgroundColor: cs.onSurface.withOpacity(0.08),
                color: _runCount >= 50 ? cs.error : cs.primary,
              ),
            ),

            // ── Comment ça marche ────────────────────────────────────────
            const SizedBox(height: 20),
            const _OrionHowItWorksCard(),

            // ── Config actuelle ───────────────────────────────────────────
            if (_config != null) ...[
              const SizedBox(height: 24),
              sectionLabel('INSTRUCTIONS ACTUELLES'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((_config!['userNeeds'] as String? ?? '').isNotEmpty) ...[
                    Text('Besoins :', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.5))),
                    const SizedBox(height: 4),
                    Text(_config!['userNeeds'] as String, style: const TextStyle(fontSize: 14)),
                  ],
                  if ((_config!['userReply'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Dernière réponse (${_config!['replyTimestamp'] ?? ''}) :',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.5))),
                    const SizedBox(height: 4),
                    Text(_config!['userReply'] as String,
                        style: TextStyle(fontSize: 14, color: cs.primary)),
                  ],
                ]),
              ),
            ],

            // ── Actions pré-établies ─────────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('ACTIONS RAPIDES'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((p) => ActionChip(
                avatar: Text(p.icon, style: const TextStyle(fontSize: 14)),
                label: Text(p.label, style: const TextStyle(fontSize: 13)),
                backgroundColor: p.taskId.isNotEmpty
                    ? Colors.green.withOpacity(0.08)
                    : cs.surfaceContainerHighest.withOpacity(0.5),
                side: p.taskId.isNotEmpty
                    ? BorderSide(color: Colors.green.withOpacity(0.3))
                    : null,
                onPressed: _triggering ? null : () => _triggerWithPreset(taskId: p.taskId, need: p.need),
              )).toList(),
            ),

            // ── Demande libre ────────────────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('DEMANDE LIBRE'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _customCtrl,
                    enabled: !_triggering,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ex : Crée un projet "Lancement produit" avec 3 phases, analyse mes retards…',
                      hintStyle: TextStyle(
                          fontSize: 13, color: cs.onSurface.withOpacity(.4)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (t.isEmpty) return;
                      _triggerWithPreset(taskId: '', need: t);
                      _customCtrl.clear();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  icon: _triggering
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Envoyer'),
                  onPressed: _triggering
                      ? null
                      : () {
                          final t = _customCtrl.text.trim();
                          if (t.isEmpty) return;
                          _triggerWithPreset(taskId: '', need: t);
                          _customCtrl.clear();
                        },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ),

            // ── Logs des cycles récents ───────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('CYCLES RÉCENTS (${_logs.length})'),
            if (_logs.isEmpty)
              Text('Aucun cycle enregistré',
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.4), fontStyle: FontStyle.italic))
            else
              for (final log in _logs) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    title: Row(children: [
                      Text(_fmtTs(log['cycleAt']),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
                      const SizedBox(width: 10),
                      if (log['skipped'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: cs.errorContainer.withOpacity(0.4), borderRadius: BorderRadius.circular(4)),
                          child: Text('skippé', style: TextStyle(fontSize: 10, color: cs.error)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text('${log['pushed'] ?? 0} message(s)', style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    subtitle: (log['userNeeds'] as String? ?? '').isNotEmpty
                        ? Text('"${(log['userNeeds'] as String).substring(0, ((log['userNeeds'] as String).length).clamp(0, 60))}…"',
                            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    children: [
                      if (log['skipped'] == true && log['skippedReason'] != null)
                        Text(log['skippedReason'] as String,
                            style: TextStyle(fontSize: 13, color: cs.error)),
                      for (final action in (log['actions'] as List? ?? []))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• $action', style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
              ],

            // ── Messages ORION ────────────────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('MESSAGES ORION (${_messages.length})'),
            if (_messages.isEmpty)
              Text('Aucun message',
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.4), fontStyle: FontStyle.italic))
            else
              for (final group in [
                ('EN ATTENTE', pendingMsgs),
                ('AFFICHÉS', shownMsgs),
                ('AUTRES', otherMsgs),
              ]) ...[
                if ((group.$2).isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Text(group.$1,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            letterSpacing: 0.8, color: cs.onSurface.withOpacity(0.4))),
                  ),
                  for (final msg in group.$2)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border(left: BorderSide(color: cs.primary.withOpacity(0.4), width: 3)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(msg['text'] as String? ?? '', style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(msg['targetDate'] as String? ?? '',
                                  style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.45))),
                              const SizedBox(width: 8),
                              Text('condition: ${(msg['condition'] as Map?)?.entries.map((e) => '${e.key}=${e.value}').join(', ') ?? ''}',
                                  style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.4))),
                            ]),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        msgChip(msg['status'] as String? ?? ''),
                      ]),
                    ),
                ],
              ],
          ],
        ),
      ),
    );
  }
}

// ── Ligne d'un item dans la vue Archives ─────────────────────────────────────

class _ArchiveItemRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool isArchived;
  final VoidCallback? onEdit;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback? onDelete;
  final ColorScheme cs;

  const _ArchiveItemRow({
    required this.label,
    required this.isArchived,
    required this.onArchive,
    required this.onRestore,
    required this.cs,
    this.subtitle,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isArchived
        ? cs.errorContainer.withOpacity(0.2)
        : cs.surfaceContainerHighest.withOpacity(0.3);
    final borderColor = isArchived
        ? cs.error.withOpacity(0.25)
        : cs.outlineVariant.withOpacity(0.4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ● bullet
          Text(
            '●',
            style: TextStyle(
              fontSize: 10,
              color: isArchived
                  ? cs.error.withOpacity(0.6)
                  : Colors.green.shade600,
            ),
          ),
          const SizedBox(width: 10),
          // Nom + sous-titre
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Bouton édition
          if (onEdit != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 15, color: cs.onSurface.withOpacity(0.4)),
              tooltip: 'Modifier',
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
            ),
          ],
          const SizedBox(width: 4),
          // Badge statut
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isArchived
                  ? cs.errorContainer
                  : Colors.green.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isArchived ? 'Archivé' : 'Actif',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isArchived
                    ? cs.error
                    : Colors.green.shade800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Boutons d'action
          if (!isArchived) ...[
            OutlinedButton(
              onPressed: onArchive,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber.shade800,
                side: BorderSide(color: Colors.amber.shade600),
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Archiver'),
            ),
          ] else ...[
            OutlinedButton(
              onPressed: onRestore,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green.shade700,
                side: BorderSide(color: Colors.green.shade400),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Restaurer'),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 6),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: const Text('Supprimer'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Comment ça marche — ORION ─────────────────────────────────────────────────

class _OrionHowItWorksCard extends StatefulWidget {
  const _OrionHowItWorksCard();

  @override
  State<_OrionHowItWorksCard> createState() => _OrionHowItWorksCardState();
}

class _OrionHowItWorksCardState extends State<_OrionHowItWorksCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          // ── Header cliquable ──────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.help_outline_rounded,
                      size: 16, color: cs.primary.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Text(
                    'Comment ça marche ?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: cs.onSurface.withOpacity(0.4),
                  ),
                ],
              ),
            ),
          ),

          // ── Contenu ──────────────────────────────────────────────────
          if (_expanded) ...[
            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Schéma 3 acteurs
                  LayoutBuilder(builder: (ctx, constraints) {
                    final narrow = constraints.maxWidth < 600;
                    final actors = [
                      _OrionActor(
                        icon: '✦',
                        iconColor: const Color(0xFF6366f1),
                        title: 'Claude',
                        subtitle: 'claude.ai · Claude Desktop',
                        description:
                            'Tu lui parles en langage naturel. Via MCP, il lit et modifie tes données directement : crée des projets, planifie tes journées, gère tes objectifs.',
                        cs: cs,
                      ),
                      _OrionActor(
                        icon: '◉',
                        iconColor: const Color(0xFF10b981),
                        title: 'ORION',
                        subtitle: 'Agent autonome · toutes les 6h',
                        description:
                            'Tourne en arrière-plan sans que tu aies à lui demander. Il analyse ton contexte, détecte tes retards et te pousse des messages actionnables sur iOS.',
                        cs: cs,
                      ),
                      _OrionActor(
                        icon: '⬡',
                        iconColor: const Color(0xFF8b5cf6),
                        title: 'App web',
                        subtitle: 'Projets · Documents · Pilotage',
                        description:
                            'Ton tableau de bord Gantt. Tu peux aussi déclencher ORION manuellement, voir ses logs et configurer ses instructions depuis ici.',
                        cs: cs,
                      ),
                    ];

                    return narrow
                        ? Column(
                            children: actors
                                .map((a) => Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: a,
                                    ))
                                .toList(),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: actors[0]),
                              _Arrow(cs: cs),
                              Expanded(child: actors[1]),
                              _Arrow(cs: cs),
                              Expanded(child: actors[2]),
                            ],
                          );
                  }),

                  const SizedBox(height: 20),

                  // Firestore — socle commun
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFf97316).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFf97316).withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Text('🗄', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Firestore — tes données, partagées en temps réel',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withOpacity(0.8),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Domaines · Activités · Projets Gantt · Plan du jour · Messages ORION',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withOpacity(0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Flux en 4 étapes
                  Text(
                    'Le flux en pratique',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(0.55),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final step in [
                    ('1', 'Tu configures tes données',
                        'Depuis l\'app iOS ou en demandant à Claude de le faire.'),
                    ('2', 'ORION analyse toutes les 6h',
                        'Il lit ton contexte complet et génère 1 à 3 messages ciblés.'),
                    ('3', 'Tu reçois une notification push',
                        'Le message apparaît dans l\'app iOS avec une action directe.'),
                    ('4', 'Tu peux aussi déclencher manuellement',
                        'Via les actions rapides ci-dessous ou en activant depuis iOS.'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(top: 1, right: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              step.$1,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(step.$2,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                Text(step.$3,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            cs.onSurface.withOpacity(0.5))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrionActor extends StatelessWidget {
  final String icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String description;
  final ColorScheme cs;

  const _OrionActor({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: iconColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icon,
                style: TextStyle(
                    fontSize: 16,
                    color: iconColor,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 10,
                  color: iconColor.withOpacity(0.8),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(description,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.55),
                  height: 1.5)),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  final ColorScheme cs;
  const _Arrow({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      child: Icon(Icons.sync_alt_rounded,
          size: 18, color: cs.onSurface.withOpacity(0.2)),
    );
  }
}
