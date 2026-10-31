import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/recharge.dart' show isSleepName;
import 'package:productivitwo_v1/widgets/mode_sheet.dart' show kRechargeColor, kRechargeInk;

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _dur(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// Recharge sur Aujourd'hui (maquette validée 2026-10-30). Le matin, avant le
/// premier geste : « Bonjour · 7 h 25 de recharge · Comment tu démarres ? »
/// (Flemme · Normal · En forme ; sans choix, le premier geste vaut Normal).
/// Le soir, une fois le sommeil commencé : « Recharge depuis 22:40 » et
/// « Pas encore couché » (repointe le mode : la recharge attend le chrono
/// Sommeil). Rien quand la personne est éveillée.
class RechargeCard extends StatelessWidget {
  final AppLogic logic;
  const RechargeCard({super.key, required this.logic});

  @override
  Widget build(BuildContext context) {
    final since = logic.rechargeSinceNow;
    if (since == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final ymd = livedProgramYmd(now, logic.dayStartMin);
    final morning = !logic.state.moodMarks.any((m) => m.isElan && m.ymd == ymd) && logic.livedNowMinNow < 12 * 60;
    final mode = logic.mode;
    final byId = {for (final a in logic.state.activities) a.id: a};
    final sleepRunning = logic.state.sessions.any((x) => x.endAt == null && !x.deleted && isSleepName(byId[x.activityId]?.name));
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kRechargeColor.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kRechargeInk.withValues(alpha: .25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bedtime_outlined, size: 16, color: kRechargeInk),
          const SizedBox(width: 6),
          Text(
            morning ? 'BONJOUR · ${_dur(now.difference(since)).toUpperCase()} DE RECHARGE' : 'RECHARGE DEPUIS ${_hm(since)}',
            style: TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w700, color: kRechargeInk.withValues(alpha: .85)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(morning ? 'Comment tu démarres ?' : 'Tes modes s’arrêtent jusqu’à demain',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kRechargeInk)),
        const SizedBox(height: 4),
        Text(
          morning
              ? 'Pas envie de choisir ? Ton premier geste (un +1, un chrono) te met en Normal.'
              : 'La nuit ne compte ni dans ton élan, ni dans la flemme.',
          style: TextStyle(fontSize: 12.5, height: 1.35, color: kRechargeInk.withValues(alpha: .8)),
        ),
        const SizedBox(height: 10),
        if (morning)
          Row(children: [
            for (final m in DayMode.values) ...[
              if (m != DayMode.low) const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => logic.setMode(m),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kRechargeInk,
                      side: BorderSide(color: kRechargeInk.withValues(alpha: .4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(kModeLabels[m]!, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ])
        else if (sleepRunning)
          // Recharge lancée par le chrono Sommeil : rester debout = l'arrêter.
          TextButton(
            onPressed: () => _stillUp(mode),
            style: TextButton.styleFrom(foregroundColor: kRechargeInk, padding: EdgeInsets.zero),
            child: const Text('Pas encore couché · arrêter le chrono Sommeil'),
          )
        else
          TextButton(
            onPressed: () => logic.setMode(mode),
            style: TextButton.styleFrom(foregroundColor: kRechargeInk, padding: EdgeInsets.zero),
            child: Text('Pas encore couché · garder ${kModeLabels[mode]}'),
          ),
      ]),
    );
  }

  /// Arrête le chrono Sommeil (une session de moins de 5 min = lancée trop tôt :
  /// retirée) et remet le mode : la recharge s'arrête.
  void _stillUp(DayMode mode) {
    final s = logic.stopActive(notify: false);
    if (s != null && s.endAt != null && s.endAt!.difference(s.startAt).inMinutes < 5) {
      logic.deleteSession(s.id);
      logic.sync?.deleteSession(s.id);
    }
    logic.setMode(mode);
  }
}
