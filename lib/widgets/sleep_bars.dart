import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/sleep_nights.dart';
import 'package:productivitwo_v1/widgets/mode_sheet.dart' show kRechargeInk;

/// Barres de sommeil de la barre du haut (retour user 2026-10-30 : « les petites
/// barres, c'était mieux » qu'un texte) : une barre par nuit sur 7 nuits, hauteur
/// = durée (9 h = pleine), la dernière nuit en clair, plus vive quand le chrono de
/// sommeil tourne. Même pilule que les 24 h. Rien sans aucun chrono de sommeil.
class SleepBars extends StatelessWidget {
  final AppLogic logic;
  final VoidCallback? onTap;
  const SleepBars({super.key, required this.logic, this.onTap});

  static const _fullMin = 9 * 60;

  @override
  Widget build(BuildContext context) {
    final st = logic.state;
    final nights = sleepNights(sessions: st.sessions, activities: st.activities, now: DateTime.now(), dayStartMin: logic.dayStartMin);
    if (nights.every((n) => n == null)) return const SizedBox.shrink();
    final running = sleepRunning(st.sessions, st.activities);
    final cs = Theme.of(context).colorScheme;
    final last = nights.last;
    return Tooltip(
      message: last == null ? 'Sommeil · 7 nuits' : '${running ? 'En cours' : 'La nuit dernière'} · ${fmtSleep(last)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bedtime_outlined, size: 13, color: kRechargeInk.withValues(alpha: .8)),
              const SizedBox(width: 5),
              SizedBox(
                height: 18,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < nights.length; i++)
                    Container(
                      width: 4,
                      margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                      height: nights[i] == null ? 2 : (2 + 16 * (nights[i]! / _fullMin).clamp(0.0, 1.0)),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1.5),
                        color: nights[i] == null
                            ? cs.onSurface.withValues(alpha: .15)
                            : kRechargeInk.withValues(alpha: i == nights.length - 1 ? (running ? 1 : .9) : .45),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
