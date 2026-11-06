/// Journée difficile (maquette validée 2026-11-06 « Journée difficile ») : le lendemain d'une journée hors norme,
/// on la déclare et toutes les séries de ce jour-là sont GELÉES (ni cassées, ni allongées), comme un jour de veille.
/// Rare : une fois tous les [kHardDayCooldownDays] jours. Le jour déclaré ne compte ni pour Journée parfaite, ni
/// pour Métronome, ni pour Montre suisse, et ne forge pas de braise. `data/meta.hardDays` = liste de `YYYY-MM-DD`.
const kHardDayCooldownDays = 14;
const _kKept = 60;

final _re = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _shift(String ymd, int days) {
  final d = DateTime.parse(ymd);
  return _ymd(DateTime(d.year, d.month, d.day + days));
}

List<String> parseHardDays(dynamic raw) {
  if (raw is! List) return const [];
  final out = <String>{for (final x in raw) if (x is String && _re.hasMatch(x)) x}.toList()..sort();
  return out;
}

/// La dernière journée difficile déclarée avant [beforeYmd] (exclu), sinon null.
String? lastHardDayBefore(List<String> days, String beforeYmd) {
  String? best;
  for (final d in days) {
    if (d.compareTo(beforeYmd) < 0 && (best == null || d.compareTo(best) > 0)) best = d;
  }
  return best;
}

/// Premier jour qu'on pourra de nouveau déclarer difficile après [lastYmd].
String nextHardDayAfter(String lastYmd) => _shift(lastYmd, kHardDayCooldownDays);

/// [ymd] (en pratique hier) peut-il être déclaré journée difficile ?
bool canDeclareHardDay(List<String> days, String ymd) {
  if (days.contains(ymd)) return false;
  final last = lastHardDayBefore(days, ymd);
  return last == null || nextHardDayAfter(last).compareTo(ymd) <= 0;
}

List<String> withHardDay(List<String> days, String ymd) {
  final out = <String>{...days, ymd}.toList()..sort();
  return out.length > _kKept ? out.sublist(out.length - _kKept) : out;
}

List<String> withoutHardDay(List<String> days, String ymd) => [for (final d in days) if (d != ymd) d];

/// Les journées difficiles jusqu'à [todayYmd] inclus (jamais à l'avance).
Set<String> hardDaysUpTo(List<String> days, String todayYmd) => {for (final d in days) if (d.compareTo(todayYmd) <= 0) d};
