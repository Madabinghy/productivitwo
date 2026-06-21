part of '../models.dart';

class AppState {
  List<Domain> domains; // inclut les deleted:true (filtrés par activeDomains)
  List<Domain> get activeDomains => domains.where((d) => !d.deleted).toList();
  List<Activity> activities;
  List<Activity> get activeActivities => activities.where((a) => !a.deleted).toList();
  List<Session> sessions;
  List<HabitProgress> habitProgress;

  // NEW: activité → ISO8601 jusqu’à quand elle est “snoozed”
  Map<String, String> snoozedUntil;

  List<InboxItem> inbox;

  String? lastRolloverYmd;
  String? lastCarryYmd; // on a déjà fait "Hier → Aujourd'hui" pour ce jour ?
  String? lastPrepYmd; // on a déjà fait "Aujourd'hui → Demain" pour ce jour ?

  List<String> focusTodayIds;
  bool sortTodayByDashboard;
  bool showTodayPriorities; // section "Priorités du jour" en tête de l'onglet Projets
  bool onboardingDone;

  // ✅ Habits context (associations)
  List<HabitHit> habitHits;
  List<Redemption> redemptions; // crédits de reconquête (jeu, ≠ relevé factuel)
  Map<String, String> habitPinnedActivity;
  Map<String, List<String>> nowSkippedByYmd;
  Map<String, List<String>> nowDoneByYmd; // ids "pas aujourd'hui / ok"
  Map<String, List<String>>
      habitChecklistByHabitId; // habitId -> ["item1","item2"]

  // ✅ NEW : progress checklist persisté
// habitId -> periodKey -> [indexes cochés]
  Map<String, Map<String, List<int>>> habitChecklistDone;
  FilterState filters;

  List<ActivityLog> activityLogs;
  bool coursesArchivedOnce;
  bool coursesRestoredOnce;
  bool coursesRestoredV2;
  bool linkedActivitiesMigratedOnce;
  bool voitureMigratedOnce;

  // Blocs journaliers
  List<DayBlock> blocks;

  // Priorités libres du jour
  List<TodayItem> todayItems;
  Map<String, List<String>> disabledBlocksByYmd; // ymd -> [blockIds désactivés]

  // Gamification
  List<EarnedBadge> earnedBadges;
  List<String> skippedChallengeDates;
  int weeklyScoreTarget; // % objectif hebdomadaire (0-100) // yyyymmdd où le défi a été passé
  int notifHour;           // rappel quotidien (défaut 9h)
  int notifMinute;
  bool notifEnabled;
  int reviewNotifHour;     // résumé fin de journée (défaut 21h)
  int reviewNotifMinute;
  bool reviewNotifEnabled;
  int streakNotifHour;     // streak en danger (défaut 20h)
  int streakNotifMinute;
  bool streakNotifEnabled;
  int challengeNotifHour;  // défi du jour (défaut 16h)
  int challengeNotifMinute;
  bool challengeNotifEnabled;
  int midDayNotifHour;     // score mi-journée (défaut 13h)
  int midDayNotifMinute;
  bool midDayNotifEnabled;
  bool domainIdBackfilledOnce;
  String alarmSound;       // clé de la sonnerie d'alarme (voir kAlarmRingtones)

  // Défis « Challenge me » (suivi léger : compteur + streak de jours)
  int challengesDone;          // total de défis relevés
  int challengeStreak;         // jours consécutifs avec ≥1 défi
  String? lastChallengeYmd;    // dernier jour (YYYYMMDD) où un défi a été relevé
  Map<String, int> ganttActionsByDay;  // actions Gantt cochées par jour (XP)
  Map<String, int> challengeWinsByDay; // défis relevés par jour (XP du jour)
  Map<String, int> battleShurikensByDay; // shurikens dépensés par jour (déloges gagnés)

  // ── Économie d'Or (système stratégique : gagner/perdre/dépenser) ──────────
  int gold;                    // solde de pièces d'or courant (plancher 0)
  int goldLifetime;            // or brut gagné à vie (monotone) → pilote le niveau
  String? goldLastProcessedDay;// YYYYMMDD : curseur du rattrapage idempotent
  Map<String, int> goldInventory; // consommables achetés : {gel, sursis, joker, shield, boost}
  List<String> goldGelDays;    // jours de routine gelés : "activityId_YYYYMMDD"
  List<String> goldTaskShieldDays; // jours de tâche protégés du retard : "taskId_YYYYMMDD"
  List<String> goldBoostDays;  // jours à gains ×2 : "YYYYMMDD"
  List<String> cosmeticsOwned; // cosmétiques possédés (ex: titres)
  String? activeTitle;         // titre cosmétique actif (override du titre de niveau)
  String? activeAvatar;        // emoji du skin d'avatar actif sur la carte (null = 🧍)
  int unlockedLevel;           // niveau effectif RÉVÉLÉ (payé) : l'XP rend éligible, on paie pour débloquer le titre/niveau (gate séquentiel)
  List<String> expeditionCleared; // nœuds franchis (V1 donjon, Phase 2) ; vidé à la complétion
  List<String> bossInvasions; // domaines envahis par un boss de donjon (jusqu'à la victoire)
  // ── Overworld (carte 2D explorable, per-map ; vidés à la complétion) ──
  List<String> expeditionRevealed; // cases éclairées "x_y"
  String? expeditionPos;           // case du perso "x_y"
  // ── Monde unifié (walk state de l'avatar ; PAS dans le doc territoire spectatable) ──
  List<String> unifiedRevealed;    // cases éclairées "x_y" sur la grande map
  String? unifiedPos;              // case de l'avatar "x_y" sur la grande map
  List<String> unifiedTurrets;     // tours TD posées "x_y" sur la grande map
  List<String> expeditionPicked;   // collectibles ramassés sur la map courante (ids)
  List<String> expeditionEntities; // nuisibles/bonus vivants "type:x_y:spawnYmd"
  List<String> collection;         // collectibles trouvés à vie (persistant → écran Collection)
  Map<String, String> collectionMeta; // id → 'ymd|provenance' (où/quand obtenu)
  String? lastFreeStepYmd;         // jour du dernier pas gratuit (yyyymmdd)
  String? lastPestDrainAt;         // ISO : dernier drain horaire des nuisibles
  // Or des gains du jour crédité EN TEMPS RÉEL sur le solde (dépensable de suite).
  // `goldTodayGain` = montant flottant déjà crédité pour `goldTodayGainYmd` ;
  // retiré à la clôture (materialize recrédite alors le jour clos).
  int goldTodayGain;
  String? goldTodayGainYmd;
  // Jour de départ de l'économie (posé au reset) : la courbe d'or/XP ignore les
  // jours AVANT cet epoch → on repart de zéro et l'XP remonte à partir d'ici.
  String? goldEpochYmd;
  // Quête du jour : dernier jour où le coffre quotidien a été ouvert (anti-rejeu).
  String? lastQuestClaimedYmd;
  int questStreak; // jours consécutifs où la quête a été accomplie
  // Clés du donjon : routines déjà faites aujourd'hui DÉJÀ utilisées pour franchir
  // un nœud (consommées). Remis à zéro chaque jour (cf. donjonKeysYmd).
  List<String> donjonKeysUsed;
  String? donjonKeysYmd;
  // Défis du donjon préparés par Orion (JSON strings), liés au niveau visé.
  // Écrits par Orion (serveur) ; l'app les lit et auto-valide depuis ses données.
  // {level, type:'routine'|'task'|'time', refId, target, label}
  List<String> expeditionChallenges;
  // Niveau dont le donjon a DÉJÀ été ouvert → on y entre directement ensuite
  // (la 1ʳᵉ fois on passe par l'overworld pour trouver le château). 0 = jamais.
  int expeditionDonjonLevel;
  int expeditionGuardianKilledLevel; // niveau dont le gardien a été vaincu (0=aucun)
  // Combat — modèle stock/munitions : l'arme se GAGNE par la productivité
  // (routine→couteau, tâche→épée, dérivé des données) et se DÉPENSE au kill.
  // On ne persiste que le dépensé (par clé 'couteau'/'epee') et les captures.
  Map<String, int> weaponsSpent; // armes consommées (clé → nombre)
  Map<String, int> pestKills; // captures par type ('spider'/'scorpion'/'snake')
  // Combats ENGAGÉS (épinglés via armes globales) : "type~itemId~sbiresLeft".
  // Apparaissent dans « Combats en cours » jusqu'à ce que l'item soit rattrapé (PV 0).
  List<String> engagedEnemies;
  // Attaquer les cœurs : capacité dérivée de cosmeticsOwned.contains('avatar_ninja')
  // (posséder l'avatar Ninja). Plus de flag dédié — l'avatar EST la capacité.
  Map<String, int> weaponPickups; // armes ramassées sur la carte (clé → count)
  // Social « Le Monde » : jetons de relâche déjà consommés. Disponibles =
  // (captures totales / capturesPerReleaseToken) − releaseTokensUsed.
  int releaseTokensUsed;
  // Invasion / Territoires : ARSENAL de nuisibles rouges craftés, par palier
  // ('spider'/'scorpion'/'serpent') → nombre DISPONIBLE (non déployé). Et nuisibles
  // (du deck lifetime) dépensés au craft, par PALIER → dispo = deck lifetime −
  // craftSpent. Trust-client v1.
  Map<String, int> redRoster;
  Map<String, int> craftSpent;
  // Dégâts au deck vert infligés par un boss PvE ayant franchi (par palier). RÉCUPÉRABLE
  // (on refarme), monotone comme craftSpent : dispo = deck lifetime − craftSpent − deckDamage.
  Map<String, int> deckDamage;
  // Bataille de nuisibles : masse d'armée mintée à vie (1 capture de routine =
  // effort-minutes, plancher 5) et masse déjà dépensée en déploiements.
  // Disponible = battleMasseEarned − battleMasseUsed.
  int battleMasseEarned;
  int battleMasseUsed;
  // Masse gagnée aujourd'hui (« +X aujourd'hui »), remise à 0 au changement de
  // jour via battleMasseTodayYmd.
  int battleMasseToday;
  String battleMasseTodayYmd;
  // Reset du deck d'invasion : les captures de routine dont le jour est ANTÉRIEUR
  // à cette date (YYYY-MM-DD) ne comptent plus dans le deck lifetime (deck propre
  // sans toucher à l'historique réel). '' = pas de reset (tout compte).
  String deckResetYmd;
  // Position des tours de défense de domaine (placement stratégique persisté) :
  // clé "domainId~routineId" → "x_y". Routine absente = retombe en zone de départ.
  Map<String, String> domTurretPos;

  AppState({
    required this.domains,
    required this.activities,
    required this.sessions,
    required this.habitProgress,
    Map<String, String>? snoozedUntil,
    List<InboxItem>? inbox,
    List<String>? focusTodayIds,
    this.sortTodayByDashboard = false,
    this.showTodayPriorities = false,
    this.onboardingDone = false,
    this.lastRolloverYmd,
    this.lastCarryYmd,
    this.lastPrepYmd,
    List<HabitHit>? habitHits,
    List<Redemption>? redemptions,
    Map<String, String>? habitPinnedActivity,
    Map<String, List<String>>? habitChecklistByHabitId,
    List<DayBlock>? blocks,
    List<TodayItem>? todayItems,
    Map<String, List<String>>? disabledBlocksByYmd,
    List<EarnedBadge>? earnedBadges,
    List<String>? skippedChallengeDates,
    this.weeklyScoreTarget = 80,
    this.notifHour = 9,
    this.notifMinute = 0,
    this.notifEnabled = true,
    this.reviewNotifHour = 21,
    this.reviewNotifMinute = 0,
    this.reviewNotifEnabled = true,
    this.streakNotifHour = 20,
    this.streakNotifMinute = 0,
    this.streakNotifEnabled = true,
    this.challengeNotifHour = 16,
    this.challengeNotifMinute = 0,
    this.challengeNotifEnabled = true,
    this.midDayNotifHour = 13,
    this.midDayNotifMinute = 0,
    this.midDayNotifEnabled = true,
    this.domainIdBackfilledOnce = false,
    this.alarmSound = 'default',
    this.challengesDone = 0,
    this.challengeStreak = 0,
    this.lastChallengeYmd,
    Map<String, int>? ganttActionsByDay,
    Map<String, int>? challengeWinsByDay,
    Map<String, int>? battleShurikensByDay,
    this.gold = 0,
    this.goldLifetime = 0,
    this.goldLastProcessedDay,
    Map<String, int>? goldInventory,
    List<String>? goldGelDays,
    List<String>? goldTaskShieldDays,
    List<String>? goldBoostDays,
    List<String>? cosmeticsOwned,
    this.activeTitle,
    this.activeAvatar,
    this.unlockedLevel = 1,
    List<String>? expeditionCleared,
    List<String>? bossInvasions,
    List<String>? expeditionRevealed,
    this.expeditionPos,
    List<String>? unifiedRevealed,
    this.unifiedPos,
    List<String>? unifiedTurrets,
    List<String>? expeditionPicked,
    List<String>? expeditionEntities,
    List<String>? collection,
    Map<String, String>? collectionMeta,
    this.lastFreeStepYmd,
    this.lastPestDrainAt,
    this.goldTodayGain = 0,
    this.goldTodayGainYmd,
    this.goldEpochYmd,
    this.lastQuestClaimedYmd,
    this.questStreak = 0,
    List<String>? donjonKeysUsed,
    this.donjonKeysYmd,
    this.expeditionDonjonLevel = 0,
    this.expeditionGuardianKilledLevel = 0,
    this.releaseTokensUsed = 0,
    this.battleMasseEarned = 0,
    this.battleMasseUsed = 0,
    this.battleMasseToday = 0,
    this.battleMasseTodayYmd = '',
    this.deckResetYmd = '',
    Map<String, String>? domTurretPos,
    Map<String, int>? weaponsSpent,
    Map<String, int>? pestKills,
    Map<String, int>? redRoster,
    Map<String, int>? craftSpent,
    Map<String, int>? deckDamage,
    List<String>? engagedEnemies,
    Map<String, int>? weaponPickups,
    List<String>? expeditionChallenges,
    // ✅ NOUVEAU
    Map<String, List<String>>? nowSkippedByYmd,
    Map<String, List<String>>? nowDoneByYmd,
    Map<String, Map<String, List<int>>>? habitChecklistDone,
    List<ActivityLog>? activityLogs,
    FilterState? filters,
    this.coursesArchivedOnce = false,
    this.linkedActivitiesMigratedOnce = false,
    this.voitureMigratedOnce = false,
    this.coursesRestoredOnce = false,
    this.coursesRestoredV2 = false,
  })  : snoozedUntil = snoozedUntil ?? <String, String>{},
        inbox = inbox ?? <InboxItem>[],
        focusTodayIds = focusTodayIds ?? <String>[],
        habitHits = habitHits ?? <HabitHit>[],
        redemptions = redemptions ?? <Redemption>[],
        habitPinnedActivity = habitPinnedActivity ?? <String, String>{},
        habitChecklistByHabitId =
            habitChecklistByHabitId ?? <String, List<String>>{},
        // ✅ NOUVEAU
        nowSkippedByYmd = nowSkippedByYmd ?? <String, List<String>>{},
        nowDoneByYmd = nowDoneByYmd ?? <String, List<String>>{},
        habitChecklistDone =
            habitChecklistDone ?? <String, Map<String, List<int>>>{},
        activityLogs = activityLogs ?? <ActivityLog>[],
        filters = filters ?? FilterState(),
        blocks = blocks ?? <DayBlock>[],
        todayItems = todayItems ?? <TodayItem>[],
        disabledBlocksByYmd = disabledBlocksByYmd ?? <String, List<String>>{},
        earnedBadges = earnedBadges ?? <EarnedBadge>[],
        skippedChallengeDates = skippedChallengeDates ?? <String>[],
        ganttActionsByDay = ganttActionsByDay ?? <String, int>{},
        challengeWinsByDay = challengeWinsByDay ?? <String, int>{},
        battleShurikensByDay = battleShurikensByDay ?? <String, int>{},
        goldInventory = goldInventory ?? <String, int>{},
        goldGelDays = goldGelDays ?? <String>[],
        goldTaskShieldDays = goldTaskShieldDays ?? <String>[],
        goldBoostDays = goldBoostDays ?? <String>[],
        expeditionCleared = expeditionCleared ?? <String>[],
        bossInvasions = bossInvasions ?? <String>[],
        expeditionRevealed = expeditionRevealed ?? <String>[],
        unifiedRevealed = unifiedRevealed ?? <String>[],
        unifiedTurrets = unifiedTurrets ?? <String>[],
        expeditionPicked = expeditionPicked ?? <String>[],
        expeditionEntities = expeditionEntities ?? <String>[],
        expeditionChallenges = expeditionChallenges ?? <String>[],
        weaponsSpent = weaponsSpent ?? <String, int>{},
        domTurretPos = domTurretPos ?? <String, String>{},
        pestKills = pestKills ?? <String, int>{},
        redRoster = redRoster ?? <String, int>{},
        craftSpent = craftSpent ?? <String, int>{},
        deckDamage = deckDamage ?? <String, int>{},
        engagedEnemies = engagedEnemies ?? <String>[],
        weaponPickups = weaponPickups ?? <String, int>{},
        collection = collection ?? <String>[],
        collectionMeta = collectionMeta ?? <String, String>{},
        donjonKeysUsed = donjonKeysUsed ?? <String>[],
        cosmeticsOwned = cosmeticsOwned ?? <String>[];

  Map<String, dynamic> toJson() => {
        'domains': domains.map((e) => e.toJson()).toList(),
        'activities': activities.map((e) => e.toJson()).toList(),
        'sessions': sessions.map((e) => e.toJson()).toList(),
        'habitProgress': habitProgress.map((e) => e.toJson()).toList(),
        'snoozedUntil': snoozedUntil,
        'inbox': inbox.map((e) => e.toJson()).toList(),

        'lastRolloverYmd': lastRolloverYmd,
        'lastCarryYmd': lastCarryYmd,
        'lastPrepYmd': lastPrepYmd,

        'focusTodayIds': focusTodayIds,
        'sortTodayByDashboard': sortTodayByDashboard,
        'showTodayPriorities': showTodayPriorities,
        'onboardingDone': onboardingDone,

        // ✅ persist
        'habitHits': habitHits.map((e) => e.toJson()).toList(),
        'redemptions': redemptions.map((e) => e.toJson()).toList(),
        'habitPinnedActivity': habitPinnedActivity,

        // ✅ NOW TAB
        'nowSkippedByYmd': nowSkippedByYmd,
        'nowDoneByYmd': nowDoneByYmd,
        'habitChecklistByHabitId': habitChecklistByHabitId,
        'habitChecklistDone': habitChecklistDone,
        'activityLogs': activityLogs.map((e) => e.toJson()).toList(),
        'filters': filters.toJson(),
        'coursesArchivedOnce': coursesArchivedOnce,
        'coursesRestoredOnce': coursesRestoredOnce,
        'coursesRestoredV2': coursesRestoredV2,
        'linkedActivitiesMigratedOnce': linkedActivitiesMigratedOnce,
        'voitureMigratedOnce': voitureMigratedOnce,
        'blocks': blocks.map((e) => e.toJson()).toList(),
        'todayItems': todayItems.map((e) => e.toJson()).toList(),
        'disabledBlocksByYmd': disabledBlocksByYmd,
        'earnedBadges': earnedBadges.map((e) => e.toJson()).toList(),
        'skippedChallengeDates': skippedChallengeDates,
        'challengesDone': challengesDone,
        'challengeStreak': challengeStreak,
        'lastChallengeYmd': lastChallengeYmd,
        'ganttActionsByDay': ganttActionsByDay,
        'challengeWinsByDay': challengeWinsByDay,
        'battleShurikensByDay': battleShurikensByDay,
        'gold': gold,
        'goldLifetime': goldLifetime,
        'goldLastProcessedDay': goldLastProcessedDay,
        'goldInventory': goldInventory,
        'goldGelDays': goldGelDays,
        'goldTaskShieldDays': goldTaskShieldDays,
        'goldBoostDays': goldBoostDays,
        'cosmeticsOwned': cosmeticsOwned,
        'activeTitle': activeTitle,
        'activeAvatar': activeAvatar,
        'unlockedLevel': unlockedLevel,
        'expeditionCleared': expeditionCleared,
        'bossInvasions': bossInvasions,
        'expeditionRevealed': expeditionRevealed,
        'expeditionPos': expeditionPos,
        'unifiedRevealed': unifiedRevealed,
        'unifiedPos': unifiedPos,
        'unifiedTurrets': unifiedTurrets,
        'expeditionPicked': expeditionPicked,
        'expeditionEntities': expeditionEntities,
        'expeditionChallenges': expeditionChallenges,
        'expeditionDonjonLevel': expeditionDonjonLevel,
        'expeditionGuardianKilledLevel': expeditionGuardianKilledLevel,
        'weaponsSpent': weaponsSpent,
        'pestKills': pestKills,
        'redRoster': redRoster,
        'craftSpent': craftSpent,
        'deckDamage': deckDamage,
        'releaseTokensUsed': releaseTokensUsed,
        'battleMasseEarned': battleMasseEarned,
        'battleMasseUsed': battleMasseUsed,
        'battleMasseToday': battleMasseToday,
        'battleMasseTodayYmd': battleMasseTodayYmd,
        'deckResetYmd': deckResetYmd,
        'domTurretPos': domTurretPos,
        'engagedEnemies': engagedEnemies,
        'weaponPickups': weaponPickups,
        'collection': collection,
        'collectionMeta': collectionMeta,
        'lastFreeStepYmd': lastFreeStepYmd,
        'lastPestDrainAt': lastPestDrainAt,
        'goldTodayGain': goldTodayGain,
        'goldTodayGainYmd': goldTodayGainYmd,
        'goldEpochYmd': goldEpochYmd,
        'lastQuestClaimedYmd': lastQuestClaimedYmd,
        'donjonKeysUsed': donjonKeysUsed,
        'donjonKeysYmd': donjonKeysYmd,
        'questStreak': questStreak,
        'weeklyScoreTarget': weeklyScoreTarget,
        'notifHour': notifHour,
        'notifMinute': notifMinute,
        'notifEnabled': notifEnabled,
        'reviewNotifHour': reviewNotifHour,
        'reviewNotifMinute': reviewNotifMinute,
        'reviewNotifEnabled': reviewNotifEnabled,
        'streakNotifHour': streakNotifHour,
        'streakNotifMinute': streakNotifMinute,
        'streakNotifEnabled': streakNotifEnabled,
        'challengeNotifHour': challengeNotifHour,
        'challengeNotifMinute': challengeNotifMinute,
        'challengeNotifEnabled': challengeNotifEnabled,
        'midDayNotifHour': midDayNotifHour,
        'midDayNotifMinute': midDayNotifMinute,
        'midDayNotifEnabled': midDayNotifEnabled,
        'domainIdBackfilledOnce': domainIdBackfilledOnce,
        'alarmSound': alarmSound,
      };

  static AppState from(Map j) {
    Map<String, List<String>> _mapSL(dynamic v) {
      if (v == null) return <String, List<String>>{};
      return (v as Map).map(
        (k, val) => MapEntry(
          k as String,
          (val as List).cast<String>(),
        ),
      );
    }

    Map<String, Map<String, List<int>>> _mapSMapListInt(dynamic v) {
      if (v == null) return <String, Map<String, List<int>>>{};

      final out = <String, Map<String, List<int>>>{};
      (v as Map).forEach((k, vv) {
        final inner = <String, List<int>>{};
        (vv as Map).forEach((kk, list) {
          inner[kk as String] =
              (list as List).map((e) => (e as num).toInt()).toList();
        });
        out[k as String] = inner;
      });
      return out;
    }

    // Helpers safe
    List<T> _list<T>(dynamic v, T Function(dynamic) mapFn) {
      if (v == null) return <T>[];
      return (v as List).map(mapFn).toList();
    }

    Map<String, String> _mapSS(dynamic v) {
      if (v == null) return <String, String>{};
      return (v as Map).map((k, val) => MapEntry(k as String, val as String));
    }

    return AppState(
      domains: _list(j['domains'], (e) => Domain.from(e)),
      activities: _list(j['activities'], (e) => Activity.from(e)),
      sessions: _list(j['sessions'], (e) => Session.from(e)),
      habitProgress: _list(j['habitProgress'], (e) => HabitProgress.from(e)),
      snoozedUntil: _mapSS(j['snoozedUntil']),
      inbox: _list(j['inbox'], (e) => InboxItem.from(e)),
      lastRolloverYmd: j['lastRolloverYmd'] as String?,
      lastCarryYmd: j['lastCarryYmd'] as String?,
      lastPrepYmd: j['lastPrepYmd'] as String?,
      focusTodayIds:
          (j['focusTodayIds'] as List?)?.cast<String>() ?? <String>[],
      sortTodayByDashboard: (j['sortTodayByDashboard'] as bool?) ?? false,
      showTodayPriorities: (j['showTodayPriorities'] as bool?) ?? false,
      onboardingDone: (j['onboardingDone'] as bool?) ?? false,
      habitHits: _list(j['habitHits'], (e) => HabitHit.from(e)),
      redemptions: _list(j['redemptions'], (e) => Redemption.from(e)),
      habitPinnedActivity: _mapSS(j['habitPinnedActivity']),
      nowSkippedByYmd: _mapSL(j['nowSkippedByYmd']),
      nowDoneByYmd: _mapSL(j['nowDoneByYmd']),
      habitChecklistByHabitId: _mapSL(j['habitChecklistByHabitId']),
      habitChecklistDone: _mapSMapListInt(j['habitChecklistDone']),
      filters: FilterState.from(j['filters']),
      coursesArchivedOnce: (j['coursesArchivedOnce'] as bool?) ?? false,
      coursesRestoredOnce: (j['coursesRestoredOnce'] as bool?) ?? false,
      coursesRestoredV2: (j['coursesRestoredV2'] as bool?) ?? false,
      linkedActivitiesMigratedOnce: (j['linkedActivitiesMigratedOnce'] as bool?) ?? false,
      voitureMigratedOnce: (j['voitureMigratedOnce'] as bool?) ?? false,
      blocks: _list(j['blocks'], (e) => DayBlock.from(e)),
      todayItems: _list(j['todayItems'], (e) => TodayItem.from(e)),
      disabledBlocksByYmd: _mapSL(j['disabledBlocksByYmd']),
      earnedBadges: _list(j['earnedBadges'], (e) => EarnedBadge.tryFrom(e))
          .whereType<EarnedBadge>()
          .toList(),
      skippedChallengeDates:
          (j['skippedChallengeDates'] as List?)?.cast<String>() ?? <String>[],
      challengesDone: (j['challengesDone'] as int?) ?? 0,
      challengeStreak: (j['challengeStreak'] as int?) ?? 0,
      lastChallengeYmd: j['lastChallengeYmd'] as String?,
      ganttActionsByDay: (j['ganttActionsByDay'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{},
      challengeWinsByDay: (j['challengeWinsByDay'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{},
      battleShurikensByDay: (j['battleShurikensByDay'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{},
      gold: (j['gold'] as num?)?.toInt() ?? 0,
      goldLifetime: (j['goldLifetime'] as num?)?.toInt() ?? 0,
      goldLastProcessedDay: j['goldLastProcessedDay'] as String?,
      goldInventory: (j['goldInventory'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{},
      goldGelDays: (j['goldGelDays'] as List?)?.cast<String>() ?? <String>[],
      goldTaskShieldDays:
          (j['goldTaskShieldDays'] as List?)?.cast<String>() ?? <String>[],
      goldBoostDays:
          (j['goldBoostDays'] as List?)?.cast<String>() ?? <String>[],
      cosmeticsOwned: (j['cosmeticsOwned'] as List?)?.cast<String>() ?? <String>[],
      activeTitle: j['activeTitle'] as String?,
      activeAvatar: j['activeAvatar'] as String?,
      // 0 = champ absent (doc antérieur au gate) → backfill one-shot au rang acquis.
      unlockedLevel: (j['unlockedLevel'] as num?)?.toInt() ?? 0,
      expeditionCleared:
          (j['expeditionCleared'] as List?)?.cast<String>() ?? <String>[],
      bossInvasions:
          (j['bossInvasions'] as List?)?.cast<String>() ?? <String>[],
      expeditionRevealed:
          (j['expeditionRevealed'] as List?)?.cast<String>() ?? <String>[],
      expeditionPos: j['expeditionPos'] as String?,
      unifiedRevealed:
          (j['unifiedRevealed'] as List?)?.cast<String>() ?? <String>[],
      unifiedPos: j['unifiedPos'] as String?,
      unifiedTurrets:
          (j['unifiedTurrets'] as List?)?.cast<String>() ?? <String>[],
      expeditionPicked:
          (j['expeditionPicked'] as List?)?.cast<String>() ?? <String>[],
      expeditionEntities:
          (j['expeditionEntities'] as List?)?.cast<String>() ?? <String>[],
      expeditionChallenges:
          (j['expeditionChallenges'] as List?)?.cast<String>() ?? <String>[],
      expeditionDonjonLevel: (j['expeditionDonjonLevel'] as num?)?.toInt() ?? 0,
      expeditionGuardianKilledLevel: (j['expeditionGuardianKilledLevel'] as num?)?.toInt() ?? 0,
      weaponsSpent: (j['weaponsSpent'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? <String, int>{},
      pestKills: (j['pestKills'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? <String, int>{},
      redRoster: (j['redRoster'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? <String, int>{},
      craftSpent: (j['craftSpent'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? <String, int>{},
      deckDamage: (j['deckDamage'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? <String, int>{},
      releaseTokensUsed: (j['releaseTokensUsed'] as num?)?.toInt() ?? 0,
      battleMasseEarned: (j['battleMasseEarned'] as num?)?.toInt() ?? 0,
      battleMasseUsed: (j['battleMasseUsed'] as num?)?.toInt() ?? 0,
      battleMasseToday: (j['battleMasseToday'] as num?)?.toInt() ?? 0,
      battleMasseTodayYmd: (j['battleMasseTodayYmd'] as String?) ?? '',
      deckResetYmd: (j['deckResetYmd'] as String?) ?? '',
      domTurretPos: (j['domTurretPos'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          <String, String>{},
      engagedEnemies: (j['engagedEnemies'] as List?)?.cast<String>() ?? <String>[],
      weaponPickups: (j['weaponPickups'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? <String, int>{},
      collection: (j['collection'] as List?)?.cast<String>() ?? <String>[],
      collectionMeta: (j['collectionMeta'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? <String, String>{},
      lastFreeStepYmd: j['lastFreeStepYmd'] as String?,
      lastPestDrainAt: j['lastPestDrainAt'] as String?,
      goldTodayGain: (j['goldTodayGain'] as num?)?.toInt() ?? 0,
      goldTodayGainYmd: j['goldTodayGainYmd'] as String?,
      goldEpochYmd: j['goldEpochYmd'] as String?,
      lastQuestClaimedYmd: j['lastQuestClaimedYmd'] as String?,
      donjonKeysUsed: (j['donjonKeysUsed'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      donjonKeysYmd: j['donjonKeysYmd'] as String?,
      questStreak: (j['questStreak'] as num?)?.toInt() ?? 0,
      weeklyScoreTarget: (j['weeklyScoreTarget'] as int?) ?? 80,
      notifHour: (j['notifHour'] as int?) ?? 9,
      notifMinute: (j['notifMinute'] as int?) ?? 0,
      notifEnabled: (j['notifEnabled'] as bool?) ?? true,
      reviewNotifHour: (j['reviewNotifHour'] as int?) ?? 21,
      reviewNotifMinute: (j['reviewNotifMinute'] as int?) ?? 0,
      reviewNotifEnabled: (j['reviewNotifEnabled'] as bool?) ?? true,
      streakNotifHour: (j['streakNotifHour'] as int?) ?? 20,
      streakNotifMinute: (j['streakNotifMinute'] as int?) ?? 0,
      streakNotifEnabled: (j['streakNotifEnabled'] as bool?) ?? true,
      challengeNotifHour: (j['challengeNotifHour'] as int?) ?? 16,
      challengeNotifMinute: (j['challengeNotifMinute'] as int?) ?? 0,
      challengeNotifEnabled: (j['challengeNotifEnabled'] as bool?) ?? true,
      midDayNotifHour: (j['midDayNotifHour'] as int?) ?? 13,
      midDayNotifMinute: (j['midDayNotifMinute'] as int?) ?? 0,
      midDayNotifEnabled: (j['midDayNotifEnabled'] as bool?) ?? true,
      domainIdBackfilledOnce: (j['domainIdBackfilledOnce'] as bool?) ?? false,
      alarmSound: (j['alarmSound'] as String?) ?? 'default',
    );
  }

  String encode() => jsonEncode(toJson());

  static AppState decode(String s) {
    final t = s.trim();
    if (t.isEmpty) {
      // retourne un état vide (ou tu peux appeler ton _seedMinimal ailleurs)
      return AppState(
        domains: <Domain>[],
        activities: <Activity>[],
        sessions: <Session>[],
        habitProgress: <HabitProgress>[],
      );
    }

    try {
      return from(jsonDecode(t));
    } catch (_) {
      return AppState(
        domains: <Domain>[],
        activities: <Activity>[],
        sessions: <Session>[],
        habitProgress: <HabitProgress>[],
      );
    }
  }
}
