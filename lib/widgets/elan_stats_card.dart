import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/widgets/elan_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onglet Stats : « Élan & discipline » (la semaine en sept colonnes, un point
/// par pointage à la hauteur de son élan, « Face à la flemme · 5 / 7 · 71 % »,
/// trois chiffres) puis « Quand l'élan est là » (créneau × jour). Les chiffres
/// disent ce qui a été fait, jamais ce qu'il aurait fallu.
class ElanStatsCards extends StatefulWidget {
  final AppLogic? logic;
  final FirestoreSync sync;
  // Web (sans AppLogic) : données passées telles quelles.
  final List<MoodMark>? marks;
  final List<HabitHit>? hits;
  final List<Activity>? activities;
  final int? dayStartMin;
  const ElanStatsCards({super.key, this.logic, required this.sync, this.marks, this.hits, this.activities, this.dayStartMin})
      : assert(logic != null || (marks != null && hits != null && activities != null));

  @override
  State<ElanStatsCards> createState() => _ElanStatsCardsState();
}

class _ElanStatsCardsState extends State<ElanStatsCards> {
  late Future<List<DailySchedule>> _schedules;
  // Allègement 2026-10 : repliée par défaut, l'en-tête garde les deux chiffres.
  static const _kFoldKey = 'stats_elan_folded';
  bool _folded = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool(_kFoldKey);
      if (v != null && mounted && v != _folded) setState(() => _folded = v);
    });
    final now = DateTime.now();
    _schedules = widget.sync.fetchDailySchedulesRange(ymdOf(now.subtract(const Duration(days: 8))), ymdOf(now));
  }

  @override
  Widget build(BuildContext context) {
    final marks = widget.marks ?? widget.logic!.state.moodMarks;
    if (marks.where((m) => m.kind == kMoodElan).isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<DailySchedule>>(
      future: _schedules,
      builder: (ctx, snap) {
        final days = buildElanDays(
          marks: marks,
          schedulesByYmd: {for (final s in snap.data ?? const <DailySchedule>[]) s.date: s},
          hits: widget.hits ?? widget.logic!.state.habitHits,
          activities: widget.activities ?? widget.logic!.state.activities,
          now: DateTime.now(),
          dayStartMin: widget.dayStartMin ?? widget.logic!.dayStartMin,
        );
        final m = elanMetrics(days);
        final cs = Theme.of(ctx).colorScheme;
        final pct = m.discipline == null ? null : (m.discipline! * 100).round();
        return Column(children: [
          Card(
            elevation: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() => _folded = !_folded);
                SharedPreferences.getInstance().then((p) => p.setBool(_kFoldKey, _folded));
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(children: [
                  const Text('Élan & discipline', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${m.count == 0 ? '—' : m.mean.toStringAsFixed(1).replaceAll('.', ',')} / 5 · face à la flemme ${pct == null ? '—' : '${m.lowWon} / ${m.lowCount}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6)),
                    ),
                  ),
                  Icon(_folded ? Icons.expand_more : Icons.expand_less, size: 20, color: cs.onSurface.withValues(alpha: .5)),
                ]),
              ),
            ),
          ),
          if (!_folded) ...[_ElanWeekCard(days: days), _ElanHeatmapCard(days: days)],
        ]);
      },
    );
  }
}

Widget _card(BuildContext context, {required String title, required String sub, required Widget child}) {
  final cs = Theme.of(context).colorScheme;
  return Card(
    elevation: 1,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(sub, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55))),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    ),
  );
}

const _dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

class _ElanWeekCard extends StatelessWidget {
  final List<ElanDay> days;
  const _ElanWeekCard({required this.days});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = elanMetrics(days);
    final muted = cs.onSurface.withValues(alpha: .5);
    final pct = m.discipline == null ? null : (m.discipline! * 100).round();
    return _card(
      context,
      title: 'Élan & discipline',
      sub: '7 derniers jours',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 136,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 44,
              height: 110,
              child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final l in const ['Lancé', 'Moyen', 'Flemme']) Text(l, style: TextStyle(fontSize: 10, color: muted)),
              ]),
            ),
            for (final d in days) ...[
              const SizedBox(width: 6),
              Expanded(child: _dayColumn(cs, d)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: .4)),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Face à la flemme', style: TextStyle(fontSize: 14)),
          const Spacer(),
          Text(pct == null ? '—' : '${m.lowWon} / ${m.lowCount} · $pct %',
              style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: .8), fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        if (m.lowCount > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < m.lowCount; i++)
              Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(right: i < m.lowCount - 1 ? 4 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i < m.lowWon ? elanColor(4) : cs.onSurface.withValues(alpha: .1),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Text(
            '${m.lowCount} pointage${m.lowCount > 1 ? 's' : ''} « Flemme » ou « Mou » ; ${m.lowWon} fois la chose a été faite quand même.',
            style: TextStyle(fontSize: 12, height: 1.35, color: muted),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Aucun pointage « Flemme » ou « Mou » cette semaine.', style: TextStyle(fontSize: 12, color: muted)),
          ),
        const SizedBox(height: 12),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: .4)),
        const SizedBox(height: 10),
        Row(children: [
          _kpi(cs, m.count == 0 ? '—' : m.mean.toStringAsFixed(1).replaceAll('.', ','), 'élan moyen'),
          _kpi(cs, '${m.count}', 'pointages'),
          _kpi(cs, '${m.lowWon}', 'victoires sur la flemme'),
        ]),
      ]),
    );
  }

  Widget _kpi(ColorScheme cs, String v, String l) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
          const SizedBox(height: 3),
          Text(l, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: .55))),
        ]),
      );

  Widget _dayColumn(ColorScheme cs, ElanDay d) {
    final weekday = DateTime.parse(d.ymd).weekday;
    return Column(children: [
      Container(
        height: 110,
        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(children: [
          for (var lv = 5; lv >= 1; lv--)
            Expanded(
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final mk in d.marks.where((x) => x.value == lv))
                  Tooltip(
                    message: '${kElanBucketLabels[mk.bucket] ?? mk.bucket} · ${kElanLabels[mk.value]}${mk.won ? ' · fait' : ' · rien de fait'}',
                    child: Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: elanColor(mk.value).withValues(alpha: mk.won ? 1 : .35),
                      ),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Text(_dayLetters[weekday - 1], style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: .55))),
      const SizedBox(height: 3),
      Container(
        width: 14,
        height: 4,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          color: d.mood == null
              ? cs.onSurface.withValues(alpha: .08)
              : [cs.onSurface.withValues(alpha: .35), const Color(0xFF8E8150), const Color(0xFFB8A86A)][d.mood!],
        ),
      ),
    ]);
  }
}

class _ElanHeatmapCard extends StatelessWidget {
  final List<ElanDay> days;
  const _ElanHeatmapCard({required this.days});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: .55);
    Widget cell(ElanMarkView? mk) => Expanded(
          child: Container(
            height: 26,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: mk == null ? null : elanColor(mk.value),
              border: mk == null ? Border.all(color: cs.outlineVariant.withValues(alpha: .4)) : null,
            ),
            child: mk != null && !mk.won ? Center(child: Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface))) : null,
          ),
        );
    return _card(
      context,
      title: 'Quand l’élan est là',
      sub: 'créneau × jour',
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 72),
          for (final d in days)
            Expanded(child: Center(child: Text(_dayLetters[DateTime.parse(d.ymd).weekday - 1], style: TextStyle(fontSize: 11, color: muted)))),
        ]),
        for (final b in kElanBuckets)
          Row(children: [
            SizedBox(width: 72, child: Text(kElanBucketLabels[b]!, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .8)))),
            for (final d in days) cell(d.marks.where((m) => m.bucket == b).firstOrNull),
          ]),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 4, children: [
          for (var i = 1; i <= 5; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: elanColor(i))),
              const SizedBox(width: 4),
              Text(kElanLabels[i], style: TextStyle(fontSize: 11, color: muted)),
            ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: elanColor(3)), child: Center(child: Container(width: 3, height: 3, decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface)))),
            const SizedBox(width: 4),
            Text('rien de fait ensuite', style: TextStyle(fontSize: 11, color: muted)),
          ]),
        ]),
      ]),
    );
  }
}

/// Créneau d'élan courant (pour les écrans qui posent la question).
String currentElanBucket(AppLogic logic) => elanBucket(logic.livedNowMinNow);

String livedYmdFor(AppLogic logic) => livedProgramYmd(DateTime.now(), logic.dayStartMin);
