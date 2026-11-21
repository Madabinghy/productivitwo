import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

/// Trace d'une cible gardée dans la session : la reprise retrouve une cible déjà touchée.
void main() {
  final pompes = Activity(id: 'pom', domainId: 'd', name: 'Pompes', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 20);

  test('aller-retour : titre, nature, montants, partie et gains', () {
    final t = SniperTarget(
      Stake(StakeGesture(key: 'routine:pom', kind: StakeGestureKind.routine, title: 'Pompes', costMin: 5, activity: pompes),
          [const StakeGain(kind: StakeGainKind.seriesTonight, label: 'Série de 12 j', weight: 30, losesTonight: true)]),
      SniperKind.routine,
      minutes: 0,
      delta: 10,
      need: 20,
      section: kSniperSecMoment,
    );
    final back = sniperFromSnapshot('routine:pom', sniperSnapshot(t))!;
    expect(back.key, 'routine:pom');
    expect(back.title, 'Pompes');
    expect(back.kind, SniperKind.routine);
    expect(back.delta, 10);
    expect(back.need, 20);
    expect(back.isMini, isTrue);
    expect(back.section, kSniperSecMoment);
    expect(back.gains.single.label, 'Série de 12 j');
    expect(back.losesTonight, isTrue);
  });

  test('cible minutée', () {
    final t = SniperTarget(
      Stake(const StakeGesture(key: 'activity:lec', kind: StakeGestureKind.activity, title: 'Lecture', costMin: 25), const []),
      SniperKind.timed,
      minutes: 25,
    );
    final back = sniperFromSnapshot('activity:lec', sniperSnapshot(t))!;
    expect(back.kind, SniperKind.timed);
    expect(back.minutes, 25);
    expect(back.cost, 25);
    expect(back.isMini, isFalse);
  });

  test('trace illisible : rien', () {
    expect(sniperFromSnapshot('x', null), isNull);
    expect(sniperFromSnapshot('x', {'t': 'A', 'k': 'inconnu'}), isNull);
  });
}
