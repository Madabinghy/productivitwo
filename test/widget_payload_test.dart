import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/widget_payload.dart';

void main() {
  test('un bloc de la nuit (doc du lendemain) commence le lendemain', () {
    final b = ScheduleBlock(id: 'b', startTime: '00:30', durationMin: 300, title: 'Sommeil', category: 'personal')..dayOffset = 1;
    final m = widgetBlock(b, DateTime(2026, 10, 31), '2026-11-01', const []);
    expect(DateTime.fromMillisecondsSinceEpoch(m['startMs'] as int), DateTime(2026, 11, 1, 0, 30));
    expect(m['end'], '05:30');
    expect(m['doc'], '2026-11-01');
  });

  test('cases de la journée parfaite : 12 au plus, pleines au prorata', () {
    expect(perfectCells(3, 4), [true, true, true, false]);
    expect(perfectCells(12, 24).length, 12);
    expect(perfectCells(12, 24).where((x) => x).length, 6);
    expect(perfectCells(0, 0), isEmpty);
  });
}
