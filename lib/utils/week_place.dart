import 'package:productivitwo_v1/utils/week_spread.dart';

/// Poser sa semaine (maquette validée 2026-11-01 « toi qui places, l'app qui
/// aide ») : on dit ce qu'on veut en morceaux (n × durée), puis on place
/// chaque morceau soi-même ; « Proposer » ne pose que des fantômes à garder.

class PieceSpec {
  final int count;
  final int minutes;
  const PieceSpec(this.count, this.minutes);
  int get total => count * minutes;
}

int _round15(num m) => ((m / 15).round() * 15).toInt();

/// Le découpage par défaut d'une envie selon sa famille : travail en morceaux
/// de 1h30, fond = un par jour, corps = ses séances ; au quotidien et besoins
/// de base ne se placent pas.
PieceSpec pieceSpecOf(PlanFamily f, int weeklyMin) {
  if (weeklyMin <= 0) return const PieceSpec(0, 0);
  switch (f) {
    case PlanFamily.work:
      final m = weeklyMin >= 90 ? 90 : _round15(weeklyMin).clamp(30, 90);
      return PieceSpec((weeklyMin / m).round().clamp(1, 14), m);
    case PlanFamily.fond:
      return PieceSpec(7, _round15(weeklyMin / 7).clamp(30, 60));
    case PlanFamily.body:
      final s = bodySessions(weeklyMin);
      return PieceSpec(s.count, s.minutes);
    case PlanFamily.daily:
    case PlanFamily.base:
      return const PieceSpec(0, 0);
  }
}

class WeekPiece {
  final String id;
  final int minutes;
  /// Proposé par l'app, pas encore gardé : ne compte pas.
  final bool ghost;
  final String? reason;
  const WeekPiece(this.id, this.minutes, {this.ghost = false, this.reason});
  WeekPiece kept() => WeekPiece(id, minutes, reason: reason);
}

/// Morceaux placés (gardés) d'une activité sur la semaine.
int placedCount(List<List<WeekPiece>> days, String id) =>
    days.fold(0, (s, d) => s + d.where((p) => !p.ghost && p.id == id).length);

/// Minutes posées (gardées) d'un jour.
int dayLoad(List<WeekPiece> day) => day.where((p) => !p.ghost).fold(0, (s, p) => s + p.minutes);

/// Il reste la place pour [minutes] ce jour-là.
bool fitsDay(int freeMin, List<WeekPiece> day, int minutes) => freeMin - dayLoad(day) >= minutes;

/// Ce qu'il reste à placer par activité (morceaux).
Map<String, int> remainingPieces(Map<String, PieceSpec> wanted, List<List<WeekPiece>> days) => {
      for (final e in wanted.entries)
        if (e.value.count - placedCount(days, e.key) > 0) e.key: e.value.count - placedCount(days, e.key),
    };

/// Une répartition (minutes par jour et activité) → fantômes, découpés à la
/// durée du morceau de chaque activité, sans dépasser ce qu'il reste.
List<List<WeekPiece>> ghostsFromSpread(
  List<Map<String, int>> spread,
  Map<String, PieceSpec> wanted,
  Map<String, int> remaining, {
  Map<String, String> reasons = const {},
}) {
  final left = {...remaining};
  return [
    for (var d = 0; d < spread.length; d++)
      [
        for (final e in spread[d].entries)
          if (wanted[e.key] != null && wanted[e.key]!.minutes > 0)
            for (var k = 0; k < (e.value / wanted[e.key]!.minutes).round().clamp(1, 7); k++)
              if ((left[e.key] ?? 0) > 0 && (left[e.key] = left[e.key]! - 1) >= 0)
                WeekPiece(e.key, wanted[e.key]!.minutes, ghost: true, reason: reasons['$d|${e.key}']),
      ],
  ];
}
