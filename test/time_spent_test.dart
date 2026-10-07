import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/time_spent.dart';

Session _s(String start, int? min, {String? actionId}) {
  final a = DateTime.parse(start);
  return Session(
      activityId: 'act',
      startAt: a,
      endAt: min == null ? null : a.add(Duration(minutes: min)),
      actionId: actionId);
}

void main() {
  test('estimateFactor : médiane réel/estimé sur les actions faites, 3 échantillons minimum', () {
    TaskAction a(String id, int? est, {bool done = true}) =>
        TaskAction(id: id, title: id, estimatedMin: est, done: done);
    final p = Project(id: 'p', title: 'p', startDate: DateTime(2026, 1, 1), createdBy: 'u', tasks: [
      ProjectTask(id: 't', title: 't', startDate: DateTime(2026, 1, 1), actions: [
        a('x', 30), a('y', 20), a('z', 60), a('open', 30, done: false), a('noest', null),
      ]),
    ]);
    final spent = {'x': 45, 'y': 20, 'z': 120, 'open': 90, 'noest': 50};
    expect(estimateFactor([p], spent), 1.5); // ratios 1,5 · 1 · 2 → médiane 1,5
    expect(estimateFactor([p], {'x': 45}), isNull);
    expect(estimateFactorLabel(1.5), 'Réel ≈ 1,5× l\'estimé');
    expect(estimateFactorLabel(null), isNull);
  });

  test('closedSessionMin : fermée, ouverte, chrono oublié', () {
    expect(closedSessionMin(_s('2026-10-01T09:00:00', 45)), 45);
    expect(closedSessionMin(_s('2026-10-01T09:00:00', null)), 0);
    expect(closedSessionMin(_s('2026-10-01T09:00:00', 13 * 60)), 0);
  });

  test('spentByAction : cumul par action, sessions sans action ignorées', () {
    final m = spentByAction([
      _s('2026-10-01T09:00:00', 30, actionId: 'a'),
      _s('2026-10-02T09:00:00', 20, actionId: 'a'),
      _s('2026-10-02T10:00:00', 15, actionId: 'b'),
      _s('2026-10-02T11:00:00', 50),
      _s('2026-10-02T12:00:00', null, actionId: 'b'),
    ]);
    expect(m, {'a': 50, 'b': 15});
  });

  test('spentLabel : libellé et dépassement', () {
    expect(spentLabel(0, 30, fmtMin), isNull);
    final r = spentLabel(50, 30, fmtMin)!;
    expect(r.label, '⏱ 50 min passées');
    expect(r.over, isTrue);
    expect(spentLabel(20, 30, fmtMin)!.over, isFalse);
    expect(spentLabel(20, null, fmtMin)!.over, isFalse);
  });
}
