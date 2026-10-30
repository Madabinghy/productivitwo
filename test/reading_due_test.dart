import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/evening_ledger.dart';
import 'package:productivitwo_v1/utils/notif_digest.dart';
import 'package:productivitwo_v1/utils/reading_due.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

StrategicObjective _obj(String id, List<String> dates, {int every = 7}) => StrategicObjective(
      id: id,
      title: 'Objectif $id',
      startDate: DateTime(2026, 9, 1),
      checkInEvery: every,
      metric: ObjectiveMetric(label: 'Poids', unit: 'kg', startValue: 95, targetValue: 90),
      readings: [for (final d in dates) ObjectiveReading(date: d, value: 93)],
    );

void main() {
  final now = DateTime(2026, 10, 30, 18);

  test('relevé dû, dernier jour, série cassée', () {
    final dueWeek = _obj('a', ['2026-10-16', '2026-10-23']); // 7 j : dû, pas le dernier jour
    final lastDay = _obj('b', ['2026-10-15', '2026-10-22']); // 8 j : dernier jour
    final broken = _obj('c', ['2026-10-10', '2026-10-20']); // 10 j : série cassée
    final fresh = _obj('d', ['2026-10-28']); // pas dû
    final due = readingsDue([dueWeek, lastDay, broken, fresh], now);
    expect(due.map((r) => r.objective.id).toList(), ['b', 'a', 'c']);
    expect(due.first.lastDay, isTrue);
    expect(due.first.series, 2);
    expect(due[1].lastDay, isFalse);
    expect(due[2].series, 0);
    expect(due[2].lastDay, isFalse);
  });

  test('enjeu : « se perd ce soir » le dernier jour, bilan et notification', () {
    final lastDay = _obj('b', ['2026-10-15', '2026-10-22']);
    final facts = TodayFacts(ymd: '2026-10-30', now: now, objectives: [lastDay]);
    final deck = BadgeDeck([
      BadgeState(def: const BadgeDef(id: 'releve-fidele', family: BadgeFamily.objectives, name: 'Relevé fidèle', symbol: 'ledger', tiers: kReadingTiers, unit: 'relevés'), level: 0, value: 2),
    ]);
    final board = buildStakeBoard(deck: deck, facts: facts);
    final s = [...board.top, ...board.rest].singleWhere((s) => s.gesture.kind == StakeGestureKind.reading);
    expect(s.losesTonight, isTrue);
    expect(s.gesture.objective?.id, 'b');
    final ledger = buildEveningLedger(
        board: board, deck: deck, projects: const [], activities: const [], sessions: const [], objectiveDays: const [], dayStart: DateTime(2026, 10, 30, 5), now: now);
    expect(ledger.slipped.any((l) => l.title.contains('relevé')), isTrue);
    final n = eveningDigest(routines: 0, blocks: 0, seriesAtRisk: const [], readingsLastDay: ['Poids']);
    expect(n?.title, 'Relevé à noter ce soir');
  });
}
