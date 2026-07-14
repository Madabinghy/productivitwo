import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';

// Un domaine ACTIF par défaut : le nudge domaines (Partie D) ne se déclenche
// que s'il existe un domaine absent ou seulement nommé — les moments horaires
// se testent donc avec une fiche définie.
AppState _st(List<Session> sessions) => AppState(
      domains: [
        Domain(
            name: 'Santé',
            definitionStatus: 'active',
            intention: 'tenir le rythme'),
      ],
      activities: [],
      sessions: sessions,
      habitProgress: [],
    );

AppState _stDomains(List<Domain> domains) => AppState(
      domains: domains,
      activities: [],
      sessions: [],
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
    test('21a — aucun domaine nommé ni défini → nudge prioritaire', () {
      final now = DateTime(2026, 7, 7, 18, 12);
      // Même avec un programme en place, l'invite prime sur l'horaire.
      final sched = _sched(today, [_block(startTime: '15:00')]);
      final m = computeCoachMoment(now, _stDomains([]), sched, null, []);
      expect(m.type, CoachMomentType.defineNudge);
      expect(m.actions.first.kind, CoachActionKind.nameDomains);
      expect(m.actions[1].kind, CoachActionKind.nameTonight);
    });

    test('21a — les domaines legacy (none) comptent comme absents', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final m = computeCoachMoment(
          now, _stDomains([Domain(name: 'Vieux domaine')]), null, null, []);
      expect(m.type, CoachMomentType.defineNudge);
      expect(m.actions.first.kind, CoachActionKind.nameDomains);
    });

    test('22c — nommés, rien de posé → « Définir le rang 1 » + chips', () {
      final now = DateTime(2026, 7, 7, 18, 15);
      final st = _stDomains([
        Domain(name: 'Santé', definitionStatus: 'named'),
        Domain(name: 'Business', definitionStatus: 'named'),
      ]);
      final m = computeCoachMoment(now, st, null, null, []);
      expect(m.type, CoachMomentType.defineNudge);
      expect(m.actions.first.kind, CoachActionKind.startSession);
      expect(m.actions.first.domain, 'Santé'); // rang 1 = ordre de nommage
      expect(m.actions[1].kind, CoachActionKind.poseSessions);
      expect(m.chips, hasLength(2));
    });

    test('21b — session posée → « Garder [créneau] », défini ✓ en chip', () {
      final now = DateTime(2026, 7, 7, 19, 40);
      final st = _stDomains([
        Domain(
            name: 'Santé', definitionStatus: 'active', intention: 'rythme'),
        Domain(name: 'Business', definitionStatus: 'named'),
      ]);
      final m = computeCoachMoment(now, st, null, null, [],
          nextSessionLabel: 'demain 18 h 30');
      expect(m.type, CoachMomentType.defineNudge);
      expect(m.message, contains('Business'));
      expect(m.message, contains('demain 18 h 30'));
      expect(m.actions[1].kind, CoachActionKind.dismiss);
      expect(m.actions[1].label, 'Garder demain 18 h 30');
      expect(m.chips.where((c) => c.done), hasLength(1));
    });

    test('21c — ≥ 2 reports → escalade factuelle, version courte', () {
      final now = DateTime(2026, 7, 13, 12, 35);
      final st = _stDomains([
        Domain(
            name: 'Business',
            definitionStatus: 'named',
            namedAt: DateTime(2026, 7, 9)),
      ]);
      final m =
          computeCoachMoment(now, st, null, null, [], sessionSkipCount: 2);
      expect(m.type, CoachMomentType.defineNudge);
      expect(m.tone, CoachTone.alert);
      expect(m.actions.first.kind, CoachActionKind.startSessionShort);
      expect(m.stats.any((s) => s.value == '4 j'), isTrue); // nommé depuis
      expect(m.stats.any((s) => s.value == '2'), isTrue); // sessions sautées
    });

    test('nudge écarté (« Garder ») → les moments horaires reprennent', () {
      final now = DateTime(2026, 7, 7, 19, 40);
      final st = _stDomains([
        Domain(name: 'Business', definitionStatus: 'named'),
      ]);
      final m =
          computeCoachMoment(now, st, null, null, [], nudgeDismissed: true);
      expect(m.type, CoachMomentType.evening);
    });

    test('tout est défini ou en session → pas de nudge', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final st = _stDomains([
        Domain(name: 'Santé', definitionStatus: 'active', intention: 'x'),
        Domain(name: 'Business', definitionStatus: 'draft'),
      ]);
      final sched = _sched(today, [_block(startTime: '09:00')]);
      final m = computeCoachMoment(now, st, sched, null, []);
      expect(m.type, isNot(CoachMomentType.defineNudge));
    });

    test('dimanche soir : le rapport hebdo garde la main sur le nudge', () {
      final now = DateTime(2026, 7, 12, 20, 0); // dimanche
      final st = _stDomains([
        Domain(name: 'Business', definitionStatus: 'named'),
      ]);
      final report = WeeklyReport(weekStart: '2026-07-06');
      final m = computeCoachMoment(now, st, null, null, [],
          weeklyReport: report);
      expect(m.type, CoachMomentType.weekly);
    });

    test('mode soirée (23c) : carte « journée pliée tôt » avant 19 h', () {
      final now = DateTime(2026, 7, 7, 15, 7);
      final sched = DailySchedule(
        date: today,
        dayMode: 'evening',
        dayModeActivatedAt: DateTime(2026, 7, 7, 15, 7),
        blocks: [
          _block(startTime: '14:00', title: 'Relancer 3 prospects'),
          _block(startTime: '19:30', title: 'Dîner du menu'),
        ],
      );
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.evening);
      expect(m.tagLabel, contains('JOURNÉE PLIÉE TÔT'));
      expect(m.message, contains('assumé'));
      expect(m.message, contains('Relancer 3 prospects'));
      expect(m.message, contains('on les recase au check-in'));
      expect(m.message, contains('Ce soir tient en 1 chose'));
    });

    test('mode soirée : après 19 h la soirée normale reprend', () {
      final now = DateTime(2026, 7, 7, 20, 0);
      final sched = DailySchedule(date: today, dayMode: 'evening');
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.evening);
      expect(m.tagLabel, isNot(contains('PLIÉE')));
    });

    test('après-midi : la bascule est explicite (endAfternoon, plus jamais « Passer en soirée »)',
        () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [_block(startTime: '16:00')]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.afternoon);
      expect(m.actions.any((a) => a.kind == CoachActionKind.endAfternoon),
          isTrue);
      expect(m.actions.any((a) => a.label == 'Passer en soirée'), isFalse);
    });

    test('prochain bloc lointain → « dans 3 h 58 », jamais « 238 min »', () {
      final now = DateTime(2026, 7, 11, 17, 2);
      final sched = _sched(today, [
        _block(startTime: '21:00', title: 'Payer l\'eau'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.afternoon);
      expect(m.message, contains('dans 3 h 58'));
      expect(m.message, isNot(contains('min')));
    });

    test('pause active → AUCUNE carte (le guide prend la place), pas de dérive',
        () {
      final now = DateTime(2026, 7, 11, 15, 0);
      final sched = DailySchedule(
        date: today,
        unavailableUntil: DateTime(2026, 7, 11, 18, 0),
        unavailableReason: 'pas_sur_place',
        blocks: [
          // Bloc en dérive flagrante (posé 14h, 0 min logguée) : silencieux.
          _block(startTime: '14:00', title: 'Relances', activityId: 'a'),
        ],
      );
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      // « Je suis le flow » = zéro relance : ni carte calme, ni nudge, ni
      // dérive — le guide « que souhaites-tu faire ? » occupe l'écran, et
      // l'état/la sortie de pause vivent sur le bouton ⏸ de l'en-tête.
      expect(m.hidden, isTrue);
    });

    test('pause : même le nudge domaines se tait', () {
      final now = DateTime(2026, 7, 11, 15, 0);
      final st = _stDomains([
        Domain(name: 'Business', definitionStatus: 'named'),
      ]);
      final sched = DailySchedule(
        date: today,
        unavailableUntil: DateTime(2026, 7, 11, 18, 0),
      );
      final m = computeCoachMoment(now, st, sched, null, []);
      expect(m.hidden, isTrue);
    });

    test('pause : le check-in du soir attend AUSSI la fin de la fenêtre', () {
      final now = DateTime(2026, 7, 11, 20, 0);
      final sched = DailySchedule(
        date: today,
        unavailableUntil: DateTime(2026, 7, 11, 22, 0),
      );
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      // La pause prime sur tout — le check-in reprend à 22 h, pas avant.
      expect(m.hidden, isTrue);
      // Fenêtre finie → check-in normal.
      final after = computeCoachMoment(
          DateTime(2026, 7, 11, 22, 5), _st([]), sched, null, []);
      expect(after.type, CoachMomentType.evening);
    });

    test('pause « pas aujourd\'hui » posée hier : silence aussi à minuit', () {
      final now = DateTime(2026, 7, 8, 0, 30);
      final yest = DailySchedule(
        date: today,
        unavailableUntil: DateTime(2026, 7, 8, 5, 0),
      );
      final m = computeCoachMoment(now, _st([]), null, yest, []);
      expect(m.hidden, isTrue);
    });

    test('fenêtre expirée → le flow normal reprend', () {
      final now = DateTime(2026, 7, 11, 15, 0);
      final sched = DailySchedule(
        date: today,
        unavailableUntil: DateTime(2026, 7, 11, 14, 0),
        blocks: [_block(startTime: '16:00')],
      );
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.afternoon);
      expect(m.tagLabel, isNot(contains('FLOW')));
    });

    test('dérive : le CTA s\'aligne sur la durée réelle du bloc (1 min)', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [
        _block(
            startTime: '05:30',
            durationMin: 1,
            title: 'Vitamines',
            activityId: 'r1'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.drift);
      // Plus jamais « 25 min » pour un bloc d'une minute.
      expect(m.message, contains('1 minute suffit'));
      expect(m.actions.first.label, 'Lancer 1 min');
    });

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

    test('après-midi sans bloc : carte visible avec la bascule mode soirée',
        () {
      final now = DateTime(2026, 7, 7, 16, 0);
      final m = computeCoachMoment(now, _st([]), null, null, []);
      expect(m.type, CoachMomentType.afternoon);
      expect(m.actions.any((a) => a.kind == CoachActionKind.endAfternoon),
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
      // La bascule système reste disponible, en secondaire — explicite (23c).
      expect(m.actions.any((a) => a.kind == CoachActionKind.endAfternoon),
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

    test('vital TEMPS (heures) : mesuré depuis les sessions logguées', () {
      final now = DateTime(2026, 7, 8, 12, 30); // mercredi
      final st = AppState(
        domains: [
          Domain(
            id: 'd1',
            name: 'Sommeil',
            definitionStatus: 'active',
            intention: 'me sentir en forme',
            vitalMinimum: [
              VitalMinimum(
                  label: '7 h / nuit',
                  metric: 'hours_day',
                  target: 7,
                  period: 'day'),
            ],
          ),
        ],
        activities: [
          Activity(id: 'a1', name: 'Sommeil', domainId: 'd1'),
        ],
        sessions: [
          Session(
              activityId: 'a1',
              startAt: DateTime(2026, 7, 7, 23, 0), // mardi soir, même semaine
              endAt: DateTime(2026, 7, 8, 6, 30)), // 7 h 30 dormies
        ],
        habitProgress: [],
      );
      final sched = _sched('2026-07-08', [
        _block(startTime: '09:00', title: 'Bloc', status: 'done'),
      ]);
      final m = computeCoachMoment(now, st, sched, null, st.sessions);
      expect(m.type, CoachMomentType.midday);
      // Cible journalière ramenée à la semaine (7 h × 7 = 49 h), réel mesuré.
      expect(
          m.stats.any((s) => s.label == 'Sommeil' && s.value == '7,5/49 h · sem.'),
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

    test('point fait (reviewedAt) → carte du soir clôturée, pas de re-proposition',
        () {
      final now = DateTime(2026, 7, 7, 21, 30);
      final sched = DailySchedule(
        date: today,
        reviewedAt: DateTime(2026, 7, 7, 21, 10),
      );
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.evening);
      expect(m.tagLabel, contains('JOURNÉE CLÔTURÉE'));
      expect(m.message, isNot(contains('Prends deux minutes')));
      expect(m.tone, CoachTone.positive);
      // « Revoir le point » reste accessible, sans insister.
      expect(m.actions.single.kind, CoachActionKind.openDayReview);
      expect(m.actions.single.label, 'Revoir le point');
      // Round-trip : le fait survit à la sérialisation.
      expect(DailySchedule.from(sched.toJson()).reviewedAt, isNotNull);
    });

    test('point non fait → check-in normal (inchangé)', () {
      final now = DateTime(2026, 7, 7, 21, 30);
      final m = computeCoachMoment(
          now, _st([]), DailySchedule(date: today), null, []);
      expect(m.type, CoachMomentType.evening);
      expect(m.message, contains('clôturer ta journée'));
    });

    test('rapport LU (fait readAt) → le teaser se tait, check-in normal', () {
      final now = DateTime(2026, 7, 12, 20, 0); // dimanche
      final report = WeeklyReport(
        weekStart: '2026-07-06',
        readAt: DateTime(2026, 7, 12, 17, 30), // lu en fin d'aprem
      );
      final m = computeCoachMoment(now, _st([]), null, null, [],
          weeklyReport: report);
      // Le rapport n'est pas la dernière chose de la journée : une fois lu,
      // la carte reprend son cours (check-in, propositions).
      expect(m.type, CoachMomentType.evening);
      expect(
          m.actions.any((a) => a.kind == CoachActionKind.openWeeklyReport),
          isFalse);
      // Round-trip : le fait survit à la sérialisation.
      final back = WeeklyReport.from(report.toJson());
      expect(back.readAt, isNotNull);
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

  group('heure habituelle + combleur de trous', () {
    List<HabitHit> hitsAt(String id, DateTime now,
            List<({int daysAgo, int h, int m})> specs) =>
        [
          for (final s in specs)
            HabitHit(
                habitId: id,
                ts: DateTime(
                    now.year, now.month, now.day - s.daysAgo, s.h, s.m)),
        ];

    AppState stRoutines(List<HabitHit> hits) => AppState(
          domains: [
            Domain(
                name: 'Santé',
                definitionStatus: 'active',
                intention: 'tenir le rythme'),
          ],
          activities: [
            Activity(
                id: 'r1',
                name: 'Méditation',
                domainId: 'd1',
                type: 'habit',
                habitFreq: HabitFreq.daily,
                timerMin: 10,
                order: 0),
            Activity(
                id: 'r2',
                name: 'Marche',
                domainId: 'd1',
                type: 'habit',
                habitFreq: HabitFreq.daily,
                timerMin: 30,
                order: 1),
          ],
          sessions: [],
          habitProgress: [],
          habitHits: hits,
        );

    test('typicalMinuteOf : médiane des hits réels', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final hits = hitsAt('r1', now, [
        (daysAgo: 1, h: 9, m: 0),
        (daysAgo: 2, h: 9, m: 25),
        (daysAgo: 3, h: 10, m: 0),
      ]);
      expect(typicalMinuteOf('r1', hits, now), 9 * 60 + 25);
    });

    test('typicalMinuteOf : moins de 3 hits → null (jamais inventé)', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final hits = hitsAt('r1', now, [
        (daysAgo: 1, h: 9, m: 0),
        (daysAgo: 2, h: 9, m: 30),
      ]);
      expect(typicalMinuteOf('r1', hits, now), isNull);
      // Les hits d'une AUTRE routine ne comptent pas.
      final other = hitsAt('r2', now,
          [for (var i = 1; i <= 5; i++) (daysAgo: i, h: 9, m: 0)]);
      expect(typicalMinuteOf('r1', [...hits, ...other], now), isNull);
    });

    test('typicalMinuteOf : hits nocturnes = fin de la journée vécue', () {
      final now = DateTime(2026, 7, 7, 22, 0);
      final hits = hitsAt('r1', now, [
        (daysAgo: 1, h: 23, m: 50),
        (daysAgo: 2, h: 0, m: 10), // 0h10 = fin de la veille, pas 0h du matin
        (daysAgo: 3, h: 23, m: 30),
      ]);
      expect(typicalMinuteOf('r1', hits, now), 23 * 60 + 50);
    });

    test('gapFillers : faite aujourd\'hui / trop longue / déjà posée = écartées',
        () {
      final now = DateTime(2026, 7, 7, 9, 30);
      // Méditation (10 min) faite ce matin → seule Marche (30 min) reste.
      final done = hitsAt('r1', now, [(daysAgo: 0, h: 8, m: 0)]);
      var fillers = gapFillers(now, stRoutines(done), 120);
      expect(fillers.map((f) => f.routine.id), ['r2']);
      // Trou de 30 min : Marche (30 + 10 de marge) ne tient plus.
      fillers = gapFillers(now, stRoutines(done), 30);
      expect(fillers, isEmpty);
      // Marche déjà posée en bloc pending → le programme la porte déjà.
      fillers = gapFillers(now, stRoutines(done), 120, blocks: [
        _block(startTime: '17:00', title: 'Marche', activityId: 'r2'),
      ]);
      expect(fillers, isEmpty);
    });

    test('gapFillers : l\'heure habituelle proche prime sur l\'ordre user', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      // Marche (ordre 1) a une heure habituelle ≈ maintenant → passe devant.
      final hits = hitsAt('r2', now,
          [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 9, m: 40)]);
      final fillers = gapFillers(now, stRoutines(hits), 120);
      expect(fillers.map((f) => f.routine.id), ['r2', 'r1']);
      expect(fillers.first.usualTime, isTrue);
      expect(fillers.first.typicalMinute, 9 * 60 + 40);
      // Méditation sans historique : proposée quand même, sans fait inventé.
      expect(fillers[1].typicalMinute, isNull);
      expect(fillers[1].usualTime, isFalse);
    });

    test('gapFillers : jamais faite autour de cette heure (> 4 h) = écartée',
        () {
      final now = DateTime(2026, 7, 7, 9, 30);
      // Marche toujours faite à 21 h → pas proposée à 9 h 30.
      final hits = hitsAt('r2', now,
          [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 21, m: 0)]);
      final fillers = gapFillers(now, stRoutines(hits), 120);
      expect(fillers.map((f) => f.routine.id), ['r1']);
    });

    test('sans historique, le méta-contexte tranche : pas d\'« Hygiène du '
        'soir » en combleur du matin', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final st = AppState(
        domains: [
          Domain(
              name: 'Santé',
              definitionStatus: 'active',
              intention: 'tenir le rythme'),
        ],
        activities: [
          Activity(
              id: 'r1',
              name: 'Hygiène du soir',
              domainId: 'd1',
              type: 'habit',
              habitFreq: HabitFreq.daily,
              timerMin: 5,
              order: 0),
        ],
        sessions: [],
        habitProgress: [],
      );
      expect(gapFillers(now, st, 120), isEmpty); // fenêtre soir ≠ 9 h 30
      // Le soir, elle redevient un combleur légitime.
      final evening = DateTime(2026, 7, 7, 20, 0);
      expect(gapFillers(evening, st, 120).map((f) => f.routine.id), ['r1']);
      // L'heure MESURÉE bat le catalogue : tenue le matin 3 fois → proposée.
      st.habitHits.addAll([
        for (var i = 1; i <= 3; i++)
          HabitHit(
              habitId: 'r1', ts: DateTime(2026, 7, 7 - i, 9, 40)),
      ]);
      expect(gapFillers(now, st, 120).map((f) => f.routine.id), ['r1']);
    });

    test('routine sans minuteur : pas de durée inventée — coche directe (✓)',
        () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final st = AppState(
        domains: [
          Domain(
              name: 'Santé',
              definitionStatus: 'active',
              intention: 'tenir le rythme'),
        ],
        activities: [
          // « Boire de l'eau » : routine à cocher, aucun minuteur.
          Activity(
              id: 'r1',
              name: 'Boire de l\'eau',
              domainId: 'd1',
              type: 'habit',
              habitFreq: HabitFreq.daily,
              order: 0),
        ],
        sessions: [],
        habitProgress: [],
        habitHits: [
          for (var i = 1; i <= 7; i++)
            HabitHit(
                habitId: 'r1', ts: DateTime(2026, 7, 7 - i, 9, 30)),
        ],
      );
      final sched = _sched(today, [_block(startTime: '12:30', title: 'Réunion')]);
      final m = computeCoachMoment(now, st, sched, null, []);
      // Aucun « 20 min » inventé, et la phrase se termine sur le « ? » du streak.
      expect(m.message, contains('D\'ici là : Boire de l\'eau — '));
      expect(m.message, isNot(contains('20 min')));
      expect(m.message, contains('7 jours d\'affilée, on continue ?'));
      expect(m.message, isNot(contains('?.')));
      // Le CTA est une coche, pas un chrono.
      final check = m.actions
          .where((a) => a.kind == CoachActionKind.checkRoutine)
          .toList();
      expect(check, hasLength(1));
      expect(check.first.label, '✓ Boire de l\'eau');
      expect(check.first.block?.activityId, 'r1');
      expect(
          m.actions.any((a) =>
              a.kind == CoachActionKind.launchBlock &&
              a.block?.activityId == 'r1'),
          isFalse);
    });

    test('carte matin : prochain bloc loin → « D\'ici là » + heure habituelle',
        () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final hits = hitsAt('r1', now,
          [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 9, m: 25)]);
      final sched = _sched(today, [
        _block(startTime: '12:30', title: 'Réunion'),
      ]);
      final m = computeCoachMoment(now, stRoutines(hits), sched, null, []);
      expect(m.type, CoachMomentType.morning);
      expect(m.message, contains('D\'ici là : Méditation, 10 min'));
      expect(m.message, contains('heure habituelle (vers 9h25)'));
      final launch = m.actions
          .where((a) =>
              a.kind == CoachActionKind.launchBlock &&
              a.block?.activityId == 'r1')
          .toList();
      expect(launch, hasLength(1));
      expect(launch.first.block!.durationMin, 10);
    });

    test('carte matin : prochain bloc proche → pas de combleur', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final sched = _sched(today, [
        _block(startTime: '10:30', title: 'Réunion'),
      ]);
      final m = computeCoachMoment(now, stRoutines([]), sched, null, []);
      expect(m.type, CoachMomentType.morning);
      expect(m.message, isNot(contains('D\'ici là')));
    });

    test('après-midi sans programme : « Par exemple » + lancement en un tap',
        () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final m = computeCoachMoment(
          now, stRoutines([]), _sched(today, []), null, [],
          unplannedDismissed: true);
      expect(m.type, CoachMomentType.afternoon);
      expect(m.message, contains('Par exemple : Méditation, 10 min'));
      expect(
          m.actions.any((a) =>
              a.kind == CoachActionKind.launchBlock &&
              a.block?.activityId == 'r1'),
          isTrue);
    });
  });

  group('élan, enchaînement, vital en tension', () {
    // Domaine d1 défini + 2 routines quotidiennes + 1 activité-temps Sport.
    AppState stFull(List<HabitHit> hits,
            {List<Session> sessions = const [],
            List<VitalMinimum> vital = const []}) =>
        AppState(
          domains: [
            Domain(
                id: 'd1',
                name: 'Santé',
                definitionStatus: 'active',
                intention: 'tenir le rythme',
                vitalMinimum: vital),
          ],
          activities: [
            Activity(
                id: 'r1',
                name: 'Méditation',
                domainId: 'd1',
                type: 'habit',
                habitFreq: HabitFreq.daily,
                timerMin: 10,
                order: 0),
            Activity(
                id: 'r2',
                name: 'Marche',
                domainId: 'd1',
                type: 'habit',
                habitFreq: HabitFreq.daily,
                timerMin: 30,
                order: 1),
            Activity(id: 'a1', name: 'Sport', domainId: 'd1', order: 2),
          ],
          sessions: sessions,
          habitProgress: [],
          habitHits: hits,
        );

    List<HabitHit> daily(String id, DateTime now, int days,
            {int h = 9, int m = 0, int fromDaysAgo = 1}) =>
        [
          for (var i = fromDaysAgo; i < fromDaysAgo + days; i++)
            HabitHit(
                habitId: id,
                ts: DateTime(now.year, now.month, now.day - i, h, m)),
        ];

    test('streakOf : série en cours, cassée, journée vécue', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      // 4 jours d'affilée jusqu'à hier — pas encore aujourd'hui : série vivante.
      expect(streakOf('r1', daily('r1', now, 4), now), 4);
      // Trou avant-hier → la série repart d'hier.
      final broken = [
        HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 6, 9, 0)),
        HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 4, 9, 0)),
      ];
      expect(streakOf('r1', broken, now), 1);
      // Hit fait aujourd'hui : compte dans la série.
      final withToday = [
        HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 7, 8, 0)),
        ...daily('r1', now, 2),
      ];
      expect(streakOf('r1', withToday, now), 3);
      // Hit nocturne (0h30) = fin de la veille, pas un jour de plus.
      final night = [
        HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 7, 0, 30)), // = 6 juil.
        HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 5, 22, 0)),
      ];
      expect(streakOf('r1', night, now), 2);
      expect(streakOf('r1', const [], now), 0);
    });

    test('le combleur cite l\'élan : « 4 jours d\'affilée, on continue ? »',
        () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final hits = daily('r1', now, 4, h: 9, m: 25);
      final sched = _sched(today, [_block(startTime: '12:30', title: 'Réunion')]);
      final m = computeCoachMoment(now, stFull(hits), sched, null, []);
      expect(m.type, CoachMomentType.morning);
      expect(m.message, contains('heure habituelle (vers 9h25)'));
      expect(m.message, contains('4 jours d\'affilée, on continue ?'));
    });

    test('« Et ensuite ? » : chrono terminé ≤ 10 min → carte chain', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final sessions = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 7, 9, 30),
            endAt: DateTime(2026, 7, 7, 9, 55)),
      ];
      final m = computeCoachMoment(
          now, stFull([], sessions: sessions), _sched(today, []), null,
          sessions);
      expect(m.type, CoachMomentType.chain);
      expect(m.tagLabel, 'ORION · ET ENSUITE ?');
      expect(m.message, contains('Sport terminé — 25 min au compteur'));
      // La suite proposée : une routine qui tient dans le trou, en un tap.
      expect(
          m.actions.any((a) =>
              a.kind == CoachActionKind.launchBlock &&
              a.block?.activityId == 'r1'),
          isTrue);
      expect(m.tone, CoachTone.positive);
    });

    test('« Et ensuite ? » : fenêtre expirée ou chrono en cours → pas de carte',
        () {
      final now = DateTime(2026, 7, 7, 10, 0);
      // Terminé il y a 25 min : le moment est passé, carte normale.
      final old = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 7, 9, 0),
            endAt: DateTime(2026, 7, 7, 9, 35)),
      ];
      final m1 = computeCoachMoment(
          now, stFull([], sessions: old), _sched(today, []), null, old);
      expect(m1.type, isNot(CoachMomentType.chain));
      // Chrono en cours (endAt null) : rien à enchaîner, on n'interrompt pas.
      final running = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 7, 9, 30),
            endAt: DateTime(2026, 7, 7, 9, 55)),
        Session(activityId: 'a1', startAt: DateTime(2026, 7, 7, 9, 58)),
      ];
      final m2 = computeCoachMoment(
          now, stFull([], sessions: running), _sched(today, []), null,
          running);
      expect(m2.type, isNot(CoachMomentType.chain));
    });

    test('vital en tension (jeudi+) : « on en case une ? » → Planifions', () {
      final now = DateTime(2026, 7, 9, 15, 0); // jeudi
      final vital = [
        VitalMinimum(
            label: '3 séances / sem',
            metric: 'sessions_week',
            target: 3,
            period: 'week'),
      ];
      final sessions = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 8, 18, 0), // mercredi, même semaine
            endAt: DateTime(2026, 7, 8, 18, 30)),
      ];
      final sched = _sched('2026-07-09', [
        _block(startTime: '17:00', title: 'Réunion'),
      ]);
      final m = computeCoachMoment(now,
          stFull([], sessions: sessions, vital: vital), sched, null, sessions);
      expect(m.type, CoachMomentType.afternoon);
      expect(m.message,
          contains('Santé : 1/3 séances cette semaine — on en case une ?'));
      final cta = m.actions
          .where((a) => a.kind == CoachActionKind.planNext)
          .toList();
      expect(cta, hasLength(1));
      expect(cta.first.block?.activityId, 'a1');
      // Une seule proposition à la fois : la tension éteint le combleur.
      expect(m.message, isNot(contains('D\'ici là')));
      expect(m.stats.any((s) => s.label == 'Santé' && s.value == '1/3 · sem.'),
          isTrue);
    });

    test('vital en tension : silence en début de semaine (mardi)', () {
      final now = DateTime(2026, 7, 7, 15, 0); // mardi
      final vital = [
        VitalMinimum(
            label: '3 séances / sem',
            metric: 'sessions_week',
            target: 3,
            period: 'week'),
      ];
      final sched = _sched(today, [_block(startTime: '17:00', title: 'Réunion')]);
      final m = computeCoachMoment(
          now, stFull([], vital: vital), sched, null, []);
      expect(m.type, CoachMomentType.afternoon);
      expect(m.message, isNot(contains('on en case une ?')));
      expect(m.actions.any((a) => a.kind == CoachActionKind.planNext), isFalse);
    });
  });

  group('défi ORION dans la carte', () {
    ChallengeProposal chal(
            {String id = 'a1',
            String name = 'Sport',
            int minutes = 20,
            int doneMin = 0,
            int targetMin = 60,
            int streak = 0}) =>
        ChallengeProposal(
            activity:
                Activity(id: id, name: name, domainId: 'd1', goalMin: targetMin),
            minutes: minutes,
            doneMin: doneMin,
            targetMin: targetMin,
            streak: streak);

    AppState stBase() => AppState(
          domains: [
            Domain(
                id: 'd1',
                name: 'Santé',
                definitionStatus: 'active',
                intention: 'tenir le rythme'),
          ],
          activities: [
            Activity(
                id: 'r1',
                name: 'Méditation',
                domainId: 'd1',
                type: 'habit',
                habitFreq: HabitFreq.daily,
                timerMin: 10,
                order: 0),
            Activity(id: 'a1', name: 'Sport', domainId: 'd1', goalMin: 60),
          ],
          sessions: [],
          habitProgress: [],
        );

    test('après-midi : retard franc + trou → « ORION te défie » + CTA nommé',
        () {
      final now = DateTime(2026, 7, 7, 15, 0); // mardi — pas de tension vitale
      final sched = _sched(today, [_block(startTime: '17:00', title: 'Réunion')]);
      final m = computeCoachMoment(now, stBase(), sched, null, [],
          challenge: chal(streak: 3));
      expect(m.type, CoachMomentType.afternoon);
      expect(m.message,
          contains('ORION te défie : 20 min de « Sport » — il en manque 60'));
      // UN CTA, qui porte le NOM du défi (constaté sur build : « Je relève »
      // seul ne dit pas ce qu'on accepte) — la confirmation se fait en aval.
      final accept = m.actions
          .where((a) => a.kind == CoachActionKind.challengeAccept)
          .toList();
      expect(accept, hasLength(1));
      expect(accept.first.label, 'Défi : Sport — 20 min');
      expect(accept.first.block?.activityId, 'a1');
      expect(accept.first.block?.durationMin, 20);
      // Le streak de défis est un fait affiché, et le défi éteint le combleur.
      expect(m.stats.any((s) => s.label == 'Défis' && s.value == '3 j d\'affilée'),
          isTrue);
      expect(m.message, isNot(contains('D\'ici là')));
    });

    test('pas de retard franc (moitié faite) → pas de défi, combleur de retour',
        () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [_block(startTime: '17:00', title: 'Réunion')]);
      final m = computeCoachMoment(now, stBase(), sched, null, [],
          challenge: chal(doneMin: 40, targetMin: 60));
      expect(m.message, isNot(contains('ORION te défie')));
      expect(m.message, contains('D\'ici là : Méditation'));
    });

    test('défi passé ou déjà relevé aujourd\'hui → une sollicitation par jour',
        () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [_block(startTime: '17:00', title: 'Réunion')]);
      final skipped = stBase()..skippedChallengeDates.add('20260707');
      final m1 = computeCoachMoment(now, skipped, sched, null, [],
          challenge: chal());
      expect(m1.message, isNot(contains('ORION te défie')));
      final won = stBase()..challengeWinsByDay['20260707'] = 1;
      final m2 =
          computeCoachMoment(now, won, sched, null, [], challenge: chal());
      expect(m2.message, isNot(contains('ORION te défie')));
    });

    test('la tension vitale prime sur le défi (une proposition à la fois)', () {
      final now = DateTime(2026, 7, 9, 15, 0); // jeudi
      final st = stBase();
      st.domains.first.vitalMinimum.add(VitalMinimum(
          label: '3 séances / sem',
          metric: 'sessions_week',
          target: 3,
          period: 'week'));
      final sched = _sched('2026-07-09', [
        _block(startTime: '17:00', title: 'Réunion'),
      ]);
      final m =
          computeCoachMoment(now, st, sched, null, [], challenge: chal());
      expect(m.message, contains('on en case une ?'));
      expect(m.message, isNot(contains('ORION te défie')));
    });

    test('« Et ensuite ? » : le défi est la suite — sauf sur l\'activité finie',
        () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final sessions = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 7, 9, 30),
            endAt: DateTime(2026, 7, 7, 9, 55)),
      ];
      final st = stBase()..sessions.addAll(sessions);
      // Défi sur une AUTRE activité : il prend la place du combleur.
      final m1 = computeCoachMoment(now, st, _sched(today, []), null, sessions,
          challenge: chal(id: 'a2', name: 'Guitare', targetMin: 45,
              minutes: 25));
      expect(m1.type, CoachMomentType.chain);
      expect(m1.message, contains('ORION te défie : 25 min de « Guitare »'));
      expect(
          m1.actions.any((a) =>
              a.kind == CoachActionKind.challengeAccept &&
              a.label == 'Défi : Guitare — 25 min' &&
              a.block?.activityId == 'a2'),
          isTrue);
      // Défi sur l'activité qu'on vient de finir : non — le combleur reprend.
      final m2 = computeCoachMoment(now, st, _sched(today, []), null, sessions,
          challenge: chal());
      expect(m2.type, CoachMomentType.chain);
      expect(m2.message, isNot(contains('ORION te défie')));
      expect(m2.message, contains('Méditation'));
    });
  });

  group('« C\'était ton heure » (programme idéal)', () {
    List<HabitHit> hitsAt(String id, DateTime now,
            List<({int daysAgo, int h, int m})> specs) =>
        [
          for (final s in specs)
            HabitHit(
                habitId: id,
                ts: DateTime(
                    now.year, now.month, now.day - s.daysAgo, s.h, s.m)),
        ];

    AppState stRoutines(List<HabitHit> hits, {int? timerMin = 10}) => AppState(
          domains: [
            Domain(
                name: 'Santé',
                definitionStatus: 'active',
                intention: 'tenir le rythme'),
          ],
          activities: [
            Activity(
                id: 'r1',
                name: 'Méditation',
                domainId: 'd1',
                type: 'habit',
                habitFreq: HabitFreq.daily,
                timerMin: timerMin,
                order: 0),
          ],
          sessions: [],
          habitProgress: [],
          habitHits: hits,
        );

    // Un bloc pending SANS rapport pour que « journée non planifiée » se taise.
    final other = _block(startTime: '14:00', title: 'Dossier', status: 'pending');

    test('heure habituelle passée de 10-90 min, rien de coché → la carte', () {
      final now = DateTime(2026, 7, 7, 10, 20);
      final hits = hitsAt('r1', now,
          [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 9, m: 40)]);
      final m = computeCoachMoment(
          now, stRoutines(hits), _sched(today, [other]), null, []);
      expect(m.type, CoachMomentType.idealHour);
      expect(m.tagLabel, 'ORION · C\'ÉTAIT TON HEURE');
      expect(m.message, contains('vers 9h40')); // heure RÉELLE mesurée
      expect(m.message, contains('il est 10h20'));
      expect(
          m.actions.single.kind, CoachActionKind.launchBlock); // minutée → ▶
      expect(m.actions.single.block?.activityId, 'r1');
      expect(m.actions.single.block?.durationMin, 10);
    });

    test('avant l\'heure ou bien après (> 90 min) → pas de carte', () {
      final hits = hitsAt('r1', DateTime(2026, 7, 7),
          [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 9, m: 40)]);
      // 9 h 45 : 5 min de retard seulement — elle viendra d'elle-même.
      final early = computeCoachMoment(DateTime(2026, 7, 7, 9, 45),
          stRoutines(hits), _sched(today, [other]), null, []);
      expect(early.type, isNot(CoachMomentType.idealHour));
      // 11 h 20 : 100 min — le moment est passé, les combleurs reprennent.
      final late = computeCoachMoment(DateTime(2026, 7, 7, 11, 20),
          stRoutines(hits), _sched(today, [other]), null, []);
      expect(late.type, isNot(CoachMomentType.idealHour));
    });

    test('déjà cochée aujourd\'hui ou portée par un bloc pending → silence',
        () {
      final now = DateTime(2026, 7, 7, 10, 20);
      final hits = hitsAt('r1', now,
          [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 9, m: 40)]);
      final done = [...hits, ...hitsAt('r1', now, [(daysAgo: 0, h: 9, m: 45)])];
      final m1 = computeCoachMoment(
          now, stRoutines(done), _sched(today, [other]), null, []);
      expect(m1.type, isNot(CoachMomentType.idealHour));
      final withBlock = _sched(today, [
        other,
        _block(startTime: '17:00', title: 'Méditation', activityId: 'r1'),
      ]);
      final m2 = computeCoachMoment(
          now, stRoutines(hits), withBlock, null, []);
      expect(m2.type, isNot(CoachMomentType.idealHour));
    });

    test('routine sans minuteur → coche directe (✓), pas de durée inventée',
        () {
      final now = DateTime(2026, 7, 7, 10, 20);
      final hits = hitsAt('r1', now,
          [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 9, m: 40)]);
      final m = computeCoachMoment(now, stRoutines(hits, timerMin: null),
          _sched(today, [other]), null, []);
      expect(m.type, CoachMomentType.idealHour);
      expect(m.actions.single.kind, CoachActionKind.checkRoutine);
      expect(m.message, isNot(contains(' min')));
    });

    test('plusieurs candidates → la plus récemment passée', () {
      final now = DateTime(2026, 7, 7, 10, 20);
      final st = stRoutines([]);
      st.activities.add(Activity(
          id: 'r2',
          name: 'Marche',
          domainId: 'd1',
          type: 'habit',
          habitFreq: HabitFreq.daily,
          timerMin: 30,
          order: 1));
      st.habitHits.addAll([
        ...hitsAt('r1', now,
            [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 9, m: 0)]),
        ...hitsAt('r2', now,
            [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 10, m: 0)]),
      ]);
      final m =
          computeCoachMoment(now, st, _sched(today, [other]), null, []);
      expect(m.type, CoachMomentType.idealHour);
      expect(m.title, 'Marche'); // 20 min de retard < 80 min
    });

    test('l\'après-midi, la dérive prime ; la série réelle est citée', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final hits = hitsAt('r1', now,
          [for (var i = 1; i <= 4; i++) (daysAgo: i, h: 14, m: 20)]);
      // Bloc lié du début d'après-midi laissé pending → dérive d'abord.
      final drifting = _sched(today, [
        _block(
            startTime: '14:00',
            durationMin: 30,
            title: 'Dossier',
            activityId: 'a9'),
      ]);
      final m1 =
          computeCoachMoment(now, stRoutines(hits), drifting, null, []);
      expect(m1.type, CoachMomentType.drift);
      // Sans dérive : la carte, avec la série mesurée (4 jours).
      final m2 = computeCoachMoment(
          now, stRoutines(hits), _sched(today, [other]), null, []);
      expect(m2.type, CoachMomentType.idealHour);
      expect(m2.message, contains('4 jours d\'affilée'));
    });
  });

  group('Gantt invisible : micro-action de projet', () {
    Project proj(String title, List<ProjectTask> tasks, {String status = 'active'}) =>
        Project(
            id: 'p-$title',
            title: title,
            startDate: DateTime(2026, 6, 1),
            status: status,
            createdBy: 'u1',
            tasks: tasks);
    ProjectTask task(String id, String title,
            {DateTime? deadline,
            String status = 'pending',
            List<TaskAction>? actions}) =>
        ProjectTask(
            id: id,
            title: title,
            startDate: DateTime(2026, 6, 10),
            endDate: deadline,
            status: status,
            actions: actions);

    test('la tâche à la deadline la plus proche gagne ; done/milestone exclus',
        () {
      final g = ganttMicroAction([
        proj('Site', [
          task('t1', 'Maquette', deadline: DateTime(2026, 7, 30)),
          task('t2', 'Contenu', deadline: DateTime(2026, 7, 20)),
          task('t3', 'Vieille', deadline: DateTime(2026, 7, 1), status: 'done'),
        ]),
        proj('Archivé', [task('t9', 'X', deadline: DateTime(2026, 7, 2))],
            status: 'archived'),
      ]);
      expect(g!.taskTitle, 'Contenu');
      expect(g.projectTitle, 'Site');
      expect(g.deadline, DateTime(2026, 7, 20));
    });

    test('tâche déjà portée par un bloc pending du jour → exclue', () {
      final g = ganttMicroAction([
        proj('Site', [task('t1', 'Maquette', deadline: DateTime(2026, 7, 20))]),
      ], blocks: [
        _block(startTime: '16:00', title: 'Maquette', taskId: 't1'),
      ]);
      expect(g, isNull);
    });

    test(
        'étape définie → « Étape : X — 15 min » (chrono ciblé) + « Programmer »',
        () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final g = ganttMicroAction([
        proj('Site', [
          task('t1', 'Maquette',
              deadline: DateTime(2026, 7, 20),
              actions: [
                TaskAction(id: 'a0', title: 'Cadrer le brief', done: true),
                TaskAction(id: 'a1', title: 'Choisir la palette'),
              ]),
        ]),
      ]);
      expect(g!.needsSteps, isFalse);
      final m = computeCoachMoment(now, _st([]), _sched(today, []), null, [],
          ganttAction: g);
      expect(m.type, CoachMomentType.afternoon);
      expect(m.message, contains('« Maquette » attend (deadline le 20/7)'));
      expect(m.message,
          contains('Prochaine étape : Choisir la palette (1/2 faites)'));
      final cta = m.actions
          .firstWhere((a) => a.label == 'Étape : Choisir la palette — 15 min');
      expect(cta.kind, CoachActionKind.launchBlock);
      expect(cta.block?.projectId, 'p-Site');
      expect(cta.block?.taskId, 't1');
      expect(cta.block?.actionId, 'a1'); // chrono ciblé sur l'ÉTAPE
      final sched = m.actions
          .firstWhere((a) => a.kind == CoachActionKind.scheduleStep);
      expect(sched.block?.actionId, 'a1');
    });

    test('pas d\'étape définie → « Définir la prochaine étape » (GTD)', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final g = ganttMicroAction([
        proj('Site', [task('t1', 'Maquette', deadline: DateTime(2026, 7, 20))]),
      ]);
      expect(g!.needsSteps, isTrue);
      final m = computeCoachMoment(now, _st([]), _sched(today, []), null, [],
          ganttAction: g);
      expect(m.message, contains('n\'a pas de prochaine étape définie'));
      expect(m.actions.where((a) => a.kind == CoachActionKind.launchBlock),
          isEmpty); // rien ne se lance sur du flou
      final cta = m.actions
          .firstWhere((a) => a.kind == CoachActionKind.defineSteps);
      expect(cta.block?.projectId, 'p-Site');
      expect(cta.block?.taskId, 't1');
    });

    test('étape déjà programmée (aujourd\'hui ou futur) → le coach n\'insiste pas',
        () {
      final g = ganttMicroAction([
        proj('Site', [task('t1', 'Maquette')]),
      ], excludeTaskIds: {'t1'});
      expect(g, isNull);
    });

    test('un combleur routine disponible → la routine prime sur le Gantt', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final st = AppState(
        domains: [
          Domain(
              name: 'Santé',
              definitionStatus: 'active',
              intention: 'tenir le rythme'),
        ],
        activities: [
          Activity(
              id: 'r1',
              name: 'Méditation',
              domainId: 'd1',
              type: 'habit',
              habitFreq: HabitFreq.daily,
              timerMin: 10,
              order: 0),
        ],
        sessions: [],
        habitProgress: [],
      );
      final g = ganttMicroAction([
        proj('Site', [task('t1', 'Maquette')]),
      ]);
      final m = computeCoachMoment(now, st, _sched(today, []), null, [],
          ganttAction: g);
      expect(m.message, contains('Méditation'));
      expect(m.message, isNot(contains('Maquette')));
    });
  });

  group('horizon actionnable (90 min) : le soir n\'est pas l\'affaire du midi',
      () {
    test('midi : bloc de 21 h → mention « ce soir », jamais le bloc-clé ni Lancer',
        () {
      final now = DateTime(2026, 7, 7, 13, 0);
      final sched = _sched(today, [
        _block(
            startTime: '21:00',
            durationMin: 5,
            title: 'Hygiène du soir',
            activityId: 'r1'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.midday);
      expect(m.message, contains('L\'après-midi est à toi.'));
      expect(m.message, contains('Ce soir : Hygiène du soir à 21h.'));
      expect(m.actions.where((a) => a.kind == CoachActionKind.launchBlock),
          isEmpty);
    });

    test('midi : bloc d\'après-midi PROCHE → bloc-clé + Lancer ; loin → pas de Lancer',
        () {
      final now = DateTime(2026, 7, 7, 13, 0);
      final near = computeCoachMoment(
          now,
          _st([]),
          _sched(today, [
            _block(startTime: '14:00', title: 'Dossier', activityId: 'a1'),
          ]),
          null,
          []);
      expect(near.message, contains('qu\'une chose à tenir : Dossier'));
      expect(
          near.actions.any((a) => a.kind == CoachActionKind.launchBlock), isTrue);
      final far = computeCoachMoment(
          now,
          _st([]),
          _sched(today, [
            _block(startTime: '17:30', title: 'Dossier', activityId: 'a1'),
          ]),
          null,
          []);
      expect(far.message, contains('qu\'une chose à tenir : Dossier'));
      expect(far.actions.where((a) => a.kind == CoachActionKind.launchBlock),
          isEmpty);
    });

    test('après-midi : prochain bloc à > 90 min → pas de CTA Lancer', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final far = computeCoachMoment(
          now,
          _st([]),
          _sched(today, [
            _block(startTime: '18:00', title: 'Dossier', activityId: 'a1'),
          ]),
          null,
          []);
      expect(far.type, CoachMomentType.afternoon);
      expect(far.actions.where((a) => a.kind == CoachActionKind.launchBlock),
          isEmpty);
      final near = computeCoachMoment(
          now,
          _st([]),
          _sched(today, [
            _block(startTime: '16:00', title: 'Dossier', activityId: 'a1'),
          ]),
          null,
          []);
      expect(near.actions.any((a) => a.kind == CoachActionKind.launchBlock),
          isTrue);
    });
  });

  group('micro-cible : la question du réglage (ORION · RÉGLAGE)', () {
    AppState stTime({int goalMin = 1, String targetSource = 'default'}) =>
        AppState(
          domains: [
            Domain(
                name: 'Spiritualité',
                definitionStatus: 'active',
                intention: 'tenir le rythme'),
          ],
          activities: [
            Activity(
                id: 'a1',
                name: 'Louanges',
                domainId: 'd1',
                type: 'time',
                goalMin: goalMin,
                targetSource: targetSource),
          ],
          sessions: [],
          habitProgress: [],
        );

    List<Session> sess(DateTime now, int days, int perDayMin) => [
          for (var i = 0; i < days; i++)
            Session(
                activityId: 'a1',
                startAt: DateTime(now.year, now.month, now.day - i, 9, 0),
                endAt:
                    DateTime(now.year, now.month, now.day - i, 9, perDayMin)),
        ];

    final other = _block(startTime: '14:00', title: 'Dossier');

    test('cible 1 min, vécue 4 j à ~40 min → la question, avec les faits', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final m = computeCoachMoment(
          now, stTime(), _sched(today, [other]), null, sess(now, 4, 40));
      expect(m.type, CoachMomentType.microTarget);
      expect(m.tagLabel, 'ORION · RÉGLAGE');
      expect(m.message, contains('restée à 1 min/j'));
      expect(m.message, contains('4 jours sur les 28 derniers'));
      expect(m.message, contains('~40 min quand tu t\'y mets'));
      expect(m.actions.map((a) => a.kind), [
        CoachActionKind.keepMicroTarget,
        CoachActionKind.calibrateTarget,
        CoachActionKind.dismiss,
      ]);
      expect(m.actions.first.label, 'Garder 1 min — déclencheur');
      expect(m.actions.first.block?.activityId, 'a1');
      // « Plus tard » → silence pour la session.
      final d = computeCoachMoment(
          now, stTime(), _sched(today, [other]), null, sess(now, 4, 40),
          microTargetDismissed: true);
      expect(d.type, isNot(CoachMomentType.microTarget));
    });

    test('réel COHÉRENT avec la micro-cible (sessions ~1 min) → pas de question',
        () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final m = computeCoachMoment(
          now, stTime(), _sched(today, [other]), null, sess(now, 5, 1));
      expect(m.type, isNot(CoachMomentType.microTarget));
    });

    test('déjà réglée (user/orion) ou pas assez de faits → pas de question',
        () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final pinned = computeCoachMoment(now, stTime(targetSource: 'user'),
          _sched(today, [other]), null, sess(now, 4, 40));
      expect(pinned.type, isNot(CoachMomentType.microTarget));
      final few = computeCoachMoment(
          now, stTime(), _sched(today, [other]), null, sess(now, 2, 40));
      expect(few.type, isNot(CoachMomentType.microTarget));
    });
  });
}
