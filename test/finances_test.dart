import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';

void main() {
  test('jours suivis, série, rattrapage d\'hier seulement', () {
    final f = const Finances().copyWith(
      expenses: {
        'a': const Expense(id: 'a', ymd: '2026-11-01', amount: 2340, envelopeId: 'courses'),
        'b': const Expense(id: 'b', ymd: '2026-10-31', amount: 500, envelopeId: 'sorties'),
      },
      nothing: {'2026-10-30'},
    );
    expect(trackedDays(f), {'2026-11-01', '2026-10-31', '2026-10-30'});
    expect(trackingStreak(f, '2026-11-02'), 3);
    expect(trackedSince(f, '2026-10-31'), 2);
    expect(canLogOn('2026-11-01', '2026-11-02'), isTrue);
    expect(canLogOn('2026-10-31', '2026-11-02'), isFalse);
  });

  test('le mois : reste à vivre, enveloppes face à l\'attendu, fixes', () {
    final f = const Finances(
      envelopes: [Envelope(id: 'courses', name: 'Courses', monthly: 40000), Envelope(id: 'essence', name: 'Essence', monthly: 12000)],
      recurring: [
        Recurring(id: 'sal', name: 'Salaire', amount: 200000, income: true),
        Recurring(id: 'loyer', name: 'Loyer', amount: 65000),
        Recurring(id: 'elec', name: 'Électricité', amount: 8500, day: 5),
      ],
    ).copyWith(
      expenses: {
        'a': const Expense(id: 'a', ymd: '2026-11-02', amount: 3800, envelopeId: 'courses'),
        'b': const Expense(id: 'b', ymd: '2026-11-01', amount: 4500, envelopeId: 'essence'),
        'c': const Expense(id: 'c', ymd: '2026-10-31', amount: 9900, envelopeId: 'courses'),
      },
      paid: {
        '2026-11': {'loyer': const Paid(65000, '2026-11-01')}
      },
    );
    final m = monthSummary(f, '2026-11-02');
    expect(m.spent, 8300);
    expect(m.remaining, 200000 - 73500 - 8300);
    expect(m.daysLeft, 29);
    expect(m.fixedPaidCount, 1);
    expect(m.fixedCount, 2);
    final ess = m.envelopes.firstWhere((e) => e.envelope.id == 'essence');
    expect(ess.expected, 800);
    expect(ess.ahead, isTrue);
    expect(m.envelopes.first.ahead, isTrue);
    expect(dueYmdOf(const Recurring(id: 'x', name: 'x', amount: 1, day: 31), '2026-11-02'), '2026-11-30');
  });

  test('le point de la semaine : écart face au dernier solde', () {
    final f = const Finances(recurring: [Recurring(id: 'elec', name: 'Électricité', amount: 8500)]).copyWith(
      checks: {'2026-10-25': 210400},
      expenses: {
        'a': const Expense(id: 'a', ymd: '2026-10-28', amount: 25150, envelopeId: 'courses'),
        'old': const Expense(id: 'old', ymd: '2026-10-25', amount: 999, envelopeId: 'courses'),
      },
      paid: {
        '2026-11': {'elec': const Paid(8500, '2026-11-01')}
      },
    );
    final c = balanceCheck(f, '2026-11-01');
    expect(c.lastYmd, '2026-10-25');
    expect(c.expected, 210400 - 25150 - 8500);
    expect(c.gap(172750), 172750 - (210400 - 25150 - 8500));
    expect(balanceCheck(const Finances(), '2026-11-01').expected, isNull);
  });

  test('aller-retour JSON et montants', () {
    final f = const Finances(recurring: [Recurring(id: 'loyer', name: 'Loyer', amount: 65000, day: 3)]).copyWith(
      expenses: {'a': const Expense(id: 'a', ymd: '2026-11-02', amount: 2340, envelopeId: 'courses', note: 'Lidl')},
      nothing: {'2026-11-01'},
      paid: {
        '2026-11': {'loyer': const Paid(65000, '2026-11-01')}
      },
      checks: {'2026-11-01': 100},
    );
    final g = parseFinances(f.toJson());
    expect(g.expenses['a']!.note, 'Lidl');
    expect(g.recurring.single.day, 3);
    expect(g.paid['2026-11']!['loyer']!.amount, 65000);
    expect(g.checks['2026-11-01'], 100);
    expect(g.envelopes.length, kDefaultEnvelopes.length);
    expect(euros(124000), '1 240 €');
    expect(euros(2340), '23,40 €');
    expect(euros(-4000), '− 40 €');
    expect(parseEuros('23,4'), 2340);
    expect(parseEuros('0'), isNull);
  });

  test('une dépense ou « rien dépensé » coche une fois « Suivre mon budget »', () async {
    final r = Activity(id: 'b', domainId: 'd', name: 'Suivre mon budget', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
    final st = AppState(domains: [], activities: [r], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final today = logic.livedTodayYmd;
    await logic.logExpense(amount: 1200, envelopeId: 'courses');
    await logic.logExpense(amount: 300, envelopeId: 'courses');
    expect(st.habitHits.where((h) => h.habitId == 'b').length, 1);
    final yesterday = prevYmd(today);
    await logic.setNothingSpent(yesterday, true);
    expect(st.habitHits.where((h) => h.habitId == 'b').length, 2);
    expect(isTracked(logic.finances, yesterday), isTrue);
    expect(await logic.logExpense(amount: 100, envelopeId: 'courses', ymd: prevYmd(yesterday)), isNull);
  });

  test('le point est dû tous les 7 jours, un écart < 1 € ne compte pas', () {
    expect(checkDue(const Finances(), '2026-11-02'), isTrue);
    final f = const Finances().copyWith(checks: {'2026-10-25': 100, '2026-10-30': 200});
    expect(lastCheckYmd(f), '2026-10-30');
    expect(checkDue(f, '2026-11-02'), isFalse);
    expect(checkDue(f, '2026-11-06'), isTrue);
    expect(gapIsZero(-99), isTrue);
    expect(gapIsZero(-100), isFalse);
  });

  test('un ticket enregistré par Claude (serveur) coche aussi la routine', () {
    final r = Activity(id: 'b', domainId: 'd', name: 'Suivre mon budget', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
    final st = AppState(domains: [], activities: [r], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final today = logic.livedTodayYmd;
    logic.onFinancesFromServer(const Finances().copyWith(expenses: {'x': Expense(id: 'x', ymd: today, amount: 100, envelopeId: 'courses')}));
    expect(st.habitHits.where((h) => h.habitId == 'b').length, 1);
    logic.onFinancesFromServer(logic.finances);
    expect(st.habitHits.where((h) => h.habitId == 'b').length, 1);
  });
}
