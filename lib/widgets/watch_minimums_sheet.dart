import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin, pickDurationMin;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/utils/watch_minimums.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// « Garder » d'une activité qui bloque : la question ne revient pas avant
/// [kBlockerKeepDays] jours (mémoire locale, par appareil).
class WatchKeepStore {
  static const _key = 'watch_minimum_kept';
  static Map<String, String> current = {};

  static Future<Map<String, String>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      current = raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      current = {};
    }
    return current;
  }

  static Future<void> keep(String activityId) async {
    current = {...current, activityId: ymdOf(DateTime.now())};
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(current));
    } catch (_) {}
  }
}

/// Les activités qui coûtent la montre, d'après les données de l'appareil.
List<WatchBlocker> watchBlockersOf(AppLogic logic) {
  final st = logic.state;
  final resting = {for (final d in st.activeDomains) if (logic.isDomainResting(d.id)) d.id};
  return watchBlockers(
    activities: st.activities.where((a) => !resting.contains(a.domainId)).toList(),
    sessions: st.sessions,
    now: DateTime.now(),
    frozenOf: (a) => logic.frozenOf(a.id),
    keptYmd: WatchKeepStore.current,
  );
}

/// Pose le minimum d'une activité comme un réglage fait à la main, avec
/// « Annuler » dans la foulée.
void setActivityMinimum(BuildContext context, AppLogic logic, Activity a, int min, {VoidCallback? onChanged}) {
  final oldMin = a.goalMin;
  final oldSource = a.targetSource;
  a.goalMin = min.clamp(0, 720);
  a.targetSource = 'user';
  logic.onChange();
  onChanged?.call();
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Text(min <= 0 ? '${a.name} : plus de minimum' : '${a.name} : minimum ${fmtMin(min)} / j'),
    action: SnackBarAction(
      label: 'Annuler',
      onPressed: () {
        a.goalMin = oldMin;
        a.targetSource = oldSource;
        logic.onChange();
        onChanged?.call();
      },
    ),
  ));
}

/// L'encart sous la barre d'une activité qui bloque.
class WatchBlockerCard extends StatelessWidget {
  final WatchBlocker blocker;
  final VoidCallback onNone;
  final void Function(int min) onLower;
  final VoidCallback onKeep;
  final bool compact;
  const WatchBlockerCard({super.key, required this.blocker, required this.onNone, required this.onLower, required this.onKeep, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final b = blocker;
    final a = b.activity;
    final lower = b.suggestedMin;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: compact ? 0 : 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: kBRaised, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (compact)
          Row(children: [
            Expanded(child: Text(a.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: kBText))),
            Text('${b.lostDays} journées perdues sur $kBlockerWindowDays', style: const TextStyle(fontSize: 11.5, color: kBText3)),
          ])
        else
          Text('${a.name} te coûte souvent la Montre suisse',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText, height: 1.3)),
        const SizedBox(height: 3),
        Text(
          compact
              ? 'minimum ${fmtMin(a.goalMin)} / j · tu fais ${fmtMin(b.avgMin)}'
              : '${b.lostDays} journées perdues sur $kBlockerWindowDays à cause d’elle. Minimum ${fmtMin(a.goalMin)} / j, tu en fais ${fmtMin(b.avgMin)} en moyenne.',
          style: const TextStyle(fontSize: 12.5, height: 1.35, color: kBText2),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _btn('Pas de minimum', onNone, filled: true),
          if (lower != null) _btn('Baisser à ${fmtMin(lower)}', () => onLower(lower)),
          _btn('Garder', onKeep, text: true),
        ]),
        if (!compact) ...[
          const SizedBox(height: 6),
          Text('Pas de minimum : tu chronomètres toujours ${a.name}, elle ne compte plus pour la montre.',
              style: const TextStyle(fontSize: 11.5, height: 1.35, color: kBText3)),
        ],
      ]),
    );
  }

  Widget _btn(String label, VoidCallback onTap, {bool filled = false, bool text = false}) {
    final style = const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700);
    const pad = EdgeInsets.symmetric(horizontal: 12);
    if (filled) {
      return SizedBox(
        height: 34,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(backgroundColor: kBPrimary, foregroundColor: kBBg, padding: pad, textStyle: style, visualDensity: VisualDensity.compact),
          child: Text(label),
        ),
      );
    }
    if (text) {
      return SizedBox(
        height: 34,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(foregroundColor: kBText3, padding: const EdgeInsets.symmetric(horizontal: 8), textStyle: style, visualDensity: VisualDensity.compact),
          child: Text(label),
        ),
      );
    }
    return SizedBox(
      height: 34,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(foregroundColor: kBPrimary, side: const BorderSide(color: kBPrimary), padding: pad, textStyle: style, visualDensity: VisualDensity.compact),
        child: Text(label),
      ),
    );
  }
}

/// « Tes minimums » : les activités qui coûtent la montre (avec les trois
/// gestes), celles dont le minimum est tenu, puis celles sans minimum.
Future<void> showWatchMinimumsSheet(BuildContext context, AppLogic logic) async {
  await WatchKeepStore.load();
  if (!context.mounted) return;
  await showFiche<void>(context, builder: (ctx, scroll) {
    return StatefulBuilder(builder: (ctx, setLocal) {
      final now = DateTime.now();
      final st = logic.state;
      final blockers = watchBlockersOf(logic);
      final blockingIds = {for (final b in blockers) b.activity.id};
      final timeActs = st.activities.where((a) => !a.deleted && !a.isHabit && !logic.isActivitySnoozed(a.id, now)).toList()
        ..sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
      final kept = timeActs.where((a) => a.goalMin > 0 && !blockingIds.contains(a.id)).toList();
      final without = timeActs.where((a) => a.goalMin <= 0).toList();
      var withoutOpen = false;
      void refresh() => setLocal(() {});
      Future<void> edit(Activity a) async {
        final v = await pickDurationMin(ctx, initial: a.goalMin, title: 'Minimum · ${a.name}', allowZero: true);
        if (v == null || !ctx.mounted) return;
        setActivityMinimum(ctx, logic, a, v, onChanged: refresh);
      }

      Widget row(Activity a) {
        final avg = averageMinPerDay(a.id, st.sessions, now);
        return InkWell(
          onTap: () => edit(a),
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBLine))),
            child: Row(children: [
              Expanded(child: Text(a.name, style: const TextStyle(fontSize: 14, color: kBText))),
              Text(a.goalMin > 0 ? '${fmtMin(a.goalMin)} / j · tu fais ${fmtMin(avg)}' : 'tu fais ${fmtMin(avg)} / j',
                  style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18, color: kBText4),
            ]),
          ),
        );
      }

      Widget title(String t) => Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 8),
            child: Text(t, style: const TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w600, color: kBText3)),
          );

      return StatefulBuilder(builder: (ctx, setFold) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            const FicheHeader(title: 'Tes minimums', info: InfoDot(kRuleWatch, startAt: 4)),
            const SizedBox(height: 6),
            const Text('Un minimum, c’est ce que tu veux tenir chaque semaine. Une activité occasionnelle n’en a pas besoin.',
                style: TextStyle(fontSize: 13.5, height: 1.4, color: kBText2)),
            if (blockers.isNotEmpty) ...[
              title('TE COÛTENT LA MONTRE · ${blockers.length}'),
              for (final b in blockers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WatchBlockerCard(
                    blocker: b,
                    compact: true,
                    onNone: () => setActivityMinimum(ctx, logic, b.activity, 0, onChanged: refresh),
                    onLower: (m) => setActivityMinimum(ctx, logic, b.activity, m, onChanged: refresh),
                    onKeep: () async {
                      await WatchKeepStore.keep(b.activity.id);
                      refresh();
                    },
                  ),
                ),
            ],
            if (kept.isNotEmpty) ...[
              title(blockers.isEmpty ? 'AVEC UN MINIMUM · ${kept.length}' : 'TENUS · ${kept.length}'),
              for (final a in kept) row(a),
            ],
            if (without.isNotEmpty) ...[
              InkWell(
                onTap: () => setFold(() => withoutOpen = !withoutOpen),
                child: Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('SANS MINIMUM · ${without.length}',
                            style: const TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w600, color: kBText3)),
                        if (!withoutOpen)
                          Text(without.take(4).map((a) => a.name).join(', ') + (without.length > 4 ? '…' : ''),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kBText4)),
                      ]),
                    ),
                    Icon(withoutOpen ? Icons.expand_less : Icons.expand_more, color: kBText4),
                  ]),
                ),
              ),
              if (withoutOpen) for (final a in without) row(a),
            ],
          ],
        );
      });
    });
  });
}
