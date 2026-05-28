import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class WebEmailSignInScreen extends StatefulWidget {
  final String emailLink;
  const WebEmailSignInScreen({super.key, required this.emailLink});

  @override
  State<WebEmailSignInScreen> createState() => _WebEmailSignInScreenState();
}

class _WebEmailSignInScreenState extends State<WebEmailSignInScreen> {
  _Step _step = _Step.enterEmail;
  bool _loading = false;
  String? _error;
  String? _signedInEmail;
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _completeSignIn() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Adresse email invalide.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailLink(
        email: email,
        emailLink: widget.emailLink,
      );
      setState(() {
        _loading = false;
        _signedInEmail = email;
        _step = _Step.success;
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message ?? 'Erreur de connexion.';
      });
    }
  }

  Future<void> _openApp() async {
    final uri = Uri.parse('com.madabinghy.productivitwo://email-signin');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _step == _Step.success ? _buildSuccess() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Productivi',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(text: 'two', style: TextStyle(color: Color(0xFFC9A84C), fontSize: 28, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 40),
        const Text(
          'Confirme ton adresse email\npour te connecter.',
          style: TextStyle(color: Colors.white, fontSize: 18, height: 1.4),
        ),
        const SizedBox(height: 8),
        const Text(
          'Saisis l\'email avec lequel tu as demandé le lien de connexion.',
          style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'ton@email.com',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : _completeSignIn,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC9A84C),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Confirmer et me connecter', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Color(0xFF10B981), size: 32),
        ),
        const SizedBox(height: 24),
        const Text(
          'Connexion réussie !',
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          _signedInEmail ?? '',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _openApp,
            icon: const Icon(Icons.phone_iphone, color: Colors.white),
            label: const Text('Ouvrir dans Productivitwo', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC9A84C),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Si le bouton ne fonctionne pas, ouvre Productivitwo manuellement — tu seras déjà connecté.',
          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

enum _Step { enterEmail, success }
