import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gamification_flags.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/evening_verdict.dart';
import 'package:productivitwo_v1/widgets/plan_day_screen.dart';

/// Check-in du soir guidé : constat → pourquoi → verdict + pont vers demain.
/// Le « pourquoi » d'un engagement rompu devient un fait tracké (skipReason /
/// dayReason), jamais un souvenir. Verdict déterministe (0 LLM).
Future<void> showDayReviewSheet(
  BuildContext context, {
  required AppLogic logic,
  List<Project> projects = const [],
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DayReviewSheet(logic: logic, projects: projects),
  );
}

class _DayReviewSheet extends StatefulWidget {
  final AppLogic logic;
  final List<Project> projects;
  const _DayReviewSheet({required this.logic, this.projects = const []});

  @override
  State<_DayReviewSheet> createState() => _DayReviewSheetState();
}

class _DayReviewSheetState extends State<_DayReviewSheet> {
  AppLogic get logic => widget.logic;
  AppState get st => logic.state;

  bool _showRoutines = false;
  bool _showDetails = false;

  final _sync = FirestoreSync();
  StreamSubscription<DailySchedule?>? _schedSub;
  DailySchedule? _schedule;
  // La journée VÉCUE : avant 5 h du matin, le check-in clôture encore HIER
  // (fin de soirée des couche-tard — même seuil que la nuit de la carte
  // coach). Sinon à 00:25 on demanderait de clore un samedi vide de 25 min.
  late final DateTime _anchor;
  late final String _todayYmd; // ymd de la journée vécue (= _anchor)

  // ── Flux guidé ─────────────────────────────────────────────────────────────
  int _step = 0; // 0 = constat · 1 = pourquoi · 2 = verdict + pont
  final Map<String, String> _reasons = {}; // blockId → skipReason choisie
  String? _dayReasonChoice; // 3+ rompus → cause globale
  // Blocs des 7 derniers jours (aujourd'hui exclu) — récurrences du verdict.
  List<ScheduleBlock> _weekBlocks = const [];
  int? _plannedCount; // « Poser demain » validé → N blocs (état 9a)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchor = now.hour < 5 ? now.subtract(const Duration(days: 1)) : now;
    _todayYmd =
        '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}-${_anchor.day.toString().padLeft(2, '0')}';
    _schedSub = _sync.streamDailySchedule(_todayYmd).listen((s) {
      if (mounted) setState(() => _schedule = s);
    });
    _loadWeekHistory(_anchor);
  }

  Future<void> _loadWeekHistory(DateTime now) async {
    final all = <ScheduleBlock>[];
    for (var i = 1; i <= 7; i++) {
      final d = now.subtract(Duration(days: i));
      final ymd =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      try {
        final s = await _sync.fetchDailySchedule(ymd);
        all.addAll(
            (s?.blocks ?? const []).where((b) => b.status != 'deleted'));
      } catch (_) {}
    }
    if (mounted) setState(() => _weekBlocks = all);
  }

  @override
  void dispose() {
    _schedSub?.cancel();
    super.dispose();
  }

  // ── Données dérivées ───────────────────────────────────────────────────────

  List<ScheduleBlock> get _liveBlocks =>
      (_schedule?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  /// Engagements = blocs du jour, hors preps et pauses.
  List<ScheduleBlock> get _engagements => _liveBlocks
      .where((b) => !b.isPrep && b.category != 'break')
      .toList();

  List<ScheduleBlock> get _broken =>
      _engagements.where((b) => b.status != 'done').toList();

  List<ScheduleBlock> get _prepBlocks =>
      _liveBlocks.where((b) => b.isPrep).toList();

  Future<void> _togglePrep(ScheduleBlock b) async {
    final newStatus = b.status == 'done' ? 'pending' : 'done';
    await _sync.updateBlockStatus(_todayYmd, b.id, newStatus);
  }

  /// Minutes réelles logguées sur un bloc (même croisement que la carte
  /// coach). Fenêtre = la journée VÉCUE : du début du jour d'ancre jusqu'à
  /// maintenant — une session lancée à 00:10 compte encore pour hier soir.
  int _blockLoggedMin(ScheduleBlock b) {
    final now = DateTime.now();
    final dayStart = DateTime(_anchor.year, _anchor.month, _anchor.day);
    var total = 0;
    for (final s in st.sessions) {
      if (s.startAt.isBefore(dayStart) || s.startAt.isAfter(now)) continue;
      final matches = (b.activityId != null && s.activityId == b.activityId) ||
          (b.taskId != null && s.taskId == b.taskId);
      if (!matches) continue;
      total += (s.endAt ?? now).difference(s.startAt).inMinutes;
    }
    return total;
  }

  // ── Navigation du flux ─────────────────────────────────────────────────────

  void _continueFromStep1() {
    setState(() => _step = _broken.isEmpty ? 2 : 1);
  }

  Future<void> _continueFromStep2() async {
    // Écriture au « Continuer » (pas au tap de chip) — faits trackés.
    if (_broken.length >= 3) {
      if (_dayReasonChoice != null) {
        await _sync.setDayReason(_todayYmd, _dayReasonChoice!);
      }
    } else {
      for (final e in _reasons.entries) {
        await _sync.updateBlockSkipReason(_todayYmd, e.key, e.value);
      }
    }
    if (mounted) setState(() => _step = 2);
  }

  void _skipStep2() => setState(() => _step = 2);

  Future<void> _openPlanTomorrow() async {
    // « Demain » relatif à la journée vécue : à 00:25 c'est bien AUJOURD'HUI
    // (samedi) qu'on pose, pas dimanche.
    final tomorrow = _anchor.add(const Duration(days: 1));
    final ymd =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    final count = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => PlanDayScreen(
          logic: logic, targetDate: ymd, rattrapage: false),
    ));
    if (count != null && mounted) {
      setState(() => _plannedCount = count);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${_dayName(tomorrow)} est posé — $count blocs'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          _header(cs),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(0, .03), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: switch (_step) {
              0 => _step1(cs, key: const ValueKey('s1')),
              1 => _step2(cs, key: const ValueKey('s2')),
              _ => _step3(cs, key: const ValueKey('s3')),
            },
          ),
        ],
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    final now = _anchor; // l'en-tête date la journée VÉCUE (« ven 10 juil »)
    final title = switch (_step) {
      0 => 'Check-in du soir',
      1 => _broken.length >= 3
          ? 'La journée a déraillé'
          : _broken.length == 2
              ? 'Deux engagements ont sauté'
              : 'Un engagement a sauté',
      _ => 'Clore la journée',
    };
    final subtitle = switch (_step) {
      0 => '${_formatDate(now)} — 3 étapes, 2 min',
      1 => _broken.length >= 3
          ? '${_broken.length} engagements sur ${_engagements.length} — pas d\'interrogatoire, une question'
          : 'le pourquoi nourrit le coach — 10 s',
      _ => 'le verdict, puis demain',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withOpacity(.5))),
            ],
          ),
        ),
        // Stepper : 3 segments.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 16,
                  height: 4,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: i <= _step
                        ? cs.primary
                        : cs.onSurface.withOpacity(.15),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Étape 1 : le constat (10a) ─────────────────────────────────────────────

  Widget _step1(ColorScheme cs, {required Key key}) {
    final ymd = yyyymmdd(DateTime(_anchor.year, _anchor.month, _anchor.day));
    final score = logic.dailyScore(ymd);
    final scorePct = (score * 100).round();

    final routines = st.activities
        .where(
            (a) => a.isHabit && logic.effectiveHabitFreq(a) == HabitFreq.daily)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final routinesDone =
        routines.where((a) => _routineReachedOnAnchor(a)).length;

    final done = _engagements.where((b) => b.status == 'done').length;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ScoreCard(score: score, scorePct: scorePct, cs: cs),
        const SizedBox(height: 18),

        // ── Engagements du jour ─────────────────────────────────────────────
        Text('Engagements du jour  $done/${_engagements.length}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: cs.onSurface.withOpacity(.7))),
        const SizedBox(height: 8),
        if (_engagements.isEmpty)
          _emptyHint(cs, 'Aucun engagement posé aujourd\'hui.'),
        for (final b in _engagements) _engagementRow(cs, b),
        const SizedBox(height: 12),

        // ── Chips compactes ─────────────────────────────────────────────────
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (routines.isNotEmpty)
              Chip(
                label: Text('Routines $routinesDone/${routines.length}',
                    style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              ),
            // Fait rejoué sans culpabiliser : « planifié au réveil » (5b).
            if (_schedule?.plannedSameDay == true &&
                _schedule?.plannedAt != null)
              Chip(
                avatar: Icon(Icons.wb_sunny_outlined,
                    size: 14, color: cs.tertiary),
                label: Text(
                    '${_hmFr(_schedule!.plannedAt!)} — planifié au réveil',
                    style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Détails (routines, Gantt, badges) — repliés par défaut ──────────
        _expandable(
          cs,
          label: 'Détails',
          color: cs.onSurface.withOpacity(.5),
          expanded: _showDetails,
          onTap: () => setState(() => _showDetails = !_showDetails),
          children: [_detailsSection(cs, routines, routinesDone)],
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _continueFromStep1,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: const Text('Continuer'),
        ),
      ],
    );
  }

  Widget _engagementRow(ColorScheme cs, ScheduleBlock b) {
    final isDone = b.status == 'done';
    final logged = _blockLoggedMin(b);
    final String trailing;
    if (isDone) {
      trailing = logged > 0
          ? _fmtDur(logged)
          : (b.doneAt != null ? _hmFr(b.doneAt!) : '✓');
    } else {
      trailing = '0 min';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: isDone ? Colors.green : cs.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              b.title,
              style: TextStyle(
                fontSize: 13.5,
                decoration: isDone ? TextDecoration.lineThrough : null,
                color: isDone
                    ? cs.onSurface.withOpacity(.45)
                    : cs.onSurface.withOpacity(.9),
              ),
            ),
          ),
          Text(
            trailing,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: isDone ? cs.onSurface.withOpacity(.45) : cs.error,
            ),
          ),
        ],
      ),
    );
  }

  /// Routine tenue sur la journée VÉCUE : hits du jour d'ancre (+ la fin de
  /// soirée jusqu'à 5 h du matin) ≥ quota — le calendaire de la revue, pas la
  /// fenêtre glissante de habitReached (qui a basculé à minuit).
  bool _routineReachedOnAnchor(Activity a) {
    final dayStart = DateTime(_anchor.year, _anchor.month, _anchor.day);
    final dayEnd = dayStart.add(const Duration(days: 1, hours: 5));
    final quota = logic.dayQuotaFor(a);
    if (quota <= 0) return false;
    final hits = st.habitHits
        .where((h) =>
            h.habitId == a.id &&
            !h.ts.isBefore(dayStart) &&
            h.ts.isBefore(dayEnd))
        .length;
    return hits >= quota;
  }

  Widget _detailsSection(
      ColorScheme cs, List<Activity> routines, int routinesDone) {
    final today = DateTime(_anchor.year, _anchor.month, _anchor.day);
    final ymd = yyyymmdd(today);
    final List<({String taskTitle, String actionTitle})> ganttDone = [];
    for (final project in widget.projects) {
      for (final task in project.tasks) {
        for (final action in task.actions) {
          if (action.done && action.doneAt != null) {
            final d = action.doneAt!;
            if (d.year == today.year &&
                d.month == today.month &&
                d.day == today.day) {
              ganttDone
                  .add((taskTitle: task.title, actionTitle: action.title));
            }
          }
        }
      }
    }
    final todayBadges =
        st.earnedBadges.where((b) => b.earnedAt == ymd).toList();
    final lv = logic.userLevelData();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (routines.isNotEmpty) ...[
          const SizedBox(height: 4),
          _expandable(
            cs,
            label:
                'Routines : $routinesDone validée${routinesDone > 1 ? 's' : ''} sur ${routines.length}',
            color: cs.primary,
            expanded: _showRoutines,
            onTap: () => setState(() => _showRoutines = !_showRoutines),
            children: routines.map((a) {
              final reached = logic.habitReached(a);
              final val = logic.habitValueOn(a.id, today);
              final quota = logic.dayQuotaFor(a);
              final suffix = quota > 1 ? '  $val/$quota' : '';
              return _actionRow(cs, '${a.name}$suffix', done: reached);
            }).toList(),
          ),
        ],
        if (ganttDone.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader(cs,
              icon: Icons.account_tree_outlined,
              title:
                  'Projets  ${ganttDone.length} sous-action${ganttDone.length > 1 ? 's' : ''}'),
          const SizedBox(height: 6),
          for (final item in ganttDone)
            _actionRow(cs, '${item.taskTitle} · ${item.actionTitle}',
                done: true),
        ],
        // Ancienne gamification — coupée par flag (code mort volontaire).
        if (kOldGamificationEnabled) ...[
          const SizedBox(height: 8),
          _sectionHeader(cs,
              icon: Icons.emoji_events_outlined, title: 'Badges & XP'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('${lv.xp} XP — Niveau ${lv.level} ${lv.title}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.primary)),
          ),
          for (final b in todayBadges)
            _actionRow(cs, '${badgeMeta(b.id).emoji} ${badgeMeta(b.id).label}',
                done: true),
        ],
      ],
    );
  }

  // ── Étape 2 : le pourquoi (10b / 11b / 11c) ────────────────────────────────

  static const _blockChips = [
    ('imprevu', 'Imprévu client'),
    ('energie', 'Pas d\'énergie'),
    ('sous_estime', 'Sous-estimé'),
    ('evite', 'J\'ai évité'),
  ];
  static const _dayChips = [
    ('imprevu_global', 'Un imprévu a mangé la journée'),
    ('energie', 'Journée sans énergie'),
    ('irrealiste', 'Le programme était irréaliste'),
  ];

  Widget _step2(ColorScheme cs, {required Key key}) {
    final broken = _broken;
    final many = broken.length >= 3;
    final canContinue =
        many ? _dayReasonChoice != null : _reasons.isNotEmpty;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (many) ...[
          // 11c : liste compacte lecture seule + une seule question.
          for (final b in broken)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(Icons.radio_button_unchecked, size: 16, color: cs.error),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(b.title,
                        style: TextStyle(
                            fontSize: 13.5,
                            color: cs.onSurface.withOpacity(.85)))),
              ]),
            ),
          const SizedBox(height: 14),
          Text('Qu\'est-ce qui a tout emporté ?',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _dayChips)
                _reasonChip(cs, c.$2, _dayReasonChoice == c.$1,
                    () => setState(() => _dayReasonChoice = c.$1)),
              _otherChip(cs, selected: _dayReasonChoice != null &&
                  !_dayChips.any((c) => c.$1 == _dayReasonChoice),
                  onText: (t) => setState(() => _dayReasonChoice = t)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '« Le programme était irréaliste » est une vraie réponse — Orion allégera la proposition de demain au lieu de te demander de tenir plus.',
            style: TextStyle(
                fontSize: 12, height: 1.4, color: cs.onSurface.withOpacity(.5)),
          ),
        ] else ...[
          // 11b : raccourci « même cause » si un historique existe.
          if (broken.length == 2) ...[
            Builder(builder: (_) {
              final top = topWeeklyCause(_weekBlocks);
              if (top == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() {
                    for (final b in broken) {
                      _reasons[b.id] = top;
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: cs.tertiary.withOpacity(.6)),
                      color: cs.tertiary.withOpacity(.07),
                    ),
                    child: Row(children: [
                      Icon(Icons.bolt, size: 16, color: cs.tertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            'Même cause pour les deux : « ${skipReasonLabel(top)} »',
                            style: TextStyle(
                                fontSize: 13, color: cs.onSurface)),
                      ),
                    ]),
                  ),
                ),
              );
            }),
          ],
          for (final b in broken) _whyBlockCard(cs, b),
          const SizedBox(height: 4),
          Text(
            'Réponse enregistrée sur le bloc — le rapport hebdo compte les « imprévu client » et posera la vraie question si ça se répète.',
            style: TextStyle(
                fontSize: 12, height: 1.4, color: cs.onSurface.withOpacity(.5)),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _skipStep2,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('Passer'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: canContinue ? _continueFromStep2 : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('Continuer'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _whyBlockCard(ColorScheme cs, ScheduleBlock b) {
    // Récurrence réelle : « 2ᵉ fois cette semaine » (aujourd'hui inclus).
    final skips = weeklySkipCount(b, _weekBlocks) + 1;
    final recurrence = skips > 1 ? ' · ${skips}ᵉ fois cette semaine' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.radio_button_unchecked, size: 16, color: cs.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(b.title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            Text('0 min',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.error)),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 2),
            child: Text('posé à ${_hhmmFr(b.startTime)}$recurrence',
                style: TextStyle(
                    fontSize: 11.5, color: cs.onSurface.withOpacity(.5))),
          ),
          const SizedBox(height: 10),
          Text('Pourquoi ?',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withOpacity(.6))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _blockChips)
                _reasonChip(cs, c.$2, _reasons[b.id] == c.$1,
                    () => setState(() => _reasons[b.id] = c.$1)),
              _otherChip(cs,
                  selected: _reasons[b.id] != null &&
                      !_blockChips.any((c) => c.$1 == _reasons[b.id]),
                  onText: (t) => setState(() => _reasons[b.id] = t)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reasonChip(
      ColorScheme cs, String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 13)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: cs.primary,
      labelStyle: TextStyle(color: selected ? cs.surface : cs.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      visualDensity: const VisualDensity(vertical: 1),
    );
  }

  Widget _otherChip(ColorScheme cs,
      {required bool selected, required void Function(String) onText}) {
    return ChoiceChip(
      label: Text(selected ? 'Autre ✓' : 'Autre…',
          style: const TextStyle(fontSize: 13)),
      selected: selected,
      onSelected: (_) async {
        final ctrl = TextEditingController();
        final text = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Pourquoi ?', style: TextStyle(fontSize: 16)),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'En un mot ou deux…'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                  child: const Text('OK')),
            ],
          ),
        );
        if (text != null && text.isNotEmpty) onText(text);
      },
      selectedColor: cs.primary,
      labelStyle: TextStyle(color: selected ? cs.surface : cs.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      visualDensity: const VisualDensity(vertical: 1),
    );
  }

  // ── Étape 3 : verdict + pont vers demain (10c) ─────────────────────────────

  Widget _step3(ColorScheme cs, {required Key key}) {
    final pendingPreps =
        _prepBlocks.where((b) => b.status == 'pending').length;
    // 9a : après « Poser demain », le verdict laisse place au geste restant.
    final planned = _plannedCount != null;
    final verdict = planned
        ? (pendingPreps > 0
            ? 'Demain est décidé — il reste un geste : les affaires. 3 minutes maintenant, et demain tu n\'auras rien à penser.'
            : 'Demain est décidé. Bonne nuit — demain se gagne ce soir, et c\'est fait.')
        : buildEveningVerdict(
            todayBlocks: _liveBlocks,
            weekBlocks: _weekBlocks,
            dayReason: _dayReasonChoice ?? _schedule?.dayReason,
          );

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Carte verdict Orion — déterministe, chiffres réels.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.primary.withOpacity(.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ORION',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: cs.primary)),
              const SizedBox(height: 6),
              Text(verdict,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: cs.onSurface.withOpacity(.9))),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Préparer demain — le geste clé du soir.
        if (_prepBlocks.isNotEmpty) ...[
          for (final b in _prepBlocks)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _togglePrep(b),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: b.status == 'done'
                          ? cs.primary.withOpacity(.5)
                          : cs.onSurface.withOpacity(.15)),
                  color: b.status == 'done'
                      ? cs.primary.withOpacity(.06)
                      : Colors.transparent,
                ),
                child: Row(children: [
                  Icon(
                    b.status == 'done'
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: b.status == 'done'
                        ? cs.primary
                        : cs.onSurface.withOpacity(.4),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              decoration: b.status == 'done'
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: b.status == 'done'
                                  ? cs.onSurface.withOpacity(.5)
                                  : cs.onSurface,
                            )),
                        Text(
                          b.status == 'done' && b.doneAt != null
                              ? 'fait à ${_hmFr(b.doneAt!)}${b.prepForDate != null ? ' · pour demain' : ''}'
                              : '${b.startTime}${b.prepForDate != null ? ' · pour demain' : ''}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(.45)),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 8),
        ],

        // Pont vers demain.
        if (!planned)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: _openPlanTomorrow,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                  child: const Text('Poser demain — 2 min'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                  child: const Text('Clore'),
                ),
              ),
            ],
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('Clore la journée'),
          ),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) {
    const months = [
      '', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    const days = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month]}';
  }

  String _dayName(DateTime d) => const [
        'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
      ][d.weekday - 1];

  String _hmFr(DateTime d) =>
      '${d.hour} h ${d.minute.toString().padLeft(2, '0')}';

  String _hhmmFr(String hm) {
    final p = hm.split(':');
    final h = int.tryParse(p.first) ?? 0;
    final m = p.length > 1 ? p[1] : '00';
    return m == '00' ? '$h h' : '$h h $m';
  }

  String _fmtDur(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  Widget _sectionHeader(ColorScheme cs,
      {required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.onSurface.withOpacity(.5)),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: cs.onSurface.withOpacity(.7))),
      ],
    );
  }

  Widget _expandable(
    ColorScheme cs, {
    required String label,
    required Color color,
    required bool expanded,
    required VoidCallback onTap,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color)),
                const Spacer(),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: cs.onSurface.withOpacity(.4),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children),
          ),
      ],
    );
  }

  Widget _actionRow(ColorScheme cs, String title,
      {required bool done, bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: done
                ? Colors.green
                : muted
                    ? cs.onSurface.withOpacity(.3)
                    : cs.onSurface.withOpacity(.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                decoration: done ? TextDecoration.lineThrough : null,
                color: done
                    ? cs.onSurface.withOpacity(.4)
                    : muted
                        ? cs.onSurface.withOpacity(.55)
                        : cs.onSurface.withOpacity(.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text,
            style:
                TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.4))),
      );
}

// ── Score card ───────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final double score;
  final int scorePct;
  final ColorScheme cs;

  const _ScoreCard(
      {required this.score, required this.scorePct, required this.cs});

  String get _emoji {
    if (score >= 1.0) return '🎉';
    if (score >= 0.8) return '⭐';
    if (score >= 0.6) return '👍';
    if (score >= 0.4) return '📈';
    if (score >= 0.2) return '💪';
    return '🌱';
  }

  String get _label {
    if (score >= 1.0) return 'Journée parfaite !';
    if (score >= 0.8) return 'Excellente journée !';
    if (score >= 0.6) return 'Bonne journée';
    if (score >= 0.4) return 'Journée correcte';
    if (score >= 0.2) return 'Journée difficile';
    return 'Demain sera mieux';
  }

  Color get _color {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.lightGreen;
    if (score >= 0.4) return Colors.orange;
    return cs.error;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _color.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withOpacity(.2)),
      ),
      child: Row(
        children: [
          Text(_emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$scorePct%',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: _color),
                ),
                Text(_label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(.7))),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 8,
              height: 64,
              child: RotatedBox(
                quarterTurns: -1,
                child: LinearProgressIndicator(
                  value: score.clamp(0.0, 1.0),
                  backgroundColor: cs.onSurface.withOpacity(.1),
                  color: _color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
