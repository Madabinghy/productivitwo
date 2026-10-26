import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart';

/// Élan (lot 2 badges, 2026-10) : logique pure des pointages d'état.
/// Trois créneaux d'élan par jour vécu (matin < 12 h, après-midi < 18 h,
/// soir), une FENÊTRE par pointage d'élan (de son heure au pointage suivant ou
/// à la fin de la journée vécue), une « fenêtre de flemme » quand l'élan est
/// Flemme ou Mou (≤ 2) ; une « victoire sur la flemme » = un bloc terminé ou
/// une routine qui atteint sa cible dans une telle fenêtre.

const kElanBuckets = ['matin', 'aprem', 'soir'];
const kElanBucketLabels = {'matin': 'Matin', 'aprem': 'Après-midi', 'soir': 'Soir'};

/// Créneau d'un instant de la journée vécue (`livedNowMin`, 0 → 24 h 30).
String elanBucket(int livedMin) => livedMin < 12 * 60 ? 'matin' : (livedMin < 18 * 60 ? 'aprem' : 'soir');

MoodMark? elanMarkOf(List<MoodMark> marks, String ymd, String bucket) {
  MoodMark? best;
  for (final m in marks) {
    if (m.kind != kMoodElan || m.ymd != ymd || m.moment != bucket) continue;
    if (best == null || m.at.isAfter(best.at)) best = m;
  }
  return best;
}

MoodMark? moodOfDay(List<MoodMark> marks, String ymd) {
  MoodMark? best;
  for (final m in marks) {
    if (m.kind != kMoodMood || m.ymd != ymd) continue;
    if (best == null || m.at.isAfter(best.at)) best = m;
  }
  return best;
}

MoodMark? effortOfBlock(List<MoodMark> marks, String blockId) {
  MoodMark? best;
  for (final m in marks) {
    if (m.kind != kMoodEffort || m.blockId != blockId) continue;
    if (best == null || m.at.isAfter(best.at)) best = m;
  }
  return best;
}

/// L'élan est à demander : pas encore pointé ni passé pour ce créneau.
bool elanDue(List<MoodMark> marks, String ymd, String bucket, Set<String> skipped) =>
    elanMarkOf(marks, ymd, bucket) == null && !skipped.contains('$ymd:$bucket');

class ElanWindow {
  final MoodMark mark;
  final DateTime end;
  const ElanWindow(this.mark, this.end);
  bool contains(DateTime t) => !t.isBefore(mark.at) && t.isBefore(end);
  bool get low => mark.lowElan;
}

/// Fenêtres des pointages d'élan d'un jour vécu, dans l'ordre.
List<ElanWindow> elanWindows(List<MoodMark> marks, String ymd, {int dayStartMin = kDefaultDayStartMin}) {
  final day = DateTime.tryParse(ymd);
  if (day == null) return const [];
  final dayEnd = DateTime(day.year, day.month, day.day + 1).add(Duration(minutes: dayStartMin));
  final ms = marks.where((m) => m.kind == kMoodElan && m.ymd == ymd).toList()..sort((a, b) => a.at.compareTo(b.at));
  return [
    for (var i = 0; i < ms.length; i++) ElanWindow(ms[i], i + 1 < ms.length ? ms[i + 1].at : dayEnd),
  ];
}

/// Ce qui a été fait dans une fenêtre : blocs terminés (hors supprimés) et
/// routines quotidiennes dont la cible du jour est atteinte PAR un hit de la
/// fenêtre. Retourne les instants des faits (un par bloc, un par routine).
List<DateTime> winsIn(
  ElanWindow w, {
  required List<ScheduleBlock> blocks,
  required List<HabitHit> hits,
  required List<Activity> activities,
  int dayStartMin = kDefaultDayStartMin,
}) {
  final out = <DateTime>[];
  for (final b in blocks) {
    final t = b.doneAt;
    if (b.status == 'done' && t != null && w.contains(t)) out.add(t);
  }
  final ymd = w.mark.ymd;
  for (final a in activities) {
    if (a.deleted || !a.isHabit || a.habitFreq != HabitFreq.daily) continue;
    final target = (a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1);
    final dayHits = hits.where((h) => h.habitId == a.id && ymdOf(livedDate(h.ts, dayStartMin)) == ymd).toList()
      ..sort((x, y) => x.ts.compareTo(y.ts));
    if (dayHits.length < target) continue;
    final reachedAt = dayHits[target - 1].ts;
    if (w.contains(reachedAt)) out.add(reachedAt);
  }
  return out;
}

class ElanMarkView {
  final String bucket;
  final int value;
  final bool won; // au moins une chose faite dans la fenêtre
  const ElanMarkView(this.bucket, this.value, this.won);
}

class ElanDay {
  final String ymd;
  final List<ElanMarkView> marks;
  final int? mood;
  const ElanDay(this.ymd, this.marks, this.mood);
  double? get mean => marks.isEmpty ? null : marks.fold(0, (s, m) => s + m.value) / marks.length;
}

/// Les `days` derniers jours vécus (aujourd'hui compris), du plus ancien au
/// plus récent, avec leurs pointages d'élan et le sort de chaque fenêtre.
List<ElanDay> buildElanDays({
  required List<MoodMark> marks,
  required Map<String, DailySchedule> schedulesByYmd,
  required List<HabitHit> hits,
  required List<Activity> activities,
  required DateTime now,
  int days = 7,
  int dayStartMin = kDefaultDayStartMin,
}) {
  final today = livedDate(now, dayStartMin);
  final out = <ElanDay>[];
  for (var i = days - 1; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    final ymd = ymdOf(d);
    final views = <ElanMarkView>[];
    for (final w in elanWindows(marks, ymd, dayStartMin: dayStartMin)) {
      final wins = winsIn(w, blocks: schedulesByYmd[ymd]?.blocks ?? const [], hits: hits, activities: activities, dayStartMin: dayStartMin);
      views.add(ElanMarkView(w.mark.moment ?? elanBucket(w.mark.at.hour * 60 + w.mark.at.minute), w.mark.value, wins.isNotEmpty));
    }
    out.add(ElanDay(ymd, views, moodOfDay(marks, ymd)?.value));
  }
  return out;
}

class ElanMetrics {
  final int count; // pointages d'élan
  final double mean;
  final int lowCount; // fenêtres de flemme
  final int lowWon; // … où au moins une chose a été faite
  const ElanMetrics(this.count, this.mean, this.lowCount, this.lowWon);
  double? get discipline => lowCount == 0 ? null : lowWon / lowCount;
}

ElanMetrics elanMetrics(List<ElanDay> days) {
  var n = 0, sum = 0, low = 0, won = 0;
  for (final d in days) {
    for (final m in d.marks) {
      n++;
      sum += m.value;
      if (m.value <= 2) {
        low++;
        if (m.won) won++;
      }
    }
  }
  return ElanMetrics(n, n == 0 ? 0 : sum / n, low, won);
}

/// Tout ce dont la famille Discipline a besoin, sur l'historique entier.
class DisciplineStats {
  final List<DateTime> wins; // instants des victoires sur la flemme, triés
  final Map<String, double> meanByYmd; // élan moyen par jour pointé
  final List<DateTime> elanMarkDates; // dates des pointages d'élan, triées
  const DisciplineStats(this.wins, this.meanByYmd, this.elanMarkDates);
}

DisciplineStats disciplineStats({
  required List<MoodMark> marks,
  required List<DailySchedule> schedules,
  required List<HabitHit> hits,
  required List<Activity> activities,
  int dayStartMin = kDefaultDayStartMin,
}) {
  final byYmd = {for (final s in schedules) s.date: s};
  final ymds = marks.where((m) => m.kind == kMoodElan).map((m) => m.ymd).toSet();
  final wins = <DateTime>[];
  final mean = <String, double>{};
  for (final ymd in ymds) {
    final ws = elanWindows(marks, ymd, dayStartMin: dayStartMin);
    if (ws.isEmpty) continue;
    mean[ymd] = ws.fold(0, (s, w) => s + w.mark.value) / ws.length;
    for (final w in ws) {
      if (!w.low) continue;
      wins.addAll(winsIn(w, blocks: byYmd[ymd]?.blocks ?? const [], hits: hits, activities: activities, dayStartMin: dayStartMin));
    }
  }
  wins.sort();
  final dates = marks.where((m) => m.kind == kMoodElan).map((m) => m.at).toList()..sort();
  return DisciplineStats(wins, mean, dates);
}
