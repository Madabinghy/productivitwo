import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/urge_session.dart';

void main() {
  test('envie en cours : fin à 10 min, temps restant, oubli après 12 h', () {
    final start = DateTime(2026, 11, 4, 15, 33);
    final u = PendingUrge(freedomId: 'f1', startMs: start.millisecondsSinceEpoch, intensity: 3, trigger: 'Fatigue');
    expect(u.endsAt, DateTime(2026, 11, 4, 15, 43));
    expect(u.secondsLeft(DateTime(2026, 11, 4, 15, 40)), 180);
    expect(u.isOver(DateTime(2026, 11, 4, 15, 42, 59)), isFalse);
    expect(u.isOver(DateTime(2026, 11, 4, 15, 43)), isTrue);
    expect(u.secondsLeft(DateTime(2026, 11, 4, 16)), 0);
    expect(u.isStale(DateTime(2026, 11, 5, 3, 34)), isTrue);
    final back = PendingUrge.from(u.copyWith(parade: 'Marcher 5 min').toJson())!;
    expect(back.trigger, 'Fatigue');
    expect(back.parade, 'Marcher 5 min');
    expect(back.copyWith(clearTrigger: true).trigger, isNull);
    expect(PendingUrge.from({'freedomId': 1}), isNull);
  });
}
