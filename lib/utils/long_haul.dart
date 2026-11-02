import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';

/// Cartes « au long cours » (2026-11-02, retour user : une fois les enjeux du
/// jour gagnés, continuer ne rapportait plus rien). Elles ne regardent que le
/// cumul, sans série ni journée : chaque minute de chrono et chaque coche en
/// plus de la cible du jour les font avancer, et rien ne se perd.
///  - `heures-<activité>` : heures de chrono sur une activité-temps ;
///  - `heures-total` : toutes les heures chronométrées (le chemin des 10 000 h) ;
///  - `fois-<routine>` : nombre total de coches d'une routine.
const kActivityHourTiers = [5, 20, 50, 100, 250, 500, 1000, 10000];
const kTotalHourTiers = [100, 500, 1000, 2500, 5000, 10000];
const kRoutineCountTiers = [10, 50, 100, 250, 500, 1000];

/// Une carte apparaît dès 1 h (activité) ou 3 coches (routine) : pas d'album
/// rempli de cartes vides pour chaque activité créée.
const kLongHaulMinHours = 1.0;
const kLongHaulMinCount = 3;

bool isLongHaulId(String id) => id.startsWith('heures-') || id.startsWith('fois-');

List<BadgeState> longHaulBadges({
  required List<Activity> activities,
  required List<HabitHit> habitHits,
  required List<Session> sessions,
  required DateTime now,
}) {
  final out = <BadgeState>[];
  // Minutes par activité, et le jour où chaque palier a été franchi.
  final byAct = <String, List<Session>>{};
  for (final s in sessions) {
    if (s.deleted) continue;
    byAct.putIfAbsent(s.activityId, () => []).add(s);
  }
  int minutesOf(Session s) {
    final end = s.endAt ?? now;
    final m = end.difference(s.startAt).inMinutes;
    return m < 0 ? 0 : m;
  }

  List<DateTime?> hourDates(List<Session> list, List<int> tiers) {
    final sorted = [...list]..sort((a, b) => a.startAt.compareTo(b.startAt));
    final out = List<DateTime?>.filled(tiers.length, null);
    var acc = 0;
    for (final s in sorted) {
      acc += minutesOf(s);
      for (var i = 0; i < tiers.length; i++) {
        if (out[i] == null && acc >= tiers[i] * 60) out[i] = DateTime(s.startAt.year, s.startAt.month, s.startAt.day);
      }
    }
    return out;
  }

  int lv(List<int> tiers, num v) => tiers.where((t) => v >= t).length;
  String h(double v) => '${v.toStringAsFixed(v < 10 ? 1 : 0).replaceAll('.', ',')} h';

  final times = activities.where((a) => !a.deleted && !a.isHabit).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  for (final a in times) {
    final list = byAct[a.id] ?? const <Session>[];
    final hours = list.fold<int>(0, (s, x) => s + minutesOf(x)) / 60;
    if (hours < kLongHaulMinHours) continue;
    final level = lv(kActivityHourTiers, hours);
    final next = level < kActivityHourTiers.length ? kActivityHourTiers[level] : null;
    out.add(BadgeState(
      def: BadgeDef(id: 'heures-${a.id}', family: BadgeFamily.time, name: a.name, symbol: 'hourglass', tiers: kActivityHourTiers, unit: 'h', unitLong: 'heures', subjectId: a.id),
      level: level,
      value: double.parse(hours.toStringAsFixed(1)),
      tierDates: hourDates(list, kActivityHourTiers),
      facts: [
        ('Heures au total', h(hours)),
        if (next != null) ('Prochain palier', '$next h · encore ${h(next - hours)}'),
      ],
    ));
  }

  final all = [for (final a in times) ...?byAct[a.id]];
  final total = all.fold<int>(0, (s, x) => s + minutesOf(x)) / 60;
  if (total < kLongHaulMinHours) return [...out, ..._routineCounts(activities, habitHits)];
  final tLevel = lv(kTotalHourTiers, total);
  final tNext = tLevel < kTotalHourTiers.length ? kTotalHourTiers[tLevel] : null;
  out.add(BadgeState(
    def: const BadgeDef(id: 'heures-total', family: BadgeFamily.time, name: 'Le chemin des 10 000 h', symbol: 'watch', tiers: kTotalHourTiers, unit: 'h', unitLong: 'heures'),
    level: tLevel,
    value: double.parse(total.toStringAsFixed(1)),
    tierDates: hourDates(all, kTotalHourTiers),
    facts: [
      ('Heures chronométrées', h(total)),
      if (tNext != null) ('Prochain palier', '${fmtInt(tNext)} h · encore ${h(tNext - total)}'),
    ],
  ));

  out.addAll(_routineCounts(activities, habitHits));
  return out;
}

List<BadgeState> _routineCounts(List<Activity> activities, List<HabitHit> habitHits) {
  final out = <BadgeState>[];
  int lv(List<int> tiers, num v) => tiers.where((t) => v >= t).length;
  final hitsBy = <String, List<HabitHit>>{};
  for (final x in habitHits) {
    hitsBy.putIfAbsent(x.habitId, () => []).add(x);
  }
  final routines = activities.where((a) => !a.deleted && a.isHabit).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  for (final a in routines) {
    final list = [...?hitsBy[a.id]]..sort((x, y) => x.ts.compareTo(y.ts));
    final n = list.length;
    if (n < kLongHaulMinCount) continue;
    final level = lv(kRoutineCountTiers, n);
    final next = level < kRoutineCountTiers.length ? kRoutineCountTiers[level] : null;
    out.add(BadgeState(
      def: BadgeDef(id: 'fois-${a.id}', family: BadgeFamily.actions, name: a.name, symbol: 'check', tiers: kRoutineCountTiers, unit: 'fois', unitLong: 'fois', subjectId: a.id),
      level: level,
      value: n,
      tierDates: [for (final t in kRoutineCountTiers) t <= n ? DateTime(list[t - 1].ts.year, list[t - 1].ts.month, list[t - 1].ts.day) : null],
      facts: [
        ('Faite au total', '${fmtInt(n)} fois'),
        if (next != null) ('Prochain palier', '$next fois · encore ${next - n}'),
      ],
    ));
  }
  return out;
}

/// Ce qu'une carte au long cours a gagné aujourd'hui (journée vécue) : la ligne
/// « +40 min · Lecture à 2 h 10 du palier » du bilan du soir.
({double hoursToday, int countToday}) longHaulToday({
  required BadgeState b,
  required List<HabitHit> habitHits,
  required List<Session> sessions,
  required DateTime dayStart,
  required DateTime now,
}) {
  final id = b.def.subjectId;
  if (b.def.id.startsWith('fois-')) {
    final n = habitHits.where((x) => x.habitId == id && !x.ts.isBefore(dayStart)).length;
    return (hoursToday: 0, countToday: n);
  }
  var m = 0;
  for (final s in sessions) {
    if (s.deleted) continue;
    if (id != null && s.activityId != id) continue;
    final st = s.startAt.isBefore(dayStart) ? dayStart : s.startAt;
    final end = s.endAt ?? now;
    if (end.isAfter(st)) m += end.difference(st).inMinutes;
  }
  return (hoursToday: m / 60, countToday: 0);
}
