// ignore_for_file: deprecated_member_use

import 'dart:io';
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
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/storage.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';

enum _Tab { dashboard, now, today, stats }

class MiniRingThick extends StatelessWidget {
  const MiniRingThick({
    super.key,
    required this.progress,
    required this.center,
    this.strokeWidth = 7,
  });

  final double progress; // 0..1
  final Widget center;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingPainter(
        progress: progress.clamp(0.0, 1.0),
        strokeWidth: strokeWidth,
        bg: Theme.of(context).colorScheme.onSurface.withOpacity(0.10),
        fg: Theme.of(context).colorScheme.primary.withOpacity(0.95),
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

  const StatsView({
    super.key,
    required this.logic,
    required this.state,
    required this.selectedDomainId,
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
        .rolloverUndone(); // 👈 Ramène les non-faits d’hier vers aujourd’hui
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
                      ...widget.state.domains.map(
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
                          axisNameSize: 24, // espace pour le titre de l’axe Y
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
            ],
          ),
        ),
      ],
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  runApp(const ProductivitwoApp());
}

class ProductivitwoApp extends StatelessWidget {
  const ProductivitwoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal, // ← change la teinte ici
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system, // clair/sombre selon l’iPhone
      home: const AppRoot(),
    );
  }
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
  final VoidCallback? onTap; // ex: aller sur l’onglet Maintenant

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
              onTap: () {
                widget.logic.stopActive();
                setState(() {});
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
    _ensureTicking(); // démarre/stoppe selon présence d’une session
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

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  final store = FileStore();
  DateTime _lastGlobalScan = DateTime.fromMillisecondsSinceEpoch(0);
  AppState? _state;
  late AppLogic logic;
  String? selectedDomainId;
  TimeScope scope = TimeScope.day;
  Timer? _heartbeat;
  _Tab _tab = _Tab.dashboard;
// affiché une seule fois tant que l’app reste ouverte

  // Champs d’état pour les badges
  Map<String, int> _domainAutoDeltas =
      {}; // agrégat des deltas d’activités par domaine

  Timer? _saveDebounce;
  bool _saveQueued = false;
  bool _saving = false;

  late final ValueNotifier<int> _tick; // seconds

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _tick = ValueNotifier<int>(0);

    _startMinuteHeartbeat();
    _init();
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
    _tick.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      // évite de scanner trop souvent (ex: toutes les 6h)
      if (DateTime.now().difference(_lastGlobalScan) >
          const Duration(hours: 6)) {
        final bumps = await logic.scanAllActivities();
        _lastGlobalScan = DateTime.now();
        if (bumps > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("$bumps objectif(s) ajusté(s) d’après les 30j"),
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
    final s = await store.loadOrInit();

    setState(() {
      _state = s;
      logic = AppLogic(_state!, _saveAndRefresh);

      () async {
        final bumps = await logic.scanAllActivities();
        if (bumps > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("$bumps objectif(s) ajusté(s) d’après les 30j"),
                duration: const Duration(seconds: 2)),
          );
          await store.save(_state!);
        }
      }();

      if (_state!.domains.isEmpty) {
        _state!.domains.add(Domain(name: 'Général'));
      }
      selectedDomainId ??= _state!.domains.first.id;
    });

    // ✅ ICI (point unique au démarrage)
    logic.rolloverUndoneOncePerDay();
    logic.ensureDailyHabitsPlanned();
    normalizeToPlanActivityId();

    // ... le reste inchangé
    final changes = await logic.reviewGoals();

    if (mounted) {
      setState(() {
        _domainAutoDeltas = {};
        for (final ch in changes.where((c) => c.kind == 'activity')) {
          final act = _state!.activities.firstWhere((a) => a.id == ch.id,
              orElse: () =>
                  Activity(domainId: '', name: 'deleted', habitTarget: 1));
          final dom = _state!.domains.firstWhere((d) => d.id == act.domainId,
              orElse: () => Domain(name: 'deleted'));
          if (dom.autoGoal) {
            _domainAutoDeltas[dom.id] =
                (_domainAutoDeltas[dom.id] ?? 0) + ch.deltaMin;
          }
        }
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

// 1) Helpers d’index <-> enum
  int _tabIndex(_Tab t) {
    switch (t) {
      case _Tab.dashboard:
        return 0;
      case _Tab.now:
        return 1;
      case _Tab.today:
        return 2;
      case _Tab.stats:
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
      default:
        return _Tab.stats;
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
        if (itAct != null && itAct.isNotEmpty) return itAct == runningId;
        return isInbox(it);
      }

      return true;
    }

    final filteredTodo = sections.todo.where(passesEffective).toList();

    return IndexedStack(
      index: _tabIndex(_tab),
      children: [
        _buildDashboardBody(context),
        NowTab(
          logic: logic,
          st: st,
          items: filteredTodo,
          day: DateTime.now(),
          buildRowsGrouped: logic.buildRowsGrouped,
          onGoTodo: () => setState(() => _tab = _Tab.today),
        ),
        TodayView(
          logic: logic,
          state: _state!,
          onGoNow: (habitId) {
            logic.forceNowHabit(habitId); // ce que tu as déjà
            setState(() => _tab = _Tab.now);
          },
          onGoNowTab: () => setState(() => _tab = _Tab.now),
        ),
        StatsView(logic: logic, state: st, selectedDomainId: null),
      ],
    );
  }

  // ---------- UI ----------

  Future<String?> _askText(BuildContext ctx, String title) async {
    final ctrl = TextEditingController();
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
    );

    logic.onChange();
  }

  Future<String?> _pickDomainId(BuildContext context) async {
    final domains = logic.state.domains;

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
      habitFreq: HabitFreq.monthly,
      habitTarget: 1,
      autoTune: true,
      linkedActivityId: result.linkedActivityId,
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

  bool _shouldShowFab() {
    switch (_tab) {
      case _Tab.today:
        return true;
      case _Tab.now:
        return false;
      case _Tab.stats:
        return false;
      default:
        return false;
    }
  }

  Widget _buildFab() {
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
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: "fab_now_action",
          tooltip: "Nouvelle action",
          onPressed: () async {
            await _createActionFromNow(context);
            if (!mounted) return;
            setState(() {});
          },
          child: const Icon(Icons.add),
        ),
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
              !it.archived)
          .toList();
      final actionsDone = actions.where((it) => it.done).length;
      final actionsTotal = actions.length;
      final routineSummary = logic.routineProgressSummaryForCurrentPeriod();
      final pct = total == 0 ? 0 : (done / total * 100).round();

      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final cs = theme.colorScheme;
          final ringColor = pct >= 100
              ? cs.primary
              : Color.lerp(cs.error, cs.primary, (pct / 100).clamp(0.0, 1.0))!;

          return SafeArea(
            child: Padding(
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
                ],
              ),
            ),
          );
        },
      );
    }

    Widget _buildDailyScoreChip(BuildContext context) {
      final today = yyyymmdd(DateTime.now());
      final actions = logic.state.dayPlan
          .where((it) =>
              it.yyyymmdd == today &&
              it.kind == PlanKind.action &&
              !it.archived)
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 5,
        title: Row(
          children: [
            const SizedBox(width: 3),
            ValueListenableBuilder<int>(
              valueListenable: _tick,
              builder: (context, _, __) {
                return AppBarProductivityBars(logic: logic, state: _state);
              },
            ),
            const SizedBox(width: 3),
            ValueListenableBuilder<int>(
              valueListenable: _tick,
              builder: (context, _, __) {
                final bins24 = logic.minutesByHourLast24(DateTime.now());
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
                        child: MiniHourBars24h(bins: bins24),
                      ),
                    ),
                  ),
                );
              },
            ),
            const Spacer(),
            _buildDailyScoreChip(context),
            const SizedBox(width: 6),
            _buildRoutineChip(context),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _openFiltersSheet(context),
              onLongPress: () {
                HapticFeedback.heavyImpact();

                setState(() {
                  logic.state.filters.enabled = !logic.state.filters.enabled;
                });

                logic.onChange();
              },
              child: Icon(
                Icons.tune,
                color: filtersOn
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).iconTheme.color,
              ),
            ),
            const SizedBox(width: 2),
            // 🛠 DEV ONLY — bouton reset data
            IconButton(
              icon: const Icon(Icons.restart_alt, size: 20),
              tooltip: 'Réinitialiser les données',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Réinitialiser ?'),
                    content: const Text(
                        'Toutes les données seront supprimées et l\'app repartira du seed initial.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Réinitialiser')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await FileStore().wipe();
                  exit(0);
                }
              },
            ),
            const SizedBox(width: 2),
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

// FAB uniquement sur Dashboard (ou adapte si tu veux aussi sur Today)
      //floatingActionButton: _tab == _Tab.dashboard ? _buildFocusFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex(_tab),
        onTap: (i) => setState(() => _tab = _tabFromIndex(i)),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.checklist), label: 'À faire'),
          BottomNavigationBarItem(
              icon: Icon(Icons.play_arrow), label: 'Maintenant'),
          BottomNavigationBarItem(
              icon: Icon(Icons.show_chart), label: 'Stats'),
        ],
      ),

      floatingActionButton: _shouldShowFab() ? _buildFab() : null,
    );
  }

  void _openFiltersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FiltersSheet(
        st: _state!, // ou widget.logic.state si c’est ta source
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

    final dailyTargetMinAll = _state!.activities
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
      for (final d in _state!.domains) {
        // done par domaine
        DateTime day = DateTime(start.year, start.month, start.day);
        while (day.isBefore(end)) {
          for (final a in _state!.activities
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
      for (final a in _state!.activities.where((a) => a.isHabit)) {
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
    // Les valeurs “live” (temps today jusqu’à now, halo, label, etc.)
    // seront calculées dans ValueListenableBuilder via _compute... (voir plus bas)

    return Column(
      children: [
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: ValueListenableBuilder<int>(
            valueListenable: _tick,
            builder: (context, _, __) {
              final now = DateTime.now();
              final g = _computeGlobalTimeGauges(now);
              final h = _computeGlobalHabitsGauge(now);
              final obj = _computeGoalsGauge();
              final cs = Theme.of(context).colorScheme;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GaugeRing(
                        label: 'Temps',
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
                ],
              );
            },
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: _tick,
            builder: (context, _, __) {
              final now = DateTime.now();
              return _buildDomainListLive(context, now);
            },
          ),
        )
      ],
    );
  }

  Widget _buildDomainListLive(BuildContext context, DateTime now) {
    final today0 = DateTime(now.year, now.month, now.day);
    final tomorrow = today0.add(const Duration(days: 1));

    // Fenêtres “incluant aujourd’hui”
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

    return ListView(
      children: [
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
          final dailyTargetMinD = _state!.activities
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

          return SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
                      label: 'Temps · $timeLabel',
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
                      color: _colorForProgress(routinesProgress, context),
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
        const SizedBox(height: 80),
      ],
    );
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
        (_state!.domains.isNotEmpty ? _state!.domains.first.id : null);

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
                    items: _state!.domains
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
                    "Objectif automatique : 1 / mois (s’ajuste tout seul chaque jour).",
                    style: TextStyle(fontSize: 12),
                  ),
                ] else ...[
                  const Text(
                    "Objectif automatique : 1 minute (s’ajuste tout seul chaque jour).",
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
    final s = await _askText(context, "Renommer l’activité");
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
                      ? "Réafficher l’activité"
                      : "Cacher l’activité",
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
      builder: (ctx) {
        Future<void> hideUntil(DateTime until) async {
          logic.snoozeActivityUntil(a.id, until);
          Navigator.pop(ctx, true); // ✅ changed
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: InkWell(
                  onTap: () {
                    String draft = a.name;
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (ctx2) => SafeArea(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.only(
                            left: 16, right: 16, top: 12,
                            bottom: MediaQuery.of(ctx2).viewInsets.bottom + 16,
                          ),
                          child: StatefulBuilder(
                            builder: (ctx2, setLocal) => Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Renommer l'activité",
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 12),
                                TextFormField(
                                  initialValue: a.name,
                                  autofocus: true,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                      hintText: "Nom de l'activité"),
                                  onChanged: (v) =>
                                      setLocal(() => draft = v),
                                  onFieldSubmitted: (_) {
                                    final v = draft.trim();
                                    if (v.isNotEmpty) {
                                      setState(() => a.name = v);
                                      logic.onChange();
                                    }
                                    Navigator.pop(ctx2);
                                    Navigator.pop(ctx, true);
                                  },
                                ),
                                const SizedBox(height: 16),
                                Row(children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.pop(ctx2),
                                      child: const Text("Annuler"),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () {
                                        final v = draft.trim();
                                        if (v.isNotEmpty) {
                                          setState(() => a.name = v);
                                          logic.onChange();
                                        }
                                        Navigator.pop(ctx2);
                                        Navigator.pop(ctx, true);
                                      },
                                      child: const Text("Enregistrer"),
                                    ),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: Text(
                    a.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text("Demain"),
                onTap: () =>
                    hideUntil(_endOfDay(now.add(const Duration(days: 1)))),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_view_week_outlined),
                title: const Text("Dans 3 jours"),
                onTap: () =>
                    hideUntil(_endOfDay(now.add(const Duration(days: 3)))),
              ),
              ListTile(
                leading: const Icon(Icons.event_repeat_outlined),
                title: const Text("Dans 7 jours"),
                onTap: () =>
                    hideUntil(_endOfDay(now.add(const Duration(days: 7)))),
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text("Choisir une date…"),
                onTap: () async {
                  // ✅ Variante clean: on choisit la date DANS le sheet,
                  // puis on pop(true) quand c’est appliqué.
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
                leading: const Icon(Icons.restore),
                title: const Text("Annuler le masquage"),
                onTap: () {
                  logic.clearSnooze(a.id);
                  Navigator.pop(ctx, true); // ✅ changed
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    return changed == true;
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
            (_ringAnimTokenByHabit[habitId] ?? 0) + 1; // ✅ tick d’anim
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

            // petit helper pour afficher l’unité / libellé
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
                    // Écrit dans l’objet
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
                                  // ne rien faire, on parse à l’enregistrement
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
                                        false; // manuel > auto (évite l’ambiguïté)
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
                        false; // ✅ évite que le lock garde l’ordre/sections figées
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

            // ratios existants (garde ton ring 90j)
            final s7 = logic.timeSliding(a.id, 7);

            // Données journalières sur ~60 jours (pour tracer 30 points + fenêtre 30j)
            final start = dayKey(now).subtract(const Duration(days: 59));
            final end = dayKey(now).add(const Duration(days: 1));

            final minutesByDay = timeByDayForActivity(
              sessions: _state!.sessions,
              activityId: a.id,
              start: start,
              end: end,
              now: now,
            );

            final series7 = movingAvgHoursSeries(
              minutesByDay: minutesByDay,
              today: now,
              windowDays: 7,
              points: 30,
            );

            final series30 = movingAvgHoursSeries(
              minutesByDay: minutesByDay,
              today: now,
              windowDays: 30,
              points: 30,
            );

            final goalHoursPerDay = (s7.targetMin / 7.0) / 60.0;

            final avg7 = avgHoursNow(
                minutesByDay: minutesByDay, today: now, windowDays: 7);
            final cs = Theme.of(context).colorScheme;

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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 1),
                    ),
                    const SizedBox(height: 2),
                    DigitalAvgText(
                      text: fmtHhMmFromHours(avg7),
                      fontSize: 11,
                      suffix: "",
                      textColor: cs.primary.withOpacity(0.95),
                      bgOpacity: 0.05,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 1),
                    ),
                  ],
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 34,
                    child: MiniAvgLineChart(
                      series7: series7,
                      series30: series30,
                      goalHoursPerDay: goalHoursPerDay,
                    ),
                  ),
                ],
              ),
              trailing: FilledButton.icon(
                onPressed: () {
                  logic.start(a.id);
                  Navigator.pop(ctx, true);
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text("Go"),
              ),
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
                return "Aujourd’hui : $dayDone / $dayQuota";
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
                            Text("Impossible de reporter l’activité en cours"),
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
                await showHabitSettingsSheet(
                  context,
                  act: a,
                  onRename: (refresh) async {
                    await _renameRoutine(a);
                    refresh(); // update titre dans le sheet
                  },
                  onSaved: () {
                    logic.onChange();
                    setSB(() {}); // ✅ rebuild du dashboard sheet
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
                .toList();

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
                  (_state!.domains.isNotEmpty ? _state!.domains.first.id : null);
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
                              items: _state!.domains
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
                : ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.only(bottom: 100),
                    children: [
                      for (final g in activeGoals)
                        GoalCard(
                          goal: g,
                          muted: false,
                          logic: logic,
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
                          },
                        ),
                    ],
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
              ? "Quitter le challenge (l’activité continue)"
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
  final double height;
  final double width;
  final double gap;

  const MiniHourBars24h({
    super.key,
    required this.bins,
    this.height = 18,
    this.width = 54,
    this.gap = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // couleurs: cyan (réalisé) + rouge (reste)
    final doneColor = cs.primary; // cyan/teal
    final restColor = Colors.black.withOpacity(0.45);

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

          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gap / 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Column(
                  children: [
                    // haut = reste (rouge)
                    Expanded(
                      flex: (restFrac * 1000).round().clamp(0, 1000),
                      child: Container(color: restColor),
                    ),
                    // bas = réalisé (cyan)
                    Expanded(
                      flex: (doneFrac * 1000).round().clamp(0, 1000),
                      child: Container(
                        color: isCurrentHour
                            ? doneColor.withOpacity(1)
                            : doneColor.withOpacity(0.7),
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
