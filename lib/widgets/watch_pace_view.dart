import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/utils/half_days.dart' show ActivityPace, paceOn, minutesByActivityDay;
import 'package:productivitwo_v1/utils/watch_minimums.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart' show kBadgeGaugeTrack;
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/widgets/watch_minimums_sheet.dart';

const _kPast = Color(0xFF4C6555);

/// Montre suisse sur 7 jours glissants (maquette validée 2026-10-30) : une
/// barre par activité dont le bout = 7 × le minimum ; gris = les 6 jours
/// passés, vert = aujourd'hui, piste = ce qui manque. Les activités à
/// compléter d'abord, « reste n min » ou « ✓ couverte · n d'avance ».
/// Avec [logic] (mobile), la vue se recalcule elle-même et propose, sous une
/// activité qui coûte souvent la montre, de retirer ou baisser son minimum.
class WatchPaceView extends StatefulWidget {
  final List<ActivityPace> pace;
  final void Function(String activityId, int minutes)? onChrono;
  final AppLogic? logic;
  const WatchPaceView({super.key, required this.pace, this.onChrono, this.logic});

  @override
  State<WatchPaceView> createState() => _WatchPaceViewState();
}

class _WatchPaceViewState extends State<WatchPaceView> {
  @override
  void initState() {
    super.initState();
    if (widget.logic != null) WatchKeepStore.load().then((_) => mounted ? setState(() {}) : null);
  }

  List<ActivityPace> get _pace {
    final logic = widget.logic;
    if (logic == null) return widget.pace;
    final st = logic.state;
    final now = DateTime.now();
    final resting = {for (final d in st.activeDomains) if (logic.isDomainResting(d.id)) d.id};
    return paceOn(now,
        activities: st.activities.where((a) => !resting.contains(a.domainId)).toList(),
        minutes: minutesByActivityDay(st.sessions, now),
        frozenOf: (a) => logic.frozenOf(a.id));
  }

  @override
  Widget build(BuildContext context) {
    final pace = _pace;
    final logic = widget.logic;
    final blockers = logic == null ? const <String, WatchBlocker>{} : {for (final b in watchBlockersOf(logic)) b.activity.id: b};
    if (pace.isEmpty) return const SizedBox.shrink();
    final rows = [...pace]..sort((a, b) {
        if (a.onPace != b.onPace) return a.onPace ? 1 : -1;
        return a.onPace ? b.aheadMin.compareTo(a.aheadMin) : a.missingMin.compareTo(b.missingMin);
      });
    final covered = pace.where((p) => p.onPace).length;
    final missing = rows.where((p) => !p.onPace).toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: kBBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('7 DERNIERS JOURS', style: TextStyle(fontSize: 11, letterSpacing: .8, color: kBText4))),
          const InfoDot(kRuleWatch, size: 16),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('$covered / ${pace.length}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kBText, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
          const Text('couvertes', style: TextStyle(fontSize: 14, color: kBText2)),
        ]),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Reste ce soir : ${missing.map((p) => '${p.activity.name} ${fmtMin(p.missingMin)}').join(' · ')}',
                style: const TextStyle(fontSize: 12.5, height: 1.35, color: kBText)),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 4, children: const [
          _Legend(color: _kPast, label: '6 jours passés'),
          _Legend(color: kBPrimary, label: 'aujourd’hui'),
          _Legend(color: kBadgeGaugeTrack, label: 'manque'),
        ]),
        for (final p in rows) ...[
          _row(p),
          if (!p.onPace && logic != null && blockers[p.activity.id] != null)
            WatchBlockerCard(
              blocker: blockers[p.activity.id]!,
              onNone: () => setActivityMinimum(context, logic, p.activity, 0, onChanged: _refresh),
              onLower: (m) => setActivityMinimum(context, logic, p.activity, m, onChanged: _refresh),
              onKeep: () async {
                await WatchKeepStore.keep(p.activity.id);
                _refresh();
              },
            ),
        ],
        if (logic != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                await showWatchMinimumsSheet(context, logic);
                _refresh();
              },
              style: TextButton.styleFrom(foregroundColor: kBPrimary, padding: EdgeInsets.zero),
              child: const Text('Régler tes minimums ›'),
            ),
          ),
      ]),
    );
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Widget _row(ActivityPace p) {
    final need = p.expectedMin <= 0 ? 1 : p.expectedMin;
    final pastR = (p.pastMin / need).clamp(0.0, 1.0);
    final todayR = (p.todayMin / need).clamp(0.0, 1.0 - pastR);
    final label = p.onPace ? (p.aheadMin > 0 ? '✓ couverte · ${fmtMin(p.aheadMin)} d’avance' : '✓ couverte') : 'reste ${fmtMin(p.missingMin)}';
    final chrono = widget.onChrono;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(p.activity.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kBText))),
              Text(label,
                  style: TextStyle(fontSize: 12, color: p.onPace ? kBPrimary : kBText, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: LayoutBuilder(builder: (_, c) {
                  final w = c.maxWidth;
                  return Stack(children: [
                    Container(color: kBadgeGaugeTrack),
                    Container(width: w * pastR, color: _kPast),
                    Positioned(left: w * pastR, top: 0, bottom: 0, child: Container(width: w * todayR, color: kBPrimary)),
                  ]);
                }),
              ),
            ),
            const SizedBox(height: 3),
            Text('${fmtMin(p.doneMin)} / ${fmtMin(p.expectedMin)} · minimum ${fmtMin(p.activity.goalMin)} / j',
                style: const TextStyle(fontSize: 11, color: kBText4, fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        ),
        if (!p.onPace && chrono != null) ...[
          const SizedBox(width: 10),
          SizedBox(
            height: 32,
            child: FilledButton(
              onPressed: () => chrono(p.activity.id, p.missingMin),
              style: FilledButton.styleFrom(
                backgroundColor: kBPrimary,
                foregroundColor: kBBg,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              child: const Text('Chrono'),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: kBText3)),
      ]);
}
