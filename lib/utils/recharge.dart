import 'package:productivitwo_v1/models.dart';

/// Recharge (maquette validée 2026-10-30) : la nuit sort des modes. Du début
/// du sommeil (bloc « Sommeil » ou chrono Sommeil, après le dernier pointage)
/// jusqu'au premier geste du matin, la personne n'est ni en Flemme, ni en
/// Normal : elle recharge. Rien n'est stocké. Pour les statistiques, la recharge
/// est un pointage VIRTUEL de valeur [kRechargeValue] qui ferme le dernier
/// pointage du jour : la nuit ne pèse plus dans l'élan, ni dans la flemme.
/// Une sieste (« Sieste ») est un repos : un bloc de sieste fait n'est pas une
/// victoire sur la flemme. Logique pure.
const kRechargeValue = 0;

String _norm(String? s) => (s ?? '')
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u');

/// Un nom de sommeil de nuit : « Sommeil », « Dormir », « Nuit », « Coucher ».
bool isSleepName(String? s) {
  final n = _norm(s);
  return n.startsWith('sommeil') || n.startsWith('dormir') || n.startsWith('nuit') || n.startsWith('coucher');
}

/// Un repos : sommeil de nuit ou sieste.
bool isRestName(String? s) => isSleepName(s) || _norm(s).startsWith('sieste');

/// Un besoin de base (2026-10-30, retour user) : repos ou repas (« Manger »,
/// « Repas », « Déjeuner », « Dîner », « Petit-déjeuner », « Goûter »). Ne vaut
/// jamais une victoire sur la flemme. « Cuisiner » n'en est pas un : c'est un effort.
bool isBasicNeedName(String? s) {
  if (isRestName(s)) return true;
  final n = _norm(s);
  return n.startsWith('manger') || n.startsWith('repas') || n.startsWith('dejeuner') || n.startsWith('diner') ||
      n.startsWith('petit-dej') || n.startsWith('petit dej') || n.startsWith('gouter');
}

/// Un bloc de besoin de base (titre ou activité).
bool isBasicNeedBlock(ScheduleBlock b, Map<String, Activity> activitiesById) =>
    isBasicNeedName(b.title) || isBasicNeedName(activitiesById[b.activityId]?.name);

/// Un bloc de repos (titre ou activité) : ne compte jamais comme une chose
/// faite malgré la flemme.
bool isRestBlock(ScheduleBlock b, Map<String, Activity> activitiesById) =>
    isRestName(b.title) || isRestName(activitiesById[b.activityId]?.name);


/// Débuts de sommeil d'une journée vécue qui commence à [dayStart] : les
/// chronos Sommeil lancés dans la journée vécue. Depuis le 2026-10-31, le bloc
/// Sommeil du programme ne démarre plus la recharge (on ne se couche pas pile à
/// l'heure) : Aujourd'hui propose « Je vais me coucher » (`bedtimePrompt`).
List<DateTime> sleepStartsOf({
  required DateTime dayStart,
  required List<Session> sessions,
  required Map<String, Activity> activitiesById,
}) {
  final dayEnd = dayStart.add(const Duration(days: 1));
  return [
    for (final s in sessions)
      if (!s.deleted && isSleepName(activitiesById[s.activityId]?.name) && !s.startAt.isBefore(dayStart) && s.startAt.isBefore(dayEnd)) s.startAt,
  ]..sort();
}

/// Début de la recharge d'une journée vécue : le premier début de sommeil
/// qui suit le dernier pointage d'élan réel du jour (« Pas encore couché »
/// repousse donc la recharge au prochain chrono Sommeil). Null sinon.
DateTime? rechargeStart({required List<DateTime> sleepStarts, required List<MoodMark> dayMarks}) {
  DateTime? last;
  for (final m in dayMarks) {
    if (!m.isElan || m.value == kRechargeValue) continue;
    if (last == null || m.at.isAfter(last)) last = m.at;
  }
  for (final t in sleepStarts) {
    if (last == null || !t.isBefore(last)) return t;
  }
  return null;
}

/// Pointages d'élan + un pointage virtuel de recharge par journée vécue
/// ([rechargeByYmd], déjà commencée à [now]). Pour les statistiques seulement.
List<MoodMark> withRechargeMarks(List<MoodMark> marks, Map<String, DateTime> rechargeByYmd, DateTime now) => [
      ...marks,
      for (final e in rechargeByYmd.entries)
        if (!e.value.isAfter(now)) MoodMark(id: 'recharge:${e.key}', at: e.value, ymd: e.key, kind: kMoodElan, value: kRechargeValue),
    ];

/// Recharges des journées vécues de [schedulesByYmd] (docs du programme par
/// `YYYY-MM-DD`), d'après les blocs et chronos Sommeil.
Map<String, DateTime> rechargeByYmd({
  required Map<String, DailySchedule> schedulesByYmd,
  required List<MoodMark> marks,
  required List<Session> sessions,
  required List<Activity> activities,
  required int dayStartMin,
  Iterable<String> extraYmds = const [],
}) {
  final byId = {for (final a in activities) a.id: a};
  final out = <String, DateTime>{};
  final ymds = {...schedulesByYmd.keys, ...extraYmds, for (final m in marks) if (m.isElan) m.ymd};
  for (final ymd in ymds) {
    final day = DateTime.tryParse(ymd);
    if (day == null) continue;
    final dayStart = DateTime(day.year, day.month, day.day).add(Duration(minutes: dayStartMin));
    final starts = sleepStartsOf(
      dayStart: dayStart,
      sessions: sessions,
      activitiesById: byId,
    );
    final r = rechargeStart(sleepStarts: starts, dayMarks: [for (final m in marks) if (m.ymd == ymd) m]);
    if (r != null) out[ymd] = r;
  }
  return out;
}

/// En recharge MAINTENANT, et depuis quand (null = non) : le soir, dès le début
/// du sommeil sans pointage depuis ; la nuit, tant qu'un chrono Sommeil tourne ;
/// le matin, jusqu'au premier geste (pointage, +1, chrono hors sommeil, bloc
/// fait) — [lastSleepStart] donne alors l'heure du coucher si elle est connue.
DateTime? rechargeSince({
  required DateTime now,
  required DateTime dayStart,
  required List<DateTime> sleepStarts,
  required List<MoodMark> dayMarks,
  required List<Session> sessions,
  required List<HabitHit> hits,
  required List<ScheduleBlock> blocks,
  required Map<String, Activity> activitiesById,
  DateTime? lastSleepStart,
}) {
  final realMarks = dayMarks.where((m) => m.isElan && m.value != kRechargeValue).toList();
  final r = rechargeStart(sleepStarts: sleepStarts, dayMarks: realMarks);
  if (r != null && !r.isAfter(now)) return r;
  final running = sessions.where((s) => !s.deleted && s.endAt == null).toList();
  for (final s in running) {
    if (isSleepName(activitiesById[s.activityId]?.name) && !realMarks.any((m) => m.at.isAfter(s.startAt))) return s.startAt;
  }
  if (realMarks.isNotEmpty) return null;
  if (hits.any((h) => !h.ts.isBefore(dayStart) && !h.ts.isAfter(now))) return null;
  final awake = sessions.any((s) => !s.deleted && !s.startAt.isBefore(dayStart) && !isRestName(activitiesById[s.activityId]?.name));
  if (awake) return null;
  final done = blocks.any((b) => b.status == 'done' && b.doneAt != null && !b.doneAt!.isBefore(dayStart) && !isRestBlock(b, activitiesById));
  if (done) return null;
  return lastSleepStart ?? dayStart;
}

// ── Aller se coucher (2026-10-31) ─────────────────────────────────────────────

/// Ce que la carte du soir propose avant le bloc Sommeil.
enum BedtimeStep { plan, bed }

/// La carte « Je vais me coucher » d'Aujourd'hui, avant le bloc Sommeil du
/// programme ([sleepAt]) : une heure avant, si demain n'est pas posé
/// ([planned]), proposer de planifier ; une fois posé (ou dès 30 min avant),
/// proposer d'aller se coucher. Visible jusqu'à 3 h après l'heure du bloc,
/// jamais en recharge, jamais quand la personne a dit « Pas encore »
/// ([snoozedUntil]). Null = rien à proposer.
BedtimeStep? bedtimePrompt({
  required DateTime now,
  required DateTime? sleepAt,
  required bool planned,
  required bool inRecharge,
  DateTime? snoozedUntil,
}) {
  if (sleepAt == null || inRecharge) return null;
  if (snoozedUntil != null && now.isBefore(snoozedUntil)) return null;
  final before = sleepAt.difference(now).inMinutes;
  if (before > 60 || before < -180) return null;
  if (!planned) return BedtimeStep.plan;
  return BedtimeStep.bed;
}
