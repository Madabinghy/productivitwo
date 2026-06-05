import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';

/// Bibliothèque de challenges partagée (Phase 2) : parcourir les défis approuvés
/// (curés par super-Orion), s'abonner, et soumettre les siens.
Future<void> showChallengeLibrarySheet(BuildContext context, FirestoreSync sync) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ChallengeLibrarySheet(sync: sync),
  );
}

class _ChallengeLibrarySheet extends StatefulWidget {
  final FirestoreSync sync;
  const _ChallengeLibrarySheet({required this.sync});

  @override
  State<_ChallengeLibrarySheet> createState() => _ChallengeLibrarySheetState();
}

class _ChallengeLibrarySheetState extends State<_ChallengeLibrarySheet> {
  List<Map<String, dynamic>> _items = [];
  Set<String> _subs = {};
  bool _loading = true;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await widget.sync.fetchChallengeLibrary();
    final subs = await widget.sync.fetchMySubscriptions();
    if (mounted) {
      setState(() {
        _items = items;
        _subs = subs;
        _loading = false;
      });
    }
  }

  Future<void> _toggleSub(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    final isSub = _subs.contains(id);
    setState(() => _busy.add(id));
    final err = await widget.sync.subscribeChallenge(id, !isSub);
    if (!mounted) return;
    setState(() {
      _busy.remove(id);
      if (err == null) {
        if (isSub) {
          _subs.remove(id);
          item['subscribers'] = (item['subscribers'] as int) - 1;
        } else {
          _subs.add(id);
          item['subscribers'] = (item['subscribers'] as int) + 1;
        }
      }
    });
  }

  Future<void> _submit() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Proposer un défi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Titre du défi'),
            ),
            TextField(
              controller: descCtrl,
              maxLength: 300,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Description (optionnel)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Soumettre')),
        ],
      ),
    );
    final title = titleCtrl.text.trim();
    final desc = descCtrl.text.trim();
    titleCtrl.dispose();
    descCtrl.dispose();
    if (ok != true || title.length < 3) return;
    final err = await widget.sync.submitChallenge(title, desc);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ??
          'Défi soumis ✅ — il apparaîtra après validation par Orion.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                const Text('📚', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text('Bibliothèque de défis',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Proposer'),
                ),
              ]),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Aucun défi pour l\'instant. Sois le premier à en proposer un !',
                  style: TextStyle(
                      color: cs.onSurface.withOpacity(.5),
                      fontStyle: FontStyle.italic),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1, color: cs.outlineVariant.withOpacity(.3)),
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    final id = it['id'] as String;
                    final isSub = _subs.contains(id);
                    final busy = _busy.contains(id);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it['title'] as String,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                                if ((it['description'] as String).isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(it['description'] as String,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurface.withOpacity(.6))),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  '${it['category']} · ${it['durationMin']} min · ⭐ ${it['xp']} · 👥 ${it['subscribers']}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurface.withOpacity(.45)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          busy
                              ? const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Padding(
                                    padding: EdgeInsets.all(6),
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ))
                              : IconButton(
                                  icon: Icon(
                                    isSub
                                        ? Icons.check_circle
                                        : Icons.add_circle_outline,
                                    color: isSub ? cs.primary : null,
                                  ),
                                  tooltip: isSub ? 'Abonné' : 'S\'abonner',
                                  onPressed: () => _toggleSub(it),
                                ),
                        ],
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
