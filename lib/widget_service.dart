// widget_service.dart — pousse les données vers les widgets iOS home screen
// Utilise home_widget + App Group "group.com.madabinghy.productivitwo"

import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:productivitwo_v1/app_logic.dart';

const _kAppGroup = 'group.com.madabinghy.productivitwo';

/// Résultat du dernier appel à WidgetService.update — visible dans l'UI de debug.
class WidgetDiag {
  final int routinesDone;
  final int routinesTotal;
  final int ganttCount;
  final String? error;
  final DateTime ts;

  WidgetDiag({
    required this.routinesDone,
    required this.routinesTotal,
    required this.ganttCount,
    this.error,
    required this.ts,
  });

  @override
  String toString() {
    if (error != null) return '❌ $error';
    return '✅ routines $routinesDone/$routinesTotal · gantt $ganttCount · ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}';
  }
}

class WidgetService {
  WidgetService._();

  static WidgetDiag? lastDiag;

  /// Pousse l'état courant vers tous les widgets home screen.
  /// Appelé depuis _saveAndRefresh(), au chargement initial, et sur le stream projets.
  static Future<void> update(AppLogic logic) async {
    if (!Platform.isIOS) return;

    try {
      await HomeWidget.setAppGroupId(_kAppGroup);

      // --- Routines : done / total pour la période en cours ---
      final routineItems = logic.routineProgressItemsForCurrentPeriod();
      final int routinesDone =
          routineItems.where((it) => it.done >= it.target).length;
      final int routinesTotal = routineItems.length;

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
        HomeWidget.saveWidgetData<String>('gantt_json', jsonEncode(ganttTasks)),
      ]);

      await HomeWidget.updateWidget(
        iOSName: 'ProductivitwoWidget',
        androidName: 'ProductivitwoWidget',
        qualifiedAndroidName:
            'com.madabinghy.productivitwo.ProductivitwoWidget',
      );

      lastDiag = WidgetDiag(
        routinesDone: routinesDone,
        routinesTotal: routinesTotal,
        ganttCount: ganttTasks.length,
        ts: DateTime.now(),
      );
    } catch (e) {
      lastDiag = WidgetDiag(
        routinesDone: 0,
        routinesTotal: 0,
        ganttCount: 0,
        error: e.toString(),
        ts: DateTime.now(),
      );
    }
  }
}
