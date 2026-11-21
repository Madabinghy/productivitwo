import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

/// Sniper par moment (maquette validée 2026-11-21) : le viseur ne propose que les routines du moment et ce qui
/// reste des moments d'avant ; celles des moments plus tard attendent derrière « Plus tard ».
Activity _r(String id, String name, {String? ctx, int target = 1, List<String> split = const []}) =>
    Activity(id: id, domainId: 'd', name: name, type: 'habit', habitFreq: HabitFreq.daily, habitTarget: target, timeContext: ctx)..splitMoments = split;

HabitHit _hit(String id, DateTime at, int k) => HabitHit(id: '$id-$k', habitId: id, ts: at);

void main() {
  final lit = _r('lit', 'Faire mon lit', ctx: 'morning');
  final lou = _r('lou', 'Louanges', ctx: 'morning');
  final vai = _r('vai', 'Vaisselle', ctx: 'midday');
  final mar = _r('mar', 'Marche', ctx: 'afternoon');
  final den = _r('den', 'Dents', ctx: 'evening');
  final eau = _r('eau', 'Verre d’eau', target: 8, split: const [kMomentMorning, kMomentMidday, kMomentAfternoon, kMomentEvening]);
  final lib = _r('lib', 'Louer', ctx: null);
  final all = [lit, lou, vai, mar, den, eau, lib];

  Stake plain(Activity a, {int done = 0}) => Stake(
        StakeGesture(key: 'routine:${a.id}', kind: StakeGestureKind.routine, title: a.name, costMin: 5, activity: a, progress: '$done / ${a.habitTarget}'),
        [StakeGain(kind: StakeGainKind.routine, label: '$done / ${a.habitTarget} aujourd’hui', weight: 4)],
      );
  Stake serie(Activity a, {bool loses = true}) => Stake(
        StakeGesture(key: 'routine:${a.id}', kind: StakeGestureKind.routine, title: a.name, costMin: 5, activity: a),
        [StakeGain(kind: StakeGainKind.seriesTonight, label: 'série 12 j', weight: 30, losesTonight: loses)],
      );
  final kingdom = Stake(
    StakeGesture(key: 'activity:k', kind: StakeGestureKind.activity, title: 'Kingdom', costMin: 25),
    const [StakeGain(kind: StakeGainKind.halfDay, label: 'Montre suisse', weight: 12, losesTonight: true)],
  );

  SniperScope scopeAt(int h, int m, {List<HabitHit> hits = const []}) =>
      sniperScopeOf(buildRoutineDay(activities: all, hits: hits, now: DateTime(2026, 11, 21, h, m)));

  test('à midi : le midi est le moment, le matin pas fait est « resté », l’après-midi et le soir attendent', () {
    final sc = scopeAt(12, 0);
    expect(sc.moment.key, kMomentMidday);
    expect(sc.section['routine:vai'], kSniperSecMoment);
    expect(sc.section['routine:lit'], kSniperSecLeft);
    expect(sc.section['routine:lou'], kSniperSecLeft);
    expect(sc.later, {'routine:mar': 'cet après-midi', 'routine:den': 'ce soir'});
    expect(sc.laterOrder, ['cet après-midi', 'ce soir']);
    expect(sc.leftLabel, 'RESTE DU MATIN');
    expect(sc.momentLabel, 'CE MIDI');
    expect(sc.before, 'avant l’après-midi');
    // Une routine sans moment n'est ni du moment ni mise de côté.
    expect(sc.section.containsKey('routine:lib'), isFalse);
    expect(sc.later.containsKey('routine:lib'), isFalse);
  });

  test('routine répartie : la part du moment, plus ce qui n’a pas été fait avant', () {
    // 8 par jour sur 4 moments = 2 · 2 · 2 · 2. Rien bu le matin : à midi, 2 d'avant + 2 ce midi.
    final none = scopeAt(12, 0);
    expect(none.section['routine:eau'], kSniperSecMoment);
    expect(none.shareLeft['routine:eau'], 4);
    expect(none.shareLabel['routine:eau'], '2 d’avant + 2 ce midi');
    // Les 2 du matin bus : la part de midi seulement.
    final at = DateTime(2026, 11, 21, 8, 0);
    final drunk = scopeAt(12, 0, hits: [_hit('eau', at, 1), _hit('eau', at, 2)]);
    expect(drunk.shareLeft['routine:eau'], 2);
    expect(drunk.shareLabel['routine:eau'], 'part du midi · 2 sur 6 à faire');
    // Le soir, il ne reste que la fin de la journée : plus de part, la cible entière (et ses vrais enjeux).
    expect(scopeAt(20, 0).shareLeft.containsKey('routine:eau'), isFalse);
  });

  test('le plan : reste d’avant, puis le moment, puis le reste de ce qui est en jeu ; plus tard à part', () {
    final sc = scopeAt(12, 0);
    final stakes = [kingdom, plain(den), plain(mar), plain(vai), plain(lib), serie(lou), plain(lit), plain(eau)];
    final plan = planSniper(stakes: stakes, budgetMin: 120, routineLeft: {'eau': 8, 'lit': 1, 'lou': 1, 'vai': 1, 'lib': 1}, scope: sc);
    expect([for (final t in plan.aimed) t.key], ['routine:lou', 'routine:lit', 'routine:vai', 'routine:eau', 'activity:k', 'routine:lib']);
    expect([for (final t in plan.aimed) t.section], [kSniperSecLeft, kSniperSecLeft, kSniperSecMoment, kSniperSecMoment, kSniperSecOther, kSniperSecOther]);
    expect([for (final m in plan.later) m.target.key], ['routine:den', 'routine:mar']);
    expect(plan.later.first.reason, 'plus tard · ce soir');
    // La part : +4, et le tir ne montre que la part (la série ne tombe pas avec elle).
    final water = plan.aimed.firstWhere((t) => t.key == 'routine:eau');
    expect(water.delta, 4);
    expect(water.need, 4);
    expect(water.isMini, isFalse);
    expect(water.gains.single.label, '2 d’avant + 2 ce midi');
  });

  test('avancer une routine de plus tard : elle n’entre que choisie', () {
    final sc = scopeAt(12, 0);
    final base = planSniper(stakes: [plain(vai), plain(mar), plain(den)], budgetMin: 60, scope: sc);
    expect([for (final t in base.aimed) t.key], ['routine:vai']);
    final more = adjustPlan(base, added: {'routine:mar'});
    expect([for (final t in more.aimed) t.key], ['routine:vai', 'routine:mar']);
    expect([for (final m in more.later) m.target.key], ['routine:den']);
  });

  test('sans moment (Sniper ciblé, anciens appels) : rien ne change', () {
    expect(sniperTargetOf(plain(vai)), isNull);
    final plan = planSniper(stakes: [plain(vai), serie(lou), kingdom], budgetMin: 60);
    expect(plan.later, isEmpty);
    expect(plan.aimed.every((t) => t.section == kSniperSecOther), isTrue);
  });

  miracleTests();

  test('« Toute la journée » à 8 : répartie du matin au soir, pas les 8 dès le matin', () {
    final water = _r('w', 'Boire de l’eau', ctx: 'allday', target: 8);
    final one = _r('o', 'Vaisselle', ctx: 'allday');
    SniperScope at(int h, int m, {int drunk = 0, bool miracle = false}) => sniperScopeOf(buildRoutineDay(
          activities: [water, one],
          hits: [for (var k = 0; k < drunk; k++) _hit('w', DateTime(2026, 11, 21, 7, k), k)],
          now: DateTime(2026, 11, 21, h, m),
          moments: miracle ? timedMomentsWith({kMomentMiracle: (300, 360)}) : null,
        ));
    // 8 sur matin · midi · après-midi · soir = 2 · 2 · 2 · 2.
    final morning = at(8, 0);
    expect(morning.section['routine:w'], kSniperSecMoment);
    expect(morning.shareLeft['routine:w'], 2);
    expect(morning.shareLabel['routine:w'], 'part du matin · 2 sur 8 à faire');
    // Une fois par jour : pas de partage, elle reste avec le reste.
    expect(morning.section.containsKey('routine:o'), isFalse);
    // À midi sans rien bu : 2 d'avant + 2 ce midi.
    final noon = at(12, 0);
    expect(noon.shareLeft['routine:w'], 4);
    expect(noon.shareLabel['routine:w'], '2 d’avant + 2 ce midi');
    // La part du matin bue : rien à faire avant midi.
    final done = at(9, 0, drunk: 2);
    expect(done.section.containsKey('routine:w'), isFalse);
    expect(done.later['routine:w'], 'ce midi');
    // Le soir : ce qui reste de la journée, la cible entière.
    expect(at(20, 0).shareLeft.containsKey('routine:w'), isFalse);
    expect(at(20, 0).section['routine:w'], kSniperSecMoment);
    // Pendant le Miracle Morning : elle attend le matin.
    final ritual = at(5, 15, miracle: true);
    expect(ritual.later['routine:w'], 'ce matin');
    final plan = planSniper(stakes: [
      Stake(StakeGesture(key: 'routine:w', kind: StakeGestureKind.routine, title: 'Eau', costMin: 5, activity: water),
          const [StakeGain(kind: StakeGainKind.routine, label: '0 / 8', weight: 4)]),
    ], budgetMin: 60, routineLeft: {'w': 8}, scope: morning);
    expect(plan.aimed.single.delta, 2);
  });

  test('à moins d’un quart d’heure de la fin d’un moment, le Sniper prend déjà le suivant', () {
    final ms = timedMomentsWith(const {});
    expect(sniperMomentShift(13 * 60 + 30, ms), 0);
    expect(sniperMomentShift(13 * 60 + 50, ms), 10);
    // Dans un creux (11 h → 11 h 30) le moment est déjà le suivant : rien à décaler.
    expect(sniperMomentShift(11 * 60 + 10, ms), 0);
    // Le soir est le dernier moment : jamais décalé.
    expect(sniperMomentShift(28 * 60 + 55, ms), 0);
  });
}

/// Lot 2 : Miracle Morning, un cinquième moment avant le matin, et les parts réglées d'une routine répartie.
void miracleTests() {
  // La journée commence à 3 h, le Miracle Morning va de 3 h à 6 h.
  const start = 3 * 60;
  final ms = timedMomentsWith({kMomentMiracle: (start, 6 * 60)}, dayStartMin: start);
  Activity r(String id, String name, {String? ctx, int target = 1, int? order, List<String> split = const [], Map<String, int>? shares}) =>
      Activity(id: id, domainId: 'd', name: name, type: 'habit', habitFreq: HabitFreq.daily, habitTarget: target, timeContext: ctx, splitMoments: split, momentShares: shares)
        ..routineOrder = order;
  const five = [kMomentMiracle, kMomentMorning, kMomentMidday, kMomentAfternoon, kMomentEvening];
  final eau = r('eau', 'Verre d’eau', target: 8, split: five, shares: {kMomentMiracle: 1, kMomentMorning: 2, kMomentMidday: 2, kMomentAfternoon: 2, kMomentEvening: 1});
  final lou = r('lou', 'Louanges', ctx: kMomentMiracle, order: 2);
  final lec = r('lec', 'Lecture', ctx: kMomentMiracle, order: 1);
  final lit = r('lit', 'Faire mon lit', ctx: kMomentMorning);
  final all = [eau, lou, lec, lit];
  Stake plain(Activity a) => Stake(
        StakeGesture(key: 'routine:${a.id}', kind: StakeGestureKind.routine, title: a.name, costMin: 5, activity: a),
        [const StakeGain(kind: StakeGainKind.routine, label: 'aujourd’hui', weight: 4)],
      );
  final kingdom = Stake(
    StakeGesture(key: 'activity:k', kind: StakeGestureKind.activity, title: 'Kingdom', costMin: 25),
    const [StakeGain(kind: StakeGainKind.halfDay, label: 'Montre suisse', weight: 12, losesTonight: true)],
  );
  RoutineDay dayAt(int h, int m, {List<HabitHit> hits = const [], List<Moment>? moments}) =>
      buildRoutineDay(activities: all, hits: hits, now: DateTime(2026, 11, 21, h, m), dayStartMin: start, moments: moments ?? ms);

  test('le moment Miracle Morning : avant le matin, de la bascule à sa fin ; le matin commence quand il finit', () {
    expect([for (final m in ms) m.key], five);
    expect((ms.first.startMin, ms.first.endMin), (start, 6 * 60));
    expect(ms[1].startMin, 6 * 60);
    expect(currentMoment(3 * 60 + 30, ms).key, kMomentMiracle);
    expect(currentMoment(6 * 60 + 10, ms).key, kMomentMorning);
    expect(validateMoments(ms), isNull);
    // Pas réglé : quatre moments, comme avant.
    expect([for (final m in timedMomentsWith(const {})) m.key], five.skip(1));
    // Le réglage se lit et se réécrit.
    final w = parseMomentWindows({'miracle': {'start': start, 'end': 360}});
    expect(w[kMomentMiracle], (start, 360));
    expect(momentOf(kMomentMiracle).label, 'Miracle Morning');
  });

  test('parts réglées : 1 · 2 · 2 · 2 · 1, et la somme suit la cible du jour', () {
    expect(momentParts(8, five, eau.momentShares), [1, 2, 2, 2, 1]);
    expect(momentParts(4, five, eau.momentShares), [1, 1, 1, 1, 0]);
    expect(momentParts(11, five, eau.momentShares).fold<int>(0, (s, x) => s + x), 11);
    // Sans réglage : parts égales, le surplus aux premiers.
    expect(momentParts(3, const [kMomentMorning, kMomentEvening]), [2, 1]);
    expect(momentParts(8, five), [2, 2, 2, 1, 1]);
  });

  test('l’eau : 1 au Miracle Morning, puis 2 de plus le matin — 3 si rien n’est bu', () {
    final at = dayAt(3, 30).slots.firstWhere((s) => s.id == 'eau').share!;
    expect((at.moment, at.done, at.target, at.carried), (kMomentMiracle, 0, 1, 0));
    final none = dayAt(6, 10).slots.firstWhere((s) => s.id == 'eau').share!;
    expect((none.moment, none.target, none.carried), (kMomentMorning, 3, 1));
    final drunk = dayAt(6, 10, hits: [_hit('eau', DateTime(2026, 11, 21, 3, 40), 1)]).slots.firstWhere((s) => s.id == 'eau').share!;
    expect((drunk.moment, drunk.done, drunk.target, drunk.carried), (kMomentMorning, 0, 2, 0));
  });

  test('moment Miracle Morning éteint : ses routines sont celles du matin, sa part aussi', () {
    final four = timedMomentsWith(const {}, dayStartMin: start);
    final d = dayAt(7, 0, moments: four);
    expect(d.slots.firstWhere((s) => s.id == 'lou').moment, kMomentMorning);
    final sh = d.slots.firstWhere((s) => s.id == 'eau').share!;
    expect((sh.moment, sh.target), (kMomentMorning, 3));
    expect(liveMomentParts(eau, 8, four), [(kMomentMorning, 3), (kMomentMidday, 2), (kMomentAfternoon, 2), (kMomentEvening, 1)]);
  });

  test('le Sniper pendant le Miracle Morning : un rituel, dans ton ordre, et rien d’autre', () {
    final sc = sniperScopeOf(dayAt(3, 30));
    expect(sc.ritual, isTrue);
    expect(sc.momentLabel, 'MIRACLE MORNING');
    expect(sc.before, 'avant le matin');
    expect(sc.later, {'routine:lit': 'ce matin'});
    final plan = planSniper(stakes: [kingdom, plain(lit), plain(lou), plain(eau), plain(lec)], budgetMin: 150, routineLeft: {'eau': 8}, scope: sc);
    // L'ordre réglé : Lecture (1), Louanges (2), puis l'eau (sans rang, par nom).
    expect([for (final t in plan.aimed) t.key], ['routine:lec', 'routine:lou', 'routine:eau']);
    expect(plan.aimed.last.delta, 1);
    expect(plan.aimed.last.gains.single.label, 'part du Miracle Morning · 1 sur 8 à faire');
    expect([for (final m in plan.later) m.reason], ['plus tard · ensuite', 'plus tard · ce matin']);
    expect(sc.laterLine(plan.later), '1 ce matin · 1 ensuite');
  });

  test('à 6 h passées : le reste du Miracle Morning d’abord, l’eau à +3, les autres enjeux reviennent', () {
    final sc = sniperScopeOf(dayAt(6, 10));
    expect(sc.ritual, isFalse);
    expect(sc.leftLabel, 'RESTE DU MIRACLE MORNING');
    final plan = planSniper(stakes: [kingdom, plain(lit), plain(lou), plain(eau), plain(lec)], budgetMin: 150, routineLeft: {'eau': 8}, scope: sc);
    expect([for (final t in plan.aimed) t.section], [kSniperSecLeft, kSniperSecLeft, kSniperSecMoment, kSniperSecMoment, kSniperSecOther]);
    final water = plan.aimed.firstWhere((t) => t.key == 'routine:eau');
    expect(water.delta, 3);
    expect(water.gains.single.label, '1 d’avant + 2 ce matin');
    expect(plan.later, isEmpty);
  });

  test('« Plus tard » : au-delà de deux groupes, le premier puis « n ensuite »', () {
    SniperMiss miss(String when) => SniperMiss(sniperTargetOf(kingdom)!, 'plus tard · $when');
    const sc = SniperScope(moment: kMiracleMoment, laterOrder: ['ce matin', 'ce midi', 'ce soir']);
    expect(sc.laterLine([miss('ce soir'), miss('ce matin'), miss('ce midi'), miss('ce soir'), miss('ensuite')]), '1 ce matin · 4 ensuite');
    expect(sc.laterLine([miss('ce soir'), miss('ce matin')]), '1 ce matin · 1 ce soir');
  });
}
