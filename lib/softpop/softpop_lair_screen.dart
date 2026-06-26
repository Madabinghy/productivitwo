import 'package:flutter/material.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Ami raidable (mock).
class _Friend {
  final String name, emoji;
  final Color color, bg;
  final int defense, lvl;
  const _Friend(this.name, this.emoji, this.color, this.bg, this.defense,
      this.lvl);
}

const _friends = [
  _Friend('Sarah', '🦊', SoftPop.coral, SoftPop.coralSoft, 240, 8),
  _Friend('Tom', '🐼', SoftPop.violet, SoftPop.violetSoft, 180, 6),
  _Friend('Mia', '🐯', SoftPop.amber, SoftPop.amberSoft, 300, 9),
];

/// Écran « Le Repaire » — hub de la couche jeu (preview).
///
/// Réf : maquette `01_design_produit` (Minijeu · Base) + handoff `02_couche_jeu`
/// (boucle 24 h, monnaies ✦/⚡/💎, raid asynchrone, ligue). Point d'entrée du
/// jeu : la productivité alimente l'énergie ⚡, qu'on dépense pour raider un ami.
/// Données mock — non punitif, jamais en temps réel.
class SoftPopLairScreen extends StatelessWidget {
  const SoftPopLairScreen({super.key});

  // Énergie du jour = round(standardPct × (1 + bonus_série)). Ex : 100 % × 1.24.
  static const int _energy = 124;
  static const int _streakBonusPct = 24;
  static const int _xp = 1240;
  static const int _gems = 340;
  static const int _lairLevel = 3;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Ton Repaire')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            _currencies(),
            const SizedBox(height: SoftPop.s12),
            _lairScene(),
            const SizedBox(height: SoftPop.s12),
            _morningResolution(),
            const SizedBox(height: SoftPop.s12),
            _energyCard(),
            const SizedBox(height: SoftPop.s20),
            Text('Attaquer un ami',
                style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: SoftPop.s4),
            Text('Dépense ton énergie pour piller un repaire (en asynchrone).',
                style: SoftPop.ui(size: 12, color: SoftPop.inkSecondary)),
            const SizedBox(height: SoftPop.s12),
            for (final f in _friends) _friendTile(context, f),
            const SizedBox(height: SoftPop.s12),
            _leagueCard(),
          ],
        ),
      ),
    );
  }

  // ── 3 monnaies ──────────────────────────────────────────────────────────────
  Widget _currencies() => Row(
        children: [
          Expanded(child: _coin('✦', '$_xp', 'XP', SoftPop.violet)),
          const SizedBox(width: SoftPop.s8),
          Expanded(child: _coin('⚡', '$_energy', 'énergie', SoftPop.amber)),
          const SizedBox(width: SoftPop.s8),
          Expanded(child: _coin('💎', '$_gems', 'gemmes', SoftPop.teal)),
        ],
      );

  Widget _coin(String emoji, String value, String label, Color c) => SoftCard(
        radius: SoftPop.rChip,
        padding: const EdgeInsets.symmetric(vertical: SoftPop.s12),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: SoftPop.s4),
            Text(value, style: SoftPop.mono(size: 16, color: c)),
            Text(label, style: SoftPop.ui(size: 10, color: SoftPop.inkMuted)),
          ],
        ),
      );

  // ── Scène du repaire (illustration stylisée) ────────────────────────────────
  Widget _lairScene() => ClipRRect(
        borderRadius: BorderRadius.circular(SoftPop.rCard),
        child: Container(
          height: 180,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEAE4FF), Color(0xFFFDEAE6)],
            ),
          ),
          child: Stack(
            children: [
              const Positioned(
                  top: 18, left: 24, child: Text('☁️', style: TextStyle(fontSize: 26))),
              const Positioned(
                  top: 34, right: 30, child: Text('☁️', style: TextStyle(fontSize: 20))),
              // Sol.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Color(0xFFCDEFD8),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                  ),
                ),
              ),
              // Repaire.
              const Align(
                alignment: Alignment(0, 0.35),
                child: Text('🏰', style: TextStyle(fontSize: 64)),
              ),
              const Align(
                alignment: Alignment(-0.55, 0.55),
                child: Text('🗼', style: TextStyle(fontSize: 30)),
              ),
              const Align(
                alignment: Alignment(0.55, 0.55),
                child: Text('🗼', style: TextStyle(fontSize: 30)),
              ),
              // Badge niveau.
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SoftPop.s12, vertical: SoftPop.s4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .85),
                    borderRadius: BorderRadius.circular(SoftPop.rPill),
                  ),
                  child: Text('Repaire · Niv. $_lairLevel',
                      style: SoftPop.ui(
                          size: 12,
                          weight: FontWeight.w700,
                          color: SoftPop.violetDark)),
                ),
              ),
            ],
          ),
        ),
      );

  // ── Résolution du matin (calme, non punitif) ────────────────────────────────
  Widget _morningResolution() => Container(
        padding: const EdgeInsets.all(SoftPop.s12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [SoftPop.tealSoft, SoftPop.violetSoft],
          ),
          borderRadius: BorderRadius.circular(SoftPop.rCardSm),
        ),
        child: Row(
          children: [
            const Text('🌅', style: TextStyle(fontSize: 22)),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Résolution du matin',
                      style: SoftPop.ui(
                          size: 13,
                          weight: FontWeight.w700,
                          color: SoftPop.tealDark)),
                  Text('Ta défense a tenu cette nuit. Butin : +15 💎 · Ligue ↑',
                      style: SoftPop.ui(
                          size: 12, color: SoftPop.inkSecondary, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Énergie du jour ─────────────────────────────────────────────────────────
  Widget _energyCard() => SoftCard(
        radius: SoftPop.rCardSm,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: SoftPop.streakGradient,
                shape: BoxShape.circle,
                boxShadow: SoftPop.coloredShadow(SoftPop.amber),
              ),
              child: const Text('⚡', style: TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('$_energy ⚡',
                          style:
                              SoftPop.mono(size: 22, color: SoftPop.amberDark)),
                      const SizedBox(width: SoftPop.s8),
                      Text('disponible aujourd’hui',
                          style: SoftPop.ui(
                              size: 12, color: SoftPop.inkSecondary)),
                    ],
                  ),
                  Text(
                      '100 % de ton standard × série (+$_streakBonusPct %). Gagnée par tes routines & jalons.',
                      style: SoftPop.ui(
                          size: 11, color: SoftPop.inkMuted, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Ami raidable ────────────────────────────────────────────────────────────
  Widget _friendTile(BuildContext context, _Friend f) => Padding(
        padding: const EdgeInsets.only(bottom: SoftPop.s8),
        child: SoftCard(
          padding: const EdgeInsets.all(SoftPop.s12),
          radius: SoftPop.rCardSm,
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: f.bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(f.emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: SoftPop.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.name,
                        style: SoftPop.ui(size: 15, weight: FontWeight.w700)),
                    Text('Niv. ${f.lvl} · 🛡 ${f.defense} défense',
                        style:
                            SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
                  ],
                ),
              ),
              _raidButton(context, f),
            ],
          ),
        ),
      );

  Widget _raidButton(BuildContext context, _Friend f) {
    final canRaid = _energy >= 60;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(SoftPop.rPill),
        onTap: () {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text(
                  canRaid
                      ? 'Raid sur ${f.name} → Constructeur de stratégie (à venir)'
                      : 'Énergie trop basse. Fais des routines pour recharger.',
                  style: SoftPop.ui(
                      color: Colors.white, weight: FontWeight.w600)),
              backgroundColor: canRaid ? SoftPop.violet : SoftPop.inkSecondary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SoftPop.rChip)),
            ));
        },
        child: Ink(
          decoration: BoxDecoration(
            gradient: canRaid ? SoftPop.heroGradient : null,
            color: canRaid ? null : SoftPop.violetSoft,
            borderRadius: BorderRadius.circular(SoftPop.rPill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: SoftPop.s16, vertical: SoftPop.s8),
            child: Text('⚔️ Raid',
                style: SoftPop.ui(
                    size: 13,
                    weight: FontWeight.w700,
                    color: canRaid ? Colors.white : SoftPop.inkMuted)),
          ),
        ),
      ),
    );
  }

  // ── Ligue hebdo ─────────────────────────────────────────────────────────────
  Widget _leagueCard() => SoftCard(
        radius: SoftPop.rCardSm,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SoftPop.amberSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('🏆', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ligue Argent · 3ᵉ',
                      style: SoftPop.ui(size: 15, weight: FontWeight.w700)),
                  Text('Plus que 40 💎 pour passer Or. Fin dans 3 j.',
                      style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
                ],
              ),
            ),
            Text('↑2', style: SoftPop.mono(size: 16, color: SoftPop.tealDark)),
          ],
        ),
      );
}
