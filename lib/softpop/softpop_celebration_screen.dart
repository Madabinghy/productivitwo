import 'dart:math' as math;
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Écran « Célébration de jalon » (preview).
///
/// Réf : maquette `01_design_produit` (Jalon atteint / Célébration).
/// Confettis + récompenses (XP / 💎 / cosmétique) + saut de progression du
/// projet. Moment de fierté, chaleureux. Données mock.
class SoftPopCelebrationScreen extends StatefulWidget {
  const SoftPopCelebrationScreen({super.key});

  @override
  State<SoftPopCelebrationScreen> createState() =>
      _SoftPopCelebrationScreenState();
}

class _SoftPopCelebrationScreenState extends State<SoftPopCelebrationScreen> {
  late final ConfettiController _confetti =
      ConfettiController(duration: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    _confetti.play();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    SoftPop.s24, SoftPop.s24, SoftPop.s24, SoftPop.s32),
                child: Column(
                  children: [
                    const SizedBox(height: SoftPop.s24),
                    Text('JALON ATTEINT 🎉',
                        style: SoftPop.ui(
                            size: 14,
                            weight: FontWeight.w700,
                            color: SoftPop.violet,
                            letterSpacing: 1)),
                    const SizedBox(height: SoftPop.s24),
                    _pop(0, const PomoMascot(size: 110)),
                    const SizedBox(height: SoftPop.s20),
                    Text('4 accords ouverts',
                        textAlign: TextAlign.center,
                        style: SoftPop.ui(size: 24, weight: FontWeight.w700)),
                    Text('maîtrisés !',
                        textAlign: TextAlign.center,
                        style: SoftPop.ui(size: 24, weight: FontWeight.w700)),
                    const SizedBox(height: SoftPop.s8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SoftPop.s12, vertical: SoftPop.s4),
                      decoration: BoxDecoration(
                        color: SoftPop.violetSoft,
                        borderRadius: BorderRadius.circular(SoftPop.rPill),
                      ),
                      child: Text('🎸 Apprendre la guitare',
                          style: SoftPop.ui(
                              size: 12, color: SoftPop.violetDark)),
                    ),
                    const SizedBox(height: SoftPop.s24),
                    _rewards(),
                    const SizedBox(height: SoftPop.s20),
                    _progress(),
                    const SizedBox(height: SoftPop.s24),
                    SoftHeroButton(
                      label: 'Continuer',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            ),
            // Confettis depuis le haut.
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confetti,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.05,
                numberOfParticles: 18,
                maxBlastForce: 22,
                minBlastForce: 8,
                gravity: 0.25,
                colors: const [
                  SoftPop.violet,
                  SoftPop.coral,
                  SoftPop.teal,
                  SoftPop.amber,
                  SoftPop.pink,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Récompenses (pop-in décalé) ────────────────────────────────────────────
  Widget _rewards() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _pop(150, _rewardCard('✦', '+120', 'XP', SoftPop.violet)),
          const SizedBox(width: SoftPop.s12),
          _pop(300, _rewardCard('💎', '+15', 'gemmes', SoftPop.teal)),
          const SizedBox(width: SoftPop.s12),
          _pop(450, _rewardCard('🎨', '1', 'cosmétique', SoftPop.amber)),
        ],
      );

  Widget _rewardCard(String emoji, String value, String label, Color c) =>
      Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: SoftPop.s16),
        decoration: BoxDecoration(
          color: SoftPop.card,
          borderRadius: BorderRadius.circular(SoftPop.rCard),
          boxShadow: SoftPop.coloredShadow(c),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: SoftPop.s8),
            Text(value, style: SoftPop.mono(size: 18, color: c)),
            Text(label, style: SoftPop.ui(size: 11, color: SoftPop.inkSecondary)),
          ],
        ),
      );

  // ── Progression du projet (anime 50% → 62%) ────────────────────────────────
  Widget _progress() => SoftCard(
        radius: SoftPop.rCardSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Progression du projet',
                    style: SoftPop.ui(size: 13, weight: FontWeight.w600)),
                Text('50% → 62%',
                    style: SoftPop.mono(size: 12, color: SoftPop.tealDark)),
              ],
            ),
            const SizedBox(height: SoftPop.s8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.50, end: 0.62),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => SoftXpBar(value: v),
            ),
          ],
        ),
      );

  // Animation pop-in (scale + fade) décalée de [delayMs].
  Widget _pop(int delayMs, Widget child) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 400 + delayMs),
        curve: Curves.elasticOut,
        builder: (_, v, c) => Opacity(
          opacity: v.clamp(0, 1).toDouble(),
          child: Transform.scale(scale: 0.6 + 0.4 * math.min(v, 1.2), child: c),
        ),
      );
}
