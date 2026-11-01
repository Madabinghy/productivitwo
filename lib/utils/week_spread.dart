import 'package:productivitwo_v1/utils/planning.dart' show WeekWant;

/// Répartir la semaine par familles (maquette validée 2026-11-01 « Répartir la
/// semaine, autrement ») : on trie le contrat avant de le poser, chaque famille
/// a sa règle naturelle — plus de morceaux de 45 min jetés dans le jour le plus
/// libre.

enum PlanFamily { work, fond, body, daily, base }

const kFamilyLabels = {
  PlanFamily.work: 'Le travail',
  PlanFamily.fond: 'Le fond, chaque jour',
  PlanFamily.body: 'Le corps',
  PlanFamily.daily: 'Au quotidien, sans bloc',
  PlanFamily.base: 'Déjà dans ta journée',
};

const kFamilyRules = {
  PlanFamily.work: 'En Deep work, les jours ouvrés · 2 blocs max par jour',
  PlanFamily.fond: 'Un bloc par jour, à la même heure',
  PlanFamily.body: 'Jamais deux jours de suite la même · un repos après deux jours de séance',
  PlanFamily.daily: 'Gardé libre chaque jour, fait au fil de la journée',
  PlanFamily.base: 'Besoins de base : jamais posés',
};

/// Seuils par jour : < 30 min = au quotidien, ≤ 60 min = le fond, au-delà = travail.
const kDailyMaxMin = 30;
const kFondMaxMin = 60;
const kDeepChunks = [120, 90];
const kMaxWorkBlocksPerDay = 2;

int _round15(num m) => ((m / 15).round() * 15).toInt();

/// La famille d'une envie : réglage de l'utilisateur d'abord, puis besoin de
/// base, sport, et la taille par jour (le travail garde aussi les activités de
/// ses domaines au-delà de 30 min / j).
Map<String, PlanFamily> classifyWants(
  List<WeekWant> wants, {
  required String? Function(String activityId) domainOf,
  required bool Function(String activityId) isBase,
  required bool Function(String activityId) isSport,
  Map<String, PlanFamily> overrides = const {},
}) {
  final out = <String, PlanFamily>{};
  final workDomains = <String>{};
  for (final w in wants) {
    final id = w.activityId;
    if (overrides[id] != null) {
      out[id] = overrides[id]!;
    } else if (isBase(id)) {
      out[id] = PlanFamily.base;
    } else if (isSport(id)) {
      out[id] = PlanFamily.body;
    } else if (w.weeklyMin / 7 < kDailyMaxMin && w.weeklyMin > 0) {
      out[id] = PlanFamily.daily;
    } else if (w.weeklyMin / 7 <= kFondMaxMin && w.weeklyMin > 0) {
      out[id] = PlanFamily.fond;
    } else {
      out[id] = PlanFamily.work;
    }
    if (out[id] == PlanFamily.work && domainOf(id) != null) workDomains.add(domainOf(id)!);
  }
  for (final w in wants) {
    final id = w.activityId;
    if (overrides[id] == null && out[id] == PlanFamily.fond && workDomains.contains(domainOf(id))) out[id] = PlanFamily.work;
  }
  return out;
}

class WeekSpread {
  final List<Map<String, int>> days;
  /// Pourquoi ce bloc ce jour-là : `"jour|activité"` → phrase.
  final Map<String, String> reasons;
  /// Ce qui ne tient pas (activité → minutes).
  final Map<String, int> unplaced;
  /// Minutes « au quotidien » gardées libres chaque jour.
  final int dailyReserve;
  const WeekSpread(this.days, this.reasons, this.unplaced, this.dailyReserve);
}

/// Séances d'une activité de sport : 45 min par défaut (1 h au-delà de 3 h / sem),
/// entre 1 et 4 séances.
({int count, int minutes}) bodySessions(int weeklyMin) {
  if (weeklyMin <= 0) return (count: 0, minutes: 0);
  final len = weeklyMin >= 180 ? 60 : 45;
  final n = (weeklyMin / len).round().clamp(1, 4);
  return (count: n, minutes: _round15(weeklyMin / n).clamp(30, 90));
}

/// Pose le contrat sur 7 jours (lundi → dimanche). [free] = minutes libres par
/// jour (déjà réduites de la marge), [prefill] = déjà posé (prépa d'une séance).
WeekSpread spreadByFamily(
  List<WeekWant> wants,
  Map<String, PlanFamily> families,
  List<int> free, {
  List<Map<String, int>>? prefill,
  bool workSaturday = false,
}) {
  final n = free.length;
  final days = [for (var i = 0; i < n; i++) <String, int>{...?prefill?[i]}];
  final reasons = <String, String>{};
  final unplaced = <String, int>{};
  final workBlocks = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    workBlocks[i] = days[i].length;
  }
  final reserve = wants.where((w) => families[w.activityId] == PlanFamily.daily).fold(0, (s, w) => s + (w.weeklyMin / 7).round());
  final left = [
    for (var i = 0; i < n; i++) (free[i] - reserve - days[i].values.fold(0, (s, m) => s + m)).clamp(0, 1 << 30).toInt(),
  ];
  void put(int d, String id, int m, String why) {
    days[d][id] = (days[d][id] ?? 0) + m;
    left[d] -= m;
    reasons['$d|$id'] = why;
  }

  // Le fond : chaque jour, la même part.
  for (final w in wants.where((w) => families[w.activityId] == PlanFamily.fond)) {
    final m = _round15(w.weeklyMin / 7).clamp(30, 60);
    var miss = 0;
    for (var d = 0; d < n; d++) {
      if (left[d] >= m) {
        put(d, w.activityId, m, 'Le fond : un bloc chaque jour, à la même heure.');
      } else {
        miss += m;
      }
    }
    if (miss > 0) unplaced[w.activityId] = miss;
  }

  // Le corps : des séances espacées.
  final bodyDays = List<bool>.filled(n, false);
  final bodies = wants.where((w) => families[w.activityId] == PlanFamily.body).toList()
    ..sort((a, b) => bodySessions(b.weeklyMin).count.compareTo(bodySessions(a.weeklyMin).count));
  for (final w in bodies) {
    final s = bodySessions(w.weeklyMin);
    final mine = <int>[];
    for (var k = 0; k < s.count; k++) {
      var best = -1;
      var bestScore = -1 << 30;
      for (var d = 0; d < n; d++) {
        if (left[d] < s.minutes || mine.contains(d)) continue;
        if (mine.contains(d - 1) || mine.contains(d + 1)) continue;
        // Trois jours de séance d'affilée : non.
        bool run(int a, int b, int c) => a >= 0 && c < n && (a == d || bodyDays[a]) && (b == d || bodyDays[b]) && (c == d || bodyDays[c]);
        if (run(d - 2, d - 1, d) || run(d - 1, d, d + 1) || run(d, d + 1, d + 2)) continue;
        // Étaler : loin des séances déjà posées, sur les jours les plus libres.
        var gap = n;
        for (final x in mine) {
          final g = (x - d).abs();
          if (g < gap) gap = g;
        }
        final score = gap * 100 + (bodyDays[d] ? -200 : 0) + left[d] ~/ 10;
        if (score > bestScore) {
          bestScore = score;
          best = d;
        }
      }
      if (best < 0) {
        unplaced[w.activityId] = (unplaced[w.activityId] ?? 0) + s.minutes;
        continue;
      }
      mine.add(best);
      bodyDays[best] = true;
      put(best, w.activityId, s.minutes, 'Le corps : séance ${mine.length} sur ${s.count}, jamais la veille ni le lendemain d’une autre de la même activité.');
    }
  }

  // Le travail : Deep work les jours ouvrés, deux blocs au plus par jour.
  final workDays = [for (var d = 0; d < n; d++) if (d < 5 || (d == 5 && workSaturday)) d];
  final works = wants.where((w) => families[w.activityId] == PlanFamily.work).toList()..sort((a, b) => b.weeklyMin.compareTo(a.weeklyMin));
  final rest = {for (final w in works) w.activityId: w.weeklyMin};
  // À tour de rôle : un bloc par activité et par tour, une activité au plus
  // une fois par jour, le jour ouvré le plus libre.
  var placed = true;
  while (placed) {
    placed = false;
    for (final w in works) {
      final r = rest[w.activityId]!;
      if (r < 30) continue;
      int? best;
      var piece = 0;
      for (final size in [...kDeepChunks, 60, 45, 30]) {
        final want = r >= size ? size : _round15(r).clamp(30, size);
        if (want > r + 14) continue;
        for (final d in workDays) {
          if (workBlocks[d] >= kMaxWorkBlocksPerDay || left[d] < want || days[d].containsKey(w.activityId)) continue;
          if (best == null || left[d] > left[best]) best = d;
        }
        if (best != null) {
          piece = want;
          break;
        }
      }
      if (best == null) continue;
      put(best, w.activityId, piece, 'Le travail : Deep work un jour ouvré, le moins chargé.');
      workBlocks[best]++;
      rest[w.activityId] = r - piece;
      placed = true;
    }
  }
  for (final e in rest.entries) {
    if (e.value >= 30) unplaced[e.key] = (unplaced[e.key] ?? 0) + e.value;
  }
  return WeekSpread(days, reasons, unplaced, reserve);
}

Map<String, PlanFamily> parseFamilies(Map<String, dynamic>? raw) {
  if (raw == null) return const {};
  final out = <String, PlanFamily>{};
  raw.forEach((k, v) {
    final f = PlanFamily.values.where((x) => x.name == v).firstOrNull;
    if (f != null) out[k] = f;
  });
  return out;
}
