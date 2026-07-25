import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

/// Résumé partagé coach-coaché (Espace Coach V1.1, US-2).
///
/// Construit PAR L'APP DU COACHÉ, à partir de son AppState, et écrit dans
/// `coach_links/{id}/data/summary`. C'est la SEULE chose que le coach lit :
/// - minimisation par construction — un domaine non partagé n'entre jamais
///   dans le résumé, même agrégé (règle produit n°5 du design) ;
/// - zéro double saisie — tout vient de l'usage normal de l'app ;
/// - les états d'énergie (À fond / Correct / À plat) ne sont JAMAIS inclus
///   (règle n°6 : étanchéité).

DateTime _mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Engagement hebdo dérivé d'une routine : cible de la semaine + réalisé.
({int target, int done}) _weekEngagement(
    Activity habit, List<HabitHit> hits, DateTime weekStart) {
  final weekEnd = weekStart.add(const Duration(days: 7));
  final done = hits
      .where((h) =>
          h.habitId == habit.id &&
          !h.ts.isBefore(weekStart) &&
          h.ts.isBefore(weekEnd))
      .length;
  // habitTarget est nullable : cible par défaut 1 (routine simple).
  final base = habit.habitTarget ?? 1;
  final target = habit.habitFreq == HabitFreq.daily ? base * 7 : base;
  return (target: target <= 0 ? 1 : target, done: done);
}

/// Construit le résumé pour un périmètre donné. [granularity] :
/// 'status' = compteurs tenus/en retard seulement ; 'detail' = + minutes par
/// activité de la semaine.
Map<String, dynamic> buildCoachSummary(
  AppState state, {
  required List<String> domainIds,
  required String granularity,
}) {
  final now = DateTime.now();
  final weekStart = _mondayOf(now);
  final shared = domainIds.toSet();

  final sharedActivities = state.activities
      .where((a) => !a.deleted && shared.contains(a.domainId))
      .toList();
  final sharedIds = sharedActivities.map((a) => a.id).toSet();
  final habits = sharedActivities
      .where((a) => a.isHabit && a.habitFreq != HabitFreq.monthly)
      .toList();

  // Engagements de la semaine en cours.
  final engagements = <Map<String, dynamic>>[];
  for (final h in habits) {
    final e = _weekEngagement(h, state.habitHits, weekStart);
    engagements.add({
      'id': h.id,
      'domainId': h.domainId,
      'label': h.name,
      'target': e.target,
      'done': e.done,
      'kept': e.done >= e.target,
    });
  }

  // Tendance : % d'engagements tenus sur les 4 dernières semaines
  // (S-3 → semaine en cours).
  final weeks = <Map<String, dynamic>>[];
  for (var i = 3; i >= 0; i--) {
    final ws = weekStart.subtract(Duration(days: 7 * i));
    var kept = 0;
    for (final h in habits) {
      final e = _weekEngagement(h, state.habitHits, ws);
      if (e.done >= e.target) kept++;
    }
    weeks.add({
      'startYmd': _ymd(ws),
      'pct': habits.isEmpty ? 0 : ((kept / habits.length) * 100).round(),
    });
  }

  // Dernière activité — dans le périmètre partagé uniquement.
  DateTime? last;
  for (final s in state.sessions) {
    if (!sharedIds.contains(s.activityId)) continue;
    if (last == null || s.startAt.isAfter(last)) last = s.startAt;
  }
  for (final h in state.habitHits) {
    if (!sharedIds.contains(h.habitId)) continue;
    if (last == null || h.ts.isAfter(last)) last = h.ts;
  }

  // Détail (opt-in) : minutes de la semaine par activité-temps partagée.
  Map<String, int>? timeMin;
  if (granularity == 'detail') {
    timeMin = {};
    for (final s in state.sessions) {
      if (s.startAt.isBefore(weekStart)) continue;
      final act = sharedActivities
          .where((a) => a.id == s.activityId && !a.isHabit)
          .firstOrNull;
      if (act == null) continue;
      timeMin[act.name] = (timeMin[act.name] ?? 0) + s.duration.inMinutes;
    }
  }

  final domainNames = {
    for (final d in state.domains)
      if (shared.contains(d.id)) d.id: d.name,
  };

  return {
    'updatedAt': DateTime.now().toIso8601String(),
    'weekStartYmd': _ymd(weekStart),
    'granularity': granularity,
    'domains': domainNames,
    'engagements': engagements,
    'keptCount': engagements.where((e) => e['kept'] == true).length,
    'totalCount': engagements.length,
    'weeks': weeks,
    'lastActivityAt': last?.toIso8601String(),
    if (timeMin != null) 'timeMinByActivity': timeMin,
  };
}

/// Recalcule et pousse le résumé si un lien coach actif existe.
/// Appelé au démarrage de l'app et à chaque changement de consentement —
/// fire-and-forget, jamais bloquant.
Future<void> refreshCoachSummaryIfLinked(
    AppState state, FirestoreSync sync) async {
  try {
    final link = await sync.myCoachLinkAsCoachee();
    if (link == null || !link.isActive) return;
    if (link.sharedDomainIds.isEmpty) return; // rien de partagé, rien d'écrit
    await sync.writeCoachSummary(
      link.id,
      buildCoachSummary(state,
          domainIds: link.sharedDomainIds, granularity: link.granularity),
    );
  } catch (_) {}
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
