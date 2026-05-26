import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:productivitwo_v1/models.dart';

// ── Modèles ───────────────────────────────────────────────────────────────────

class AssistantMessageData {
  final String id;
  final String text;
  final String characterName;
  final int priority;
  final AssistantActionData? action;

  const AssistantMessageData({
    required this.id,
    required this.text,
    required this.characterName,
    required this.priority,
    this.action,
  });
}

class AssistantActionData {
  final String type;
  final String? label;
  final Map<String, dynamic>? payload;

  const AssistantActionData({
    required this.type,
    this.label,
    this.payload,
  });
}

// ── Moteur ────────────────────────────────────────────────────────────────────

class AssistantEngine {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // Les fallbacks ne s'affichent qu'une fois par session (évite la répétition à chaque refresh)
  static bool _fallbackShownThisSession = false;

  /// Évalue les messages en attente pour aujourd'hui.
  /// Si Firestore est vide, génère des messages fallback autonomes.
  /// Appelé une fois au chargement de la page web.
  static Future<List<AssistantMessageData>> evaluate({
    required List<Project> projects,
    List<Domain> domains = const [],
  }) async {
    final uid = _uid;
    if (uid == null) return [];

    final today = DateTime.now();
    final todayStr = _isoDate(today);

    final snap = await _db
        .collection('users/$uid/assistant_messages')
        .where('status', isEqualTo: 'pending')
        .get();

    // Aucun message Claude → fallbacks autonomes
    if (snap.docs.isEmpty) {
      if (_fallbackShownThisSession) return [];
      final fallbacks = _buildFallbacks(
        projects: projects,
        today: today,
      );
      if (fallbacks.isNotEmpty) {
        _fallbackShownThisSession = true;
        // Persister en Firestore pour qu'ils apparaissent dans l'historique
        for (final msg in fallbacks) {
          _db.collection('users/$uid/assistant_messages').doc('${todayStr}_${msg.id}').set({
            'id': '${todayStr}_${msg.id}',
            'targetDate': todayStr,
            'text': msg.text,
            'characterName': msg.characterName,
            'condition': {'type': 'always'},
            'priority': msg.priority,
            'status': 'shown',
            'createdBy': 'fallback',
            'createdAt': FieldValue.serverTimestamp(),
            'shownAt': FieldValue.serverTimestamp(),
            'expiresAfterDays': 1,
            'action': msg.action != null ? {
              'type': msg.action!.type,
              'label': msg.action!.label,
              'payload': msg.action!.payload,
            } : null,
          }, SetOptions(merge: true));
        }
      }
      return fallbacks;
    }

    // Chargement lazy des données supplémentaires si nécessaire
    final conditionTypes = snap.docs
        .map((d) => ((d.data()['condition'] as Map?)?.cast<String, dynamic>() ?? {})['type'] as String? ?? '')
        .toSet();

    List<Map<String, dynamic>>? goalsCache;
    List<Map<String, dynamic>>? sessionsCache;
    List<Map<String, dynamic>>? habitHitsCache;
    List<Map<String, dynamic>>? activitiesCache;

    await Future.wait([
      if (conditionTypes.any(_needsGoals))
        _fetchGoals(uid).then((v) => goalsCache = v),
      if (conditionTypes.any(_needsSessions))
        _fetchRecentSessions(uid, today).then((v) => sessionsCache = v),
      if (conditionTypes.any(_needsHabitHits))
        _fetchRecentHabitHits(uid, today).then((v) => habitHitsCache = v),
      if (conditionTypes.any(_needsActivities))
        _fetchActivities(uid).then((v) => activitiesCache = v),
    ]);

    final results = <AssistantMessageData>[];

    for (final doc in snap.docs) {
      final data = doc.data();
      final targetDate = data['targetDate'] as String?;
      if (targetDate == null) continue;
      if (targetDate.compareTo(todayStr) > 0) continue; // pas encore

      // Expiration
      final expiresAfterDays = (data['expiresAfterDays'] as num?)?.toInt() ?? 2;
      final targetDt = DateTime.tryParse(targetDate);
      if (targetDt == null) continue;
      if (today.isAfter(targetDt.add(Duration(days: expiresAfterDays)))) {
        doc.reference.update({'status': 'expired'});
        continue;
      }

      final condition = (data['condition'] as Map?)?.cast<String, dynamic>();
      if (condition == null) continue;

      final met = _evaluate(
        condition: condition,
        projects: projects,
        domains: domains,
        today: today,
        goals: goalsCache,
        sessions: sessionsCache,
        habitHits: habitHitsCache,
        activities: activitiesCache,
      );
      if (!met) continue;

      doc.reference.update({
        'status': 'shown',
        'shownAt': FieldValue.serverTimestamp(),
      });

      results.add(AssistantMessageData(
        id: data['id'] as String? ?? doc.id,
        text: data['text'] as String? ?? '',
        characterName: data['characterName'] as String? ?? 'ORION',
        priority: (data['priority'] as num?)?.toInt() ?? 1,
        action: _parseAction(data['action']),
      ));
    }

    results.sort((a, b) => a.priority.compareTo(b.priority));
    return results;
  }

  // ── Messages fallback (sans Claude) ──────────────────────────────────────

  static List<AssistantMessageData> _buildFallbacks({
    required List<Project> projects,
    required DateTime today,
  }) {
    final messages = <AssistantMessageData>[];
    final todayD = DateTime(today.year, today.month, today.day);

    // Deadline dans les 3 prochains jours (priorité max)
    for (final p in projects) {
      if (p.endDate == null || p.status == 'archived') continue;
      final diff = p.endDate!.difference(todayD).inDays;
      if (diff >= 0 && diff <= 3) {
        final label = diff == 0
            ? 'Aujourd\'hui est la deadline de "${p.title}".'
            : 'La deadline de "${p.title}" est dans $diff jour${diff > 1 ? 's' : ''}.';
        messages.add(AssistantMessageData(
          id: 'fallback_deadline_${p.id}',
          text: label,
          characterName: 'ORION',
          priority: 1,
          action: AssistantActionData(
            type: 'open_project',
            label: 'Voir le projet',
            payload: {'projectId': p.id},
          ),
        ));
      }
    }

    // Jalons aujourd'hui
    for (final p in projects) {
      for (final t in p.tasks) {
        if (!t.isMilestone || t.status == 'done') continue;
        final ms = DateTime(t.startDate.year, t.startDate.month, t.startDate.day);
        if (ms == todayD) {
          messages.add(AssistantMessageData(
            id: 'fallback_milestone_${t.id}',
            text: 'Jalon aujourd\'hui sur "${p.title}" : ${t.title}.',
            characterName: 'ORION',
            priority: 1,
            action: AssistantActionData(
              type: 'open_project',
              label: 'Voir le projet',
              payload: {'projectId': p.id},
            ),
          ));
        }
      }
    }

    // Tâches en retard
    final overdueCount = _countOverdueTasks(projects, todayD);
    if (overdueCount > 0) {
      messages.add(AssistantMessageData(
        id: 'fallback_overdue',
        text: overdueCount == 1
            ? 'Tu as 1 tâche Gantt en retard. Un œil dessus ?'
            : 'Tu as $overdueCount tâches Gantt en retard. Un tri s\'impose.',
        characterName: 'ORION',
        priority: 2,
        action: const AssistantActionData(type: 'open_day_plan', label: 'Voir le focus'),
      ));
    }


    // Message de début de semaine
    if (today.weekday == DateTime.monday && messages.isEmpty) {
      messages.add(const AssistantMessageData(
        id: 'fallback_week_start',
        text: 'Nouvelle semaine. Prends 5 minutes pour aligner tes priorités avant de te lancer.',
        characterName: 'ORION',
        priority: 4,
      ));
    }

    // Message de fin de semaine
    if (today.weekday == DateTime.friday && messages.isEmpty) {
      messages.add(const AssistantMessageData(
        id: 'fallback_week_end',
        text: 'C\'est vendredi. Bon moment pour faire le bilan de la semaine.',
        characterName: 'ORION',
        priority: 4,
      ));
    }

    messages.sort((a, b) => a.priority.compareTo(b.priority));
    return messages;
  }

  // ── Évaluation d'une condition ─────────────────────────────────────────────

  static bool _evaluate({
    required Map<String, dynamic> condition,
    required List<Project> projects,
    required List<Domain> domains,
    required DateTime today,
    List<Map<String, dynamic>>? goals,
    List<Map<String, dynamic>>? sessions,
    List<Map<String, dynamic>>? habitHits,
    List<Map<String, dynamic>>? activities,
  }) {
    final type = condition['type'] as String? ?? '';
    final todayD = DateTime(today.year, today.month, today.day);

    switch (type) {

      // ── Conditions temporelles (aucune donnée requise) ────────────────────

      case 'always':
        return true;

      case 'week_start':
        return today.weekday == DateTime.monday;

      case 'week_end':
        return today.weekday == DateTime.friday || today.weekday == DateTime.sunday;

      case 'custom_date':
        final date = condition['date'] as String?;
        return date != null && date == _isoDate(today);

      case 'first_open_of_day':
        // Le moteur est appelé au chargement — toujours vrai
        return true;

      // ── Conditions projets ────────────────────────────────────────────────

      case 'overdue_count':
        final min = (condition['min'] as num?)?.toInt() ?? 1;
        final count = _countOverdueTasks(projects, todayD);
        return count >= min;

      case 'project_deadline_near':
        final projectId = condition['projectId'] as String?;
        final daysBefore = (condition['daysBefore'] as num?)?.toInt() ?? 3;
        if (projectId == null) return false;
        final p = projects.where((p) => p.id == projectId).firstOrNull;
        if (p == null || p.endDate == null) return false;
        final diff = p.endDate!.difference(todayD).inDays;
        return diff >= 0 && diff <= daysBefore;

      case 'project_milestone_today':
        final projectId = condition['projectId'] as String?;
        if (projectId == null) return false;
        final p = projects.where((p) => p.id == projectId).firstOrNull;
        if (p == null) return false;
        return p.tasks.any((t) =>
            t.isMilestone &&
            t.status != 'done' &&
            DateTime(t.startDate.year, t.startDate.month, t.startDate.day) == todayD);

      case 'project_inactive_days':
        final projectId = condition['projectId'] as String?;
        final days = (condition['days'] as num?)?.toInt() ?? 7;
        if (projectId == null) return false;
        final p = projects.where((p) => p.id == projectId).firstOrNull;
        if (p == null) return false;
        // Approx : aucune tâche done après (today - days)
        final cutoff = todayD.subtract(Duration(days: days));
        // On ne peut pas savoir quand une tâche a été passée en done sans timestamps.
        // Fallback : si aucune tâche n'est done et que le projet a démarré depuis > N jours.
        final doneTasks = p.tasks.where((t) => t.status == 'done').length;
        final started = p.startDate.isBefore(cutoff);
        return started && doneTasks == 0;

      // ── Conditions plan journalier (non utilisées — dayPlan supprimé) ───────

      case 'day_plan_empty':
      case 'day_plan_overloaded':
      case 'no_now_focus':
        return false;

      case 'inbox_overflow':
        // Non implémenté — inbox dans collection séparée (captures)
        return false;

      // ── Conditions objectifs ──────────────────────────────────────────────

      case 'goal_near_deadline':
        final goalId = condition['goalId'] as String?;
        final daysBefore = (condition['daysBefore'] as num?)?.toInt() ?? 3;
        if (goalId == null || goals == null) return false;
        final goal = goals.where((g) => g['id'] == goalId).firstOrNull;
        if (goal == null) return false;
        final dueDateStr = goal['dueDate'] as String?;
        if (dueDateStr == null) return false;
        final dueDate = DateTime.tryParse(dueDateStr);
        if (dueDate == null) return false;
        final diff = dueDate.difference(todayD).inDays;
        return diff >= 0 && diff <= daysBefore;

      case 'goal_undone_actions':
        final activityId = condition['activityId'] as String?;
        final min = (condition['min'] as num?)?.toInt() ?? 1;
        if (goals == null) return false;
        int undone = 0;
        for (final g in goals) {
          if (activityId != null && g['activityId'] != activityId) continue;
          final actions = (g['actions'] as List?) ?? [];
          undone += actions.where((a) => a['done'] != true).length;
        }
        return undone >= min;

      // ── Conditions activités (sessions) ──────────────────────────────────

      case 'no_activity_logged_today':
        if (sessions == null) return false;
        final todayStart = todayD.toIso8601String();
        return !sessions.any((s) {
          final start = s['startAt'] as String?;
          return start != null && start.compareTo(todayStart) >= 0;
        });

      case 'activity_behind_target':
        final actId = condition['activityId'] as String?;
        if (actId == null || sessions == null || activities == null) return false;
        final act = activities.where((a) => a['id'] == actId && a['deleted'] != true).firstOrNull;
        if (act == null) return false;
        final goalMin = (act['goalMin'] as num?)?.toDouble() ?? 0;
        if (goalMin <= 0) return false;
        // Progression attendue jusqu'à aujourd'hui dans la semaine (1=Lun..7=Dim)
        final expectedMin = goalMin * today.weekday;
        // Lundi de cette semaine
        final weekStart = todayD.subtract(Duration(days: today.weekday - 1));
        double loggedMin = 0;
        for (final s in sessions) {
          if (s['activityId'] != actId) continue;
          final start = s['startAt'] as String?;
          final end   = s['endAt']   as String?;
          if (start == null || end == null) continue;
          if (start.compareTo(weekStart.toIso8601String()) < 0) continue;
          final startDt = DateTime.tryParse(start);
          final endDt   = DateTime.tryParse(end);
          if (startDt == null || endDt == null) continue;
          loggedMin += endDt.difference(startDt).inSeconds / 60.0;
        }
        return loggedMin < expectedMin * 0.7;

      case 'activity_streak':
        final actId2 = condition['activityId'] as String?;
        final minDays = (condition['minDays'] as num?)?.toInt() ?? 3;
        if (actId2 == null || sessions == null) return false;
        int streak = 0;
        for (int i = 1; i <= 30; i++) {
          final day = todayD.subtract(Duration(days: i));
          final dayStr = _isoDate(day);
          final nextStr = _isoDate(day.add(const Duration(days: 1)));
          final hasSession = sessions.any((s) {
            if (s['activityId'] != actId2) return false;
            final start = s['startAt'] as String?;
            return start != null && start.compareTo(dayStr) >= 0 && start.compareTo(nextStr) < 0;
          });
          if (hasSession) { streak++; } else { break; }
        }
        return streak >= minDays;

      // ── Conditions habitudes (habitHits) ──────────────────────────────────

      case 'habit_streak_broken':
        final habitId = condition['habitId'] as String?;
        if (habitId == null || habitHits == null) return false;
        final yesterday    = todayD.subtract(const Duration(days: 1));
        final dayBefore    = todayD.subtract(const Duration(days: 2));
        final yStr  = _isoDate(yesterday);
        final dbStr = _isoDate(dayBefore);
        bool hadHitDayBefore = false;
        bool hadHitYesterday = false;
        for (final h in habitHits) {
          if (h['habitId'] != habitId) continue;
          final ts = _hitDate(h['ts']);
          if (ts == null) continue;
          final tsStr = _isoDate(ts);
          if (tsStr == dbStr) hadHitDayBefore = true;
          if (tsStr == yStr)  hadHitYesterday = true;
        }
        // Streak rompue : avait un hit avant-hier mais pas hier
        return hadHitDayBefore && !hadHitYesterday;

      case 'routine_completion_low':
        final maxPercent = (condition['maxPercent'] as num?)?.toDouble() ?? 50;
        if (habitHits == null || activities == null) return false;
        final habits = activities.where((a) =>
            a['deleted'] != true &&
            (a['type'] == 'habit' || a['habitFreq'] != null)).toList();
        if (habits.isEmpty) return false;
        for (final habit in habits) {
          final hId = habit['id'] as String?;
          if (hId == null) continue;
          final freq   = (habit['habitFreq']   as num?)?.toInt() ?? 0;
          final target = (habit['habitTarget'] as num?)?.toDouble() ?? 1;
          // Cible sur 7 jours selon fréquence (0=daily, 1=weekly, 2=monthly)
          final expected = switch (freq) {
            1 => target,                      // hebdo
            2 => target * 7 / 30,             // mensuel → approx 7j
            _ => target * 7,                  // daily
          };
          if (expected <= 0) continue;
          final hits = habitHits.where((h) => h['habitId'] == hId).length;
          if (hits / expected * 100 < maxPercent) return true;
        }
        return false;

      default:
        return false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static int _countOverdueTasks(List<Project> projects, DateTime todayD) {
    int count = 0;
    for (final p in projects) {
      for (final t in p.tasks) {
        if (t.endDate != null &&
            t.endDate!.isBefore(todayD) &&
            t.status != 'done' &&
            t.status != 'skipped') {
          count++;
        }
      }
    }
    return count;
  }

  static bool _needsGoals(String type) => const {
    'goal_near_deadline', 'goal_undone_actions',
  }.contains(type);

  static bool _needsSessions(String type) => const {
    'activity_behind_target', 'no_activity_logged_today', 'activity_streak',
  }.contains(type);

  static bool _needsHabitHits(String type) => const {
    'habit_streak_broken', 'routine_completion_low',
  }.contains(type);

  static bool _needsActivities(String type) => const {
    'activity_behind_target', 'routine_completion_low',
  }.contains(type);

  static Future<List<Map<String, dynamic>>> _fetchRecentSessions(
      String uid, DateTime today) async {
    final since = today.subtract(const Duration(days: 30)).toIso8601String();
    final snap = await _db
        .collection('users/$uid/sessions')
        .where('startAt', isGreaterThanOrEqualTo: since)
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  static Future<List<Map<String, dynamic>>> _fetchRecentHabitHits(
      String uid, DateTime today) async {
    final since = today.subtract(const Duration(days: 7));
    final snap = await _db
        .collection('users/$uid/habitHits')
        .where('ts', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  static Future<List<Map<String, dynamic>>> _fetchActivities(String uid) async {
    final snap = await _db.collection('users/$uid/activities').get();
    return snap.docs.map((d) => d.data()).toList();
  }

  // Convertit un champ ts (Timestamp ou String) en DateTime
  static DateTime? _hitDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static Future<List<Map<String, dynamic>>> _fetchGoals(String uid) async {
    final snap = await _db
        .collection('users/$uid/goals')
        .where('status', isEqualTo: 'active')
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  static AssistantActionData? _parseAction(dynamic raw) {
    if (raw == null) return null;
    final m = (raw as Map).cast<String, dynamic>();
    return AssistantActionData(
      type: m['type'] as String? ?? '',
      label: m['label'] as String?,
      payload: (m['payload'] as Map?)?.cast<String, dynamic>(),
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
