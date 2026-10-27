import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/mode_moves.dart';

void main() {
  DailySchedule sched(String date, List<ScheduleBlock> blocks) => DailySchedule(date: date, generatedBy: 'claude', generatedAt: DateTime(2026, 10, 1), blocks: blocks);

  test('deep work = bloc choisi (kind deepwork) couvert ≥ 60 min par un chrono de la même source ; un chrono long seul ne compte pas', () {
    final dw = ScheduleBlock(id: 'dw', startTime: '09:00', durationMin: 90, title: 'Deep work · Livre', category: 'project', kind: 'deepwork', projectId: 'livre', taskId: 't1', activityId: 'ecrire');
    final dwAct = ScheduleBlock(id: 'dw2', startTime: '14:00', durationMin: 90, title: 'Deep work · Lire', category: 'personal', kind: 'deepwork', activityId: 'lire');
    final normal = ScheduleBlock(id: 'n', startTime: '16:00', durationMin: 120, title: 'Séance', category: 'project', taskId: 't9');
    final schedules = [sched('2026-10-20', [dw, dwAct, normal])];
    final s = [
      Session(activityId: 'ecrire', taskId: 't1', startAt: DateTime(2026, 10, 20, 9, 5), endAt: DateTime(2026, 10, 20, 10, 20)), // 75 min dans le bloc → compte
      Session(activityId: 'lire', startAt: DateTime(2026, 10, 20, 14), endAt: DateTime(2026, 10, 20, 14, 45)), // 45 min → non
      Session(activityId: 'bois', taskId: 't9', startAt: DateTime(2026, 10, 20, 16), endAt: DateTime(2026, 10, 20, 18)), // 2 h sur un bloc normal → non
      Session(activityId: 'sommeil', startAt: DateTime(2026, 10, 20, 22), endAt: DateTime(2026, 10, 21, 5)), // 7 h sans bloc → non
      Session(activityId: 'ecrire', taskId: 't1', startAt: DateTime(2026, 10, 20, 9), endAt: DateTime(2026, 10, 20, 10, 30))..deleted = true,
    ];
    expect(deepWorkSessions(s, schedules), [DateTime(2026, 10, 20, 10, 20)]);
    final deck = computeBadges(activities: const [], habitHits: const [], schedules: schedules, projects: const [], objectives: const [], sessions: s, now: DateTime(2026, 10, 27));
    final b = deck.byId('deep-work')!;
    expect(b.value, 1);
    expect(b.level, 0);
    expect(b.nextTarget, 3);
    expect(deepWorkSessions(s, const []), isEmpty); // sans bloc de deep work, rien
  });

  test('le bloc créé par « Deep work 90 min » porte kind deepwork', () {
    const c = DeepWorkCandidate(kind: 'project', title: 'Livre', subtitle: '', projectId: 'livre', taskId: 't1');
    expect(deepWorkBlock(c, DateTime(2026, 10, 27, 14)).kind, 'deepwork');
  });
}
