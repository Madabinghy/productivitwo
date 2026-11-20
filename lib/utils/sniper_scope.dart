import 'dart:math' as math;

/// Géométrie de la lunette du Sniper (maquette validée 2026-11-20 « Sniper en
/// lunette ») : logique pure, les angles sont en degrés depuis le haut, dans le
/// sens des aiguilles d'une montre.

/// Une cible sur le tour de la lunette du viseur.
class ScopeArc {
  final int index;
  final double start, sweep;
  const ScopeArc(this.index, this.start, this.sweep);
  double get mid => start + sweep / 2;
  double get end => start + sweep;
}

class AimScope {
  final List<ScopeArc> arcs;

  /// Le temps libre que rien ne vise (pointillés) ; [airSweep] = 0 quand tout est pris.
  final double airStart, airSweep;

  /// Un trait par minute libre, un par 5 minutes au-delà de [kScopeMinuteTicks].
  final int ticks;
  const AimScope({this.arcs = const [], this.airStart = 0, this.airSweep = 360, this.ticks = 60});
}

/// Plus petit arc lisible (une routine à cocher ne coûte qu'une minute).
const kScopeMinArc = 9.0;
const kScopeMinuteTicks = 90;

/// Le tour complet = le temps libre [freeMin] (au moins ce qui est visé). Chaque
/// cible prend un arc à sa durée [costs], la pause entre deux tirs [pauseMin]
/// reste vide entre deux arcs, le reste est de l'air.
AimScope aimScope({required List<int> costs, required int freeMin, int pauseMin = 0}) {
  final n = costs.length;
  final total = costs.fold<int>(0, (s, c) => s + c) + (n > 1 ? pauseMin * (n - 1) : 0);
  final turn = math.max(math.max(freeMin, total), 1);
  final ticks = turn <= kScopeMinuteTicks ? turn : (turn / 5).round();
  if (n == 0) return AimScope(ticks: ticks);
  final k = 360 / turn;
  final gap = n > 1 ? pauseMin * k : 0.0;
  var sweeps = [for (final c in costs) math.max(c * k, kScopeMinArc)];
  final used = sweeps.fold<double>(0, (s, x) => s + x) + gap * (n - 1);
  if (used > 360) {
    // Les petits arcs agrandis débordent : on resserre les arcs, pas les pauses.
    final room = math.max(360 - gap * (n - 1), 1.0);
    final sum = sweeps.fold<double>(0, (s, x) => s + x);
    sweeps = [for (final s in sweeps) s * room / sum];
  }
  final arcs = <ScopeArc>[];
  var a = 0.0;
  for (var i = 0; i < n; i++) {
    arcs.add(ScopeArc(i, a, sweeps[i]));
    a += sweeps[i] + (i < n - 1 ? gap : 0);
  }
  final air = math.max(0.0, 360 - a);
  return AimScope(arcs: arcs, airStart: a, airSweep: air < 2 ? 0 : air, ticks: ticks);
}

/// Les cercles du carton de tir : écart au temps visé (minutes) → part du rayon.
const kCardRings = <(int, double)>[(1, .39), (2, .59), (3, .80), (5, 1.0)];
const kCardBull = .20;

/// Distance au centre d'un impact : pile = dans le centre, ±1 min sur le premier
/// cercle, ±5 min et plus au bord.
double impactRadius(int gapMin) {
  final g = gapMin.abs();
  if (g == 0) return .09;
  var prevGap = 0, prevR = .09;
  for (final (gap, r) in kCardRings) {
    if (g <= gap) return prevR + (r - prevR) * (g - prevGap) / (gap - prevGap);
    prevGap = gap;
    prevR = r;
  }
  return 1.0;
}

/// Un impact du carton : [number] = le rang du tir dans la session.
class CardImpact {
  final int number;
  final double radius, angle;

  /// Mini-tir : impact creux.
  final bool mini;
  final int gapMin;
  const CardImpact({required this.number, required this.radius, required this.angle, required this.gapMin, this.mini = false});
}

/// Un tir de la session, dans l'ordre : touché ou non, écart en minutes, mini-tir.
typedef CardShot = ({bool hit, int gapMin, bool mini});

/// Un impact par cible touchée ; une cible passée n'en laisse pas. Les tirs
/// pile se groupent en rond dans le centre (un seul = en plein milieu), les
/// autres se répartissent autour (angle d'or) à la distance de leur écart.
List<CardImpact> shotCard(List<CardShot> shots) {
  final exact = [for (var i = 0; i < shots.length; i++) if (shots[i].hit && shots[i].gapMin == 0) i];
  final exactR = exact.length == 1 ? 0.0 : (exact.length > 4 ? .12 : .09);
  return [
    for (var i = 0; i < shots.length; i++)
      if (shots[i].hit)
        CardImpact(
          number: i + 1,
          radius: shots[i].gapMin == 0 ? exactR : impactRadius(shots[i].gapMin),
          angle: shots[i].gapMin == 0 ? (330 + exact.indexOf(i) * 360 / exact.length) % 360 : (60 + i * 137.5) % 360,
          gapMin: shots[i].gapMin,
          mini: shots[i].mini,
        ),
  ];
}

/// Durée de l'impact entre deux tirs (toucher l'écran = tout de suite).
const kSniperImpact = Duration(milliseconds: 1500);

/// Durée du balayage qui redessine la miniature du viseur quand ses cibles changent.
const kSniperReload = Duration(milliseconds: 1800);
