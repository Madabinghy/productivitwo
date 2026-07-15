import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── GOOGLE AGENDA — RÉGLAGES (Direction D) ──────────────────────────────────
//
// Connexion OAuth CÔTÉ SERVEUR : l'app ne voit jamais les tokens Google —
// elle demande une URL de consentement (gcalApi/authUrl), l'utilisateur
// approuve dans le navigateur, le serveur stocke le refresh token. Ensuite
// TOUTE écriture du programme (app, MCP, ORION) est synchronisée par le
// trigger Firestore — l'app n'a rien à faire.

const _kGcalApiUrl = 'https://gcalapi-dzos75b65q-uc.a.run.app';

/// Sync silencieuse BIDIRECTIONNELLE (import des rendez-vous → miroirs, puis
/// push du programme) pour aujourd'hui et demain — appelée à l'ouverture de
/// l'app. Agenda non connecté → le serveur répond « not_connected », coût
/// quasi nul. Toute erreur est avalée : jamais bloquant pour le démarrage.
Future<void> gcalBackgroundSync(FirestoreSync sync) async {
  try {
    final now = DateTime.now();
    for (final d in [now, now.add(const Duration(days: 1))]) {
      await gcalSyncDay(sync, _ymd(d));
    }
  } catch (_) {
    // Hors-ligne / pas connecté : rien à faire, on réessaiera à la prochaine
    // ouverture.
  }
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Sync bidirectionnelle d'UN jour (import miroirs + push du programme).
/// Retourne la réponse serveur ({ok, created, updated, deleted, reason?…}) —
/// null = réseau/token indisponible. Utilisée par la sync de fond et le
/// bouton ⟳ agenda de l'onglet Aujourd'hui.
Future<Map<String, dynamic>?> gcalSyncDay(
    FirestoreSync sync, String date) async {
  try {
    final token = await sync.ensureWidgetToken();
    final raw = token.rawToken;
    final uid = sync.uid;
    if (raw == null || raw.isEmpty || uid == null) return null;
    final resp = await http
        .post(
          Uri.parse(_kGcalApiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $raw',
          },
          body: jsonEncode({'uid': uid, 'action': 'syncDay', 'date': date}),
        )
        .timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) return null;
    return jsonDecode(resp.body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<void> showGcalSettingsSheet(BuildContext context,
    {required FirestoreSync sync}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _GcalSheet(sync: sync),
  );
}

class _GcalSheet extends StatefulWidget {
  final FirestoreSync sync;
  const _GcalSheet({required this.sync});

  @override
  State<_GcalSheet> createState() => _GcalSheetState();
}

class _GcalSheetState extends State<_GcalSheet> {
  bool _loading = true;
  bool _busy = false;
  bool _connected = false;
  bool _autoSync = true;
  bool _revoked = false;
  String? _email;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<Map<String, dynamic>?> _call(String action,
      {Map<String, dynamic> extra = const {}}) async {
    try {
      final token = await widget.sync.ensureWidgetToken();
      final raw = token.rawToken;
      final uid = widget.sync.uid;
      if (raw == null || raw.isEmpty || uid == null) {
        throw Exception('token indisponible');
      }
      final resp = await http
          .post(
            Uri.parse(_kGcalApiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $raw',
            },
            body: jsonEncode({'uid': uid, 'action': action, ...extra}),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      if (mounted) setState(() => _error = 'Connexion au serveur impossible.');
      return null;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final s = await _call('status');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (s != null) {
        _connected = s['connected'] == true;
        _autoSync = s['autoSync'] != false;
        _revoked = s['revoked'] == true;
        _email = s['email'] as String?;
      }
    });
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    final r = await _call('authUrl');
    if (!mounted) return;
    setState(() => _busy = false);
    final url = r?['url'] as String?;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _syncToday() async {
    setState(() => _busy = true);
    final r = await _call('syncDay');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) return;
    final msg = r['ok'] == true
        ? '🗓️ Programme synchronisé — ${r['created']} créé(s), ${r['updated']} mis à jour, ${r['deleted']} retiré(s).'
        : 'Synchronisation impossible (${r['reason']}).';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _disconnect() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Déconnecter Google Agenda ?'),
        content: const Text(
            'Les événements déjà créés restent dans ton agenda — plus rien ne sera synchronisé.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Déconnecter')),
        ],
      ),
    );
    if (sure != true) return;
    setState(() => _busy = true);
    await _call('disconnect');
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.calendar_month_rounded, size: 22),
              const SizedBox(width: 10),
              const Text('Google Agenda',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (_loading || _busy)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 8),
            Text(
              'Ton programme du jour (blocs, défis, événements) apparaît dans ton agenda '
              'et suit chaque changement — sans passer par Claude. Les événements '
              'personnels de ton agenda ne sont jamais touchés.',
              style: TextStyle(color: cs.onSurface.withOpacity(.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: TextStyle(color: cs.error, fontSize: 13)),
              ),
            if (!_loading && !_connected) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _connect,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Connecter mon Google Agenda'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('J\'ai approuvé — vérifier la connexion'),
                ),
              ),
            ],
            if (!_loading && _connected) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                    _revoked ? Icons.link_off_rounded : Icons.check_circle_rounded,
                    color: _revoked ? cs.error : Colors.teal),
                title: Text(_revoked ? 'Accès révoqué côté Google' : 'Connecté'),
                subtitle: Text(_revoked
                    ? 'Reconnecte l\'agenda pour reprendre la synchronisation.'
                    : (_email ?? 'Compte Google')),
              ),
              if (_revoked)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Reconnecter'),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Synchronisation automatique'),
                subtitle: const Text(
                    'Chaque changement du programme met l\'agenda à jour'),
                value: _autoSync,
                onChanged: _busy
                    ? null
                    : (v) async {
                        setState(() => _autoSync = v);
                        await _call('setAutoSync', extra: {'value': v});
                      },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Synchroniser aujourd\'hui'),
                onTap: _busy ? null : _syncToday,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.link_off_rounded, color: cs.error),
                title: Text('Déconnecter',
                    style: TextStyle(color: cs.error)),
                onTap: _busy ? null : _disconnect,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
