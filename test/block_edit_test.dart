import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_edit.dart';

/// « Modifier le bloc » ne règle que quelques champs : tout le reste doit survivre
/// (bug user 2026-11-21 : Sommeil déplacé à 23:00 disparaissait du programme).
void main() {
  ScheduleBlock edit(ScheduleBlock b, {String start = '23:00', String? projectId, String? timeBlock}) => editedBlock(b,
      startTime: start,
      durationMin: b.durationMin,
      title: b.title,
      category: b.category,
      projectId: projectId ?? b.projectId,
      taskId: b.taskId,
      activityId: b.activityId,
      actionId: b.actionId,
      timeBlock: timeBlock);

  test('un rendez-vous d\'agenda déplacé garde son lien avec l\'agenda', () {
    final sleep = ScheduleBlock(id: 'gcal-ev1', startTime: '22:00', durationMin: 420, title: 'Sommeil', gcalEventId: 'ev1', activityId: 'a');
    final moved = edit(sleep);
    expect(moved.id, 'gcal-ev1');
    expect(moved.startTime, '23:00');
    expect(moved.gcalEventId, 'ev1');
    expect(moved.activityId, 'a');
    expect(sleep.startTime, '22:00');
  });

  test('un rendez-vous retouché dans l\'app est marqué : l\'app fait foi jusqu\'à ce que l\'agenda ait suivi', () {
    final sleep = ScheduleBlock(id: 'gcal-ev1', startTime: '23:00', durationMin: 420, title: 'Sommeil', gcalEventId: 'ev1');
    expect(sleep.toJson().containsKey('gcalDirty'), isFalse);
    sleep.gcalDirty = true;
    expect(sleep.toJson()['gcalDirty'], isTrue);
    expect(ScheduleBlock.from(sleep.toJson()).gcalDirty, isTrue);
    expect(edit(sleep, start: '23:30').gcalDirty, isTrue);
  });

  test('un bloc de la nuit garde son doc, un bloc retouché ses autres réglages', () {
    final night = ScheduleBlock(id: 'n', startTime: '00:30', durationMin: 60, title: 'Lecture', noAutoWin: true, reminders: ['00:20'])
      ..docDate = '2026-11-22'
      ..dayOffset = 1;
    final moved = edit(night, start: '01:00');
    expect(moved.docDate, '2026-11-22');
    expect(moved.dayOffset, 1);
    expect(moved.noAutoWin, isTrue);
    expect(moved.reminders, ['00:20']);
  });

  test('cibles suivantes : gardées sur le même projet, lâchées quand le projet change ; le mode se retire', () {
    final deep = ScheduleBlock(
        id: 'd',
        startTime: '09:00',
        durationMin: 90,
        title: 'Deep work',
        projectId: 'p1',
        taskId: 't1',
        timeBlock: 'deep',
        extraTargets: [BlockTarget(projectId: 'p1', taskId: 't2')]);
    final same = edit(deep, timeBlock: 'deep');
    expect(same.extraTargets.single.taskId, 't2');
    expect(same.timeBlock, 'deep');
    final other = edit(deep, projectId: 'p2');
    expect(other.extraTargets, isEmpty);
    expect(other.timeBlock, isNull);
  });

  test('deux blocs au même id : un seul est lu, celui qui porte le lien avec l\'agenda', () {
    Map<String, dynamic> block(String start, {String? ev}) =>
        ScheduleBlock(id: 'gcal-ev1', startTime: start, durationMin: 420, title: 'Sommeil', gcalEventId: ev).toJson();
    final twins = DailySchedule.from({
      'date': '2026-11-20',
      'blocks': [
        ScheduleBlock(id: 'a', startTime: '09:00', durationMin: 60, title: 'Cours').toJson(),
        block('23:00'),
        block('23:00'),
      ],
    });
    expect(twins.blocks.map((b) => b.id), ['a', 'gcal-ev1']);
    final mixed = DailySchedule.from({
      'date': '2026-11-20',
      'blocks': [block('23:00'), block('22:00', ev: 'ev1')],
    });
    expect(mixed.blocks.single.startTime, '22:00');
    expect(mixed.blocks.single.gcalEventId, 'ev1');
  });
}
