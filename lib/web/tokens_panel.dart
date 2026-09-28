import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

// Panneau « Connecter Claude » : tokens API (MCP), options de connexion.

// ── Panel Connecter Claude / Tokens ──────────────────────────────────────────

class TokensPanel extends StatefulWidget {
  final FirestoreSync sync;
  const TokensPanel({super.key, required this.sync});

  @override
  State<TokensPanel> createState() => TokensPanelState();
}

class TokensPanelState extends State<TokensPanel>
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
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
                                    Text(
                                        'Token actif : ${activeTokens.first.label}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                cs.onSurface.withOpacity(0.7))),
                                    const SizedBox(height: 6),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.add, size: 14),
                                      label: const Text('Créer un autre token'),
                                      onPressed: _create,
                                      style: OutlinedButton.styleFrom(
                                          visualDensity: VisualDensity.compact),
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
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface.withOpacity(0.45),
                                      fontStyle: FontStyle.italic))
                              : Builder(builder: (context) {
                                  final displayToken = _newTokenValue ??
                                      activeTokens.first.rawToken;
                                  if (displayToken == null) {
                                    return Text(
                                      'Crée un nouveau token (étape 1) pour voir ton URL complète.',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: cs.onSurface.withOpacity(0.55),
                                          fontStyle: FontStyle.italic),
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // URL principale (simple)
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer
                                              .withOpacity(0.4),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color:
                                                  cs.primary.withOpacity(0.25)),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: SelectableText(
                                                _mcpUrl(displayToken),
                                                style: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 11),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.copy_outlined,
                                                  size: 16),
                                              onPressed: () => _copy(
                                                  _mcpUrl(displayToken),
                                                  'URL copiée'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      // Option A : Claude.ai web
                                      _ConnectOption(
                                        icon: Icons.language_outlined,
                                        title: 'Claude.ai web',
                                        description:
                                            'Paramètres → Personnaliser → Connecteurs → colle l\'URL',
                                      ),
                                      const SizedBox(height: 8),
                                      // Option B : Claude Desktop
                                      _ConnectOption(
                                        icon: Icons.desktop_mac_outlined,
                                        title: 'Claude Desktop',
                                        description:
                                            'Paramètres → Développeur → Modifier la config → colle le JSON ci-dessous',
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest
                                              .withOpacity(0.6),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: SelectableText(
                                                _mcpConfig(displayToken),
                                                style: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 10),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.copy_outlined,
                                                  size: 14),
                                              onPressed: () => _copy(
                                                  _mcpConfig(displayToken),
                                                  'Config copiée'),
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
                            style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurface.withOpacity(0.65),
                                height: 1.5),
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
                                Icon(Icons.info_outline,
                                    size: 14, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'Token créé (visible une seule fois)',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: cs.primary)),
                                      SelectableText(_newTokenValue!,
                                          style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon:
                                      const Icon(Icons.copy_outlined, size: 14),
                                  onPressed: () =>
                                      _copy(_newTokenValue!, 'Token copié'),
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
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withOpacity(0.6))),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Nouveau'),
                          onPressed: _create,
                          style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact),
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
                                    style: TextStyle(
                                        color: cs.onSurface.withOpacity(0.4))))
                            : ListView.builder(
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
                                          color: cs.onSurface.withOpacity(0.4)),
                                    ),
                                    trailing: TextButton(
                                      child: Text('Révoquer',
                                          style: TextStyle(
                                              color: cs.error, fontSize: 12)),
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
  const _ConnectOption(
      {required this.icon, required this.title, required this.description});

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
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.65),
                  height: 1.4),
              children: [
                TextSpan(
                    text: '$title — ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
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
          width: 28,
          height: 28,
          decoration:
              BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(number,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.primary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ],
    );
  }
}
