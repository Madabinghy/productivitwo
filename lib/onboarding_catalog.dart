import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';

/// Catalogue de suggestions d'onboarding (domaines / activités / routines) et
/// packs prédéfinis — **source unique** partagée par l'onboarding historique
/// (`widgets/onboarding_screen.dart`) et l'onboarding refondu Soft Pop
/// (`softpop/softpop_onboarding_screen.dart`). Une seule vérité, pas de drift.

// ── Modèles de suggestions ────────────────────────────────────────────────────

class ActivitySug {
  final String name;
  final IconData icon;
  const ActivitySug(this.name, this.icon);
}

class RoutineSug {
  final String name;
  final IconData icon;
  final HabitFreq defaultFreq;
  final String? linkedActivity;
  final int habitTarget;
  const RoutineSug(
    this.name,
    this.icon, {
    this.defaultFreq = HabitFreq.daily,
    this.linkedActivity,
    this.habitTarget = 1,
  });
}

class DomainSug {
  final List<ActivitySug> activities;
  final List<RoutineSug> routines;
  const DomainSug({required this.activities, required this.routines});
}

// ── Catalogue ─────────────────────────────────────────────────────────────────

final kOnboardingCatalogue = <String, DomainSug>{
  'Santé': DomainSug(
    activities: [
      ActivitySug('Méditation', Icons.self_improvement_outlined),
      ActivitySug('Hydratation', Icons.water_drop_outlined),
      ActivitySug('Nutrition', Icons.restaurant_outlined),
      ActivitySug('Sommeil', Icons.bedtime_outlined),
    ],
    routines: [
      RoutineSug('Méditer', Icons.self_improvement_outlined, linkedActivity: 'Méditation'),
      RoutineSug("Boire de l'eau", Icons.water_drop_outlined, habitTarget: 8, linkedActivity: 'Hydratation'),
      RoutineSug('Vitamines', Icons.medication_outlined),
      RoutineSug('Peser mon poids', Icons.monitor_weight_outlined, defaultFreq: HabitFreq.weekly),
    ],
  ),
  'Sport': DomainSug(
    activities: [
      ActivitySug('Musculation', Icons.fitness_center_outlined),
      ActivitySug('Running', Icons.directions_run_outlined),
      ActivitySug('Yoga', Icons.accessibility_new_outlined),
      ActivitySug('Natation', Icons.pool_outlined),
    ],
    routines: [
      RoutineSug('Séance de sport', Icons.fitness_center_outlined, linkedActivity: 'Musculation'),
      RoutineSug('Course à pied', Icons.directions_run_outlined, linkedActivity: 'Running'),
      RoutineSug('Yoga', Icons.accessibility_new_outlined, linkedActivity: 'Yoga'),
      RoutineSug('Étirements', Icons.sports_gymnastics),
    ],
  ),
  'Business': DomainSug(
    activities: [
      ActivitySug('Prospection', Icons.call_outlined),
      ActivitySug('Création de contenu', Icons.edit_outlined),
      ActivitySug('Admin', Icons.article_outlined),
      ActivitySug('Stratégie', Icons.trending_up_outlined),
    ],
    routines: [
      RoutineSug('Revue journalière', Icons.analytics_outlined),
      RoutineSug('Prospecter', Icons.call_outlined, linkedActivity: 'Prospection'),
      RoutineSug('Créer du contenu', Icons.edit_outlined, linkedActivity: 'Création de contenu'),
      RoutineSug("Gérer l'admin", Icons.article_outlined, defaultFreq: HabitFreq.weekly, linkedActivity: 'Admin'),
    ],
  ),
  'Organisation': DomainSug(
    activities: [
      ActivitySug('Planification', Icons.calendar_today_outlined),
      ActivitySug('Gestion des tâches', Icons.checklist),
      ActivitySug('Inbox', Icons.mail_outline),
    ],
    routines: [
      RoutineSug('Planifier ma journée', Icons.calendar_today_outlined, linkedActivity: 'Planification'),
      RoutineSug('Vider mon inbox', Icons.mail_outline, linkedActivity: 'Inbox'),
      RoutineSug('Journaling', Icons.edit_note_outlined),
      RoutineSug('Revue hebdo', Icons.date_range_outlined, defaultFreq: HabitFreq.weekly),
    ],
  ),
  'Finances': DomainSug(
    activities: [
      ActivitySug('Budget', Icons.calculate_outlined),
      ActivitySug('Investissement', Icons.trending_up_outlined),
    ],
    routines: [
      RoutineSug('Vérifier mon budget', Icons.calculate_outlined, linkedActivity: 'Budget'),
      RoutineSug('Épargner', Icons.savings, defaultFreq: HabitFreq.monthly),
      RoutineSug('Tracker mes dépenses', Icons.receipt_long),
    ],
  ),
  'Famille': DomainSug(
    activities: [
      ActivitySug('Temps famille', Icons.people_outline),
      ActivitySug('Appels proches', Icons.call_outlined),
    ],
    routines: [
      RoutineSug('Appeler ma famille', Icons.call_outlined, defaultFreq: HabitFreq.weekly, linkedActivity: 'Appels proches'),
      RoutineSug('Moment de qualité', Icons.favorite_outline, linkedActivity: 'Temps famille'),
    ],
  ),
  'Spiritualité': DomainSug(
    activities: [
      ActivitySug('Prière', Icons.church_outlined),
      ActivitySug('Lecture spirituelle', Icons.menu_book_outlined),
      ActivitySug('Méditation profonde', Icons.self_improvement_outlined),
    ],
    routines: [
      RoutineSug('Prier', Icons.church_outlined, linkedActivity: 'Prière'),
      RoutineSug('Lire', Icons.menu_book_outlined, linkedActivity: 'Lecture spirituelle'),
      RoutineSug('Gratitude', Icons.volunteer_activism_outlined),
    ],
  ),
  'Créativité': DomainSug(
    activities: [
      ActivitySug('Dessin', Icons.draw_outlined),
      ActivitySug('Écriture', Icons.edit_note_outlined),
      ActivitySug('Musique', Icons.music_note),
      ActivitySug('Photo / Vidéo', Icons.photo_camera_outlined),
    ],
    routines: [
      RoutineSug('Dessiner', Icons.draw_outlined, linkedActivity: 'Dessin'),
      RoutineSug('Écrire', Icons.edit_note_outlined, linkedActivity: 'Écriture'),
      RoutineSug('Jouer de la musique', Icons.music_note, linkedActivity: 'Musique'),
      RoutineSug('Photographier', Icons.photo_camera_outlined, linkedActivity: 'Photo / Vidéo'),
    ],
  ),
  'Apprentissage': DomainSug(
    activities: [
      ActivitySug('Lecture', Icons.menu_book_outlined),
      ActivitySug('Formation en ligne', Icons.school_outlined),
      ActivitySug('Pratique de langue', Icons.translate),
      ActivitySug('Podcast', Icons.headphones_outlined),
    ],
    routines: [
      RoutineSug('Lire 30 min', Icons.menu_book_outlined, linkedActivity: 'Lecture'),
      RoutineSug('Suivre une formation', Icons.school_outlined, linkedActivity: 'Formation en ligne'),
      RoutineSug('Pratiquer ma langue', Icons.translate, linkedActivity: 'Pratique de langue'),
      RoutineSug('Écouter un podcast', Icons.headphones_outlined, linkedActivity: 'Podcast'),
    ],
  ),
  'Social': DomainSug(
    activities: [
      ActivitySug('Réseau', Icons.handshake_outlined),
      ActivitySug('Sorties', Icons.groups_outlined),
    ],
    routines: [
      RoutineSug("Contacter quelqu'un", Icons.chat_bubble_outline, linkedActivity: 'Réseau'),
      RoutineSug('Sortir avec des amis', Icons.groups_outlined, defaultFreq: HabitFreq.weekly, linkedActivity: 'Sorties'),
    ],
  ),
  'Environnement': DomainSug(
    activities: [
      ActivitySug('Ménage', Icons.cleaning_services_outlined),
      ActivitySug('Lessive', Icons.local_laundry_service_outlined),
      ActivitySug('Vaisselle', Icons.kitchen_outlined),
      ActivitySug('Voiture', Icons.directions_car_outlined),
      ActivitySug('Rénovation', Icons.handyman_outlined),
    ],
    routines: [
      RoutineSug('Faire la vaisselle', Icons.kitchen_outlined, linkedActivity: 'Vaisselle'),
      RoutineSug('Passer l\'aspirateur', Icons.cleaning_services_outlined, defaultFreq: HabitFreq.weekly, linkedActivity: 'Ménage'),
      RoutineSug('Faire la lessive', Icons.local_laundry_service_outlined, defaultFreq: HabitFreq.weekly, linkedActivity: 'Lessive'),
      RoutineSug('Laver la voiture', Icons.directions_car_outlined, defaultFreq: HabitFreq.monthly, linkedActivity: 'Voiture'),
      RoutineSug('Ranger', Icons.chair_outlined),
    ],
  ),
  'Bien-être': DomainSug(
    activities: [
      ActivitySug('Relaxation', Icons.spa_outlined),
      ActivitySug('Journaling', Icons.edit_note_outlined),
    ],
    routines: [
      RoutineSug('Se relaxer', Icons.spa_outlined, linkedActivity: 'Relaxation'),
      RoutineSug('Journaling', Icons.edit_note_outlined, linkedActivity: 'Journaling'),
      RoutineSug('Douche froide', Icons.shower_outlined),
    ],
  ),
};

// ── Packs prédéfinis ─────────────────────────────────────────────────────────

class PackDef {
  final String emoji;
  final String name;
  final String description;
  final List<String> domains;
  final List<String> activities;
  final List<String> routines;
  const PackDef({
    required this.emoji,
    required this.name,
    required this.description,
    required this.domains,
    required this.activities,
    required this.routines,
  });
}

const kOnboardingPacks = [
  PackDef(
    emoji: '💪',
    name: 'Sport & Santé',
    description: 'Entraînement, nutrition et récupération',
    domains: ['Sport', 'Santé'],
    activities: ['Musculation', 'Running', 'Méditation', 'Hydratation', 'Sommeil'],
    routines: ['Séance de sport', 'Course à pied', 'Méditer', "Boire de l'eau", 'Vitamines', 'Peser mon poids'],
  ),
  PackDef(
    emoji: '🚀',
    name: 'Entrepreneur',
    description: 'Deep work, prospection et organisation',
    domains: ['Business', 'Organisation', 'Finances'],
    activities: ['Prospection', 'Création de contenu', 'Stratégie', 'Planification', 'Budget'],
    routines: ['Revue journalière', 'Prospecter', 'Créer du contenu', 'Planifier ma journée', 'Vider mon inbox', 'Revue hebdo', 'Vérifier mon budget'],
  ),
  PackDef(
    emoji: '🌱',
    name: 'Développement personnel',
    description: 'Lecture, bien-être et apprentissage',
    domains: ['Apprentissage', 'Bien-être', 'Organisation'],
    activities: ['Lecture', 'Formation en ligne', 'Relaxation', 'Journaling', 'Planification'],
    routines: ['Lire 30 min', 'Suivre une formation', 'Journaling', 'Se relaxer', 'Planifier ma journée', 'Douche froide', 'Gratitude'],
  ),
];

// ─── Fréquence label ─────────────────────────────────────────────────────────
String onboardingFreqLabel(HabitFreq f) => switch (f) {
      HabitFreq.daily => 'Quotidienne',
      HabitFreq.weekly => 'Hebdo',
      HabitFreq.monthly => 'Mensuelle',
    };
