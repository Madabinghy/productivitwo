import 'package:productivitwo_v1/models.dart';

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
  dismiss, // « À la volée » — masque la carte pour la matinée
}

class CoachAction {
  final String label;
  final CoachActionKind kind;
  final ScheduleBlock? block;
  final CoachMomentType? target;
  const CoachAction(this.label, this.kind, {this.block, this.target});
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

/// [advancedTo] = avance manuelle via le CTA de transition de la carte
/// (« Attaquer la journée », « Pause de midi »…) : le user peut faire avancer
/// la journée AVANT l'horloge (levé à 5h → carte matin sans attendre 9h).
/// L'avance ne peut jamais reculer, et l'horloge la rattrape naturellement.
/// [unplannedDismissed] : le user a tapé « À la volée » sur la carte
/// « journée non planifiée » — on ne la re-propose pas de la matinée.
CoachMoment computeCoachMoment(
  DateTime now,
  AppState st,
  DailySchedule? today,
  DailySchedule? yesterday,
  List<Session> recentSessions, {
  CoachMomentType? advancedTo,
  bool unplannedDismissed = false,
}) {
  final minutes = now.hour * 60 + now.minute;
  final blocks = _liveBlocks(today);
  final sessionsToday =
      recentSessions.where((s) => _sameDay(s.startAt, now)).toList();
  // Minimum vital hebdo des domaines définis — affiché midi et soir.
  final vitals = _vitalStats(now, st, recentSessions);

  // 00h–1h : fin de soirée pour les couche-tard — même carte check-in, mais le
  // doc du jour a basculé à minuit : les blocs prep « de ce soir » vivent dans
  // le programme d'HIER (et leur bloc cible est désormais ce matin).
  if (minutes < 60) return _eveningMoment(_liveBlocks(yesterday), const []);
  if (minutes < 5 * 60) return CoachMoment.none; // nuit (1h–5h)

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
    clock = _eveningMoment(blocks, vitals);
  } else if (minutes >= 14 * 60) {
    clock = _driftMoment(now, blocks, sessionsToday) ??
        _afternoonMoment(now, blocks);
  } else if (minutes >= 11 * 60 + 45) {
    clock = _middayMoment(now, blocks, recentSessions, vitals);
  } else if (minutes >= 9 * 60) {
    clock = _morningMoment(now, blocks);
  } else {
    clock = _wakeMoment(now, blocks, yesterday, today);
  }

  // Avance manuelle : ne s'applique que si elle est PLUS LOIN dans la journée
  // que l'horloge (sinon elle est périmée). Avancer en soirée fait aussi taire
  // une éventuelle dérive (le user a explicitement clos son après-midi).
  if (advancedTo != null && _dayOrder(advancedTo) > _dayOrder(clock.type)) {
    switch (advancedTo) {
      case CoachMomentType.morning:
        return _morningMoment(now, blocks);
      case CoachMomentType.midday:
        return _middayMoment(now, blocks, recentSessions, vitals);
      case CoachMomentType.afternoon:
        return _afternoonMoment(now, blocks);
      case CoachMomentType.evening:
        return _eveningMoment(blocks, vitals);
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
      CoachMomentType.evening => 4,
      CoachMomentType.hidden => -1,
    };

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

CoachMoment _morningMoment(DateTime now, List<ScheduleBlock> blocks) {
  const advance = CoachAction('Pause de midi', CoachActionKind.advanceMoment,
      target: CoachMomentType.midday);
  final firstDone = _firstDoneEngagement(blocks);
  if (firstDone != null) {
    final at = firstDone.doneAt;
    final atStr = at != null ? ' à ${_hhmmToFr(_hm(at))}' : '';
    return CoachMoment(
      type: CoachMomentType.morning,
      tagLabel: 'ORION · MATIN',
      message:
          '${firstDone.title} fait$atStr — la journée est lancée, c\'est ça qu\'on voulait.',
      actions: const [advance],
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
    List<Session> recentSessions, List<StatItem> vitals) {
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
  final message = key != null
      ? 'L\'après-midi n\'a qu\'une chose à tenir : ${key.title}. Tout le reste est du bonus.'
      : 'Belle matinée. L\'après-midi est à toi.';

  final actions = <CoachAction>[];
  if (key != null && _launchable(key)) {
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
  const advance = CoachAction('Passer en soirée',
      CoachActionKind.advanceMoment,
      target: CoachMomentType.evening);
  final next = _firstEngagement(now, blocks);
  if (next == null) {
    // Quick fix (constaté sur build) : à 14h46 sans programme, proposer
    // « Passer en soirée » abdique la demi-journée — la soirée commence à 19h.
    // On propose de PLANIFIER l'après-midi ; la transition reste en secondaire.
    return const CoachMoment(
      type: CoachMomentType.afternoon,
      tagLabel: 'ORION · APRÈS-MIDI',
      message:
          'Rien de posé pour la suite. 2 minutes et l\'après-midi a une colonne vertébrale.',
      actions: [
        CoachAction('Planifier l\'après-midi · 2 min', CoachActionKind.planDay),
        advance,
      ],
      tone: CoachTone.neutral,
    );
  }
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
      advance,
    ],
    tone: CoachTone.neutral,
  );
}

CoachMoment _eveningMoment(List<ScheduleBlock> blocks, List<StatItem> vitals) {
  final pendingPreps =
      blocks.where((b) => b.isPrep && b.status == 'pending').length;
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

/// Minimum vital hebdo des domaines définis, vérifié par les données réelles :
/// une « séance » = une session ≥ 10 min sur une activité du domaine, semaine
/// courante (lundi → maintenant). V1 : métriques `sessions*` / period `week`
/// uniquement — le reste est omis (jamais de chiffre inventé). Max 2 stats.
List<StatItem> _vitalStats(DateTime now, AppState st, List<Session> sessions) {
  final stats = <StatItem>[];
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  for (final d in st.domains) {
    if (d.deleted || !d.isDefined) continue;
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
      stats.add(StatItem(d.name, '$count/${v.target.toInt()} · sem.',
          sub: v.label));
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
