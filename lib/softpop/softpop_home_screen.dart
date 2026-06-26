import 'package:flutter/material.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Écran « Accueil » de la refonte Soft Pop — boucle cœur (preview).
///
/// Données MOCK et interactives : cocher une routine fait monter l'XP du jour,
/// remplit la barre de niveau et rapproche du bonus 💎. But : valider la boucle
/// et le ressenti AVANT de brancher les vraies données (AppState/AppLogic).
/// Réf : maquette `01_design_produit/ProductiviTwo Ecrans.dc.html` (écran Accueil).
class SoftPopHomeScreen extends StatefulWidget {
  const SoftPopHomeScreen({super.key});

  @override
  State<SoftPopHomeScreen> createState() => _SoftPopHomeScreenState();
}

/// Bloc de journée.
class _Block {
  final String key, label, emoji;
  const _Block(this.key, this.label, this.emoji);
}

const _blocks = [
  _Block('matin', 'Matin', '🌅'),
  _Block('midi', 'Midi', '☀️'),
  _Block('soir', 'Soir', '🌙'),
];

/// Routine mock (couleur = couleur de domaine).
class _Routine {
  final String emoji, name, target, block;
  final int xp;
  final Color color, bg;
  bool done;
  _Routine(this.emoji, this.name, this.target, this.xp, this.color, this.bg,
      this.block,
      {this.done = false});
}

class _SoftPopHomeScreenState extends State<SoftPopHomeScreen> {
  // Niveau / progression (mock).
  static const int _level = 7;
  static const String _rank = 'Régulier';
  static const int _gems = 340;
  static const int _streak = 12;
  static const int _xpFloor = 540; // XP au début du niveau
  static const int _xpNext = 700; // XP requis pour le niveau suivant
  static const int _bonusGoal = 5; // routines pour le bonus 💎

  late final List<_Routine> _routines = [
    _Routine('💧', "Boire de l'eau", 'objectif 8 verres', 15, SoftPop.coral,
        SoftPop.coralSoft, 'matin', done: true),
    _Routine('🧘', 'Méditer 10 min', '1 séance', 20, SoftPop.violet,
        SoftPop.violetSoft, 'matin'),
    _Routine('📖', 'Lire 10 pages', 'objectif 10 pages', 15, SoftPop.amber,
        SoftPop.amberSoft, 'midi'),
    _Routine('💼', 'Bloc focus projet', '1 session', 25, SoftPop.teal,
        SoftPop.tealSoft, 'midi'),
    _Routine('🏋️', 'Salle de sport', '1 séance', 30, SoftPop.coral,
        SoftPop.coralSoft, 'soir'),
    _Routine('🍳', 'Cuisiner maison', '1 repas', 20, SoftPop.amber,
        SoftPop.amberSoft, 'soir'),
    _Routine('📓', 'Journal de gratitude', '3 lignes', 15, SoftPop.pink,
        SoftPop.pinkSoft, 'soir'),
    _Routine('😴', 'Au lit avant 23h', 'objectif 23:00', 15, SoftPop.violet,
        SoftPop.violetSoft, 'soir'),
  ];

  int get _xpToday =>
      _routines.where((r) => r.done).fold(0, (s, r) => s + r.xp);
  int get _doneCount => _routines.where((r) => r.done).length;
  double get _xpPct =>
      ((_xpFloor + _xpToday) / _xpNext).clamp(0.0, 1.0).toDouble();

  void _toggle(_Routine r) {
    setState(() => r.done = !r.done);
    if (r.done) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('+${r.xp} XP 🎉  ·  ${r.name}',
              style: SoftPop.ui(color: Colors.white, weight: FontWeight.w600)),
          duration: const Duration(milliseconds: 1100),
          backgroundColor: SoftPop.violet,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SoftPop.rChip)),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
            children: [
              _header(),
              const SizedBox(height: SoftPop.s12),
              _statsRow(),
              const SizedBox(height: SoftPop.s12),
              _levelCard(),
              const SizedBox(height: SoftPop.s12),
              _nudge(),
              const SizedBox(height: SoftPop.s20),
              Text('Aujourd’hui',
                  style: SoftPop.ui(size: 18, weight: FontWeight.w700)),
              const SizedBox(height: SoftPop.s12),
              for (final b in _blocks) ..._blockSection(b),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header : pill + mascotte + salutation ──────────────────────────────────
  Widget _header() => Row(
        children: [
          const PomoMascot(size: 42),
          const SizedBox(width: SoftPop.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Salut Léa 👋',
                    style: SoftPop.ui(size: 13, color: SoftPop.inkMuted)),
                Text('Belle journée qui démarre',
                    style: SoftPop.ui(size: 18, weight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      );

  // ── 3 stats : niveau, gemmes, série ────────────────────────────────────────
  Widget _statsRow() => Row(
        children: [
          SoftCard(
            padding: const EdgeInsets.symmetric(
                horizontal: SoftPop.s12, vertical: SoftPop.s8),
            radius: SoftPop.rChip,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: SoftPop.heroGradient,
                    borderRadius: BorderRadius.circular(SoftPop.rTiny),
                  ),
                  child: Text('$_level',
                      style: SoftPop.ui(
                          size: 12,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                ),
                const SizedBox(width: SoftPop.s8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Niv. $_level',
                        style: SoftPop.ui(size: 12, weight: FontWeight.w600)),
                    Text(_rank,
                        style: SoftPop.ui(size: 9, color: SoftPop.inkMuted)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: SoftPop.s8),
          Expanded(child: _miniStat('💎', '$_gems', SoftPop.violet)),
          const SizedBox(width: SoftPop.s8),
          Expanded(child: _miniStat('🔥', '$_streak', SoftPop.coral)),
        ],
      );

  Widget _miniStat(String emoji, String value, Color c) => SoftCard(
        padding: const EdgeInsets.symmetric(vertical: SoftPop.s12),
        radius: SoftPop.rChip,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: SoftPop.s4),
            Text(value, style: SoftPop.mono(size: 14, color: c)),
          ],
        ),
      );

  // ── Carte niveau + barre XP ────────────────────────────────────────────────
  Widget _levelCard() => SoftCard(
        radius: SoftPop.rCardSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Niveau $_level',
                    style: SoftPop.ui(size: 14, weight: FontWeight.w600)),
                Text('+$_xpToday XP aujourd’hui',
                    style: SoftPop.mono(size: 11, color: SoftPop.tealDark)),
              ],
            ),
            const SizedBox(height: SoftPop.s8),
            SoftXpBar(
              value: _xpPct,
              gradient: const LinearGradient(
                  colors: [SoftPop.violet, SoftPop.teal]),
            ),
          ],
        ),
      );

  // ── Bandeau encouragement (jamais punitif) ─────────────────────────────────
  Widget _nudge() {
    final remaining = (_bonusGoal - _doneCount).clamp(0, _bonusGoal);
    final text = remaining == 0
        ? 'Bravo ! Bonus 💎 du jour débloqué. 🎉'
        : 'Tu avances super bien. Encore $remaining routine${remaining > 1 ? 's' : ''} pour un bonus 💎 !';
    return Container(
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
          Text(remaining == 0 ? '🎉' : '💛',
              style: const TextStyle(fontSize: 17)),
          const SizedBox(width: SoftPop.s8),
          Expanded(
            child: Text(text,
                style: SoftPop.ui(
                    size: 12, color: SoftPop.tealDark, height: 1.3)),
          ),
        ],
      ),
    );
  }

  // ── Section d'un bloc (Matin/Midi/Soir) ────────────────────────────────────
  List<Widget> _blockSection(_Block b) {
    final items = _routines.where((r) => r.block == b.key).toList();
    if (items.isEmpty) return const [];
    final done = items.where((r) => r.done).length;
    return [
      Padding(
        padding: const EdgeInsets.only(
            top: SoftPop.s8, bottom: SoftPop.s8, left: SoftPop.s4),
        child: Row(
          children: [
            Text(b.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: SoftPop.s8),
            Text(b.label,
                style: SoftPop.ui(
                    size: 13,
                    weight: FontWeight.w700,
                    color: SoftPop.inkSecondary)),
            const SizedBox(width: SoftPop.s8),
            Text('$done/${items.length}',
                style: SoftPop.mono(size: 11, color: SoftPop.inkMuted)),
          ],
        ),
      ),
      for (final r in items) ...[
        _routineTile(r),
        const SizedBox(height: SoftPop.s8),
      ],
    ];
  }

  Widget _routineTile(_Routine r) => SoftCard(
        padding: const EdgeInsets.all(SoftPop.s12),
        radius: SoftPop.rCardSm,
        onTap: () => _toggle(r),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: r.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(r.emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name,
                      style: SoftPop.ui(
                          size: 14,
                          weight: FontWeight.w600,
                          color: r.done ? SoftPop.inkMuted : SoftPop.ink)),
                  Text('${r.target} · +${r.xp} XP',
                      style: SoftPop.ui(
                          size: 10,
                          weight: FontWeight.w500,
                          color: r.done
                              ? SoftPop.inkMuted
                              : _darken(r.color))),
                ],
              ),
            ),
            _check(r),
          ],
        ),
      );

  Widget _check(_Routine r) {
    if (r.done) {
      return Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            color: SoftPop.teal, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 16, color: Colors.white),
      );
    }
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: SoftPop.inkMuted.withValues(alpha: .4), width: 2),
      ),
    );
  }

  // Variante foncée approximative pour le sous-titre (lisible sur fond clair).
  Color _darken(Color c) {
    if (c == SoftPop.coral) return SoftPop.coralDark;
    if (c == SoftPop.violet) return SoftPop.violetDark;
    if (c == SoftPop.teal) return SoftPop.tealDark;
    if (c == SoftPop.amber) return SoftPop.amberDark;
    if (c == SoftPop.pink) return SoftPop.pinkDark;
    return SoftPop.inkSecondary;
  }
}
