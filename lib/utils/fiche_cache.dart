import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

/// Données des fiches relues en arrière-plan (2026-10-30, retour user : la
/// page domaine et la fiche d'activité « bougeaient » à l'ouverture, les
/// objectifs et les déroulés arrivant après coup). La page domaine précharge
/// les objectifs AVANT de s'ouvrir et les déroulés de ses activités ; les
/// fiches partent du cache et ne se redessinent que si la relecture diffère.
class FicheCache {
  FicheCache._();
  static List<StrategicObjective>? objectives;
  static final Map<String, List<SessionTemplate>> templates = {};

  static Future<List<StrategicObjective>> loadObjectives(FirestoreSync sync) async {
    final all = await sync.fetchStrategicObjectives();
    objectives = all;
    return all;
  }

  /// Le cache tout de suite s'il existe (relu derrière), sinon la lecture,
  /// bornée par [wait] pour ne jamais retenir l'ouverture.
  static Future<List<StrategicObjective>?> objectivesFast(FirestoreSync sync, {Duration wait = const Duration(milliseconds: 700)}) async {
    final cached = objectives;
    final fresh = loadObjectives(sync);
    if (cached != null) {
      fresh.ignore();
      return cached;
    }
    try {
      return await fresh.timeout(wait);
    } catch (_) {
      return objectives;
    }
  }

  static Future<List<SessionTemplate>> loadTemplates(FirestoreSync sync, String activityId) async {
    final t = await sync.fetchSessionTemplates(activityId: activityId);
    templates[activityId] = t;
    return t;
  }

  /// Même contenu (ids + date de mise à jour) : pas la peine de redessiner.
  static bool sameObjectives(List<StrategicObjective>? a, List<StrategicObjective>? b) {
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].updatedAt != b[i].updatedAt || a[i].status != b[i].status) return false;
    }
    return true;
  }

  static bool sameTemplates(List<SessionTemplate>? a, List<SessionTemplate>? b) {
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].toJson().toString() != b[i].toJson().toString()) return false;
    }
    return true;
  }
}
