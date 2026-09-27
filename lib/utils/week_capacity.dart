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
