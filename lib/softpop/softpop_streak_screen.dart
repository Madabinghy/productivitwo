import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Écran « Série » (streaks) — moteur d'engagement, jamais punitif (preview).
///
/// Réf : maquette `01_design_produit` (écran Série) + couche jeu
/// `02_couche_jeu` (§4.4) :
/// - seuil indulgent : une journée ≥ 60 % du standard maintient la série ;
/// - multiplicateur d'énergie : +2 %/jour, plafonné à +30 % ;
/// - boucliers de répit : 1 tous les 7 j (max 2), absorbe un jour manqué ;
/// - repli doux : sans bouclier, la série recule de 3 j (jamais à zéro).
/// Le simulateur en bas illustre ces règles en direct (données mock).
class SoftPopStreakScreen extends StatefulWidget {
  const SoftPopStreakScreen({super.key});

  @override
  State<SoftPopStreakScreen> createState() => _SoftPopStreakScreenState();
}

class _SoftPopStreakScreenState extends State<SoftPopStreakScreen> {
  int _streak = 12;
  int _shields = 1; // boucliers de répit (max 2)

  int get _multPct => math.min(_streak, 15) * 2; // +2 %/j, plafond +30 %

  void _toast(String msg, Color c, {String emoji = ''}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('$emoji  $msg'.trim(),
            style: SoftPop.ui(color: Colors.white, weight: FontWeight.w600)),
        duration: const Duration(milliseconds: 1300),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SoftPop.rChip)),
      ));
  }

  void _success() {
    setState(() {
      _streak++;
      if (_streak % 7 == 0 && _shields < 2) {
        _shields++;
        _toast('Jour réussi · bouclier gagné 🛡️', SoftPop.amber, emoji: '🔥');
        return;
      }
    });
    if (_streak % 7 != 0) {
      _toast('Jour réussi · série +1', SoftPop.amber, emoji: '🔥');
    }
  }

  void _miss() {
    setState(() {
      if (_shields > 0) {
        _shields--;
        _toast('Bouclier utilisé · série préservée', SoftPop.teal, emoji: '🛡️');
      } else {
        _streak = math.max(0, _streak - 3);
        _toast('Repli doux (−3 j) · jamais à zéro', SoftPop.violet, emoji: '💛');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Ta série')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            _flameHero(),
            const SizedBox(height: SoftPop.s12),
            _weekStrip(),
            const SizedBox(height: SoftPop.s12),
            _statsRow(),
            const SizedBox(height: SoftPop.s20),
            Text('Comment ça marche',
                style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: SoftPop.s8),
            _rules(),
            const SizedBox(height: SoftPop.s20),
            Text('Paliers',
                style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: SoftPop.s8),
            _milestones(),
            const SizedBox(height: SoftPop.s20),
            _simulator(),
          ],
        ),
      ),
    );
  }

  // ── Héros flamme + mascotte ────────────────────────────────────────────────
  Widget _flameHero() => SoftCard(
        gradient: SoftPop.streakGradient,
        padding: const EdgeInsets.symmetric(
            vertical: SoftPop.s24, horizontal: SoftPop.s16),
        child: Column(
          children: [
            const PomoMascot(size: 48),
            const SizedBox(height: SoftPop.s8),
            Text('Pomo est fier de toi',
                style: SoftPop.ui(
                    size: 13, color: Colors.white.withValues(alpha: .9))),
            const SizedBox(height: SoftPop.s8),
            const Text('🔥', style: TextStyle(fontSize: 40)),
            Text('$_streak',
                style: SoftPop.mono(
                    size: 52, weight: FontWeight.w700, color: Colors.white)),
            Text('jours de série',
                style: SoftPop.ui(
                    size: 14, color: Colors.white.withValues(alpha: .9))),
          ],
        ),
      );

  // ── Semaine : ✓ passés · 🔥 aujourd'hui · vide à venir ─────────────────────
  Widget _weekStrip() {
    const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    const todayIdx = 4; // vendredi (mock)
    return SoftCard(
      radius: SoftPop.rCardSm,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 7; i++)
            Column(
              children: [
                Text(days[i],
                    style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
                const SizedBox(height: SoftPop.s8),
                _dayCell(i, todayIdx),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(int i, int todayIdx) {
    if (i < todayIdx) {
      return Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration:
            const BoxDecoration(color: SoftPop.teal, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 16, color: Colors.white),
      );
    }
    if (i == todayIdx) {
      return Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: SoftPop.streakGradient,
          shape: BoxShape.circle,
          boxShadow: SoftPop.coloredShadow(SoftPop.coral),
        ),
        child: const Text('🔥', style: TextStyle(fontSize: 15)),
      );
    }
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border:
            Border.all(color: SoftPop.inkMuted.withValues(alpha: .25), width: 2),
      ),
    );
  }

  // ── Multiplicateur + boucliers ─────────────────────────────────────────────
  Widget _statsRow() => Row(
        children: [
          Expanded(
            child: SoftCard(
              radius: SoftPop.rCardSm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('⚡', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: SoftPop.s4),
                    Text('+$_multPct%',
                        style: SoftPop.mono(size: 20, color: SoftPop.amberDark)),
                  ]),
                  const SizedBox(height: 2),
                  Text('multiplicateur d’énergie',
                      style: SoftPop.ui(size: 11, color: SoftPop.inkSecondary)),
                  Text('plafond +30 %',
                      style: SoftPop.ui(size: 9, color: SoftPop.inkMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(width: SoftPop.s8),
          Expanded(
            child: SoftCard(
              radius: SoftPop.rCardSm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    for (var i = 0; i < 2; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Opacity(
                          opacity: i < _shields ? 1 : .25,
                          child: const Text('🛡️',
                              style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    const SizedBox(width: SoftPop.s4),
                    Text('$_shields/2',
                        style: SoftPop.mono(size: 16, color: SoftPop.tealDark)),
                  ]),
                  const SizedBox(height: 2),
                  Text('boucliers de répit',
                      style: SoftPop.ui(size: 11, color: SoftPop.inkSecondary)),
                  Text('absorbe un jour manqué',
                      style: SoftPop.ui(size: 9, color: SoftPop.inkMuted)),
                ],
              ),
            ),
          ),
        ],
      );

  // ── Règles (non punitif) ───────────────────────────────────────────────────
  Widget _rules() => Column(
        children: [
          _ruleTile('💛', 'Jamais punitif',
              'Une journée à ≥ 60 % de ton standard maintient la série. Pas besoin de tout faire.'),
          const SizedBox(height: SoftPop.s8),
          _ruleTile('🛡️', 'Boucliers de répit',
              '1 bouclier gagné tous les 7 jours (max 2). Un jour manqué en consomme un, la série est préservée.'),
          const SizedBox(height: SoftPop.s8),
          _ruleTile('📉', 'Repli doux',
              'Sans bouclier, la série recule de 3 jours seulement — elle ne retombe jamais à zéro brutalement.'),
        ],
      );

  Widget _ruleTile(String emoji, String title, String body) => SoftCard(
        padding: const EdgeInsets.all(SoftPop.s12),
        radius: SoftPop.rCardSm,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: SoftPop.ui(size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: SoftPop.ui(
                          size: 12, color: SoftPop.inkSecondary, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Paliers (cosmétiques, non-puissance) ───────────────────────────────────
  Widget _milestones() {
    final items = <(int, String, String)>[
      (7, '🛡️', 'Bouclier'),
      (15, '⚡', 'Multi max'),
      (30, '✨', 'Tourelles dorées'),
      (60, '👑', 'Prestige'),
    ];
    return Wrap(
      spacing: SoftPop.s8,
      runSpacing: SoftPop.s8,
      children: [
        for (final (days, emoji, label) in items)
          _milestoneChip(days, emoji, label, _streak >= days),
      ],
    );
  }

  Widget _milestoneChip(int days, String emoji, String label, bool reached) =>
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SoftPop.s12, vertical: SoftPop.s8),
        decoration: BoxDecoration(
          color: reached ? SoftPop.amberSoft : SoftPop.card,
          borderRadius: BorderRadius.circular(SoftPop.rPill),
          border: Border.all(
            color: reached
                ? SoftPop.amber
                : SoftPop.inkMuted.withValues(alpha: .25),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: SoftPop.s4),
            Text('$days j',
                style: SoftPop.mono(
                    size: 11,
                    color: reached ? SoftPop.amberDark : SoftPop.inkMuted)),
            const SizedBox(width: SoftPop.s4),
            Text(label,
                style: SoftPop.ui(
                    size: 11,
                    weight: FontWeight.w600,
                    color: reached ? SoftPop.ink : SoftPop.inkMuted)),
            if (reached) ...[
              const SizedBox(width: SoftPop.s4),
              const Icon(Icons.check_circle, size: 13, color: SoftPop.amberDark),
            ],
          ],
        ),
      );

  // ── Simulateur (montre les règles en direct) ───────────────────────────────
  Widget _simulator() => SoftCard(
        radius: SoftPop.rCardSm,
        color: SoftPop.violetSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Simuler une journée',
                style: SoftPop.ui(size: 14, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Pour voir comment la série réagit (jamais de chute brutale).',
                style: SoftPop.ui(size: 11, color: SoftPop.inkSecondary)),
            const SizedBox(height: SoftPop.s12),
            Row(
              children: [
                Expanded(
                  child: SoftHeroButton(
                      label: '✓ Jour réussi', onPressed: _success),
                ),
                const SizedBox(width: SoftPop.s8),
                Expanded(
                  child: Material(
                    color: SoftPop.card,
                    borderRadius: BorderRadius.circular(SoftPop.rPill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(SoftPop.rPill),
                      onTap: _miss,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: SoftPop.s16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(SoftPop.rPill),
                          border: Border.all(
                              color: SoftPop.inkMuted.withValues(alpha: .3)),
                        ),
                        child: Text('✕ Jour manqué',
                            style: SoftPop.ui(
                                size: 15,
                                weight: FontWeight.w600,
                                color: SoftPop.inkSecondary)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
