import 'package:productivitwo_v1/models.dart' show yyyymmdd;

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
