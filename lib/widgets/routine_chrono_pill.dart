import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart' show kBAttention;
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart' show pickLinkedActivity;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show kRoutineAccent;

/// Chrono d'une routine sans quitter l'écran (carte du moment, Enchaîner
/// routines, Enchaîner programme) : « ▶ Lecture » = chrono libre sur
/// l'activité liée (arrête l'éventuel chrono en cours — enchaîner les routines
/// enchaîne donc les chronos), « ■ Arrêter · Lecture » si déjà dessus, appui
/// long = changer l'activité ; « Lier une activité » quand la routine n'en a
/// pas. Persistance du lien comme la fiche routine (`logic.onChange`).
class RoutineChronoPill extends StatelessWidget {
  final AppLogic logic;
  final Activity routine;
  final VoidCallback? onChanged;
  final bool centered;
  const RoutineChronoPill({super.key, required this.logic, required this.routine, this.onChanged, this.centered = false});

  static Activity? linkedOf(AppLogic logic, Activity a) {
    final id = (a.linkedActivityId ?? '').trim();
    if (id.isEmpty) return null;
    return logic.state.activeActivities.where((x) => x.id == id).firstOrNull;
  }

  static bool isRunning(AppLogic logic, Activity linked) => logic.runningActivity()?.id == linked.id;

  static void toggleChrono(AppLogic logic, Activity linked) {
    HapticFeedback.lightImpact();
    if (isRunning(logic, linked)) {
      logic.stopActive();
    } else {
      if (logic.runningActivity() != null) logic.stopActive();
      logic.start(linked.id);
    }
    logic.onChange();
  }

  Future<void> _link(BuildContext context) async {
    if (!await pickLinkedActivity(context, st: logic.state, act: routine)) return;
    logic.onChange();
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    final linked = linkedOf(logic, routine);
    final align = centered ? Alignment.center : Alignment.centerLeft;
    if (linked == null) {
      return Align(
        alignment: align,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _link(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_link, size: 15, color: pal.text3),
              const SizedBox(width: 5),
              Text('Lier une activité', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.text3)),
            ]),
          ),
        ),
      );
    }
    final running = isRunning(logic, linked);
    final color = running ? kBAttention : kRoutineAccent;
    return Align(
      alignment: align,
      child: Material(
        color: color.withOpacity(running ? .16 : .14),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            toggleChrono(logic, linked);
            onChanged?.call();
          },
          onLongPress: () => _link(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 16, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(running ? 'Arrêter · ${linked.name}' : linked.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
