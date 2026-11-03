import 'dart:math' as math;

import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/interventions.dart' show isMilestoneTask;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedNowMin;
import 'package:productivitwo_v1/utils/recharge.dart' show isBasicNeedName;
import 'package:productivitwo_v1/utils/today_logic.dart' show blockEndMin, blockStartMin;

/// « Plongé, pas perdu » (maquette validée 2026-11-03) : pendant un deep work,
/// seule une chose DATÉE peut déranger — un rendez-vous de l'agenda (miroir) ou
/// une séance (bloc qui vise la tâche 🎯 d'une intervention). Les blocs
/// souples, routines et actions attendent le point d'étape ou le retour.

/// Minutes avant le rendez-vous où sonne l'alarme d'atterrissage.
const kLandingLeadMin = 10;

/// Ids des tâches de séance (🎯) des projets : un bloc qui en vise une est daté.
Set<String> sessionTaskIdsOf(Iterable<Project> projects) => {
      for (final p in projects)
        for (final t in p.tasks)
          if (isMilestoneTask(t)) t.id,
    };

/// Bloc daté : à faire, pas un bloc de temps, pas un besoin de base (sommeil,
/// repas), et un rendez-vous d'agenda ou une séance.
bool isFixedBlock(ScheduleBlock b, {Set<String> sessionTaskIds = const {}}) =>
    b.status == 'pending' &&
    !b.isTimeBlock &&
    !isBasicNeedName(b.title) &&
    (b.gcalEventId != null || (b.taskId != null && sessionTaskIds.contains(b.taskId)));

class FixedAhead {
  final ScheduleBlock block;
  /// Heure de début réelle.
  final DateTime at;
  /// Minutes d'ici là (arrondies vers le haut, 0 = maintenant).
  final int inMin;
  const FixedAhead(this.block, this.at, this.inMin);

  DateTime get landingAt => at.subtract(const Duration(minutes: kLandingLeadMin));
}

/// Prochain bloc daté de la journée vécue qui n'a pas encore commencé.
FixedAhead? nextFixed(List<ScheduleBlock> blocks, DateTime now, int dayStartMin, {Set<String> sessionTaskIds = const {}}) {
  final nowMin = livedNowMin(now, dayStartMin);
  final base = DateTime(now.year, now.month, now.day, now.hour, now.minute);
  ScheduleBlock? best;
  for (final b in blocks) {
    if (!isFixedBlock(b, sessionTaskIds: sessionTaskIds)) continue;
    if (blockStartMin(b) < nowMin) continue;
    if (best == null || blockStartMin(b) < blockStartMin(best)) best = b;
  }
  if (best == null) return null;
  final at = base.add(Duration(minutes: blockStartMin(best) - nowMin));
  final inMin = (at.difference(now).inSeconds / 60).ceil();
  return FixedAhead(best, at, inMin < 0 ? 0 : inMin);
}

/// « dans 35 min » · « dans 1 h 05 » · « maintenant ».
String inLabel(int min) {
  if (min <= 0) return 'maintenant';
  if (min < 60) return 'dans $min min';
  final h = min ~/ 60, m = min % 60;
  return m == 0 ? 'dans $h h' : 'dans $h h ${m.toString().padLeft(2, '0')}';
}

/// Le point d'étape (lot 2) : les prochains blocs à faire de la journée, datés
/// ou souples, sans les besoins de base ; [limit] au plus.
List<({ScheduleBlock block, DateTime at, bool fixed})> upcomingBlocks(List<ScheduleBlock> blocks, DateTime now, int dayStartMin,
    {Set<String> sessionTaskIds = const {}, int limit = 3}) {
  final nowMin = livedNowMin(now, dayStartMin);
  final base = DateTime(now.year, now.month, now.day, now.hour, now.minute);
  final list = blocks.where((b) => b.status == 'pending' && blockStartMin(b) >= nowMin && !isBasicNeedName(b.title)).toList()
    ..sort((a, b) => blockStartMin(a).compareTo(blockStartMin(b)));
  return [
    for (final b in list.take(limit))
      (block: b, at: base.add(Duration(minutes: blockStartMin(b) - nowMin)), fixed: isFixedBlock(b, sessionTaskIds: sessionTaskIds)),
  ];
}

/// Série qui se perd ce soir si rien n'est fait : routine quotidienne pas encore
/// atteinte aujourd'hui, avec une série d'au moins 2 jours jusqu'à hier.
class SeriesAtRisk {
  final String name;
  final int count;
  final int target;
  final int streak;
  final String id;
  const SeriesAtRisk(this.name, this.count, this.target, this.streak, {this.id = ''});
}

List<SeriesAtRisk> seriesAtRisk(Iterable<SeriesAtRisk> routines, {int limit = 3}) {
  final l = routines.where((r) => r.count < r.target && r.streak >= 2).toList()..sort((a, b) => b.streak.compareTo(a.streak));
  return l.take(limit).toList();
}

/// Fin du bloc Deep work (lot 3) : le bloc Deep work à faire qui contient maintenant.
ScheduleBlock? currentDeepBlock(List<ScheduleBlock> blocks, DateTime now, int dayStartMin) {
  final nowMin = livedNowMin(now, dayStartMin);
  for (final b in blocks) {
    if (b.timeBlock == 'deep' && b.status == 'pending' && blockStartMin(b) <= nowMin && nowMin < blockEndMin(b)) return b;
  }
  return null;
}

/// Les blocs souples qui suivent [after] jusqu'au prochain bloc daté (exclu) :
/// ce que « Continuer » décale. Jamais un daté, un besoin de base ni un bloc de nuit.
List<ScheduleBlock> softFollowing(List<ScheduleBlock> blocks, ScheduleBlock after, {Set<String> sessionTaskIds = const {}}) {
  final from = blockEndMin(after);
  final fixedStarts = [
    for (final b in blocks)
      if (b.id != after.id && isFixedBlock(b, sessionTaskIds: sessionTaskIds) && blockStartMin(b) >= from) blockStartMin(b),
  ]..sort();
  final until = fixedStarts.isEmpty ? 24 * 60 : fixedStarts.first;
  final l = blocks
      .where((b) =>
          b.id != after.id &&
          b.status == 'pending' &&
          b.dayOffset == 0 &&
          !isFixedBlock(b, sessionTaskIds: sessionTaskIds) &&
          b.gcalEventId == null &&
          !isBasicNeedName(b.title) &&
          blockStartMin(b) >= from &&
          blockStartMin(b) < until)
      .toList()
    ..sort((a, b) => blockStartMin(a).compareTo(blockStartMin(b)));
  return l;
}

/// Minutes que « Continuer » peut ajouter sans entamer l'atterrissage du
/// prochain daté : au plus [wanted], par 5 min ; 0 = pas la place (< 10 min).
int continueRoom(List<ScheduleBlock> blocks, ScheduleBlock after, {Set<String> sessionTaskIds = const {}, int wanted = 30}) {
  final from = blockEndMin(after);
  var room = wanted;
  for (final b in blocks) {
    if (b.id == after.id || !isFixedBlock(b, sessionTaskIds: sessionTaskIds)) continue;
    final s = blockStartMin(b);
    if (s < from) continue;
    final free = s - kLandingLeadMin - from;
    if (free < room) room = free;
  }
  room = room - room % 5;
  return room < 10 ? 0 : room;
}

/// « HH:MM » d'une minute de la journée vécue.
String hmOf(int min) {
  final m = min % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// « Continuer [delta] min » : le bloc Deep work s'allonge, les blocs souples
/// qui le suivent jusqu'au prochain daté reculent d'autant (plafond minuit).
/// Modifie en place et retourne tout ce qui a changé (le bloc compris).
List<ScheduleBlock> extendDeep(List<ScheduleBlock> blocks, ScheduleBlock deep, int delta, {Set<String> sessionTaskIds = const {}}) {
  if (delta <= 0) return const [];
  final soft = softFollowing(blocks, deep, sessionTaskIds: sessionTaskIds);
  deep.durationMin += delta;
  final changed = <ScheduleBlock>[deep];
  for (final b in soft) {
    final start = blockStartMin(b);
    final next = math.min(start + delta, 24 * 60 - b.durationMin);
    if (next <= start) continue;
    b.startTime = hmOf(next);
    changed.add(b);
  }
  return changed;
}

/// Reprise (lot 4) : les blocs à faire passés pendant qu'on était dedans —
/// finis entre [since] (fin du coup en cours quand on a quitté l'écran) et
/// maintenant ; ni bloc de temps, ni besoin de base.
List<ScheduleBlock> missedWhileAway(List<ScheduleBlock> blocks, DateTime since, DateTime now, int dayStartMin) {
  final nowMin = livedNowMin(now, dayStartMin);
  final sinceMin = now.difference(since).inMinutes >= nowMin ? 0 : nowMin - now.difference(since).inMinutes;
  final l = blocks
      .where((b) =>
          b.status == 'pending' &&
          !b.isTimeBlock &&
          !isBasicNeedName(b.title) &&
          blockEndMin(b) > sinceMin &&
          blockEndMin(b) <= nowMin)
      .toList()
    ..sort((a, b) => blockStartMin(a).compareTo(blockStartMin(b)));
  return l;
}
