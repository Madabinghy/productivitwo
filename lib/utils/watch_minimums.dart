import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/half_days.dart';

/// « Donner la main sur les minimums » (maquette validée 2026-10-30) : les
/// activités qui coûtent souvent la Montre suisse, pour proposer de retirer ou
/// de baisser leur minimum. Logique pure.

/// Fenêtre d'observation (jours clos) et seuil de journées perdues.
const kBlockerWindowDays = 30;
const kBlockerLostDays = 3;

/// « Garder » : la question ne revient pas avant n jours.
const kBlockerKeepDays = 30;

class WatchBlocker {
  final Activity activity;
  /// Journées clos où la montre a été perdue avec cette activité en retard.
  final int lostDays;
  /// Moyenne réelle par jour sur la fenêtre.
  final int avgMin;
  const WatchBlocker(this.activity, this.lostDays, this.avgMin);

  /// Minimum proposé pour « Baisser » : ce que tu fais vraiment, ou null si
  /// c'est moins d'une minute par jour ou pas plus bas que l'actuel.
  int? get suggestedMin => avgMin >= 1 && avgMin < activity.goalMin ? avgMin : null;
}

/// Les activités à minimum qui ont coûté la montre au moins [kBlockerLostDays]
/// fois sur les [kBlockerWindowDays] derniers jours clos, la plus coûteuse
/// d'abord. [keptYmd] = jour du dernier « Garder » par activité.
List<WatchBlocker> watchBlockers({
  required List<Activity> activities,
  required List<Session> sessions,
  required DateTime now,
  Set<String> Function(Activity a)? frozenOf,
  Map<String, String> keptYmd = const {},
}) {
  final today = DateTime(now.year, now.month, now.day);
  final minutes = minutesByActivityDay(sessions, now);
  final lost = <String, int>{};
  for (var i = 1; i <= kBlockerWindowDays; i++) {
    final d = today.subtract(Duration(days: i));
    final pace = paceOn(d, activities: activities, minutes: minutes, frozenOf: frozenOf);
    final behind = pace.where((p) => !p.onPace).toList();
    for (final p in behind) {
      lost[p.activity.id] = (lost[p.activity.id] ?? 0) + 1;
    }
  }
  final keepSince = ymdOf(today.subtract(const Duration(days: kBlockerKeepDays)));
  final out = <WatchBlocker>[];
  for (final a in activities) {
    if (a.deleted || a.isHabit || a.goalMin <= 0) continue;
    final n = lost[a.id] ?? 0;
    if (n < kBlockerLostDays) continue;
    final kept = keptYmd[a.id];
    if (kept != null && kept.compareTo(keepSince) > 0) continue;
    var total = 0;
    final byDay = minutes[a.id] ?? const {};
    for (var i = 1; i <= kBlockerWindowDays; i++) {
      total += byDay[ymdOf(today.subtract(Duration(days: i)))] ?? 0;
    }
    out.add(WatchBlocker(a, n, (total / kBlockerWindowDays).round()));
  }
  out.sort((x, y) => y.lostDays.compareTo(x.lostDays));
  return out;
}

/// Moyenne réelle par jour d'une activité sur les [days] derniers jours clos.
int averageMinPerDay(String activityId, List<Session> sessions, DateTime now, {int days = kBlockerWindowDays}) {
  final today = DateTime(now.year, now.month, now.day);
  final byDay = minutesByActivityDay(sessions, now)[activityId] ?? const {};
  var total = 0;
  for (var i = 1; i <= days; i++) {
    total += byDay[ymdOf(today.subtract(Duration(days: i)))] ?? 0;
  }
  return (total / days).round();
}
