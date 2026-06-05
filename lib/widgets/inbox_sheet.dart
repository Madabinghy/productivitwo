import 'dart:async';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

Future<void> showInboxSheet(BuildContext context, FirestoreSync sync) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _InboxSheet(sync: sync),
  );
}

class _InboxSheet extends StatefulWidget {
  final FirestoreSync sync;
  const _InboxSheet({required this.sync});

  @override
  State<_InboxSheet> createState() => _InboxSheetState();
}

class _InboxSheetState extends State<_InboxSheet> {
  List<CaptureItem> _items = [];
  StreamSubscription<List<CaptureItem>>? _sub;
  String? _editingId;
  final _editCtrl = TextEditingController();

  Future<void> _addItem() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle idée'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ton idée, note rapide...'),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Capturer')),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (confirmed == true && text.isNotEmpty) {
      await widget.sync.saveCaptureItem(CaptureItem(text: text, createdAt: DateTime.now()));
    }
  }

  @override
  void initState() {
    super.initState();
    _sub = widget.sync.streamCaptures().listen((items) {
      if (mounted) setState(() => _items = items);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _editCtrl.dispose();
    super.dispose();
  }

  List<CaptureItem> get _pending =>
      _items.where((i) => i.status == 'pending').toList();
  List<CaptureItem> get _processed =>
      _items.where((i) => i.status == 'processed').toList();

  Future<void> _delete(CaptureItem item) async {
    await widget.sync.deleteCaptureItem(item.id);
  }

  Future<void> _saveEdit(CaptureItem item) async {
    final text = _editCtrl.text.trim();
    if (text.isEmpty) return;
    await widget.sync.updateCaptureItem(item.id, {'text': text});
    setState(() => _editingId = null);
  }

  void _startEdit(CaptureItem item) {
    _editCtrl.text = item.text;
    setState(() => _editingId = item.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    color: Colors.amber.shade600, size: 20),
                const SizedBox(width: 8),
                Text('Inbox',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
                const Spacer(),
                if (_pending.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${_pending.length}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 22),
                  tooltip: 'Nouvelle idée',
                  onPressed: _addItem,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: ctrl,
              // + viewInsets : le champ d'édition reste visible au-dessus du clavier.
              padding: EdgeInsets.fromLTRB(
                  16, 0, 16, 32 + MediaQuery.of(context).viewInsets.bottom),
              children: [
                // ── En attente ───────────────────────────────────────────────
                if (_pending.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
                    child: Column(
                      children: [
                        Text('Aucune idée en attente',
                            style: TextStyle(
                                color: cs.onSurface.withOpacity(.4),
                                fontSize: 14)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withOpacity(.45),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cs.onSurface.withOpacity(.06)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('💡',
                                  style: TextStyle(fontSize: 15)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'ORION récupère tes idées et les structure automatiquement toutes les 6h — il peut créer des projets, planifier des rappels ou les ajouter à tes tâches existantes.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withOpacity(.55),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _sectionHeader('EN ATTENTE', cs),
                  for (final item in _pending)
                    _editingId == item.id
                        ? _buildEditTile(item, cs)
                        : _buildPendingTile(item, cs),
                ],

                // ── Historique ORION ─────────────────────────────────────────
                if (_processed.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionHeader('TRAITÉ PAR ORION', cs),
                  for (final item in _processed)
                    _buildProcessedTile(item, cs),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: cs.onSurface.withOpacity(.4))),
      );

  Widget _buildPendingTile(CaptureItem item, ColorScheme cs) => Dismissible(
        key: Key(item.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red.shade400,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        onDismissed: (_) => _delete(item),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(.2)),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Icon(Icons.lightbulb_outline,
                size: 18, color: Colors.amber.shade600),
            title: Text(item.text,
                style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              _formatDate(item.createdAt),
              style: TextStyle(
                  fontSize: 11, color: cs.onSurface.withOpacity(.4)),
            ),
            trailing: IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: cs.onSurface.withOpacity(.4)),
              onPressed: () => _startEdit(item),
            ),
          ),
        ),
      );

  Widget _buildEditTile(CaptureItem item, ColorScheme cs) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(.3),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: cs.primary.withOpacity(.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _editCtrl,
                  autofocus: true,
                  maxLines: null,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                      isDense: true, border: InputBorder.none),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.check, size: 18),
                onPressed: () => _saveEdit(item),
              ),
              IconButton(
                icon: Icon(Icons.close,
                    size: 18, color: cs.onSurface.withOpacity(.4)),
                onPressed: () => setState(() => _editingId = null),
              ),
            ],
          ),
        ),
      );

  Widget _buildProcessedTile(CaptureItem item, ColorScheme cs) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(.15)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Icon(Icons.check_circle_outline,
              size: 18, color: Colors.green.withOpacity(.7)),
          title: Text(item.text,
              style: TextStyle(
                  fontSize: 14, color: cs.onSurface.withOpacity(.55))),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.orionNote != null && item.orionNote!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '→ ${item.orionNote}',
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.primary.withOpacity(.7),
                        fontStyle: FontStyle.italic),
                  ),
                ),
              Text(
                _formatDate(item.processedAt ?? item.createdAt),
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withOpacity(.3)),
              ),
            ],
          ),
        ),
      );

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    return '${dt.day}/${dt.month}';
  }
}
