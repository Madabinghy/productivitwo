import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';

/// Modes et coups tactiques (lot 0, 2026-10, handoff
/// `docs/specs/modes-et-coups-2026-10`). Le MODE du jour (Flemme · Normal · En
/// forme) n'est pas stocké : c'est le DERNIER pointage d'élan de la journée
/// vécue (`mood_marks`, kind "elan") — ≤ 2 Flemme · 3 Normal · ≥ 4 En forme ;
/// aucun pointage = Normal. Miroir TypeScript : `functions/src/mode.ts`
/// (**garder alignés**).
enum DayMode { low, normal, high }

const kModeLabels = {DayMode.low: 'Flemme', DayMode.normal: 'Normal', DayMode.high: 'En forme'};

/// Valeur d'élan écrite quand l'utilisateur POSE un mode.
int modeElanValue(DayMode m) => switch (m) { DayMode.low => 2, DayMode.normal => 3, DayMode.high => 4 };

/// 0 = recharge (pointage virtuel de la nuit, `utils/recharge.dart`) : ni
/// malgré tout, ni à fond.
DayMode modeFromElan(int value) => value == 0 ? DayMode.normal : (value <= 2 ? DayMode.low : (value >= 4 ? DayMode.high : DayMode.normal));

/// Dernier pointage d'élan de la journée vécue [ymd] (YYYY-MM-DD), à [at] au plus tard.
MoodMark? lastElanMark(Iterable<MoodMark> marks, String ymd, {DateTime? at}) {
  MoodMark? best;
  for (final m in marks) {
    if (m.kind != kMoodElan || m.ymd != ymd) continue;
    if (at != null && m.at.isAfter(at)) continue;
    if (best == null || m.at.isAfter(best.at)) best = m;
  }
  return best;
}

/// Mode courant : dernier élan de la journée vécue, sinon Normal.
DayMode modeOf(Iterable<MoodMark> marks, DateTime now, int dayStartMin) {
  final m = lastElanMark(marks, livedProgramYmd(now, dayStartMin));
  return m == null ? DayMode.normal : modeFromElan(m.value);
}

/// Mode en vigueur au moment [at] (pour qualifier une chose faite après coup).
DayMode modeAt(Iterable<MoodMark> marks, DateTime at, int dayStartMin) {
  final m = lastElanMark(marks, livedProgramYmd(at, dayStartMin), at: at);
  return m == null ? DayMode.normal : modeFromElan(m.value);
}

/// « Malgré tout » : fait pendant le mode Flemme. Dérivé, jamais stocké.
bool malgreTout(DateTime doneAt, Iterable<MoodMark> marks, int dayStartMin) => modeAt(marks, doneAt, dayStartMin) == DayMode.low;

/// « À fond » : fait pendant le mode En forme.
bool aFond(DateTime doneAt, Iterable<MoodMark> marks, int dayStartMin) => modeAt(marks, doneAt, dayStartMin) == DayMode.high;

/// `data/meta.restDomains {domainId: "YYYY-MM-DD"}` — domaines en veille jusqu'à
/// cette date INCLUSE.
Map<String, String> parseRestDomains(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, String>{};
  raw.forEach((k, v) {
    final s = v?.toString() ?? '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) out[k.toString()] = s;
  });
  return out;
}

bool isResting(String? domainId, Map<String, String> restDomains, DateTime today) {
  if (domainId == null) return false;
  final until = restDomains[domainId];
  if (until == null) return false;
  return until.compareTo(ymdDashOf(today)) >= 0;
}

/// Domaines dont la veille court encore à [today].
Map<String, String> activeRests(Map<String, String> restDomains, DateTime today) =>
    {for (final e in restDomains.entries) if (e.value.compareTo(ymdDashOf(today)) >= 0) e.key: e.value};

/// `data/meta.budgetWindowDays` : 7 (défaut) ou 14 jours.
int parseBudgetWindowDays(dynamic raw) {
  final v = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  return v == 14 ? 14 : 7;
}
