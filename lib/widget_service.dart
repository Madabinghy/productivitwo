// widget_service.dart — pousse les données vers les widgets iOS home screen
// Utilise home_widget + App Group "group.com.madabinghy.productivitwo"

import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

const _kAppGroup = 'group.com.madabinghy.productivitwo';

class WidgetService {
  WidgetService._();

  /// Appelé depuis _saveAndRefresh() et au chargement initial.
  static Future<void> update(AppLogic logic) async {
    if (!Platform.isIOS) return;

    try {
      await HomeWidget.setAppGroupId(_kAppGroup);

      // --- Routines : done / total pour la période en cours ---
      final routineItems = logic.routineProgressItemsForCurrentPeriod();
      final int routinesDone =
          routineItems.where((it) => it.done >= it.target).length;
      final int routinesTotal = routineItems.length;

      // --- Plan du jour : 4 premières actions non-archivées ---
      final today = _todayYmd();
      final planItems = logic.state.dayPlan
          .where((it) =>
              it.yyyymmdd == today &&
              !it.archived &&
              it.status != ActionStatus.archived)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      final top4 = planItems.take(4).map((it) => {
            'title': it.title,
            'done': it.done,
          }).toList();

      // --- Tâches Gantt actives (projets non archivés, tâches non terminées) ---
      final ganttTasks = <Map<String, dynamic>>[];
      for (final project in logic.currentProjects) {
        if (project.status == 'archived' || project.status == 'done') continue;
        for (final task in project.tasks) {
          if (task.status == 'done' || task.status == 'skipped') continue;
          ganttTasks.add({
            'project': project.title,
            'task': task.title,
            'done': task.stepsDone,
            'total': task.stepsTotal,
          });
          if (ganttTasks.length >= 12) break;
        }
        if (ganttTasks.length >= 12) break;
      }

      // --- Écriture UserDefaults via App Group ---
      await Future.wait([
        HomeWidget.saveWidgetData<int>('routines_done', routinesDone),
        HomeWidget.saveWidgetData<int>('routines_total', routinesTotal),
        HomeWidget.saveWidgetData<String>('plan_json', jsonEncode(top4)),
        HomeWidget.saveWidgetData<String>('gantt_json', jsonEncode(ganttTasks)),
      ]);

      await HomeWidget.updateWidget(
        iOSName: 'ProductivitwoWidget',
        androidName: 'ProductivitwoWidget',
        qualifiedAndroidName:
            'com.madabinghy.productivitwo.ProductivitwoWidget',
      );
    } catch (_) {
      // Le widget n'est pas installé ou l'App Group n'est pas encore configuré —
      // on avale silencieusement pour ne pas crasher l'app.
    }
  }

  static String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}
