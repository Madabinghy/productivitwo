import 'package:productivitwo_v1/models.dart';

// Routines branchées sur une fonctionnalité de l'app (2026-11-04, retour user) :
// « Planifier ma journée » ouvre l'écran de planification et se coche quand la
// journée est posée ; « Boire de l'eau » se coche au point d'étape de la
// Guérilla. Carte du catalogue d'abord, sinon le nom.

const kPlanRoutineCatalogId = 'planifier-journee';
const kWaterRoutineCatalogId = 'boire-eau';

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('’', "'");

/// « Planifier ma journée », « Planifier demain », « Plan du jour »…
bool isPlanRoutineName(String name) {
  final n = _fold(name);
  final plan = n.contains('planifi') || RegExp(r'\bplan\b').hasMatch(n) || n.contains('programmer');
  final day = n.contains('journee') || n.contains('demain') || RegExp(r'\bjour\b').hasMatch(n) || n.contains('ma semaine');
  return plan && day;
}

/// « Boire de l'eau », « Verre d'eau », « Hydratation »…
bool isWaterRoutineName(String name) {
  final n = _fold(name);
  return n.contains('hydrat') || RegExp(r"\beau\b|d'eau").hasMatch(n);
}

Activity? _routineOf(List<Activity> acts, String catalogId, bool Function(String) byName) {
  final rs = acts.where((a) => !a.deleted && a.isHabit).toList();
  return rs.where((a) => a.catalogId == catalogId).firstOrNull ?? rs.where((a) => byName(a.name)).firstOrNull;
}

Activity? planRoutineOf(List<Activity> acts) => _routineOf(acts, kPlanRoutineCatalogId, isPlanRoutineName);
Activity? waterRoutineOf(List<Activity> acts) => _routineOf(acts, kWaterRoutineCatalogId, isWaterRoutineName);

bool isPlanRoutine(Activity a) => a.catalogId == kPlanRoutineCatalogId || (a.catalogId == null && isPlanRoutineName(a.name));
