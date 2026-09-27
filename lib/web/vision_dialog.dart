import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/web/desktop_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// Vision (première session / session mensuelle Pro), ex-carte de Focus.
/// Ouverte depuis le menu ⋯ depuis la refonte web 2026-09.
void showVisionDialog(BuildContext context) =>
    showDesktopDialog(context, maxWidth: 440, builder: (_) => const VisionPanel());

class VisionPanel extends StatefulWidget {
  const VisionPanel({super.key});
  @override
  State<VisionPanel> createState() => _VisionPanelState();
}

class _VisionPanelState extends State<VisionPanel> {
  static const _visionApi = 'https://getvisionaccess-dzos75b65q-uc.a.run.app';

  bool _loading = true;
  bool _isPro = false;
  bool _available = false;
  bool _onboardingDone = false;
  DateTime? _nextAvailableAt;
  String? _accessUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() { _loading = false; });
        return;
      }
      final idToken = await user.getIdToken();
      final res = await http.post(
        Uri.parse(_visionApi),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() { _loading = false; });
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _loading = false;
        _isPro = body['isPro'] == true;
        _available = body['available'] == true;
        _onboardingDone = body['onboardingDone'] == true;
        _accessUrl = body['accessUrl'] as String?;
        final nextStr = body['nextAvailableAt'] as String?;
        _nextAvailableAt = nextStr != null ? DateTime.tryParse(nextStr) : null;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  void _openVision() {
    final url = _accessUrl;
    if (url == null) return;
    html.window.open(url, '_blank');
  }

  String _daysUntilNext() {
    if (_nextAvailableAt == null) return '';
    final diff = _nextAvailableAt!.difference(DateTime.now());
    if (diff.isNegative) return 'maintenant';
    final days = diff.inDays;
    if (days == 0) return 'aujourd\'hui';
    if (days == 1) return 'demain';
    return 'dans $days jours';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const gold = Color(0xFFC9A84C);

    return Container(
      color: kBSurface,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Row(children: [
          Icon(Icons.auto_awesome_outlined, size: 16, color: gold),
          SizedBox(width: 8),
          Text('Vision', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: gold)),
        ]),
        const SizedBox(height: 14),
        _loading
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.onSurface.withOpacity(.3))),
                const SizedBox(width: 8),
                Text('Chargement…', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.4))),
              ]),
            )
          : !_onboardingDone
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configure Productivitwo en discutant avec ton guide, à ton rythme — ta progression est sauvegardée. Domaines, activités et premier plan créés pour toi.',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.6), height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    if (_accessUrl != null)
                      InkWell(
                        onTap: _openVision,
                        child: Row(children: [
                          Icon(Icons.auto_awesome_outlined, size: 14, color: gold),
                          const SizedBox(width: 6),
                          Text('Commencer ma première session', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: gold)),
                        ]),
                      ),
                  ],
                )
              : !_isPro
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fais évoluer ta vision chaque mois (~20 min) avec Productivitwo Pro.',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.6), height: 1.5),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => html.window.open('https://app.productivitwo.com', '_blank'),
                          child: Row(children: [
                            Icon(Icons.workspace_premium_outlined, size: 14, color: gold),
                            const SizedBox(width: 6),
                            Text('Passer en Pro', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: gold)),
                          ]),
                        ),
                      ],
                    )
                  : _available
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ta session mensuelle est disponible.',
                              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.65), height: 1.5),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _openVision,
                                icon: const Icon(Icons.auto_awesome, size: 14),
                                label: const Text('Démarrer ma Vision', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: gold,
                                  foregroundColor: Colors.black87,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.schedule, size: 13, color: cs.onSurface.withOpacity(.4)),
                              const SizedBox(width: 6),
                              Text(
                                'Prochaine vision ${_daysUntilNext()}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(.6)),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Text(
                              'Une session par mois pour faire évoluer ta vision.',
                              style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.4), height: 1.5),
                            ),
                          ],
                        ),
      ]),
    );
  }
}
