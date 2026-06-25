import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

// POC Rive — prouve que Rive tourne DANS Productivitwo (web + mobile).
// L'anim est chargée depuis le réseau (ton appareil va la chercher ; l'éditeur
// Claude est bloqué par son proxy, pas ton téléphone). Échantillon générique :
// le but est de valider le rendu/animation, pas le perso final.
// Le vrai héros = un hero.riv sur-mesure piloté par tes données (voir
// docs/rive_poc.md). Accès : ?proto=rive (sans auth).
class RivePocScreen extends StatelessWidget {
  const RivePocScreen({super.key});

  // Échantillon public Rive (peut être remplacé par notre hero.riv plus tard).
  static const _sampleUrl = 'https://cdn.rive.app/animations/vehicles.riv';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('POC Rive',
                  style: TextStyle(
                      color: Color(0xFFB6FF3C),
                      fontSize: 24,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text(
                  'Si l\'anim ci-dessous bouge, Rive tourne bien dans l\'app.',
                  style: TextStyle(color: Color(0xFF8FA0C8), fontSize: 13)),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0D12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF35E0FF).withOpacity(0.3)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RiveAnimation.network(
                    _sampleUrl,
                    fit: BoxFit.contain,
                    placeHolder: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Chargement de l\'anim Rive…',
                              style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Échantillon générique (une démo publique Rive). Le vrai héros\n'
                'serait un hero.riv sur-mesure : marche + humeurs pilotées par ta\n'
                'régularité réelle (le moteur reste en code). Voir docs/rive_poc.md.',
                style: TextStyle(
                    color: Color(0xFF7FD0C0), fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
