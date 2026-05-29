import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widget_service.dart';

class ApiTokensScreen extends StatefulWidget {
  final FirestoreSync sync;
  final String uid;
  final AppLogic? logic;

  const ApiTokensScreen({super.key, required this.sync, this.uid = '', this.logic});

  @override
  State<ApiTokensScreen> createState() => _ApiTokensScreenState();
}

class _ApiTokensScreenState extends State<ApiTokensScreen> {
  List<ApiToken> _tokens = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final tokens = await widget.sync.fetchApiTokens();
    if (!mounted) return;
    setState(() {
      _tokens = tokens;
      _loading = false;
    });
  }

  Future<void> _createToken() async {
    final label = await _showLabelDialog();
    if (label == null || label.isEmpty) return;

    final token = await widget.sync.createApiToken(label);
    if (!mounted) return;

    await _showTokenCreatedDialog(token);
    await _load();
  }

  Future<void> _revoke(ApiToken token) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Révoquer ce token ?'),
        content: Text(
          '"${token.label}" ne pourra plus être utilisé pour '
          'envoyer des données dans Productivitwo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await widget.sync.revokeApiToken(token.id);
    _load();
  }

  Future<String?> _showLabelDialog() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau token'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom du token',
            hintText: 'ex: Claude MCP, Coach Antoine',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
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

  Future<void> _showTokenCreatedDialog(ApiToken token) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Token créé'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copie ce token maintenant — il ne sera plus affiché.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                token.rawToken ?? '',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copier'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: token.rawToken ?? ''));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Token copié'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('J\'ai copié le token'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = _tokens.where((t) => t.active).toList();
    final revoked = _tokens.where((t) => !t.active).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tokens API'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nouveau token',
            onPressed: _loading ? null : _createToken,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // ── UID (pour lier avec le web app) ────────────────────────
                if (widget.uid.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ton UID (pour le web app)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          cs.onSurface.withOpacity(0.5)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.uid,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 16),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: widget.uid));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('UID copié'),
                                    duration: Duration(seconds: 2)),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                // ── En-tête explicatif ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Les tokens permettent à Claude ou à un coach '
                            'd\'envoyer des projets Gantt dans ton espace '
                            'sans avoir accès à ton compte.',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withOpacity(0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Widget iOS diag ────────────────────────────────────────
                _WidgetDiagTile(logic: widget.logic),

                // ── Tokens actifs ───────────────────────────────────────────
                if (active.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(
                      'Aucun token actif.\nAppuie sur + pour en créer un.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: cs.onSurface.withOpacity(0.45),
                          fontSize: 14),
                    ),
                  )
                else ...[
                  _SectionHeader('Actifs (${active.length})'),
                  for (final t in active)
                    _TokenTile(
                      token: t,
                      onRevoke: () => _revoke(t),
                    ),
                ],

                // ── Tokens révoqués ─────────────────────────────────────────
                if (revoked.isNotEmpty) ...[
                  _SectionHeader('Révoqués (${revoked.length})'),
                  for (final t in revoked)
                    _TokenTile(token: t, onRevoke: null),
                ],

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ── Tuile token ───────────────────────────────────────────────────────────────

class _TokenTile extends StatelessWidget {
  final ApiToken token;
  final VoidCallback? onRevoke;

  const _TokenTile({required this.token, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = token.active;

    String _lastUsed() {
      if (token.lastUsedAt == null) return 'jamais utilisé';
      final d = token.lastUsedAt!;
      final diff = DateTime.now().difference(d);
      if (diff.inDays == 0) return 'utilisé aujourd\'hui';
      if (diff.inDays == 1) return 'utilisé hier';
      if (diff.inDays < 7) return 'utilisé il y a ${diff.inDays}j';
      return 'utilisé le ${d.day}/${d.month}/${d.year}';
    }

    return Dismissible(
      key: ValueKey(token.id),
      direction: onRevoke != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      confirmDismiss: (_) async {
        onRevoke?.call();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: cs.errorContainer,
        child: Icon(Icons.block_outlined, color: cs.error),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive
                ? cs.primaryContainer
                : cs.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.key_outlined,
            size: 18,
            color: isActive ? cs.primary : cs.onSurface.withOpacity(0.35),
          ),
        ),
        title: Text(
          token.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isActive
                ? cs.onSurface
                : cs.onSurface.withOpacity(0.4),
            decoration: isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Text(
          _lastUsed(),
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withOpacity(0.45),
          ),
        ),
        trailing: isActive && onRevoke != null
            ? IconButton(
                icon:
                    Icon(Icons.block_outlined, size: 18, color: cs.error),
                tooltip: 'Révoquer',
                onPressed: onRevoke,
              )
            : isActive
                ? null
                : Chip(
                    label: const Text('Révoqué',
                        style: TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
      ),
    );
  }
}

// ── Diagnostic Widget iOS ─────────────────────────────────────────────────────

class _WidgetDiagTile extends StatefulWidget {
  final AppLogic? logic;
  const _WidgetDiagTile({this.logic});

  @override
  State<_WidgetDiagTile> createState() => _WidgetDiagTileState();
}

class _WidgetDiagTileState extends State<_WidgetDiagTile> {
  bool _updating = false;

  Future<void> _forceUpdate() async {
    final l = widget.logic;
    if (l == null) return;
    setState(() => _updating = true);
    await WidgetService.update(l);
    if (mounted) setState(() => _updating = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final diag = WidgetService.lastDiag;
    final isError = diag?.error != null;
    final color = diag == null
        ? cs.onSurface.withOpacity(0.4)
        : isError
            ? cs.error
            : Colors.green;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(
              diag == null
                  ? Icons.widgets_outlined
                  : isError
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                diag == null
                    ? 'Widget iOS : pas encore mis à jour cette session'
                    : diag.toString(),
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
            if (widget.logic != null)
              TextButton(
                onPressed: _updating ? null : _forceUpdate,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: _updating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Forcer', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      );
}
