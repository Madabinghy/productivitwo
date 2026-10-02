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

/// Peut-on rattacher une session à ce bloc de façon à ce que
/// [sessionMatchesBlock] devienne vrai ? Faux pour un bloc libre (ni tâche,
/// ni activité-temps, ni projet avec activité liée).
bool canAttachSessionToBlock(ScheduleBlock b,
    {Activity? blockActivity, Project? project}) {
  if (b.taskId != null) return true;
  return blockChronoActivityId(b, blockActivity: blockActivity, project: project) != null;
}

/// « Pour ce bloc » : ré-attribue la session EN COURS au bloc — elle porte
/// désormais la tâche et l'action du bloc, et tourne sur son activité-temps
/// quand le bloc en impose une. Le temps compte alors pour le bloc (et peut le
/// valider). Mutation en mémoire : l'appelant persiste (`onChange` / save).
/// Retourne false (sans rien toucher) si le bloc n'est pas rattachable.
bool attachSessionToBlock(Session s, ScheduleBlock b,
    {Activity? blockActivity, Project? project}) {
  if (!canAttachSessionToBlock(b, blockActivity: blockActivity, project: project)) {
    return false;
  }
  s.taskId = b.taskId;
  s.actionId = b.actionId;
  final act = blockChronoActivityId(b, blockActivity: blockActivity, project: project);
  if (act != null) s.activityId = act;
  return true;
}

/// « Décaler après ma parenthèse » : prochain quart d'heure ≥ maintenant, en
/// "HH:mm" ; null si le bloc ne tiendrait plus dans la journée.
String? shiftedStartAfter(int nowMin, int durationMin) {
  final start = ((nowMin + 14) ~/ 15) * 15;
  if (start + durationMin > 24 * 60) return null;
  return '${(start ~/ 60).toString().padLeft(2, '0')}:${(start % 60).toString().padLeft(2, '0')}';
}

/// Où écrire quand l'utilisateur dit « Pour ce bloc » :
/// - [session] : le bloc a une source (tâche, activité-temps, routine liée,
///   projet lié) → la session est réécrite dessus (`attachSessionToBlock`) ;
/// - [block] : bloc LIBRE (import Google Agenda, bloc perso, projet sans
///   activité liée) → le bloc prend l'activité du chrono (`attachBlockToSession`) ;
/// - null : rien à faire (routine sans activité liée).
enum AttachTarget { session, block }

AttachTarget? attachTargetFor(ScheduleBlock b,
    {Activity? blockActivity, Project? project}) {
  if (canAttachSessionToBlock(b, blockActivity: blockActivity, project: project)) {
    return AttachTarget.session;
  }
  if (b.taskId == null && b.activityId == null) return AttachTarget.block;
  return null;
}

/// « Pour ce bloc » sur un bloc libre : le bloc devient un bloc de l'activité
/// du chrono (et de son action propre, le cas échéant), donc
/// [sessionMatchesBlock] devient vrai. Mutation en mémoire : l'appelant
/// persiste le bloc (`upsertScheduleBlock`). Les miroirs Google Agenda gardent
/// ce lien : la resynchronisation ne touche qu'heure, durée et titre.
bool attachBlockToSession(ScheduleBlock b, Session s) {
  if (b.taskId != null || b.activityId != null) return false;
  b.activityId = s.activityId;
  b.actionId = s.taskId == null ? s.actionId : null;
  return true;
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
