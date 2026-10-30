/// Reprise (lot « Pause, record et reprise », 2026-10-30) : une routine coupée
/// au moins [kRepriseGap] jours (jours gelés par une veille non comptés), puis
/// tenue [kRepriseHold] jours d'affilée. Une coupure d'un seul jour relève des
/// braises, pas d'une reprise. Jamais stocké : recalculé depuis les jours tenus.
const kRepriseGap = 2;
const kRepriseHold = 3;
const kRepriseTiers = [1, 5, 15];

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class RepriseEvent {
  /// Jour où la reprise est acquise (3ᵉ jour tenu).
  final String ymd;
  /// Jours manqués de la coupure reprise.
  final int gap;
  const RepriseEvent(this.ymd, this.gap);
}

/// Une reprise possible ou en cours aujourd'hui.
class RepriseNow {
  /// Jours tenus depuis la coupure, aujourd'hui compris s'il est tenu.
  final int held;
  final bool todayHeld;
  /// Jours manqués de la coupure.
  final int gap;
  const RepriseNow({required this.held, required this.todayHeld, required this.gap});
  bool get completedToday => todayHeld && held >= kRepriseHold;
  /// Le +1 d'aujourd'hui fait la reprise.
  bool get tonight => !todayHeld && held == kRepriseHold - 1;
  /// Avancement après le geste du jour (pour les jauges).
  int get afterToday => todayHeld ? held : held + 1;
}

class RepriseHistory {
  final List<RepriseEvent> events;
  final RepriseNow? now;
  const RepriseHistory(this.events, this.now);
  static const empty = RepriseHistory([], null);
}

/// [held] = jours tenus (atteints ou comblés par une braise) ; [frozen] = jours
/// gelés par une veille, transparents : ils ne comptent ni comme tenus ni comme
/// manqués. Aujourd'hui non tenu n'est pas (encore) un manque.
RepriseHistory reprisesOf(Set<String> held, Set<String> frozen, String todayYmd) {
  if (held.isEmpty) return RepriseHistory.empty;
  final first = (held.toList()..sort()).first;
  if (first.compareTo(todayYmd) > 0) return RepriseHistory.empty;
  final events = <RepriseEvent>[];
  var gap = 0, run = 0, runGap = 0;
  var counted = false;
  var d = DateTime.parse(first);
  var guard = 0;
  while (guard++ < 4000) {
    final y = _ymd(d);
    if (y.compareTo(todayYmd) > 0) break;
    if (held.contains(y)) {
      if (gap > 0) {
        runGap = gap;
        run = 0;
        counted = false;
      }
      gap = 0;
      run++;
      if (!counted && runGap >= kRepriseGap && run == kRepriseHold) {
        events.add(RepriseEvent(y, runGap));
        counted = true;
      }
    } else if (!frozen.contains(y) && y != todayYmd) {
      gap++;
    }
    d = DateTime(d.year, d.month, d.day + 1);
  }
  final todayHeld = held.contains(todayYmd);
  final heldNow = gap == 0 ? run : 0;
  final gapNow = gap == 0 ? runGap : gap;
  RepriseNow? now;
  if (gapNow >= kRepriseGap) {
    final r = RepriseNow(held: heldNow, todayHeld: todayHeld, gap: gapNow);
    if (heldNow < kRepriseHold || (r.completedToday && heldNow == kRepriseHold)) now = r;
  }
  return RepriseHistory(events, now);
}
