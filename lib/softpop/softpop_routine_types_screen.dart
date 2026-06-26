import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Écran « Types de routine » — détail des 3 façons de suivre une routine (preview).
///
/// Démonstration interactive et MOCK des 3 types (réf maquette
/// `01_design_produit`, sections COMPTEUR / BINAIRE / CHRONO) :
/// - **Compteur** : objectif quotidien (ex. 8 verres), boutons − / + ;
/// - **Binaire** : fait / pas fait, un tap valide ;
/// - **Chrono** : play/pause, le temps loggé « monte au domaine ».
class SoftPopRoutineTypesScreen extends StatefulWidget {
  const SoftPopRoutineTypesScreen({super.key});

  @override
  State<SoftPopRoutineTypesScreen> createState() =>
      _SoftPopRoutineTypesScreenState();
}

class _SoftPopRoutineTypesScreenState extends State<SoftPopRoutineTypesScreen> {
  // ── Compteur ───────────────────────────────────────────────────────────────
  static const int _waterTarget = 8;
  int _waterN = 3;
  bool get _waterDone => _waterN >= _waterTarget;

  // ── Binaire ────────────────────────────────────────────────────────────────
  bool _bedDone = false;

  // ── Chrono ─────────────────────────────────────────────────────────────────
  Timer? _timer;
  int _elapsed = 0; // secondes
  bool get _running => _timer != null;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleChrono() {
    setState(() {
      if (_running) {
        _timer!.cancel();
        _timer = null;
      } else {
        _timer = Timer.periodic(const Duration(seconds: 1),
            (_) => setState(() => _elapsed++));
      }
    });
  }

  void _toast(String msg, Color c) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: SoftPop.ui(color: Colors.white, weight: FontWeight.w600)),
        duration: const Duration(milliseconds: 1100),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SoftPop.rChip)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Types de routine')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            _typeLabel('Compteur', 'objectif quotidien', SoftPop.teal),
            const SizedBox(height: SoftPop.s8),
            _counterCard(),
            const SizedBox(height: SoftPop.s20),
            _typeLabel('Binaire', 'fait / pas fait', SoftPop.violet),
            const SizedBox(height: SoftPop.s8),
            _binaryCard(),
            const SizedBox(height: SoftPop.s20),
            _typeLabel(
                'Chrono', 'le temps loggé monte au domaine', SoftPop.amber),
            const SizedBox(height: SoftPop.s8),
            _chronoCard(),
          ],
        ),
      ),
    );
  }

  Widget _typeLabel(String t, String sub, Color c) => Padding(
        padding: const EdgeInsets.only(left: SoftPop.s4),
        child: Row(
          children: [
            Text(t.toUpperCase(),
                style: SoftPop.ui(
                    size: 11,
                    weight: FontWeight.w700,
                    color: c,
                    letterSpacing: .5)),
            const SizedBox(width: SoftPop.s8),
            Text(sub, style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
          ],
        ),
      );

  // Fil d'Ariane « 💪 Santé › Hydratation ».
  Widget _breadcrumb(String domain, String group, Color c) => Row(
        children: [
          Text(domain, style: SoftPop.ui(size: 11, weight: FontWeight.w600, color: c)),
          Text('  ›  ', style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
          Text(group, style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
        ],
      );

  // ── 1. Compteur ─────────────────────────────────────────────────────────────
  Widget _counterCard() => SoftCard(
        child: Column(
          children: [
            SizedBox(
              height: 132,
              width: 132,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(132, 132),
                    painter: _RingPainter(
                      progress: (_waterN / _waterTarget).clamp(0, 1).toDouble(),
                      color: SoftPop.teal,
                      track: SoftPop.tealSoft,
                    ),
                  ),
                  if (_waterDone)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('✓',
                            style: TextStyle(
                                fontSize: 34, color: SoftPop.teal)),
                        Text('Validé !',
                            style: SoftPop.ui(
                                size: 12,
                                weight: FontWeight.w600,
                                color: SoftPop.tealDark)),
                      ],
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$_waterN',
                            style: SoftPop.mono(
                                size: 40,
                                weight: FontWeight.w700,
                                color: SoftPop.ink)),
                        Text('/ $_waterTarget verres',
                            style: SoftPop.ui(
                                size: 11, color: SoftPop.inkMuted)),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: SoftPop.s16),
            _breadcrumb('💪 Santé', 'Hydratation', SoftPop.coralDark),
            const SizedBox(height: 2),
            Text("Boire de l'eau",
                style: SoftPop.ui(size: 17, weight: FontWeight.w700)),
            Text('objectif 8 verres · +15 XP',
                style: SoftPop.ui(size: 11, color: SoftPop.tealDark)),
            const SizedBox(height: SoftPop.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _roundBtn(Icons.remove, SoftPop.violetSoft, SoftPop.violet, () {
                  if (_waterN > 0) setState(() => _waterN--);
                }),
                const SizedBox(width: SoftPop.s24),
                _roundBtn(Icons.add, SoftPop.teal, Colors.white, () {
                  if (_waterN < _waterTarget) {
                    setState(() => _waterN++);
                    if (_waterDone) _toast('Objectif atteint · +15 XP 🎉', SoftPop.teal);
                  }
                }, big: true),
              ],
            ),
          ],
        ),
      );

  Widget _roundBtn(IconData icon, Color bg, Color fg, VoidCallback onTap,
          {bool big = false}) =>
      Material(
        color: bg,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: big ? 60 : 48,
            height: big ? 60 : 48,
            child: Icon(icon, color: fg, size: big ? 28 : 22),
          ),
        ),
      );

  // ── 2. Binaire ───────────────────────────────────────────────────────────────
  Widget _binaryCard() => SoftCard(
        onTap: () {
          setState(() => _bedDone = !_bedDone);
          if (_bedDone) _toast('+10 XP 🎉  ·  Faire mon lit', SoftPop.violet);
        },
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SoftPop.violetSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('🛏️', style: TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _breadcrumb('💪 Santé', 'Forme', SoftPop.coralDark),
                  Text('Faire mon lit',
                      style: SoftPop.ui(size: 15, weight: FontWeight.w700)),
                  Text('+10 XP à la validation',
                      style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _bedDone ? SoftPop.teal : Colors.transparent,
                border: _bedDone
                    ? null
                    : Border.all(
                        color: SoftPop.inkMuted.withValues(alpha: .4), width: 2),
              ),
              child: _bedDone
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : null,
            ),
          ],
        ),
      );

  // ── 3. Chrono ────────────────────────────────────────────────────────────────
  Widget _chronoCard() {
    final mm = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final ss = (_elapsed % 60).toString().padLeft(2, '0');
    return SoftCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SoftPop.amberSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('📖', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: SoftPop.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _breadcrumb('🧠 Esprit', 'Lecture', SoftPop.violetDark),
                    Text('Lire 20 min',
                        style: SoftPop.ui(size: 15, weight: FontWeight.w700)),
                    Text("le temps s'ajoute à l'activité",
                        style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SoftPop.s16),
          Row(
            children: [
              Text('$mm:$ss',
                  style: SoftPop.mono(
                      size: 30, weight: FontWeight.w700, color: SoftPop.ink)),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(SoftPop.rPill),
                  onTap: _toggleChrono,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: _running
                          ? null
                          : SoftPop.streakGradient,
                      color: _running ? SoftPop.amberSoft : null,
                      borderRadius: BorderRadius.circular(SoftPop.rPill),
                      boxShadow: _running
                          ? null
                          : SoftPop.coloredShadow(SoftPop.amber),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SoftPop.s20, vertical: SoftPop.s12),
                      child: Row(
                        children: [
                          Icon(_running ? Icons.pause : Icons.play_arrow,
                              size: 18,
                              color: _running ? SoftPop.amberDark : Colors.white),
                          const SizedBox(width: SoftPop.s4),
                          Text(_running ? 'Pause' : 'Démarrer',
                              style: SoftPop.ui(
                                  size: 14,
                                  weight: FontWeight.w600,
                                  color: _running
                                      ? SoftPop.amberDark
                                      : Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: SoftPop.s24),
          Row(
            children: [
              const Text('🧠', style: TextStyle(fontSize: 14)),
              const SizedBox(width: SoftPop.s8),
              Expanded(
                child: Text(
                    'Aujourd’hui : ${(_elapsed ~/ 60) + 12} min sur Esprit',
                    style:
                        SoftPop.ui(size: 11, color: SoftPop.inkSecondary)),
              ),
              Text('+1 niv. à 4h', style: SoftPop.mono(size: 10, color: SoftPop.inkMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Anneau de progression circulaire (compteur).
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color, track;
  _RingPainter(
      {required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 8;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(c, r, base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
