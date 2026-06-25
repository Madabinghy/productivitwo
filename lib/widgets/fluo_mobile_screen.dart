import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/web/fluo_data_screen.dart';
import 'package:productivitwo_v1/prototypes/fluo_prototype.dart';

// Onglet « Galaxie » (mobile) : « Fluo Adventure » branché sur tes vraies
// données via AppLogic. Galaxie (domaines) → tape une planète → map (activités,
// torches) → carte à nœuds → combat tower-defense. Réutilise buildFluoData +
// FluoNavScreen (mêmes que le web ?proto=orbit).
class FluoMobileScreen extends StatefulWidget {
  final AppLogic logic;
  const FluoMobileScreen({super.key, required this.logic});

  @override
  State<FluoMobileScreen> createState() => _FluoMobileScreenState();
}

class _FluoMobileScreenState extends State<FluoMobileScreen> {
  // Construit une fois au montage (l'état est déjà chargé quand l'accueil rend).
  late final _fd = buildFluoData(widget.logic.state);

  @override
  Widget build(BuildContext context) {
    return FluoNavScreen(
      data: _fd.doms,
      bodies: _fd.bodies,
      sunFill: _fd.sunFill,
      sunLabel: _fd.sunLabel,
    );
  }
}
