import 'package:flutter/material.dart';
import 'models.dart';

class GoalChange {
  final String kind; // 'activity' | 'domain'
  final String id; // activityId ou domainId
  final int deltaMin;
  final int newGoalMin;
  GoalChange({
    required this.kind,
    required this.id,
    required this.deltaMin,
    required this.newGoalMin,
  });
}

class FocusItem {
  final String kind; // 'time' | 'habit' | 'goal'
  final double score; // priorité (plus haut = plus prioritaire)
  final String reason; // explication courte

  // charge utile
  final Activity? activity; // pour time/habit OU goal lié à une activité
  final Goal? goal; // pour goal
  final Duration? timeDeficit;
  final int? habitDeficit;

  // affichage
  final String? titleOverride; // ex. titre de l’objectif
  final String? subtitleOverride; // ex. prochaine action

  FocusItem({
    required this.kind,
    required this.score,
    required this.reason,
    this.activity,
    this.goal,
    this.timeDeficit,
    this.habitDeficit,
    this.titleOverride,
    this.subtitleOverride,
  });
}

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
    maybeAutoAdjustActivity(activityId);
    onChange();
  }

  void stopActive() {
    final run = state.sessions.where((s) => s.endAt == null).toList();
    if (run.isNotEmpty) {
      final ended = run.last;
      ended.endAt = DateTime.now();
      onChange();
      // auto-ajuste l’activité qui vient de finir
      maybeAutoAdjustActivity(ended.activityId);
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
    maybeAutoAdjustActivity(activityId);
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

  // ---------  SNOOZE ---------
  bool isSnoozed(String activityId, {DateTime? now}) {
    final untilIso = state.snoozedUntil[activityId];
    if (untilIso == null) return false;
    final t = now ?? DateTime.now();
    return DateTime.parse(untilIso).isAfter(t);
  }

  void snooze(String activityId, {int minutes = 30}) {
    final until = DateTime.now().add(Duration(minutes: minutes));
    state.snoozedUntil[activityId] = until.toIso8601String();
    onChange(); // persiste via _saveAndRefresh
  }

  void clearExpiredSnoozes({DateTime? now}) {
    final t = now ?? DateTime.now();
    final toRemove = <String>[];
    state.snoozedUntil.forEach((id, iso) {
      if (!DateTime.parse(iso).isAfter(t)) toRemove.add(id);
    });
    for (final id in toRemove) {
      state.snoozedUntil.remove(id);
    }
    if (toRemove.isNotEmpty) onChange();
  }

  // Temps cumulé sur l'activité liée à l'objectif depuis sa création
  int goalEffortSpentMin(Goal g, {DateTime? now}) {
    if (g.activityId == null) return 0;
    final aId = g.activityId!;
    final start = g.createdAt;
    final end = now ?? DateTime.now();
    return totalForRangeByActivity(aId, start, end).inMinutes;
  }

// Ratio principal de progression (0..1) + libellé
  ({double? ratio, String? label}) goalProgress(Goal g) {
    // 1) Étapes si définies
    if (g.stepsPlanned != null && g.stepsPlanned! > 0) {
      final done = g.stepsDone.clamp(0, g.stepsPlanned!);
      final r = (done / g.stepsPlanned!).clamp(0.0, 1.0);
      return (ratio: r, label: "Étapes ${done}/${g.stepsPlanned}");
    }
    // 2) Effort total si estimé et activité liée
    if (g.effortEstimateMin != null &&
        g.effortEstimateMin! > 0 &&
        g.activityId != null) {
      final spent = goalEffortSpentMin(g);
      final r = (spent / g.effortEstimateMin!).clamp(0.0, 1.0);
      return (ratio: r, label: "Effort ${spent}/${g.effortEstimateMin}m");
    }
    // 3) Rien à mesurer pour l’instant
    return (ratio: null, label: null);
  }

// Rythme semaine glissante basé sur l’activité liée
  ({double ratio, String label}) goalWeeklyPace(Goal g) {
    if (g.activityId == null) return (ratio: 0.0, label: "Semaine 0m / 0m");
    final w = timeSliding(g.activityId!, 7); // déjà implémenté plus tôt
    // w.doneMin vs w.targetMin (goal/jour de l'activité × 7)
    return (ratio: w.ratio, label: "Semaine ${w.doneMin}/${w.targetMin}m");
  }

// Incrémenter une étape (utile dans le menu ...)
  void incGoalStep(String goalId, {int delta = 1}) {
    final g = state.goals.firstWhere((x) => x.id == goalId);
    g.stepsDone = (g.stepsDone + delta).clamp(0, g.stepsPlanned ?? 9999);
    onChange();
  }

//------- Helpers “progress %” (glissants jour/7j/30j)

  // --- fenêtres glissantes
  ({DateTime start, DateTime end, int days}) _dayWin(DateTime now) {
    final s = DateTime(now.year, now.month, now.day);
    return (start: s, end: s.add(const Duration(days: 1)), days: 1);
  }

  ({DateTime start, DateTime end, int days}) _weekWin(DateTime now) {
    final e =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final s = e.subtract(const Duration(days: 7));
    return (start: s, end: e, days: 7);
  }

// --- % pour une activité time
  double timePct(String activityId, DateTime start, DateTime end, int days) {
    final doneMin = totalForRangeByActivity(activityId, start, end).inMinutes;
    final goalDay =
        state.activities.firstWhere((a) => a.id == activityId).goalMin;
    final target = goalDay * days;
    if (target <= 0) return 0.0;
    return doneMin / target; // 1.0 == 100%
  }

// --- % pour une activité habit
  double habitPct(String activityId, DateTime start, DateTime end, int days) {
    final a = state.activities.firstWhere((x) => x.id == activityId);
    final target = (a.dailyTarget ?? 0) * days;
    if (target <= 0) return 0.0;
    int sum = 0;
    var d = DateTime(start.year, start.month, start.day);
    while (d.isBefore(end)) {
      sum += habitValueOn(activityId, d);
      d = d.add(const Duration(days: 1));
    }
    return sum / target;
  }

  // ----  Filtrage + tri (proche de 100% en premier)
// items pour l’écran "lanceur / gestion" (type='time' ou 'habit')
  List<Activity> listUnderCapSorted({
    String? domainId,
    required bool habits,
    DateTime? now,
    bool onlyUnderCap = true, // <-- NEW: true = cacher les >=100% partout
  }) {
    final t = now ?? DateTime.now();

    ({DateTime start, DateTime end, int days}) dayWin() {
      final s = DateTime(t.year, t.month, t.day);
      return (start: s, end: s.add(const Duration(days: 1)), days: 1);
    }

    ({DateTime start, DateTime end, int days}) weekWin() {
      final e = DateTime(t.year, t.month, t.day).add(const Duration(days: 1));
      return (start: e.subtract(const Duration(days: 7)), end: e, days: 7);
    }

    ({DateTime start, DateTime end, int days}) monthWin() {
      final e = DateTime(t.year, t.month, t.day).add(const Duration(days: 1));
      return (start: e.subtract(const Duration(days: 30)), end: e, days: 30);
    }

    double pct(Activity a, DateTime s, DateTime e, int d) {
      if (a.isHabit) {
        final target = (a.dailyTarget ?? 0) * d;
        if (target <= 0) return 0.0;
        int sum = 0;
        var x = DateTime(s.year, s.month, s.day);
        while (x.isBefore(e)) {
          sum += habitValueOn(a.id, x);
          x = x.add(const Duration(days: 1));
        }
        return sum / target;
      } else {
        final done = totalForRangeByActivity(a.id, s, e).inMinutes;
        final target = a.goalMin * d;
        if (target <= 0) return 0.0;
        return done / target;
      }
    }

    final wD = dayWin(), wW = weekWin(), wM = monthWin();

    bool keep(Activity a) {
      if (domainId != null && a.domainId != domainId) return false;
      if (habits != a.isHabit) return false;
      if (!onlyUnderCap) return true; // <-- en mode domaine: on garde tout
      final pD = pct(a, wD.start, wD.end, wD.days);
      final pW = pct(a, wW.start, wW.end, wW.days);
      final pM = pct(a, wM.start, wM.end, wM.days);
      // garder si AU MOINS une jauge < 100% (mode global)
      return (pD < 1.0) || (pW < 1.0) || (pM < 1.0);
    }

    // Score priorité:
    // - si au moins une jauge <100%: score = 1 - minGapUnder (proche de 1 en tête)
    // - sinon (toutes >=100%): score négatif = -minOver, pour les mettre APRÈS celles sous 100%
    double priorityScore(Activity a) {
      final pD = pct(a, wD.start, wD.end, wD.days);
      final pW = pct(a, wW.start, wW.end, wW.days);
      final pM = pct(a, wM.start, wM.end, wM.days);

      final gapsUnder = <double>[];
      if (pD < 1.0) gapsUnder.add(1.0 - pD);
      if (pW < 1.0) gapsUnder.add(1.0 - pW);
      if (pM < 1.0) gapsUnder.add(1.0 - pM);

      if (gapsUnder.isNotEmpty) {
        final minGap = gapsUnder.reduce((a, b) => a < b ? a : b);
        return 1.0 - minGap; // [0,1)
      }

      // Toutes >=100% : si onlyUnderCap=true on ne les verra pas,
      // sinon on les classe après celles sous 100%, les plus proches d'abord
      if (!onlyUnderCap) {
        final overs = <double>[pD - 1.0, pW - 1.0, pM - 1.0];
        final minOver = overs.reduce((a, b) => a < b ? a : b);
        return -minOver; // ex: -0.05 (105%) mieux que -0.50 (150%)
      }

      return -999.0; // cas non utilisé
    }

    final list = state.activities.where(keep).toList();
    list.sort((a, b) => priorityScore(b).compareTo(priorityScore(a)));
    return list;
  }

  Future<void> monthlyAutoAdjust({
    DateTime? now,
    double threshold = 1.20,
    double targetTime = 0.95,
    double targetHabit = 1.00,
    int minTimeFloorMin = 15, // ne jamais descendre sous ce plancher (sécurité)
    int maxTimeCeilMin = 12 * 60, // borne haute
    int maxDailyHabit = 9999, // borne haute
  }) async {
    final t = now ?? DateTime.now();
    final win = _monthWin(t);
    bool changed = false;

    for (final a in state.activities) {
      if (!a.isHabit) {
        // -- TIME
        final doneMin =
            totalForRangeByActivity(a.id, win.start, win.end).inMinutes;
        final targetMin = (a.goalMin * win.days);
        if (targetMin <= 0) continue;
        final ratio = doneMin / targetMin;

        if (ratio > threshold) {
          // nouveau objectif/jour tel que doneMin / (newGoal*days) = targetTime
          final newGoal = (doneMin / (targetTime * win.days)).ceil();
          final adj = newGoal.clamp(minTimeFloorMin, maxTimeCeilMin);
          if (adj > a.goalMin) {
            a.goalMin = adj;
            changed = true;
          }
        }
      } else {
        // -- HABIT
        int sum = 0;
        var d = DateTime(win.start.year, win.start.month, win.start.day);
        while (d.isBefore(win.end)) {
          sum += habitValueOn(a.id, d);
          d = d.add(const Duration(days: 1));
        }
        final daily = (a.dailyTarget ?? 0);
        final target = daily * win.days;
        if (target <= 0) continue;
        final ratio = sum / target;

        if (ratio > threshold) {
          // done / (newDaily * days) = targetHabit
          final newDaily = (sum / (targetHabit * win.days)).ceil();
          final adj = newDaily.clamp(1, maxDailyHabit);
          if (adj > daily) {
            a.dailyTarget = adj;
            changed = true;
          }
        }
      }
    }

    if (changed) onChange();
  }

  // Auto Ajustement des activités
// --- déjà présent ---
  final Map<String, DateTime> _lastAutoAdjust = {}; // cooldown horodaté

// --- nouveau : anti-doublon (1 bump max / jour / activité quand scan global) ---
  final Map<String, String> _autoAdjustDay = {}; // key -> 'YYYYMMDD'

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  ({DateTime start, DateTime end, int days}) _monthWin(DateTime now) {
    final end =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final start = end.subtract(const Duration(days: 30));
    return (start: start, end: end, days: 30);
  }

  Future<int?> maybeAutoAdjustActivity(
    String activityId, {
    DateTime? now,
    double threshold = 1.20,
    double targetTime = 0.95,
    double targetHabit = 1.00,
    int minStepMin = 5,
    int floorMin = 15,
    int cooldownHours = 3,
    bool ignoreCooldown = false, // <-- AJOUT
  }) async {
    final t = now ?? DateTime.now();

    // Cooldown horaire (sauf scan global)
    final last = _lastAutoAdjust[activityId];
    if (!ignoreCooldown &&
        last != null &&
        t.difference(last) < Duration(hours: cooldownHours)) {
      return null;
    }

    // Anti-doublon au scan : max 1 bump / jour / activité
    if (ignoreCooldown) {
      final today = _ymd(t);
      if (_autoAdjustDay[activityId] == today) return null;
    }

    final a = state.activities.firstWhere(
      (x) => x.id == activityId,
      orElse: () => Activity(domainId: '', name: 'deleted'),
    );

    // fenêtre 30j glissants
    ({DateTime start, DateTime end, int days}) _monthWin(DateTime now) {
      final end =
          DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      final start = end.subtract(const Duration(days: 30));
      return (start: start, end: end, days: 30);
    }

    final win = _monthWin(t);

    if (!a.isHabit) {
      final doneMin =
          totalForRangeByActivity(a.id, win.start, win.end).inMinutes;
      final target = a.goalMin * win.days;
      if (target <= 0) return null;
      final ratio = doneMin / target;
      if (ratio <= threshold) return null;

      final computed = (doneMin / (targetTime * win.days)).ceil();
      final stepped = (computed / minStepMin).ceil() * minStepMin;
      final adj = stepped.clamp(floorMin, 12 * 60);
      if (adj > a.goalMin) {
        final delta = adj - a.goalMin;
        a.goalMin = adj;
        _lastAutoAdjust[activityId] = t;
        if (ignoreCooldown) _autoAdjustDay[activityId] = _ymd(t);
        onChange();
        return delta;
      }
    } else {
      // HABITS
      int sum = 0;
      var d = DateTime(win.start.year, win.start.month, win.start.day);
      while (d.isBefore(win.end)) {
        sum += habitValueOn(activityId, d);
        d = d.add(const Duration(days: 1));
      }

      final daily = a.dailyTarget ?? 0;
      final target = daily * win.days;
      if (target <= 0) return null;
      final ratio = sum / target;
      if (ratio <= threshold) return null;

      final newDaily = (sum / (targetHabit * win.days)).ceil();
      if (newDaily > daily) {
        final delta = newDaily - daily;
        a.dailyTarget = newDaily.clamp(1, 9999);
        _lastAutoAdjust[activityId] = t;
        if (ignoreCooldown) _autoAdjustDay[activityId] = _ymd(t);
        onChange();
        return delta;
      }
    }
    return null;
  }

  /// Parcourt toutes les activités/routines et applique l’auto-ajustement si nécessaire.
  /// Retourne le nombre de bumps effectués.
  Future<int> scanAllActivities({DateTime? now}) async {
    final t = now ?? DateTime.now();
    int bumps = 0;
    for (final a in state.activities) {
      final delta =
          await maybeAutoAdjustActivity(a.id, now: t, ignoreCooldown: true);
      if (delta != null && delta > 0) bumps++;
    }
    if (bumps > 0) onChange();
    return bumps;
  }
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
  Future<List<GoalChange>> reviewGoals(
      {DateTime? now,
      int lookbackDays = 7, // nombre de jours regardés (hier inclus)
      int neededHits = 5, // nb de jours “au-dessus/au-dessous” nécessaires
      double lower = 0.85, // zone neutre bas  (≤ 85% => “en dessous”)
      double upper = 1.15, // zone neutre haut (≥115% => “au dessus”)
      double high = 1.50, // très au-dessus (≥150%) active un petit boost
      double pctStep = 0.10, // pas = 10% de l’objectif courant
      int minStepMin = 15, // mais au moins 15 min
      int maxPerDayMin = 12 * 60, // plafond journalier 12h
      double maxWeeklyPct = 0.20 // cap de +20% / “revue” (style hebdo)
      }) async {
    final changes = <GoalChange>[];
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);

    // 1) une seule passe par jour (sauf si tu passes un "now" de test)
    if (state.lastGoalsReview != null) {
      final last = DateTime(state.lastGoalsReview!.year,
          state.lastGoalsReview!.month, state.lastGoalsReview!.day);
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
        if (ratio >= high) wayAbove++;
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
        final ratio =
            domainProgressOnDay(d.id, day); // (minutes faites) / (goalMinDay)
        if (ratio >= upper) above++;
        if (ratio <= lower) below++;
        if (ratio >= high) wayAbove++;
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
    onChange(); // déclenche ta sauvegarde via _saveAndRefresh
    return changes; // pour afficher les badges, logs, etc.
  }

  /// Calcule des recommandations Focus (MVP jour: 24h glissantes pour le temps, aujourd'hui pour les habitudes)
  List<FocusItem> buildFocusCandidates({
    DateTime? now,
    String? domainId, // si fourni : filtre par domaine
  }) {
    final t = now ?? DateTime.now();

    // --- TEMPS : 24h glissantes ---
    final start24 = t.subtract(const Duration(hours: 24));
    final end24 = t;

    final items = <FocusItem>[];

/*     for (final a in state.activities) {
      if (domainId != null && a.domainId != domainId) continue;
      if (isSnoozed(a.id, now: t)) continue; // <— skip snoozed

      if (!a.isHabit) {
        // TIME
        final done = totalForRangeByActivity(a.id, start24, end24);
        final needMin = a.goalMin;
        final doneMin = done.inMinutes;
        final deficitMin = (needMin - doneMin).clamp(0, 1 << 30);
        final ratio = (needMin > 0) ? (doneMin / needMin) : 1.0;

        // score simple : plus de déficit => plus prioritaire
        final score = (needMin > 0) ? (deficitMin / needMin) : 0.0;

        final reason = (needMin <= 0)
            ? "Pas d’objectif"
            : (deficitMin <= 0
                ? "Objectif du jour atteint"
                : "Manque ${deficitMin} min sur ${needMin} min");

        items.add(FocusItem(
          activity: a,
          kind: 'time',
          score: score,
          reason: reason,
          timeDeficit: Duration(minutes: deficitMin),
        ));
      } else {
        // HABIT (MVP quotidien)
        final todayKey = yyyymmdd(t);
        final doneToday = state.habitProgress
            .where((h) => h.activityId == a.id && h.yyyymmdd == todayKey)
            .map((h) => h.value)
            .fold(0, (s, v) => s + v);
        final target = a.dailyTarget ?? 0;
        final deficit = (target - doneToday);
        final score = (target > 0) ? (deficit.clamp(0, 1 << 30) / target) : 0.0;

        final reason = (target <= 0)
            ? "Pas de cible"
            : (deficit <= 0
                ? "Cible du jour atteinte"
                : "Il reste $deficit ${a.unit ?? ''}");

        items.add(FocusItem(
          activity: a,
          kind: 'habit',
          score: score,
          reason: reason,
          habitDeficit: deficit > 0 ? deficit : 0,
        ));
      }
    } */

    // ---- GOALS avec prochaine action (GTD light) ----
// ---- GOALS (afficher même sans nextAction) ----
    for (final g in state.goals.where((x) => x.status == 'active')) {
      if (domainId != null && g.domainId != domainId) continue;

      // Optionnel: si tu veux pouvoir snoozer un goal entier
      final snoozeKey = 'goal:${g.id}';
      if (isSnoozed(snoozeKey, now: t)) continue;

      final hasNext = (g.nextAction?.trim().isNotEmpty ?? false);

      // Récupérer l’activité liée *en nullable* (sans orElse null)
      Activity? act;
      if (g.activityId != null) {
        final idx = state.activities.indexWhere((a) => a.id == g.activityId);
        if (idx != -1) act = state.activities[idx];
      }

      double score = hasNext ? 0.8 : 0.2;
      String reason =
          hasNext ? "Prochaine action à faire" : "Définir une prochaine action";
      Duration? timeDef;
      int? habitDef;

      // Si prochaine action ET activité liée -> calcule un "déficit" pour affiner le score/raison
      if (hasNext && act != null) {
        if (!act!.isHabit) {
          final m = totalForRangeByActivity(act!.id, start24, end24).inMinutes;
          final need = act!.goalMin;
          final deficit = need - m;
          if (need > 0) {
            score =
                (deficit > 0 ? deficit / need : 0).clamp(0.0, 1.0).toDouble();
            reason = deficit > 0
                ? "Manque ${deficit} min sur ${need} min"
                : "Objectif du jour atteint";
            timeDef = Duration(minutes: deficit.clamp(0, need));
          }
        } else {
          final today = DateTime(t.year, t.month, t.day);
          final done = habitValueOn(act!.id, today);
          final target = act!.dailyTarget ?? 0;
          final deficit = target - done;
          if (target > 0) {
            score =
                (deficit > 0 ? deficit / target : 0).clamp(0.0, 1.0).toDouble();
            reason = deficit > 0
                ? "Il reste $deficit ${act!.unit ?? ''}"
                : "Cible du jour atteinte";
            habitDef = deficit.clamp(0, target);
          }
        }
      }

      items.add(FocusItem(
        kind: 'goal',
        score: score,
        reason: reason,
        goal: g,
        activity: act, // peut être null
        timeDeficit: timeDef,
        habitDeficit: habitDef,
        titleOverride: g.title,
        subtitleOverride: g.nextAction, // peut être null/vidé
      ));
    }

    // filtrer les items déjà “verts” (score ≈ 0), mais garder au moins quelque chose
    items.sort((b, a) => a.score.compareTo(b.score)); // desc
    final nonZero = items.where((it) => it.score > 0).toList();
    if (nonZero.isNotEmpty) return nonZero;
    return items.take(5).toList(); // fallback
  }
}

extension SlidingProgress on AppLogic {
  // bornes [start, end) glissantes
  DateTimeRange lastNDays(int n, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final end = t;
    final start = t.subtract(Duration(days: n));
    return DateTimeRange(start: start, end: end);
  }

  // ---- Temps (activity.type == 'time')
  ({int doneMin, int targetMin, double ratio}) timeSliding(
    String activityId,
    int days, {
    DateTime? now,
  }) {
    final r = lastNDays(days, now: now);
    final dur = totalForRangeByActivity(activityId, r.start, r.end);
    final a = state.activities.firstWhere((x) => x.id == activityId);
    final target =
        (a.goalMin * days).clamp(0, 24 * 60 * days); // simple: goal/j * n
    final done = dur.inMinutes;
    final ratio = target > 0 ? (done / target).clamp(0.0, 1.0) : 0.0;
    return (doneMin: done, targetMin: target, ratio: ratio);
  }

  // ---- Habitudes (activity.type == 'habit')
  ({int done, int target, double ratio}) habitSliding(
    String activityId,
    int days, {
    DateTime? now,
  }) {
    final r = lastNDays(days, now: now);
    final done = habitSumForRange(activityId, r.start, r.end);
    final a = state.activities.firstWhere((x) => x.id == activityId);
    final targetPerDay = a.dailyTarget ?? 0;
    final target = targetPerDay * days;
    final ratio = target > 0 ? (done / target).clamp(0.0, 1.0) : 0.0;
    return (done: done, target: target, ratio: ratio);
  }

  // --- GOALS: helpers ---
  List<Goal> goalsOfDomain(String domainId, {bool onlyActive = true}) {
    final it = state.goals.where((g) => g.domainId == domainId);
    return onlyActive
        ? it.where((g) => g.status == 'active').toList()
        : it.toList();
  }

  Goal createGoal({
    required String domainId,
    required String title,
    String? activityId,
    String? nextAction,
    String? context,
  }) {
    final g = Goal(
      domainId: domainId,
      title: title,
      activityId: activityId,
      nextAction: nextAction,
      context: context,
    );
    state.goals.add(g);
    onChange();
    return g;
  }

  void setGoalNextAction(String goalId, String? nextAction) {
    final g = state.goals.firstWhere((x) => x.id == goalId);
    g.nextAction = nextAction; // null = aucune action active
    onChange();
  }

  void markGoalDone(String goalId) {
    final g = state.goals.firstWhere((x) => x.id == goalId);
    g.status = 'done';
    g.doneAt = DateTime.now();
    onChange();
  }

  void archiveGoal(String goalId) {
    final g = state.goals.firstWhere((x) => x.id == goalId);
    g.status = 'archived';
    onChange();
  }

  // INBOX
  void inboxAdd(String title) {
    if (title.trim().isEmpty) return;
    state.inbox.add(InboxItem(title: title.trim()));
    onChange();
  }

  void inboxRemove(String id) {
    state.inbox.removeWhere((x) => x.id == id);
    onChange();
  }

// Clarify -> créer un Goal depuis un InboxItem
  Goal inboxToGoal({
    required String inboxId,
    required String domainId,
    required String title,
    String? activityId,
    String? nextAction,
    String? context,
  }) {
    final g = createGoal(
      domainId: domainId,
      title: title,
      activityId: activityId,
      nextAction: nextAction,
      context: context,
    );
    inboxRemove(inboxId);
    return g;
  }
}
