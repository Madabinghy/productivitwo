// ignore_for_file: deprecated_member_use

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/pro_manager.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

Future<bool> showPaywallSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _PaywallSheet(),
  );
  return result == true;
}

// ── Paywall sheet ─────────────────────────────────────────────────────────────

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet();
  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  bool _yearly = true;
  bool _loading = false;

  static const _benefits = [
    (Icons.cloud_outlined, 'Synchronisation cloud',
        'Backup automatique et accès multi-appareils'),
    (Icons.bar_chart_outlined, 'Statistiques avancées',
        'Heatmap 12 semaines, rapports de temps détaillés'),
    (Icons.history_outlined, 'Historique illimité',
        'Toutes tes données conservées indéfiniment'),
    (Icons.new_releases_outlined, 'Nouvelles fonctionnalités',
        'Accès prioritaire à chaque mise à jour'),
  ];

  Future<void> _subscribe() async {
    setState(() => _loading = true);
    // TODO: intégrer RevenueCat / StoreKit 2
    // Exemple RevenueCat :
    //   final offerings = await Purchases.getOfferings();
    //   final package = _yearly ? offerings.current?.annual : offerings.current?.monthly;
    //   await Purchases.purchasePackage(package!);
    await ProManager.activate();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _restore() async {
    // TODO: Purchases.restorePurchases()
    await ProManager.activate();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.rocket_launch_outlined, color: cs.primary, size: 28),
                ),
              ),
              const SizedBox(height: 14),
              Text('Productivitwo Pro',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 6),
              Text('Débloque toutes les fonctionnalités',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(.5))),
              const SizedBox(height: 24),

              // Bénéfices
              ...(_benefits.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(b.$1, size: 18, color: cs.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.$2,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface)),
                              const SizedBox(height: 2),
                              Text(b.$3,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withOpacity(.5))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ))),

              const SizedBox(height: 8),

              // Sélecteur de plan
              Row(
                children: [
                  Expanded(child: _PlanCard(
                    cs: cs,
                    label: 'Mensuel',
                    price: '4,99 €',
                    sub: 'par mois',
                    badge: null,
                    selected: !_yearly,
                    onTap: () => setState(() => _yearly = false),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _PlanCard(
                    cs: cs,
                    label: 'Annuel',
                    price: '29,99 €',
                    sub: '2,50 € / mois',
                    badge: '−50 %',
                    selected: _yearly,
                    onTap: () => setState(() => _yearly = true),
                  )),
                ],
              ),
              const SizedBox(height: 20),

              // CTA
              FilledButton(
                onPressed: _loading ? null : _subscribe,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        _yearly
                            ? 'Commencer l\'essai gratuit 7 jours'
                            : 'S\'abonner pour 4,99 € / mois',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : _restore,
                  child: Text('Restaurer mes achats',
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurface.withOpacity(.4))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final String price;
  final String sub;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.cs,
    required this.label,
    required this.price,
    required this.sub,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest.withOpacity(.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? cs.primary : cs.onSurface.withOpacity(.6))),
                const SizedBox(height: 4),
                Text(price,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(.45))),
              ],
            ),
            if (badge != null)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badge!,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimary)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── ProGate — wrapper qui grise les features Pro ──────────────────────────────

class ProGate extends StatelessWidget {
  final Widget child;
  final String featureName;

  const ProGate({super.key, required this.child, required this.featureName});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ProManager.notifier,
      builder: (context, isPro, _) {
        if (isPro) return child;
        return _LockedOverlay(child: child, featureName: featureName);
      },
    );
  }
}

class _LockedOverlay extends StatelessWidget {
  final Widget child;
  final String featureName;

  const _LockedOverlay({required this.child, required this.featureName});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // Contenu flouté (aperçu)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: IgnorePointer(child: child),
          ),

          // Overlay semi-transparent
          Positioned.fill(
            child: Container(
              color: cs.surface.withOpacity(.55),
            ),
          ),

          // Badge Pro centré
          Positioned.fill(
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(.12),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outlined, color: cs.primary, size: 28),
                    const SizedBox(height: 8),
                    Text(featureName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface)),
                    const SizedBox(height: 4),
                    Text('Disponible avec Pro',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurface.withOpacity(.5))),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => showPaywallSheet(context),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(160, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 20)),
                      child: const Text('Débloquer Pro',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
