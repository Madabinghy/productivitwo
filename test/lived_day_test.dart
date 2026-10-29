import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin;

void main() {
  test('livedDate / livedYmd : avant la bascule = la veille', () {
    expect(livedDate(DateTime(2026, 10, 17, 0, 30), 5 * 60), DateTime(2026, 10, 16));
    expect(livedDate(DateTime(2026, 10, 17, 5, 0), 5 * 60), DateTime(2026, 10, 17));
    expect(livedDate(DateTime(2026, 10, 17, 9, 0), 10 * 60), DateTime(2026, 10, 16)); // travail de nuit
    expect(livedYmd(DateTime(2026, 10, 17, 0, 30), 5 * 60), '20261016');
    expect(livedDate(DateTime(2026, 10, 17, 0, 30), 0), DateTime(2026, 10, 17)); // minuit = calendaire
  });

  test('livedProgramYmd : clé du programme de la journée vécue', () {
    expect(livedProgramYmd(DateTime(2026, 10, 17, 0, 30), 5 * 60), '2026-10-16');
    expect(livedProgramYmd(DateTime(2026, 10, 17, 6, 0), 5 * 60), '2026-10-17');
  });

  test('livedDayStart / livedNowMin', () {
    expect(livedDayStart(DateTime(2026, 10, 17, 0, 30), 5 * 60), DateTime(2026, 10, 16, 5));
    expect(livedDayStart(DateTime(2026, 10, 17, 23, 0), 5 * 60), DateTime(2026, 10, 17, 5));
    expect(livedNowMin(DateTime(2026, 10, 17, 0, 30), 5 * 60), 24 * 60 + 30);
    expect(livedNowMin(DateTime(2026, 10, 17, 7, 0), 5 * 60), 7 * 60);
  });

  test('parseDayStartMin : bornes et défaut ; dayStartLabel', () {
    expect(parseDayStartMin(null), kDefaultDayStartMin);
    expect(parseDayStartMin(600), 600);
    expect(parseDayStartMin(13 * 60), kDefaultDayStartMin);
    expect(parseDayStartMin(-1), kDefaultDayStartMin);
    expect(dayStartLabel(5 * 60), '5 h');
    expect(dayStartLabel(5 * 60 + 30), '5 h 30');
  });

  test('livedDayBlocks / mergeLivedDay : la nuit du lendemain rejoint la journée vécue', () {
    ScheduleBlock b(String id, String start, {int dur = 30}) =>
        ScheduleBlock(id: id, startTime: start, durationMin: dur, title: id, category: 'personal');
    final day = DailySchedule(date: '2026-10-29', generatedBy: 'auto', blocks: [b('matin', '09:00'), b('soir', '22:00', dur: 420), b('tot', '04:00')]);
    final next = DailySchedule(date: '2026-10-30', blocks: [b('nuit', '00:20', dur: 60), b('demain', '09:00')]);
    final merged = mergeLivedDay('2026-10-29', day, next, 5 * 60)!;
    expect(merged.date, '2026-10-29');
    expect(merged.generatedBy, 'auto');
    expect(merged.blocks.map((x) => x.id).toList(), ['matin', 'soir', 'nuit']);
    final nuit = merged.blocks.last;
    expect(nuit.docDate, '2026-10-30');
    expect(nuit.dayOffset, 1);
    expect(blockStartMin(nuit), 24 * 60 + 20);
    expect(nuit.startTime, '00:20'); // affichage inchangé, stockage inchangé
    expect(nuit.toJson().containsKey('docDate'), isFalse);
    expect(merged.blocks.first.dayOffset, 0);
    // Sans doc du jour mais une nuit → programme réduit à la nuit ; rien → null.
    expect(mergeLivedDay('2026-10-29', null, next, 5 * 60)!.blocks.map((x) => x.id).toList(), ['nuit']);
    expect(mergeLivedDay('2026-10-29', null, DailySchedule(date: '2026-10-30', blocks: [b('demain', '09:00')]), 5 * 60), isNull);
    expect(mergeLivedDay('2026-10-29', null, null, 5 * 60), isNull);
  });

  test('nextYmd / docForNewBlock : après minuit, le bloc créé va sur le doc du lendemain', () {
    expect(nextYmd('2026-10-31'), '2026-11-01');
    expect(docForNewBlock('2026-10-29', DateTime(2026, 10, 30, 0, 20), 5 * 60), '2026-10-30');
    expect(docForNewBlock('2026-10-29', DateTime(2026, 10, 29, 23, 20), 5 * 60), '2026-10-29');
    expect(docForNewBlock('2026-10-29', DateTime(2026, 10, 29, 14, 0), 5 * 60), '2026-10-29');
  });
}
