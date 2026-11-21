import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/sniper_container.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

void main() {
  final kingdom = Activity(id: 'kin', domainId: 'd', name: 'Kingdom', goalMin: 30);
  final lecture = Activity(id: 'lec', domainId: 'd', name: 'Lecture', goalMin: 30);
  final d0 = DateTime(2026, 11, 21);

  Stake timed(Activity a, int min) => Stake(
        StakeGesture(key: 'activity:${a.id}', kind: StakeGestureKind.activity, title: a.name, costMin: min, activity: a),
        [const StakeGain(kind: StakeGainKind.halfDay, label: 'Montre suisse', weight: 10)],
      );
  Stake own(Activity owner, String id, int est, {String label = 'Visée aujourd’hui', StakeGainKind k = StakeGainKind.focus}) => Stake(
        StakeGesture(
            key: 'action:$id', kind: StakeGestureKind.action, title: id, costMin: est, action: TaskAction(id: id, title: id, estimatedMin: est), owner: owner),
        [StakeGain(kind: k, label: label, weight: 20)],
      );
  SniperStep step(String id, int min, {String? reason}) => SniperStep(
        StakeGesture(key: 'action:$id', kind: StakeGestureKind.action, title: id, costMin: min, action: TaskAction(id: id, title: id, estimatedMin: min), owner: kingdom),
        minutes: min,
        reason: reason,
      );

  test('une action dont le chrono tourne sur une activité visée entre dans sa cible : le temps n’est plus compté deux fois', () {
    final plan = planSniper(stakes: [timed(kingdom, 37), own(kingdom, 'Écrire la page', 15), own(kingdom, 'Répondre au devis', 10, label: 'Parole tenue · encore 1')], budgetMin: 70);
    expect(plan.aimed, hasLength(1));
    final t = plan.aimed.single;
    expect(t.title, 'Kingdom');
    expect(t.minutes, 37);
    expect([for (final x in t.steps) x.title], containsAll(['Écrire la page', 'Répondre au devis']));
    expect(t.freeMin, 12);
    expect(t.steps.firstWhere((x) => x.title == 'Répondre au devis').reason, 'promise hier');
    expect(t.steps.firstWhere((x) => x.title == 'Écrire la page').reason, 'visée aujourd’hui');
    // Les gains des actions passent sur la cible.
    expect(t.gains.map((g) => g.label), contains('Parole tenue · encore 1'));
  });

  test('une action d’une autre activité reste une cible à part', () {
    final plan = planSniper(stakes: [timed(kingdom, 37), own(lecture, 'Lire un chapitre', 15)], budgetMin: 70);
    expect(plan.aimed.map((t) => t.title), containsAll(['Kingdom', 'Lire un chapitre']));
    expect(plan.aimed.firstWhere((t) => t.title == 'Kingdom').isContainer, isFalse);
  });

  test('des actions plus longues que le manque allongent le tir', () {
    final plan = planSniper(stakes: [timed(kingdom, 20), own(kingdom, 'a', 15), own(kingdom, 'b', 15)], budgetMin: 70);
    expect(plan.aimed.single.minutes, 30);
    expect(plan.aimed.single.freeMin, 0);
  });

  test('la file complète tant que le temps de l’activité n’est pas rempli, sans doublon', () {
    final plan = planSniper(
      stakes: [timed(kingdom, 37), own(kingdom, 'Écrire la page', 15)],
      budgetMin: 70,
      fill: {
        'kin': [step('Écrire la page', 15), step('Relancer Martin', 5, reason: 'en retard'), step('Bilan du mois', 30), step('Trier', 10)],
      },
    );
    final t = plan.aimed.single;
    expect([for (final x in t.steps) x.title], ['Écrire la page', 'Relancer Martin', 'Trier']);
    expect(t.freeMin, 7);
  });

  test('choisir les actions à la main : le tir dure le manque, ou plus si les actions le demandent', () {
    final t = planSniper(stakes: [timed(kingdom, 37)], budgetMin: 70).aimed.single;
    expect(t.isContainer, isFalse);
    final two = t.withSteps([step('a', 10), step('b', 15)]);
    expect(two.minutes, 37);
    expect(two.freeMin, 12);
    final big = t.withSteps([step('a', 30), step('b', 20)]);
    expect(big.minutes, 50);
    expect(big.isMini, isFalse);
    expect(big.withAmount(40).steps, hasLength(2));
  });

  test('la file d’une activité : visées aujourd’hui d’abord, puis la prochaine action de chaque projet lié', () {
    final today = d0;
    final p = Project(id: 'p', title: 'Site vitrine', startDate: d0, createdBy: 'u', linkedActivityId: 'kin', tasks: [
      ProjectTask(id: 't', title: 'Écrire', startDate: d0, actions: [TaskAction(id: 'x1', title: 'Rédiger l’accueil', estimatedMin: 15)]),
    ]);
    final a = Activity(id: 'kin', domainId: 'd', name: 'Kingdom', goalMin: 30, ownActions: [TaskAction(id: 'o1', title: 'Ranger le bureau', estimatedMin: 10)]);
    final fill = containerFill(a, [p], today);
    expect([for (final x in fill) x.title], ['Rédiger l’accueil', 'Ranger le bureau']);
    expect(fill.first.reason, 'prochaine action · Site vitrine');
    final pool = activityStepPool(a, [p], today);
    expect(pool.map((x) => x.title), ['Rédiger l’accueil', 'Ranger le bureau']);
  });
}
