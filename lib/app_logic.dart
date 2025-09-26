import 'models.dart';

class AppLogic {
  AppState state;
  final void Function() onChange;
  AppLogic(this.state, this.onChange);

  // ---------- SESSIONS TEMPS ----------
  void start(String activityId) {
    for (final s in state.sessions.where((s) => s.endAt == null)) {
      s.endAt = DateTime.now();
    }
    state.sessions
        .add(Session(activityId: activityId, startAt: DateTime.now()));
    onChange();
  }

  void stopActive() {
    final run = state.sessions.where((s) => s.endAt == null).toList();
    if (run.isNotEmpty) {
      run.last.endAt = DateTime.now();
      onChange();
    }
  }

  Duration totalForDay(DateTime day, {String? domainId}) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return totalForRange(start, end, domainId: domainId);
  }

  Duration totalForRange(DateTime start, DateTime end, {String? domainId}) {
    bool inRange(Session s) {
      final e = s.endAt ?? DateTime.now();
      return s.startAt.isBefore(end) && e.isAfter(start);
    }

    bool inDomain(Session s) {
      if (domainId == null) return true;
      final act = state.activities.firstWhere(
        (a) => a.id == s.activityId,
        orElse: () => Activity(domainId: '', name: 'deleted'),
      );
      return act.domainId == domainId;
    }

    return state.sessions.where(inRange).where(inDomain).fold(Duration.zero,
        (sum, s) {
      final st = s.startAt.isBefore(start) ? start : s.startAt;
      final en = (s.endAt ?? DateTime.now()).isAfter(end)
          ? end
          : (s.endAt ?? DateTime.now());
      if (!en.isAfter(st)) return sum;
      return sum + en.difference(st);
    });
  }

  Duration totalForRangeByActivity(
      String activityId, DateTime start, DateTime end) {
    Duration sum = Duration.zero;
    for (final s in state.sessions.where((s) => s.activityId == activityId)) {
      final e = s.endAt ?? DateTime.now();
      if (s.startAt.isBefore(end) && e.isAfter(start)) {
        final st = s.startAt.isBefore(start) ? start : s.startAt;
        final en = e.isAfter(end) ? end : e;
        if (en.isAfter(st)) sum += en.difference(st);
      }
    }
    return sum;
  }

  // Totaux temps par domaine sur une plage
  Map<String, Duration> timeTotalsByDomain(DateTime start, DateTime end) {
    final map = <String, Duration>{};
    for (final d in state.domains) {
      map[d.id] = totalForRange(start, end, domainId: d.id);
    }
    return map;
  }

  // ---------- HABITUDES (compteur) ----------
  int habitValueOn(String activityId, DateTime day) {
    final key = yyyymmdd(day);
    final hp = state.habitProgress
        .where((h) => h.activityId == activityId && h.yyyymmdd == key)
        .toList();
    return hp.isEmpty ? 0 : hp.first.value;
  }

  int habitSumForRange(String activityId, DateTime start, DateTime end) {
    // somme inclusive: jours [start, end)
    int sum = 0;
    DateTime d = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (d.isBefore(end)) {
      sum += habitValueOn(activityId, d);
      d = d.add(const Duration(days: 1));
    }
    return sum;
  }

  void incHabit(String activityId, int delta, DateTime day) {
    final key = yyyymmdd(day);
    final idx = state.habitProgress
        .indexWhere((h) => h.activityId == activityId && h.yyyymmdd == key);
    if (idx < 0) {
      state.habitProgress.add(HabitProgress(
          activityId: activityId,
          yyyymmdd: key,
          value: delta.clamp(0, 1000000)));
    } else {
      final v = (state.habitProgress[idx].value + delta);
      state.habitProgress[idx].value = v < 0 ? 0 : v;
    }
    onChange();
  }

  // Sommes d'habitudes par domaine (range)
  Map<String, int> habitTotalsByDomain(DateTime start, DateTime end) {
    final map = <String, int>{};
    for (final d in state.domains) {
      int sum = 0;
      for (final a
          in state.activities.where((a) => a.domainId == d.id && a.isHabit)) {
        sum += habitSumForRange(a.id, start, end);
      }
      map[d.id] = sum;
    }
    return map;
  }

  // ---------- DOMAINES ----------
  List<Activity> activitiesOfDomain(String domainId) =>
      state.activities.where((a) => a.domainId == domainId).toList();

  //Graph helpers
  // Série d'heures par jour (double en heures), pour [start, start+days)
  List<double> timeHoursPerDay(DateTime start, int days, {String? domainId}) {
    final List<double> res = List.filled(days, 0);
    for (int i = 0; i < days; i++) {
      final s =
          DateTime(start.year, start.month, start.day).add(Duration(days: i));
      final e = s.add(const Duration(days: 1));
      final dur = totalForRange(s, e, domainId: domainId);
      res[i] = dur.inMinutes / 60.0;
    }
    return res;
  }

// Série d'habitudes par jour (sommes), pour [start, start+days)
  List<int> habitCountPerDay(DateTime start, int days, {String? domainId}) {
    final List<int> res = List.filled(days, 0);
    for (int i = 0; i < days; i++) {
      final d =
          DateTime(start.year, start.month, start.day).add(Duration(days: i));
      int sum = 0;
      final acts = (domainId == null)
          ? state.activities.where((a) => a.isHabit)
          : state.activities.where((a) => a.isHabit && a.domainId == domainId);
      for (final a in acts) {
        sum += habitValueOn(a.id, d);
      }
      res[i] = sum;
    }
    return res;
  }

// Objectif d’habitudes/jour (somme des cibles quotidiennes)
  int habitDailyTarget({String? domainId}) {
    final acts = (domainId == null)
        ? state.activities.where((a) => a.isHabit)
        : state.activities.where((a) => a.isHabit && a.domainId == domainId);
    int t = 0;
    for (final a in acts) {
      t += (a.dailyTarget ?? 0);
    }
    return t;
  }
}

class GoalChange {
  final String kind; // 'activity' | 'domain'
  final String id;   // activityId ou domainId
  final int deltaMin;
  final int newGoalMin;
  GoalChange({
    required this.kind,
    required this.id,
    required this.deltaMin,
    required this.newGoalMin,
  });
}


extension DomainGoals on AppLogic {
  // Objectif/jour d’un domaine en minutes : auto = somme des activités time, sinon valeur manuelle
  int domainGoalMinDay(String domainId) {
    final d = state.domains.firstWhere((x) => x.id == domainId);
    if (!d.autoGoal) return d.goalMinDay ?? 0;
    return state.activities
        .where((a) => a.domainId == domainId && !a.isHabit)
        .fold<int>(0, (s, a) => s + a.goalMin);
  }

  // Progression d’un domaine sur une journée calendaire (0..+inf)
  double domainProgressOnDay(String domainId, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final dur = totalForRange(start, end, domainId: domainId);
    final goalMin = domainGoalMinDay(domainId);
    if (goalMin <= 0) return 0.0;
    return dur.inMinutes / goalMin;
  }

  // Auto-ajustement simple : si sur les N derniers jours on atteint la cible >= T jours → +step
Future<List<GoalChange>> reviewGoals({
  DateTime? now,
  int lookbackDays = 7,      // nombre de jours regardés (hier inclus)
  int neededHits = 5,        // nb de jours “au-dessus/au-dessous” nécessaires
  double lower = 0.85,       // zone neutre bas  (≤ 85% => “en dessous”)
  double upper = 1.15,       // zone neutre haut (≥115% => “au dessus”)
  double high  = 1.50,       // très au-dessus (≥150%) active un petit boost
  double pctStep = 0.10,     // pas = 10% de l’objectif courant
  int minStepMin = 15,       // mais au moins 15 min
  int maxPerDayMin = 12 * 60,// plafond journalier 12h
  double maxWeeklyPct = 0.20 // cap de +20% / “revue” (style hebdo)
}) async {
  final changes = <GoalChange>[];
  final t = now ?? DateTime.now();
  final today = DateTime(t.year, t.month, t.day);

  // 1) une seule passe par jour (sauf si tu passes un "now" de test)
  if (state.lastGoalsReview != null) {
    final last = DateTime(state.lastGoalsReview!.year, state.lastGoalsReview!.month, state.lastGoalsReview!.day);
    if (last == today) return changes;
  }

  // 2) liste des jours observés (J-1, J-2, ..., J-lookback)
  final daysBack = List<DateTime>.generate(
    lookbackDays,
    (i) {
      final d = today.subtract(Duration(days: i + 1));
      return DateTime(d.year, d.month, d.day);
    },
  );

  int clampNonNeg(int v) => v < 0 ? 0 : v;

  int clampToWeeklyCap(int base, int delta) {
    final cap = (base * maxWeeklyPct).round();
    if (cap <= 0) return delta;
    return delta > cap ? cap : delta;
  }

  // ---------- ACTIVITÉS (type "time") ----------
  for (final a in state.activities.where((x) => !x.isHabit)) {
    final base = a.goalMin; // minutes/jour
    if (base <= 0) continue;

    int above = 0, below = 0, wayAbove = 0;

    for (final d in daysBack) {
      final start = d;
      final end = d.add(const Duration(days: 1));
      final doneMin = totalForRangeByActivity(a.id, start, end).inMinutes;
      final ratio = base > 0 ? (doneMin / base) : 0.0;

      if (ratio >= upper) above++;
      if (ratio <= lower) below++;
      if (ratio >= high)  wayAbove++;
    }

    var newGoal = base;

    if (above >= neededHits) {
      // hausse
      var step = (base * pctStep).round();
      if (step < minStepMin) step = minStepMin;
      step = clampToWeeklyCap(base, step);
      final boost = wayAbove >= (neededHits ~/ 2) ? (step ~/ 2) : 0;
      newGoal = (base + step + boost).clamp(0, maxPerDayMin);
    } else if (below >= neededHits) {
      // baisse (symétrique, sans cap hebdo nécessaire)
      var step = (base * pctStep).round();
      if (step < minStepMin) step = minStepMin;
      newGoal = clampNonNeg(base - step);
    }

    if (newGoal != base) {
      final delta = newGoal - base;
      a.goalMin = newGoal;
      changes.add(GoalChange(
        kind: 'activity',
        id: a.id,
        deltaMin: delta,
        newGoalMin: newGoal,
      ));
    }
  }

  // ---------- DOMAINES (seulement si objectif MANUEL) ----------
  for (final d in state.domains.where((dom) => !dom.autoGoal)) {
    final base = d.goalMinDay ?? 0; // minutes/jour
    if (base <= 0) continue;

    int above = 0, below = 0, wayAbove = 0;

    for (final day in daysBack) {
      final ratio = domainProgressOnDay(d.id, day); // (minutes faites) / (goalMinDay)
      if (ratio >= upper) above++;
      if (ratio <= lower) below++;
      if (ratio >= high)  wayAbove++;
    }

    var newGoal = base;

    if (above >= neededHits) {
      var step = (base * pctStep).round();
      if (step < minStepMin) step = minStepMin;
      step = clampToWeeklyCap(base, step);
      final boost = wayAbove >= (neededHits ~/ 2) ? (step ~/ 2) : 0;
      newGoal = (base + step + boost).clamp(0, maxPerDayMin);
    } else if (below >= neededHits) {
      var step = (base * pctStep).round();
      if (step < minStepMin) step = minStepMin;
      newGoal = clampNonNeg(base - step);
    }

    if (newGoal != base) {
      final delta = newGoal - base;
      d.goalMinDay = newGoal;
      changes.add(GoalChange(
        kind: 'domain',
        id: d.id,
        deltaMin: delta,
        newGoalMin: newGoal,
      ));
    }
  }

  // 3) finalisation
  state.lastGoalsReview = t;
  onChange();           // déclenche ta sauvegarde via _saveAndRefresh
  return changes;       // pour afficher les badges, logs, etc.
}

}
