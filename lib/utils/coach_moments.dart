import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/evening_verdict.dart';
import 'package:productivitwo_v1/utils/routine_context.dart';

// ─── CARTE COACH « MAINTENANT » ──────────────────────────────────────────────
//
// Fonction pure, testable unitairement : à partir de l'heure courante, de l'état
// et des programmes du jour / de la veille + des sessions récentes, elle calcule
// LE moment de coaching à afficher. Aucun appel réseau ni LLM — les textes sont
// des templates avec les chiffres RÉELS (jamais inventés ; une donnée absente est
// omise, pas remplie). Le déterministe relance, fiable et à coût zéro.

enum CoachTone { neutral, positive, alert }

enum CoachMomentType {
  wake,
  morning,
  unplanned, // matin sans programme → CTA « Planifier · 2 min » (maquette 5a)
  midday,
  drift,
  afternoon,
  evening,
  weekly, // dimanche soir : teaser du rapport hebdo (maquette 16a)
  defineNudge, // domaines absents/nommés → l'app invite (Partie D, 21a-21c)
  chain, // un chrono vient de finir → « Et ensuite ? » (enchaînement immédiat)
  idealHour, // routine quotidienne juste après son heure habituelle, pas cochée
  microTarget, // cible restée au défaut (< 10 min) mais activité vécue → question
  hidden,
}

/// Une action proposée par la carte. [block] cible le bloc concerné (chrono
/// ciblé, renégociation…) ; [target] est le moment visé par une transition
/// manuelle (CTA « Attaquer la journée », « Pause de midi »…).
enum CoachActionKind {
  launchBlock,
  openDayReview,
  renegotiate,
  advanceMoment,
  planDay, // ouvre l'écran de planification (rattrapage du matin)
  dismiss, // « À la volée » / « Garder [créneau] » — masque la carte du jour
  mealEaten, // ✓ Mangé (carte midi menu, 15c)
  mealShift, // « Autre chose aujourd'hui » — glisse le menu d'un jour
  openWeeklyReport, // « Lire le rapport — 3 min » (16a)
  // ── Partie D — nudge domaines (21a-21c / 22a-22c) ──────────────────────────
  nameDomains, // ouvre le sheet de nommage in-place (22a)
  nameTonight, // « Ce soir plutôt » — pose un bloc « nommer » dans le programme
  startSession, // « Faire la session maintenant — 15 min » (domain)
  startSessionShort, // « Version courte — 8 min » (21c, intention + vital)
  poseSessions, // « Plus tard » — pose les sessions restantes (mécanique 18b)
  // ── Phase 5 — contrôle direct (23b/23c) ────────────────────────────────────
  endAfternoon, // bascule système EXPLICITE en mode soirée (réversible)
  availableNow, // « Je suis dispo » — efface la fenêtre d'indisponibilité
  planNext, // « Planifions » — pose la prochaine exécution d'une routine
  // ── Défi ORION dans la carte ────────────────────────────────────────────────
  challengeAccept, // « Je relève 🔥 » — chrono + minuteur-alarme + streak
  challengeSchedule, // « Programmer 📅 » — défi daté dans le programme
  checkRoutine, // ✓ — coche une routine sans minuteur (pas de chrono)
  // ── Gantt invisible — GTD minimaliste (micro-projet) ────────────────────────
  defineSteps, // la tâche n'a pas d'étape → définir la prochaine petite action
  scheduleStep, // programmer l'étape au moment où le user sera dispo pour elle
  // ── Réglage micro-cible (carte « ORION · RÉGLAGE ») ─────────────────────────
  keepMicroTarget, // « c'est un déclencheur voulu » → épingle (targetSource user)
  calibrateTarget, // « cale sur mon réel » → cible = mesuré 30 j (source orion)
}

class CoachAction {
  final String label;
  final CoachActionKind kind;
  final ScheduleBlock? block;
  final CoachMomentType? target;
  final String? artifactId; // menu concerné (mealEaten / mealShift)
  final String? domain; // domaine visé (startSession / startSessionShort)
  const CoachAction(this.label, this.kind,
      {this.block, this.target, this.artifactId, this.domain});
}

class StatItem {
  final String label;
  final String value;
  final String? sub;
  const StatItem(this.label, this.value, {this.sub});
}

/// Défi ORION prêt à afficher — calculé par l'appelant depuis le réel
/// (AppLogic.challengeActivity + challengeDurationFor) : l'activité-temps la
/// plus en retard sur sa cible du JOUR. La carte n'applique que les règles de
/// moment (retard franc, trou suffisant, une sollicitation par jour).
class ChallengeProposal {
  final Activity activity;
  final int minutes; // durée suggérée (reste vers la cible, borné 10-45)
  final int doneMin; // minutes réellement logguées aujourd'hui
  final int targetMin; // cible du jour (goalMin)
  final int streak; // jours consécutifs avec ≥ 1 défi relevé
  const ChallengeProposal(
      {required this.activity,
      required this.minutes,
      required this.doneMin,
      required this.targetMin,
      this.streak = 0});
}

class CoachMoment {
  final CoachMomentType type;
  final String tagLabel; // micro-label émeraude/gris (« ORION · RÉVEIL »)
  final String? title;
  final String message;
  final List<StatItem> stats;
  final List<CoachAction> actions;
  final CoachTone tone;
  // Chips domaines du nudge (21b) : « Santé ✓ · Business · Perso ».
  final List<({String label, bool done})> chips;

  const CoachMoment({
    required this.type,
    required this.tagLabel,
    this.title,
    required this.message,
    this.stats = const [],
    this.actions = const [],
    this.tone = CoachTone.neutral,
    this.chips = const [],
  });

  bool get hidden => type == CoachMomentType.hidden;

  static const CoachMoment none = CoachMoment(
      type: CoachMomentType.hidden, tagLabel: '', message: '');
}

// ── Point d'entrée ────────────────────────────────────────────────────────────

/// [advancedTo] = avance manuelle via le CTA de transition de la carte
/// (« Attaquer la journée », « Pause de midi »…) : le user peut faire avancer
/// la journée AVANT l'horloge (levé à 5h → carte matin sans attendre 9h).
/// L'avance ne peut jamais reculer, et l'horloge la rattrape naturellement.
/// [unplannedDismissed] : le user a tapé « À la volée » sur la carte
/// « journée non planifiée » — on ne la re-propose pas de la matinée.
/// [sessionSkipCount] : sessions de définition sautées/reportées (14 jours) —
/// déclenche l'escalade factuelle 21c à partir de 2. [nextSessionLabel] :
/// prochaine session posée (« demain 18 h 30 »), calculée par l'appelant.
/// [nudgeDismissed] : « Garder [créneau] » / « Ce soir plutôt » — le nudge se
/// tait pour la journée (le bloc posé prend le relais).
CoachMoment computeCoachMoment(
  DateTime now,
  AppState st,
  DailySchedule? today,
  DailySchedule? yesterday,
  List<Session> recentSessions, {
  CoachMomentType? advancedTo,
  bool unplannedDismissed = false,
  List<Artifact> artifacts = const [],
  WeeklyReport? weeklyReport,
  int sessionSkipCount = 0,
  String? nextSessionLabel,
  bool nudgeDismissed = false,
  bool microTargetDismissed = false,
  // Une renégociation vient d'être faite : la carte dérive RESPIRE (~45 min,
  // géré par l'appelant) — pas de rafale « dérive suivante » juste après
  // avoir trié la précédente (constaté sur build). Le check-in rattrape tout.
  bool driftSnoozed = false,
  ChallengeProposal? challenge,
  GanttMicroAction? ganttAction,
}) {
  final minutes = now.hour * 60 + now.minute;
  // Défi ORION proactif : une sollicitation par jour maximum — passé
  // (skippedChallengeDates) ou déjà relevé aujourd'hui = silence. Le bouton
  // et la chip du guide restent disponibles à la demande, eux.
  final ymdCompact =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  final chal = challenge != null &&
          !st.skippedChallengeDates.contains(ymdCompact) &&
          !st.challengeWinsByDay.containsKey(ymdCompact)
      ? challenge
      : null;
  final blocks = _liveBlocks(today);
  final sessionsToday =
      recentSessions.where((s) => _sameDay(s.startAt, now)).toList();
  // Minimum vital hebdo des domaines définis — affiché midi et soir.
  final vitals = _vitalStats(now, st, recentSessions);
  // Repas du jour du menu (15c) — zéro décision à midi.
  final meal = _todayMeal(now, artifacts);

  // 00h–1h : fin de soirée pour les couche-tard — même carte check-in, mais le
  // doc du jour a basculé à minuit : les blocs prep « de ce soir » vivent dans
  // le programme d'HIER (et leur bloc cible est désormais ce matin). Une pause
  // posée hier soir (« pas aujourd'hui » → jusqu'à 5 h) vit sur le doc d'HIER.
  if (minutes < 60) {
    if (yesterday?.unavailableAt(now) == true) return CoachMoment.none;
    return _eveningMoment(_liveBlocks(yesterday), const [],
        reviewedAt: yesterday?.reviewedAt);
  }
  if (minutes < 5 * 60) return CoachMoment.none; // nuit (1h–5h)

  // Pause déclarée (« pas dispo avant X ») : le coach SUIT LE FLOW — AUCUNE
  // carte, aucune relance (nudge, défi ET check-in du soir compris) avant
  // l'heure dite. Le guide « que souhaites-tu faire ? » prend la place : lui
  // est PULL, pas push. L'état et la sortie de pause vivent sur le bouton ⏸
  // de l'en-tête ; le check-in redevient possible dès la fin de la fenêtre.
  if (today?.unavailableAt(now) == true) {
    return CoachMoment.none;
  }

  // ── Nudge domaines (Partie D) : prioritaire sur les moments horaires tant
  // qu'un domaine est absent ou seulement nommé. Le teaser du rapport (16a)
  // garde le dimanche soir — la semaine se juge avant de se nudger.
  // Le teaser du rapport ne vaut que tant que le rapport n'est pas LU — une
  // fois lu (fait readAt), la soirée reprend son cours normal : le rapport
  // n'est pas forcément la dernière chose de la journée.
  final unreadReport = weeklyReport != null && weeklyReport.readAt == null;
  final sundayReport =
      now.weekday == DateTime.sunday && minutes >= 19 * 60 && unreadReport;
  if (!nudgeDismissed && !sundayReport) {
    final nudge = _defineNudge(now, st, sessionSkipCount, nextSessionLabel);
    if (nudge != null) return nudge;
  }

  // Mode soirée (23c) : la journée est pliée tôt — assumé, réversible. Avant
  // 19 h la carte le dit explicitement ; après, la soirée normale reprend.
  if (today?.eveningMode == true && minutes < 19 * 60) {
    return _eveningModeMoment(today!, blocks, vitals);
  }

  // « Et ensuite ? » : un chrono vient de se terminer (≤ 10 min) — le moment
  // le plus précieux pour enchaîner. Avant 19 h seulement (check-in sacré).
  if (minutes < 19 * 60) {
    final chain =
        _chainMoment(now, st, blocks, recentSessions, challenge: chal);
    if (chain != null) return chain;
  }

  // « Journée non planifiée » (5a) : matinée sans programme (hors preps) →
  // prime sur les templates réveil/matin, sous la dérive (après-midi de toute
  // façon). Masquée après « À la volée ».
  if (minutes < 11 * 60 + 45 &&
      !unplannedDismissed &&
      blocks.where((b) => !b.isPrep).isEmpty) {
    return const CoachMoment(
      type: CoachMomentType.unplanned,
      tagLabel: 'ORION · MATIN',
      title: 'Journée non planifiée',
      message:
          'Rien n\'est posé pour aujourd\'hui. 2 minutes maintenant et la journée a une colonne vertébrale.',
      actions: [
        CoachAction('Planifier · 2 min', CoachActionKind.planDay),
        CoachAction('À la volée', CoachActionKind.dismiss),
      ],
      tone: CoachTone.neutral,
    );
  }

  // Moment « horloge ». drift prime sur afternoon dans sa fenêtre (14–19h).
  final CoachMoment clock;
  if (minutes >= 19 * 60) {
    // Dimanche soir : le rapport hebdo prime sur le check-in (16a) — la
    // semaine se juge avant de se clore. Une fois LU, le check-in reprend.
    clock = (now.weekday == DateTime.sunday && unreadReport)
        ? _weeklyTeaser(weeklyReport)
        : _eveningMoment(blocks, vitals, reviewedAt: today?.reviewedAt);
  } else if (minutes >= 14 * 60) {
    clock = (driftSnoozed ? null : _driftMoment(now, st, blocks, sessionsToday)) ??
        _idealHourMoment(now, st, blocks) ??
        _afternoonMoment(now, st, blocks, recentSessions,
            challenge: chal, gantt: ganttAction);
  } else if (minutes >= 11 * 60 + 45) {
    clock = _middayMoment(now, blocks, recentSessions, vitals, meal);
  } else if (minutes >= 9 * 60) {
    clock = _idealHourMoment(now, st, blocks) ??
        (microTargetDismissed
            ? null
            : _microTargetMoment(now, st, recentSessions)) ??
        _morningMoment(now, st, blocks);
  } else {
    clock = _idealHourMoment(now, st, blocks) ??
        _wakeMoment(now, st, blocks, yesterday, today);
  }

  // Avance manuelle : ne s'applique que si elle est PLUS LOIN dans la journée
  // que l'horloge (sinon elle est périmée). Avancer en soirée fait aussi taire
  // une éventuelle dérive (le user a explicitement clos son après-midi).
  if (advancedTo != null && _dayOrder(advancedTo) > _dayOrder(clock.type)) {
    switch (advancedTo) {
      case CoachMomentType.morning:
        return _morningMoment(now, st, blocks);
      case CoachMomentType.midday:
        return _middayMoment(now, blocks, recentSessions, vitals, meal);
      case CoachMomentType.afternoon:
        return _afternoonMoment(now, st, blocks, recentSessions,
            challenge: chal, gantt: ganttAction);
      case CoachMomentType.evening:
        return _eveningMoment(blocks, vitals, reviewedAt: today?.reviewedAt);
      default:
        break;
    }
  }
  return clock;
}

/// Position de chaque moment dans le déroulé de la journée (drift et afternoon
/// partagent la même fenêtre).
int _dayOrder(CoachMomentType t) => switch (t) {
      CoachMomentType.wake => 0,
      CoachMomentType.morning => 1,
      CoachMomentType.unplanned => 1,
      CoachMomentType.midday => 2,
      CoachMomentType.drift => 3,
      CoachMomentType.afternoon => 3,
      CoachMomentType.idealHour => 3, // seule la soirée passe devant
      CoachMomentType.microTarget => 1, // question du matin — tout la dépasse

      CoachMomentType.evening => 4,
      CoachMomentType.weekly => 4,
      CoachMomentType.defineNudge => 5, // hors déroulé — jamais dépassé
      CoachMomentType.chain => 5, // hors déroulé — fenêtre de 10 min
      CoachMomentType.hidden => -1,
    };

// ── Nudge domaines (Partie D, maquettes 21a-21c) ─────────────────────────────
//
// Le trou entre « le modèle domaine existe » et « le user pense à s'en
// servir » : si rien n'est défini, c'est l'app qui invite, dans Maintenant,
// et tout se fait sur place. Templates déterministes, chiffres réels. 0 LLM.

CoachMoment? _defineNudge(
    DateTime now, AppState st, int skips, String? nextLabel) {
  final domains = st.domains.where((d) => !d.deleted).toList();
  final named =
      domains.where((d) => d.definitionStatus == 'named').toList();
  final started = domains
      .where((d) =>
          d.definitionStatus == 'active' || d.definitionStatus == 'draft')
      .toList();

  // 21a — rien n'est nommé ni défini : le programme ne peut pas exister.
  if (named.isEmpty && started.isEmpty) {
    return const CoachMoment(
      type: CoachMomentType.defineNudge,
      tagLabel: 'ORION · À FAIRE UNE FOIS',
      message:
          'Je peux te planifier des journées — mais pour l\'instant je ne sais pas ce qui compte pour toi. Donne-moi tes 2 ou 3 domaines, ici même : 2 minutes, et je commence à travailler.',
      actions: [
        CoachAction('Nommer mes domaines — 2 min', CoachActionKind.nameDomains),
        CoachAction('Ce soir plutôt — pose-le dans mon programme',
            CoachActionKind.nameTonight),
      ],
    );
  }
  if (named.isEmpty) return null; // tout est défini ou en session — silence

  final first = named.first;
  final active = domains.where((d) => d.isDefined).toList();
  final chips = <({String label, bool done})>[
    for (final d in [...active, ...started.where((d) => !d.isDefined), ...named])
      (label: d.name, done: d.isDefined),
  ];
  final total = chips.length;

  // 21c — ≥ 2 reports : escalade FACTUELLE uniquement, jamais de morale.
  if (skips >= 2) {
    final namedDays =
        first.namedAt != null ? now.difference(first.namedAt!).inDays : null;
    final planned = active.isNotEmpty
        ? 'tes journées ne contiennent que ${active.map((d) => d.name).join(' et ')}'
        : 'je planifie sans lui';
    return CoachMoment(
      type: CoachMomentType.defineNudge,
      tagLabel: 'ORION · SESSION EN ATTENTE · $skips REPORTS',
      message:
          '${first.name} est nommé${namedDays != null ? ' depuis $namedDays j' : ''} et sa session a sauté $skips fois. Résultat concret : $planned. Version courte, ici : intention + minimum vital, le reste plus tard.',
      stats: [
        if (namedDays != null) StatItem('Nommé depuis', '$namedDays j'),
        StatItem('Sessions sautées', '$skips'),
        if (nextLabel == null) StatItem('Bloc ${first.name} posé', '0'),
      ],
      actions: [
        CoachAction('Version courte — 8 min', CoachActionKind.startSessionShort,
            domain: first.name),
        const CoachAction('Reposer un créneau', CoachActionKind.poseSessions),
      ],
      tone: CoachTone.alert,
      chips: chips,
    );
  }

  // 22c — tout juste nommé, rien de posé : on enchaîne sur le rang 1.
  if (active.isEmpty && started.isEmpty && nextLabel == null) {
    return CoachMoment(
      type: CoachMomentType.defineNudge,
      tagLabel: 'ORION · LA SUITE · 0 DÉFINI / $total',
      message:
          'Nommer, c\'est fait. Définir, c\'est ce qui me rend utile : intention + minimum vital. On commence par ${first.name} — c\'est toi qui l\'as mis en 1.',
      actions: [
        CoachAction('Définir « ${first.name} » — 15 min',
            CoachActionKind.startSession, domain: first.name),
        CoachAction(
            'Plus tard — pose les ${named.length} sessions dans ma semaine',
            CoachActionKind.poseSessions),
      ],
      chips: chips,
    );
  }

  // 21b — nommés, session en attente.
  return CoachMoment(
    type: CoachMomentType.defineNudge,
    tagLabel: 'ORION · SESSION EN ATTENTE · ${active.length} DÉFINI / $total',
    message:
        '${first.name} attend sa session${nextLabel != null ? ' — elle est posée $nextLabel' : ''}. Si tu as 15 min, on la fait ici, tout de suite. Tant qu\'il n\'est pas défini, je planifie sans lui.',
    actions: [
      CoachAction('Faire la session maintenant — 15 min',
          CoachActionKind.startSession, domain: first.name),
      nextLabel != null
          ? CoachAction('Garder $nextLabel', CoachActionKind.dismiss)
          : CoachAction(
              'Plus tard — pose les ${named.length} sessions dans ma semaine',
              CoachActionKind.poseSessions),
    ],
    chips: chips,
  );
}

// ── Moments ───────────────────────────────────────────────────────────────────

CoachMoment _wakeMoment(DateTime now, AppState st, List<ScheduleBlock> blocks,
    DailySchedule? yesterday, DailySchedule? today) {
  final todayStr = _ymd(now);
  final first = _firstEngagement(now, blocks);
  final prepReady = _prepReadyFrom(yesterday, todayStr);

  final stats = <StatItem>[];
  if (prepReady) {
    stats.add(const StatItem('Préparation', '✓ prêtes depuis hier'));
  }

  final actions = <CoachAction>[];
  String message;
  if (first != null) {
    final mins = _minutesUntil(now, first.startTime);
    final whenStr = _inFr(mins);
    stats.add(StatItem('Premier bloc', _hhmmToFr(first.startTime),
        sub: first.title));
    final prepSuffix =
        prepReady ? ', les affaires sont prêtes depuis hier' : '';
    message =
        'Là tout de suite : ${first.title} $whenStr$prepSuffix. On y va tranquille.';
    if (_launchable(first) && mins <= 90) {
      actions.add(CoachAction('Lancer', CoachActionKind.launchBlock,
          block: first));
    }
    // Trou avant le premier bloc : une routine qui tient dedans, la plus
    // proche de son heure habituelle en premier.
    if (mins >= 60) {
      final f = gapFillers(now, st, mins, blocks: blocks).firstOrNull;
      if (f != null) {
        message = '$message ${_fillerText(f, hasNext: true)}';
        actions.add(_fillerAction(now, f));
      }
    }
  } else {
    message = prepReady
        ? 'Journée libre côté programme — mais les affaires sont prêtes depuis hier, prêt à démarrer.'
        : 'Nouvelle journée. Prends une minute pour poser ton premier bloc.';
  }
  actions.add(const CoachAction('Attaquer la journée',
      CoachActionKind.advanceMoment,
      target: CoachMomentType.morning));

  return CoachMoment(
    type: CoachMomentType.wake,
    tagLabel: 'ORION · RÉVEIL',
    message: message,
    stats: stats,
    actions: actions,
    tone: CoachTone.neutral,
  );
}

CoachMoment _morningMoment(
    DateTime now, AppState st, List<ScheduleBlock> blocks) {
  const advance = CoachAction('Pause de midi', CoachActionKind.advanceMoment,
      target: CoachMomentType.midday);
  // Prochain engagement et trou avant lui (jusqu'à midi si rien n'est posé).
  final next = _firstEngagement(now, blocks);
  final gap = next != null
      ? _minutesUntil(now, next.startTime)
      : 12 * 60 - (now.hour * 60 + now.minute);
  final filler = gap >= 60
      ? gapFillers(now, st, gap, blocks: blocks).firstOrNull
      : null;

  final firstDone = _firstDoneEngagement(blocks);
  if (firstDone != null) {
    final at = firstDone.doneAt;
    final atStr = at != null ? ' à ${_hhmmToFr(_hm(at))}' : '';
    var message =
        '${firstDone.title} fait$atStr — la journée est lancée, c\'est ça qu\'on voulait.';
    final actions = <CoachAction>[];
    if (filler != null) {
      message = '$message ${_fillerText(filler, hasNext: next != null)}';
      actions.add(_fillerAction(now, filler));
    }
    actions.add(advance);
    return CoachMoment(
      type: CoachMomentType.morning,
      tagLabel: 'ORION · MATIN',
      message: message,
      actions: actions,
      tone: CoachTone.positive,
    );
  }
  // Carte réduite : le prochain bloc seulement.
  final actions = <CoachAction>[];
  String message;
  final stats = <StatItem>[];
  if (next != null) {
    final whenStr = _inFr(gap);
    stats.add(StatItem('Prochain', _hhmmToFr(next.startTime), sub: next.title));
    message = 'Prochain rendez-vous : ${next.title} $whenStr.';
    if (_launchable(next) && gap <= 90) {
      actions.add(
          CoachAction('Lancer', CoachActionKind.launchBlock, block: next));
    }
  } else {
    message = 'Matinée libre. Choisis une chose à faire avancer.';
  }
  if (filler != null) {
    message = '$message ${_fillerText(filler, hasNext: next != null)}';
    actions.add(_fillerAction(now, filler));
  }
  actions.add(advance);
  return CoachMoment(
    type: CoachMomentType.morning,
    tagLabel: 'ORION · MATIN',
    message: message,
    stats: stats,
    actions: actions,
    tone: CoachTone.neutral,
  );
}

CoachMoment _middayMoment(DateTime now, List<ScheduleBlock> blocks,
    List<Session> recentSessions, List<StatItem> vitals, _MealInfo? meal) {
  final dayStart = DateTime(now.year, now.month, now.day);
  final noon = dayStart.add(const Duration(hours: 12));
  final loggedBeforeNoon =
      _loggedMinutesInWindow(recentSessions, dayStart, noon);

  // Blocs tenus avant midi (done / total des blocs matinaux).
  final morningBlocks = blocks
      .where((b) => _blockStart(b, now).isBefore(noon))
      .toList();
  final held = morningBlocks.where((b) => b.status == 'done').length;

  // Rang de la matinée sur 7 jours (somme des minutes matinales par jour).
  final rank = _morningRank(now, recentSessions, loggedBeforeNoon);

  final stats = <StatItem>[
    StatItem('Loggué avant 12h', _fmtDur(loggedBeforeNoon)),
    StatItem('Blocs tenus', '$held/${morningBlocks.length}'),
    if (rank != null) StatItem('Matinée', '#$rank / 7 j'),
    ...vitals,
  ];

  final key = _afternoonKeyBlock(now, blocks);
  // Le soir n'est pas l'affaire de l'après-midi : mention factuelle à part.
  final evening = _eveningPreview(now, blocks);
  final eveningNote = evening != null
      ? ' Ce soir : ${evening.title} à ${_hhmmToFr(evening.startTime)}.'
      : '';
  var message = key != null
      ? 'L\'après-midi n\'a qu\'une chose à tenir : ${key.title}. Tout le reste est du bonus.$eveningNote'
      : 'Belle matinée. L\'après-midi est à toi.$eveningNote';

  final actions = <CoachAction>[];
  // Repas du menu (15c) : « zéro décision » — le fait mangé/autre est tracké.
  if (meal != null) {
    message =
        '${meal.title} au frigo — réchauffe 10 min, zéro décision. $message';
    if (meal.weeklyTarget > 0) {
      stats.add(StatItem('Repas cuisinés',
          '${meal.eatenThisWeek}/${meal.weeklyTarget}'));
    }
    actions.add(CoachAction('✓ Mangé', CoachActionKind.mealEaten,
        artifactId: meal.artifactId));
    actions.add(CoachAction('Autre chose aujourd\'hui',
        CoachActionKind.mealShift,
        artifactId: meal.artifactId));
  }
  if (key != null &&
      _launchable(key) &&
      _minutesUntil(now, key.startTime) <= 90) {
    actions
        .add(CoachAction('Lancer', CoachActionKind.launchBlock, block: key));
  }
  actions.add(const CoachAction('Attaquer l\'aprèm',
      CoachActionKind.advanceMoment,
      target: CoachMomentType.afternoon));

  return CoachMoment(
    type: CoachMomentType.midday,
    tagLabel: 'ORION · RAPPORT DE MATINÉE',
    message: message,
    stats: stats,
    actions: actions,
    tone: CoachTone.positive,
  );
}

// ── Repas du jour (menu, maquette 15c) ────────────────────────────────────────

class _MealInfo {
  final String artifactId;
  final String title;
  final int eatenThisWeek;
  final int weeklyTarget;
  _MealInfo(this.artifactId, this.title, this.eatenThisWeek, this.weeklyTarget);
}

/// Le repas prévu aujourd'hui par le menu actif : entrée datée du jour ou motif
/// hebdo du jour de semaine, non encore loggée (mangé/autre). Null si pas de
/// menu, pas de repas prévu, ou déjà tranché — la carte n'invente rien.
_MealInfo? _todayMeal(DateTime now, List<Artifact> artifacts) {
  final todayStr = _ymd(now);
  const codes = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final wd = codes[now.weekday - 1];
  for (final a in artifacts) {
    if (a.deleted || a.kind != 'weekly_menu') continue;
    if (a.mealLog[todayStr] != null) return null; // déjà tranché aujourd'hui
    ArtifactEntry? entry;
    for (final e in a.entries) {
      if (e.date == todayStr || (e.date == null && e.weekday == wd)) {
        entry = e;
        break;
      }
    }
    if (entry == null) continue;
    // Semaine courante (lundi → dim.) : repas mangés / cible = nb de repas du
    // motif hebdo (à défaut, les entrées datées de la semaine).
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    var eaten = 0;
    a.mealLog.forEach((date, v) {
      final d = DateTime.tryParse(date);
      if (v == 'eaten' && d != null && !d.isBefore(monday)) eaten++;
    });
    final weeklyCount = a.entries.where((e) => e.weekday != null).length;
    return _MealInfo(a.id, entry.title, eaten,
        weeklyCount > 0 ? weeklyCount : 0);
  }
  return null;
}

/// Retourne un moment `drift` si un bloc source est posé depuis > 45 min avec
/// 0 min logguée, sinon null.
CoachMoment? _driftMoment(DateTime now, AppState st,
    List<ScheduleBlock> blocks, List<Session> sessionsToday) {
  ScheduleBlock? drifting;
  DateTime? driftStart;
  for (final b in blocks) {
    if (b.status != 'pending') continue;
    if (b.activityId == null && b.taskId == null) continue;
    final start = _blockStart(b, now);
    if (now.difference(start).inMinutes <= 45) continue;
    // Bloc-routine : l'engagement se tient AUSSI par le temps loggué sur
    // l'activité-temps LIÉE (« Prier » routine ↔ « Prière » activité —
    // constaté sur build : 9 min priées, carte à « 0 min logguée »), et par
    // une COCHE de la routine aujourd'hui — dans les deux cas, pas de dérive.
    Activity? act;
    for (final a in st.activities) {
      if (a.id == b.activityId) {
        act = a;
        break;
      }
    }
    final extraIds = <String>{
      if (act != null &&
          act.isHabit &&
          (act.linkedActivityId ?? '').trim().isNotEmpty)
        act.linkedActivityId!.trim(),
    };
    if (act != null &&
        act.isHabit &&
        st.habitHits.any((h) => h.habitId == act!.id && _sameDay(h.ts, now))) {
      continue; // routine tenue aujourd'hui — l'engagement est honoré
    }
    final logged =
        _blockLoggedMin(b, sessionsToday, start, now, extraIds: extraIds);
    if (logged > 0) continue;
    if (driftStart == null || start.isBefore(driftStart)) {
      drifting = b;
      driftStart = start;
    }
  }
  if (drifting == null || driftStart == null) return null;

  // « 25 min » n'a aucun sens pour un bloc d'1 min (vitamines) : le CTA
  // s'aligne sur la durée RÉELLE du bloc, plafonnée à 25.
  final relance =
      drifting.durationMin < 25 ? drifting.durationMin : 25;
  final actions = <CoachAction>[
    if (_launchable(drifting))
      CoachAction('Lancer $relance min', CoachActionKind.launchBlock,
          block: drifting),
    CoachAction('Renégocier', CoachActionKind.renegotiate, block: drifting),
  ];

  return CoachMoment(
    type: CoachMomentType.drift,
    tagLabel: 'ORION · DÉRIVE DÉTECTÉE',
    title: drifting.title,
    message:
        'Le bloc « ${drifting.title} » est posé depuis ${_hhmmToFr(drifting.startTime)} — 0 min logguée. ${relance == 1 ? '1 minute suffit' : '$relance minutes suffisent'} pour l\'enclencher.',
    actions: actions,
    tone: CoachTone.alert,
  );
}

// ── Défi ORION dans la carte ─────────────────────────────────────────────────

/// Fragment de message du défi : chiffres réels (durée suggérée, manque vers
/// la cible du jour).
String _challengeText(ChallengeProposal c) =>
    'ORION te défie : ${c.minutes} min de « ${c.activity.name} » — il en manque ${c.targetMin - c.doneMin} vers ta cible du jour.';

/// Bloc porteur du défi (activityId + durée) pour les handlers de la carte.
ScheduleBlock _challengeBlock(ChallengeProposal c) => ScheduleBlock(
    startTime: '00:00',
    durationMin: c.minutes,
    title: c.activity.name,
    category: 'personal',
    activityId: c.activity.id);

// ── « Et ensuite ? » : enchaînement immédiat après un chrono terminé ─────────
//
// Le moment où le user vient de finir quelque chose est le plus propice à
// enchaîner : la carte le dit avec les faits (ce qui vient d'être fait, durée)
// et propose UNE suite concrète — le prochain bloc s'il est proche, sinon une
// routine qui tient dans le trou. Rien à proposer = pas de carte.

CoachMoment? _chainMoment(DateTime now, AppState st,
    List<ScheduleBlock> blocks, List<Session> sessions,
    {ChallengeProposal? challenge}) {
  Session? last;
  for (final s in sessions) {
    if (s.endAt == null) {
      // Chrono en cours : pas d'enchaînement à proposer.
      if (_sameDay(s.startAt, now)) return null;
      continue;
    }
    if (!_sameDay(s.endAt!, now)) continue;
    if (last == null || s.endAt!.isAfter(last.endAt!)) last = s;
  }
  if (last == null) return null;
  final since = now.difference(last.endAt!).inMinutes;
  if (since < 0 || since > 10) return null;

  final durMin = last.endAt!.difference(last.startAt).inMinutes;
  final act = st.activities.where((a) => a.id == last!.activityId).firstOrNull;
  final done = act?.name ?? 'Session';

  final actions = <CoachAction>[];
  String proposal = '';
  final next = _firstEngagement(now, blocks);
  final gap = next != null
      ? _minutesUntil(now, next.startTime)
      : 19 * 60 - (now.hour * 60 + now.minute);
  // Défi ORION comme suite : jamais sur l'activité qu'on vient de finir, et
  // seulement s'il tient dans le trou. Sinon : prochain bloc / routine.
  final chal = challenge != null &&
          challenge.activity.id != last.activityId &&
          challenge.minutes + 10 <= gap
      ? challenge
      : null;
  if (next != null && gap < 60) {
    proposal = 'Prochain : ${next.title} ${_inFr(gap)}.';
    if (_launchable(next)) {
      actions.add(
          CoachAction('Lancer ${next.title}', CoachActionKind.launchBlock,
              block: next));
    }
  } else if (chal != null) {
    proposal = _challengeText(chal);
    actions.add(CoachAction(
        'Défi : ${chal.activity.name} — ${chal.minutes} min',
        CoachActionKind.challengeAccept,
        block: _challengeBlock(chal)));
  } else {
    final f = gapFillers(now, st, gap, blocks: blocks).firstOrNull;
    if (f != null) {
      proposal = _fillerText(f, hasNext: next != null);
      actions.add(_fillerAction(now, f));
    } else if (next != null) {
      proposal = 'Prochain : ${next.title} ${_inFr(gap)}.';
      if (_launchable(next)) {
        actions.add(
            CoachAction('Lancer ${next.title}', CoachActionKind.launchBlock,
                block: next));
      }
    }
  }
  if (actions.isEmpty) return null; // rien de réel à proposer — silence

  return CoachMoment(
    type: CoachMomentType.chain,
    tagLabel: 'ORION · ET ENSUITE ?',
    message:
        '$done terminé${durMin >= 1 ? ' — $durMin min au compteur' : ''}. Tu es lancé : $proposal',
    actions: actions,
    tone: CoachTone.positive,
  );
}

// ── Mode soirée (23c) : journée pliée tôt — assumé, jamais de rattrapage ─────

CoachMoment _eveningModeMoment(
    DailySchedule today, List<ScheduleBlock> blocks, List<StatItem> vitals) {
  final at = today.dayModeActivatedAt;
  final atStr = at != null
      ? ' à ${at.minute == 0 ? '${at.hour} h' : '${at.hour} h ${at.minute.toString().padLeft(2, '0')}'}'
      : '';
  final waiting = blocks
      .where((b) =>
          b.status == 'pending' &&
          !b.isPrep &&
          b.category != 'break' &&
          b.startTime.compareTo('19:00') < 0)
      .toList();
  final tonight = blocks
      .where((b) =>
          b.status == 'pending' &&
          !b.isPrep &&
          b.startTime.compareTo('19:00') >= 0)
      .toList();

  final parts = <String>['Après-midi terminé$atStr — assumé.'];
  if (waiting.isNotEmpty) {
    final names = waiting.take(2).map((b) => b.title).join(' et ');
    final suffix = waiting.length > 2 ? ' (+${waiting.length - 2})' : '';
    parts.add(
        '$names$suffix en attente : on les recase au check-in, pas maintenant.');
  }
  if (tonight.isNotEmpty) {
    parts.add(
        'Ce soir tient en ${tonight.length} chose${tonight.length > 1 ? 's' : ''} : ${tonight.take(2).map((b) => b.title).join(', ')}.');
  }

  return CoachMoment(
    type: CoachMomentType.evening,
    tagLabel: 'ORION · SOIRÉE · JOURNÉE PLIÉE TÔT',
    message: parts.join(' '),
    stats: vitals,
    actions: const [
      CoachAction('Faire le point', CoachActionKind.openDayReview),
    ],
    tone: CoachTone.neutral,
  );
}

CoachMoment _afternoonMoment(DateTime now, AppState st,
    List<ScheduleBlock> blocks, List<Session> sessions,
    {ChallengeProposal? challenge, GanttMicroAction? gantt}) {
  // 23b/23c : « Passer en soirée » (bascule invisible) devient la bascule
  // système EXPLICITE — nommée, conséquence visible, réversible (dayMode).
  const advance = CoachAction('Terminer l\'après-midi — mode soirée',
      CoachActionKind.endAfternoon);
  final next = _firstEngagement(now, blocks);
  // Trou réel : jusqu'au prochain bloc, sinon jusqu'au check-in du soir.
  final gap = next != null
      ? _minutesUntil(now, next.startTime)
      : 19 * 60 - (now.hour * 60 + now.minute);
  // Vital en tension : fin de semaine (jeudi+), un minimum hebdo n'y est pas
  // encore — la carte le dit et propose de CASER une séance (→ Planifions).
  // Une seule proposition à la fois : tension > défi ORION > combleur.
  final tension = _vitalTension(now, st, sessions);
  final tensionText = tension != null
      ? ' ${tension.domain.name} : ${tension.count}/${tension.target} séance${tension.target > 1 ? 's' : ''} cette semaine — on en case une ?'
      : '';
  final tensionAction = tension != null
      ? CoachAction('Caser une séance ${tension.domain.name}',
          CoachActionKind.planNext,
          block: ScheduleBlock(
              startTime: '00:00',
              durationMin: tension.activity.timerMin ?? 30,
              title: tension.activity.name,
              category: 'routine',
              activityId: tension.activity.id))
      : null;
  // Défi ORION : retard FRANC sur la cible du jour (moins de la moitié faite)
  // et un trou qui laisse la place de le relever. C'est l'après-midi que la
  // cible du jour se joue — jamais le matin, jamais le soir.
  final chal = tension == null &&
          challenge != null &&
          challenge.doneMin * 2 < challenge.targetMin &&
          challenge.minutes + 10 <= gap
      ? challenge
      : null;
  // Le CTA porte le NOM du défi (constaté sur build : « Je relève » seul ne
  // dit pas ce qu'on accepte) et ouvre le dialog de confirmation — le chrono
  // ne démarre jamais sur un simple tap de carte.
  final challengeActions = chal != null
      ? [
          CoachAction('Défi : ${chal.activity.name} — ${chal.minutes} min',
              CoachActionKind.challengeAccept,
              block: _challengeBlock(chal)),
        ]
      : const <CoachAction>[];
  final chalStats = <StatItem>[
    if (chal != null && chal.streak >= 2)
      StatItem('Défis', '${chal.streak} j d\'affilée'),
  ];
  if (next == null) {
    // Quick fix (constaté sur build) : à 14h46 sans programme, proposer
    // « Passer en soirée » abdique la demi-journée — la soirée commence à 19h.
    // On propose de PLANIFIER l'après-midi ; la transition reste en secondaire.
    // Trou jusqu'au check-in du soir : une routine peut le remplir tout de suite.
    final f = tension == null && chal == null && gap >= 60
        ? gapFillers(now, st, gap, blocks: blocks).firstOrNull
        : null;
    // Gantt invisible : quand rien d'autre ne se propose, une micro-action de
    // projet fait avancer le fond — dernier de la hiérarchie (tension > défi >
    // combleur > Gantt), 30 min de trou suffisent.
    final g =
        tension == null && chal == null && f == null && gap >= 30 ? gantt : null;
    var message =
        'Rien de posé pour la suite. 2 minutes et l\'après-midi a une colonne vertébrale.$tensionText';
    if (chal != null) message = '$message ${_challengeText(chal)}';
    if (f != null) message = '$message ${_fillerText(f, hasNext: false)}';
    if (g != null) message = '$message ${_ganttText(g)}';
    return CoachMoment(
      type: CoachMomentType.afternoon,
      tagLabel: 'ORION · APRÈS-MIDI',
      message: message,
      stats: chalStats,
      actions: [
        const CoachAction(
            'Planifier l\'après-midi · 2 min', CoachActionKind.planDay),
        if (tensionAction != null) tensionAction,
        ...challengeActions,
        if (f != null) _fillerAction(now, f),
        if (g != null) ..._ganttCtas(now, g),
        advance,
      ],
      tone: CoachTone.neutral,
    );
  }
  final whenStr = _inFr(gap);
  final f = tension == null && chal == null && gap >= 60
      ? gapFillers(now, st, gap, blocks: blocks).firstOrNull
      : null;
  final g =
      tension == null && chal == null && f == null && gap >= 30 ? gantt : null;
  var message = 'Prochain : ${next.title} $whenStr.$tensionText';
  if (chal != null) message = '$message ${_challengeText(chal)}';
  if (f != null) message = '$message ${_fillerText(f, hasNext: true)}';
  if (g != null) message = '$message ${_ganttText(g)}';
  return CoachMoment(
    type: CoachMomentType.afternoon,
    tagLabel: 'ORION · APRÈS-MIDI',
    message: message,
    stats: [
      StatItem('Prochain', _hhmmToFr(next.startTime), sub: next.title),
      if (tension != null)
        StatItem(tension.domain.name, '${tension.count}/${tension.target} · sem.'),
      ...chalStats,
    ],
    actions: [
      // Horizon actionnable : un bloc à > 90 min n'est pas « le moment ».
      if (_launchable(next) && gap <= 90)
        CoachAction('Lancer', CoachActionKind.launchBlock, block: next),
      if (tensionAction != null) tensionAction,
      ...challengeActions,
      if (f != null) _fillerAction(now, f),
      if (g != null) ..._ganttCtas(now, g),
      advance,
    ],
    tone: CoachTone.neutral,
  );
}

// ── Gantt invisible : micro-action de projet dans la carte ──────────────────
//
// « Le coach me challenge à avancer sur des petites actions du Gantt qu'il
// maintient » : la tâche la plus urgente (deadline la plus proche, puis date
// de début) des projets ACTIFS, proposée en 15 min quand rien d'autre n'a la
// priorité. Faits réels uniquement : la deadline n'est citée que si la tâche
// en a une, la prochaine sous-action que si elle existe.

class GanttMicroAction {
  final String projectId;
  final String projectTitle;
  final String taskId;
  final String taskTitle;
  final DateTime? deadline;
  final String? nextAction; // première sous-action non faite — null si aucune
  final String? nextActionId; // son id → chrono ciblé (Session.actionId)
  final int stepsDone; // étapes cochées (fait réel, cité)
  final int stepsTotal;
  const GanttMicroAction(
      {required this.projectId,
      required this.projectTitle,
      required this.taskId,
      required this.taskTitle,
      this.deadline,
      this.nextAction,
      this.nextActionId,
      this.stepsDone = 0,
      this.stepsTotal = 0});

  /// GTD minimaliste : la tâche n'a pas de prochaine étape définie — le coach
  /// propose de la DÉFINIR (puis de choisir quand la faire) plutôt que de
  /// lancer un chrono sur du flou.
  bool get needsSteps => nextAction == null;
}

/// La micro-action Gantt du moment — null si aucun projet actif n'a de tâche
/// pending, ou si la plus urgente est déjà portée par un bloc pending du jour.
/// [excludeTaskIds] : tâches dont une étape est déjà PROGRAMMÉE (aujourd'hui
/// ou plus tard) — le moment est choisi, le coach n'insiste pas.
GanttMicroAction? ganttMicroAction(List<Project> projects,
    {List<ScheduleBlock> blocks = const [],
    Set<String> excludeTaskIds = const {}}) {
  final planned = {
    ...excludeTaskIds,
    for (final b in blocks)
      if (b.status == 'pending' && b.taskId != null) b.taskId!
  };
  ({Project p, ProjectTask t})? best;
  for (final p in projects) {
    if (p.status != 'active') continue;
    for (final t in p.tasks) {
      if (t.status != 'pending' || t.isMilestone) continue;
      if (planned.contains(t.id)) continue;
      if (best == null) {
        best = (p: p, t: t);
        continue;
      }
      final a = t.endDate;
      final b = best.t.endDate;
      final earlier = a != null && (b == null || a.isBefore(b)) ||
          (a == null && b == null && t.startDate.isBefore(best.t.startDate));
      if (earlier) best = (p: p, t: t);
    }
  }
  if (best == null) return null;
  final next = best.t.actions
      .where((a) => !a.done && a.title.trim().isNotEmpty)
      .firstOrNull;
  return GanttMicroAction(
    projectId: best.p.id,
    projectTitle: best.p.title,
    taskId: best.t.id,
    taskTitle: best.t.title,
    deadline: best.t.endDate,
    nextAction: next?.title.trim(),
    nextActionId: next?.id,
    stepsDone: best.t.stepsDone,
    stepsTotal: best.t.stepsTotal,
  );
}

String _ganttText(GanttMicroAction g) {
  final dl = g.deadline != null
      ? ' (deadline le ${g.deadline!.day}/${g.deadline!.month})'
      : '';
  if (g.needsSteps) {
    // GTD minimaliste : pas d'étape définie → on ne lance rien sur du flou.
    // Définir la prochaine petite action EST l'avancée du moment.
    return 'Côté « ${g.projectTitle} », la tâche « ${g.taskTitle} » attend$dl '
        'et n\'a pas de prochaine étape définie. 2 minutes pour la poser — '
        'tu la feras au bon moment.';
  }
  final count = g.stepsTotal > 0 ? ' (${g.stepsDone}/${g.stepsTotal} faites)' : '';
  return 'Côté « ${g.projectTitle} », la tâche « ${g.taskTitle} » attend$dl. '
      'Prochaine étape : ${g.nextAction}$count — 15 minutes suffisent, '
      'maintenant ou au moment que tu choisis.';
}

/// CTA(s) de la micro-action Gantt : sans étape → « Définir la prochaine
/// étape » ; avec étape → la faire maintenant (chrono ciblé sur l'actionId)
/// OU la programmer au moment où le user sait qu'il sera dispo pour ELLE.
List<CoachAction> _ganttCtas(DateTime now, GanttMicroAction g) {
  final block = ScheduleBlock(
      startTime: _hm(now),
      durationMin: 15,
      title: g.nextAction ?? g.taskTitle,
      category: 'project',
      projectId: g.projectId,
      taskId: g.taskId,
      actionId: g.nextActionId);
  if (g.needsSteps) {
    return [
      CoachAction('Définir la prochaine étape', CoachActionKind.defineSteps,
          block: block),
    ];
  }
  return [
    CoachAction('Étape : ${g.nextAction} — 15 min',
        CoachActionKind.launchBlock,
        block: block),
    CoachAction('Programmer l\'étape', CoachActionKind.scheduleStep,
        block: block),
  ];
}

/// Premier domaine défini dont le minimum vital hebdo (metric `sessions*`,
/// period `week`) est en retard alors que la semaine se termine (jeudi ou
/// plus) — avec l'activité-temps du domaine à poser. Null si rien à dire ou
/// rien à poser (domaine sans activité, suspendu, suivi déclaré).
({Domain domain, Activity activity, int count, int target})? _vitalTension(
    DateTime now, AppState st, List<Session> sessions) {
  if (now.weekday < DateTime.thursday) return null;
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final ymd = _ymd(now);
  for (final d in st.domains) {
    if (d.deleted || !d.isDefined) continue;
    if (d.suspendedOn(ymd)) continue;
    if (d.tracking == 'declared') continue;
    for (final v in d.vitalMinimum) {
      if (v.period != 'week' || v.target <= 0) continue;
      if (!v.metric.startsWith('sessions')) continue;
      var count = 0;
      for (final s in sessions) {
        if (s.startAt.isBefore(monday)) continue;
        final act =
            st.activities.where((a) => a.id == s.activityId).firstOrNull;
        if (act == null || act.domainId != d.id) continue;
        if ((s.endAt ?? now).difference(s.startAt).inMinutes >= 10) count++;
      }
      final target = v.target.toInt();
      if (count >= target) break; // ce domaine est à jour
      final activity = st.activities
          .where((a) => !a.deleted && !a.isHabit && a.domainId == d.id)
          .firstOrNull;
      if (activity == null) break; // rien à poser — pas de CTA inventé
      return (domain: d, activity: activity, count: count, target: target);
    }
  }
  return null;
}

/// Teaser du rapport hebdo (16a) — chiffres réels du rapport généré.
CoachMoment _weeklyTeaser(WeeklyReport r) {
  final motif = r.motifs.isNotEmpty ? r.motifs.first : null;
  return CoachMoment(
    type: CoachMomentType.weekly,
    tagLabel: 'ORION · RAPPORT HEBDO',
    title: 'Semaine ${r.isoWeek}',
    message:
        'Le rapport fait 3 minutes, la question de fond en fait une.',
    stats: [
      StatItem('Engagements tenus', '${r.held}/${r.total}'),
      if (motif != null)
        StatItem('« ${skipReasonLabel(motif.cause)} »', '×${motif.count}'),
    ],
    actions: const [
      CoachAction('Lire le rapport — 3 min', CoachActionKind.openWeeklyReport),
      CoachAction('Faire le point', CoachActionKind.openDayReview),
    ],
    tone: CoachTone.positive,
  );
}

CoachMoment _eveningMoment(List<ScheduleBlock> blocks, List<StatItem> vitals,
    {DateTime? reviewedAt}) {
  final pendingPreps =
      blocks.where((b) => b.isPrep && b.status == 'pending').length;
  // Point déjà fait (fait reviewedAt) : la carte ne re-propose pas ce qui est
  // fait — clôture calme, la soirée est à toi. « Revoir » reste accessible.
  if (reviewedAt != null) {
    return CoachMoment(
      type: CoachMomentType.evening,
      tagLabel: 'ORION · JOURNÉE CLÔTURÉE',
      message: pendingPreps > 0
          ? 'Le point est fait — il reste $pendingPreps préparation${pendingPreps > 1 ? 's' : ''} à cocher pour armer demain, puis la soirée est à toi.'
          : 'Le point est fait, demain est armé — la soirée est à toi.',
      stats: vitals,
      actions: const [
        CoachAction('Revoir le point', CoachActionKind.openDayReview),
      ],
      tone: CoachTone.positive,
    );
  }
  final stats = <StatItem>[
    if (pendingPreps > 0)
      StatItem('À préparer', '$pendingPreps bloc${pendingPreps > 1 ? 's' : ''}'),
    ...vitals,
  ];
  final message = pendingPreps > 0
      ? 'Demain se gagne ce soir. Clôture ta journée et arme demain — $pendingPreps préparation${pendingPreps > 1 ? 's' : ''} à cocher.'
      : 'Demain se gagne ce soir. Prends deux minutes pour clôturer ta journée.';
  return CoachMoment(
    type: CoachMomentType.evening,
    tagLabel: 'ORION · CHECK-IN DU SOIR',
    message: message,
    stats: stats,
    actions: const [
      CoachAction('Faire le point', CoachActionKind.openDayReview),
    ],
    tone: CoachTone.neutral,
  );
}

// ── Helpers purs ──────────────────────────────────────────────────────────────

// ── Heure habituelle & combleur de trous ─────────────────────────────────────
//
// Deux dynamiques pour Maintenant : quand le prochain bloc est loin, la carte
// propose « d'ici là » une routine qui TIENT dans le trou ; et quand une
// routine a une heure habituelle (médiane de ses hits réels), c'est elle qui
// est proposée à son heure. 0 LLM, chiffres réels — pas d'historique = pas de
// fait, jamais de chiffre inventé.

/// Heure habituelle d'une routine : médiane des heures de ses hits sur
/// [lookbackDays] jours, en minutes depuis minuit. Les hits nocturnes (< 5 h)
/// comptent comme fin de la journée précédente (+24 h) — cohérent avec la
/// « journée vécue ». Null sous [minHits] hits : pas assez de données.
int? typicalMinuteOf(String habitId, List<HabitHit> hits, DateTime now,
    {int lookbackDays = 28, int minHits = 3}) {
  final cutoff = now.subtract(Duration(days: lookbackDays));
  final mins = <int>[];
  for (final h in hits) {
    if (h.habitId != habitId || h.ts.isBefore(cutoff)) continue;
    var m = h.ts.hour * 60 + h.ts.minute;
    if (m < 5 * 60) m += 24 * 60;
    mins.add(m);
  }
  if (mins.length < minHits) return null;
  mins.sort();
  return mins[mins.length ~/ 2] % (24 * 60);
}

/// Distance circulaire entre deux minutes-du-jour (23h50 et 0h10 = 20 min).
int _circDist(int a, int b) {
  final d = (a - b).abs();
  return d <= 720 ? d : 1440 - d;
}

/// Série en cours d'une routine : jours consécutifs avec ≥ 1 hit, en remontant
/// depuis aujourd'hui — ou depuis hier si rien encore aujourd'hui (la série
/// n'est pas cassée tant que la journée n'est pas finie). Hits nocturnes
/// (< 5 h) rattachés à la journée vécue, comme partout.
int streakOf(String habitId, List<HabitHit> hits, DateTime now) {
  final days = <String>{};
  for (final h in hits) {
    if (h.habitId != habitId) continue;
    final t = h.ts.hour * 60 + h.ts.minute < 5 * 60
        ? h.ts.subtract(const Duration(days: 1))
        : h.ts;
    days.add(_ymd(t));
  }
  var d = DateTime(now.year, now.month, now.day);
  if (!days.contains(_ymd(d))) d = d.subtract(const Duration(days: 1));
  var streak = 0;
  while (days.contains(_ymd(d))) {
    streak++;
    d = d.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Une routine proposée pour combler le temps libre avant le prochain bloc.
/// [durationMin] null = routine sans minuteur (« boire de l'eau ») : pas de
/// chiffre inventé, pas de chrono — une coche directe (✓) suffit.
class GapFiller {
  final Activity routine;
  final int? durationMin;
  final int? typicalMinute; // heure habituelle — null si historique insuffisant
  final bool usualTime; // ± 45 min autour de maintenant
  final int streakDays; // jours d'affilée (série en cours, aujourd'hui exclu)
  const GapFiller(
      {required this.routine,
      this.durationMin,
      this.typicalMinute,
      this.usualTime = false,
      this.streakDays = 0});
}

/// Routines quotidiennes pas encore tenues qui tiennent dans [gapMin] (durée
/// + 10 min de marge pour arriver au bloc suivant à l'heure), classées par
/// proximité de leur heure habituelle avec maintenant — sans historique,
/// l'ordre utilisateur. Une routine jamais faite autour de cette heure
/// (habituelle à > 4 h d'ici) est écartée : la bonne routine au bon moment.
/// [blocks] : une routine déjà posée en bloc pending aujourd'hui est écartée
/// aussi — le programme la porte déjà.
List<GapFiller> gapFillers(DateTime now, AppState st, int gapMin,
    {List<ScheduleBlock> blocks = const [], int max = 2}) {
  final nowMin = now.hour * 60 + now.minute;
  final planned = {
    for (final b in blocks)
      if (b.status == 'pending' && b.activityId != null) b.activityId!
  };
  final routines = st.activities
      .where((a) => !a.deleted && a.isHabit && a.effHabitFreq == HabitFreq.daily)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  final entries = <({GapFiller f, int dist, int idx})>[];
  for (var i = 0; i < routines.length; i++) {
    final a = routines[i];
    if (planned.contains(a.id)) continue;
    if (st.habitHits.any((h) => h.habitId == a.id && _sameDay(h.ts, now))) {
      continue;
    }
    // Durée RÉELLE uniquement (constaté sur build : « Boire de l'eau, 20 min »
    // n'a aucun sens). Sans minuteur : proposée sans chiffre, coche directe —
    // elle ne prend pas de temps, elle tient dans n'importe quel trou.
    final dur = (a.timerMin ?? 0) > 0 ? a.timerMin : null;
    if (dur != null && dur + 10 > gapMin) continue;
    final tm = typicalMinuteOf(a.id, st.habitHits, now);
    final dist = tm != null ? _circDist(tm, nowMin) : null;
    if (dist != null && dist > 240) continue;
    // Sans historique MESURÉ, le méta-contexte tranche : « Hygiène du soir »
    // n'est pas un combleur de 10 h du matin (le réel, lui, bat le catalogue).
    if (tm == null && !(effTimeContextOf(a)?.allows(nowMin) ?? true)) continue;
    entries.add((
      f: GapFiller(
          routine: a,
          durationMin: dur,
          typicalMinute: tm,
          usualTime: dist != null && dist <= 45,
          streakDays: streakOf(a.id, st.habitHits, now)),
      dist: dist ?? 1 << 20,
      idx: i,
    ));
  }
  entries.sort((a, b) {
    if (a.dist != b.dist) return a.dist.compareTo(b.dist);
    // À proximité égale (ou sans historique) : l'élan d'abord, puis l'ordre user.
    if (a.f.streakDays != b.f.streakDays) {
      return b.f.streakDays.compareTo(a.f.streakDays);
    }
    return a.idx.compareTo(b.idx); // tri stable : ordre utilisateur
  });
  return [for (final e in entries.take(max)) e.f];
}

/// Fragment de message pour un combleur : « D'ici là : X, 10 min — c'est ton
/// heure habituelle (vers 9h30) · 4 jours d'affilée, on continue ? »
/// [hasNext] pilote la formule d'accroche. Faits réels uniquement — pas de
/// durée si la routine n'a pas de minuteur, pas de point après un « ? ».
String _fillerText(GapFiller f, {required bool hasNext}) {
  final facts = <String>[
    if (f.usualTime && f.typicalMinute != null)
      'c\'est ton heure habituelle (vers ${_minToFr(f.typicalMinute!)})',
    if (f.routine.finalTarget != null)
      'palier ${f.routine.effHabitTarget}/j, cap ${f.routine.finalTarget}',
    if (f.streakDays >= 3) '${f.streakDays} jours d\'affilée, on continue ?',
  ];
  final suffix = facts.isEmpty ? '' : ' — ${facts.join(' · ')}';
  final head = hasNext ? 'D\'ici là' : 'Par exemple';
  final dur = f.durationMin != null ? ', ${f.durationMin} min' : '';
  final body = '$head : ${f.routine.name}$dur$suffix';
  return body.endsWith('?') ? body : '$body.';
}

/// CTA d'un combleur : routine minutée → chrono ciblé (même machinerie que le
/// ▶ du programme) ; routine sans minuteur → coche directe (✓), rien à lancer.
CoachAction _fillerAction(DateTime now, GapFiller f) => f.durationMin != null
    ? CoachAction(
        '${f.routine.name} — ${f.durationMin} min', CoachActionKind.launchBlock,
        block: ScheduleBlock(
            startTime: _hm(now),
            durationMin: f.durationMin!,
            title: f.routine.name,
            category: 'routine',
            activityId: f.routine.id))
    : CoachAction('✓ ${f.routine.name}', CoachActionKind.checkRoutine,
        block: ScheduleBlock(
            startTime: _hm(now),
            durationMin: 5,
            title: f.routine.name,
            category: 'routine',
            activityId: f.routine.id));

// ── « C'était ton heure » (programme idéal) ──────────────────────────────────
//
// Une routine quotidienne dont l'heure habituelle MESURÉE vient de passer
// (10 à 90 min), pas encore tenue aujourd'hui, sans bloc pending qui la
// porte : la carte le signale pendant que le moment est encore rattrapable.
// Avant l'heure, la routine viendra d'elle-même ; bien après, les combleurs
// prennent le relais. Plusieurs candidates → la plus récemment passée.

CoachMoment? _idealHourMoment(
    DateTime now, AppState st, List<ScheduleBlock> blocks) {
  final nowMin = now.hour * 60 + now.minute;
  final planned = {
    for (final b in blocks)
      if (b.status == 'pending' && b.activityId != null) b.activityId!
  };
  ({Activity a, int tm, int delta})? best;
  for (final a in st.activities) {
    if (a.deleted || !a.isHabit || a.effHabitFreq != HabitFreq.daily) continue;
    if (planned.contains(a.id)) continue;
    if (st.habitHits.any((h) => h.habitId == a.id && _sameDay(h.ts, now))) {
      continue;
    }
    final tm = typicalMinuteOf(a.id, st.habitHits, now);
    if (tm == null) continue;
    final delta = nowMin - tm;
    if (delta < 10 || delta > 90) continue;
    if (best == null || delta < best.delta) best = (a: a, tm: tm, delta: delta);
  }
  if (best == null) return null;
  final a = best.a;
  final streak = streakOf(a.id, st.habitHits, now);
  final dur = (a.timerMin ?? 0) > 0 ? a.timerMin : null;
  final endFacts = <String>[
    if (a.finalTarget != null)
      'Palier : ${a.effHabitTarget}/j — cap ${a.finalTarget}.',
    if (streak >= 3) '$streak jours d\'affilée, on continue ?',
  ];
  final suffix = endFacts.isEmpty ? '' : ' ${endFacts.join(' ')}';
  return CoachMoment(
    type: CoachMomentType.idealHour,
    tagLabel: 'ORION · C\'ÉTAIT TON HEURE',
    title: a.name,
    message:
        'D\'habitude tu fais « ${a.name} » vers ${_minToFr(best.tm)} — il est '
        '${_minToFr(nowMin)} et rien n\'est coché. Encore le bon moment.$suffix',
    actions: [
      _fillerAction(
          now,
          GapFiller(
              routine: a,
              durationMin: dur,
              typicalMinute: best.tm,
              usualTime: true,
              streakDays: streak)),
    ],
  );
}

// ── Micro-cible : la question du réglage, posée au fil de l'eau ──────────────
//
// Une activité-temps restée à sa cible de DÉPART (< 10 min, targetSource
// 'default') mais réellement vécue (≥ 3 jours de sessions sur 28 j) est
// ambiguë : micro-cible VOULUE (« 10 pompes + 3 tractions en 1 min, juste
// pour démarrer ») ou réglage jamais fait ? On ne tranche pas à sa place —
// la carte pose la question UNE fois, avec les faits mesurés. La réponse
// devient un fait (targetSource 'user' ou 'orion') et la question disparaît.
// Fenêtre du matin uniquement, jamais au-dessus d'une proposition d'action.

CoachMoment? _microTargetMoment(
    DateTime now, AppState st, List<Session> sessions) {
  final cutoff = now.subtract(const Duration(days: 28));
  ({Activity a, int days, int median})? best;
  for (final a in st.activities) {
    if (a.deleted || a.isHabit || a.role == ActivityRole.shopping) continue;
    if (a.targetSource != 'default') continue; // déjà réglée (user/orion)
    if (a.goalMin <= 0 || a.goalMin >= 10) continue;
    final byDay = <String, int>{};
    for (final s in sessions) {
      if (s.activityId != a.id || s.startAt.isBefore(cutoff)) continue;
      final min = (s.endAt ?? now).difference(s.startAt).inMinutes;
      if (min <= 0) continue;
      byDay[_ymd(s.startAt)] = (byDay[_ymd(s.startAt)] ?? 0) + min;
    }
    if (byDay.length < 3) continue; // pas assez de faits pour poser la question
    final totals = byDay.values.toList()..sort();
    final median = totals[totals.length ~/ 2];
    // Micro-cible vécue en micro-sessions (médiane sous 10 min) : cohérente —
    // rien à demander. La question ne vaut que si le réel CONTREDIT la cible.
    if (median < 10) continue;
    if (best == null || byDay.length > best.days) {
      best = (a: a, days: byDay.length, median: median);
    }
  }
  if (best == null) return null;
  final a = best.a;
  final block = ScheduleBlock(
      startTime: _hm(now),
      durationMin: a.goalMin,
      title: a.name,
      category: 'personal',
      activityId: a.id);
  return CoachMoment(
    type: CoachMomentType.microTarget,
    tagLabel: 'ORION · RÉGLAGE',
    title: a.name,
    message:
        'Ta cible « ${a.name} » est restée à ${a.goalMin} min/j (réglage de '
        'départ) — mais tu l\'as pratiquée ${best.days} jours sur les 28 '
        'derniers, ~${best.median} min quand tu t\'y mets. C\'est une '
        'micro-cible voulue (déclencheur), ou on la cale sur ton réel ?',
    actions: [
      CoachAction('Garder ${a.goalMin} min — déclencheur',
          CoachActionKind.keepMicroTarget,
          block: block),
      CoachAction('Caler sur mon réel', CoachActionKind.calibrateTarget,
          block: block),
      const CoachAction('Plus tard', CoachActionKind.dismiss),
    ],
  );
}

/// « dans 238 min » est illisible : sous l'heure on parle en minutes, au-delà
/// en heures (« dans 3 h 58 »). 0 ou moins = « maintenant ».
String _inFr(int mins) {
  if (mins <= 0) return 'maintenant';
  if (mins < 60) return 'dans $mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? 'dans $h h' : 'dans $h h ${m.toString().padLeft(2, '0')}';
}

/// Minimum vital hebdo des domaines définis, vérifié par les données réelles :
/// métriques `sessions*` (séances ≥ 10 min sur une activité du domaine, semaine
/// courante) et métriques TEMPS `hours*`/`minutes*` (heures réelles logguées
/// sur le domaine — cible journalière ramenée à la semaine ×7). Le reste est
/// omis (jamais de chiffre inventé). Max 2 stats.
List<StatItem> _vitalStats(DateTime now, AppState st, List<Session> sessions) {
  final stats = <StatItem>[];
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final ymd =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  String fmtH(double v) => v % 1 == 0
      ? v.toInt().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');
  for (final d in st.domains) {
    if (d.deleted || !d.isDefined) continue;
    // Suspension assumée (12b) : le coach ne demande rien pendant la pause.
    if (d.suspendedOn(ymd)) continue;
    // Suivi déclaré (20) : pas de score, absent de la carte quotidienne —
    // son vital n'existe qu'au rapport du dimanche.
    if (d.tracking == 'declared') continue;
    for (final v in d.vitalMinimum) {
      if (v.target <= 0) continue;
      final metric = v.metric.toLowerCase();
      if (metric.startsWith('sessions')) {
        if (v.period != 'week') continue;
        var count = 0;
        for (final s in sessions) {
          if (s.startAt.isBefore(monday)) continue;
          final act =
              st.activities.where((a) => a.id == s.activityId).firstOrNull;
          if (act == null || act.domainId != d.id) continue;
          if ((s.endAt ?? now).difference(s.startAt).inMinutes >= 10) count++;
        }
        stats.add(StatItem(d.name, '$count/${v.target.toInt()} · sem.',
            sub: v.label));
      } else if (RegExp(r'hour|heure|min').hasMatch(metric)) {
        // Métrique temps : heures réelles de la semaine sur le domaine.
        final isHours = RegExp(r'hour|heure').hasMatch(metric);
        final weekTargetMin =
            (v.period == 'day' ? v.target * 7 : v.target) * (isHours ? 60 : 1);
        var mins = 0;
        for (final s in sessions) {
          if (s.startAt.isBefore(monday)) continue;
          final act =
              st.activities.where((a) => a.id == s.activityId).firstOrNull;
          if (act == null || act.domainId != d.id) continue;
          mins += (s.endAt ?? now).difference(s.startAt).inMinutes;
        }
        stats.add(StatItem(d.name,
            '${fmtH(mins / 60)}/${fmtH(weekTargetMin / 60)} h · sem.',
            sub: v.label));
      } else {
        continue; // métrique non mesurable → omise
      }
      break; // une stat par domaine — la carte reste compacte
    }
    if (stats.length >= 2) break;
  }
  return stats;
}

List<ScheduleBlock> _liveBlocks(DailySchedule? s) =>
    (s?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

bool _launchable(ScheduleBlock b) => b.projectId != null || b.activityId != null;

/// Premier bloc d'engagement (non-prep, non-pause) dont le créneau couvre
/// l'heure ou est à venir.
ScheduleBlock? _firstEngagement(DateTime now, List<ScheduleBlock> blocks) {
  for (final b in blocks) {
    if (b.isPrep || b.category == 'break' || b.status != 'pending') continue;
    final start = _blockStart(b, now);
    final end = start.add(Duration(minutes: b.durationMin));
    if (now.isBefore(end)) return b; // en cours ou à venir
  }
  return null;
}

ScheduleBlock? _firstDoneEngagement(List<ScheduleBlock> blocks) {
  for (final b in blocks) {
    if (b.isPrep || b.category == 'break') continue;
    if (b.status == 'done') return b;
  }
  return null;
}

/// Le bloc-clé de l'après-midi : premier bloc pending entre 12 h et 19 h,
/// projet en priorité. Les blocs du SOIR (≥ 19 h) ne sont pas l'affaire de
/// l'après-midi (constaté sur build : « l'après-midi n'a qu'une chose à
/// tenir : Hygiène du soir, 21 h ») — ils sont cités à part (_eveningPreview).
ScheduleBlock? _afternoonKeyBlock(DateTime now, List<ScheduleBlock> blocks) {
  final noon = DateTime(now.year, now.month, now.day, 12);
  final evening = DateTime(now.year, now.month, now.day, 19);
  final afternoon = blocks
      .where((b) =>
          !b.isPrep &&
          b.category != 'break' &&
          b.status == 'pending' &&
          !_blockStart(b, now).isBefore(noon) &&
          _blockStart(b, now).isBefore(evening))
      .toList();
  if (afternoon.isEmpty) return null;
  final projects = afternoon.where((b) => b.category == 'project').toList();
  return (projects.isNotEmpty ? projects : afternoon).first;
}

/// Premier bloc pending du SOIR (≥ 19 h) — mentionné, jamais proposé au
/// lancement en pleine journée.
ScheduleBlock? _eveningPreview(DateTime now, List<ScheduleBlock> blocks) {
  final evening = DateTime(now.year, now.month, now.day, 19);
  for (final b in blocks) {
    if (b.isPrep || b.category == 'break' || b.status != 'pending') continue;
    if (!_blockStart(b, now).isBefore(evening)) return b;
  }
  return null;
}

bool _prepReadyFrom(DailySchedule? yesterday, String todayStr) {
  for (final b in yesterday?.blocks ?? const <ScheduleBlock>[]) {
    if (b.isPrep && b.status == 'done' && b.prepForDate == todayStr) return true;
  }
  return false;
}

int? _morningRank(
    DateTime now, List<Session> sessions, int todayMorningMin) {
  final byDay = <String, int>{};
  for (var i = 0; i < 7; i++) {
    final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
    final dayStart = d;
    final noon = d.add(const Duration(hours: 12));
    byDay[_ymd(d)] = _loggedMinutesInWindow(sessions, dayStart, noon);
  }
  byDay[_ymd(now)] = todayMorningMin;
  final todayVal = todayMorningMin;
  if (todayVal <= 0) return null;
  final sorted = byDay.values.toList()..sort((a, b) => b.compareTo(a));
  return sorted.indexOf(todayVal) + 1;
}

int _blockLoggedMin(ScheduleBlock b, List<Session> sessions, DateTime start,
    DateTime now,
    {Set<String> extraIds = const {}}) {
  var total = 0;
  for (final s in sessions) {
    final matches = (b.activityId != null && s.activityId == b.activityId) ||
        extraIds.contains(s.activityId) ||
        (b.taskId != null && s.taskId == b.taskId);
    if (!matches) continue;
    total += _overlapMin(s.startAt, s.endAt ?? now, start, now);
  }
  return total;
}

int _loggedMinutesInWindow(
    List<Session> sessions, DateTime start, DateTime end) {
  var total = 0;
  for (final s in sessions) {
    total += _overlapMin(s.startAt, s.endAt ?? end, start, end);
  }
  return total;
}

int _overlapMin(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
  final start = aStart.isAfter(bStart) ? aStart : bStart;
  final end = aEnd.isBefore(bEnd) ? aEnd : bEnd;
  final mins = end.difference(start).inMinutes;
  return mins > 0 ? mins : 0;
}

DateTime _blockStart(ScheduleBlock b, DateTime now) {
  final parts = b.startTime.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return DateTime(now.year, now.month, now.day, h, m);
}

int _minutesUntil(DateTime now, String hm) {
  final parts = hm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final target = DateTime(now.year, now.month, now.day, h, m);
  return target.difference(now).inMinutes;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 570 (minutes depuis minuit) → "9h30" ; 540 → "9h".
String _minToFr(int m) {
  final h = m ~/ 60;
  final mm = m % 60;
  return mm == 0 ? '${h}h' : '${h}h${mm.toString().padLeft(2, '0')}';
}

/// "07:15" → "7h15" ; "07:00" → "7h".
String _hhmmToFr(String hm) {
  final parts = hm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? parts[1] : '00';
  return m == '00' ? '${h}h' : '${h}h$m';
}

String _fmtDur(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}
