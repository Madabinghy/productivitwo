import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/embers.dart';

void main() {
  const today = '2026-10-29';
  final pompes = {'2026-10-24', '2026-10-25', '2026-10-26', '2026-10-27'}; // cassée le 28

  test('une journée parfaite = une braise, acquise après le jour même, réserve plafonnée à 3', () {
    final l = emberLedger(perfectYmds: ['2026-10-01', '2026-10-05', '2026-10-09', '2026-10-12', today], spends: const [], reached: const {}, todayYmd: today);
    expect(l.stock, 3);
    expect(l.history.first.kind, EmberEventKind.capped); // la 4ᵉ ne forge rien ; aujourd'hui n'est pas clos
    expect(l.available, 3);
  });

  test('rallumer : en attente tant que la routine n’est pas atteinte aujourd’hui, puis effective', () {
    final spend = [const EmberSpend(activityId: 'p', lostYmd: '2026-10-28', spentYmd: today)];
    final waiting = emberLedger(perfectYmds: ['2026-10-20'], spends: spend, reached: {'p': pompes}, todayYmd: today);
    expect(waiting.pending, isNotNull);
    expect(waiting.stock, 1);
    expect(waiting.available, 0);
    expect(waiting.bridged['p'], isNull);

    final done = emberLedger(perfectYmds: ['2026-10-20'], spends: spend, reached: {'p': {...pompes, today}}, todayYmd: today);
    expect(done.pending, isNull);
    expect(done.stock, 0);
    expect(done.bridged['p'], {'2026-10-28'});
    expect(done.history.first.kind, EmberEventKind.spent);
  });

  test('un rallumage d’un jour passé sans la routine ne coûte rien', () {
    final l = emberLedger(
      perfectYmds: ['2026-10-01'],
      spends: const [EmberSpend(activityId: 'p', lostYmd: '2026-10-09', spentYmd: '2026-10-10')],
      reached: {'p': {'2026-10-08'}},
      todayYmd: today,
    );
    expect(l.stock, 1);
    expect(l.bridged, isEmpty);
  });

  test('sans braise, pas de rallumage ; une série par mois', () {
    final none = emberLedger(perfectYmds: const [], spends: const [EmberSpend(activityId: 'p', lostYmd: '2026-10-28', spentYmd: today)], reached: {'p': {...pompes, today}}, todayYmd: today);
    expect(none.bridged, isEmpty);
    final twice = emberLedger(
      perfectYmds: ['2026-10-01', '2026-10-02'],
      spends: const [
        EmberSpend(activityId: 'p', lostYmd: '2026-10-14', spentYmd: '2026-10-15'),
        EmberSpend(activityId: 'p', lostYmd: '2026-10-28', spentYmd: today),
      ],
      reached: {'p': {'2026-10-13', '2026-10-15', ...pompes, today}},
      todayYmd: today,
    );
    expect(twice.bridged['p'], {'2026-10-14'});
    expect(twice.stock, 1);
  });

  test('séries perdues hier : rallumable, bloquée par la règle des 30 jours ou faute de braise', () {
    final ledger = emberLedger(perfectYmds: ['2026-10-01', '2026-10-20'], spends: const [EmberSpend(activityId: 't', lostYmd: '2026-10-16', spentYmd: '2026-10-17')], reached: {'t': {'2026-10-15', '2026-10-17', '2026-10-26', '2026-10-27'}}, todayYmd: today);
    final lost = lostYesterday(
      routines: const [('p', 'Pompes'), ('t', 'Tractions'), ('l', 'Lecture')],
      reached: {'p': pompes, 't': {'2026-10-15', '2026-10-17', '2026-10-26', '2026-10-27'}, 'l': {'2026-10-27', '2026-10-28'}},
      ledger: ledger,
      todayYmd: today,
    );
    expect(lost.map((x) => x.name), ['Pompes', 'Tractions']); // Lecture tenue hier
    expect(lost.first.length, 4);
    expect(lost.first.nextTier, 7);
    expect(lost.first.rekindlable, isTrue);
    expect(lost[1].blocked, contains('déjà rallumée le 17 oct.'));
    final broke = emberLedger(perfectYmds: const [], spends: const [], reached: const {}, todayYmd: today);
    final noEmber = lostYesterday(routines: const [('p', 'Pompes')], reached: {'p': pompes}, ledger: broke, todayYmd: today);
    expect(noEmber.single.blocked, 'aucune braise en réserve');
  });

  test('écriture : rallumer puis annuler l’attente', () {
    final w = withRekindle(const [], 'p', today);
    expect(w.single.lostYmd, '2026-10-28');
    expect(withoutPending(w, 'p', today), isEmpty);
    expect(EmberSpend.listFrom([w.single.toJson(), {'bad': 1}]).single.activityId, 'p');
  });

  test('deck : le jour comblé tient la série, jamais la journée parfaite', () {
    final a = Activity(id: 'p', name: 'Pompes', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 10, 1));
    final hits = [for (final d in [24, 25, 26, 27, 29]) HabitHit(habitId: 'p', ts: DateTime(2026, 10, d, 9))];
    BadgeDeck deckOf(List<EmberSpend> spends) => computeBadges(
          activities: [a], habitHits: hits, schedules: const [], projects: const [], objectives: const [], sessions: const [],
          now: DateTime(2026, 10, 29, 18), emberSpends: spends);
    final plain = deckOf(const []);
    final lit = deckOf(const [EmberSpend(activityId: 'p', lostYmd: '2026-10-28', spentYmd: today)]);
    BadgeState serie(BadgeDeck d) => d.badges.firstWhere((b) => b.def.id == 'serie-p');
    BadgeState perfect(BadgeDeck d) => d.badges.firstWhere((b) => b.def.id == 'journee-parfaite');
    expect(serie(plain).value, 1);
    expect(serie(lit).value, 6);
    expect(lit.embers.stock, 2); // 4 journées parfaites → 3 (plafond), moins le rallumage
    expect(perfect(lit).value, perfect(plain).value);
    expect(serie(lit).track!.cells.contains(TrackCell.bridged), isTrue);
  });
}
