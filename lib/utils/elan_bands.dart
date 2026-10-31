import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/recharge.dart' show kRechargeValue;

/// La semaine en bandes (maquette « Ton élan, autrement », 2026-10-31) : un
/// jour = une bande de quarts d'heure colorée par MODE (trois modes + la
/// recharge), calculée depuis l'historique des pointages.
enum BandMode { low, normal, high, recharge }

BandMode? bandModeOf(int? v) {
  if (v == null) return null;
  if (v == kRechargeValue) return BandMode.recharge;
  if (v <= 2) return BandMode.low;
  if (v >= 4) return BandMode.high;
  return BandMode.normal;
}

DateTime _dayOf(String ymd) {
  final p = ymd.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Les quarts d'heure du jour vécu [ymd] : l'élan en vigueur, null avant le
/// premier pointage, après la fin du dernier, ou après [now].
List<int?> elanCellsOfDay(List<MoodMark> marks, String ymd, DateTime now, int dayStartMin, {int stepMin = 15}) {
  final start = _dayOf(ymd).add(Duration(minutes: dayStartMin));
  final windows = elanWindows(marks, ymd, dayStartMin: dayStartMin);
  final cells = (24 * 60 / stepMin).round();
  final out = List<int?>.filled(cells, null);
  for (var i = 0; i < cells; i++) {
    final t = start.add(Duration(minutes: i * stepMin));
    if (t.isAfter(now)) break;
    for (final w in windows) {
      if (w.contains(t)) {
        out[i] = w.mark.value;
        break;
      }
    }
  }
  return out;
}

class ModeShare {
  final int low, normal, high;
  const ModeShare(this.low, this.normal, this.high);
  int get said => low + normal + high;
  int pct(BandMode m) {
    if (said == 0) return 0;
    final v = switch (m) { BandMode.low => low, BandMode.normal => normal, BandMode.high => high, BandMode.recharge => 0 };
    return (v * 100 / said).round();
  }

  BandMode? get dominant {
    if (said == 0) return null;
    if (normal >= low && normal >= high) return BandMode.normal;
    return low >= high ? BandMode.low : BandMode.high;
  }
}

/// Répartition du temps éveillé DIT (hors recharge et hors « pas dit »).
ModeShare modeShareOf(Iterable<List<int?>> days) {
  var l = 0, n = 0, h = 0;
  for (final d in days) {
    for (final v in d) {
      switch (bandModeOf(v)) {
        case BandMode.low:
          l++;
        case BandMode.normal:
          n++;
        case BandMode.high:
          h++;
        default:
      }
    }
  }
  return ModeShare(l, n, h);
}

const _weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const kBandModeLabels = {BandMode.low: 'Flemme', BandMode.normal: 'Normal', BandMode.high: 'En forme', BandMode.recharge: 'Recharge'};

/// La phrase de la semaine : le mode dominant, le jour de la flemme, les
/// démarrages malgré tout. [days] = (ymd, cellules) du plus ancien au plus récent.
String weekBandSentence(List<(String, List<int?>)> days, int wins) {
  final share = modeShareOf(days.map((d) => d.$2));
  final dom = share.dominant;
  if (dom == null) return 'Rien de dit cette semaine : touche ton mode, la semaine se dessinera ici.';
  final parts = <String>['Surtout ${kBandModeLabels[dom]}.'];
  String? lowDay;
  var lowMax = 0;
  for (final d in days) {
    final c = d.$2.where((v) => bandModeOf(v) == BandMode.low).length;
    if (c > lowMax) {
      lowMax = c;
      lowDay = d.$1;
    }
  }
  if (lowDay == null) {
    parts.add('Pas de flemme cette semaine.');
  } else {
    final name = _weekdays[_dayOf(lowDay).weekday - 1];
    parts.add(wins > 0
        ? 'La flemme surtout le $name, et tu as démarré quand même $wins fois.'
        : 'La flemme surtout le $name.');
  }
  return parts.join(' ');
}

/// Fenêtres de flemme gagnées d'un jour (« ⚡ n » au bout de sa bande).
int lowWinsOf(ElanDay d) => d.marks.where((m) => m.value >= 1 && m.value <= 2 && m.won).length;

/// Jours de la semaine où l'élan a été dit (au moins un pointage réel).
int saidDays(List<ElanDay> days) => days.where((d) => d.marks.any((m) => m.value >= 1)).length;

/// Repères de la bande : la bascule, puis toutes les 6 h.
List<String> elanHourTicks(int dayStartMin) {
  final h = dayStartMin ~/ 60;
  return ['$h h', '${(h + 6) % 24} h', '${(h + 12) % 24} h', '${(h + 18) % 24} h'];
}

// ── Ce que ça t'apprend (PR 2) ────────────────────────────────────────────────

/// Moment d'un quart d'heure de la journée vécue : matin (< 12 h), après-midi
/// (< 18 h), soir (le reste, nuit comprise).
String bandMomentOf(int index, int dayStartMin, {int stepMin = 15}) {
  final min = (dayStartMin + index * stepMin) % (24 * 60);
  if (min >= dayStartMin && min < 12 * 60) return 'matin';
  if (min >= 12 * 60 && min < 18 * 60) return 'aprem';
  return 'soir';
}

/// Quarts d'heure passés en Flemme par moment, sur ces jours.
Map<String, int> lowByMoment(Iterable<List<int?>> days, int dayStartMin) {
  final out = {'matin': 0, 'aprem': 0, 'soir': 0};
  for (final d in days) {
    for (var i = 0; i < d.length; i++) {
      if (bandModeOf(d[i]) == BandMode.low) out[bandMomentOf(i, dayStartMin)] = out[bandMomentOf(i, dayStartMin)]! + 1;
    }
  }
  return out;
}

/// Le moment le plus en Flemme (null si aucune flemme).
String? hardestMoment(Map<String, int> byMoment) {
  final e = byMoment.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
  return e.isEmpty ? null : e.first.key;
}

/// Fenêtres de flemme où tu as quand même fait quelque chose, sur ces jours.
({int won, int total}) lowWindowsOf(List<ElanDay> days) {
  var won = 0, total = 0;
  for (final d in days) {
    for (final m in d.marks) {
      if (m.value < 1 || m.value > 2) continue;
      total++;
      if (m.won) won++;
    }
  }
  return (won: won, total: total);
}

/// Guérillas (≥ [since]) dont le corps va mieux à la fin qu'au début.
({int up, int total}) guerillaRebound(List<ChainRun> runs, DateTime since) {
  var up = 0, total = 0;
  for (final r in runs) {
    if (r.kind != 'guerilla' || r.endedAt.isBefore(since) || r.bodyBefore == null || r.bodyAfter == null) continue;
    total++;
    if (r.bodyAfter! > r.bodyBefore!) up++;
  }
  return (up: up, total: total);
}

/// Part du temps dit passé en Flemme, par paquets de 7 jours (du plus ancien
/// au plus récent) ; null = rien de dit cette semaine-là.
List<int?> weeklyLowPct(List<List<int?>> days, {int weeks = 4}) {
  final out = <int?>[];
  for (var w = weeks; w >= 1; w--) {
    final end = days.length - (w - 1) * 7;
    final start = end - 7;
    if (start < 0) {
      out.add(null);
      continue;
    }
    final share = modeShareOf(days.sublist(start, end));
    out.add(share.said == 0 ? null : share.pct(BandMode.low));
  }
  return out;
}
