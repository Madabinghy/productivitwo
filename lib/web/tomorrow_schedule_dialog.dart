import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/claude_link.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/gantt_axis.dart' show kGanttWeekdaysShort;
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/utils/week_capacity.dart';
import 'package:productivitwo_v1/utils/week_planner.dart' show firstFreeSlot, minToClock;
import 'package:productivitwo_v1/web/desktop_dialog.dart';
import 'package:productivitwo_v1/web/schedule_block_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:url_launcher/url_launcher.dart';

/// « Demain » (Aujourd'hui web) : le programme du lendemain, pour préparer la
/// journée le soir — ajouter, modifier, retirer des blocs, ou demander à
/// Claude de la planifier. ‹ › pour les jours suivants (jamais avant demain).
Future<void> showTomorrowScheduleDialog(BuildContext context, FirestoreSync sync) =>
    showDesktopDialog<void>(context,
        maxWidth: 620, builder: (_) => _TomorrowScheduleDialog(sync: sync));

const _kMonths = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

class _TomorrowScheduleDialog extends StatefulWidget {
  final FirestoreSync sync;
  const _TomorrowScheduleDialog({required this.sync});

  @override
  State<_TomorrowScheduleDialog> createState() => _TomorrowScheduleDialogState();
}

class _TomorrowScheduleDialogState extends State<_TomorrowScheduleDialog> {
  int _offset = 1;
  List<ScheduleBlock>? _blocks;
  StreamSubscription<DailySchedule?>? _sub;
  DayWindow _window = kDefaultDayWindow;

  DateTime get _day {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + _offset);
  }

  String get _date => ymdOf(_day);

  String get _dayTitle {
    final d = _day;
    final name = '${kGanttWeekdaysShort[d.weekday - 1]} ${d.day} ${_kMonths[d.month - 1]}';
    return _offset == 1 ? 'Demain · $name' : name[0].toUpperCase() + name.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _listen();
    widget.sync.fetchDayWindow().then((w) {
      if (mounted) setState(() => _window = w);
    });
  }

  void _listen() {
    _sub?.cancel();
    setState(() => _blocks = null);
    _sub = widget.sync.streamDailySchedule(_date).listen((s) {
      if (!mounted) return;
      setState(() => _blocks = (s?.blocks
              .where((b) => b.status != 'deleted' && b.status != 'skipped')
              .toList() ??
          [])
        ..sort((a, b) => a.startTime.compareTo(b.startTime)));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _go(int delta) {
    final next = _offset + delta;
    if (next < 1) return;
    _offset = next;
    _listen();
  }

  Future<void> _edit(ScheduleBlock b) async {
    final updated = await showScheduleBlockDialog(context, block: b);
    if (updated == null || !mounted) return;
    await widget.sync.upsertScheduleBlock(_date, updated);
  }

  Future<void> _add() async {
    final blocks = _blocks ?? const <ScheduleBlock>[];
    final start = firstFreeSlot(blocks, 30, window: _window) ??
        math.min(blocks.fold<int>(_window.startMin, (m, b) => math.max(m, blockEndMin(b))), 23 * 60 + 30);
    final created = await showScheduleBlockDialog(
      context,
      isNew: true,
      block: ScheduleBlock(startTime: minToClock(start), durationMin: 30, title: ''),
    );
    if (created == null || !mounted) return;
    await widget.sync.upsertScheduleBlock(_date, created);
  }

  Future<void> _askClaude() async {
    final ok = await launchUrl(
        claudeNewUri(planDayPrompt(date: _date, blocks: _blocks ?? const [])),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir Claude')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks;
    final planned = (blocks ?? const <ScheduleBlock>[]).fold<int>(0, (s, b) => s + b.durationMin);
    return Container(
      color: kBSurface,
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(
            tooltip: 'Jour précédent',
            onPressed: _offset > 1 ? () => _go(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: kBText2,
            disabledColor: kBText4,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_dayTitle,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kBText)),
              const SizedBox(height: 2),
              Text(
                  blocks == null
                      ? '…'
                      : blocks.isEmpty
                          ? 'Rien de prévu pour l\'instant'
                          : '${blocks.length} bloc${blocks.length > 1 ? 's' : ''} · ${fmtMin(planned)} prévu',
                  style: const TextStyle(fontSize: 12.5, color: kBText3)),
            ]),
          ),
          IconButton(
            tooltip: 'Jour suivant',
            onPressed: () => _go(1),
            icon: const Icon(Icons.chevron_right_rounded),
            color: kBText2,
          ),
          IconButton(
            tooltip: 'Fermer',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            color: kBText3,
          ),
        ]),
        const SizedBox(height: 12),
        Flexible(
          child: blocks == null
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : blocks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Text('Ajoute des blocs, ou demande à Claude de préparer la journée.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kBText3)),
                    )
                  : ListView(shrinkWrap: true, children: [for (final b in blocks) _row(b)]),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.end, children: [
          OutlinedButton.icon(
            onPressed: _askClaude,
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: const Text('Préparer avec Claude'),
            style: OutlinedButton.styleFrom(
                foregroundColor: kBText2, side: const BorderSide(color: kBLine)),
          ),
          FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Ajouter un bloc'),
            style: FilledButton.styleFrom(backgroundColor: kBPrimary, foregroundColor: kBBg),
          ),
        ]),
      ]),
    );
  }

  Widget _row(ScheduleBlock b) {
    final color = kBCategoryColor[b.category] ?? kBText3;
    final mirror = b.gcalEventId != null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _edit(b),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(children: [
          SizedBox(
            width: 104,
            child: Text('${b.startTime} → ${minToClock(blockEndMin(b) % (24 * 60))}',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: kBText2,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          Container(
              width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(b.title.isEmpty ? 'Sans titre' : b.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: b.status == 'done' ? kBText3 : kBText)),
          ),
          if (mirror)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Tooltip(
                  message: 'Rendez-vous Google Agenda',
                  child: Icon(Icons.event_outlined, size: 15, color: kBText4)),
            ),
          const SizedBox(width: 10),
          Text(fmtMin(b.durationMin),
              style: const TextStyle(fontSize: 12, color: kBText3)),
        ]),
      ),
    );
  }
}
