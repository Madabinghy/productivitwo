import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

const _webhookBase = 'https://orionsaveconfig-dzos75b65q-uc.a.run.app';
const _countUrl = 'https://orionruncount-dzos75b65q-uc.a.run.app';

class OrionConfigSheet extends StatefulWidget {
  final FirestoreSync sync;

  const OrionConfigSheet({super.key, required this.sync});

  @override
  State<OrionConfigSheet> createState() => _OrionConfigSheetState();
}

class _OrionConfigSheetState extends State<OrionConfigSheet> {
  final _needsCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  int _runCount = 0;
  String? _activeToken;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _needsCtrl.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = widget.sync.uid;
      if (uid == null) throw Exception('Non connecté');

      // Charger config ORION + token actif en parallèle
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('users/$uid/orion_config')
            .doc('main')
            .get(),
        widget.sync.fetchApiTokens(),
      ]);

      final configSnap = results[0] as DocumentSnapshot;
      final tokens = results[1] as List<ApiToken>;

      if (configSnap.exists) {
        final d = configSnap.data() as Map<String, dynamic>;
        _needsCtrl.text = (d['userNeeds'] as String?) ?? '';
        _replyCtrl.text = (d['userReply'] as String?) ?? '';
      }

      _activeToken = tokens.firstWhere(
        (t) => t.active,
        orElse: () => tokens.isEmpty ? ApiToken(label: '', tokenHash: '') : tokens.first,
      ).rawToken;

      // Charger le compteur du jour
      if (_activeToken != null && _activeToken!.isNotEmpty) {
        await _loadRunCount();
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRunCount() async {
    final uid = widget.sync.uid;
    if (uid == null || _activeToken == null) return;
    try {
      final resp = await http.get(
        Uri.parse('$_countUrl?uid=$uid&token=$_activeToken'),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (mounted) setState(() => _runCount = (data['count'] as int?) ?? 0);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final uid = widget.sync.uid;
    if (uid == null || _activeToken == null || _activeToken!.isEmpty) {
      setState(() => _error = 'Aucun token API actif. Crée-en un dans Tokens API.');
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      final resp = await http.post(
        Uri.parse(_webhookBase),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'uid': uid,
          'token': _activeToken,
          'userNeeds': _needsCtrl.text.trim(),
          'userReply': _replyCtrl.text.trim(),
        }),
      );

      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        final pushed = data['pushed'] as int? ?? 0;
        final skipped = data['skipped'] as bool? ?? false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                skipped
                    ? 'Config sauvegardée — limite journalière atteinte (5/5)'
                    : 'Config sauvegardée — ORION a généré $pushed message${pushed > 1 ? 's' : ''}',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _replyCtrl.clear();
          await _loadRunCount();
        }
      } else {
        setState(() => _error = data['error']?.toString() ?? 'Erreur inconnue');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) {
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            // ── En-tête ─────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.smart_toy_outlined, size: 20, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Configuration ORION',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Agent IA autonome · $_runCount/5 activations aujourd\'hui',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Barre compteur journalier
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _runCount / 5,
                minHeight: 4,
                backgroundColor: cs.onSurface.withOpacity(.08),
                color: _runCount >= 5 ? cs.error : cs.primary,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(fontSize: 13, color: cs.error)),
              ),
            ],

            // ── Priorité du moment (cadrage permanent d'ORION) ───────────────
            const SizedBox(height: 24),
            _Label('Ta priorité du moment'),
            const SizedBox(height: 4),
            Text(
              'ORION la lit chaque matin et à chaque demande pour cadrer ses suggestions. Mets-la à jour quand ta priorité change.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _needsCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Ex : Je veux avancer la formation cette semaine. Pas de défis sport.',
                hintStyle: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.35)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(.4),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: const TextStyle(fontSize: 14),
            ),

            // ── Répondre à ORION ─────────────────────────────────────────────
            const SizedBox(height: 20),
            _Label('Répondre à ORION'),
            const SizedBox(height: 8),
            TextField(
              controller: _replyCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Ta réponse au dernier message ORION (optionnel)…',
                hintStyle: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.35)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(.4),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: const TextStyle(fontSize: 14),
            ),

            // ── Bouton sauvegarder ───────────────────────────────────────────
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving || _runCount >= 5 ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(_runCount >= 5 ? 'Limite atteinte (5/5)' : 'Sauvegarder et activer ORION'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

            const SizedBox(height: 12),
            Text(
              'Sauvegarder déclenche immédiatement un cycle ORION.\nORION s\'active aussi automatiquement toutes les 6h.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.4)),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
          letterSpacing: 0.3,
        ),
      );
}
