import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';
import 'package:productivitwo_v1/utils/where_we_go.dart';

AppState _st({
  List<Domain>? domains,
  List<Activity>? activities,
  List<Session>? sessions,
}) =>
    AppState(
      domains: domains ?? [],
      activities: activities ?? [],
      sessions: sessions ?? [],
      habitProgress: [],
    );

ScheduleBlock _block({
  required String startTime,
  int durationMin = 30,
  String title = 'Bloc',
  String status = 'pending',
  String category = 'personal',
  String kind = 'normal',
  String? prepForDate,
}) =>
    ScheduleBlock(
      startTime: startTime,
      durationMin: durationMin,
      title: title,
      status: status,
      category: category,
      kind: kind,
      prepForDate: prepForDate,
    );

void main() {
  final now = DateTime(2026, 7, 9, 15, 14); // jeudi

  group('capDomain — l\'intention rangée n° 1', () {
    test('premier domaine DÉFINI de la liste, avec son rang', () {
      final named = Domain(name: 'Santé', definitionStatus: 'named');
      final defined = Domain(
          name: 'Business',
          definitionStatus: 'active',
          intention: 'Décrocher 2 clients d\'ici fin juillet');
      final cap = capDomain(_st(domains: [named, defined]));
      expect(cap!.domain.name, 'Business');
      expect(cap.rank, 2);
    });

    test('aucun domaine défini → null (la carte le dira)', () {
      expect(capDomain(_st(domains: [Domain(name: 'X')])), isNull);
    });
  });

  group('buildStrategyItems — que des faits', () {
    test('décision APPLIQUÉE du rapport en priorité, avec sa provenance', () {
      final report = WeeklyReport(
        weekStart: '2026-07-06',
        isoWeek: 28,
        narrative: 'x',
        proposedDecision: WeeklyDecision(
            domainName: 'Business',
            to: 'Pitch deck fini vendredi',
            reason: 'le reste attend'),
        decisionStatus: 'applied',
      );
      final items =
          buildStrategyItems(now: now, st: _st(), report: report);
      expect(items.first.key, 'decision');
      expect(items.first.title, 'Pitch deck fini vendredi');
      expect(items.first.sub, contains('S28'));
    });

    test('décision non validée → absente (le user dispose)', () {
      final report = WeeklyReport(
        weekStart: '2026-07-06',
        proposedDecision: WeeklyDecision(to: 'X'),
        decisionStatus: 'pending',
      );
      expect(buildStrategyItems(now: now, st: _st(), report: report),
          isEmpty);
    });

    test('vital compté en direct depuis les sessions réelles', () {
      final d = Domain(
          name: 'Santé',
          definitionStatus: 'active',
          intention: 'un corps qui suit',
          vitalMinimum: [
            VitalMinimum(
                label: '2 séances / sem',
                metric: 'sessions_sport',
                target: 2,
                period: 'week'),
          ]);
      final act = Activity(domainId: d.id, name: 'Sport');
      final monday = DateTime(2026, 7, 6);
      final st = _st(domains: [d], activities: [act], sessions: [
        Session(
            activityId: act.id,
            startAt: monday.add(const Duration(hours: 8)),
            endAt: monday.add(const Duration(hours: 9))),
        // Trop courte (< 10 min) : ne compte pas.
        Session(
            activityId: act.id,
            startAt: monday.add(const Duration(days: 1, hours: 8)),
            endAt: monday.add(const Duration(days: 1, hours: 8, minutes: 5))),
      ]);
      final items = buildStrategyItems(now: now, st: st);
      expect(items.single.key, 'vital:${d.id}');
      expect(items.single.title, 'Vital Santé : 2 séances / sem');
      expect(items.single.sub, '1 / 2 · sem.');
    });

    test('Gantt en bonus, jamais du dû', () {
      const g = GanttMicroAction(
          projectId: 'p',
          projectTitle: 'Formation',
          taskId: 't',
          taskTitle: 'Relances prospects');
      final items = buildStrategyItems(now: now, st: _st(), gantt: g);
      expect(items.single.key, 'gantt');
      expect(items.single.sub, 'du bonus, pas du dû');
    });
  });

  group('applyStrategyOrder — l\'ordre du user survit', () {
    const a = StrategyItem(key: 'decision', title: 'A');
    const b = StrategyItem(key: 'vital:1', title: 'B');
    const c = StrategyItem(key: 'gantt', title: 'C');

    test('réordonne selon les clés stockées', () {
      final out = applyStrategyOrder([a, b, c], ['gantt', 'decision']);
      expect(out.map((i) => i.key).toList(),
          ['gantt', 'decision', 'vital:1']);
    });

    test('clé disparue des faits : ignorée — rien n\'est ressuscité', () {
      final out = applyStrategyOrder([a, c], ['vital:1', 'gantt']);
      expect(out.map((i) => i.key).toList(), ['gantt', 'decision']);
    });

    test('ordre vide → ordre des faits', () {
      expect(applyStrategyOrder([a, b], []), [a, b]);
    });
  });

  group('tactique — dérivée du programme, jamais inventée', () {
    test('AUJ. : les engagements pending, 3 max, heure en clair', () {
      final line = tactiqueTodayLine(now, [
        _block(startTime: '16:00', title: 'Formation IA'),
        _block(startTime: '14:00', title: 'Relances'),
        _block(startTime: '12:30', title: 'Pause', category: 'break'),
        _block(startTime: '09:00', title: 'Fait', status: 'done'),
      ]);
      expect(line, '14 h Relances · 16 h Formation IA');
    });

    test('AUJ. vide : la ligne le dit sans inventer', () {
      expect(tactiqueTodayLine(now, const []), contains('rien de posé'));
    });

    test('DEMAIN : programme posé + prep de ce soir', () {
      final line = tactiqueTomorrowLine(
        now: now,
        tomorrowBlocks: [_block(startTime: '07:15', title: 'Séance')],
        todayBlocks: [
          _block(
              startTime: '21:45',
              title: 'Préparer les affaires',
              kind: 'prep',
              prepForDate: '2026-07-10'),
        ],
      );
      expect(line, '7 h 15 Séance · prep ce soir 21 h 45');
    });

    test('DEMAIN sans programme : les artefacts font foi', () {
      final plan = Artifact(
        kind: 'training_plan',
        domainId: 'd1',
        entries: [
          ArtifactEntry(date: '2026-07-10', time: '07:15', title: 'Haut du corps', durationMin: 45),
        ],
      );
      final line = tactiqueTomorrowLine(now: now, artifacts: [plan]);
      expect(line, '7 h 15 Haut du corps (plan)');
    });

    test('DEMAIN : rien nulle part → null (ligne omise)', () {
      expect(tactiqueTomorrowLine(now: now), isNull);
    });
  });

  group('strategyOrder — persistance sur le rapport', () {
    test('aller-retour JSON', () {
      final r = WeeklyReport(
          weekStart: '2026-07-06', strategyOrder: ['gantt', 'decision']);
      final back = WeeklyReport.from(r.toJson());
      expect(back.strategyOrder, ['gantt', 'decision']);
      // Doc serveur sans le champ : liste vide, rétrocompatible.
      expect(WeeklyReport.from({'weekStart': '2026-07-06'}).strategyOrder,
          isEmpty);
    });
  });
}
