import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WebEmailSignInScreen extends StatelessWidget {
  final String emailLink;
  const WebEmailSignInScreen({super.key, required this.emailLink});

  Future<void> _openApp() async {
    final encoded = Uri.encodeComponent(emailLink);
    final uri = Uri.parse('com.madabinghy.productivitwo://email-signin?link=$encoded');
    await launchUrl(uri, webOnlyWindowName: '_self');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Productivi',
                      style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    const Text(
                      'two',
                      style: TextStyle(color: Color(0xFFC9A84C), fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(.2)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.mark_email_read_outlined, color: Color(0xFF10B981), size: 22),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Ton lien de connexion est prêt.',
                              style: TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openApp,
                        icon: const Icon(Icons.phone_iphone, color: Colors.white),
                        label: const Text(
                          'Ouvrir dans Productivitwo',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC9A84C),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Si le bouton ne fonctionne pas, ouvre Productivitwo manuellement puis retente la connexion depuis les Paramètres.',
                      style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
