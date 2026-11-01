import 'dart:math' as math;

import 'package:productivitwo_v1/models.dart';

/// Logique pure de la vue Aujourd'hui (refonte web § 2) — testable sans widget.
/// Les minutes sont comptées depuis minuit ; les blocs `deleted` doivent avoir
/// été filtrés en amont (cf. `DailySchedule` : soft-delete).

/// Minute de début d'un bloc ("HH:mm" → minutes). Format invalide → 0.
int blockStartMin(ScheduleBlock b) {
  final parts = b.startTime.split(':');
  if (parts.length < 2) return b.dayOffset * 24 * 60;
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0) + b.dayOffset * 24 * 60;
}

int blockEndMin(ScheduleBlock b) => blockStartMin(b) + b.durationMin;

/// Bloc focal : le premier bloc `pending` dont le créneau contient l'heure
/// courante (`current: true`), sinon le prochain à venir, sinon null.
({ScheduleBlock block, bool current})? focusBlock(
    List<ScheduleBlock> blocks, int nowMin) {
  for (final b in blocks) {
    final s = blockStartMin(b);
    if (b.status == 'pending' && s <= nowMin && nowMin < s + b.durationMin) {
      return (block: b, current: true);
    }
  }
  ScheduleBlock? next;
  for (final b in blocks) {
    if (b.status != 'pending' || blockStartMin(b) <= nowMin) continue;
    if (next == null || blockStartMin(b) < blockStartMin(next)) next = b;
  }
  return next == null ? null : (block: next, current: false);
}

/// Premier bloc `pending` qui commence à la fin de [block] ou après.
ScheduleBlock? nextBlockAfter(List<ScheduleBlock> blocks, ScheduleBlock block) {
  final end = blockEndMin(block);
  ScheduleBlock? next;
  for (final b in blocks) {
    if (b.id == block.id || b.status != 'pending') continue;
    if (blockStartMin(b) < end) continue;
    if (next == null || blockStartMin(b) < blockStartMin(next)) next = b;
  }
  return next;
}

/// Minutes planifiées restantes : blocs `pending` dont la fin est après
/// maintenant, tronqués à maintenant.
int remainingPlannedMin(List<ScheduleBlock> blocks, int nowMin) {
  var total = 0;
  for (final b in blocks) {
    if (b.status != 'pending') continue;
    final end = blockEndMin(b);
    if (end <= nowMin) continue;
    total += end - math.max(blockStartMin(b), nowMin);
  }
  return total;
}

/// Bornes de la frise, en heures pleines : de min(premier bloc, maintenant)
/// à max(dernier bloc, maintenant), plafonnées à 24 h.
({int startH, int endH}) timelineHours(List<ScheduleBlock> blocks, int nowMin) {
  var first = nowMin;
  var last = nowMin + 1;
  for (final b in blocks) {
    first = math.min(first, blockStartMin(b));
    last = math.max(last, blockEndMin(b));
  }
  final startH = (first ~/ 60).clamp(0, 23);
  final endH = ((last + 59) ~/ 60).clamp(startH + 1, 24);
  return (startH: startH, endH: endH);
}

/// Échelle en px/min : remplit [availablePx] mais jamais sous [minPpm]
/// (au-delà, la frise défile).
double timelinePxPerMin(double availablePx, int rangeMin,
    {double minPpm = 0.75}) {
  if (rangeMin <= 0) return minPpm;
  return math.max(availablePx / rangeMin, minPpm);
}

/// Minutes par catégorie (project · routine · personal · break), dans cet ordre,
/// sans les catégories vides.
List<({String category, int min})> minutesByCategory(List<ScheduleBlock> blocks) {
  final byCat = <String, int>{};
  for (final b in blocks) {
    byCat[b.category] = (byCat[b.category] ?? 0) + b.durationMin;
  }
  return [
    for (final c in const ['project', 'routine', 'personal', 'break'])
      if ((byCat[c] ?? 0) > 0) (category: c, min: byCat[c]!),
  ];
}

/// La session ouverte travaille-t-elle sur la SOURCE du bloc ? Tâche du bloc
/// (projet), sinon son activité, sinon l'activité liée du projet. Faux quand
/// on fait autre chose pendant le créneau (vaisselle pendant « Contenu ») :
/// la carte doit alors montrer les deux, et ne jamais cocher le bloc par
/// accident.
/// [activityLinkedActivityId] : activité-temps liée d'un bloc ROUTINE (le
/// chrono d'une routine tourne sur son activité liée, pas sur la routine).
bool sessionMatchesBlock(Session s, ScheduleBlock b,
    {String? projectLinkedActivityId, String? activityLinkedActivityId}) {
  if (b.timeBlock != null) return true; // bloc de temps : tout chrono compte
  if (b.taskId != null) return s.taskId == b.taskId;
  if (b.activityId != null) {
    return s.activityId == b.activityId ||
        (activityLinkedActivityId != null && s.activityId == activityLinkedActivityId);
  }
  if (projectLinkedActivityId != null) return s.activityId == projectLinkedActivityId;
  return false;
}

/// Temps loggué attribuable à UN bloc dans [start, end) — du plus précis au
/// plus large : `actionId` (chrono ciblé) → `taskId` (sessions de la tâche)
/// → `activityId` (total de l'activité, blocs routine/activité sans tâche).
/// Avant, l'activité primait : tous les blocs d'une même activité affichaient
/// (et se validaient sur) le même total, sans avoir été travaillés.
int loggedMinForBlock(ScheduleBlock b, Iterable<Session> sessions, DateTime start, DateTime end,
    {DateTime? now}) {
  bool Function(Session) match;
  if (b.timeBlock != null) {
    match = (_) => true; // bloc de temps : le chrono, quelle que soit l'activité
  } else if (b.actionId != null) {
    match = (s) => s.actionId == b.actionId;
  } else if (b.taskId != null) {
    match = (s) => s.taskId == b.taskId;
  } else if (b.activityId != null) {
    match = (s) => s.activityId == b.activityId;
  } else {
    return 0;
  }
  var sum = Duration.zero;
  for (final s in sessions.where(match)) {
    final e = s.endAt ?? (now ?? DateTime.now());
    if (s.startAt.isBefore(end) && e.isAfter(start)) {
      final st = s.startAt.isBefore(start) ? start : s.startAt;
      final en = e.isAfter(end) ? end : e;
      if (en.isAfter(st)) sum += en.difference(st);
    }
  }
  return sum.inMinutes;
}

/// Fenêtre (minutes depuis minuit) où le temps d'une source compte pour [b] :
/// seul bloc sur sa source (action, sinon tâche, sinon activité) ⇒ toute la
/// journée ; plusieurs blocs sur la même source (séance en deux blocs matin /
/// après-midi) ⇒ la journée est partagée à mi-chemin entre eux, pour qu'un
/// chrono du matin ne s'affiche pas aussi sur le bloc de l'après-midi.
({int start, int end}) blockLogWindow(ScheduleBlock b, Iterable<ScheduleBlock> blocks) {
  String? key(ScheduleBlock x) => x.actionId != null
      ? 'a:${x.actionId}'
      : x.taskId != null
          ? 't:${x.taskId}'
          : x.activityId != null
              ? 'v:${x.activityId}'
              : null;
  final k = key(b);
  if (k == null) return (start: 0, end: 24 * 60);
  final same = blocks.where((x) => x.status != 'deleted' && key(x) == k).toList();
  if (!same.any((x) => x.id == b.id)) same.add(b);
  if (same.length < 2) return (start: 0, end: 24 * 60);
  same.sort((x, y) => blockStartMin(x).compareTo(blockStartMin(y)));
  final i = same.indexWhere((x) => x.id == b.id);
  final start = i == 0 ? 0 : (blockEndMin(same[i - 1]) + blockStartMin(b)) ~/ 2;
  final end = i == same.length - 1
      ? 24 * 60
      : (blockEndMin(b) + blockStartMin(same[i + 1])) ~/ 2;
  return (start: start, end: end < start ? start : end);
}

/// « Caser demain » en un geste (2026-10) : les blocs du jour PASSÉS et non
/// faits (encore à faire, créneau fini à [nowMin]), hors miroirs d'agenda (ils
/// se déplacent dans l'agenda). L'encart du soir n'apparaît qu'à partir de 18 h
/// et de 2 blocs (`showCarryCard`).
List<ScheduleBlock> blocksToCarry(Iterable<ScheduleBlock> blocks, int nowMin) => [
      for (final b in blocks)
        if (b.status == 'pending' && b.gcalEventId == null && blockEndMin(b) <= nowMin) b,
    ];

bool showCarryCard(List<ScheduleBlock> carry, int nowMin) => nowMin >= 18 * 60 && carry.length >= 2;

/// Clé d'un rendez-vous d'agenda pour la mémoire « titre → activité »
/// (2026-10) : casse, accents de surface et espaces ignorés. Un événement
/// récurrent change d'id à chaque occurrence, pas de titre.
String mirrorKey(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Applique EN MÉMOIRE la mémoire `mirrorActivities` aux miroirs d'agenda du
/// jour encore libres (ni activité, ni projet, ni tâche — un miroir déjà relié
/// à une séance garde sa séance). Rien n'est écrit : valable pour chaque
/// occurrence d'un événement récurrent. Renvoie le nombre de blocs reliés.
int applyMirrorMemory(Iterable<ScheduleBlock> blocks, Map<String, String> memory) {
  if (memory.isEmpty) return 0;
  var n = 0;
  for (final b in blocks) {
    if (b.gcalEventId == null || b.activityId != null || b.projectId != null || b.taskId != null) continue;
    final id = memory[mirrorKey(b.title)];
    if (id == null) continue;
    b.activityId = id;
    n++;
  }
  return n;
}

/// Bloc pending dont le créneau contient [nowMin] (le premier), sinon null.
ScheduleBlock? currentBlockAt(List<ScheduleBlock> blocks, int nowMin) {
  for (final b in blocks) {
    if (b.status != 'pending' || b.status == 'deleted') continue;
    final s = blockStartMin(b);
    if (s <= nowMin && nowMin < s + b.durationMin) return b;
  }
  return null;
}

/// Bloc LIBRE en cours (essai 2026-10-30, retour user) : un chrono lancé
/// pendant un rendez-vous Google Agenda ou un bloc perso SANS source le
/// revendique en silence — le bloc prend l'activité du chrono et compte pour
/// lui. Libre = à faire, ni projet, ni tâche, ni activité, ni déroulé, bloc
/// normal (pas prép / séance / bilan / deep work), pas une pause, 3 h au plus
/// (jamais « Sommeil » 22:00 → 05:00), et DÉJÀ commencé à [nowMin].
const kFreeBlockClaimMaxMin = 180;

ScheduleBlock? freeBlockToClaim(List<ScheduleBlock> blocks, int nowMin) {
  for (final b in blocks) {
    if (b.status != 'pending') continue;
    if (b.projectId != null || b.taskId != null || b.activityId != null || b.sessionTemplateId != null || b.timeBlock != null) continue;
    if (b.kind != 'normal' || b.category == 'break') continue;
    if (b.durationMin > kFreeBlockClaimMaxMin) continue;
    final s = blockStartMin(b);
    if (s <= nowMin && nowMin < s + b.durationMin) return b;
  }
  return null;
}

/// Revendique [b] pour le chrono [s] : le bloc prend l'activité (et l'action)
/// du chrono ; la session ne change pas (elle garde sa tâche / son action).
void claimFreeBlock(ScheduleBlock b, Session s) {
  b.activityId = s.activityId;
  b.actionId = s.taskId == null ? s.actionId : null;
}

/// F1 — bloc qui porte le trait « maintenant » À L'INTÉRIEUR de sa carte
/// (liste mobile) : un bloc pending dont le créneau contient [nowMin]. Deux
/// blocs qui se chevauchent : celui qui a commencé en dernier. Null = trou
/// dans le programme, le trait se dessine entre les blocs.
ScheduleBlock? nowLineBlock(Iterable<ScheduleBlock> blocks, int nowMin) {
  ScheduleBlock? best;
  for (final b in blocks) {
    if (b.status != 'pending') continue;
    final s = blockStartMin(b);
    if (s <= nowMin && nowMin < s + b.durationMin) {
      if (best == null || s > blockStartMin(best)) best = b;
    }
  }
  return best;
}

/// Fenêtre d'anticipation : un chrono lancé moins de 15 min avant un bloc est
/// probablement pour lui (le cours de 14 h qu'on démarre à 13 h 55).
const int kBlockAttachLookaheadMin = 15;

/// Bloc auquel un chrono qui démarre à [nowMin] peut se rattacher : le bloc en
/// cours (`current: true`), sinon le premier bloc pending qui commence dans
/// les [lookaheadMin] prochaines minutes (`current: false`), sinon null.
({ScheduleBlock block, bool current})? blockToAttachAt(
    List<ScheduleBlock> blocks, int nowMin,
    {int lookaheadMin = kBlockAttachLookaheadMin}) {
  final cur = currentBlockAt(blocks, nowMin);
  if (cur != null) return (block: cur, current: true);
  ScheduleBlock? soon;
  for (final b in blocks) {
    if (b.status != 'pending') continue;
    final s = blockStartMin(b);
    if (s <= nowMin || s > nowMin + lookaheadMin) continue;
    if (soon == null || s < blockStartMin(soon)) soon = b;
  }
  return soon == null ? null : (block: soon, current: false);
}

/// Activité-temps sur laquelle doit tourner le chrono d'un bloc : son
/// activité si c'est une activité-temps, l'activité liée si c'est une routine,
/// sinon l'activité liée du projet. Null = le bloc n'impose pas d'activité.
String? blockChronoActivityId(ScheduleBlock b,
    {Activity? blockActivity, Project? project}) {
  if (b.activityId != null) {
    if (blockActivity == null) return b.activityId;
    return blockActivity.isHabit ? blockActivity.linkedActivityId : blockActivity.id;
  }
  return project?.linkedActivityId;
}

/// Peut-on rattacher une session à ce bloc ? Toujours, sauf une routine sans
/// activité liée (un chrono ne peut pas tourner « sur » une routine).
bool canAttachSessionToBlock(ScheduleBlock b,
    {Activity? blockActivity, Project? project}) {
  if (b.taskId != null) return true;
  if (blockActivity != null && blockActivity.isHabit) {
    return blockActivity.linkedActivityId != null;
  }
  return true;
}

/// Ce qu'un rattachement a modifié : rien (bloc non rattachable), la session
/// seule, ou la session ET le bloc (à persister tous les deux).
enum AttachResult { none, session, sessionAndBlock }

/// « Pour ce bloc » (chrono en cours ou session terminée) : **le chrono fait
/// foi**. La session GARDE son activité — c'est elle qui alimente les stats
/// par activité / domaine, et l'utilisateur l'a choisie en lançant le chrono
/// (la « Création de contenu » faite pendant un bloc « Préparation » reste de
/// la création de contenu). Elle prend la tâche et l'action du bloc ; quand le
/// bloc n'a pas de tâche et tourne sur une autre activité (ou aucune : miroir
/// Google Agenda, bloc perso), c'est le BLOC qui prend l'activité du chrono,
/// pour que [sessionMatchesBlock] devienne vrai. Seule exception : un bloc de
/// ROUTINE — une routine se reconnaît à son activité, la session bascule sur
/// l'activité liée de la routine (le +1 reste cohérent).
/// Mutation en mémoire : l'appelant persiste selon le résultat (session via
/// save ; bloc via `upsertScheduleBlock`, qui garde `subtitle` des miroirs).
AttachResult attachSessionToBlock(Session s, ScheduleBlock b,
    {Activity? blockActivity, Project? project}) {
  if (!canAttachSessionToBlock(b, blockActivity: blockActivity, project: project)) {
    return AttachResult.none;
  }
  if (b.taskId != null) {
    s.taskId = b.taskId;
    s.actionId = b.actionId;
    return AttachResult.session;
  }
  if (s.taskId != null) {
    s.taskId = null;
    s.actionId = null; // action de tâche : n'a plus de sens hors de sa tâche
  }
  if (blockActivity != null && blockActivity.isHabit) {
    s.actionId = b.actionId;
    s.activityId = blockActivity.linkedActivityId!;
    return AttachResult.session;
  }
  final linkAct = blockChronoActivityId(b, blockActivity: blockActivity, project: project);
  if (linkAct != null && linkAct == s.activityId) {
    s.actionId = b.actionId ?? s.actionId;
    return AttachResult.session;
  }
  b.activityId = s.activityId;
  b.actionId = s.actionId;
  return AttachResult.sessionAndBlock;
}

/// Blocs d'une journée auxquels une session (en cours ou TERMINÉE) peut être
/// rattachée après coup, les plus pertinents d'abord : chevauchement avec la
/// session (minutes) décroissant, puis proximité du début. Les blocs
/// **retirés du programme** (`status: deleted`, balayés pour alléger la page)
/// restent proposés, en fin de liste : on veut pouvoir rattacher un bloc déjà
/// passé. Seuls les blocs non rattachables sont exclus. [day] = minuit du
/// jour des blocs ; `overlapMin` = 0 si la session est hors du créneau.
List<({ScheduleBlock block, int overlapMin})> blockCandidatesForSession(
  Session s,
  List<ScheduleBlock> blocks,
  DateTime day, {
  Activity? Function(String? id)? activityOf,
  Project? Function(String? id)? projectOf,
}) {
  final sStart = s.startAt;
  final sEnd = s.endAt ?? DateTime.now();
  final out = <({ScheduleBlock block, int overlapMin})>[];
  for (final b in blocks) {
    if (!canAttachSessionToBlock(b,
        blockActivity: activityOf?.call(b.activityId), project: projectOf?.call(b.projectId))) {
      continue;
    }
    final bStart = day.add(Duration(minutes: blockStartMin(b)));
    final bEnd = day.add(Duration(minutes: blockEndMin(b)));
    final st = sStart.isAfter(bStart) ? sStart : bStart;
    final en = sEnd.isBefore(bEnd) ? sEnd : bEnd;
    final overlap = en.isAfter(st) ? en.difference(st).inMinutes : 0;
    out.add((block: b, overlapMin: overlap));
  }
  out.sort((x, y) {
    final xd = x.block.status == 'deleted', yd = y.block.status == 'deleted';
    if (xd != yd) return xd ? 1 : -1;
    if (x.overlapMin != y.overlapMin) return y.overlapMin.compareTo(x.overlapMin);
    final dx = (blockStartMin(x.block) - (sStart.hour * 60 + sStart.minute)).abs();
    final dy = (blockStartMin(y.block) - (sStart.hour * 60 + sStart.minute)).abs();
    return dx.compareTo(dy);
  });
  return out;
}

/// Ce POUR QUOI compte une session, bloc ou pas : « Tâche › action » (tâche de
/// projet, via `taskId` / `actionId`), « Activité › action propre » (`actionId`
/// seul), ou null si la session ne porte rien. Affiché dans « Modifier la
/// session » (mobile) et « Chronos du jour » (web) : un bloc peut avoir
/// disparu du programme, le lien à la tâche, lui, reste.
String? sessionTargetLabel(
  Session s, {
  required Iterable<Project> projects,
  required Iterable<Activity> activities,
}) {
  if (s.taskId != null) {
    for (final p in projects) {
      for (final t in p.tasks) {
        if (t.id != s.taskId) continue;
        final a = s.actionId == null
            ? null
            : t.actions.where((x) => x.id == s.actionId).firstOrNull;
        return a == null ? t.title : '${t.title} › ${a.title}';
      }
    }
    return 'Tâche introuvable';
  }
  if (s.actionId != null) {
    for (final act in activities) {
      if (act.id != s.activityId) continue;
      final a = act.ownActions.where((x) => x.id == s.actionId).firstOrNull;
      if (a != null) return '${act.name} › ${a.title}';
    }
    return 'Action introuvable';
  }
  return null;
}

/// B12 — le programme n'affiche que ce qui reste à faire ou ce qui a été fait.
/// Les blocs sautés ou déplacés (`status: skipped`) sortent de la vue et ne
/// laissent qu'un compteur en pied : « 2 blocs déplacés · 1 sauté ».
/// Déplacé = `movedTo` posé ou cause « reporte » ; sauté = le reste.
typedef AsideBlocks = ({
  List<ScheduleBlock> moved,
  List<ScheduleBlock> cancelled,
  List<ScheduleBlock> letGo,
  List<ScheduleBlock> skipped,
});

/// Cause d'un bloc ANNULÉ par l'utilisateur (« pas disponible ») : il sort du
/// programme sans report ni déplacement, et se rétablit d'un tap.
const kSkipUnavailable = 'indisponible';

/// Cause d'un bloc LÂCHÉ (2026-11-01, maquette « Lâcher un bloc ») : « j'aurais
/// pu, je choisis de ne pas le faire ». Il sort de la journée mais COMPTE comme
/// non fait (journée parfaite, Cap tenu) — à l'inverse d'« empêché »
/// ([kSkipUnavailable]), qui ne compte pas.
const kSkipLetGo = 'lache';

bool isLetGoBlock(ScheduleBlock b) => b.status == 'skipped' && b.skipReason == kSkipLetGo && b.movedTo == null;

bool isCancelledBlock(ScheduleBlock b) =>
    b.status == 'skipped' && b.skipReason == kSkipUnavailable && b.movedTo == null;

/// Un bloc s'annule s'il reste à faire et ne vient pas de l'agenda (un miroir
/// se gère dans Google Agenda).
bool canCancelBlock(ScheduleBlock b) => b.status == 'pending' && b.gcalEventId == null;

AsideBlocks asideBlocks(Iterable<ScheduleBlock> blocks) {
  final moved = <ScheduleBlock>[];
  final cancelled = <ScheduleBlock>[];
  final letGo = <ScheduleBlock>[];
  final skipped = <ScheduleBlock>[];
  for (final b in blocks) {
    if (b.status != 'skipped') continue;
    if (b.movedTo != null || b.skipReason == 'reporte') {
      moved.add(b);
    } else if (isCancelledBlock(b)) {
      cancelled.add(b);
    } else if (isLetGoBlock(b)) {
      letGo.add(b);
    } else {
      skipped.add(b);
    }
  }
  return (moved: moved, cancelled: cancelled, letGo: letGo, skipped: skipped);
}

/// Libellé du compteur de pied ; null s'il n'y a rien à tracer.
String? asideLabel(AsideBlocks a) {
  final parts = <String>[];
  for (final (c, w) in [
    (a.moved.length, 'déplacé'),
    (a.letGo.length, 'lâché'),
    (a.cancelled.length, 'empêché'),
    (a.skipped.length, 'sauté'),
  ]) {
    if (c == 0) continue;
    final pl = c > 1 ? 's' : '';
    parts.add(parts.isEmpty ? '$c bloc$pl $w$pl' : '$c $w$pl');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Ligne de détail d'un bloc écarté : heure prévue, titre, et où il est parti
/// ou pourquoi il a sauté.
String asideDetail(ScheduleBlock b) {
  final mt = b.movedTo;
  if (mt != null) return '→ ${mt['date'] ?? ''} ${mt['startTime'] ?? ''}'.trim();
  switch (b.skipReason) {
    case 'reporte':
      return '→ reporté au lendemain';
    case 'replanifie':
      return 'retiré à la replanification';
    case kSkipUnavailable:
      return '⛔ empêché · ne compte pas';
    case kSkipLetGo:
      return '✋ lâché · compte comme non fait';
    case null:
    case '':
      return 'sauté';
    default:
      return 'sauté · ${b.skipReason}';
  }
}

/// Liste du jour (mobile) : les blocs TERMINÉS depuis un moment sont repliés
/// en une ligne « Plus tôt » pour garder l'écran sur ce qui vient, sans les
/// perdre (le passé reste dans le programme : rattachement après coup, bilan).
/// Repliés = blocs finis avant [nowMin], sauf les [keep] derniers (contexte
/// immédiat). Les blocs non triés sont acceptés ; l'ordre du résultat suit
/// [blocks]. Rien n'est replié s'il n'y a pas plus de [keep] blocs finis.
({List<ScheduleBlock> folded, List<ScheduleBlock> shown}) foldEarlierBlocks(
    List<ScheduleBlock> blocks, int nowMin, {int keep = 2}) {
  final ended = blocks.where((b) => blockEndMin(b) <= nowMin).toList()
    ..sort((a, b) => blockEndMin(a).compareTo(blockEndMin(b)));
  if (ended.length <= keep) return (folded: const [], shown: blocks);
  final foldedIds = ended.sublist(0, ended.length - keep).map((b) => b.id).toSet();
  return (
    folded: blocks.where((b) => foldedIds.contains(b.id)).toList(),
    shown: blocks.where((b) => !foldedIds.contains(b.id)).toList(),
  );
}

/// « Décaler après ma parenthèse » : prochain quart d'heure ≥ maintenant, en
/// "HH:mm" ; null si le bloc ne tiendrait plus dans la journée.
String? shiftedStartAfter(int nowMin, int durationMin) {
  final start = ((nowMin + 14) ~/ 15) * 15;
  if (start + durationMin > 24 * 60) return null;
  return '${(start ~/ 60).toString().padLeft(2, '0')}:${(start % 60).toString().padLeft(2, '0')}';
}

/// Réveil au changement de bloc : à chaque tick (minute), signale qu'un bloc
/// VIENT de devenir courant alors que le chrono en cours ne lui correspond pas
/// — le cours de 14 h qui arrive pendant un chrono « Productivité » lancé à
/// 13 h 40. Une seule fois par couple session × bloc (réponse « parenthèse »
/// respectée, question déjà posée au `start()` non répétée) ; l'état trouvé au
/// premier tick avec un programme n'est jamais signalé (ouverture de l'app).
class BlockTransitionWatcher {
  String? _lastCurrentId;
  bool _primed = false;
  final Set<String> _asked = {};

  static String _key(Session s, ScheduleBlock b) => '${s.id}:${b.id}';

  /// À appeler quand la question a déjà été posée par un autre chemin.
  void markAsked(Session s, ScheduleBlock b) => _asked.add(_key(s, b));

  /// Bloc à proposer au chrono [open], ou null. [matches] = la règle
  /// `sessionMatchesBlock` avec ses activités liées résolues par l'appelant.
  ScheduleBlock? tick({
    required List<ScheduleBlock> blocks,
    required int nowMin,
    required Session? open,
    required bool Function(Session s, ScheduleBlock b) matches,
  }) {
    final cur = currentBlockAt(blocks, nowMin);
    final changed = _primed && cur != null && cur.id != _lastCurrentId;
    if (blocks.isNotEmpty) _primed = true;
    _lastCurrentId = cur?.id;
    if (!changed || open == null) return null;
    final key = _key(open, cur);
    if (_asked.contains(key) || matches(open, cur)) return null;
    _asked.add(key);
    return cur;
  }
}

/// Un bloc du jour suit l'action qu'il vise (sinon sa tâche, s'il n'en vise
/// aucune) : faite ⇒ bloc fait (`doneBy: "action"`), rouverte ⇒ un bloc coché
/// ainsi redevient à faire. Un bloc décoché à la main (`noAutoWin`) ou coché à
/// la main n'est jamais touché. Modifie [blocks] en place ; true si changé.
bool settleBlocksByWork(
  List<Map<String, dynamic>> blocks, {
  Map<String, bool> actions = const {},
  Map<String, bool> tasks = const {},
  required String nowIso,
}) {
  var changed = false;
  for (final b in blocks) {
    final aid = (b['actionId'] as String?) ?? '';
    final tid = (b['taskId'] as String?) ?? '';
    final bool? done = aid.isNotEmpty ? actions[aid] : (tid.isNotEmpty ? tasks[tid] : null);
    if (done == null) continue;
    final status = b['status'] ?? 'pending';
    if (done && status == 'pending' && b['noAutoWin'] != true) {
      b['status'] = 'done';
      b['doneAt'] = nowIso;
      b['doneBy'] = 'action';
      changed = true;
    } else if (!done && status == 'done' && b['doneBy'] == 'action') {
      b['status'] = 'pending';
      b.remove('doneAt');
      b.remove('doneBy');
      changed = true;
    }
  }
  return changed;
}

/// Frise : blocs qui se chevauchent posés côte à côte. Pour chaque bloc,
/// sa colonne et le nombre de colonnes de son groupe (blocs reliés par des
/// chevauchements). Un bloc seul = (0, 1).
Map<String, ({int col, int cols})> overlapColumns(List<ScheduleBlock> blocks) {
  final sorted = [...blocks]..sort((a, b) {
      final c = blockStartMin(a).compareTo(blockStartMin(b));
      return c != 0 ? c : blockEndMin(b).compareTo(blockEndMin(a));
    });
  final out = <String, ({int col, int cols})>{};
  var group = <ScheduleBlock>[];
  var colOf = <String, int>{};
  var colEnds = <int>[];
  var groupEnd = -1;
  void flush() {
    for (final b in group) {
      out[b.id] = (col: colOf[b.id]!, cols: colEnds.length);
    }
    group = [];
    colOf = {};
    colEnds = [];
  }

  for (final b in sorted) {
    final start = blockStartMin(b);
    if (group.isNotEmpty && start >= groupEnd) flush();
    var col = colEnds.indexWhere((end) => end <= start);
    if (col < 0) {
      col = colEnds.length;
      colEnds.add(blockEndMin(b));
    } else {
      colEnds[col] = blockEndMin(b);
    }
    colOf[b.id] = col;
    group.add(b);
    groupEnd = group.length == 1 ? blockEndMin(b) : math.max(groupEnd, blockEndMin(b));
  }
  flush();
  return out;
}
