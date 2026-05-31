import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/web/web_magic_link_complete_screen.dart';

// Continuation URL du magic link web — racine pour que _AuthGate complète sur le web
// (le chemin /email-signin est réservé au relay natif).
const _kWebContinuationUrl = 'https://productivitwo-app.web.app/';

class WebAuthScreen extends StatefulWidget {
  const WebAuthScreen({super.key});

  @override
  State<WebAuthScreen> createState() => _WebAuthScreenState();
}

class _WebAuthScreenState extends State<WebAuthScreen> {
  bool _loading = false;
  String? _error;
  bool _emailSent = false;

  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMagicLink() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Adresse email invalide');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: ActionCodeSettings(
          url: _kWebContinuationUrl,
          handleCodeInApp: true,
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kWebEmailPendingKey, email);
      if (mounted) setState(() => _emailSent = true);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Envoi impossible');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // ── Fond dégradé ─────────────────────────────────────────────────
          _GanttBackground(dark: dark),

          // ── Contenu centré ────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // ── Branding ────────────────────────────────────────────────
                _BrandingHeader(dark: dark),

                const Spacer(flex: 1),

                // ── Card de connexion ────────────────────────────────────────
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                            decoration: BoxDecoration(
                              color: dark
                                  ? Colors.white.withOpacity(0.10)
                                  : Colors.white.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: dark
                                    ? Colors.white.withOpacity(0.12)
                                    : Colors.white.withOpacity(0.6),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 8),
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
                                              fontSize: 12,
                                              color: cs.onErrorContainer)),
                                    ),
                                  ),

                                _EmailLoginTab(
                                  emailCtrl: _emailCtrl,
                                  loading: _loading,
                                  sent: _emailSent,
                                  onSubmit: _sendMagicLink,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                const Spacer(flex: 2),

                // ── Copyright ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    '© ${DateTime.now().year} Emeric Edmond · Productivitwo',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6BBFA3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fond animé Gantt ──────────────────────────────────────────────────────────

class _GanttBackground extends StatelessWidget {
  final bool dark;
  const _GanttBackground({required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF071510), Color(0xFF0D2A1E), Color(0xFF0A1E30)]
              : const [Color(0xFF0D2A1E), Color(0xFF1D9E75), Color(0xFF155F47)],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _GanttLinePainter(dark: dark),
      ),
    );
  }
}

class _GanttLinePainter extends CustomPainter {
  final bool dark;
  _GanttLinePainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(dark ? 0.04 : 0.08)
      ..strokeWidth = 1;

    // Lignes horizontales (style Gantt)
    const rowH = 44.0;
    for (double y = rowH; y < size.height; y += rowH) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Lignes verticales (colonnes semaines)
    const colW = 80.0;
    for (double x = colW; x < size.width; x += colW) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Barres de Gantt décoratives (fond)
    final barPaint = Paint()
      ..color = Colors.white.withOpacity(dark ? 0.05 : 0.1)
      ..style = PaintingStyle.fill;

    final bars = [
      (80.0, 2 * rowH,  240.0, rowH * 0.5),
      (240.0, 4 * rowH, 320.0, rowH * 0.5),
      (160.0, 6 * rowH, 400.0, rowH * 0.5),
      (80.0, 8 * rowH,  560.0, rowH * 0.5),
      (400.0, 3 * rowH, 160.0, rowH * 0.5),
      (320.0, 10 * rowH, 280.0, rowH * 0.5),
    ];

    for (final (x, y, w, h) in bars) {
      if (y + h < size.height && x + w < size.width) {
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y + rowH * 0.25, w, h),
          const Radius.circular(4),
        );
        canvas.drawRRect(rrect, barPaint);
      }
    }

    // Jalons (diamants)
    final milestonePaint = Paint()
      ..color = Colors.white.withOpacity(dark ? 0.08 : 0.15)
      ..style = PaintingStyle.fill;

    final milestones = [
      (560.0, 2 * rowH + rowH / 2),
      (400.0, 6 * rowH + rowH / 2),
      (640.0, 10 * rowH + rowH / 2),
    ];

    for (final (mx, my) in milestones) {
      if (mx < size.width && my < size.height) {
        final path = Path()
          ..moveTo(mx, my - 8)
          ..lineTo(mx + 8, my)
          ..lineTo(mx, my + 8)
          ..lineTo(mx - 8, my)
          ..close();
        canvas.drawPath(path, milestonePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_GanttLinePainter old) => old.dark != dark;
}

// ── Branding header ───────────────────────────────────────────────────────────

class _BrandingHeader extends StatelessWidget {
  final bool dark;
  const _BrandingHeader({required this.dark});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Logo
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(dark ? 0.12 : 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.account_tree_outlined,
            color: Colors.white,
            size: 36,
          ),
        ),
        const SizedBox(height: 16),
        // Wordmark
        const Text(
          'Productivitwo',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Color(0xFFE6F7F2), // blanc teinté teal, doux sur les yeux
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        // Tagline
        Text(
          'Gérez vos projets, pilotés par l\'IA',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF9FE1CB), // vert clair doux
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

// ── Onglet Email (magic link) ───────────────────────────────────────────────

class _EmailLoginTab extends StatelessWidget {
  final TextEditingController emailCtrl;
  final bool loading;
  final bool sent;
  final VoidCallback onSubmit;

  const _EmailLoginTab({
    required this.emailCtrl,
    required this.loading,
    required this.sent,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (sent) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mark_email_read_outlined, color: cs.primary, size: 40),
            const SizedBox(height: 16),
            Text(
              'Lien envoyé ! Ouvre ton email et clique sur le lien de connexion.',
              style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.75)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Reviens ensuite sur cet onglet — la connexion se finalisera automatiquement.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.45)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reçois un lien de connexion par email.\nPas de mot de passe à retenir.',
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.55)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Ton email',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => loading ? null : onSubmit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: loading ? null : onSubmit,
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 44)),
            child: loading
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Recevoir mon lien'),
          ),
        ],
      ),
    );
  }
}
