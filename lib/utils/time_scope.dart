// Déplace (ou définis) l’énum ici si elle était dans main.dart
enum TimeScope { day, week, month }

// Renvoie un record (start, end, days)
({DateTime start, DateTime end, int days}) rangeForScope(TimeScope scope, DateTime now) {
  switch (scope) {
    case TimeScope.day:
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      return (start: start, end: end, days: 1);

    case TimeScope.week:
      // Semaine courante: Lundi 00:00 → Lundi suivant 00:00
      final dow = now.weekday; // 1=lundi..7=dimanche
      final start = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: dow - 1));
      final end = start.add(const Duration(days: 7));
      return (start: start, end: end, days: 7);

    case TimeScope.month:
      final start = DateTime(now.year, now.month, 1);
      final nextMonth = (now.month == 12)
          ? DateTime(now.year + 1, 1, 1)
          : DateTime(now.year, now.month + 1, 1);
      final end = nextMonth;
      final days = end.difference(start).inDays;
      return (start: start, end: end, days: days);
  }
}

String fmtCompactFromMin(int minutes) => fmtCompact(Duration(minutes: minutes));

String fmtCompact(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return "${m}m";
  return "${h}h ${m.toString().padLeft(2,'0')}m";
}
