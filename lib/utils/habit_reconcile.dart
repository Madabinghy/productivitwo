import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedYmd;

/// Les deux comptes d'une routine — le compteur du jour (`habitProgress`) et
/// les hits horodatés (séries, badges, journée parfaite, routines du jour) —
/// ont divergé avant le 2026-10-30 : un « +3 » ne posait qu'un hit, le lanceur
/// écrivait sur le jour calendaire. On les aligne, jour par jour, sur le plus
/// grand des deux : hits manquants ajoutés (ids déterministes `recon-…` : deux
/// appareils qui réconcilient en même temps ne doublent rien), compteur relevé.
/// Idempotent. Retourne le nombre de corrections.
int reconcileHabitStores(AppState st, {required int dayStartMin, required DateTime now}) {
  final hits = <String, int>{};
  final ids = <String>{};
  for (final h in st.habitHits) {
    ids.add(h.id);
    final k = '${h.habitId}|${livedYmd(h.ts, dayStartMin)}';
    hits[k] = (hits[k] ?? 0) + 1;
  }
  final todayYmd = livedYmd(now, dayStartMin);
  var changes = 0;
  final counters = <String, HabitProgress>{};
  for (final hp in st.habitProgress) {
    counters['${hp.activityId}|${hp.yyyymmdd}'] = hp;
    if (hp.yyyymmdd.compareTo(todayYmd) > 0) continue;
    final k = '${hp.activityId}|${hp.yyyymmdd}';
    var missing = hp.value - (hits[k] ?? 0);
    if (missing <= 0) continue;
    final day = DateTime.tryParse(hp.yyyymmdd);
    if (day == null) continue;
    var ts = DateTime(day.year, day.month, day.day, 12);
    if (ts.isAfter(now)) ts = now;
    if (livedYmd(ts, dayStartMin) != hp.yyyymmdd) continue;
    for (var i = 0; missing > 0 && i < 1000; i++) {
      final id = 'recon-${hp.activityId}-${hp.yyyymmdd}-$i';
      if (ids.contains(id)) continue;
      st.habitHits.add(HabitHit(id: id, habitId: hp.activityId, ts: ts.add(Duration(milliseconds: i))));
      ids.add(id);
      hits[k] = (hits[k] ?? 0) + 1;
      missing--;
      changes++;
    }
  }
  hits.forEach((k, n) {
    final hp = counters[k];
    if (hp == null) {
      final sep = k.lastIndexOf('|');
      final id = k.substring(0, sep), ymd = k.substring(sep + 1);
      st.habitProgress.add(HabitProgress(id: 'recon-$id-$ymd', activityId: id, yyyymmdd: ymd, value: n));
      changes++;
    } else if (hp.value < n) {
      hp.value = n;
      changes++;
    }
  });
  return changes;
}
