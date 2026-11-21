import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin;

/// Mode Sniper (maquette validée 2026-11-01) : entre la Guérilla et
/// l'Offensive. L'app prend les enjeux du jour (`buildStakeBoard`), calcule le
/// temps EXACT qui fait tomber chacun (37 min de Lecture = pile ce qui couvre
/// la Montre suisse), les range — ce qui se perd ce soir, puis les paliers de
/// ce soir, puis le plus de gain par minute — et garde ce qui tient dans le
/// temps libre jusqu'au prochain rendez-vous. Puis on enchaîne les tirs, sans
/// décision entre deux. Une session est une [ChainRun] `kind:"sniper"`
/// (`doneCount` = cibles touchées, `total` = cibles visées) ; elle compte pour
/// le badge Sniper quand toutes les cibles visées sont touchées, au moins
/// [kSniperCountedMin]. Logique pure.
const kSniperKind = 'sniper';
const kSniperPauseMin = 2;
const kSniperMaxMin = 60;
const kSniperMaxTargets = 8;
const kSniperCountedMin = 3;
const kSniperTiers = [1, 5, 15];

enum SniperKind { routine, timed, action, reading }

/// Sniper par moment (maquette validée 2026-11-21) : le viseur range ses cibles en trois parties — ce qui reste des
/// moments d'avant, les routines du moment, puis le reste de ce qui est en jeu.
const kSniperSecLeft = 0;
const kSniperSecMoment = 1;
const kSniperSecOther = 2;
const kSniperLaterPrefix = 'plus tard · ';

/// À moins de [kSniperMomentLeadMin] de la fin d'un moment, le Sniper prend déjà le suivant.
const kSniperMomentLeadMin = 15;

/// Le moment vu par le Sniper : où va chaque routine (clé de geste `routine:<id>`), ce qui attend un moment plus
/// tard, et la part à viser d'une routine répartie.
class SniperScope {
  final Moment moment;

  /// `routine:<id>` → [kSniperSecLeft] ou [kSniperSecMoment] ; absente = [kSniperSecOther].
  final Map<String, int> section;

  /// `routine:<id>` → « cet après-midi » : routine d'un moment plus tard, mise de côté.
  final Map<String, String> later;

  /// `routine:<id>` → coches de la part du moment (routine répartie), et sa phrase (« 1 d'avant + 2 ce matin »).
  final Map<String, int> shareLeft;
  final Map<String, String> shareLabel;

  /// « RESTE DU MATIN », « RESTE D'AVANT ».
  final String leftLabel;

  /// Les moments plus tard qui ont des routines, dans l'ordre de la journée (« cet après-midi », « ce soir »).
  final List<String> laterOrder;

  /// « avant midi » : ce qui borne la lunette quand aucun bloc ne vient avant la fin du moment (null = dernier moment).
  final String? before;
  const SniperScope({
    required this.moment,
    this.section = const {},
    this.later = const {},
    this.shareLeft = const {},
    this.shareLabel = const {},
    this.leftLabel = 'RESTE D’AVANT',
    this.laterOrder = const [],
    this.before,
    this.rank = const {},
  });

  /// Pendant le Miracle Morning, le viseur est un rituel : ses routines dans TON ordre ([rank]), et rien d'autre
  /// (les autres enjeux attendent derrière « Plus tard »).
  bool get ritual => moment.key == kMomentMiracle;

  /// `routine:<id>` → rang dans l'ordre réglé des routines du moment (rituel seulement).
  final Map<String, int> rank;

  /// « 5 cet après-midi · 4 ce soir » pour ce qui est mis de côté ; au-delà de deux groupes, le premier puis
  /// « n ensuite ».
  String laterLine(List<SniperMiss> misses) {
    final n = <String, int>{};
    for (final m in misses) {
      final w = m.reason.startsWith(kSniperLaterPrefix) ? m.reason.substring(kSniperLaterPrefix.length) : m.reason;
      n[w] = (n[w] ?? 0) + 1;
    }
    final labels = [
      for (final w in laterOrder)
        if (n.containsKey(w)) w,
      for (final w in n.keys)
        if (!laterOrder.contains(w)) w,
    ];
    if (labels.length <= 2) return [for (final w in labels) '${n[w]} $w'].join(' · ');
    final rest = labels.skip(1).fold<int>(0, (s, w) => s + n[w]!);
    return '${n[labels.first]} ${labels.first} · $rest ensuite';
  }

  /// « CE MATIN », « MIRACLE MORNING ».
  String get momentLabel => ritual ? 'MIRACLE MORNING' : moment.thisOne.toUpperCase();

  String sectionLabel(int section) => switch (section) {
        kSniperSecLeft => leftLabel,
        kSniperSecMoment => momentLabel,
        _ => 'AUSSI EN JEU',
      };
}

/// Le moment vu par le Sniper, d'après la journée en routines ([buildRoutineDay]).
SniperScope sniperScopeOf(RoutineDay day) {
  final cur = day.current;
  final section = <String, int>{}, later = <String, String>{}, shareLeft = <String, int>{}, shareLabel = <String, String>{};
  final from = <String>{};
  final rank = <String, int>{};
  final ritual = cur.key == kMomentMiracle;
  for (final s in day.slots) {
    if (s.reached || day.dismissed.contains(s.id)) continue;
    final m = day.timed.where((x) => x.key == s.moment).firstOrNull;
    final key = 'routine:${s.id}';
    if (m == null) {
      // « Toute la journée » à plusieurs fois par jour : répartie sur la journée (du matin au soir). Libre et
      // « Toute la journée » à une fois restent avec le reste de ce qui est en jeu.
      if (s.moment == kMomentAllDay) _spreadAllDay(day, s, key, section: section, later: later, shareLeft: shareLeft, shareLabel: shareLabel);
      continue;
    }
    if (m.key == cur.key) {
      section[key] = kSniperSecMoment;
      // Les routines arrivent déjà dans l'ordre réglé (« Organiser »).
      if (ritual) rank[key] = rank.length;
    } else if (m.endMin <= cur.startMin) {
      section[key] = kSniperSecLeft;
      from.add(m.key);
    } else {
      later[key] = m.thisOne;
      continue;
    }
    final sh = s.share;
    final dayLeft = (s.todo.dayTarget ?? 0) - s.todo.dayDone;
    if (sh != null && sh.left > 0 && sh.left < dayLeft) {
      shareLeft[key] = sh.left;
      final own = sh.target - sh.carried;
      shareLabel[key] = sh.carried > 0 && sh.done == 0 ? '${sh.carried} d’avant + $own ${m.thisOne}' : 'part ${m.of} · ${sh.left} sur $dayLeft à faire';
    }
  }
  final left = from.length == 1 ? 'RESTE ${day.timed.firstWhere((m) => m.key == from.first).of.toUpperCase()}' : 'RESTE D’AVANT';
  final next = nextMomentAfter(cur, day.timed);
  final before = switch (next?.key) {
    null => null,
    kMomentMorning => 'avant le matin',
    kMomentMidday => 'avant midi',
    kMomentAfternoon => 'avant l’après-midi',
    kMomentEvening => 'avant le soir',
    _ => 'avant ${next!.label.toLowerCase()}',
  };
  return SniperScope(
    moment: cur,
    section: section,
    later: later,
    shareLeft: shareLeft,
    shareLabel: shareLabel,
    leftLabel: left,
    laterOrder: [for (final m in day.timed) if (later.containsValue(m.thisOne)) m.thisOne],
    before: before,
    rank: rank,
  );
}

/// Une routine « Toute la journée » à plusieurs fois par jour (8 verres d'eau, 2026-11-21, retour user : le Sniper
/// proposait les 8 dès le matin) : sa cible se partage à parts égales entre les moments du matin au soir (le Miracle
/// Morning reste au rituel), ce qui n'a pas été fait avant s'ajoute ; une part déjà faite la met de côté jusqu'au
/// moment suivant.
void _spreadAllDay(
  RoutineDay day,
  RoutineSlot s,
  String key, {
  required Map<String, int> section,
  required Map<String, String> later,
  required Map<String, int> shareLeft,
  required Map<String, String> shareLabel,
}) {
  final n = s.todo.dayTarget ?? 0;
  if (n < 2) return;
  final moments = [for (final m in day.timed) if (m.key != kMomentMiracle) m];
  if (moments.isEmpty) return;
  final cur = day.current;
  if (cur.key == kMomentMiracle) {
    later[key] = moments.first.thisOne;
    return;
  }
  final i = moments.indexWhere((m) => m.key == cur.key);
  if (i < 0) return;
  final parts = momentParts(n, [for (final m in moments) m.key]);
  final before = parts.take(i).fold<int>(0, (a, b) => a + b);
  final upTo = before + parts[i];
  final done = s.todo.dayDone;
  final left = upTo - done;
  if (left <= 0) {
    for (var j = i + 1; j < moments.length; j++) {
      if (parts[j] > 0) {
        later[key] = moments[j].thisOne;
        return;
      }
    }
    return;
  }
  section[key] = kSniperSecMoment;
  final dayLeft = n - done;
  if (left >= dayLeft) return;
  shareLeft[key] = left;
  final carried = before - done;
  shareLabel[key] = carried > 0 ? '$carried d’avant + ${parts[i]} ${cur.thisOne}' : 'part ${cur.of} · $left sur $dayLeft à faire';
}

/// L'instant à regarder pour choisir le moment : à moins d'un quart d'heure de la fin du moment en cours, c'est
/// déjà le suivant (sauf le dernier de la journée). [nowMin] = minute de la journée vécue.
int sniperMomentShift(int nowMin, List<Moment> timed) {
  final cur = currentMoment(nowMin, timed);
  final left = cur.endMin - nowMin;
  if (nowMin < cur.startMin || left <= 0 || left >= kSniperMomentLeadMin) return 0;
  return nextMomentAfter(cur, timed) == null ? 0 : left;
}

/// Une action DANS une cible de temps (l'activité comme contenant, maquette validée 2026-11-21) : son geste
/// (projet, tâche, action, porteuse), sa durée estimée et pourquoi elle est là.
class SniperStep {
  final StakeGesture gesture;
  final int minutes;
  final String? reason;
  const SniperStep(this.gesture, {required this.minutes, this.reason});

  String get key => gesture.key;
  String get title => gesture.title;
  TaskAction? get action => gesture.action;
}

class SniperTarget {
  final Stake stake;
  final SniperKind kind;

  /// Durée du minuteur (0 = un geste immédiat : +1, relevé).
  final int minutes;

  /// Routine : nombre de +1 pour l'atteindre.
  final int delta;
  final int? _need;

  /// Partie du viseur ([kSniperSecLeft], [kSniperSecMoment], [kSniperSecOther]).
  final int section;

  /// Rang dans un rituel (Miracle Morning) : l'ordre réglé passe avant l'ordre calculé. Null ailleurs.
  final int? rank;

  /// Cible de temps d'une activité qui CONTIENT ses actions (promises, visées, en retard, prochaine
  /// action d'un projet lié) : on les fait l'une après l'autre dans le même tir, le reste du temps est
  /// libre sur l'activité. Vide = une cible de temps simple.
  final List<SniperStep> steps;
  const SniperTarget(this.stake, this.kind,
      {required this.minutes, this.delta = 1, int? need, this.section = kSniperSecOther, this.rank, this.steps = const []})
      : _need = need;

  bool get isContainer => steps.isNotEmpty;

  /// Minutes des actions du contenant.
  int get stepsMin => steps.fold(0, (s, x) => s + x.minutes);

  /// Temps libre sur l'activité une fois ses actions faites.
  int get freeMin => minutes > stepsMin ? minutes - stepsMin : 0;

  /// Les actions choisies à la main : le tir dure ce qui manque à l'activité, ou plus si les actions
  /// le demandent.
  SniperTarget withSteps(List<SniperStep> list) {
    final sum = list.fold(0, (s, x) => s + x.minutes);
    final base = stake.gesture.costMin;
    final m = sum > base ? sum : base;
    return SniperTarget(stake, kind, minutes: m, delta: delta, need: m, section: section, rank: rank, steps: list);
  }

  /// Routine à minuteur (Louanges 15 min) : on règle la durée, la coche
  /// tombe au bout quel que soit le temps choisi.
  bool get timedRoutine => kind == SniperKind.routine && minutes > 0;
  bool get _countsReps => kind == SniperKind.routine && !timedRoutine;

  /// Ce qu'on vise : coches pour une routine, minutes sinon (et pour une
  /// routine à minuteur).
  int get amount => _countsReps ? delta : minutes;

  /// Ce qui manque à la journée (la cible proposée au départ).
  int get need => _need ?? amount;

  /// Un relevé est un geste, il ne s'ajuste pas.
  bool get adjustable => kind != SniperKind.reading;

  /// Mini-tir : moins que ce qui manque, l'enjeu ne tombe pas encore (une
  /// action tombe à « Action faite », quel que soit le temps visé).
  bool get isMini => (_countsReps || kind == SniperKind.timed) && amount < need;

  /// Ce qui restera à faire après ce tir.
  int get leftAfter => need > amount ? need - amount : 0;

  SniperTarget withAmount(int a) => _countsReps
      ? SniperTarget(stake, kind, minutes: minutes, delta: a, need: need, section: section, rank: rank, steps: steps)
      : SniperTarget(stake, kind, minutes: a, delta: delta, need: need, section: section, rank: rank, steps: steps);

  String get key => stake.gesture.key;
  String get title => stake.gesture.title;
  List<StakeGain> get gains => stake.gains;
  bool get losesTonight => stake.losesTonight;
  bool get tierTonight => gains.any((g) => g.kind == StakeGainKind.tierTonight || g.label.contains('palier'));
  int get weight => gains.fold(0, (s, g) => s + g.weight);

  /// « 37 min », « +1 », « +3 », « 1 min ».
  String get durLabel {
    if (kind == SniperKind.routine && minutes == 0) return '+$delta';
    if (minutes == 0) return '1 min';
    return '$minutes min';
  }

  /// Minutes comptées dans le budget (un geste immédiat compte 1 min).
  int get cost => minutes == 0 ? 1 : minutes;
}

/// Trace d'une cible visée, gardée dans la session : une cible déjà touchée n'est plus dans les enjeux du jour, la
/// reprise la retrouve quand même à sa place (sinon la session perd ses tirs à chaque réouverture, bug user 2026-11-21).
Map<String, dynamic> sniperSnapshot(SniperTarget t) => {
      't': t.title,
      'k': t.kind.name,
      'm': t.minutes,
      'd': t.delta,
      'n': t.need,
      's': t.section,
      'g': [
        for (final g in t.gains) {'k': g.kind.name, 'l': g.label, 'w': g.weight, if (g.losesTonight) 'x': true},
      ],
    };

/// La cible reconstituée d'après sa trace (null si la trace est illisible). Elle ne porte plus d'objet de l'app :
/// elle ne sert qu'à garder sa place, son titre et ses gains (piste, bilan).
SniperTarget? sniperFromSnapshot(String key, Object? snap) {
  if (snap is! Map) return null;
  final kind = SniperKind.values.where((k) => k.name == snap['k']).firstOrNull;
  final title = snap['t'];
  if (kind == null || title is! String) return null;
  int n(Object? v, int d) => v is num ? v.toInt() : d;
  final minutes = n(snap['m'], 0);
  final gains = <StakeGain>[
    if (snap['g'] case final List gl)
      for (final g in gl)
        if (g is Map && g['l'] is String)
          StakeGain(
            kind: StakeGainKind.values.where((k) => k.name == g['k']).firstOrNull ?? StakeGainKind.routine,
            label: g['l'] as String,
            weight: n(g['w'], 0),
            losesTonight: g['x'] == true,
          ),
  ];
  final gesture = StakeGesture(
    key: key,
    kind: switch (kind) {
      SniperKind.routine => StakeGestureKind.routine,
      SniperKind.timed => StakeGestureKind.activity,
      SniperKind.action => StakeGestureKind.action,
      SniperKind.reading => StakeGestureKind.reading,
    },
    title: title,
    costMin: minutes == 0 ? 1 : minutes,
  );
  return SniperTarget(Stake(gesture, gains), kind,
      minutes: minutes, delta: n(snap['d'], 1), need: n(snap['n'], kind == SniperKind.routine && minutes == 0 ? n(snap['d'], 1) : minutes), section: n(snap['s'], kSniperSecOther));
}

class SniperMiss {
  final SniperTarget target;
  final String reason;
  const SniperMiss(this.target, this.reason);
}

class SniperPlan {
  final List<SniperTarget> aimed;
  final List<SniperMiss> outOfReach;

  /// Routines d'un moment plus tard dans la journée : pas proposées, mais on peut en avancer une.
  final List<SniperMiss> later;
  final int budgetMin;
  final int pauseMin;
  const SniperPlan({this.aimed = const [], this.outOfReach = const [], this.later = const [], required this.budgetMin, this.pauseMin = kSniperPauseMin});

  /// Temps des tirs + pauses entre eux.
  int get totalMin => totalOf(aimed, pauseMin);
  static int totalOf(List<SniperTarget> t, int pauseMin) => t.isEmpty ? 0 : t.fold<int>(0, (s, x) => s + x.cost) + pauseMin * (t.length - 1);
}

int _round5(num m) => ((m / 5).ceil() * 5).toInt();

/// L'activité sur laquelle tourne le chrono d'une action : la sienne, sinon celle du projet, sinon la porteuse.
String? chronoActivityIdOf(StakeGesture g) => g.action?.linkedActivityId ?? g.project?.linkedActivityId ?? g.owner?.id;

/// Pourquoi une action est dans le tir, d'après ses gains.
String? _stepReason(List<StakeGain> gains) {
  if (gains.any((g) => g.label.startsWith('Parole'))) return 'promise hier';
  if (gains.any((g) => g.kind == StakeGainKind.focus)) return 'visée aujourd’hui';
  if (gains.any((g) => g.kind == StakeGainKind.session)) return 'prépa de séance';
  return gains.isEmpty ? null : gains.first.label;
}

/// L'activité comme contenant : une action dont le chrono tourne sur une activité déjà visée en temps
/// n'est plus une cible à part (son temps compte déjà pour l'activité, il était demandé deux fois). Elle
/// entre dans la cible de l'activité, avec ses gains ; puis [fill] (par activité, dans l'ordre de
/// priorité) complète tant que le temps de l'activité n'est pas rempli. Le tir dure ce qui manque à
/// l'activité, ou plus si les actions absorbées le demandent.
List<SniperTarget> containTargets(List<SniperTarget> targets, {Map<String, List<SniperStep>> fill = const {}}) {
  final acts = <String>{
    for (final t in targets)
      if (t.kind == SniperKind.timed && t.stake.gesture.kind == StakeGestureKind.activity && t.stake.gesture.activity != null) t.stake.gesture.activity!.id,
  };
  if (acts.isEmpty) return targets;
  final absorbed = <String, List<SniperTarget>>{};
  final rest = <SniperTarget>[];
  for (final t in targets) {
    final id = t.kind == SniperKind.action ? chronoActivityIdOf(t.stake.gesture) : null;
    if (id != null && acts.contains(id)) {
      (absorbed[id] ??= []).add(t);
    } else {
      rest.add(t);
    }
  }
  return [
    for (final t in rest)
      if (t.kind == SniperKind.timed && t.stake.gesture.activity != null && acts.contains(t.stake.gesture.activity!.id))
        containerOf(t, absorbed[t.stake.gesture.activity!.id] ?? const [], fill[t.stake.gesture.activity!.id] ?? const [])
      else
        t,
  ];
}

/// La cible de temps [t] avec ses actions : celles qu'elle absorbe d'abord (ce qui se perd ce soir
/// devant), puis celles de [fill] qui tiennent encore dans son temps.
SniperTarget containerOf(SniperTarget t, List<SniperTarget> absorbed, List<SniperStep> fill) {
  final abs = [...absorbed]..sort(compareSniper);
  final steps = [for (final a in abs) SniperStep(a.stake.gesture, minutes: a.minutes, reason: _stepReason(a.gains))];
  final absMin = steps.fold(0, (s, x) => s + x.minutes);
  final base = t.minutes;
  final seen = {for (final x in steps) x.key};
  var used = absMin;
  for (final f in fill) {
    if (seen.contains(f.key) || used + f.minutes > base) continue;
    steps.add(f);
    seen.add(f.key);
    used += f.minutes;
  }
  final m = absMin > base ? absMin : base;
  final labels = {for (final g in t.gains) g.label};
  final gains = [
    ...t.gains,
    for (final a in abs)
      for (final g in a.gains)
        if (labels.add(g.label)) g,
  ];
  return SniperTarget(Stake(t.stake.gesture, gains), SniperKind.timed, minutes: m, need: m > base ? m : t.need, section: t.section, rank: t.rank, steps: steps);
}

/// La cible d'un enjeu, ou null quand le Sniper ne s'en charge pas (bloc à
/// heure fixe, enjeu sans badge ni objectif). [routineLeft] = coches restantes
/// des routines du jour ; [factor] = réel / estimé des actions. Avec un
/// [scope] (Sniper par moment), toute routine du jour est une cible, et une
/// routine répartie ne vise que la part du moment.
SniperTarget? sniperTargetOf(Stake s, {Map<String, int> routineLeft = const {}, double factor = 1, SniperScope? scope}) {
  final g = s.gesture;
  if (s.gains.every((x) => x.kind == StakeGainKind.routine) && !(scope != null && g.kind == StakeGestureKind.routine)) return null;
  final section = scope?.section[g.key] ?? kSniperSecOther;
  switch (g.kind) {
    case StakeGestureKind.block:
      return null;
    case StakeGestureKind.routine:
      final share = scope?.shareLeft[g.key];
      final left = share ?? routineLeft[g.activity?.id] ?? 1;
      final timer = g.activity?.timerMin ?? 0;
      // Une part ne fait pas tomber la série : elle ne montre que ce qu'elle est.
      final stake = share == null
          ? s
          : Stake(g, [StakeGain(kind: StakeGainKind.routine, label: scope!.shareLabel[g.key] ?? 'part du moment', weight: s.gains.fold(0, (w, x) => w + x.weight))]);
      return SniperTarget(stake, SniperKind.routine, minutes: timer > 0 ? timer : 0, delta: left < 1 ? 1 : left, section: section, rank: scope?.rank[g.key]);
    case StakeGestureKind.activity:
      return SniperTarget(s, SniperKind.timed, minutes: g.costMin < 1 ? 1 : g.costMin, section: section);
    case StakeGestureKind.action:
      final est = g.action?.estimatedMin ?? 45;
      final m = _round5(est * (factor <= 0 ? 1 : factor));
      return SniperTarget(s, SniperKind.action, minutes: m < 5 ? 5 : m, section: section);
    case StakeGestureKind.reading:
      return SniperTarget(s, SniperKind.reading, minutes: 0, section: section);
  }
}

/// Ordre des tirs : la partie du viseur (reste d'avant, moment, le reste), puis
/// se perd ce soir → palier ce soir → gain par minute.
int compareSniper(SniperTarget a, SniperTarget b) {
  if (a.section != b.section) return a.section.compareTo(b.section);
  if (a.rank != null && b.rank != null && a.rank != b.rank) return a.rank!.compareTo(b.rank!);
  if (a.losesTonight != b.losesTonight) return a.losesTonight ? -1 : 1;
  if (a.tierTonight != b.tierTonight) return a.tierTonight ? -1 : 1;
  final ra = a.weight / (a.cost + 3), rb = b.weight / (b.cost + 3);
  final c = rb.compareTo(ra);
  if (c != 0) return c;
  return a.cost.compareTo(b.cost);
}

String _hm(int min) {
  final m = min % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Le plan : les cibles qui tiennent dans [budgetMin] (pauses comprises), le
/// reste « hors de portée » avec sa raison. [untilMin] = heure du rendez-vous
/// qui borne le temps (pour la raison « ne tient plus avant HH:MM »).
SniperPlan planSniper({
  required List<Stake> stakes,
  required int budgetMin,
  int? untilMin,
  Map<String, int> routineLeft = const {},
  double factor = 1,
  int pauseMin = kSniperPauseMin,
  int maxTargets = kSniperMaxTargets,
  int maxMin = kSniperMaxMin,
  Set<String> excluded = const {},
  SniperScope? scope,
  Map<String, List<SniperStep>> fill = const {},
}) {
  var targets = <SniperTarget>[];
  final later = <SniperMiss>[];
  for (final s in stakes) {
    if (excluded.contains(s.gesture.key)) continue;
    final t = sniperTargetOf(s, routineLeft: routineLeft, factor: factor, scope: scope);
    if (t == null) continue;
    if (scope?.later[t.key] case final at?) {
      later.add(SniperMiss(t, '$kSniperLaterPrefix$at'));
    } else if (scope != null && scope.ritual && t.section == kSniperSecOther) {
      // Pendant le Miracle Morning, rien d'autre que le rituel.
      later.add(SniperMiss(t, '${kSniperLaterPrefix}ensuite'));
    } else {
      targets.add(t);
    }
  }
  targets = containTargets(targets, fill: fill)..sort(compareSniper);
  final aimed = <SniperTarget>[];
  final out = <SniperMiss>[];
  var used = 0;
  for (final t in targets) {
    if (t.minutes > maxMin) {
      out.add(SniperMiss(t, 'plus d’une heure · pour l’Offensive'));
      continue;
    }
    if (aimed.length >= maxTargets) {
      out.add(SniperMiss(t, 'au-delà de $maxTargets cibles'));
      continue;
    }
    final add = t.cost + (aimed.isEmpty ? 0 : pauseMin);
    if (used + add > budgetMin) {
      out.add(SniperMiss(t, untilMin == null ? 'ne tient plus dans ton temps libre' : 'ne tient plus avant ${_hm(untilMin)}'));
      continue;
    }
    used += add;
    aimed.add(t);
  }
  return SniperPlan(aimed: aimed, outOfReach: out, later: later, budgetMin: budgetMin, pauseMin: pauseMin);
}

/// Le temps libre à partir de [nowMin] (minute de la journée vécue) : jusqu'au
/// prochain bloc À FAIRE qui commence plus tard (hors blocs de temps, qu'un
/// Sniper peut occuper), sinon jusqu'à [endMin]. [until] = ce bloc.
({int minutes, int untilMin, ScheduleBlock? until}) sniperBudget({required List<ScheduleBlock> blocks, required int nowMin, required int endMin}) {
  ScheduleBlock? next;
  for (final b in blocks) {
    if (b.status != 'pending' || b.isTimeBlock) continue;
    final s = blockStartMin(b);
    if (s <= nowMin) continue;
    if (next == null || s < blockStartMin(next)) next = b;
  }
  final until = next == null ? endMin : (blockStartMin(next) < endMin ? blockStartMin(next) : endMin);
  final m = until - nowMin;
  return (minutes: m < 0 ? 0 : m, untilMin: until, until: next != null && blockStartMin(next) <= endMin ? next : null);
}

/// Précision d'un tir ou d'une session : 100 % quand le temps tiré égale le
/// temps visé, moins l'écart relatif.
int sniperPrecision(int aimedMin, int firedMin) {
  if (aimedMin <= 0) return 100;
  final p = 100 - ((firedMin - aimedMin).abs() * 100 / aimedMin).round();
  return p < 0 ? 0 : p;
}

bool isSniperRun(ChainRun r) => r.kind == kSniperKind;

/// Une session compte : toutes les cibles visées touchées, dont au moins 3
/// EN ENTIER (2026-11-01 : un mini-tir est touché mais ne compte pas parmi
/// les 3 ; une session d'avant les mini-tirs n'a pas `fullCount`).
bool sniperSessionCounts({required int hit, required int aimed, required int full}) => hit >= aimed && full >= kSniperCountedMin;
bool sniperCounts(ChainRun r) => isSniperRun(r) && sniperSessionCounts(hit: r.doneCount, aimed: r.total, full: r.fullCount ?? r.doneCount);

String sniperCountLine(int hit, int aimed, {int? full}) {
  final f = full ?? hit;
  final mini = hit - f;
  final pre = mini > 0 ? 'dont $f pleine${f > 1 ? 's' : ''} · ' : '';
  if (sniperSessionCounts(hit: hit, aimed: aimed, full: f)) return '${pre}session comptée';
  if (f < kSniperCountedMin) return '$pre${mini > 0 ? 'il faut $kSniperCountedMin cibles pleines' : 'une session compte dès $kSniperCountedMin cibles, toutes touchées'}';
  return '${pre}une session compte quand toutes les cibles visées tombent';
}

/// Le plan ajusté à la main (2026-11-01, retour user : écarter une cible
/// faisait entrer la suivante hors de portée, le temps visé ne bougeait
/// pas) : on part du plan calculé une fois ([base]), on retire les cibles
/// écartées et on ajoute celles que la personne a choisies parmi les hors
/// de portée. Rien ne rentre tout seul.
///
/// [amounts] = tirs ajustés à la main (2026-11-01, retour user : 20 pompes
/// d'un coup, 6 verres d'eau) : coches ou minutes par cible. L'ordre reste
/// celui des cibles entières, il ne bouge pas pendant qu'on ajuste.
///
/// [order] = l'ordre des tirs posé à la main (null = l'ordre conseillé) :
/// les cibles qu'il ne connaît pas viennent après, dans l'ordre conseillé.
SniperPlan adjustPlan(SniperPlan base, {Set<String> excluded = const {}, Set<String> added = const {}, Map<String, int> amounts = const {}, List<String>? order}) {
  final sorted = [
    for (final t in base.aimed)
      if (!excluded.contains(t.key)) t,
    for (final m in [...base.outOfReach, ...base.later])
      if (added.contains(m.target.key) && !excluded.contains(m.target.key)) m.target,
  ]..sort(compareSniper);
  if (order != null) {
    final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
    final conseil = {for (var i = 0; i < sorted.length; i++) sorted[i].key: i};
    sorted.sort((a, b) => (rank[a.key] ?? order.length + conseil[a.key]!).compareTo(rank[b.key] ?? order.length + conseil[b.key]!));
  }
  final aimed = [
    for (final t in sorted)
      if (amounts[t.key] case final a? when t.adjustable && a > 0) t.withAmount(a) else t,
  ];
  final out = [
    for (final m in base.outOfReach)
      if (!added.contains(m.target.key)) m
  ];
  final later = [
    for (final m in base.later)
      if (!added.contains(m.target.key)) m
  ];
  return SniperPlan(aimed: aimed, outOfReach: out, later: later, budgetMin: base.budgetMin, pauseMin: base.pauseMin);
}

/// La cible tient-elle encore dans le temps libre, en plus de [aimed] ?
/// Une cible déjà visée (même clé) est remplacée : sert aussi à vérifier
/// qu'un tir agrandi tient.
bool fitsPlan(SniperPlan plan, SniperTarget t) =>
    SniperPlan.totalOf([
      for (final x in plan.aimed)
        if (x.key != t.key) x,
      t
    ], plan.pauseMin) <=
    plan.budgetMin;

/// Le pas d'ajustement : 5 coches pour une routine à 10 ou plus, 1 sinon ;
/// 5 min pour un temps.
int sniperStep(SniperTarget t) => t.kind == SniperKind.routine && !t.timedRoutine ? (t.need >= 10 ? 5 : 1) : 5;

/// Le tir suivant en montant ou en descendant, null quand il est au bout :
/// une routine de 1 à ce qui manque (au-delà, rien ne compte de plus) ; un
/// temps de 5 min (ou moins si ce qui manque est plus court) à
/// [kSniperMaxMin], calé sur les multiples de 5.
int? stepAmount(SniperTarget t, {required bool up}) {
  if (!t.adjustable) return null;
  final step = sniperStep(t);
  final a = t.amount;
  if (t.kind == SniperKind.routine && !t.timedRoutine) {
    final n = up ? ((a ~/ step) + 1) * step : ((a - 1) ~/ step) * step;
    final c = n < 1 ? 1 : (n > t.need ? t.need : n);
    return c == a ? null : c;
  }
  final lo = t.need < 5 ? t.need : 5;
  final n = up ? ((a ~/ step) + 1) * step : ((a - 1) ~/ step) * step;
  final c = n < lo ? lo : (n > kSniperMaxMin ? kSniperMaxMin : n);
  return c == a ? null : c;
}
