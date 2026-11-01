import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/acquired.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show routineReachedDays;
import 'package:productivitwo_v1/utils/elan_bands.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/half_days.dart' show minutesByActivityDay, paceOn;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/parole.dart';
import 'package:productivitwo_v1/utils/planning.dart' show capHeld;
import 'package:productivitwo_v1/utils/sleep_stats.dart';

/// Signaux de la semaine pour le coach (maquette validée 2026-11-01 « Cockpit
/// coach ») : calculés par l'app sur les 7 derniers jours clos et déposés dans
/// l'instantané `data/badges.signals`. Le serveur ne recalcule rien ; il filtre
/// selon le consentement (sommeil à part, activités des domaines partagés).
///
/// Une case par jour, du plus ancien au plus récent : `true` gagné / tenu,
/// `false` perdu / manqué, `null` rien à mesurer ce jour-là.

const kSignalDays = 7;

/// Les [kSignalDays] derniers jours clos (hier vécu compris), en ordre.
List<String> signalDays(DateTime now, int dayStartMin) {
  final today = livedDate(now, dayStartMin);
  return [for (var k = kSignalDays; k >= 1; k--) ymdOf(DateTime(today.year, today.month, today.day - k))];
}

/// Journée posée la veille par le mode Planification : `held` tenue à 70 %,
/// `posed` posée mais pas tenue, null pas posée la veille.
String? capStateOf(DailySchedule? s) {
  if (s == null || s.generatedBy != 'plan' || s.plannedSameDay || s.plannedAt == null) return null;
  final p = s.date.split('-').map(int.parse).toList();
  if (!s.plannedAt!.isBefore(DateTime(p[0], p[1], p[2]))) return null;
  return capHeld(s) ? 'held' : 'posed';
}

Map<String, dynamic> coachSignals({
  required DateTime now,
  required int dayStartMin,
  required List<Activity> activities,
  required List<Session> sessions,
  required List<HabitHit> hits,
  required List<DailySchedule> schedules,
  Map<String, ParoleDay> paroles = const {},
  List<Project> projects = const [],
  List<MoodMark> marks = const [],
  Set<String> Function(Activity a)? frozenOf,
  Map<String, Acquired> acquired = const {},
}) {
  final days = signalDays(now, dayStartMin);
  final live = activities.where((a) => !a.deleted).toList();

  // Montre suisse : chaque soir, toutes les activités à minimum couvertes sur 7 j.
  final minutes = minutesByActivityDay(sessions, now);
  final watch = <bool?>[];
  final blockers = <String, int>{};
  for (final ymd in days) {
    final pace = paceOn(DateTime.parse(ymd), activities: live, minutes: minutes, frozenOf: frozenOf);
    if (pace.isEmpty) {
      watch.add(null);
      continue;
    }
    final won = pace.every((p) => p.onPace);
    watch.add(won);
    if (!won) {
      for (final p in pace.where((p) => !p.onPace)) {
        blockers[p.activity.id] = (blockers[p.activity.id] ?? 0) + 1;
      }
    }
  }
  final byId = {for (final a in live) a.id: a};
  final topBlockers = (blockers.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3).map((e) {
    final a = byId[e.key]!;
    return {'name': a.name, 'domainId': a.domainId, 'lostDays': e.value, 'goalMin': a.goalMin};
  }).toList();

  // Métronome : toutes les routines quotidiennes dues atteintes.
  final routines = live.where((a) => a.isHabit && a.habitFreq == HabitFreq.daily).toList();
  final reached = {for (final a in routines) a.id: routineReachedDays(a, hits, dayStartMin: dayStartMin)};
  final metronome = <bool?>[];
  for (final ymd in days) {
    final d = DateTime.parse(ymd);
    var due = 0, ok = 0;
    for (final a in routines) {
      if (DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day).isAfter(d)) continue;
      if (isAcquiredOn(acquired, a.id, ymd)) continue;
      if (frozenOf != null && frozenOf(a).contains(ymd)) continue;
      due++;
      if (reached[a.id]?.contains(ymd) ?? false) ok++;
    }
    metronome.add(due == 0 ? null : ok == due);
  }

  // Parole tenue : seulement les jours où une parole (≥ 3 actions) a été donnée.
  final index = paroleIndex(projects, activities);
  final parole = <bool?>[];
  for (final ymd in days) {
    final p = paroles[ymd];
    if (p == null) {
      parole.add(null);
      continue;
    }
    final o = paroleOutcome(p, index, dayStartMin);
    parole.add(o.counts ? o.held : null);
  }

  // Posé la veille (mode Planification).
  final byYmd = {for (final s in schedules) s.date: s};
  final cap = [for (final ymd in days) capStateOf(byYmd[ymd])];

  // Sommeil : 7 dernières nuits (la dernière = celle qui précède aujourd'hui).
  final sleep = sleepActivityOf(activities);
  final target = sleepTargetMin(sleep);
  final nights30 = sleepNightList(sessions: sessions, activities: activities, now: now, dayStartMin: dayStartMin, nights: 30);
  final week = nights30.sublist(nights30.length - kSignalDays);
  final st = sleepStats(week, target);
  final planned = plannedSleep(schedules, sleepActivityIds(activities));
  final todayYmd = ymdOf(livedDate(now, dayStartMin));
  final nextDays = <String, SleepNextDay>{};
  for (final n in nights30.whereType<SleepNight>()) {
    final share = modeShareOf([elanCellsOfDay(marks, n.nextYmd, now, dayStartMin)]);
    if (share.said > 0) nextDays[n.nextYmd] = SleepNextDay(lowShare: share.low / share.said);
  }
  final impact = sleepImpact(nights30, nextDays, target, todayYmd);

  return {
    'days': days,
    'watch': {'days': watch, 'blockers': topBlockers},
    'metronome': {'days': metronome},
    'parole': {'days': parole},
    'cap': {'days': cap},
    'sleep': {
      'nights': [for (final n in week) n?.minutes],
      'targetMin': target,
      'avgMin': st.avgMin,
      'debtMin': st.debtMin,
      'avgBed': st.avgBed,
      'spreadMin': st.spreadMin,
      'plannedBed': planned?.bed,
      if (impact.enough && impact.long.lowShare != null && impact.short.lowShare != null)
        'impact': {
          'longLowPct': (impact.long.lowShare! * 100).round(),
          'shortLowPct': (impact.short.lowShare! * 100).round(),
          'longDays': impact.long.days,
          'shortDays': impact.short.days,
        },
    },
  };
}
