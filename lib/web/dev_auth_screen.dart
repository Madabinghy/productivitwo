import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// DEV-LOGIN LOCAL (localhost uniquement, cf. web_app.dart) : signe une vraie session
// Firebase sur TON compte via getCustomToken({uid, token}) où token = ton token API
// (MCP : PRODUCTIVITWO_UID + PRODUCTIVITWO_TOKEN). uid + token sont stockés UNIQUEMENT
// dans le localStorage du navigateur (SharedPreferences) — JAMAIS dans le repo.
const _kGetCustomTokenUrl =
    'https://us-central1-productivitwo-app.cloudfunctions.net/getCustomToken';
const _kDevUidKey = 'dev_auth_uid';
const _kDevTokenKey = 'dev_auth_token';

class DevAuthScreen extends StatefulWidget {
  final VoidCallback? onSignedIn;
  const DevAuthScreen({super.key, this.onSignedIn});

  @override
  State<DevAuthScreen> createState() => _DevAuthScreenState();
}

class _DevAuthScreenState extends State<DevAuthScreen> {
  final _uidCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAndMaybeSignIn();
  }

  Future<void> _loadAndMaybeSignIn() async {
    final prefs = await SharedPreferences.getInstance();
    _uidCtrl.text = prefs.getString(_kDevUidKey) ?? '';
    _tokenCtrl.text = prefs.getString(_kDevTokenKey) ?? '';
    if (mounted) setState(() {});
    if (_uidCtrl.text.isNotEmpty && _tokenCtrl.text.isNotEmpty) {
      _signIn(); // auto : déjà renseigné une fois
    }
  }

  Future<void> _signIn() async {
    final uid = _uidCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (uid.isEmpty || token.isEmpty) {
      setState(() => _error = 'uid et token requis');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse(_kGetCustomTokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'token': token}),
      );
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        throw Exception(body['error'] ?? 'HTTP ${res.statusCode}');
      }
      final customToken = (jsonDecode(res.body) as Map)['customToken'] as String;
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDevUidKey, uid);
      await prefs.setString(_kDevTokenKey, token);
      widget.onSignedIn?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _uidCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('🔧 Dev-login local',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text(
                    'Tes identifiants MCP (PRODUCTIVITWO_UID + PRODUCTIVITWO_TOKEN). '
                    'Stockés en local seulement.',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 16),
                TextField(
                  controller: _uidCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      labelText: 'uid', labelStyle: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenCtrl,
                  style: const TextStyle(color: Colors.white),
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'token API',
                      labelStyle: TextStyle(color: Colors.white54)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: Color(0xFFE05858), fontSize: 12)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _signIn,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Se connecter avec mes données'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
