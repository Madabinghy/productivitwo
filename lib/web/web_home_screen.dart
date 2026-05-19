import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/web/gantt_screen.dart';
import 'package:productivitwo_v1/web/help_sheet.dart';

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

  Future<void> _showLinkIosDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LinkIosDialog(onLinked: _load),
    );
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
            const HelpButton(),
            TextButton.icon(
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('Connecter Claude'),
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_tree_outlined,
                    size: 56, color: cs.onSurface.withOpacity(0.15)),
                const SizedBox(height: 20),
                Text('Aucun projet',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(0.4))),
                const SizedBox(height: 24),

                // ── Carte : déjà utilisateur iOS ? ──────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: cs.primary.withOpacity(0.2), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.smartphone_outlined,
                              size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Text('Tu as Productivitwo sur iPhone ?',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connecte ton compte iOS pour retrouver tes activités, '
                        'routines et objectifs, et laisser Claude les piloter.',
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withOpacity(0.65),
                            height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.link_outlined, size: 16),
                          label: const Text('Connecter mon compte iOS'),
                          onPressed: () => _showLinkIosDialog(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Séparateur ───────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                        child: Divider(
                            color: cs.onSurface.withOpacity(0.12))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('ou',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.35))),
                    ),
                    Expanded(
                        child: Divider(
                            color: cs.onSurface.withOpacity(0.12))),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Génère ton premier Gantt avec Claude',
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurface.withOpacity(0.35)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
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

  String _mcpUrl(String token) =>
      'https://productivitwo-app.web.app/mcp/$_uid/$token';

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

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          // Titre
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Connecter Claude',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
                        controller: scroll,
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
                                : Column(
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
                                                _mcpUrl(activeTokens.first.token),
                                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.copy_outlined, size: 16),
                                              onPressed: () => _copy(_mcpUrl(activeTokens.first.token), 'URL copiée'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      // Option A : Claude.ai web
                                      _ConnectOption(
                                        icon: Icons.language_outlined,
                                        title: 'Claude.ai web',
                                        description: 'Paramètres → Intégrations → Ajouter un serveur MCP → colle l\'URL',
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
                                                _mcpConfig(activeTokens.first.token),
                                                style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.copy_outlined, size: 14),
                                              onPressed: () => _copy(_mcpConfig(activeTokens.first.token), 'Config copiée'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
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
      ),
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

// ── Dialog liaison compte iOS ─────────────────────────────────────────────────

class _LinkIosDialog extends StatefulWidget {
  final VoidCallback onLinked;
  const _LinkIosDialog({required this.onLinked});

  @override
  State<_LinkIosDialog> createState() => _LinkIosDialogState();
}

class _LinkIosDialogState extends State<_LinkIosDialog> {
  final _uidCtrl   = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  static const _customTokenUrl =
      'https://getcustomtoken-dzos75b65q-uc.a.run.app';

  @override
  void dispose() {
    _uidCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final uid   = _uidCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (uid.isEmpty || token.isEmpty) {
      setState(() => _error = 'UID et token requis');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse(_customTokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'token': token}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        throw Exception(body['error'] ?? 'Erreur (${res.statusCode})');
      }
      final customToken = body['customToken'] as String?;
      if (customToken == null) throw Exception('Token Firebase manquant');

      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      if (mounted) Navigator.pop(context);
      widget.onLinked();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.link_outlined, color: cs.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Connecter mon compte iOS',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '1. Ouvre Productivitwo iOS → menu ⋮ → Tokens API\n'
                '2. Copie ton UID (en haut) et génère un token\n'
                '3. Colle-les ici',
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withOpacity(0.6),
                    height: 1.5),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!,
                      style:
                          TextStyle(fontSize: 12, color: cs.onErrorContainer)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _uidCtrl,
                decoration: const InputDecoration(
                  labelText: 'UID iOS',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Token',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _link,
                child: _loading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Connecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
