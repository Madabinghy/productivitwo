import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/module_journey.dart';
import 'package:productivitwo_v1/utils/modules.dart';

void main() {
  const core = ModuleSettings.only({});
  const ready = JourneyFacts(usageDays: 9, activeDaysLast7: 6);

  test('rien de prêt = rien proposé', () {
    expect(nextProposal(settings: core, journey: const ModuleJourney(), facts: const JourneyFacts(), today: '2026-11-16'), isNull);
  });

  test('Planification proposée quand on avance chaque jour', () {
    expect(nextProposal(settings: core, journey: const ModuleJourney(), facts: ready, today: '2026-11-16'), AppModule.planning);
  });

  test('tout allumé = rien proposé', () {
    expect(nextProposal(settings: ModuleSettings.everything, journey: const ModuleJourney(), facts: ready, today: '2026-11-16'), isNull);
  });

  test('une proposition en attente reste, même bloquée', () {
    const j = ModuleJourney(pending: AppModule.sleep, lastProposed: '2026-11-15');
    expect(nextProposal(settings: core, journey: j, facts: const JourneyFacts(), today: '2026-11-16', blocked: true), AppModule.sleep);
  });

  test('une par semaine au plus', () {
    const j = ModuleJourney(lastProposed: '2026-11-12');
    expect(nextProposal(settings: core, journey: j, facts: ready, today: '2026-11-16'), isNull);
    expect(nextProposal(settings: core, journey: j, facts: ready, today: '2026-11-19'), AppModule.planning);
  });

  test('bloqué (Le minimum) = rien de nouveau', () {
    expect(nextProposal(settings: core, journey: const ModuleJourney(), facts: ready, today: '2026-11-16', blocked: true), isNull);
  });

  test('Pas pour moi = jamais ; Plus tard = dans 30 jours', () {
    final never = ModuleJourney(declined: {AppModule.planning: 'never'});
    expect(nextProposal(settings: core, journey: never, facts: ready, today: '2026-11-16'), isNull);
    final later = ModuleJourney(declined: {AppModule.planning: 'later:${laterUntil('2026-11-16')}'});
    expect(nextProposal(settings: core, journey: later, facts: ready, today: '2026-11-20'), isNull);
    expect(nextProposal(settings: core, journey: later, facts: ready, today: '2026-12-16'), AppModule.planning);
  });

  test('Liberté jamais proposée', () {
    expect(moduleSignal(AppModule.freedom, ready), isNull);
  });

  test('relecture', () {
    final j = ModuleJourney.from({'since': '2026-11-01', 'pending': 'sleep', 'lastProposed': '2026-11-10', 'declined': {'game': 'never', 'x': 'never'}});
    expect(j.since, '2026-11-01');
    expect(j.pending, AppModule.sleep);
    expect(j.declined, {AppModule.game: 'never'});
  });

  test('repartir comme un débutant, puis retrouver son app', () {
    final json = beginnerModules(ModuleSettings.everything, '2026-11-16');
    final s = parseModules(json);
    final j = ModuleJourney.from(json);
    expect(s.count, 0);
    expect(j.since, '2026-11-16');
    expect(j.before!.length, kModules.length);
    final back = parseModules(restoredModules(j));
    expect(back.count, kModules.length);
    expect(ModuleJourney.from(restoredModules(j)).before, isNull);
  });
}
