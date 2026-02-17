// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../app_logic.dart';

DateTime startOfDay(DateTime now, {int dayStartHour = 0}) {
  final s = DateTime(now.year, now.month, now.day, dayStartHour);
  return now.isBefore(s) ? s.subtract(const Duration(days: 1)) : s;
}

double pacingFractionDay(DateTime now, {int dayStartHour = 0}) {
  final s = startOfDay(now, dayStartHour: dayStartHour);
  final elapsed = now.difference(s).inSeconds.clamp(0, 24 * 3600);
  return elapsed / (24 * 3600);
}

/// Pacing agrégé (MVP) pour les habitudes "count" quotidiennes
class HabitPacingAgg {
  final int target; // somme des cibles quotidiennes du périmètre
  final int done;   // somme des valeurs faites aujourd’hui
  final int pace;   // cible attendue à cette heure
  final int delta;  // done - pace (positif = en avance)
  HabitPacingAgg({required this.target, required this.done, required this.pace, required this.delta});
}

/// Agrège pour: domaine donné OU tous domaines si domainId == null
HabitPacingAgg computeDailyPacingAggregate(AppLogic logic, {String? domainId, int dayStartHour = 0}) {
  final now = DateTime.now();

  // 1) liste des habitudes "count" quotidiennes du périmètre
  final acts = logic.state.activities.where((a) {
    final inDom = (domainId == null) ? true : a.domainId == domainId;
    final isCountDaily = a.isHabit; // MVP: on traite tout "habit" comme 'count' quotidien
    return inDom && isCountDaily;
  });

  // 2) somme des targets & du fait aujourd’hui
  int target = 0;
  int done = 0;
  for (final a in acts) {
    target += logic.dayQuotaFor(a);
    done   += logic.habitValueOn(a.id, DateTime(now.year, now.month, now.day));
  }

  // 3) pacing à cette heure
  final f = pacingFractionDay(now, dayStartHour: dayStartHour);
  final pace = (target * f).round();
  final delta = done - pace;

  return HabitPacingAgg(target: target, done: done, pace: pace, delta: delta);
}


Widget buildPacingChip(HabitPacingAgg agg) {
  if (agg.target <= 0) return const SizedBox.shrink();

  late Color c;
  late IconData ic;
  late String label;

  if (agg.delta > 0) {
    c = Colors.green;
    ic = Icons.trending_up;
    label = "+${agg.delta} en avance";
  } else if (agg.delta == 0) {
    c = Colors.blueGrey;
    ic = Icons.more_horiz;
    label = "À l’heure";
  } else {
    c = Colors.orange;
    ic = Icons.trending_down;
    label = "${agg.delta.abs()} à rattraper";
  }

  return Align(
    alignment: Alignment.centerRight,
    child: Chip(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      avatar: Icon(ic, size: 16, color: c),
      label: Text(label, style: TextStyle(fontSize: 12, color: c)),
      backgroundColor: c.withOpacity(0.12),
      shape: StadiumBorder(side: BorderSide(color: c.withOpacity(0.25))),
    ),
  );
}
