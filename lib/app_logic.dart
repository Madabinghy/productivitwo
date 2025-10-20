// applogic.dart — version sans dailyTarget, cibles dérivées partout ✨

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:productivitwo_v1/models.dart';

// ---------- Constantes ----------
const int kMinDailyGoalMin = 1; // plancher dur pour activités "time"
final _uuid = const Uuid();

// ---------- Périodes / compteurs ----------
class PeriodCount {
  final int done, target;
  double get ratio => target > 0 ? done / target : 0.0;
  const PeriodCount(this.done, this.target);
}

// ---------- Auto-tune (trace) ----------
class TuneChange {
  String activityId;
  String note;
  TuneChange(this.activityId, this.note);
}

// =====================================================
// ===============  LOGIQUE PRINCIPALE  ================
// =====================================================

class AppLogic {
  AppState state;
  final void Function() onChange;
  AppLogic(this.state, this.onChange);

  // Retourne la liste d'activités du focus (en respectant les IDs)
  List<Activity> get focusToday {
    final ids = state.focusTodayIds.toSet();
    if (ids.isEmpty) return [];
    return state.activities.where((a) => ids.contains(a.id)).toList();
  }

  bool isInFocus(String activityId) => state.focusTodayIds.contains(activityId);

  void toggleFocus(String activityId) {
    if (state.focusTodayIds.contains(activityId)) {
      state.focusTodayIds.remove(activityId);
    } else {
      state.focusTodayIds.add(activityId);
    }
    onChange();
  }

  /// Optionnel : proposer automatiquement les habitudes quotidiennes non atteintes
  void suggestAutoFocusForToday({int maxCount = 4}) {
    final candidates = <Activity>[];

    // 1) routines quotidiennes non atteintes en priorité
    for (final a in state.activities.where((x) => x.isHabit)) {
      if (effectiveHabitFreq(a) == HabitFreq.daily) {
        final tgt = activeHabitTarget(a);
        if (tgt > 0 && activeHabitDone(a) < tgt) {
          candidates.add(a);
        }
      }
    }

    // 2) compléter si besoin avec une ou deux activités "time" (déficitaires)
    if (candidates.length < maxCount) {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 24));
      final deficits = state.activities.where((a) => !a.isHabit).map((a) {
        final done = totalForRangeByActivity(a.id, start, now).inMinutes;
        final need = a.goalMin;
        final deficit = (need - done).clamp(0, 1 << 30);
        return (a: a, deficit: deficit);
      }).toList()
        ..sort((b, a) => a.deficit.compareTo(b.deficit));

      for (final it in deficits) {
        if (candidates.length >= maxCount) break;
        if (it.deficit > 0) candidates.add(it.a);
      }
    }

    // écrire (sans dupliquer)
    final set = state.focusTodayIds.toSet();
    for (final a in candidates.take(maxCount)) {
      set.add(a.id);
    }
    state.focusTodayIds = set.toList();
    onChange();
  }

  bool isFocused(String activityId) => state.focusTodayIds.contains(activityId);

  // ---------- TEMPS (type=time) ----------
  void start(String activityId) {
    for (final s in state.sessions.where((s) => s.endAt == null)) {
      s.endAt = DateTime.now();
    }
    state.sessions
        .add(Session(activityId: activityId, startAt: DateTime.now()));
    onChange();

    // Préparer demain (optionnel)
    //ensurePlannedTomorrow(PlanKind.activityTime, activityId);
    // Si tu veux retirer de "Aujourd’hui", décommente :
    // final removed = removeFromDay(_todayKey(), PlanKind.activityTime, activityId);
    // if (removed) onChange();
  }

  // AppLogic
  Future<int> scanAllActivities({DateTime? now}) async {
    final t = now ?? DateTime.now();

    // 1) Revue des objectifs temps & domaines (force = même jour)
    try {
      await reviewGoals(now: t, force: true);
    } catch (_) {
      // si reviewGoals sans 'force' dans ta version:
      try {
        await reviewGoals(now: t);
      } catch (_) {}
    }

    // 2) Auto-tune des routines (si dispo dans ta base)
    int bumps = 0;
    try {
      for (final a in state.activities.where((x) => x.isHabit)) {
        // version "immédiate" si tu l'as:
        try {
          autoTuneHabitImmediate(this, a);
        } catch (_) {}
        // version tolérante:
        try {
          autoTuneHabit(this, a, now: t);
        } catch (_) {}
        // si tu veux compter les changements, incrémente 'bumps' ici
      }
    } catch (_) {
      // no-op si pas encore implémenté
    }

    onChange(); // persiste + notifie l’UI
    return bumps;
  }

// AppLogic
  Future<void> devAddHabitHistory(
    String activityId, {
    int days = 7, // nb de jours à remplir (en remontant depuis aujourd’hui)
    int perDay = 1, // nb d’incréments par jour (ex: 2 verres/jour)
    DateTime? now, // pour tests (sinon DateTime.now())
  }) async {
    final t = now ?? DateTime.now();

    // sécurité : ne fait rien si ce n’est pas une routine
    final idx = state.activities.indexWhere((a) => a.id == activityId);
    if (idx < 0 || !state.activities[idx].isHabit) return;

    for (int i = 0; i < days; i++) {
      final d = DateTime(t.year, t.month, t.day).subtract(Duration(days: i));
      for (int k = 0; k < perDay; k++) {
        incHabit(activityId, 1, d); // incHabit appelle déjà onChange()
      }
    }
  }

// ---------------- INBOX ----------------
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

// ---------------- GOALS ----------------
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
      status: 'active', // <- ajuste si ton modèle utilise un enum/const
      createdAt: DateTime.now(), // <- si ton modèle a ce champ
    );
    state.goals.add(g);
    onChange();
    return g;
  }

  void setGoalNextAction(String goalId, String? nextAction) {
    final g = state.goals.firstWhere((x) => x.id == goalId);
    g.nextAction = nextAction;
    onChange();
  }

  void markGoalDone(String goalId) {
    final g = state.goals.firstWhere((x) => x.id == goalId);
    g.status = 'done';
    g.doneAt = DateTime.now(); // si ton modèle a ce champ
    onChange();
  }

  void archiveGoal(String goalId) {
    final g = state.goals.firstWhere((x) => x.id == goalId);
    g.status = 'archived';
    onChange();
  }

// Sommes d'habitudes par domaine (range de dates)
  Map<String, int> habitTotalsByDomain(DateTime start, DateTime end) {
    // Si on regarde "aujourd'hui" (ou ~1 jour), on aligne sur 24h glissantes
    final useSliding24h = end.difference(start).inHours <= 24;

    final DateTime s, e;
    if (useSliding24h) {
      e = DateTime.now();
      s = e.subtract(const Duration(hours: 24));
    } else {
      s = DateTime(start.year, start.month, start.day);
      e = DateTime(end.year, end.month, end.day);
    }

    final map = <String, int>{};
    for (final d in state.domains) {
      int sum = 0;
      for (final a
          in state.activities.where((a) => a.domainId == d.id && a.isHabit)) {
        sum += habitSumForRange(a.id, s, e);
      }
      map[d.id] = sum;
    }
    return map;
  }

  void stopActive() {
    final run = state.sessions.where((s) => s.endAt == null).toList();
    if (run.isNotEmpty) {
      final ended = run.last;
      ended.endAt = DateTime.now();
      onChange();
      // boost auto (time)
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
        orElse: () => Activity(domainId: '', name: 'deleted', habitTarget: 1),
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

  Map<String, Duration> timeTotalsByDomain(DateTime start, DateTime end) {
    final map = <String, Duration>{};
    for (final d in state.domains) {
      map[d.id] = totalForRange(start, end, domainId: d.id);
    }
    return map;
  }

  // ---------- HABITUDES (type=habit) ----------
  int habitValueOn(String activityId, DateTime day) {
    final key = yyyymmdd(day);
    final hp = state.habitProgress
        .where((h) => h.activityId == activityId && h.yyyymmdd == key)
        .toList();
    return hp.isEmpty ? 0 : hp.first.value;
  }

  int habitSumForRange(String activityId, DateTime start, DateTime end) {
    // normalise les bornes sur minuit
    DateTime d = DateTime(start.year, start.month, start.day);
    final until = DateTime(end.year, end.month, end.day); // exclusif

    int sum = 0;
    while (d.isBefore(until)) {
      sum += habitValueOn(activityId, d);
      d = d.add(const Duration(days: 1));
    }
    return sum;
  }

  void incHabit(String activityId, int delta, DateTime day) {
    final key = yyyymmdd(day);

    // valeur AVANT modif (pour détecter le franchissement)
    final prevIdx = state.habitProgress.indexWhere(
      (h) => h.activityId == activityId && h.yyyymmdd == key,
    );
    final prevVal = (prevIdx >= 0) ? state.habitProgress[prevIdx].value : 0;

    // --- MAJ compteur ---
    if (prevIdx < 0) {
      state.habitProgress.add(HabitProgress(
        activityId: activityId,
        yyyymmdd: key,
        value: math.max(0, delta), // pas de négatif à la création
      ));
    } else {
      final v = state.habitProgress[prevIdx].value + delta;
      state.habitProgress[prevIdx].value = v < 0 ? 0 : v;
    }

    // Récupère l’activité
    final act = state.activities.firstWhere((a) => a.id == activityId);

    // Conditions "quotidienne" + quotas
    final isDaily = (effectiveHabitFreq(act) == HabitFreq.daily);
    final dayQuota = dayQuotaFor(act);

    // Valeur APRÈS modif
    final today = DateTime(day.year, day.month, day.day);
    final nowIsToday = (yyyymmdd(DateTime.now()) == key);
    final newVal = habitValueOn(activityId, today);

    // Ne déclenche que si on vient de FRANCHIR le seuil aujourd'hui
    final crossedNow = isDaily &&
        dayQuota > 0 &&
        nowIsToday &&
        (prevVal < dayQuota) &&
        (newVal >= dayQuota);

    if (crossedNow) {
      // 1) append dans DEMAIN (conserve l'ordre d'achèvement)
      ensurePlannedTomorrow(PlanKind.habit, activityId);

      // 2) retirer d'Aujourd'hui pour alléger la liste
      removeFromDay(yyyymmdd(today), PlanKind.habit, activityId);
    }

    // auto-tune (safe)
    _autoTuneHabitSafe(act);

    // Un seul onChange() à la fin
    onChange();
  }

  // ---------- Cibles dérivées (habits) ----------
  HabitFreq effectiveHabitFreq(Activity a) {
    return a.habitFreq ?? HabitFreq.monthly; // défaut raisonnable
  }

  int effectiveHabitTarget(Activity a) {
    return (a.habitTarget ?? 1); // défaut : 1
  }

  // Période active -> "fait" & "cible" (utile à l'UI)
  PeriodCount habitPeriod(Activity a, {DateTime? now}) {
    final t = now ?? DateTime.now();
    switch (effectiveHabitFreq(a)) {
      case HabitFreq.daily:
        final d = DateTime(t.year, t.month, t.day);
        return PeriodCount(habitValueOn(a.id, d), dayQuotaFor(a));
      case HabitFreq.weekly:
        return PeriodCount(habitSliding(a.id, 7).done, weekTargetFrom(a));
      case HabitFreq.monthly:
        return PeriodCount(habitSliding(a.id, 30).done, monthTargetFrom(a));
    }
  }

  // ---------- Snooze ----------
  bool isSnoozed(String activityId, {DateTime? now}) {
    final untilIso = state.snoozedUntil[activityId];
    if (untilIso == null) return false;
    final t = now ?? DateTime.now();
    return DateTime.parse(untilIso).isAfter(t);
  }

  void snooze(String activityId, {int minutes = 30}) {
    final until = DateTime.now().add(Duration(minutes: minutes));
    state.snoozedUntil[activityId] = until.toIso8601String();
    onChange();
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

  // ---------- Domaines ----------
  List<Activity> activitiesOfDomain(String domainId) =>
      state.activities.where((a) => a.domainId == domainId).toList();

  int domainGoalMinDay(String domainId) {
    final d = state.domains.firstWhere((x) => x.id == domainId);
    if (!d.autoGoal) return d.goalMinDay ?? 0;
    return state.activities
        .where((a) => a.domainId == domainId && !a.isHabit)
        .fold<int>(0, (s, a) => s + a.goalMin);
  }

  double domainProgressOnDay(String domainId, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final dur = totalForRange(start, end, domainId: domainId);
    final goalMin = domainGoalMinDay(domainId);
    if (goalMin <= 0) return 0.0;
    return dur.inMinutes / goalMin;
  }

  // ---------- Focus (MVP : items objectifs — partie time/habit possible si tu veux) ----------
  List<FocusItem> buildFocusCandidates({DateTime? now, String? domainId}) {
    final t = now ?? DateTime.now();
    final start24 = t.subtract(const Duration(hours: 24));
    final items = <FocusItem>[];

    // GOALS — toujours affichés
    for (final g in state.goals.where((x) => x.status == 'active')) {
      if (domainId != null && g.domainId != domainId) continue;

      final snoozeKey = 'goal:${g.id}';
      if (isSnoozed(snoozeKey, now: t)) continue;

      final hasNext = (g.nextAction?.trim().isNotEmpty ?? false);

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

      if (hasNext && act != null) {
        if (!act!.isHabit) {
          final m = totalForRangeByActivity(act!.id, start24, t).inMinutes;
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
          // si la routine est quotidienne, calcule un "déficit" sur le quota jour
          if (effectiveHabitFreq(act!) == HabitFreq.daily) {
            final today = DateTime(t.year, t.month, t.day);
            final done = habitValueOn(act!.id, today);
            final target = dayQuotaFor(act!);
            final deficit = target - done;
            if (target > 0) {
              score = (deficit > 0 ? deficit / target : 0)
                  .clamp(0.0, 1.0)
                  .toDouble();
              reason = deficit > 0
                  ? "Il reste $deficit ${act!.unit ?? ''}"
                  : "Cible du jour atteinte";
              habitDef = deficit.clamp(0, target);
            }
          } else {
            // hebdo/mensuel — garder un score modeste
            score = 0.3;
            reason =
                "Rattraper la routine ${effectiveHabitFreq(act!) == HabitFreq.weekly ? 'hebdo' : 'mensuelle'}";
          }
        }
      }

      items.add(FocusItem(
        kind: 'goal',
        score: score,
        reason: reason,
        goal: g,
        activity: act,
        timeDeficit: timeDef,
        habitDeficit: habitDef,
        titleOverride: g.title,
        subtitleOverride: g.nextAction,
      ));
    }

    items.sort((b, a) => a.score.compareTo(b.score));
    final nonZero = items.where((it) => it.score > 0).toList();
    if (nonZero.isNotEmpty) return nonZero;
    return items.take(5).toList();
  }

  // ---------- Tri/filtre “sous cap” ----------
  List<Activity> listUnderCapSorted({
    String? domainId,
    required bool habits,
    bool onlyUnderCap = false,
    bool dailyStrict = false,
  }) {
    Iterable<Activity> src = state.activities.where((a) => a.isHabit == habits);
    if (domainId != null) src = src.where((a) => a.domainId == domainId);
    final items = src.toList();

    bool underCap(Activity a) {
      if (a.isHabit) {
        final r1 = habitSliding(a.id, 1).ratio;
        final r7 = habitSliding(a.id, 7).ratio;
        final r30 = habitSliding(a.id, 30).ratio;
        return dailyStrict
            ? (r1 < 1.0)
            : !((r1 >= 1.0) || (r7 >= 1.0 && r30 >= 1.0));
      } else {
        final r1 = timeSliding(a.id, 1).ratio;
        final r7 = timeSliding(a.id, 7).ratio;
        final r30 = timeSliding(a.id, 30).ratio;
        return dailyStrict
            ? (r1 < 1.0)
            : !((r1 >= 1.0) || (r7 >= 1.0 && r30 >= 1.0));
      }
    }

    final filtered = onlyUnderCap ? items.where(underCap).toList() : items;

    double urgency(Activity a) {
      if (a.isHabit) {
        final r1 = habitSliding(a.id, 1).ratio;
        final r7 = habitSliding(a.id, 7).ratio;
        final r30 = habitSliding(a.id, 30).ratio;
        final pick =
            dailyStrict ? r1 : [r1, r7, r30].reduce((x, y) => x > y ? x : y);
        return 1.0 - pick;
      } else {
        final r1 = timeSliding(a.id, 1).ratio;
        final r7 = timeSliding(a.id, 7).ratio;
        final r30 = timeSliding(a.id, 30).ratio;
        final pick =
            dailyStrict ? r1 : [r1, r7, r30].reduce((x, y) => x > y ? x : y);
        return 1.0 - pick;
      }
    }

    filtered.sort((a, b) => urgency(a).compareTo(urgency(b)));
    return filtered;
  }

  // ---------- Auto-ajustement (TIME) en temps réel (soft) ----------
  final Map<String, DateTime> _lastAutoAdjust = {};
  final Map<String, String> _autoAdjustDay = {};
  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  ({DateTime start, DateTime end, int days}) _monthWin(DateTime now) {
    final end =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final start = end.subtract(const Duration(days: 30));
    return (start: start, end: end, days: 30);
  }

// AppLogic
  void ensureDailyHabitsPlanned({DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    final todayKey = yyyymmdd(today);

    // Habits déjà présents aujourd’hui (pour dédup & nettoyage)
    final presentToday = state.dayPlan
        .where((e) => e.yyyymmdd == todayKey && e.kind == PlanKind.habit)
        .map((e) => e.refId)
        .whereType<String>()
        .toSet();

    int nextOrder = _nextOrderForDay(todayKey);

    for (final a in state.activities.where((x) => x.isHabit)) {
      // On ne s’occupe que des QUOTIDIENNES
      if (effectiveHabitFreq(a) != HabitFreq.daily) continue;

      final quota = dayQuotaFor(a);
      if (quota <= 0) continue;

      final doneToday = habitValueOn(a.id, today);

      if (doneToday >= quota) {
        // Déjà atteinte : ne pas (ré)ajouter, et nettoyer si présent
        if (presentToday.contains(a.id)) {
          state.dayPlan.removeWhere((e) =>
              e.yyyymmdd == todayKey &&
              e.kind == PlanKind.habit &&
              e.refId == a.id);
        }
        continue;
      }

      // Pas encore atteinte : s'assurer qu’elle est planifiée
      if (!presentToday.contains(a.id)) {
        state.dayPlan.add(DayPlanItem(
          id: _uuid.v4(),
          kind: PlanKind.habit,
          refId: a.id,
          title: a.name,
          yyyymmdd: todayKey,
          done: false,
          allDay: true,
          order: nextOrder++,
        ));
      }
    }

    onChange();
  }

  Future<int?> maybeAutoAdjustActivity(
    String activityId, {
    DateTime? now,
    double threshold = 1.20,
    double targetTime = 0.95,
    double targetHabit = 1.00, // (pas utilisé ici)
    int minStepMin = 5,
    int floorMin = kMinDailyGoalMin,
    int cooldownHours = 3,
    bool ignoreCooldown = false,
  }) async {
    final t = now ?? DateTime.now();

    final last = _lastAutoAdjust[activityId];
    if (!ignoreCooldown &&
        last != null &&
        t.difference(last) < Duration(hours: cooldownHours)) {
      return null;
    }

    if (ignoreCooldown) {
      final today = _ymd(t);
      if (_autoAdjustDay[activityId] == today) return null;
    }

    final a = state.activities.firstWhere(
      (x) => x.id == activityId,
      orElse: () => Activity(domainId: '', name: 'deleted', habitTarget: 1),
    );

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
    }

    return null;
  }

  Future<void> autoAdjustStandardsRealtime({
    DateTime? now,
    int floorMin = kMinDailyGoalMin,
    int maxPerDayMin = 12 * 60,
    double raiseTrigger = 1.20,
    double aimUp = 0.95,
    double deadbandLow = 0.80,
    double deadbandHigh = 1.10,
    double lowerHard = 0.50,
    double aimDown = 0.90,
    int minStepMin = 5,
    double maxWeeklyPct = 0.20,
    Duration coolDown = const Duration(hours: 48),
  }) async {
    final t = now ?? DateTime.now();
    bool touched = false;

    for (final a in state.activities.where((x) => !x.isHabit)) {
      final s30 = timeSliding(a.id, 30); // doneMin/targetMin/ratio

      if (a.goalMin < floorMin) a.goalMin = floorMin;

      if (a.lastTuneAt != null &&
          t.difference(a.lastTuneAt!).compareTo(coolDown) < 0) {
        continue;
      }

      if (s30.targetMin <= 0 && s30.doneMin > 0) {
        final avg = (s30.doneMin / 30.0)
            .clamp(floorMin.toDouble(), maxPerDayMin.toDouble());
        final seed = _roundTo5(avg * 0.80);
        if (seed > a.goalMin) {
          a.goalMin = seed;
          a.lastTuneAt = t;
          touched = true;
        }
        continue;
      }

      if (s30.ratio >= deadbandLow && s30.ratio <= deadbandHigh) continue;

      int capUp(int proposed) {
        final maxDelta = (a.goalMin * maxWeeklyPct).round();
        final ceil = (a.goalMin + maxDelta).clamp(floorMin, maxPerDayMin);
        return proposed.clamp(floorMin, ceil);
      }

      int capDown(int proposed) {
        final maxDelta = (a.goalMin * maxWeeklyPct).round();
        final floor = (a.goalMin - maxDelta).clamp(floorMin, maxPerDayMin);
        return proposed.clamp(floor, a.goalMin);
      }

      if (s30.ratio >= raiseTrigger) {
        final desired = (s30.doneMin / 30.0) / aimUp;
        var proposed = _roundTo5(desired);
        if (proposed < a.goalMin + minStepMin)
          proposed = a.goalMin + minStepMin;
        proposed = capUp(proposed);
        if (proposed > a.goalMin) {
          a.goalMin = proposed;
          a.lastTuneAt = t;
          touched = true;
        }
        continue;
      }

      if (s30.ratio <= lowerHard) {
        final desired = (s30.doneMin / 30.0) / aimDown;
        var proposed = _roundTo5(desired);
        if (proposed > a.goalMin - minStepMin)
          proposed = a.goalMin - minStepMin;
        proposed = capDown(proposed);
        if (proposed < a.goalMin) {
          a.goalMin = proposed;
          if (a.goalMin < floorMin) a.goalMin = floorMin;
          a.lastTuneAt = t;
          touched = true;
        }
      }
    }

    if (touched) onChange();
  }

  // ---------- Revue périodique des objectifs ----------
  Future<List<GoalChange>> reviewGoals({
    DateTime? now,
    int lookbackDays = 7,
    int neededHits = 5,
    double lower = 0.85,
    double upper = 1.15,
    double high = 1.50,
    double pctStep = 0.10,
    int minStepMin = 15,
    int maxPerDayMin = 12 * 60,
    double maxWeeklyPct = 0.20,
    bool force = false,
  }) async {
    final changes = <GoalChange>[];
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);

    if (!force && state.lastGoalsReview != null) {
      final last = DateTime(state.lastGoalsReview!.year,
          state.lastGoalsReview!.month, state.lastGoalsReview!.day);
      if (last == today) return changes;
    }

    final daysBack = List<DateTime>.generate(lookbackDays, (i) {
      final d = today.subtract(Duration(days: i + 1));
      return DateTime(d.year, d.month, d.day);
    });

    int clampNonNeg(int v) => v < 0 ? 0 : v;
    int clampToWeeklyCap(int base, int delta) {
      final cap = (base * maxWeeklyPct).round();
      if (cap <= 0) return delta;
      return delta > cap ? cap : delta;
    }

    // TIME
    for (final a in state.activities.where((x) => !x.isHabit)) {
      final base = a.goalMin;
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
        var step = (base * pctStep).round();
        if (step < minStepMin) step = minStepMin;
        step = clampToWeeklyCap(base, step);
        final boost = wayAbove >= (neededHits ~/ 2) ? (step ~/ 2) : 0;
        newGoal = (base + step + boost).clamp(0, maxPerDayMin);
      } else if (below >= neededHits) {
        var step = (base * pctStep).round();
        if (step < minStepMin) step = minStepMin;
        newGoal = math.max(kMinDailyGoalMin, base - step);
      }

      if (newGoal != base) {
        final delta = newGoal - base;
        a.goalMin = newGoal;
        changes.add(GoalChange(
            kind: 'activity', id: a.id, deltaMin: delta, newGoalMin: newGoal));
      }
    }

    // DOMAINES (manuel)
    for (final d in state.domains.where((dom) => !dom.autoGoal)) {
      final base = d.goalMinDay ?? 0;
      if (base <= 0) continue;

      int above = 0, below = 0, wayAbove = 0;

      for (final day in daysBack) {
        final ratio = domainProgressOnDay(d.id, day);
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
            kind: 'domain', id: d.id, deltaMin: delta, newGoalMin: newGoal));
      }
    }

    // HABITS : ajustements
    for (final a in state.activities.where((x) => x.isHabit)) {
      autoTuneHabitImmediate(this, a); // hausse immédiate si >120%
      _autoTuneHabitSafe(a, now: t); // finetune avec cooldown
    }

    state.lastGoalsReview = t;
    onChange();
    return changes;
  }

  void _autoTuneHabitSafe(Activity a, {DateTime? now}) {
    try {
      autoTuneHabit(this, a, now: now);
    } catch (_) {
      // no-op
    }
  }

  // ---------- Mesures glissantes ----------
  DateTimeRange lastNDays(int n, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final end = t;
    final start = t.subtract(Duration(days: n));
    return DateTimeRange(start: start, end: end);
  }

  ({int doneMin, int targetMin, double ratio}) timeSliding(
      String activityId, int days,
      {DateTime? now}) {
    final r = lastNDays(days, now: now);
    final dur = totalForRangeByActivity(activityId, r.start, r.end);
    final a = state.activities.firstWhere((x) => x.id == activityId);
    final target = (a.goalMin * days).clamp(0, 24 * 60 * days);
    final done = dur.inMinutes;
    final ratio = target > 0 ? (done / target).clamp(0.0, 1.0) : 0.0;
    return (doneMin: done, targetMin: target, ratio: ratio);
  }

  ({int done, int target, double ratio}) habitSliding(
    String activityId,
    int days, {
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();

    // Fenêtre CALENDAIRE (pas glissante à l’heure) :
    final today0 = DateTime(t.year, t.month, t.day);
    final start = today0.subtract(Duration(days: days - 1)); // J-(days-1) 00:00
    final end = today0.add(const Duration(days: 1)); // demain 00:00

    final done = habitSumForRange(activityId, start, end);

    final a = state.activities.firstWhere((x) => x.id == activityId);

    // cible "par jour" dérivée (selon ta fréquence effective)
    int perDay;
    switch (effectiveHabitFreq(a)) {
      case HabitFreq.daily:
        perDay = effectiveHabitTarget(a);
        break;
      case HabitFreq.weekly:
        perDay = (effectiveHabitTarget(a) / 7).ceil();
        break;
      case HabitFreq.monthly:
        perDay = (effectiveHabitTarget(a) / 30).ceil();
        break;
    }

    final target = perDay * days;
    final ratio = target > 0 ? (done / target).clamp(0.0, 1.0) : 0.0;

    return (done: done, target: target, ratio: ratio);
  }

  // ---------- Graph helpers ----------
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

  List<int> habitCountPerDay(DateTime start, int days, {String? domainId}) {
    final res = List<int>.filled(days, 0);

    for (int i = 0; i < days; i++) {
      // Jour i : fenêtre glissante de 24h qui SE TERMINE à la fin de ce jour
      final dayEnd = DateTime(start.year, start.month, start.day)
          .add(Duration(days: i + 1)); // minuit du jour suivant
      final dayStart = dayEnd.subtract(const Duration(hours: 24)); // glissant

      final acts = state.activities.where(
        (a) => a.isHabit && (domainId == null || a.domainId == domainId),
      );

      int sum = 0;
      for (final a in acts) {
        sum += habitSumForRange(a.id, dayStart, dayEnd);
      }
      res[i] = sum;
    }
    return res;
  }

  /// Objectif total d’habitudes/jour (somme des quotas journaliers dérivés)
  int habitDailyTarget({String? domainId}) {
    final acts = (domainId == null)
        ? state.activities.where((a) => a.isHabit)
        : state.activities.where((a) => a.isHabit && a.domainId == domainId);
    int t = 0;
    for (final a in acts) {
      t += dayQuotaFor(a); // ✅ plus de dailyTarget
    }
    return t;
  }

  // ---------- Aujourd’hui / Demain ----------
  String _todayKey() => yyyymmdd(DateTime.now());
  String _tomorrowKey() =>
      yyyymmdd(DateTime.now().add(const Duration(days: 1)));

  int _nextOrderForDay(String ymd) {
    final same = state.dayPlan.where((e) => e.yyyymmdd == ymd);
    if (same.isEmpty) return 0;
    return same.map((e) => e.order).reduce((a, b) => a > b ? a : b) + 1;
  }

  void ensurePlannedTomorrow(PlanKind kind, String refId) {
    final tomoKey = _tomorrowKey();
    final exists = state.dayPlan.any(
        (e) => e.yyyymmdd == tomoKey && e.kind == kind && e.refId == refId);
    if (exists) return;

    String title;
    switch (kind) {
      case PlanKind.activityTime:
        title = state.activities
            .firstWhere(
              (a) => a.id == refId,
              orElse: () =>
                  Activity(domainId: '', name: 'Activité', habitTarget: 1),
            )
            .name;
        break;
      case PlanKind.habit:
        title = state.activities
            .firstWhere(
              (a) => a.id == refId,
              orElse: () => Activity(
                  domainId: '', name: 'Routine', type: 'habit', habitTarget: 1),
            )
            .name;
        break;
      case PlanKind.action:
        title = 'Action';
        break;
    }

    state.dayPlan.add(DayPlanItem(
      id: _uuid.v4(),
      kind: kind,
      refId: refId,
      title: title,
      yyyymmdd: tomoKey,
      done: false,
      allDay: false,
      order: _nextOrderForDay(tomoKey),
    ));
  }

  bool removeFromDay(String ymd, PlanKind kind, String refId) {
    final before = state.dayPlan.length;
    state.dayPlan.removeWhere(
        (e) => e.yyyymmdd == ymd && e.kind == kind && e.refId == refId);
    return state.dayPlan.length != before;
  }

  void movePlannedToTomorrowIfPresent(PlanKind kind, String refId,
      {bool addIfMissing = false}) {
    final todayKey = _todayKey();
    final tomoKey = _tomorrowKey();

    final idx = _indexInDay(todayKey, kind, refId);
    DayPlanItem? removed;
    if (idx >= 0) {
      removed = state.dayPlan.removeAt(idx);
    }

    final existsTomorrow = _indexInDay(tomoKey, kind, refId) >= 0;
    if (existsTomorrow) {
      onChange();
      return;
    }

    DayPlanItem? toAdd;
    if (removed != null) {
      toAdd = DayPlanItem(
        id: removed.id,
        kind: removed.kind,
        refId: removed.refId,
        title: removed.title,
        yyyymmdd: tomoKey,
        done: false,
        allDay: removed.allDay,
        order: _nextOrderForDay(tomoKey),
      );
    } else if (addIfMissing) {
      String title;
      switch (kind) {
        case PlanKind.activityTime:
          title = state.activities
              .firstWhere(
                (a) => a.id == refId,
                orElse: () =>
                    Activity(domainId: '', name: 'Activité', habitTarget: 1),
              )
              .name;
          break;
        case PlanKind.habit:
          title = state.activities
              .firstWhere(
                (a) => a.id == refId,
                orElse: () => Activity(
                    domainId: '',
                    name: 'Routine',
                    type: 'habit',
                    habitTarget: 1),
              )
              .name;
          break;
        case PlanKind.action:
          title = 'Action';
          break;
      }
      toAdd = DayPlanItem(
        id: _uuid.v4(),
        kind: kind,
        refId: refId,
        title: title,
        yyyymmdd: tomoKey,
        done: false,
        allDay: false,
        order: _nextOrderForDay(tomoKey),
      );
    }

    if (toAdd != null) state.dayPlan.add(toAdd);
    onChange();
  }

// Hier → Aujourd'hui (copie les non-faits d'hier). À appeler 1x/jour au lancement.
  void maybeCarryFromYesterday({DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = _ymd(t);
    if (state.lastCarryYmd == today) return;
    rolloverUndone(now: t); // ta fonction existante (yesterday -> today)
    state.lastCarryYmd = today;
    onChange();
  }

// Aujourd'hui → Demain (déplace les non-faits). À appeler le soir (ou via bouton).
  void maybePrepTomorrow(
      {DateTime? now, int cutoffHour = 22, bool force = false}) {
    final t = now ?? DateTime.now();
    final today = _ymd(t);
    if (!force) {
      if (t.hour < cutoffHour) return; // pas encore l’heure
      if (state.lastPrepYmd == today) return; // déjà fait aujourd’hui
    }
    rolloverUnfinishedToTomorrow(
        now: t); // ta fonction existante (today -> tomorrow)
    state.lastPrepYmd = today;
    onChange();
  }

  // ---------- Rollover (facultatif) ----------
  void rolloverUnfinishedToTomorrow({DateTime? now}) {
    final _now = now ?? DateTime.now();
    final String todayKey = yyyymmdd(_now);
    final String tomorrowKey = yyyymmdd(_now.add(const Duration(days: 1)));

    int nextOrder = 1;
    for (final e in state.dayPlan.where((e) => e.yyyymmdd == tomorrowKey)) {
      if (e.order >= nextOrder) nextOrder = e.order + 1;
    }

    final todayItems =
        state.dayPlan.where((e) => e.yyyymmdd == todayKey).toList();

    bool _shouldMove(DayPlanItem it) {
      switch (it.kind) {
        case PlanKind.action:
          return it.done == false;
        case PlanKind.habit:
          final a = state.activities.firstWhere((x) => x.id == it.refId);
          final freq = effectiveHabitFreq(a);
          if (freq != HabitFreq.daily)
            return false; // on ne déplace auto que le quotidien
          final d = DateTime(_now.year, _now.month, _now.day);
          final done = habitValueOn(it.refId!, d);
          final target = dayQuotaFor(a);
          return done < target;
        case PlanKind.activityTime:
          final dayStart = DateTime(_now.year, _now.month, _now.day);
          final dur = totalForRangeByActivity(it.refId!, dayStart, _now);
          return dur.inMinutes == 0;
      }
    }

    for (final it in todayItems) {
      if (_shouldMove(it)) {
        it.yyyymmdd = tomorrowKey;
        it.order = nextOrder++;
      }
    }

    onChange();
  }

  // =====================
// HABITS: helpers cible/done + atteint ?
// =====================

// Quota "jour" pour l’anneau
  int dayQuotaFor(Activity a) {
    final f = a.habitFreq ?? HabitFreq.monthly;
    final t = a.habitTarget ?? 1;
    return (f == HabitFreq.daily) ? t : 1; // hebdo/mensuel = 1/jour
  }

// Cible semaine (affichage)
  int weekTargetFrom(Activity a) {
    final f = a.habitFreq ?? HabitFreq.monthly;
    final t = a.habitTarget ?? 1;
    switch (f) {
      case HabitFreq.daily:
        return t * 7;
      case HabitFreq.weekly:
        return t;
      case HabitFreq.monthly:
        return (t / 4).ceil(); // approx 4 semaines
    }
  }

// Cible mois (affichage)
  int monthTargetFrom(Activity a) {
    final f = a.habitFreq ?? HabitFreq.monthly;
    final t = a.habitTarget ?? 1;
    switch (f) {
      case HabitFreq.daily:
        return t * 30;
      case HabitFreq.weekly:
        return t * 4; // approx 4 semaines
      case HabitFreq.monthly:
        return t;
    }
  }

// A-t-on atteint la cible active (selon la fréquence actuelle) ?
  bool habitReached(Activity a) {
    final f = a.habitFreq ?? HabitFreq.monthly;

    int target;
    int done;

    if (f == HabitFreq.daily) {
      target = dayQuotaFor(a);
      done = habitSliding(a.id, 1).done;
    } else if (f == HabitFreq.weekly) {
      target = weekTargetFrom(a);
      done = habitSliding(a.id, 7).done;
    } else {
      target = monthTargetFrom(a);
      done = habitSliding(a.id, 30).done;
    }

    return target > 0 && done >= target;
  }

// ========= GOALS: progression globale d’un objectif =========
// 1) Priorité aux étapes (steps planned / done)
// 2) Sinon, si effort estimé (en minutes) + activité liée → calcule via sessions temps
// 3) Sinon, pas de métrique (ratio/label = null)
  ({double? ratio, String? label}) goalProgress(Goal g, {DateTime? now}) {
    // 1) Étapes
    if (g.stepsPlanned != null && g.stepsPlanned! > 0) {
      final planned = g.stepsPlanned!;
      final done = g.stepsDone.clamp(0, planned);
      final r = (done / planned).clamp(0.0, 1.0);
      return (ratio: r, label: "Étapes ${done}/${planned}");
    }

    // 2) Effort Temps (nécessite une activité liée et une estimation en minutes)
    if (g.effortEstimateMin != null &&
        g.effortEstimateMin! > 0 &&
        g.activityId != null) {
      final start = g.createdAt; // début de l’obj (supposé présent dans Goal)
      final end = now ?? DateTime.now();
      final spent =
          totalForRangeByActivity(g.activityId!, start, end).inMinutes;
      final est = g.effortEstimateMin!;
      final r = (spent / est).clamp(0.0, 1.0);
      return (ratio: r, label: "Effort ${spent}/${est}m");
    }

    // 3) Pas de métrique mesurable pour l’instant
    return (ratio: null, label: null);
  }

// ========= GOALS: rythme hebdo sur l’activité liée =========
// - Temps: utilise timeSliding(7j) → "Semaine Xm / Ym"
// - Habitude: utilise habitSliding(7j) → "Semaine X / Y <unité>"
  ({double ratio, String label}) goalWeeklyPace(Goal g, {DateTime? now}) {
    if (g.activityId == null) return (ratio: 0.0, label: "Semaine 0 / 0");

    // Récupère l’activité (si absente → neutre)
    final idx = state.activities.indexWhere((a) => a.id == g.activityId);
    if (idx < 0) return (ratio: 0.0, label: "Semaine 0 / 0");
    final act = state.activities[idx];

    if (!act.isHabit) {
      final w = timeSliding(act.id, 7, now: now); // {doneMin,targetMin,ratio}
      return (ratio: w.ratio, label: "Semaine ${w.doneMin}/${w.targetMin}m");
    } else {
      final w = habitSliding(act.id, 7, now: now); // {done,target,ratio}
      final unit = (act.unit ?? '').isNotEmpty ? ' ${act.unit}' : '';
      return (ratio: w.ratio, label: "Semaine ${w.done}/${w.target}$unit");
    }
  }

// ========= GOALS: incrémenter/décrémenter le nombre d’étapes =========
  void incGoalStep(String goalId, {int delta = 1}) {
    final i = state.goals.indexWhere((x) => x.id == goalId);
    if (i < 0) return;
    final g = state.goals[i];

    // stepsPlanned peut être null → on clamp seulement sur 0..(planned?) si présent
    if (g.stepsPlanned != null) {
      final maxSteps = g.stepsPlanned!;
      g.stepsDone = (g.stepsDone + delta).clamp(0, maxSteps);
    } else {
      // pas de plafond connu : clamp 0..999999 (ou ce que tu veux)
      g.stepsDone = (g.stepsDone + delta).clamp(0, 999999);
    }

    onChange(); // persiste + notifie l’UI
  }

// Cible active (selon la fréquence courante de la routine)
  int activeHabitTarget(Activity a) {
    final f = a.habitFreq ?? HabitFreq.monthly; // défaut raisonnable
    switch (f) {
      case HabitFreq.daily:
        return dayQuotaFor(a); // ex: 1/jour
      case HabitFreq.weekly:
        return weekTargetFrom(a); // ex: 1/sem
      case HabitFreq.monthly:
        return monthTargetFrom(a); // ex: 4/mois
    }
  }

// Réalisé à date sur la fenêtre active (1, 7 ou 30 jours)
  int activeHabitDone(Activity a) {
    final f = a.habitFreq ?? HabitFreq.monthly;
    switch (f) {
      case HabitFreq.daily:
        return habitSliding(a.id, 1).done;
      case HabitFreq.weekly:
        return habitSliding(a.id, 7).done;
      case HabitFreq.monthly:
        return habitSliding(a.id, 30).done;
    }
  }

  /// Somme des cibles actives pour un domaine (ou tous si null).
  int sumHabitTarget(String? domainId, int days) {
    // on choisit le mode : si days=1 → daily, si 7 → weekly, si 30 → monthly
    return state.activities
        .where((a) => a.isHabit && (domainId == null || a.domainId == domainId))
        .fold<int>(0, (sum, a) {
      final freq = a.habitFreq ?? HabitFreq.monthly;
      int perDay;
      switch (freq) {
        case HabitFreq.daily:
          perDay = effectiveHabitTarget(a);
          break;
        case HabitFreq.weekly:
          perDay = (effectiveHabitTarget(a) / 7).ceil();
          break;
        case HabitFreq.monthly:
          perDay = (effectiveHabitTarget(a) / 30).ceil();
          break;
      }
      return sum + perDay * days;
    });
  }

  /// Somme des réalisés sur N jours pour un domaine.
  int sumHabitDone(String? domainId, int days) {
    final r = lastNDays(days); // [now - days, now)
    final acts = state.activities.where(
      (a) => a.isHabit && (domainId == null || a.domainId == domainId),
    );

    int done = 0;
    for (final a in acts) {
      done += habitSumForRange(a.id, r.start, r.end);
    }
    return done;
  }
}

// =====================================================
// ===================  EXTENSIONS  ====================
// =====================================================

extension TodayLogic on AppLogic {
  int _indexInDay(String ymd, PlanKind kind, String refId) {
    return state.dayPlan.indexWhere(
        (e) => e.yyyymmdd == ymd && e.kind == kind && e.refId == refId);
  }

  List<DayPlanItem> planFor(String ymd) {
    final list = state.dayPlan.where((e) => e.yyyymmdd == ymd).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  String _todayKeyLocal() {
    final now = DateTime.now();
    return yyyymmdd(DateTime(now.year, now.month, now.day));
  }

  Future<void> addPlanAction({
    required String ymd, // <- tu peux garder le param pour compat,
    required String title,
  }) async {
    final todayKey = _todayKeyLocal(); // toujours le jour local
    final ord = planFor(todayKey).isEmpty // ← corriger ici
        ? 0
        : planFor(todayKey).last.order + 1;

    state.dayPlan.add(DayPlanItem(
      id: _uuid.v4(),
      kind: PlanKind.action,
      title: title,
      yyyymmdd: todayKey, // on force la clé locale
      order: ord,
    ));
    onChange();
  }

  Future<void> addPlanActivity({
    required String ymd,
    required String activityId,
    required bool isHabit,
    bool allDay = false,
  }) async {
    final act = state.activities.firstWhere((a) => a.id == activityId);
    final todayKey = _todayKeyLocal();
    final ord =
        planFor(todayKey).isEmpty ? 0 : planFor(todayKey).last.order + 1;

    state.dayPlan.add(DayPlanItem(
      id: const Uuid().v4(),
      kind: isHabit ? PlanKind.habit : PlanKind.activityTime,
      refId: activityId,
      title: act.name,
      yyyymmdd: todayKey, // 👈 toujours le jour local
      allDay: isHabit ? allDay : false,
      order: ord,
    ));
    onChange();
  }

  void toggleDone(String itemId, bool done) {
    final i = state.dayPlan.indexWhere((e) => e.id == itemId);
    if (i >= 0) {
      state.dayPlan[i].done = done;
      onChange();
    }
  }

  void reorderPlan(String ymd, int oldIndex, int newIndex) {
    final list = planFor(ymd);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    for (int i = 0; i < list.length; i++) {
      list[i].order = i;
    }
    onChange();
  }

  void rolloverUndone({DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = yyyymmdd(DateTime(t.year, t.month, t.day));
    final yesterday = yyyymmdd(
        DateTime(t.year, t.month, t.day).subtract(const Duration(days: 1)));

    final carry =
        state.dayPlan.where((e) => e.yyyymmdd == yesterday && !e.done).toList();
    if (carry.isEmpty) return;

    final baseOrder = planFor(today).length;
    for (int i = 0; i < carry.length; i++) {
      final e = carry[i];
      state.dayPlan.add(DayPlanItem(
        id: const Uuid().v4(),
        kind: e.kind,
        refId: e.refId,
        title: e.title,
        yyyymmdd: today,
        done: false,
        allDay: e.allDay,
        order: baseOrder + i,
      ));
    }

    // Optionnel : supprimer les doublons anciens
    state.dayPlan.removeWhere((e) => e.yyyymmdd == yesterday);
    onChange();
  }

  void ensureTodayDailyHabits({DateTime? now}) {
    final t = now ?? DateTime.now();
    final todayKey = yyyymmdd(t);
    final todayDate = DateTime(t.year, t.month, t.day);

    bool changed = false;

    for (final a in state.activities.where((x) => x.isHabit)) {
      // On ne gère que les routines "quotidiennes" actives
      if (effectiveHabitFreq(a) != HabitFreq.daily) continue;

      final quota = dayQuotaFor(a);
      if (quota <= 0) continue;

      final done = habitValueOn(a.id, todayDate);

      if (done >= quota) {
        // Déjà atteinte aujourd’hui → s’assurer qu’elle N’EST PAS dans "Aujourd’hui"
        final removed = removeFromDay(todayKey, PlanKind.habit, a.id);
        if (removed) changed = true;
        continue;
      }

      // Pas encore atteinte → s’assurer qu’elle EST dans "Aujourd’hui"
      final exists = state.dayPlan.any((e) =>
          e.yyyymmdd == todayKey &&
          e.kind == PlanKind.habit &&
          e.refId == a.id);
      if (!exists) {
        state.dayPlan.add(DayPlanItem(
          id: const Uuid().v4(),
          kind: PlanKind.habit,
          refId: a.id,
          title: a.name,
          yyyymmdd: todayKey,
          done: false,
          allDay: true, // utile pour visuel "sur la journée"
          order: _nextOrderForDay(todayKey),
        ));
        changed = true;
      }
    }

    if (changed) onChange(); // persiste + notifie l’UI
  }
}

// =====================================================
// =================  OUTILS ANNEXES  ==================
// =====================================================

class FocusItem {
  final String kind; // 'time' | 'habit' | 'goal'
  final double score;
  final String reason;
  final Activity? activity;
  final Goal? goal;
  final Duration? timeDeficit;
  final int? habitDeficit;
  final String? titleOverride;
  final String? subtitleOverride;

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

// Auto-tune “intelligent” (respecte manualTarget, cooldown)
List<TuneChange> autoTuneHabit(AppLogic l, Activity a, {DateTime? now}) {
  final res = <TuneChange>[];
  if (!a.isHabit || (a.autoTune == false) || (a.manualTarget == true))
    return res;

  final t = now ?? DateTime.now();
  if (a.lastTuneAt != null && t.difference(a.lastTuneAt!).inDays < 7)
    return res;

  final freq = l.effectiveHabitFreq(a);
  int target = l.effectiveHabitTarget(a);

  final w = l.habitSliding(a.id, 7).done;
  final m = l.habitSliding(a.id, 30).done;

  bool changed = false;

  int clampMin(int v) => v < 1 ? 1 : v;

  if (freq == HabitFreq.monthly) {
    if (m >= target + 1) {
      target += 1;
      changed = true;
    }
    if (!changed && target >= 4) {
      a.habitFreq = HabitFreq.weekly;
      target = (target / 4.0).ceil();
      changed = true;
    }
  } else if (freq == HabitFreq.weekly) {
    if (w >= target + 1) {
      target += 1;
      changed = true;
    }
    if (!changed && target >= 6) {
      a.habitFreq = HabitFreq.daily;
      target = 1;
      changed = true;
    }
  } else {
    // daily : optionnel (on garde simple)
  }

  if (!changed) {
    final p = l.habitPeriod(a, now: t);
    if (p.ratio < 0.6 && target > 1) {
      target -= 1;
      changed = true;
    }
  }

  if (changed) {
    a.habitTarget = clampMin(target);
    a.lastTuneAt = t;
    l.onChange();
    res.add(TuneChange(a.id, 'auto-tune → ${a.habitFreq} x${a.habitTarget}'));
  }
  return res;
}

// Hausse immédiate si >120% de la période active (respecte manualTarget)
void autoTuneHabitImmediate(AppLogic l, Activity a) {
  if (!a.isHabit || (a.manualTarget == true)) return;

  final freq = l.effectiveHabitFreq(a);
  final target = l.effectiveHabitTarget(a);
  if (target <= 0) return;

  int done;
  switch (freq) {
    case HabitFreq.daily:
      done = l.habitSliding(a.id, 1).done;
      break;
    case HabitFreq.weekly:
      done = l.habitSliding(a.id, 7).done;
      break;
    case HabitFreq.monthly:
      done = l.habitSliding(a.id, 30).done;
      break;
  }

  final ratio = target > 0 ? (done / target) : 0.0;

  if (ratio >= 1.20) {
    int newTarget;
    if (freq == HabitFreq.monthly) {
      if (done >= 4) {
        a.habitFreq = HabitFreq.weekly;
        a.habitTarget = 1;
        return;
      }
      newTarget = (done / 0.95).ceil();
      if (newTarget < target + 1) newTarget = target + 1;
      a.habitTarget = newTarget;
      return;
    }
    if (freq == HabitFreq.weekly) {
      if (done >= 7) {
        a.habitFreq = HabitFreq.daily;
        a.habitTarget = 1;
        return;
      }
      newTarget = (done / 0.95).ceil();
      if (newTarget < target + 1) newTarget = target + 1;
      a.habitTarget = newTarget;
      return;
    }
    // daily
    newTarget = (done / 0.95).ceil();
    if (newTarget < target + 1) newTarget = target + 1;
    a.habitTarget = newTarget;
  }
}

// ---------- Utilitaires ----------
int _roundTo5(num x) => (x / 5.0).round() * 5;

// ---------- Sliding helpers pour domaines/graphs ----------
extension SlidingProgress on AppLogic {
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

  double timePct(String activityId, DateTime start, DateTime end, int days) {
    final doneMin = totalForRangeByActivity(activityId, start, end).inMinutes;
    final goalDay =
        state.activities.firstWhere((a) => a.id == activityId).goalMin;
    final target = goalDay * days;
    if (target <= 0) return 0.0;
    return doneMin / target;
  }
}

// ---------- Focus/Goals annexes ----------
class GoalChange {
  final String kind; // 'activity' | 'domain'
  final String id;
  final int deltaMin;
  final int newGoalMin;
  GoalChange(
      {required this.kind,
      required this.id,
      required this.deltaMin,
      required this.newGoalMin});
}
