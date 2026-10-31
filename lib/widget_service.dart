// widget_service.dart — pousse les données vers les widgets iOS home screen
// Écriture directe via Method Channel vers UserDefaults(suiteName:) côté Swift.
// On bypass home_widget pour les écritures car le plugin peut écrire dans la
// mauvaise suite sur certaines configs iOS. home_widget reste utilisé pour
// Android.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFocusedOn;
import 'package:productivitwo_v1/utils/dashboard_tiles.dart' show perfectDayTile;
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/embers.dart' show kEmberCap;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDayBlocks;
import 'package:productivitwo_v1/utils/mode.dart' show kModeLabels;
import 'package:productivitwo_v1/utils/progress_bricks.dart' show projectBricks;
import 'package:productivitwo_v1/utils/project_moment.dart' show rankProjectMoments;
import 'package:productivitwo_v1/utils/routine_moments.dart' show buildRoutineDay;
import 'package:productivitwo_v1/utils/widget_payload.dart';

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
  /// Posé par l'écran racine : faits du jour vécu (journée parfaite, Montre suisse…).
  static BadgeCenter? badges;
  static bool _authProvisioned = false;

  /// Écrit (une fois par session) uid + token API dans l'App Group pour que les
  /// widgets actionnables puissent appeler mcpHandler. Sans secret brut local
  /// (réinstall / nouvel appareil), on n'écrit rien — le widget reste lecture seule.
  static Future<void> provisionAuth(FirestoreSync sync) async {
    if (kIsWeb) return; // web : pas de widgets natifs (Platform.* crasherait)
    if (_authProvisioned) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final token = await sync.ensureWidgetToken();
      final raw = token.rawToken;
      if (raw == null || raw.isEmpty) return;
      if (Platform.isIOS) {
        await _kIosWidgetChannel
            .invokeMethod('setString', {'key': 'mcp_uid', 'value': uid});
        await _kIosWidgetChannel
            .invokeMethod('setString', {'key': 'mcp_token', 'value': raw});
      } else {
        await HomeWidget.setAppGroupId(_kAppGroup);
        await HomeWidget.saveWidgetData<String>('mcp_uid', uid);
        await HomeWidget.saveWidgetData<String>('mcp_token', raw);
      }
      _authProvisioned = true;
    } catch (_) {}
  }

  /// Pousse l'état courant vers tous les widgets home screen.
  /// Appelé depuis _saveAndRefresh(), au chargement initial, et sur le stream projets.
  static Future<void> update(AppLogic logic) async {
    if (kIsWeb) return; // web : pas de widgets natifs (Platform.* crasherait)
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
                'id': it.activity.id,
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

      // --- Tâche du haut (widget Tâche actionnable) ---
      // Première tâche non terminée du premier projet actif.
      String focusTaskJson = 'null';
      for (final p in logic.currentProjects) {
        if (p.status == 'archived' || p.status == 'done') continue;
        ProjectTask? task;
        for (final t in p.tasks) {
          if (t.status != 'done' && t.status != 'skipped') {
            task = t;
            break;
          }
        }
        if (task == null) continue;
        focusTaskJson = jsonEncode({
          'projectId': p.id,
          'taskId': task.id,
          'projectTitle': p.title,
          'title': task.title,
          'actions': task.actions
              .take(8)
              .map((a) => {'id': a.id, 'title': a.title, 'done': a.done})
              .toList(),
        });
        break;
      }

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
                      'id': b.id,
                      'time': b.startTime,
                      'title': b.title,
                      'cat': b.category,
                      'status': b.status,
                    })
                .toList());
          }
        }
      } catch (_) {}

      final todayJson = await _todayJson(logic);

      if (Platform.isIOS) {
        // Écriture directe via Method Channel — UserDefaults(suiteName:) côté Swift
        await Future.wait([
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'today_json', 'value': todayJson}),
          _kIosWidgetChannel.invokeMethod('setInt', {'key': 'routines_done', 'value': routinesDone}),
          _kIosWidgetChannel.invokeMethod('setInt', {'key': 'routines_total', 'value': routinesTotal}),
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'gantt_json', 'value': ganttJson}),
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'routines_json', 'value': routinesJson}),
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'projects_json', 'value': projectsJson}),
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'schedule_json', 'value': scheduleJson}),
          _kIosWidgetChannel.invokeMethod('setString', {'key': 'focus_task_json', 'value': focusTaskJson}),
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
          HomeWidget.saveWidgetData<String>('focus_task_json', focusTaskJson),
          HomeWidget.saveWidgetData<String>('today_json', todayJson),
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

  /// Widgets revus (2026-10-31) : tout ce que l'écran d'accueil montre, calculé
  /// avec la même logique que l'app, sur la journée vécue. Une clé, un JSON.
  static Future<String> _todayJson(AppLogic logic) async {
    final now = DateTime.now();
    final lived = logic.livedToday;
    final ymd = logic.livedTodayYmd;
    final next = DateTime(lived.year, lived.month, lived.day + 1);
    final nextYmd = '${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
    final out = <String, dynamic>{'ymd': ymd, 'at': now.millisecondsSinceEpoch};

    // Programme de la journée vécue (nuit après minuit comprise).
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        Future<DailySchedule?> read(String d) async {
          final snap = await FirebaseFirestore.instance.doc('users/$uid/daily_schedules/$d').get();
          final data = snap.data();
          return data == null ? null : DailySchedule.from(data);
        }

        final day = await read(ymd);
        final nxt = await read(nextYmd);
        final blocks = livedDayBlocks(day, nxt, logic.dayStartMin)
            .where((b) => b.status == 'pending' || b.status == 'done')
            .where((b) => b.kind != 'prep' && b.kind != 'session')
            .toList()
          ..sort((a, b) => blockStartAt(a, lived).compareTo(blockStartAt(b, lived)));
        out['blocks'] = [
          for (final b in blocks) widgetBlock(b, lived, b.docDate ?? ymd, logic.currentProjects),
        ];
      }
    } catch (_) {}

    // Chrono en cours.
    Session? run;
    for (final s in logic.state.sessions) {
      if (s.endAt != null || s.deleted) continue;
      if (run == null || s.startAt.isAfter(run.startAt)) run = s;
    }
    if (run != null) {
      final a = logic.state.activities.where((x) => x.id == run!.activityId).firstOrNull;
      out['running'] = {'activity': a?.name ?? 'Chrono', 'startMs': run.startAt.millisecondsSinceEpoch};
    }

    // Journée parfaite, braises, mode.
    final bc = badges;
    final facts = bc?.todayFacts();
    final ledger = logic.emberLedgerNow();
    final tile = perfectDayTile(facts, ledger);
    if (facts != null && tile != null) {
      final total = facts.routines.length + facts.countedBlocks.length;
      final done = facts.routinesReached + facts.blocksDone;
      out['perfect'] = {
        'value': tile.value,
        'sub': tile.sub,
        'cells': perfectCells(done, total),
        'done': done,
        'total': total,
      };
    }
    out['embers'] = '${ledger.available} / $kEmberCap';
    out['mode'] = {
      'label': logic.inRecharge ? 'Recharge' : kModeLabels[logic.mode],
      'key': logic.inRecharge ? 'recharge' : logic.mode.name,
      'wins': facts?.disciplineWinsToday ?? 0,
    };

    // Routines du moment : ce qui reste, puis le compte des faites.
    final lymd = logic.livedYmdNow;
    final rd = buildRoutineDay(
      activities: logic.state.activeActivities,
      hits: logic.state.habitHits,
      now: now,
      pushed: logic.routinePushed(lymd),
      deferred: logic.state.nowSkippedByYmd[lymd] ?? const [],
      dismissed: logic.nowDoneSet(lymd),
      dayStartMin: logic.dayStartMin,
      moments: logic.moments,
      exclude: logic.acquiredIds,
    );
    final all = rd.countAll;
    final q = rd.queue;
    out['routines'] = {
      'moment': rd.current.thisOne,
      'done': all.done,
      'total': all.total,
      'later': all.total - all.done - q.length,
      'todo': [
        for (final s in q.take(6))
          {
            'id': s.id,
            'label': s.activity.name,
            'done': s.share?.done ?? s.todo.dayDone,
            'target': s.share?.target ?? s.todo.dayTarget ?? s.todo.weekTarget,
            'series': logic.habitCurrentStreak(s.id),
          },
      ],
    };

    // Actions visées aujourd'hui.
    final focused = <Map<String, dynamic>>[];
    for (final p in logic.currentProjects) {
      if (p.status == 'archived' || p.status == 'done') continue;
      for (final t in p.tasks) {
        for (final a in t.actions) {
          if (isFocusedOn(a, lived)) {
            focused.add({'title': a.title, 'done': a.done, 'projectId': p.id, 'taskId': t.id, 'actionId': a.id});
          }
        }
      }
    }
    for (final act in logic.state.activeActivities) {
      for (final a in act.ownActions) {
        if (isFocusedOn(a, lived)) focused.add({'title': a.title, 'done': a.done, 'activityId': act.id, 'actionId': a.id});
      }
    }
    focused.sort((a, b) => (a['done'] == true ? 1 : 0).compareTo(b['done'] == true ? 1 : 0));
    out['focused'] = {
      'done': focused.where((a) => a['done'] == true).length,
      'total': focused.length,
      'items': focused.take(6).toList(),
    };

    // Montre suisse : activités couvertes sur 7 jours glissants.
    if (facts != null) {
      final pace = facts.pace;
      final behind = pace.where((x) => !x.onPace).toList()..sort((a, b) => b.missingMin.compareTo(a.missingMin));
      out['watch'] = {
        'covered': pace.length - behind.length,
        'total': pace.length,
        'behind': [
          for (final x in behind.take(3))
            {
              'name': x.activity.name,
              'missing': x.missingMin,
              'frac': x.expectedMin > 0 ? (x.doneMin / x.expectedMin).clamp(0.0, 1.0) : 1.0,
            },
        ],
      };
    }

    // Projet du moment : briques et prochaine action.
    final ranked = rankProjectMoments(logic.currentProjects, logic.state.sessions, lived)
        .where((m) => !m.upcoming)
        .toList();
    if (ranked.isNotEmpty) {
      final m = ranked.first;
      final row = projectBricks(m.project, lived);
      out['project'] = {
        'id': m.project.id,
        'title': m.project.title,
        'pill': m.daysToSession != null
            ? (m.daysToSession == 0 ? 'séance aujourd\'hui' : m.daysToSession == 1 ? 'séance demain' : 'séance dans ${m.daysToSession} j')
            : (m.behind ? 'en retard sur le plan' : null),
        'bricks': [for (final b in row.bricks.take(16)) b.state.name],
        'line': '${m.plan.done} / ${m.plan.total} tâches${m.behind ? ' · ${m.plan.expected - m.plan.done} en retard sur le plan' : ''}',
        if (m.next != null) 'next': m.next!.action.title,
      };
    }

    return jsonEncode(out);
  }

  // Couleur Flutter → "#RRGGBB" (ou null).
  static String? _hex(Color? c) => c == null
      ? null
      : '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}
