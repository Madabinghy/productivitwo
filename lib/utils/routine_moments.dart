import 'package:productivitwo_v1/utils/lived_day.dart';
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

  /// Même moment avec d'autres bornes (réglage utilisateur).
  Moment withWindow(int s, int e) => Moment(key, label, of, thisOne, momentWindowLabel(s, e), s, e);
}

/// « 19 h → 5 h » (une fin après minuit s'affiche sur le cadran).
String momentWindowLabel(int s, int e) => '${_hLabel(s)} → ${_hLabel(e % (24 * 60))}';
String _hLabel(int min) =>
    min % 60 == 0 ? '${min ~/ 60} h' : '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';

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
  Moment(kMomentEvening, 'Soir', 'du soir', 'ce soir', '19 h → 5 h', 19 * 60, 24 * 60 + kDefaultDayStartMin),
  Moment(kMomentAllDay, 'Toute la journée', 'de la journée', 'aujourd\'hui', '', -1, -1),
  Moment(kMomentAny, 'Libre', 'libres', 'aujourd\'hui', 'sans moment', -1, -1),
];

Moment momentOf(String key) => kMoments.firstWhere((m) => m.key == key, orElse: () => kMoments.last);

List<Moment> get kTimedMoments => kMoments.where((m) => m.timed).toList();

/// Fin maximale d'un moment : midi le lendemain (le Soir d'un travailleur de
/// nuit peut finir à 10 h).
const int kMomentEndMax = 36 * 60;

/// Les quatre moments horaires RÉGLÉS : bornes de `data/meta.momentWindows`
/// (clé → (début, fin), minutes ; fin > 24 h = le lendemain) sur les défauts.
/// Sans réglage, le Soir court jusqu'au début de la journée vécue
/// (`dayStartMin`, 5 h par défaut) : la nuit appartient au soir.
List<Moment> timedMomentsWith(Map<String, (int, int)> windows, {int dayStartMin = kDefaultDayStartMin}) => [
      for (final m in kTimedMoments)
        if (windows[m.key] case final w?)
          m.withWindow(w.$1, w.$2)
        else if (m.key == kMomentEvening)
          m.withWindow(m.startMin, 24 * 60 + dayStartMin)
        else
          m,
    ];

/// Les six moments (horaires réglés + toute la journée + libre), pour les vues.
List<Moment> momentsWith(Map<String, (int, int)> windows, {int dayStartMin = kDefaultDayStartMin}) => [
      ...timedMomentsWith(windows, dayStartMin: dayStartMin),
      ...kMoments.where((m) => !m.timed),
    ];

/// Lit `data/meta.momentWindows` : `{morning: {start, end}, …}` ; une entrée
/// incohérente est ignorée (retour au défaut pour ce moment).
Map<String, (int, int)> parseMomentWindows(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, (int, int)>{};
  for (final m in kTimedMoments) {
    final v = raw[m.key];
    if (v is! Map) continue;
    final s = (v['start'] as num?)?.toInt(), e = (v['end'] as num?)?.toInt();
    if (s == null || e == null || s < 0 || s >= 24 * 60 || e <= s || e > kMomentEndMax) continue;
    out[m.key] = (s, e);
  }
  return out;
}

Map<String, Map<String, int>> momentWindowsToJson(Map<String, (int, int)> windows) =>
    {for (final e in windows.entries) e.key: {'start': e.value.$1, 'end': e.value.$2}};

/// Cohérence des quatre moments réglés : chaque début avant sa fin, et les
/// moments dans l'ordre sans chevauchement (des creux sont permis). Null = ok,
/// sinon le message à afficher.
String? validateMoments(List<Moment> timed) {
  for (final m in timed) {
    if (m.endMin <= m.startMin) return 'Le ${m.label.toLowerCase()} finit avant de commencer.';
    if (m.endMin > kMomentEndMax) return 'Le ${m.label.toLowerCase()} ne peut pas finir après midi le lendemain.';
  }
  for (var i = 1; i < timed.length; i++) {
    final a = timed[i - 1], b = timed[i];
    if (b.startMin < a.endMin) return 'Le ${b.label.toLowerCase()} commence avant la fin du ${a.label.toLowerCase()}.';
  }
  return null;
}

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
Moment currentMoment(int nowMin, [List<Moment>? moments]) {
  final ms = moments ?? kTimedMoments;
  for (final m in ms) {
    if (nowMin >= m.startMin && nowMin < m.endMin) return m;
  }
  for (final m in ms) {
    if (nowMin < m.startMin) return m;
  }
  return ms.last;
}

Moment? nextMomentAfter(Moment m, [List<Moment>? moments]) {
  final ms = moments ?? kTimedMoments;
  final i = ms.indexWhere((x) => x.key == m.key);
  return i < 0 || i + 1 >= ms.length ? null : ms[i + 1];
}

/// Une routine dans la journée : son moment du jour (reporté ou d'origine),
/// son état, et d'où elle vient si elle n'est pas « à sa place ».
class RoutineSlot {
  final RoutineToDo todo;
  /// Moment d'origine (réglage de la routine).
  final String home;
  /// Moment où elle apparaît aujourd'hui (report « cet après-midi »).
  final String moment;
  /// Part du moment quand la routine est répartie sur plusieurs moments.
  final MomentShare? share;
  const RoutineSlot(this.todo, this.home, this.moment, {this.share});

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
  /// Les quatre moments horaires en vigueur (réglés) ; vide = défauts.
  final List<Moment> moments;
  const RoutineDay(this.current, this.slots, this.deferred, this.dismissed, {this.moments = const []});

  List<Moment> get timed => moments.isEmpty ? kTimedMoments : moments;

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
        for (final past in timed.where((x) => x.endMin <= m.startMin))
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
      timed.where((m) => m.startMin >= current.endMin).toList();

  /// « Routines · 5 / 18 · 3 à faire ce matin · 1 restée du matin ».
  String get shortLine {
    final all = countAll;
    final q = queue;
    final left = leftoversBefore(current).length;
    final own = q.length - left;
    var s = 'Routines · ${all.done} / ${all.total}';
    if (own > 0) s += ' · $own à faire ${current.thisOne}';
    if (left > 0) {
      final from = timed.firstWhere((m) => of(m.key).any((x) => !x.reached && !dismissed.contains(x.id)),
          orElse: () => current);
      s += ' · $left restée${left > 1 ? 's' : ''} ${from.of}';
    }
    if (own == 0 && left == 0 && all.total > 0) s += ' · rien à faire ${current.thisOne}';
    return s;
  }
}

/// Part d'une routine RÉPARTIE (2026-10-30) dans le moment où elle se trouve :
/// [done] / [target] pour ce moment (« 7 / 10 ce matin »).
class MomentShare {
  final String moment;
  final int done;
  final int target;
  const MomentShare(this.moment, this.done, this.target);
  int get left => (target - done).clamp(0, target);

  /// « 7 / 10 ce matin » ; rien fait encore = « 10 ce soir ».
  String get label => done > 0 ? '$done / $target ${momentOf(moment).thisOne}' : '$target ${momentOf(moment).thisOne}';
}

/// Moments horaires d'une routine répartie, dans l'ordre de la journée ; vide
/// si elle n'est pas répartie (moins de deux moments).
List<String> splitMomentsOf(Activity a) {
  final set = a.splitMoments.toSet();
  final keys = [for (final m in kTimedMoments) if (set.contains(m.key)) m.key];
  return keys.length < 2 ? const [] : keys;
}

/// Où en est une routine répartie sur plusieurs moments. Parts = cible ÷
/// moments, le surplus aux premiers (3 sur 2 → 2 puis 1) ; un moment sans part
/// (cible < moments) est ignoré. La routine reste dans le premier moment dont
/// la part cumulée n'est pas atteinte et qui n'est pas fini ; un moment fini
/// laisse son reste au suivant. Null = pas répartie, cible du jour atteinte,
/// ou routine hebdo.
MomentShare? momentShareOf(Activity a, {required int dayDone, required int? dayTarget, required int nowMin, List<Moment>? moments}) {
  final keys = splitMomentsOf(a);
  final n = dayTarget ?? 0;
  if (keys.isEmpty || n <= 0 || dayDone >= n) return null;
  final ms = moments ?? kTimedMoments;
  final base = n ~/ keys.length, extra = n % keys.length;
  final parts = <(String, int)>[];
  for (var i = 0; i < keys.length; i++) {
    final share = base + (i < extra ? 1 : 0);
    if (share > 0) parts.add((keys[i], share));
  }
  var cum = 0;
  final cums = <int>[];
  for (final p in parts) {
    cum += p.$2;
    cums.add(cum);
  }
  bool ended(String key) {
    final m = ms.where((x) => x.key == key).firstOrNull ?? momentOf(key);
    return nowMin >= m.endMin;
  }

  var i = 0;
  while (i < parts.length - 1 && (dayDone >= cums[i] || ended(parts[i].$1))) {
    i++;
  }
  final start = i == 0 ? 0 : (dayDone < cums[i - 1] ? dayDone : cums[i - 1]);
  return MomentShare(parts[i].$1, (dayDone - start).clamp(0, cums[i] - start), cums[i] - start);
}

/// Moment d'une routine non répartie (ou atteinte) : son réglage ; une
/// routine répartie atteinte reste dans son dernier moment.
String _homeOf(Activity a) {
  final keys = splitMomentsOf(a);
  return keys.isNotEmpty ? keys.last : momentKeyOf(a);
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
  int dayStartMin = kDefaultDayStartMin,
  List<Moment>? moments,
}) {
  final ms = moments ?? timedMomentsWith(const {}, dayStartMin: dayStartMin);
  // Journée vécue : avant la bascule, le moment courant reste « ce soir ».
  final nowMin = livedNowMin(now, dayStartMin);
  final current = currentMoment(nowMin, ms);
  final todos = routinesForToday(activities, hits, now, dayStartMin: dayStartMin);
  final slots = <RoutineSlot>[
    for (final t in todos)
      if (momentShareOf(t.activity, dayDone: t.dayDone, dayTarget: t.dayTarget, nowMin: nowMin, moments: ms) case final share?)
        RoutineSlot(t, share.moment, pushed[t.activity.id] ?? share.moment, share: share)
      else
        RoutineSlot(t, _homeOf(t.activity), pushed[t.activity.id] ?? _homeOf(t.activity)),
  ]..sort(_cmpSlots);
  return RoutineDay(current, slots, deferred, dismissed, moments: ms);
}
