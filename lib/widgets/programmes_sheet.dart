import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ProgrammesSheet extends StatefulWidget {
  final FirestoreSync sync;
  final List<Domain> domains;

  const ProgrammesSheet({
    super.key,
    required this.sync,
    required this.domains,
  });

  @override
  State<ProgrammesSheet> createState() => _ProgrammesSheetState();
}

class _ProgrammesSheetState extends State<ProgrammesSheet> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final docs = await widget.sync.fetchDocuments();
    if (mounted) setState(() { _docs = docs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Group documents by domainId
    final Map<String?, List<Map<String, dynamic>>> grouped = {};
    for (final doc in _docs) {
      final domainId = doc['domainId'] as String?;
      grouped.putIfAbsent(domainId, () => []).add(doc);
    }

    // Sort: domains with id first, then null (no domain)
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => a == null ? 1 : b == null ? -1 : 0);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Programmes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _docs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.description_outlined,
                                size: 48,
                                color: cs.onSurface.withOpacity(0.25)),
                            const SizedBox(height: 12),
                            Text(
                              'Aucun programme pour l\'instant',
                              style: TextStyle(
                                  color: cs.onSurface.withOpacity(0.5)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Demande à Claude de créer un programme !',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withOpacity(0.35)),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          for (final domainId in sortedKeys) ...[
                            _DomainSection(
                              domainId: domainId,
                              domains: widget.domains,
                              docs: grouped[domainId]!,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _DomainSection extends StatelessWidget {
  final String? domainId;
  final List<Domain> domains;
  final List<Map<String, dynamic>> docs;

  const _DomainSection({
    required this.domainId,
    required this.domains,
    required this.docs,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final domain = domainId != null
        ? domains.where((d) => d.id == domainId).firstOrNull
        : null;
    final color = domainColor(domainId, domains) ?? cs.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                domain?.name ?? 'Sans domaine',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withOpacity(0.6),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        for (final doc in docs)
          _ProgrammeCard(doc: doc, domainColor: color),
      ],
    );
  }
}

class _ProgrammeCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final Color domainColor;

  const _ProgrammeCard({required this.doc, required this.domainColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = doc['title'] as String? ?? 'Programme';
    final subtitle = doc['subtitle'] as String?;
    final createdAt = _parseDate(doc['createdAt']);
    final updatedAt = _parseDate(doc['updatedAt']);
    final dateLabel = _formatDate(updatedAt ?? createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openViewer(context, title, doc['content'] as String? ?? ''),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  domainColor.withOpacity(0.18),
                  domainColor.withOpacity(0.06),
                ],
              ),
              border: Border.all(
                color: domainColor.withOpacity(0.3),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: domainColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    color: domainColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(0.55),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (dateLabel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(0.35),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: domainColor.withOpacity(0.6),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, String title, String html) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ProgrammeViewer(title: title, htmlContent: html),
      ),
    );
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    try { return DateTime.parse(raw.toString()); } catch (_) { return null; }
  }

  String? _formatDate(DateTime? dt) {
    if (dt == null) return null;
    final now = DateTime.now();
    final diff = now.difference(dt).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return "Hier";
    if (diff < 7) return "Il y a $diff jours";
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
  }
}

// ── Full-screen HTML viewer ───────────────────────────────────────────────────

class _ProgrammeViewer extends StatefulWidget {
  final String title;
  final String htmlContent;

  const _ProgrammeViewer({required this.title, required this.htmlContent});

  @override
  State<_ProgrammeViewer> createState() => _ProgrammeViewerState();
}

class _ProgrammeViewerState extends State<_ProgrammeViewer> {
  WebViewController? _webController;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _webController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0A0A0A))
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) { if (mounted) setState(() => _ready = true); },
        ))
        ..loadHtmlString(widget.htmlContent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 0,
      ),
      body: kIsWeb
          ? const Center(
              child: Text(
                'Ouvre le programme depuis l\'app web.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : Stack(
              children: [
                if (_webController != null)
                  WebViewWidget(controller: _webController!),
                if (!_ready)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
