// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:productivitwo_v1/widgets/deep_work_sheet.dart' show showDeepWorkSheet;
import 'package:productivitwo_v1/widgets/activity_launcher_sheet.dart';
import 'package:productivitwo_v1/widgets/routine_launcher_sheet.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart';
import 'package:productivitwo_v1/utils/notif_digest.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart' show parseMomentWindows, momentWindowsToJson;
import 'package:productivitwo_v1/widgets/moments_editor_sheet.dart';
import 'package:productivitwo_v1/utils/block_queue.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/habit_reconcile.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routineTodayCount;
import 'package:productivitwo_v1/widgets/action_focus_screen.dart' show showBlockFocusScreen;
import 'package:productivitwo_v1/utils/time_scope.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFocusedOn, overdueActionCount, stopTargetCandidates;
import 'package:productivitwo_v1/utils/badges_logic.dart' show countsForBadges;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/claude_link.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/widgets/session_player_screen.dart';
import 'package:productivitwo_v1/widgets/block_work_screen.dart';
import 'package:productivitwo_v1/widgets/alarm_ringtone_sheet.dart';
import 'package:productivitwo_v1/widgets/filters_sheet.dart';
import 'package:productivitwo_v1/widgets/claude_automation_sheet.dart';
import 'package:productivitwo_v1/widgets/gcal_settings_sheet.dart';
import 'package:productivitwo_v1/softpop/softpop_preview_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_home_live_screen.dart';
import 'package:productivitwo_v1/softpop/softpop_shell.dart';
import 'package:productivitwo_v1/widgets/ring_painter.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/mode_colors.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart' show supersededMoodMarks;
import 'package:productivitwo_v1/widgets/mode_sheet.dart';
import 'package:productivitwo_v1/widgets/domain_page.dart';
import 'package:productivitwo_v1/widgets/activity_fiche_sheet.dart';
import 'package:productivitwo_v1/widgets/goals_view.dart';
import 'package:productivitwo_v1/widgets/week_stats_view.dart';
import 'package:productivitwo_v1/widgets/new_routine_sheet.dart';
import 'package:productivitwo_v1/widgets/pest_counter.dart';
import 'package:productivitwo_v1/widgets/objectives_home_view.dart';
import 'package:productivitwo_v1/widgets/actions_view.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/utils/badge_hunt.dart';
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart';
import 'package:productivitwo_v1/widgets/coach_space_sheet.dart';
import 'package:productivitwo_v1/widgets/data_settings_sheet.dart';
import 'package:productivitwo_v1/widgets/next_actions_section.dart'
    show showCreateActionOrProjectSheet;
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart';
import 'package:productivitwo_v1/widgets/day_review_sheet.dart';
import 'package:productivitwo_v1/widgets/domain_session_screen.dart';
import 'package:productivitwo_v1/widgets/onboarding_screen.dart';
import 'package:confetti/confetti.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/embers.dart' show EmberSpend;
import 'package:productivitwo_v1/gamification_flags.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/storage.dart';
import 'package:productivitwo_v1/notifications.dart';
import 'package:alarm/alarm.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:productivitwo_v1/widgets/routine_tile_bits.dart';
import 'package:productivitwo_v1/widgets/time_report_card.dart';
import 'package:productivitwo_v1/widgets/today_logged_pie.dart';
import 'package:productivitwo_v1/widgets/changelog_sheet.dart';
import 'package:productivitwo_v1/widgets/privacy_policy_screen.dart';
import 'package:productivitwo_v1/web/web_app_stub.dart'
    if (dart.library.html) 'package:productivitwo_v1/web/web_app.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/dev_logger.dart';
import 'package:productivitwo_v1/pro_manager.dart';
import 'package:productivitwo_v1/fcm_service.dart';
import 'package:productivitwo_v1/live_activity_service.dart';
import 'package:productivitwo_v1/widgets/paywall_sheet.dart';
import 'package:productivitwo_v1/widgets/apple_sign_in_button.dart';
import 'package:productivitwo_v1/widgets/email_sign_in_tile.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/widgets/project_sheet.dart';
import 'package:productivitwo_v1/widgets/inbox_sheet.dart';
import 'package:productivitwo_v1/widgets/weekly_review_sheet.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/widgets/orion_screen.dart';
import 'package:productivitwo_v1/widgets/habit_count_sheet.dart';
import 'package:productivitwo_v1/widgets/proposals_sheet.dart';
import 'package:productivitwo_v1/widgets/today_view.dart';
import 'package:productivitwo_v1/widgets/task_schedule.dart';
import 'package:productivitwo_v1/web/assistant_engine.dart';
import 'package:productivitwo_v1/web/assistant_widget.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:productivitwo_v1/widget_service.dart';
import 'package:productivitwo_v1/siri_service.dart';

enum _Tab { dashboard, projets, aujourdhui, actions, stats }

class MiniRingThick extends StatelessWidget {
  const MiniRingThick({
    super.key,
    required this.progress,
    required this.center,
    this.strokeWidth = 7,
    this.color,
  });

  final double progress; // 0..1
  final Widget center;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.primary.withOpacity(0.95);
    return CustomPaint(
      painter: _RingPainter(
        progress: progress.clamp(0.0, 1.0),
        strokeWidth: strokeWidth,
        bg: Theme.of(context).colorScheme.onSurface.withOpacity(0.10),
        fg: fg,
      ),
      child: Center(child: center),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.bg,
    required this.fg,
  });

  final double progress;
  final double strokeWidth;
  final Color bg;
  final Color fg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.shortestSide / 2) - strokeWidth / 2;

    final pBg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = bg;

    final pFg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = fg;

    canvas.drawCircle(c, r, pBg);

    final start = -3.1415926535 / 2; // 12h
    final sweep = 2 * 3.1415926535 * progress;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r), start, sweep, false, pFg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.strokeWidth != strokeWidth ||
      old.bg != bg ||
      old.fg != fg;
}

class MiniRing extends StatelessWidget {
  final double progress; // 0..1
  final double size;
  final double stroke;
  final Widget? center;
  const MiniRing(
      {super.key,
      required this.progress,
      this.size = 52,
      this.stroke = 6,
      this.center});

  Color _ringColor(BuildContext c, double p) {
    if (p >= 1) return Colors.green;
    if (p >= .5) return const Color(0xFFFFA000); // orange
    return Theme.of(c).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.onSurface.withOpacity(.12);
    final col = _ringColor(context, progress);
    final p = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(value: 1, strokeWidth: stroke, color: track),
        CircularProgressIndicator(value: p, strokeWidth: stroke, color: col),
        if (center != null) center!,
      ]),
    );
  }
}

class GaugeRing extends StatelessWidget {
  final String label;
  final IconData? labelIcon;
  final String? valueText;
  final double progress; // 0..1
  final double size;
  final Color? color;
  final VoidCallback? onTap;

  final String? centerText;
  final String? subText;

  // NEW
  final double strokeWidth;
  final StrokeCap strokeCap;

  final double? innerProgress; // ex: 90j
  final Color? innerColor;

  final double? outerProgress; // ex: 24h glissantes
  final Color? outerColor;

  const GaugeRing({
    super.key,
    required this.label,
    this.labelIcon,
    this.valueText,
    required this.progress,
    this.size = 130,
    this.color,
    this.onTap,
    this.centerText,
    this.subText,
    this.strokeWidth = 20,
    this.strokeCap = StrokeCap.round, // ⬅️ ICI tu changes round/butt/square
    this.innerProgress,
    this.innerColor,
    this.outerProgress,
    this.outerColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.primary;
    final bg = cs.surfaceContainerHighest.withValues(alpha: 0.35);
    //final bg = Colors.transparent;

    final main = (centerText != null && centerText!.isNotEmpty)
        ? centerText!
        : (valueText ?? "");

    final innerW = size * 0.74;

    final ring = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (_, val, __) {
        final hasOuter = outerProgress != null;
        final outerAbove = hasOuter && outerProgress! > val;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
// Halo “derrière” si outer > main, sinon “devant”
              if (hasOuter && outerAbove)
                CustomPaint(
                  size: Size.square(size * 1.08),
                  painter: GaugeRingPainter(
                    progress: outerProgress!.clamp(0.0, 1.0),
                    fg: Colors.cyanAccent.withValues(alpha: 0.45),
                    bg: Colors.transparent,
                    strokeWidth: strokeWidth,
                    cap: StrokeCap.round,
                  ),
                ),

              CustomPaint(
                size: Size.square(size),
                painter: GaugeRingPainter(
                  progress: val,
                  fg: fg,
                  bg: bg,
                  strokeWidth: strokeWidth,
                  cap: strokeCap,
                ),
              ),

              if (hasOuter && !outerAbove)
                CustomPaint(
                  size: Size.square(size * 1.08),
                  painter: GaugeRingPainter(
                    progress: outerProgress!.clamp(0.0, 1.0),
                    fg: Colors.cyanAccent.withValues(alpha: 0.45),
                    bg: Colors.transparent,
                    strokeWidth: strokeWidth,
                    cap: StrokeCap.butt,
                  ),
                ),

              // ✅ INNER ring (90j)
              if (innerProgress != null)
                CustomPaint(
                  size: Size.square(size * 0.78),
                  painter: GaugeRingPainter(
                    progress: innerProgress!.clamp(0.0, 1.0),
                    fg: (innerColor ?? fg).withValues(alpha: 0.80),
                    bg: Colors.transparent,
                    strokeWidth: strokeWidth * 0.55,
                    cap: strokeCap,
                  ),
                ),

              // ✅ TEXTE AU CENTRE (il doit être après les CustomPaint)
              SizedBox(
                width: innerW,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            main,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                          if ((subText ?? "").isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subText!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.70),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    labelIcon != null
                        ? Icon(labelIcon, size: 16,
                            color: cs.onSurface.withValues(alpha: 0.55))
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    return onTap == null
        ? ring
        : InkWell(
            borderRadius: BorderRadius.circular(size),
            onTap: onTap,
            child: ring,
          );
  }
}

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const SectionCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(12)});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: padding, child: child),
    );
  }
}

class StatsView extends StatefulWidget {
  final AppLogic logic;
  final AppState state;
  final String? selectedDomainId;
  final ScrollController? scrollController;
  final FirestoreSync? sync;
  final VoidCallback? onDataChanged;

  const StatsView({
    super.key,
    required this.logic,
    required this.state,
    required this.selectedDomainId,
    this.scrollController,
    this.sync,
    this.onDataChanged,
  });

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  int days = 30; // 7 ou 30
  bool onlyDomain = true; // Domaine sélectionné vs Tous
  String? statsDomainId; // null = Tous

  @override
  void initState() {
    super.initState();
    widget.logic
        .rolloverUndone(); // 👈 Ramène les non-faits d'hier vers aujourd'hui
    statsDomainId = widget.selectedDomainId; // point de départ UNIQUEMENT
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));

    // Données
    final String? domainId = statsDomainId; // null => Tous domaines
    final hours = widget.logic.timeHoursPerDay(start, days, domainId: domainId);
    final habits =
        widget.logic.habitCountPerDay(start, days, domainId: domainId);
    //final habitDailyTarget = widget.logic.habitDailyTarget(domainId: domainId);
// AFTER (derived from the new habit model)
    final habitDailyTarget = widget.logic.sumHabitTarget(domainId, 1);
    final habitTotalTarget = habitDailyTarget * days;
    // avant de construire les charts :
    final maxHabitsY = ([
          (habits.isEmpty ? 0 : habits.reduce((a, b) => a > b ? a : b))
              .toDouble(),
          habitDailyTarget.toDouble()
        ].reduce((a, b) => a > b ? a : b)).ceilToDouble() +
        1;

    // Labels X
    final xLabels = List.generate(days, (i) {
      final d = start.add(Duration(days: i));
      return (days == 30)
          ? "${d.day}" // ← seulement le numéro du jour
          : "${d.day}/${d.month}";
    });

    return Column(
      children: [
        // Contrôles (jours / filtre)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 j')),
                  ButtonSegment(value: 30, label: Text('30 j')),
                ],
                selected: {days},
                onSelectionChanged: (s) => setState(() => days = s.first),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Domaine :'),
                  const SizedBox(width: 8),
                  DropdownButton<String?>(
                    value: statsDomainId, // peut être null
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Tous')),
                      ...widget.state.activeDomains.map((d) {
                        final dColor = domainColor(
                                d.id, widget.state.activeDomains) ??
                            Theme.of(context).colorScheme.primary;
                        return DropdownMenuItem<String?>(
                          value: d.id,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: dColor,
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Text(d.name),
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: (v) =>
                        setState(() => statsDomainId = v),
                  )
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              const Text('Temps (heures / jour)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ClipRect(
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 24,
                      gridData: const FlGridData(show: true),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          axisNameWidget: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text('Temps (heures / jour)'),
                              SizedBox(height: 4), // ← marge supplémentaire
                            ],
                          ),
                          axisNameSize: 24, // espace pour le titre de l'axe Y
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize:
                                44, // marge à gauche pour éviter les collisions
                            getTitlesWidget: (val, meta) {
                              // n'afficher que les entiers (0,1,2,...)
                              if (val % 1 != 0) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  val.toInt().toString(),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            getTitlesWidget: (val, meta) {
                              final i = val.toInt();
                              if (i < 0 || i >= xLabels.length)
                                return const SizedBox.shrink();
                              // en 30 j : 1 label sur 3
                              if (days == 30 && i % 3 != 0)
                                return const SizedBox.shrink();
                              return SizedBox(
                                width: 28,
                                child: Transform.rotate(
                                  angle: -0.7, // ~ -40°
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    xLabels[i],
                                    style: const TextStyle(fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          isCurved: true,
                          barWidth: 3,
                          color: domainColor(statsDomainId,
                              widget.state.activeDomains) ??
                              Theme.of(context).colorScheme.primary,
                          belowBarData: BarAreaData(
                            show: true,
                            color: (domainColor(statsDomainId,
                                        widget.state.activeDomains) ??
                                    Theme.of(context).colorScheme.primary)
                                .withOpacity(.10),
                          ),
                          spots: List.generate(
                              days, (i) => FlSpot(i.toDouble(), hours[i])),
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Habitudes (total: ${habits.fold<int>(0, (a, b) => a + b)} / $habitTotalTarget)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ClipRect(
                  child: BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: maxHabitsY,
                      gridData: const FlGridData(show: true),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          axisNameWidget: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text('Habitudes / jour'),
                              SizedBox(height: 4),
                            ],
                          ),
                          axisNameSize: 24,
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (val, meta) {
                              if (val % 1 != 0) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  val.toInt().toString(),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            getTitlesWidget: (val, meta) {
                              final i = val.toInt();
                              if (i < 0 || i >= xLabels.length)
                                return const SizedBox.shrink();
                              if (days == 30 && i % 3 != 0)
                                return const SizedBox.shrink();
                              return SizedBox(
                                width: 28,
                                child: Transform.rotate(
                                  angle: -0.7,
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    xLabels[i],
                                    style: const TextStyle(fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(
                        days,
                        (i) => BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: habits[i].toDouble(),
                              color: domainColor(statsDomainId,
                                      widget.state.activeDomains) ??
                                  Theme.of(context).colorScheme.primary,
                            )
                          ],
                        ),
                      ),
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          if (habitDailyTarget > 0)
                            HorizontalLine(
                                y: habitDailyTarget.toDouble(),
                                color: (domainColor(statsDomainId,
                                            widget.state.activeDomains) ??
                                        Theme.of(context).colorScheme.primary)
                                    .withOpacity(.6),
                                dashArray: [6, 4]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 16),
            ProGate(
              featureName: 'Rapport de temps',
              child: TimeReportCard(logic: widget.logic, days: days),
            ),
            const SizedBox(height: 40),
            if (widget.sync != null) ...[
              const Divider(),
              const SizedBox(height: 8),
              AppleSignInTile(
                sync: widget.sync!,
                state: widget.state,
                onDataChanged: widget.onDataChanged ?? () {},
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 60),
            ],
          ),
        ),
      ],
    );
  }
}

final _navigatorKey = GlobalKey<NavigatorState>();

/// Flag refonte : true = nouvelle UI Soft Pop (shell) par défaut au lancement.
/// Persisté dans SharedPreferences ('ui_softpop'). Réversible à tout moment.
final ValueNotifier<bool> softpopShellEnabled = ValueNotifier<bool>(false);

Future<void> setSoftpopShell(bool v) async {
  softpopShellEnabled.value = v;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ui_softpop', v);
  } catch (_) {}
}

Future<void> loadSoftpopShellFlag() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    softpopShellEnabled.value = prefs.getBool('ui_softpop') ?? false;
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // Web : Firebase uniquement — timeout 10s pour éviter un blocage sur Firefox/Safari
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
                options: DefaultFirebaseOptions.currentPlatform)
            .timeout(const Duration(seconds: 10),
                onTimeout: () =>
                    throw TimeoutException('Firebase init timeout on web'));
      }
    } catch (e) {
      devLog.error('Firebase.initializeApp FAIL on web', tag: 'MAIN', error: e);
    }
    debugPrint('▶ PRODUCTIVITWO WEB — $kWebBuildTag');
    runApp(const WebApp());
    return;
  }

  // Mobile / desktop — Firebase DOIT être initialisé AVANT ProManager
  // (qui lit le grant Pro via Firestore/Auth dans init()).
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform);
      }
      devLog.log('Firebase.initializeApp OK', tag: 'MAIN');
    } catch (e) {
      devLog.error('Firebase.initializeApp FAIL', tag: 'MAIN', error: e);
    }
  }
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    try {
      await ProManager.init();
    } catch (e) {
      devLog.error('ProManager.init FAIL', tag: 'MAIN', error: e);
    }
  }
  try {
    await NotificationService.init();
  } catch (e) {
    devLog.error('NotificationService.init FAIL', tag: 'MAIN', error: e);
  }
  try {
    await Alarm.init();
    // Avertissement (FR) affiché si l'app est tuée alors qu'un minuteur tourne :
    // sur iOS, une app fermée ne peut pas faire sonner l'alarme.
    await Alarm.setWarningNotificationOnKill(
      'Minuteur interrompu',
      'Garde Productivitwo en arrière-plan (ne la ferme pas) pour que l\'alarme sonne à la fin.',
    );
  } catch (e) {
    devLog.error('Alarm.init FAIL', tag: 'MAIN', error: e);
  }
  await loadSoftpopShellFlag(); // refonte : UI Soft Pop par défaut ?
  runApp(const ProductivitwoApp());
}

class ProductivitwoApp extends StatelessWidget {
  const ProductivitwoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DayMode>(
      valueListenable: AppLogic.modeNotifier,
      builder: (context, mode, _) => MaterialApp(
      navigatorKey: _navigatorKey,
      locale: const Locale('fr', 'FR'),

      supportedLocales: const [
        Locale('fr', 'FR'),
      ],

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      title: 'Productivitwo',
      theme: _buildTheme(Brightness.light, mode),
      darkTheme: _buildTheme(Brightness.dark, mode),
      themeMode: ThemeMode.system, // clair/sombre selon l'iPhone
      // Overlay assistant AU-DESSUS du Navigator → visible même par-dessus les
      // bottom sheets (sinon il était caché derrière, jamais vu).
      builder: (context, child) => GlobalAssistantOverlay(child: child!),
      home: const AppRoot(),
      ),
    );
  }
}

/// L'accent suit le mode du jour (ambiance, lot 1 Modes et coups) : Flemme
/// ambre, Normal teal, En forme teal électrique.
ThemeData _buildTheme(Brightness brightness, [DayMode mode = DayMode.normal]) {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: modeSeed(mode),
    brightness: brightness,
  );
  final cs = base.colorScheme;
  return base.copyWith(
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(.35)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    dividerTheme: DividerThemeData(
      color: cs.outlineVariant.withOpacity(.4),
      thickness: 1,
      space: 1,
    ),
  );
}

enum TimeScope { day, week, month }

class _EditSessionResult {
  final bool delete;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? activityId;
  /// Bloc du programme à rattacher après coup (null = inchangé) ;
  /// [detachBlock] = retirer la tâche / l'action de la session.
  final ScheduleBlock? block;
  final bool detachBlock;

  const _EditSessionResult._({
    required this.delete,
    this.startAt,
    this.endAt,
    this.activityId,
    this.block,
    this.detachBlock = false,
  });

  factory _EditSessionResult.delete() =>
      const _EditSessionResult._(delete: true);

  factory _EditSessionResult.save({
    DateTime? startAt,
    DateTime? endAt,
    String? activityId,
    ScheduleBlock? block,
    bool detachBlock = false,
  }) =>
      _EditSessionResult._(
        delete: false,
        startAt: startAt,
        endAt: endAt,
        activityId: activityId,
        block: block,
        detachBlock: detachBlock,
      );
}

class _EditSessionSheet extends StatefulWidget {
  final Session session;
  final AppLogic logic;

  const _EditSessionSheet({
    required this.session,
    required this.logic,
  });

  @override
  State<_EditSessionSheet> createState() => _EditSessionSheetState();
}

class _EditSessionSheetState extends State<_EditSessionSheet> {
  late DateTime _start;
  DateTime? _end;
  late String _activityId;
  // Rattachement après coup : blocs du jour de la session (chargés une fois).
  List<ScheduleBlock> _dayBlocks = const [];
  bool _blocksLoaded = false;
  ScheduleBlock? _block;
  bool _detachBlock = false;

  @override
  void initState() {
    super.initState();
    _start = widget.session.startAt;
    _end = widget.session.endAt;
    _activityId = widget.session.activityId;
    _loadDayBlocks();
  }

  DateTime get _day => DateTime(_start.year, _start.month, _start.day);
  String get _dayKey =>
      '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';

  Future<void> _loadDayBlocks() async {
    final sched = await FirestoreSync().fetchDailySchedule(_dayKey);
    if (!mounted) return;
    setState(() {
      // Les blocs retirés du programme restent rattachables (proposés en fin
      // de liste) ; pour l'affichage, un bloc vivant prime.
      _dayBlocks = sched?.blocks.toList() ?? const [];
      _blocksLoaded = true;
      _block = _dayBlocks.where((b) => b.status != 'deleted').where(_sessionOn).firstOrNull ??
          _dayBlocks.where(_sessionOn).firstOrNull;
    });
  }

  Activity? _actOf(String? id) =>
      id == null ? null : widget.logic.state.activities.firstWhereOrNull((a) => a.id == id);
  Project? _projOf(String? id) =>
      id == null ? null : widget.logic.currentProjects.firstWhereOrNull((p) => p.id == id);

  bool _sessionOn(ScheduleBlock b) => sessionMatchesBlock(widget.session, b,
      projectLinkedActivityId: _projOf(b.projectId)?.linkedActivityId,
      activityLinkedActivityId: _actOf(b.activityId)?.linkedActivityId);

  /// Libellé « Tâche › action » de la session, en tenant compte d'un bloc
  /// choisi mais pas encore enregistré.
  String? _targetLabel() {
    final s = widget.session;
    final b = _block;
    final preview = b != null && !_sessionOn(b)
        ? (Session(activityId: s.activityId, startAt: s.startAt, taskId: b.taskId, actionId: b.actionId))
        : s;
    return sessionTargetLabel(preview,
        projects: widget.logic.currentProjects, activities: widget.logic.state.activities);
  }

  Future<void> _pickBlock(BuildContext context) async {
    final candidates = blockCandidatesForSession(widget.session, _dayBlocks, _day,
        activityOf: _actOf, projectOf: _projOf);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Pour quel bloc compte ce temps ?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          ListTile(
            leading: const Icon(Icons.block_outlined),
            title: const Text('Aucun — hors bloc'),
            onTap: () => Navigator.pop(context, ''),
          ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text('Aucun bloc rattachable ce jour-là (il faut un bloc de tâche ou d\'activité).',
                  style: TextStyle(fontSize: 13)),
            ),
          for (final c in candidates)
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: Text(c.block.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${c.block.startTime} · ${c.block.durationMin} min'
                  '${c.overlapMin > 0 ? ' · ${c.overlapMin} min en commun' : ''}'
                  '${c.block.status == 'deleted' ? ' · retiré du programme' : ''}'),
              onTap: () => Navigator.pop(context, c.block.id),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (picked.isEmpty) {
        _block = null;
        _detachBlock = true;
      } else {
        _block = _dayBlocks.firstWhereOrNull((b) => b.id == picked);
        _detachBlock = false;
      }
    });
  }

  Future<String?> _pickActivity(BuildContext context) {
    final st = widget.logic.state;
    // Activités-temps (celle de la session en plus si c'est une routine).
    final acts = st.activities.where((a) => !a.deleted && (!a.isHabit || a.id == _activityId)).toList();
    final cur = st.activities.where((a) => a.id == _activityId).firstOrNull;
    return showActivityPicker(context,
        activities: acts,
        domains: st.activeDomains,
        title: 'Activité de la session',
        selectedId: _activityId,
        preferDomainId: cur?.domainId);
  }

  String _activityName(BuildContext context, String activityId) {
    final a = widget.logic.state.activities.firstWhere(
      (x) => x.id == activityId,
      orElse: () => Activity(domainId: '', name: 'Activité', habitTarget: 1),
    );

    return a.name.isEmpty ? "Activité" : a.name;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dur = (_end ?? now).difference(_start);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Modifier la session",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Activité"),
              subtitle: Text(_activityName(context, _activityId)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final selected = await _pickActivity(context);
                if (selected != null) {
                  setState(() => _activityId = selected);
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Début"),
              subtitle: Text(_fmtDateTime(_start)),
              onTap: () async {
                final dt = await _pickDateTime(context, _start);
                if (dt != null) setState(() => _start = dt);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Fin"),
              subtitle: Text(_end == null ? "En cours" : _fmtDateTime(_end!)),
              trailing: _end == null
                  ? TextButton(
                      onPressed: () => setState(() => _end = now),
                      child: const Text("Mettre maintenant"),
                    )
                  : TextButton(
                      onPressed: () => setState(() => _end = null),
                      child: const Text("Marquer en cours"),
                    ),
              onTap: () async {
                final base = _end ?? now;
                final dt = await _pickDateTime(context, base);
                if (dt != null) setState(() => _end = dt);
              },
            ),
            // Rattachement après coup : le temps de la session compte pour ce
            // bloc (elle prend sa tâche / son action, même règle que « Pour ce bloc »).
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Bloc du programme"),
              subtitle: Text(!_blocksLoaded
                  ? "Chargement…"
                  : _detachBlock
                      ? "Aucun — hors bloc"
                      : _block == null
                          ? "Aucun — hors bloc"
                          : "${_block!.startTime} · ${_block!.title}"
                              "${_block!.status == 'deleted' ? ' (retiré du programme)' : ''}"),
              trailing: const Icon(Icons.chevron_right),
              onTap: _blocksLoaded ? () => _pickBlock(context) : null,
            ),
            // Ce pour quoi compte la session (tâche › action), même sans bloc
            // visible : le bloc peut avoir disparu du programme, pas le lien.
            if (!_detachBlock && _targetLabel() != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined),
                title: const Text("Pour"),
                subtitle: Text(_targetLabel()!),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text("Durée : ${_fmtDur(dur)}"),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, _EditSessionResult.delete()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text("Supprimer"),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final e = _end;
                    if (e != null && !e.isAfter(_start)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text("La fin doit être après le début.")),
                      );
                      return;
                    }
                    Navigator.pop(
                      context,
                      _EditSessionResult.save(
                        startAt: _start,
                        endAt: _end,
                        activityId: _activityId,
                        // Inchangé si l'utilisateur n'a pas touché au bloc.
                        block: _detachBlock || _block == null || _sessionOn(_block!) ? null : _block,
                        detachBlock: _detachBlock,
                      ),
                    );
                  },
                  child: const Text("Enregistrer"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _pickDateTime(
      BuildContext context, DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return null;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (t == null) return null;

    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  String _fmtDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}";
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h <= 0) return "${m}m";
    return "${h}h${m.toString().padLeft(2, '0')}";
  }
}

class RunningChipAppBar extends StatefulWidget {
  final AppState? state;
  final AppLogic logic;
  final VoidCallback? onTap; // ex: aller sur l'onglet Maintenant

  const RunningChipAppBar({
    super.key,
    required this.state,
    required this.logic,
    this.onTap,
  });

  @override
  State<RunningChipAppBar> createState() => _RunningChipAppBarState();
}

class _RunningChipAppBarState extends State<RunningChipAppBar> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _ensureTicking();
  }

  @override
  void didUpdateWidget(covariant RunningChipAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureTicking();
  }

  void _ensureTicking() {
    final st = widget.state;
    final hasRunning = st != null && st.sessions.any((x) => x.endAt == null);

    if (hasRunning) {
      _t ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
    } else {
      _t?.cancel();
      _t = null;
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? "${h}h ${m}m ${sec}s" : "${m}m ${sec}s";
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    if (st == null) return const SizedBox.shrink();

    final s = st.sessions.lastWhere(
      (x) => x.endAt == null,
      orElse: () => Session(
        id: '',
        activityId: '',
        startAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    if (s.id.isEmpty) return const SizedBox.shrink();

    final a = st.activities.firstWhere(
      (x) => x.id == s.activityId,
      orElse: () => Activity(domainId: '', name: 'Activité', habitTarget: 1),
    );

    final dur = DateTime.now().difference(s.startAt);
    final label = "${a.name} · ${_fmt(dur)}";
    final cs = Theme.of(context).colorScheme;
    final runningColor = domainColor(a.domainId, st.activeDomains) ?? cs.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: runningColor.withOpacity(0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, size: 16, color: runningColor),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: GestureDetector(
              onTap: widget.onTap,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: runningColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => widget.logic.stopActive(),
            child: Icon(Icons.stop, size: 16, color: runningColor),
          ),
        ],
      ),
    );
  }
}

class RunningActivityBanner extends StatefulWidget {
  final AppState? state;
  final AppLogic logic;
  final VoidCallback? onTap;
  final DateTime? countdownEndsAt;

  const RunningActivityBanner({
    super.key,
    required this.state,
    required this.logic,
    this.onTap,
    this.countdownEndsAt,
  });

  @override
  State<RunningActivityBanner> createState() => _RunningActivityBannerState();
}

class _RunningActivityBannerState extends State<RunningActivityBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _clock?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h}h $m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    if (st == null) return const SizedBox.shrink();

    final session = st.sessions.lastWhereOrNull((s) => s.endAt == null);
    if (session == null) return const SizedBox.shrink();

    final activity = st.activities.firstWhereOrNull(
            (a) => a.id == session.activityId) ??
        Activity(domainId: '', name: 'Activité', habitTarget: 1);

    final elapsed = DateTime.now().difference(session.startAt);
    final cs = Theme.of(context).colorScheme;
    final bandColor = domainColor(activity.domainId, st.activeDomains) ?? cs.primary;

    // Countdown : calcul du temps restant
    final endsAt = widget.countdownEndsAt;
    final remaining = endsAt != null ? endsAt.difference(DateTime.now()) : null;
    final isCountdown = remaining != null && remaining > Duration.zero;
    final timeColor = isCountdown
        ? (remaining.inSeconds < 60 ? Colors.red.shade400 : Colors.orange.shade600)
        : bandColor;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 38,
        color: bandColor.withOpacity(0.18),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bandColor.withOpacity(0.4 + 0.6 * _pulse.value),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                activity.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCountdown)
              Icon(Icons.timer_outlined, size: 13, color: timeColor),
            if (isCountdown) const SizedBox(width: 4),
            Text(
              isCountdown ? _fmt(remaining) : _fmt(elapsed),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: timeColor,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () async {
                final (_, name, delta) =
                    await widget.logic.stopActiveWithAdjustment();
                setState(() {});
                if (delta != null && delta > 0 && name != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Objectif ajusté : $name +${delta}min'),
                    duration: const Duration(seconds: 3),
                  ));
                }
              },
              child: Icon(Icons.stop_rounded,
                  size: 20, color: bandColor),
            ),
          ],
        ),
      ),
    );
  }
}

class RunningBannerGlobal extends StatefulWidget {
  final AppState? state; // mets ton vrai type
  final AppLogic logic; // mets ton vrai type

  const RunningBannerGlobal({
    super.key,
    required this.state,
    required this.logic,
  });

  @override
  State<RunningBannerGlobal> createState() => _RunningBannerGlobalState();
}

class _RunningBannerGlobalState extends State<RunningBannerGlobal> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _ensureTicking();
  }

  @override
  void didUpdateWidget(covariant RunningBannerGlobal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureTicking(); // démarre/stoppe selon présence d'une session
  }

  void _ensureTicking() {
    final st = widget.state;
    final hasRunning = st != null && st.sessions.any((x) => x.endAt == null);

    if (hasRunning) {
      _t ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {}); // rebuild seulement CE widget
      });
    } else {
      _t?.cancel();
      _t = null;
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? "${h}h ${m}m ${sec}s" : "${m}m ${sec}s";
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    if (st == null) return const SizedBox.shrink();

    final activeSessions = st.sessions.where((x) => x.endAt == null).toList();
    if (activeSessions.isEmpty) return const SizedBox.shrink();

    final s = activeSessions.last;

    final a = st.activities.firstWhere(
      (x) => x.id == s.activityId,
      orElse: () => Activity(domainId: '', name: 'Activité', habitTarget: 1),
    );

    final dur = DateTime.now().difference(s.startAt);
    final domainCol = domainColor(a.domainId, st.activeDomains);
    final runColor = domainCol ?? Colors.green;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 84),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: runColor.withOpacity(0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: runColor.withOpacity(0.25), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: runColor, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "En cours depuis",
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.75),
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    _fmt(dur),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 104,
              height: 40,
              child: FilledButton.icon(
                onPressed: () =>
                    widget.logic.stopActive(), // pas besoin de setState ici
                icon: const Icon(Icons.stop, size: 18),
                label: const Text("Stop"),
                style: FilledButton.styleFrom(
                  backgroundColor: runColor,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton doré « Challenge me » en tête du lanceur d'activité.
/// Feuille « Modifier la session » (début, fin, activité, bloc du programme,
/// suppression), partagée par « Dernières 24 h » et la fiche activité.
/// Renvoie `true` quand la session a changé.
Future<bool> openEditSessionSheet(
  BuildContext context,
  AppLogic logic,
  Session s, {
  FirestoreSync? sync,
}) async {
  final res = await showModalBottomSheet<_EditSessionResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EditSessionSheet(
      session: s,
      logic: logic,
    ),
  );

  if (res == null) return false;

  if (res.delete) {
    logic.deleteSession(s.id);
    sync?.deleteSession(s.id); // hard-delete Firestore — évite le retour au prochain pull
    return true;
  }

  final newStart = res.startAt ?? s.startAt;
  final newEnd = res.endAt;

  if (newEnd != null && !newEnd.isAfter(newStart)) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("La fin doit être après le début.")),
    );
    return false;
  }

  logic.updateSession(
    s.id,
    startAt: res.startAt,
    endAt: res.endAt,
    activityId: res.activityId,
  );
  // Rattachement après coup à un bloc (ou détachement) : la session garde
  // son activité et prend la tâche / l'action du bloc ; un bloc sans tâche
  // sur une autre activité prend celle du chrono (le chrono fait foi).
  if (res.detachBlock) {
    s.taskId = null;
    s.actionId = null;
    logic.onChange();
    sync?.saveSession(s);
  } else if (res.block != null) {
    final b = res.block!;
    final acts = (logic.state.activities as List).cast<Activity>();
    final projs = (logic.currentProjects as List).cast<Project>();
    final r = attachSessionToBlock(s, b,
        blockActivity: acts.firstWhereOrNull((a) => a.id == b.activityId),
        project: projs.firstWhereOrNull((p) => p.id == b.projectId));
    if (r != AttachResult.none) {
      logic.onChange();
      sync?.saveSession(s);
      if (r == AttachResult.sessionAndBlock) {
        final d = s.startAt;
        final ymd =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        sync?.upsertScheduleBlock(ymd, b);
      }
    }
  }
  return true;
}

class _Last24hSessionsSheet extends StatefulWidget {
  final dynamic logic;
  final FirestoreSync? sync;
  const _Last24hSessionsSheet({required this.logic, this.sync});

  @override
  State<_Last24hSessionsSheet> createState() => _Last24hSessionsSheetState();
}

class _Last24hSessionsSheetState extends State<_Last24hSessionsSheet> {
  dynamic get logic => widget.logic;
  FirestoreSync? get sync => widget.sync;

  @override
  void initState() {
    super.initState();
    // Refresh temps réel : toute modification (édition/suppression, chrono en
    // cours) rafraîchit la liste sans avoir à quitter le widget.
    logic.rev?.addListener(_onRev);
  }

  @override
  void dispose() {
    logic.rev?.removeListener(_onRev);
    super.dispose();
  }

  void _onRev() {
    if (mounted) setState(() {});
  }

  void _deleteSession(Session s) {
    logic.deleteSession(s.id);
    sync?.deleteSession(s.id); // hard-delete Firestore — évite le retour au prochain pull
    if (mounted) setState(() {});
  }

  /// Couleur du domaine de l'activité d'une session (null si introuvable).
  Color? _domainColorFor(Session s) {
    final acts = (logic.state.activities as List).cast<Activity>();
    final a = acts.firstWhereOrNull((x) => x.id == s.activityId);
    if (a == null) return null;
    return domainColor(
        a.domainId, (logic.state.activeDomains as List).cast<Domain>());
  }

  Future<void> _openEditSessionSheet(BuildContext context, dynamic logic, Session s) async {
    final changed = await openEditSessionSheet(context, logic as AppLogic, s, sync: sync);
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final from = now.subtract(const Duration(hours: 24));

    // 1) filtre sessions intersectant les dernières 24h
    final List<Session> sessions = (logic.state.sessions as List)
        .cast<Session>()
        .where((s) => _intersectsWindow(s.startAt, s.endAt, from, now))
        .toList()
      ..sort((Session a, Session b) => b.startAt.compareTo(a.startAt));

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.access_time_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Dernières 24h',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (sessions.isNotEmpty)
                  Text(
                    '${sessions.length} session${sessions.length > 1 ? 's' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: .6)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text("Aucune session sur les dernières 24h."),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    final actName = _activityName(logic, s.activityId);

                    final end = s.endAt;
                    final dur = s.duration;
                    final dColor = _domainColorFor(s) ?? cs.primary;

                    return Dismissible(
                      key: ValueKey(s.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: cs.errorContainer,
                        child: Icon(Icons.delete_outline,
                            color: cs.onErrorContainer),
                      ),
                      onDismissed: (_) => _deleteSession(s),
                      child: ListTile(
                        minLeadingWidth: 6,
                        leading: Container(
                          width: 4,
                          height: 34,
                          decoration: BoxDecoration(
                            color: dColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        title: Text(
                          actName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          "${_hm(s.startAt)} → ${end == null ? "en cours" : _hm(end)}  •  ${_fmtDur(dur)}",
                        ),
                        onTap: () => _openEditSessionSheet(context, logic, s),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () =>
                              _openEditSessionSheet(context, logic, s),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _intersectsWindow(
      DateTime start, DateTime? end, DateTime wStart, DateTime wEnd) {
    final e = end ?? DateTime.now();
    // intersection si start < wEnd ET end > wStart
    return start.isBefore(wEnd) && e.isAfter(wStart);
  }

  String _activityName(dynamic logic, String activityId) {
    // Comme ton runningActivity(): fallback Activity si introuvable
    final a = logic.state.activities.firstWhere(
      (x) => x.id == activityId,
      orElse: () => Activity(domainId: '', name: 'Activité', habitTarget: 1),
    );
    return (a.name.isEmpty) ? "Activité" : a.name;
  }

  String _hm(DateTime d) =>
      "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h <= 0) return "${m}m";
    return "${h}h${m.toString().padLeft(2, '0')}";
  }
}


class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final store = FileStore();
  final _sync = FirestoreSync();
  late final BadgeCenter _badges = BadgeCenter(logic: logic, sync: _sync);
  String _syncStatus = ''; // '' = en cours, '☁️' = OK, '⚠️' = local
  DateTime _lastGlobalScan = DateTime.fromMillisecondsSinceEpoch(0);
  AppState? _state;
  late AppLogic logic;
  StreamSubscription<Map<String, dynamic>>? _dayStartSub;

  /// Suit `data/meta` pour la journée vécue des routines (`dayStartMin`) et
  /// les bornes des moments (`momentWindows`) : posés sur AppLogic, les vues
  /// se recalculent via onChange.
  void _bindDayStart() {
    _dayStartSub?.cancel();
    _dayStartSub = _sync.streamMetaDoc().listen((m) {
      final start = parseDayStartMin(m['dayStartMin']);
      final windows = parseMomentWindows(m['momentWindows']);
      final hunts = parseBadgeHunts(m['badgeHunts']);
      final spends = EmberSpend.listFrom(m['emberSpends']);
      final sameSpends = spends.map((x) => x.toJson().toString()).join('|') == logic.emberSpends.map((x) => x.toJson().toString()).join('|');
      final elanAll = m['elanPromptsAll'] == true;
      final rest = parseRestDomains(m['restDomains']);
      final budget = parseBudgetWindowDays(m['budgetWindowDays']);
      final sameHunts = hunts.map((h) => h.toJson().toString()).join('|') == logic.badgeHunts.map((h) => h.toJson().toString()).join('|');
      final same = logic.dayStartMin == start &&
          momentWindowsToJson(logic.momentWindows).toString() == momentWindowsToJson(windows).toString() &&
          sameHunts &&
          sameSpends &&
          logic.elanPromptsAll == elanAll &&
          logic.budgetWindowDays == budget &&
          rest.toString() == logic.restDomains.toString();
      if (same) return;
      logic.dayStartMin = start;
      logic.momentWindows = windows;
      logic.badgeHunts = hunts;
      logic.emberSpends = spends;
      logic.elanPromptsAll = elanAll;
      logic.restDomains = rest;
      logic.budgetWindowDays = budget;
      logic.onChange();
    });
  }
  String? selectedDomainId;
  TimeScope scope = TimeScope.day;
  Timer? _heartbeat;
  _Tab _tab = _Tab.aujourdhui;
  // Onglet unique Aujourd'hui (handoff iOS 2026-09, PR 2) : toute navigation
  // « vers Maintenant » atterrit ici, carte MAINTENANT en tête.
  final _todayKey = GlobalKey<TodayViewState>();
  _Tab _goNowTab() {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _todayKey.currentState?.scrollToTop());
    return _Tab.aujourdhui;
  }
// affiché une seule fois tant que l'app reste ouverte

  Timer? _saveDebounce;
  Timer? _countdownTimer;
  DateTime? _countdownEndsAt;
  // Minuteur d'activité → vraie alarme (package `alarm`, sonne même en arrière-plan).
  static const int _timerAlarmId = 42;
  StreamSubscription<AlarmSettings>? _alarmRingSub;
  String? _countdownActivityName;
  int? _countdownTotalSec; // durée totale du minuteur en cours (pour l'anneau)
  String? _countdownRoutineId; // si le minuteur a été lancé pour une routine
  // Nœud d'expédition à franchir SI ce minuteur va à son terme (mode 5 min du
  // donjon). Annuler le minuteur = pas d'avancement. Reposé à chaque lancement.
  String? _countdownExpeditionNode;
  int _countdownExpeditionBonus = 0;
  bool _saveQueued = false;
  bool _saving = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<Uri?>? _deepLinkSub;
  // Lien reçu au cold-start avant que l'état soit chargé → rejoué quand l'app est prête.
  Uri? _pendingDeepLink;
  StreamSubscription<List<Domain>>? _domainsSub;
  StreamSubscription<List<Project>>? _projectsSub;
  StreamSubscription<List<Session>>? _sessionsSub;
  StreamSubscription<List<CaptureItem>>? _inboxSub;
  int _inboxPendingCount = 0;
  List<Project> _dashboardProjects = [];
  Project? _focusProject;
  ProjectTask? _focusTask;
  // Activité chronométrée pour la tâche focus → sert à purger le focus quand on
  // arrête OU quand on lance une AUTRE activité (voir _buildBody).
  String? _focusActivityId;
  bool _wasOffline = false;
  // Session Apple/email perdue au démarrage (voir _init) : bannière jusqu'à
  // la reconnexion — les données restent locales, rien ne se synchronise.
  bool _authLost = false;
  StreamSubscription<String?>? _authSub;

  late final ValueNotifier<int> _tick; // seconds
  late final ConfettiController _confettiController;
  late final AnimationController _tabFadeController;
  late final Animation<double> _tabFade;

  // Garde anti-doublon confetti : score 100% → max 1 fois par jour
  String _lastConfettiDate = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    softpopShellEnabled.addListener(_onSoftpopFlag);

    _tick = ValueNotifier<int>(0);
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
    _tabFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1.0,
    );
    _tabFade = CurvedAnimation(parent: _tabFadeController, curve: Curves.easeIn);

    _startMinuteHeartbeat();
    _startConnectivityListener();
    _initDeepLinks();
    _authSub = _sync.authUidChanges.listen((uid) {
      if (uid != null && _authLost && mounted) {
        setState(() => _authLost = false);
        unawaited(_sync.rememberAccount());
      }
    });
    // Sonnerie du minuteur : déclenchée par le package `alarm` (même app en arrière-plan).
    if (!kIsWeb) _alarmRingSub = Alarm.ringStream.stream.listen(_onAlarmRing);
    // Timeout global 15s sur _init() — l'app s'ouvre toujours en local si ça bloque
    _init().timeout(
      const Duration(seconds: 15),
      onTimeout: () async {
        devLog.error('_init() timeout global 15s — fallback local', tag: 'MAIN');
        if (_state == null) {
          final s = await store.loadOrInit();
          if (mounted) setState(() {
            _state = s;
            logic = AppLogic(_state!, _saveAndRefresh)..sync = _sync;
            _bindDayStart();
            _syncStatus = '⚠️';
          });
        }
      },
    ).catchError((e) {
      devLog.error('_init() exception non catchée', tag: 'MAIN', error: e);
    }).whenComplete(_drainPendingDeepLink).whenComplete(_restoreCountdownFromAlarm);

    // Ouvre la bonne chose quand l'utilisateur tape une notification (locale
    // ou ORION affichée au premier plan) : la charge utile décide, l'id sert
    // de repli pour les notifications planifiées avant 2026-10-30.
    NotificationService.onNotificationTap = _onNotificationTap;

    // Traite un tap bufferisé (race condition background).
    // handleLaunchNotification() est appelé à la fin de _init(), après que
    // logic soit initialisé, pour éviter un LateInitializationError.
    NotificationService.drainPending();
  }

  Timer? _dayNotifsDebounce;

  /// Après un changement (routine, bloc, action visée…), replanifie les
  /// notifications du jour une fois l'agitation retombée.
  void _scheduleDayNotifsRefresh() {
    _dayNotifsDebounce?.cancel();
    _dayNotifsDebounce = Timer(const Duration(seconds: 20), () {
      if (mounted) _refreshDayNotifs();
    });
  }

  /// Notifications du jour (2026-10-30) : leur texte est calculé pour le jour
  /// de leur prochaine occurrence, à chaque ouverture, retour dans l'app et
  /// changement (`_scheduleDayNotifsRefresh`).
  Future<void> _refreshDayNotifs() async {
    final st = _state;
    if (st == null) return;
    try {
      if (st.notifEnabled) {
        final day = NotificationService.nextOccurrenceDay(st.notifHour, st.notifMinute);
        final schedule = await _sync.fetchDailySchedule(ymdOf(day));
        final blocks = (schedule?.blocks ?? const <ScheduleBlock>[]).where((b) => countsForBadges(b) && b.status == 'pending').length;
        final daily = logic.state.activities
            .where((a) => !a.deleted && a.isHabit && logic.effectiveHabitFreq(a) == HabitFreq.daily && !logic.isActivitySnoozed(a.id, day))
            .toList();
        var focused = 0;
        for (final p in logic.currentProjects) {
          for (final t in p.tasks) {
            focused += t.actions.where((a) => isFocusedOn(a, day)).length;
          }
        }
        for (final a in logic.state.activities) {
          if (!a.deleted) focused += a.ownActions.where((x) => isFocusedOn(x, day)).length;
        }
        final series = daily.where((a) => logic.habitCurrentStreak(a.id) > 0).length;
        await NotificationService.scheduleDailyReminder(
          hour: st.notifHour,
          minute: st.notifMinute,
          body: morningDigest(blocks: blocks, routines: daily.length, focused: focused, series: series),
        );
      }
      // Soir : ce qu'il manque AUJOURD'HUI pour une journée parfaite.
      if (st.eveningNotifEnabled) {
        final facts = _badges.todayFacts();
        final missingRoutines = facts.routines.where((r) => !r.reached).toList();
        final atRisk = [
          for (final r in missingRoutines)
            if (logic.effectiveHabitFreq(r.activity) == HabitFreq.daily && logic.habitCurrentStreak(r.activity.id) > 0) r.activity.name,
        ];
        await NotificationService.scheduleEveningPerfect(
          hour: st.streakNotifHour,
          minute: st.streakNotifMinute,
          digest: eveningDigest(routines: missingRoutines.length, blocks: facts.pendingBlocks.length, seriesAtRisk: atRisk),
        );
      } else {
        await NotificationService.cancelById(3);
      }

      // Rappels des blocs : aujourd'hui et demain (jours calendaires), hors
      // miroirs d'agenda (l'agenda prévient déjà) et pauses.
      final now = DateTime.now();
      final alerts = <({String ymd, String id, String title, DateTime start, int durationMin})>[];
      for (final d in [DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day + 1)]) {
        final ymd = ymdOf(d);
        final sched = await _sync.fetchDailySchedule(ymd);
        for (final b in sched?.blocks ?? const <ScheduleBlock>[]) {
          if (b.status != 'pending' || b.gcalEventId != null || b.category == 'break' || b.kind != 'normal' && b.kind != 'deepwork') continue;
          final hm = b.startTime.split(':');
          if (hm.length < 2) continue;
          final h = int.tryParse(hm[0]), m = int.tryParse(hm[1]);
          if (h == null || m == null) continue;
          alerts.add((ymd: ymd, id: b.id, title: b.title.isEmpty ? 'Bloc' : b.title, start: DateTime(d.year, d.month, d.day, h, m), durationMin: b.durationMin));
        }
      }
      await NotificationService.scheduleBlockAlerts(alerts);
    } catch (e) {
      devLog.error('refreshDayNotifs', tag: 'NOTIF', error: e);
    }
  }

  /// Tap sur le rappel d'un bloc : relit le programme et ouvre la source du
  /// bloc (page focus d'un bloc d'activité, écran bloc d'une tâche, séance…).
  Future<void> _openBlockFromNotif(String payload) async {
    final rest = payload.substring('block:'.length);
    final sep = rest.indexOf('|');
    if (sep < 0) return;
    final sched = await _sync.fetchDailySchedule(rest.substring(0, sep));
    final b = sched?.blocks.firstWhereOrNull((x) => x.id == rest.substring(sep + 1));
    if (!mounted) return;
    setState(() => _tab = _goNowTab());
    if (b != null) _openBlockSource(b);
  }

  void _onNotificationTap(int id, String? payload) {
    final ctx = _navigatorKey.currentState?.overlay?.context;
    if (ctx == null) return;
    void onToday(void Function(TodayViewState t) open) {
      setState(() => _tab = _goNowTab());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final t = _todayKey.currentState;
        if (t != null && t.mounted) open(t);
      });
    }

    final p = payload ??
        switch (id) {
          1 => NotificationService.kPayloadProgram,
          2 => NotificationService.kPayloadReview,
          3 => NotificationService.kPayloadPerfect,
          100 => NotificationService.kPayloadOrion,
          _ => NotificationService.kPayloadToday,
        };
    if (p == NotificationService.kPayloadOrion) {
      OrionScreen.show(ctx, _sync);
    } else if (p.startsWith('http')) {
      FcmService.openUrl(p);
    } else if (p == NotificationService.kPayloadReview) {
      showDayReviewSheet(ctx, logic: logic, projects: _dashboardProjects);
    } else if (p == NotificationService.kPayloadProgram) {
      onToday((t) => t.openProgramSheet());
    } else if (p.startsWith('block:')) {
      _openBlockFromNotif(p);
    } else if (p == NotificationService.kPayloadPerfect) {
      onToday((t) => t.openPerfectDaySheet());
    } else {
      setState(() => _tab = _goNowTab());
    }
  }

  void _startMinuteHeartbeat() {
    _heartbeat?.cancel();

    final now = DateTime.now();
    final nextMinute =
        DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    final delay = nextMinute.difference(now);

    // 1) tick pile au prochain changement de minute
    Timer(delay, () {
      if (!mounted) return;
      _tick.value++;
      logic.tickBlockTransition();

      // 2) puis toutes les minutes
      _heartbeat = Timer.periodic(const Duration(minutes: 1), (_) {
        _tick.value++;
        logic.tickBlockTransition();
      });
    });
  }

  void _onSoftpopFlag() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    softpopShellEnabled.removeListener(_onSoftpopFlag);
    _heartbeat?.cancel();
    _dayNotifsDebounce?.cancel();
    _countdownTimer?.cancel();
    _alarmRingSub?.cancel();
    _authSub?.cancel();
    _connectivitySub?.cancel();
    _deepLinkSub?.cancel();
    _domainsSub?.cancel();
    _projectsSub?.cancel();
    _sessionsSub?.cancel();
    _inboxSub?.cancel();
    _tick.dispose();
    _confettiController.dispose();
    _tabFadeController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startConnectivityListener() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((results) {
      final isOffline = results.every((r) => r == ConnectivityResult.none);
      if (_wasOffline && !isOffline && _state != null && !_sync.isAnonymous) {
        // Retour en ligne → on re-sync
        _sync.pushDeltas(_state!).catchError((_) {});
        setState(() => _syncStatus = '☁️');
      }
      if (isOffline) setState(() => _syncStatus = '⚠️');
      _wasOffline = isOffline;
    });
  }

  void _initDeepLinks() {
    final appLinks = AppLinks();
    // Lien initial (app lancée depuis un lien)
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });
    // Liens suivants (app déjà ouverte)
    _deepLinkSub = appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  // Rejoue un lien mémorisé au cold-start, une fois l'état chargé.
  void _drainPendingDeepLink() {
    final uri = _pendingDeepLink;
    if (uri == null || !mounted) return;
    _pendingDeepLink = null;
    _handleDeepLink(uri);
  }

  Future<void> _handleDeepLink(Uri uri) async {
    // Widget Projets → ouvrir un projet :
    //   com.madabinghy.productivitwo://project/<projectId>
    if (uri.host == 'project' && uri.pathSegments.isNotEmpty) {
      // Cold-start : l'app n'a pas fini de charger → on mémorise et on rejoue
      // une fois l'état prêt (sinon le lien retombe sur le dashboard et est perdu).
      if (_state == null) {
        _pendingDeepLink = uri;
        return;
      }
      _openProjectSheet(uri.pathSegments.first);
      return;
    }
    // Format 1 : com.madabinghy.productivitwo://email-signin?link=ENCODED_URL
    //   → lien Firebase encodé dans le param 'link' (depuis la page relay web)
    // Format 2 : lien Firebase direct (deep link natif iOS, fallback)
    String link;
    if (uri.host == 'email-signin' && uri.queryParameters.containsKey('link')) {
      link = uri.queryParameters['link']!;
    } else {
      link = uri.toString();
    }
    if (!_sync.isEmailSignInLink(link)) return;
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email_sign_in_pending');
    if (email == null || email.isEmpty) {
      final ctx = _navigatorKey.currentState?.overlay?.context;
      if (ctx == null) return;
      final entered = await _askEmailDialog(ctx);
      if (entered == null) return;
      _completeEmailSignIn(entered, link);
    } else {
      _completeEmailSignIn(email, link);
    }
  }

  Future<String?> _askEmailDialog(BuildContext ctx) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Confirme ton email'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'ton@email.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Confirmer')),
        ],
      ),
    );
  }

  Future<void> _completeEmailSignIn(String email, String link) async {
    try {
      final result = await _sync.signInWithEmailLink(email, link);
      await ProManager.loginUser(result.uid);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('email_sign_in_pending');
      if (!result.isNew) {
        final remote = await _sync.pull();
        if (remote != null && mounted) {
          await store.save(remote);
          final s = await store.loadOrInit();
          if (mounted) setState(() {
            _state = s;
            logic = AppLogic(_state!, _saveAndRefresh)..sync = _sync;
            _bindDayStart();
          });
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      devLog.error('Email sign-in failed', tag: 'AUTH', error: e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (_state == null) return; // pas encore initialisé
    if (state == AppLifecycleState.resumed) {
      FcmService.clearOrionBadge();
      // Économie d'or coupée avec l'ancienne gamification : pas de transaction
      // Firestore gold_ledger à chaque retour au premier plan.
      if (kOldGamificationEnabled) {
        logic.reconcileLiveGold(_sync); // gains du jour dispo de suite au retour
      }
      _restoreCountdownFromAlarm(); // le minuteur survit au quitter/rouvrir
      unawaited(_refreshDayNotifs());
      // évite de scanner trop souvent (ex: toutes les 6h)
      if (DateTime.now().difference(_lastGlobalScan) >
          const Duration(hours: 6)) {
        logic.skipBadgeCheck = true; // pas de confetti sur le scan de reprise
        final bumps = await logic.scanAllActivities();
        _lastGlobalScan = DateTime.now();
        if (bumps > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("$bumps routine(s) passée(s) en mode manuel"),
                duration: const Duration(seconds: 2)),
          );
          await store.save(_state!);
        }
      }
      _sync.pushProductivitySnapshot(logic.productivitySnapshot());
    }
  }

  Future<void> _init() async {
    // Sync Firestore pour tous les users (anonymes inclus) — l'UID anonyme
    // est stable dans le Keychain iOS, et Claude écrit via cet UID.
    final onMobile = !kIsWeb && !Platform.isMacOS && !Platform.isWindows && !Platform.isLinux;

    // Garantit une session Firebase Auth. On attend d'abord la restauration
    // de la session persistée ; si elle manque ALORS QU'un compte Apple/email
    // a déjà été utilisé ici, on ne crée PAS d'anonyme (ça « déconnectait »
    // l'utilisateur en silence et forkait ses données sur un compte fantôme) :
    // on reste en local avec une bannière « Se reconnecter ». L'anonyme n'est
    // créé qu'à la première installation / après une déconnexion voulue.
    if (onMobile && _sync.uid == null) {
      final restored = await _sync.restoredUid();
      if (restored == null) {
        if (await _sync.hadNamedAccount()) {
          if (mounted) setState(() => _authLost = true);
          devLog.error('Session Apple/email absente au démarrage — pas d\'anonyme, mode local',
              tag: 'FIREBASE');
        } else {
          try { await _sync.signInAnonymously(); } catch (_) {}
        }
      }
    }
    if (_sync.uid != null) unawaited(_sync.rememberAccount());

    // Web inclus : le clone web (auth déjà faite par le gate) lit/écrit Firestore
    // comme le mobile. Les services NATIFS (widgets, alarme, FCM) restent gardés ailleurs.
    final firestoreEnabled = (onMobile || kIsWeb) && _sync.uid != null;

    AppState? remote;
    if (firestoreEnabled) {
      try {
        devLog.log('uid: ${_sync.uid}', tag: 'FIREBASE');
        devLog.log('Pull Firestore…', tag: 'FIREBASE');
        remote = await _sync.pull().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            devLog.error('Timeout 10s', tag: 'FIREBASE');
            return null;
          },
        );
        if (remote != null) {
          devLog.log('Pull OK — données Firestore chargées', tag: 'FIREBASE');
          setState(() => _syncStatus = '☁️');
        } else {
          devLog.log('Aucune donnée Firestore → fallback local', tag: 'FIREBASE');
          setState(() => _syncStatus = '⚠️');
        }
      } catch (e) {
        devLog.error('Erreur Firebase', tag: 'FIREBASE', error: e);
        setState(() => _syncStatus = '⚠️');
      }
    }

    // Merge remote + local pour éviter les conflits inter-appareils
    final local = await store.loadOrInit();
    final s = (firestoreEnabled && remote != null)
        ? FirestoreSync.merge(local, remote)
        : local;

    // Compteur du jour et hits des routines alignés (divergence d'avant le
    // 2026-10-30) : le résultat part avec le re-push ci-dessous.
    reconcileHabitStores(s, dayStartMin: kDefaultDayStartMin, now: DateTime.now());

    // Pointages remplacés restés en base (un clic = un document, avant 2026-10) :
    // purgés une fois pour toutes à la première fusion.
    if (firestoreEnabled && remote != null) {
      final stale = supersededMoodMarks(remote.moodMarks).map((m) => m.id).toList();
      if (stale.isNotEmpty) _sync.deleteMoodMarks(stale).catchError((_) {});
    }
    // Si on a mergé, on re-push le résultat pour que Firestore soit à jour
    if (firestoreEnabled && remote != null) {
      _sync.pushAll(s).catchError((e) =>
          devLog.error('Push merge échoué', tag: 'FIREBASE', error: e));
    }
    // Migration one-shot : première fois qu'on a un compte mais pas de données remote
    if (firestoreEnabled && remote == null) {
      _sync.pushAll(local).catchError((e) =>
          devLog.error('Push migration échoué', tag: 'FIREBASE', error: e));
    }

    setState(() {
      _state = s;
      logic = AppLogic(_state!, _saveAndRefresh)..sync = _sync;
            _bindDayStart();

      // Fuseau vécu → fait serveur (agenda, proposition, assistant).
      _sync.setDeviceTimezone().catchError((_) {});
      // Agenda Google : sync silencieuse bidirectionnelle (aujourd'hui +
      // demain) — les rendez-vous réels entrent dans le programme en miroirs.
      gcalBackgroundSync(_sync);

      () async {
        final bumps = await logic.scanAllActivities();
        if (bumps > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("$bumps routine(s) passée(s) en mode manuel"),
                duration: const Duration(seconds: 2)),
          );
          await store.save(_state!);
        }
        // Progression par paliers : évaluation hebdo déterministe des routines
        // à cap — chaque changement de palier est annoncé avec ses faits.
        final steps = logic.applyWeeklyProgression();
        // Calibration des cibles de temps (« plug and play ») : la cible
        // quotidienne suit le réel mesuré — sauf épinglage manuel ('user').
        final tuned = await logic.autoAdjustStandardsRealtime();
        final facts = [...steps, ...tuned];
        if (facts.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Ajustements — ${facts.join(' · ')}'),
                duration: const Duration(seconds: 4)),
          );
        }
      }();

      // Migration : utilisateurs existants avec des données → onboarding déjà fait
      if (!_state!.onboardingDone && _state!.activeDomains.isNotEmpty) {
        _state!.onboardingDone = true;
      }

      // Blocs par défaut si l'utilisateur n'en a pas encore
      if (_state!.blocks.isEmpty) {
        const defaultBlocks = [
          'Miracle Morning',
          'Matinée',
          'Midi',
          'Après-midi',
          'Soir',
          'Routine Soir',
        ];
        for (var i = 0; i < defaultBlocks.length; i++) {
          _state!.blocks.add(DayBlock(
            name: defaultBlocks[i],
            order: i,
          ));
        }
      }

      // Migration : assigne l'icône water_drop aux routines "Boire de l'eau" existantes
      for (final a in _state!.activeActivities) {
        if (a.iconCode == null &&
            (a.name == "Boire de l'eau" || a.name == "💧 Boire de l'eau")) {
          a.iconCode = 0xf0695; // Icons.water_drop_outlined
        }
      }

      if (_state!.activeDomains.isEmpty && _state!.onboardingDone) {
        _state!.domains.add(Domain(name: 'Général'));
      }
      if (_state!.activeDomains.isNotEmpty) {
        selectedDomainId ??= _state!.activeDomains.first.id;
      }
    });

    // Note : currentProjects n'est pas encore peuplé ici (pull() ne charge pas les projets).
    // La mise à jour initiale du widget se fait via le stream ou fetchProjects() ci-dessous.

    // Affiche l'onboarding pour les nouveaux utilisateurs
    if (!_state!.onboardingDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => OnboardingScreen(
            logic: logic,
            sync: _sync,
            onDone: () {
              Navigator.of(context).pop();
              setState(() {
                selectedDomainId = _state!.activeDomains.isNotEmpty
                    ? _state!.activeDomains.first.id
                    : null;
              });
            },
          ),
        ));
      });
    }

    // Streams temps réel — se mettent à jour dès qu'une donnée change dans Firestore
    if (firestoreEnabled) {
      _domainsSub?.cancel();
      _domainsSub = _sync.streamDomains().listen((domains) {
        if (mounted && _state != null) setState(() => _state!.domains = domains);
      });
      _projectsSub?.cancel();
      _projectsSub = _sync.streamProjects().listen((projects) {
        if (!mounted) return;
        // Persiste `ganttActionsByDay` réconcilié UNIQUEMENT s'il a réellement
        // changé — chaque event du stream déclenchait une sauvegarde complète
        // (écritures Firestore à chaque écriture de projet par le web/ORION).
        final before = jsonEncode(_state?.ganttActionsByDay ?? const {});
        logic.updateGanttCounts(projects); // met à jour les compteurs + currentProjects
        if (jsonEncode(_state?.ganttActionsByDay ?? const {}) != before) {
          unawaited(_doSave());
        }
        setState(() => _dashboardProjects = projects);
        _checkGanttBadges();
        WidgetService.update(logic); // widget Large : tâches Gantt fraîches
        _sync.pushProductivitySnapshot(logic.productivitySnapshot());
      });
      // Sessions en temps réel (source de vérité = Firestore, comme domains/projects)
      // → reflète une session lancée depuis le WEB et pilote la Live Activity iOS.
      _sessionsSub?.cancel();
      _sessionsSub = _sync.streamSessions().listen((sessions) {
        if (!mounted || _state == null) return;
        _state!.sessions = sessions;
        final running = sessions.where((s) => s.endAt == null).toList();
        if (running.isNotEmpty) {
          final s = running.last;
          final a = _state!.activities
              .firstWhereOrNull((x) => x.id == s.activityId);
          LiveActivityService.instance
              .start(activityName: a?.name ?? 'Activité', startAt: s.startAt);
        } else {
          LiveActivityService.instance.end();
        }
        setState(() {});
      });
    }

    // Évaluation assistant ORION (non bloquant)
    unawaited(() async {
      List<Project> projects = [];
      var fetched = false;
      try { projects = await _sync.fetchProjects(); fetched = true; } catch (_) {}
      // Économie d'Or — ordre strict pour que le banking lise des comptes à jour :
      //  1) soigner un curseur empoisonné (peut REMBOBINER → rouvre un jour) ;
      //  2) réconcilier `ganttActionsByDay` depuis les projets chargés (toutes
      //     surfaces : web/mobile/focus), y compris le jour rouvert par le heal ;
      //  3) matérialiser les jours clos ; 4) créditer le solde du jour.
      // Si le fetch a ÉCHOUÉ, on NE réconcilie PAS (sinon on zéroterait l'or du
      // jour) → fallback sur les comptes persistés ; le stream réconciliera ensuite.
      // Économie d'or coupée avec l'ancienne gamification : ni heal, ni
      // matérialisation, ni réconciliation (= zéro transaction gold_ledger au
      // lancement). updateGanttCounts reste : il alimente aussi les widgets.
      if (kOldGamificationEnabled) await logic.healGoldCursorIfNeeded(_sync);
      if (fetched) logic.updateGanttCounts(projects);
      if (kOldGamificationEnabled) {
        logic.materializeGoldUpTo(_sync, DateTime.now());
        logic.reconcileLiveGold(_sync);
      }
      // Alimente les widgets avec les données Gantt réelles dès que disponibles.
      if (projects.isNotEmpty && mounted) {
        WidgetService.update(logic);
        _sync.pushProductivitySnapshot(logic.productivitySnapshot());
      }
      // Routines déjà planifiées (30 j) → exclues des ennemis du donjon.
      unawaited(logic.refreshPlannedActivityIds());
      final messages = await AssistantEngine.evaluate(
        projects: projects,
        domains: _state!.domains,
      );
      if (mounted && messages.isNotEmpty) {
        assistantActionHandler = _handleAssistantAction;
        assistantMessagesNotifier.value = messages;
      }
    }());

    // Notifications : demande permission + planifie rappel quotidien 9h
    unawaited(() async {
      await NotificationService.requestPermissions();
      final st = logic.state;
      await _refreshDayNotifs();
      logic.addListener(_scheduleDayNotifsRefresh);
      if (st.reviewNotifEnabled) await NotificationService.scheduleDailyReview(
        hour: st.reviewNotifHour, minute: st.reviewNotifMinute);
      // Défi ORION retiré (2026-10-30) : on annule le rappel quotidien encore
      // programmé sur les appareils.
      await NotificationService.cancelById(4);
      // Score mi-journée retiré (2026-10-30) : idem.
      await NotificationService.cancelById(5);

      // FCM — enregistre le token et écoute les notifications ORION
      final uid = _sync.uid;
      if (uid != null) {
        FcmService.onOrionNotificationTap = () {
          if (mounted) OrionScreen.show(context, _sync);
        };
        unawaited(FcmService.init(uid));
        _sync.registerOrionSubscription();
        _inboxSub = _sync.streamCaptures().listen((items) {
          if (mounted) {
            setState(() => _inboxPendingCount =
                items.where((i) => i.status == 'pending').length);
          }
        });
      }

    }());

    if (mounted) {
      // Gestion "app terminée lancée depuis une notification" — appelé ici
      // car logic est maintenant initialisé.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) NotificationService.handleLaunchNotification();
      });
    }
  }

  bool _pendingRefresh = false;

  Future<void> _doSave() async {
    if (_state == null) return;

    if (_saving) {
      _saveQueued = true;
      return;
    }

    _saving = true;
    try {
      await store.save(_state!);
      // Sync Firestore pour tous les users (anonymes inclus). Inclut le WEB : le
      // clone mobile (?mobilepreview=true) doit ÉCRIRE dans Firestore comme un vrai
      // device (sinon ses changements — chrono lancé, routine validée… — ne se
      // synchronisent pas vers le web/les autres appareils).
      if (_sync.uid != null &&
          (kIsWeb ||
              (!Platform.isMacOS &&
                  !Platform.isWindows &&
                  !Platform.isLinux))) {
        _sync.pushDeltas(_state!).catchError((_) {});
      }
    } catch (e) {
    } finally {
      _saving = false;
    }

    if (_saveQueued) {
      _saveQueued = false;
      await _doSave();
    }
  }

  // Compte tâches + sous-actions Gantt validées
  int _ganttActionCount() {
    final tasks = _dashboardProjects.expand((p) => p.tasks);
    final tasksDone = tasks.where((t) => t.status == 'done').length;
    final stepsDone = tasks.fold<int>(0, (sum, t) => sum + t.stepsDone);
    return tasksDone + stepsDone;
  }

  // Vérifie et déclenche les badges Gantt — appelé depuis le stream ET depuis saveAndRefresh
  void _checkGanttBadges() {
    if (_state == null || !mounted) return;
    final newBadges = logic.checkAndAwardBadges(
        ganttDoneCount: _ganttActionCount());
    if (newBadges.isNotEmpty) {
      _doSave(); // persiste les nouveaux badges en local + Firestore
      final meta = badgeMeta(newBadges.last.id);
      _confettiController.play();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        content: Text('${meta.emoji} Badge débloqué : ${meta.label}'),
      ));
    }
  }

  Future<void> _saveAndRefresh() async {
    if (_state == null) return;

    // Vérification badges + célébration (pas après une suppression)
    final skipBadge = logic.skipBadgeCheck;
    logic.skipBadgeCheck = false;
    if (!skipBadge) _checkGanttBadges();
    final newBadges = <EarnedBadge>[];  // déjà géré dans _checkGanttBadges
    if (newBadges.isNotEmpty && mounted) {
      final meta = badgeMeta(newBadges.last.id);
      _confettiController.play();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        content: Text('${meta.emoji} Badge débloqué : ${meta.label}'),
      ));
    } else if (mounted) {
      // Célébration score 100% — max 1 fois par jour pour éviter le confetti au démarrage
      final today = yyyymmdd(DateTime.now());
      if (_lastConfettiDate != today) {
        final rs = logic.routineProgressSummaryForCurrentPeriod();
        final done  = rs.reached;
        final total = rs.total;
        if (total > 0 && done >= total) {
          _lastConfettiDate = today;
          _confettiController.play();
        }
      }
    }

    // ✅ Debounce sauvegarde (regroupe les onChange rapides)
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _doSave();
    });

    // Mise à jour des widgets home screen iOS
    // Si le stream Gantt n'a pas encore tiré, on s'assure d'avoir les projets à jour
    if (logic.currentProjects.isEmpty && _dashboardProjects.isNotEmpty) {
      logic.updateGanttCounts(_dashboardProjects);
    }
    WidgetService.update(logic);
    WidgetService.provisionAuth(_sync); // expose uid+token aux widgets actionnables (1×/session)
    _sync.pushProductivitySnapshot(logic.productivitySnapshot()); // → ORION (levier du jour)

    // ✅ Refresh UI (ton code, inchangé)
    if (!mounted) return;
    if (_pendingRefresh) return;
    _pendingRefresh = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pendingRefresh = false;
      setState(() {});
    });
  }

  // ---------- MINUTEUR DE DÉMARRAGE ----------

  /// Lance un minuteur N minutes → vraie alarme (sonne même téléphone verrouillé /
  /// app en arrière-plan, jusqu'à ce que l'utilisateur l'arrête). Le Timer Dart ne
  /// sert plus qu'à rafraîchir l'affichage du temps restant.
  void _startCountdown(int minutes, String activityName,
      {String? routineId, String? expeditionNodeId, int expeditionBonus = 0}) {
    _countdownTimer?.cancel();
    final endsAt = DateTime.now().add(Duration(minutes: minutes));
    _countdownEndsAt = endsAt;
    _countdownActivityName = activityName;
    _countdownTotalSec = minutes * 60;
    _countdownRoutineId = routineId;
    // Reposé à chaque lancement → un minuteur sans nœud efface l'ancien.
    _countdownExpeditionNode = expeditionNodeId;
    _countdownExpeditionBonus = expeditionBonus;

    final ringtone = ringtoneByKey(logic.state.alarmSound);
    if (!kIsWeb) Alarm.set(
      alarmSettings: AlarmSettings(
        id: _timerAlarmId,
        dateTime: endsAt,
        assetAudioPath: 'assets/audio/${ringtone.asset}',
        loopAudio: true,
        vibrate: true,
        warningNotificationOnKill: Platform.isIOS,
        androidFullScreenIntent: true,
        volumeSettings: VolumeSettings.fade(
          volume: 0.9,
          fadeDuration: const Duration(seconds: 3),
          volumeEnforced: true,
        ),
        notificationSettings: NotificationSettings(
          title: '⏱ Minuteur terminé',
          body: '$minutes min — $activityName',
          stopButton: 'Arrêter',
        ),
        // Durée totale (s) [+ routine liée] — restaure l'anneau au resume et
        // permet de retrouver la routine à créditer si l'app a été tuée.
        payload: '${minutes * 60}${routineId != null ? '|r:$routineId' : ''}',
      ),
    );

    // Filet de secours : une notification programmée fire même si l'app est TUÉE
    // (déclenchée par l'OS) — au moins un bip + bannière là où l'alarme ne peut plus sonner.
    NotificationService.scheduleTimerEnd(
        activityName: activityName, minutes: minutes, ringtone: ringtone);

    // Tic d'affichage : quand le temps est écoulé, on laisse l'alarme prendre le relais.
    _countdownTimer = Timer(Duration(minutes: minutes), () {
      _countdownTimer = null;
      if (mounted) setState(() {});
    });
  }

  /// Appelé quand l'alarme du minuteur sonne (app vivante ou réouverte).
  /// La session NE s'arrête PAS d'office : on propose de continuer en chrono
  /// (sur sa lancée) ou de terminer — auquel cas la fiche de l'activité se
  /// rouvre pour voir sa progression (et éventuellement remettre un coup).
  Future<void> _onAlarmRing(AlarmSettings settings) async {
    if (settings.id != _timerAlarmId) return;
    NotificationService.cancelTimerEnd();
    if (!mounted) {
      await Alarm.stop(_timerAlarmId);
      return;
    }

    // Minuteur de ROUTINE : pas de dialog. On coche la routine et on BASCULE en
    // chrono (l'activité liée continue de tourner et de logguer le temps) tant
    // que l'user n'arrête pas — il finit souvent au-delà du minuteur réglé.
    String? routineId = _countdownRoutineId;
    if (routineId == null) {
      final p = settings.payload ?? '';
      final i = p.indexOf('|r:');
      if (i >= 0) routineId = p.substring(i + 3);
    }
    if (routineId != null) {
      setState(() {
        _countdownEndsAt = null;
        _countdownTotalSec = null;
      });
      await Alarm.stop(_timerAlarmId);
      _countdownActivityName = null;
      _countdownRoutineId = null;
      final expNode = _countdownExpeditionNode;
      final expBonus = _countdownExpeditionBonus;
      _countdownExpeditionNode = null;
      _countdownExpeditionBonus = 0;
      // On NE coupe PAS l'activité : le décompte retiré (_countdownEndsAt=null)
      // fait basculer l'UI en chrono count-up → le temps continue de se logguer.
      final now = DateTime.now();
      logic.incHabit(routineId, 1, DateTime(now.year, now.month, now.day));
      // Mode 5 min du donjon : la routine est allée à son terme → on franchit le
      // nœud. (Sur annulation on ne passe jamais ici → pas d'avancement.)
      if (expNode != null && !logic.state.expeditionCleared.contains(expNode)) {
        final ok = await _sync.advanceExpedition(nodeId: expNode);
        if (ok) {
          logic.state.expeditionCleared.add(expNode);
          if (expBonus > 0) {
            logic.applyGold(_sync, expBonus,
                category: 'gain',
                reasonCode: 'donjon_action',
                label: 'Action express');
          }
        }
      }
      _saveAndRefresh();
      if (mounted) {
        final rName = logic.state.activities
                .firstWhereOrNull((a) => a.id == routineId)
                ?.name ??
            'Routine';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ $rName — fait 🔥 · chrono en cours, arrête quand tu veux')));
        setState(() {});
      }
      return;
    }

    final running = logic.runningActivity();
    final name = running?.name ?? _countdownActivityName ?? 'activité';

    // Fin du décompte : on retire l'overlay → l'UI repasse en chrono (temps écoulé).
    setState(() {
      _countdownEndsAt = null;
      _countdownTotalSec = null;
    });

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.timer_off_rounded, size: 32),
        title: const Text('Minuteur terminé'),
        content: Text('« $name » — tu continues sur ta lancée ou tu t\'arrêtes ?',
            textAlign: TextAlign.center),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, 'stop'),
              child: const Text('Terminer')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(d, 'continue'),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Continuer'),
          ),
        ],
      ),
    );

    await Alarm.stop(_timerAlarmId);
    _countdownActivityName = null;

    if (choice == 'continue') {
      // La session tourne toujours → bascule naturelle en chrono count-up.
      if (mounted) setState(() {});
      return;
    }

    // Terminer : on arrête, on logue, puis on rouvre la fiche (progression à jour).
    logic.stopActive();
    _saveAndRefresh();
    if (running != null && mounted) {
      await _openActivitySheet(running);
      if (mounted) setState(() {});
    }
  }

  /// Restaure l'overlay de décompte depuis l'alarme persistée par le package
  /// (le minuteur survit ainsi à un quitter/rouvrir de l'app, au lieu de
  /// retomber en chrono). Ne restaure que si l'alarme est encore à venir ET
  /// qu'une activité tourne.
  Future<void> _restoreCountdownFromAlarm() async {
    if (kIsWeb) return; // pas d'alarme native sur web
    try {
      final a = await Alarm.getAlarm(_timerAlarmId);
      final now = DateTime.now();
      final running = logic.runningActivity();
      if (a != null && a.dateTime.isAfter(now) && running != null) {
        if (!mounted) return;
        setState(() {
          _countdownEndsAt = a.dateTime;
          _countdownTotalSec = int.tryParse(a.payload ?? '') ??
              a.dateTime.difference(now).inSeconds;
          _countdownActivityName = running.name;
        });
      }
    } catch (_) {}
  }

  /// Tap sur un bloc issu d'une source → ouvre SA fiche : tâche (projet),
  /// routine ou activité. Bloc libre (perso/pause) → géré côté DailyScheduleView
  /// (sheet de renommage), pas d'appel ici.
  void _openBlockSource(ScheduleBlock block) {
    if (block.projectId != null) {
      final project =
          _dashboardProjects.firstWhereOrNull((p) => p.id == block.projectId);
      if (project != null) {
        void openTask() => showProjectSheet(context,
            project: project,
            domains: _state?.domains ?? [],
            targetTaskId: block.taskId,
            activities: _state?.activities ?? const []);
        final task = project.tasks.firstWhereOrNull((t) => t.id == block.taskId);
        if (task == null) {
          openTask();
          return;
        }
        // Bloc d'une séance : l'écran séance (déroulé, étape en cours).
        if (task.interventionRole == 'session' && task.interventionId != null) {
          final i = project.interventions.firstWhereOrNull((x) => x.id == task.interventionId);
          if (i != null) {
            showSessionPlayer(context, project: project, intervention: i, sessionTask: task, sync: _sync);
            return;
          }
        }
        // Bloc de tâche : ce qu'il y a à faire (action + étapes), pas la fiche.
        final isToday = logic.todayBlocks.any((b) => b.id == block.id);
        showBlockWorkScreen(context,
            project: project,
            task: task,
            block: block,
            isToday: isToday,
            dayStartMin: logic.dayStartMin,
            sync: _sync,
            onStartTimer: isToday && block.status == 'pending'
                ? () => _launchScheduledBlock(block, goToNow: false)
                : null,
            onOpenTask: openTask,
            onBlockDone: isToday
                ? () => _sync.updateBlockStatus(block.docDate ?? logic.livedTodayYmd, block.id, 'done', manual: true)
                : null);
        return;
      }
    }
    if (block.activityId != null) {
      final act =
          _state?.activities.firstWhereOrNull((a) => a.id == block.activityId);
      if (act == null) return;
      if (act.isHabit) {
        showRoutineSheet(context,
            logic: logic,
            habitId: act.id,
            day: DateTime.now(),
            onSaved: () {
              if (mounted) setState(() {});
            });
      } else {
        _openActivitySheet(act);
      }
    }
  }

  /// Lance un bloc du programme (▶) : démarre le chrono de l'activité liée et
  /// met la tâche en focus (ses actions s'affichent dans l'onglet Maintenant).
  /// [goToNow] = false : lancement depuis la carte MAINTENANT d'Aujourd'hui,
  /// on reste sur l'onglet.
  Future<void> _launchScheduledBlock(ScheduleBlock block,
      {bool goToNow = true}) async {
    // Séance programmée : chrono sur l'activité + player sur SON déroulé.
    if (block.sessionTemplateId != null && block.activityId != null) {
      final tpl =
          await FirestoreSync().fetchSessionTemplate(block.sessionTemplateId!);
      if (tpl != null && tpl.activityId == block.activityId) {
        logic.startTemplate(tpl);
        setState(() {
          _focusProject = null;
          _focusTask = null;
          if (goToNow) _tab = _goNowTab();
        });
        return;
      }
      // Template archivé/introuvable → lancement normal de l'activité.
    }
    // Bloc routine/activité : on démarre directement son activité.
    if (block.projectId == null) {
      if (block.activityId != null) {
        final act = _state?.activities
            .firstWhereOrNull((a) => a.id == block.activityId);
        // Routine avec minuteur → petit menu : chrono libre OU décompte (anneau).
        if (act != null &&
            act.isHabit &&
            (act.timerMin ?? 0) > 0 &&
            (act.linkedActivityId ?? '').trim().isNotEmpty) {
          final linked = _state?.activities
              .firstWhereOrNull((a) => a.id == act.linkedActivityId!.trim());
          if (linked != null) {
            await _chooseRoutineLaunch(act, linked);
            return;
          }
        }
        // Routine minutée SANS activité liée : décompte direct en un tap —
        // la routine se coche à la fin (micro-routines : 1 min suffit).
        if (act != null && act.isHabit && (act.timerMin ?? 0) > 0) {
          _startRoutineTimer(act);
          return;
        }
        // Routine sans minuteur → chrono sur l'activité liée si elle existe.
        if (act != null && act.isHabit) {
          final linkedId = (act.linkedActivityId ?? '').trim();
          final linked = linkedId.isEmpty
              ? null
              : _state?.activities.firstWhereOrNull((a) => a.id == linkedId);
          if (linked != null) {
            logic.start(linked.id);
            setState(() {
              _focusProject = null;
              _focusTask = null;
              if (goToNow) _tab = _goNowTab();
            });
            return;
          }
          // Routine NON liée : ne JAMAIS démarrer un chrono sur la routine
          // elle-même — ça fabrique une fausse activité-temps (« Repas
          // équilibré » à côté de « Manger »). Le temps a UN propriétaire :
          // on demande une fois où le tracer, la réponse est mémorisée.
          await _askRoutineTimeOwner(act);
          return;
        }
        // Bloc d'ACTIVITÉ sans action visée (2026-10, « Blocs d'activité ») :
        // la page focus ouvre la file du bloc — une action par projet lié à
        // l'activité, puis ses actions propres. Rien à proposer → chrono seul.
        if (act != null && !act.isHabit && block.actionId == null) {
          final queue = blockQueue(
            activity: act,
            projects: _dashboardProjects,
            today: logic.livedToday,
          );
          if (queue.isNotEmpty && mounted) {
            await showBlockFocusScreen(context,
                logic: logic,
                block: block,
                activity: act,
                queue: queue,
                ymd: block.docDate ?? logic.livedTodayYmd);
            return;
          }
        }
        // Bloc ciblant une action propre de l'activité → chrono ciblé (actionId).
        logic.start(block.activityId!, actionId: block.actionId);
        setState(() {
          _focusProject = null;
          _focusTask = null;
          if (goToNow) _tab = _goNowTab();
        });
      }
      return;
    }
    final project =
        _dashboardProjects.firstWhereOrNull((p) => p.id == block.projectId);
    if (project == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Projet introuvable.')));
      }
      return;
    }
    final task = block.taskId == null
        ? null
        : project.tasks.firstWhereOrNull((t) => t.id == block.taskId);
    // Activité-temps du domaine du projet (auto si une seule, sinon on choisit).
    final domainActs = (_state?.activities ?? [])
        .where((a) =>
            a.domainId == project.domainId && !a.isHabit && !a.deleted)
        .toList();
    Activity? activity;
    if (domainActs.length == 1) {
      activity = domainActs.first;
    } else if (domainActs.isNotEmpty) {
      final id = await showActivityPicker(context,
          activities: domainActs,
          domains: _state?.activeDomains ?? const [],
          title: 'Sur quelle activité chronométrer ?');
      activity = domainActs.firstWhereOrNull((a) => a.id == id);
    }
    if (activity == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Aucune activité de temps dans ce domaine pour lancer le chrono.')));
      }
      return;
    }
    // Chrono ciblé sur la sous-action si le bloc en désigne une (actionId).
    logic.start(activity.id, taskId: block.taskId, actionId: block.actionId);
    final focusActId = activity.id;
    setState(() {
      _focusProject = project;
      _focusTask = task;
      _focusActivityId = focusActId;
      if (goToNow) _tab = _goNowTab();
    });
    // Jalon d'une intervention : le téléphone passe en « séance en cours ».
    if (task != null && task.interventionRole == 'session' && task.interventionId != null) {
      final i = project.interventions.where((x) => x.id == task.interventionId).firstOrNull;
      if (i != null && mounted) {
        await showSessionPlayer(context, project: project, intervention: i, sessionTask: task, sync: _sync);
      }
    }
  }

  /// Chrono lancé pendant un bloc en cours d'une autre source : une question
  /// courte, jamais bloquante (fermer = parenthèse). « Pour ce bloc » ré-attribue
  /// la session au bloc (elle compte alors pour lui) ; « Décaler » pousse le
  /// bloc au prochain quart d'heure.
  /// « Ces 42 min, c'était pour quoi ? » (2026-10) : un chrono arrêté qui ne
  /// visait aucune action (ni tâche) se rattache en un tap à l'une des actions
  /// probables de son activité — le temps réel alimente l'estimé vs réel sans
  /// saisie de plus. Rien de proposé (< 3 min, aucune candidate) = rien.
  void _askStopTarget(Session s) {
    if (s.actionId != null || s.taskId != null) return;
    final min = s.duration.inMinutes;
    if (min < 3) return;
    final act = logic.state.activities.firstWhereOrNull((a) => a.id == s.activityId);
    if (act == null || act.isHabit) return;
    final planned = {for (final b in logic.todayBlocks) if (b.actionId != null) b.actionId!};
    final cands = stopTargetCandidates(_dashboardProjects, logic.state.activeActivities, s.activityId,
        today: DateTime.now(), plannedIds: planned);
    if (cands.isEmpty) return;
    String fmt(int m) => m >= 60 ? '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}' : '$m min';
    Future<void>.delayed(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      final picked = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Ces ${fmt(min)}, c\'était pour quoi ?',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Actions liées à « ${act.name} », les plus probables d\'abord',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
                const SizedBox(height: 10),
                for (var i = 0; i < cands.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: cs.surfaceContainerHighest.withOpacity(.4),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(ctx, i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(children: [
                            Icon(Icons.radio_button_unchecked, size: 18, color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(cands[i].action.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                Text(
                                  [
                                    if (cands[i].project != null) cands[i].project!.title,
                                    if (cands[i].task != null) cands[i].task!.title,
                                    if (cands[i].activity != null) cands[i].activity!.name,
                                  ].join(' › '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.55)),
                                ),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Rien de précis')),
              ]),
            ),
          );
        },
      );
      if (picked == null || !mounted) return;
      final c = cands[picked];
      s.taskId = c.task?.id;
      s.actionId = c.action.id;
      logic.onChange();
      await _sync.saveSession(s);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${fmt(min)} rattachées à « ${c.action.title} »'),
        duration: const Duration(seconds: 3),
      ));
    });
  }

  void _askSessionVsBlock(Session session, ScheduleBlock block) {
    // Appelé PENDANT le tap du lanceur (FAB, routines…) qui enchaîne
    // start() puis Navigator.pop() : ouvrir la feuille tout de suite la fait
    // fermer par ce pop (dernière route) et laisse le lanceur ouvert — vu sur
    // build 443. On laisse la navigation se poser, puis on vérifie que la
    // session tourne encore avant de poser la question.
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (!mounted || session.endAt != null) return;
      if (!logic.state.sessions.contains(session)) return;
      _showSessionVsBlockSheet(session, block);
    });
  }

  /// Une ligne « ÉTIQUETTE  [pastille colorée : nom]  détail » de la feuille
  /// « Pour ce bloc » : le nom est le seul élément en couleur et en gras.
  Widget _attachLine(ColorScheme cs, String label, String name, Color color, IconData icon,
      {String? detail}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(
        width: 58,
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: cs.onSurface.withOpacity(.45))),
      ),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withOpacity(.45)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
              ),
            ]),
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 3),
              child: Text(detail,
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(.55),
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
        ]),
      ),
    ]);
  }

  void _showSessionVsBlockSheet(Session session, ScheduleBlock block) {
    final ctx = _navigatorKey.currentState?.overlay?.context;
    if (ctx == null || !mounted) return;
    final actName = _state?.activities
            .firstWhereOrNull((a) => a.id == session.activityId)
            ?.name ??
        'ce chrono';
    final end = blockEndMin(block);
    final endLabel =
        '${(end ~/ 60).toString().padLeft(2, '0')}:${(end % 60).toString().padLeft(2, '0')}';
    // Bloc pas encore commencé (anticipation ≤ 15 min) : on ne propose que
    // le rattachement — décaler ou réorganiser n'a pas de sens avant l'heure.
    final upcoming = blockStartMin(block) > logic.livedNowMinNow;
    final blockProject =
        logic.currentProjects.firstWhereOrNull((p) => p.id == block.projectId);
    final blockAct =
        _state?.activities.firstWhereOrNull((a) => a.id == block.activityId);
    final attachable =
        canAttachSessionToBlock(block, blockActivity: blockAct, project: blockProject);
    final cs = Theme.of(ctx).colorScheme;
    showModalBottomSheet<void>(
      context: ctx,
      showDragHandle: true,
      // En-tête + 4 choix dépassent la hauteur par défaut d'une feuille sur
      // iPhone : feuille haute et défilante (constaté : overflow sur 14).
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .85),
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // En-tête : ce qu'on associe à quoi, lisible d'un coup d'œil —
          // CHRONO (activité, pastille primaire) et BLOC (titre, pastille à la
          // couleur de sa catégorie) sur deux lignes étiquetées, puis la question.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _attachLine(cs, 'CHRONO', actName, cs.primary, Icons.timer_outlined),
              const SizedBox(height: 8),
              _attachLine(
                  cs,
                  'BLOC',
                  block.title,
                  switch (block.category) {
                    'routine' => const Color(0xFF1A9E6E),
                    'personal' => cs.secondary,
                    'break' => cs.outline,
                    _ => cs.tertiary,
                  },
                  Icons.event_note_outlined,
                  detail: upcoming
                      ? 'commence à ${block.startTime}'
                      : '${block.startTime} → $endLabel · en cours'),
              const SizedBox(height: 12),
              Text('C\'est pour ce bloc ?',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: cs.onSurface)),
            ]),
          ),
          if (attachable)
            ListTile(
              leading: Icon(Icons.link_rounded, color: cs.primary),
              title: const Text('Pour ce bloc'),
              subtitle: Text('Le temps de « $actName » compte pour ce bloc'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final r = attachSessionToBlock(session, block,
                    blockActivity: blockAct, project: blockProject);
                if (r == AttachResult.none) return;
                logic.onChange();
                if (r == AttachResult.sessionAndBlock) {
                  // Le bloc prend l'activité du chrono (le chrono fait foi).
                  final n = DateTime.now();
                  final ymd =
                      '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
                  await _sync.upsertScheduleBlock(ymd, block);
                }
              },
            ),
          ListTile(
            leading: Icon(Icons.pause_circle_outline, color: cs.onSurface.withOpacity(.7)),
            title: Text(upcoming ? 'Non, autre chose' : 'Une parenthèse — je reprends après'),
            subtitle: const Text('Le bloc reste en attente, rien ne bouge'),
            onTap: () => Navigator.pop(sheetCtx),
          ),
          if (!upcoming) ...[
          ListTile(
            leading: Icon(Icons.schedule_send_outlined, color: cs.onSurface.withOpacity(.7)),
            title: const Text('Décaler le bloc après'),
            subtitle: const Text('Il repart au prochain quart d\'heure'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              final n = DateTime.now();
              final start = shiftedStartAfter(logic.livedNowMinNow, block.durationMin);
              if (start == null) return;
              block.startTime = start;
              final ymd =
                  '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
              await _sync.upsertScheduleBlock(ymd, block);
            },
          ),
          const Divider(height: 8, indent: 20, endIndent: 20),
          // Ouvre LE Claude de l'utilisateur (claude.ai/new?q=…) avec la
          // demande écrite : il envoie, Claude replanifie via son connecteur
          // Productivitwo — rien ne passe par nos functions ni une clé API.
          ListTile(
            leading: Icon(Icons.auto_awesome, color: cs.primary),
            title: const Text('Réorganiser la suite avec Claude'),
            subtitle: const Text('Ouvre Claude avec la journée et ce qui vient de changer'),
            onTap: () {
              Navigator.pop(sheetCtx);
              final n = DateTime.now();
              final ymd =
                  '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
              final prompt = reorganizeAfterAsidePrompt(
                date: ymd,
                now: n,
                block: block,
                activityName: actName,
                todayBlocks: logic.todayBlocks,
              );
              launchUrl(claudeNewUri(prompt), mode: LaunchMode.externalApplication);
            },
          ),
          ],
          const SizedBox(height: 8),
        ]),
        ),
      ),
    );
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (!kIsWeb) Alarm.stop(_timerAlarmId);
    NotificationService.cancelTimerEnd();
    _countdownActivityName = null;
    _countdownTotalSec = null;
    // Annulation = on n'a PAS fait la routine → on ne franchit pas le nœud.
    _countdownExpeditionNode = null;
    _countdownExpeditionBonus = 0;
    setState(() => _countdownEndsAt = null);
  }

  // ---------- UTIL DATES ----------
  (DateTime start, DateTime end, int days) _rangeForScope(DateTime now) {
    switch (scope) {
      case TimeScope.day:
        final start = DateTime(now.year, now.month, now.day);
        return (start, start.add(const Duration(days: 1)), 1);
      case TimeScope.week:
        // Lundi -> Dimanche
        final weekday = (now.weekday + 6) % 7; // 0=lundi
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weekday));
        return (start, start.add(const Duration(days: 7)), 7);
      case TimeScope.month:
        final start = DateTime(now.year, now.month, 1);
        final nextMonth = (now.month == 12)
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);
        final days = nextMonth.difference(start).inDays;
        return (start, nextMonth, days);
    }
  }

  String _fmtHoursHM(double h) {
    final totalMin = (h * 60).round();
    final hh = totalMin ~/ 60;
    final mm = totalMin % 60;
    return "${hh}h ${mm}m";
  }

// 1) Helpers d'index <-> enum
  /// Onglets visibles dans la barre. Deux rôles distincts (2026-09) :
  /// « Actions » = l'EXÉCUTION (les actions des projets actifs, non en
  /// pause) ; « Projets » = la STRUCTURE (tout ce qu'on veut faire, y
  /// compris en veille) — les DEUX cohabitent quand le Gantt est visible.
  /// hideProjectsTab ne masque plus que « Projets » (la structure passe en
  /// coulisse, l'exécution reste). La pile de vues (IndexedStack) garde ses
  /// index — seule la barre change.
  // « Stats » = l'ancien Accueil (tableau de bord), promu onglet principal :
  // les stats de temps sont un moteur d'ouverture de l'app (constat user).
  // Ordre de la barre (demande user 2026-10) : Actions AVANT Aujourd'hui,
  // l'onglet d'arrivée reste tout à droite.
  List<_Tab> get _visibleTabs => _state?.hideProjectsTab == true
      ? const [_Tab.dashboard, _Tab.stats, _Tab.actions, _Tab.aujourdhui]
      : const [_Tab.dashboard, _Tab.stats, _Tab.projets, _Tab.actions, _Tab.aujourdhui];

  int _tabIndex(_Tab t) {
    switch (t) {
      case _Tab.dashboard:   return 0;
      case _Tab.projets:     return 1;
      case _Tab.aujourdhui:  return 2;
      case _Tab.actions:     return 3;
      case _Tab.stats:       return 4;
    }
  }

  Widget _buildBody(BuildContext context) {
    // Le focus de tâche (« Maintenant ») ne survit que tant que SON activité
    // tourne (ou qu'un décompte est actif). Sinon — session arrêtée par
    // n'importe quel bouton, étoile décochée, app relancée, OU lancement d'une
    // AUTRE activité — on le purge.
    if ((_focusTask != null || _focusProject != null) &&
        _countdownEndsAt == null) {
      final running = logic.runningActivity();
      final stale = running == null ||
          (_focusActivityId != null && running.id != _focusActivityId);
      if (stale) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final r = logic.runningActivity();
          if ((_focusTask != null || _focusProject != null) &&
              _countdownEndsAt == null &&
              (r == null ||
                  (_focusActivityId != null && r.id != _focusActivityId))) {
            setState(() {
              _focusProject = null;
              _focusTask = null;
              _focusActivityId = null;
            });
          }
        });
      }
    }
    // Hook minuteur : permet aux feuilles modales (mode 5 min du donjon) de
    // lancer une vraie alarme via l'infra de l'accueil.
    logic.launchTimerHook ??= (int m, String n,
            {String? routineId,
            String? expeditionNodeId,
            int expeditionBonus = 0}) =>
        _startCountdown(m, n,
            routineId: routineId,
            expeditionNodeId: expeditionNodeId,
            expeditionBonus: expeditionBonus);
    logic.programBacklogHook ??= _programBacklogItem;
    logic.onSessionOffBlock ??= _askSessionVsBlock;
    logic.onUserStopped ??= _askStopTarget;



    return FadeTransition(
      opacity: _tabFade,
      child: IndexedStack(
        index: _tabIndex(_tab),
        children: [
          _buildObjectivesBody(context),
          GoalsView(
            visible: _tab == _Tab.projets,
            logic: logic,
            domains: _state?.domains ?? [],
            activities: _state?.activities ?? [],
            sessions: _state?.sessions ?? [],
            header: logic.state.showTodayPriorities
                ? _buildTodayPrioritiesSection(
                    context, Theme.of(context).colorScheme)
                : null,
            onStartTimer: (activity, project, task) {
              logic.start(activity.id);
              setState(() {
                _focusProject = project;
                _focusTask = task;
                _tab = _goNowTab();
              });
            },
            onBadgeCheck: (doneCount) {
              final newBadges = logic.checkAndAwardBadges(ganttDoneCount: doneCount);
              if (newBadges.isNotEmpty && mounted) {
                _doSave(); // persiste les nouveaux badges
                final meta = badgeMeta(newBadges.last.id);
                _confettiController.play();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  duration: const Duration(seconds: 4),
                  content: Text('${meta.emoji} Badge débloqué : ${meta.label}'),
                ));
              }
            },
          ),
          // Onglet Aujourd'hui : programme du jour + planif du lendemain.
          TodayView(
            key: _todayKey,
            logic: logic,
            badges: _badges,
            sync: _sync,
            onLaunch: _launchScheduledBlock,
            onOpenSource: _openBlockSource,
            // L'auto-scroll « maintenant » attend la 1ʳᵉ ouverture VISIBLE
            // (l'IndexedStack construit l'onglet dès le lancement).
            visible: _tab == _Tab.aujourdhui,
            // Carte MAINTENANT en tête (handoff iOS 2026-09, PR 1).
            focusProject: _focusProject,
            focusTask: _focusTask,
            countdownEndsAt: _countdownEndsAt,
            countdownTotalSec: _countdownTotalSec,
            onNowLaunch: (b) => _launchScheduledBlock(b, goToNow: false),
            onNowLaunchTimed: (b, m) async {
              await _launchScheduledBlock(b, goToNow: false);
              _startCountdown(m, b.title);
              if (mounted) setState(() {});
            },
            onStopCountdown: () {
              _cancelCountdown();
              setState(() {});
            },
            onStopTimer: () {
              _cancelCountdown();
              logic.stopActive();
              setState(() {
                _focusProject = null;
                _focusTask = null;
                _focusActivityId = null;
              });
            },
            onOpenRoutines: () => _showRoutinesSheet(context),
            onOpenActivities: () => _showLaunchActivitySheet(context),
            onOpenActions: () => setState(() => _tab = _Tab.actions),
            onOpenProjects: _state?.hideProjectsTab == true ? null : () => setState(() => _tab = _Tab.projets),
            onOpenTask: (project, task) => showProjectSheet(
              context,
              project: project,
              domains: _state?.domains ?? [],
              targetTaskId: task.id,
              activities: _state?.activities ?? const [],
            ),
            onOpenDayReview: () => showDayReviewSheet(context,
                logic: logic, projects: _dashboardProjects),
            // Minuteur d'une routine (« Le meilleur à faire ») : chrono ciblé +
            // décompte, routine cochée à la fin.
            onStartTimed: (a, minutes) {
              if (a.isHabit) {
                final linkedId = (a.linkedActivityId ?? '').trim();
                final linked = linkedId.isEmpty
                    ? null
                    : logic.state.activities
                        .firstWhereOrNull((x) => x.id == linkedId);
                final target = linked ?? a;
                logic.start(target.id);
                _startCountdown(minutes, target.name, routineId: a.id);
              } else {
                logic.start(a.id);
                _startCountdown(minutes, a.name);
              }
              setState(() {
                _focusProject = null;
                _focusTask = null;
              });
            },
          ),
          // Onglet « Actions » (index 3) : liste GTD par projet + contexte du
          // moment — remplace « Projets » quand le Gantt est en retrait.
          ActionsView(logic: logic),
          // Onglet « Stats » (index 4) : l'ancien Accueil (tableau de bord),
          // promu onglet principal — jauges, temps, domaines, retards.
          _buildDashboardBody(context),
        ],
      ),
    );
  }

  void _handleAssistantAction(AssistantActionData action) {
    switch (action.type) {
      case 'open_day_plan':
      case 'open_goals':
        setState(() => _tab = _Tab.projets);
      case 'open_project':
        _openProjectSheet(action.payload?['projectId'] as String?);
      case 'open_gantt_task':
        _openProjectSheet(
          action.payload?['projectId'] as String?,
          targetTaskId: action.payload?['taskId'] as String?,
        );
      case 'open_activity':
        setState(() => _tab = _goNowTab());
    }
  }

  Future<void> _openProjectSheet(String? projectId, {String? targetTaskId}) async {
    if (projectId == null || _state == null) {
      setState(() => _tab = _Tab.dashboard);
      return;
    }
    // Cherche d'abord dans les projets déjà fetchés (si dispo), sinon fetch
    List<Project> projects = [];
    try { projects = await _sync.fetchProjects(); } catch (_) {}
    final project = projects.where((p) => p.id == projectId).firstOrNull;
    if (project == null || !mounted) {
      setState(() => _tab = _Tab.dashboard);
      return;
    }
    showProjectSheet(
      context,
      project: project,
      domains: _state!.domains,
      targetTaskId: targetTaskId,
      activities: _state?.activities ?? const [],
    );
  }

  // ---------- UI ----------

  /// Programme un défi dans le futur : pose un bloc 🔥 dans le plan du jour
  /// cible + une notif-alarme à l'heure + un rappel en amont. Le défi est
  /// « gagné » plus tard quand l'user le coche ou logge le temps (voir
  /// DailyScheduleView). Ne compte PAS de défi à la programmation.
  /// Programme un item de backlog (depuis la carte de combat). Routine/activité
  /// → défi daté + rappel (_programChallenge). Tâche → bloc projet dans le
  /// programme (heure + durée).
  Future<void> _programBacklogItem(String type, String itemId) async {
    if (type == 'snake') {
      for (final p in _dashboardProjects) {
        final t = p.tasks.firstWhereOrNull((x) => x.id == itemId);
        if (t == null) continue;
        if (t.todayFlag) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Déjà dans ton programme (étoile).')));
          }
        } else {
          await toggleTaskTodayAndSchedule(context, _sync, p, t);
          if (mounted) setState(() {});
        }
        return;
      }
      return;
    }
    final a = _state?.activities.firstWhereOrNull((x) => x.id == itemId);
    if (a == null) return;
    final minutes = (a.timerMin ?? 0) > 0 ? a.timerMin! : 25;
    await _programChallenge(a, minutes);
  }

  Future<void> _programChallenge(Activity a, int minutes) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var day = today.add(const Duration(days: 1)); // demain par défaut
    var time = const TimeOfDay(hour: 8, minute: 0);
    var reminder = 'eve'; // eve | h1 | m15 | at

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          final cs = Theme.of(ctx).colorScheme;
          final tomorrow = today.add(const Duration(days: 1));
          final afterTomorrow = today.add(const Duration(days: 2));
          DateTime scheduledAt() =>
              DateTime(day.year, day.month, day.day, time.hour, time.minute);
          final isTomorrow = day == tomorrow;
          final isAfter = day == afterTomorrow;
          String dayLabel() {
            const mois = [
              'janv', 'févr', 'mars', 'avr', 'mai', 'juin',
              'juil', 'août', 'sept', 'oct', 'nov', 'déc'
            ];
            if (day == today) return 'aujourd\'hui';
            if (isTomorrow) return 'demain';
            if (isAfter) return 'après-demain';
            return '${day.day} ${mois[day.month - 1]}';
          }

          Widget reminderChip(String value, String label) => ChoiceChip(
                label: Text(label),
                selected: reminder == value,
                onSelected: (_) => setSheet(() => reminder = value),
              );

          final past = !scheduledAt().isAfter(now);

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                left: 20,
                right: 20,
                top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Programmer le défi',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('🔥 $minutes min de « ${a.name} »',
                    style: TextStyle(color: cs.onSurface.withOpacity(.7))),
                const SizedBox(height: 16),
                Text('Quand',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(.8))),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    label: const Text('Aujourd\'hui'),
                    selected: day == today,
                    onSelected: (_) => setSheet(() {
                      day = today;
                      // Heure par défaut = dans 1 h, arrondie, pour rester future.
                      final t = now.add(const Duration(hours: 1));
                      time = TimeOfDay(hour: t.hour, minute: 0);
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Demain matin'),
                    selected: isTomorrow,
                    onSelected: (_) => setSheet(() {
                      day = tomorrow;
                      time = const TimeOfDay(hour: 8, minute: 0);
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Après-demain matin'),
                    selected: isAfter,
                    onSelected: (_) => setSheet(() {
                      day = afterTomorrow;
                      time = const TimeOfDay(hour: 8, minute: 0);
                    }),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text('Autre…'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: day,
                        firstDate: today,
                        lastDate: today.add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setSheet(() =>
                            day = DateTime(picked.year, picked.month, picked.day));
                      }
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.schedule_rounded,
                      size: 18, color: cs.onSurface.withOpacity(.6)),
                  const SizedBox(width: 8),
                  Text('${dayLabel()} à ${time.format(ctx)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: ctx, initialTime: time);
                      if (t != null) setSheet(() => time = t);
                    },
                    child: const Text('Modifier l\'heure'),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('Rappel',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(.8))),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  reminderChip('eve', 'La veille au soir'),
                  reminderChip('h1', '1h avant'),
                  reminderChip('m15', '15 min avant'),
                  reminderChip('at', 'À l\'heure'),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: past ? null : () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.notifications_active_rounded),
                    label: Text(past ? 'Choisis un horaire futur' : 'Programmer'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
    if (confirmed != true) return;

    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    final ymd =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final hhmm =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    DateTime? remAt;
    switch (reminder) {
      case 'eve':
        final eve = DateTime(day.year, day.month, day.day)
            .subtract(const Duration(days: 1));
        remAt = DateTime(eve.year, eve.month, eve.day, 20, 0);
        break;
      case 'h1':
        remAt = at.subtract(const Duration(hours: 1));
        break;
      case 'm15':
        remAt = at.subtract(const Duration(minutes: 15));
        break;
      case 'at':
        remAt = null; // l'alarme à l'heure suffit
        break;
    }

    final block = ScheduleBlock(
      startTime: hhmm,
      durationMin: minutes,
      title: '🔥 Défi : ${a.name}',
      category: a.isHabit ? 'routine' : 'personal',
      activityId: a.id,
      challenge: true,
      reminders: remAt != null ? [remAt.toIso8601String()] : [],
    );
    await FirestoreSync().addScheduleBlock(ymd, block);

    // Le défi remplace un bloc d'AUJOURD'HUI sur la même activité et part à
    // une date FUTURE : changer de date = un report. Le bloc du jour passe en
    // sauté « reporté » — la trace reste (barré, check-in, stats d'hygiène),
    // le coach arrête de relancer, rien ne disparaît en silence.
    final todayYmd0 = logic.livedTodayYmd;
    if (ymd != todayYmd0) {
      final sync = FirestoreSync();
      final todaySched = await sync.fetchDailySchedule(todayYmd0);
      for (final b in todaySched?.blocks ?? const <ScheduleBlock>[]) {
        if (b.status != 'pending' || b.activityId != a.id || b.challenge) {
          continue;
        }
        await sync.updateBlockStatus(todayYmd0, b.id, 'skipped');
        await sync.updateBlockSkipReason(todayYmd0, b.id, 'reporte');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🔥 Défi programmé ${_relativeDayLabel(day)} à $hhmm'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  String _relativeDayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'aujourd\'hui';
    if (diff == 1) return 'demain';
    if (diff == 2) return 'après-demain';
    return 'le ${day.day}/${day.month}';
  }

  /// Lanceur d'activités (FAB) : `widgets/activity_launcher_sheet.dart`.
  Future<void> _showLaunchActivitySheet(BuildContext context) {
    return showActivityLauncher(
      context,
      logic: logic,
      onStart: (a) {
        logic.start(a.id);
        logic.rev.value++;
        setState(() => _tab = _goNowTab());
      },
      onStartTimed: (a, m) {
        logic.start(a.id);
        _startCountdown(m, a.name);
        setState(() => _tab = _goNowTab());
      },
      onDeepWork: (a) => showDeepWorkSheet(
        context,
        logic: logic,
        sync: _sync,
        date: logic.livedTodayYmd,
        preferActivityId: a.id,
        onLaunch: (b) => _launchScheduledBlock(b, goToNow: true),
      ),
      onOpenFiche: (a) async {
        await _openActivitySheet(a);
        if (mounted) setState(() {});
      },
      onStop: () async {
        _cancelCountdown();
        final (_, name, delta) = await logic.stopActiveWithAdjustment();
        if (!mounted) return;
        setState(() {});
        if (delta != null && delta > 0 && name != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Objectif ajusté : $name +${delta}min'),
            duration: const Duration(seconds: 3),
          ));
        }
      },
      onNew: () => _createActivityDialog(domainId: null, isHabit: false),
    );
  }

  Future<void> _createRoutineFromNow(BuildContext context) async {
    final result = await showNewRoutineSheet(context, logic: logic);
    if (result == null) return;

    final a = Activity(
      domainId: result.domainId,
      name: result.name,
      type: 'habit',
      habitFreq: result.freq,
      habitTarget: result.target,
      autoTune: true,
      linkedActivityId: result.linkedActivityId,
      iconCode: result.iconCode,
    );

    logic.state.activities.add(a);

    if ((result.blockId ?? '').isNotEmpty) {
      logic.addActivityToBlock(result.blockId!, a.id);
    }

    logic.onChange();

    if (!mounted) return;
    setState(() {});
  }

  void _openLast24hSessionsSheet(BuildContext context, dynamic logic) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Last24hSessionsSheet(logic: logic, sync: _sync),
    );
  }

  Future<void> _loadDemoData() async {
    final st = logic.state;
    final now = DateTime.now();

    // ── Domaines ──────────────────────────────────────────────────────────────
    final dSante = Domain(name: 'Santé');
    final dSport = Domain(name: 'Sport');
    final dBusiness = Domain(name: 'Business');
    st.domains.addAll([dSante, dSport, dBusiness]);

    // ── Activités (suivi temps) ────────────────────────────────────────────────
    final aMeditation = Activity(domainId: dSante.id, name: 'Méditation', goalMin: 20, order: 0);
    final aMusculation = Activity(domainId: dSport.id, name: 'Musculation', goalMin: 60, order: 0);
    final aRunning = Activity(domainId: dSport.id, name: 'Running', goalMin: 30, order: 1);
    final aDeepWork = Activity(domainId: dBusiness.id, name: 'Deep Work', goalMin: 120, order: 0);
    st.activities.addAll([aMeditation, aMusculation, aRunning, aDeepWork]);

    // ── Routines quotidiennes (type habit) — alimentent la heatmap ────────────
    // 5 habits → 6 niveaux de score (0/5 à 5/5) couvrant toute la palette de couleurs
    final hLecture = Activity(
      domainId: dSante.id, name: 'Lecture', type: 'habit',
      habitFreq: HabitFreq.daily, habitTarget: 1, order: 2,
    );
    final hEau = Activity(
      domainId: dSante.id, name: 'Hydratation', type: 'habit',
      habitFreq: HabitFreq.daily, habitTarget: 1, order: 3,
    );
    final hRevue = Activity(
      domainId: dBusiness.id, name: 'Revue quotidienne', type: 'habit',
      habitFreq: HabitFreq.daily, habitTarget: 1, order: 1,
    );
    final hSport = Activity(
      domainId: dSport.id, name: 'Sport', type: 'habit',
      habitFreq: HabitFreq.daily, habitTarget: 1, order: 2,
    );
    final hVeille = Activity(
      domainId: dBusiness.id, name: 'Veille', type: 'habit',
      habitFreq: HabitFreq.daily, habitTarget: 1, order: 2,
    );
    st.activities.addAll([hLecture, hEau, hRevue, hSport, hVeille]);

    // ── Sessions : aujourd'hui + 12 semaines d'historique ────────────────────
    // Aujourd'hui
    st.sessions.addAll([
      Session(activityId: aMeditation.id,
          startAt: DateTime(now.year, now.month, now.day, 7, 0),
          endAt:   DateTime(now.year, now.month, now.day, 7, 22)),
      Session(activityId: aMusculation.id,
          startAt: DateTime(now.year, now.month, now.day, 8, 0),
          endAt:   DateTime(now.year, now.month, now.day, 9, 5)),
      Session(activityId: aDeepWork.id,
          startAt: DateTime(now.year, now.month, now.day, 9, 30),
          endAt:   DateTime(now.year, now.month, now.day, 11, 15)),
      Session(activityId: aRunning.id,
          startAt: DateTime(now.year, now.month, now.day, 12, 0),
          endAt:   DateTime(now.year, now.month, now.day, 12, 28)),
    ]);
    // Historique 12 semaines (seed fixe pour reproductibilité)
    final rng = Random(42);
    final todayDt = DateTime(now.year, now.month, now.day);
    for (int daysAgo = 83; daysAgo >= 1; daysAgo--) {
      final day = todayDt.subtract(Duration(days: daysAgo));
      final isWeekend = day.weekday >= 6;
      final ymd = yyyymmdd(day);
      DateTime t(int h, int m) => DateTime(day.year, day.month, day.day, h, m);
      // Méditation : 75% des jours
      if (rng.nextDouble() < 0.75) {
        final dur = 15 + rng.nextInt(20);
        st.sessions.add(Session(activityId: aMeditation.id,
            startAt: t(7, 0), endAt: t(7, 0).add(Duration(minutes: dur))));
      }
      // Musculation : lundi / mercredi / vendredi à 70%
      if ([1, 3, 5].contains(day.weekday) && rng.nextDouble() < 0.70) {
        final dur = 45 + rng.nextInt(30);
        st.sessions.add(Session(activityId: aMusculation.id,
            startAt: t(8, 0), endAt: t(8, 0).add(Duration(minutes: dur))));
      }
      // Running : mardi / samedi à 65%
      if ([2, 6].contains(day.weekday) && rng.nextDouble() < 0.65) {
        final dur = 25 + rng.nextInt(20);
        st.sessions.add(Session(activityId: aRunning.id,
            startAt: t(12, 0), endAt: t(12, 0).add(Duration(minutes: dur))));
      }
      // Deep Work : jours de semaine à 72%
      if (!isWeekend && rng.nextDouble() < 0.72) {
        final dur = 90 + rng.nextInt(90);
        st.sessions.add(Session(activityId: aDeepWork.id,
            startAt: t(9, 30), endAt: t(9, 30).add(Duration(minutes: dur))));
      }
      // Heatmap : vague de productivité sinusoïdale sur 12 semaines
      // → semaines vertes (wave ≈ 0.9) et semaines creuses orange (wave ≈ 0.1)
      final weekIndex = daysAgo ~/ 7;
      final wave = (0.5 + 0.38 * sin(weekIndex * 0.9)).clamp(0.05, 0.95);
      if (rng.nextDouble() < wave * 0.92) {
        st.habitProgress.add(HabitProgress(activityId: hLecture.id, yyyymmdd: ymd, value: 1));
      }
      if (rng.nextDouble() < (wave + 0.12).clamp(0.0, 1.0)) {
        st.habitProgress.add(HabitProgress(activityId: hEau.id, yyyymmdd: ymd, value: 1));
      }
      if (rng.nextDouble() < wave * 0.78) {
        st.habitProgress.add(HabitProgress(activityId: hRevue.id, yyyymmdd: ymd, value: 1));
      }
      if (rng.nextDouble() < wave * 0.70) {
        st.habitProgress.add(HabitProgress(activityId: hSport.id, yyyymmdd: ymd, value: 1));
      }
      if (rng.nextDouble() < wave * 0.62) {
        st.habitProgress.add(HabitProgress(activityId: hVeille.id, yyyymmdd: ymd, value: 1));
      }
    }

    logic.onChange();
    if (mounted) setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Données de démo chargées ✓')),
      );
    }
  }

  Future<void> _showCaptureSheet(BuildContext context) async {
    final ctrl = TextEditingController();
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.lightbulb_outline,
                        color: Colors.amber.shade600, size: 20),
                    const SizedBox(width: 8),
                    Text('Capturer une idée',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).colorScheme.onSurface)),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Ton idée, note rapide...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (_) => Navigator.pop(ctx, true),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.send_outlined, size: 16),
                      label: const Text('Capturer'),
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber.shade600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    final text = ctrl.text.trim();
    if (submitted == true && text.isNotEmpty) {
      final item = CaptureItem(text: text, createdAt: DateTime.now());
      await _sync.saveCaptureItem(item);
    }
    ctrl.dispose();
  }

  /// Minutes de sommeil des 7 dernières nuits (ancien → récent) + cible.
  /// Nuit attribuée au jour du RÉVEIL (fin de session) ; activités retenues :
  /// domaine « Sommeil » ou nom contenant « sommeil ».
  /// Pastille rouge « actions en retard » sur l'icône de l'onglet Actions.
  Widget _overdueBadge(Widget icon) {
    final n = overdueActionCount(logic.currentProjects, DateTime.now());
    if (n == 0) return icon;
    return Badge.count(
      count: n,
      backgroundColor: Theme.of(context).colorScheme.error,
      child: icon,
    );
  }

  bool _shouldShowFab() {
    return _tab == _Tab.dashboard || _tab == _Tab.aujourdhui;
  }

  Widget _buildFab() {
    // RANGÉE horizontale (ergonomie pouce) : la pile verticale masquait le
    // contenu. Capture (GTD), créer action/projet, routine, ▶ activité.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'fab_capture',
          mini: true,
          tooltip: 'Capturer une idée',
          backgroundColor: Colors.amber.shade600,
          foregroundColor: Colors.white,
          onPressed: () => _showCaptureSheet(context),
          child: const Icon(Icons.lightbulb_outline, size: 20),
        ),
        const SizedBox(width: 10),
        FloatingActionButton(
          heroTag: 'fab_create_action',
          mini: true,
          tooltip: 'Créer une action ou un projet',
          onPressed: () => showCreateActionOrProjectSheet(
            context,
            logic: logic,
            sync: _sync,
            onCreated: () {
              if (mounted) setState(() {});
            },
          ),
          child: const Icon(Icons.add_task, size: 20),
        ),
        const SizedBox(width: 10),
        FloatingActionButton(
          heroTag: 'fab_now_routine',
          mini: true,
          tooltip: 'Lancer une routine',
          onPressed: () => _showRoutinesSheet(context),
          child: const Icon(Icons.repeat_rounded),
        ),
        const SizedBox(width: 10),
        FloatingActionButton(
          heroTag: 'fab_launch_activity',
          tooltip: 'Lancer une activité',
          onPressed: () => _showLaunchActivitySheet(context),
          child: const Icon(Icons.play_arrow_rounded),
        ),
      ],
    );
  }

  /// Lance le minuteur d'une routine : démarre l'activité liée + le décompte
  /// (l'anneau s'affiche), et la routine sera cochée à la fin (voir _onAlarmRing).
  void _startRoutineTimer(Activity r) {
    final linkedId = (r.linkedActivityId ?? '').trim();
    final linked = linkedId.isEmpty
        ? null
        : logic.state.activities.firstWhereOrNull((a) => a.id == linkedId);
    final minutes = r.timerMin ?? 0;
    if (minutes <= 0) return;
    // Sans activité liée, le décompte tourne sur la routine elle-même —
    // micro-routine (1 min : vitamines, verre d'eau) cochée à la fin.
    final target = linked ?? r;
    logic.start(target.id);
    _startCountdown(minutes, target.name, routineId: r.id);
    setState(() => _tab = _goNowTab());
  }

  /// ▶ sur une routine sans activité liée : « Où tracer le temps ? » — les
  /// activités-temps du domaine d'abord, choix MÉMORISÉ (linkedActivityId).
  /// « Juste cocher » = pas de chrono (compteur − / + si routine comptée) ;
  /// le sheet reviendra au prochain ▶, laissant la porte ouverte au lien.
  Future<void> _askRoutineTimeOwner(Activity r) async {
    final acts = logic.state.activities
        .where((a) =>
            !a.isHabit && !a.deleted && a.role != ActivityRole.shopping)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final picked = await showActivityPicker(context,
        activities: acts,
        domains: logic.state.activeDomains,
        title: 'Où tracer le temps de « ${r.name} » ?',
        subtitle: 'Le chrono tournera sur l\'activité choisie, la routine se cochera comme d\'habitude — choix mémorisé.',
        preferDomainId: r.domainId,
        trailingExtras: const [ActivityPickerExtra('__check__', 'Juste cocher — pas de chrono', icon: Icons.check_rounded)]);
    if (picked == null || !mounted) return;

    if (picked == '__check__') {
      final tgt = logic.activeHabitTarget(r);
      if (tgt > 1) {
        await showHabitCountSheet(context, logic: logic, activity: r);
        return;
      }
      if (tgt > 0 && routineTodayCount(logic, r) >= tgt) return;
      logic.incHabit(r.id, 1, logic.livedToday);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Routine validée : ${r.name}'),
        duration: const Duration(seconds: 2),
      ));
      return;
    }

    // Lien posé UNE fois — les prochains ▶ iront directement sur l'activité.
    r.linkedActivityId = picked;
    logic.onChange();
    logic.start(picked);
    setState(() {
      _focusProject = null;
      _focusTask = null;
      _tab = _goNowTab();
    });
  }

  /// Menu au lancement (▶) d'un bloc routine minuté dans le programme du jour :
  /// laisse choisir entre chrono libre et minuteur (décompte) sur l'activité liée.
  Future<void> _chooseRoutineLaunch(Activity r, Activity linked) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(r.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Démarrer le chrono'),
              subtitle: Text('Sur « ${linked.name} »'),
              onTap: () {
                Navigator.pop(ctx);
                logic.start(linked.id);
                logic.rev.value++;
                setState(() {
                  _focusProject = null;
                  _focusTask = null;
                  _tab = _goNowTab();
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('Démarrer le minuteur (${r.timerMin} min)'),
              subtitle: Text('Sur « ${linked.name} »'),
              onTap: () {
                Navigator.pop(ctx);
                _startRoutineTimer(r);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Mini-menu d'actions au tap d'une routine dans le lanceur (FAB).
  /// Lanceur de routines (FAB) : `widgets/routine_launcher_sheet.dart`.
  void _showRoutinesSheet(BuildContext context) {
    showRoutineLauncher(
      context,
      logic: logic,
      sync: _sync,
      onNew: () async {
        await _createRoutineFromNow(context);
        if (mounted) setState(() {});
      },
      onChrono: (linked) {
        logic.start(linked.id);
        logic.rev.value++;
        setState(() => _tab = _goNowTab());
      },
      onTimer: _startRoutineTimer,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1) État de chargement (avant que FileStore ait chargé le JSON)
    if (_state == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Refonte : si la nouvelle UI Soft Pop est activée, on rend la coquille
    // dédiée (réversible via son onglet Réglages).
    if (softpopShellEnabled.value) {
      return SoftPopShell(
        logic: logic,
        onExitToClassic: () => setSoftpopShell(false),
      );
    }

    // (Le mode Manoir plein écran a été supprimé avec la couche jeu.)

    final filtersOn = logic.state.filters.isActive;

    // (Hub gamification — score/or/classement/défis — supprimé avec la couche jeu.)

    // 2) App prête -> Scaffold complet. L'overlay assistant est désormais rendu
    // globalement (MaterialApp.builder → GlobalAssistantOverlay), au-dessus des
    // sheets.
    return Stack(
      children: [
        Scaffold(
      appBar: AppBar(
        titleSpacing: 5,
        title: Row(
          children: [
            const SizedBox(width: 3),
            ValueListenableBuilder<int>(
              valueListenable: _tick,
              builder: (context, _, __) {
                final now = DateTime.now();
                final bins24 = logic.minutesByHourLast24(now);
                final domainIds = logic.domainByHourLast24(now);
                final domColors = domainIds
                    .map((id) => id == null
                        ? null
                        : domainColor(id, logic.state.activeDomains))
                    .toList();
                final cs = Theme.of(context).colorScheme;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openLast24hSessionsSheet(context, logic),
                      borderRadius: BorderRadius.circular(999),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest
                              .withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color:
                                  cs.outlineVariant.withValues(alpha: .55)),
                        ),
                        child: MiniHourBars24h(
                            bins: bins24, domainColors: domColors),
                      ),
                    ),
                  ),
                );
              },
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ModePill(logic: logic, badges: _badges),
                ),
              ),
            ),

          ],
        ),
        actions: [
            Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.lightbulb_outline, size: 20),
                tooltip: 'Inbox',
                onPressed: () => showInboxSheet(context, _sync),
              ),
              if (_inboxPendingCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade600,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Plus',
            onSelected: (v) async {
              if (v == 'sync_status') {
                // Ouverture (kFreeForAll) : plus de paywall, console directe.
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DevConsoleScreen()));
              } else if (v == 'proposals') {
                showProposalsSheet(context, _sync);
              } else if (v == 'orion') {
                OrionScreen.show(context, _sync);
              } else if (v == 'weekly_review') {
                showWeeklyReviewSheet(context, _sync);
              } else if (v == 'filters') {
                _openFiltersSheet(context);
              } else if (v == 'changelog') {
                showChangelogSheet(context);
              } else if (v == 'catalogue') {
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: 0.92,
                    minChildSize: 0.5,
                    maxChildSize: 0.95,
                    builder: (_, controller) => CatalogueSheet(
                      logic: logic,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                );
              } else if (v == 'settings') {
                _showSettingsSheet(context);
              }
            },
            itemBuilder: (_) => [
              // Indicateur sync / Pro
              PopupMenuItem(
                value: 'sync_status',
                child: ValueListenableBuilder<bool>(
                  valueListenable: ProManager.notifier,
                  builder: (ctx, isPro, _) => Row(
                    children: [
                      Icon(
                        isPro
                            ? (_syncStatus == '☁️' ? Icons.cloud_done_outlined : Icons.cloud_off_outlined)
                            : Icons.lock_outlined,
                        size: 18,
                        color: isPro ? null : Theme.of(ctx).colorScheme.onSurface.withOpacity(.4),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isPro
                            ? (_syncStatus == '☁️' ? 'Sync OK' : 'Mode local')
                            : 'Passer à Pro',
                        style: TextStyle(
                          color: isPro ? null : Theme.of(ctx).colorScheme.onSurface.withOpacity(.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'proposals',
                child: Row(children: [
                  Icon(Icons.fact_check_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('Propositions à valider'),
                ]),
              ),
              const PopupMenuItem(
                value: 'orion',
                child: Row(children: [
                  Icon(Icons.smart_toy_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('Orion Stratège'),
                ]),
              ),
              const PopupMenuItem(
                value: 'weekly_review',
                child: Row(children: [
                  Icon(Icons.cleaning_services_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('Revue de la semaine'),
                ]),
              ),
              PopupMenuItem(
                value: 'filters',
                child: Row(children: [
                  Icon(Icons.tune, size: 18,
                      color: filtersOn ? Theme.of(context).colorScheme.primary : null),
                  const SizedBox(width: 12),
                  Text('Filtres',
                      style: filtersOn
                          ? TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)
                          : null),
                ]),
              ),
              const PopupMenuItem(
                value: 'changelog',
                child: Row(children: [
                  Icon(Icons.new_releases_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('Nouveautés'),
                ]),
              ),
              const PopupMenuItem(
                value: 'catalogue',
                child: Row(children: [
                  Icon(Icons.library_add_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('Catalogue'),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'settings',
                child: Row(children: [
                  Icon(Icons.settings_outlined, size: 18),
                  SizedBox(width: 12),
                  Text('Paramètres'),
                  Spacer(),
                  Icon(Icons.chevron_right, size: 16),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),

// --- Dans build(...) ---

      body: Column(
        children: [
          if (_authLost)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: SafeArea(
                bottom: false,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.cloud_off_outlined,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  title: Text(
                      'Session expirée — tes données restent ici, mais rien ne se synchronise.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onErrorContainer)),
                  trailing: TextButton(
                    onPressed: () => _showSettingsSheet(context),
                    child: const Text('Se reconnecter'),
                  ),
                ),
              ),
            ),
          ValueListenableBuilder<int>(
            valueListenable: _tick,
            builder: (_, __, ___) {
              final running = logic.runningActivity();
              if (running == null) return const SizedBox.shrink();
              return RunningActivityBanner(
                state: _state,
                logic: logic,
                countdownEndsAt: _countdownEndsAt,
                onTap: () => setState(() => _tab = _goNowTab()),
              );
            },
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
      /* Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: _hasRunningSession ? 92.0 : 0.0),
            child: _buildBody(context),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              bottom: false,
              child: _runningBannerGlobal(),
            ),
          ),
        ],
      ), */

      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      bottomNavigationBar: BottomNavigationBar(
        // Onglet courant absent de la barre (Projets ouvert via un widget
        // alors qu'il est masqué) : on surligne Accueil sans casser la vue.
        currentIndex: _visibleTabs.contains(_tab)
            ? _visibleTabs.indexOf(_tab)
            : 0,
        onTap: (i) {
          final tapped = _visibleTabs[i];
          _tabFadeController.forward(from: 0);
          setState(() => _tab = tapped);
        },
        type: BottomNavigationBarType.fixed,
        // 5 onglets (Maintenant fusionné dans Aujourd'hui) : les libellés
        // tiennent à nouveau, y compris sur iPhone SE.
        showUnselectedLabels: true,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: [
          for (final t in _visibleTabs)
            switch (t) {
              _Tab.dashboard => const BottomNavigationBarItem(
                  icon: Icon(Icons.track_changes_outlined),
                  activeIcon: Icon(Icons.track_changes),
                  label: 'Objectifs'),
              _Tab.stats => const BottomNavigationBarItem(
                  icon: Icon(Icons.query_stats),
                  activeIcon: Icon(Icons.query_stats),
                  label: 'Stats'),
              _Tab.projets => const BottomNavigationBarItem(
                  icon: Icon(Icons.account_tree_outlined),
                  activeIcon: Icon(Icons.account_tree),
                  label: 'Projets'),
              _Tab.aujourdhui => const BottomNavigationBarItem(
                  icon: Icon(Icons.wb_sunny_outlined),
                  activeIcon: Icon(Icons.wb_sunny),
                  label: 'Aujourd\'hui'),
              // Pastille = actions en retard (même règle que le groupe
              // « En retard » de l'onglet).
              _Tab.actions => BottomNavigationBarItem(
                  icon: _overdueBadge(const Icon(Icons.checklist_rtl_outlined)),
                  activeIcon: _overdueBadge(const Icon(Icons.checklist_rtl)),
                  label: 'Actions'),
            },
        ],
      ),

      floatingActionButton: _shouldShowFab() ? _buildFab() : null,
        ),
        // Confetti par-dessus tout
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 30,
            gravity: 0.2,
            emissionFrequency: 0.05,
            maxBlastForce: 20,
            minBlastForce: 8,
            colors: const [
              Color(0xFF6FFFE9),
              Color(0xFF5BC0F8),
              Color(0xFFFFD700),
              Color(0xFFFF6B6B),
              Color(0xFF9B59B6),
            ],
          ),
        ),
      ],
    );
  }

  void _openFiltersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FiltersSheet(
        st: _state!, // ou widget.logic.state si c'est ta source
        logic: logic,
        onChanged: () {
          setState(() {}); // refresh écran après changement filtres
        },
      ),
    );
  }

  /// Indicateur de série affiché sous le nom de la routine.
  /// 🔥×N → ⭐ par tranche de 5j → badge violet au-delà de 25j.

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // La liste a dépassé un écran (Notifications, Mes données, Mon coach…) :
      // hauteur plafonnée + scroll, sinon les entrées du bas sont inatteignables.
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * .85,
          ),
          child: SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Paramètres',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              // (Les entrées « Manoir d'Ombrelune » ont été supprimées avec la
              // couche jeu.)
              // Affichage : Défis du moment (désactivé par défaut)
              StatefulBuilder(
                builder: (ctx, setLocal) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.star_outline),
                  title: const Text('Défis du moment'),
                  subtitle: const Text(
                      'Section en tête de l\'onglet Projets (défis du donjon + priorités)'),
                  value: logic.state.showTodayPriorities,
                  onChanged: (v) {
                    logic.state.showTodayPriorities = v;
                    logic.onChange();
                    setLocal(() {});
                    setState(() {});
                  },
                ),
              ),
              // Gantt invisible : masquer l'onglet Projets — le coach porte
              // les micro-actions dans Maintenant, le Gantt vit en coulisse.
              StatefulBuilder(
                builder: (ctx, setLocal) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Masquer les projets Gantt'),
                  subtitle: const Text(
                      'Le Gantt reste en coulisse (coach, ORION) : blocs du jour, chrono et fiches tâche continuent de fonctionner. S\'applique aussi à l\'app web.'),
                  value: logic.state.hideProjectsTab,
                  onChanged: (v) {
                    logic.state.hideProjectsTab = v;
                    // « Actions » reste visible dans les deux modes ; seul
                    // « Projets » disparaît quand le Gantt passe en coulisse.
                    if (v && _tab == _Tab.projets) _tab = _Tab.actions;
                    logic.onChange();
                    // Pilote aussi la visibilité côté app web (flag Firestore).
                    unawaited(_sync.setGanttVisible(!v));
                    setLocal(() {});
                    setState(() {});
                  },
                ),
              ),
              // Google Agenda natif : le programme suit dans l'agenda,
              // sans passer par le connecteur Claude (OAuth côté serveur).
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Google Agenda'),
                subtitle: const Text(
                    'Programme synchronisé automatiquement dans ton agenda'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showGcalSettingsSheet(context, sync: _sync),
              ),
              // Automatiser avec Claude : tâches planifiées dans LE Claude de
              // l'utilisateur (ouvre claude.ai/new?q=…, rien côté serveur).
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Automatiser avec Claude'),
                subtitle: const Text(
                    'Préparer demain chaque soir, bilan du dimanche…'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showClaudeAutomationSheet(context, sync: _sync),
              ),
              // Sonnerie de l'alarme
              StatefulBuilder(
                builder: (ctx, setLocal) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Sonnerie de l\'alarme'),
                  subtitle: Text(ringtoneByKey(logic.state.alarmSound).label),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () async {
                    await showAlarmRingtoneSheet(context, logic);
                    setLocal(() {});
                    setState(() {});
                  },
                ),
              ),
              // Notifications — déplacé ici depuis le bas de l'onglet Stats.
              // Programmation automatique : la routine Claude du matin lit ce
              // réglage (data/meta.autoPlan) avant d'écrire le programme.
              StreamBuilder<bool>(
                stream: _sync.streamAutoPlan(),
                builder: (ctx, snap) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.auto_mode_outlined),
                  title: const Text('Programmation automatique'),
                  subtitle: Text(snap.data == true
                      ? 'Claude complète ton programme chaque matin vers 6 h'
                      : 'Désactivée · tu planifies toi-même'),
                  value: snap.data == true,
                  onChanged: (v) => _sync.setAutoPlan(v),
                ),
              ),
              // Mode du jour (lot 1 Modes et coups) : même feuille que la
              // pilule de MAINTENANT.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(modeIcon(logic.mode)),
                title: const Text('Mode du jour'),
                subtitle: Text('${modeDescription(logic.mode)} · repart en Normal demain'),
                trailing: Text(kModeLabels[logic.mode]!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                onTap: () => showModeSheet(context, logic, badges: _badges),
              ),
              // Budget des minimums (Modes et coups lot 4) : 7 j = semaine
              // calendaire, 14 j = quinzaine à départ fixe (concentrer plutôt qu'étaler).
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_view_week_outlined),
                title: const Text('Budget des minimums'),
                subtitle: Text(logic.budgetWindowDays == 14
                    ? 'Sur 14 jours · pousser 3 jours puis lâcher 5 jours reste au rythme'
                    : 'Sur la semaine · attendu = minimum × jours écoulés'),
                trailing: Text(logic.budgetWindowDays == 14 ? '14 j' : '7 j', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                onTap: () async {
                  final picked = await showModalBottomSheet<int>(
                    context: context,
                    showDragHandle: true,
                    builder: (c) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text('Budget des minimums de domaine', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        ListTile(
                          title: const Text('Sur la semaine · 7 j'),
                          subtitle: const Text('Attendu chaque jour, remis à zéro le lundi'),
                          trailing: logic.budgetWindowDays == 7 ? const Icon(Icons.check, size: 18) : null,
                          onTap: () => Navigator.pop(c, 7),
                        ),
                        ListTile(
                          title: const Text('Sur 14 jours · conseillé'),
                          subtitle: const Text('Quinzaine à départ fixe : on peut concentrer, le repère « attendu aujourd\'hui » reste'),
                          trailing: logic.budgetWindowDays == 14 ? const Icon(Icons.check, size: 18) : null,
                          onTap: () => Navigator.pop(c, 14),
                        ),
                        const SizedBox(height: 8),
                      ]),
                    ),
                  );
                  if (picked == null) return;
                  logic.budgetWindowDays = picked;
                  logic.onChange();
                  await _sync.setBudgetWindowDays(picked);
                },
              ),
              // Élan (allègement 2026-10) : une fois par jour par défaut, à
              // chaque moment sur demande.
              StreamBuilder<Map<String, dynamic>>(
                stream: _sync.streamMetaDoc(),
                builder: (ctx, snap) {
                  final all = snap.data?['elanPromptsAll'] == true;
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.mood_outlined),
                    title: const Text('Élan : demander à chaque moment'),
                    subtitle: Text(all
                        ? 'Matin, après-midi et soir · trois pointages par jour'
                        : 'Une fois par jour, au premier geste · « Ton élan, là ? »'),
                    value: all,
                    onChanged: (v) => _sync.setElanPromptsAll(v),
                  );
                },
              ),
              // Journée vécue des routines : avant cette heure, on est encore
              // « hier » (compte, moment courant, reports). Travail de nuit →
              // 8 h ou 10 h.
              StreamBuilder<int>(
                stream: _sync.streamDayStartMin(),
                builder: (ctx, snap) {
                  final v = snap.data ?? logic.dayStartMin;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bedtime_outlined),
                    title: const Text('La journée commence à'),
                    subtitle: Text('${dayStartLabel(v)} · avant, les routines et les moments restent sur la veille'),
                    trailing: Text(dayStartLabel(v),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    onTap: () async {
                      final picked = await showModalBottomSheet<int>(
                        context: ctx,
                        showDragHandle: true,
                        builder: (c) => SafeArea(
                          child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: Text('La journée commence à',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            ),
                            for (var h = 0; h <= 12; h++)
                              ListTile(
                                title: Text(h == 0 ? 'Minuit' : '$h h'),
                                subtitle: h == 5 ? const Text('par défaut') : null,
                                trailing: v == h * 60 ? const Icon(Icons.check, size: 18) : null,
                                onTap: () => Navigator.pop(c, h * 60),
                              ),
                          ]),
                        ),
                      );
                      if (picked == null) return;
                      await _sync.setDayStartMin(picked);
                    },
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.wb_twilight_outlined),
                title: const Text('Moments de la journée'),
                subtitle: Text(logic.moments.map((m) => '${m.label} ${m.window}').join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showMomentsEditor(context, logic: logic, sync: _sync),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                subtitle: const Text(
                    'Rappel quotidien, résumé du jour, streaks…'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showNotificationsSheet(context);
                },
              ),
              // Badges (lot 1, 2026-10) : aperçu du gabarit et du deck calculé
              // sur les vraies données — pas encore d'onglet ni de signal.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.military_tech_outlined),
                title: const Text('Badges · aperçu'),
                subtitle: const Text('Le deck calculé sur tes routines, journées, objectifs et actions'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.of(sheetCtx).push(MaterialPageRoute<void>(
                    builder: (_) => BadgeGalleryScreen(logic: logic, sync: _sync, center: _badges))),
              ),
              // Siri & Raccourcis (iOS uniquement)
              if (!kIsWeb && Platform.isIOS)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mic_none_outlined),
                  title: const Text('Siri & Raccourcis'),
                  subtitle: const Text(
                      'Cocher une routine et lire ton programme à la voix'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () async {
                    await SiriService.refreshShortcuts();
                    if (!sheetCtx.mounted) return;
                    await showDialog<void>(
                      context: sheetCtx,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Siri & Raccourcis'),
                        content: const Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Dis à Siri :'),
                            SizedBox(height: 8),
                            Text('• « Quel est mon programme dans Productivitwo »'),
                            Text('• « Quelle est ma tâche du jour dans Productivitwo »'),
                            Text('• « Coche ma routine dans Productivitwo »'),
                            SizedBox(height: 12),
                            Text(
                              'Tu peux aussi créer tes propres raccourcis dans l\'app Raccourcis.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dctx),
                            child: const Text('Fermer'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(dctx);
                              launchUrl(Uri.parse('shortcuts://'));
                            },
                            child: const Text('Ouvrir Raccourcis'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              // Aperçu Soft Pop (design system de la refonte — preview)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Aperçu Soft Pop'),
                subtitle: const Text('Design system de la refonte (preview)'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SoftPopPreviewScreen(),
                    ),
                  );
                },
              ),
              // Accueil Soft Pop branché sur les vraies données (aperçu)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home_outlined),
                title: const Text('Accueil Soft Pop · vraies données'),
                subtitle:
                    const Text('Tes routines réelles dans le nouveau design'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SoftPopHomeLiveScreen(logic: logic),
                    ),
                  );
                },
              ),
              // Bascule : utiliser la nouvelle UI Soft Pop par défaut (réversible)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Nouvelle UI Soft Pop par défaut'),
                subtitle: const Text(
                    'Lance l’app sur la nouvelle interface (retour possible depuis ses Réglages)'),
                value: softpopShellEnabled.value,
                onChanged: (v) {
                  setSoftpopShell(v);
                  Navigator.pop(sheetCtx);
                },
              ),
              // Compte
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: const Text('Compte'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Compte',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).colorScheme.onSurface)),
                          const SizedBox(height: 12),
                          // Connexion email proposée seulement si pas encore
                          // connecté : une fois un compte lié, on n'affiche que
                          // ce compte (pas d'option de connexion redondante).
                          if (_sync.isAnonymous) ...[
                            EmailSignInTile(
                              sync: _sync,
                              state: _state!,
                              onDataChanged: () {
                                Navigator.pop(context);
                                _init();
                              },
                            ),
                            const Divider(height: 24),
                          ],
                          AppleSignInTile(
                            sync: _sync,
                            state: _state!,
                            onDataChanged: () {
                              Navigator.pop(context);
                              _init();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Mes données — export/restauration/suppression (lot « Coffre »)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Mes données'),
                subtitle:
                    const Text('Sauvegarde, restauration, suppression'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DataSettingsScreen(
                      logic: logic,
                      sync: _sync,
                      store: store,
                    ),
                  ));
                },
              ),
              // Mon coach — le coaché gère SON partage (consentement,
              // périmètre, révocation). Le rôle coach vit sur la console web.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.supervisor_account_outlined),
                title: const Text('Mon coach'),
                subtitle: const Text(
                    'Ce que ton coach voit — et ce qu\'il ne voit pas'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CoachSpaceScreen(logic: logic),
                  ));
                },
              ),
              // Confidentialité
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Confidentialité'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyScreen(),
                  ));
                },
              ),
              // Suggérer une feature
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lightbulb_outline),
                title: const Text('Suggérer une feature'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final uri = Uri(
                    scheme: 'mailto',
                    path: 'emeric.edmond@gmail.com',
                    queryParameters: {
                      'subject': '[Productivitwo] Suggestion',
                      'body': 'Bonjour,\n\nVoici ma suggestion :\n\n',
                    },
                  );
                  launchUrl(uri);
                },
              ),
              // Données de démo
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.science_outlined),
                title: const Text('Charger des données de démo'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _loadDemoData();
                },
              ),
              // Console dev
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.terminal_outlined),
                title: const Text('Console dev'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const DevConsoleScreen(),
                  ));
                },
              ),
              const Divider(height: 24),
              // Supprimer le compte — zone danger
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error),
                title: Text(
                  'Supprimer mon compte',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Supprimer mon compte'),
                      content: const Text(
                        'Toutes vos données seront supprimées définitivement '
                        '(activités, routines, sessions, objectifs).\n\n'
                        'Cette action est irréversible.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Supprimer définitivement'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    // Spinner pendant la suppression
                    if (context.mounted) {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => const PopScope(
                          canPop: false,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      );
                    }
                    try { await _sync.deleteAccount(); } catch (_) {}
                    await store.wipe();
                    await ProManager.deactivate();
                    exit(0);
                  }
                },
              ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }

  int? effectiveTarget(Activity act) {
    switch (act.habitFreq) {
      case HabitFreq.daily:
        return act.habitTarget;
      case HabitFreq.weekly:
        return act.habitTarget;
      case HabitFreq.monthly:
        return act.habitTarget;
      default:
        return 0;
    }
  }

  ({double prog7, double haloAbs, double prog90, double bigAll, String label, double todayProgress, String centerText, String subText})
      _computeGlobalTimeGauges(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    final start7Inc = today.subtract(const Duration(days: 6));
    final end7Inc = today.add(const Duration(days: 1));

    final start90Inc = today.subtract(const Duration(days: 89));
    final end90Inc = today.add(const Duration(days: 1));

    final totalsToday = logic.timeTotalsByDomain(today, now);
    final totalTodayDur =
        totalsToday.values.fold<Duration>(Duration.zero, (a, b) => a + b);
    final totalTodayHours = totalTodayDur.inMinutes / 60.0;

    final dailyTargetMinRaw = _state!.activeActivities
        .where((a) => a.type == 'time' && a.goalMin > 0)
        .fold<int>(0, (sum, a) => sum + a.goalMin);
    // Plafond 24h : la cible globale = somme des cibles p90 de chaque domaine
    // (on vise le meilleur jour de chacun), ce qui peut dépasser une journée.
    // On bride l'objectif VISIBLE à 24h pour que le % reste lisible.
    final dailyTargetMinAll =
        dailyTargetMinRaw > 24 * 60 ? 24 * 60 : dailyTargetMinRaw;

    final dailyTargetHoursAll = dailyTargetMinAll / 60.0;

    double totalHoursOverRange(DateTime start, DateTime endExcl) {
      final totals = logic.timeTotalsByDomain(start, endExcl);
      final dur = totals.values.fold<Duration>(Duration.zero, (a, b) => a + b);
      return dur.inMinutes / 60.0;
    }

    final done7HoursAll = totalHoursOverRange(start7Inc, end7Inc);
    final done90HoursAll = totalHoursOverRange(start90Inc, end90Inc);

    final target7HoursAll = dailyTargetHoursAll * 7.0;

    final total7HoursAbs = 7.0 * 24.0;
    final progTimeAll7 = (done7HoursAll / total7HoursAbs).clamp(0.0, 1.0);

    final total24Hours = 24.0;
    final haloAllAbs = (totalTodayHours / total24Hours).clamp(0.0, 1.0);

    final bigAll = (target7HoursAll > 0)
        ? (done7HoursAll / target7HoursAll).clamp(0.0, 1.0)
        : 0.0;

    final total90HoursAbs = 90.0 * 24.0;
    final progTimeAll90 = (done90HoursAll / total90HoursAbs).clamp(0.0, 1.0);

    final labelAll = _fmtHoursHM(totalTodayHours);

    // Pour GaugeRing : progression aujourd'hui vs objectif journalier
    final todayProg = dailyTargetHoursAll > 0
        ? (totalTodayHours / dailyTargetHoursAll).clamp(0.0, 1.5)
        : 0.0;
    final totalTodayMin = totalTodayDur.inMinutes;
    final doneH = totalTodayMin ~/ 60;
    final doneM = totalTodayMin % 60;
    final centerTxt = doneH > 0
        ? '${doneH}h${doneM.toString().padLeft(2, '0')}'
        : '${doneM}min';
    final goalH = dailyTargetMinAll ~/ 60;
    final goalM = dailyTargetMinAll % 60;
    final subTxt = goalH > 0
        ? 'Objectif ${goalH}h${goalM > 0 ? goalM.toString().padLeft(2, '0') : ''}'
        : 'Objectif ${dailyTargetMinAll}min';

    return (
      prog7: progTimeAll7,
      haloAbs: haloAllAbs,
      prog90: progTimeAll90,
      bigAll: bigAll,
      label: labelAll,
      todayProgress: todayProg,
      centerText: centerTxt,
      subText: subTxt,
    );
  }

  ({
    double bigForGauge,
    double rate90,
    double outerPrimary,
    String label,
    String centerText,
    String subText,
  }) _computeGlobalHabitsGauge(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // Fenêtres (calendaires)
    final start7Inc = today.subtract(const Duration(days: 6));
    final end7Inc = tomorrow;

    final start90 = today.subtract(const Duration(days: 89));
    final end90 = tomorrow;

    int doneHabitsAllCalendar(DateTime start, DateTime end) {
      int sum = 0;
      for (final d in _state!.activeDomains) {
        // done par domaine
        DateTime day = DateTime(start.year, start.month, start.day);
        while (day.isBefore(end)) {
          for (final a in _state!.activeActivities
              .where((a) => a.isHabit && a.domainId == d.id)) {
            sum += logic.habitValueOn(a.id, day);
          }
          day = day.add(const Duration(days: 1));
        }
      }
      return sum;
    }

    int targetHabitsAllCalendar(DateTime start, DateTime end) {
      final days = end.difference(start).inDays;
      int sum = 0;
      for (final a in _state!.activeActivities.where((a) => a.isHabit)) {
        sum += logic.dayQuotaFor(a) * days;
      }
      return sum;
    }

    // Today / Week
    final doneToday = doneHabitsAllCalendar(today, tomorrow);
    final tgtToday = targetHabitsAllCalendar(today, tomorrow);

    final done7 = doneHabitsAllCalendar(start7Inc, end7Inc);
    final tgt7 = targetHabitsAllCalendar(start7Inc, end7Inc);

    final rateToday = tgtToday == 0 ? 0.0 : (doneToday / tgtToday);
    final rateWeek = tgt7 == 0 ? 0.0 : (done7 / tgt7);

    final bigForGauge = (done7 == 0 && doneToday > 0) ? rateToday : rateWeek;

    // 90j
    final done90 = doneHabitsAllCalendar(start90, end90);
    final tgt90 = targetHabitsAllCalendar(start90, end90);
    final rate90 = tgt90 == 0 ? 0.0 : (done90 / tgt90).clamp(0.0, 1.0);

    // Comptage binaire : routines atteintes / total
    final routineItems = logic.routineProgressItemsForCurrentPeriod();
    final totalRoutines = routineItems.length;
    final reachedRoutines = routineItems.where((it) => it.isReached).length;
    final label = "$reachedRoutines / $totalRoutines";
    final outerPrimary = totalRoutines == 0
        ? 0.0
        : (reachedRoutines / totalRoutines).clamp(0.0, 1.0);

    return (
      bigForGauge: bigForGauge.clamp(0.0, 1.0),
      rate90: rate90,
      outerPrimary: outerPrimary,
      label: label,
      centerText: label,
      subText: 'Routines',
    );
  }

  // ── Priorités du jour ──────────────────────────────────────────────────────

  Widget _buildTodayPrioritiesSection(BuildContext context, ColorScheme cs) {
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final List<({Project project, ProjectTask task})> todayTasks = [];
    for (final project in _dashboardProjects) {
      if (project.status == 'archived' || project.status == 'done') continue;
      for (final task in project.tasks) {
        if (task.todayFlag && task.status != 'skipped') {
          todayTasks.add((project: project, task: task));
        }
      }
    }

    final todayActivities = logic.state.activities
        .where((a) => a.isHabit && !a.deleted && a.todayFlag)
        .toList();

    final freeItems = logic.state.todayItems
        .where((i) => i.date == todayKey)
        .toList();

    final total =
        todayTasks.length + todayActivities.length + freeItems.length;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade600),
                const SizedBox(width: 6),
                Text(
                  'DÉFIS DU MOMENT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: cs.onSurface.withOpacity(.5),
                  ),
                ),
                const Spacer(),
                if (total > 0) ...[
                  Text(
                    '$total',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.amber.shade600,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                // Bouton + ajout rapide
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _showAddTodayItemSheet(context),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.add_circle_outline,
                        size: 18, color: cs.onSurface.withOpacity(.45)),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(.3)),
          // ── Items Gantt ──────────────────────────────────────────────────────
          for (final entry in todayTasks)
            _buildPriorityTaskTile(context, cs, entry.project, entry.task),
          // ── Routines ────────────────────────────────────────────────────────
          for (final activity in todayActivities)
            _buildPriorityActivityTile(context, cs, activity, today),
          // ── Items libres ─────────────────────────────────────────────────────
          for (final item in freeItems)
            _buildPriorityFreeTile(context, cs, item),
          // ── État vide ────────────────────────────────────────────────────────
          if (total == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text(
                'Aucun défi pour le moment — appuie sur + pour en ajouter un',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withOpacity(.35),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _showAddTodayItemSheet(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ajouter une priorité',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Faire…',
                  hintStyle:
                      TextStyle(color: cs.onSurface.withOpacity(.35)),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withOpacity(.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                onSubmitted: (v) {
                  final text = v.trim();
                  if (text.isEmpty) return;
                  logic.addTodayItem(text);
                  setState(() {});
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final text = ctrl.text.trim();
                    if (text.isEmpty) return;
                    logic.addTodayItem(text);
                    setState(() {});
                    Navigator.pop(ctx);
                  },
                  child: const Text('Ajouter'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPriorityFreeTile(
      BuildContext context, ColorScheme cs, TodayItem item) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      leading: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          logic.toggleTodayItem(item.id);
          setState(() {});
        },
        child: Icon(
          item.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 20,
          color: item.done
              ? Colors.green.shade500
              : cs.onSurface.withOpacity(.4),
        ),
      ),
      title: Text(
        item.text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          decoration: item.done ? TextDecoration.lineThrough : null,
          color: cs.onSurface.withOpacity(item.done ? .4 : .9),
        ),
      ),
      trailing: IconButton(
        icon: Icon(Icons.close, size: 16, color: cs.onSurface.withOpacity(.3)),
        visualDensity: VisualDensity.compact,
        onPressed: () {
          logic.removeTodayItem(item.id);
          setState(() {});
        },
      ),
    );
  }

  Widget _buildPriorityTaskTile(
      BuildContext context, ColorScheme cs, Project project, ProjectTask task) {
    final isDone = task.status == 'done';

    // 3 premières sous-actions non cochées, dans leur ordre actuel
    final pendingActions = task.actions
        .where((a) => !a.done)
        .take(3)
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── En-tête tâche ────────────────────────────────────────────────────
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          leading: GestureDetector(
            onTap: () async {
              setState(() => task.status = isDone ? 'pending' : 'done');
              await _sync.saveProjectTasks(project.id, project.tasks);
            },
            child: Icon(
              isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 20,
              color: isDone ? Colors.green.shade500 : cs.onSurface.withOpacity(.4),
            ),
          ),
          title: Text(
            task.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: isDone ? TextDecoration.lineThrough : null,
              color: cs.onSurface.withOpacity(isDone ? .4 : .9),
            ),
          ),
          subtitle: Text(
            project.title,
            style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.4)),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.star_rounded, size: 18),
            color: Colors.amber.shade600,
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await _sync.toggleTaskTodayFlag(project.id, task.id, false);
              setState(() {});
            },
          ),
        ),
        // ── Sous-actions (si tâche pas encore done et qu'il y en a) ─────────
        if (!isDone && pendingActions.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: pendingActions.length,
            onReorder: (oldIdx, newIdx) {
              setState(() {
                // Retrouver les indices réels dans task.actions (parmi les non-done)
                final pendingIndices = task.actions
                    .asMap()
                    .entries
                    .where((e) => !e.value.done)
                    .map((e) => e.key)
                    .take(3)
                    .toList();
                if (newIdx > oldIdx) newIdx--;
                final from = pendingIndices[oldIdx];
                final to = pendingIndices[newIdx];
                final item = task.actions.removeAt(from);
                task.actions.insert(to, item);
              });
              _sync.saveProjectTasks(project.id, project.tasks);
            },
            itemBuilder: (ctx, i) {
              final action = pendingActions[i];
              return ListTile(
                key: ValueKey(action.id),
                dense: true,
                minLeadingWidth: 0,
                contentPadding: const EdgeInsets.only(left: 40, right: 8),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: Icon(Icons.drag_handle_rounded,
                      size: 16, color: cs.onSurface.withOpacity(.25)),
                ),
                title: Text(
                  action.title,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(.75),
                  ),
                ),
                trailing: GestureDetector(
                  onTap: () async {
                    setState(() {
                      action.done = true;
                      action.doneAt = DateTime.now();
                    });
                    await _sync.saveProjectTasks(project.id, project.tasks);
                  },
                  child: Icon(Icons.radio_button_unchecked,
                      size: 16, color: cs.onSurface.withOpacity(.35)),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPriorityActivityTile(
      BuildContext context, ColorScheme cs, Activity activity, DateTime today) {
    final value = logic.habitValueOn(activity.id, today);
    final isDone = value >= 1;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      leading: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          logic.incHabitWithAssocEvent(activity.id, isDone ? -1 : 1, today);
          logic.onChange();
          setState(() {});
        },
        child: Icon(
          isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 20,
          color: isDone ? Colors.green.shade500 : cs.onSurface.withOpacity(.4),
        ),
      ),
      title: Text(
        activity.name,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          decoration: isDone ? TextDecoration.lineThrough : null,
          color: cs.onSurface.withOpacity(isDone ? .4 : .9),
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.star_rounded, size: 18),
        color: Colors.amber.shade600,
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          logic.setActivityTodayFlag(activity.id, false);
          await _sync.toggleActivityTodayFlag(activity.id, false);
          setState(() {});
        },
      ),
    );
  }

  /// Onglet OBJECTIFS : pyramide Aujourd'hui / Cette semaine / 30 jours.
  /// Le tableau de bord est maintenant l'onglet « Stats » — l'icône en
  /// haut d'Objectifs y bascule (plus d'écran poussé).
  Widget _buildObjectivesBody(BuildContext context) {
    return ObjectivesHomeView(
      logic: logic,
      sync: _sync,
      badges: _badges,
      projects: _dashboardProjects,
      onOpenDashboard: () {
        _tabFadeController.forward(from: 0);
        setState(() => _tab = _Tab.stats);
      },
      onOpenNow: () {
        _tabFadeController.forward(from: 0);
        setState(() => _tab = _goNowTab());
      },
    );
  }

  // Cache anti-jank de l'onglet Stats : la page est chère à construire
  // (stats par domaine sur TOUTES les sessions) et chaque setState global
  // (streams Firestore, heartbeat…) la reconstruisait entière — pendant un
  // scroll, ça lague et fait sauter la liste. Les enfants ne sont refaits
  // que quand la minute ou les données changent réellement.
  String? _statsCacheKey;
  List<Widget>? _statsCacheChildren;

  Widget _buildDashboardBody(BuildContext context) {
    // 1) Temps “de contexte” (scope/range). OK de recalculer au build.
    final now = DateTime.now();

    // Scope calendaire (détails domaine)
    final (startCal, endCal, days) = _rangeForScope(now);

    // Helpers habits calendaire (tu peux les laisser ici)

    // ⚠️ IMPORTANT :
    // Les valeurs “live” (temps today jusqu'à now, halo, label, etc.)
    // seront calculées dans ValueListenableBuilder via _compute... (voir plus bas)

    return ValueListenableBuilder<int>(
      valueListenable: _tick,
      builder: (context, tickValue, __) {
        final stx = _state!;
        // Empreinte volontairement bon marché : tick minute + proxys de
        // volume. Une édition purement cosmétique (renommage…) peut mettre
        // jusqu'à une minute à se refléter ici — compromis assumé.
        final cacheKey = [
          tickValue,
          scope,
          stx.sessions.length,
          stx.habitHits.length,
          stx.habitProgress.fold<int>(0, (a, hp) => a + hp.value),
          stx.activities.length,
          stx.domains.length,
          _dashboardProjects.length,
          stx.hideProjectsTab,
        ].join('|');
        if (cacheKey == _statsCacheKey && _statsCacheChildren != null) {
          return ListView(children: _statsCacheChildren!);
        }
        _statsCacheKey = cacheKey;
        final now = DateTime.now();
        final g = _computeGlobalTimeGauges(now);
        final h = _computeGlobalHabitsGauge(now);
        final cs = Theme.of(context).colorScheme;

        // Sections nommées de la fiche « Ma semaine » (2026-10) : chacune est
        // repliable, plus de lectures empilées en vrac.
        List<WeekDetailSection> weekDetails(BuildContext ctx) => [
        (title: 'JAUGES DU JOUR · COURBE DE LA SEMAINE', child: SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Builder(
            builder: (context) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(builder: (context) {
                    final today2 = DateTime.now();
                    final todayD2 = DateTime(today2.year, today2.month, today2.day);
                    final activeProjects = _dashboardProjects
                        .where((p) => p.status != 'archived' && p.status != 'done')
                        .toList();
                    final ganttTasks = activeProjects
                        .expand((p) => p.tasks)
                        .where((t) =>
                            t.startDate.isBefore(todayD2.add(const Duration(days: 1))) &&
                            t.status != 'skipped')
                        .toList();
                    // Tâches sans sous-actions : comptées au niveau tâche.
                    // Tâches avec sous-actions : comptées au niveau sous-action.
                    int ganttDone = 0, ganttTotal = 0;
                    for (final t in ganttTasks) {
                      if (t.actions.isEmpty) {
                        ganttTotal += 1;
                        if (t.status == 'done') ganttDone += 1;
                      } else {
                        ganttTotal += t.actions.length;
                        ganttDone += t.stepsDone;
                      }
                    }
                    final ganttProg = ganttTotal == 0 ? 0.0 : (ganttDone / ganttTotal).clamp(0.0, 1.0);

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GaugeRing(
                          label: 'Activités',
                          labelIcon: Icons.timer_outlined,
                          progress: g.todayProgress,
                          centerText: g.centerText,
                          color: _colorForProgress(g.todayProgress, context),
                          size: 115,
                          onTap: () async {
                            final goNow = await _showDomainDetail(
                                null, startCal, endCal, days,
                                focus: 'time');
                            if (!mounted) return;
                            if (goNow == true) setState(() => _tab = _goNowTab());
                          },
                        ),
                        GaugeRing(
                          label: 'Routines',
                          labelIcon: Icons.repeat_rounded,
                          progress: h.outerPrimary,
                          centerText: h.centerText,
                          color: _colorForProgress(h.outerPrimary, context),
                          size: 115,
                          onTap: () => _showDomainDetail(
                              null, startCal, endCal, days,
                              focus: 'habit'),
                        ),
                        // Jauge Projets gatée avec l'onglet : quand le Gantt
                        // est en retrait, le user ne pilote plus par actions.
                        if (!logic.state.hideProjectsTab)
                          GaugeRing(
                            label: 'Projets',
                            labelIcon: Icons.account_tree_outlined,
                            progress: ganttProg,
                            centerText: ganttTotal == 0 ? '—' : '$ganttDone/$ganttTotal',
                            color: _colorForProgress(ganttProg, context),
                            size: 115,
                            onTap: () => setState(() => _tab = _Tab.projets),
                          ),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    final weekData = logic.weeklyScoreData();
                    final current = weekData.current;
                    final previous = weekData.previous;
                    final diff = current - previous;
                    final currentPct = (current * 100).round();
                    final previousPct = (previous * 100).round();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WeekScoreChart(
                          scores: weekData.days7,
                          target: logic.state.weeklyScoreTarget / 100.0,
                          todayIndex: now.weekday - 1,
                          cs: cs,
                          onDayTap: (i) {
                            setState(() {
                              _tab = _Tab.dashboard;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Text(
                                'Cette semaine : $currentPct%',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withOpacity(.5),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Sem. préc. : $previousPct%',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withOpacity(.4),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Icon(
                                diff >= 0
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 13,
                                color: diff >= 0
                                    ? cs.primary
                                    : cs.error.withOpacity(.7),
                              ),
                              Text(
                                '${diff >= 0 ? '+' : ''}${(diff * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: diff >= 0
                                      ? cs.primary
                                      : cs.error.withOpacity(.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              );
            },
          ),
        )),
        // Lecture du temps (venue d'Objectifs, allègement 2026-10) : heatmap par
        // domaine, 12 semaines, camembert du jour.
        (title: 'TEMPS PAR DOMAINE · 12 SEMAINES', child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: AccueilTimeStats(logic: logic),
        )),
        (title: 'AUJOURD\'HUI · TEMPS LOGGUÉ', child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TodayLoggedPie(logic: logic),
        )),
        (title: 'RETARDS', child: PestCounterCard(logic: logic)),
        ];
        _statsCacheChildren = [
          WeekStatsView(
            logic: logic,
            sync: _sync,
            badges: _badges,
            onOpenDomain: (d, {focus = 'time'}) async {
              final goNow = await _showDomainDetail(d, startCal, endCal, days, focus: focus);
              if (!mounted) return goNow;
              if (goNow == true) setState(() => _tab = _goNowTab());
              return goNow;
            },
            onManageDomains: () => _showDomainsSheet(context),
            weekDetails: weekDetails,
          ),
        ];
        return ListView(children: _statsCacheChildren!);
      },
    );
  }

  Widget _notifSettingRow(
    BuildContext context,
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required int hour,
    required int minute,
    required bool enabled,
    required Future<void> Function(TimeOfDay) onPicked,
    required Future<void> Function(bool) onToggled,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: cs.onSurface.withOpacity(enabled ? .55 : .25)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withOpacity(enabled ? .7 : .35))),
          ),
          if (enabled)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: hour, minute: minute),
                  helpText: label,
                );
                if (picked == null || !mounted) return;
                await onPicked(picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.primary),
                ),
              ),
            ),
          Switch(
            value: enabled,
            onChanged: (v) => onToggled(v),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  void _showDomainsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final cs = Theme.of(ctx).colorScheme;
          final domains = logic.state.activeDomains;

          Future<void> rename(Domain d) async {
            final ctrl = TextEditingController(text: d.name);
            final result = await showDialog<String>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                title: const Text('Renommer le domaine'),
                content: TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  onSubmitted: (_) => Navigator.pop(dctx, ctrl.text.trim()),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dctx),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
                      child: const Text('OK')),
                ],
              ),
            );
            if (result == null || result.isEmpty) return;
            d.name = result;
            logic.onChange();
            setS(() {});
            setState(() {});
          }

          Future<void> addDomain() async {
            final ctrl = TextEditingController();
            final result = await showDialog<String>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                title: const Text('Nouveau domaine'),
                content: TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  onSubmitted: (_) => Navigator.pop(dctx, ctrl.text.trim()),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dctx),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
                      child: const Text('Créer')),
                ],
              ),
            );
            if (result == null || result.isEmpty) return;
            logic.createDomain(result);
            setS(() {});
            setState(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Domaines',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 18)),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Ajouter'),
                          style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                          onPressed: addDomain,
                        ),
                      ],
                    ),
                  ),
                  // Pastille « Mes domaines » : intentions & minimum vital
                  // (sessions de définition avec Orion).
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DomainsScreen(logic: logic),
                      ));
                    },
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .primaryContainer
                            .withOpacity(.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Theme.of(ctx)
                                .colorScheme
                                .primary
                                .withOpacity(.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.flag_outlined,
                              size: 14,
                              color: Theme.of(ctx).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Intentions & minimum vital — définis tes domaines avec Orion',
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(.65)),
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: Theme.of(ctx)
                                  .colorScheme
                                  .primary
                                  .withOpacity(.5)),
                        ],
                      ),
                    ),
                  ),
                  // Pastille catalogue
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => SizedBox(
                          height: MediaQuery.of(context).size.height * 0.85,
                          child: CatalogueSheet(
                            logic: logic,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.primaryContainer.withOpacity(.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Theme.of(ctx).colorScheme.primary.withOpacity(.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_outlined,
                              size: 14,
                              color: Theme.of(ctx).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Découvre les domaines et activités préconfigurés dans le catalogue',
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.65)),
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: Theme.of(ctx).colorScheme.primary.withOpacity(.5)),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: domains.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16),
                    itemBuilder: (ctx, i) {
                      final d = domains[i];
                      final dColor = domainColor(d.id, domains)
                          ?? kDomainPalette[i % kDomainPalette.length];
                      return ListTile(
                        leading: GestureDetector(
                          onTap: () async {
                            final picked = await showDialog<Color>(
                              context: ctx,
                              builder: (dctx) => AlertDialog(
                                title: const Text('Couleur du domaine'),
                                content: Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: kColorPickerOptions.map((c) =>
                                    GestureDetector(
                                      onTap: () => Navigator.pop(dctx, c),
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: c,
                                          shape: BoxShape.circle,
                                          border: d.colorValue == c.value
                                              ? Border.all(
                                                  color: cs.primary, width: 3)
                                              : Border.all(
                                                  color: Colors.transparent),
                                        ),
                                      ),
                                    ),
                                  ).toList(),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dctx),
                                    child: const Text('Annuler'),
                                  ),
                                  if (d.colorValue != null)
                                    TextButton(
                                      onPressed: () {
                                        d.colorValue = null;
                                        logic.onChange();
                                        setS(() {});
                                        setState(() {});
                                        Navigator.pop(dctx);
                                      },
                                      child: const Text('Réinitialiser'),
                                    ),
                                ],
                              ),
                            );
                            if (picked == null) return;
                            d.colorValue = picked.value;
                            logic.onChange();
                            setS(() {});
                            setState(() {});
                          },
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: dColor,
                          ),
                        ),
                        title: Text(d.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit_outlined,
                                  size: 18, color: cs.onSurface.withOpacity(.45)),
                              onPressed: () => rename(d),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: cs.error.withOpacity(.7)),
                              onPressed: () async {
                                final actCount = logic.state.activities
                                    .where((a) => a.domainId == d.id)
                                    .length;
                                final confirm = await showDialog<bool>(
                                  context: ctx,
                                  builder: (dctx) => AlertDialog(
                                    title: const Text('Supprimer le domaine'),
                                    content: Text(actCount > 0
                                        ? 'Supprimer "${d.name}" ? Les $actCount activité(s) liée(s) seront détachées.'
                                        : 'Supprimer "${d.name}" ?'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dctx, false),
                                          child: const Text('Annuler')),
                                      FilledButton(
                                          style: FilledButton.styleFrom(
                                              backgroundColor: cs.error),
                                          onPressed: () =>
                                              Navigator.pop(dctx, true),
                                          child: const Text('Supprimer')),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                logic.deleteDomain(d);
                                setS(() {});
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showNotificationsSheet(BuildContext context) {
    final orionPush = ValueNotifier<bool?>(null);
    _sync.fetchOrionPushEnabled().then((v) => orionPush.value = v).catchError((_) => orionPush.value = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSB) {
          final cs = Theme.of(ctx).colorScheme;
          void rebuild() => setSB(() => setState(() {}));

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text('Notifications',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                  const Divider(height: 1),
                  _notifSettingRow(ctx, cs,
                    icon: Icons.notifications_outlined,
                    label: 'Ta journée (matin)',
                    hour: _state!.notifHour,
                    minute: _state!.notifMinute,
                    enabled: _state!.notifEnabled,
                    onToggled: (v) async {
                      setState(() => _state!.notifEnabled = v);
                      logic.onChange(); rebuild();
                      if (!v) { await NotificationService.cancelById(1); return; }
                      await _refreshDayNotifs();
                    },
                    onPicked: (picked) async {
                      setState(() { _state!.notifHour = picked.hour; _state!.notifMinute = picked.minute; });
                      logic.onChange(); rebuild();
                      await _refreshDayNotifs();
                    },
                  ),
                  const Divider(height: 1),
                  _notifSettingRow(ctx, cs,
                    icon: Icons.summarize_outlined,
                    label: 'Résumé du jour',
                    hour: _state!.reviewNotifHour,
                    minute: _state!.reviewNotifMinute,
                    enabled: _state!.reviewNotifEnabled,
                    onToggled: (v) async {
                      setState(() => _state!.reviewNotifEnabled = v);
                      logic.onChange(); rebuild();
                      if (!v) { await NotificationService.cancelById(2); return; }
                      await NotificationService.scheduleDailyReview(
                          hour: _state!.reviewNotifHour, minute: _state!.reviewNotifMinute);
                    },
                    onPicked: (picked) async {
                      setState(() { _state!.reviewNotifHour = picked.hour; _state!.reviewNotifMinute = picked.minute; });
                      logic.onChange(); rebuild();
                      await NotificationService.scheduleDailyReview(hour: picked.hour, minute: picked.minute);
                    },
                  ),
                  const Divider(height: 1),
                  _notifSettingRow(ctx, cs,
                    icon: Icons.local_fire_department_outlined,
                    label: 'Ce soir · journée parfaite',
                    hour: _state!.streakNotifHour,
                    minute: _state!.streakNotifMinute,
                    enabled: _state!.eveningNotifEnabled,
                    onToggled: (v) async {
                      setState(() => _state!.eveningNotifEnabled = v);
                      logic.onChange(); rebuild();
                      await _refreshDayNotifs();
                    },
                    onPicked: (picked) async {
                      setState(() { _state!.streakNotifHour = picked.hour; _state!.streakNotifMinute = picked.minute; });
                      logic.onChange(); rebuild();
                      await _refreshDayNotifs();
                    },
                  ),
                  const Divider(height: 1),
                  // Push du serveur : pas d'heure, un interrupteur.
                  ValueListenableBuilder<bool?>(
                    valueListenable: orionPush,
                    builder: (_, on, __) => SwitchListTile(
                      secondary: const Icon(Icons.forum_outlined),
                      title: const Text('Messages ORION / coach'),
                      subtitle: const Text('Dès qu\'un message arrive, jamais avant le jour prévu'),
                      value: on ?? true,
                      onChanged: on == null
                          ? null
                          : (v) {
                              orionPush.value = v;
                              _sync.setOrionPushEnabled(v);
                            },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double snapToFull(double value, {double threshold = 0.97}) {
    if (value >= threshold) return 1.0;
    return value.clamp(0.0, 1.0);
  }

  Future<void> _createActivityDialog({
    String? domainId, // si null -> on affiche un dropdown
    required bool isHabit,
  }) async {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(); // seulement pertinent pour habit
    String? selectedDomainId = domainId ??
        (_state!.activeDomains.isNotEmpty ? _state!.activeDomains.first.id : null);

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isHabit ? "Nouvelle routine" : "Nouvelle activité"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (domainId == null) // choix du domaine si "Tous"
                  DropdownButtonFormField<String>(
                    value: selectedDomainId,
                    onChanged: (v) => selectedDomainId = v,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: "Domaine"),
                    items: _state!.activeDomains
                        .map((d) =>
                            DropdownMenuItem(value: d.id, child: Text(d.name)))
                        .toList(),
                  ),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "Nom"),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                if (isHabit) ...[
                  TextField(
                    controller: unitCtrl,
                    decoration: const InputDecoration(
                      labelText: "Unité (facultatif) ex: verres, pompes",
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Objectif automatique : 1 / mois (s'ajuste tout seul chaque jour).",
                    style: TextStyle(fontSize: 12),
                  ),
                ] else ...[
                  const Text(
                    "Objectif automatique : 1 minute (s'ajuste tout seul chaque jour).",
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Annuler"),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty || selectedDomainId == null) return;

                if (isHabit) {
                  // ROUTINE : 1 / mois par défaut (auto-tune actif)
                  final a = Activity(
                    domainId: selectedDomainId!,
                    name: name,
                    type: 'habit',
                    habitFreq: HabitFreq.monthly, // 👈 1 / mois
                    habitTarget: 1,
                    autoTune: true,
                    unit: unitCtrl.text.trim().isEmpty
                        ? null
                        : unitCtrl.text.trim(),
                  );
                  _state!.activities.add(a);
                } else {
                  // ACTIVITÉ TEMPS : 1 minute par défaut
                  final a = Activity(
                    domainId: selectedDomainId!,
                    name: name,
                    type: 'time',
                    goalMin: 1, habitTarget: 1, // 👈 1 min
                  );
                  _state!.activities.add(a);
                }

                _saveAndRefresh();
                Navigator.of(ctx).pop();
              },
              child: const Text("Créer"),
            ),
          ],
        );
      },
    );
  }

  // ---- Helpers HABIT ----
  bool _habitDayReached(AppLogic l, Activity a) {
    final int tgt = logic.dayQuotaFor(a);
    if (tgt <= 0) return false;
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    final done = l.habitValueOn(a.id, d);
    return done >= tgt;
  }

  bool _habitWeekMonthReached(AppLogic l, Activity a) {
    final w = l.habitSliding(a.id, 7);
    final m = l.habitSliding(a.id, 30);
    final wOK = (w.target > 0) && (w.done >= w.target);
    final mOK = (m.target > 0) && (m.done >= m.target);
    return wOK && mOK;
  }

  /// dailyStrict: global => vrai (on juge uniquement le JOUR)
  bool isHabitOverCap(AppLogic l, Activity a, {required bool dailyStrict}) {
    final dayOK = _habitDayReached(l, a);
    return dailyStrict ? dayOK : (dayOK || _habitWeekMonthReached(l, a));
  }

// ---- Helpers TEMPS ----
  bool isTimeOverCap(AppLogic l, Activity a, {required bool dailyStrict}) {
    final d1 = l.timeSliding(a.id, 1); // {doneMin, targetMin}
    final d7 = l.timeSliding(a.id, 7);
    final d30 = l.timeSliding(a.id, 30);
    final dayOK = (d1.targetMin > 0) && (d1.doneMin >= d1.targetMin);
    final weekOK = (d7.targetMin > 0) && (d7.doneMin >= d7.targetMin);
    final monthOK = (d30.targetMin > 0) && (d30.doneMin >= d30.targetMin);
    return dailyStrict ? dayOK : (dayOK || (weekOK && monthOK));
  }

  Activity? firstUnderToSuggestTime(List<Activity> base) {
    const snap = 0.95;
    final cache = <String, bool>{};

    bool reached(Activity a) => cache.putIfAbsent(
          a.id,
          () => isTimeReachedByAvg7(
            logic,
            a,
            sessions: _state!.sessions,
            snap: snap,
          ),
        );

    final under = base.where((a) => !reached(a)).toList();
    return under.isEmpty ? null : under.first;
  }

  /// Fiche d'une activité-temps (refonte 2026-10, `widgets/activity_fiche_sheet.dart`).
  /// Renvoie `true` quand quelque chose a changé ou qu'un chrono a été lancé.
  Future<bool> _openActivitySheet(Activity a) => showActivityFiche(
        context,
        logic: logic,
        sync: _sync,
        activity: a,
        onLaunchTimed: (act, m) {
          logic.start(act.id);
          _startCountdown(m, act.name);
        },
        onLaunchBlock: (b) => _launchScheduledBlock(b, goToNow: false),
        onEditSession: (sess) => openEditSessionSheet(context, logic, sess, sync: _sync),
      );


  /// Page d'un domaine (ou de toutes les activités / routines) : refonte
  /// « une carte, une fiche » 2026-10 (`widgets/domain_page.dart`). Renvoie
  /// `true` quand un chrono a été lancé depuis la page.
  Future<bool?> _showDomainDetail(Domain? domain, DateTime start, DateTime end, int days, {String focus = 'time'}) {
    return showDomainPage(
      context,
      logic: logic,
      sync: _sync,
      domain: domain,
      focus: focus,
      onCreate: ({String? domainId, required bool isHabit}) => _createActivityDialog(domainId: domainId, isHabit: isHabit),
      onOpenActivity: _openActivitySheet,
      onLaunchTimed: (a, m) {
        logic.start(a.id);
        _startCountdown(m, a.name);
      },
      onLaunchBlock: (b) => _launchScheduledBlock(b, goToNow: false),
    );
  }
  Color _colorForProgress(double p, BuildContext ctx) {
    //if (p >= 0.99) return Colors.transparent;
    if (p >= 0.50) return Colors.green;
    if (p >= 0.25) return Colors.orange;
    return Colors.redAccent;
  }

}

class ChallengeActivityChip extends StatelessWidget {
  final String title;
  final DateTime? endsAt; // null => pas en cours
  final Duration duration; // affichage quand pas en cours
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback? onPickSnooze;

  const ChallengeActivityChip({
    super.key,
    required this.title,
    required this.endsAt,
    required this.duration,
    required this.onStart,
    required this.onStop,
    required this.onPickSnooze,
  });

  String _mmss(Duration d) {
    final s = d.inSeconds.clamp(0, 999999);
    final m = s ~/ 60;
    final sec = s % 60;
    return "$m:${sec.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final running = endsAt != null && endsAt!.isAfter(DateTime.now());

        final left = running ? endsAt!.difference(DateTime.now()) : duration;
        final label = _mmss(left);

        return Tooltip(
          message: running
              ? "Quitter le challenge (l'activité continue)"
              : "Démarrer un challenge de ${duration.inMinutes} min",
          waitDuration: const Duration(milliseconds: 400),
          showDuration: const Duration(seconds: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: running ? onStop : onStart,
            onLongPress: onPickSnooze,
            child: _chipUi(context, label, title, running),
          ),
        );
      },
    );
  }

  Widget _chipUi(
      BuildContext context, String label, String title, bool running) {
    final theme = Theme.of(context);
    final bg = theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final accent = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: bg,
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined,
              size: 18, color: accent.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Text(
            "$label • $title",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: accent.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            running ? Icons.close : Icons.play_circle_outline,
            size: 18,
            color: accent.withValues(alpha: 0.85),
          ),
        ],
      ),
    );
  }
}

class AppBarProductivityBars extends StatelessWidget {
  final AppLogic logic;
  final AppState? state;

  const AppBarProductivityBars({
    super.key,
    required this.logic,
    required this.state,
  });

  String _fmtHhMmPerDay(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return "${h}h${m.toString().padLeft(2, '0')}/j";
  }

  Widget _bar(BuildContext context, double p) {
    final bg = Theme.of(context).colorScheme.onSurface.withOpacity(0.10);
    Theme.of(context).colorScheme.onSurface.withOpacity(0.70);
    final progress = p.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 40,
        height: 4,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth;

            // ✅ minimum 1px si progress > 0
            final fill = (progress <= 0) ? 0.0 : (w * progress).clamp(1.0, w);
            final cs = Theme.of(context).colorScheme;

            // couleurs: cyan (réalisé) + rouge (reste)
            final doneColor = cs.primary; // cyan/teal
            return Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: bg)),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: fill,
                  child: ColoredBox(color: doneColor),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    final m7 = logic.avgMinutesPerDayInclToday(7);
    final m30 = logic.avgMinutesPerDayInclToday(30);
    final m90 = logic.avgMinutesPerDayInclToday(90);

    final t7 = logic.totalMinutesInclToday(7);
    final t30 = logic.totalMinutesInclToday(30);
    final t90 = logic.totalMinutesInclToday(90);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;

        Widget row(String label, int avgMin, int totalMin) {
          final totalH = totalMin ~/ 60;
          final totalM = totalMin % 60;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (avgMin / 1440.0).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor:
                              cs.onSurface.withValues(alpha: .10),
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmtHhMmPerDay(avgMin),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      "${totalH}h${totalM.toString().padLeft(2, '0')} total",
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: .55)),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.bar_chart_rounded, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Productivité',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Temps actif moyen par jour · base 24h',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: .6)),
                    ),
                  ),
                ),
                row('90 jours', m90, t90),
                row('30 jours', m30, t30),
                row('7 jours', m7, t7),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final m7 = logic.avgMinutesPerDayInclToday(7);
    final m30 = logic.avgMinutesPerDayInclToday(30);
    final m90 = logic.avgMinutesPerDayInclToday(90);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openSheet(context),
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .55)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _bar(context, m90 / 1440.0),
                const SizedBox(height: 3),
                _bar(context, m30 / 1440.0),
                const SizedBox(height: 3),
                _bar(context, m7 / 1440.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini-graphe SOMMEIL de l'appbar (test 2026-09) : 7 nuits en barres
/// (nuit attribuée au jour du RÉVEIL — fin de session), échelle 9 h,
/// vert dès la cible atteinte (goalMin de l'activité sommeil, sinon 7 h).
class MiniSleepBars extends StatelessWidget {
  final List<int> nightsMin; // 7 valeurs, minutes, ancien → récent
  final int goalMin;
  final double height;
  final double width;

  const MiniSleepBars({
    super.key,
    required this.nightsMin,
    required this.goalMin,
    this.height = 18,
    this.width = 26,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const maxMin = 9 * 60;
    return SizedBox(
      width: width,
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.5),
                child: FractionallySizedBox(
                  heightFactor: nightsMin[i] <= 0
                      ? 0.08
                      : (nightsMin[i] / maxMin).clamp(0.15, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: nightsMin[i] <= 0
                          ? cs.onSurface.withOpacity(.15)
                          : nightsMin[i] >= goalMin
                              ? Colors.teal.shade400
                              : Colors.indigo.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MiniHourBars24h extends StatelessWidget {
  final List<int> bins; // 24 valeurs (0..60)
  final List<Color?>? domainColors; // couleur dominante par heure (optionnel)
  final double height;
  final double width;
  final double gap;

  const MiniHourBars24h({
    super.key,
    required this.bins,
    this.domainColors,
    this.height = 18,
    this.width = 54,
    this.gap = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final restColor = cs.onSurface.withOpacity(0.12);

    return SizedBox(
      width: width,
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(24, (i) {
          final isCurrentHour = i == bins.length - 1;
          final mins = (i < bins.length) ? bins[i].clamp(0, 60) : 0;
          final doneFrac = mins / 60.0;
          final restFrac = 1.0 - doneFrac;
          final barColor = (domainColors != null && i < domainColors!.length)
              ? (domainColors![i] ?? cs.primary)
              : cs.primary;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gap / 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Column(
                  children: [
                    Expanded(
                      flex: (restFrac * 1000).round().clamp(0, 1000),
                      child: Container(color: restColor),
                    ),
                    Expanded(
                      flex: (doneFrac * 1000).round().clamp(0, 1000),
                      child: Container(
                        color: isCurrentHour
                            ? barColor
                            : barColor.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Graphe score 7 jours ──────────────────────────────────────────────────────

class _WeekScoreChart extends StatefulWidget {
  final List<double> scores;
  final double target;
  final int todayIndex;
  final ColorScheme cs;
  final void Function(int dayIndex)? onDayTap;

  const _WeekScoreChart({
    required this.scores,
    required this.target,
    required this.todayIndex,
    required this.cs,
    this.onDayTap,
  });

  @override
  State<_WeekScoreChart> createState() => _WeekScoreChartState();
}

class _WeekScoreChartState extends State<_WeekScoreChart> {
  int? _selected;

  static const _labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const _maxH = 46.0;
  static const _labelH = 18.0;
  static const _chipH = 18.0;

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final lineBottom = _labelH + widget.target * _maxH;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: _chipH + 2 + _maxH + _labelH, // 84
        child: Stack(
          children: [
            // ── Barres ───────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final score = widget.scores[i];
                final isFuture = score < 0;
                final isToday = i == widget.todayIndex;
                final isSelected = _selected == i;
                final ratio = isFuture ? 0.0 : score.clamp(0.0, 1.0);

                final Color barColor;
                if (isFuture) {
                  barColor = cs.onSurface.withOpacity(.07);
                } else if (score == 0) {
                  barColor = cs.onSurface.withOpacity(.10);
                } else if (score >= widget.target) {
                  barColor = cs.primary;
                } else {
                  barColor = cs.primary.withOpacity(.45);
                }

                final barH = isFuture
                    ? 3.0
                    : (ratio * _maxH < 4.0 ? 4.0 : ratio * _maxH);

                return Expanded(
                  child: GestureDetector(
                    onTap: isFuture
                        ? null
                        : () {
                            setState(() {
                              _selected = isSelected ? null : i;
                            });
                            widget.onDayTap?.call(i);
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Chip score (zone toujours réservée)
                          SizedBox(
                            height: _chipH,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: isSelected && !isFuture
                                  ? Center(
                                      key: ValueKey('chip_$i'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cs.primary,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${(score * 100).round()}%',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: cs.onPrimary,
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Barre
                          SizedBox(
                            height: _maxH,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                                height: barH,
                                decoration: BoxDecoration(
                                  color: barColor,
                                  borderRadius: BorderRadius.circular(4),
                                  border: isSelected
                                      ? Border.all(
                                          color: cs.primary, width: 1.5)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Label jour
                          Text(
                            _labels[i],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: (isToday || isSelected)
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: (isToday || isSelected)
                                  ? cs.primary
                                  : cs.onSurface.withOpacity(.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),

            // ── Ligne de seuil ────────────────────────────────────────
            Positioned(
              bottom: lineBottom,
              left: 0,
              right: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: _DashedLinePainter(
                          color: cs.primary.withOpacity(.35)),
                      child: const SizedBox(height: 1),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${(widget.target * 100).round()}%',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: cs.primary.withOpacity(.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const dashW = 4.0;
    const gapW = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashW, 0), paint);
      x += dashW + gapW;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

