part of '../gold_engine.dart';

extension GoldEnginePests on AppLogic {
  // ── Compteur global de nuisibles (HUD du Monde web) ─────────────────────────

  /// Totaux de nuisibles VIVANTS, tous domaines confondus :
  /// 🕷️ spiders = jours-routine manqués (fenêtre 7j) · 🦂 scorpions = jours
  /// d'activité-temps en retard sur la cible 7j · 🐍 snakes = tâches en retard.
  ({int spiders, int scorpions, int snakes}) worldPestTotals() {
    var spiders = 0, scorpions = 0, snakes = 0;
    for (final a in state.activeActivities) {
      if (a.isHabit) {
        // Post-pardon de série (cohérent avec le combat).
        for (final t in routineWaveTokens(a.id)) {
          if (t.type == 'spider') spiders++;
        }
      } else if (a.goalMin > 0) {
        for (final t in activityTimeTokens(a.id)) {
          if (t.type == 'spider') scorpions++;
        }
      }
    }
    for (final e in backlogEnemies()) {
      if (e.type == 'snake') snakes++;
    }
    return (spiders: spiders, scorpions: scorpions, snakes: snakes);
  }

  /// Jours « tenus » sur la fenêtre de 7 jours finissant à `end` (inclus), tous
  /// domaines : routineDays = (routine, jour) où le quota est atteint ;
  /// activityDays = (activité-temps, jour) où la cible du jour est atteinte.
  /// Sert au comparatif hebdo du HUD (cette semaine vs la précédente).
  ({int routineDays, int activityDays}) worldWeekWins(DateTime end) {
    final day0 = DateTime(end.year, end.month, end.day);
    var routineDays = 0, activityDays = 0;
    for (var i = 0; i < 7; i++) {
      final date = day0.subtract(Duration(days: i));
      for (final a in state.activeActivities) {
        if (a.isHabit) {
          final q = dayQuotaFor(a);
          if (q > 0 && habitValueOn(a.id, date) >= q) routineDays++;
        } else if (a.goalMin > 0 && _minutesOnDay(a.id, date) >= a.goalMin) {
          activityDays++;
        }
      }
    }
    return (routineDays: routineDays, activityDays: activityDays);
  }

  /// Jours (0-6, lun→dim) de CETTE semaine où la routine est MANQUÉE (jours passés
  /// ou aujourd'hui seulement) = les nuisibles de sa ligne dans le calendrier.
  List<int> routineMissedThisWeek(String routineId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == routineId) {
        a = x;
        break;
      }
    }
    if (a == null || !a.isHabit) return const [];
    final quota = dayQuotaFor(a);
    if (quota <= 0) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final mon = today.subtract(Duration(days: today.weekday - 1));
    final out = <int>[];
    for (var d = 0; d < 7; d++) {
      final date = mon.add(Duration(days: d));
      if (date.isAfter(today)) break; // jour futur → pas encore jouable
      if (habitValueOn(a.id, date) < quota) out.add(d);
    }
    return out;
  }

  /// Remplissage du CHÂTEAU d'une ligne de routine = bilan des jours PASSÉS
  /// (au-delà des 7 jours visibles, fenêtre ~3 semaines) : chaque jour manqué = +1
  /// toile, chaque jour fait RETIRE une toile d'abord (net). Net > 0 → toiles ;
  /// net < 0 (en avance) → feuilles. Plafonné à la largeur du château (9).
  ({int webs, int leaves}) routineChateauFill(String routineId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == routineId) {
        a = x;
        break;
      }
    }
    if (a == null || !a.isHabit) return (webs: 0, leaves: 0);
    final quota = dayQuotaFor(a);
    if (quota <= 0) return (webs: 0, leaves: 0);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final freq = effectiveHabitFreq(a);
    final period =
        freq == HabitFreq.weekly ? 7 : (freq == HabitFreq.monthly ? 30 : 1);
    var misses = 0, dones = 0;
    for (var k = 7; k < 28; k++) {
      final date = today.subtract(Duration(days: k));
      if (_habitValueOnGarden(a.id, date) >= quota) {
        dones++;
        continue;
      }
      if (freq == HabitFreq.daily) {
        misses++;
        continue;
      }
      // Non-daily : ce jour compte comme retard SEULEMENT si rien fait dans la
      // période (grâce). Sinon ni toile ni rien.
      var doneInPeriod = false;
      for (var p = 0; p < period; p++) {
        if (_habitValueOnGarden(a.id, date.subtract(Duration(days: p))) >= quota) {
          doneInPeriod = true;
          break;
        }
      }
      if (!doneInPeriod) misses++;
    }
    final net = misses - dones;
    final webs = net > 9 ? 9 : (net < 0 ? 0 : net);
    final leaves = net < 0 ? (-net > 9 ? 9 : -net) : 0;
    return (webs: webs, leaves: leaves);
  }

  /// HEATMAP HEBDO d'une routine : pour les `weeks` dernières semaines (lun→dim),
  /// le nb de jours où le quota a été atteint (0..7) = les « flammes » de la
  /// semaine. Index 0 = la plus ANCIENNE, dernier = la semaine EN COURS.
  /// 0 → semaine perdue (toile d'araignée) ; >0 → nb de flammes.
  List<int> routineWeeklyHeatmap(String routineId, {int weeks = 12}) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == routineId) {
        a = x;
        break;
      }
    }
    if (a == null || !a.isHabit) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMon = today.subtract(Duration(days: today.weekday - 1));
    return [
      for (var w = weeks - 1; w >= 0; w--)
        _routineWeekDone(a, thisMon.subtract(Duration(days: 7 * w)))
    ];
  }

  /// HEATMAP HEBDO d'une activité-temps : nb de jours où l'objectif-temps a été
  /// atteint par semaine (même ordre/convention que routineWeeklyHeatmap).
  List<int> activityTimeWeeklyHeatmap(String activityId, {int weeks = 12}) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == activityId) {
        a = x;
        break;
      }
    }
    if (a == null || a.isHabit) return const [];
    final goal = a.goalMin;
    if (goal <= 0) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMon = today.subtract(Duration(days: today.weekday - 1));
    return [
      for (var w = weeks - 1; w >= 0; w--)
        () {
          final mon = thisMon.subtract(Duration(days: 7 * w));
          var n = 0;
          for (var i = 0; i < 7; i++) {
            if (_minutesOnDay(a!.id, mon.add(Duration(days: i))) >= goal) n++;
          }
          return n;
        }()
    ];
  }

  /// PV d'une araignée de cette routine = la CIBLE quotidienne (quota) : grosse
  /// routine (boire 10 verres) = araignée à 10 PV.
  int routineTarget(String routineId) {
    for (final x in state.activeActivities) {
      if (x.id == routineId) return x.isHabit ? dayQuotaFor(x) : 0;
    }
    return 0;
  }
}
