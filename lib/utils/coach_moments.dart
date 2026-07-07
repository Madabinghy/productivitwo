import 'package:productivitwo_v1/models.dart';

// ─── CARTE COACH « MAINTENANT » ──────────────────────────────────────────────
//
// Fonction pure, testable unitairement : à partir de l'heure courante, de l'état
// et des programmes du jour / de la veille + des sessions récentes, elle calcule
// LE moment de coaching à afficher. Aucun appel réseau ni LLM — les textes sont
// des templates avec les chiffres RÉELS (jamais inventés ; une donnée absente est
// omise, pas remplie). Le déterministe relance, fiable et à coût zéro.

enum CoachTone { neutral, positive, alert }

enum CoachMomentType { wake, morning, midday, drift, afternoon, evening, hidden }

/// Une action proposée par la carte. [block] cible le bloc concerné (chrono
/// ciblé, renégociation…).
enum CoachActionKind { launchBlock, openDayReview, renegotiate }

class CoachAction {
  final String label;
  final CoachActionKind kind;
  final ScheduleBlock? block;
  const CoachAction(this.label, this.kind, {this.block});
}

class StatItem {
  final String label;
  final String value;
  final String? sub;
  const StatItem(this.label, this.value, {this.sub});
}

class CoachMoment {
  final CoachMomentType type;
  final String tagLabel; // micro-label émeraude/gris (« ORION · RÉVEIL »)
  final String? title;
  final String message;
  final List<StatItem> stats;
  final List<CoachAction> actions;
  final CoachTone tone;

  const CoachMoment({
    required this.type,
    required this.tagLabel,
    this.title,
    required this.message,
    this.stats = const [],
    this.actions = const [],
    this.tone = CoachTone.neutral,
  });

  bool get hidden => type == CoachMomentType.hidden;

  static const CoachMoment none = CoachMoment(
      type: CoachMomentType.hidden, tagLabel: '', message: '');
}

// ── Point d'entrée ────────────────────────────────────────────────────────────

CoachMoment computeCoachMoment(
  DateTime now,
  AppState st,
  DailySchedule? today,
  DailySchedule? yesterday,
  List<Session> recentSessions,
) {
  final minutes = now.hour * 60 + now.minute;
  final blocks = _liveBlocks(today);
  final sessionsToday =
      recentSessions.where((s) => _sameDay(s.startAt, now)).toList();

  // drift prime sur morning/midday/afternoon dans sa fenêtre (14:00–19:00).
  if (minutes >= 14 * 60 && minutes < 19 * 60) {
    final drift = _driftMoment(now, blocks, sessionsToday);
    if (drift != null) return drift;
  }

  if (minutes >= 5 * 60 && minutes < 9 * 60) {
    return _wakeMoment(now, blocks, yesterday, today);
  }
  if (minutes >= 9 * 60 && minutes < 11 * 60 + 45) {
    return _morningMoment(now, blocks);
  }
  if (minutes >= 11 * 60 + 45 && minutes < 14 * 60) {
    return _middayMoment(now, blocks, recentSessions);
  }
  if (minutes >= 14 * 60 && minutes < 19 * 60) {
    return _afternoonMoment(now, blocks);
  }
  if (minutes >= 19 * 60 && minutes < 23 * 60) {
    return _eveningMoment(blocks);
  }
  return CoachMoment.none; // nuit
}

// ── Moments ───────────────────────────────────────────────────────────────────

CoachMoment _wakeMoment(DateTime now, List<ScheduleBlock> blocks,
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
    final whenStr = mins > 0 ? 'dans $mins min' : 'maintenant';
    stats.add(StatItem('Premier bloc', _hhmmToFr(first.startTime),
        sub: first.title));
    final prepSuffix =
        prepReady ? ', les affaires sont prêtes depuis hier' : '';
    message =
        'Là tout de suite : ${first.title} $whenStr$prepSuffix. On y va tranquille.';
    if (_launchable(first)) {
      actions.add(CoachAction('Lancer', CoachActionKind.launchBlock,
          block: first));
    }
  } else {
    message = prepReady
        ? 'Journée libre côté programme — mais les affaires sont prêtes depuis hier, prêt à démarrer.'
        : 'Nouvelle journée. Prends une minute pour poser ton premier bloc.';
  }

  return CoachMoment(
    type: CoachMomentType.wake,
    tagLabel: 'ORION · RÉVEIL',
    message: message,
    stats: stats,
    actions: actions,
    tone: CoachTone.neutral,
  );
}

CoachMoment _morningMoment(DateTime now, List<ScheduleBlock> blocks) {
  final firstDone = _firstDoneEngagement(blocks);
  if (firstDone != null) {
    final at = firstDone.doneAt;
    final atStr = at != null ? ' à ${_hhmmToFr(_hm(at))}' : '';
    return CoachMoment(
      type: CoachMomentType.morning,
      tagLabel: 'ORION · MATIN',
      message:
          '${firstDone.title} fait$atStr — la journée est lancée, c\'est ça qu\'on voulait.',
      tone: CoachTone.positive,
    );
  }
  // Carte réduite : le prochain bloc seulement.
  final next = _firstEngagement(now, blocks);
  final actions = <CoachAction>[];
  String message;
  final stats = <StatItem>[];
  if (next != null) {
    final mins = _minutesUntil(now, next.startTime);
    final whenStr = mins > 0 ? 'dans $mins min' : 'maintenant';
    stats.add(StatItem('Prochain', _hhmmToFr(next.startTime), sub: next.title));
    message = 'Prochain rendez-vous : ${next.title} $whenStr.';
    if (_launchable(next)) {
      actions.add(
          CoachAction('Lancer', CoachActionKind.launchBlock, block: next));
    }
  } else {
    message = 'Matinée libre. Choisis une chose à faire avancer.';
  }
  return CoachMoment(
    type: CoachMomentType.morning,
    tagLabel: 'ORION · MATIN',
    message: message,
    stats: stats,
    actions: actions,
    tone: CoachTone.neutral,
  );
}

CoachMoment _middayMoment(
    DateTime now, List<ScheduleBlock> blocks, List<Session> recentSessions) {
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
  ];

  final key = _afternoonKeyBlock(now, blocks);
  final message = key != null
      ? 'L\'après-midi n\'a qu\'une chose à tenir : ${key.title}. Tout le reste est du bonus.'
      : 'Belle matinée. L\'après-midi est à toi.';

  final actions = <CoachAction>[];
  if (key != null && _launchable(key)) {
    actions
        .add(CoachAction('Lancer', CoachActionKind.launchBlock, block: key));
  }

  return CoachMoment(
    type: CoachMomentType.midday,
    tagLabel: 'ORION · RAPPORT DE MATINÉE',
    message: message,
    stats: stats,
    actions: actions,
    tone: CoachTone.positive,
  );
}

/// Retourne un moment `drift` si un bloc source est posé depuis > 45 min avec
/// 0 min logguée, sinon null.
CoachMoment? _driftMoment(
    DateTime now, List<ScheduleBlock> blocks, List<Session> sessionsToday) {
  ScheduleBlock? drifting;
  DateTime? driftStart;
  for (final b in blocks) {
    if (b.status != 'pending') continue;
    if (b.activityId == null && b.taskId == null) continue;
    final start = _blockStart(b, now);
    if (now.difference(start).inMinutes <= 45) continue;
    final logged = _blockLoggedMin(b, sessionsToday, start, now);
    if (logged > 0) continue;
    if (driftStart == null || start.isBefore(driftStart)) {
      drifting = b;
      driftStart = start;
    }
  }
  if (drifting == null || driftStart == null) return null;

  final actions = <CoachAction>[
    if (_launchable(drifting))
      CoachAction('Lancer 25 min', CoachActionKind.launchBlock, block: drifting),
    CoachAction('Renégocier', CoachActionKind.renegotiate, block: drifting),
  ];

  return CoachMoment(
    type: CoachMomentType.drift,
    tagLabel: 'ORION · DÉRIVE DÉTECTÉE',
    title: drifting.title,
    message:
        'Le bloc « ${drifting.title} » est posé depuis ${_hhmmToFr(drifting.startTime)} — 0 min logguée. 25 minutes suffisent pour l\'enclencher.',
    actions: actions,
    tone: CoachTone.alert,
  );
}

CoachMoment _afternoonMoment(DateTime now, List<ScheduleBlock> blocks) {
  final next = _firstEngagement(now, blocks);
  if (next == null) return CoachMoment.none;
  final mins = _minutesUntil(now, next.startTime);
  final whenStr = mins > 0 ? 'dans $mins min' : 'maintenant';
  return CoachMoment(
    type: CoachMomentType.afternoon,
    tagLabel: 'ORION · APRÈS-MIDI',
    message: 'Prochain : ${next.title} $whenStr.',
    stats: [StatItem('Prochain', _hhmmToFr(next.startTime), sub: next.title)],
    actions: [
      if (_launchable(next))
        CoachAction('Lancer', CoachActionKind.launchBlock, block: next),
    ],
    tone: CoachTone.neutral,
  );
}

CoachMoment _eveningMoment(List<ScheduleBlock> blocks) {
  final pendingPreps =
      blocks.where((b) => b.isPrep && b.status == 'pending').length;
  final stats = <StatItem>[
    if (pendingPreps > 0)
      StatItem('À préparer', '$pendingPreps bloc${pendingPreps > 1 ? 's' : ''}'),
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

/// Le bloc-clé de l'après-midi : premier bloc pending à partir de 12h, projet en
/// priorité.
ScheduleBlock? _afternoonKeyBlock(DateTime now, List<ScheduleBlock> blocks) {
  final noon = DateTime(now.year, now.month, now.day, 12);
  final afternoon = blocks
      .where((b) =>
          !b.isPrep &&
          b.category != 'break' &&
          b.status == 'pending' &&
          !_blockStart(b, now).isBefore(noon))
      .toList();
  if (afternoon.isEmpty) return null;
  final projects = afternoon.where((b) => b.category == 'project').toList();
  return (projects.isNotEmpty ? projects : afternoon).first;
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
    DateTime now) {
  var total = 0;
  for (final s in sessions) {
    final matches = (b.activityId != null && s.activityId == b.activityId) ||
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
