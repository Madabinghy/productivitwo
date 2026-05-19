import 'dart:convert';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const _kCustomTokenUrl = 'https://getcustomtoken-dzos75b65q-uc.a.run.app';

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

  Future<void> _signInWithIosToken() async {
    final uid   = _uidCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (uid.isEmpty || token.isEmpty) {
      setState(() => _error = 'UID et token requis');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
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
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: dark
                                  ? Colors.white.withOpacity(0.07)
                                  : Colors.white.withOpacity(0.88),
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
                                // Tabs
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                  child: TabBar(
                                    controller: _tabs,
                                    dividerColor: Colors.transparent,
                                    indicatorColor: cs.primary,
                                    tabs: const [
                                      Tab(text: 'Compte iOS'),
                                      Tab(text: 'Nouveau compte'),
                                    ],
                                  ),
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
                                              fontSize: 12,
                                              color: cs.onErrorContainer)),
                                    ),
                                  ),

                                SizedBox(
                                  height: 230,
                                  child: TabBarView(
                                    controller: _tabs,
                                    children: [
                                      // ── Onglet iOS ──────────────────────
                                      _IosLoginTab(
                                        uidCtrl: _uidCtrl,
                                        tokenCtrl: _tokenCtrl,
                                        loading: _loading,
                                        onSubmit: _signInWithIosToken,
                                      ),

                                      // ── Onglet Google ───────────────────
                                      _GoogleLoginTab(
                                        loading: _loading,
                                        onSubmit: _signInWithGoogle,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
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

// ── Onglet iOS ────────────────────────────────────────────────────────────────

class _IosLoginTab extends StatelessWidget {
  final TextEditingController uidCtrl;
  final TextEditingController tokenCtrl;
  final bool loading;
  final VoidCallback onSubmit;

  const _IosLoginTab({
    required this.uidCtrl,
    required this.tokenCtrl,
    required this.loading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'iOS → menu ⋮ → Tokens API → copie UID + token',
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: uidCtrl,
            decoration: const InputDecoration(
              labelText: 'UID iOS',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: tokenCtrl,
            decoration: InputDecoration(
              labelText: 'Token',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste_outlined, size: 16),
                onPressed: () async {
                  final d = await Clipboard.getData('text/plain');
                  if (d?.text != null) tokenCtrl.text = d!.text!;
                },
              ),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: loading ? null : onSubmit,
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 44)),
            child: loading
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Connecter mon compte iOS'),
          ),
        ],
      ),
    );
  }
}

// ── Onglet Google ─────────────────────────────────────────────────────────────

class _GoogleLoginTab extends StatelessWidget {
  final bool loading;
  final VoidCallback onSubmit;

  const _GoogleLoginTab({required this.loading, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tu découvres Productivitwo sur le web,\nou tu utilises Android.',
            style: TextStyle(
                fontSize: 13, color: cs.onSurface.withOpacity(0.55)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: loading ? null : onSubmit,
            icon: loading
                ? SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.onPrimary))
                : const Icon(Icons.login_outlined, size: 18),
            label: Text(loading ? 'Connexion…' : 'Continuer avec Google'),
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48)),
          ),
        ],
      ),
    );
  }
}
