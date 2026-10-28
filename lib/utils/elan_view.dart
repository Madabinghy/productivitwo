import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart';

/// Voir son élan (2026-10, maquette « Élan visible ») : la journée par
/// créneau, la semaine, les 30 derniers jours et la tendance. Logique pure,
/// construite sur `elanWindows` / `winsIn` / `buildElanDays` ; l'UI vit dans
/// la feuille du mode (`widgets/mode_sheet.dart`). Des faits, jamais un
/// jugement.

/// Un créneau du jour vécu : pointé (valeur, heure, choses faites ensuite) ou pas.
class ElanSlot {
  final String bucket; // matin · aprem · soir
  final int? value;
  final DateTime? at;
  final int wins; // choses faites dans la fenêtre du pointage
  /// Le créneau est déjà commencé (sinon « à partir de 12 h »).
  final bool started;
  final bool current;
  const ElanSlot(this.bucket, {this.value, this.at, this.wins = 0, this.started = false, this.current = false});
  bool get pointed => value != null;
  String get label => kElanBucketLabels[bucket] ?? bucket;
  /// Début du créneau (heure du jour vécu).
  int get startHour => switch (bucket) { 'matin' => 5, 'aprem' => 12, _ => 18 };
}

/// Les trois créneaux d'aujourd'hui, avec ce qui a été fait après chaque pointage.
List<ElanSlot> todayElanSlots({
  required List<MoodMark> marks,
  required DailySchedule? schedule,
  required List<HabitHit> hits,
  required List<Activity> activities,
  required DateTime now,
  int dayStartMin = kDefaultDayStartMin,
}) {
  final ymd = ymdOf(livedDate(now, dayStartMin));
  final nowMin = livedNowMin(now, dayStartMin);
  final cur = elanBucket(nowMin);
  final windows = elanWindows(marks, ymd, dayStartMin: dayStartMin);
  final out = <ElanSlot>[];
  for (final b in kElanBuckets) {
    final w = windows.where((x) => (x.mark.moment ?? elanBucket(x.mark.at.hour * 60 + x.mark.at.minute)) == b).lastOrNull;
    final startMin = switch (b) { 'matin' => 0, 'aprem' => 12 * 60, _ => 18 * 60 };
    if (w == null) {
      out.add(ElanSlot(b, started: nowMin >= startMin, current: b == cur));
      continue;
    }
    final wins = winsIn(w, blocks: schedule?.blocks ?? const [], hits: hits, activities: activities, dayStartMin: dayStartMin).length;
    out.add(ElanSlot(b, value: w.mark.value, at: w.mark.at, wins: wins, started: true, current: b == cur));
  }
  return out;
}

/// Créneau le plus souvent pointé bas sur [days] (null si aucune flemme).
String? hardestBucket(List<ElanDay> days) {
  final low = <String, int>{};
  for (final d in days) {
    for (final m in d.marks) {
      if (m.value <= 2) low[m.bucket] = (low[m.bucket] ?? 0) + 1;
    }
  }
  if (low.isEmpty) return null;
  final sorted = low.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.first.key;
}

class ElanMonth {
  final List<ElanDay> days; // 30, du plus ancien au plus récent
  final double? mean;
  final int pointedDays;
  final int lowDays; // jours à élan moyen ≤ 2,5
  final int lowDaysWon; // … avec au moins une fenêtre de flemme gagnée
  final int highDays; // jours à élan moyen ≥ 4
  final double? previousMean; // 30 jours d'avant
  const ElanMonth({
    required this.days,
    required this.mean,
    required this.pointedDays,
    required this.lowDays,
    required this.lowDaysWon,
    required this.highDays,
    required this.previousMean,
  });

  /// Écart avec les 30 jours d'avant (null sans comparaison possible).
  double? get delta => mean == null || previousMean == null ? null : mean! - previousMean!;
  /// Jours consécutifs pointés jusqu'à hier au moins (aujourd'hui compris s'il l'est).
  int get pointedStreak {
    var n = 0;
    for (var i = days.length - 1; i >= 0; i--) {
      final d = days[i];
      if (d.marks.isEmpty) {
        if (i == days.length - 1) continue; // aujourd'hui pas encore pointé : on n'y touche pas
        break;
      }
      n++;
    }
    return n;
  }
}

/// Les 30 derniers jours (aujourd'hui compris) et la comparaison avec les 30
/// d'avant. [days60] = `buildElanDays(days: 60)`, du plus ancien au plus récent.
ElanMonth elanMonth(List<ElanDay> days60) {
  final n = days60.length;
  final cur = n > 30 ? days60.sublist(n - 30) : days60;
  final prev = n > 30 ? days60.sublist(0, n - 30) : const <ElanDay>[];
  double? meanOf(List<ElanDay> ds) {
    final m = elanMetrics(ds);
    return m.count == 0 ? null : m.mean;
  }

  var pointed = 0, low = 0, lowWon = 0, high = 0;
  for (final d in cur) {
    final m = d.mean;
    if (m == null) continue;
    pointed++;
    if (m <= 2.5) {
      low++;
      if (d.marks.any((x) => x.value <= 2 && x.won)) lowWon++;
    }
    if (m >= 4) high++;
  }
  return ElanMonth(days: cur, mean: meanOf(cur), pointedDays: pointed, lowDays: low, lowDaysWon: lowWon, highDays: high, previousMean: meanOf(prev));
}

/// Moyenne par semaine calendaire des [days] (clé = lundi `YYYY-MM-DD`), dans l'ordre.
List<({String monday, double? mean, int count})> weeklyMeans(List<ElanDay> days) {
  final out = <String, List<int>>{};
  final order = <String>[];
  for (final d in days) {
    final date = DateTime.parse(d.ymd);
    final monday = ymdOf(date.subtract(Duration(days: date.weekday - 1)));
    if (!out.containsKey(monday)) {
      out[monday] = [];
      order.add(monday);
    }
    out[monday]!.addAll(d.marks.map((m) => m.value));
  }
  return [
    for (final k in order)
      (monday: k, mean: out[k]!.isEmpty ? null : out[k]!.fold<int>(0, (s, v) => s + v) / out[k]!.length, count: out[k]!.length),
  ];
}

String fmtElan(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1).replaceAll('.', ',');

/// « ↗ +0,4 vs les 30 j d'avant », « → stable », null sans comparaison.
String? trendLabel(ElanMonth m) {
  final d = m.delta;
  if (d == null) return null;
  if (d.abs() < 0.15) return '→ stable vs les 30 j d’avant';
  return '${d > 0 ? '↗ +' : '↘ −'}${fmtElan(d.abs())} vs les 30 j d’avant';
}
