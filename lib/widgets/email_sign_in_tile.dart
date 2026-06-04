import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/pro_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmailSignInTile extends StatefulWidget {
  final FirestoreSync sync;
  final AppState state;
  final VoidCallback onDataChanged;

  const EmailSignInTile({
    super.key,
    required this.sync,
    required this.state,
    required this.onDataChanged,
  });

  @override
  State<EmailSignInTile> createState() => _EmailSignInTileState();
}

class _EmailSignInTileState extends State<EmailSignInTile> {
  bool _loading = false;
  bool _linkSent = false;
  String? _error;
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Adresse email invalide.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await widget.sync.sendSignInLink(email);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('email_sign_in_pending', email);
      if (mounted) setState(() { _loading = false; _linkSent = true; });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final email = widget.sync.userEmail;
    final isAnon = widget.sync.isAnonymous;

    if (_loading) {
      return const ListTile(
        leading: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        title: Text('Connexion en cours…'),
      );
    }

    // Connecté avec email
    if (!isAnon && email != null) {
      return ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Colors.green, size: 18),
        ),
        title: const Text('Compte connecté', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(email, style: const TextStyle(fontSize: 12)),
        trailing: TextButton(
          onPressed: () async {
            await widget.sync.signOut();
            await ProManager.logoutUser();
            if (mounted) widget.onDataChanged();
          },
          child: Text('Déconnecter', style: TextStyle(color: cs.onSurface.withOpacity(.45), fontSize: 13)),
        ),
      );
    }

    // Lien envoyé — attente du clic
    if (_linkSent) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mark_email_read_outlined, color: Colors.green, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lien envoyé à ${_emailCtrl.text.trim()}.\nOuvre ton email et clique sur le lien pour te connecter.',
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() { _linkSent = false; }),
              child: const Text('Changer d\'adresse email'),
            ),
          ],
        ),
      );
    }

    // Formulaire envoi du lien
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.email_outlined),
            title: Text('Connexion par email'),
            subtitle: Text('Reçois un lien magique — sans mot de passe'),
          ),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'ton@email.com',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sendLink,
              child: const Text('Envoyer le lien de connexion'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(fontSize: 12, color: cs.error)),
            ),
        ],
      ),
    );
  }
}
