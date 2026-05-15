import 'package:flutter/material.dart';

// Icônes curated pour les routines, par catégorie.
// `final` (pas const) car IconData n'est pas une constante compile-time.
final _categories = [
  (
    'Santé & Corps',
    [
      (Icons.water_drop_outlined, 'Eau'),
      (Icons.bedtime_outlined, 'Sommeil'),
      (Icons.medication_outlined, 'Médicament'),
      (Icons.health_and_safety_outlined, 'Santé'),
      (Icons.spa_outlined, 'Bien-être'),
      (Icons.self_improvement_outlined, 'Méditation'),
      (Icons.face_outlined, 'Soin visage'),
      (Icons.shower_outlined, 'Douche'),
      (Icons.mood_outlined, 'Humeur'),
      (Icons.thermostat_outlined, 'Température'),
      (Icons.local_hospital_outlined, 'Médecin'),
      (Icons.healing_outlined, 'Soin'),
      (Icons.visibility_outlined, 'Vue'),
      (Icons.air, 'Respiration'),
      (Icons.nights_stay_outlined, 'Nuit'),
      (Icons.elderly_outlined, 'Posture'),
      (Icons.vaccines_outlined, 'Vaccin'),
      (Icons.monitor_weight_outlined, 'Poids'),
    ]
  ),
  (
    'Sport & Mouvement',
    [
      (Icons.fitness_center_outlined, 'Musculation'),
      (Icons.directions_run_outlined, 'Course'),
      (Icons.directions_bike_outlined, 'Vélo'),
      (Icons.pool_outlined, 'Natation'),
      (Icons.hiking_outlined, 'Marche'),
      (Icons.sports_outlined, 'Sport'),
      (Icons.accessibility_new_outlined, 'Étirements'),
      (Icons.nordic_walking_outlined, 'Cardio'),
      (Icons.sports_martial_arts, 'Arts martiaux'),
      (Icons.sports_gymnastics, 'Gym'),
      (Icons.skateboarding, 'Skate'),
      (Icons.surfing, 'Surf'),
      (Icons.snowboarding, 'Snow'),
      (Icons.rowing, 'Aviron'),
      (Icons.sports_tennis, 'Tennis'),
      (Icons.sports_soccer, 'Foot'),
    ]
  ),
  (
    'Alimentation',
    [
      (Icons.restaurant_outlined, 'Repas'),
      (Icons.breakfast_dining_outlined, 'Petit-déj'),
      (Icons.lunch_dining_outlined, 'Déjeuner'),
      (Icons.no_food_outlined, 'Jeûne'),
      (Icons.local_cafe_outlined, 'Café'),
      (Icons.blender_outlined, 'Smoothie'),
      (Icons.kitchen_outlined, 'Cuisine'),
      (Icons.bakery_dining_outlined, 'Pain'),
      (Icons.rice_bowl_outlined, 'Riz'),
      (Icons.local_pizza_outlined, 'Pizza'),
      (Icons.set_meal_outlined, 'Plateau'),
      (Icons.local_bar_outlined, 'Boisson'),
      (Icons.egg_alt_outlined, 'Œuf'),
      (Icons.icecream_outlined, 'Dessert'),
    ]
  ),
  (
    'Mental & Spirituel',
    [
      (Icons.menu_book_outlined, 'Lecture'),
      (Icons.edit_note_outlined, 'Journal'),
      (Icons.lightbulb_outlined, 'Idées'),
      (Icons.psychology_outlined, 'Réflexion'),
      (Icons.volunteer_activism_outlined, 'Gratitude'),
      (Icons.church_outlined, 'Prière'),
      (Icons.wb_sunny_outlined, 'Matin'),
      (Icons.auto_stories_outlined, 'Histoires'),
      (Icons.music_note, 'Musique'),
      (Icons.nature_outlined, 'Nature'),
      (Icons.star_outline, 'Étoile'),
      (Icons.local_florist_outlined, 'Fleur'),
      (Icons.celebration_outlined, 'Célébration'),
      (Icons.emoji_nature_outlined, 'Plein air'),
    ]
  ),
  (
    'Travail & Apprentissage',
    [
      (Icons.laptop_outlined, 'Travail'),
      (Icons.school_outlined, 'Formation'),
      (Icons.code_outlined, 'Code'),
      (Icons.draw_outlined, 'Dessin'),
      (Icons.headphones_outlined, 'Podcast'),
      (Icons.calculate_outlined, 'Finances'),
      (Icons.trending_up_outlined, 'Objectifs'),
      (Icons.business_center_outlined, 'Business'),
      (Icons.analytics_outlined, 'Analytics'),
      (Icons.email_outlined, 'Email'),
      (Icons.videocam_outlined, 'Vidéo'),
      (Icons.mic_outlined, 'Micro'),
      (Icons.brush_outlined, 'Pinceau'),
      (Icons.photo_camera_outlined, 'Photo'),
    ]
  ),
  (
    'Maison & Quotidien',
    [
      (Icons.cleaning_services_outlined, 'Ménage'),
      (Icons.local_laundry_service_outlined, 'Lessive'),
      (Icons.yard_outlined, 'Jardin'),
      (Icons.pets_outlined, 'Animal'),
      (Icons.shopping_cart_outlined, 'Courses'),
      (Icons.home_outlined, 'Maison'),
      (Icons.chair_outlined, 'Rangement'),
      (Icons.bed_outlined, 'Lit'),
      (Icons.bathtub_outlined, 'Bain'),
      (Icons.deck_outlined, 'Terrasse'),
      (Icons.garage_outlined, 'Garage'),
      (Icons.countertops_outlined, 'Cuisine'),
    ]
  ),
  (
    'Social & Famille',
    [
      (Icons.people_outline, 'Famille'),
      (Icons.chat_bubble_outline, 'Amis'),
      (Icons.call_outlined, 'Appel'),
      (Icons.favorite_outline, 'Relation'),
      (Icons.handshake_outlined, 'Réseau'),
      (Icons.groups_outlined, 'Groupe'),
      (Icons.emoji_events_outlined, 'Trophée'),
      (Icons.card_giftcard_outlined, 'Cadeau'),
      (Icons.sports_esports_outlined, 'Jeux'),
      (Icons.diversity_3_outlined, 'Communauté'),
    ]
  ),
];

Future<int?> showIconPickerSheet(
  BuildContext context, {
  int? current,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _IconPickerSheet(current: current),
  );
}

class _IconPickerSheet extends StatelessWidget {
  final int? current;
  const _IconPickerSheet({this.current});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Choisir une icône',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              if (current != null)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, -1), // -1 = supprimer
                  child: const Text('Retirer'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (label, icons) in _categories) ...[
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withOpacity(.45),
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (iconData, tooltip) in icons)
                  _IconChip(
                    iconData: iconData,
                    tooltip: tooltip,
                    selected: current == iconData.codePoint,
                    onTap: () => Navigator.pop(ctx, iconData.codePoint),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData iconData;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _IconChip({
    required this.iconData,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected
                ? cs.primaryContainer
                : cs.surfaceContainerHighest.withOpacity(.5),
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: cs.primary, width: 2)
                : Border.all(color: Colors.transparent),
          ),
          child: Icon(
            iconData,
            size: 22,
            color: selected ? cs.primary : cs.onSurface.withOpacity(.65),
          ),
        ),
      ),
    );
  }
}
