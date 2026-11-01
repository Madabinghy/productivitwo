import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/projects_today.dart';

void main() {
  test('pour aujourd’hui : parole, programme, visées, un retard par projet', () {
    final today = DateTime(2026, 11, 2);
    final late1 = TaskAction(title: 'Corriger les copies')..dueDate = DateTime(2026, 10, 30);
    final late2 = TaskAction(title: 'Imprimer')..dueDate = DateTime(2026, 10, 31);
    final focus = TaskAction(title: 'Maquette')..focusDate = today;
    final pledged = TaskAction(title: 'Préparer la séance');
    final p = Project(title: '5e', createdBy: 'u', startDate: DateTime(2026, 9, 1), endDate: DateTime(2027, 6, 30), tasks: [
      ProjectTask(title: 'Éval', startDate: DateTime(2026, 9, 1), endDate: DateTime(2026, 11, 30), actions: [late1, late2, focus, pledged]),
    ]);
    final own = TaskAction(title: 'Nettoyer le frigo')..focusDate = today;
    final act = Activity(id: 'n', domainId: 'd', name: 'Nettoyer', role: ActivityRole.generic, type: 'time', goalMin: 0, createdAt: DateTime(2026))..ownActions.add(own);
    final list = todayActions(projects: [p], activities: [act], today: today, paroleIds: {pledged.id});
    expect(list.map((x) => x.action.title), ['Préparer la séance', 'Maquette', 'Nettoyer le frigo', 'Corriger les copies']);
    expect(list.last.reason, TodayReason.late);
    expect(looseActions([act]).single.$2.title, 'Nettoyer le frigo');
  });
}
