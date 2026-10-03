/// Capacité de planification par jour de semaine (minutes), stockée dans
/// `users/{uid}/data/meta.weekCapacityMin` sous la forme `{mon: 420, …, sun: 0}`.
/// Absent ou partiel = défauts (7 h du lundi au vendredi, 0 le week-end).
library;

const List<String> kWeekDayKeys = [
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
];

const int kDefaultWeekdayCapacityMin = 420;

Map<String, int> defaultWeekCapacity() => {
      for (final k in kWeekDayKeys)
        k: kWeekDayKeys.indexOf(k) < 5 ? kDefaultWeekdayCapacityMin : 0,
    };

/// Clé `mon..sun` d'une date (DateTime.weekday : 1 = lundi).
String weekDayKey(DateTime d) => kWeekDayKeys[d.weekday - 1];

/// Fusionne une valeur brute Firestore avec les défauts. Les clés inconnues
/// sont ignorées, les valeurs négatives ou non numériques retombent au défaut.
Map<String, int> parseWeekCapacity(dynamic raw) {
  final out = defaultWeekCapacity();
  if (raw is! Map) return out;
  for (final k in kWeekDayKeys) {
    final v = raw[k];
    final n = v is num ? v.toInt() : int.tryParse('$v');
    if (n != null && n >= 0) out[k] = n;
  }
  return out;
}

int capacityMinFor(Map<String, int> capacity, DateTime day) =>
    capacity[weekDayKey(day)] ?? 0;

/// Journée active : plage horaire (minutes depuis minuit) dans laquelle les
/// blocs comptent pour la charge, la règle « journée bloquée » et les créneaux
/// proposés. Stockée dans `data/meta.dayWindow` = `{startMin, endMin}`.
/// Défaut 8 h → 22 h ; quelqu'un qui se lève à 4 h règle 4 h → 20 h.
class DayWindow {
  final int startMin;
  final int endMin;
  const DayWindow(this.startMin, this.endMin);

  int get spanMin => endMin - startMin;
  String get label => '${_h(startMin)} → ${_h(endMin)}';

  static String _h(int min) =>
      min % 60 == 0 ? '${min ~/ 60} h' : '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';

  Map<String, int> toJson() => {'startMin': startMin, 'endMin': endMin};

  @override
  bool operator ==(Object o) => o is DayWindow && o.startMin == startMin && o.endMin == endMin;
  @override
  int get hashCode => Object.hash(startMin, endMin);
}

const DayWindow kDefaultDayWindow = DayWindow(8 * 60, 22 * 60);
const int kDayWindowMinSpan = 4 * 60;

/// Valide une plage : début ≥ 0 h, fin ≤ 24 h, au moins 4 h d'écart.
bool isValidDayWindow(int startMin, int endMin) =>
    startMin >= 0 && endMin <= 24 * 60 && endMin - startMin >= kDayWindowMinSpan;

/// Lit `data/meta.dayWindow` ; toute valeur absente ou incohérente retombe
/// au défaut.
DayWindow parseDayWindow(dynamic raw) {
  if (raw is! Map) return kDefaultDayWindow;
  int? n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');
  final s = n(raw['startMin']), e = n(raw['endMin']);
  if (s == null || e == null || !isValidDayWindow(s, e)) return kDefaultDayWindow;
  return DayWindow(s, e);
}
