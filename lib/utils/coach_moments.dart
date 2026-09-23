import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_context.dart';

// ─── CARTE COACH « MAINTENANT » — ÉVÉNEMENTIELLE ─────────────────────────────
//
// Refonte 2026-09 (retour user : « je n'ai jamais suivi le coach, je ne
// comprends pas ce qu'il m'apporte ») : le coach ne commente plus la journée.
// AUCUNE carte par défaut — elle n'existe que quand un ÉVÉNEMENT réel s'est
// produit, que l'écran ne montre pas déjà :
//   1. un chrono vient de finir (≤ 10 min) → « Et ensuite ? » (une suite
//      concrète : prochain bloc, routine du même contexte, défi, combleur) ;
//   2. un bloc posé dérive (> 45 min, 0 min logguée) → « Lancer / Renégocier ».
// Tout le reste (réveil, matin, rapport de matinée, après-midi, check-in du
// soir, nudges, micro-cible, mode soirée en carte) a été supprimé — l'état de
// la journée vit dans la timeline, l'appbar (24 h + sommeil) et « Résumé du
// jour ». Fonction pure, 0 LLM, chiffres réels uniquement.

enum CoachTone { neutral, positive, alert }

enum CoachMomentType {
  drift, // bloc posé depuis > 45 min, 0 min logguée → alerte actionnable
  chain, // un chrono vient de finir → « Et ensuite ? » (enchaînement immédiat)
  hidden,
}

/// Une action proposée par la carte. [block] cible le bloc concerné (chrono
/// ciblé, renégociation…).
enum CoachActionKind {
  launchBlock,
  renegotiate,
  dismiss, // « Ignorer » (dérive) — silence jusqu'à demain
  challengeAccept, // « Je relève 🔥 » — chrono + minuteur-alarme + streak
  checkRoutine, // ✓ — coche une routine sans minuteur (pas de chrono)
}

class CoachAction {
  final String label;
  final CoachActionKind kind;
  final ScheduleBlock? block;
  const CoachAction(this.label, this.kind, {this.block});
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
  final String tagLabel; // micro-label émeraude/ambre (« ORION · ET ENSUITE ? »)
  final String? title;
  final String message;
  final List<CoachAction> actions;
  final CoachTone tone;

  const CoachMoment({
    required this.type,
    required this.tagLabel,
    this.title,
    required this.message,
    this.actions = const [],
    this.tone = CoachTone.neutral,
  });

  bool get hidden => type == CoachMomentType.hidden;

  static const CoachMoment none = CoachMoment(
      type: CoachMomentType.hidden, tagLabel: '', message: '');
}

// ── Point d'entrée ────────────────────────────────────────────────────────────

/// [driftSnoozed] : une renégociation vient d'être faite ou la dérive a été
/// ignorée — la carte dérive se tait (fenêtre gérée par l'appelant).
/// [challenge] : défi ORION calculé par l'appelant, proposé comme suite dans
/// « Et ensuite ? » (une sollicitation par jour maximum).
CoachMoment computeCoachMoment(
  DateTime now,
  AppState st,
  DailySchedule? today,
  List<Session> recentSessions, {
  bool driftSnoozed = false,
  ChallengeProposal? challenge,
}) {
  final minutes = now.hour * 60 + now.minute;
  if (minutes < 5 * 60) return CoachMoment.none; // nuit
  // Soir (≥ 19 h) : silence total — plus aucune carte ORION.
  if (minutes >= 19 * 60) return CoachMoment.none;
  // Pause déclarée (« pas dispo avant X ») et mode soirée (journée pliée
  // tôt) : le coach suit le flow — aucune relance avant l'heure dite.
  if (today?.unavailableAt(now) == true) return CoachMoment.none;
  if (today?.eveningMode == true) return CoachMoment.none;

  final blocks = _liveBlocks(today);
  final sessionsToday =
      recentSessions.where((s) => _sameDay(s.startAt, now)).toList();
  // Défi ORION : une sollicitation par jour maximum — passé
  // (skippedChallengeDates) ou déjà relevé aujourd'hui = silence. Le bouton
  // doré et la chip du guide restent disponibles à la demande, eux.
  final ymdCompact =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  final chal = challenge != null &&
          !st.skippedChallengeDates.contains(ymdCompact) &&
          !st.challengeWinsByDay.containsKey(ymdCompact)
      ? challenge
      : null;

  // Événement 1 — un chrono vient de finir (≤ 10 min) : « Et ensuite ? ».
  final chain = _chainMoment(now, st, blocks, recentSessions, challenge: chal);
  if (chain != null) return chain;

  // Événement 2 — un bloc posé dérive (> 45 min, 0 min logguée). Pas avant
  // 9 h : on ne relance pas quelqu'un sur son petit-déjeuner.
  if (minutes >= 9 * 60 && !driftSnoozed) {
    final drift = _driftMoment(now, st, blocks, sessionsToday);
    if (drift != null) return drift;
  }

  return CoachMoment.none;
}

/// Le bloc en dérive : posé depuis > 45 min avec 0 min logguée (routine liée
/// et coche du jour comprises), sinon null. Public : c'est aussi le signal du
/// déclencheur n° 2 de la question d'état (24a) — la question remplace alors
/// la carte dérive.
ScheduleBlock? driftingBlock(DateTime now, AppState st,
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
  return drifting;
}

/// Retourne un moment `drift` si un bloc source est posé depuis > 45 min avec
/// 0 min logguée, sinon null.
CoachMoment? _driftMoment(DateTime now, AppState st,
    List<ScheduleBlock> blocks, List<Session> sessionsToday) {
  final drifting = driftingBlock(now, st, blocks, sessionsToday);
  if (drifting == null) return null;

  // « 25 min » n'a aucun sens pour un bloc d'1 min (vitamines) : le CTA
  // s'aligne sur la durée RÉELLE du bloc, plafonnée à 25.
  final relance =
      drifting.durationMin < 25 ? drifting.durationMin : 25;
  final actions = <CoachAction>[
    if (_launchable(drifting))
      CoachAction('Lancer $relance min', CoachActionKind.launchBlock,
          block: drifting),
    CoachAction('Renégocier', CoachActionKind.renegotiate, block: drifting),
    // « Ignorer » : la dérive se tait jusqu'à demain (snooze côté appelant).
    const CoachAction('Ignorer', CoachActionKind.dismiss),
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
  // CTA CONTEXTE PARTAGÉ : ce qu'on vient de finir portait @maison → une
  // routine @maison pas encore validée est l'enchaînement le plus naturel
  // (« je viens de laver la voiture @maison → vaisselle, aussi @maison »).
  Activity? sameCtx;
  String? sharedCtx;
  final finishedCtxs = act?.contexts ?? const <String>[];
  if (finishedCtxs.isNotEmpty) {
    for (final r in st.activeActivities) {
      if (!r.isHabit || r.id == last.activityId) continue;
      final shared =
          r.contexts.where(finishedCtxs.contains).toList();
      if (shared.isEmpty) continue;
      final hitToday = st.habitHits
          .any((h) => h.habitId == r.id && _sameDay(h.ts, now));
      if (hitToday) continue;
      sameCtx = r;
      sharedCtx = shared.first;
      break;
    }
  }
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
  } else if (sameCtx != null) {
    proposal =
        'Tu es toujours $sharedCtx — « ${sameCtx.name} » l\'est aussi.';
    actions.add(CoachAction(
        'Enchaîner : ${sameCtx.name}', CoachActionKind.launchBlock,
        block: ScheduleBlock(
          startTime:
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
          durationMin: sameCtx.timerMin ?? 15,
          title: sameCtx.name,
          category: 'routine',
          activityId: sameCtx.id,
        )));
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
    // Projet en pause (GTD) : le coach ne pousse pas ses micro-actions.
    if (p.status != 'active' || p.paused) continue;
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
    : CoachAction(
        // Routine comptée (palier > 1 : pompes, tractions…) → la cible est
        // annoncée sur le bouton ; le tap ouvre la saisie − / + préremplie.
        f.routine.effHabitTarget > 1
            ? '✓ ${f.routine.name} — cible ${f.routine.effHabitTarget}'
            : '✓ ${f.routine.name}',
        CoachActionKind.checkRoutine,
        block: ScheduleBlock(
            startTime: _hm(now),
            durationMin: 5,
            title: f.routine.name,
            category: 'routine',
            activityId: f.routine.id));

/// « dans 238 min » est illisible : sous l'heure on parle en minutes, au-delà
/// en heures (« dans 3 h 58 »). 0 ou moins = « maintenant ».
String _inFr(int mins) {
  if (mins <= 0) return 'maintenant';
  if (mins < 60) return 'dans $mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? 'dans $h h' : 'dans $h h ${m.toString().padLeft(2, '0')}';
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
