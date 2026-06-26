import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Type d'unité d'attaque (mock — réf handoff §4.5/§4.6).
class _Unit {
  final String key, emoji, name, role;
  final int mult; // dégâts = énergie × mult
  final Color color, bg;
  const _Unit(
      this.key, this.emoji, this.name, this.role, this.mult, this.color, this.bg);
}

const _units = [
  _Unit('belier', '🐏', 'Bélier', 'ouvre les structures', 9, SoftPop.coral,
      SoftPop.coralSoft),
  _Unit('assaut', '⚔️', 'Assaut', 'gros dégâts au coffre', 12, SoftPop.violet,
      SoftPop.violetSoft),
  _Unit('mage', '✨', 'Mage', 'dégâts à distance', 10, SoftPop.amber,
      SoftPop.amberSoft),
  _Unit('soigneur', '✚', 'Soigneur', "soutient l'escouade", 7, SoftPop.teal,
      SoftPop.tealSoft),
];

/// Écran « Constructeur de stratégie » — allocation d'énergie + résolution (preview).
///
/// Réf : handoff `02_couche_jeu` §4.6 (allocation) & §4.7 (résolution).
/// On répartit le budget ⚡ du jour entre unités d'attaque et défense, on lit la
/// stratégie qui émerge, puis on simule le duel asynchrone. Données mock.
class SoftPopStrategyScreen extends StatefulWidget {
  const SoftPopStrategyScreen({super.key});

  @override
  State<SoftPopStrategyScreen> createState() => _SoftPopStrategyScreenState();
}

class _SoftPopStrategyScreenState extends State<SoftPopStrategyScreen> {
  static const int _budget = 124; // énergie du jour (cf. Repaire)
  static const int _step = 4;
  static const int _oppDef = 520;
  static const int _oppAttack = 760;
  static const int _vaultMax = 1000;

  // Énergie allouée par poste (unités d'attaque + 'def' pour les tourelles).
  final Map<String, int> _alloc = {
    'belier': 24,
    'assaut': 36,
    'mage': 0,
    'soigneur': 0,
    'def': 40,
  };

  bool _resolved = false;

  int get _spent => _alloc.values.fold(0, (s, v) => s + v);
  int get _remaining => _budget - _spent;
  int get _atkEnergy =>
      _units.fold(0, (s, u) => s + (_alloc[u.key] ?? 0));
  int get _defEnergy => _alloc['def'] ?? 0;

  int get _yourAttack =>
      _units.fold(0, (s, u) => s + (_alloc[u.key] ?? 0) * u.mult);
  int get _yourDef => _defEnergy * 12;
  int get _oppVault =>
      (_vaultMax - math.max(0, _yourAttack - _oppDef)).clamp(0, _vaultMax).toInt();
  int get _yourVault =>
      (_vaultMax - math.max(0, _oppAttack - _yourDef)).clamp(0, _vaultMax).toInt();
  bool get _win => _yourVault >= _oppVault;

  String get _strategy {
    final atk = _atkEnergy, def = _defEnergy;
    if (atk == 0 && def == 0) return 'À répartir';
    if (def == 0) return 'Verre canon ⚔️';
    if (atk == 0) return 'Forteresse 🛡️';
    if (atk >= def * 1.8) return 'Agressif';
    if (def >= atk * 1.8) return 'Défensif';
    final topUnit =
        _units.map((u) => _alloc[u.key] ?? 0).fold(0, math.max);
    if (atk > 0 && topUnit >= atk * 0.7) return 'Spécialiste';
    return 'Équilibré';
  }

  void _bump(String key, int delta) {
    if (delta > 0 && _remaining < _step) return;
    setState(() {
      _alloc[key] = math.max(0, (_alloc[key] ?? 0) + delta * _step);
      _resolved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Stratégie de raid')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            _budgetCard(),
            const SizedBox(height: SoftPop.s16),
            Text('Attaque',
                style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: SoftPop.s8),
            for (final u in _units) _allocRow(u),
            const SizedBox(height: SoftPop.s16),
            Text('Défense',
                style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: SoftPop.s8),
            _defenseRow(),
            const SizedBox(height: SoftPop.s20),
            SoftHeroButton(
              label: 'Simuler le duel',
              icon: Icons.sports_kabaddi,
              onPressed: _spent == 0
                  ? null
                  : () => setState(() => _resolved = true),
            ),
            if (_resolved) ...[
              const SizedBox(height: SoftPop.s16),
              _resolution(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Budget + lecture de stratégie ──────────────────────────────────────────
  Widget _budgetCard() => SoftCard(
        radius: SoftPop.rCardSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Text('⚡', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: SoftPop.s4),
                  Text('$_spent / $_budget',
                      style: SoftPop.mono(size: 18, color: SoftPop.amberDark)),
                ]),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SoftPop.s12, vertical: SoftPop.s4),
                  decoration: BoxDecoration(
                    color: SoftPop.violetSoft,
                    borderRadius: BorderRadius.circular(SoftPop.rPill),
                  ),
                  child: Text(_strategy,
                      style: SoftPop.ui(
                          size: 12,
                          weight: FontWeight.w700,
                          color: SoftPop.violetDark)),
                ),
              ],
            ),
            const SizedBox(height: SoftPop.s8),
            SoftXpBar(value: _spent / _budget),
            const SizedBox(height: SoftPop.s4),
            Text(
                _remaining > 0
                    ? '$_remaining ⚡ encore à répartir'
                    : 'Budget entièrement alloué',
                style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
          ],
        ),
      );

  // ── Ligne d'allocation d'une unité d'attaque ───────────────────────────────
  Widget _allocRow(_Unit u) {
    final e = _alloc[u.key] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: SoftPop.s8),
      child: SoftCard(
        padding: const EdgeInsets.all(SoftPop.s12),
        radius: SoftPop.rCardSm,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: u.bg, borderRadius: BorderRadius.circular(12)),
              child: Text(u.emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.name,
                      style: SoftPop.ui(size: 14, weight: FontWeight.w600)),
                  Text(
                      e > 0 ? '${e * u.mult} dégâts · ${u.role}' : u.role,
                      style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
                ],
              ),
            ),
            _stepper(u.key, e, u.color),
          ],
        ),
      ),
    );
  }

  Widget _defenseRow() {
    final e = _defEnergy;
    return SoftCard(
      padding: const EdgeInsets.all(SoftPop.s12),
      radius: SoftPop.rCardSm,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: SoftPop.tealSoft,
                borderRadius: BorderRadius.circular(12)),
            child: const Text('🗼', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: SoftPop.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tourelles',
                    style: SoftPop.ui(size: 14, weight: FontWeight.w600)),
                Text(
                    e > 0
                        ? '${e * 12} PV de défense'
                        : 'protège ton coffre',
                    style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
              ],
            ),
          ),
          _stepper('def', e, SoftPop.teal),
        ],
      ),
    );
  }

  Widget _stepper(String key, int value, Color c) => Row(
        children: [
          _stepBtn(Icons.remove, value > 0, () => _bump(key, -1),
              SoftPop.violetSoft, SoftPop.violet),
          SizedBox(
            width: 42,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: SoftPop.mono(size: 15, color: c)),
          ),
          _stepBtn(Icons.add, _remaining >= _step, () => _bump(key, 1), c,
              Colors.white),
        ],
      );

  Widget _stepBtn(
          IconData icon, bool enabled, VoidCallback onTap, Color bg, Color fg) =>
      Opacity(
        opacity: enabled ? 1 : .35,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
                width: 32, height: 32, child: Icon(icon, size: 18, color: fg)),
          ),
        ),
      );

  // ── Résolution du duel ──────────────────────────────────────────────────────
  Widget _resolution() => SoftCard(
        radius: SoftPop.rCard,
        color: _win ? SoftPop.tealSoft : SoftPop.violetSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_win ? '🏆' : '🛡️', style: const TextStyle(fontSize: 22)),
                const SizedBox(width: SoftPop.s8),
                Text(_win ? 'Victoire !' : 'Repaire défendu',
                    style: SoftPop.ui(
                        size: 18,
                        weight: FontWeight.w700,
                        color: _win ? SoftPop.tealDark : SoftPop.violetDark)),
                const Spacer(),
                Text(_win ? '+24 💎' : '+6 💎',
                    style: SoftPop.mono(
                        size: 14,
                        color: _win ? SoftPop.tealDark : SoftPop.violetDark)),
              ],
            ),
            const SizedBox(height: SoftPop.s16),
            _vaultBar('Ton coffre', _yourVault, SoftPop.violet),
            const SizedBox(height: SoftPop.s12),
            _vaultBar('Coffre adverse', _oppVault, SoftPop.coral),
            const SizedBox(height: SoftPop.s12),
            Text(
                'Le coffre avec le plus de PV restants l\'emporte. '
                'Ton attaque ${_yourAttack} · ta défense ${_yourDef} PV.',
                style: SoftPop.ui(
                    size: 11, color: SoftPop.inkSecondary, height: 1.3)),
          ],
        ),
      );

  Widget _vaultBar(String label, int pv, Color c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: SoftPop.ui(size: 12, weight: FontWeight.w600)),
              Text('$pv PV', style: SoftPop.mono(size: 12, color: c)),
            ],
          ),
          const SizedBox(height: SoftPop.s4),
          SoftXpBar(
            value: pv / _vaultMax,
            gradient: LinearGradient(colors: [c, c]),
            track: Colors.white,
          ),
        ],
      );
}
