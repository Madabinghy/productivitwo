import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/dashboard_tiles.dart';

void main() {
  ScheduleBlock b(String id, String start, int dur) => ScheduleBlock(id: id, startTime: start, durationMin: dur, title: id);
  test('trait « maintenant » sur la bande du programme', () {
    final blocks = [b('a', '09:00', 60), b('b', '11:00', 60)];
    expect(stripNowAt(blocks, 8 * 60), isNull); // avant le premier bloc
    expect(stripNowAt(blocks, 9 * 60 + 30), closeTo(.25, .001)); // milieu du 1er
    expect(stripNowAt(blocks, 10 * 60 + 30), closeTo(.5, .001)); // entre les deux
    expect(stripNowAt(blocks, 13 * 60), isNull); // après le dernier
  });
}
