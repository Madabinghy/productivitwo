import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/sleep_night.dart';
import 'package:productivitwo_v1/widgets/mode_sheet.dart' show kRechargeColor, kRechargeInk;

/// Pastille sommeil de la barre du haut (retour user 2026-10-30) : « 🌙 7 h 12 »
/// = la dernière nuit chronométrée (`lastNightSleep`), « en cours » quand le
/// chrono de sommeil tourne. Rien sans chrono de sommeil. Tap = [onTap].
class SleepPill extends StatelessWidget {
  final AppLogic logic;
  final VoidCallback? onTap;
  const SleepPill({super.key, required this.logic, this.onTap});

  @override
  Widget build(BuildContext context) {
    final st = logic.state;
    final night = lastNightSleep(sessions: st.sessions, activities: st.activities, now: DateTime.now(), dayStartMin: logic.dayStartMin);
    if (night == null) return const SizedBox.shrink();
    return Tooltip(
      message: night.running ? 'Sommeil en cours' : 'La nuit dernière',
      child: Material(
        color: kRechargeColor.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: kRechargeInk.withValues(alpha: .25))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bedtime_outlined, size: 15, color: kRechargeInk),
              const SizedBox(width: 5),
              Text(
                night.running ? '${fmtSleep(night.minutes)} · en cours' : fmtSleep(night.minutes),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kRechargeInk, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
