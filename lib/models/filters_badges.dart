part of '../models.dart';

class FilterState {
  bool enabled; // toggle global "Filtré"
  bool focusOnly; // mode Focus ⭐ (optionnel ici)
  Set<String> domainIds;
  Set<String> activityIds;
  Set<String> contextIds; // si tu as une notion de contexte
  bool includeNoDomain;
  bool includeNoActivity;

  FilterState({
    this.enabled = true,
    this.focusOnly = false,
    Set<String>? domainIds,
    Set<String>? activityIds,
    Set<String>? contextIds,
    this.includeNoDomain = true,
    this.includeNoActivity = true,
  })  : domainIds = domainIds ?? <String>{},
        activityIds = activityIds ?? <String>{},
        contextIds = contextIds ?? <String>{};

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'focusOnly': focusOnly,
        'domainIds': domainIds.toList(),
        'activityIds': activityIds.toList(),
        'contextIds': contextIds.toList(),
        'includeNoDomain': includeNoDomain,
        'includeNoActivity': includeNoActivity,
      };

  static FilterState from(dynamic j) {
    if (j == null) return FilterState();
    final m = j as Map;
    return FilterState(
      enabled: (m['enabled'] as bool?) ?? false,
      focusOnly: (m['focusOnly'] as bool?) ?? false,
      domainIds: ((m['domainIds'] as List?)?.cast<String>() ?? const <String>[])
          .toSet(),
      activityIds:
          ((m['activityIds'] as List?)?.cast<String>() ?? const <String>[])
              .toSet(),
      contextIds:
          ((m['contextIds'] as List?)?.cast<String>() ?? const <String>[])
              .toSet(),
      includeNoDomain: (m['includeNoDomain'] as bool?) ?? true,
      includeNoActivity: (m['includeNoActivity'] as bool?) ?? true,
    );
  }

  bool get isActive => domainIds.isNotEmpty || activityIds.isNotEmpty;
}

// ─── Badges ──────────────────────────────────────────────────────────────────

enum BadgeId {
  streak3, streak7, streak21, streak66, streak100,
  scoreFirst100, score7dAt80, score30dAt80,
  actions10, actions50, actions100,
  actions200, actions300, actions500, actions750, actions1000,
  actions1500, actions2000, actions3000, actions5000, actions7500, actions10000,
}

class BadgeMeta {
  final String emoji;
  final String label;
  final String description;
  const BadgeMeta(this.emoji, this.label, this.description);
}

BadgeMeta badgeMeta(BadgeId id) {
  switch (id) {
    case BadgeId.streak3:      return const BadgeMeta('🔥', '3 jours',        'Série de 3 jours d\'affilée');
    case BadgeId.streak7:      return const BadgeMeta('🔥', '7 jours',        'Une semaine sans fauter');
    case BadgeId.streak21:     return const BadgeMeta('⚡', '21 jours',       'L\'habitude est prise');
    case BadgeId.streak66:     return const BadgeMeta('💎', '66 jours',       'Ancré dans le quotidien');
    case BadgeId.streak100:    return const BadgeMeta('👑', '100 jours',      'Centurion');
    case BadgeId.scoreFirst100:return const BadgeMeta('⭐', 'Journée parfaite','Première journée à 100%');
    case BadgeId.score7dAt80:  return const BadgeMeta('🌟', 'Semaine solide', '7 jours consécutifs à 80%+');
    case BadgeId.score30dAt80: return const BadgeMeta('🌟', 'Mois solide',    '30 jours consécutifs à 80%+');
    case BadgeId.actions10:    return const BadgeMeta('🎯', '10 actions',   '10 tâches ou sous-actions Gantt validées');
    case BadgeId.actions50:    return const BadgeMeta('🎯', '50 actions',   '50 tâches ou sous-actions Gantt validées');
    case BadgeId.actions100:   return const BadgeMeta('🏆', '100 actions',  '100 tâches ou sous-actions Gantt validées');
    case BadgeId.actions200:   return const BadgeMeta('🏆', '200 actions',  '200 tâches ou sous-actions Gantt validées');
    case BadgeId.actions300:   return const BadgeMeta('💎', '300 actions',  '300 tâches ou sous-actions Gantt validées');
    case BadgeId.actions500:   return const BadgeMeta('💎', '500 actions',  '500 tâches ou sous-actions Gantt validées');
    case BadgeId.actions750:   return const BadgeMeta('👑', '750 actions',   '750 tâches ou sous-actions Gantt validées');
    case BadgeId.actions1000:  return const BadgeMeta('👑', '1 000 actions',  '1 000 tâches ou sous-actions Gantt validées');
    case BadgeId.actions1500:  return const BadgeMeta('🌠', '1 500 actions',  '1 500 tâches ou sous-actions Gantt validées');
    case BadgeId.actions2000:  return const BadgeMeta('🌠', '2 000 actions',  '2 000 tâches ou sous-actions Gantt validées');
    case BadgeId.actions3000:  return const BadgeMeta('🔮', '3 000 actions',  '3 000 tâches ou sous-actions Gantt validées');
    case BadgeId.actions5000:  return const BadgeMeta('🔮', '5 000 actions',  '5 000 tâches ou sous-actions Gantt validées');
    case BadgeId.actions7500:  return const BadgeMeta('🌌', '7 500 actions',  '7 500 tâches ou sous-actions Gantt validées');
    case BadgeId.actions10000: return const BadgeMeta('🌌', '10 000 actions', 'Légende Productivitwo');
  }
}

class EarnedBadge {
  final BadgeId id;
  final String? habitId; // null = badge global
  final String earnedAt; // yyyymmdd

  EarnedBadge({required this.id, this.habitId, required this.earnedAt});

  /// ID composite utilisé comme clé Firestore : "streak3_activityId" ou "actions10_"
  String get docId => '${id.name}_${habitId ?? ""}';

  Map<String, dynamic> toJson() => {
    'id': docId,       // clé Firestore unique (compatible habitId multiple)
    'badgeId': id.name, // type de badge pour la désérialisation
    if (habitId != null) 'habitId': habitId,
    'earnedAt': earnedAt,
  };

  static EarnedBadge? tryFrom(dynamic j) {
    try {
      final m = j as Map;
      // Supporte l'ancien format (id = badgeName) et le nouveau (id = composite, badgeId = badgeName)
      final badgeName = (m['badgeId'] ?? m['id']) as String;
      // Pour l'ancien format, le badgeName peut contenir "_activityId" — extraire la partie badge
      final cleanName = badgeName.contains('_') && !BadgeId.values.any((b) => b.name == badgeName)
          ? badgeName.split('_').first
          : badgeName;
      final id = BadgeId.values.firstWhere((b) => b.name == cleanName);
      return EarnedBadge(
        id: id,
        habitId: m['habitId'] as String?,
        earnedAt: m['earnedAt'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
