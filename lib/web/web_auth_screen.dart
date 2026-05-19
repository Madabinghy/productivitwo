import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const _kCustomTokenUrl =
    'https://getcustomtoken-dzos75b65q-uc.a.run.app';

class WebAuthScreen extends StatefulWidget {
  const WebAuthScreen({super.key});

  @override
  State<WebAuthScreen> createState() => _WebAuthScreenState();
}

class _WebAuthScreenState extends State<WebAuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = false;
  String? _error;

  final _uidCtrl   = TextEditingController();
  final _tokenCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _uidCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  // ── Connexion Google ────────────────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Erreur de connexion');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Connexion via token iOS ─────────────────────────────────────────────────

  Future<void> _signInWithIosToken() async {
    final uid   = _uidCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (uid.isEmpty || token.isEmpty) {
      setState(() => _error = 'UID et token requis');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      // 1. Obtenir un Firebase custom token depuis la Cloud Function
      final res = await http.post(
        Uri.parse(_kCustomTokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'token': token}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode != 200) {
        throw Exception(body['error'] ?? 'Erreur serveur (${res.statusCode})');
      }

      final customToken = body['customToken'] as String?;
      if (customToken == null) throw Exception('Token Firebase manquant');

      // 2. Se connecter → même UID que l'app iOS
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.account_tree_outlined,
                            color: cs.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Productivitwo',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface)),
                          Text('Projects',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withOpacity(0.5))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Tabs
                TabBar(
                  controller: _tabs,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  tabs: const [
                    Tab(text: 'Google'),
                    Tab(text: 'Compte iOS'),
                  ],
                ),

                // Erreur
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!,
                          style: TextStyle(
                              fontSize: 13, color: cs.onErrorContainer)),
                    ),
                  ),

                // Tab content
                SizedBox(
                  height: 220,
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      // ── Onglet Google ────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Nouveau compte ou compte sans iOS.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withOpacity(0.55)),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _loading ? null : _signInWithGoogle,
                              icon: _loading
                                  ? SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: cs.onPrimary))
                                  : const Icon(Icons.login_outlined, size: 18),
                              label: Text(_loading
                                  ? 'Connexion…'
                                  : 'Continuer avec Google'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Onglet iOS ───────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Copie ton UID et un token depuis\nProductivitwo iOS → Tokens API.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withOpacity(0.55)),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _uidCtrl,
                              decoration: const InputDecoration(
                                labelText: 'UID iOS',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _tokenCtrl,
                              decoration: InputDecoration(
                                labelText: 'Token',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.paste_outlined, size: 16),
                                  onPressed: () async {
                                    final data = await Clipboard.getData('text/plain');
                                    if (data?.text != null) {
                                      _tokenCtrl.text = data!.text!;
                                    }
                                  },
                                ),
                              ),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _loading ? null : _signInWithIosToken,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 44),
                              ),
                              child: Text(_loading
                                  ? 'Connexion…'
                                  : 'Connecter mon compte iOS'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
