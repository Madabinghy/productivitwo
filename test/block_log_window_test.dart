import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

ScheduleBlock _b(String id, String start, int dur, {String? taskId, String? activityId}) =>
    ScheduleBlock(
        id: id, startTime: start, durationMin: dur, title: id, taskId: taskId, activityId: activityId);

void main() {
  test('seul bloc sur sa source : toute la journée', () {
    final b = _b('a', '08:30', 240, taskId: 't');
    final w = blockLogWindow(b, [b, _b('x', '13:30', 180, taskId: 'autre')]);
    expect((w.start, w.end), (0, 1440));
  });

  test('séance en deux blocs : la journée est partagée à mi-chemin', () {
    final am = _b('am', '08:30', 240, taskId: 't');
    final pm = _b('pm', '13:30', 180, taskId: 't');
    final all = [am, pm];
    final wa = blockLogWindow(am, all), wp = blockLogWindow(pm, all);
    expect((wa.start, wa.end), (0, 13 * 60));
    expect((wp.start, wp.end), (13 * 60, 1440));

    final day = DateTime(2026, 10, 9);
    final morning = Session(
        id: 's',
        activityId: 'act',
        taskId: 't',
        startAt: day.add(const Duration(hours: 8, minutes: 40)),
        endAt: day.add(const Duration(hours: 11, minutes: 57)));
    int logged(ScheduleBlock b, ({int start, int end}) w) => loggedMinForBlock(
        b, [morning], day.add(Duration(minutes: w.start)), day.add(Duration(minutes: w.end)));
    expect(logged(am, wa), 197);
    expect(logged(pm, wp), 0);
  });

  test('bloc supprimé ignoré', () {
    final am = _b('am', '08:30', 240, taskId: 't');
    final gone = ScheduleBlock(
        id: 'pm', startTime: '13:30', durationMin: 180, title: 'pm', taskId: 't', status: 'deleted');
    final w = blockLogWindow(am, [am, gone]);
    expect((w.start, w.end), (0, 1440));
  });
}
