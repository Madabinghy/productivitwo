import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show countsForBadges;
import 'package:productivitwo_v1/utils/planning.dart' show capHeld;
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/widgets/remove_block_sheet.dart';

ScheduleBlock _b(String id, String status, {String? reason}) =>
    ScheduleBlock(id: id, startTime: '09:00', durationMin: 60, title: id, status: status, skipReason: reason);

void main() {
  test('un bloc lâché compte comme non fait, un bloc empêché ne compte pas', () {
    expect(countsForBadges(_b('l', 'skipped', reason: kSkipLetGo)), isTrue);
    expect(countsForBadges(_b('e', 'skipped', reason: kSkipUnavailable)), isFalse);
    expect(countsForBadges(_b('s', 'skipped')), isFalse);
    expect(isLetGoBlock(_b('l', 'skipped', reason: kSkipLetGo)), isTrue);
    // Rendez-vous d'agenda : ne compte pas tant qu'il est à faire, compte s'il est lâché.
    ScheduleBlock m(String status, {String? reason}) =>
        ScheduleBlock(id: 'm', startTime: '09:00', durationMin: 60, title: 'GDS', status: status, skipReason: reason, gcalEventId: 'evt');
    expect(countsForBadges(m('pending')), isFalse);
    expect(countsForBadges(m('skipped', reason: kSkipLetGo)), isTrue);
    expect(countsForBadges(m('skipped', reason: kSkipUnavailable)), isFalse);
  });

  test('Cap tenu : le bloc lâché reste dans le compte', () {
    DailySchedule day(List<ScheduleBlock> blocks) => DailySchedule(
          date: '2026-11-02',
          generatedBy: 'plan',
          generatedAt: DateTime(2026, 11, 1, 21),
          blocks: blocks,
        )..plannedAt = DateTime(2026, 11, 1, 21);
    final done = [for (var i = 0; i < 2; i++) _b('d$i', 'done')];
    expect(capHeld(day([...done, _b('e', 'skipped', reason: kSkipUnavailable)])), isTrue);
    expect(capHeld(day([...done, _b('l', 'skipped', reason: kSkipLetGo)])), isFalse);
  });

  testWidgets('feuille « Pourquoi ? » : quatre choix, le lâcher renvoyé', (t) async {
    RemoveBlockChoice? got;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => got = await showRemoveBlockSheet(ctx, _b('GDS', 'pending'), flemme: true),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    expect(find.text('Je le déplace'), findsOneWidget);
    expect(find.text('J’ai été empêché'), findsOneWidget);
    expect(find.text('10 min'), findsOneWidget);
    expect(find.textContaining('Google Agenda'), findsNothing);
    await t.tap(find.text('Je lâche ce bloc'));
    await t.pumpAndSettle();
    expect(got, RemoveBlockChoice.letGo);
  });
}
