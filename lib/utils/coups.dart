import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';

/// Coups tactiques (Modes et coups lot 3, 2026-10) : un objectif
/// `horizon: "tactical"` de 3 à 10 jours, UNE cible, sur un projet ou une
/// activité. Logique pure, aucune écriture.
const kCoupMinDays = 3;
const kCoupMaxDays = 10;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Jours restants, fin incluse (aujourd'hui = dernier jour → 1) ; null sans échéance.
int? coupDaysLeft(StrategicObjective o, DateTime today) {
  final end = o.endDate;
  if (end == null) return null;
  return _day(end).difference(_day(today)).inDays + 1;
}

String dayMonthFr(DateTime d) {
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${d.day} ${months[d.month - 1]}';
}

/// « jusqu'au 2 nov. · 4 j », « dernier jour », « terminé ».
String coupLabel(StrategicObjective o, DateTime today) {
  final left = coupDaysLeft(o, today);
  if (left == null) return 'sans échéance';
  if (left <= 0) return 'terminé';
  if (left == 1) return 'dernier jour';
  return 'jusqu\'au ${dayMonthFr(o.endDate!)} · $left j';
}

/// Validation à la création : titre, échéance entre 3 et 10 jours (fin incluse).
String? validateCoup({required String title, required DateTime? endDate, required DateTime today, required bool hasSource}) {
  if (title.trim().isEmpty) return 'Dis ce que tu vises.';
  if (endDate == null) return 'Choisis jusqu\'à quand.';
  final days = _day(endDate).difference(_day(today)).inDays + 1;
  if (days < kCoupMinDays) return 'Un rush dure au moins $kCoupMinDays jours.';
  if (days > kCoupMaxDays) return 'Un rush dure au plus $kCoupMaxDays jours — au-delà, c\'est un objectif.';
  if (!hasSource) return 'Rattache le rush à un projet ou à une activité.';
  return null;
}

/// La veille proposée avec un coup court jusqu'à sa fin (date incluse).
String coupRestUntil(StrategicObjective o) => ymdDashOf(o.endDate ?? DateTime.now());

/// Projets des coups en cours (En forme : passent en tête de Projets).
Set<String> coupProjectIds(Iterable<StrategicObjective> objectives, DateTime today) => {
      for (final o in objectives)
        if (o.isTactical && o.status == 'active' && (coupDaysLeft(o, today) ?? 1) > 0) ...o.projectIds,
    };

/// Domaine « du coup » : celui du projet ou de l'activité rattachée (jamais mis en veille d'office).
Set<String> coupDomainIds(StrategicObjective o, List<Project> projects, List<Activity> activities) => {
      if (o.domainId != null) o.domainId!,
      for (final p in projects)
        if (o.projectIds.contains(p.id) && p.domainId != null) p.domainId!,
      for (final a in activities)
        if (o.timeCommitments.any((c) => c.activityId == a.id) && a.domainId.isNotEmpty) a.domainId,
    };
