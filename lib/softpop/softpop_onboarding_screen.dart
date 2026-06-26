import 'package:flutter/material.dart';
import 'package:productivitwo_v1/onboarding_catalog.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Onboarding refondu « Soft Pop » (preview).
///
/// Reprend la direction visuelle Soft Pop ET le **catalogue réel** partagé
/// (`onboarding_catalog.dart`) : domaines / activités / routines déjà proposés
/// par l'app — aucun contenu inventé. Multi-étapes : accueil (Pomo) → packs →
/// domaines → habitudes → récap.
///
/// ⚠️ Preview non destructive : le récap n'écrit PAS encore dans AppLogic
/// (le branchement réel créera Domain/Activity/Routine via le même mapping).
class SoftPopOnboardingScreen extends StatefulWidget {
  const SoftPopOnboardingScreen({super.key});

  @override
  State<SoftPopOnboardingScreen> createState() =>
      _SoftPopOnboardingScreenState();
}

class _SoftPopOnboardingScreenState extends State<SoftPopOnboardingScreen> {
  final _pager = PageController();
  int _page = 0;
  static const _steps = 4;

  final Set<String> _domains = {};
  final Set<String> _routines = {}; // par nom

  // Couleur d'accent par domaine (le catalogue n'en porte pas) — cycle palette.
  static const _palette = [
    SoftPop.violet,
    SoftPop.coral,
    SoftPop.teal,
    SoftPop.amber,
    SoftPop.pink,
  ];
  Color _domColor(String name) =>
      _palette[kOnboardingCatalogue.keys.toList().indexOf(name) % _palette.length];

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _go(int p) {
    setState(() => _page = p);
    _pager.animateToPage(p,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  void _applyPack(PackDef pack) {
    setState(() {
      _domains.addAll(pack.domains);
      _routines.addAll(pack.routines);
    });
    _go(2); // saute aux domaines (pré-cochés)
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _progress(),
              Expanded(
                child: PageView(
                  controller: _pager,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (p) => setState(() => _page = p),
                  children: [
                    _welcomeStep(),
                    _domainsStep(),
                    _routinesStep(),
                    _recapStep(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progress() => Padding(
        padding: const EdgeInsets.all(SoftPop.s16),
        child: Row(
          children: [
            if (_page > 0)
              IconButton(
                onPressed: () => _go(_page - 1),
                icon: const Icon(Icons.arrow_back, color: SoftPop.inkSecondary),
              ),
            Expanded(
              child: Row(
                children: List.generate(
                  _steps,
                  (i) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i <= _page ? SoftPop.violet : SoftPop.violetSoft,
                        borderRadius: BorderRadius.circular(SoftPop.rPill),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: SoftPop.s8),
          ],
        ),
      );

  Widget _pad(Widget child) => Padding(
        padding: const EdgeInsets.fromLTRB(
            SoftPop.s20, SoftPop.s8, SoftPop.s20, SoftPop.s20),
        child: child,
      );

  // ── 0 · Accueil + packs ─────────────────────────────────────────────────────
  Widget _welcomeStep() => _pad(ListView(
        children: [
          const SizedBox(height: SoftPop.s12),
          const Center(child: PomoMascot(size: 96)),
          const SizedBox(height: SoftPop.s16),
          Text("Salut, moi c'est Pomo !",
              textAlign: TextAlign.center,
              style: SoftPop.ui(size: 22, weight: FontWeight.w700)),
          const SizedBox(height: SoftPop.s8),
          Text(
              'On va construire tes habitudes ensemble, à ton rythme. Choisis un pack pour démarrer vite — ou pars de zéro.',
              textAlign: TextAlign.center,
              style: SoftPop.ui(
                  size: 14, color: SoftPop.inkSecondary, height: 1.4)),
          const SizedBox(height: SoftPop.s20),
          for (final pack in kOnboardingPacks) ...[
            SoftCard(
              radius: SoftPop.rCardSm,
              onTap: () => _applyPack(pack),
              child: Row(
                children: [
                  Text(pack.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: SoftPop.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pack.name,
                            style: SoftPop.ui(
                                size: 15, weight: FontWeight.w700)),
                        Text(pack.description,
                            style: SoftPop.ui(
                                size: 12, color: SoftPop.inkSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: SoftPop.inkMuted),
                ],
              ),
            ),
            const SizedBox(height: SoftPop.s8),
          ],
          const SizedBox(height: SoftPop.s12),
          SoftHeroButton(
              label: 'Partir de zéro', icon: Icons.tune, onPressed: () => _go(1)),
        ],
      ));

  // ── 1 · Domaines ────────────────────────────────────────────────────────────
  Widget _domainsStep() => _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tes domaines de vie',
              style: SoftPop.ui(size: 22, weight: FontWeight.w700)),
          const SizedBox(height: SoftPop.s4),
          Text('Sur quoi veux-tu progresser ? (plusieurs possibles)',
              style: SoftPop.ui(size: 13, color: SoftPop.inkSecondary)),
          const SizedBox(height: SoftPop.s16),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: SoftPop.s8,
                runSpacing: SoftPop.s8,
                children: [
                  for (final name in kOnboardingCatalogue.keys)
                    SoftPill(
                      label: name,
                      accent: _domColor(name),
                      selected: _domains.contains(name),
                      onTap: () => setState(() => _domains.contains(name)
                          ? _domains.remove(name)
                          : _domains.add(name)),
                    ),
                ],
              ),
            ),
          ),
          SoftHeroButton(
            label: _domains.isEmpty
                ? 'Choisis au moins un domaine'
                : 'Continuer (${_domains.length})',
            onPressed: _domains.isEmpty ? null : () => _go(2),
          ),
        ],
      ));

  // ── 2 · Habitudes ─────────────────────────────────────────────────────────────
  Widget _routinesStep() {
    final doms = kOnboardingCatalogue.keys.where(_domains.contains).toList();
    return _pad(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choisis tes habitudes',
            style: SoftPop.ui(size: 22, weight: FontWeight.w700)),
        const SizedBox(height: SoftPop.s4),
        Text('Coche celles qui te parlent. Tu pourras ajuster plus tard.',
            style: SoftPop.ui(size: 13, color: SoftPop.inkSecondary)),
        const SizedBox(height: SoftPop.s16),
        Expanded(
          child: ListView(
            children: [
              for (final dom in doms) ...[
                Padding(
                  padding: const EdgeInsets.only(
                      top: SoftPop.s8, bottom: SoftPop.s8, left: SoftPop.s4),
                  child: Text(dom,
                      style: SoftPop.ui(
                          size: 13,
                          weight: FontWeight.w700,
                          color: _domColor(dom))),
                ),
                for (final r in kOnboardingCatalogue[dom]!.routines)
                  _routineTile(dom, r),
              ],
            ],
          ),
        ),
        SoftHeroButton(
          label: 'Continuer (${_routines.length})',
          onPressed: _routines.isEmpty ? null : () => _go(3),
        ),
      ],
    ));
  }

  Widget _routineTile(String dom, RoutineSug r) {
    final on = _routines.contains(r.name);
    final c = _domColor(dom);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoftPop.s8),
      child: SoftCard(
        padding: const EdgeInsets.all(SoftPop.s12),
        radius: SoftPop.rCardSm,
        onTap: () => setState(
            () => on ? _routines.remove(r.name) : _routines.add(r.name)),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(r.icon, size: 20, color: c),
            ),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name,
                      style: SoftPop.ui(size: 14, weight: FontWeight.w600)),
                  Text(onboardingFreqLabel(r.defaultFreq) +
                      (r.habitTarget > 1 ? ' · objectif ${r.habitTarget}' : ''),
                      style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? SoftPop.teal : Colors.transparent,
                border: on
                    ? null
                    : Border.all(
                        color: SoftPop.inkMuted.withValues(alpha: .4), width: 2),
              ),
              child: on
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── 3 · Récap ─────────────────────────────────────────────────────────────────
  Widget _recapStep() => _pad(ListView(
        children: [
          const SizedBox(height: SoftPop.s12),
          const Center(child: PomoMascot(size: 80)),
          const SizedBox(height: SoftPop.s16),
          Text('Tout est prêt ! 🎉',
              textAlign: TextAlign.center,
              style: SoftPop.ui(size: 22, weight: FontWeight.w700)),
          const SizedBox(height: SoftPop.s8),
          Text('Voici ton point de départ :',
              textAlign: TextAlign.center,
              style: SoftPop.ui(size: 14, color: SoftPop.inkSecondary)),
          const SizedBox(height: SoftPop.s20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _recapStat('${_domains.length}', 'domaines', SoftPop.violet),
              const SizedBox(width: SoftPop.s12),
              _recapStat('${_routines.length}', 'habitudes', SoftPop.teal),
            ],
          ),
          const SizedBox(height: SoftPop.s20),
          for (final dom in kOnboardingCatalogue.keys.where(_domains.contains))
            _recapDomain(dom),
          const SizedBox(height: SoftPop.s20),
          SoftHeroButton(
            label: 'Commencer',
            icon: Icons.rocket_launch_outlined,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Aperçu : ${_domains.length} domaines · ${_routines.length} habitudes (non créés — preview)',
                    style: SoftPop.ui(
                        color: Colors.white, weight: FontWeight.w600)),
                backgroundColor: SoftPop.violet,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SoftPop.rChip)),
              ));
            },
          ),
        ],
      ));

  Widget _recapStat(String v, String l, Color c) => SoftCard(
        radius: SoftPop.rCardSm,
        padding: const EdgeInsets.symmetric(
            horizontal: SoftPop.s24, vertical: SoftPop.s16),
        child: Column(
          children: [
            Text(v, style: SoftPop.mono(size: 28, color: c)),
            Text(l, style: SoftPop.ui(size: 12, color: SoftPop.inkSecondary)),
          ],
        ),
      );

  Widget _recapDomain(String dom) {
    final rs = kOnboardingCatalogue[dom]!
        .routines
        .where((r) => _routines.contains(r.name))
        .toList();
    if (rs.isEmpty) return const SizedBox.shrink();
    final c = _domColor(dom);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoftPop.s8),
      child: SoftCard(
        radius: SoftPop.rCardSm,
        padding: const EdgeInsets.all(SoftPop.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dom,
                style: SoftPop.ui(
                    size: 13, weight: FontWeight.w700, color: c)),
            const SizedBox(height: SoftPop.s8),
            Wrap(
              spacing: SoftPop.s8,
              runSpacing: SoftPop.s8,
              children: [
                for (final r in rs)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(r.icon, size: 14, color: c),
                      const SizedBox(width: SoftPop.s4),
                      Text(r.name,
                          style: SoftPop.ui(size: 12, color: SoftPop.ink)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
