// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';

// ── Dialog visualisation documents ───────────────────────────────────────────

class DocumentViewerDialog extends StatefulWidget {
  final String projectTitle;
  final List<Map<String, dynamic>> documents;
  final FirestoreSync sync;
  final VoidCallback? onDeleted;

  const DocumentViewerDialog({
    super.key,
    required this.projectTitle,
    required this.documents,
    required this.sync,
    this.onDeleted,
  });

  @override
  State<DocumentViewerDialog> createState() => DocumentViewerDialogState();
}

class DocumentViewerDialogState extends State<DocumentViewerDialog> {
  int _selectedIndex = 0;
  late List<Map<String, dynamic>> _docs;

  @override
  void initState() {
    super.initState();
    _docs = List.of(widget.documents);
  }

  Map<String, dynamic> get _current => _docs[_selectedIndex];

  Future<void> _deleteDocument() async {
    final doc = _current;
    final docId = doc['id'] as String?;
    if (docId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce document ?'),
        content: Text('"${doc['title'] ?? 'Document'}" sera supprimé définitivement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.sync.hardDelete('documents', docId);
    widget.onDeleted?.call();

    if (_docs.length == 1) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _docs.removeAt(_selectedIndex);
      if (_selectedIndex >= _docs.length) _selectedIndex = _docs.length - 1;
    });
  }

  void _download() {
    final title = _current['title'] as String? ?? 'document';
    final htmlContent = _current['content'] as String? ?? '';
    final content = htmlContent.contains('<html')
        ? htmlContent
        : '<html><head><meta charset="utf-8"></head><body>$htmlContent</body></html>';
    final blob = html.Blob([content], 'text/html');
    final url = html.Url.createObjectUrl(blob);
    final filename =
        '${title.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_')}.html';
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasMultiple = _docs.length > 1;
    final title = _current['title'] as String? ?? 'Document';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        // Lot 5 : largeur utile pour lire un document (ex 900×700).
        constraints: const BoxConstraints(maxWidth: 1160, maxHeight: 820),
        child: Column(
          children: [
            // AppBar-like header
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12)),
                border: Border(
                  bottom: BorderSide(
                      color: cs.outlineVariant.withOpacity(0.4)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasMultiple
                          ? '${widget.projectTitle} — $title'
                          : title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.download_outlined,
                        size: 18, color: cs.onSurface.withOpacity(.6)),
                    tooltip: 'Télécharger (.html)',
                    onPressed: _download,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: cs.onSurface.withOpacity(.45)),
                    tooltip: 'Supprimer ce document',
                    onPressed: _deleteDocument,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_outlined, size: 18),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Fermer',
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: Row(
                children: [
                  // Sidebar list (only when multiple docs)
                  if (hasMultiple) ...[
                    Container(
                      width: 200,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                              color: cs.outlineVariant.withOpacity(0.4)),
                        ),
                      ),
                      child: ListView.builder(
                        itemCount: _docs.length,
                        itemBuilder: (_, i) {
                          final doc = _docs[i];
                          final docTitle =
                              doc['title'] as String? ?? 'Document ${i + 1}';
                          final isSelected = i == _selectedIndex;
                          return ListTile(
                            dense: true,
                            selected: isSelected,
                            selectedTileColor:
                                cs.primaryContainer.withOpacity(0.4),
                            leading: Icon(
                              Icons.article_outlined,
                              size: 16,
                              color: isSelected
                                  ? cs.primary
                                  : cs.onSurface.withOpacity(0.5),
                            ),
                            title: Text(
                              docTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? cs.primary
                                    : cs.onSurface,
                              ),
                            ),
                            onTap: () =>
                                setState(() => _selectedIndex = i),
                          );
                        },
                      ),
                    ),
                  ],

                  // HTML content viewer
                  Expanded(
                    child: HtmlDocViewer(
                      key: ValueKey(_current['id'] ?? _selectedIndex),
                      documentId:
                          _current['id'] as String? ?? 'doc-$_selectedIndex',
                      htmlContent: _current['content'] as String? ?? '',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widget rendu HTML via iframe ──────────────────────────────────────────────

class HtmlDocViewer extends StatefulWidget {
  final String documentId;
  final String htmlContent;

  const HtmlDocViewer({
    super.key,
    required this.documentId,
    required this.htmlContent,
  });

  @override
  State<HtmlDocViewer> createState() => HtmlDocViewerState();
}

class HtmlDocViewerState extends State<HtmlDocViewer> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'html-doc-${widget.documentId}';
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (_) {
      final iframe = html.IFrameElement()
        ..srcdoc = widget.htmlContent
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}
