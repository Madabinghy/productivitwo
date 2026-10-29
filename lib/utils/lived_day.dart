import 'package:productivitwo_v1/models.dart' show yyyymmdd, DailySchedule, ScheduleBlock, HabitHit;

/// Journée vécue (2026-10) : la journée des ROUTINES ne bascule pas à minuit
/// mais à l'heure réglée par l'utilisateur (`data/meta.dayStartMin`, défaut
/// 5 h — la règle que les stats appliquaient déjà). Avant cette heure, on est
/// encore « hier » : compte du jour, moment courant (« ce soir » et non « ce
/// matin »), reports et « pas aujourd'hui » tiennent. Le programme du jour,
/// lui, reste sur la date calendaire (un doc par date, blocs qui passent
/// minuit déjà gérés). Quelqu'un qui travaille de nuit règle 8 h ou 10 h.
const int kDefaultDayStartMin = 5 * 60;
const int kDayStartMinMax = 12 * 60;

/// Lit `data/meta.dayStartMin` : entier 0 → 12 h, sinon le défaut.
int parseDayStartMin(dynamic raw) {
  final n = raw is num ? raw.toInt() : int.tryParse('$raw');
  if (n == null || n < 0 || n > kDayStartMinMax) return kDefaultDayStartMin;
  return n;
}

/// Date (jour seul) de la journée vécue contenant [now].
DateTime livedDate(DateTime now, int dayStartMin) {
  final nowMin = now.hour * 60 + now.minute;
  final d = nowMin < dayStartMin ? now.subtract(const Duration(days: 1)) : now;
  return DateTime(d.year, d.month, d.day);
}

/// Début de la journée vécue contenant [now] (hier à l'heure de bascule si on
/// est avant elle).
DateTime livedDayStart(DateTime now, int dayStartMin) =>
    livedDate(now, dayStartMin).add(Duration(minutes: dayStartMin));

/// Clé `YYYYMMDD` de la journée vécue (état du jour des routines).
String livedYmd(DateTime now, int dayStartMin) => yyyymmdd(livedDate(now, dayStartMin));

/// Clé `YYYY-MM-DD` du PROGRAMME de la journée vécue (`daily_schedules`) :
/// jusqu'à la bascule, « aujourd'hui » reste le programme de la veille.
String livedProgramYmd(DateTime now, int dayStartMin) => ymdDashOf(livedDate(now, dayStartMin));

String ymdDashOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Minutes depuis minuit de la journée vécue : avant la bascule, on continue
/// la veille (00:30 avec bascule à 5 h → 24 h 30), ce qui garde le moment
/// courant sur « ce soir » (`currentMoment`).
int livedNowMin(DateTime now, int dayStartMin) {
  final nowMin = now.hour * 60 + now.minute;
  return nowMin < dayStartMin ? nowMin + 24 * 60 : nowMin;
}

/// « 5 h » / « 5 h 30 ».
String dayStartLabel(int min) =>
    min % 60 == 0 ? '${min ~/ 60} h' : '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';

/// Lendemain d'un `YYYY-MM-DD`.
String nextYmd(String ymd) {
  final d = DateTime.parse(ymd).add(const Duration(days: 1));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

int _rawStartMin(ScheduleBlock b) {
  final p = b.startTime.split(':');
  return (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}

/// Blocs de la JOURNÉE VÉCUE [day] (doc du jour) : ses blocs qui commencent à
/// la bascule ou après, puis ceux du doc du lendemain [next] qui commencent
/// AVANT la bascule — la nuit après minuit — marqués `dayOffset = 1` et
/// `docDate` = le doc du lendemain, pour que l'affichage les place après le
/// soir et que les écritures visent le bon doc. Les blocs du jour avant la
/// bascule appartiennent à la nuit de la veille : ils ne sont pas ici.
List<ScheduleBlock> livedDayBlocks(DailySchedule? day, DailySchedule? next, int dayStartMin) {
  final out = <ScheduleBlock>[];
  for (final b in day?.blocks ?? const <ScheduleBlock>[]) {
    if (_rawStartMin(b) < dayStartMin) continue;
    b.docDate = null;
    b.dayOffset = 0;
    out.add(b);
  }
  for (final b in next?.blocks ?? const <ScheduleBlock>[]) {
    if (_rawStartMin(b) >= dayStartMin) continue;
    b.docDate = next!.date;
    b.dayOffset = 1;
    out.add(b);
  }
  return out;
}

/// `DailySchedule` de la journée vécue [ymd] : les faits du doc du jour
/// (généré par, planifié quand, mode soirée…) et les blocs de `livedDayBlocks`.
/// Null si aucun des deux docs n'existe.
DailySchedule? mergeLivedDay(String ymd, DailySchedule? day, DailySchedule? next, int dayStartMin) {
  if (day == null && next == null) return null;
  final blocks = livedDayBlocks(day, next, dayStartMin);
  if (day == null && blocks.isEmpty) return null;
  return DailySchedule(
    date: ymd,
    generatedBy: day?.generatedBy ?? 'claude',
    generatedAt: day?.generatedAt,
    blocks: blocks,
    dayReason: day?.dayReason,
    plannedAt: day?.plannedAt,
    plannedSameDay: day?.plannedSameDay ?? false,
    dayMode: day?.dayMode ?? 'normal',
    dayModeActivatedAt: day?.dayModeActivatedAt,
    unavailableUntil: day?.unavailableUntil,
    unavailableReason: day?.unavailableReason,
    reviewedAt: day?.reviewedAt,
    energyState: day?.energyState,
    recoverySequence: day?.recoverySequence,
  );
}

/// Doc qui doit recevoir un bloc CRÉÉ maintenant dans la vue de la journée
/// vécue [viewYmd] : après minuit (minute vécue ≥ 24 h) c'est le doc du
/// lendemain, à l'heure de l'horloge ; sinon le doc de la vue.
String docForNewBlock(String viewYmd, DateTime now, int dayStartMin) =>
    livedNowMin(now, dayStartMin) >= 24 * 60 ? nextYmd(viewYmd) : viewYmd;

/// Compte du jour d'une routine = ses hits depuis le début de la journée vécue
/// (même règle que `routineTodayCount` côté mobile ; jamais le compteur du jour
/// calendaire `habitProgress`).
int livedHitCount(List<HabitHit> hits, String habitId, DateTime now, int dayStartMin) {
  final start = livedDayStart(now, dayStartMin);
  return hits.where((h) => h.habitId == habitId && !h.ts.isBefore(start)).length;
}
