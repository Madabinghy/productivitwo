import 'dart:html' as html;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Clé partagée avec web_auth_screen pour retrouver l'email saisi à la demande du lien.
const String kWebEmailPendingKey = 'web_email_sign_in_pending';

// Page de complétion du magic link sur le web : finalise signInWithEmailLink.
// Affichée par _AuthGate quand l'URL contient mode=signIn&oobCode hors /email-signin.
// Contrairement au natif (relay vers custom scheme), ici on connecte directement.
class WebMagicLinkCompleteScreen extends StatefulWidget {
  final String emailLink;
  final VoidCallback? onSignedIn;
  const WebMagicLinkCompleteScreen({
    super.key,
    required this.emailLink,
    this.onSignedIn,
  });

  @override
  State<WebMagicLinkCompleteScreen> createState() =>
      _WebMagicLinkCompleteScreenState();
}

class _WebMagicLinkCompleteScreenState
    extends State<WebMagicLinkCompleteScreen> {
  String? _error;
  bool _askEmail = false;
  final _emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final auth = FirebaseAuth.instance;
    if (!auth.isSignInWithEmailLink(widget.emailLink)) {
      setState(() => _error = 'Ce lien de connexion n\'est pas valide.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(kWebEmailPendingKey);
    if (email == null || email.isEmpty) {
      // Lien ouvert sur un autre appareil/navigateur : on redemande l'email.
      setState(() => _askEmail = true);
      return;
    }
    await _complete(email);
  }

  Future<void> _complete(String email) async {
    try {
      try {
        await FirebaseAuth.instance
            .signInWithEmailLink(email: email.trim(), emailLink: widget.emailLink);
      } on TypeError catch (_) {
        // firebase_auth web peut lancer un TypeError JS-interop sur le UserCredential
        // même quand l'auth réussit — on vérifie currentUser comme fallback.
        await Future.delayed(const Duration(milliseconds: 400));
        if (FirebaseAuth.instance.currentUser == null) rethrow;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kWebEmailPendingKey);
      // Retire mode/oobCode de l'URL pour qu'un refresh ne re-déclenche pas la complétion.
      html.window.history.replaceState(null, '', '/');
      // Notifie _AuthGate pour qu'il se reconstruise et bascule vers WebHomeScreen.
      widget.onSignedIn?.call();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _askEmail = true;
          _error = e.message ?? 'Connexion impossible. Vérifie ton email.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('Productivi',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800)),
                      Text('two',
                          style: TextStyle(
                              color: Color(0xFFC9A84C),
                              fontSize: 28,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 40),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Color(0xFFFFB4AB), fontSize: 13)),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_askEmail) ...[
                    const Text(
                      'Confirme ton email pour finaliser la connexion.',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'ton@email.com',
                        hintStyle: TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Color(0xFF1C1C2A),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        final v = _emailCtrl.text.trim();
                        if (v.isEmpty) return;
                        setState(() {
                          _askEmail = false;
                          _error = null;
                        });
                        _complete(v);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFC9A84C),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Me connecter',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ] else if (_error == null) ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 20),
                    const Text(
                      'Connexion en cours…',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
