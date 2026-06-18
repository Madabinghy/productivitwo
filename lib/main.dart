// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:productivitwo_v1/utils/time_scope.dart';
import 'package:productivitwo_v1/widgets/alarm_ringtone_sheet.dart';
import 'package:productivitwo_v1/widgets/appbar_routines_summery.dart';
import 'package:productivitwo_v1/widgets/filters_sheet.dart';
import 'package:productivitwo_v1/widgets/habit_settings_sheet.dart';
import 'package:productivitwo_v1/widgets/habit_tile_full.dart';
import 'package:productivitwo_v1/widgets/ring_painter.dart';
import 'package:productivitwo_v1/widgets/goals_view.dart';
import 'package:productivitwo_v1/widgets/new_routine_sheet.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart';
import 'package:productivitwo_v1/widgets/day_review_sheet.dart';
import 'package:productivitwo_v1/widgets/productivity_stats_card.dart';
import 'package:productivitwo_v1/widgets/onboarding_screen.dart';
import 'package:confetti/confetti.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/storage.dart';
import 'package:productivitwo_v1/notifications.dart';
import 'package:alarm/alarm.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:productivitwo_v1/widgets/time_report_card.dart';
import 'package:productivitwo_v1/widgets/routine_freq_card.dart';
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
import 'package:productivitwo_v1/widgets/expedition_map_game.dart';
import 'package:productivitwo_v1/widgets/expedition_sheet.dart';
import 'package:productivitwo_v1/widgets/gold_sheet.dart';
import 'package:productivitwo_v1/widgets/gamification_hub_sheet.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';
import 'package:productivitwo_v1/widgets/orion_screen.dart';
import 'package:productivitwo_v1/widgets/proposals_sheet.dart';
import 'package:productivitwo_v1/widgets/world_mobile_sheet.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:productivitwo_v1/widgets/focus_view.dart';
import 'package:productivitwo_v1/widgets/task_schedule.dart';
import 'package:productivitwo_v1/web/assistant_engine.dart';
import 'package:productivitwo_v1/web/assistant_widget.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:productivitwo_v1/widget_service.dart';
import 'package:productivitwo_v1/siri_service.dart';

enum _Tab { dashboard, projets, maintenant, monde }

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
  runApp(const ProductivitwoApp());
}

class ProductivitwoApp extends StatelessWidget {
  const ProductivitwoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system, // clair/sombre selon l'iPhone
      // Overlay assistant AU-DESSUS du Navigator → visible même par-dessus les
      // bottom sheets (sinon il était caché derrière, jamais vu).
      builder: (context, child) => GlobalAssistantOverlay(child: child!),
      home: const AppRoot(),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.teal,
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

  const _EditSessionResult._({
    required this.delete,
    this.startAt,
    this.endAt,
    this.activityId,
  });

  factory _EditSessionResult.delete() =>
      const _EditSessionResult._(delete: true);

  factory _EditSessionResult.save({
    DateTime? startAt,
    DateTime? endAt,
    String? activityId,
  }) =>
      _EditSessionResult._(
        delete: false,
        startAt: startAt,
        endAt: endAt,
        activityId: activityId,
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

  @override
  void initState() {
    super.initState();
    _start = widget.session.startAt;
    _end = widget.session.endAt;
    _activityId = widget.session.activityId;
  }

  Future<String?> _pickActivity(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        final acts = widget.logic.state.activities;

        return ListView.builder(
          itemCount: acts.length,
          itemBuilder: (_, i) {
            final a = acts[i];
            return ListTile(
              title: Text(a.name),
              onTap: () => Navigator.pop(context, a.id),
            );
          },
        );
      },
    );
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
class _ChallengeMeButton extends StatelessWidget {
  final int streak;
  final VoidCallback onTap;
  const _ChallengeMeButton({required this.streak, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFFE7C66B), Color(0xFFB8860B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB8860B).withOpacity(.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Challenge me',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                    Text('ORION choisit, tu relèves',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              if (streak > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('🔥 $streak',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }
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

  Future<void> _openEditSessionSheet(
    BuildContext context,
    dynamic logic,
    Session s,
  ) async {
    final res = await showModalBottomSheet<_EditSessionResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditSessionSheet(
        session: s,
        logic: logic,
      ),
    );

    if (res == null) return;

    if (res.delete) {
      logic.deleteSession(s.id);
      sync?.deleteSession(s.id); // hard-delete Firestore — évite le retour au prochain pull
      if (mounted) setState(() {});
      return;
    }

    final newStart = res.startAt ?? s.startAt;
    final newEnd = res.endAt;

    if (newEnd != null && !newEnd.isAfter(newStart)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La fin doit être après le début.")),
      );
      return;
    }

    logic.updateSession(
      s.id,
      startAt: res.startAt,
      endAt: res.endAt,
      activityId: res.activityId,
    );
    if (mounted) setState(() {}); // refresh immédiat (pas besoin de quitter)
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
  String _syncStatus = ''; // '' = en cours, '☁️' = OK, '⚠️' = local
  DateTime _lastGlobalScan = DateTime.fromMillisecondsSinceEpoch(0);
  AppState? _state;
  late AppLogic logic;
  String? selectedDomainId;
  TimeScope scope = TimeScope.day;
  Timer? _heartbeat;
  _Tab _tab = _Tab.dashboard;
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
    // Sonnerie du minuteur : déclenchée par le package `alarm` (même app en arrière-plan).
    _alarmRingSub = Alarm.ringStream.stream.listen(_onAlarmRing);
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
            _syncStatus = '⚠️';
          });
        }
      },
    ).catchError((e) {
      devLog.error('_init() exception non catchée', tag: 'MAIN', error: e);
    }).whenComplete(_drainPendingDeepLink).whenComplete(_restoreCountdownFromAlarm);

    // Ouvre le bon sheet quand l'utilisateur tape une notification
    NotificationService.onNotificationTap = (id) {
      final ctx = _navigatorKey.currentState?.overlay?.context;
      if (ctx == null) return;
      switch (id) {
        case 2: // Résumé du jour
          showDayReviewSheet(ctx, logic: logic, projects: _dashboardProjects);
        case 3: // Streak en danger → onglet À faire
        case 4: // Défi du jour → onglet À faire
          setState(() => _tab = _Tab.projets);
        case 5: // Score mi-journée → résumé du jour
          showDayReviewSheet(ctx, logic: logic, projects: _dashboardProjects);
      }
    };

    // Traite un tap bufferisé (race condition background).
    // handleLaunchNotification() est appelé à la fin de _init(), après que
    // logic soit initialisé, pour éviter un LateInitializationError.
    NotificationService.drainPending();
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

      // 2) puis toutes les minutes
      _heartbeat = Timer.periodic(const Duration(minutes: 1), (_) {
        _tick.value++;
      });
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _countdownTimer?.cancel();
    _alarmRingSub?.cancel();
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
      logic.reconcileLiveGold(_sync); // gains du jour dispo de suite au retour
      _restoreCountdownFromAlarm(); // le minuteur survit au quitter/rouvrir
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

    // Garantit une session Firebase Auth — crée une session anonyme si nécessaire
    // (cas : première installation ou après suppression de compte)
    if (onMobile && _sync.uid == null) {
      try { await _sync.signInAnonymously(); } catch (_) {}
    }

    final firestoreEnabled = onMobile && _sync.uid != null;

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
        logic.updateGanttCounts(projects); // met à jour les compteurs + currentProjects
        // Persiste le compteur `ganttActionsByDay` réconcilié (actions cochées
        // sur n'importe quelle surface) → le banking du soir lit la même source.
        unawaited(_doSave());
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
      // Live Activity iOS : persiste les tokens APNs (push‑to‑start / activité) →
      // permet le démarrage distant app fermée (cf. Cloud Function APNs).
      LiveActivityService.instance.onToken = (type, token, {activityId}) {
        unawaited(_sync.saveLiveActivityToken(
            type: type, token: token, activityId: activityId));
      };
      unawaited(LiveActivityService.instance.registerForRemoteStart());
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
      await logic.healGoldCursorIfNeeded(_sync);
      if (fetched) logic.updateGanttCounts(projects);
      logic.materializeGoldUpTo(_sync, DateTime.now());
      logic.reconcileLiveGold(_sync);
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
      final routineCount = logic.state.activities
          .where((a) =>
              a.isHabit &&
              logic.effectiveHabitFreq(a) == HabitFreq.daily)
          .length;
      final st = logic.state;
      if (st.notifEnabled) await NotificationService.scheduleDailyReminder(
        hour: st.notifHour, minute: st.notifMinute, routineCount: routineCount);
      if (st.reviewNotifEnabled) await NotificationService.scheduleDailyReview(
        hour: st.reviewNotifHour, minute: st.reviewNotifMinute);
      if (st.streakNotifEnabled) await NotificationService.scheduleStreakReminder(
        hour: st.streakNotifHour, minute: st.streakNotifMinute,
        routineNames: logic.streakAtRiskNames());
      if (st.challengeNotifEnabled) await NotificationService.scheduleChallengeReminder(
        hour: st.challengeNotifHour, minute: st.challengeNotifMinute);
      if (st.midDayNotifEnabled) await NotificationService.scheduleMidDayScore(
        hour: st.midDayNotifHour, minute: st.midDayNotifMinute);
      final blocksWithTime = st.blocks
          .where((b) => b.startHour != null)
          .map((b) => (
                id: b.id,
                label: '${b.emoji != null ? "${b.emoji} " : ""}${b.name}',
                hour: b.startHour!,
                minute: b.startMinute ?? 0,
              ))
          .toList();
      await NotificationService.scheduleBlockReminders(blocks: blocksWithTime);

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
      // Sync Firestore pour tous les users (anonymes inclus)
      if (_sync.uid != null && !kIsWeb && !Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
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
    Alarm.set(
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
        showProjectSheet(context,
            project: project,
            domains: _state?.domains ?? [],
            targetTaskId: block.taskId);
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
  Future<void> _launchScheduledBlock(ScheduleBlock block) async {
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
              _tab = _Tab.maintenant;
            });
            return;
          }
        }
        logic.start(block.activityId!);
        setState(() {
          _focusProject = null;
          _focusTask = null;
          _tab = _Tab.maintenant;
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
      activity = await showModalBottomSheet<Activity>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Sur quelle activité chronométrer ?',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
              for (final a in domainActs)
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(a.name),
                  onTap: () => Navigator.pop(ctx, a),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }
    if (activity == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Aucune activité de temps dans ce domaine pour lancer le chrono.')));
      }
      return;
    }
    logic.start(activity.id);
    final focusActId = activity.id;
    setState(() {
      _focusProject = project;
      _focusTask = task;
      _focusActivityId = focusActId;
      _tab = _Tab.maintenant;
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    Alarm.stop(_timerAlarmId);
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
  int _tabIndex(_Tab t) {
    switch (t) {
      case _Tab.dashboard:   return 0;
      case _Tab.projets:     return 1;
      case _Tab.maintenant:  return 2;
      case _Tab.monde:       return 3;
    }
  }

  _Tab _tabFromIndex(int i) {
    switch (i) {
      case 0:  return _Tab.dashboard;
      case 1:  return _Tab.projets;
      case 2:  return _Tab.maintenant;
      case 3:  return _Tab.monde;
      default: return _Tab.dashboard;
    }
  }

  Widget _buildBody(BuildContext context) {
    final st = _state!;
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



    return FadeTransition(
      opacity: _tabFade,
      child: IndexedStack(
        index: _tabIndex(_tab),
        children: [
          _buildDashboardBody(context),
          GoalsView(
            domains: _state?.domains ?? [],
            activities: _state?.activities ?? [],
            header: logic.state.showTodayPriorities
                ? _buildTodayPrioritiesSection(
                    context, Theme.of(context).colorScheme)
                : null,
            onStartTimer: (activity, project, task) {
              logic.start(activity.id);
              setState(() {
                _focusProject = project;
                _focusTask = task;
                _tab = _Tab.maintenant;
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
          FocusView(
            logic: logic,
            state: st,
            // Quête retirée de « Maintenant » une fois le coffre récupéré.
            header: logic.state.lastQuestClaimedYmd ==
                    yyyymmdd(DateTime.now())
                ? null
                : _buildQuestBanner(context, Theme.of(context).colorScheme),
            focusProject: _focusProject,
            focusTask: _focusTask,
            countdownEndsAt: _countdownEndsAt,
            countdownTotalSec: _countdownTotalSec,
            onLaunchScheduledBlock: _launchScheduledBlock,
            onOpenScheduledBlockSource: _openBlockSource,
            onGoToProjects: () => setState(() => _tab = _Tab.projets),
            onStartTimer: (activity, project, task) {
              logic.start(activity.id);
              setState(() {
                _focusProject = project;
                _focusTask = task;
                _focusActivityId = activity.id;
              });
            },
            // Couper le minuteur AVANT la fin → bascule en chrono (session continue).
            onStopCountdown: () {
              _cancelCountdown();
              setState(() {});
            },
            // Arrêter (mode chrono) → stoppe la session pour de bon.
            onStopTimer: () {
              _cancelCountdown(); // sécurité si un décompte traînait
              logic.stopActive();
              setState(() {
                _focusProject = null;
                _focusTask = null;
                _focusActivityId = null;
              });
            },
            onClearFocusTask: (project, task) {
              setState(() {
                _focusProject = null;
                _focusTask = null;
                _focusActivityId = null;
              });
            },
            onTaskTap: (project, task) => showProjectSheet(
              context,
              project: project,
              domains: _state?.domains ?? [],
              targetTaskId: task.id,
            ),
          ),
          WorldMobileScreen(
            logic: logic,
            sync: _sync,
            onOpenActivity: (id) {
              final a = logic.state.activities
                  .firstWhereOrNull((x) => x.id == id);
              if (a != null) _openActivitySheet(a);
            },
          ),
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
        setState(() => _tab = _Tab.maintenant);
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
    );
  }

  // ---------- UI ----------

  /// Défi ORION : choisit localement l'activité la plus en retard sur sa cible
  /// du jour, propose un minuteur, et lance l'activité + l'alarme si accepté.
  Future<void> _showChallenge() async {
    // Exclut les activités ayant déjà un défi programmé (aujourd'hui/futur) →
    // ORION propose autre chose, l'utilisateur étale ses défis.
    final scheduledIds = await _sync.fetchScheduledChallengeActivityIds();
    if (!mounted) return;
    final a = logic.challengeActivity(exclude: scheduledIds);
    if (a == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🤖 Tes cibles du jour sont à jour — rien à rattraper 💪'),
        duration: Duration(seconds: 3),
      ));
      return;
    }
    final minutes = logic.challengeDurationFor(a);
    final cs = Theme.of(context).colorScheme;
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.smart_toy_rounded,
            color: Color(0xFFB8860B), size: 32),
        title: const Text('ORION te défie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$minutes min de « ${a.name} »',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                'Maintenant, ou programme-le pour plus tard (il rejoint ton plan du jour).',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withOpacity(.6))),
          ],
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, null),
              child: const Text('Pas maintenant')),
          TextButton(
              onPressed: () => Navigator.pop(d, 'schedule'),
              child: const Text('Programmer 📅')),
          FilledButton(
              onPressed: () => Navigator.pop(d, 'now'),
              child: const Text('Je relève 🔥')),
        ],
      ),
    );
    if (choice == 'schedule') {
      await _programChallenge(a, minutes);
      return;
    }
    if (choice != 'now') return;
    logic.start(a.id);
    _startCountdown(minutes, a.name);
    final now = DateTime.now();
    final ymd =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    logic.recordChallengeAccepted(ymd);
    if (mounted) setState(() => _tab = _Tab.maintenant);
  }

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

    final ids = NotificationService.challengeNotifIds(block.id);
    await NotificationService.scheduleChallengeAt(
      id: ids.atTime,
      when: at,
      title: '🔥 Défi : ${a.name}',
      body: '$minutes min — c\'est le moment 💪',
      alarm: true,
      ringtone: ringtoneByKey(logic.state.alarmSound),
    );
    if (remAt != null) {
      await NotificationService.scheduleChallengeAt(
        id: ids.reminder,
        when: remAt,
        title: 'Défi prévu : ${a.name}',
        body: 'À $hhmm • $minutes min',
        alarm: false,
      );
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

  Future<void> _showLaunchActivitySheet(BuildContext context) async {
    final activities = logic.state.activities
        .where((a) => !a.isHabit && a.role != ActivityRole.shopping)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (activities.isEmpty) return;

    final domainById = {for (final d in logic.state.activeDomains) d.id: d};

    // Grouper par domaine
    final Map<String, List<Activity>> byDomain = {};
    for (final a in activities) {
      (byDomain[a.domainId] ??= []).add(a);
    }
    final domainOrder = logic.state.activeDomains.map((d) => d.id).toList()
      ..add(''); // domaines orphelins en dernier

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final running = logic.runningActivity();

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (ctx, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Lancer une activité',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                    if (running != null)
                      TextButton.icon(
                        icon: const Icon(Icons.stop, size: 16),
                        label: const Text('Arrêter'),
                        style: TextButton.styleFrom(
                            foregroundColor: cs.error,
                            visualDensity: VisualDensity.compact),
                        onPressed: () async {
                          _cancelCountdown();
                          final (_, name, delta) =
                              await logic.stopActiveWithAdjustment();
                          setState(() {});
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (delta != null && delta > 0 && name != null &&
                              mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text('Objectif ajusté : $name +${delta}min'),
                              duration: const Duration(seconds: 3),
                            ));
                          }
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: [
                    // ── Bouton doré « Challenge me » (défi ORION) ──────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: _ChallengeMeButton(
                        streak: logic.state.challengeStreak,
                        onTap: () {
                          Navigator.pop(ctx);
                          _showChallenge();
                        },
                      ),
                    ),
                    for (final domId in domainOrder)
                      if (byDomain.containsKey(domId)) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                          child: Text(
                            domainById[domId]?.name ?? 'Sans domaine',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: cs.onSurface.withOpacity(.45),
                            ),
                          ),
                        ),
                        for (final a in byDomain[domId]!) ...[
                          Builder(builder: (ctx2) {
                            final isRunning = running?.id == a.id;
                            final dColor = domainColor(domId, logic.state.activeDomains) ?? cs.primary;
                            final now2 = DateTime.now();
                            final todayStart = DateTime(now2.year, now2.month, now2.day);
                            final todayMin = logic.totalForRangeByActivity(a.id, todayStart, now2).inMinutes;
                            final timeStr = todayMin == 0 ? null
                                : todayMin < 60 ? '${todayMin}min'
                                : '${(todayMin / 60).floor()}h${(todayMin % 60).toString().padLeft(2, '0')}';

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  // Ouvre le sheet de l'activité : l'user voit ses stats
                                  // et choisit chrono libre OU minuteur avant de lancer.
                                  await _openActivitySheet(a);
                                  if (mounted) setState(() {});
                                },
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                  decoration: BoxDecoration(
                                    color: isRunning
                                        ? cs.errorContainer.withOpacity(.15)
                                        : cs.surfaceContainerHighest.withOpacity(.4),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isRunning
                                          ? cs.error.withOpacity(.3)
                                          : dColor.withOpacity(.2),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10, height: 10,
                                        decoration: BoxDecoration(
                                          color: isRunning ? cs.error : dColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          a.name,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: isRunning ? cs.error : cs.onSurface,
                                          ),
                                        ),
                                      ),
                                      if (timeStr != null) ...[
                                        Text(timeStr,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: cs.onSurface.withOpacity(.45))),
                                        const SizedBox(width: 8),
                                      ],
                                      Icon(
                                        isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                        size: 22,
                                        color: isRunning ? cs.error : dColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _askText(BuildContext ctx, String title, {String? initial}) async {
    final ctrl = TextEditingController(text: initial);
    if (initial != null) ctrl.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
    return await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
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

  bool _shouldShowFab() {
    return _tab == _Tab.dashboard || _tab == _Tab.maintenant;
  }

  Widget _buildFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
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
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'fab_now_routine',
          mini: true,
          tooltip: 'Lancer une routine',
          onPressed: () => _showRoutinesSheet(context),
          child: const Icon(Icons.repeat_rounded),
        ),
        const SizedBox(height: 12),
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
    if (linked == null || minutes <= 0) return;
    logic.start(linked.id);
    _startCountdown(minutes, linked.name, routineId: r.id);
    setState(() => _tab = _Tab.maintenant);
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
                  _tab = _Tab.maintenant;
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
  Future<void> _showRoutineActions(BuildContext sheetCtx, Activity r,
      DateTime todayD, void Function(VoidCallback) setS) async {
    final linkedId = (r.linkedActivityId ?? '').trim();
    final linked = linkedId.isEmpty
        ? null
        : logic.state.activities.firstWhereOrNull((a) => a.id == linkedId);
    final canTimer = linked != null && (r.timerMin ?? 0) > 0;
    await showModalBottomSheet<void>(
      context: sheetCtx,
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
            if (canTimer)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text('Démarrer le minuteur (${r.timerMin} min)'),
                subtitle: Text('Sur « ${linked.name} »'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pop(sheetCtx); // ferme aussi le lanceur
                  _startRoutineTimer(r);
                },
              ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Marquer comme fait'),
              onTap: () {
                logic.incHabit(r.id, 1, todayD);
                _saveAndRefresh();
                Navigator.pop(ctx);
                setS(() {});
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Réglages'),
              onTap: () {
                Navigator.pop(ctx);
                showRoutineSheet(
                  sheetCtx,
                  logic: logic,
                  habitId: r.id,
                  day: todayD,
                  onSaved: () => setS(() {}),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Pastille de fréquence affichée sur chaque carte de routine.
  Widget _freqPill(HabitFreq f, ColorScheme cs) {
    final label = switch (f) {
      HabitFreq.daily => 'Quotidien',
      HabitFreq.weekly => 'Hebdo',
      HabitFreq.monthly => 'Mensuel',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(.55))),
    );
  }

  /// Contrôles de lancement d'une routine dans le lanceur (FAB) :
  /// ▶ chrono (si activité liée) et ⏱ minuteur (si minuteur réglé).
  /// Sans activité liée, retombe sur la pastille de fréquence.
  Widget _routineLaunchControl(
      BuildContext sheetCtx, Activity r, ColorScheme cs, Color? dColor) {
    final linkedId = (r.linkedActivityId ?? '').trim();
    final linked = linkedId.isEmpty
        ? null
        : logic.state.activities.firstWhereOrNull((a) => a.id == linkedId);
    if (linked == null) {
      return _freqPill(logic.effectiveHabitFreq(r), cs);
    }
    final accent = dColor ?? cs.primary;
    final hasTimer = (r.timerMin ?? 0) > 0;

    Widget btn(IconData icon, String tooltip, VoidCallback onTap) {
      return Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withOpacity(.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Lancement temps (chrono libre sur l'activité liée)
        btn(Icons.play_arrow_rounded, 'Démarrer le chrono sur « ${linked.name} »',
            () {
          logic.start(linked.id);
          logic.rev.value++;
          Navigator.pop(sheetCtx); // ferme le lanceur
          setState(() => _tab = _Tab.maintenant);
        }),
        // Lancement minuteur (si réglé)
        if (hasTimer)
          btn(Icons.timer_outlined, 'Démarrer le minuteur (${r.timerMin} min)',
              () {
            Navigator.pop(sheetCtx); // ferme le lanceur
            _startRoutineTimer(r);
          }),
      ],
    );
  }

  void _showRoutinesSheet(BuildContext context) {
    final today = DateTime.now();
    final todayD = DateTime(today.year, today.month, today.day);

    final domainById = {for (final d in logic.state.activeDomains) d.id: d};
    final domainOrder = logic.state.activeDomains.map((d) => d.id).toList()
      ..add(''); // domaines orphelins en dernier
    // Toujours afficher toutes les routines (pas de pré-filtre sur le domaine de
    // l'activité en cours) → en-têtes de domaine toujours visibles.
    const showDomainHeaders = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            final cs = Theme.of(ctx).colorScheme;
            // Recalculé à chaque rebuild (setS) pour refléter les suppressions.
            final allRoutines = logic.state.activities
                .where((a) => a.isHabit && !a.deleted)
                .toList()
              ..sort((a, b) => a.order.compareTo(b.order));
            final routines = allRoutines;
            // Tri par domaine (comme le lanceur d'activité) : en-têtes + cartes.
            final Map<String, List<Activity>> byDomain = {};
            for (final r in routines) {
              (byDomain[r.domainId] ??= []).add(r);
            }
            // Liste à plat : String = en-tête de domaine, Activity = routine.
            final List<Object> rows = [];
            for (final domId in domainOrder) {
              final list = byDomain[domId];
              if (list == null) continue;
              if (showDomainHeaders) {
                rows.add(domainById[domId]?.name ?? 'Sans domaine');
              }
              rows.addAll(list);
            }
            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              maxChildSize: 0.92,
              minChildSize: 0.3,
              expand: false,
              builder: (_, scroll) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.repeat_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: const Text(
                            'Lancer une routine',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: Theme.of(ctx).colorScheme.primary,
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Nouvelle',
                              style: TextStyle(fontSize: 13)),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _createRoutineFromNow(context);
                            if (!mounted) return;
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant.withOpacity(.3)),
                  if (routines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Aucune routine configurée.',
                        style: TextStyle(
                            color: cs.onSurface.withOpacity(.4),
                            fontStyle: FontStyle.italic),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: rows.length,
                        itemBuilder: (ctx, i) {
                          final row = rows[i];
                          if (row is String) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                              child: Text(
                                row,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: cs.onSurface.withOpacity(.45),
                                ),
                              ),
                            );
                          }
                          final r = row as Activity;
                          // Compteur DE PÉRIODE (jour/semaine/mois) — pas juste
                          // aujourd'hui (sinon une routine hebdo affiche 0/4 même
                          // si on l'a faite 2× cette semaine). Le − reste lié au jour.
                          final todayValue = logic.habitValueOn(r.id, todayD);
                          final period = logic.habitPeriod(r);
                          final value = period.done;
                          final target = period.target;
                          final isDone = value >= target;
                          final dColor = domainColor(r.domainId,
                              logic.state.activeDomains);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () =>
                                  _showRoutineActions(ctx, r, todayD, setS),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                decoration: BoxDecoration(
                                  color: isDone
                                      ? (dColor ?? cs.primary).withOpacity(.08)
                                      : cs.surfaceContainerHighest.withOpacity(.4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDone
                                        ? (dColor ?? cs.primary).withOpacity(.25)
                                        : cs.outlineVariant.withOpacity(.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Dot domaine
                                    if (dColor != null) ...[
                                      Container(
                                        width: 8, height: 8,
                                        decoration: BoxDecoration(
                                            color: dColor,
                                            shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    // Nom + série (sur deux lignes si streak > 0)
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            r.name,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: isDone
                                                  ? cs.onSurface.withOpacity(.45)
                                                  : cs.onSurface,
                                              decoration: isDone
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                          _buildStreakBadge(
                                              logic.habitCurrentStreak(r.id)),
                                        ],
                                      ),
                                    ),
                                    // Lancement temps / minuteur (selon réglage),
                                    // sinon pastille de fréquence
                                    _routineLaunchControl(
                                        ctx, r, cs, dColor),
                                    const SizedBox(width: 6),
                                    // Étoile : planifier la routine dans Aujourd'hui
                                    // (ON → heure+durée → bloc routine ; OFF → retire).
                                    GestureDetector(
                                      onTap: () async {
                                        final changed =
                                            await toggleRoutineTodayAndSchedule(
                                                ctx, _sync, logic, r);
                                        if (!changed) return;
                                        setS(() {});
                                        setState(() {});
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: Icon(
                                          r.todayFlag
                                              ? Icons.star_rounded
                                              : Icons.star_outline_rounded,
                                          size: 18,
                                          color: r.todayFlag
                                              ? Colors.amber.shade600
                                              : cs.onSurface.withOpacity(.25),
                                        ),
                                      ),
                                    ),
                                    // Score + incrément
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          target == 1
                                              ? (isDone ? '✓' : '○')
                                              : '$value/$target',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: isDone
                                                ? (dColor ?? cs.primary)
                                                : cs.onSurface.withOpacity(.4),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (todayValue > 0)
                                          GestureDetector(
                                            onTap: () {
                                              logic.incHabitWithAssocEvent(
                                                  r.id, -1, todayD);
                                              logic.onChange();
                                              setS(() {});
                                              setState(() {});
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: cs.onSurface
                                                    .withOpacity(.08),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(Icons.remove,
                                                  size: 16,
                                                  color: cs.onSurface
                                                      .withOpacity(.4)),
                                            ),
                                          ),
                                        const SizedBox(width: 6),
                                        GestureDetector(
                                          onTap: () {
                                            logic.incHabitWithAssocEvent(
                                                r.id, 1, todayD);
                                            logic.onChange();
                                            setS(() {});
                                            setState(() {});
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: (dColor ?? cs.primary)
                                                  .withOpacity(.12),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(Icons.add,
                                                size: 16,
                                                color: dColor ?? cs.primary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
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

    final filtersOn = logic.state.filters.isActive;

    void _openFullStats(BuildContext ctx) {
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) => StatsView(
            logic: logic,
            state: _state!,
            selectedDomainId: null,
            scrollController: controller,
            sync: _sync,
            onDataChanged: () {
              Navigator.pop(ctx);
              _init();
            },
          ),
        ),
      );
    }

    // Détail complet du score (jour + niveau + semaine + paliers), affiché
    // directement (inline) dans l'onglet Score du hub. `refresh` rebuild le
    // sous-arbre quand l'objectif hebdomadaire change.
    List<Widget> _scoreDetailChildren(
        BuildContext ctx, StateSetter refresh, int done, int total) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // Sous-actions Gantt cochées aujourd'hui (via doneAt)
      final ganttDoneToday = _dashboardProjects
          .where((p) => p.status != 'archived' && p.status != 'done')
          .expand((p) => p.tasks)
          .expand((t) => t.actions)
          .where((a) =>
              a.done &&
              a.doneAt != null &&
              !a.doneAt!.isBefore(todayStart) &&
              a.doneAt!.isBefore(todayEnd))
          .length;

      final routineSummary = logic.routineProgressSummaryForCurrentPeriod();
      // Total tâches Gantt + sous-actions projet validées (même base que les badges)
      final totalHistoricalDone = _ganttActionCount();
      final pct = total == 0 ? 0 : (done / total * 100).round();
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final ringColor = pct >= 100
          ? cs.primary
          : Color.lerp(cs.error, cs.primary, (pct / 100).clamp(0.0, 1.0))!;

      return [
                  Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          value: total == 0 ? 0 : done / total,
                          strokeWidth: 5,
                          backgroundColor: cs.onSurface.withValues(alpha: .12),
                          color: ringColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$pct%',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: pct >= 100 ? cs.primary : null,
                            ),
                          ),
                          Text(
                            "Journée d'aujourd'hui",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: .6),
                            ),
                          ),
                        ],
                      ),
                      if (pct >= 100) ...[
                        const Spacer(),
                        const Text('🎉', style: TextStyle(fontSize: 32)),
                      ],
                    ],
                  ),
                  // Section niveau global
                  Builder(builder: (ctx) {
                    final lv = logic.userLevelData();
                    // Prestige Élite I/II… : il y a toujours un palier suivant.
                    final progress = (lv.xp - lv.xpCurrent) /
                        (lv.xpNext - lv.xpCurrent).clamp(1, 99999);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 24),
                        GestureDetector(
                          onTap: () => showDialog(
                            context: ctx,
                            builder: (_) => AlertDialog(
                              title: const Text('Comment marche l\'or ?'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('💰  Gagner de l\'or',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '🔁  Routine validée : +${GoldEconomy.routineMet} or/jour '
                                      '(+1 tous les ${GoldEconomy.routineStreakBonusStep} jours de série, '
                                      'jusqu\'à +${GoldEconomy.routineStreakBonusCap} → '
                                      'max ${GoldEconomy.routineMet + GoldEconomy.routineStreakBonusCap}/jour)\n'
                                      '⏱️  Temps loggué : +${GoldEconomy.timePerHour} or / heure\n'
                                      '✅  Action de projet cochée : +${GoldEconomy.ganttAction} or\n'
                                      '🏆  Défi relevé : +${GoldEconomy.challengeDone} or\n'
                                      '✨  Multiplicateur ×2 (boutique) : double tes gains du jour',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('💸  Perdre de l\'or',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '🔁  Routine lancée puis manquée : −${GoldEconomy.routineMissed} or/jour\n'
                                      '⏰  Tâche en retard : −${GoldEconomy.lateTaskPerDay} or/jour par tâche\n'
                                      '⏳  Repousser une échéance : −${GoldEconomy.deadlinePush} or\n'
                                      '🗑️  Supprimer : action −${GoldEconomy.deleteAction}, '
                                      'routine −${GoldEconomy.deleteRoutine}, '
                                      'tâche/projet selon le contenu',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '🏅  L\'or sert à révéler tes niveaux et à acheter '
                                      'des protections en boutique. Ton niveau, lui, ne '
                                      'descend jamais : l\'or gagné à vie est conservé.',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color:
                                              cs.onSurface.withValues(alpha: .7)),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(_),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          ),
                          child: Row(
                          children: [
                            Text(
                              '🏅',
                              style: const TextStyle(fontSize: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Niveau ${lv.level}',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        lv.title,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: cs.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.info_outline,
                                          size: 14,
                                          color: cs.onSurface.withValues(alpha: .35)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: progress.clamp(0.0, 1.0),
                                      minHeight: 6,
                                      backgroundColor:
                                          cs.onSurface.withValues(alpha: .10),
                                      color: cs.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${lv.xp} / ${lv.xpNext} XP',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurface.withValues(alpha: .5),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Or du jour + courbe 7 jours
                                  Builder(builder: (_) {
                                    final now = DateTime.now();
                                    final today = logic.provisionalGoldToday();
                                    final vals = List.generate(
                                        7,
                                        (i) => logic.goldGainForDay(now
                                            .subtract(Duration(days: 6 - i))));
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text("Aujourd'hui : +$today XP",
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: cs.primary)),
                                        const SizedBox(height: 6),
                                        SizedBox(
                                          height: 34,
                                          width: double.infinity,
                                          child: CustomPaint(
                                            painter: _GoldSparkline(
                                              values: vals,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                        ),
                        if (logic.levelRevealInfo().pending) ...[
                          const SizedBox(height: 12),
                          Builder(builder: (_) {
                            final rv = logic.levelRevealInfo();
                            return SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFD4A017)),
                                icon: const Text('🎁',
                                    style: TextStyle(fontSize: 14)),
                                label: Text(
                                    'Explorer la carte du niveau ${rv.nextLevel}'),
                                onPressed: () async {
                                  // Déjà entré dans le donjon → on y retourne
                                  // direct ; sinon overworld (trouver le château).
                                  if (logic.donjonAlreadyEntered) {
                                    final goOverworld = await showExpeditionSheet(ctx, logic, _sync);
                                    if (goOverworld && ctx.mounted) {
                                      await showExpeditionGame(ctx, logic, _sync);
                                    }
                                  } else {
                                    await showExpeditionGame(ctx, logic, _sync);
                                  }
                                  refresh(() {});
                                },
                              ),
                            );
                          }),
                        ],
                      ],
                    );
                  }),

                  // Section score hebdomadaire
                  Builder(builder: (ctx) {
                    final w = logic.weeklyScoreData();
                    final weekPct = (w.current * 100).round();
                    final prevPct = (w.previous * 100).round();
                    final bars = w.days7
                        .map((v) => v < 0 ? 0.0 : v.clamp(0.0, 1.0))
                        .toList();
                    final trend = w.previous > 0
                        ? w.current - w.previous
                        : null;
                    final target = logic.state.weeklyScoreTarget;
                    final onTrack = weekPct >= target;
                    final close = weekPct >= (target * 0.85).round();
                    final statusEmoji = onTrack ? '🟢' : (close ? '🟡' : '🔴');
                    final statusLabel = onTrack
                        ? 'Objectif atteint !'
                        : close
                            ? 'En route'
                            : 'En retard';

                    Future<void> pickTarget() async {
                      const presets = [60, 70, 75, 80, 90, 100];
                      final picked = await showDialog<int>(
                        context: ctx,
                        builder: (d) => SimpleDialog(
                          title: const Text('Objectif hebdomadaire'),
                          children: presets
                              .map((p) => SimpleDialogOption(
                                    onPressed: () => Navigator.pop(d, p),
                                    child: Text(
                                      '$p%',
                                      style: TextStyle(
                                        fontWeight: p == target
                                            ? FontWeight.w800
                                            : FontWeight.w400,
                                        color: p == target ? cs.primary : null,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      );
                      if (picked == null) return;
                      logic.state.weeklyScoreTarget = picked;
                      logic.onChange();
                      refresh(() {});
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Semaine',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface.withValues(alpha: .5),
                                  ),
                                ),
                                Text(
                                  '$weekPct%',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TinyRatioBars(values: bars, height: 32),
                              ),
                            ),
                            if (w.previous > 0) ...[
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Sem. passée',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurface.withValues(alpha: .5),
                                    ),
                                  ),
                                  Text(
                                    '$prevPct%',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13),
                                  ),
                                  if (trend != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          trend >= 0
                                              ? Icons.trending_up
                                              : Icons.trending_down,
                                          size: 14,
                                          color: trend >= 0
                                              ? Colors.green
                                              : cs.error,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${trend >= 0 ? '+' : ''}${(trend * 100).round()}%',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: trend >= 0
                                                ? Colors.green
                                                : cs.error,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Objectif hebdomadaire
                        GestureDetector(
                          onTap: pickTarget,
                          child: Row(
                            children: [
                              Text(
                                '$statusEmoji  Objectif $target%',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withValues(alpha: .7),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '· $statusLabel',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: onTrack
                                      ? Colors.green
                                      : close
                                          ? Colors.orange
                                          : cs.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Icon(Icons.edit,
                                  size: 14,
                                  color: cs.onSurface.withValues(alpha: .3)),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),

                  const SizedBox(height: 24),
                  if (ganttDoneToday > 0)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_tree_outlined),
                      title: const Text('Actions Gantt · aujourd\'hui'),
                      trailing: Text(
                        '$ganttDoneToday cochée${ganttDoneToday > 1 ? 's' : ''}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.emoji_events_rounded),
                    title: const Text('Routines'),
                    trailing: Text(
                      '${routineSummary.reached} / ${routineSummary.total}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Divider(height: 24),
                  Text(
                    'Paliers',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withValues(alpha: .5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // --- Actions ---
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      MapEntry(10, BadgeId.actions10),
                      MapEntry(50, BadgeId.actions50),
                      MapEntry(100, BadgeId.actions100),
                    ].map<Widget>((e) {
                      final threshold = e.key;
                      final id = e.value;
                      final isEarned = logic.state.earnedBadges
                          .any((b) => b.id == id);
                      final meta = badgeMeta(id);
                      if (isEarned) {
                        return Chip(
                          backgroundColor: cs.primaryContainer,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          label: Text(
                            '${meta.emoji} ${meta.label}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        );
                      }
                      final progress =
                          totalHistoricalDone.clamp(0, threshold);
                      return Chip(
                        backgroundColor:
                            cs.surfaceContainerHighest.withValues(alpha: .35),
                        side: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: .4)),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        label: Text(
                          '${meta.emoji} $progress / $threshold',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: .45),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  // --- Score ---
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      BadgeId.scoreFirst100,
                      BadgeId.score7dAt80,
                      BadgeId.score30dAt80,
                    ].map<Widget>((id) {
                      final isEarned = logic.state.earnedBadges
                          .any((b) => b.id == id);
                      final meta = badgeMeta(id);
                      if (isEarned) {
                        return Chip(
                          backgroundColor: cs.primaryContainer,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          label: Text(
                            '${meta.emoji} ${meta.label}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        );
                      }
                      // Progression : pour scoreFirst100, montrer le % du jour
                      final hint = id == BadgeId.scoreFirst100
                          ? '$pct / 100%'
                          : meta.label;
                      return Chip(
                        backgroundColor:
                            cs.surfaceContainerHighest.withValues(alpha: .35),
                        side: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: .4)),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        label: Text(
                          '${meta.emoji} $hint',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: .45),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
      ];
    }

    // Onglet « Score » du hub : le détail complet du score est affiché
    // directement (plus de bouton « voir le détail »).
    Widget _scoreHubTab(BuildContext ctx, int done, int total) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          // Détail complet affiché directement (le bouton « voir le détail »
          // est supprimé). StatefulBuilder = refresh local pour l'objectif hebdo.
          StatefulBuilder(
            builder: (ctx, refresh) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _scoreDetailChildren(ctx, refresh, done, total),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.bar_chart_outlined, size: 18),
            label: const Text('Statistiques complètes'),
            onPressed: () => _openFullStats(ctx),
          ),
        ],
      );
    }

    /// Lance une routine depuis « Mon or » : ferme le hub, démarre le chrono ou
    /// le minuteur (5 min par défaut si la routine n'a pas de durée), bascule sur
    /// l'onglet Maintenant. Nécessite une activité liée (pour logger le temps).
    void _launchRoutineFromGold(BuildContext context, Activity r,
        {required bool timer}) {
      final linkedId = (r.linkedActivityId ?? '').trim();
      final linked = linkedId.isEmpty
          ? null
          : logic.state.activities.firstWhereOrNull((a) => a.id == linkedId);
      if (linked == null) return;
      Navigator.of(context, rootNavigator: true).pop(); // ferme le hub
      logic.start(linked.id);
      if (timer) {
        final mins = (r.timerMin ?? 0) > 0 ? r.timerMin! : 5; // défaut 5 min
        _startCountdown(mins, linked.name, routineId: r.id);
      } else {
        logic.rev.value++;
      }
      setState(() => _tab = _Tab.maintenant);
    }

    void _openGamificationHub(BuildContext context) {
      final routineSummary = logic.routineProgressSummaryForCurrentPeriod();
      final done = routineSummary.reached;
      final total = routineSummary.total;
      showGamificationHub(context, logic, _sync,
          scoreTab: (ctx) => _scoreHubTab(ctx, done, total),
          onLaunchRoutine: (r, {required bool timer}) =>
              _launchRoutineFromGold(context, r, timer: timer));
    }

    // Indicateur composite : ⭐ gains du jour · anneau de score (sans %) · pièce d'or net
    // projeté ce soir. Tap → hub gamification (Mon or / Score / Classement / Défis).
    Widget _buildGamificationIndicator(BuildContext context) {
      final cs = Theme.of(context).colorScheme;
      final now = DateTime.now();
      final ymd = yyyymmdd(now);
      final score = logic.dailyScore(ymd).clamp(0.0, 1.0);
      final gainToday = logic.provisionalGoldToday();
      final solde = logic.gold; // solde réel (= « Mon or »), pas le net projeté
      final ringColor = score >= 1.0
          ? const Color(0xFF1D9E75)
          : Color.lerp(cs.error, cs.primary, score)!;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openGamificationHub(context),
            borderRadius: BorderRadius.circular(999),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(999),
                border:
                    Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (logic.dailyChestClaimable()) ...[
                    const Text('🎁', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                  ],
                  Text('⭐ +$gainToday',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1D9E75))),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      value: score,
                      strokeWidth: 2.5,
                      backgroundColor: cs.onSurface.withValues(alpha: .15),
                      color: ringColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const GoldIcon(size: 13),
                  const SizedBox(width: 3),
                  Text('$solde',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD4A017))),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
            const Spacer(),
            // Indicateur composite gamifié (gains du jour · score · net projeté).
            _buildGamificationIndicator(context),
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
            // Propositions à valider (déplacé ici depuis la Revue de la semaine).
            // Orion Stratège déplacé dans le menu « Plus ».
            IconButton(
              icon: const Icon(Icons.fact_check_outlined, size: 20),
              tooltip: 'Propositions à valider',
              onPressed: () => showProposalsSheet(context, _sync),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Plus',
              onSelected: (v) async {
                if (v == 'sync_status') {
                  final isPro = ProManager.isPro;
                  if (!isPro) {
                    final unlocked = await showPaywallSheet(context);
                    if (unlocked) setState(() {});
                  } else {
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DevConsoleScreen()));
                  }
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
          ],
        ),
      ),

// --- Dans build(...) ---

      body: Column(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: _tick,
            builder: (_, __, ___) {
              final running = logic.runningActivity();
              if (running == null) return const SizedBox.shrink();
              return RunningActivityBanner(
                state: _state,
                logic: logic,
                countdownEndsAt: _countdownEndsAt,
                onTap: () => setState(() => _tab = _Tab.maintenant),
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
        currentIndex: _tabIndex(_tab),
        onTap: (i) {
          final tapped = _tabFromIndex(i);
          _tabFadeController.forward(from: 0);
          setState(() => _tab = tapped);
        },
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Accueil'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.account_tree_outlined),
              activeIcon: Icon(Icons.account_tree),
              label: 'Projets'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.play_circle_outline),
              activeIcon: Icon(Icons.play_circle),
              label: 'Maintenant'),
          BottomNavigationBarItem(
              icon: SvgPicture.asset('assets/icons/gunshot.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                      Theme.of(context).unselectedWidgetColor,
                      BlendMode.srcIn)),
              activeIcon: SvgPicture.asset('assets/icons/gunshot.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.primary, BlendMode.srcIn)),
              label: 'Combattre'),
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
  Widget _buildStreakBadge(int streak) {
    if (streak == 0) return const SizedBox.shrink();

    final Widget icons;
    if (streak > 25) {
      icons = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 5; i++)
            Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade500),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade400,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${streak}j',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    } else {
      final stars  = streak ~/ 5;
      final flames = streak % 5;
      icons = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < stars; i++)
            Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade500),
          for (int i = 0; i < flames; i++)
            Icon(Icons.local_fire_department,
                size: 12, color: Colors.deepOrange.shade400),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: icons,
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
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
              // Siri & Raccourcis (iOS uniquement)
              if (Platform.isIOS)
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

    // Défis du donjon (du niveau visé) : ils « se déposent » ici.
    final donjonChallenges = logic.expeditionChallengeStatuses();

    final total = todayTasks.length +
        todayActivities.length +
        freeItems.length +
        donjonChallenges.length;

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
          // ── Défis du donjon ──────────────────────────────────────────────────
          for (final c in donjonChallenges)
            _buildDonjonChallengeTile(context, cs, c),
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

  /// Tuile d'un défi du donjon dans « Défis du moment » → tap ouvre le donjon.
  Widget _buildDonjonChallengeTile(
      BuildContext context,
      ColorScheme cs,
      ({String label, String type, int target, int progress, bool done}) c) {
    final color = c.done ? Colors.green.shade600 : const Color(0xFFD4A017);
    return InkWell(
      onTap: () async {
        if (logic.donjonAlreadyEntered) {
          final goOverworld = await showExpeditionSheet(context, logic, _sync);
          if (goOverworld && mounted) await showExpeditionGame(context, logic, _sync);
        } else {
          await showExpeditionGame(context, logic, _sync);
        }
        if (mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          Text(c.done ? '✅' : '🎯', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.done ? Colors.green.shade700 : null,
                        decoration:
                            c.done ? TextDecoration.lineThrough : null)),
                if (c.target > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('${c.progress}/${c.target}',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurface.withOpacity(.5))),
                  ),
              ],
            ),
          ),
          Icon(Icons.castle_outlined, size: 16, color: color),
        ]),
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

  /// Bannière compacte « Quête du jour » en tête de l'accueil → tap ouvre Mon or.
  Widget _buildQuestBanner(BuildContext context, ColorScheme cs) {
    final progress = logic.dailyQuestProgress();
    final target = logic.dailyQuestTarget;
    final claimable = logic.dailyChestClaimable();
    final claimed = logic.state.lastQuestClaimedYmd == yyyymmdd(DateTime.now());
    final streak = logic.questStreak;
    final pct = target > 0 ? (progress / target).clamp(0.0, 1.0) : 0.0;
    const dark = Color(0xFF231900); // texte quasi-noir chaud (lisible sur jaune)
    const gold = Color(0xFFD4A017);
    return Padding(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await showGoldSheet(context, logic, _sync);
          if (mounted) setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: claimable
                    ? [const Color(0xFFFFE9A8), const Color(0xFFFFD24D)]
                    : [
                        cs.surfaceContainerHighest.withOpacity(.5),
                        cs.surfaceContainerHighest.withOpacity(.3)
                      ]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: gold.withOpacity(claimable ? .7 : .3)),
          ),
          child: Row(children: [
            const Text('🎯', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Quête du jour',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: claimable ? dark : cs.onSurface)),
                      if (streak > 0) ...[
                        const SizedBox(width: 6),
                        Text('🔥$streak',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: claimable
                                    ? dark
                                    : cs.onSurface.withOpacity(.8))),
                      ],
                      const Spacer(),
                      Text('$progress/$target',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: claimable
                                  ? dark
                                  : cs.onSurface.withOpacity(.6))),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 5,
                          backgroundColor: Colors.black.withOpacity(.12),
                          color: claimable ? const Color(0xFF8A6D00) : gold),
                    ),
                  ]),
            ),
            const SizedBox(width: 10),
            Text(claimable ? '🎁' : (claimed ? '✅' : '→'),
                style: const TextStyle(fontSize: 16)),
          ]),
        ),
      ),
    );
  }

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
      builder: (context, _, __) {
        final now = DateTime.now();
        final g = _computeGlobalTimeGauges(now);
        final h = _computeGlobalHabitsGauge(now);
        final cs = Theme.of(context).colorScheme;

        return ListView(
          children: [
        SectionCard(
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
                            if (goNow == true) setState(() => _tab = _Tab.maintenant);
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
        ),
        // Camembert activités loggées aujourd'hui
        Builder(builder: (context) {
          final nowPie = DateTime.now();
          final todayStart = DateTime(nowPie.year, nowPie.month, nowPie.day);
          final byActivity = <String, double>{};
          for (final s in logic.state.sessions) {
            final start = s.startAt.isAfter(todayStart) ? s.startAt : todayStart;
            final end = s.endAt ?? nowPie;
            if (end.isBefore(todayStart)) continue;
            final minutes = end.difference(start).inSeconds / 60.0;
            if (minutes <= 0) continue;
            byActivity[s.activityId] = (byActivity[s.activityId] ?? 0) + minutes;
          }
          if (byActivity.isEmpty) return const SizedBox.shrink();
          final totalMin = byActivity.values.fold(0.0, (a, b) => a + b);
          final activities = logic.state.activeActivities;
          final entries = byActivity.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final pieCols = Theme.of(context).colorScheme;
          final sections = entries.map((e) {
            final act = activities.where((a) => a.id == e.key).firstOrNull;
            final col = domainColor(act?.domainId, logic.state.activeDomains) ?? pieCols.primary;
            final pct = e.value / totalMin;
            return PieChartSectionData(
              value: e.value,
              color: col,
              radius: 70,
              showTitle: pct > 0.08,
              title: '${(pct * 100).round()}%',
              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
            );
          }).toList();
          return SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Activités loggées aujourd\'hui',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: pieCols.onSurface)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: PieChart(PieChartData(
                      sections: sections, sectionsSpace: 2, centerSpaceRadius: 36)),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16, runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: entries.map((e) {
                    final act = activities.where((a) => a.id == e.key).firstOrNull;
                    final col = domainColor(act?.domainId, logic.state.activeDomains) ?? pieCols.primary;
                    final mins = e.value.round();
                    return Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 10, height: 10,
                          decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(
                        '${act?.name ?? '?'}  ${mins >= 60 ? '${(mins / 60).toStringAsFixed(1)}h' : '${mins}m'}',
                        style: TextStyle(fontSize: 12, color: pieCols.onSurface.withOpacity(.6)),
                      ),
                    ]);
                  }).toList(),
                ),
              ],
            ),
          );
        }),

        SectionCard(
          child: ProGate(
            featureName: 'Statistiques avancées',
            child: ProductivityStatsCard(logic: logic),
          ),
        ),
        SectionCard(
          child: ProGate(
            featureName: 'Statistiques avancées',
            child: AccueilTimeStats(logic: logic),
          ),
        ),
        SectionCard(
          child: RoutineFreqCard(
            logic: logic,
            onCreateRoutine: () async {
              await _createRoutineFromNow(context);
              setState(() {});
            },
            onEditRoutine: (activity) async {
              final res = await showHabitSettingsSheet(
                context,
                act: activity,
                applyDirectly: true,
                onSaved: () => setState(() {}),
              );
              if (res == null) return;
              logic.onChange();
              setState(() {});
            },
            onDeleteRoutine: (activity) {
              activity.deleted = true;
              logic.onChange();
              setState(() {});
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 0),
          child: Row(
            children: [
              Text(
                'Domaines',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(.4),
                  letterSpacing: .5,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                icon: const Icon(Icons.tune, size: 14),
                label: const Text('Gérer', style: TextStyle(fontSize: 12)),
                onPressed: () => _showDomainsSheet(context),
              ),
            ],
          ),
        ),
        ..._buildDomainListLive(context, now),
        _buildDayReviewButton(context),
        _buildNotificationsButton(context),
      ],
        );
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

  Widget _buildNotificationsButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.notifications_outlined, size: 18),
        label: const Text('Notifications'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          side: BorderSide(color: cs.onSurface.withOpacity(.2)),
          foregroundColor: cs.onSurface.withOpacity(.6),
        ),
        onPressed: () => _showNotificationsSheet(context),
      ),
    );
  }

  void _showNotificationsSheet(BuildContext context) {
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
                    label: 'Rappel quotidien',
                    hour: _state!.notifHour,
                    minute: _state!.notifMinute,
                    enabled: _state!.notifEnabled,
                    onToggled: (v) async {
                      setState(() => _state!.notifEnabled = v);
                      logic.onChange(); rebuild();
                      if (!v) { await NotificationService.cancelById(1); return; }
                      final count = logic.state.activities.where((a) =>
                          a.isHabit && logic.effectiveHabitFreq(a) == HabitFreq.daily).length;
                      await NotificationService.scheduleDailyReminder(
                          hour: _state!.notifHour, minute: _state!.notifMinute, routineCount: count);
                    },
                    onPicked: (picked) async {
                      setState(() { _state!.notifHour = picked.hour; _state!.notifMinute = picked.minute; });
                      logic.onChange(); rebuild();
                      final count = logic.state.activities.where((a) =>
                          a.isHabit && logic.effectiveHabitFreq(a) == HabitFreq.daily).length;
                      await NotificationService.scheduleDailyReminder(
                          hour: picked.hour, minute: picked.minute, routineCount: count);
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
                    label: 'Streak en danger',
                    hour: _state!.streakNotifHour,
                    minute: _state!.streakNotifMinute,
                    enabled: _state!.streakNotifEnabled,
                    onToggled: (v) async {
                      setState(() => _state!.streakNotifEnabled = v);
                      logic.onChange(); rebuild();
                      if (!v) { await NotificationService.cancelById(3); return; }
                      await NotificationService.scheduleStreakReminder(
                          hour: _state!.streakNotifHour, minute: _state!.streakNotifMinute,
                          routineNames: logic.streakAtRiskNames());
                    },
                    onPicked: (picked) async {
                      setState(() { _state!.streakNotifHour = picked.hour; _state!.streakNotifMinute = picked.minute; });
                      logic.onChange(); rebuild();
                      await NotificationService.scheduleStreakReminder(
                          hour: picked.hour, minute: picked.minute, routineNames: logic.streakAtRiskNames());
                    },
                  ),
                  const Divider(height: 1),
                  _notifSettingRow(ctx, cs,
                    icon: Icons.bolt_outlined,
                    label: 'Défi du jour',
                    hour: _state!.challengeNotifHour,
                    minute: _state!.challengeNotifMinute,
                    enabled: _state!.challengeNotifEnabled,
                    onToggled: (v) async {
                      setState(() => _state!.challengeNotifEnabled = v);
                      logic.onChange(); rebuild();
                      if (!v) { await NotificationService.cancelById(4); return; }
                      await NotificationService.scheduleChallengeReminder(
                          hour: _state!.challengeNotifHour, minute: _state!.challengeNotifMinute);
                    },
                    onPicked: (picked) async {
                      setState(() { _state!.challengeNotifHour = picked.hour; _state!.challengeNotifMinute = picked.minute; });
                      logic.onChange(); rebuild();
                      await NotificationService.scheduleChallengeReminder(hour: picked.hour, minute: picked.minute);
                    },
                  ),
                  const Divider(height: 1),
                  _notifSettingRow(ctx, cs,
                    icon: Icons.wb_sunny_outlined,
                    label: 'Score mi-journée',
                    hour: _state!.midDayNotifHour,
                    minute: _state!.midDayNotifMinute,
                    enabled: _state!.midDayNotifEnabled,
                    onToggled: (v) async {
                      setState(() => _state!.midDayNotifEnabled = v);
                      logic.onChange(); rebuild();
                      if (!v) { await NotificationService.cancelById(5); return; }
                      await NotificationService.scheduleMidDayScore(
                          hour: _state!.midDayNotifHour, minute: _state!.midDayNotifMinute);
                    },
                    onPicked: (picked) async {
                      setState(() { _state!.midDayNotifHour = picked.hour; _state!.midDayNotifMinute = picked.minute; });
                      logic.onChange(); rebuild();
                      await NotificationService.scheduleMidDayScore(hour: picked.hour, minute: picked.minute);
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

  Widget _buildDayReviewButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.bar_chart_rounded, size: 18),
        label: const Text('Résumé du jour'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          side: BorderSide(color: cs.primary.withOpacity(.4)),
          foregroundColor: cs.primary,
        ),
        onPressed: () => showDayReviewSheet(context, logic: logic, projects: _dashboardProjects),
      ),
    );
  }

  List<Widget> _buildDomainListLive(BuildContext context, DateTime now) {
    final cs = Theme.of(context).colorScheme;
    final today0 = DateTime(now.year, now.month, now.day);
    final tomorrow = today0.add(const Duration(days: 1));

    // Fenêtres “incluant aujourd'hui”
    final start7Inc = today0.subtract(const Duration(days: 6));
    final end7Inc = tomorrow;

    final (startCal, endCal, days) = _rangeForScope(now);

    const haloReachedThreshold = 0.99;
    final order = logic.computeDashboardDomainOrder(
      haloReachedThreshold: haloReachedThreshold,
    );
    final sortedDomains = order.sortedDomains;

    // ✅ TEMPS: maps calculées 1 seule fois par tick
    final totalsTodayAll = logic.timeTotalsByDomain(today0, now);
    final totals7All = logic.timeTotalsByDomain(start7Inc, end7Inc);

    // ✅ ROUTINES: comptage binaire "atteinte ou non" par domaine
    final routineItems = logic.routineProgressItemsForCurrentPeriod();
    final routineReachedByDomain = <String, int>{};
    final routineTotalByDomain = <String, int>{};
    for (final item in routineItems) {
      final domId = item.activity.domainId;
      routineTotalByDomain[domId] = (routineTotalByDomain[domId] ?? 0) + 1;
      if (item.isReached) {
        routineReachedByDomain[domId] = (routineReachedByDomain[domId] ?? 0) + 1;
      }
    }

    return [
        ...sortedDomains.map((d) {
          // ---- ROUTINES domain (binaire : atteinte ou non)
          final routinesReached = routineReachedByDomain[d.id] ?? 0;
          final routinesTotal = routineTotalByDomain[d.id] ?? 0;

          // ---- TIME domain
          final dailyTargetMinD = _state!.activeActivities
              .where((a) =>
                  a.domainId == d.id && a.type == 'time' && a.goalMin > 0)
              .fold<int>(0, (sum, a) => sum + a.goalMin);

          final dailyTargetHoursD = dailyTargetMinD / 60.0;

          final doneTodayHoursD = (totalsTodayAll[d.id]?.inMinutes ?? 0) / 60.0;
          final done7HoursD = (totals7All[d.id]?.inMinutes ?? 0) / 60.0;

          final target7HoursD = dailyTargetHoursD * 7.0;
          final bigProgressTime = target7HoursD > 0
              ? (done7HoursD / target7HoursD).clamp(0.0, 1.0)
              : 0.0;

          final timeLabel = _fmtHoursHM(doneTodayHoursD);

          final dColor = domainColor(d.id, _state!.activeDomains) ?? cs.primary;
          final hasTarget = dailyTargetMinD > 0;
          final hasTimeLogged = done7HoursD >= 0.017; // > 1 min sur la semaine
          final showTimeSection = hasTarget || hasTimeLogged;
          final week7Str = done7HoursD >= 0.017 ? _fmtHoursHM(done7HoursD) : '—';
          final pct7 = hasTarget
              ? '${(bigProgressTime * 100).round()}%'
              : null;

          return SectionCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Row 1 : nom + temps aujourd'hui ─────────────────────────
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final goNow = await _showDomainDetail(
                        d, startCal, endCal, days, focus: 'time');
                    if (!mounted) return;
                    if (goNow == true) setState(() => _tab = _Tab.maintenant);
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          d.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: cs.onSurface.withOpacity(.8),
                          ),
                        ),
                      ),
                      if (doneTodayHoursD >= 0.017)
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: dColor,
                          ),
                        ),
                    ],
                  ),
                ),

                if (showTimeSection || routinesTotal > 0) ...[
                  const SizedBox(height: 10),

                  // ── Row 2 : barre de progression semaine ─────────────────
                  if (hasTarget) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: bigProgressTime.clamp(0.0, 1.0),
                              minHeight: 7,
                              backgroundColor: dColor.withOpacity(.12),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                bigProgressTime >= 1.0
                                    ? Colors.green
                                    : dColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$pct7 · 7j',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withOpacity(.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  // ── Row 3 : stats footer ─────────────────────────────────
                  Row(
                    children: [
                      if (showTimeSection) ...[
                        Icon(Icons.timer_outlined,
                            size: 12, color: cs.onSurface.withOpacity(.4)),
                        const SizedBox(width: 4),
                        Text(
                          week7Str,
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(.5)),
                        ),
                      ],
                      if (routinesTotal > 0) ...[
                        if (showTimeSection) const SizedBox(width: 14),
                        GestureDetector(
                          onTap: () => _showDomainDetail(
                              d, startCal, endCal, days,
                              focus: 'habit'),
                          child: Row(
                            children: [
                              Icon(
                                routinesReached == routinesTotal
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked,
                                size: 12,
                                color: routinesReached == routinesTotal
                                    ? Colors.green
                                    : cs.onSurface.withOpacity(.35),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$routinesReached / $routinesTotal routines',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: routinesReached == routinesTotal
                                      ? Colors.green.withOpacity(.75)
                                      : cs.onSurface.withOpacity(.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          );
        }),
        const SizedBox(height: 60),
    ];
  }

  // Snap helper (gauge)
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

  Future<void> _renameActivity(Activity a) async {
    final s = await _askText(context, "Renommer l'activité", initial: a.name);
    if (s == null) return;
    final name = s.trim();
    if (name.isEmpty) return;

    setState(() {
      a.name = name;
      logic.onChange();
    });
  }

  void _openActivityBottomSheet(Activity a) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text("Renommer"),
                onTap: () {
                  Navigator.pop(context);
                  _renameActivity(a);
                },
              ),
              ListTile(
                leading: const Icon(Icons.snooze),
                title: Text(
                  logic.isActivitySnoozed(a.id, DateTime.now())
                      ? "Réafficher l'activité"
                      : "Cacher l'activité",
                ),
                onTap: () {
                  logic.toggleActivitySnooze(a.id);
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
            ],
          ),
        );
      },
    );
  }

  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  Future<bool> _openActivitySheet(Activity a) async {
    final now = DateTime.now();
    int _sheetMinutes = a.timerMin ?? 0;

    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        Future<void> hideUntil(DateTime until) async {
          logic.snoozeActivityUntil(a.id, until);
          Navigator.pop(ctx, true);
        }

        final cs = Theme.of(ctx).colorScheme;
        final domain = logic.state.activeDomains
            .firstWhereOrNull((d) => d.id == a.domainId);
        final dColor = domainColor(a.domainId, logic.state.activeDomains);

        // Stats temps
        final today = DateTime(now.year, now.month, now.day);
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        final monthStart = DateTime(now.year, now.month, 1);
        final durDay = logic.totalForRangeByActivity(a.id, today, now);
        final durWeek = logic.totalForRangeByActivity(a.id, weekStart, now);
        final durMonth = logic.totalForRangeByActivity(a.id, monthStart, now);

        String fmtDur(Duration d) {
          if (d.inMinutes == 0) return '—';
          if (d.inHours == 0) return '${d.inMinutes}min';
          final m = d.inMinutes % 60;
          return m == 0 ? '${d.inHours}h' : '${d.inHours}h${m.toString().padLeft(2, '0')}';
        }

        // Heatmap 12 semaines (1 ligne = cette activité)
        const cellSize = 12.0;
        const gap = 2.0;
        final thisMonday = today.subtract(Duration(days: today.weekday - 1));
        final startMonday = thisMonday.subtract(const Duration(days: 77));
        const weeks = 12;

        // Complétions par jour pour cette activité (sessions timer)
        final Map<String, int> countByYmd = {};
        // Sessions timer (en minutes, normalisées sur 30 min = 1 unité)
        for (final s in logic.state.sessions.where((s) => s.activityId == a.id)) {
          final sEnd = s.endAt ?? now;
          if (s.startAt.isAfter(now) || sEnd.isBefore(startMonday)) continue;
          var cursor = DateTime(s.startAt.year, s.startAt.month, s.startAt.day);
          while (!cursor.isAfter(today)) {
            final dayEnd = cursor.add(const Duration(days: 1));
            final segStart = cursor.isBefore(s.startAt) ? s.startAt : cursor;
            final segEnd = dayEnd.isAfter(sEnd) ? sEnd : dayEnd;
            final mins = segEnd.difference(segStart).inMinutes;
            if (mins > 0) {
              final ymd = '${cursor.year}${cursor.month.toString().padLeft(2, '0')}${cursor.day.toString().padLeft(2, '0')}';
              countByYmd[ymd] = (countByYmd[ymd] ?? 0) + (mins / 30).ceil();
            }
            cursor = dayEnd;
          }
        }
        // Référence = 90e percentile des jours actifs (1 unité = 30 min) : valorise
        // l'activité selon son propre standard, robuste aux pics isolés. Plus de plafond 5h.
        final referenceCount =
            percentileOf(countByYmd.values.toList(), 0.90).clamp(1.0, double.infinity);

        // Helper chips masquage
        Widget snoozeChip(String label, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.onSurface.withOpacity(.1)),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.65))),
          ),
        );

        String fmtGoal(int min) {
          if (min <= 0) return 'Pas de cible';
          if (min < 60) return '${min} min/j';
          final h = min ~/ 60;
          final m = min % 60;
          return m == 0 ? '${h}h / j' : '${h}h${m.toString().padLeft(2, '0')} / j';
        }

        final accentColor = dColor ?? cs.primary;
        final weeklyTargetMin = (logic.timeSliding(a.id, 7).targetMin);
        final weeklyTargetH = weeklyTargetMin / 60.0;
        final weekProgress = weeklyTargetH > 0
            ? (durWeek.inMinutes / 60.0 / weeklyTargetH).clamp(0.0, 1.0)
            : 0.0;

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: accentColor, shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 20)),
                            if (domain != null)
                              Text(domain.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: accentColor,
                                    fontWeight: FontWeight.w600,
                                  )),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () async {
                          final s = await _askText(ctx, 'Renommer', initial: a.name);
                          if (s == null || s.trim().isEmpty) return;
                          setState(() => a.name = s.trim());
                          logic.onChange();
                          Navigator.pop(ctx, true);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: 'Supprimer',
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: ctx,
                            builder: (dctx) => AlertDialog(
                              title: Text('Supprimer « ${a.name} » ?'),
                              content: Text(a.isHabit
                                  ? 'Cette routine sera supprimée et retirée des plans.'
                                  : 'Cette activité sera supprimée et retirée des plans.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(dctx, false),
                                    child: const Text('Annuler')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(dctx, true),
                                    child: const Text('Supprimer')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          final name = a.name;
                          logic.deleteActivityCascade(a.id);
                          if (ctx.mounted) Navigator.pop(ctx, true);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Supprimé : $name')));
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ],
                  ),
                ),

                // ── Stats hero ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Semaine — stat principale
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SEMAINE',
                                style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: cs.onSurface.withOpacity(.4),
                                )),
                            const SizedBox(height: 2),
                            Text(fmtDur(durWeek),
                                style: TextStyle(
                                  fontSize: 28, fontWeight: FontWeight.w800,
                                  color: accentColor,
                                  height: 1.0,
                                )),
                            if (weeklyTargetH > 0) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: weekProgress,
                                  minHeight: 6,
                                  backgroundColor: accentColor.withOpacity(.12),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    weekProgress >= 1.0 ? Colors.green : accentColor),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${(weekProgress * 100).round()}% de l\'objectif',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurface.withOpacity(.4)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Stats secondaires
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _miniStat('Aujourd\'hui', fmtDur(durDay), cs),
                          const SizedBox(height: 6),
                          _miniStat('Ce mois', fmtDur(durMonth), cs),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Graphe ───────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: SizedBox(
                    height: 80,
                    child: () {
                      final start = today.subtract(const Duration(days: 59));
                      final end = today.add(const Duration(days: 1));
                      final mbd = timeByDayForActivity(
                        sessions: _state!.sessions,
                        activityId: a.id,
                        start: start,
                        end: end,
                        now: now,
                      );
                      final s7 = movingAvgHoursSeries(
                          minutesByDay: mbd, today: now, windowDays: 7, points: 30);
                      final s30 = movingAvgHoursSeries(
                          minutesByDay: mbd, today: now, windowDays: 30, points: 30);
                      final goalH = (logic.timeSliding(a.id, 7).targetMin / 7.0) / 60.0;
                      return MiniAvgLineChart(
                        series7: s7,
                        series30: s30,
                        goalHoursPerDay: goalH,
                        color: dColor,
                      );
                    }(),
                  ),
                ),

                // ── Heatmap 12 semaines ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(weeks, (col) => Padding(
                              padding: const EdgeInsets.only(right: gap),
                              child: Column(
                                children: List.generate(7, (row) {
                                  final d = startMonday.add(Duration(days: col * 7 + row));
                                  if (d.isAfter(today)) {
                                    return SizedBox(height: cellSize + gap, width: cellSize);
                                  }
                                  final ymd = '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
                                  final count = countByYmd[ymd] ?? 0;
                                  final intensity = count == 0 ? 0.0 : (count / referenceCount).clamp(0.15, 1.0);
                                  final emptyColor = cs.onSurface.withOpacity(.10);
                                  final fullColor = accentColor;
                                  final color = count == 0
                                      ? emptyColor
                                      : Color.lerp(emptyColor, fullColor, intensity)!;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: gap),
                                    child: Container(
                                      width: cellSize, height: cellSize,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            )),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('12 sem.',
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600,
                              color: cs.onSurface.withOpacity(.35),
                            )),
                      ),
                    ],
                  ),
                ),

                // ── Pills durée + CTA (StatefulBuilder pour mise à jour locale) ─
                StatefulBuilder(builder: (ctx2, setLocal) {
                  Widget pill(String label, int min) => GestureDetector(
                    onTap: () {
                      setLocal(() => _sheetMinutes = min);
                      logic.setActivityTimerMin(a.id, min == 0 ? null : min);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: _sheetMinutes == min
                            ? accentColor.withOpacity(.12)
                            : cs.surfaceContainerHighest.withOpacity(.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _sheetMinutes == min
                              ? accentColor
                              : cs.onSurface.withOpacity(.12),
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _sheetMinutes == min
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: _sheetMinutes == min
                              ? accentColor
                              : cs.onSurface.withOpacity(.6),
                        ),
                      ),
                    ),
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Ligne de pills
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              pill('⏱ Libre', 0),
                              pill('5 min', 5),
                              pill('10 min', 10),
                              pill('15 min', 15),
                              pill('25 min', 25),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      // CTA principal
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: FilledButton.icon(
                          onPressed: () {
                            logic.start(a.id);
                            if (_sheetMinutes > 0) {
                              _startCountdown(_sheetMinutes, a.name);
                            }
                            Navigator.pop(ctx, true);
                            setState(() => _tab = _Tab.maintenant);
                          },
                          icon: Icon(
                            _sheetMinutes == 0
                                ? Icons.play_arrow_rounded
                                : Icons.timer_rounded,
                            size: 20,
                          ),
                          label: Text(
                            _sheetMinutes == 0
                                ? 'Lancer'
                                : 'Démarrer $_sheetMinutes min',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: accentColor,
                          ),
                        ),
                      ),
                    ],
                  );
                }),

                // ── Actions secondaires : Domaine + Cible ────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      // Changer de domaine
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final domains = logic.state.activeDomains;
                            final picked = await showModalBottomSheet<String>(
                              context: ctx,
                              showDragHandle: true,
                              builder: (_) => ListView(
                                shrinkWrap: true,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                                    child: Text('Choisir un domaine',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700, fontSize: 16)),
                                  ),
                                  for (final d in domains)
                                    ListTile(
                                      leading: CircleAvatar(
                                        radius: 8,
                                        backgroundColor:
                                            domainColor(d.id, domains) ?? cs.primary,
                                      ),
                                      title: Text(d.name),
                                      trailing: d.id == a.domainId
                                          ? Icon(Icons.check, color: cs.primary)
                                          : null,
                                      onTap: () => Navigator.pop(_, d.id),
                                    ),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            );
                            if (picked == null || picked == a.domainId) return;
                            setState(() => a.domainId = picked);
                            logic.onChange();
                            Navigator.pop(ctx, true);
                          },
                          icon: const Icon(Icons.folder_outlined, size: 14),
                          label: Text(
                            domain?.name ?? 'Domaine',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Cible quotidienne
                      StatefulBuilder(builder: (ctx2, setGoal) => Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final ctrl = TextEditingController(
                                text: a.goalMin > 0 ? '${a.goalMin}' : '');
                            final result = await showDialog<int>(
                              context: ctx,
                              builder: (d) => AlertDialog(
                                title: const Text('Cible quotidienne'),
                                content: TextField(
                                  controller: ctrl,
                                  autofocus: true,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Minutes par jour',
                                    suffixText: 'min',
                                    border: OutlineInputBorder(),
                                    helperText: 'ex : 45 pour 45 min, 90 pour 1h30',
                                  ),
                                  onSubmitted: (_) {
                                    final v = int.tryParse(ctrl.text.trim()) ?? 0;
                                    Navigator.pop(d, v.clamp(0, 720));
                                  },
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(d),
                                    child: const Text('Annuler'),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      final v = int.tryParse(ctrl.text.trim()) ?? 0;
                                      Navigator.pop(d, v.clamp(0, 720));
                                    },
                                    child: const Text('Enregistrer'),
                                  ),
                                ],
                              ),
                            );
                            if (result == null) return;
                            setGoal(() {
                              a.goalMin = result;
                              a.targetSource = 'user'; // épinglage manuel : ORION n'y touche plus
                            });
                            logic.onChange();
                          },
                          icon: const Icon(Icons.timer_outlined, size: 14),
                          label: Text(
                            fmtGoal(a.goalMin),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      )),
                    ],
                  ),
                ),

                // ── Masquer jusqu'à (chips) ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Masquer jusqu\'à',
                          style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: cs.onSurface.withOpacity(.35),
                          )),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          snoozeChip('Demain',
                              () => hideUntil(_endOfDay(now.add(const Duration(days: 1))))),
                          snoozeChip('3 jours',
                              () => hideUntil(_endOfDay(now.add(const Duration(days: 3))))),
                          snoozeChip('7 jours',
                              () => hideUntil(_endOfDay(now.add(const Duration(days: 7))))),
                          snoozeChip('Date…', () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: DateTime.now().add(const Duration(days: 1)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked == null) return;
                            await hideUntil(_endOfDay(picked));
                          }),
                          snoozeChip('↩ Annuler', () {
                            logic.clearSnooze(a.id);
                            Navigator.pop(ctx, true);
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    // Lance le minuteur si une durée a été sélectionnée
    if (changed == true && _sheetMinutes > 0) {
      _startCountdown(_sheetMinutes, a.name);
    }

    return changed == true;
  }

  Widget _miniStat(String label, String value, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10, color: cs.onSurface.withOpacity(.4))),
        const SizedBox(width: 6),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withOpacity(.75))),
      ],
    );
  }

  Future<bool?> _showDomainDetail(
    Domain? domain,
    DateTime start,
    DateTime end,
    int days, {
    String focus = 'time', // 'time' | 'habit'
  }) {
    final cs = Theme.of(context).colorScheme;

    // ----- LOCK : fige sections + ordre quand on édite (habits & time) -----
    bool _lockActive = false;
    List<String> _lockUnderIds = <String>[];
    List<String> _lockOverIds = <String>[];
    void _lockNow() => _lockActive = true;

    final Map<String, int> _ringAnimTokenByHabit = {};

    void _triggerRingAnimFor(String habitId, StateSetter setSB) {
      setSB(() {
        _lockNow();
        _ringAnimTokenByHabit[habitId] =
            (_ringAnimTokenByHabit[habitId] ?? 0) + 1; // ✅ tick d'anim
      });
    }

    Timer? _unlockTimer;

    void _unlockSoon(StateSetter setSB) {
      _unlockTimer?.cancel();
      _unlockTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setSB(() => _lockActive = false);
      });
    }

    bool hiddenExpanded = true;

    String tab = focus == 'habit' ? 'habit' : 'time';
    final scrollCtrl = ScrollController();

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (ctx) {

        return StatefulBuilder(builder: (ctx, setSB) {
          Future<void> _renameRoutineFromDashboard(
              BuildContext context, Activity a) async {
            String draft = a.name;

            final String? newName = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (ctx) {
                return SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                    ),
                    child: StatefulBuilder(
                      builder: (ctx, setLocal) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Renommer la routine",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: a.name,
                              autofocus: true,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: "Nom de la routine",
                              ),
                              onChanged: (v) => setLocal(() => draft = v),
                              onFieldSubmitted: (v) =>
                                  Navigator.pop(ctx, v.trim()),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text("Annuler"),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, draft.trim()),
                                    child: const Text("Enregistrer"),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            );

            final v = (newName ?? '').trim();
            if (v.isEmpty || v == a.name) return;
            if (!mounted) return;

            setState(() => a.name = v);
            logic.onChange(); // persist
          }

          Future<void> openHabitEditSheet({
            required BuildContext context,
            required AppLogic logic,
            required Activity habit,
            VoidCallback? onSaved, // optional: pour rafraîchir l'écran parent
          }) async {

            // État local (copié de l'activité pour édition non destructive)
            HabitFreq freq = habit.habitFreq ?? HabitFreq.monthly;
            int target = habit.habitTarget ?? 1;

            // Pour éviter la perte de focus du TextField quand on change de radio/switch
            final targetCtrl = TextEditingController(text: '$target');
            final targetNode = FocusNode();

            // petit helper pour afficher l'unité / libellé
            String unitSuffix() {
              final unit = (habit.unit ?? '').trim();
              return unit.isEmpty ? '' : ' $unit';
            }

            String freqLabel(HabitFreq f) {
              switch (f) {
                case HabitFreq.daily:
                  return 'par jour';
                case HabitFreq.weekly:
                  return 'par semaine';
                case HabitFreq.monthly:
                  return 'par mois';
              }
            }

            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (ctx) {
                return StatefulBuilder(builder: (ctx, setSB) {
                  void saveAndClose() {
                    final parsed = int.tryParse(targetCtrl.text.trim());
                    habit.manualTarget = true;
                    habit.habitFreq = freq;
                    habit.habitTarget = (parsed == null || parsed < 1) ? 1 : parsed;
                    habit.autoTune = false;

                    logic.onChange();
                    onSaved?.call();
                    Navigator.pop(ctx);
                  }

                  // Contenu
                  return SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () =>
                                _renameRoutineFromDashboard(context, habit),
                            child: Text(
                              habit.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Fréquence
                          Column(
                            children: [
                              RadioListTile<HabitFreq>(
                                title: const Text("Quotidienne"),
                                value: HabitFreq.daily,
                                groupValue: freq,
                                onChanged: (v) =>
                                    setSB(() => freq = v ?? freq),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              RadioListTile<HabitFreq>(
                                title: const Text("Hebdomadaire"),
                                value: HabitFreq.weekly,
                                groupValue: freq,
                                onChanged: (v) =>
                                    setSB(() => freq = v ?? freq),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              RadioListTile<HabitFreq>(
                                title: const Text("Mensuelle"),
                                value: HabitFreq.monthly,
                                groupValue: freq,
                                onChanged: (v) =>
                                    setSB(() => freq = v ?? freq),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Champ cible
                          TextField(
                            controller: targetCtrl,
                            focusNode: targetNode,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: "Cible ${freqLabel(freq)}",
                              helperText:
                                  "Entier ≥ 1${unitSuffix().isNotEmpty ? " (${unitSuffix().trim()})" : ""}",
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) {},
                            onTapOutside: (_) => targetNode.unfocus(),
                          ),

                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: saveAndClose,
                              child: const Text("Enregistrer"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                });
              },
            );
          }

          Future<String?> _promptText({
            required String title,
            String initial = "",
          }) async {
            final c = TextEditingController(text: initial);
            return showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(title),
                content: TextField(
                  controller: c,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.of(ctx).pop(c.text.trim()),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(null),
                    child: const Text("Annuler"),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
                    child: const Text("OK"),
                  ),
                ],
              ),
            );
          }

          Future<void> _renameRoutine(Activity act) async {
            // ✅ simple guard
            final current = act.name.trim();
            final txt = await _promptText(
              title: "Renommer la routine",
              initial: current,
            );

            final next = (txt ?? "").trim();
            if (next.isEmpty || next == current) return;

            setState(() {
              act.name = next;
            });

            logic.onChange();

            // optionnel: petit feedback
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Routine renommée"),
                  duration: Duration(milliseconds: 900),
                ),
              );
            });
          }

/*           Future<void> _openHabitManualEditor(
              Activity a, void Function(void Function()) refresh) async {
            final cs = Theme.of(context).colorScheme;

            // Etats initiaux
            bool manual = a.manualTarget;
            bool auto = a.autoTune;
            HabitFreq freq = a.habitFreq ?? HabitFreq.monthly;
            final int initialTarget = a.habitTarget ?? 1;

            final targetCtrl =
                TextEditingController(text: initialTarget.toString());

            String freqLabel(HabitFreq f) => f == HabitFreq.daily
                ? 'Jour'
                : (f == HabitFreq.weekly ? 'Semaine' : 'Mois');

            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (ctx) {
                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 8,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                    ),
                    child: StatefulBuilder(
                      builder: (ctx, setLocal) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () =>
                                  _renameRoutineFromDashboard(context, a),
                              child: Text(
                                a.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Basculer en "manuel"
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title:
                                  const Text("Définir la cible manuellement"),
                              value: manual,
                              onChanged: (v) {
                                setLocal(() {
                                  manual = v;
                                  if (manual) {
                                    auto =
                                        false; // manuel > auto (évite l'ambiguïté)
                                  }
                                });
                              },
                            ),

                            // Auto-tune (désactivé si manuel)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text("Ajustement automatique"),
                              value: auto,
                              onChanged: manual
                                  ? null // verrouillé si manuel
                                  : (v) => setLocal(() => auto = v ?? false),
                            ),

                            // Si manuel → afficher fréquence + cible
                            if (manual) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<HabitFreq>(
                                      value: freq,
                                      decoration: const InputDecoration(
                                          labelText: "Période"),
                                      items: HabitFreq.values.map((f) {
                                        return DropdownMenuItem(
                                          value: f,
                                          child: Text(freqLabel(f)),
                                        );
                                      }).toList(),
                                      onChanged: (f) =>
                                          setLocal(() => freq = f ?? freq),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 120,
                                    child: TextFormField(
                                      controller: targetCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText:
                                            "Cible / ${freqLabel(freq).toLowerCase()}",
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Ex.: 10 ${a.unit ?? ''} / ${freqLabel(freq).toLowerCase()}",
                                style: TextStyle(
                                    color: cs.onSurface.withOpacity(.7)),
                              ),
                            ],

                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text("Annuler"),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () {
                                      // Appliquer
                                      a.manualTarget = manual;
                                      a.autoTune = auto;

                                      if (manual) {
                                        final parsed = int.tryParse(
                                            targetCtrl.text.trim());
                                        final tgt =
                                            (parsed == null || parsed < 1)
                                                ? 1
                                                : parsed;
                                        a.habitFreq = freq;
                                        a.habitTarget = tgt;
                                      }

                                      // Persiste + rafraîchit la feuille & la liste appelante
                                      logic.onChange();
                                      refresh(() {});
                                      Navigator.pop(ctx);
                                    },
                                    child: const Text("Enregistrer"),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            );
          } */

          // ---------- UI helpers ----------
          Widget _sectionTitle(String text) => Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color:
                        Theme.of(context).colorScheme.onSurface.withOpacity(.6),
                  ),
                ),
              );

          Widget _wrapTile(Activity a, int i, int len, Widget child) {
            return InkWell(
              onTap: () async {
                final changed = await _openActivitySheet(a);
                if (changed) {
                  setSB(() {
                    _lockActive =
                        false; // ✅ évite que le lock garde l'ordre/sections figées
                  });
                }
              },
              child: child,
            );
          }

          // ---------- Source triée ----------
// 1) Source BRUTE (pas de filtrage "cap" ici)
          final bool isHabitsTab = (tab == 'habit');
          final String? domainId = domain?.id;

          List<Activity> base = isHabitsTab
              ? logic.state.activities
                  .where((a) =>
                      a.isHabit &&
                      !a.deleted &&
                      (domainId == null || a.domainId == domainId))
                  .toList()
              : logic.state.activities
                  .where((a) =>
                      !a.isHabit &&
                      !a.deleted &&
                      (domainId == null || a.domainId == domainId))
                  .toList();

// 2) Listes cibles

          List<Activity> visibleUnder = [];
          List<Activity> visibleOver = [];
          List<Activity> hiddenActivities = [];
          List<Activity> under = [];
          List<Activity> over = [];

          if (isHabitsTab) {
            // ---- regroupement via ta logique "primary meter" ----
            final notReached = <Activity>[];
            final reached = <Activity>[];

            for (final a in base) {
              (logic.habitReached(a) ? reached : notReached).add(a);
            }

            // tri “proche de 100% en haut”
            int cmpByExit(Activity x, Activity y) {
              double ratio(Activity a) {
                final tgt = logic.activeHabitTarget(a);
                if (tgt <= 0) return 0.0;
                final done = logic.activeHabitDone(a);
                return (done / tgt).clamp(0.0, 1.0);
              }

              return (1 - ratio(x)).compareTo(1 - ratio(y));
            }

            notReached.sort(cmpByExit);
            reached.sort(cmpByExit);

            under = notReached;
            over = reached;

            // (option) dans "Tous les domaines", on cache la section "Déjà atteint"
            final bool isGlobal = (domain == null);
            if (isGlobal) over = [];
          } else {
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

            under = base.where((a) => !reached(a)).toList();
            over = base.where((a) => reached(a)).toList();

            final now = DateTime.now();
            visibleUnder = under
                .where((a) => !logic.isActivitySnoozed(a.id, now))
                .toList();
            visibleOver =
                over.where((a) => !logic.isActivitySnoozed(a.id, now)).toList();

            hiddenActivities = [
              ...under.where((a) => logic.isActivitySnoozed(a.id, now)),
              ...over.where((a) => logic.isActivitySnoozed(a.id, now)),
            ];
          }

          if (isHabitsTab) {
            visibleUnder = under;
            visibleOver = over;
            hiddenActivities = const []; // pas de snooze pour les habitudes
          }

          // ---------- Lock d'ordre visuel pendant +/− ----------
          if (_lockActive) {
            final byId = {for (final a in base) a.id: a};
            under = _lockUnderIds
                .map((id) => byId[id])
                .whereType<Activity>()
                .toList();
            over = _lockOverIds
                .map((id) => byId[id])
                .whereType<Activity>()
                .toList();
          } else {
            _lockUnderIds = under.map((a) => a.id).toList();
            _lockOverIds = over.map((a) => a.id).toList();
          }

          // ---------- Header ----------
          final title = domain?.name ?? "Tous les domaines";
          final header = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                expandedInsets: EdgeInsets.zero,
                segments: const [
                  ButtonSegment(value: 'time', icon: Icon(Icons.access_time_rounded)),
                  ButtonSegment(value: 'habit', icon: Icon(Icons.repeat_rounded)),
                ],
                selected: {tab},
                onSelectionChanged: (s) => setSB(() => tab = s.first),
              ),
            ],
          );

          Widget _buildTimeTile(Activity a) {
            final now = DateTime.now();
            final s7 = logic.timeSliding(a.id, 7);
            final start = dayKey(now).subtract(const Duration(days: 59));
            final end = dayKey(now).add(const Duration(days: 1));
            final minutesByDay = timeByDayForActivity(
              sessions: _state!.sessions,
              activityId: a.id,
              start: start,
              end: end,
              now: now,
            );
            final goalHoursPerDay = (s7.targetMin / 7.0) / 60.0;
            final avg7 = avgHoursNow(
                minutesByDay: minutesByDay, today: now, windowDays: 7);
            final cs = Theme.of(context).colorScheme;
            final accentColor = domainColor(a.domainId, _state!.activeDomains) ?? cs.primary;

            // Bande heatmap 12 semaines (Pro uniquement)
            Widget chartWidget;
            // Graphe (Basic + Pro)
            final series7 = movingAvgHoursSeries(
                minutesByDay: minutesByDay, today: now, windowDays: 7, points: 30);
            final series30 = movingAvgHoursSeries(
                minutesByDay: minutesByDay, today: now, windowDays: 30, points: 30);
            final lineChart = MiniAvgLineChart(
              series7: series7, series30: series30,
              goalHoursPerDay: goalHoursPerDay,
              color: accentColor,
            );

            final showHeatmap = ProManager.isPro;
            if (showHeatmap) {
              // Heatmap 7×12 (Pro)
              const cellSize = 9.0;
              const gap = 1.5;
              final today = dayKey(now);
              final thisMonday = today.subtract(Duration(days: today.weekday - 1));
              final startMonday = thisMonday.subtract(const Duration(days: 77));
              final Map<String, int> countByYmd = {};
              for (final s in _state!.sessions.where((s) => s.activityId == a.id)) {
                final sEnd = s.endAt ?? now;
                if (s.startAt.isAfter(now) || sEnd.isBefore(startMonday)) continue;
                var cursor = DateTime(s.startAt.year, s.startAt.month, s.startAt.day);
                while (!cursor.isAfter(today)) {
                  final dayEnd = cursor.add(const Duration(days: 1));
                  final segStart = cursor.isBefore(s.startAt) ? s.startAt : cursor;
                  final segEnd = dayEnd.isAfter(sEnd) ? sEnd : dayEnd;
                  final mins = segEnd.difference(segStart).inMinutes;
                  if (mins > 0) {
                    final ymd = '${cursor.year}${cursor.month.toString().padLeft(2, '0')}${cursor.day.toString().padLeft(2, '0')}';
                    countByYmd[ymd] = (countByYmd[ymd] ?? 0) + (mins / 30).ceil();
                  }
                  cursor = dayEnd;
                }
              }
              final reference =
                  percentileOf(countByYmd.values.toList(), 0.90).clamp(1.0, double.infinity);
              final heatmap = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(12, (col) => Padding(
                  padding: const EdgeInsets.only(right: gap),
                  child: Column(
                    children: List.generate(7, (row) {
                      final d = startMonday.add(Duration(days: col * 7 + row));
                      if (d.isAfter(today)) {
                        return SizedBox(height: cellSize + gap, width: cellSize);
                      }
                      final ymd = '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
                      final count = countByYmd[ymd] ?? 0;
                      final intensity = count == 0 ? 0.0 : (count / reference).clamp(0.12, 1.0);
                      final emptyColor = cs.onSurface.withOpacity(.10);
                      final color = count == 0
                          ? emptyColor
                          : Color.lerp(emptyColor, accentColor, intensity)!;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: gap),
                        child: Container(
                          width: cellSize, height: cellSize,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      );
                    }),
                  ),
                )),
              );
              chartWidget = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: SizedBox(height: 34, child: lineChart)),
                  const SizedBox(width: 10),
                  heatmap,
                ],
              );
            } else {
              chartWidget = lineChart;
            }

            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: SizedBox(
                width: 82,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DigitalAvgText(
                      text: fmtHhMmFromHours(goalHoursPerDay),
                      fontSize: 13,
                      suffix: "",
                      textColor: cs.onSurface.withOpacity(0.75),
                      bgOpacity: 0.03,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    ),
                    const SizedBox(height: 2),
                    DigitalAvgText(
                      text: fmtHhMmFromHours(avg7),
                      fontSize: 11,
                      suffix: "",
                      textColor: cs.primary.withOpacity(0.95),
                      bgOpacity: 0.05,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    ),
                  ],
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: showHeatmap ? 75 : 34,
                    child: Align(alignment: Alignment.centerLeft, child: chartWidget),
                  ),
                ],
              ),
              trailing: null,
            );
          }

          String _habitSubText({
            required HabitFreq freq,
            required int dayDone,
            required int dayQuota,
            required int weekDone,
            required int weekTarget,
            required int monthDone,
            required int monthTarget,
          }) {
            switch (freq) {
              case HabitFreq.daily:
                return "Aujourd'hui : $dayDone / $dayQuota";
              case HabitFreq.weekly:
                return "7 j : $weekDone / $weekTarget";
              case HabitFreq.monthly:
                return "30 j : $monthDone / $monthTarget";
            }
          }

          Widget _dismissibleActivityTile(Activity a, Widget child) {
            final now = DateTime.now();

            return Dismissible(
              key: ValueKey("dashAct:${a.id}"),
              direction: DismissDirection.horizontal,
              background: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                color: Colors.cyanAccent.withOpacity(0.15),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_forward_rounded, color: Colors.cyanAccent),
                    SizedBox(width: 8),
                    Text("À demain"),
                  ],
                ),
              ),
              secondaryBackground: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                color: Colors.red.withOpacity(0.15),
                child: const Icon(Icons.delete, color: Colors.red),
              ),
              confirmDismiss: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  final running = logic.runningActivity();
                  if (running != null && running.id == a.id) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text("Impossible de reporter l'activité en cours"),
                      ),
                    );
                    return false;
                  }

                  logic.snoozeActivityUntil(a.id, _endOfDay(now));
                  setSB(() {});
/* 
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Reporté à demain : ${a.name}")),
                  ); */

                  return false;
                }

                if (direction == DismissDirection.endToStart) {
                  return await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text("Supprimer « ${a.name} » ?"),
                          content: Text(a.isHabit
                              ? "Cette routine sera supprimée et retirée des plans."
                              : "Cette activité sera supprimée et retirée des plans."),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("Annuler"),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("Supprimer"),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                }

                return false;
              },
              onDismissed: (direction) {
                if (direction == DismissDirection.endToStart) {
                  logic.deleteActivityCascade(a.id);
                  setSB(() {});
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Supprimé : ${a.name}")),
                  );
                }
              },
              child: child,
            );
          }

          List<double> movingAverage(List<double> values, int window) {
            if (values.isEmpty) return const [];
            if (window <= 1) return values;

            final n = values.length;
            final out = List<double>.filled(n, 0);

            for (int i = 0; i < n; i++) {
              final start = (i - window + 1) < 0 ? 0 : (i - window + 1);
              double sum = 0;
              int count = 0;
              for (int j = start; j <= i; j++) {
                sum += values[j];
                count++;
              }
              out[i] = count == 0 ? 0 : (sum / count);
            }
            return out;
          }

          Widget _buildHabitTile(Activity a) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);

            final dH = logic.habitSliding(a.id, 1);
            final freq = logic.effectiveHabitFreq(a);
            final quotaD = logic.dayQuotaFor(a);

            final series30Raw = List<double>.generate(30, (i) {
              final day = DateTime(now.year, now.month, now.day)
                  .subtract(Duration(days: 29 - i));
              return logic.habitValueOn(a.id, day).toDouble();
            });

            const smoothWindow = 7;
            final series30 = movingAverage(series30Raw, smoothWindow);

            final maxSeries =
                series30.fold<double>(0.0, (m, v) => v > m ? v : m);

            // Daily : barres relatives à la cible journalière
            // Autres : barres relatives au max de la série (toujours 100% de hauteur)
            final histMax = (freq == HabitFreq.daily)
                ? quotaD.toDouble().clamp(1.0, 9999.0)
                : maxSeries.clamp(0.01, 9999.0);

            // Ring adaptatif selon la fréquence
            final ringRatio = switch (freq) {
              HabitFreq.daily => logic.habitSliding(a.id, 7).ratio,
              HabitFreq.weekly => logic.habitSliding(a.id, 7).ratio,
              HabitFreq.monthly => logic.habitSliding(a.id, 30).ratio,
            };
            final token = _ringAnimTokenByHabit[a.id] ?? 0;

            return HabitTileFull(
              habit: a,
              logic: logic,
              domains: logic.state.activeDomains,
              ringTarget: ringRatio,
              ringToken: token,
              onRingBump: () => _triggerRingAnimFor(a.id, setSB),
              series30: series30,
              histMax: histMax,
              subText: _habitSubText(
                freq: a.habitFreq ?? HabitFreq.monthly,
                dayDone: dH.done,
                dayQuota: quotaD,
                weekDone: logic.habitSliding(a.id, 7).done,
                weekTarget: logic.weekTargetFrom(a),
                monthDone: logic.habitSliding(a.id, 30).done,
                monthTarget: logic.monthTargetFrom(a),
              ),
              onTap: () async {
                await showRoutineSheet(
                  context,
                  logic: logic,
                  habitId: a.id,
                  day: DateTime.now(),
                  onRename: (refresh) async {
                    await _renameRoutine(a);
                    refresh();
                  },
                  onSaved: () {
                    logic.onChange();
                    setSB(() {});
                  },
                );
              },
              onLongPress: () => openHabitEditSheet(
                context: context,
                logic: logic,
                habit: a,
                onSaved: () => setSB(() {}),
              ),
              onInc: () {
                logic.incHabit(a.id, 1, today);
                _unlockSoon(setSB);
                setSB(() {});
              },
              onDec: () {
                logic.incHabit(a.id, -1, today);
                _unlockSoon(setSB);
                setSB(() {});
              },
            );
          }

          final baseVisible =
              base.where((a) => !logic.isActivityHidden(a.id)).toList();

          under = [];
          over = [];

          if (isHabitsTab) {
            final notReached = <Activity>[];
            final reached = <Activity>[];

            for (final a in baseVisible) {
              (logic.habitReached(a) ? reached : notReached).add(a);
            }

            // tri “proche de 100% en haut”
            int cmpByExit(Activity x, Activity y) {
              double ratio(Activity a) {
                final tgt = logic.activeHabitTarget(a);
                if (tgt <= 0) return 0.0;
                final done = logic.activeHabitDone(a);
                return (done / tgt).clamp(0.0, 1.0);
              }

              return (1 - ratio(x)).compareTo(1 - ratio(y));
            }

            notReached.sort(cmpByExit);
            reached.sort(cmpByExit);

            under = notReached;
            over = reached;

            final bool isGlobal = (domain == null);
            if (isGlobal) over = [];
          } else {
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

            under = baseVisible.where((a) => !reached(a)).toList();
            over = baseVisible.where((a) => reached(a)).toList();
          }

          // ---------- Lock d'ordre visuel pendant +/− (2ème passe) ----------
          if (_lockActive) {
            final byId = {for (final a in baseVisible) a.id: a};
            under = _lockUnderIds
                .map((id) => byId[id])
                .whereType<Activity>()
                .toList();
            over = _lockOverIds
                .map((id) => byId[id])
                .whereType<Activity>()
                .toList();
          } else {
            _lockUnderIds = under.map((a) => a.id).toList();
            _lockOverIds = over.map((a) => a.id).toList();
          }

          // ✅ RE-CALC FINAL des sections visibles / cachées (à faire après under/over + lock)
          final nowS = DateTime.now();

          if (isHabitsTab) {
            visibleUnder = under;
            visibleOver = over;
            hiddenActivities = const [];
          } else {
            visibleUnder = under
                .where((a) => !logic.isActivitySnoozed(a.id, nowS))
                .toList();

            visibleOver = over
                .where((a) => !logic.isActivitySnoozed(a.id, nowS))
                .toList();

            hiddenActivities = [
              ...under.where((a) => logic.isActivitySnoozed(a.id, nowS)),
              ...over.where((a) => logic.isActivitySnoozed(a.id, nowS)),
            ];
          }



          // ---------- Rendu des sections ----------
          final bool isGlobalHabits = isHabitsTab && domain == null;

          // Vue "Tous les domaines" : routines regroupées par domaine
          List<Widget> _buildGlobalHabitsGrouped() {
            final widgets = <Widget>[];
            final domains = logic.state.activeDomains;
            final cs = Theme.of(context).colorScheme;

            for (final d in domains) {
              final group =
                  baseVisible.where((a) => a.domainId == d.id).toList();
              if (group.isEmpty) continue;
              final dColor = domainColor(d.id, domains) ?? cs.primary;
              widgets.add(Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                child: Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: dColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(d.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface.withOpacity(.6),
                      )),
                ]),
              ));
              for (int i = 0; i < group.length; i++) {
                final a = group[i];
                final tile = _buildHabitTile(a);
                final wrapped = _wrapTile(a, i, group.length, tile);
                widgets.add(_dismissibleActivityTile(a, wrapped));
              }
            }

            // Routines sans domaine assigné
            final noDomain = baseVisible
                .where((a) => !domains.any((d) => d.id == a.domainId))
                .toList();
            if (noDomain.isNotEmpty) {
              widgets.add(_sectionTitle("Sans domaine"));
              for (int i = 0; i < noDomain.length; i++) {
                final a = noDomain[i];
                final tile = _buildHabitTile(a);
                final wrapped = _wrapTile(a, i, noDomain.length, tile);
                widgets.add(_dismissibleActivityTile(a, wrapped));
              }
            }

            if (widgets.isEmpty) {
              widgets.add(const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text("Rien à afficher.")),
              ));
            }
            return widgets;
          }

          final list = ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.only(bottom: 16),
            children: isGlobalHabits
                ? _buildGlobalHabitsGrouped()
                : [
                    if (visibleUnder.isNotEmpty) _sectionTitle("À rattraper"),
                    ...List.generate(visibleUnder.length, (i) {
                      final a = visibleUnder[i];
                      final tile =
                          a.isHabit ? _buildHabitTile(a) : _buildTimeTile(a);
                      final wrapped =
                          _wrapTile(a, i, visibleUnder.length, tile);
                      return _dismissibleActivityTile(a, wrapped);
                    }),
                    if (visibleOver.isNotEmpty && visibleUnder.isNotEmpty)
                      const SizedBox(height: 8),
                    if (visibleOver.isNotEmpty) _sectionTitle("Déjà atteint"),
                    ...List.generate(visibleOver.length, (i) {
                      final a = visibleOver[i];
                      final tile =
                          a.isHabit ? _buildHabitTile(a) : _buildTimeTile(a);
                      final wrapped =
                          _wrapTile(a, i, visibleOver.length, tile);
                      return _dismissibleActivityTile(a, wrapped);
                    }),
                    if (hiddenActivities.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(Icons.snooze, size: 20),
                        title: Text(
                          "Cachées (${hiddenActivities.length})",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: Icon(
                          hiddenExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        onTap: () {
                          setSB(() {
                            hiddenExpanded = !hiddenExpanded;
                          });
                        },
                      ),
                      if (hiddenExpanded)
                        ...hiddenActivities.map((a) {
                          final content = ListTile(
                            title: Text(
                              a.name,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: const Text("Activité masquée"),
                            trailing: TextButton(
                              child: const Text("Afficher"),
                              onPressed: () {
                                logic.unsnoozeActivity(a.id);
                                setSB(() {});
                              },
                            ),
                            onTap: () => _openActivityBottomSheet(a),
                          );
                          return _dismissibleActivityTile(a, content);
                        }),
                    ],
                    if (under.isEmpty && over.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text("Rien à afficher.")),
                      ),
                  ],
          );

          final body = Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              children: [
                header,
                const SizedBox(height: 8),
                Expanded(child: list),
              ],
            ),
          );

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: body,
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () async {
                final isHabit = (tab == 'habit');
                await _createActivityDialog(
                    domainId: domainId, isHabit: isHabit);
                setSB(() {});
              },
              icon: Icon(tab == 'habit' ? Icons.add_task : Icons.timelapse),
              label: Text(
                  tab == 'habit' ? "Nouvelle routine" : "Nouvelle activité"),
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          );
        });
      },
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

/// Courbe d'historique d'or (7 derniers jours) : ligne lissée + dégradé sous la
/// courbe + point sur le jour courant. Échelle relative au max de la fenêtre.
class _GoldSparkline extends CustomPainter {
  final List<int> values;
  final Color color;
  const _GoldSparkline({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold(1, (a, b) => b > a ? b : a).toDouble();
    const pad = 3.0; // marge verticale pour que le point ne soit pas rogné
    final n = values.length;
    final dx = n > 1 ? size.width / (n - 1) : 0.0;
    double yFor(int v) =>
        size.height - pad - (size.height - 2 * pad) * (v / maxV);

    final pts = [
      for (int i = 0; i < n; i++) Offset(i * dx, yFor(values[i])),
    ];

    // Tracé lissé (courbe de Catmull-Rom → Bézier cubique).
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 0; i < n - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 < n ? i + 2 : n - 1];
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      line.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    // Dégradé sous la courbe.
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: .0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Point sur le jour courant.
    canvas.drawCircle(pts.last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GoldSparkline old) =>
      old.color != color || !listEquals(old.values, values);
}
