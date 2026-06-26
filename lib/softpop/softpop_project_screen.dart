import 'package:flutter/material.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Action cochable d'un jalon (mock → futur `TaskAction`).
class _Act {
  final String title;
  bool done;
  _Act(this.title, {this.done = false});
}

/// Jalon (mock → futur `ProjectTask` avec `isMilestone`).
class _Milestone {
  final int num;
  final String icon, label, xp;
  final List<_Act> actions;
  _Milestone(this.num, this.icon, this.label, this.xp, this.actions);
  bool get done => actions.every((a) => a.done);
  int get doneCount => actions.where((a) => a.done).length;
}

/// Écran « Détail projet · Parcours à jalons » (preview).
///
/// Réf : maquette `01_design_produit` (Métaphore 1 · Quête / Parcours).
/// Frise verticale de jalons → chaque jalon est un accordéon de sous-actions
/// cochables ; % = actions cochées / total. Données mock (→ `Project`/
/// `ProjectTask`/`TaskAction`).
class SoftPopProjectScreen extends StatefulWidget {
  const SoftPopProjectScreen({super.key});

  @override
  State<SoftPopProjectScreen> createState() => _SoftPopProjectScreenState();
}

class _SoftPopProjectScreenState extends State<SoftPopProjectScreen> {
  late final List<_Milestone> _jalons = [
    _Milestone(1, '1', 'JALON 1 · ACCORDAGE', '+15 XP', [
      _Act("Installer une appli d'accordage", done: true),
      _Act('Accorder les 6 cordes', done: true),
    ]),
    _Milestone(2, '2', 'JALON 2 · PREMIERS ACCORDS', '+25 XP', [
      _Act('Apprendre Mi mineur (Em)', done: true),
      _Act('Apprendre La mineur (Am)'),
      _Act('Apprendre Sol & Do'),
    ]),
    _Milestone(3, '3', 'JALON 3 · ENCHAÎNEMENTS', '+25 XP', [
      _Act('Changer Em → Am en 3 s'),
      _Act('Jouer au métronome (60 bpm)'),
      _Act('Tenir 2 min sans regarder'),
    ]),
    _Milestone(4, '🏆', 'JALON 4 · PREMIÈRE CHANSON', '+40 XP', [
      _Act('Choisir une chanson à 4 accords'),
      _Act('La jouer en entier'),
    ]),
  ];

  final Set<int> _expanded = {1}; // index du jalon « en cours » ouvert par défaut

  int get _totalActions => _jalons.fold(0, (s, m) => s + m.actions.length);
  int get _doneActions =>
      _jalons.fold(0, (s, m) => s + m.doneCount);
  double get _pct => _totalActions == 0 ? 0 : _doneActions / _totalActions;
  int get _currentIdx {
    final i = _jalons.indexWhere((m) => !m.done);
    return i < 0 ? _jalons.length : i;
  }

  void _toggleAction(_Milestone m, _Act a) {
    final wasDone = m.done;
    setState(() => a.done = !a.done);
    if (!wasDone && m.done) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('Jalon atteint ! ${m.xp} 🎉',
              style: SoftPop.ui(color: Colors.white, weight: FontWeight.w600)),
          backgroundColor: SoftPop.teal,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
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
        appBar: AppBar(title: const Text('Parcours du projet')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            _projectHeader(),
            const SizedBox(height: SoftPop.s16),
            for (var i = 0; i < _jalons.length; i++)
              _milestoneRow(_jalons[i], i, i == 0, i == _jalons.length - 1),
          ],
        ),
      ),
    );
  }

  // ── En-tête projet ──────────────────────────────────────────────────────────
  Widget _projectHeader() => SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SoftPop.violetSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('🎸', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: SoftPop.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Apprendre la guitare',
                          style:
                              SoftPop.ui(size: 17, weight: FontWeight.w700)),
                      Text('📅 Échéance 12 août',
                          style: SoftPop.ui(
                              size: 11, color: SoftPop.inkMuted)),
                    ],
                  ),
                ),
                Text('${(_pct * 100).round()}%',
                    style: SoftPop.mono(size: 20, color: SoftPop.violet)),
              ],
            ),
            const SizedBox(height: SoftPop.s12),
            SoftXpBar(value: _pct),
            const SizedBox(height: SoftPop.s4),
            Text('$_doneActions / $_totalActions actions',
                style: SoftPop.mono(size: 10, color: SoftPop.inkMuted)),
          ],
        ),
      );

  // ── Ligne de frise (rail + carte accordéon) ────────────────────────────────
  Widget _milestoneRow(_Milestone m, int idx, bool isFirst, bool isLast) {
    final isCurrent = idx == _currentIdx;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Stack(
              children: [
                if (!isFirst)
                  Positioned(
                    top: 0,
                    left: 19,
                    height: 22,
                    child: Container(
                        width: 2, color: SoftPop.inkMuted.withValues(alpha: .25)),
                  ),
                if (!isLast)
                  Positioned(
                    top: 22,
                    bottom: 0,
                    left: 19,
                    child: Container(
                        width: 2, color: SoftPop.inkMuted.withValues(alpha: .25)),
                  ),
                Positioned(top: 10, left: 8, child: _node(m, isCurrent)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: SoftPop.s12),
              child: _milestoneCard(m, idx, isCurrent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _node(_Milestone m, bool isCurrent) {
    Color bg;
    Widget child;
    if (m.done) {
      bg = SoftPop.teal;
      child = const Icon(Icons.check, size: 14, color: Colors.white);
    } else if (isCurrent) {
      bg = SoftPop.violet;
      child = Text('${m.num}',
          style:
              SoftPop.ui(size: 12, weight: FontWeight.w700, color: Colors.white));
    } else {
      bg = SoftPop.card;
      child = Text('${m.num}',
          style:
              SoftPop.ui(size: 12, weight: FontWeight.w700, color: SoftPop.inkMuted));
    }
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: (!m.done && !isCurrent)
            ? Border.all(color: SoftPop.inkMuted.withValues(alpha: .35), width: 2)
            : null,
        boxShadow: isCurrent ? SoftPop.coloredShadow(SoftPop.violet) : null,
      ),
      child: child,
    );
  }

  Widget _milestoneCard(_Milestone m, int idx, bool isCurrent) {
    final open = _expanded.contains(idx);
    return SoftCard(
      padding: EdgeInsets.zero,
      radius: SoftPop.rCardSm,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(SoftPop.rCardSm),
            onTap: () => setState(
                () => open ? _expanded.remove(idx) : _expanded.add(idx)),
            child: Padding(
              padding: const EdgeInsets.all(SoftPop.s12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.label,
                            style: SoftPop.ui(
                                size: 12,
                                weight: FontWeight.w700,
                                color: m.done
                                    ? SoftPop.tealDark
                                    : (isCurrent
                                        ? SoftPop.violetDark
                                        : SoftPop.inkSecondary),
                                letterSpacing: .3)),
                        const SizedBox(height: 2),
                        Text('${m.doneCount}/${m.actions.length} · ${m.xp}',
                            style: SoftPop.ui(
                                size: 11, color: SoftPop.inkMuted)),
                      ],
                    ),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      color: SoftPop.inkMuted, size: 20),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SoftPop.s12, 0, SoftPop.s12, SoftPop.s12),
              child: Column(
                children: [
                  for (final a in m.actions) _actionRow(m, a),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionRow(_Milestone m, _Act a) => InkWell(
        borderRadius: BorderRadius.circular(SoftPop.rTiny),
        onTap: () => _toggleAction(m, a),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SoftPop.s8),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: a.done ? SoftPop.teal : Colors.transparent,
                  border: a.done
                      ? null
                      : Border.all(
                          color: SoftPop.inkMuted.withValues(alpha: .4),
                          width: 2),
                ),
                child: a.done
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: SoftPop.s12),
              Expanded(
                child: Text(a.title,
                    style: SoftPop.ui(
                        size: 13,
                        color: a.done ? SoftPop.inkMuted : SoftPop.ink,
                        weight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      );
}
