import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';

AppState _st(List<Session> sessions) => AppState(
      domains: [],
      activities: [],
      sessions: sessions,
      habitProgress: [],
    );

DailySchedule _sched(String date, List<ScheduleBlock> blocks) =>
    DailySchedule(date: date, blocks: blocks);

ScheduleBlock _block({
  required String startTime,
  int durationMin = 30,
  String title = 'Bloc',
  String category = 'personal',
  String status = 'pending',
  String? activityId,
  String? projectId,
  String? taskId,
  DateTime? doneAt,
  String kind = 'normal',
  String? prepForDate,
  String? prepForBlockId,
}) =>
    ScheduleBlock(
      startTime: startTime,
      durationMin: durationMin,
      title: title,
      category: category,
      status: status,
      activityId: activityId,
      projectId: projectId,
      taskId: taskId,
      doneAt: doneAt,
      kind: kind,
      prepForDate: prepForDate,
      prepForBlockId: prepForBlockId,
    );

void main() {
  const today = '2026-07-07';
  const yesterday = '2026-07-06';

  group('computeCoachMoment', () {
    test('nuit (1h–5h) → carte masquée', () {
      final now = DateTime(2026, 7, 7, 3, 0);
      final m = computeCoachMoment(now, _st([]), null, null, []);
      expect(m.hidden, isTrue);
      expect(m.type, CoachMomentType.hidden);
    });

    test('23h25 → toujours la carte du soir (fenêtre étendue)', () {
      final now = DateTime(2026, 7, 7, 23, 25);
      final m = computeCoachMoment(now, _st([]), null, null, []);
      expect(m.type, CoachMomentType.evening);
    });

    test('0h30 → carte du soir, preps lues dans le programme d\'HIER', () {
      final now = DateTime(2026, 7, 8, 0, 30);
      // À 0h30 le doc « du jour » est celui du 08 (vide) ; la prep du soir
      // vit dans le doc du 07.
      final yestSched = _sched(today, [
        _block(
            startTime: '21:45',
            title: 'Préparer le sac',
            kind: 'prep',
            prepForDate: '2026-07-08',
            prepForBlockId: 'x'),
      ]);
      final m = computeCoachMoment(now, _st([]), null, yestSched, []);
      expect(m.type, CoachMomentType.evening);
      expect(m.stats.any((s) => s.label == 'À préparer'), isTrue);
    });

    test('réveil : affiche « prêtes depuis hier » + compte à rebours', () {
      final now = DateTime(2026, 7, 7, 7, 0);
      final todaySched = _sched(today, [
        _block(
            startTime: '07:15',
            title: 'Séance jambes',
            category: 'routine',
            activityId: 'act-sport'),
      ]);
      final yestSched = _sched(yesterday, [
        _block(
            startTime: '21:45',
            title: 'Préparer les affaires',
            status: 'done',
            kind: 'prep',
            prepForDate: today,
            prepForBlockId: 'x'),
      ]);
      final m = computeCoachMoment(now, _st([]), todaySched, yestSched, []);
      expect(m.type, CoachMomentType.wake);
      expect(m.message, contains('prêtes depuis hier'));
      expect(m.message, contains('dans 15 min'));
      expect(m.stats.any((s) => s.value.contains('prêtes depuis hier')), isTrue);
      expect(m.actions.any((a) => a.kind == CoachActionKind.launchBlock), isTrue);
    });

    test('réveil sans prep : pas de mention « prêtes »', () {
      final now = DateTime(2026, 7, 7, 6, 30);
      final todaySched = _sched(today, [
        _block(startTime: '08:00', title: 'Bloc', activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), todaySched, null, []);
      expect(m.type, CoachMomentType.wake);
      expect(m.message, isNot(contains('prêtes depuis hier')));
    });

    test('matin : premier engagement fait → message positif', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final sched = _sched(today, [
        _block(
            startTime: '07:15',
            title: 'Séance jambes',
            category: 'routine',
            status: 'done',
            doneAt: DateTime(2026, 7, 7, 7, 15)),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.morning);
      expect(m.tone, CoachTone.positive);
      expect(m.message, contains('Séance jambes'));
      expect(m.message, contains('7h15'));
    });

    test('matin : rien fait → carte réduite (prochain bloc)', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final sched = _sched(today, [
        _block(startTime: '11:00', title: 'Réunion', activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.morning);
      expect(m.message, contains('Réunion'));
    });

    test('midi : rapport de matinée avec minutes logguées réelles', () {
      final now = DateTime(2026, 7, 7, 12, 30);
      final sched = _sched(today, [
        _block(
            startTime: '08:00',
            title: 'Travail',
            category: 'project',
            status: 'done'),
        _block(
            startTime: '15:00',
            title: 'Formation IA',
            category: 'project',
            projectId: 'p',
            taskId: 't'),
      ]);
      final sessions = [
        Session(
            activityId: 'a',
            startAt: DateTime(2026, 7, 7, 8, 0),
            endAt: DateTime(2026, 7, 7, 9, 30)), // 90 min avant midi
      ];
      final m = computeCoachMoment(now, _st(sessions), sched, null, sessions);
      expect(m.type, CoachMomentType.midday);
      expect(m.stats.any((s) => s.value.contains('1h30')), isTrue);
      expect(m.message, contains('Formation IA'));
    });

    test('dérive : bloc posé > 45 min, 0 min logguée → carte ambre', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [
        _block(
            startTime: '14:00',
            title: 'Formation IA',
            category: 'project',
            projectId: 'p',
            taskId: 't',
            activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.drift);
      expect(m.tone, CoachTone.alert);
      expect(m.message, contains('0 min logguée'));
      expect(m.actions.any((a) => a.kind == CoachActionKind.renegotiate), isTrue);
      expect(m.actions.any((a) => a.kind == CoachActionKind.launchBlock), isTrue);
    });

    test('pas de dérive si du temps a été loggué sur le bloc', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [
        _block(
            startTime: '14:00',
            title: 'Formation IA',
            category: 'project',
            activityId: 'a'),
      ]);
      final sessions = [
        Session(
            activityId: 'a',
            startAt: DateTime(2026, 7, 7, 14, 10),
            endAt: DateTime(2026, 7, 7, 14, 40)),
      ];
      final m = computeCoachMoment(now, _st(sessions), sched, null, sessions);
      // Fenêtre 14-19 sans dérive → moment après-midi léger, pas de dérive.
      expect(m.type, isNot(CoachMomentType.drift));
    });

    test('soir : CTA day review + compte des preps à faire', () {
      final now = DateTime(2026, 7, 7, 20, 0);
      final sched = _sched(today, [
        _block(
            startTime: '21:45',
            title: 'Préparer le sac',
            kind: 'prep',
            prepForDate: '2026-07-08',
            prepForBlockId: 'x'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.evening);
      expect(m.message, contains('Demain se gagne ce soir'));
      expect(
          m.actions.any((a) => a.kind == CoachActionKind.openDayReview), isTrue);
    });

    test('CTA transition : levé à 5h, « Attaquer la journée » → carte matin',
        () {
      final now = DateTime(2026, 7, 7, 5, 30);
      final sched = _sched(today, [
        _block(startTime: '07:15', title: 'Séance', activityId: 'a'),
      ]);
      final wake = computeCoachMoment(now, _st([]), sched, null, []);
      expect(wake.type, CoachMomentType.wake);
      final advance = wake.actions
          .firstWhere((a) => a.kind == CoachActionKind.advanceMoment);
      expect(advance.target, CoachMomentType.morning);

      final m = computeCoachMoment(now, _st([]), sched, null, [],
          advancedTo: CoachMomentType.morning);
      expect(m.type, CoachMomentType.morning);
    });

    test('avance périmée : advancedTo=morning à 12h30 → l\'horloge gagne', () {
      final now = DateTime(2026, 7, 7, 12, 30);
      final m = computeCoachMoment(now, _st([]), null, null, [],
          advancedTo: CoachMomentType.morning);
      expect(m.type, CoachMomentType.midday);
    });

    test('avancer en soirée fait taire une dérive en cours', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [
        _block(
            startTime: '14:00',
            title: 'Formation IA',
            category: 'project',
            projectId: 'p',
            taskId: 't',
            activityId: 'a'),
      ]);
      final drift = computeCoachMoment(now, _st([]), sched, null, []);
      expect(drift.type, CoachMomentType.drift);
      final m = computeCoachMoment(now, _st([]), sched, null, [],
          advancedTo: CoachMomentType.evening);
      expect(m.type, CoachMomentType.evening);
    });

    test('après-midi sans bloc : carte visible avec « Passer en soirée »', () {
      final now = DateTime(2026, 7, 7, 16, 0);
      final m = computeCoachMoment(now, _st([]), null, null, []);
      expect(m.type, CoachMomentType.afternoon);
      expect(
          m.actions.any((a) =>
              a.kind == CoachActionKind.advanceMoment &&
              a.target == CoachMomentType.evening),
          isTrue);
    });

    test('matin sans programme → carte « journée non planifiée » (5a)', () {
      final now = DateTime(2026, 7, 7, 7, 58);
      final m = computeCoachMoment(now, _st([]), null, null, []);
      expect(m.type, CoachMomentType.unplanned);
      expect(m.title, 'Journée non planifiée');
      expect(m.actions.any((a) => a.kind == CoachActionKind.planDay), isTrue);
      expect(m.actions.any((a) => a.kind == CoachActionKind.dismiss), isTrue);
    });

    test('« À la volée » → la carte réveil/matin reprend la main', () {
      final now = DateTime(2026, 7, 7, 7, 58);
      final m = computeCoachMoment(now, _st([]), null, null, [],
          unplannedDismissed: true);
      expect(m.type, CoachMomentType.wake);
    });

    test('un programme (même 1 bloc) suffit → pas de carte non planifiée', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final sched = _sched(today, [
        _block(startTime: '11:00', title: 'Réunion', activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.morning);
    });

    test('des preps seules ne comptent pas comme programme', () {
      final now = DateTime(2026, 7, 7, 8, 0);
      final sched = _sched(today, [
        _block(
            startTime: '21:45',
            title: 'Prep',
            kind: 'prep',
            prepForDate: '2026-07-08',
            prepForBlockId: 'x'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.unplanned);
    });

    test('quick fix : aprem sans bloc → « Planifier l\'après-midi », pas d\'abdication',
        () {
      final now = DateTime(2026, 7, 7, 14, 46);
      final m = computeCoachMoment(now, _st([]), null, null, []);
      expect(m.type, CoachMomentType.afternoon);
      expect(
          m.actions.any((a) =>
              a.kind == CoachActionKind.planDay &&
              a.label.contains('après-midi')),
          isTrue);
      // La transition reste disponible, en secondaire.
      expect(m.actions.any((a) => a.kind == CoachActionKind.advanceMoment),
          isTrue);
    });

    test('vital hebdo : « 1/2 séances · sem. » sur la carte midi (réel)', () {
      final now = DateTime(2026, 7, 8, 12, 30); // mercredi
      final st = AppState(
        domains: [
          Domain(
            id: 'd1',
            name: 'Santé',
            intention: 'Un corps qui suit le rythme',
            definitionStatus: 'active',
            vitalMinimum: [
              VitalMinimum(
                  label: '2 séances / sem',
                  metric: 'sessions_week',
                  target: 2,
                  period: 'week'),
            ],
          ),
        ],
        activities: [
          Activity(id: 'a1', name: 'Sport', domainId: 'd1'),
        ],
        sessions: [
          Session(
              activityId: 'a1',
              startAt: DateTime(2026, 7, 7, 7, 15), // mardi — même semaine
              endAt: DateTime(2026, 7, 7, 7, 45)),
        ],
        habitProgress: [],
      );
      final sched = _sched('2026-07-08', [
        _block(startTime: '09:00', title: 'Bloc', status: 'done'),
      ]);
      final m =
          computeCoachMoment(now, st, sched, null, st.sessions);
      expect(m.type, CoachMomentType.midday);
      expect(
          m.stats.any((s) => s.label == 'Santé' && s.value == '1/2 · sem.'),
          isTrue);
    });

    test('vital omis sans domaine défini (jamais de chiffre inventé)', () {
      final now = DateTime(2026, 7, 8, 12, 30);
      final sched = _sched('2026-07-08', [
        _block(startTime: '09:00', title: 'Bloc', status: 'done'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.stats.any((s) => s.value.contains('sem.')), isFalse);
    });

    test('carte midi menu (15c) : repas du jour + chips ✓ Mangé / Autre chose',
        () {
      final now = DateTime(2026, 7, 8, 12, 30); // mercredi
      final menu = Artifact(
        id: 'menu1',
        kind: 'weekly_menu',
        domainId: 'd1',
        entries: [
          ArtifactEntry(weekday: 'wed', time: '12:30', title: 'Chili sin carne'),
          ArtifactEntry(weekday: 'mon', time: '12:30', title: 'Poulet rôti'),
        ],
        mealLog: {'2026-07-06': 'eaten'}, // lundi de la même semaine
      );
      final sched = _sched('2026-07-08', [
        _block(startTime: '09:00', title: 'Bloc', status: 'done'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, [],
          artifacts: [menu]);
      expect(m.type, CoachMomentType.midday);
      expect(m.message, contains('Chili sin carne au frigo'));
      expect(m.stats.any((s) => s.label == 'Repas cuisinés' && s.value == '1/2'),
          isTrue);
      expect(
          m.actions.any((a) =>
              a.kind == CoachActionKind.mealEaten && a.artifactId == 'menu1'),
          isTrue);
      expect(m.actions.any((a) => a.kind == CoachActionKind.mealShift), isTrue);
    });

    test('repas déjà tranché aujourd\'hui → pas de section repas', () {
      final now = DateTime(2026, 7, 8, 12, 30);
      final menu = Artifact(
        id: 'menu1',
        kind: 'weekly_menu',
        domainId: 'd1',
        entries: [ArtifactEntry(weekday: 'wed', time: '12:30', title: 'Chili')],
        mealLog: {'2026-07-08': 'eaten'},
      );
      final sched = _sched('2026-07-08', [
        _block(startTime: '09:00', title: 'Bloc', status: 'done'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, [],
          artifacts: [menu]);
      expect(m.message, isNot(contains('au frigo')));
      expect(m.actions.any((a) => a.kind == CoachActionKind.mealEaten), isFalse);
    });

    test('shiftMenuOneDay : le futur glisse d\'un jour, le passé ne bouge pas',
        () {
      final menu = Artifact(
        kind: 'weekly_menu',
        domainId: 'd1',
        entries: [
          ArtifactEntry(date: '2026-07-07', time: '12:30', title: 'Passé'),
          ArtifactEntry(date: '2026-07-08', time: '12:30', title: 'Aujourd\'hui'),
          ArtifactEntry(date: '2026-07-09', time: '12:30', title: 'Demain'),
          ArtifactEntry(weekday: 'sun', time: '17:00', title: 'Batch'),
        ],
      );
      shiftMenuOneDay(menu, '2026-07-08');
      expect(menu.entries[0].date, '2026-07-07'); // passé intouché
      expect(menu.entries[1].date, '2026-07-09');
      expect(menu.entries[2].date, '2026-07-10');
      expect(menu.entries[3].weekday, 'sun'); // motif hebdo intouché
    });

    test('dimanche soir + rapport → teaser 16a (chiffres réels)', () {
      final now = DateTime(2026, 7, 12, 20, 0); // dimanche
      final report = WeeklyReport(
        weekStart: '2026-07-06',
        isoWeek: 28,
        held: 11,
        total: 14,
        motifs: [ReportMotif(cause: 'imprevu', count: 3, brokenTotal: 4)],
      );
      final m = computeCoachMoment(now, _st([]), null, null, [],
          weeklyReport: report);
      expect(m.type, CoachMomentType.weekly);
      expect(m.stats.any((s) => s.value == '11/14'), isTrue);
      expect(m.stats.any((s) => s.value == '×3'), isTrue);
      expect(
          m.actions.any((a) => a.kind == CoachActionKind.openWeeklyReport),
          isTrue);
    });

    test('dimanche soir sans rapport → check-in normal', () {
      final now = DateTime(2026, 7, 12, 20, 0);
      final m = computeCoachMoment(now, _st([]), null, null, []);
      expect(m.type, CoachMomentType.evening);
    });

    test('lundi soir avec rapport → check-in normal (le teaser est dominical)',
        () {
      final now = DateTime(2026, 7, 13, 20, 0); // lundi
      final report = WeeklyReport(weekStart: '2026-07-13');
      final m = computeCoachMoment(now, _st([]), null, null, [],
          weeklyReport: report);
      expect(m.type, CoachMomentType.evening);
    });

    test('WeeklyReport : round-trip toJson → from', () {
      final r = WeeklyReport(
        weekStart: '2026-07-06',
        weekEnd: '2026-07-12',
        isoWeek: 28,
        held: 11,
        total: 14,
        checkinsDone: 5,
        domains: [
          ReportDomainFact(domainId: 'd1', name: 'Santé', vitals: [
            ReportVital(label: '2 séances / sem', done: 2, target: 2),
          ]),
        ],
        motifs: [
          ReportMotif(
              cause: 'imprevu',
              count: 3,
              brokenTotal: 4,
              hours: ['14:00', '15:00', '16:00']),
        ],
        narrative: 'Meilleure semaine du mois.',
        question: 'On déplace les relances au matin ?',
        proposedDecision: WeeklyDecision(
            domainId: 'd2',
            domainName: 'Business',
            from: 'relances à 14h',
            to: 'relances à 9h',
            reason: '0/3 à 14h'),
        decisionStatus: 'pending',
      );
      final back = WeeklyReport.from(r.toJson());
      expect(back.held, 11);
      expect(back.total, 14);
      expect(back.isoWeek, 28);
      expect(back.domains.single.vitals.single.done, 2);
      expect(back.motifs.single.hoursLabel, 'toujours entre 14 h et 16 h');
      expect(back.proposedDecision?.to, 'relances à 9h');
      expect(back.decisionStatus, 'pending');
    });

    test('recaleArtifactOneWeek : la semaine se rejoue, le passé ne bouge pas',
        () {
      final plan = Artifact(
        kind: 'training_plan',
        domainId: 'd1',
        entries: [
          ArtifactEntry(date: '2026-07-09', time: '07:15', title: 'S1 passée'),
          ArtifactEntry(date: '2026-07-14', time: '07:15', title: 'S2 mardi'),
          ArtifactEntry(date: '2026-07-16', time: '07:15', title: 'S2 jeudi'),
          ArtifactEntry(weekday: 'sat', time: '09:30', title: 'Motif hebdo'),
        ],
      );
      recaleArtifactOneWeek(plan, '2026-07-13'); // lundi de la semaine à venir
      expect(plan.entries[0].date, '2026-07-09'); // passé intouché
      expect(plan.entries[1].date, '2026-07-21'); // S2 rejouée +7 j
      expect(plan.entries[2].date, '2026-07-23');
      expect(plan.entries[3].weekday, 'sat'); // motif hebdo intouché
    });

    test('WeeklyReport court : parse minutesLogged/renegotiations/secondMinimal',
        () {
      final r = WeeklyReport.from({
        'weekStart': '2026-07-06',
        'kind': 'short',
        'secondMinimal': true,
        'weekModeChosen': null,
        'facts': {
          'engagements': {'held': 2, 'total': 12},
          'checkinsDone': 3,
          'minutesLogged': 3120, // 52 h
          'renegotiations': 1,
          'domains': [],
          'motifs': [],
        },
        'narrative': 'Une semaine comme ça n\'annule rien.',
        'question': null,
      });
      expect(r.kind, 'short');
      expect(r.minutesLogged, 3120);
      expect(r.renegotiations, 1);
      expect(r.secondMinimal, isTrue);
      expect(r.weekModeChosen, isNull);
      // Round-trip conserve les champs courts.
      final back = WeeklyReport.from(r.toJson());
      expect(back.minutesLogged, 3120);
      expect(back.secondMinimal, isTrue);
    });

    test('rétrocompat : programme sans champ kind → moment calculé normalement',
        () {
      final now = DateTime(2026, 7, 7, 10, 0);
      // Bloc construit depuis une map legacy (aucun champ prep).
      final legacy = ScheduleBlock.from({
        'id': 'b1',
        'startTime': '11:00',
        'durationMin': 30,
        'title': 'Legacy',
        'category': 'personal',
        'status': 'pending',
      });
      expect(legacy.kind, 'normal');
      expect(legacy.isPrep, isFalse);
      final m = computeCoachMoment(now, _st([]), _sched(today, [legacy]), null, []);
      expect(m.type, CoachMomentType.morning);
    });
  });
}
