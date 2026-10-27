import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show mondayOf;
import 'package:productivitwo_v1/utils/week_stats.dart' show minutesByActivity;

/// Budget des minimums de domaine (Modes et coups lot 4, 2026-10) : l'attendu
/// n'est plus « minimum × jours écoulés de la semaine » mais sur une fenêtre de
/// [days] jours à DÉPART FIXE — 7 = la semaine calendaire (lundi), 14 = la
/// quinzaine calée sur des blocs de deux semaines depuis le lundi 5 janvier
/// 2026. Pousser 3 jours sur un sujet puis le lâcher 5 jours reste « au
/// rythme » ; le repère « attendu aujourd'hui » garde son sens.
final DateTime kFortnightAnchor = DateTime(2026, 1, 5); // un lundi

/// Début de la fenêtre courante ([days] = 7 ou 14).
DateTime budgetWindowStart(DateTime now, int days) {
  final monday = mondayOf(now);
  if (days != 14) return monday;
  final weeks = monday.difference(kFortnightAnchor).inDays ~/ 7;
  return weeks.isEven ? monday : monday.subtract(const Duration(days: 7));
}

/// Jour courant dans la fenêtre (1 = premier jour).
int budgetDayIndex(DateTime now, int days) {
  final start = budgetWindowStart(now, days);
  return DateTime(now.year, now.month, now.day).difference(start).inDays + 1;
}

/// Minutes de chrono par domaine et par jour sur [days] jours depuis [start]
/// (une session à cheval sur minuit est coupée au jour). Index 0 = [start].
Map<String, List<int>> dailyMinutesByDomain(
  List<Session> sessions,
  List<Activity> activities,
  DateTime start,
  int days, {
  required DateTime now,
}) {
  final domainOf = {for (final a in activities) a.id: a.domainId};
  final out = <String, List<int>>{};
  for (var i = 0; i < days; i++) {
    final from = DateTime(start.year, start.month, start.day + i);
    final to = DateTime(start.year, start.month, start.day + i + 1);
    if (from.isAfter(now)) break;
    final m = minutesByActivity(sessions, from, to.isAfter(now) ? now : to);
    m.forEach((id, min) {
      final d = domainOf[id];
      if (d == null) return;
      final row = out.putIfAbsent(d, () => List<int>.filled(days, 0));
      row[i] += min;
    });
  }
  return out;
}

/// « 14 j · jour 9 », « semaine · jour 3 ».
String budgetWindowLabel(DateTime now, int days) => '${days == 14 ? '14 j' : 'semaine'} · jour ${budgetDayIndex(now, days)} / $days';
