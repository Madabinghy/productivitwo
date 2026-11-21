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
    expect(sc.laterLine(['routine:mar', 'routine:den']), '1 cet après-midi · 1 ce soir');
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
