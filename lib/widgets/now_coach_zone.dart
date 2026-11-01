import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';
import 'package:productivitwo_v1/widgets/coach_moment_card.dart';
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

  const NowCoachZone({
    super.key,
    required this.logic,
    required this.schedule,
    required this.date,
    required this.tabOpens,
    this.onLaunch,
  });

  @override
  State<NowCoachZone> createState() => _NowCoachZoneState();
}

class _NowCoachZoneState extends State<NowCoachZone> {
  // Renégociation faite → la carte dérive respire 45 min ; « Ignorer » → elle
  // se tait jusqu'à demain.
  DateTime? _driftSnoozeUntil;

  AppLogic get logic => widget.logic;
  AppState get st => widget.logic.state;


  // La question d'état « ORION · ÉTAT » (À fond · Correct · À plat) est retirée
  // le 2026-10-30 : le mode Flemme / Normal / En forme la remplace.
  @override
  Widget build(BuildContext context) => _coachCard(DateTime.now());

  Widget _coachCard(DateTime now) {
    final moment = computeCoachMoment(now, st, widget.schedule, st.sessions,
        driftSnoozed: _driftSnoozeUntil != null && now.isBefore(_driftSnoozeUntil!),
        timeContexts: logic.timeContexts);
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
        onCheckRoutine: (block) async {
          final a = st.activities.where((x) => x.id == block.activityId).firstOrNull;
          if (a == null || !a.isHabit) return;
          final day = DateTime.now();
          final tgt = logic.activeHabitTarget(a);
          if (tgt > 0 && logic.habitValueOn(a.id, day) >= tgt) return;
          if (tgt > 1) {
            final total = await showHabitCountSheet(context, logic: logic, activity: a);
            if (total == null || !context.mounted) return;
            ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
              content: Text('${a.name} : $total/$tgt aujourd\'hui'),
              duration: const Duration(seconds: 2),
            ));
            return;
          }
          logic.incHabit(a.id, 1, DateTime(day.year, day.month, day.day));
          ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
            content: Text('Routine validée : ${a.name}'),
            duration: const Duration(seconds: 2),
          ));
        },
      ),
    );
  }
}
