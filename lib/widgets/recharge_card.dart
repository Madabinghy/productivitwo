import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/game_rules.dart' show kRuleRecharge;
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/utils/recharge.dart' show isSleepName, BedtimeStep;
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
          const Spacer(),
          const InfoDot(kRuleRecharge, size: 16),
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

/// Avant le bloc Sommeil (2026-10-31, retour user : la recharge ne démarre plus
/// toute seule) : une heure avant, « Pose demain, puis au lit » si demain n'est
/// pas planifié ; sinon « Va te coucher » → chrono Sommeil (= recharge).
class BedtimeCard extends StatelessWidget {
  final BedtimeStep step;
  final DateTime sleepAt;
  final VoidCallback onPlan;
  final VoidCallback onBed;
  final VoidCallback onSnooze;
  const BedtimeCard({super.key, required this.step, required this.sleepAt, required this.onPlan, required this.onBed, required this.onSnooze});

  @override
  Widget build(BuildContext context) {
    final plan = step == BedtimeStep.plan;
    final late = DateTime.now().isAfter(sleepAt);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: kRechargeColor.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kRechargeInk.withValues(alpha: .25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bedtime_outlined, size: 16, color: kRechargeInk),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              late ? 'BLOC SOMMEIL DEPUIS ${_hm(sleepAt)}' : 'AVANT DE DORMIR · SOMMEIL À ${_hm(sleepAt)}',
              style: TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w700, color: kRechargeInk.withValues(alpha: .85)),
            ),
          ),
          const InfoDot(kRuleRecharge, size: 16),
        ]),
        const SizedBox(height: 6),
        Text(plan ? 'Pose demain, puis au lit' : 'Va te coucher, la journée est finie',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kRechargeInk)),
        const SizedBox(height: 4),
        Text(
          plan
              ? 'Quelques minutes pour poser demain : le soir, ça se décide mieux.'
              : 'Le chrono Sommeil lance ta recharge : la nuit ne compte plus dans tes modes.',
          style: TextStyle(fontSize: 12.5, color: kRechargeInk.withValues(alpha: .75)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton.icon(
            onPressed: plan ? onPlan : onBed,
            style: FilledButton.styleFrom(
              backgroundColor: kRechargeInk,
              foregroundColor: kRechargeColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(plan ? Icons.explore_outlined : Icons.bedtime, size: 18),
            label: Text(plan ? 'Planifier demain' : 'Je vais me coucher', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        Row(children: [
          if (plan)
            TextButton(
              onPressed: onBed,
              style: TextButton.styleFrom(foregroundColor: kRechargeInk, padding: EdgeInsets.zero),
              child: const Text('Aller me coucher'),
            ),
          const Spacer(),
          TextButton(
            onPressed: onSnooze,
            style: TextButton.styleFrom(foregroundColor: kRechargeInk.withValues(alpha: .7), padding: EdgeInsets.zero),
            child: const Text('Pas encore'),
          ),
        ]),
      ]),
    );
  }
}
