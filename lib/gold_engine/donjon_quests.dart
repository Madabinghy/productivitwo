part of '../gold_engine.dart';

extension GoldEngineDonjon on AppLogic {
  // ── Défis du donjon (préparés par Orion, auto-validés) ──────────────────────

  /// Statut auto-validé des défis Orion pour le niveau VISÉ (`effectiveLevel+1`),
  /// dérivé des vraies données (routines / tâches / temps). Aucun écrit ici.
  List<({String label, String type, int target, int progress, bool done})>
      expeditionChallengeStatuses() {
    final target = effectiveLevel() + 1;
    final out =
        <({String label, String type, int target, int progress, bool done})>[];
    for (final raw in state.expeditionChallenges) {
      Map<String, dynamic> m;
      try {
        m = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if ((m['level'] as num?)?.toInt() != target) continue;
      final type = m['type'] as String? ?? '';
      final refId = m['refId'] as String? ?? '';
      final tgt = (m['target'] as num?)?.toInt() ?? 1;
      final label = m['label'] as String? ?? '';
      final since = m['createdYmd'] as String?; // ne compte qu'À PARTIR d'ici
      switch (type) {
        case 'task':
          final done = _taskIsDone(refId);
          out.add((
            label: label, type: type,
            target: 1, progress: done ? 1 : 0, done: done,
          ));
          break;
        case 'routine':
          final p = _routineMetDays(refId, since).clamp(0, tgt);
          out.add((
            label: label, type: type,
            target: tgt, progress: p, done: p >= tgt,
          ));
          break;
        case 'time':
          final p = _activityLoggedMinutes(refId, since).clamp(0, tgt);
          out.add((
            label: label, type: type,
            target: tgt, progress: p, done: p >= tgt,
          ));
          break;
        default:
          out.add((
            label: label, type: type,
            target: 1, progress: 0, done: false,
          ));
      }
    }
    return out;
  }

  /// Génère les défis du donjon CÔTÉ APP (instantané, sans Orion) si aucun
  /// n'existe pour le niveau visé. Pioche des objectifs réels et pertinents :
  /// 1 routine active (3 j), 1 tâche ouverte à deadline proche, 30 min de temps.
  /// Cibles de départ raisonnables (réglables). À appeler à l'ouverture du donjon.
  void ensureExpeditionChallenges(FirestoreSync sync) {
    final target = effectiveLevel() + 1;
    final already = state.expeditionChallenges.any((raw) {
      try {
        return (jsonDecode(raw)['level'] as num?)?.toInt() == target;
      } catch (_) {
        return false;
      }
    });
    if (already) return;
    final built = _buildChallengesForLevel(target);
    if (built.isEmpty) return; // pas de données → l'UI invite à créer routine/tâche
    state.expeditionChallenges = built;
    onChange();
    sync.setExpeditionChallenges(built);
  }

  List<String> _buildChallengesForLevel(int target) {
    final out = <String>[];
    final days = GoldEconomy.challengeRoutineDays(target);
    final mins = GoldEconomy.challengeTimeMinutes(target);
    final created = yyyymmdd(DateTime.now()); // défi compté À PARTIR d'ici

    // 1 routine active (habitude mesurable) — difficulté scalée par niveau.
    for (final a in state.activeActivities) {
      if (a.isHabit && activeHabitTarget(a) > 0) {
        out.add(jsonEncode({
          'level': target, 'type': 'routine', 'refId': a.id, 'target': days,
          'createdYmd': created,
          'label': days == 1
              ? 'Fais la routine « ${a.name} » aujourd\'hui'
              : 'Fais la routine « ${a.name} » pendant $days jours',
        }));
        break;
      }
    }

    // 1 tâche ouverte à l'échéance la plus proche (la plus pertinente).
    ProjectTask? bestTask;
    DateTime? bestEnd;
    for (final p in currentProjects) {
      if (p.status != 'active') continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        final d = t.endDate;
        final better = bestTask == null ||
            (d != null && (bestEnd == null || d.isBefore(bestEnd)));
        if (better) {
          bestTask = t;
          if (d != null) bestEnd = d;
        }
      }
    }
    if (bestTask != null) {
      out.add(jsonEncode({
        'level': target, 'type': 'task', 'refId': bestTask.id, 'target': 1,
        'createdYmd': created,
        'label': 'Termine la tâche « ${bestTask.title} »',
      }));
    }

    // 1 activité temps : minutes scalées par niveau.
    for (final a in state.activeActivities) {
      if (!a.isHabit) {
        out.add(jsonEncode({
          'level': target, 'type': 'time', 'refId': a.id, 'target': mins,
          'createdYmd': created,
          'label': 'Logue $mins min sur « ${a.name} »',
        }));
        break;
      }
    }

    return out;
  }

  /// Vrai si le donjon du niveau visé a déjà été ouvert → on y entre direct
  /// (sinon on passe par l'overworld pour trouver le château).
  bool get donjonAlreadyEntered =>
      state.expeditionDonjonLevel == effectiveLevel() + 1;

  /// Tous les défis du niveau visé sont accomplis (→ donjon franchissable).
  bool expeditionChallengesAllDone() {
    final st = expeditionChallengeStatuses();
    return st.isNotEmpty && st.every((c) => c.done);
  }

  /// Vrai si un défi du niveau visé cible une donnée DISPARUE (activité supprimée,
  /// tâche introuvable, JSON malformé, type inconnu) : il ne pourra jamais se
  /// valider → le donjon est bloqué. Sert à proposer « Régénérer les défis ».
  bool expeditionHasObsoleteChallenge() {
    final target = effectiveLevel() + 1;
    for (final raw in state.expeditionChallenges) {
      Map<String, dynamic> m;
      try {
        m = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return true; // malformé
      }
      if ((m['level'] as num?)?.toInt() != target) continue;
      if (_challengeTargetMissing(
          m['type'] as String? ?? '', m['refId'] as String? ?? '')) {
        return true;
      }
    }
    return false;
  }

  bool _challengeTargetMissing(String type, String refId) {
    switch (type) {
      case 'routine':
      case 'time':
        for (final a in state.activities) {
          if (a.id == refId) return a.deleted; // présente mais supprimée = obsolète
        }
        return true; // activité introuvable
      case 'task':
        for (final p in currentProjects) {
          for (final t in p.tasks) {
            if (t.id == refId) return false; // tâche présente
          }
        }
        return true; // tâche introuvable
      default:
        return true; // type inconnu
    }
  }

  /// Régénère les défis du niveau visé depuis des cibles VALIDES (données
  /// actuelles) et remet le donjon à zéro (parcours réinitialisé). No-op si aucune
  /// cible valide n'existe (on ne casse pas un donjon en cours pour rien).
  void regenerateExpeditionChallenges(FirestoreSync sync) {
    final target = effectiveLevel() + 1;
    final built = _buildChallengesForLevel(target);
    if (built.isEmpty) return;
    state.expeditionChallenges
      ..removeWhere((raw) {
        try {
          return (jsonDecode(raw)['level'] as num?)?.toInt() == target;
        } catch (_) {
          return true; // malformé → on jette
        }
      })
      ..addAll(built);
    state.expeditionCleared.clear(); // donjon remis à zéro
    onChange();
    sync.resetExpeditionProgress(state.expeditionChallenges);
  }

  bool _taskIsDone(String taskId) {
    for (final p in currentProjects) {
      for (final t in p.tasks) {
        if (t.id == taskId) return t.status == 'done';
      }
    }
    return false;
  }

  int _routineMetDays(String activityId, [String? since]) {
    Activity? a;
    for (final x in state.activities) {
      if (x.id == activityId) {
        a = x;
        break;
      }
    }
    if (a == null) return 0;
    // Seuil PAR JOUR (un jour « fait »), pas la cible de période : `activeHabitTarget`
    // renvoie la cible HEBDO/MENSUELLE pour ces fréquences, qu'un seul jour
    // (`hp.value` ≈ 1) n'atteint jamais → le défi « N jours » devenait IMPOSSIBLE
    // (donjon bloqué). `dayQuotaFor` = 1/jour en hebdo/mensuel, inchangé en quotidien.
    final tgt = dayQuotaFor(a);
    if (tgt <= 0) return 0;
    var days = 0;
    for (final hp in state.habitProgress) {
      if (hp.activityId != activityId || hp.value < tgt) continue;
      if (since != null && hp.yyyymmdd.compareTo(since) < 0) continue;
      days++;
    }
    return days;
  }

  int _activityLoggedMinutes(String activityId, [String? since]) {
    var min = 0;
    for (final s in state.sessions) {
      if (s.activityId != activityId) continue;
      if (since != null && yyyymmdd(s.startAt).compareTo(since) < 0) continue;
      min += s.duration.inMinutes;
    }
    return min;
  }

  /// Minutes loggées sur UN jour précis (pour la sévérité par jour).
  int _loggedMinutesOnDay(String activityId, String ymd) {
    var min = 0;
    for (final s in state.sessions) {
      if (s.activityId != activityId) continue;
      if (yyyymmdd(s.startAt) != ymd) continue;
      min += s.duration.inMinutes;
    }
    return min;
  }

  // ── Prévisualisation des coûts (Phase B) ────────────────────────────────────

  int previewDeleteActionCost() => GoldEconomy.deleteAction;
  int previewDeleteRoutineCost() => GoldEconomy.deleteRoutine;
  int previewDeadlinePushCost() => GoldEconomy.deadlinePush;

  int previewDeleteProjectCost(Project p) {
    final actions = p.tasks.fold<int>(0, (s, t) => s + t.actions.length);
    return GoldEconomy.deleteProjectCost(p.tasks.length, actions);
  }

  // ── Risques & provisoire (Phase C) ──────────────────────────────────────────

  /// Or « gain » d'un jour donné (gains seuls, sans pénalité), cohérent avec la
  /// matérialisation. Sert au provisoire du jour ET à la courbe d'historique.
  int goldGainForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final ymd = yyyymmdd(d);
    // Jours AVANT l'epoch (reset) → ignorés : l'historique repart de zéro.
    final epoch = state.goldEpochYmd;
    if (epoch != null && ymd.compareTo(epoch) < 0) return 0;
    final mult = state.goldBoostDays.contains(ymd) ? 2 : 1; // ×2 du jour
    final cursed = pestsAlive; // un ennemi vivant maudit tes routines (gain ÷2)
    var g = GoldEconomy.goldForMinutes(totalForDay(d).inMinutes, effectiveLevel());
    g += (state.challengeWinsByDay[ymd] ?? 0) * GoldEconomy.challengeDone;
    g += (state.ganttActionsByDay[ymd] ?? 0) * GoldEconomy.ganttAction;
    for (final a in state.activeActivities.where((x) => x.isHabit)) {
      final tgt = activeHabitTarget(a);
      if (tgt > 0 && habitValueOn(a.id, d) >= tgt) {
        var rg = GoldEconomy.routineGain(habitStreakEndingOn(a.id, d));
        if (cursed) rg = (rg / 2).ceil(); // malus de combat
        g += rg;
      }
    }
    return g * mult;
  }

  /// Vrai si au moins un nuisible est vivant sur la carte (applique le malus).
  bool get pestsAlive =>
      state.expeditionEntities.any((e) => isPestType(decodeEntity(e).type));

  /// Drain HORAIRE des nuisibles : à chaque visite de la carte, on retire
  /// (somme des forces : 2/3/5 or/h) × heures écoulées (plafonné `pestDrainCapHours`).
  /// Remplace l'ancien drain quotidien. À appeler à l'ouverture de l'overworld.
  void drainPestsHourly(FirestoreSync sync) {
    final now = DateTime.now();
    final live = state.expeditionEntities
        .where((e) => isPestType(decodeEntity(e).type))
        .toList();
    if (live.isEmpty) {
      state.lastPestDrainAt = now.toIso8601String();
      return;
    }
    final last = state.lastPestDrainAt != null
        ? DateTime.tryParse(state.lastPestDrainAt!)
        : null;
    final hours = last == null
        ? 0
        : (now.difference(last).inMinutes ~/ 60)
            .clamp(0, GoldEconomy.pestDrainCapHours);
    state.lastPestDrainAt = now.toIso8601String();
    if (hours <= 0) {
      onChange();
      return;
    }
    final rate = live.fold<int>(
        0, (s, e) => s + GoldEconomy.pestCost(decodeEntity(e).type));
    final drain = rate * hours;
    if (drain <= 0) return;
    state.gold -= drain;
    if (state.gold < 0) state.gold = 0;
    onChange();
    sync.applyGold(GoldLedgerEntry(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      delta: -drain,
      category: 'loss',
      reasonCode: 'pest_drain_hourly',
      label: 'Nuisibles (−$rate or/h × ${hours}h)',
    ));
  }

  /// Or provisoire gagné aujourd'hui (gains seuls, sans pénalité — jour non clos).
  int provisionalGoldToday() => goldGainForDay(DateTime.now());

  // ── Quête du jour + coffre quotidien ────────────────────────────────────────

  int get dailyQuestTarget => GoldEconomy.dailyQuestTarget;

  /// Nombre d'« actions » accomplies aujourd'hui (routines validées + actions de
  /// projet cochées + défis relevés) → plus tu en fais, plus la quête avance.
  int dailyQuestProgress() {
    final today = DateTime.now();
    final ymd = yyyymmdd(today);
    int n = 0;
    for (final a in state.activeActivities) {
      if (!a.isHabit) continue;
      final tgt = activeHabitTarget(a);
      if (tgt > 0 && habitValueOn(a.id, today) >= tgt) n++;
    }
    n += state.ganttActionsByDay[ymd] ?? 0;
    n += state.challengeWinsByDay[ymd] ?? 0;
    return n;
  }

  bool dailyQuestDone() => dailyQuestProgress() >= dailyQuestTarget;

  /// Coffre du jour disponible : quête remplie ET pas encore ouvert aujourd'hui.
  bool dailyChestClaimable() =>
      dailyQuestDone() &&
      state.lastQuestClaimedYmd != yyyymmdd(DateTime.now());

  /// Or de série affiché sur la carte (🔥 jours consécutifs de quête).
  int get questStreak => state.questStreak;

  /// Ouvre le coffre quotidien → récompense VARIABLE (or + bonus de série +
  /// palier + chance de butin). Optimiste local + persistance.
  ({int gold, String? emoji, String? name, int streak, int milestone})
      claimDailyChest(FirestoreSync sync) {
    final today = DateTime.now();
    final ymd = yyyymmdd(today);
    if (state.lastQuestClaimedYmd == ymd) {
      return (gold: 0, emoji: null, name: null, streak: state.questStreak, milestone: 0);
    }
    final yesterday = yyyymmdd(today.subtract(const Duration(days: 1)));
    final streak =
        (state.lastQuestClaimedYmd == yesterday) ? state.questStreak + 1 : 1;
    final rng = Random();
    var gold = GoldEconomy.questChestGoldMin +
        rng.nextInt(
            GoldEconomy.questChestGoldMax - GoldEconomy.questChestGoldMin + 1);
    gold += (streak - 1).clamp(0, 10); // bonus de série croissant (cap +10/j)
    // Paliers de série : grosse récompense aux jalons.
    int milestone = 0;
    if (streak == 3) {
      milestone = 15;
    } else if (streak == 7) {
      milestone = 40;
    } else if (streak == 14) {
      milestone = 75;
    } else if (streak >= 30 && streak % 30 == 0) {
      milestone = 200;
    }
    gold += milestone;
    String? cid, emoji, name;
    if (rng.nextInt(100) < GoldEconomy.questChestCollectibleChancePct) {
      final pool = overworldCollectibles
          .where((c) => !state.collection.contains(c.id))
          .toList();
      if (pool.isNotEmpty) {
        final c = pool[rng.nextInt(pool.length)];
        cid = c.id;
        emoji = c.emoji;
        name = c.name;
      }
    }
    state.gold += gold;
    addLifetimeCapped(gold);
    if (cid != null && !state.collection.contains(cid)) {
      state.collection.add(cid);
      state.collectionMeta[cid] = '$ymd|coffre de quête';
      sync.setCollectionMeta(state.collectionMeta);
    }
    state.lastQuestClaimedYmd = ymd;
    state.questStreak = streak;
    onChange();
    sync.claimDailyQuest(
        gold: gold, collectibleId: cid, ymd: ymd, questStreak: streak);
    return (gold: gold, emoji: emoji, name: name, streak: streak, milestone: milestone);
  }

  /// Or que rapporterait une routine si elle est validée aujourd'hui (gain de
  /// base + bonus de série projeté). Sert à l'affichage « +N or » de « Mon or ».
  int routineGainToday(Activity a) {
    final today = DateTime.now();
    final tgt = activeHabitTarget(a);
    final doneToday = tgt > 0 && habitValueOn(a.id, today) >= tgt;
    final streak = doneToday
        ? habitStreakEndingOn(a.id, today)
        : habitStreakEndingOn(a.id, today.subtract(const Duration(days: 1))) + 1;
    return GoldEconomy.routineGain(streak);
  }

  /// Net d'or projeté ce soir si rien ne change : gains provisoires du jour
  /// moins les pertes à venir (routines lancées non faites + tâches en retard).
  int projectedGoldNetToday() {
    final losses = bleedingRoutines().length * GoldEconomy.routineMissed +
        lateTasks().length * GoldEconomy.lateTaskPerDay;
    return provisionalGoldToday() - losses;
  }

  /// Routines lancées mais NON faites aujourd'hui (saignent −1/j), avec l'or
  /// approximatif déjà rapporté (nb de jours faits × routineMet).
  List<({Activity activity, int earned})> bleedingRoutines() {
    final today = DateTime.now();
    final out = <({Activity activity, int earned})>[];
    final todayYmd = yyyymmdd(today);
    for (final a in state.activeActivities.where((x) => x.isHabit)) {
      final tgt = activeHabitTarget(a);
      if (tgt <= 0) continue;
      if (habitValueOn(a.id, today) >= tgt) continue; // faite aujourd'hui
      if (state.goldGelDays.contains('${a.id}_$todayYmd')) continue; // gelée
      if (!_routineLaunchedBy(a, today)) continue; // jamais lancée
      var metDays = 0;
      for (final hp in state.habitProgress) {
        if (hp.activityId == a.id && hp.value >= tgt) metDays++;
      }
      out.add((activity: a, earned: metDays * GoldEconomy.routineMet));
    }
    return out;
  }

  /// Tâches Gantt en retard avec le nombre de jours de retard.
  List<({Project project, ProjectTask task, int daysLate})> lateTasks() {
    final today = DateTime.now();
    final todayMid = DateTime(today.year, today.month, today.day);
    final todayYmd = yyyymmdd(today);
    final out = <({Project project, ProjectTask task, int daysLate})>[];
    for (final p in currentProjects) {
      if (p.status != 'active') continue; // skip draft + archived (hors économie)
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        if (state.goldTaskShieldDays.contains('${t.id}_$todayYmd')) {
          continue; // bouclier anti-retard actif aujourd'hui
        }
        if (t.endDate != null && t.endDate!.isBefore(todayMid)) {
          final days = todayMid
              .difference(DateTime(
                  t.endDate!.year, t.endDate!.month, t.endDate!.day))
              .inDays;
          out.add((project: p, task: t, daysLate: days));
        }
      }
    }
    return out;
  }
}
