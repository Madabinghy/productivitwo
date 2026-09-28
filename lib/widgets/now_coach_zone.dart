import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';
import 'package:productivitwo_v1/utils/energy_state.dart';
import 'package:productivitwo_v1/widgets/coach_moment_card.dart';
import 'package:productivitwo_v1/widgets/energy_cards.dart';
import 'package:productivitwo_v1/widgets/habit_count_sheet.dart';
import 'package:productivitwo_v1/widgets/renegotiate_sheet.dart';

/// Zone coach sous la carte MAINTENANT (ex-`_coachZone` de FocusView, handoff
/// iOS 2026-09 § 3.5) : question d'état d'énergie (24a) quand un déclencheur
/// existe, sinon la carte coach événementielle (fin de chrono, dérive, défi).
/// Mêmes conditions d'affichage qu'avant ; rien par défaut.
class NowCoachZone extends StatefulWidget {
  final AppLogic logic;
  final DailySchedule? schedule;
  final String date; // YYYY-MM-DD
  // Ouvertures de l'onglet (déclencheur n° 1 de la question d'état).
  final List<DateTime> tabOpens;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(Activity activity, int minutes)? onChallengeAccept;
  final Future<void> Function(Activity activity, int minutes)? onChallengeSchedule;

  const NowCoachZone({
    super.key,
    required this.logic,
    required this.schedule,
    required this.date,
    required this.tabOpens,
    this.onLaunch,
    this.onChallengeAccept,
    this.onChallengeSchedule,
  });

  @override
  State<NowCoachZone> createState() => _NowCoachZoneState();
}

class _NowCoachZoneState extends State<NowCoachZone> {
  final _sync = FirestoreSync();
  Set<String> _scheduledChallengeIds = const {};
  // Renégociation faite → la carte dérive respire 45 min ; « Ignorer » → elle
  // se tait jusqu'à demain.
  DateTime? _driftSnoozeUntil;

  AppLogic get logic => widget.logic;
  AppState get st => widget.logic.state;

  @override
  void initState() {
    super.initState();
    _sync.fetchScheduledChallengeActivityIds().then((ids) {
      if (mounted) setState(() => _scheduledChallengeIds = ids);
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<ScheduleBlock> get _live =>
      (widget.schedule?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final s = widget.schedule;
    final energy = s?.energyState;
    final live = _live;
    final sessionsToday = st.sessions.where((x) => _sameDay(x.startAt, now)).toList();
    final trigger = energyAskTrigger(
      now,
      state: energy,
      reviewedAt: s?.reviewedAt,
      idleOpens: idleOpenCount(now, widget.tabOpens, lastActionAt(now, st, live)),
      drifting: driftingBlock(now, st, live, sessionsToday),
      requested: false,
    );
    if (trigger != null) return _energyQuestion(now, trigger, live, sessionsToday);
    return _coachCard(now);
  }

  Widget _energyQuestion(DateTime now, EnergyAskTrigger trigger, List<ScheduleBlock> live,
      List<Session> sessionsToday) {
    final lastAction = lastActionAt(now, st, live);
    final idle = widget.tabOpens
        .where((o) =>
            now.difference(o).inMinutes <= 90 && (lastAction == null || o.isAfter(lastAction)))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: EnergyQuestionCard(
        message: energyAskMessage(trigger,
            idleOpens: idle.length,
            firstOpen: idle.isNotEmpty ? idle.first : null,
            drifting: driftingBlock(now, st, live, sessionsToday)),
        onPick: (level, note) async {
          await _sync.setEnergyState(widget.date, level, note: note);
          if (!mounted) return;
          setState(() {});
          if (level == 'ok') {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Noté — on continue, rien ne change.'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ));
          }
        },
      ),
    );
  }

  ChallengeProposal? _challengeProposal(DateTime now) {
    final a = logic.challengeActivity(exclude: _scheduledChallengeIds);
    if (a == null) return null;
    final todayStart = DateTime(now.year, now.month, now.day);
    final done = logic.totalForRangeByActivity(a.id, todayStart, now).inMinutes;
    return ChallengeProposal(
        activity: a,
        minutes: logic.challengeDurationFor(a),
        doneMin: done,
        targetMin: a.goalMin,
        streak: st.challengeStreak);
  }

  Widget _coachCard(DateTime now) {
    final moment = computeCoachMoment(now, st, widget.schedule, st.sessions,
        driftSnoozed: _driftSnoozeUntil != null && now.isBefore(_driftSnoozeUntil!),
        challenge: _challengeProposal(now));
    if (moment.hidden) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: CoachMomentCard(
        moment: moment,
        onLaunch: widget.onLaunch,
        onRenegotiate: (block) async {
          await showRenegotiateSheet(
            context,
            logic: logic,
            block: block,
            date: widget.date,
            onLaunch: widget.onLaunch,
          );
          if (mounted) {
            setState(() =>
                _driftSnoozeUntil = DateTime.now().add(const Duration(minutes: 45)));
          }
        },
        onDismiss: () => setState(() => _driftSnoozeUntil =
            DateTime(now.year, now.month, now.day).add(const Duration(days: 1))),
        onChallengeAccept: (block) {
          final a = st.activities.where((x) => x.id == block.activityId).firstOrNull;
          if (a != null) _confirmChallenge(a, block.durationMin);
        },
        onCheckRoutine: (block) async {
          final a = st.activities.where((x) => x.id == block.activityId).firstOrNull;
          if (a == null || !a.isHabit) return;
          final day = DateTime.now();
          final tgt = logic.activeHabitTarget(a);
          if (tgt > 0 && logic.habitValueOn(a.id, day) >= tgt) return;
          if (tgt > 1) {
            final total = await showHabitCountSheet(context, logic: logic, activity: a);
            if (total == null || !context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${a.name} : $total/$tgt aujourd\'hui'),
              duration: const Duration(seconds: 2),
            ));
            return;
          }
          logic.incHabit(a.id, 1, DateTime(day.year, day.month, day.day));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Routine validée : ${a.name}'),
            duration: const Duration(seconds: 2),
          ));
        },
      ),
    );
  }

  /// Confirmation du défi (même dialog que le bouton doré) : rien ne se lance
  /// sans ça.
  Future<void> _confirmChallenge(Activity a, int minutes) async {
    final cs = Theme.of(context).colorScheme;
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.smart_toy_rounded, color: Color(0xFFB8860B), size: 32),
        title: const Text('ORION te défie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$minutes min de « ${a.name} »',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                '« Je relève » lance le chrono et le minuteur-alarme tout de suite. « Programmer » le pose pour plus tard.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withOpacity(.6))),
          ],
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, null), child: const Text('Pas maintenant')),
          TextButton(
              onPressed: () => Navigator.pop(d, 'schedule'), child: const Text('Programmer')),
          FilledButton(onPressed: () => Navigator.pop(d, 'now'), child: const Text('Je relève')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'now') widget.onChallengeAccept?.call(a, minutes);
    if (choice == 'schedule') {
      await widget.onChallengeSchedule?.call(a, minutes);
      final ids = await _sync.fetchScheduledChallengeActivityIds();
      if (mounted) setState(() => _scheduledChallengeIds = ids);
    }
  }
}
