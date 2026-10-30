import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/recharge.dart' show kRechargeValue, isBasicNeedBlock, isBasicNeedName;

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

/// Règle d'affichage de la question (allègement 2026-10) : par défaut UNE fois
/// par jour vécu (au premier geste, quel que soit le créneau) ; avec
/// `allMoments` (réglage « à chaque moment »), une fois par créneau.
bool elanPromptDue(List<MoodMark> marks, String ymd, String bucket, Set<String> skipped, {bool allMoments = false}) {
  if (allMoments) return elanDue(marks, ymd, bucket, skipped);
  if (marks.any((m) => m.kind == kMoodElan && m.ymd == ymd)) return false;
  return !skipped.any((k) => k.startsWith('$ymd:'));
}

class ElanWindow {
  final MoodMark mark;
  final DateTime end;
  const ElanWindow(this.mark, this.end);
  bool contains(DateTime t) => !t.isBefore(mark.at) && t.isBefore(end);
  bool get low => mark.lowElan;
}

/// Historique des changements d'élan (2026-10) : chaque changement de mode
/// est un pointage, SAUF un changement moins de [kElanCorrectionMin] minutes
/// après le précédent du même jour vécu, qui le REMPLACE (correction d'un
/// clic). L'état entre deux pointages est connu (le dernier), donc la bande
/// horaire de 15 min se calcule, rien n'est échantillonné. Effort : un par
/// (jour, bloc) ; humeur : un par jour. Miroir TypeScript :
/// `functions/src/elan.ts` (**garder alignés**).
const kElanCorrectionMin = 5;

/// Clé « un pointage par … » des pointages NON élan (effort, humeur).
String moodMarkKey(MoodMark m) => switch (m.kind) {
      kMoodEffort => 'effort:${m.ymd}:${m.blockId ?? m.id}',
      _ => '${m.kind}:${m.ymd}',
    };

/// Les pointages gardés : élan = l'historique du jour moins les corrections
/// (< 5 min avant un autre pointage du même jour) ; effort / humeur = le plus
/// récent par clé. Triés par instant.
List<MoodMark> dedupeMoodMarks(Iterable<MoodMark> marks) {
  final out = <MoodMark>[];
  final elanByYmd = <String, List<MoodMark>>{};
  final best = <String, MoodMark>{};
  for (final m in marks) {
    if (m.kind == kMoodElan) {
      elanByYmd.putIfAbsent(m.ymd, () => []).add(m);
      continue;
    }
    final k = moodMarkKey(m);
    final cur = best[k];
    if (cur == null || m.at.isAfter(cur.at)) best[k] = m;
  }
  out.addAll(best.values);
  for (final list in elanByYmd.values) {
    list.sort((a, b) => a.at.compareTo(b.at));
    for (var i = 0; i < list.length; i++) {
      final next = i + 1 < list.length ? list[i + 1] : null;
      // La recharge (virtuelle) ne corrige rien et n'est jamais corrigée.
      final real = list[i].value != kRechargeValue && next?.value != kRechargeValue;
      if (real && next != null && next.at.difference(list[i].at).inMinutes < kElanCorrectionMin) continue;
      out.add(list[i]);
    }
  }
  return out..sort((a, b) => a.at.compareTo(b.at));
}

/// Les pointages que [kept] a remplacés (même clé, plus anciens).
List<MoodMark> supersededMoodMarks(Iterable<MoodMark> all) {
  final keptIds = dedupeMoodMarks(all).map((m) => m.id).toSet();
  return all.where((m) => !keptIds.contains(m.id)).toList();
}

/// Fenêtres des pointages d'élan d'un jour vécu, dans l'ordre (un par créneau).
List<ElanWindow> elanWindows(List<MoodMark> marks, String ymd, {int dayStartMin = kDefaultDayStartMin}) {
  final day = DateTime.tryParse(ymd);
  if (day == null) return const [];
  final dayEnd = DateTime(day.year, day.month, day.day + 1).add(Duration(minutes: dayStartMin));
  final ms = dedupeMoodMarks(marks.where((m) => m.kind == kMoodElan && m.ymd == ymd));
  return [
    for (var i = 0; i < ms.length; i++) ElanWindow(ms[i], i + 1 < ms.length ? ms[i + 1].at : dayEnd),
  ];
}

/// Une victoire sur la flemme (maquette « Malgré tout », 2026-10-30) : quoi,
/// comment, quand. Dérivée, jamais stockée.
class FlemmeWin {
  final DateTime at;
  final String what;
  final String how;
  const FlemmeWin(this.at, this.what, this.how);
}

/// Minutes de chrono, lancé dans la fenêtre, qui font une victoire : en Flemme,
/// c'est démarrer qui compte (« 10 min, malgré tout » comme « Tout le bloc »).
const kFlemmeChronoMin = 10;

/// Une action faite (projet ou action propre d'une activité), pour les victoires.
typedef DoneAction = ({DateTime at, String title});

/// Les actions faites des projets et des activités (`doneAt` connu).
List<DoneAction> doneActionsOf(Iterable<Project> projects, Iterable<Activity> activities) => [
      for (final p in projects)
        for (final t in p.tasks)
          for (final a in t.actions)
            if (a.done && a.doneAt != null) (at: a.doneAt!, title: a.title),
      for (final act in activities)
        for (final a in act.ownActions)
          if (a.done && a.doneAt != null) (at: a.doneAt!, title: a.title),
    ];

/// Ce qui a été fait dans une fenêtre, en détail : un chrono lancé dans la
/// fenêtre et tenu [kFlemmeChronoMin] min, une action cochée, un bloc fait (sauf
/// si un chrono compté porte déjà sur son activité), une routine quotidienne
/// atteinte par un hit de la fenêtre. Jamais un besoin de base (repos, repas).
List<FlemmeWin> flemmeWinsIn(
  ElanWindow w, {
  required List<ScheduleBlock> blocks,
  required List<HabitHit> hits,
  required List<Activity> activities,
  List<Session> sessions = const [],
  List<DoneAction> doneActions = const [],
  int dayStartMin = kDefaultDayStartMin,
  DateTime? now,
}) {
  final out = <FlemmeWin>[];
  if (w.mark.value == kRechargeValue) return out;
  final byId = {for (final a in activities) a.id: a};
  final t0 = now ?? DateTime.now();
  final chronoActs = <String>{};
  for (final s in sessions) {
    if (s.deleted || !w.contains(s.startAt)) continue;
    final name = byId[s.activityId]?.name;
    if (isBasicNeedName(name)) continue;
    final mins = (s.endAt ?? t0).difference(s.startAt).inMinutes;
    if (mins < kFlemmeChronoMin) continue;
    chronoActs.add(s.activityId);
    out.add(FlemmeWin(s.startAt.add(const Duration(minutes: kFlemmeChronoMin)), name ?? 'Chrono', 'chrono tenu $mins min'));
  }
  for (final b in blocks) {
    final t = b.doneAt;
    if (b.status != 'done' || t == null || !w.contains(t)) continue;
    if (isBasicNeedBlock(b, byId)) continue;
    if (b.activityId != null && chronoActs.contains(b.activityId)) continue; // déjà compté par son chrono
    out.add(FlemmeWin(t, b.title.isEmpty ? (byId[b.activityId]?.name ?? 'Bloc') : b.title, 'bloc fait'));
  }
  for (final a in doneActions) {
    if (w.contains(a.at)) out.add(FlemmeWin(a.at, a.title, 'action cochée'));
  }
  final ymd = w.mark.ymd;
  for (final a in activities) {
    if (a.deleted || !a.isHabit || a.habitFreq != HabitFreq.daily) continue;
    if (isBasicNeedName(a.name)) continue;
    final target = (a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1);
    final dayHits = hits.where((h) => h.habitId == a.id && ymdOf(livedDate(h.ts, dayStartMin)) == ymd).toList()
      ..sort((x, y) => x.ts.compareTo(y.ts));
    if (dayHits.length < target) continue;
    final reachedAt = dayHits[target - 1].ts;
    if (w.contains(reachedAt)) out.add(FlemmeWin(reachedAt, a.name, 'routine atteinte'));
  }
  return out..sort((x, y) => x.at.compareTo(y.at));
}

/// Les instants de [flemmeWinsIn].
List<DateTime> winsIn(
  ElanWindow w, {
  required List<ScheduleBlock> blocks,
  required List<HabitHit> hits,
  required List<Activity> activities,
  List<Session> sessions = const [],
  List<DoneAction> doneActions = const [],
  int dayStartMin = kDefaultDayStartMin,
  DateTime? now,
}) =>
    [
      for (final x in flemmeWinsIn(w,
          blocks: blocks, hits: hits, activities: activities, sessions: sessions, doneActions: doneActions, dayStartMin: dayStartMin, now: now))
        x.at
    ];

class ElanMarkView {
  final String bucket;
  final int value;
  final bool won; // au moins une chose faite dans la fenêtre
  /// Durée de la fenêtre (jusqu'au pointage suivant, la fin de journée ou
  /// maintenant), pour peser la moyenne par le temps. 0 = inconnue.
  final int minutes;
  const ElanMarkView(this.bucket, this.value, this.won, {this.minutes = 0});
}

class ElanDay {
  final String ymd;
  final List<ElanMarkView> marks;
  final int? mood;
  const ElanDay(this.ymd, this.marks, this.mood);

  /// Élan moyen du jour, PONDÉRÉ par le temps tenu (une heure de Flemme pèse
  /// une heure) ; moyenne simple quand les durées sont inconnues.
  double? get mean {
    if (marks.isEmpty) return null;
    final total = marks.fold<int>(0, (s, m) => s + m.minutes);
    if (total <= 0) return marks.fold<int>(0, (s, m) => s + m.value) / marks.length;
    return marks.fold<double>(0, (s, m) => s + m.value * m.minutes) / total;
  }

  /// Créneaux pointés (matin · aprem · soir), 3 au plus.
  int get slots => marks.map((m) => m.bucket).toSet().length;
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
  List<Session> sessions = const [],
  List<DoneAction> doneActions = const [],
}) {
  final today = livedDate(now, dayStartMin);
  final out = <ElanDay>[];
  for (var i = days - 1; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    final ymd = ymdOf(d);
    final views = <ElanMarkView>[];
    for (final w in elanWindows(marks, ymd, dayStartMin: dayStartMin)) {
      if (w.mark.value == kRechargeValue) continue; // la nuit ne pèse pas
      final wins = winsIn(w,
          blocks: schedulesByYmd[ymd]?.blocks ?? const [], hits: hits, activities: activities, sessions: sessions, doneActions: doneActions, dayStartMin: dayStartMin, now: now);
      final end = w.end.isAfter(now) ? now : w.end;
      final minutes = end.difference(w.mark.at).inMinutes;
      views.add(ElanMarkView(w.mark.moment ?? elanBucket(w.mark.at.hour * 60 + w.mark.at.minute), w.mark.value, wins.isNotEmpty, minutes: minutes < 0 ? 0 : minutes));
    }
    out.add(ElanDay(ymd, views, moodOfDay(marks, ymd)?.value));
  }
  return out;
}

class ElanMetrics {
  final int count; // pointages d'élan (changements gardés)
  /// Moyenne PONDÉRÉE par le temps tenu (simple quand les durées manquent).
  final double mean;
  final int lowCount; // fenêtres de flemme
  final int lowWon; // … où au moins une chose a été faite
  final int slots; // créneaux pointés (3 par jour au plus)
  const ElanMetrics(this.count, this.mean, this.lowCount, this.lowWon, {this.slots = 0});
  double? get discipline => lowCount == 0 ? null : lowWon / lowCount;
}

ElanMetrics elanMetrics(List<ElanDay> days) {
  var n = 0, sum = 0, low = 0, won = 0, slots = 0, minutes = 0;
  var weighted = 0.0;
  for (final d in days) {
    slots += d.slots;
    for (final m in d.marks) {
      n++;
      sum += m.value;
      minutes += m.minutes;
      weighted += m.value * m.minutes;
      if (m.value <= 2) {
        low++;
        if (m.won) won++;
      }
    }
  }
  final mean = n == 0 ? 0.0 : (minutes > 0 ? weighted / minutes : sum / n);
  return ElanMetrics(n, mean, low, won, slots: slots);
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
  List<Session> sessions = const [],
  List<DoneAction> doneActions = const [],
}) {
  final byYmd = {for (final s in schedules) s.date: s};
  marks = dedupeMoodMarks(marks);
  final ymds = marks.where((m) => m.kind == kMoodElan).map((m) => m.ymd).toSet();
  final wins = <DateTime>[];
  final mean = <String, double>{};
  final now = DateTime.now();
  for (final ymd in ymds) {
    final ws = elanWindows(marks, ymd, dayStartMin: dayStartMin);
    if (ws.isEmpty) continue;
    var minutes = 0;
    var weighted = 0.0;
    for (final w in ws) {
      if (w.mark.value == kRechargeValue) continue;
      final end = w.end.isAfter(now) ? now : w.end;
      final m = end.difference(w.mark.at).inMinutes;
      if (m > 0) {
        minutes += m;
        weighted += w.mark.value * m;
      }
    }
    final real = ws.where((w) => w.mark.value != kRechargeValue).toList();
    if (real.isEmpty) continue;
    mean[ymd] = minutes > 0 ? weighted / minutes : real.fold(0, (s, w) => s + w.mark.value) / real.length;
    for (final w in ws) {
      if (!w.low) continue;
      wins.addAll(winsIn(w,
          blocks: byYmd[ymd]?.blocks ?? const [], hits: hits, activities: activities, sessions: sessions, doneActions: doneActions, dayStartMin: dayStartMin, now: now));
    }
  }
  wins.sort();
  // Baromètre compte les CRÉNEAUX pointés (3 par jour au plus), pas les changements.
  final firstBySlot = <String, DateTime>{};
  for (final m in marks) {
    if (m.kind != kMoodElan || m.value == kRechargeValue) continue;
    final k = '${m.ymd}:${m.moment ?? elanBucket(m.at.hour * 60 + m.at.minute)}';
    final cur = firstBySlot[k];
    if (cur == null || m.at.isBefore(cur)) firstBySlot[k] = m.at;
  }
  final dates = firstBySlot.values.toList()..sort();
  return DisciplineStats(wins, mean, dates);
}

/// Élan d'un objet (routine, objectif) : les pointages dont la fenêtre contient
/// un geste sur cet objet ; `victories` = ceux à élan bas.
class ElanFacts {
  final int count;
  final double? mean;
  final int victories;
  const ElanFacts(this.count, this.mean, this.victories);
}

ElanFacts _factsOf(List<MoodMark> marks, Iterable<DateTime> events, {int dayStartMin = kDefaultDayStartMin}) {
  final byYmd = <String, List<ElanWindow>>{};
  var n = 0, sum = 0, low = 0;
  for (final t in events) {
    final ymd = ymdOf(livedDate(t, dayStartMin));
    final ws = byYmd.putIfAbsent(ymd, () => elanWindows(marks, ymd, dayStartMin: dayStartMin));
    for (final w in ws) {
      if (!w.contains(t)) continue;
      if (w.mark.value == kRechargeValue) break;
      n++;
      sum += w.mark.value;
      if (w.low) low++;
      break;
    }
  }
  return ElanFacts(n, n == 0 ? null : sum / n, low);
}

/// Routine : le hit qui atteint la cible du jour, pour chaque jour atteint.
ElanFacts routineElanFacts(Activity a, List<MoodMark> marks, List<HabitHit> hits, {int dayStartMin = kDefaultDayStartMin}) {
  final target = (a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1);
  final byDay = <String, List<DateTime>>{};
  for (final h in hits) {
    if (h.habitId != a.id) continue;
    byDay.putIfAbsent(ymdOf(livedDate(h.ts, dayStartMin)), () => []).add(h.ts);
  }
  final events = <DateTime>[];
  for (final ts in byDay.values) {
    ts.sort();
    if (ts.length >= target) events.add(ts[target - 1]);
  }
  return _factsOf(marks, events, dayStartMin: dayStartMin);
}

/// Objectif : le début de chaque session sur ses activités engagées.
ElanFacts objectiveElanFacts(StrategicObjective o, List<MoodMark> marks, List<Session> sessions, {int dayStartMin = kDefaultDayStartMin}) {
  final ids = o.timeCommitments.map((c) => c.activityId).toSet();
  return _factsOf(marks, sessions.where((s) => !s.deleted && ids.contains(s.activityId)).map((s) => s.startAt), dayStartMin: dayStartMin);
}
