import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_context.dart';
import 'package:productivitwo_v1/utils/routines_today.dart';

/// Vue Routines d'Aujourd'hui (mobile, 2026-10) : la journée vue par les
/// routines, découpée en MOMENTS. Le moment d'une routine est son
/// `timeContext` effectif (réglé, sinon deviné d'après le nom —
/// `effTimeContextOf`), ramené à six cases : matin, midi, après-midi, soir,
/// toute la journée, libre. Logique pure, testée.

class Moment {
  final String key;
  final String label;
  /// « du matin », « du midi », « de l'après-midi », « du soir ».
  final String of;
  /// « ce matin », « ce midi », « cet après-midi », « ce soir ».
  final String thisOne;
  final String window;
  final int startMin;
  final int endMin;
  const Moment(this.key, this.label, this.of, this.thisOne, this.window, this.startMin, this.endMin);

  /// Les quatre moments horaires, dans l'ordre de la journée.
  bool get timed => startMin >= 0;
}

const kMomentMorning = 'morning';
const kMomentMidday = 'midday';
const kMomentAfternoon = 'afternoon';
const kMomentEvening = 'evening';
const kMomentAllDay = 'allday';
const kMomentAny = 'any';

const kMoments = <Moment>[
  Moment(kMomentMorning, 'Matin', 'du matin', 'ce matin', '5 h 30 → 11 h', 5 * 60 + 30, 11 * 60),
  Moment(kMomentMidday, 'Midi', 'du midi', 'ce midi', '11 h 30 → 14 h', 11 * 60 + 30, 14 * 60),
  Moment(kMomentAfternoon, 'Après-midi', 'de l\'après-midi', 'cet après-midi', '14 h → 19 h', 14 * 60, 19 * 60),
  Moment(kMomentEvening, 'Soir', 'du soir', 'ce soir', '19 h → 23 h 30', 19 * 60, 23 * 60 + 30),
  Moment(kMomentAllDay, 'Toute la journée', 'de la journée', 'aujourd\'hui', '', -1, -1),
  Moment(kMomentAny, 'Libre', 'libres', 'aujourd\'hui', 'sans moment', -1, -1),
];

Moment momentOf(String key) => kMoments.firstWhere((m) => m.key == key, orElse: () => kMoments.last);

List<Moment> get kTimedMoments => kMoments.where((m) => m.timed).toList();

/// Case de [a] : `timeContext` effectif ramené aux six moments
/// (repas → midi, journée → toute la journée, rien → libre).
String momentKeyOf(Activity a) {
  final ctx = effTimeContextOf(a)?.key;
  switch (ctx) {
    case 'morning':
    case 'midday':
    case 'afternoon':
    case 'evening':
    case 'allday':
      return ctx!;
    case 'meal':
      return kMomentMidday;
    case 'day':
      return kMomentAllDay;
    default:
      return kMomentAny;
  }
}

/// Moment courant : celui dont la plage contient [nowMin] ; dans un creux,
/// le prochain ; après le soir, le soir ; avant le matin, le matin.
Moment currentMoment(int nowMin) {
  for (final m in kTimedMoments) {
    if (nowMin >= m.startMin && nowMin < m.endMin) return m;
  }
  for (final m in kTimedMoments) {
    if (nowMin < m.startMin) return m;
  }
  return kTimedMoments.last;
}

Moment? nextMomentAfter(Moment m) {
  final i = kTimedMoments.indexWhere((x) => x.key == m.key);
  return i < 0 || i + 1 >= kTimedMoments.length ? null : kTimedMoments[i + 1];
}

/// Une routine dans la journée : son moment du jour (reporté ou d'origine),
/// son état, et d'où elle vient si elle n'est pas « à sa place ».
class RoutineSlot {
  final RoutineToDo todo;
  /// Moment d'origine (réglage de la routine).
  final String home;
  /// Moment où elle apparaît aujourd'hui (report « cet après-midi »).
  final String moment;
  const RoutineSlot(this.todo, this.home, this.moment);

  Activity get activity => todo.activity;
  String get id => todo.activity.id;
  bool get reached => todo.reached;
  bool get pushed => moment != home;
}

class RoutineDay {
  final Moment current;
  final List<RoutineSlot> slots;
  final List<String> deferred;
  final Set<String> dismissed;
  const RoutineDay(this.current, this.slots, this.deferred, this.dismissed);

  List<RoutineSlot> of(String momentKey) => slots.where((s) => s.moment == momentKey).toList();

  ({int done, int total}) countOf(String momentKey) {
    final l = of(momentKey).where((s) => !dismissed.contains(s.id)).toList();
    return (done: l.where((s) => s.reached).length, total: l.length);
  }

  ({int done, int total}) get countAll {
    final l = slots.where((s) => !dismissed.contains(s.id)).toList();
    return (done: l.where((s) => s.reached).length, total: l.length);
  }

  /// Routines d'un moment PASSÉ non atteintes et non écartées (« restées »).
  List<RoutineSlot> leftoversBefore(Moment m) => [
        for (final past in kTimedMoments.where((x) => x.endMin <= m.startMin))
          ...of(past.key).where((s) => !s.reached && !dismissed.contains(s.id)),
      ];

  int leftoverCountOf(String momentKey) {
    final m = momentOf(momentKey);
    if (!m.timed || m.endMin > current.startMin) return 0;
    return of(momentKey).where((s) => !s.reached && !dismissed.contains(s.id)).length;
  }

  /// La file du moment : restées des moments passés, puis celles du moment
  /// courant, non atteintes et non écartées ; les « Pas maintenant » en fin,
  /// dans l'ordre où on les a reculées. Toute la journée et Libre n'y entrent
  /// pas.
  List<RoutineSlot> get queue {
    final base = [
      ...leftoversBefore(current),
      ...of(current.key).where((s) => !s.reached && !dismissed.contains(s.id)),
    ];
    final first = base.where((s) => !deferred.contains(s.id)).toList();
    final later = base.where((s) => deferred.contains(s.id)).toList()
      ..sort((a, b) => deferred.indexOf(a.id).compareTo(deferred.indexOf(b.id)));
    return [...first, ...later];
  }

  /// Moments plus tard dans la journée où reporter une routine de la file.
  List<Moment> get laterMoments =>
      kTimedMoments.where((m) => m.startMin >= current.endMin).toList();

  /// « Routines · 5 / 18 · 3 à faire ce matin · 1 restée du matin ».
  String get shortLine {
    final all = countAll;
    final q = queue;
    final left = leftoversBefore(current).length;
    final own = q.length - left;
    var s = 'Routines · ${all.done} / ${all.total}';
    if (own > 0) s += ' · $own à faire ${current.thisOne}';
    if (left > 0) {
      final from = kTimedMoments.firstWhere((m) => of(m.key).any((x) => !x.reached && !dismissed.contains(x.id)),
          orElse: () => current);
      s += ' · $left restée${left > 1 ? 's' : ''} ${from.of}';
    }
    if (own == 0 && left == 0 && all.total > 0) s += ' · rien à faire ${current.thisOne}';
    return s;
  }
}

int _cmpSlots(RoutineSlot a, RoutineSlot b) {
  final oa = a.activity.routineOrder, ob = b.activity.routineOrder;
  if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
  if (oa != null && ob == null) return -1;
  if (oa == null && ob != null) return 1;
  return a.activity.name.toLowerCase().compareTo(b.activity.name.toLowerCase());
}

/// La journée en routines. [pushed] = reports du jour (routineId → moment),
/// [deferred] = « Pas maintenant » (fin de file, ordre du report), [dismissed]
/// = « Pas aujourd'hui ».
RoutineDay buildRoutineDay({
  required List<Activity> activities,
  required List<HabitHit> hits,
  required DateTime now,
  Map<String, String> pushed = const {},
  List<String> deferred = const [],
  Set<String> dismissed = const {},
}) {
  final nowMin = now.hour * 60 + now.minute;
  final current = currentMoment(nowMin);
  final todos = routinesForToday(activities, hits, now);
  final slots = <RoutineSlot>[
    for (final t in todos)
      RoutineSlot(t, momentKeyOf(t.activity), pushed[t.activity.id] ?? momentKeyOf(t.activity)),
  ]..sort(_cmpSlots);
  return RoutineDay(current, slots, deferred, dismissed);
}
