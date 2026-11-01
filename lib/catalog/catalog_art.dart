import 'package:productivitwo_v1/catalog/routine_catalog.dart';
import 'package:productivitwo_v1/models.dart';

/// Le dessin du catalogue pour les cartes de série (catalogue de routines,
/// lot 2) : routine → sa fiche du catalogue, par `Activity.catalogId`. Posé
/// à chaque recalcul du deck (`BadgeCenter`) et quand le catalogue serveur
/// arrive ; une routine créée à la main n'a pas de dessin (flamme).
class CatalogArt {
  static List<CatalogRoutine> _catalog = kRoutineCatalogSeed;
  static Map<String, CatalogRoutine> _byActivity = const {};

  static void setCatalog(List<CatalogRoutine> remote) {
    if (remote.isEmpty) return;
    _catalog = remote;
  }

  static void setActivities(Iterable<Activity> activities) {
    final byId = {for (final c in _catalog) c.id: c};
    _byActivity = {
      for (final a in activities)
        if (a.catalogId != null && byId[a.catalogId] != null) a.id: byId[a.catalogId]!,
    };
  }

  /// La fiche du catalogue d'une routine (id d'activité), null sans dessin.
  static CatalogRoutine? forActivity(String? activityId) => activityId == null ? null : _byActivity[activityId];
}
