import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Politique de confidentialité')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            'Politique de confidentialité — Productivitwo',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                color: cs.onSurface),
          ),
          const SizedBox(height: 4),
          Text('Dernière mise à jour : mai 2026',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
          const SizedBox(height: 24),
          _section('1. Qui sommes-nous ?',
              'Productivitwo est une application mobile de productivité personnelle. '
              'Elle est développée et maintenue par Emeric Edmond.'),
          _section('2. Données collectées',
              'Productivitwo collecte uniquement les données que vous saisissez '
              'dans l\'application :\n\n'
              '• Activités, routines et habitudes que vous créez\n'
              '• Sessions de travail et durées enregistrées\n'
              '• Objectifs, actions planifiées et progressions\n'
              '• Paramètres de l\'application\n\n'
              'Aucune donnée personnelle (nom, email, téléphone) n\'est collectée '
              'sauf si vous créez un compte avec votre email.'),
          _section('3. Comment vos données sont-elles utilisées ?',
              'Vos données sont utilisées exclusivement pour :\n\n'
              '• Afficher votre suivi de productivité dans l\'application\n'
              '• Synchroniser vos données entre vos appareils\n'
              '• Sauvegarder vos données en cas de réinstallation\n\n'
              'Vos données ne sont jamais vendues, partagées ou utilisées '
              'à des fins publicitaires.'),
          _section('4. Où sont stockées vos données ?',
              'Les données sont stockées de deux façons :\n\n'
              '• Localement sur votre appareil\n'
              '• Dans Firebase Firestore (Google), un service cloud sécurisé\n\n'
              'La synchronisation cloud utilise un identifiant anonyme unique '
              'associé à votre appareil. Vos données dans Firestore sont '
              'accessibles uniquement par vous.'),
          _section('5. Services tiers',
              'Productivitwo utilise Firebase (Google) pour :\n\n'
              '• L\'authentification anonyme (Firebase Auth)\n'
              '• Le stockage cloud des données (Firebase Firestore)\n\n'
              'Firebase est soumis à la politique de confidentialité de Google : '
              'https://policies.google.com/privacy'),
          _section('6. Conservation des données',
              'Vos données sont conservées tant que votre compte existe. '
              'Vous pouvez supprimer votre compte et toutes les données associées '
              'à tout moment depuis les paramètres de l\'application '
              '(⋮ → Supprimer mon compte).'),
          _section('7. Vos droits',
              'Conformément au RGPD, vous disposez des droits suivants :\n\n'
              '• Accès à vos données\n'
              '• Rectification de vos données\n'
              '• Suppression de vos données\n'
              '• Portabilité de vos données\n\n'
              'Pour exercer ces droits, contactez-nous à : '
              'emeric.edmond@gmail.com'),
          _section('8. Modifications',
              'Cette politique peut être mise à jour. La date de dernière '
              'modification est indiquée en haut de ce document. '
              'L\'utilisation continue de l\'application vaut acceptation '
              'des modifications.'),
          _section('9. Contact',
              'Pour toute question relative à cette politique de confidentialité :\n'
              'emeric.edmond@gmail.com'),
        ],
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }
}
