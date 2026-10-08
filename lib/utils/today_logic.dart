import 'dart:math' as math;

import 'package:productivitwo_v1/models.dart';

/// Logique pure de la vue Aujourd'hui (refonte web § 2) — testable sans widget.
/// Les minutes sont comptées depuis minuit ; les blocs `deleted` doivent avoir
/// été filtrés en amont (cf. `DailySchedule` : soft-delete).

/// Minute de début d'un bloc ("HH:mm" → minutes). Format invalide → 0.
int blockStartMin(ScheduleBlock b) {
  final parts = b.startTime.split(':');
  if (parts.length < 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
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
  if (b.actionId != null) {
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

/// Bloc pending dont le créneau contient [nowMin] (le premier), sinon null.
ScheduleBlock? currentBlockAt(List<ScheduleBlock> blocks, int nowMin) {
  for (final b in blocks) {
    if (b.status != 'pending' || b.status == 'deleted') continue;
    final s = blockStartMin(b);
    if (s <= nowMin && nowMin < s + b.durationMin) return b;
  }
  return null;
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
({List<ScheduleBlock> moved, List<ScheduleBlock> skipped}) asideBlocks(
    Iterable<ScheduleBlock> blocks) {
  final moved = <ScheduleBlock>[];
  final skipped = <ScheduleBlock>[];
  for (final b in blocks) {
    if (b.status != 'skipped') continue;
    (b.movedTo != null || b.skipReason == 'reporte' ? moved : skipped).add(b);
  }
  return (moved: moved, skipped: skipped);
}

/// Libellé du compteur de pied ; null s'il n'y a rien à tracer.
String? asideLabel(({List<ScheduleBlock> moved, List<ScheduleBlock> skipped}) a) {
  final parts = <String>[];
  if (a.moved.isNotEmpty) {
    parts.add('${a.moved.length} bloc${a.moved.length > 1 ? 's' : ''} déplacé${a.moved.length > 1 ? 's' : ''}');
  }
  if (a.skipped.isNotEmpty) {
    parts.add(a.moved.isEmpty
        ? '${a.skipped.length} bloc${a.skipped.length > 1 ? 's' : ''} sauté${a.skipped.length > 1 ? 's' : ''}'
        : '${a.skipped.length} sauté${a.skipped.length > 1 ? 's' : ''}');
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
