// widget_service.dart — pousse les données vers les widgets iOS home screen
// Écriture directe via Method Channel vers UserDefaults(suiteName:) côté Swift.
// On bypass home_widget pour les écritures car le plugin peut écrire dans la
// mauvaise suite sur certaines configs iOS. home_widget reste utilisé pour
// Android.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

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

      // --- Routines (liste + couleur domaine, pour le "reste à faire") ---
      final routinesJson = jsonEncode(routineItems
          .map((it) => {
                'label': it.label,
                'done': it.done,
                'target': it.target,
                'color': _hex(
                    domainColor(it.activity.domainId, logic.state.activeDomains)),
              })
          .toList());

      // --- Projets actifs (id + titre + progression + couleur, navigables) ---
      final projectsJson = jsonEncode(logic.currentProjects
          .where((p) => p.status != 'archived' && p.status != 'done')
          .map((p) {
        final tasks = p.tasks.where((t) => t.status != 'skipped').toList();
        return {
          'id': p.id,
          'title': p.title,
          'done': tasks.fold<int>(0, (s, t) => s + t.stepsDone),
          'total': tasks.fold<int>(0, (s, t) => s + t.stepsTotal),
          'color': _hex(domainColor(p.domainId, logic.state.activeDomains)),
        };
      }).toList());

      // --- Programme du jour (blocs horaires depuis Firestore) ---
      final now = DateTime.now();
      final todayStr =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      String scheduleJson = '[]';
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final doc = await FirebaseFirestore.instance
              .doc('users/$uid/daily_schedules/$todayStr')
              .get();
          final data = doc.data();
          if (data != null) {
            final sched = DailySchedule.from(data);
            scheduleJson = jsonEncode(sched.blocks
                .where((b) => b.status != 'deleted')
                .map((b) => {
                      'time': b.startTime,
                      'title': b.title,
                      'cat': b.category,
                      'status': b.status,
                    })
                .toList());
          }
        }
      } catch (_) {}

      if (Platform.isIOS) {
        // Écriture directe via Method Channel — UserDefaults(suiteName:) côté Swift
        await Future.wait([
          _kIosWidgetChannel.invokeMethod('setInt', {'key': 'routines_done', 'value': routinesDone}),
          _kIosWidgetChannel.invokeMethod('setInt', {'key': 'routines_total', 'value': routinesTotal}),
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'gantt_json', 'value': ganttJson}),
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'routines_json', 'value': routinesJson}),
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'projects_json', 'value': projectsJson}),
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'schedule_json', 'value': scheduleJson}),
        ]);
        await _kIosWidgetChannel.invokeMethod('reload');
      } else {
        // Android : home_widget toujours utilisé
        await HomeWidget.setAppGroupId(_kAppGroup);
        await Future.wait([
          HomeWidget.saveWidgetData<int>('routines_done', routinesDone),
          HomeWidget.saveWidgetData<int>('routines_total', routinesTotal),
          HomeWidget.saveWidgetData<String>('gantt_json', ganttJson),
          HomeWidget.saveWidgetData<String>('routines_json', routinesJson),
          HomeWidget.saveWidgetData<String>('projects_json', projectsJson),
          HomeWidget.saveWidgetData<String>('schedule_json', scheduleJson),
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

  // Couleur Flutter → "#RRGGBB" (ou null).
  static String? _hex(Color? c) => c == null
      ? null
      : '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}
