import 'package:flutter/material.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';
import 'softpop_home_screen.dart';
import 'softpop_routine_types_screen.dart';
import 'softpop_streak_screen.dart';
import 'softpop_balance_screen.dart';
import 'softpop_project_screen.dart';
import 'softpop_celebration_screen.dart';
import 'softpop_onboarding_screen.dart';
import 'softpop_focus_screen.dart';
import 'softpop_lair_screen.dart';

/// Galerie du design system « Soft Pop ».
///
/// Écran de validation visuelle (palette, typo, composants) AVANT de refondre
/// les vrais écrans par-dessus. Accessible via Paramètres → « Aperçu Soft Pop ».
/// Applique [softPopTheme] localement → n'affecte pas le reste de l'app.
class SoftPopPreviewScreen extends StatefulWidget {
  const SoftPopPreviewScreen({super.key});

  @override
  State<SoftPopPreviewScreen> createState() => _SoftPopPreviewScreenState();
}

class _SoftPopPreviewScreenState extends State<SoftPopPreviewScreen> {
  int _routineType = 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Aperçu Soft Pop')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            _heroHeader(),
            const SizedBox(height: SoftPop.s16),
            SoftHeroButton(
              label: 'Voir l’écran Accueil',
              icon: Icons.home_outlined,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const SoftPopHomeScreen()),
              ),
            ),
            const SizedBox(height: SoftPop.s8),
            Wrap(
              spacing: SoftPop.s8,
              runSpacing: SoftPop.s8,
              children: [
                SoftPill(
                  label: 'Onboarding',
                  icon: Icons.waving_hand_outlined,
                  accent: SoftPop.violet,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SoftPopOnboardingScreen()),
                  ),
                ),
                SoftPill(
                  label: 'Maintenant / Focus',
                  icon: Icons.play_circle_outline,
                  accent: SoftPop.teal,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SoftPopFocusScreen()),
                  ),
                ),
                SoftPill(
                  label: 'Le Repaire (jeu)',
                  icon: Icons.castle_outlined,
                  accent: SoftPop.coral,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SoftPopLairScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SoftPop.s8),
            Wrap(
              spacing: SoftPop.s8,
              runSpacing: SoftPop.s8,
              children: [
                SoftPill(
                  label: 'Types de routine',
                  icon: Icons.tune,
                  accent: SoftPop.teal,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SoftPopRoutineTypesScreen()),
                  ),
                ),
                SoftPill(
                  label: 'Série',
                  icon: Icons.local_fire_department,
                  accent: SoftPop.coral,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SoftPopStreakScreen()),
                  ),
                ),
                SoftPill(
                  label: 'Équilibre',
                  icon: Icons.donut_large,
                  accent: SoftPop.amber,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SoftPopBalanceScreen()),
                  ),
                ),
                SoftPill(
                  label: 'Projet à jalons',
                  icon: Icons.flag_outlined,
                  accent: SoftPop.pink,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SoftPopProjectScreen()),
                  ),
                ),
                SoftPill(
                  label: 'Célébration',
                  icon: Icons.celebration_outlined,
                  accent: SoftPop.violet,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SoftPopCelebrationScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SoftPop.s20),
            _section('Couleurs'),
            _swatches(),
            const SizedBox(height: SoftPop.s20),
            _section('Typographie'),
            _typography(),
            const SizedBox(height: SoftPop.s20),
            _section('Boutons & pills'),
            _buttons(),
            const SizedBox(height: SoftPop.s20),
            _section('Progression & stats'),
            _progress(),
            const SizedBox(height: SoftPop.s20),
            _section('Domaines de vie'),
            _domains(),
          ],
        ),
      ),
    );
  }

  // ── En-tête héros + mascotte ──────────────────────────────────────────────
  Widget _heroHeader() => SoftCard(
        gradient: SoftPop.heroGradient,
        padding: const EdgeInsets.all(SoftPop.s20),
        child: Row(
          children: [
            const PomoMascot(size: 56),
            const SizedBox(width: SoftPop.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Salut 👋',
                      style: SoftPop.ui(
                          size: 14, color: Colors.white.withValues(alpha: .85))),
                  const SizedBox(height: 2),
                  Text('Prêt pour aujourd’hui ?',
                      style: SoftPop.ui(
                          size: 20,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            ),
            Column(
              children: [
                Text('Niv. 7',
                    style: SoftPop.mono(
                        size: 16, color: Colors.white, weight: FontWeight.w700)),
                Text('✦ 1 240',
                    style: SoftPop.mono(
                        size: 12,
                        color: Colors.white.withValues(alpha: .85),
                        weight: FontWeight.w400)),
              ],
            ),
          ],
        ),
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: SoftPop.s12, left: SoftPop.s4),
        child: Text(t, style: SoftPop.ui(size: 13, weight: FontWeight.w700, color: SoftPop.inkSecondary)),
      );

  Widget _swatches() {
    final items = <(String, Color)>[
      ('Violet', SoftPop.violet),
      ('Corail', SoftPop.coral),
      ('Teal', SoftPop.teal),
      ('Ambre', SoftPop.amber),
      ('Rose', SoftPop.pink),
      ('Encre', SoftPop.ink),
    ];
    return Wrap(
      spacing: SoftPop.s12,
      runSpacing: SoftPop.s12,
      children: [
        for (final (name, c) in items)
          Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(SoftPop.rChip),
                  boxShadow: SoftPop.coloredShadow(c),
                ),
              ),
              const SizedBox(height: SoftPop.s4),
              Text(name, style: SoftPop.ui(size: 11, color: SoftPop.inkSecondary)),
            ],
          ),
      ],
    );
  }

  Widget _typography() => SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fredoka — titre', style: SoftPop.ui(size: 22, weight: FontWeight.w700)),
            const SizedBox(height: SoftPop.s4),
            Text('Fredoka — corps de texte régulier, lisible et chaleureux.',
                style: SoftPop.ui(size: 15, color: SoftPop.inkSecondary)),
            const Divider(height: SoftPop.s24),
            Row(
              children: [
                Text('Space Mono : ', style: SoftPop.ui(size: 14)),
                Text('12:45  ⚡124  💎88  92%',
                    style: SoftPop.mono(size: 16, color: SoftPop.violet)),
              ],
            ),
          ],
        ),
      );

  Widget _buttons() => SoftCard(
        child: Column(
          children: [
            SoftHeroButton(label: 'Commencer ma journée', icon: Icons.bolt, onPressed: () {}),
            const SizedBox(height: SoftPop.s12),
            Wrap(
              spacing: SoftPop.s8,
              runSpacing: SoftPop.s8,
              children: const [
                SoftPill(label: 'Santé', icon: Icons.favorite, accent: SoftPop.teal, selected: true),
                SoftPill(label: 'Travail', icon: Icons.work_outline, accent: SoftPop.violet),
                SoftPill(label: 'Social', icon: Icons.people_outline, accent: SoftPop.pink),
              ],
            ),
          ],
        ),
      );

  Widget _progress() => SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Niveau 7 — Esprit',
                style: SoftPop.ui(size: 15, weight: FontWeight.w600)),
            const SizedBox(height: SoftPop.s8),
            const SoftXpBar(value: 0.62),
            const SizedBox(height: SoftPop.s4),
            Text('1 240 / 2 000 ✦',
                style: SoftPop.mono(size: 12, color: SoftPop.inkMuted)),
            const Divider(height: SoftPop.s24),
            const SoftXpBar(value: 0.8, gradient: SoftPop.streakGradient),
            const SizedBox(height: SoftPop.s12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                SoftStat(value: '12', label: 'Série', accent: SoftPop.coral, emoji: '🔥'),
                SoftStat(value: '124', label: 'Énergie', accent: SoftPop.amber, emoji: '⚡'),
                SoftStat(value: '88', label: 'Gemmes', accent: SoftPop.teal, emoji: '💎'),
              ],
            ),
          ],
        ),
      );

  Widget _domains() {
    final demo = <(String, String, Color)>[
      ('Santé', 'Niv. 5', SoftPop.teal),
      ('Travail', 'Niv. 8', SoftPop.violet),
      ('Apprentissage', 'Niv. 3', SoftPop.amber),
      ('Maison', 'Niv. 4', SoftPop.coral),
      ('Social', 'Niv. 6', SoftPop.pink),
    ];
    // Sélecteur de type de routine (compteur / binaire / chrono) — démo d'état.
    const types = ['Compteur', 'Binaire', 'Chrono'];
    return Column(
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type de routine', style: SoftPop.ui(size: 15, weight: FontWeight.w600)),
              const SizedBox(height: SoftPop.s12),
              Wrap(
                spacing: SoftPop.s8,
                children: [
                  for (var i = 0; i < types.length; i++)
                    SoftPill(
                      label: types[i],
                      accent: SoftPop.violet,
                      selected: _routineType == i,
                      onTap: () => setState(() => _routineType = i),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: SoftPop.s12),
        for (final (name, lvl, c) in demo) ...[
          SoftCard(
            padding: const EdgeInsets.all(SoftPop.s12),
            onTap: () {},
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(SoftPop.rChip),
                  ),
                  child: Icon(Icons.circle, color: c, size: 18),
                ),
                const SizedBox(width: SoftPop.s12),
                Expanded(
                    child: Text(name,
                        style: SoftPop.ui(size: 15, weight: FontWeight.w600))),
                Text(lvl, style: SoftPop.mono(size: 13, color: c)),
              ],
            ),
          ),
          const SizedBox(height: SoftPop.s8),
        ],
      ],
    );
  }
}
