import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ── Couleurs cohérentes avec AssistantWidget ──────────────────────────────────
const _bg     = Color(0xFF0f0f0f);
const _surface = Color(0xFF181818);
const _gold   = Color(0xFFe8c94a);
const _border = Color(0xFF2a2a2a);
const _muted  = Color(0xFF747070);
const _text   = Color(0xFFf0ece0);

// ── Modèle local ──────────────────────────────────────────────────────────────

class _HistoryItem {
  final String id;
  final String text;
  final String characterName;
  final String status;
  final String targetDate;
  final DateTime? shownAt;
  final DateTime? createdAt;

  const _HistoryItem({
    required this.id,
    required this.text,
    required this.characterName,
    required this.status,
    required this.targetDate,
    this.shownAt,
    this.createdAt,
  });
}

// ── Sheet principale ──────────────────────────────────────────────────────────

class AssistantHistorySheet extends StatefulWidget {
  const AssistantHistorySheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AssistantHistorySheet(),
    );
  }

  @override
  State<AssistantHistorySheet> createState() => _AssistantHistorySheetState();
}

class _AssistantHistorySheetState extends State<AssistantHistorySheet> {
  List<_HistoryItem> _shown = [];
  List<_HistoryItem> _pending = [];
  bool _loading = true;
  bool _advancedExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    final snap = await FirebaseFirestore.instance
        .collection('users/$uid/assistant_messages')
        .where('status', whereIn: ['shown', 'dismissed', 'pending'])
        .limit(50)
        .get();

    final all = snap.docs.map((doc) {
      final d = doc.data();
      return _HistoryItem(
        id: d['id'] as String? ?? doc.id,
        text: d['text'] as String? ?? '',
        characterName: d['characterName'] as String? ?? 'ORION',
        status: d['status'] as String? ?? 'pending',
        targetDate: d['targetDate'] as String? ?? '',
        shownAt: _toDate(d['shownAt']),
        createdAt: _toDate(d['createdAt']),
      );
    }).toList();

    final shown = all.where((i) => i.status == 'shown' || i.status == 'dismissed').toList()
      ..sort((a, b) {
        final dateA = a.shownAt ?? a.createdAt ?? DateTime(0);
        final dateB = b.shownAt ?? b.createdAt ?? DateTime(0);
        return dateB.compareTo(dateA);
      });

    final pending = all.where((i) => i.status == 'pending').toList()
      ..sort((a, b) {
        final dateA = a.createdAt ?? DateTime(0);
        final dateB = b.createdAt ?? DateTime(0);
        return dateB.compareTo(dateA);
      });

    if (mounted) setState(() { _shown = shown; _pending = pending; _loading = false; });
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(
            top: BorderSide(color: _gold, width: 1.5),
            left: BorderSide(color: _border),
            right: BorderSide(color: _border),
          ),
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              decoration: const BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                border: Border(bottom: BorderSide(color: _border)),
              ),
              child: Row(
                children: [
                  const Text('◉', style: TextStyle(color: _gold, fontSize: 14)),
                  const SizedBox(width: 10),
                  const Text(
                    'MESSAGES ORION',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                      color: _gold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: _muted),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Contenu ──────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _gold))
                  : _shown.isEmpty && _pending.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.smart_toy_outlined, size: 40, color: _muted),
                              const SizedBox(height: 12),
                              const Text(
                                'Aucun message pour l\'instant.',
                                style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: _muted),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Connecte Claude pour recevoir des conseils.',
                                style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: _muted),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          controller: scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          children: [
                            // Messages affichés
                            if (_shown.isNotEmpty) ...[
                              for (int i = 0; i < _shown.length; i++) ...[
                                _HistoryTile(item: _shown[i]),
                                if (i < _shown.length - 1)
                                  const Divider(color: _border, height: 1),
                              ],
                            ],

                            // Section avancée — messages en attente (visible uniquement sur web)
                            if (_pending.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: () => setState(() => _advancedExpanded = !_advancedExpanded),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _surface,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: _border),
                                  ),
                                  child: Row(
                                    children: [
                                      const Text('⚙', style: TextStyle(fontSize: 11, color: _muted)),
                                      const SizedBox(width: 8),
                                      Text(
                                        'AVANCÉ — ${_pending.length} message${_pending.length > 1 ? 's' : ''} en attente',
                                        style: const TextStyle(
                                          fontFamily: 'monospace', fontSize: 10,
                                          letterSpacing: 1.5, color: _muted,
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        _advancedExpanded ? Icons.expand_less : Icons.expand_more,
                                        size: 16, color: _muted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_advancedExpanded) ...[
                                const SizedBox(height: 8),
                                for (int i = 0; i < _pending.length; i++) ...[
                                  _HistoryTile(item: _pending[i]),
                                  if (i < _pending.length - 1)
                                    const Divider(color: _border, height: 1),
                                ],
                              ],
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tuile message ─────────────────────────────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  final _HistoryItem item;
  const _HistoryTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final isShown   = item.status == 'shown';
    final isPending = item.status == 'pending';
    final date = item.shownAt ?? item.createdAt;
    final dateStr = date != null ? _fmt(date) : item.targetDate;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indicateur statut
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 12),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isShown
                    ? _muted
                    : isPending
                        ? _gold
                        : _muted,
              ),
            ),
          ),

          // Contenu
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nom personnage + date
                Row(
                  children: [
                    Text(
                      item.characterName,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: _gold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: _muted,
                      ),
                    ),
                    const Spacer(),
                    if (isPending)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _gold.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: _gold.withOpacity(0.3), width: 1),
                        ),
                        child: const Text(
                          'PRÉVU',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: _gold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // Texte
                Text(
                  item.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.6,
                    color: isShown
                        ? _text.withOpacity(0.55)
                        : _text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    const months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
