// applogic.dart — version sans dailyTarget, cibles dérivées partout ✨

// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/time_scope.dart';
import 'package:productivitwo_v1/widgets/appbar_routines_summery.dart';
import 'package:productivitwo_v1/widgets/habit_settings_sheet.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';

// ---------- Constantes ----------
const int kMinDailyGoalMin = 1; // plancher dur pour activités "time"

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

sealed class RowItem {
  String get id;
  const RowItem();
}

class RowHeader extends RowItem {
  @override
  final String id;
  final String title;
  const RowHeader(this.id, this.title);
}

enum HabitAssocEventType { pinned, changeSuggested }

class HabitAssocEvent {
  final HabitAssocEventType type;
  final String habitId;
  final String? fromActivityId;
  final String? toActivityId;

  const HabitAssocEvent._(
    this.type, {
    required this.habitId,
    this.fromActivityId,
    this.toActivityId,
  });

  factory HabitAssocEvent.pinned(String habitId, String toActId) =>
      HabitAssocEvent._(HabitAssocEventType.pinned,
          habitId: habitId, toActivityId: toActId);

  factory HabitAssocEvent.changeSuggested(
          String habitId, String fromActId, String toActId) =>
      HabitAssocEvent._(HabitAssocEventType.changeSuggested,
          habitId: habitId, fromActivityId: fromActId, toActivityId: toActId);
}

class HabitTrendPoint {
  final DateTime day; // jour de l’axe (30 points)
  final double avg7; // moyenne brute / jour (sur 7 jours)
  final double ratio; // avg7 / rythmeAttendu (0..1+)
  const HabitTrendPoint(this.day, this.avg7, this.ratio);
}

// =====================================================
// ===============  LOGIQUE PRINCIPALE  ================
// =====================================================

/// Contexte de scoring d'une fenêtre : références p90 (temps / projets),
/// minutes totales/jour, et quelles dimensions sont actives pour l'utilisateur.
typedef ScoreCtx = ({
  double timeRef,
  double ganttRef,
  Map<String, int> totalMinByDay,
  bool timeActive,
  bool ganttActive,
});

/// Sous-score d'une dimension de productivité du jour (pour la triade visuelle).
/// [isFocus] = dimension active la plus basse (le levier à travailler).
typedef DimScore = ({
  String key,
  String label,
  double score,
  String detail,
  bool isFocus,
});

class AppLogic {
  AppState state;

  final void Function() onChange;
  AppLogic(this.state, this.onChange);

  /// Hook posé par l'écran d'accueil pour lancer un minuteur (vraie alarme) depuis
  /// n'importe quelle feuille modale (ex. mode 5 min du donjon). Null si pas prêt.
  void Function(int minutes, String activityName, {String? routineId})?
      launchTimerHook;

  /// Accès Firestore pour les écritures autoritatives d'or (posé après
  /// construction dans main.dart). Null tant que non configuré.
  FirestoreSync? sync;

  String? nowHabitId; // habitId actuellement affichée dans Maintenant (routine)
  String? _checkYmd; // pour reset journalier

  // Score Gantt par jour (ymd -> 0.0..1.0) : progression moyenne des tâches travaillées ce jour
  // Mis à jour depuis main.dart à chaque changement du stream projets
  // Actions Gantt cochées par jour (yyyymmdd → nombre). Sert de signal "projets"
  // dans le score de productivité, normalisé sur le standard propre de l'user (p90).
  final Map<String, int> _ganttDonePerDay = {};

  // Snapshot des projets actifs — mis à jour par updateGanttCounts()
  List<Project> currentProjects = [];

  void updateGanttCounts(List<Project> projects) {
    currentProjects = projects;
    _ganttDonePerDay.clear();

    // Nombre d'actions cochées par jour (clé = doneAt). Le score de productivité
    // normalise ensuite ce count sur le standard propre de l'utilisateur (p90),
    // au lieu de l'ancien dénominateur « backlog total » qui plombait le score
    // dès qu'on avait beaucoup d'actions planifiées.
    for (final project in projects) {
      if (project.status != 'active') continue; // draft + archived hors score/gains
      for (final task in project.tasks) {
        if (task.status == 'skipped') continue;
        for (final action in task.actions) {
          if (action.done && action.doneAt != null) {
            final ymd = yyyymmdd(action.doneAt!);
            _ganttDonePerDay[ymd] = (_ganttDonePerDay[ymd] ?? 0) + 1;
          }
        }
      }
    }
  }

  /// Positionner à true avant une suppression pour éviter que le badge
  /// "journée parfaite" se déclenche sur un score artificiellement à 100%.
  bool skipBadgeCheck = false;

  String? _avg7CacheDayKey;
  double? _avg7CacheValue;

  final Map<String, Set<String>> _checkedTodayByHabit =
      {}; // habitId -> labels cochés

  final ValueNotifier<int> rev = ValueNotifier<int>(0);

  void bumpRev() => rev.value++;

  Future<void> attachLinkedActivityToRoutine(
    String habitId,
    String? linkedTimeActivityId,
  ) async {
    final acts = state.activeActivities;

    final idx = acts.indexWhere((a) => a.id == habitId);
    if (idx == -1) return;

    final routine = acts[idx];

    final updated = routine.copyWith(
      linkedActivityId: linkedTimeActivityId,
    );

    // remplace dans la liste existante
    acts[idx] = updated;

    // si tu as une persistance
    //await saveActivity(updated);

    // refresh UI
    onChange();
    rev.value++;
  }

  RoutineCatchupSummary routineCatchupSummary() {
    final routines = routineProgressItemsForCurrentPeriod();

    int achieved = 0;
    int remaining = 0;

    for (final r in routines) {
      if (r.done >= r.target) {
        achieved++;
      } else {
        remaining++;
      }
    }

    return RoutineCatchupSummary(
      achieved: achieved,
      remaining: remaining,
    );
  }

  RoutineProgressSummary routineProgressSummaryForCurrentPeriod() {
    final items = routineProgressItemsForCurrentPeriod();

    int reached = 0;
    int catchup = 0;

    for (final it in items) {
      if (it.isReached) {
        reached++;
      } else if (it.isCatchup) {
        catchup++;
      }
    }

    return RoutineProgressSummary(
      reached: reached,
      catchup: catchup,
    );
  }

  List<RoutineProgressItem> routineProgressItemsForCurrentPeriod() {
    final base = state.activeActivities.where((a) => a.isHabit).toList();

    double ratio(Activity a) {
      final tgt = activeHabitTarget(a);
      if (tgt <= 0) return 0.0;
      final done = activeHabitDone(a);
      return (done / tgt).clamp(0.0, 1.0);
    }

    base.sort((x, y) => (1 - ratio(x)).compareTo(1 - ratio(y)));

    return base
        .map((a) => RoutineProgressItem(
              activity: a,
              label: a.name,
              done: activeHabitDone(a),
              target: activeHabitTarget(a),
            ))
        .where((it) => it.target > 0)
        .toList();
  }

  Activity? getActivityById(String id) {
    for (final a in state.activeActivities) {
      if (a.id == id) return a;
    }
    return null;
  }

  double _expectedPerDay(Activity a) {
    final freq = effectiveHabitFreq(a);
    final target = effectiveHabitTarget(a).clamp(1, 999999);

    switch (freq) {
      case HabitFreq.daily:
        return target.toDouble(); // ex: 10/j
      case HabitFreq.weekly:
        return target / 7.0; // ex: 1/sem => ~0.142/j
      case HabitFreq.monthly:
        return target / 30.0; // ex: 1/mois => ~0.033/j
    }
  }

  List<int> habitBars30dUi(String habitId, DateTime now, {int maxBar = 10}) {
    final a = state.activeActivities.firstWhere((x) => x.id == habitId);
    final freq = effectiveHabitFreq(a);

    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 29));

    int valueOn(DateTime d) =>
        habitValueOn(habitId, DateTime(d.year, d.month, d.day));

    double expectedPerDay() {
      final t = effectiveHabitTarget(a).clamp(1, 999999);
      switch (freq) {
        case HabitFreq.daily:
          return t.toDouble(); // ex 10/j
        case HabitFreq.weekly:
          return t / 7.0; // ex 1/sem => 0.14/j
        case HabitFreq.monthly:
          return t / 30.0; // ex 1/mois => 0.03/j
      }
    }

    double avg7At(DateTime d) {
      int sum = 0;
      for (int i = 0; i < 7; i++) {
        final dd = d.subtract(Duration(days: i));
        sum += valueOn(dd);
      }
      return sum / 7.0;
    }

    final out = <int>[];
    final exp = expectedPerDay();

    for (int i = 0; i < 30; i++) {
      final d = start.add(Duration(days: i));

      if (freq == HabitFreq.daily) {
        // ✅ exactement comme avant (barres brutes)
        final v = valueOn(d).clamp(0, maxBar);
        out.add(v);
      } else {
        // ✅ lissé + normalisé
        final avg7 = avg7At(d);
        final ratio = exp <= 0.000001 ? 0.0 : (avg7 / exp); // 1.0 = au rythme
        final scaled = (ratio * maxBar).round(); // 0..maxBar
        out.add(scaled.clamp(0, maxBar));
      }
    }

    return out;
  }

  List<HabitTrendPoint> habitTrend30dAvg7(String habitId, DateTime now) {
    final a = state.activeActivities.firstWhere((x) => x.id == habitId);
    final expected = _expectedPerDay(a); // rythme attendu / jour

    final end = _dayOnly(now);
    final start = end.subtract(const Duration(days: 29)); // 30 jours inclus

    // Pour accélérer : map ymd -> value
    final map = <String, int>{};
    for (final hp in state.habitProgress) {
      if (hp.activityId != habitId) continue;
      map[hp.yyyymmdd] = hp.value;
    }

    int valueOn(DateTime d) => map[yyyymmdd(d)] ?? 0;

    // calc avg7 sur fenêtre [d-6..d]
    double avg7At(DateTime d) {
      int sum = 0;
      for (int i = 0; i < 7; i++) {
        final dd = d.subtract(Duration(days: i));
        sum += valueOn(dd);
      }
      return sum / 7.0;
    }

    final out = <HabitTrendPoint>[];
    for (int i = 0; i < 30; i++) {
      final d = start.add(Duration(days: i));
      final avg7 = avg7At(d);

      // ratio “progression vs rythme attendu”
      final ratio = expected <= 0.000001 ? 0.0 : (avg7 / expected);

      out.add(HabitTrendPoint(d, avg7, ratio));
    }
    return out;
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int habitValueOnYmd(String habitId, String ymd) {
    final idx = state.habitProgress.indexWhere(
      (h) => h.activityId == habitId && h.yyyymmdd == ymd,
    );
    if (idx < 0) return 0;
    return state.habitProgress[idx].value;
  }

  void deleteActivityCascade(String activityId) {
    final id = activityId.trim();
    if (id.isEmpty) return;

    // 1) stop si c’est l’activité en cours
    final running = runningActivity();
    if (running != null && running.id == id) {
      stopActive();
    }

    // 2) soft-delete : marque deleted=true (JAMAIS removeWhere — sinon le merge
    //    Firestore la fait réapparaître à la réouverture, le remote la gardant
    //    en deleted:false). Même pattern que la suppression de domaine.
    final idx = state.activities.indexWhere((a) => a.id == id);
    if (idx >= 0) {
      final act = state.activities[idx];
      // Coût d'or : supprimer une routine (habit) coûte (déduction douce, plancher 0).
      if (act.isHabit && sync != null) {
        sync!.applyGold(GoldLedgerEntry(
          delta: -GoldEconomy.deleteRoutine,
          category: 'loss',
          reasonCode: 'delete_routine',
          label: 'Suppression routine « ${act.name} »',
          refType: 'activity',
          refId: act.id,
        ));
      }
      act.deleted = true;
    }

    // 3) purge filtres
    state.filters.activityIds.remove(id);

    onChange();
  }

  Activity? _firstWhereOrNull<T extends Object>(
    Iterable<Activity> items,
    bool Function(Activity) test,
  ) {
    for (final x in items) {
      if (test(x)) return x;
    }
    return null;
  }

  String activityName(String activityId) {
    final a = _firstWhereOrNull(
      state.activeActivities,
      (x) => x.id == activityId,
    );
    return a?.name ?? 'Activité';
  }

  List<ActivityLog> logsBetween(DateTime from, DateTime to) {
    return state.activityLogs.where((l) {
      final e = l.end ?? DateTime.now();
      return l.start.isBefore(to) && e.isAfter(from); // intersection fenêtre
    }).toList();
  }

  void deleteLog(String logId) {
    state.activityLogs.removeWhere((l) => l.id == logId);
    onChange(); // persiste
  }

  void updateLog(String logId, {DateTime? start, DateTime? end}) {
    final idx = state.activityLogs.indexWhere((l) => l.id == logId);
    if (idx < 0) return;
    final old = state.activityLogs[idx];
    state.activityLogs[idx] = ActivityLog(
      id: old.id,
      activityId: old.activityId,
      start: start ?? old.start,
      end: end,
    );
    onChange();
  }

  void ensureChecklistDay(String ymd) {
    if (_checkYmd == ymd) return;
    _checkYmd = ymd;
    _checkedTodayByHabit.clear();
  }

  Set<String> checkedTodayForHabit(String habitId) =>
      _checkedTodayByHabit[habitId] ?? <String>{};

  void setCheckedToday(String habitId, String label, bool checked) {
    final s = _checkedTodayByHabit.putIfAbsent(habitId, () => <String>{});
    if (checked) {
      s.add(label);
    } else {
      s.remove(label);
    }
  }

  bool isActivitySnoozed(String? activityId, DateTime now) {
    final id = (activityId ?? '').trim();
    if (id.isEmpty) return false; // ✅ IMPORTANT

    final s = state.snoozedUntil[id];
    if (s == null || s.isEmpty) return false;

    final u = DateTime.tryParse(s);
    return u != null && u.isAfter(now);
  }

  void unsnoozeActivity(String? activityId) {
    final id = (activityId ?? '').trim();
    if (id.isEmpty) return;
    state.snoozedUntil.remove(id);
    onChange();
  }

  void snoozeActivityFar(String? activityId) {
    final id = (activityId ?? '').trim();
    if (id.isEmpty) return;
    state.snoozedUntil[id] = DateTime(2099, 12, 31).toIso8601String();
    onChange();
  }

  void toggleActivitySnooze(String? activityId) {
    final id = (activityId ?? '').trim();
    if (id.isEmpty) return; // ✅ IMPORTANT

    final now = DateTime.now();
    if (isActivitySnoozed(id, now)) {
      unsnoozeActivity(id);
    } else {
      snoozeActivityFar(id);
    }
  }

  void snoozeActivityUntil(String activityId, DateTime until) {
    state.snoozedUntil[activityId] = until.toIso8601String();
    onChange();
  }

  void clearSnooze(String activityId) {
    state.snoozedUntil.remove(activityId);
    onChange();
  }

  String? _lastRolloverDay;
  final List<HabitAssocEvent> habitAssocEvents = [];

  String? forcedNowHabitId;

  void forceNowHabit(String habitId) {
    forcedNowHabitId = habitId;
  }

  void pinHabitToActivity(String habitId, String activityId) {
    habitAssocEvents.removeWhere(
        (e) => e.type == HabitAssocEventType.pinned && e.habitId == habitId);
    habitAssocEvents.add(HabitAssocEvent.pinned(habitId, activityId));
  }

  String? pinnedActivityForRoutine(String routineId) {
    for (var i = habitAssocEvents.length - 1; i >= 0; i--) {
      final e = habitAssocEvents[i];
      if (e.habitId == routineId && e.type == HabitAssocEventType.pinned) {
        return e.toActivityId;
      }
    }
    return null;
  }

  void pinRoutineToActivity(String routineId, String activityId) {
    // retire les anciens pinned de cette routine
    habitAssocEvents.removeWhere(
      (e) => e.habitId == routineId && e.type == HabitAssocEventType.pinned,
    );
    habitAssocEvents.add(HabitAssocEvent.pinned(routineId, activityId));
    onChange(); // si tu as déjà une persistance centrale; sinon setState côté UI
  }

  void deleteSession(String sessionId) {
    state.sessions.removeWhere((s) => s.id == sessionId);
    onChange();
  }

  void updateSession(
    String sessionId, {
    DateTime? startAt,
    DateTime? endAt,
    String? activityId,
  }) {
    final s = state.sessions.firstWhere((x) => x.id == sessionId);

    if (startAt != null) s.startAt = startAt;
    s.endAt = endAt;
    if (activityId != null) s.activityId = activityId;

    onChange();
  }

  Activity? runningActivity() {
    Session? last;
    for (final s in state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    if (last == null) return null;

    return state.activeActivities.firstWhere(
      (a) => a.id == last!.activityId,
      orElse: () => Activity(domainId: '', name: '', habitTarget: 1),
    );
  }

  String? runningActivityId() {
    // dernière session non terminée (si plusieurs, prends la plus récente)
    Session? last;
    for (final s in state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last?.activityId;
  }

  String? runningDomainId() {
    final actId = runningActivityId();
    if (actId == null) return null;

    final a = state.activeActivities.firstWhere(
      (x) => x.id == actId,
      orElse: () => Activity(domainId: '', name: '', habitTarget: 1),
    );
    return a.domainId.isEmpty ? null : a.domainId;
  }

  void rolloverUndoneOncePerDay({DateTime? now}) {
    final t = now ?? DateTime.now();
    final todayKey = yyyymmdd(DateTime(t.year, t.month, t.day));
    if (_lastRolloverDay == todayKey) return;

    rolloverUndone(now: t);
    _lastRolloverDay = todayKey;
  }

  // Retourne la liste d'activités du focus (en respectant les IDs)
  List<Activity> get focusToday {
    final ids = state.focusTodayIds.toSet();
    if (ids.isEmpty) return [];
    return state.activeActivities.where((a) => ids.contains(a.id)).toList();
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

  void setActivityTodayFlag(String activityId, bool value) {
    final idx = state.activities.indexWhere((a) => a.id == activityId);
    if (idx < 0) return;
    state.activities[idx].todayFlag = value;
    onChange();
  }

  /// Sauvegarde la durée minuteur préférée pour une activité (null = chrono libre).
  void setActivityTimerMin(String activityId, int? minutes) {
    final idx = state.activities.indexWhere((a) => a.id == activityId);
    if (idx < 0) return;
    state.activities[idx].timerMin = minutes;
    onChange();
  }

  // ── Priorités libres du jour ────────────────────────────────────────────────

  void addTodayItem(String text) {
    final today = DateTime.now();
    final date =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    // Purge les items de jours précédents (garde uniquement aujourd'hui)
    state.todayItems.removeWhere((i) => i.date != date);
    state.todayItems.add(TodayItem(text: text, date: date));
    onChange();
  }

  void toggleTodayItem(String id) {
    final idx = state.todayItems.indexWhere((i) => i.id == id);
    if (idx < 0) return;
    state.todayItems[idx].done = !state.todayItems[idx].done;
    onChange();
  }

  void removeTodayItem(String id) {
    state.todayItems.removeWhere((i) => i.id == id);
    onChange();
  }

  /// Optionnel : proposer automatiquement les habitudes quotidiennes non atteintes
  void suggestAutoFocusForToday({int maxCount = 4}) {
    final candidates = <Activity>[];

    // 1) routines quotidiennes non atteintes en priorité
    for (final a in state.activeActivities.where((x) => x.isHabit)) {
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
      final deficits = state.activeActivities.where((a) => !a.isHabit).map((a) {
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

  DateTime? snoozedUntilOf(String activityId) {
    final s = state.snoozedUntil[activityId];
    if (s == null) return null;
    return DateTime.tryParse(s);
  }

// “Cacher” sans toucher au modèle (date lointaine)
  void hideActivity(String activityId) {
    snoozeActivityUntil(activityId, DateTime(2099, 12, 31));
  }

  bool isActivityHidden(String activityId) {
    final u = snoozedUntilOf(activityId);
    return u != null && u.year >= 2099;
  }

  // ---------- TEMPS (type=time) ----------
  void start(String activityId) {
    // ✅ si l’utilisateur démarre l’activité, on casse le snooze
    clearSnooze(activityId);

    // 1) stop sessions en cours
    for (final s in state.sessions.where((s) => s.endAt == null)) {
      s.endAt = DateTime.now();
    }

    // 2) nouvelle session
    state.sessions
        .add(Session(activityId: activityId, startAt: DateTime.now()));

    onChange();
  }

  List<String> checklistForHabit(String habitId) {
    return List<String>.from(
        state.habitChecklistByHabitId[habitId] ?? const <String>[]);
  }

  void addChecklistItem(String habitId, String label) {
    final list = List<String>.from(
        state.habitChecklistByHabitId[habitId] ?? const <String>[]);
    list.add(label);
    state.habitChecklistByHabitId[habitId] = list;
    onChange();
  }

  void renameChecklistItem(String habitId, int index, String newLabel) {
    final list = List<String>.from(
        state.habitChecklistByHabitId[habitId] ?? const <String>[]);
    if (index < 0 || index >= list.length) return;
    list[index] = newLabel;
    state.habitChecklistByHabitId[habitId] = list;
    onChange();
  }

  void removeChecklistItem(String habitId, int index) {
    final list = List<String>.from(
        state.habitChecklistByHabitId[habitId] ?? const <String>[]);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    state.habitChecklistByHabitId[habitId] = list;
    onChange();
  }

  // AppLogic
  Future<int> scanAllActivities({DateTime? now}) async {
    onChange();
    return 0;
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
    final idx = state.activeActivities.indexWhere((a) => a.id == activityId);
    if (idx < 0 || !state.activeActivities[idx].isHabit) return;

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

  // ─── Helpers onboarding ───────────────────────────────────────────────────

  Domain createDomain(String name) {
    final d = Domain(name: name);
    state.domains.add(d);
    onChange();
    return d;
  }

  void deleteDomain(Domain domain) {
    // Soft-delete : le doc reste dans Firestore avec deleted:true pour sync multi-device.
    // activeDomains filtre automatiquement les deleted:true.
    final idx = state.domains.indexWhere((d) => d.id == domain.id);
    if (idx >= 0) state.domains[idx].deleted = true;
    for (final a in state.activities) {
      if (a.domainId == domain.id) a.domainId = '';
    }
    onChange();
  }

  Activity createHabit({
    required String domainId,
    required String name,
    required HabitFreq freq,
    int target = 1,
  }) {
    final a = Activity(
      domainId: domainId,
      name: name,
      type: 'habit',
      habitFreq: freq,
      habitTarget: target,
      manualTarget: true,
      autoTune: false,
    );
    state.activities.add(a);
    onChange();
    return a;
  }

  void reorderDailyRoutines(int oldIndex, int newIndex) {
    final habits = state.activeActivities
        .where((a) => a.isHabit && effectiveHabitFreq(a) == HabitFreq.daily)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (newIndex > oldIndex) newIndex--;
    final moved = habits.removeAt(oldIndex);
    habits.insert(newIndex, moved);
    for (int i = 0; i < habits.length; i++) habits[i].order = i;
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
    for (final d in state.activeDomains) {
      int sum = 0;
      for (final a
          in state.activeActivities.where((a) => a.domainId == d.id && a.isHabit)) {
        sum += habitSumForRange(a.id, s, e);
      }
      map[d.id] = sum;
    }
    return map;
  }

  Session? stopActive() {
    final run = state.sessions.where((s) => s.endAt == null).toList();
    if (run.isEmpty) return null;

    final ended = run.last;
    ended.endAt = DateTime.now();
    onChange();

    return ended;
  }

  Future<(Session?, String?, int?)> stopActiveWithAdjustment() async {
    final session = stopActive();
    return (session, null, null);
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
      final act = state.activeActivities.firstWhere(
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
    for (final d in state.activeDomains) {
      map[d.id] = totalForRange(start, end, domainId: d.id);
    }
    return map;
  }

  /// Retourne {domainId: {ymd: minutes}} en un seul pass sur les sessions.
  Map<String, Map<String, int>> timeMinutesPerDomainPerDay(
      DateTime start, DateTime end) {
    final activityDomain = {
      for (final a in state.activeActivities) a.id: a.domainId
    };
    final result = <String, Map<String, int>>{};

    for (final s in state.sessions) {
      final sEnd = s.endAt ?? DateTime.now();
      if (s.startAt.isAfter(end) || sEnd.isBefore(start)) continue;

      final domainId = activityDomain[s.activityId] ?? '';
      if (domainId.isEmpty) continue;

      final clampedStart = s.startAt.isBefore(start) ? start : s.startAt;
      final clampedEnd = sEnd.isAfter(end) ? end : sEnd;
      if (!clampedEnd.isAfter(clampedStart)) continue;

      // Distribue les minutes jour par jour si la session chevauche minuit
      var cursor = DateTime(clampedStart.year, clampedStart.month, clampedStart.day);
      while (!cursor.isAfter(clampedEnd)) {
        final dayEnd = cursor.add(const Duration(days: 1));
        final segStart = cursor.isBefore(clampedStart) ? clampedStart : cursor;
        final segEnd = dayEnd.isAfter(clampedEnd) ? clampedEnd : dayEnd;
        final mins = segEnd.difference(segStart).inMinutes;
        if (mins > 0) {
          final ymd =
              '${cursor.year}${cursor.month.toString().padLeft(2, '0')}${cursor.day.toString().padLeft(2, '0')}';
          (result[domainId] ??= {})[ymd] =
              ((result[domainId]!)[ymd] ?? 0) + mins;
        }
        cursor = dayEnd;
      }
    }
    return result;
  }

  String habitSubText({
    required HabitFreq freq,
    required int dayDone,
    required int dayQuota,
    required int weekDone,
    required int weekTarget,
    required int monthDone,
    required int monthTarget,
    required bool swowTodayText,
  }) {
    switch (freq) {
      case HabitFreq.daily:
        return swowTodayText
            ? "Focus : $dayDone / $dayQuota"
            : "$dayDone / $dayQuota";
      case HabitFreq.weekly:
        return "7 j : $weekDone / $weekTarget";
      case HabitFreq.monthly:
        return "30 j : $monthDone / $monthTarget";
    }
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

  HabitAssocEvent? incHabitWithAssocEvent(
      String activityId, int delta, DateTime day) {
    final key = yyyymmdd(day);

    // --- MAJ compteur (par jour) ---
    final prevIdx = state.habitProgress.indexWhere(
      (h) => h.activityId == activityId && h.yyyymmdd == key,
    );

    if (prevIdx < 0) {
      state.habitProgress.add(
        HabitProgress(
          activityId: activityId,
          yyyymmdd: key,
          value: math.max(0, delta),
        ),
      );
    } else {
      final v = state.habitProgress[prevIdx].value + delta;
      state.habitProgress[prevIdx].value = v < 0 ? 0 : v;
    }


    HabitAssocEvent? assocEvent;

    // --- LOG hit + PIN (uniquement sur incrément) ---
    if (delta > 0) {
      final running = runningActivity(); // activité en cours (peut être null)

      // log du contexte (30j)
      state.habitHits.add(HabitHit(
        habitId: activityId,
        ts: DateTime.now(),
        contextActivityId: running?.id,
      ));

      // pin au 1er clic si activité en cours
      if (running != null) {
        final pinned = state.habitPinnedActivity[activityId];

        if (pinned == null) {
          state.habitPinnedActivity[activityId] = running.id;
          assocEvent = HabitAssocEvent.pinned(activityId, running.id);
        } else if (pinned != running.id) {
          // on ne change pas automatiquement : on demande confirmation via UI
          assocEvent =
              HabitAssocEvent.changeSuggested(activityId, pinned, running.id);
        }
      }
    }

    onChange();
    return assocEvent;
  }

  String checklistPeriodKey(String habitId, DateTime day) {
    final act = state.activeActivities.firstWhere((a) => a.id == habitId);
    final d = DateTime(day.year, day.month, day.day);

    final freq = effectiveHabitFreq(act);
    switch (freq) {
      case HabitFreq.daily:
        return yyyymmdd(d);

      case HabitFreq.weekly:
        final monday =
            d.subtract(Duration(days: (d.weekday - DateTime.monday)));
        return 'W:${yyyymmdd(monday)}';

      case HabitFreq.monthly:
        final mm = d.month.toString().padLeft(2, '0');
        return 'M:${d.year}-$mm';
    }
  }

  Set<int> checklistDoneSet(String habitId, DateTime day) {
    final key = checklistPeriodKey(habitId, day);
    final list = state.habitChecklistDone[habitId]?[key] ?? const <int>[];
    return list.toSet();
  }

  void toggleChecklistItem(String habitId, DateTime day, int index) {
    final key = checklistPeriodKey(habitId, day);

    final byPeriod = state.habitChecklistDone.putIfAbsent(
      habitId,
      () => <String, List<int>>{},
    );

    final cur = (byPeriod[key] ?? <int>[]).toSet();
    if (cur.contains(index)) {
      cur.remove(index);
    } else {
      cur.add(index);
    }

    byPeriod[key] = cur.toList()..sort();
    onChange();
  }

  void removeChecklistItemAndFixDone(
      String habitId, DateTime day, int removeIndex) {
    // 1) supprime le texte (template)
    removeChecklistItem(habitId, removeIndex);

    // 2) fixe les coches (progress)
    final key = checklistPeriodKey(habitId, day);
    final byPeriod = state.habitChecklistDone[habitId];
    if (byPeriod == null) {
      onChange();
      return;
    }

    final cur = (byPeriod[key] ?? <int>[]).toSet();

    final next = <int>{};
    for (final i in cur) {
      if (i == removeIndex) continue; // coche supprimée
      if (i > removeIndex)
        next.add(i - 1); // shift
      else
        next.add(i);
    }

    byPeriod[key] = next.toList()..sort();
    onChange();
  }

  void clearChecklistForPeriod(String habitId, DateTime day) {
    final key = checklistPeriodKey(habitId, day);
    final byPeriod = state.habitChecklistDone[habitId];
    if (byPeriod == null) return;
    byPeriod.remove(key);
    onChange();
  }

  void incHabit(String activityId, int delta, DateTime day) {
    final key = yyyymmdd(day);

    // --- valeur AVANT modif (pour détecter création / seuils)
    final prevIdx = state.habitProgress.indexWhere(
      (h) => h.activityId == activityId && h.yyyymmdd == key,
    );

    // --- MAJ compteur ---
    if (prevIdx < 0) {
      state.habitProgress.add(
        HabitProgress(
          activityId: activityId,
          yyyymmdd: key,
          value: math.max(0, delta), // pas de négatif à la création
        ),
      );
    } else {
      final v = state.habitProgress[prevIdx].value + delta;
      state.habitProgress[prevIdx].value = v < 0 ? 0 : v;
    }

    // --- après MAJ compteur ---

    if (delta > 0) {
      final running = runningActivity();
      state.habitHits.add(HabitHit(
        habitId: activityId,
        ts: DateTime.now(),
        contextActivityId: running?.id,
      ));
    }

    onChange();
  }

  Map<String, int> habitActivityCounts30d(String habitId, DateTime now) {
    final start = now.subtract(const Duration(days: 30));
    final counts = <String, int>{};

    for (final h in state.habitHits) {
      if (h.habitId != habitId) continue;
      if (h.ts.isBefore(start)) continue;
      final actId = h.contextActivityId;
      if (actId == null) continue;
      counts[actId] = (counts[actId] ?? 0) + 1;
    }
    return counts;
  }

  bool activityUnderGoal(Activity a, DateTime day) {
    final base = a.goalMin;
    if (base <= 0) return false;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final doneMin = totalForRangeByActivity(a.id, start, end).inMinutes;
    return doneMin < base;
  }

  String? suggestedActivityForHabit({
    required String habitId,
    required DateTime now,
  }) {
    final counts = habitActivityCounts30d(habitId, now);
    if (counts.isEmpty) return null;

    String? bestId;
    var best = 0;
    var total = 0;

    counts.forEach((id, c) {
      total += c;
      if (c > best) {
        best = c;
        bestId = id;
      }
    });

    // ✅ seuil de confiance (évite 1 seul test qui “colle” une activité)
    final strongEnough = best >= 2 || (total > 0 && (best / total) >= 0.5);
    if (!strongEnough) return null;

    return bestId;
  }

  // ---------- Cibles dérivées (habits) ----------
  HabitFreq effectiveHabitFreq(Activity a) {
    if (!a.isHabit) return HabitFreq.monthly;

    // ✅ manuel = vérité
    if (a.manualTarget == true) {
      return a.habitFreq ?? HabitFreq.monthly;
    }

    // auto = ce que tu as calculé
    return a.habitFreq ?? HabitFreq.monthly;
  }

  int effectiveHabitTarget(Activity a) {
    if (!a.isHabit) return 0;

    // ✅ manuel = vérité
    if (a.manualTarget == true) {
      return (a.habitTarget ?? 1).clamp(1, 999999);
    }

    // auto = ce que tu as calculé
    return (a.habitTarget ?? 1).clamp(1, 999999);
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

  // ---------- Domaines ----------
  List<Activity> activitiesOfDomain(String domainId) =>
      state.activeActivities.where((a) => a.domainId == domainId).toList();

  int domainGoalMinDay(String domainId) {
    final d = state.activeDomains.firstWhere((x) => x.id == domainId);
    if (!d.autoGoal) return d.goalMinDay ?? 0;
    return state.activeActivities
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

  // ---------- Tri/filtre “sous cap” ----------
  List<Activity> listUnderCapSorted({
    String? domainId,
    required bool habits,
    bool onlyUnderCap = false,
    bool dailyStrict = false,
  }) {
    Iterable<Activity> src = state.activeActivities.where((a) => a.isHabit == habits);
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

    final a = state.activeActivities.firstWhere(
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

    for (final a in state.activeActivities.where((x) => !x.isHabit)) {
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
    final a = state.activeActivities.firstWhere((x) => x.id == activityId);
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

    final a = state.activeActivities.firstWhere((x) => x.id == activityId);

    // Cible proportionnelle à la fenêtre demandée
    final int target;
    final t2 = effectiveHabitTarget(a);
    switch (effectiveHabitFreq(a)) {
      case HabitFreq.daily:
        target = t2 * days;
      case HabitFreq.weekly:
        target = (t2 * days / 7.0).round().clamp(1, 999999);
      case HabitFreq.monthly:
        target = (t2 * days / 30.0).round().clamp(1, 999999);
    }

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

      final acts = state.activeActivities.where(
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
        ? state.activeActivities.where((a) => a.isHabit)
        : state.activeActivities.where((a) => a.isHabit && a.domainId == domainId);
    int t = 0;
    for (final a in acts) {
      t += dayQuotaFor(a); // ✅ plus de dailyTarget
    }
    return t;
  }

  // ---------- Aujourd’hui / Demain ----------

// app_logic.dart
  void applyHabitSettings(
    Activity act, {
    required HabitFreq freq,
    required int target,
    required bool isAuto,
  }) {
    final safeTarget = target < 1 ? 1 : target;

    act.habitFreq = freq;

    if (isAuto) {
      act.manualTarget = false;
      act.autoTune = true;
    } else {
      act.autoTune = false;
      act.manualTarget = true;
      act.habitTarget = safeTarget;
    }

    onChange();
  }


  String habitFreqLabel(HabitFreq f) {
    switch (f) {
      case HabitFreq.daily:
        return "Quotidienne";
      case HabitFreq.weekly:
        return "Hebdomadaire";
      case HabitFreq.monthly:
        return "Mensuelle";
    }
  }

  Map<String, String?> routineToActivityId(List<HabitAssocEvent> events) {
    final pinned = <String, String>{};
    final suggested = <String, String>{};

    for (final e in events) {
      if (e.type == HabitAssocEventType.pinned && e.toActivityId != null) {
        pinned[e.habitId] = e.toActivityId!;
      } else if (e.type == HabitAssocEventType.changeSuggested &&
          e.toActivityId != null) {
        suggested[e.habitId] = e.toActivityId!;
      }
    }

    final out = <String, String?>{};
    for (final id in {...pinned.keys, ...suggested.keys}) {
      out[id] = pinned[id] ?? suggested[id];
    }
    return out;
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

  /// Routine quotidienne avec la pire tendance sur 7j, non encore atteinte aujourd'hui.
  /// Retourne null si toutes sont à jour, si le défi a été passé aujourd'hui,
  /// ou s'il n'y a aucune routine quotidienne.
  Activity? dailyChallengeHabit(String todayYmd) {
    if (state.skippedChallengeDates.contains(todayYmd)) return null;

    final todayDate = DateTime(
      int.parse(todayYmd.substring(0, 4)),
      int.parse(todayYmd.substring(4, 6)),
      int.parse(todayYmd.substring(6, 8)),
    );
    final sevenDaysAgo = todayDate.subtract(const Duration(days: 7));

    Activity? worst;
    double worstRatio = double.infinity;

    for (final act in state.activeActivities.where((a) => a.isHabit)) {
      if (effectiveHabitFreq(act) != HabitFreq.daily) continue;
      final quota = dayQuotaFor(act);
      if (quota <= 0) continue;
      if (habitValueOn(act.id, todayDate) >= quota) continue; // déjà fait

      final done7 = habitSumForRange(act.id, sevenDaysAgo, todayDate);
      final ratio = done7 / (quota * 7);
      if (ratio < worstRatio) {
        worstRatio = ratio;
        worst = act;
      }
    }

    return worst;
  }

  void skipChallengeForToday(String todayYmd) {
    if (!state.skippedChallengeDates.contains(todayYmd)) {
      state.skippedChallengeDates.add(todayYmd);
      onChange();
    }
  }

  /// Routines quotidiennes avec streak ≥ 3 non encore validées aujourd'hui.
  List<String> streakAtRiskNames() {
    return state.activeActivities
        .where((a) =>
            a.isHabit &&
            effectiveHabitFreq(a) == HabitFreq.daily &&
            habitCurrentStreak(a.id) >= 3 &&
            !habitReached(a))
        .map((a) => a.name)
        .toList();
  }

  void unskipChallengeForToday(String todayYmd) {
    if (state.skippedChallengeDates.remove(todayYmd)) onChange();
  }

  // ───────── « Challenge me » (défi ORION sur une activité temps) ─────────

  /// Activité « temps » la plus en retard sur sa cible du jour (goalMin).
  /// C'est le levier d'action : « fais ça maintenant ». Null si tout est à jour.
  Activity? challengeActivity({Set<String> exclude = const {}}) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    Activity? worst;
    double worstRemaining = 0;
    for (final a in state.activeActivities) {
      if (a.isHabit || a.role == ActivityRole.shopping) continue;
      if (exclude.contains(a.id)) continue; // défi déjà programmé sur cette activité
      final target = a.goalMin;
      if (target <= 0) continue;
      final doneMin = totalForRangeByActivity(a.id, todayStart, now).inMinutes;
      if (doneMin >= target) continue; // déjà atteinte aujourd'hui
      final remaining = (target - doneMin) / target; // 1.0 = rien fait
      if (remaining > worstRemaining) {
        worstRemaining = remaining;
        worst = a;
      }
    }
    return worst;
  }

  /// Durée suggérée du défi en minutes : le reste vers la cible (ou le minuteur
  /// préféré), borné à [10, 45] et arrondi à 5.
  int challengeDurationFor(Activity a) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final doneMin = totalForRangeByActivity(a.id, todayStart, now).inMinutes;
    final base = a.timerMin ?? (a.goalMin - doneMin);
    final clamped = base.clamp(10, 45);
    return (clamped / 5).round() * 5;
  }

  /// Enregistre un défi relevé : compteur total + streak de jours consécutifs.
  void recordChallengeAccepted(String todayYmd) {
    final last = state.lastChallengeYmd;
    if (last != todayYmd) {
      final d = DateTime(
        int.parse(todayYmd.substring(0, 4)),
        int.parse(todayYmd.substring(4, 6)),
        int.parse(todayYmd.substring(6, 8)),
      );
      final y = d.subtract(const Duration(days: 1));
      final yYmd =
          '${y.year}${y.month.toString().padLeft(2, '0')}${y.day.toString().padLeft(2, '0')}';
      state.challengeStreak = (last == yYmd) ? state.challengeStreak + 1 : 1;
      state.lastChallengeYmd = todayYmd;
    }
    state.challengesDone += 1;
    state.challengeWinsByDay[todayYmd] =
        (state.challengeWinsByDay[todayYmd] ?? 0) + 1;
    onChange();
  }

  // ─── Niveau global ────────────────────────────────────────────────────────

  // Niveaux 1-15 (Débutant→Mythique). Les 10 premiers seuils sont historiques
  // (inchangés pour ne rétrograder personne) ; les 5 suivants étendent la courbe
  // afin qu'on n'atteigne plus le « bout » trop vite. Au-delà : prestige Mythique
  // I/II… par crans de `_prestigeStep` (long grind volontaire).
  // Seuils de niveau & pas de prestige : source de vérité partagée dans
  // GoldEconomy (levelThresholds / prestigeStep / thresholdForLevel).
  static const _levelTitles = [
    'Débutant', 'Curieux', 'Régulier', 'Déterminé', 'Discipliné',
    'Expert', 'Champion', 'Maître', 'Légende', 'Élite',
    'Virtuose', 'Maître d\'œuvre', 'Sage', 'Titan', 'Mythique',
  ];

  int _xpForBadge(BadgeId id) {
    switch (id) {
      case BadgeId.streak3:      return 10;
      case BadgeId.streak7:      return 25;
      case BadgeId.streak21:     return 75;
      case BadgeId.streak66:     return 200;
      case BadgeId.streak100:    return 500;
      case BadgeId.scoreFirst100:return 30;
      case BadgeId.score7dAt80:  return 50;
      case BadgeId.score30dAt80: return 150;
      case BadgeId.actions10:    return 15;
      case BadgeId.actions50:    return 50;
      case BadgeId.actions100:   return 100;
      case BadgeId.actions200:   return 150;
      case BadgeId.actions300:   return 200;
      case BadgeId.actions500:   return 300;
      case BadgeId.actions750:   return 400;
      case BadgeId.actions1000:  return 500;
      case BadgeId.actions1500:  return 650;
      case BadgeId.actions2000:  return 800;
      case BadgeId.actions3000:  return 1000;
      case BadgeId.actions5000:  return 1500;
      case BadgeId.actions7500:  return 2000;
      case BadgeId.actions10000: return 3000;
    }
  }

  /// XP « action » cumulatif (en plus de l'XP de badges) :
  /// temps 1/h · routine complétée 2 · défi 5 · action Gantt 1.
  int actionXp() {
    int totalMin = 0;
    for (final s in state.sessions) {
      final end = s.endAt ?? DateTime.now();
      totalMin += end.difference(s.startAt).inMinutes;
    }
    final hours = totalMin ~/ 60;

    final byId = {for (final a in state.activities) a.id: a};
    int routineCompletions = 0;
    for (final hp in state.habitProgress) {
      final a = byId[hp.activityId];
      if (a == null || !a.isHabit) continue;
      final tgt = activeHabitTarget(a);
      if (tgt > 0 && hp.value >= tgt) routineCompletions++;
    }

    final ganttTotal =
        state.ganttActionsByDay.values.fold(0, (a, b) => a + b);
    return hours +
        routineCompletions * 2 +
        state.challengesDone * 5 +
        ganttTotal;
  }

  /// XP gagné un jour donné (pour « XP du jour » + courbe 7 jours).
  /// temps 1/h · routine complétée 2 · défi 5 · action Gantt 1.
  int xpForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final ymd =
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final hours = totalForDay(d).inMinutes ~/ 60;

    final byId = {for (final a in state.activities) a.id: a};
    int routines = 0;
    for (final hp in state.habitProgress) {
      if (hp.yyyymmdd != ymd) continue;
      final a = byId[hp.activityId];
      if (a == null || !a.isHabit) continue;
      final tgt = activeHabitTarget(a);
      if (tgt > 0 && hp.value >= tgt) routines++;
    }
    final challenges = state.challengeWinsByDay[ymd] ?? 0;
    final gantt = state.ganttActionsByDay[ymd] ?? 0;
    return hours + routines * 2 + challenges * 5 + gantt;
  }

  static String _roman(int n) {
    const numerals = [
      [10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I'],
    ];
    var v = n;
    final sb = StringBuffer();
    for (final pair in numerals) {
      final value = pair[0] as int;
      final sym = pair[1] as String;
      while (v >= value) {
        sb.write(sym);
        v -= value;
      }
    }
    return sb.toString();
  }

  /// XP total (badges + actions), niveau + titre, bornes du palier courant.
  /// Niveaux 1-10 (Débutant→Élite) ; au-delà de 7000 : prestige Élite I/II/…
  /// par crans de 2000 XP (toujours un palier suivant).
  /// XP « historique » dérivé (ancien système, badges + actions cumulées).
  /// Sert uniquement à initialiser l'or à la migration (voir `seedGoldIfNeeded`).
  int legacyDerivedXp() {
    final badgeXp = state.earnedBadges.fold(0, (sum, b) => sum + _xpForBadge(b.id));
    return badgeXp + actionXp();
  }

  /// Seuil d'XP (or à vie) requis pour atteindre [level]. Gère le prestige.
  int _thresholdForLevel(int level) => GoldEconomy.thresholdForLevel(level);

  /// Titre d'un niveau (prestige Mythique I/II… au-delà du dernier palier nommé).
  String _titleForLevel(int level) {
    if (level <= 1) return _levelTitles.first;
    if (level <= GoldEconomy.levelThresholds.length) return _levelTitles[level - 1];
    return '${_levelTitles.last} ${_roman(level - GoldEconomy.levelThresholds.length)}';
  }

  int _levelFromXp(int xp) {
    const thresholds = GoldEconomy.levelThresholds;
    if (xp >= thresholds.last) {
      final prestige = (xp - thresholds.last) ~/ GoldEconomy.prestigeStep;
      return thresholds.length + prestige;
    }
    int level = 1;
    for (int i = thresholds.length - 1; i >= 0; i--) {
      if (xp >= thresholds[i]) {
        level = i + 1;
        break;
      }
    }
    return level;
  }

  /// Niveau ATTEINT par l'or à vie matérialisé (jours clos). Sert au grant du
  /// rang (`unlockedLevel`) à la migration/backfill — PAS le provisoire du jour.
  int earnedLevelFromXp() => _levelFromXp(state.goldLifetime);

  /// Idem mais EN INCLUANT les gains provisoires du jour (affichage live :
  /// éligibilité à révéler un niveau dès que la journée pousse au-dessus du seuil).
  int earnedLevelFromXpLive() =>
      _levelFromXp(state.goldLifetime + provisionalGoldToday());

  /// Niveau EFFECTIF = le plus haut niveau révélé (payé). Gate séquentiel :
  /// l'XP rend éligible, mais c'est `unlockedLevel` qui fait foi pour le rang,
  /// les titres et l'accès boutique.
  int effectiveLevel() => state.unlockedLevel < 1 ? 1 : state.unlockedLevel;

  ({int xp, int level, String title, int xpCurrent, int xpNext}) userLevelData() {
    // Live : on inclut les gains provisoires du jour pour que le total et la
    // barre de progression bougent en direct (matérialisés le lendemain). On
    // PLAFONNE au seuil du prochain niveau : une fois le palier atteint l'XP
    // affiche « plein → à révéler » et le surplus part visiblement en or (pas
    // d'overshoot type 262/30, y compris si du XP a été injecté en dev).
    final level = effectiveLevel();
    final next = _thresholdForLevel(level + 1);
    final raw = state.goldLifetime + provisionalGoldToday();
    final xp = raw > next ? next : raw;
    return (
      xp: xp,
      level: level,
      title: _titleForLevel(level),
      xpCurrent: _thresholdForLevel(level),
      xpNext: next,
    );
  }

  /// État de la révélation du prochain niveau (titre masqué tant que non payé).
  /// `pending` = l'XP suffit pour révéler le niveau suivant.
  ({bool pending, int nextLevel, int cost, bool affordable}) levelRevealInfo() {
    final eff = effectiveLevel();
    final next = eff + 1;
    final pending = earnedLevelFromXpLive() >= next;
    final cost = GoldEconomy.revealCost(next);
    return (
      pending: pending,
      nextLevel: next,
      cost: cost,
      affordable: state.gold >= cost,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────

  // Score journalier pour un jour passé (daily habits uniquement).
  /// Score moyen sur une semaine (lundi → until, excluant les jours vides).
  double _weekScore(DateTime monday, {DateTime? until, ScoreCtx? ctx}) {
    final c = ctx ?? _scoreContext();
    final end = until ?? DateTime.now();
    final endDay = DateTime(end.year, end.month, end.day);
    double sum = 0;
    int count = 0;
    for (int i = 0; i < 7; i++) {
      final d = monday.add(Duration(days: i));
      if (d.isAfter(endDay)) break;
      final hasRoutines = state.activeActivities.any((a) =>
          a.isHabit &&
          effectiveHabitFreq(a) == HabitFreq.daily &&
          dayQuotaFor(a) > 0);
      if (!hasRoutines) continue;
      sum += _dailyScoreFor(d, c);
      count++;
    }
    return count == 0 ? 0.0 : sum / count;
  }

  /// Score semaine courante, semaine précédente, et scores journaliers lun-dim.
  /// Les jours futurs ont la valeur -1 dans days7.
  ({double current, double previous, List<double> days7}) weeklyScoreData() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final prevMonday = monday.subtract(const Duration(days: 7));

    final ctx = _scoreContext();
    final current = _weekScore(monday, ctx: ctx);
    final previous = _weekScore(prevMonday,
        until: prevMonday.add(const Duration(days: 6)), ctx: ctx);

    final days7 = List.generate(7, (i) {
      final d = monday.add(Duration(days: i));
      if (d.isAfter(today)) return -1.0;
      return _dailyScoreFor(d, ctx);
    });

    return (current: current, previous: previous, days7: days7);
  }

  /// Score moyen par jour de la semaine sur les N dernières semaines.
  /// Index 0 = lundi, 6 = dimanche. -1 si pas de données.
  List<double> weekdayAverageScores({int weeks = 12}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final byWeekday = List.generate(7, (_) => <double>[]);
    final ctx = _scoreContext(days: weeks * 7);

    for (int i = 0; i < weeks * 7; i++) {
      final d = today.subtract(Duration(days: i));
      if (d.isAfter(today)) continue;
      final hasRoutines = state.activeActivities.any(
          (a) => a.isHabit && effectiveHabitFreq(a) == HabitFreq.daily);
      if (!hasRoutines) continue;
      byWeekday[d.weekday - 1].add(_dailyScoreFor(d, ctx));
    }

    return byWeekday.map((scores) {
      if (scores.isEmpty) return -1.0;
      return scores.reduce((a, b) => a + b) / scores.length;
    }).toList();
  }

  /// Contexte de calcul du score de productivité sur une fenêtre : références
  /// "pleine journée" (p90 du standard propre de l'user) + minutes totales/jour
  /// + dimensions actives. Calculé UNE fois par lot de scores (heatmap = 84 j).
  ScoreCtx _scoreContext({int days = 84}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: days - 1));
    final end = today.add(const Duration(days: 1));

    // Temps total loggué par jour (somme de tous les domaines).
    final perDomain = timeMinutesPerDomainPerDay(start, end);
    final totalMin = <String, int>{};
    for (final dayMap in perDomain.values) {
      dayMap.forEach((ymd, m) => totalMin[ymd] = (totalMin[ymd] ?? 0) + m);
    }
    // Référence temps = p90 des jours actifs, planchée à 60 min (évite qu'une
    // seule courte journée ne rende la barre dérisoire).
    final timeRef =
        percentileOf(totalMin.values.toList(), 0.90).clamp(60.0, double.infinity);

    // Référence Gantt = p90 des actions cochées/jour dans la fenêtre, plancher 1.
    final startYmd = yyyymmdd(start);
    final ganttVals = <int>[];
    _ganttDonePerDay.forEach((ymd, c) {
      if (ymd.compareTo(startYmd) >= 0) ganttVals.add(c);
    });
    final ganttRef =
        percentileOf(ganttVals, 0.90).clamp(1.0, double.infinity);

    // Une dimension n'entre dans le score que si l'user la pratique sur la
    // fenêtre (sinon ne pas la pénaliser : un user sans projets ne plafonne pas).
    return (
      timeRef: timeRef,
      ganttRef: ganttRef,
      totalMinByDay: totalMin,
      timeActive: totalMin.isNotEmpty,
      ganttActive: ganttVals.isNotEmpty,
    );
  }

  /// Scores journaliers des N derniers jours pour la heatmap.
  List<({String ymd, double score, bool hasData})> recentDailyScores(
      {int days = 84}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final ctx = _scoreContext(days: days);
    final hasRoutines = state.activeActivities
        .any((a) => a.isHabit && effectiveHabitFreq(a) == HabitFreq.daily);
    // Du contenu existe si l'user a des routines OU du temps loggué OU des
    // actions Gantt cochées — sinon la heatmap reste grise.
    final hasTracking = hasRoutines ||
        ctx.totalMinByDay.isNotEmpty ||
        _ganttDonePerDay.isNotEmpty;

    return List.generate(days, (i) {
      final d = today.subtract(Duration(days: days - 1 - i));
      final ymd = yyyymmdd(d);
      final isFuture = d.isAfter(today);
      return (
        ymd: ymd,
        score: isFuture ? 0.0 : _dailyScoreFor(d, ctx),
        hasData: hasTracking && !isFuture,
      );
    });
  }

  double dailyScore(String ymd) {
    final parts = [
      int.parse(ymd.substring(0, 4)),
      int.parse(ymd.substring(4, 6)),
      int.parse(ymd.substring(6, 8)),
    ];
    return _dailyScoreFor(DateTime(parts[0], parts[1], parts[2]), _scoreContext());
  }

  /// Plancher par dimension dans la moyenne géométrique : une dimension à zéro
  /// tire le score vers le bas sans tout annuler.
  static const double _scoreFloor = 0.20;

  /// Score de productivité du jour = moyenne GÉOMÉTRIQUE des dimensions actives
  /// (routines / temps / projets), chacune normalisée sur le standard propre de
  /// l'utilisateur (p90) puis planchée à [_scoreFloor]. La géométrique valorise
  /// l'équilibre : être bon partout bat cartonner sur une seule dimension, et
  /// négliger une dimension coûte plus qu'avec une moyenne simple.
  double _dailyScoreFor(DateTime day, ScoreCtx ctx) {
    final d = DateTime(day.year, day.month, day.day);
    final ymd = yyyymmdd(d);

    int routinesDone = 0, routinesTotal = 0;
    for (final act in state.activeActivities.where((a) => a.isHabit)) {
      if (effectiveHabitFreq(act) != HabitFreq.daily) continue;
      final quota = dayQuotaFor(act);
      if (quota <= 0) continue;
      routinesTotal++;
      if (habitValueOn(act.id, d) >= quota) routinesDone++;
    }

    double cap1(double v) => v > 1.0 ? 1.0 : v;
    final scores = <double>[];
    if (routinesTotal > 0) scores.add(cap1(routinesDone / routinesTotal));
    if (ctx.timeActive) scores.add(cap1((ctx.totalMinByDay[ymd] ?? 0) / ctx.timeRef));
    if (ctx.ganttActive) scores.add(cap1((_ganttDonePerDay[ymd] ?? 0) / ctx.ganttRef));

    if (scores.isEmpty) return 0.0;
    if (scores.length == 1) return scores.first; // une seule dimension : pas de plancher
    final product = scores.fold<double>(
        1.0, (p, s) => p * (s < _scoreFloor ? _scoreFloor : s));
    return math.pow(product, 1.0 / scores.length).toDouble();
  }

  String _fmtHmShort(int mins) {
    if (mins < 60) return '${mins}min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  /// Sous-scores de productivité d'AUJOURD'HUI par dimension active, pour la
  /// triade visuelle. La dimension active la plus basse porte isFocus = true
  /// (le levier qui fera le plus monter le score géométrique du jour).
  List<DimScore> todayDimensionScores() {
    final ctx = _scoreContext();
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    final ymd = yyyymmdd(d);

    final raw = <({String key, String label, double score, String detail})>[];

    int rDone = 0, rTotal = 0;
    for (final act in state.activeActivities.where((a) => a.isHabit)) {
      if (effectiveHabitFreq(act) != HabitFreq.daily) continue;
      final quota = dayQuotaFor(act);
      if (quota <= 0) continue;
      rTotal++;
      if (habitValueOn(act.id, d) >= quota) rDone++;
    }
    if (rTotal > 0) {
      raw.add((
        key: 'routines',
        label: 'Routines',
        score: (rDone / rTotal).clamp(0.0, 1.0),
        detail: '$rDone/$rTotal',
      ));
    }
    if (ctx.timeActive) {
      final mins = ctx.totalMinByDay[ymd] ?? 0;
      raw.add((
        key: 'time',
        label: 'Temps',
        score: (mins / ctx.timeRef).clamp(0.0, 1.0),
        detail: _fmtHmShort(mins),
      ));
    }
    if (ctx.ganttActive) {
      final n = _ganttDonePerDay[ymd] ?? 0;
      raw.add((
        key: 'gantt',
        label: 'Projets',
        score: (n / ctx.ganttRef).clamp(0.0, 1.0),
        detail: '$n action${n > 1 ? 's' : ''}',
      ));
    }

    if (raw.isEmpty) return const [];
    var minScore = 2.0;
    for (final r in raw) {
      if (r.score < minScore) minScore = r.score;
    }
    final result = <DimScore>[];
    var focusUsed = false;
    for (final r in raw) {
      final isFocus = !focusUsed && raw.length > 1 && r.score == minScore;
      if (isFocus) focusUsed = true;
      result.add((
        key: r.key,
        label: r.label,
        score: r.score,
        detail: r.detail,
        isFocus: isFocus,
      ));
    }
    return result;
  }

  /// Seuil sous lequel une dimension "décroche" → ORION en parle dans son brief.
  static const double _leverThreshold = 0.60;

  /// Snapshot sérialisable de la productivité d'aujourd'hui, écrit dans Firestore
  /// pour qu'ORION (Cloud Function) coache le « levier du jour ». Le levier n'est
  /// renseigné QUE si la dimension la plus faible décroche (< [_leverThreshold]).
  Map<String, dynamic> productivitySnapshot() {
    final now = DateTime.now();
    final ymd = yyyymmdd(DateTime(now.year, now.month, now.day));
    final dims = todayDimensionScores();

    Map<String, dynamic>? lever;
    for (final d in dims) {
      if (d.isFocus && d.score < _leverThreshold) {
        lever = {
          'key': d.key,
          'label': d.label,
          'detail': d.detail,
          'score': d.score,
        };
      }
    }

    return {
      'date': ymd,
      'score': dailyScore(ymd),
      'dimensions': [
        for (final d in dims)
          {
            'key': d.key,
            'label': d.label,
            'score': d.score,
            'detail': d.detail,
            'isFocus': d.isFocus,
          }
      ],
      'lever': lever,
    };
  }

  /// Vérifie tous les paliers et ajoute les badges manquants dans `state.earnedBadges`.
  /// Retourne la liste des badges nouvellement débloqués.
  /// [ganttDoneCount] = nombre total de tâches Gantt validées (passé depuis main).
  List<EarnedBadge> checkAndAwardBadges({int ganttDoneCount = 0}) {
    final today = yyyymmdd(DateTime.now());
    final now = DateTime.now();
    final newBadges = <EarnedBadge>[];

    void award(BadgeId id, {String? habitId}) {
      if (state.earnedBadges
          .any((b) => b.id == id && b.habitId == habitId)) return;
      final badge = EarnedBadge(id: id, habitId: habitId, earnedAt: today);
      state.earnedBadges.add(badge);
      newBadges.add(badge);
    }

    // --- Streaks par routine quotidienne ---
    for (final act in state.activeActivities.where((a) => a.isHabit)) {
      if (effectiveHabitFreq(act) != HabitFreq.daily) continue;
      final streak = habitCurrentStreak(act.id);
      if (streak >= 3) award(BadgeId.streak3, habitId: act.id);
      if (streak >= 7) award(BadgeId.streak7, habitId: act.id);
      if (streak >= 21) award(BadgeId.streak21, habitId: act.id);
      if (streak >= 66) award(BadgeId.streak66, habitId: act.id);
      if (streak >= 100) award(BadgeId.streak100, habitId: act.id);
    }

    // --- Tâches Gantt validées (historique total) ---
    if (ganttDoneCount >= 10)    award(BadgeId.actions10);
    if (ganttDoneCount >= 50)    award(BadgeId.actions50);
    if (ganttDoneCount >= 100)   award(BadgeId.actions100);
    if (ganttDoneCount >= 200)   award(BadgeId.actions200);
    if (ganttDoneCount >= 300)   award(BadgeId.actions300);
    if (ganttDoneCount >= 500)   award(BadgeId.actions500);
    if (ganttDoneCount >= 750)   award(BadgeId.actions750);
    if (ganttDoneCount >= 1000)  award(BadgeId.actions1000);
    if (ganttDoneCount >= 1500)  award(BadgeId.actions1500);
    if (ganttDoneCount >= 2000)  award(BadgeId.actions2000);
    if (ganttDoneCount >= 3000)  award(BadgeId.actions3000);
    if (ganttDoneCount >= 5000)  award(BadgeId.actions5000);
    if (ganttDoneCount >= 7500)  award(BadgeId.actions7500);
    if (ganttDoneCount >= 10000) award(BadgeId.actions10000);

    // --- Score journalier (basé sur les routines uniquement) ---
    final routineSummary = routineProgressSummaryForCurrentPeriod();
    final scoreDone = routineSummary.reached;
    final scoreTotal = routineSummary.total;

    if (scoreTotal > 0 && scoreDone >= scoreTotal) {
      award(BadgeId.scoreFirst100);

      // Vérifie N jours consécutifs passés à 80%+
      final scoreCtx = _scoreContext();
      bool consecutiveDaysAt80(int days) {
        final base = DateTime(now.year, now.month, now.day);
        for (int i = 1; i <= days; i++) {
          if (_dailyScoreFor(base.subtract(Duration(days: i)), scoreCtx) <
              0.80) {
            return false;
          }
        }
        return true;
      }

      if (consecutiveDaysAt80(7)) award(BadgeId.score7dAt80);
      if (consecutiveDaysAt80(30)) award(BadgeId.score30dAt80);
    }

    return newBadges;
  }

  /// Nombre de jours consécutifs où le quota est atteint (en partant d'aujourd'hui ou d'hier).
  /// Retourne 0 pour les routines hebdo/mensuelles.
  /// Longueur de série se terminant le jour [anchor] (inclus s'il est fait/gelé).
  /// Sert au gain d'or croissant avec la série (cohérent avec habitCurrentStreak).
  int habitStreakEndingOn(String habitId, DateTime anchor) {
    final act = state.activeActivities.firstWhereOrNull((a) => a.id == habitId);
    if (act == null || effectiveHabitFreq(act) != HabitFreq.daily) return 0;
    final quota = dayQuotaFor(act);
    if (quota <= 0) return 0;
    DateTime d = DateTime(anchor.year, anchor.month, anchor.day);
    int streak = 0;
    while (streak < 3650) {
      final ymd = yyyymmdd(d);
      if (habitValueOn(habitId, d) >= quota) {
        streak++;
        d = d.subtract(const Duration(days: 1));
      } else if (state.goldGelDays.contains('${habitId}_$ymd')) {
        d = d.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  int habitCurrentStreak(String habitId) {
    final act = state.activeActivities.firstWhereOrNull((a) => a.id == habitId);
    if (act == null || effectiveHabitFreq(act) != HabitFreq.daily) return 0;

    final quota = dayQuotaFor(act);
    if (quota <= 0) return 0;

    final now = DateTime.now();
    DateTime d = DateTime(now.year, now.month, now.day);

    if (habitValueOn(habitId, d) < quota) {
      d = d.subtract(const Duration(days: 1));
    }

    int streak = 0;
    while (streak < 3650) {
      if (habitValueOn(habitId, d) >= quota) {
        streak++;
        d = d.subtract(const Duration(days: 1));
      } else if (state.goldGelDays.contains('${habitId}_${yyyymmdd(d)}')) {
        // Jour gelé (Gel de série acheté) : on enjambe sans casser la chaîne
        // — ni incrément, ni rupture, comme un vrai jour de repos.
        d = d.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// Meilleur streak jamais atteint (jours consécutifs avec quota atteint).
  /// Retourne 0 pour les routines hebdo/mensuelles.
  int habitBestStreak(String habitId) {
    final act = state.activeActivities.firstWhereOrNull((a) => a.id == habitId);
    if (act == null || effectiveHabitFreq(act) != HabitFreq.daily) return 0;

    final quota = dayQuotaFor(act);
    if (quota <= 0) return 0;

    final ymds = state.habitProgress
        .where((h) => h.activityId == habitId)
        .map((h) => h.yyyymmdd)
        .toSet()
        .toList()
      ..sort();

    if (ymds.isEmpty) return 0;

    int best = 0;
    int current = 0;
    DateTime? prev;

    for (final ymd in ymds) {
      final day = DateTime(
        int.parse(ymd.substring(0, 4)),
        int.parse(ymd.substring(4, 6)),
        int.parse(ymd.substring(6, 8)),
      );
      if (habitValueOn(habitId, day) >= quota) {
        if (prev != null && day.difference(prev).inDays == 1) {
          current++;
        } else {
          current = 1;
        }
        if (current > best) best = current;
      } else {
        current = 0;
      }
      prev = day;
    }

    return best;
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
    return state.activeActivities
        .where((a) => a.isHabit && (domainId == null || a.domainId == domainId))
        .fold<int>(0, (sum, a) {
      final freq = effectiveHabitFreq(a);
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

  /// Taux d'adhérence quotidien sur les N derniers jours (valeur 0.0–1.0 par jour).
  /// Utilisé pour afficher l'évolution en mini-barres dans l'AppBar.
  List<double> habitDailyAdherenceRates(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dailyTarget = sumHabitTarget(null, 1);
    if (dailyTarget <= 0) return List.filled(days, 0.0);

    return List.generate(days, (i) {
      final day = today.subtract(Duration(days: days - 1 - i));
      int done = 0;
      for (final a in state.activeActivities.where((a) => a.isHabit)) {
        done += habitValueOn(a.id, day);
      }
      return (done / dailyTarget).clamp(0.0, 1.0);
    });
  }

  /// Somme des réalisés sur N jours pour un domaine.
  int sumHabitDone(String? domainId, int days) {
    final r = lastNDays(days); // [now - days, now)
    final acts = state.activeActivities.where(
      (a) => a.isHabit && (domainId == null || a.domainId == domainId),
    );

    int done = 0;
    for (final a in acts) {
      done += habitSumForRange(a.id, r.start, r.end);
    }
    return done;
  }
}

class DashboardDomainOrder {
  final Map<String, double> scoreByDomain;
  final Map<String, bool> haloReachedByDomain;
  final List<Domain> sortedDomains;
  final Map<String, int> rankByDomain;

  DashboardDomainOrder({
    required this.scoreByDomain,
    required this.haloReachedByDomain,
    required this.sortedDomains,
    required this.rankByDomain,
  });
}

class SuggestedActivity {
  final Activity activity;
  final int remainingMin;
  final int doneMin;

  SuggestedActivity({
    required this.activity,
    required this.remainingMin,
    required this.doneMin,
  });
}

// =====================================================
// ===================  EXTENSIONS  ====================
// =====================================================

extension TodayLogic on AppLogic {
  Set<String> nowSkippedSet(String ymd) =>
      (state.nowSkippedByYmd[ymd] ?? const <String>[]).toSet();

  Set<String> nowDoneSet(String ymd) =>
      (state.nowDoneByYmd[ymd] ?? const <String>[]).toSet();

  void setNowSkipped(String ymd, Set<String> ids) {
    state.nowSkippedByYmd[ymd] = ids.toList();
    onChange();
  }

  void setNowDone(String ymd, Set<String> ids) {
    state.nowDoneByYmd[ymd] = ids.toList();
    onChange();
  }

  void setSortTodayByDashboard(bool v) {
    state.sortTodayByDashboard = v;
    onChange();
  }

  String? _domainIdOfSession(Session s) {
    final a = state.activeActivities.firstWhere(
      (x) => x.id == s.activityId,
      orElse: () => Activity(domainId: '', name: '', habitTarget: 1),
    );
    return a.domainId.isEmpty ? null : a.domainId;
  }

  Map<String, Duration> timeTotalsByDomain(DateTime start, DateTime end) {
    final totals = <String, Duration>{};

    for (final s in state.sessions) {
      final domainId = _domainIdOfSession(s);
      if (domainId == null) continue;

      final st = s.startAt;
      final en = s.endAt ?? DateTime.now();

      // pas d'intersection
      if (en.isBefore(start) || st.isAfter(end)) continue;

      final a = st.isBefore(start) ? start : st;
      final b = en.isAfter(end) ? end : en;

      if (!b.isAfter(a)) continue;

      totals[domainId] = (totals[domainId] ?? Duration.zero) + b.difference(a);
    }

    return totals;
  }

  DashboardDomainOrder computeDashboardDomainOrder({
    DateTime? now,
    double haloReachedThreshold = 0.85, // mets ta valeur réelle si besoin
  }) {
    final t = now ?? DateTime.now();

    final todayStart = DateTime(t.year, t.month, t.day);
    final todayEnd = t;

    final start24 = t.subtract(const Duration(hours: 24));
    final end24 = t;

    final start7 = todayStart.subtract(const Duration(days: 7));
    final end7 = todayStart; // exclut aujourd’hui (comme ton dashboard)

    final totalsTodayAll = timeTotalsByDomain(todayStart, todayEnd);
    final totals24All = timeTotalsByDomain(start24, end24);
    final totals7All = timeTotalsByDomain(start7, end7);

    final scoreByDomain = <String, double>{};
    final haloReachedByDomain = <String, bool>{};

    for (final d in state.activeDomains) {
      final hoursToday = (totalsTodayAll[d.id]?.inMinutes ?? 0) / 60.0;
      final hours24 = (totals24All[d.id]?.inMinutes ?? 0) / 60.0;

      final avgWeekHoursPerDay =
          ((totals7All[d.id]?.inMinutes ?? 0) / 60.0) / 7.0;

      final denom = avgWeekHoursPerDay;

      final big = denom > 0 ? (hours24 / denom).clamp(0.0, 1.0) : 0.0;
      final outer = denom > 0 ? (hoursToday / denom).clamp(0.0, 1.0) : 0.0;

      scoreByDomain[d.id] = (big - outer).abs();
      haloReachedByDomain[d.id] = outer >= haloReachedThreshold;
    }

    final sortedDomains = [...state.activeDomains]..sort((a, b) {
        final aReached = haloReachedByDomain[a.id] ?? false;
        final bReached = haloReachedByDomain[b.id] ?? false;

        if (aReached != bReached) return aReached ? 1 : -1;

        final sa = scoreByDomain[a.id] ?? 0.0;
        final sb = scoreByDomain[b.id] ?? 0.0;
        return sb.compareTo(sa);
      });

    final rankByDomain = {
      for (var i = 0; i < sortedDomains.length; i++) sortedDomains[i].id: i,
    };

    return DashboardDomainOrder(
      scoreByDomain: scoreByDomain,
      haloReachedByDomain: haloReachedByDomain,
      sortedDomains: sortedDomains,
      rankByDomain: rankByDomain,
    );
  }

  List<Domain> sortDomainsLikeDashboard({
    required Map<String, double> scoreByDomain,
    required Map<String, bool> haloReachedByDomain,
  }) {
    final sorted = [...state.activeDomains]..sort((a, b) {
        final aReached = haloReachedByDomain[a.id] ?? false;
        final bReached = haloReachedByDomain[b.id] ?? false;

        // 1) non atteint -> en haut
        if (aReached != bReached) {
          return aReached ? 1 : -1;
        }

        // 2) score desc
        final sa = scoreByDomain[a.id] ?? 0.0;
        final sb = scoreByDomain[b.id] ?? 0.0;
        return sb.compareTo(sa);
      });

    return sorted;
  }

  Map<String, int> domainRankFromSorted(List<Domain> sorted) {
    return {for (var i = 0; i < sorted.length; i++) sorted[i].id: i};
  }

  Map<String, int> dashboardDomainRank({
    required Map<String, double> scoreByDomain,
    required Map<String, bool> haloReachedByDomain,
  }) {
    final sorted = sortDomainsLikeDashboard(
      scoreByDomain: scoreByDomain,
      haloReachedByDomain: haloReachedByDomain,
    );
    return domainRankFromSorted(sorted);
  }

  Activity? shoppingActivity() {
    for (final a in state.activeActivities) {
      if (!a.isHabit && a.role == ActivityRole.shopping) {
        return a;
      }
    }
    return null;
  }

  void clearNowSkippedFor(String ymd) {
    state.nowSkippedByYmd.remove(ymd);
    onChange();
  }

  void clearNowDoneFor(String ymd) {
    state.nowDoneByYmd.remove(ymd);
    onChange();
  }

// Option pratique : tout remettre visible
  void clearNowHiddenFor(String ymd) {
    state.nowSkippedByYmd.remove(ymd);
    state.nowDoneByYmd.remove(ymd);
    onChange();
  }

  Map<String, Duration> timeTotalsByActivity(
    DateTime start,
    DateTime endExcl,
  ) {
    final Map<String, Duration> totals = {};

    for (final s in state.sessions) {
      final DateTime sStart = s.startAt;
      final DateTime sEnd = s.endAt ?? DateTime.now();

      // hors fenêtre → skip
      if (sEnd.isBefore(start) || !sStart.isBefore(endExcl)) {
        continue;
      }

      // clamp dans la fenêtre
      final DateTime a = sStart.isBefore(start) ? start : sStart;
      final DateTime b = sEnd.isAfter(endExcl) ? endExcl : sEnd;

      if (!b.isAfter(a)) continue;

      final dur = b.difference(a);

      totals[s.activityId] = (totals[s.activityId] ?? Duration.zero) + dur;
    }

    return totals;
  }

  SuggestedActivity? suggestedCatchUpTimeByRemainingToday({
    Domain? domain, // null = tous domaines
    bool excludeCourses = true,
  }) {
    final domainId = domain?.id;

    final base = state.activeActivities
        .where((a) =>
            !a.isHabit &&
            a.goalMin > 0 &&
            (domainId == null || a.domainId == domainId))
        .toList();

    bool excluded(Activity a) =>
        excludeCourses && a.name.trim().toLowerCase() == 'courses';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final totalsToday = timeTotalsByActivity(today, now);

    final candidates = <SuggestedActivity>[];

    for (final a in base) {
      if (excluded(a)) continue;
      // ✅ EXCLUSION SNOOZE
      if (isActivitySnoozed(a.id, now)) continue;

      final doneMin = totalsToday[a.id]?.inMinutes ?? 0;
      final remaining = a.goalMin - doneMin;

      if (remaining <= 0) continue;

      candidates.add(SuggestedActivity(
        activity: a,
        remainingMin: remaining,
        doneMin: doneMin,
      ));
    }

    candidates.sort((x, y) {
      final c1 = x.remainingMin.compareTo(y.remainingMin);
      if (c1 != 0) return c1;
      return y.doneMin.compareTo(x.doneMin);
    });

    final best = candidates.first;

    return best;
  }

  Activity? suggestedCatchUpActivity({
    Domain? domain, // null = tous les domaines
    required bool isHabitsTab,
    bool excludeCourses = true,
    double snap = 0.95,
  }) {
    final String? domainId = domain?.id;

    // --- base (exactement comme ton écran) ---
    final base = isHabitsTab
        ? state.activeActivities
            .where((a) =>
                a.isHabit && (domainId == null || a.domainId == domainId))
            .toList()
        : state.activeActivities
            .where((a) =>
                !a.isHabit && (domainId == null || a.domainId == domainId))
            .toList();

    if (base.isEmpty) return null;

    // Exclusion "Courses" (simple MVP)
    bool isExcluded(Activity a) {
      if (!excludeCourses) return false;
      return a.name.trim().toLowerCase() == 'courses';
    }

    if (isHabitsTab) {
      // ---- HABITS : même logique que ton écran ----
      final notReached = <Activity>[];

      for (final a in base) {
        if (isExcluded(a)) continue;
        if (!habitReached(a)) notReached.add(a);
      }

      // tri “proche de 100% en haut”
      int cmpByExit(Activity x, Activity y) {
        double ratio(Activity a) {
          final tgt = activeHabitTarget(a);
          if (tgt <= 0) return 0.0;
          final done = activeHabitDone(a);
          return (done / tgt).clamp(0.0, 1.0);
        }

        return (1 - ratio(x)).compareTo(1 - ratio(y));
      }

      notReached.sort(cmpByExit);
      return notReached.isEmpty ? null : notReached.first;
    } else {
      // ---- TIME : même logique que ton écran ----
      final cache = <String, bool>{};

      bool reached(Activity a) => cache.putIfAbsent(
            a.id,
            () => isTimeReachedByAvg7(
              this,
              a,
              sessions: state.sessions,
              snap: snap,
            ),
          );

      final under = base.where((a) => !isExcluded(a) && !reached(a)).toList();

      // ⚠️ Ici ton écran ne trie pas explicitement under,
      // donc pour être "identique", on garde l'ordre de base.
      // Si tu veux le même tri que l'écran "À rattraper" (si tu en ajoutes un),
      // tu le mets ici aussi.

      return under.isEmpty ? null : under.first;
    }
  }

  void rolloverUndone({DateTime? now}) {
    // DayPlanItem supprimé — plus de rollover à faire
  }

  int avgMinutesPerDayInclToday(int days, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);

    final start =
        today.subtract(Duration(days: days - 1)); // inclut aujourd’hui
    final end = today.add(const Duration(days: 1)); // demain exclu

    final totals = timeTotalsByDomain(start, end);
    final totalMin = totals.values.fold<int>(0, (a, d) => a + d.inMinutes);

    return (totalMin / days.toDouble()).round();
  }

// (optionnel pour la sheet)
  int totalMinutesInclToday(int days, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);

    final start = today.subtract(Duration(days: days - 1));
    final end = today.add(const Duration(days: 1));

    final totals = timeTotalsByDomain(start, end);
    return totals.values.fold<int>(0, (a, d) => a + d.inMinutes);
  }

  double avg7HoursPerDayCached() {
    final t = DateTime.now();
    final key = "${t.year}-${t.month}-${t.day}";
    if (_avg7CacheDayKey == key && _avg7CacheValue != null)
      return _avg7CacheValue!;
    final v = avg7HoursPerDay(now: t);
    _avg7CacheDayKey = key;
    _avg7CacheValue = v;
    return v;
  }

  String fmtMinutesPerDay(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return "${h}h${m.toString().padLeft(2, '0')}/j";
  }

  String fmtPct24(int mins) {
    final pct = ((mins / 1440.0) * 100).round();
    return "$pct%";
  }

  int avg7MinutesPerDayInclToday({DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);

    final start = today
        .subtract(const Duration(days: 6)); // inclut aujourd’hui => 7 jours
    final end = DateTime(t.year, t.month, t.day)
        .add(const Duration(days: 1)); // demain exclu

    final totals = timeTotalsByDomain(start, end);
    final totalMin = totals.values.fold<int>(0, (a, d) => a + d.inMinutes);

    return (totalMin / 7.0).round(); // minute près
  }

  double avg7HoursPerDay({DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);

    final start7 = today.subtract(const Duration(days: 7));
    final end7 = today; // exclut aujourd’hui

    final totals7 = timeTotalsByDomain(start7, end7);
    final total7Dur =
        totals7.values.fold<Duration>(Duration.zero, (a, b) => a + b);

    final activeDays = totals7.values.where((d) => d > Duration.zero).length;
    if (activeDays == 0) return 0.0;

    return (total7Dur.inMinutes / 60.0) / activeDays;
  }

  List<int> minutesByHourLast24(DateTime now) {
    final t = now;

    DateTime floorToHour(DateTime d) =>
        DateTime(d.year, d.month, d.day, d.hour);

    // ✅ Axe horaire calendaire :
    // - dernière barre = heure courante (ex: 22:00 -> 23:00)
    // - première barre = heure courante - 23h
    final currentHour = floorToHour(t);
    final base = currentHour.subtract(const Duration(hours: 23));
    final windowStart = base;
    final windowEnd = currentHour.add(const Duration(hours: 1));

    final bins = List<int>.filled(24, 0);

    for (final s in state.sessions) {
      final start = s.startAt;
      final end = s.endAt ?? t;

      // clamp à la fenêtre [base .. currentHour+1h)
      final s0 = start.isAfter(windowStart) ? start : windowStart;
      final s1 = end.isBefore(windowEnd) ? end : windowEnd;
      if (!s0.isBefore(s1)) continue;

      var cur = s0;

      while (cur.isBefore(s1)) {
        final hStart = floorToHour(cur);
        final hEnd = hStart.add(const Duration(hours: 1));
        final chunkEnd = s1.isBefore(hEnd) ? s1 : hEnd;

        final minutes = chunkEnd.difference(cur).inMinutes;
        if (minutes > 0) {
          final idx = hStart.difference(base).inHours;
          if (idx >= 0 && idx < 24) {
            bins[idx] += minutes;
            if (bins[idx] > 60) bins[idx] = 60; // sécurité
          }
        }

        cur = chunkEnd;
      }
    }

    return bins;
  }

  // Retourne le domainId dominant (le plus de minutes) pour chacune des 24 heures.
  // null = aucune session dans cette heure.
  List<String?> domainByHourLast24(DateTime now) {
    final t = now;
    DateTime floorToHour(DateTime d) =>
        DateTime(d.year, d.month, d.day, d.hour);

    final currentHour = floorToHour(t);
    final base = currentHour.subtract(const Duration(hours: 23));
    final windowEnd = currentHour.add(const Duration(hours: 1));

    final activityDomain = {
      for (final a in state.activeActivities) a.id: a.domainId
    };

    // Par heure : domainId → minutes
    final bins = List<Map<String, int>>.generate(24, (_) => {});

    for (final s in state.sessions) {
      final domainId = activityDomain[s.activityId] ?? '';
      if (domainId.isEmpty) continue;

      final start = s.startAt;
      final end = s.endAt ?? t;
      final s0 = start.isAfter(base) ? start : base;
      final s1 = end.isBefore(windowEnd) ? end : windowEnd;
      if (!s0.isBefore(s1)) continue;

      var cur = s0;
      while (cur.isBefore(s1)) {
        final hStart = floorToHour(cur);
        final hEnd = hStart.add(const Duration(hours: 1));
        final chunkEnd = s1.isBefore(hEnd) ? s1 : hEnd;
        final minutes = chunkEnd.difference(cur).inMinutes;
        if (minutes > 0) {
          final idx = hStart.difference(base).inHours;
          if (idx >= 0 && idx < 24) {
            bins[idx][domainId] = (bins[idx][domainId] ?? 0) + minutes;
          }
        }
        cur = chunkEnd;
      }
    }

    return bins.map((map) {
      if (map.isEmpty) return null;
      return map.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }).toList();
  }

  // ── Blocs journaliers ──────────────────────────────────────────────────────

  bool isBlockDisabledForDay(String blockId, String ymd) {
    return (state.disabledBlocksByYmd[ymd] ?? []).contains(blockId);
  }

  void toggleBlockDisabledForDay(String blockId, String ymd) {
    final list = state.disabledBlocksByYmd[ymd] ??= [];
    if (list.contains(blockId)) {
      list.remove(blockId);
    } else {
      list.add(blockId);
    }
    onChange();
  }

  // Trouve le bloc associé à l'activité en cours via la chaîne
  // timer → linkedActivityId → routine → block.activityIds
  DayBlock? blockForRunningActivity(String ymd) {
    final running = runningActivity();
    if (running == null) return null;

    // Routines qui ont cette activité comme timer lié
    final linkedRoutines = state.activeActivities
        .where((a) => a.isHabit && a.linkedActivityId == running.id)
        .toList();

    if (linkedRoutines.isEmpty) return null;

    // Cherche le bloc qui contient l'une de ces routines.
    // Si ce bloc est désactivé pour aujourd'hui, on le réactive
    // automatiquement — lancer le timer est un signal d'intention explicite.
    final sorted = [...state.blocks]..sort((a, b) => a.order.compareTo(b.order));
    for (final block in sorted) {
      final hasRoutine =
          linkedRoutines.any((r) => block.activityIds.contains(r.id));
      if (!hasRoutine) continue;
      if (isBlockDisabledForDay(block.id, ymd)) {
        toggleBlockDisabledForDay(block.id, ymd); // réactive
      }
      return block;
    }

    return null;
  }

  void createBlock(String name, {String? emoji}) {
    final maxOrder = state.blocks.isEmpty
        ? 0
        : state.blocks.map((b) => b.order).reduce(math.max) + 1;
    state.blocks.add(DayBlock(name: name, emoji: emoji, order: maxOrder));
    onChange();
  }

  void deleteBlock(String blockId) {
    state.blocks.removeWhere((b) => b.id == blockId);
    onChange();
  }

  void updateBlock(String blockId,
      {String? name,
      String? emoji,
      bool clearEmoji = false,
      int? startHour,
      int? startMinute,
      bool clearStartTime = false}) {
    final b = state.blocks.firstWhereOrNull((b) => b.id == blockId);
    if (b == null) return;
    if (name != null) b.name = name;
    if (clearEmoji) {
      b.emoji = null;
    } else if (emoji != null) {
      b.emoji = emoji;
    }
    if (clearStartTime) {
      b.startHour = null;
      b.startMinute = null;
    } else if (startHour != null) {
      b.startHour = startHour;
      b.startMinute = startMinute ?? 0;
    }
    onChange();
  }

  void reorderBlocks(int oldIndex, int newIndex) {
    final sorted = [...state.blocks]..sort((a, b) => a.order.compareTo(b.order));
    if (newIndex > oldIndex) newIndex--;
    final b = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, b);
    for (int i = 0; i < sorted.length; i++) {
      sorted[i].order = i;
    }
    onChange();
  }

  void addActivityToBlock(String blockId, String activityId) {
    final b = state.blocks.firstWhereOrNull((b) => b.id == blockId);
    if (b == null) return;
    if (!b.activityIds.contains(activityId)) b.activityIds.add(activityId);
    onChange();
  }

  void removeActivityFromBlock(String blockId, String activityId) {
    final b = state.blocks.firstWhereOrNull((b) => b.id == blockId);
    if (b == null) return;
    b.activityIds.remove(activityId);
    onChange();
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
  final Duration? timeDeficit;
  final int? habitDeficit;
  final String? titleOverride;
  final String? subtitleOverride;

  FocusItem({
    required this.kind,
    required this.score,
    required this.reason,
    this.activity,
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

void autoTuneHabitFrom30d(AppLogic l, Activity act) {
  if (!act.isHabit || act.manualTarget == true) return;

  final done30 = l.habitSliding(act.id, 30).done;

  // Calculs sur 30 jours
  final dailyTarget = (done30 / 30.0).floor(); // 30 -> 1/j ; 60 -> 2/j
  final weeklyTarget = (done30 / 4.0).floor(); // ≈ 4 semaines sur 30j

  // 1) Daily si possible
  if (dailyTarget >= 1) {
    act.habitFreq = HabitFreq.daily;
    act.habitTarget = dailyTarget; // >= 1
    return;
  }

  // 2) Weekly seulement si >= 1
  if (weeklyTarget >= 1) {
    act.habitFreq = HabitFreq.weekly;
    act.habitTarget = weeklyTarget; // >= 1
    return;
  }

  // 3) Sinon Monthly (minimum 1)
  act.habitFreq = HabitFreq.monthly;
  act.habitTarget = math.max(1, done30);
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
  double timePct(String activityId, DateTime start, DateTime end, int days) {
    final doneMin = totalForRangeByActivity(activityId, start, end).inMinutes;
    final goalDay =
        state.activeActivities.firstWhere((a) => a.id == activityId).goalMin;
    final target = goalDay * days;
    if (target <= 0) return 0.0;
    return doneMin / target;
  }
}


class StepButton extends StatelessWidget {
  const StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}

class MiniHistogram30d extends StatelessWidget {
  const MiniHistogram30d({
    super.key,
    required this.values,
    this.maxValue,
    this.highlightLast = true,
    this.color,
  });

  final List<double> values;
  final double? maxValue;
  final bool highlightLast;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final barColor = color ?? cs.primary.withOpacity(0.9);
    return CustomPaint(
      painter: _MiniHistogramPainter(
        values: values,
        maxValue: maxValue,
        color: barColor.withOpacity(0.7),
        baseColor: cs.onSurface.withOpacity(0.12),
        highlightColor: barColor,
        highlightLast: highlightLast,
      ),
      size: Size.infinite,
    );
  }
}

class _MiniHistogramPainter extends CustomPainter {
  _MiniHistogramPainter({
    required this.values,
    required this.color,
    required this.baseColor,
    required this.highlightColor,
    required this.highlightLast,
    this.maxValue,
  });

  final List<double> values;
  final Color color;
  final Color baseColor;
  final Color highlightColor;
  final bool highlightLast;
  final double? maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final basePaint = Paint()
      ..color = baseColor
      ..strokeWidth = 1;

    final baselineY = size.height - 1;
    canvas.drawLine(
        Offset(0, baselineY), Offset(size.width, baselineY), basePaint);

    double vmax = maxValue ?? values.fold<double>(0, (m, v) => v > m ? v : m);
    if (vmax <= 0) vmax = 1.0;

    final n = values.length;
    final gap = 2.0;
    final barW = ((size.width - gap * (n - 1)) / n).clamp(1.0, 999.0);

    for (int i = 0; i < n; i++) {
      final v = values[i];
      final t = (v / vmax).clamp(0.0, 1.0);

      double h = t * (size.height - 2);
      if (v > 0 && h < 2) h = 2;

      final x = i * (barW + gap);
      final y = size.height - h;

      final isLast = highlightLast && i == n - 1;

      final paint = Paint()
        ..color = (v <= 0)
            ? baseColor.withOpacity(0.45)
            : (isLast ? highlightColor : color);

      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, h),
        const Radius.circular(2),
      );

      canvas.drawRRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniHistogramPainter old) {
    if (old.values.length != values.length) return true;
    if (old.maxValue != maxValue) return true;
    if (old.highlightLast != highlightLast) return true;
    for (int i = 0; i < values.length; i++) {
      if (old.values[i] != values[i]) return true;
    }
    return false;
  }
}

