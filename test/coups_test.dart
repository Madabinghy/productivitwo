import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coups.dart';
import 'package:productivitwo_v1/utils/project_moment.dart';
import 'package:productivitwo_v1/utils/week_stats.dart';

void main() {
  final today = DateTime(2026, 10, 27, 15);

  test('jours restants fin incluse, libellés', () {
    final o = StrategicObjective(title: 'Coup', horizon: 'tactical', endDate: DateTime(2026, 10, 30));
    expect(coupDaysLeft(o, today), 4);
    expect(coupLabel(o, today), 'jusqu\'au 30 oct. · 4 j');
    expect(coupLabel(StrategicObjective(title: 'x', horizon: 'tactical', endDate: DateTime(2026, 10, 27)), today), 'dernier jour');
    expect(coupLabel(StrategicObjective(title: 'x', horizon: 'tactical', endDate: DateTime(2026, 10, 20)), today), 'terminé');
    expect(coupRestUntil(o), '2026-10-30');
  });

  test('validation : titre, 3 à 10 jours fin incluse, une source', () {
    String? v(String t, DateTime? end, {bool src = true}) => validateCoup(title: t, endDate: end, today: today, hasSource: src);
    expect(v('', DateTime(2026, 10, 30)), isNotNull);
    expect(v('Coup', null), isNotNull);
    expect(v('Coup', DateTime(2026, 10, 28)), contains('au moins 3'));
    expect(v('Coup', DateTime(2026, 10, 29)), isNull); // 3 jours : 27, 28, 29
    expect(v('Coup', DateTime(2026, 11, 5)), isNull); // 10 jours
    expect(v('Coup', DateTime(2026, 11, 6)), contains('au plus 10'));
    expect(v('Coup', DateTime(2026, 10, 30), src: false), contains('Rattache'));
  });

  test('projets des coups en cours ; expirés et stratégiques ignorés ; domaine du coup', () {
    final coup = StrategicObjective(title: 'C', horizon: 'tactical', endDate: DateTime(2026, 10, 30), projectIds: ['livre']);
    final old = StrategicObjective(title: 'O', horizon: 'tactical', endDate: DateTime(2026, 10, 20), projectIds: ['vieux']);
    final strat = StrategicObjective(title: 'S', projectIds: ['strat']);
    expect(coupProjectIds([coup, old, strat], today), {'livre'});
    final p = Project(id: 'livre', title: 'Livre', startDate: DateTime(2026, 9, 1), createdBy: 'u', domainId: 'd-travail');
    expect(coupDomainIds(coup, [p], const []), {'d-travail'});
  });

  test('rankProjectMoments : le projet prioritaire (coup) passe devant une séance proche', () {
    ProjectTask task(String id) => ProjectTask(id: id, title: id, startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 11, 30), actions: [TaskAction(title: 'a')]);
    final a = Project(id: 'a', title: 'A', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [task('t1')], interventions: [
      ProjectIntervention(id: 'i', date: DateTime(2026, 10, 29), title: 'Séance', startTime: '09:00', endTime: '10:00'),
    ]);
    final b = Project(id: 'b', title: 'B', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [task('t2')]);
    expect(rankProjectMoments([a, b], const [], today).first.project.id, 'a');
    expect(rankProjectMoments([a, b], const [], today, priorityIds: {'b'}).first.project.id, 'b');
  });

  test('domainWeeks : un domaine en veille perd son minimum, passe en dernier, garde la date de fin', () {
    final sante = Domain(id: 's', name: 'Santé', autoGoal: false, goalMinDay: 30);
    final maison = Domain(id: 'm', name: 'Maison', autoGoal: false, goalMinDay: 20);
    final rows = domainWeeks(domains: [sante, maison], activities: const [], sessions: const [], hits: const [], now: DateTime(2026, 10, 28, 12), rest: {'s': '2026-10-30'});
    expect(rows.map((r) => r.domain.id).toList(), ['m', 's']);
    final s = rows.last;
    expect((s.resting, s.hasGoal, s.restUntil), (true, false, '2026-10-30'));
    final expired = domainWeeks(domains: [sante], activities: const [], sessions: const [], hits: const [], now: DateTime(2026, 11, 2, 12), rest: {'s': '2026-10-30'});
    expect(expired.single.resting, isFalse);
    expect(expired.single.hasGoal, isTrue);
  });
}
