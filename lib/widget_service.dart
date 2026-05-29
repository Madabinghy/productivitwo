// widget_service.dart — pousse les données vers les widgets iOS home screen
// Écriture directe via Method Channel vers UserDefaults(suiteName:) côté Swift.
// On bypass home_widget pour les écritures car le plugin peut écrire dans la
// mauvaise suite sur certaines configs iOS. home_widget reste utilisé pour
// Android.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:productivitwo_v1/app_logic.dart';

const _kAppGroup = 'group.com.madabinghy.productivitwo';
const _kIosWidgetChannel = MethodChannel('com.madabinghy.productivitwo/widget');

/// Résultat du dernier appel à WidgetService.update — visible dans l'UI de debug.
class WidgetDiag {
  final int routinesDone;
  final int routinesTotal;
  final int ganttCount;
  final int projectsLoaded;
  final String? error;
  final DateTime ts;

  WidgetDiag({
    required this.routinesDone,
    required this.routinesTotal,
    required this.ganttCount,
    required this.projectsLoaded,
    this.error,
    required this.ts,
  });

  @override
  String toString() {
    if (error != null) return '❌ $error';
    final ganttInfo = ganttCount > 0
        ? '$ganttCount tâche(s)'
        : 'aucune tâche active ($projectsLoaded projet(s) chargé(s))';
    return '✅ routines $routinesDone/$routinesTotal · gantt $ganttInfo · ${ts.hour}h${ts.minute.toString().padLeft(2, '0')}';
  }
}

class WidgetService {
  WidgetService._();

  static WidgetDiag? lastDiag;

  /// Pousse l'état courant vers tous les widgets home screen.
  /// Appelé depuis _saveAndRefresh(), au chargement initial, et sur le stream projets.
  static Future<void> update(AppLogic logic) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
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

      final ganttJson = jsonEncode(ganttTasks);

      if (Platform.isIOS) {
        // Écriture directe via Method Channel — UserDefaults(suiteName:) côté Swift
        await Future.wait([
          _kIosWidgetChannel.invokeMethod('setInt', {'key': 'routines_done', 'value': routinesDone}),
          _kIosWidgetChannel.invokeMethod('setInt', {'key': 'routines_total', 'value': routinesTotal}),
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'gantt_json', 'value': ganttJson}),
        ]);
        await _kIosWidgetChannel.invokeMethod('reload');
      } else {
        // Android : home_widget toujours utilisé
        await HomeWidget.setAppGroupId(_kAppGroup);
        await Future.wait([
          HomeWidget.saveWidgetData<int>('routines_done', routinesDone),
          HomeWidget.saveWidgetData<int>('routines_total', routinesTotal),
          HomeWidget.saveWidgetData<String>('gantt_json', ganttJson),
        ]);
        await HomeWidget.updateWidget(
          androidName: 'ProductivitwoWidget',
          qualifiedAndroidName: 'com.madabinghy.productivitwo.ProductivitwoWidget',
        );
      }

      lastDiag = WidgetDiag(
        routinesDone: routinesDone,
        routinesTotal: routinesTotal,
        ganttCount: ganttTasks.length,
        projectsLoaded: logic.currentProjects.length,
        ts: DateTime.now(),
      );
    } catch (e) {
      lastDiag = WidgetDiag(
        routinesDone: 0,
        routinesTotal: 0,
        ganttCount: 0,
        projectsLoaded: 0,
        error: e.toString(),
        ts: DateTime.now(),
      );
    }
  }
}
