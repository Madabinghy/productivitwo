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
import 'package:productivitwo_v1/widgets/appbar_routines_summery.dart';
import 'package:productivitwo_v1/widgets/filters_sheet.dart';
import 'package:productivitwo_v1/widgets/habit_settings_sheet.dart';
import 'package:productivitwo_v1/widgets/habit_tile_full.dart';
import 'package:productivitwo_v1/widgets/ring_painter.dart';
import 'package:productivitwo_v1/widgets/today_view.dart';
import 'package:productivitwo_v1/widgets/goals_view.dart';
import 'package:productivitwo_v1/widgets/day_block_sheet.dart';
import 'package:productivitwo_v1/widgets/new_action_sheet.dart';
import 'package:productivitwo_v1/widgets/new_routine_sheet.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart';
import 'package:productivitwo_v1/widgets/weekly_view.dart';
import 'package:productivitwo_v1/widgets/day_review_sheet.dart';
import 'package:productivitwo_v1/widgets/productivity_stats_card.dart';
import 'package:productivitwo_v1/widgets/onboarding_screen.dart';
import 'package:productivitwo_v1/widgets/courses_sheet.dart';
import 'package:confetti/confetti.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/storage.dart';
import 'package:productivitwo_v1/notifications.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:productivitwo_v1/widgets/time_report_card.dart';
import 'package:productivitwo_v1/widgets/routine_freq_card.dart';
import 'package:productivitwo_v1/widgets/changelog_sheet.dart';
import 'package:productivitwo_v1/widgets/privacy_policy_screen.dart';
import 'package:productivitwo_v1/widgets/api_tokens_screen.dart';
import 'package:productivitwo_v1/web/web_app_stub.dart'
    if (dart.library.html) 'package:productivitwo_v1/web/web_app.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/dev_logger.dart';
import 'package:productivitwo_v1/pro_manager.dart';
import 'package:uuid/uuid.dart';
import 'package:productivitwo_v1/widgets/paywall_sheet.dart';
import 'package:productivitwo_v1/widgets/apple_sign_in_button.dart';
import 'package:productivitwo_v1/widgets/programmes_sheet.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum _Tab { dashboard, now, today, week }

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
                    FittedBox(
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
                      ...widget.state.activeDomains.map(
                        (d) => DropdownMenuItem<String?>(
                            value: d.id, child: Text(d.name)),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => statsDomainId = v), // v peut être null
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
                          barRods: [BarChartRodData(toY: habits[i].toDouble())],
                        ),
                      ),
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          if (habitDailyTarget > 0)
                            HorizontalLine(
                                y: habitDailyTarget.toDouble(),
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
    // Web : Firebase uniquement, pas de RevenueCat ni de notifications
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform);
      }
    } catch (e) { /* ignore */ }
    runApp(const WebApp());
    return;
  }

  // Mobile / desktop
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    await ProManager.init();
  }
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
  try {
    await NotificationService.init();
  } catch (e) {
    devLog.error('NotificationService.init FAIL', tag: 'MAIN', error: e);
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
    final runningColor = cs.primary; // ou cs.tertiary si tu veux plus vert

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface.withOpacity(0.08),
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

  const RunningActivityBanner({
    super.key,
    required this.state,
    required this.logic,
    this.onTap,
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

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 38,
        color: cs.primaryContainer.withOpacity(0.6),
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
                  color: cs.primary
                      .withOpacity(0.4 + 0.6 * _pulse.value),
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
                  color: cs.onPrimaryContainer,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _fmt(elapsed),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.onPrimaryContainer,
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
                  size: 20, color: cs.onPrimaryContainer),
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

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 84),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.green, size: 24),
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
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Last24hSessionsSheet extends StatelessWidget {
  final dynamic logic; // mets le type de ta logique si tu veux
  const _Last24hSessionsSheet({required this.logic});

  Future<void> _openEditSessionSheet(
    BuildContext context,
    dynamic logic, // ou ton type de logic si tu veux
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
      return;
    }

    final newStart = res.startAt ?? s.startAt;
    final newEnd = res.endAt;

    if (newEnd != null && !newEnd.isAfter(newStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La fin doit être après le début.")),
      );
      return;
    }

    logic.updateSession(
      s.id,
      startAt: res.startAt,
      endAt: res.endAt,
    );
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

                    return ListTile(
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
                        icon: const Icon(Icons.edit),
                        onPressed: () =>
                            _openEditSessionSheet(context, logic, s),
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
  String? _weekHighlightYmd; // jour à mettre en avant dans la vue semaine
// affiché une seule fois tant que l'app reste ouverte

  // Champs d'état pour les badges
  Map<String, int> _domainAutoDeltas =
      {}; // agrégat des deltas d'activités par domaine

  Timer? _saveDebounce;
  bool _saveQueued = false;
  bool _saving = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _wasOffline = false;

  late final ValueNotifier<int> _tick; // seconds
  late final ConfettiController _confettiController;
  late final AnimationController _tabFadeController;
  late final Animation<double> _tabFade;

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
    // Timeout global 15s sur _init() — l'app s'ouvre toujours en local si ça bloque
    _init().timeout(
      const Duration(seconds: 15),
      onTimeout: () async {
        devLog.error('_init() timeout global 15s — fallback local', tag: 'MAIN');
        if (_state == null) {
          final s = await store.loadOrInit();
          if (mounted) setState(() {
            _state = s;
            logic = AppLogic(_state!, _saveAndRefresh);
            _syncStatus = '⚠️';
          });
        }
      },
    ).catchError((e) {
      devLog.error('_init() exception non catchée', tag: 'MAIN', error: e);
    });

    // Ouvre le bon sheet quand l'utilisateur tape une notification
    NotificationService.onNotificationTap = (id) {
      final ctx = _navigatorKey.currentState?.overlay?.context;
      if (ctx == null) return;
      switch (id) {
        case 2: // Résumé du jour
          showDayReviewSheet(ctx, logic: logic);
        case 3: // Streak en danger → onglet À faire
        case 4: // Défi du jour → onglet À faire
          setState(() => _tab = _Tab.today);
        case 5: // Score mi-journée → résumé du jour
          showDayReviewSheet(ctx, logic: logic);
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
    _connectivitySub?.cancel();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (_state == null) return; // pas encore initialisé
    if (state == AppLifecycleState.resumed) {
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
    }
  }

  int normalizeToPlanActivityId() {
    final shopId = logic.shoppingActivity()?.id;
    if (shopId == null) return 0;

    var fixed = 0;
    for (final a in _state!.dayPlan) {
      if (a.kind != PlanKind.action) continue;
      if (a.toPlan != true) continue;
      if (a.activityId == null) {
        a.activityId = shopId;
        fixed++;
      }
    }
    if (fixed > 0) store.save(_state!); // ou onChange()
    return fixed;
  }

  Future<void> _init() async {
    // Sync Firestore pour tous les users (anonymes inclus) — l'UID anonyme
    // est stable dans le Keychain iOS, et Claude écrit via cet UID.
    final onMobile = !kIsWeb && !Platform.isMacOS && !Platform.isWindows && !Platform.isLinux;
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
      logic = AppLogic(_state!, _saveAndRefresh);

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

      // Migration : garantit que toutes les routines déjà dans des blocs
      // ont un DayPlanItem pour aujourd'hui (sinon blockItemsForDay ne les trouve pas).
      final todayYmd = yyyymmdd(DateTime.now());
      for (final b in _state!.blocks) {
        for (final actId in b.activityIds) {
          final a = _state!.activeActivities.firstWhereOrNull((x) => x.id == actId);
          if (a != null && a.isHabit) {
            logic.ensureHabitPlannedForDay(todayYmd, actId);
          }
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

    // Affiche l'onboarding pour les nouveaux utilisateurs
    if (!_state!.onboardingDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => OnboardingScreen(
            logic: logic,
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

    // ✅ ICI (point unique au démarrage)
    logic.rolloverUndoneOncePerDay();
    logic.ensureDailyHabitsPlanned();
    normalizeToPlanActivityId();

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

      // Injecte les actions récurrentes pour aujourd'hui + 7 prochains jours
      final now2 = DateTime.now();
      for (int i = 0; i < 8; i++) {
        final d = now2.add(Duration(days: i));
        logic.ensureRecurringActionsForDay(
          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}',
        );
      }
    }());

    // ... le reste inchangé
    final changes = await logic.reviewGoals();

    if (mounted) {
      setState(() {
        _domainAutoDeltas = {};
        for (final ch in changes.where((c) => c.kind == 'activity')) {
          final act = _state!.activeActivities.firstWhere((a) => a.id == ch.id,
              orElse: () =>
                  Activity(domainId: '', name: 'deleted', habitTarget: 1));
          final dom = _state!.activeDomains.firstWhere((d) => d.id == act.domainId,
              orElse: () => Domain(name: 'deleted'));
          if (dom.autoGoal) {
            _domainAutoDeltas[dom.id] =
                (_domainAutoDeltas[dom.id] ?? 0) + ch.deltaMin;
          }
        }
      });

      // Gestion "app terminée lancée depuis une notification" — appelé ici
      // car logic est maintenant initialisé.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) NotificationService.handleLaunchNotification();
      });

      Future.delayed(const Duration(minutes: 10), () {
        if (!mounted) return;
        setState(() {
          _domainAutoDeltas = {};
        });
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

  Future<void> _saveAndRefresh() async {
    if (_state == null) return;

    // Vérification badges + célébration (pas après une suppression)
    final skipBadge = logic.skipBadgeCheck;
    logic.skipBadgeCheck = false;
    final newBadges = skipBadge ? <EarnedBadge>[] : logic.checkAndAwardBadges();
    if (newBadges.isNotEmpty && mounted) {
      final meta = badgeMeta(newBadges.last.id);
      _confettiController.play();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        content: Text('${meta.emoji} Badge débloqué : ${meta.label}'),
      ));
    } else if (mounted) {
      // Célébration score 100% (même si badge déjà acquis)
      final today = yyyymmdd(DateTime.now());
      final acts = logic.state.dayPlan
          .where((it) =>
              it.yyyymmdd == today &&
              it.kind == PlanKind.action &&
              !it.archived &&
              it.toPlan != true)
          .toList();
      final actsDone = acts.where((it) => it.done).length;
      final rs = logic.routineProgressSummaryForCurrentPeriod();
      final done = actsDone + rs.reached;
      final total = acts.length + rs.total;
      if (total > 0 && done >= total) {
        _confettiController.play();
      }
    }

    // ✅ Debounce sauvegarde (regroupe les onChange rapides)
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _doSave();
    });

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
      case _Tab.dashboard:
        return 0;
      case _Tab.today:
        return 1;
      case _Tab.now:
        return 2;
      case _Tab.week:
        return 3;
    }
  }

  _Tab _tabFromIndex(int i) {
    switch (i) {
      case 0:
        return _Tab.dashboard;
      case 1:
        return _Tab.today;
      case 2:
        return _Tab.now;
      case 3:
        return _Tab.week;
      default:
        return _Tab.dashboard;
    }
  }

  bool isInbox(DayPlanItem a) {
    final noDomain = (a.domainId == null || a.domainId!.isEmpty);
    final noAct = (a.activityId == null || a.activityId!.isEmpty);
    final notCourses = a.toPlan != true;
    return noDomain && noAct && notCourses;
  }

// 2) Body : route correctement vers TodayView
  Widget _buildBody(BuildContext context) {
    final st = _state!;
    final ymd = yyyymmdd(DateTime.now());
    final sections = logic.todaySections(yyyymmdd: ymd);

    final f = logic.state.filters;
    final manualActive = f.domainIds.isNotEmpty || f.activityIds.isNotEmpty;

    final running = logic.runningActivity();
    final runningId = running?.id;

    bool isActivitySnoozedNow(String? activityId) {
      final id = (activityId ?? '').trim();
      if (id.isEmpty) return false;

      final iso = logic.state.snoozedUntil[id];
      if (iso == null || iso.isEmpty) return false;

      final until = DateTime.tryParse(iso);
      if (until == null) return false;

      return until.isAfter(DateTime.now());
    }

    bool passesEffective(DayPlanItem it) {
      final itAct = logic.effectiveActivityId(it);

      // ✅ masquer les items liés à une activité cachée
      if (isActivitySnoozedNow(itAct)) return false;

      if (manualActive) return logic.passesFilters(it);

      if (runningId != null) {
        // Items liés à l'activité en cours → toujours visibles
        if (itAct != null && itAct.isNotEmpty) return itAct == runningId;
        // Actions sans activité et sans bloc → toujours visibles dans Maintenant
        if (it.kind == PlanKind.action &&
            (logic.effectiveBlockId(it) ?? '').isEmpty) return true;
        return isInbox(it);
      }

      return true;
    }

    final filteredTodo = sections.todo.where(passesEffective).toList();

    return FadeTransition(
      opacity: _tabFade,
      child: IndexedStack(
      index: _tabIndex(_tab),
      children: [
        _buildDashboardBody(context),
        TodayView(
          logic: logic,
          state: _state!,
          isVisible: _tab == _Tab.today,
          onGoNow: (habitId) {
            logic.forceNowHabit(habitId);
            setState(() => _tab = _Tab.now);
          },
          onGoNowTab: () => setState(() => _tab = _Tab.now),
          onOpenRoutineDetail: (habitId) {
            showModalBottomSheet(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => RoutineDetailSheet(
                logic: logic,
                st: logic.state,
                habitId: habitId,
                day: DateTime.now(),
              ),
            );
          },
        ),
        NowTab(
          logic: logic,
          st: st,
          items: filteredTodo,
          day: DateTime.now(),
          buildRowsGrouped: logic.buildRowsGrouped,
          onGoTodo: () => setState(() => _tab = _Tab.today),
        ),
        WeeklyView(logic: logic, state: st, highlightYmd: _weekHighlightYmd),
      ],
      ),
    );
  }

  // ---------- UI ----------

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
                        for (final a in byDomain[domId]!)
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: domainColor(domId, logic.state.activeDomains)
                                      ?.withOpacity(.15) ??
                                  cs.surfaceContainerHighest,
                              child: Icon(
                                running?.id == a.id
                                    ? Icons.stop_rounded
                                    : Icons.play_arrow_rounded,
                                size: 18,
                                color: running?.id == a.id
                                    ? cs.error
                                    : domainColor(domId, logic.state.activeDomains) ??
                                        cs.primary,
                              ),
                            ),
                            title: Text(a.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: running?.id == a.id ? cs.error : null,
                                )),
                            onTap: () {
                              if (running?.id == a.id) {
                                logic.stopActive();
                              } else {
                                logic.start(a.id);
                                setState(() => _tab = _Tab.now);
                              }
                              setState(() {});
                              Navigator.pop(ctx);
                            },
                          ),
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

  Future<void> _createActionFromNow(BuildContext context) async {
    final result = await showNewActionSheet(context, logic: logic);
    if (result == null) return;

    await logic.addPlanAction(
      ymd: yyyymmdd(DateTime.now()),
      title: result.title,
      domainId: result.domainId,
      activityId: result.activityId,
      blockId: result.blockId,
      goalId: result.goalId,
    );

    logic.onChange();
  }

  Future<String?> _pickDomainId(BuildContext context) async {
    final domains = logic.state.activeDomains;

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  "Choisir un domaine",
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              for (final d in domains)
                ListTile(
                  title: Text(d.name),
                  onTap: () => Navigator.pop(ctx, d.id),
                ),
            ],
          ),
        );
      },
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

    final ymd = yyyymmdd(DateTime.now());
    logic.ensurePlannedOnce(ymd, PlanKind.habit, a.id, a.name,
        domainId: a.domainId);

    logic.onChange();

    if (!mounted) return;
    setState(() {});
  }

  void _openLast24hSessionsSheet(BuildContext context, dynamic logic) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Last24hSessionsSheet(logic: logic),
    );
  }

  Future<void> _loadDemoData() async {
    final st = logic.state;
    final now = DateTime.now();
    final today = yyyymmdd(now);

    // ── Domaines ──────────────────────────────────────────────────────────────
    final dSante = Domain(name: 'Santé');
    final dSport = Domain(name: 'Sport');
    final dBusiness = Domain(name: 'Business');
    st.domains.addAll([dSante, dSport, dBusiness]);

    // ── Activités ─────────────────────────────────────────────────────────────
    final aMeditation = Activity(domainId: dSante.id, name: 'Méditation', goalMin: 20, order: 0);
    final aMusculation = Activity(domainId: dSport.id, name: 'Musculation', goalMin: 60, order: 0);
    final aRunning = Activity(domainId: dSport.id, name: 'Running', goalMin: 30, order: 1);
    final aDeepWork = Activity(domainId: dBusiness.id, name: 'Deep Work', goalMin: 120, order: 0);
    st.activities.addAll([aMeditation, aMusculation, aRunning, aDeepWork]);

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
    }

    // ── Bloc + actions du jour ────────────────────────────────────────────────
    final bloc = DayBlock(name: 'Bloc matin', emoji: '🌅', order: 0);
    st.blocks.add(bloc);

    st.dayPlan.addAll([
      DayPlanItem(
        id: const Uuid().v4(), kind: PlanKind.action,
        title: 'Préparer la journée', yyyymmdd: today,
        done: true, order: 0, blockId: bloc.id, domainId: dBusiness.id,
      ),
      DayPlanItem(
        id: const Uuid().v4(), kind: PlanKind.action,
        title: 'Répondre aux emails', yyyymmdd: today,
        done: true, order: 1, blockId: bloc.id, domainId: dBusiness.id,
      ),
      DayPlanItem(
        id: const Uuid().v4(), kind: PlanKind.action,
        title: 'Travailler sur le projet principal', yyyymmdd: today,
        done: false, order: 2, blockId: bloc.id, domainId: dBusiness.id,
      ),
      DayPlanItem(
        id: const Uuid().v4(), kind: PlanKind.action,
        title: 'Revue de la journée', yyyymmdd: today,
        done: false, order: 3, blockId: bloc.id, domainId: dBusiness.id,
      ),
    ]);

    logic.onChange();
    if (mounted) setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Données de démo chargées ✓')),
      );
    }
  }

  bool _shouldShowFab() {
    return _tab == _Tab.today || _tab == _Tab.dashboard || _tab == _Tab.week;
  }

  Widget _buildFab() {
    final playFab = FloatingActionButton(
      heroTag: "fab_launch_activity",
      tooltip: "Lancer une activité",
      onPressed: () => _showLaunchActivitySheet(context),
      child: const Icon(Icons.play_arrow_rounded),
    );

    if (_tab == _Tab.now) return playFab;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton(
          heroTag: "fab_now_routine",
          mini: true,
          tooltip: "Nouvelle routine",
          onPressed: () async {
            await _createRoutineFromNow(context);
            if (!mounted) return;
            setState(() {});
          },
          child: const Icon(Icons.repeat),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: "fab_now_action",
          mini: true,
          tooltip: "Nouvelle action",
          onPressed: () async {
            await _createActionFromNow(context);
            if (!mounted) return;
            setState(() {});
          },
          child: const Icon(Icons.add),
        ),
        const SizedBox(height: 12),
        playFab,
      ],
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

    void _showRoutineProgressSheet(BuildContext context) {
      double _roughRoutineRatioAt(DateTime day) {
        final habits = logic.state.activities.where((a) => a.isHabit).toList();

        int reached = 0;
        int total = 0;

        for (final a in habits) {
          final target = logic.activeHabitTarget(a);
          if (target <= 0) continue;

          total++;

          final done = logic.habitValueOn(a.id, day);
          if (done >= target) {
            reached++;
          }
        }

        return total == 0 ? 0.0 : reached / total;
      }

      List<double> _routineCatchupRatio30d() {
        final now = DateTime.now();
        final out = <double>[];

        for (int i = 0; i < 29; i++) {
          final day = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: 29 - i));

          // logique provisoire / approximative pour les jours passés
          out.add(_roughRoutineRatioAt(day));
        }

        // dernier point = logique exacte du sheet
        final summary = logic.routineProgressSummaryForCurrentPeriod();
        out.add(summary.total == 0 ? 0.0 : summary.reached / summary.total);

        return out;
      }

      final items = logic.routineProgressItemsForCurrentPeriod();

      final under = items.where((e) => e.isCatchup).toList();
      final over = items.where((e) => e.isReached).toList();

      void _openRoutineInNowTab(Activity activity) {
        final ymd = yyyymmdd(DateTime.now());
        final sections = logic.todaySections(yyyymmdd: ymd);

        // IMPORTANT : chercher dans la source brute, sans passesEffective
        final items = sections.todo.toList();

        DayPlanItem? match;
        for (final it in items) {
          if ((it.refId ?? '') == activity.id) {
            match = it;
            break;
          }
        }

        if (match != null) {
          logic.movePlanItemToTop(ymd, match.id);
          logic.onChange();
        }

        setState(() {
          _tab = _Tab.now;
        });
      }

      final ratio30 = _routineCatchupRatio30d();

      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final cs = theme.colorScheme;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: ListView(
                shrinkWrap: true,
                children: [
                  /// ---------- Titre ----------
                  Row(
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Progression habitudes',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Text(
                    'Évolution sur 30 jours',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: .4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TinyRatioBars(values: ratio30),
                        const SizedBox(height: 8),
                        Text(
                          '${(ratio30.isNotEmpty ? ratio30.last * 100 : 0).round()}% à jour',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// ---------- À rattraper ----------
                  if (under.isNotEmpty) ...[
                    Text(
                      'À rattraper',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...under.map(
                      (e) => ListTile(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            showDragHandle: true,
                            isScrollControlled: true,
                            builder: (_) => RoutineDetailSheet(
                              logic: logic,
                              st: logic.state,
                              habitId: e.activity.id,
                              day: DateTime.now(),
                            ),
                          );
                        },
                        leading: const Icon(Icons.radio_button_unchecked),
                        title: Text(e.label),
                        subtitle: Text('${e.done} / ${e.target}'),
                        trailing: SizedBox(
                          width: 60,
                          child: LinearProgressIndicator(
                            value: e.progress,
                            minHeight: 6,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  /// ---------- Déjà atteint ----------
                  if (over.isNotEmpty) ...[
                    Text(
                      'Déjà atteint',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...over.map(
                      (e) => ListTile(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            showDragHandle: true,
                            isScrollControlled: true,
                            builder: (_) => RoutineDetailSheet(
                              logic: logic,
                              st: logic.state,
                              habitId: e.activity.id,
                              day: DateTime.now(),
                            ),
                          );
                        },
                        leading: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                        title: Text(e.label),
                        subtitle: Text('${e.done} / ${e.target}'),
                      ),
                    ),
                  ],

                  /// ---------- Cas vide ----------
                  if (under.isEmpty && over.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          "Aucune habitude active",
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }

    void _showDailyScoreSheet(BuildContext context, int done, int total) {
      final today = yyyymmdd(DateTime.now());
      final actions = logic.state.dayPlan
          .where((it) =>
              it.yyyymmdd == today &&
              it.kind == PlanKind.action &&
              !it.archived &&
              it.toPlan != true)
          .toList();
      final actionsDone = actions.where((it) => it.done).length;
      final actionsTotal = actions.length;
      final routineSummary = logic.routineProgressSummaryForCurrentPeriod();
      // Total historique actions complétées (tous les jours)
      final totalHistoricalDone = logic.state.dayPlan
          .where((it) => it.kind == PlanKind.action && it.done)
          .length;
      final pct = total == 0 ? 0 : (done / total * 100).round();

      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) {
          final theme = Theme.of(ctx);
          final cs = theme.colorScheme;
          final ringColor = pct >= 100
              ? cs.primary
              : Color.lerp(cs.error, cs.primary, (pct / 100).clamp(0.0, 1.0))!;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                    final isMax = lv.level >= 10;
                    final progress = isMax
                        ? 1.0
                        : (lv.xp - lv.xpCurrent) /
                            (lv.xpNext - lv.xpCurrent).clamp(1, 99999);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 24),
                        GestureDetector(
                          onTap: () => showDialog(
                            context: ctx,
                            builder: (_) => AlertDialog(
                              title: const Text('Comment gagner de l\'XP ?'),
                              content: const Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('🔥  Streaks de routines',
                                      style: TextStyle(fontWeight: FontWeight.w700)),
                                  SizedBox(height: 4),
                                  Text('3 jours → 10 XP\n7 jours → 25 XP\n21 jours → 75 XP\n66 jours → 200 XP\n100 jours → 500 XP',
                                      style: TextStyle(fontSize: 13)),
                                  SizedBox(height: 12),
                                  Text('✅  Actions complétées',
                                      style: TextStyle(fontWeight: FontWeight.w700)),
                                  SizedBox(height: 4),
                                  Text('10 actions → 15 XP\n50 actions → 50 XP\n100 actions → 100 XP',
                                      style: TextStyle(fontSize: 13)),
                                  SizedBox(height: 12),
                                  Text('🎯  Score journalier',
                                      style: TextStyle(fontWeight: FontWeight.w700)),
                                  SizedBox(height: 4),
                                  Text('Score parfait → 30 XP\n7 jours à 80 %+ → 50 XP\n30 jours à 80 %+ → 150 XP',
                                      style: TextStyle(fontSize: 13)),
                                ],
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
                                    isMax
                                        ? '${lv.xp} XP — niveau max !'
                                        : '${lv.xp} / ${lv.xpNext} XP',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurface.withValues(alpha: .5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        ),
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
                      setSheetState(() {});
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
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_box_outlined),
                    title: const Text('Actions'),
                    trailing: Text(
                      '$actionsDone / $actionsTotal',
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
                ],
              ),
            ),
          );
          },
        ),
      );
    }

    Widget _buildDailyScoreChip(BuildContext context) {
      final today = yyyymmdd(DateTime.now());
      final actions = logic.state.dayPlan
          .where((it) =>
              it.yyyymmdd == today &&
              it.kind == PlanKind.action &&
              !it.archived &&
              it.toPlan != true)
          .toList();
      final actionsDone = actions.where((it) => it.done).length;
      final routineSummary = logic.routineProgressSummaryForCurrentPeriod();
      final done = actionsDone + routineSummary.reached;
      final total = actions.length + routineSummary.total;
      if (total == 0) return const SizedBox.shrink();
      return DailyScoreChip(
        done: done,
        total: total,
        onTap: () => _showDailyScoreSheet(context, done, total),
      );
    }

    Widget _buildRoutineChip(BuildContext context) {
      final summary = logic.routineProgressSummaryForCurrentPeriod();
      if (summary.total == 0) return const SizedBox.shrink();
      return RoutineAppBarChip(
        summary: summary,
        trend30d: logic.habitDailyAdherenceRates(30),
        onTap: () => _showRoutineProgressSheet(context),
      );
    }

    // 2) App prête -> Scaffold complet
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
            _buildDailyScoreChip(context),
            // Indicateur sync / Pro
            ValueListenableBuilder<bool>(
              valueListenable: ProManager.notifier,
              builder: (context, isPro, _) {
                if (!isPro) {
                  return GestureDetector(
                    onTap: () async {
                      final unlocked = await showPaywallSheet(context);
                      if (unlocked) setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Tooltip(
                        message: 'Passer à Pro — sync cloud & stats avancées',
                        child: Icon(Icons.lock_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(.35)),
                      ),
                    ),
                  );
                }
                if (_syncStatus.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onLongPress: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DevConsoleScreen()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Tooltip(
                      message: _syncStatus == '☁️'
                          ? 'Sync Firestore OK\n(appui long = console dev)'
                          : 'Mode local\n(appui long = console dev)',
                      child: Text(_syncStatus, style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.menu_book_outlined),
              tooltip: 'Programmes',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => ProgrammesSheet(
                    sync: _sync,
                    domains: _state?.domains ?? [],
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Plus',
              onSelected: (v) async {
                if (v == 'stats') {
                  showModalBottomSheet(
                    context: context,
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
                          Navigator.pop(context);
                          _init();
                        },
                      ),
                    ),
                  );
                } else if (v == 'filters') {
                  _openFiltersSheet(context);
                } else if (v == 'changelog') {
                  showChangelogSheet(context);
                } else if (v == 'privacy') {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyScreen(),
                  ));
                } else if (v == 'api_tokens') {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ApiTokensScreen(sync: _sync, uid: _sync.uid ?? ''),
                  ));
                } else if (v == 'apple_account') {
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
                } else if (v == 'feedback') {
                  final uri = Uri(
                    scheme: 'mailto',
                    path: 'emeric.edmond@gmail.com',
                    queryParameters: {
                      'subject': '[Productivitwo] Suggestion',
                      'body': 'Bonjour,\n\nVoici ma suggestion :\n\n',
                    },
                  );
                  launchUrl(uri);
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
                } else if (v == 'demo_data') {
                  await _loadDemoData();
                } else if (v == 'delete_account') {
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
                    // Si connecté avec Apple : supprimer les données Firestore + déconnecter
                    if (!_sync.isAnonymous) {
                      try { await _sync.deleteAccount(); } catch (_) {}
                    }
                    await store.wipe();
                    await ProManager.deactivate();
                    exit(0);
                  }
                } else if (v == 'dev') {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const DevConsoleScreen(),
                  ));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'stats',
                  child: Row(
                    children: [
                      Icon(Icons.bar_chart_outlined, size: 18),
                      SizedBox(width: 12),
                      Text('Statistiques'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'filters',
                  child: Row(
                    children: [
                      Icon(
                        Icons.tune,
                        size: 18,
                        color: filtersOn
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Filtres',
                        style: filtersOn
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'changelog',
                  child: Row(
                    children: [
                      Icon(Icons.new_releases_outlined, size: 18),
                      SizedBox(width: 12),
                      Text('Nouveautés'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'privacy',
                  child: Row(
                    children: [
                      Icon(Icons.privacy_tip_outlined, size: 18),
                      SizedBox(width: 12),
                      Text('Confidentialité'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'api_tokens',
                  child: Row(
                    children: [
                      Icon(Icons.key_outlined, size: 18),
                      SizedBox(width: 12),
                      Text('Tokens API'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'apple_account',
                  child: Row(
                    children: [
                      Icon(Icons.apple, size: 18),
                      SizedBox(width: 12),
                      Text('Compte Apple'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'feedback',
                  child: Row(
                    children: [
                      Icon(Icons.mail_outline, size: 18),
                      SizedBox(width: 12),
                      Text('Suggérer une feature'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'catalogue',
                  child: Row(
                    children: [
                      Icon(Icons.library_add_outlined, size: 18),
                      SizedBox(width: 12),
                      Text('Parcourir le catalogue'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'demo_data',
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined, size: 18),
                      SizedBox(width: 12),
                      Text('Charger des données de démo'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete_account',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever_outlined, size: 18,
                          color: Colors.red),
                      SizedBox(width: 12),
                      Text('Supprimer mon compte',
                          style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'dev',
                  child: Row(
                    children: [
                      Icon(Icons.bug_report_outlined, size: 18),
                      SizedBox(width: 12),
                      Text('Console dev'),
                    ],
                  ),
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
                onTap: () => setState(() => _tab = _Tab.now),
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
          _tabFadeController.forward(from: 0);
          setState(() => _tab = _tabFromIndex(i));
        },
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Accueil'),
          BottomNavigationBarItem(
              icon: Icon(Icons.checklist_outlined),
              activeIcon: Icon(Icons.checklist),
              label: 'À faire'),
          BottomNavigationBarItem(
              icon: Icon(Icons.play_circle_outline),
              activeIcon: Icon(Icons.play_circle),
              label: 'Maintenant'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_view_week_outlined),
              activeIcon: Icon(Icons.calendar_view_week),
              label: 'Semaine'),
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

    final dailyTargetMinAll = _state!.activeActivities
        .where((a) => a.type == 'time' && a.goalMin > 0)
        .fold<int>(0, (sum, a) => sum + a.goalMin);

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

  ({double progress, String centerText, String subText})
      _computeGoalsGauge() {
    final goals =
        _state!.goals.where((g) => g.status == 'active').toList();
    final totalGoals = goals.length;

    if (totalGoals == 0) {
      return (progress: 0.0, centerText: '—', subText: '0 objectif');
    }

    final totalSteps =
        goals.fold<int>(0, (sum, g) => sum + g.stepsTotal);
    final doneSteps =
        goals.fold<int>(0, (sum, g) => sum + g.stepsDone);

    final progress =
        totalSteps == 0 ? 0.0 : (doneSteps / totalSteps).clamp(0.0, 1.0);
    final centerText =
        totalSteps == 0 ? '$totalGoals' : '$doneSteps/$totalSteps';
    final subText =
        '$totalGoals objectif${totalGoals > 1 ? "s" : ""}';

    return (progress: progress, centerText: centerText, subText: subText);
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
        final obj = _computeGoalsGauge();
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GaugeRing(
                        label: 'Activités',
                        progress: g.todayProgress,
                        centerText: g.centerText,
                        subText: g.subText,
                        color: _colorForProgress(g.todayProgress, context),
                        size: 150,
                        onTap: () async {
                          final goNow = await _showDomainDetail(
                              null, startCal, endCal, days,
                              focus: 'time');
                          if (!mounted) return;
                          if (goNow == true) setState(() => _tab = _Tab.now);
                        },
                      ),
                      GaugeRing(
                        label: 'Routines',
                        progress: h.outerPrimary,
                        centerText: h.centerText,
                        subText: h.subText,
                        color: _colorForProgress(h.outerPrimary, context),
                        size: 150,
                        onTap: () => _showDomainDetail(
                            null, startCal, endCal, days,
                            focus: 'habit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => setState(() => _tab = _Tab.today),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.flag_rounded,
                              size: 16,
                              color: _colorForProgress(obj.progress, context)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: obj.progress,
                                minHeight: 8,
                                backgroundColor:
                                    cs.surfaceContainerHighest,
                                color: _colorForProgress(
                                    obj.progress, context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            obj.centerText == '—'
                                ? obj.subText
                                : '${obj.centerText}  ·  ${obj.subText}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                            final monday = now.subtract(
                                Duration(days: now.weekday - 1));
                            final tappedDay = DateTime(
                              monday.year, monday.month,
                              monday.day + i,
                            );
                            setState(() {
                              _weekHighlightYmd = yyyymmdd(tappedDay);
                              _tab = _Tab.week;
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
        _buildNextGoalCard(context),
        SectionCard(
          child: ProGate(
            featureName: 'Statistiques avancées',
            child: ProductivityStatsCard(logic: logic),
          ),
        ),
        SectionCard(
          child: RoutineFreqCard(logic: logic),
        ),
        Builder(builder: (context) {
          final reserveCount = logic.state.dayPlan
              .where((a) =>
                  a.kind == PlanKind.action &&
                  a.toPlan == true &&
                  a.archived == true &&
                  !a.done)
              .length;
          final activeCount = logic.state.dayPlan
              .where((a) =>
                  a.kind == PlanKind.action &&
                  a.toPlan == true &&
                  a.archived != true &&
                  !a.done)
              .length;
          if (reserveCount == 0 && activeCount == 0) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.shopping_cart_outlined),
                title: const Text('Courses',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(activeCount > 0
                    ? '$activeCount en liste · $reserveCount en réserve'
                    : '$reserveCount article${reserveCount > 1 ? 's' : ''} en réserve'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showCoursesSheet(context, logic: logic),
              ),
            ),
          );
        }),
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
        onPressed: () => showDayReviewSheet(context, logic: logic),
      ),
    );
  }

  Widget _buildNextGoalCard(BuildContext context) {
    final activeGoals = logic.state.goals
        .where((g) => g.status == 'active' && g.nextAction != null)
        .toList();

    if (activeGoals.isEmpty) return const SizedBox.shrink();

    // Priorité : épinglé → le plus avancé en progression
    final pinned = activeGoals.where((g) => g.pinned).firstOrNull;
    final goal = pinned ??
        (activeGoals..sort((a, b) {
          final pa = a.stepsTotal > 0 ? a.stepsDone / a.stepsTotal : 0.0;
          final pb = b.stepsTotal > 0 ? b.stepsDone / b.stepsTotal : 0.0;
          return pb.compareTo(pa); // plus avancé en premier
        })).first;
    final nextAction = goal.nextAction!;
    final domain = logic.state.activeDomains
        .firstWhereOrNull((d) => d.id == goal.domainId);
    final dColor = domainColor(goal.domainId, logic.state.activeDomains);
    final progress = goal.stepsTotal > 0
        ? goal.stepsDone / goal.stepsTotal
        : 0.0;
    final cs = Theme.of(context).colorScheme;

    return SectionCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final now = DateTime.now();
          final (startCal, endCal, days) = _rangeForScope(now);
          _showDomainDetail(domain, startCal, endCal, days, focus: 'goal');
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dColor != null)
                  Container(width: 4, color: dColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            Icon(Icons.flag_rounded,
                                size: 13,
                                color: dColor ?? cs.primary),
                            const SizedBox(width: 6),
                            Text(
                              '${goal.pinned ? '📌 ' : ''}Prochain objectif${domain != null ? '  ·  ${domain.name}' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface.withOpacity(.4),
                                letterSpacing: 0.4,
                              ),
                            ),
                            const Spacer(),
                            if (goal.stepsTotal > 0)
                              Text(
                                '${goal.stepsDone}/${goal.stepsTotal}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: dColor?.withOpacity(.7) ??
                                      cs.primary.withOpacity(.7),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Titre objectif
                        Text(
                          goal.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (goal.stepsTotal > 0) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              backgroundColor:
                                  (dColor ?? cs.primary).withOpacity(.12),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  dColor ?? cs.primary),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        // Prochaine action
                        Row(
                          children: [
                            Icon(Icons.arrow_right_rounded,
                                size: 16,
                                color: cs.onSurface.withOpacity(.4)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                nextAction.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withOpacity(.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDomainListLive(BuildContext context, DateTime now) {
    final today0 = DateTime(now.year, now.month, now.day);
    final tomorrow = today0.add(const Duration(days: 1));

    // Fenêtres “incluant aujourd'hui”
    final start7Inc = today0.subtract(const Duration(days: 6));
    final end7Inc = tomorrow;

    final start90Inc = today0.subtract(const Duration(days: 89));
    final end90Inc = tomorrow;

    final (startCal, endCal, days) = _rangeForScope(now);

    const haloReachedThreshold = 0.99;
    final order = logic.computeDashboardDomainOrder(
      haloReachedThreshold: haloReachedThreshold,
    );
    final sortedDomains = order.sortedDomains;

    // ✅ TEMPS: maps calculées 1 seule fois par tick
    final totalsTodayAll = logic.timeTotalsByDomain(today0, now);
    final totals7All = logic.timeTotalsByDomain(start7Inc, end7Inc);
    final totals90All = logic.timeTotalsByDomain(start90Inc, end90Inc);

    // ✅ TOTAL 90h global (pour share)
    final done90HoursAll = totals90All.values
            .fold<Duration>(Duration.zero, (a, b) => a + b)
            .inMinutes /
        60.0;

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

    double domainShare90(String domainId) {
      if (done90HoursAll <= 0) return 0.0;
      final h = (totals90All[domainId]?.inMinutes ?? 0) / 60.0;
      return (h / done90HoursAll).clamp(0.0, 1.0);
    }

    return [
        ...sortedDomains.map((d) {
          // ---- ROUTINES domain (binaire : atteinte ou non)
          final routinesReached = routineReachedByDomain[d.id] ?? 0;
          final routinesTotal = routineTotalByDomain[d.id] ?? 0;
          final routinesProgress = routinesTotal == 0
              ? 0.0
              : (routinesReached / routinesTotal).clamp(0.0, 1.0);
          final routinesLabelD =
              routinesTotal == 0 ? '' : '$routinesReached / $routinesTotal';

          // ---- TIME domain
          final dailyTargetMinD = _state!.activeActivities
              .where((a) =>
                  a.domainId == d.id && a.type == 'time' && a.goalMin > 0)
              .fold<int>(0, (sum, a) => sum + a.goalMin);

          final dailyTargetHoursD = dailyTargetMinD / 60.0;

          final doneTodayHoursD = (totalsTodayAll[d.id]?.inMinutes ?? 0) / 60.0;
          final done7HoursD = (totals7All[d.id]?.inMinutes ?? 0) / 60.0;
          final done90HoursD = (totals90All[d.id]?.inMinutes ?? 0) / 60.0;

          final outerProgressTime = dailyTargetHoursD > 0
              ? (doneTodayHoursD / dailyTargetHoursD).clamp(0.0, 1.0)
              : 0.0;

          final target7HoursD = dailyTargetHoursD * 7.0;
          final bigProgressTime = target7HoursD > 0
              ? (done7HoursD / target7HoursD).clamp(0.0, 1.0)
              : 0.0;

          final total90HoursAbs = 90.0 * 24.0;
          final smallProgressTime =
              (done90HoursD / total90HoursAbs).clamp(0.0, 1.0);

          final share = domainShare90(d.id);
          final timeLabel = _fmtHoursHM(doneTodayHoursD);

          // ---- GOALS domain
          final domainGoals = _state!.goals
              .where((g) => g.domainId == d.id && g.status == 'active')
              .toList();
          final goalCount = domainGoals.length;
          final totalActions =
              domainGoals.fold<int>(0, (s, g) => s + g.stepsTotal);
          final doneActions =
              domainGoals.fold<int>(0, (s, g) => s + g.stepsDone);
          final goalsProgress = totalActions > 0
              ? (doneActions / totalActions).clamp(0.0, 1.0)
              : 0.0;
          final goalsLabel = goalCount == 0
              ? 'Objectifs'
              : 'Objectifs · $goalCount actif${goalCount > 1 ? 's' : ''}';

          final dColor = domainColor(d.id, _state!.activeDomains);
          return SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (dColor != null) ...[
                      Container(
                        width: 4,
                        height: 18,
                        decoration: BoxDecoration(
                          color: dColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(d.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    _buildProgressRow(
                      icon: Icons.flag_outlined,
                      label: goalsLabel,
                      progress: goalsProgress,
                      color: _colorForProgress(goalsProgress, context),
                      onTap: () => _showDomainDetail(
                          d, startCal, endCal, days,
                          focus: 'goal'),
                    ),
                    const SizedBox(height: 6),
                    _buildProgressRow(
                      icon: Icons.timer_outlined,
                      label: 'Activités · $timeLabel',
                      progress: bigProgressTime,
                      color: _colorForProgress(bigProgressTime, context),
                      onTap: () async {
                        final goNow = await _showDomainDetail(
                            d, startCal, endCal, days,
                            focus: 'time');
                        if (!mounted) return;
                        if (goNow == true) setState(() => _tab = _Tab.now);
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildProgressRow(
                      icon: Icons.repeat,
                      label: 'Routines · $routinesLabelD',
                      progress: routinesProgress,
                      color: dColor ?? _colorForProgress(routinesProgress, context),
                      onTap: () => _showDomainDetail(
                          d, startCal, endCal, days,
                          focus: 'habit'),
                    ),
                  ],
                ),
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

        // Précalcul des complétions par jour pour cette activité (dayPlan + sessions timer)
        final Map<String, int> countByYmd = {};
        // 1) Items activityTime cochés dans le day plan (refId == a.id)
        final startMondayYmd = '${startMonday.year}${startMonday.month.toString().padLeft(2, '0')}${startMonday.day.toString().padLeft(2, '0')}';
        for (final item in logic.state.dayPlan.where((it) =>
            it.kind == PlanKind.activityTime &&
            it.refId == a.id &&
            it.done &&
            !it.archived &&
            it.yyyymmdd.compareTo(startMondayYmd) >= 0)) {
          countByYmd[item.yyyymmdd] = (countByYmd[item.yyyymmdd] ?? 0) + 1;
        }
        // 2) Sessions timer (en minutes, normalisées sur 30 min = 1 unité)
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
        // Référence = min(max de l'activité, 5h) — évite les heatmaps pâles pour les activités courtes
        final maxActivity = countByYmd.values.fold(0, (m, v) => v > m ? v : m);
        final referenceCount = maxActivity.clamp(1, 10); // 1 unité min, 10 = 5h max

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (dColor != null)
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: dColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              a.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () async {
                              final s = await _askText(ctx, "Renommer", initial: a.name);
                              if (s == null || s.trim().isEmpty) return;
                              setState(() => a.name = s.trim());
                              logic.onChange();
                              Navigator.pop(ctx, true);
                            },
                          ),
                        ],
                      ),
                      if (domain != null)
                        Text(
                          domain.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: dColor ?? cs.onSurface.withOpacity(.5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Stats ────────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      _statChip('Aujourd\'hui', fmtDur(durDay), cs),
                      const SizedBox(width: 8),
                      _statChip('Cette semaine', fmtDur(durWeek), cs),
                      const SizedBox(width: 8),
                      _statChip('Ce mois', fmtDur(durMonth), cs),
                    ],
                  ),
                ),

                // ── Graphe moyenne mobile ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Moyenne mobile',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withOpacity(.4),
                          )),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 56,
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
                    ],
                  ),
                ),

                // ── Heatmap 12 semaines ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('12 semaines',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withOpacity(.4),
                          )),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
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
                                final fullColor = dColor ?? cs.primary;
                                final color = count == 0
                                    ? emptyColor
                                    : Color.lerp(emptyColor, fullColor, intensity)!;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: gap),
                                  child: Container(
                                    width: cellSize,
                                    height: cellSize,
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
                    ],
                  ),
                ),

                const Divider(height: 1),

                // ── Lancer ───────────────────────────────────────────────────
                ListTile(
                  leading: Icon(Icons.play_arrow_rounded, color: dColor ?? cs.primary),
                  title: const Text('Lancer', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    logic.start(a.id);
                    Navigator.pop(ctx, true);
                    setState(() => _tab = _Tab.now);
                  },
                ),

                const Divider(height: 1),

                // ── Changer de domaine ────────────────────────────────────────
                ListTile(
                  leading: Icon(Icons.folder_outlined,
                      color: dColor ?? cs.onSurface.withOpacity(.6)),
                  title: const Text('Changer de domaine',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: domain != null ? Text(domain.name) : null,
                  onTap: () async {
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
                ),

                const Divider(height: 1),

                // ── Masquer jusqu'à ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text('Masquer jusqu\'à',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(.4),
                        letterSpacing: 0.5,
                      )),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text("Demain"),
                  onTap: () => hideUntil(_endOfDay(now.add(const Duration(days: 1)))),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.calendar_view_week_outlined),
                  title: const Text("Dans 3 jours"),
                  onTap: () => hideUntil(_endOfDay(now.add(const Duration(days: 3)))),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.event_repeat_outlined),
                  title: const Text("Dans 7 jours"),
                  onTap: () => hideUntil(_endOfDay(now.add(const Duration(days: 7)))),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.edit_calendar_outlined),
                  title: const Text("Choisir une date…"),
                  onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked == null) return;
                  await hideUntil(_endOfDay(picked)); // pop(true)
                },
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.restore),
                title: const Text("Annuler le masquage"),
                onTap: () {
                  logic.clearSnooze(a.id);
                  Navigator.pop(ctx, true);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
      },
    );

    return changed == true;
  }

  Widget _statChip(String label, String value, ColorScheme cs) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: cs.onSurface.withOpacity(.5))),
          ],
        ),
      ),
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

    String tab = focus == 'habit' ? 'habit' : focus == 'goal' ? 'goal' : 'time';
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
            final cs = Theme.of(context).colorScheme;

            // État local (copié de l'activité pour édition non destructive)
            bool manual = habit.manualTarget;
            HabitFreq freq = habit.habitFreq ?? HabitFreq.monthly;
            int target = habit.habitTarget ?? 1;
            bool autoTune = habit.autoTune;

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
                    // parse + clamp
                    final parsed = int.tryParse(targetCtrl.text.trim());
                    if (manual) {
                      target = (parsed == null || parsed < 1) ? 1 : parsed;
                    }
                    // Écrit dans l'objet
                    habit.manualTarget = manual;
                    habit.habitFreq = manual
                        ? freq
                        : habit.habitFreq; // si auto, on garde la freq actuelle
                    habit.habitTarget = manual ? target : habit.habitTarget;
                    habit.autoTune = autoTune;

                    logic.onChange(); // persiste
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
                          // Titre

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

                          // Switch manuel / auto
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "Définir une cible manuellement",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                              Switch(
                                value: manual,
                                onChanged: (v) {
                                  setSB(() {
                                    manual = v;
                                    if (manual) {
                                      // seed si jamais absent
                                      if (habit.habitTarget == null) {
                                        target = (target <= 0) ? 1 : target;
                                        targetCtrl.text = '$target';
                                      }
                                    }
                                  });
                                  // ne pas toucher au focus du TextField
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Choix fréquence (désactivé si pas manuel)
                          Opacity(
                            opacity: manual ? 1.0 : 0.4,
                            child: IgnorePointer(
                              ignoring: !manual,
                              child: Column(
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
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Champ cible
                          Opacity(
                            opacity: manual ? 1.0 : 0.4,
                            child: IgnorePointer(
                              ignoring: !manual,
                              child: TextField(
                                controller: targetCtrl,
                                focusNode: targetNode,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: "Cible ${freqLabel(freq)}",
                                  helperText:
                                      "Entier ≥ 1${unitSuffix().isNotEmpty ? " (${unitSuffix().trim()})" : ""}",
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (_) {
                                  // ne rien faire, on parse à l'enregistrement
                                },
                                onTapOutside: (_) => targetNode.unfocus(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                          // Switch auto-tune
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "Ajustement automatique",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                              Switch(
                                value: autoTune,
                                onChanged: (v) => setSB(() => autoTune = v),
                              ),
                            ],
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
                      a.isHabit && (domainId == null || a.domainId == domainId))
                  .toList()
              : logic.state.activities
                  .where((a) =>
                      !a.isHabit &&
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
                  ButtonSegment(value: 'goal', icon: Icon(Icons.flag_rounded)),
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
              final startMondayYmd = '${startMonday.year}${startMonday.month.toString().padLeft(2, '0')}${startMonday.day.toString().padLeft(2, '0')}';
              for (final item in _state!.dayPlan.where((it) =>
                  it.kind == PlanKind.activityTime && it.refId == a.id &&
                  it.done && !it.archived &&
                  it.yyyymmdd.compareTo(startMondayYmd) >= 0)) {
                countByYmd[item.yyyymmdd] = (countByYmd[item.yyyymmdd] ?? 0) + 1;
              }
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
              final maxCount = countByYmd.values.fold(1, (m, v) => v > m ? v : m);
              final reference = maxCount.clamp(1, 10);
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

          // ---------- Onglet Objectifs ----------
          if (tab == 'goal') {
            final activeGoals = _state!.goals
                .where((g) =>
                    g.status == 'active' &&
                    (domainId == null || g.domainId == domainId))
                .toList()
              ..sort((a, b) => a.order.compareTo(b.order));

            void openGoalDetail(Goal g) {
              showModalBottomSheet(
                context: ctx,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => GoalDetailSheet(
                  goal: g,
                  logic: logic,
                  state: _state!,
                  onChanged: () => setSB(() {}),
                ),
              );
            }

            Future<void> addGoalForDomain() async {
              String? selDomainId = domainId ??
                  (_state!.activeDomains.isNotEmpty ? _state!.activeDomains.first.id : null);
              final titleCtrl = TextEditingController();
              final actionCtrl = TextEditingController();

              await showDialog(
                context: ctx,
                builder: (dctx) => StatefulBuilder(
                  builder: (dctx, setD) => AlertDialog(
                    title: const Text('Nouvel objectif'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (domainId == null)
                            DropdownButtonFormField<String>(
                              value: selDomainId,
                              decoration: const InputDecoration(labelText: 'Domaine'),
                              items: _state!.activeDomains
                                  .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                                  .toList(),
                              onChanged: (v) => setD(() => selDomainId = v),
                            ),
                          if (domainId == null) const SizedBox(height: 12),
                          TextField(
                            controller: titleCtrl,
                            autofocus: true,
                            decoration: const InputDecoration(labelText: 'Objectif'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: actionCtrl,
                            decoration: const InputDecoration(labelText: 'Première action (optionnel)'),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Annuler')),
                      FilledButton(
                        onPressed: () {
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty || selDomainId == null) return;
                          logic.createGoal(
                            domainId: selDomainId!,
                            title: title,
                            firstAction: actionCtrl.text.trim().isEmpty ? null : actionCtrl.text.trim(),
                          );
                          setSB(() {});
                          Navigator.pop(dctx);
                        },
                        child: const Text('Ajouter'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final goalList = activeGoals.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Aucun objectif actif.',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: addGoalForDomain,
                          icon: const Icon(Icons.add),
                          label: const Text('Créer un objectif'),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    scrollController: scrollCtrl,
                    padding: const EdgeInsets.only(bottom: 100),
                    buildDefaultDragHandles: false,
                    itemCount: activeGoals.length,
                    onReorder: (oldIndex, newIndex) {
                      logic.reorderGoals(domainId, oldIndex, newIndex);
                      setSB(() {});
                    },
                    itemBuilder: (ctx, i) {
                      final g = activeGoals[i];
                      return GoalCard(
                          key: ValueKey(g.id),
                          goal: g,
                          muted: false,
                          logic: logic,
                          showDrag: true,
                          dragIndex: i,
                          onPin: () { logic.toggleGoalPin(g.id); setSB(() {}); },
                          onTap: () => openGoalDetail(g),
                          onArchive: () async {
                            final confirm = await showDialog<bool>(
                              context: ctx,
                              builder: (c) => AlertDialog(
                                title: const Text('Archiver ?'),
                                content: Text('Archiver "${g.title}" ?'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Annuler')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Archiver')),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              logic.archiveGoal(g.id);
                              setSB(() {});
                            }
                          });
                    },
                  );

            final goalBody = Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(children: [
                header,
                const SizedBox(height: 8),
                Expanded(child: goalList),
              ]),
            );

            return Scaffold(
              backgroundColor: Colors.transparent,
              body: goalBody,
              floatingActionButton: FloatingActionButton.extended(
                onPressed: addGoalForDomain,
                icon: const Icon(Icons.add),
                label: const Text('Nouvel objectif'),
              ),
              floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            );
          }

          // ---------- Rendu des sections ----------
          final list = ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (visibleUnder.isNotEmpty) _sectionTitle("À rattraper"),
              ...List.generate(visibleUnder.length, (i) {
                final a = visibleUnder[i];
                final tile = a.isHabit ? _buildHabitTile(a) : _buildTimeTile(a);

                final wrapped = _wrapTile(a, i, visibleUnder.length, tile);

                return _dismissibleActivityTile(a, wrapped);
              }),
              if (visibleOver.isNotEmpty && visibleUnder.isNotEmpty)
                const SizedBox(height: 8),
              if (visibleOver.isNotEmpty) _sectionTitle("Déjà atteint"),
              ...List.generate(visibleOver.length, (i) {
                final a = visibleOver[i];
                final tile = a.isHabit ? _buildHabitTile(a) : _buildTimeTile(a);

                final wrapped = _wrapTile(a, i, visibleOver.length, tile);

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
                    hiddenExpanded ? Icons.expand_less : Icons.expand_more,
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
/*                           ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Activité réaffichée"),
                            ),
                          ); */
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

  Widget _buildProgressRow({
    required IconData icon,
    required String label,
    required double progress,
    required Color color,
    VoidCallback? onTap,
  }) {
    final p = progress.clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.7))),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: p,
                      minHeight: 6,
                      backgroundColor: color.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
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

  String _fmtPct(int mins) => "${((mins / 1440.0) * 100).round()}%";

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

class DailyScoreChip extends StatelessWidget {
  final int done;
  final int total;
  final VoidCallback? onTap;

  const DailyScoreChip({
    super.key,
    required this.done,
    required this.total,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final score = done / total;
    final pct = (score * 100).round();

    final ringColor = score >= 1.0
        ? cs.primary
        : Color.lerp(cs.error, cs.primary, score.clamp(0.0, 1.0))!;

    final bg = cs.surfaceContainerHighest.withValues(alpha: .55);
    final border = cs.outlineVariant.withValues(alpha: .55);
    final textStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: .1,
      color: score >= 1.0 ? cs.primary : null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(width: 6),
                Text('$pct%', style: textStyle),
              ],
            ),
          ),
        ),
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
