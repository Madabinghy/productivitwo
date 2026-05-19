import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/web/gantt_screen.dart';

class WebHomeScreen extends StatefulWidget {
  const WebHomeScreen({super.key});

  @override
  State<WebHomeScreen> createState() => _WebHomeScreenState();
}

class _WebHomeScreenState extends State<WebHomeScreen> {
  final _sync = FirestoreSync();
  List<Project> _projects = [];
  List<StrategicObjective> _objectives = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final projects = await _sync.fetchProjects();
      final objectives = await _sync.fetchStrategicObjectives();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _objectives = objectives;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _showTokensPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _TokensPanel(sync: _sync),
    );
  }

  StrategicObjective? _objectiveFor(Project p) => p.strategicObjectiveId == null
      ? null
      : _objectives.where((o) => o.id == p.strategicObjectiveId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(Icons.account_tree_outlined,
                  color: cs.primary, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('Productivitwo — Projects',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          if (user != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Text(
                  user.displayName ?? user.email ?? '',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.6)),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.key_outlined, size: 18),
              tooltip: 'Tokens API',
              onPressed: () => _showTokensPanel(context),
            ),
            IconButton(
              icon: const Icon(Icons.logout_outlined, size: 18),
              tooltip: 'Déconnexion',
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
            const SizedBox(width: 8),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 64, color: cs.onSurface.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text('Aucun projet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(0.4))),
            const SizedBox(height: 8),
            Text(
              'Génère un Gantt avec Claude ou utilise l\'API pushGantt.',
              style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(0.3)),
            ),
          ],
        ),
      );
    }

    // Grouper les projets par objectif stratégique
    final withObj = <StrategicObjective, List<Project>>{};
    final withoutObj = <Project>[];

    for (final p in _projects) {
      final obj = _objectiveFor(p);
      if (obj != null) {
        withObj.putIfAbsent(obj, () => []).add(p);
      } else {
        withoutObj.add(p);
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Projets avec objectif stratégique
          for (final entry in withObj.entries) ...[
            _ObjectiveHeader(objective: entry.key),
            const SizedBox(height: 12),
            for (final p in entry.value) ...[
              _ProjectCard(
                project: p,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => GanttScreen(project: p)),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 20),
          ],
          // Projets sans objectif
          if (withoutObj.isNotEmpty) ...[
            if (withObj.isNotEmpty) ...[
              Divider(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4)),
              const SizedBox(height: 16),
            ],
            for (final p in withoutObj) ...[
              _ProjectCard(
                project: p,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => GanttScreen(project: p)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Objectif stratégique header ───────────────────────────────────────────────

class _ObjectiveHeader extends StatelessWidget {
  final StrategicObjective objective;
  const _ObjectiveHeader({required this.objective});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.flag_outlined, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            objective.title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: cs.primary,
            ),
          ),
        ),
        if (objective.kpiTarget != null)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              objective.kpiTarget!,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.primary),
            ),
          ),
      ],
    );
  }
}

// ── Carte projet ──────────────────────────────────────────────────────────────

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  const _ProjectCard({required this.project, required this.onTap});

  String _fmt(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tasks = project.tasks;
    final done = tasks.where((t) => t.status == 'done').length;
    final total = tasks.length;
    final progress = total > 0 ? done / total : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _SourceBadge(source: project.sourceType),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      size: 18,
                      color: cs.onSurface.withOpacity(0.3)),
                ],
              ),
              if (project.description != null &&
                  project.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  project.description!,
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.55)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 13,
                      color: cs.onSurface.withOpacity(0.4)),
                  const SizedBox(width: 5),
                  Text(
                    '${_fmt(project.startDate)} → ${project.endDate != null ? _fmt(project.endDate!) : '—'}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.5)),
                  ),
                  const Spacer(),
                  if (total > 0)
                    Text(
                      '$done / $total tâches',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.45)),
                    ),
                ],
              ),
              if (total > 0) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: cs.onSurface.withOpacity(0.07),
                  color: cs.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, icon) = switch (source) {
      'claude_api' => ('Claude', Icons.auto_awesome_outlined),
      'coach' => ('Coach', Icons.person_outlined),
      _ => ('Manuel', Icons.edit_outlined),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondaryContainer)),
        ],
      ),
    );
  }
}

// ── Panel Tokens API (web) ────────────────────────────────────────────────────

class _TokensPanel extends StatefulWidget {
  final FirestoreSync sync;
  const _TokensPanel({required this.sync});

  @override
  State<_TokensPanel> createState() => _TokensPanelState();
}

class _TokensPanelState extends State<_TokensPanel> {
  List<ApiToken> _tokens = [];
  bool _loading = true;
  String? _newTokenValue; // affiché une seule fois après création

  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
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
    setState(() => _newTokenValue = token.token);
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeTokens = _tokens.where((t) => t.active).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scroll) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Titre + bouton créer
            Row(
              children: [
                const Icon(Icons.key_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Tokens API',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nouveau'),
                  onPressed: _create,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // UID (pour les appels API)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ton UID Firebase',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withOpacity(0.5))),
                        const SizedBox(height: 2),
                        SelectableText(
                          _uid,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    onPressed: () => _copy(_uid, 'UID copié'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Nouveau token affiché après création
            if (_newTokenValue != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: cs.primary.withOpacity(0.3), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 14, color: cs.primary),
                        const SizedBox(width: 6),
                        Text('Token créé — copie-le maintenant',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.primary)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _newTokenValue!,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          onPressed: () =>
                              _copy(_newTokenValue!, 'Token copié'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Liste des tokens
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : activeTokens.isEmpty
                      ? Center(
                          child: Text('Aucun token actif',
                              style: TextStyle(
                                  color:
                                      cs.onSurface.withOpacity(0.4))),
                        )
                      : ListView.builder(
                          controller: scroll,
                          itemCount: activeTokens.length,
                          itemBuilder: (_, i) {
                            final t = activeTokens[i];
                            return ListTile(
                              dense: true,
                              leading: Icon(Icons.key_outlined,
                                  size: 16, color: cs.primary),
                              title: Text(t.label,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: Text(
                                t.lastUsedAt != null
                                    ? 'Utilisé le ${t.lastUsedAt!.day}/${t.lastUsedAt!.month}'
                                    : 'Jamais utilisé',
                                style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        cs.onSurface.withOpacity(0.4)),
                              ),
                              trailing: TextButton(
                                child: Text('Révoquer',
                                    style:
                                        TextStyle(color: cs.error, fontSize: 12)),
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
      ),
    );
  }
}
