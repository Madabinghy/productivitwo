import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ─── CONSOLE COACHING (web) — brique coaching v1 ─────────────────────────────
//
// Le pipeline des coachés du coach connecté (coachApi, scopé coachUid côté
// serveur) : fiches prospect → explo → actif → autonome → terminé, invitation
// (allowlist), lien de consentement partageable, tableau de bord en LECTURE
// (composé côté serveur, consentement requis), message dans l'app du coaché.

const _kCoachApiUrl = 'https://coachapi-dzos75b65q-uc.a.run.app';

const kCoachingStatuses = [
  ('prospect', 'Prospect', Color(0xFF8E24AA)),
  ('explo', 'Exploration', Color(0xFF1E88E5)),
  ('actif', 'Actif', Color(0xFF1a9e6e)),
  ('autonome', 'Autonome', Color(0xFF00897B)),
  ('termine', 'Terminé', Color(0xFF757575)),
];

/// Appel coachApi authentifié (ID token Firebase). Lève une exception avec le
/// message serveur en cas d'erreur ; 403 = pas coach (géré par l'appelant).
Future<Map<String, dynamic>> coachCall(Map<String, dynamic> body) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Non connecté');
  final idToken = await user.getIdToken();
  final resp = await http
      .post(
        Uri.parse(_kCoachApiUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 30));
  final data = resp.body.isNotEmpty
      ? jsonDecode(resp.body) as Map<String, dynamic>
      : <String, dynamic>{};
  if (resp.statusCode == 403) throw CoachAccessDenied();
  if (resp.statusCode >= 400) {
    throw Exception((data['error'] as String?) ?? 'HTTP ${resp.statusCode}');
  }
  return data;
}

class CoachAccessDenied implements Exception {}

/// Sonde discrète : le compte connecté est-il coach ? (bouton 🎓 de l'AppBar)
Future<bool> probeCoachAccess() async {
  try {
    await coachCall({'action': 'listClients'});
    return true;
  } catch (_) {
    return false;
  }
}

class CoachingScreen extends StatefulWidget {
  const CoachingScreen({super.key});

  @override
  State<CoachingScreen> createState() => _CoachingScreenState();
}

class _CoachingScreenState extends State<CoachingScreen> {
  List<Map<String, dynamic>> _clients = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await coachCall({'action': 'listClients'});
      _clients = ((r['clients'] as List?) ?? [])
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
    } on CoachAccessDenied {
      _error = 'Accès coach requis — active le droit dans /admin.html (🎓).';
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createClient() async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Nouveau coaché'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Prénom / nom'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email',
                  helperText:
                      'La fiche existe avant le compte — phase exploratoire.'),
              onSubmitted: (_) => Navigator.pop(d, true),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Créer la fiche')),
        ],
      ),
    );
    final email = emailCtrl.text.trim();
    if (ok != true || email.isEmpty) return;
    try {
      await coachCall({
        'action': 'createClient',
        'email': email,
        'name': nameCtrl.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coaching — mes coachés'),
        actions: [
          IconButton(
              tooltip: 'Rafraîchir',
              icon: const Icon(Icons.refresh),
              onPressed: _load),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createClient,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nouveau coaché'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.error)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
                  children: [
                    if (_clients.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Aucune fiche — crée ton premier coaché dès la phase '
                          'exploratoire : la fiche vit avant le compte.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: cs.onSurface.withOpacity(.5)),
                        ),
                      ),
                    for (final (key, label, color) in kCoachingStatuses)
                      ..._section(cs, key, label, color),
                  ],
                ),
    );
  }

  List<Widget> _section(
      ColorScheme cs, String key, String label, Color color) {
    final items = _clients.where((c) => c['status'] == key).toList();
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('${label.toUpperCase()} · ${items.length}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: cs.onSurface.withOpacity(.5))),
        ]),
      ),
      for (final c in items)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(.15),
              child: Text(
                ((c['name'] ?? c['email']) as String)
                    .substring(0, 1)
                    .toUpperCase(),
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ),
            title: Text((c['name'] as String?) ?? (c['email'] as String)),
            subtitle: Text(
              [
                c['email'],
                if ((c['nextSession'] as String?)?.isNotEmpty == true)
                  '📅 ${c['nextSession']}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _consentBadge(cs, c),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CoachClientScreen(client: c)));
              _load();
            },
          ),
        ),
    ];
  }

  Widget _consentBadge(ColorScheme cs, Map<String, dynamic> c) {
    final consent = c['consent'] as String?;
    final sharing = (c['sharing'] as Map?) ?? const {};
    final domainCount = (sharing['domainCount'] as num?)?.toInt() ?? 0;
    final granLabel =
        sharing['granularity'] == 'detail' ? 'détail' : 'statuts';
    final (label, color) = switch (consent) {
      'granted' when domainCount > 0 => (
          '✓ $domainCount dom. · $granLabel',
          const Color(0xFF1a9e6e)
        ),
      'granted' => ('rien de partagé', const Color(0xFFB7791F)),
      'revoked' => ('révoqué', cs.error),
      _ => ('en attente', cs.onSurface.withOpacity(.4)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ─── Fiche coaché ─────────────────────────────────────────────────────────────

class CoachClientScreen extends StatefulWidget {
  final Map<String, dynamic> client;
  const CoachClientScreen({super.key, required this.client});

  @override
  State<CoachClientScreen> createState() => _CoachClientScreenState();
}

class _CoachClientScreenState extends State<CoachClientScreen> {
  late Map<String, dynamic> c;
  late final TextEditingController _notes;
  late final TextEditingController _nextSession;
  Map<String, dynamic>? _dashboard;
  bool _dashLoading = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    c = Map<String, dynamic>.from(widget.client);
    _notes = TextEditingController(text: (c['notes'] as String?) ?? '');
    _nextSession =
        TextEditingController(text: (c['nextSession'] as String?) ?? '');
    if (c['consent'] == 'granted') _loadDashboard();
  }

  @override
  void dispose() {
    _notes.dispose();
    _nextSession.dispose();
    super.dispose();
  }

  Future<void> _update(Map<String, dynamic> patch) async {
    setState(() => _busy = true);
    try {
      await coachCall({'action': 'updateClient', 'id': c['id'], ...patch});
      c = {...c, ...patch};
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _loadDashboard() async {
    setState(() => _dashLoading = true);
    try {
      final r = await coachCall({'action': 'dashboard', 'id': c['id']});
      _dashboard = r['ok'] == true
          ? Map<String, dynamic>.from(r['dashboard'] as Map)
          : {'reason': r['reason']};
    } catch (e) {
      _dashboard = {'reason': '$e'};
    }
    if (mounted) setState(() => _dashLoading = false);
  }

  Future<void> _invite() async {
    setState(() => _busy = true);
    try {
      await coachCall({'action': 'invite', 'id': c['id']});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '✅ ${c['email']} autorisé — il peut créer son compte via le magic link.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _consentLink() async {
    setState(() => _busy = true);
    try {
      final r = await coachCall({'action': 'consentLink', 'id': c['id']});
      final url = r['url'] as String?;
      if (url != null) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  '🔗 Lien de consentement copié — envoie-le par WhatsApp/mail. Valable 14 jours, révocable par le même lien.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Suppression DURE (fiche mal créée — mauvais email…) : le serveur retire
  /// aussi l'invitation allowlist posée par ce coach et les jetons de
  /// consentement. Les données du coaché, elles, ne sont jamais touchées.
  Future<void> _deleteClient() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Supprimer la fiche « ${c['name'] ?? c['email']} » ?'),
        content: const Text(
            'La fiche, ses liens de consentement et l\'invitation partent. '
            'Les données du coaché dans SON app ne sont pas touchées.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await coachCall({'action': 'deleteClient', 'id': c['id']});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _sendMessage() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Message à ${c['name'] ?? c['email']}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(
              hintText:
                  'Il apparaîtra dans son app, signé de ton nom — même canal qu\'ORION.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Envoyer')),
        ],
      ),
    );
    final text = ctrl.text.trim();
    if (ok != true || text.isEmpty) return;
    try {
      final r = await coachCall(
          {'action': 'message', 'id': c['id'], 'text': text});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(r['ok'] == true
                ? '✉️ Envoyé — il le verra à sa prochaine ouverture.'
                : 'Impossible (${r['reason']}).')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final consent = (c['consent'] as String?) ?? 'pending';

    return Scaffold(
      appBar: AppBar(
        title: Text((c['name'] as String?) ?? (c['email'] as String)),
        actions: [
          IconButton(
            tooltip: 'Supprimer la fiche',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : _deleteClient,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
        children: [
          Text(c['email'] as String,
              style: TextStyle(color: cs.onSurface.withOpacity(.6))),
          const SizedBox(height: 16),

          // Pipeline.
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (key, label, color) in kCoachingStatuses)
              ChoiceChip(
                label: Text(label),
                selected: c['status'] == key,
                selectedColor: color.withOpacity(.2),
                onSelected:
                    _busy ? null : (_) => _update({'status': key}),
              ),
          ]),
          const SizedBox(height: 16),

          // Accès & consentement.
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _invite,
              icon: const Icon(Icons.mail_outline, size: 16),
              label: const Text('Inviter (accès app)'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _consentLink,
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Lien de consentement'),
            ),
            FilledButton.icon(
              onPressed: consent == 'granted' ? _sendMessage : null,
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Message dans son app'),
            ),
          ]),
          if (consent != 'granted')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                consent == 'revoked'
                    ? 'Accès révoqué par le coaché — renvoie un lien de consentement si vous en reparlez.'
                    : 'En attente de consentement : envoie-lui le lien — dashboard et messages s\'ouvriront quand il aura accepté.',
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurface.withOpacity(.55)),
              ),
            ),
          const SizedBox(height: 20),

          // Notes de coaching + prochaine séance.
          TextField(
            controller: _nextSession,
            decoration: const InputDecoration(
                labelText: 'Prochaine séance',
                hintText: 'ex. jeudi 18 h — bilan exploratoire'),
            onSubmitted: (v) => _update({'nextSession': v.trim()}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 6,
            minLines: 3,
            decoration: const InputDecoration(
                labelText: 'Notes de coaching',
                alignLabelWithHint: true,
                hintText:
                    'Contexte, objectifs, points de la dernière séance…'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _update({
                        'notes': _notes.text.trim(),
                        'nextSession': _nextSession.text.trim(),
                      }).then((_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Fiche enregistrée.')));
                        }
                      }),
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Enregistrer la fiche'),
            ),
          ),
          const Divider(height: 32),

          // Tableau de bord (lecture, consentement requis).
          Row(children: [
            Text('TABLEAU DE BORD',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: cs.onSurface.withOpacity(.5))),
            const Spacer(),
            if (consent == 'granted')
              IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _dashLoading ? null : _loadDashboard),
          ]),
          if (consent != 'granted')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('🔒 Visible après consentement du coaché.',
                  style: TextStyle(color: cs.onSurface.withOpacity(.5))),
            )
          else if (_dashLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_dashboard != null)
            ..._dashboardView(cs, _dashboard!),
        ],
      ),
    );
  }

  List<Widget> _dashboardView(ColorScheme cs, Map<String, dynamic> d) {
    if (d['reason'] != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
              switch (d['reason']) {
                'no_account' => 'Pas encore de compte — invite-le d\'abord.',
                'no_scope' =>
                  'Consentement donné, mais rien de partagé pour l\'instant — '
                      'il choisit ses domaines et le niveau de détail dans son '
                      'app (Paramètres → Mon coach).',
                _ => 'Indisponible : ${d['reason']}',
              },
              style: TextStyle(color: cs.onSurface.withOpacity(.5))),
        ),
      ];
    }
    final statusOnly = d['granularity'] == 'status';
    final activities = ((d['activities'] as List?) ?? [])
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
    final nameOf = {for (final a in activities) a['id']: a['name']};
    final minutes = Map<String, dynamic>.from(
        (d['weekMinutesByActivity'] as Map?) ?? {});
    final topTime = minutes.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));
    String fmtMin(num m) => m >= 60
        ? '${m ~/ 60}h${(m % 60) > 0 ? (m % 60).toString().padLeft(2, '0') : ''}'
        : '${m}min';

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(t,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.onSurface.withOpacity(.45))),
        );

    return [
      if (statusOnly)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
              '🔒 Partage en mode « statuts seulement » — pas de temps ni de '
              'blocs de journée. Seuls les domaines et engagements partagés '
              'apparaissent.',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
        )
      else ...[
        label('PROGRAMME DU JOUR (${d['date']})'),
        if (((d['todayBlocks'] as List?) ?? []).isEmpty)
          Text('Rien de programmé.',
              style: TextStyle(color: cs.onSurface.withOpacity(.5)))
        else
          for (final b in (d['todayBlocks'] as List))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${b['startTime']} · ${b['title']}'
                '${b['status'] == 'done' ? '  ✓' : b['status'] == 'skipped' ? '  (sauté)' : ''}',
                style: TextStyle(
                    fontSize: 13.5,
                    decoration: b['status'] == 'done'
                        ? TextDecoration.lineThrough
                        : null,
                    color: cs.onSurface
                        .withOpacity(b['status'] == 'pending' ? .9 : .5)),
              ),
            ),
        label('TEMPS · 7 DERNIERS JOURS'),
        if (topTime.isEmpty)
          Text('Aucune session loggée.',
              style: TextStyle(color: cs.onSurface.withOpacity(.5)))
        else
          for (final e in topTime.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                  '${nameOf[e.key] ?? e.key} — ${fmtMin(e.value as num)}',
                  style: const TextStyle(fontSize: 13.5)),
            ),
      ],
      label('DOMAINES'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final dom in ((d['domains'] as List?) ?? []))
          Chip(
            label: Text('${(dom as Map)['name']}'),
            visualDensity: VisualDensity.compact,
          ),
      ]),
      label('ROUTINES'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final a in activities.where((a) => a['type'] == 'habit'))
          Chip(
            label: Text(
                '${a['name']}${a['habitTarget'] != null && (a['habitTarget'] as num) > 1 ? ' · ${a['habitTarget']}' : ''}'),
            visualDensity: VisualDensity.compact,
          ),
      ]),
      if (d['pendingIdeas'] != null) ...[
        const SizedBox(height: 8),
        Text('💡 ${d['pendingIdeas']} idée(s) en attente dans sa boîte.',
            style: TextStyle(
                fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
      ],
    ];
  }
}
