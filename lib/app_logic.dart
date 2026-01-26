// applogic.dart — version sans dailyTarget, cibles dérivées partout ✨

import 'dart:math' as math;
import 'package:collection/collection.dart';
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

sealed class RowItem {
  String get id;
  const RowItem();
}

class RowHeader extends RowItem {
  @override final String id;
  final String title;
  const RowHeader(this.id, this.title);
}

class RowPlan extends RowItem {
  @override final String id;
  final DayPlanItem it;
   RowPlan(this.it) : id = it.id;
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

// =====================================================
// ===============  LOGIQUE PRINCIPALE  ================
// =====================================================

class AppLogic {
  AppState state;
  final void Function() onChange;
  AppLogic(this.state, this.onChange);

  String? _lastRolloverDay;
  final List<HabitAssocEvent> habitAssocEvents = [];

  void pinHabitToActivity(String habitId, String activityId) {
  habitAssocEvents.removeWhere((e) =>
      e.type == HabitAssocEventType.pinned && e.habitId == habitId);
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

  Activity? runningActivity() {
    Session? last;
    for (final s in state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last!.startAt)) last = s;
    }
    if (last == null) return null;

    return state.activities.firstWhere(
      (a) => a.id == last!.activityId,
      orElse: () => Activity(domainId: '', name: '', habitTarget: 1),
    );
  }

  String? runningActivityId() {
    // dernière session non terminée (si plusieurs, prends la plus récente)
    Session? last;
    for (final s in state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last!.startAt)) last = s;
    }
    return last?.activityId;
  }

  String? runningDomainId() {
    final actId = runningActivityId();
    if (actId == null) return null;

    final a = state.activities.firstWhere(
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

  void appendToTomorrowIfLastIsDifferent(
    PlanKind kind,
    String refId,
    String title, {
    String? domainId, // ✅ NEW
  }) {
    final tomoKey = _tomorrowKey();

    DayPlanItem? last;
    for (final e in state.dayPlan) {
      if (e.yyyymmdd != tomoKey) continue;
      if (last == null || e.order > last!.order) last = e;
    }

    final sameAsLast =
        last != null && last!.kind == kind && last!.refId == refId;
    if (sameAsLast) return;

    state.dayPlan.add(
      DayPlanItem(
        id: _uuid.v4(),
        kind: kind,
        refId: refId,
        domainId: domainId, // ✅
        title: title,
        yyyymmdd: tomoKey,
        done: false,
        allDay: false,
        order: _nextOrderForDay(tomoKey),
      ),
    );

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
    // 1) stop sessions en cours
    for (final s in state.sessions.where((s) => s.endAt == null)) {
      s.endAt = DateTime.now();
    }

    // 2) nouvelle session
    state.sessions
        .add(Session(activityId: activityId, startAt: DateTime.now()));

    // 3) journal (burst) -> demain
    final title = state.activities
        .firstWhere(
          (a) => a.id == activityId,
          orElse: () =>
              Activity(domainId: '', name: 'Activité', habitTarget: 1),
        )
        .name;

    removeFromDay(_todayKeyLocal(), PlanKind.activityTime, activityId);
    logTomorrowIfLastDifferent(PlanKind.activityTime, activityId, title);

    // 4) optionnel : préparer demain (si tu veux "planifier", pas "journaliser")
    // ensurePlannedTomorrow(PlanKind.activityTime, activityId);

    // 5) persiste une seule fois
    onChange();
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

    final act = state.activities.firstWhere((a) => a.id == activityId);
    final currentDay = DateTime(day.year, day.month, day.day);
    final doneOnDay = habitValueOn(activityId, currentDay);

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

    // --- planifier un lanceur "habit" aujourd’hui (anti-doublon) ---
    if (delta > 0 && doneOnDay > 0) {
      final ymdToday = yyyymmdd(currentDay);
      ensurePlannedOnce(
        ymdToday,
        PlanKind.habit,
        activityId,
        act.name,
        domainId: act.domainId,
      );
    }

    // --- Retirer d’aujourd’hui uniquement si manuel + daily + atteint ---
    final freq = effectiveHabitFreq(act);
    if (freq == HabitFreq.daily) {
      final dayQuota = dayQuotaFor(act);
      if (act.manualTarget && dayQuota > 0 && doneOnDay >= dayQuota) {
        removeFromDay(yyyymmdd(currentDay), PlanKind.habit, activityId);
      }
    }

    // --- auto-tune 30j seulement si AUTO et pas manuel ---
    if (!act.manualTarget && act.autoTune) {
      autoTuneHabitFrom30d(this, act);
    }

    onChange();
    return assocEvent;
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
    final act = state.activities.firstWhere((a) => a.id == activityId);
    final currentDay = DateTime(day.year, day.month, day.day);
    final doneOnDay = habitValueOn(activityId, currentDay);

    // ✅ JOURNAL (burst) — toutes fréquences, sans spam
    // - seulement sur incrément
    // - seulement s'il y a quelque chose à logguer
/*     if (delta > 0 && doneOnDay > 0) {
      logTomorrowIfLastDifferent(
        PlanKind.habit,
        activityId,
        act.name,
      );
    } */

if (delta > 0) {
  final running = runningActivity();

  // log contexte (tu l'as déjà)
  state.habitHits.add(HabitHit(
    habitId: activityId,
    ts: DateTime.now(),
    contextActivityId: running?.id,
  ));

  // ✅ PIN automatique si une activité tourne
  if (running != null) {
    pinHabitToActivity(activityId, running.id);
  }
}
    if (delta > 0 && doneOnDay > 0) {
      final ymdToday = yyyymmdd(currentDay);
      ensurePlannedOnce(
        ymdToday,
        PlanKind.habit,
        activityId,
        act.name,
        domainId: act.domainId,
      );
    }

    // ✅ Retirer d’Aujourd’hui uniquement si :
    // - cible MANUELLE
    // - logique quotidienne
    final freq = effectiveHabitFreq(act);
    if (freq == HabitFreq.daily) {
      final dayQuota = dayQuotaFor(act);
      if (act.manualTarget && dayQuota > 0 && doneOnDay >= dayQuota) {
        removeFromDay(yyyymmdd(currentDay), PlanKind.habit, activityId);
      }
    }

    // auto-tune (safe)
    //_autoTuneHabitSafe(act);

    // auto-tune basé 30 jours (sans cooldown)
    autoTuneHabitFrom30d(this, act);

    // Un seul persist à la fin
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

  List<DayPlanItem> injectSuggestedActivities({
    required List<DayPlanItem> items,
    required String ymd,
    required DateTime now,
  }) {
    final out = <DayPlanItem>[];

    // activités déjà présentes (planifiées OU injectées)
    final seenActivityIds = <String>{
      for (final it in items)
        if (it.kind == PlanKind.activityTime && it.refId != null) it.refId!,
    };

    // --- A) injection activité associée au-dessus de la routine ---
    for (final it in items) {
      if (it.kind == PlanKind.habit && it.refId != null) {
        final habitId = it.refId!;

        final suggestedActId = suggestedActivityForHabit(
          habitId: habitId,
          now: now,
        ); // ✅ pas de fallback domaine

        if (suggestedActId != null &&
            !seenActivityIds.contains(suggestedActId)) {
          final act =
              state.activities.firstWhereOrNull((a) => a.id == suggestedActId);
          if (act != null) {
            out.add(
              DayPlanItem(
                id: 'virtAct:${act.id}',
                kind: PlanKind.activityTime,
                refId: act.id,
                domainId: act.domainId,
                title: act.name,
                yyyymmdd: ymd,
                done: false,
                doneCount: 0,
                allDay: true,
                order: 1 << 30,
              ),
            );
            seenActivityIds.add(act.id);
          }
        }
      }

      out.add(it);
    }

    // --- C) ensuite, ajouter les activités "sous seuil" (à rattraper) EN BAS ---
    // ⚠️ seulement après les routines, donc ici à la fin.
    final underGoalActs = state.activities
        .where((a) => !a.isHabit) // activités temps
        .where((a) => activityUnderGoal(a, now)) // à toi: today ou 7j
        .where((a) => !seenActivityIds.contains(a.id))
        .toList();

    for (final a in underGoalActs) {
      out.add(
        DayPlanItem(
          id: 'virtActGoal:${a.id}', // virtuel "à rattraper"
          kind: PlanKind.activityTime,
          refId: a.id,
          domainId: a.domainId,
          title: a.name,
          yyyymmdd: ymd,
          done: false,
          doneCount: 0,
          allDay: true,
          order: 1 << 30,
        ),
      );
      seenActivityIds.add(a.id);
    }

    return out;
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

  void ensureDailyHabitsPlanned({DateTime? now}) {
    final t = now ?? DateTime.now();
    final todayKey = yyyymmdd(t);
    final tomorrowKey = yyyymmdd(t.add(const Duration(days: 1)));
    final today = DateTime(t.year, t.month, t.day);

    bool exists(String ymd, PlanKind kind, String refId) =>
        _existsInDay(ymd, kind, refId);

    for (final a in state.activities.where((x) => x.isHabit)) {
      if (effectiveHabitFreq(a) != HabitFreq.daily) continue;

      final quota = dayQuotaFor(a);
      if (quota <= 0) continue;

      // déjà présent aujourd'hui
      if (exists(todayKey, PlanKind.habit, a.id)) continue;

      // déjà atteint aujourd'hui
      final doneToday = habitValueOn(a.id, today);
      if (doneToday >= quota) continue;

      // déplacé vers demain => ne pas ré-ajouter aujourd'hui
      if (exists(tomorrowKey, PlanKind.habit, a.id)) continue;

      // ✅ ajouter à AUJOURD'HUI
      state.dayPlan.add(
        DayPlanItem(
          id: _uuid.v4(),
          kind: PlanKind.habit,
          refId: a.id,
          domainId: a.domainId,
          title: a.name,
          yyyymmdd: todayKey,
          done: false,
          allDay: true,
          order: _nextOrderForDay(todayKey),
        ),
      );
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
/*     for (final a in state.activities.where((x) => x.isHabit)) {
      autoTuneHabitImmediate(this, a); // hausse immédiate si >120%
      _autoTuneHabitSafe(a, now: t); // finetune avec cooldown
    } */

    for (final a in state.activities.where((x) => x.isHabit)) {
      if (a.manualTarget == true) continue;
      autoTuneHabitFrom30d(this, a);
    }

    //state.lastGoalsReview = t;
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
      (e) => e.yyyymmdd == tomoKey && e.kind == kind && e.refId == refId,
    );
    if (exists) return;

    Activity? act;
    String title;

    switch (kind) {
      case PlanKind.activityTime:
        act = state.activities.firstWhere(
          (a) => a.id == refId,
          orElse: () =>
              Activity(domainId: '', name: 'Activité', habitTarget: 1),
        );
        title = act.name;
        break;

      case PlanKind.habit:
        act = state.activities.firstWhere(
          (a) => a.id == refId,
          orElse: () => Activity(
            domainId: '',
            name: 'Routine',
            type: 'habit',
            habitTarget: 1,
          ),
        );
        title = act.name;
        break;

      case PlanKind.action:
        title = 'Action';
        break;
    }

    state.dayPlan.add(DayPlanItem(
      id: _uuid.v4(),
      kind: kind,
      refId: refId,
      domainId:
          act?.domainId.isNotEmpty == true ? act!.domainId : null, // ✅ NEW
      title: title,
      yyyymmdd: tomoKey,
      done: false,
      allDay: false,
      order: _nextOrderForDay(tomoKey),
    ));

    onChange();
  }

  bool removeFromDay(String ymd, PlanKind kind, String refId) {
    final before = state.dayPlan.length;
    state.dayPlan.removeWhere(
        (e) => e.yyyymmdd == ymd && e.kind == kind && e.refId == refId);
    return state.dayPlan.length != before;
  }

  bool backfillDomainIdsForPlan() {
    bool changed = false;

    for (final it in state.dayPlan) {
      if (it.domainId != null) continue;
      if (it.refId == null) continue;

      if (it.kind == PlanKind.habit || it.kind == PlanKind.activityTime) {
        final a = state.activities.firstWhere(
          (x) => x.id == it.refId,
          orElse: () => Activity(domainId: '', name: '', habitTarget: 1),
        );
        if (a.domainId.isNotEmpty) {
          it.domainId = a.domainId;
          changed = true;
        }
      }
    }

    if (changed) onChange();
    return changed;
  }

  void ensurePlannedOnce(String ymd, PlanKind kind, String refId, String title,
      {String? domainId}) {
    final exists = state.dayPlan
        .any((e) => e.yyyymmdd == ymd && e.kind == kind && e.refId == refId);
    if (exists) return;

    state.dayPlan.add(DayPlanItem(
      id: _uuid.v4(),
      kind: kind,
      refId: refId,
      title: title,
      domainId: domainId ?? '',
      yyyymmdd: ymd,
      done: false,
      order: 1 << 30,
      allDay: true,
    ));
  }

  void logTomorrowIfLastDifferent(
    PlanKind kind,
    String refId,
    String title, {
    String? domainId, // ✅ NEW
  }) {
    final tomoKey = _tomorrowKey();

    DayPlanItem? last;
    for (final e in state.dayPlan) {
      if (e.yyyymmdd != tomoKey) continue;
      if (last == null || e.order > last!.order) last = e;
    }

    final sameAsLast =
        last != null && last!.kind == kind && last!.refId == refId;
    if (sameAsLast) return;

    state.dayPlan.add(
      DayPlanItem(
        id: _uuid.v4(),
        kind: kind,
        refId: refId,
        domainId:
            (domainId != null && domainId.isNotEmpty) ? domainId : null, // ✅
        title: title,
        yyyymmdd: tomoKey,
        done: false,
        allDay: false,
        order: _nextOrderForDay(tomoKey),
      ),
    );

    onChange();
  }

  String? _domainIdForJournal(PlanKind kind, String? refId) {
    if (refId == null) return null;

    // Cas couverts tout de suite chez toi : refId = Activity.id
    if (kind == PlanKind.habit || kind == PlanKind.activityTime) {
      final a = state.activities.firstWhere(
        (x) => x.id == refId,
        orElse: () => Activity(domainId: '', name: '', habitTarget: 1),
      );
      return a.domainId.isEmpty ? null : a.domainId;
    }

    // Actions / autres : pas de domaine (ou à compléter plus tard)
    return null;
  }

  void journalLog({
    required PlanKind kind,
    required String? refId,
    required String title,
  }) {
    final dayKey = _tomorrowKey(); // ou _todayKey()

    DayPlanItem? last;
    for (final e in state.dayPlan) {
      if (e.yyyymmdd != dayKey) continue;
      if (last == null || e.order > last!.order) last = e;
    }

    final sameAsLast = last != null && last.kind == kind && last.refId == refId;

    if (sameAsLast) return;

    state.dayPlan.add(
      DayPlanItem(
        id: _uuid.v4(),
        kind: kind,
        refId: refId,
        domainId: _domainIdForJournal(kind, refId), // ✅ NEW
        title: title,
        yyyymmdd: dayKey,
        done: false,
        allDay: false,
        order: _nextOrderForDay(dayKey),
      ),
    );

    onChange();
  }

  void moveItemToTomorrowById(String itemId) {
    final todayKey = _todayKey();
    final tomoKey = _tomorrowKey();

    final idx = state.dayPlan
        .indexWhere((e) => e.id == itemId && e.yyyymmdd == todayKey);
    if (idx < 0) return;

    final removed = state.dayPlan.removeAt(idx);

    state.dayPlan.add(
      DayPlanItem(
        id: _uuid.v4(), // ok si tu veux une nouvelle occurrence
        kind: removed.kind,
        refId: removed.refId, // ✅ garde
        domainId: removed.domainId, // ✅ garde (si ajouté au modèle)
        title: removed.title,
        yyyymmdd: tomoKey,
        done: false,
        allDay: removed.allDay,
        order: _nextOrderForDay(tomoKey),
      ),
    );

    onChange();
  }

  void movePlannedToTomorrowIfPresent(
    PlanKind kind,
    String refId, {
    bool addIfMissing = false,
    bool logEveryOccurrence = false, // ✅ NEW
  }) {
    final todayKey = _todayKey();
    final tomoKey = _tomorrowKey();

    final idx = _indexInDay(todayKey, kind, refId);
    DayPlanItem? removed;
    if (idx >= 0) {
      removed = state.dayPlan.removeAt(idx);
    }

    // ✅ ancien comportement : dédup demain
    if (!logEveryOccurrence) {
      final existsTomorrow = _indexInDay(tomoKey, kind, refId) >= 0;
      if (existsTomorrow) {
        onChange();
        return;
      }
    }

    // Helper pour title si besoin
    String _resolveTitle() {
      switch (kind) {
        case PlanKind.activityTime:
          return state.activities
              .firstWhere(
                (a) => a.id == refId,
                orElse: () =>
                    Activity(domainId: '', name: 'Activité', habitTarget: 1),
              )
              .name;
        case PlanKind.habit:
          return state.activities
              .firstWhere(
                (a) => a.id == refId,
                orElse: () => Activity(
                    domainId: '',
                    name: 'Routine',
                    type: 'habit',
                    habitTarget: 1),
              )
              .name;
        case PlanKind.action:
          return removed?.title ?? 'Action';
      }
    }

    String? _resolveDomainId() {
      switch (kind) {
        case PlanKind.activityTime:
        case PlanKind.habit:
          final a = state.activities.firstWhere(
            (x) => x.id == refId,
            orElse: () => Activity(domainId: '', name: '', habitTarget: 1),
          );
          return a.domainId.isEmpty ? null : a.domainId;
        case PlanKind.action:
          return null;
      }
    }

    DayPlanItem? toAdd;

// ✅ si on a retiré un item aujourd’hui, on log une occurrence demain
    if (removed != null) {
      toAdd = DayPlanItem(
        id: _uuid.v4(),
        kind: removed.kind,
        refId: removed.refId,
        domainId: removed.domainId, // ✅ NEW (si champ ajouté)
        title: removed.title,
        yyyymmdd: tomoKey,
        done: false,
        allDay: removed.allDay,
        order: _nextOrderForDay(tomoKey),
      );
    } else if (addIfMissing) {
      toAdd = DayPlanItem(
        id: _uuid.v4(),
        kind: kind,
        refId: refId,
        domainId: _resolveDomainId(), // ✅ NEW
        title: _resolveTitle(),
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

// =====================================================
// ===================  EXTENSIONS  ====================
// =====================================================

extension TodayLogic on AppLogic {
  void setSortTodayByDashboard(bool v) {
    state.sortTodayByDashboard = v;
    onChange();
  }

  String? _domainIdOfSession(Session s) {
    final a = state.activities.firstWhere(
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

    for (final d in state.domains) {
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

    final sortedDomains = [...state.domains]..sort((a, b) {
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

  List<DayPlanItem> viewItemsSortedByDashboard(
    List<DayPlanItem> input,
    Map<String, int> domainRank,
  ) {
    // stabilité: garde l'ordre manuel actuel à l’intérieur d’un même domaine
    final realIndex = <String, int>{};
    for (var i = 0; i < input.length; i++) {
      realIndex[input[i].id] = i;
    }

    final sorted = [...input];
    sorted.sort((a, b) {
      final ra =
          a.domainId == null ? 1 << 30 : (domainRank[a.domainId!] ?? 1 << 20);
      final rb =
          b.domainId == null ? 1 << 30 : (domainRank[b.domainId!] ?? 1 << 20);

      final c = ra.compareTo(rb);
      if (c != 0) return c;

      // même domaine => on garde l'ordre manuel actuel
      return (realIndex[a.id] ?? 0).compareTo(realIndex[b.id] ?? 0);
    });

    return sorted;
  }

  List<Domain> sortDomainsLikeDashboard({
    required Map<String, double> scoreByDomain,
    required Map<String, bool> haloReachedByDomain,
  }) {
    final sorted = [...state.domains]..sort((a, b) {
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

  bool _existsInDay(String ymd, PlanKind kind, String refId) {
    return state.dayPlan.any(
      (e) => e.yyyymmdd == ymd && e.kind == kind && e.refId == refId,
    );
  }

  void restorePlanItem(DayPlanItem item) {
    state.dayPlan.add(item);
    onChange();
  }

  DayPlanItem? toggleDonePlanItem(String ymd, String itemId, bool value) {
    final idx = state.dayPlan.indexWhere((e) => e.id == itemId);
    if (idx == -1) return null;

    final it = state.dayPlan[idx];

    // ACTION → cochée = supprimée
    if (it.kind == PlanKind.action) {
      if (value) {
        final removed = state.dayPlan.removeAt(idx);
        onChange();
        return removed; // <-- pour annuler
      }
      return null;
    }

    // ROUTINE → on marque done
    it.done = value;
    onChange();
    return null;
  }

  void markRoutineOkForToday(String ymd, String itemId, bool value) {
    final idx =
        state.dayPlan.indexWhere((e) => e.id == itemId && e.yyyymmdd == ymd);
    if (idx == -1) return;

    final it = state.dayPlan[idx];

    // On ne valide que routines (pas actions)
    if (it.kind == PlanKind.action) return;

    it.done = value;
    onChange();
  }

  Future<void> addPlanAction({
    required String ymd,
    required String title,
  }) async {
    final key = ymd; // <- respecte l'onglet (aujourd'hui/demain/...)

    final plan = planFor(key); // trié par order
    final todayKey = _todayKeyLocal();
    final isToday = (key == todayKey);

    final ord = plan.isEmpty
        ? 0
        : (isToday
            ? (plan.first.order - 1) // Aujourd'hui -> en tête
            : (plan.last.order + 1)); // Demain/autre -> en fin

    state.dayPlan.add(DayPlanItem(
      id: _uuid.v4(),
      kind: PlanKind.action,
      title: title,
      yyyymmdd: key,
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
    final key = ymd; // respecte l'onglet (aujourd'hui/demain/...)

    final plan = planFor(key); // trié par order
    final todayKey = _todayKeyLocal();
    final isToday = (key == todayKey);

    final ord = plan.isEmpty
        ? 0
        : (isToday
            ? (plan.first.order - 1) // Aujourd'hui -> en tête
            : (plan.last.order + 1)); // Demain/autre -> en fin

    state.dayPlan.add(DayPlanItem(
      id: const Uuid().v4(),
      kind: isHabit ? PlanKind.habit : PlanKind.activityTime,
      refId: activityId,
      domainId: act.domainId.isEmpty ? null : act.domainId, // ✅ NEW
      title: act.name,
      yyyymmdd: key, // ✅ FIX: pas todayKey
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

  void movePlanItemToEnd(String ymd, String itemId) {
    final plan = planFor(ymd);
    final oldIndex = plan.indexWhere((e) => e.id == itemId);
    if (oldIndex == -1) return;

    final lastIndex = plan
        .length; // IMPORTANT: même convention que onReorder (newIndex "après")
    if (oldIndex == plan.length - 1) return; // déjà en bas

    reorderPlan(ymd, oldIndex, lastIndex);
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

  bool _existsToday(String todayKey, DayPlanItem e) {
    return state.dayPlan.any((x) =>
        x.yyyymmdd == todayKey && x.kind == e.kind && x.refId == e.refId);
  }

  void rolloverUndone({DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = yyyymmdd(DateTime(t.year, t.month, t.day));
    final yesterday = yyyymmdd(
      DateTime(t.year, t.month, t.day).subtract(const Duration(days: 1)),
    );

    final carry =
        state.dayPlan.where((e) => e.yyyymmdd == yesterday && !e.done).toList();
    if (carry.isEmpty) return;

    var order = planFor(today).length;

    for (final e in carry) {
      // ✅ si déjà présent aujourd'hui, ne pas dupliquer
      final alreadyThere = state.dayPlan.any((x) {
        if (x.yyyymmdd != today) return false;
        if (x.kind != e.kind) return false;
        if (e.kind == PlanKind.action) return x.title == e.title;
        return x.refId == e.refId;
      });
      if (alreadyThere) continue;

      state.dayPlan.add(DayPlanItem(
        id: const Uuid().v4(),
        kind: e.kind,
        refId: e.refId,
        domainId: e.domainId, // ✅ NEW (si champ ajouté)
        title: e.title,
        yyyymmdd: today,
        done: false,
        doneCount: 0, // ✅ (ou e.doneCount si tu préfères)
        allDay: e.allDay,
        order: order++, // compteur propre
      ));
    }

    state.dayPlan.removeWhere((e) => e.yyyymmdd == yesterday);
    onChange();
  }

  void ensureTodayDailyHabits({DateTime? now}) {
    final t = now ?? DateTime.now();
    final todayKey = yyyymmdd(t);
    final tomorrowKey = yyyymmdd(t.add(const Duration(days: 1)));
    final todayDate = DateTime(t.year, t.month, t.day);

    bool changed = false;

    for (final a in state.activities.where((x) => x.isHabit)) {
      if (effectiveHabitFreq(a) != HabitFreq.daily) continue;

      final quota = dayQuotaFor(a);
      if (quota <= 0) continue;

      final done = habitValueOn(a.id, todayDate);

      if (done >= quota) {
        final removed = removeFromDay(todayKey, PlanKind.habit, a.id);
        if (removed) changed = true;
        continue;
      }

      // ✅ si l'utilisateur l'a poussée à demain, ne pas la remettre aujourd'hui
      final plannedTomorrow = state.dayPlan.any((e) =>
          e.yyyymmdd == tomorrowKey &&
          e.kind == PlanKind.habit &&
          e.refId == a.id);
      if (plannedTomorrow) continue;

      final exists = state.dayPlan.any((e) =>
          e.yyyymmdd == todayKey &&
          e.kind == PlanKind.habit &&
          e.refId == a.id);

      if (!exists) {
        state.dayPlan.add(DayPlanItem(
          id: const Uuid().v4(),
          kind: PlanKind.habit,
          refId: a.id,
          domainId: a.domainId.isEmpty ? null : a.domainId, // ✅
          title: a.name,
          yyyymmdd: todayKey,
          done: false,
          allDay: true,
          order: _nextOrderForDay(todayKey),
        ));
        changed = true;
      }
    }

    if (changed) onChange();
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
  });

  final List<double> values;
  final double? maxValue;
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _MiniHistogramPainter(
        values: values,
        maxValue: maxValue,
        color: cs.primary.withOpacity(0.9),
        baseColor: cs.onSurface.withOpacity(0.12),
        highlightColor: cs.secondary.withOpacity(0.95),
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
