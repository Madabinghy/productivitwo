import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/time_scope.dart';
import 'package:productivitwo_v1/widgets/ring_painter.dart';
import 'package:productivitwo_v1/widgets/tiny_bar.dart';
import 'package:productivitwo_v1/widgets/today_view.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/storage.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:productivitwo_v1/utils/pacing.dart';

enum _Tab { dashboard, stats, today }

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
    final maxHoursY =
        (hours.isEmpty ? 0 : hours.reduce((a, b) => a > b ? a : b))
                .ceilToDouble() +
            1;
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

void main() => runApp(const ProductivitwoApp());

class ProductivitwoApp extends StatelessWidget {
  const ProductivitwoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
  bool _launcherHintSeen =
      false; // affiché une seule fois tant que l’app reste ouverte

  // Champs d’état pour les badges
  List<GoalChange> _recentGoalChanges = [];
  Map<String, int> _domainAutoDeltas =
      {}; // agrégat des deltas d’activités par domaine
  DateTime? _lastReviewDisplayedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init(); // lance l'async proprement

    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // rafraîchit l’UI pour la durée écoulée
    });
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    super.dispose();
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

    // ... le reste inchangé
    final changes = await logic.reviewGoals();

    if (mounted) {
      setState(() {
        _recentGoalChanges = changes;
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
        _lastReviewDisplayedAt = DateTime.now();
      });

      Future.delayed(const Duration(minutes: 10), () {
        if (!mounted) return;
        setState(() {
          _recentGoalChanges = [];
          _domainAutoDeltas = {};
        });
      });
    }
  }

  GoalChange? _changeForDomain(String domainId) {
    try {
      return _recentGoalChanges
          .firstWhere((c) => c.kind == 'domain' && c.id == domainId);
    } catch (_) {
      return null;
    }
  }

  GoalChange? _changeForDomainManual(String domainId) {
    try {
      return _recentGoalChanges
          .firstWhere((c) => c.kind == 'domain' && c.id == domainId);
    } catch (_) {
      return null;
    }
  }

  int _aggDeltaForDomainAuto(String domainId) {
    return _domainAutoDeltas[domainId] ?? 0;
  }

  GoalChange? _changeForActivity(String activityId) {
    try {
      return _recentGoalChanges
          .firstWhere((c) => c.kind == 'activity' && c.id == activityId);
    } catch (_) {
      return null;
    }
  }

  /// Retourne le texte du badge pour un domaine, qu’il soit manuel ou auto
  String? _domainBadgeText(Domain d) {
    // 1) domaine manuel → badge direct s’il a changé
    final manual = _changeForDomainManual(d.id);
    if (manual != null && manual.deltaMin != 0) {
      final up = manual.deltaMin > 0;
      return "${up ? '↑' : '↓'} ${manual.deltaMin.abs()}m";
    }
    // 2) domaine auto → somme des deltas d’activités
    final agg = _aggDeltaForDomainAuto(d.id);
    if (agg != 0) {
      final up = agg > 0;
      return "${up ? '↑' : '↓'} ${agg.abs()}m";
    }
    return null;
  }

  void _dismissLauncherHint(StateSetter setSB) {
    if (_launcherHintSeen) return;
    _launcherHintSeen = true;
    // rafraîchit la sheet + l'écran principal (au cas où)
    setSB(() {});
    if (mounted) setState(() {});
  }

  bool _pendingRefresh = false;

  Future<void> _saveAndRefresh() async {
    await store.save(_state!);

    if (!mounted) return;
    if (_pendingRefresh) return; // évite plusieurs rebuilds en rafale
    _pendingRefresh = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pendingRefresh = false;
      setState(() {}); // ← maintenant hors phase de build
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

  double _timeProgressAllOverRange(DateTime start, DateTime end, int days) {
    final timeByDomain = logic.timeTotalsByDomain(start, end);
    final total =
        timeByDomain.values.fold<Duration>(Duration.zero, (a, b) => a + b);
    final totalHours = total.inMinutes / 60.0;

    final goalMinDayAll = _state!.domains
        .map((d) => logic.domainGoalMinDay(d.id))
        .fold<int>(0, (a, b) => a + b);

    final maxHours = (goalMinDayAll * days) / 60.0;
    return maxHours > 0 ? (totalHours / maxHours).clamp(0.0, 1.0) : 0.0;
  }

  double _timeProgressDomainOverRange(
      String domainId, DateTime start, DateTime end, int days) {
    final timeByDomain = logic.timeTotalsByDomain(start, end);
    final dur = timeByDomain[domainId] ?? Duration.zero;
    final hours = dur.inMinutes / 60.0;

    final goalMinDay = logic.domainGoalMinDay(domainId);
    final maxHours = (goalMinDay * days) / 60.0;
    return maxHours > 0 ? (hours / maxHours).clamp(0.0, 1.0) : 0.0;
  }

  String _scopeLabel() {
    switch (scope) {
      case TimeScope.day:
        return "Jour";
      case TimeScope.week:
        return "Semaine";
      case TimeScope.month:
        return "Mois";
    }
  }

  // ---------- DOMAINES DIALOGS (identiques à avant, abrégés) ----------
  Future<void> _addDomainDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Nouveau domaine'),
            content: TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Ajouter')),
            ],
          ),
        ) ??
        false;
    if (ok) {
      final name =
          ctrl.text.trim().isEmpty ? 'Nouveau domaine' : ctrl.text.trim();
      final d = Domain(name: name);
      _state!.domains.add(d);
      selectedDomainId = d.id;
      await _saveAndRefresh();
    }
  }

  Future<void> _renameDomainDialog(Domain d) async {
    final ctrl = TextEditingController(text: d.name);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Renommer le domaine'),
            content: TextField(controller: ctrl, autofocus: true),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Enregistrer')),
            ],
          ),
        ) ??
        false;
    if (ok) {
      d.name = ctrl.text.trim().isEmpty ? d.name : ctrl.text.trim();
      await _saveAndRefresh();
    }
  }

  Future<void> _deleteDomain(Domain d) async {
    if (_state!.domains.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Garde au moins un domaine.")));
      return;
    }
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Supprimer le domaine ?'),
            content:
                const Text('Toutes les activités associées seront supprimées.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Supprimer')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    final toRemoveActs = _state!.activities
        .where((a) => a.domainId == d.id)
        .map((a) => a.id)
        .toSet();
    for (final s in _state!.sessions
        .where((s) => toRemoveActs.contains(s.activityId) && s.endAt == null)) {
      s.endAt = DateTime.now();
    }
    _state!.sessions.removeWhere((s) => toRemoveActs.contains(s.activityId));
    _state!.habitProgress
        .removeWhere((hp) => toRemoveActs.contains(hp.activityId));
    _state!.activities.removeWhere((a) => a.domainId == d.id);
    _state!.domains.removeWhere((x) => x.id == d.id);
    if (selectedDomainId == d.id) selectedDomainId = _state!.domains.first.id;
    await _saveAndRefresh();
  }

  // ---------- ACTIVITÉS (ajout/édition/suppression + habits/temps) ----------
  Future<void> _addActivityDialog() async {
    if (selectedDomainId == null) return;
    final nameCtrl = TextEditingController();
    final goalCtrl = TextEditingController(text: '15');
    final unitCtrl = TextEditingController(text: 'unités');
    final targetCtrl = TextEditingController(text: '8');
    String kind = 'time';
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (context, setStateSB) {
              return AlertDialog(
                title: const Text('Nouvelle activité / habitude'),
                content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Nom')),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Type : '),
                      DropdownButton<String>(
                        value: kind,
                        items: const [
                          DropdownMenuItem(
                              value: 'time', child: Text('Temps (timer)')),
                          DropdownMenuItem(
                              value: 'habit',
                              child: Text('Habitude (compteur)')),
                        ],
                        onChanged: (v) {
                          setStateSB(() => kind = v ?? 'time');
                        },
                      ),
                    ]),
                    if (kind == 'time')
                      TextField(
                          controller: goalCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Objectif (min)'))
                    else ...[
                      TextField(
                          controller: unitCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Unité (ex: verres, pompes)')),
                      TextField(
                          controller: targetCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Objectif/jour')),
                    ],
                  ]),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annuler')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Ajouter')),
                ],
              );
            },
          ),
        ) ??
        false;

    if (ok) {
      final name = nameCtrl.text.trim().isEmpty
          ? 'Nouvelle activité'
          : nameCtrl.text.trim();
      if (kind == 'time') {
        final goal = int.tryParse(goalCtrl.text.trim()) ?? 15;
        _state!.activities.add(Activity(
            domainId: selectedDomainId!,
            name: name,
            type: 'time',
            goalMin: goal,
            habitTarget: 1));
      } else {
        final unit =
            unitCtrl.text.trim().isEmpty ? 'unités' : unitCtrl.text.trim();
        _state!.activities.add(Activity(
            domainId: selectedDomainId!,
            name: name,
            type: 'habit',
            unit: unit,
            habitTarget: 1));
      }
      await _saveAndRefresh();
    }
  }

  Future<void> _editActivityDialog(Activity a) async {
    final nameCtrl = TextEditingController(text: a.name);
    final goalCtrl = TextEditingController(text: a.goalMin.toString());
    final unitCtrl = TextEditingController(text: a.unit ?? 'unités');
    final targetCtrl =
        TextEditingController(text: (logic.dayQuotaFor(a)).toString());
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Modifier'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nom')),
              if (a.isHabit) ...[
                TextField(
                    controller: unitCtrl,
                    decoration: const InputDecoration(labelText: 'Unité')),
                TextField(
                    controller: targetCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Objectif/jour')),
              ] else
                TextField(
                    controller: goalCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Objectif (min)')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Enregistrer')),
            ],
          ),
        ) ??
        false;

    if (ok) {
      a.name = nameCtrl.text.trim().isEmpty ? a.name : nameCtrl.text.trim();
      if (a.isHabit) {
        a.unit = unitCtrl.text.trim().isEmpty ? a.unit : unitCtrl.text.trim();
      } else {
        a.goalMin = int.tryParse(goalCtrl.text.trim()) ?? a.goalMin;
      }
      await _saveAndRefresh();
    }
  }

  Future<void> _deleteActivity(Activity a) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Supprimer ?'),
            content: Text('Supprimer "${a.name}" et ses données ?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Supprimer')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    for (final s in _state!.sessions
        .where((s) => s.activityId == a.id && s.endAt == null)) {
      s.endAt = DateTime.now();
    }
    _state!.activities.removeWhere((x) => x.id == a.id);
    _state!.sessions.removeWhere((s) => s.activityId == a.id);
    _state!.habitProgress.removeWhere((hp) => hp.activityId == a.id);
    await _saveAndRefresh();
  }

  // Dernière session en cours (ou null)
  Session? _currentSession() {
    if (_state == null) return null;
    final running = _state!.sessions.where((s) => s.endAt == null).toList();
    if (running.isEmpty) return null;
    // on prend la plus récente
    running.sort((a, b) => a.startAt.compareTo(b.startAt));
    return running.last;
  }

  Activity? _activityById(String id) {
    if (_state == null) return null;
    return _state!.activities.firstWhere(
      (a) => a.id == id,
      orElse: () =>
          Activity(domainId: '', name: 'Activité supprimée', habitTarget: 1),
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _fmtHoursHM(double h) {
    final totalMin = (h * 60).round();
    final hh = totalMin ~/ 60;
    final mm = totalMin % 60;
    return "${hh}h ${mm}m";
  }

// 1) Helpers d’index <-> enum
  int _tabIndex(_Tab t) => t == _Tab.dashboard ? 0 : (t == _Tab.today ? 1 : 2);
  _Tab _tabFromIndex(int i) =>
      i == 0 ? _Tab.dashboard : (i == 1 ? _Tab.today : _Tab.stats);

// 2) Body : route correctement vers TodayView
  Widget _buildBody(BuildContext context) {
    switch (_tab) {
      case _Tab.dashboard:
        return _buildDashboardBody(context);
      case _Tab.today:
        return TodayView(logic: logic, state: _state!);
      case _Tab.stats:
        return StatsView(
          logic: logic,
          state: _state!,
          selectedDomainId: null,
        );
    }
  }
  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    // 1) État de chargement (avant que FileStore ait chargé le JSON)
    if (_state == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2) App prête -> Scaffold complet
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // pas de flèche retour
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_currentSession() != null)
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(Icons.fiber_manual_record,
                    color: Colors.red, size: 16),
              ),
            DropdownButton<TimeScope>(
              value: scope,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: TimeScope.day, child: Text('Jour')),
                DropdownMenuItem(value: TimeScope.week, child: Text('Semaine')),
                DropdownMenuItem(value: TimeScope.month, child: Text('Mois')),
              ],
              onChanged: (v) => setState(() => scope = v ?? TimeScope.day),
            ),
            IconButton(
              tooltip: 'Ajouter un domaine',
              onPressed: _addDomainDialog,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
            IconButton(
              tooltip: 'Gérer domaines & activités',
              onPressed: _openManagementSheet,
              icon: const Icon(Icons.tune),
            ),
            IconButton(
              tooltip: "Inbox",
              onPressed: _openInboxSheet,
              icon: const Icon(Icons.inbox_outlined),
            ),
            // Dans ton AppBar actions:
            IconButton(
              tooltip: 'Panneau Dev',
              icon: const Icon(Icons.developer_mode),
              onPressed: () => _openDevPanel(context),
            ),
          ],
        ),
      ),

// --- Dans build(...) ---

      body: _buildBody(context),

// FAB uniquement sur Dashboard (ou adapte si tu veux aussi sur Today)
      floatingActionButton: _tab == _Tab.dashboard ? _buildFocusFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex(_tab),
        onTap: (i) => setState(() => _tab = _tabFromIndex(i)),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checklist),
            label: 'Aujourd’hui',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'Stats',
          ),
        ],
      ),
    );
  }

  void _openDevPanel(BuildContext context) {
    final habits = _state!.activities.where((a) => a.isHabit).toList();
    habits.sort((a, b) => a.name.compareTo(b.name));

    // petits contrôleurs pour le form
    Activity? _selectedHabit = habits.isNotEmpty ? habits.first : null;
    final daysCtrl = TextEditingController(text: '5');
    final perDayCtrl = TextEditingController(text: '1');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSB) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Panneau Dev',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),

                  // Choix de l’habitude
                  if (habits.isEmpty)
                    const Text(
                        "Aucune routine trouvée. Crée d'abord une habitude."),
                  if (habits.isNotEmpty) ...[
                    const Text('Routine cible'),
                    const SizedBox(height: 6),
                    DropdownButton<Activity>(
                      value: _selectedHabit,
                      isExpanded: true,
                      items: habits.map((a) {
                        final freq = a.habitFreq?.name ?? 'daily?';
                        final tgt = a.habitTarget ?? logic.dayQuotaFor(a);
                        return DropdownMenuItem(
                          value: a,
                          child: Text(
                            '${a.name}  ·  $freq x$tgt',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (a) => setSB(() => _selectedHabit = a),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: daysCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Jours (dernier N jours)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: perDayCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Incréments / jour',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.add_reaction),
                        label: const Text('Créer routine de test (auto)'),
                        onPressed: () {
                          final d = _state!.domains.first;
                          final h = Activity(
                            domainId: d.id,
                            name: 'TEST auto',
                            type: 'habit',
                            habitFreq: HabitFreq.monthly, // démarre à 1/mois
                            habitTarget: 1,
                            autoTune: true,
                          );
                          _state!.activities.add(h);
                          setState(() => logic.onChange());
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Routine test créée')),
                          );
                          // rafraîchir la liste locale
                          habits.add(h);
                          habits.sort((a, b) => a.name.compareTo(b.name));
                          setSB(() => _selectedHabit = h);
                        },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.history),
                        label: const Text('Injecter historique'),
                        onPressed: (_selectedHabit == null)
                            ? null
                            : () async {
                                final days =
                                    int.tryParse(daysCtrl.text.trim()) ?? 5;
                                final per =
                                    int.tryParse(perDayCtrl.text.trim()) ?? 1;
                                await logic.devAddHabitHistory(
                                    _selectedHabit!.id,
                                    days: days,
                                    perDay: per);
                                if (mounted) {
                                  setState(() {}); // refresh UI globale
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Ajouté $per/j sur $days jours')),
                                  );
                                }
                              },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.tune),
                        label: const Text('Scan global (objectifs)'),
                        onPressed: () async {
                          final changes = await logic.reviewGoals(force: true);
                          if (mounted) {
                            setState(() {}); // rafraîchir l’UI
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Scan exécuté (${changes.length} changements)')),
                            );
                          }
                        },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.list_alt),
                        label: const Text('Log 7j/30j'),
                        onPressed: () {
                          final hs = _state!.activities.where((a) => a.isHabit);
                          for (final a in hs) {
                            final w = logic.habitSliding(a.id, 7);
                            final m = logic.habitSliding(a.id, 30);
                            debugPrint('[HAB] ${a.name} '
                                'freq=${a.habitFreq}'
                                '7j=${w.done}/${w.target} 30j=${m.done}/${m.target}');
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Voir la console')),
                          );
                        },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Reset app (tout effacer)'),
                        style:
                            FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () async {
                          // stop session en cours si tu veux être clean
                          logic.stopActive();

                          await store.wipe(); // 1) supprime le fichier
                          setState(() => _state =
                              null); // 2) vide l’état pour montrer le loader
                          final s =
                              await store.loadOrInit(); // 3) recrée état seed
                          setState(() {
                            _state = s;
                            logic = AppLogic(_state!, _saveAndRefresh);
                            // (optionnel) relancer un reviewGoals si tu veux, mais pas nécessaire
                          });

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Données réinitialisées')),
                            );
                          }
                        },
                      )
                    ],
                  ),

                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Fermer'),
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

  void _openInboxSheet() {
    final txtCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSB) {
            final items = _state!.inbox.toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: 16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // champ d'ajout rapide
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: txtCtrl,
                          decoration: const InputDecoration(
                            hintText:
                                "Capture rapide (idée / tâche / objectif)",
                          ),
                          onSubmitted: (_) {
                            logic.inboxAdd(txtCtrl.text);
                            setSB(() {
                              txtCtrl.clear();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          logic.inboxAdd(txtCtrl.text);
                          setSB(() {
                            txtCtrl.clear();
                          });
                        },
                        child: const Text("Ajouter"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text("Inbox vide ✨"),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final it = items[i];
                          return ListTile(
                            dense: true,
                            title: Text(it.title,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text("Ajouté le ${it.createdAt}"),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => _clarifyInboxItem(
                                      sheetCtx, setSB, it.id, it.title),
                                  child: const Text("Clarifier"),
                                ),
                                IconButton(
                                  tooltip: "Archiver",
                                  onPressed: () {
                                    logic.inboxRemove(it.id);
                                    setSB(() {});
                                  },
                                  icon: const Icon(Icons.archive_outlined),
                                ),
                              ],
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

  void _clarifyInboxItem(
      BuildContext parentCtx,
      void Function(void Function()) setSB,
      String inboxId,
      String initialTitle) {
    final titleCtrl = TextEditingController(text: initialTitle);
    String? pickedDomainId = selectedDomainId ??
        (_state!.domains.isNotEmpty ? _state!.domains.first.id : null);
    String? pickedActivityId; // optionnel
    final nextCtrl = TextEditingController(); // prochaine action optionnelle
    final ctxCtrl = TextEditingController(); // contexte optionnel

    showDialog(
      context: parentCtx,
      builder: (dlgCtx) {
        return AlertDialog(
          title: const Text("Clarifier"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration:
                      const InputDecoration(labelText: "Titre de l’objectif"),
                ),
                const SizedBox(height: 8),
                // Domaine
                DropdownButtonFormField<String>(
                  value: pickedDomainId,
                  items: _state!.domains
                      .map((d) =>
                          DropdownMenuItem(value: d.id, child: Text(d.name)))
                      .toList(),
                  onChanged: (v) => pickedDomainId = v,
                  decoration: const InputDecoration(labelText: "Domaine"),
                ),
                const SizedBox(height: 8),
                // Activité support (optionnelle)
                DropdownButtonFormField<String>(
                  value: pickedActivityId,
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text("— Aucune activité —")),
                    ..._state!.activities.map((a) =>
                        DropdownMenuItem(value: a.id, child: Text(a.name))),
                  ],
                  onChanged: (v) => pickedActivityId = v,
                  decoration:
                      const InputDecoration(labelText: "Activité (optionnel)"),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nextCtrl,
                  decoration: const InputDecoration(
                      labelText: "Prochaine action (optionnel)"),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctxCtrl,
                  decoration: const InputDecoration(
                      labelText: "Contexte ex. maison, ordi (optionnel)"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dlgCtx).pop(),
                child: const Text("Annuler")),
            FilledButton(
              onPressed: () {
                if (pickedDomainId == null) return;
                logic.inboxToGoal(
                  inboxId: inboxId,
                  domainId: pickedDomainId!,
                  title: titleCtrl.text.trim().isEmpty
                      ? initialTitle
                      : titleCtrl.text.trim(),
                  activityId: pickedActivityId,
                  nextAction: nextCtrl.text.trim().isEmpty
                      ? null
                      : nextCtrl.text.trim(),
                  context:
                      ctxCtrl.text.trim().isEmpty ? null : ctxCtrl.text.trim(),
                );
                setSB(() {}); // refresh la feuille Inbox
                Navigator.of(dlgCtx).pop();
              },
              child: const Text("Créer l’objectif"),
            ),
          ],
        );
      },
    );
  }

  Widget _runningBanner() {
    final s = _state!.sessions.where((x) => x.endAt == null).last;
    final a = _state!.activities.firstWhere((x) => x.id == s.activityId);
    final dur = DateTime.now().difference(s.startAt);

    String _fmt(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return h > 0 ? "${h}h ${m}m ${sec}s" : "${m}m ${sec}s";
    }

    return ConstrainedBox(
      // ← hauteur fixe = pas de “saut” de layout
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

            // ---- Texte à gauche
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nom d’activité
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 2),

                  // Ligne 1
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

                  // Ligne 2 : temps seul (monospace pour éviter les micro-décalages)
                  Text(
                    _fmt(dur),
                    style: const TextStyle(
                      fontFeatures: [
                        FontFeature.tabularFigures()
                      ], // monospace numérique
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // ---- Bouton Stop à droite (taille fixe)
            SizedBox(
              width: 104,
              height: 40,
              child: FilledButton.icon(
                onPressed: () => setState(() {
                  logic.stopActive();
                }),
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

  Widget _buildDashboardBody(BuildContext context) {
// 1) Portée (calendaire)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final start90 = today.subtract(const Duration(days: 89));
    final end90 = today.add(const Duration(days: 1)); // end exclusif
    final progTimeAll90 = _timeProgressAllOverRange(start90, end90, 90);

    final start24 = now.subtract(const Duration(hours: 24));
    final totals24 = logic.timeTotalsByDomain(start24, now);
    final total24Dur =
        totals24.values.fold<Duration>(Duration.zero, (a, b) => a + b);

    final total24Hours = total24Dur.inMinutes / 60.0;
    final outerProgressAll24 = (total24Hours / 24.0).clamp(0.0, 1.0);

    final start7 = today.subtract(const Duration(days: 7));
    final end7 = today; // exclut aujourd’hui

    final totals7 = logic.timeTotalsByDomain(start7, end7);
    final total7Dur =
        totals7.values.fold<Duration>(Duration.zero, (a, b) => a + b);

    final avg7HoursPerDay = (total7Dur.inMinutes / 60.0) / 7.0;

    final mainProgress = (avg7HoursPerDay / 24.0).clamp(0.0, 1.0);
    final mainText = _fmtHoursHM(avg7HoursPerDay); // ex: 15h10

    int _doneHabitsForDomainCalendar(
        String domainId, DateTime start, DateTime end) {
      // somme calendaire: [start, end)
      int sum = 0;
      DateTime d = DateTime(start.year, start.month, start.day);
      while (d.isBefore(end)) {
        for (final a in _state!.activities
            .where((a) => a.isHabit && a.domainId == domainId)) {
          sum += logic.habitValueOn(a.id, d);
        }
        d = d.add(const Duration(days: 1));
      }
      return sum;
    }

    int _targetHabitsForDomainCalendar(
        String domainId, DateTime start, DateTime end) {
      final days = end.difference(start).inDays;
      int sum = 0;
      for (final a in _state!.activities
          .where((a) => a.isHabit && a.domainId == domainId)) {
        sum += logic.dayQuotaFor(a) * days; // cible/jour (dérivée) × nb jours
      }
      return sum;
    }

// Version “Tous domaines”
    int _doneHabitsAllCalendar(DateTime start, DateTime end) {
      int sum = 0;
      for (final d in _state!.domains) {
        sum += _doneHabitsForDomainCalendar(d.id, start, end);
      }
      return sum;
    }

    int _targetHabitsAllCalendar(DateTime start, DateTime end) {
      int sum = 0;
      for (final d in _state!.domains) {
        sum += _targetHabitsForDomainCalendar(d.id, start, end);
      }
      return sum;
    }

    final (startCal, endCal, days) = _rangeForScope(now);

    // --- Fenêtre pour les HABITUDES ---
    // Si scope == day : on prend les 7 derniers jours calendaires (aujourd'hui inclus)
    final bool rollingHabits7d = (scope == TimeScope.day);

    // today = date tronquée à minuit (tu l'as déjà défini plus haut)
    final DateTime startHabits =
        rollingHabits7d ? today.subtract(const Duration(days: 6)) : startCal;
    final DateTime endHabits =
        rollingHabits7d ? today.add(const Duration(days: 1)) : endCal;
    // Nombre de jours pour la cible (= 7 si on est en fenêtre 7j, sinon nb jours du scope)
    final int habitDays = rollingHabits7d ? 7 : days;

// 2) Fenêtre de TEMPS (glissante si scope == day)
    final bool rolling24h = (scope == TimeScope.day);
    final DateTime startTime =
        rolling24h ? now.subtract(const Duration(hours: 24)) : startCal;
    final DateTime endTime = rolling24h ? now : endCal;

// 3) Totaux TEMPS (global + par domaine) — sur [startTime, endTime]
    final timeByDomain = logic.timeTotalsByDomain(startTime, endTime);
    final totalTimeAll =
        timeByDomain.values.fold<Duration>(Duration.zero, (a, b) => a + b);
    final totalHours = totalTimeAll.inMinutes / 60.0;
    // Objectif global (minutes / jour) = somme des objectifs des domaines
    final goalMinDayAll = _state!.domains
        .map((d) => logic.domainGoalMinDay(d.id))
        .fold<int>(0, (a, b) => a + b);

// Max heures selon la période (Jour = objectif/jour, Semaine/Mois = × nb jours)
    final maxHours = (scope == TimeScope.day)
        ? goalMinDayAll / 60.0
        : (goalMinDayAll * days) / 60.0;
    final totalTimeProgress = (totalHours / maxHours).clamp(0.0, 1.0);

    final goalHours24All = goalMinDayAll / 60.0;
    final prog24All = goalHours24All > 0
        ? (total24Hours / goalHours24All).clamp(0.0, 1.0)
        : 0.0;

    // 4) Totaux HABITUDES (global + par domaine)
    // -> utilisent désormais startHabits / endHabits et habitDays
    final habitByDomain = logic.habitTotalsByDomain(startHabits, endHabits);

    final targetHabitsByDomain = {
      for (final d in _state!.domains)
        d.id: _state!.activities
            .where((a) => a.domainId == d.id && a.isHabit)
            .fold<int>(0, (sum, a) => sum + logic.dayQuotaFor(a) * habitDays),
    };

    final totalHabitsDone = _doneHabitsAllCalendar(startHabits, endHabits);
    final totalHabitsTarget = _targetHabitsAllCalendar(startHabits, endHabits);

    final totalHabitProgress = totalHabitsTarget == 0
        ? 0.0
        : (totalHabitsDone / totalHabitsTarget).clamp(0.0, 1.0);

    final running = _state!.sessions.any((x) => x.endAt == null);
    final avg90Txt = "Moy 90j : ${(progTimeAll90 * 100).round()}%";

    final tomorrow = today.add(const Duration(days: 1));
// ✅ Routines aujourd’hui
    final doneToday = _doneHabitsAllCalendar(today, tomorrow);
    final tgtToday = _targetHabitsAllCalendar(today, tomorrow);

// ✅ Moyenne “semaine” (ratio global sur 7 jours)
    final done7 = _doneHabitsAllCalendar(start7, end7);
    final tgt7 = _targetHabitsAllCalendar(start7, end7);

    final done90 = _doneHabitsAllCalendar(start90, end90);
    final tgt90 = _targetHabitsAllCalendar(start90, end90);
    final rate90 = tgt90 == 0 ? 0.0 : (done90 / tgt90).clamp(0.0, 1.0);

    final rateToday = tgtToday == 0 ? 0.0 : doneToday / tgtToday;
    final rateWeek = tgt7 == 0 ? 0.0 : done7 / tgt7;

    int _neededToBeatWeek({
      required int doneToday,
      required int tgtToday,
      required int done7,
      required int tgt7,
    }) {
      // Pas de cible => pas de seuil utile
      if (tgtToday <= 0 || tgt7 <= 0) return 0;

      final rateWeek = done7 / tgt7; // double
      final threshold = tgtToday *
          rateWeek; // double (cible "équivalente" pour être >= semaine)
      final need = threshold - doneToday; // double

      if (need <= 0) return 0;
      return need.ceil(); // arrondi au-dessus : il faut AU MOINS ce nombre
    }

    final isBelowWeek = rateToday < rateWeek;

    final need = _neededToBeatWeek(
      doneToday: doneToday,
      tgtToday: tgtToday,
      done7: done7,
      tgt7: tgt7,
    );

    int _doneForActivityPrimary(Activity a, DateTime today) {
      final f = a.habitFreq ?? HabitFreq.monthly;
      switch (f) {
        case HabitFreq.daily:
          return logic.habitSliding(a.id, 1).done;
        case HabitFreq.weekly:
          return logic.habitSliding(a.id, 7).done;
        case HabitFreq.monthly:
          return logic.habitSliding(a.id, 30).done;
      }
    }

    int _targetForActivityPrimary(Activity a) {
      final f = a.habitFreq ?? HabitFreq.monthly;
      switch (f) {
        case HabitFreq.daily:
          return logic.dayQuotaFor(a);
        case HabitFreq.weekly:
          return logic.weekTargetFrom(a);
        case HabitFreq.monthly:
          return logic.monthTargetFrom(a);
      }
    }

    double _primaryProgressForDomain(String domainId, DateTime today) {
      int done = 0;
      int tgt = 0;
      for (final a in _state!.activities
          .where((x) => x.isHabit && x.domainId == domainId)) {
        done += _doneForActivityPrimary(a, today);
        tgt += _targetForActivityPrimary(a);
      }
      return tgt == 0 ? 0.0 : (done / tgt).clamp(0.0, 1.0);
    }

    double _primaryProgressAll(DateTime today) {
      int done = 0;
      int tgt = 0;
      for (final a in _state!.activities.where((x) => x.isHabit)) {
        done += _doneForActivityPrimary(a, today);
        tgt += _targetForActivityPrimary(a);
      }
      return tgt == 0 ? 0.0 : (done / tgt).clamp(0.0, 1.0);
    }

    ({int done, int target}) _primaryAggForDomain(
        String domainId, DateTime today) {
      int done = 0;
      int target = 0;

      for (final a in _state!.activities
          .where((x) => x.isHabit && x.domainId == domainId)) {
        final f = a.habitFreq ?? HabitFreq.monthly;

        switch (f) {
          case HabitFreq.daily:
            done += logic.habitSliding(a.id, 1).done;
            target += logic.dayQuotaFor(a);
            break;
          case HabitFreq.weekly:
            done += logic.habitSliding(a.id, 7).done;
            target += logic.weekTargetFrom(a);
            break;
          case HabitFreq.monthly:
            done += logic.habitSliding(a.id, 30).done;
            target += logic.monthTargetFrom(a);
            break;
        }
      }

      return (done: done, target: target);
    }

    ({int done, int target}) _primaryAggAll(DateTime today) {
      int done = 0;
      int target = 0;

      for (final a in _state!.activities.where((x) => x.isHabit)) {
        final f = a.habitFreq ?? HabitFreq.monthly;

        switch (f) {
          case HabitFreq.daily:
            done += logic.habitSliding(a.id, 1).done;
            target += logic.dayQuotaFor(a);
            break;
          case HabitFreq.weekly:
            done += logic.habitSliding(a.id, 7).done;
            target += logic.weekTargetFrom(a);
            break;
          case HabitFreq.monthly:
            done += logic.habitSliding(a.id, 30).done;
            target += logic.monthTargetFrom(a);
            break;
        }
      }

      return (done: done, target: target);
    }

// Label épuré :
    final aggP = _primaryAggAll(today);
    final habitsLabel = "${aggP.done} / ${aggP.target}";
    final outerHabitsPrimary =
        aggP.target == 0 ? 0.0 : (aggP.done / aggP.target).clamp(0.0, 1.0);

    double snapToFull(
      double value, {
      double threshold = 0.90,
    }) {
      if (value >= threshold) return 1.0;
      return value.clamp(0.0, 1.0);
    }

    return Column(
      children: [
        if (running) _runningBanner(),

        // Anneaux globaux (Temps & Habitudes)
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
/* GaugeRing(
  label: "${_scopeLabel()} — Temps",
  centerText: _fmtHoursHM(maxHours),      // => "0h13m"
  subText: avg90Txt,                      // => "Moy 90j : 42%"
  progress: progTimeAll90,            // ou progTimeAll90 (voir note ci-dessous)
  color: _colorForProgress(progTimeAll90, context), // couleur basée sur 90j ✅
  onTap: () => _showDomainDetail(null, startCal, endCal, days, focus: 'time'),
), */

              NestedGauge(
                bigProgress: snapToFull(
                    mainProgress), // ton ring principal (objectif période)
                smallProgress: snapToFull(progTimeAll90), // ton ring 90j
                outerProgress:
                    snapToFull(outerProgressAll24), // ✅ halo “brut 24h”
                bigColor: _colorForProgress(mainProgress, context),
                smallColor: _colorForProgress(progTimeAll90, context),
                outerColor: Colors.cyanAccent, // ou blanc discret
                centerText: "",
                label: mainText, // ou maxHours selon ton choix
                onTap: () => _showDomainDetail(null, startCal, endCal, days,
                    focus: 'time'),
              ),

/*               GaugeRing(
                label: "Habitudes",
                valueText: totalHabitsTarget == 0
                    ? "0 / 0"
                    : "$totalHabitsDone / $totalHabitsTarget",
                progress: totalHabitProgress,
                color: _colorForProgress(totalHabitProgress, context),
                onTap: () => _showDomainDetail(null, startCal, endCal, days,
                    focus: 'habit'),
              ), */

              NestedGauge(
                bigProgress: snapToFull(rateWeek), // ✅ norme semaine
                smallProgress: snapToFull(
                    rate90), // option : tu peux mettre autre chose (voir note)
                outerProgress:
                    snapToFull(outerHabitsPrimary), // ✅ halo = aujourd’hui

                bigColor: _colorForProgress(rateWeek, context),
                smallColor: _colorForProgress(rate90, context), // ou neutre
                outerColor: Colors.cyanAccent,
                centerText: "",
                label: habitsLabel,
                size: 160,
                onTap: () => _showDomainDetail(null, startCal, endCal, days,
                    focus: 'habit'),
              ),
            ],
          ),
        ),

        // Liste scrollable : Jauges par domaine + Sélecteur + Activités du domaine
        Expanded(
          child: ListView(
            children: [
              // Jauges par domaine (inchangé, tu peux garder tes SectionCard si tu les utilises)
// --- Jauges par domaine (REMPLACER ton map existant) ---
              ..._state!.domains.map((d) {
                // TEMPS (sur la fenêtre choisie : 24h glissantes si Jour, sinon calendaire)
                final dur = timeByDomain[d.id] ?? Duration.zero;
                final h = dur.inMinutes / 60.0;

                // Objectif du domaine (minutes/jour) -> converti en heures selon la période
                final goalMinD = logic.domainGoalMinDay(d.id); // min / jour
                final maxHoursD = (scope == TimeScope.day)
                    ? goalMinD / 60.0
                    : (goalMinD * days) / 60.0;

                final progTime =
                    maxHoursD > 0 ? (h / maxHoursD).clamp(0.0, 1.0) : 0.0;

                // --- TEMPS : moyenne / score sur 90 jours (pour la couleur & le sous-texte)
                final progTime90 =
                    _timeProgressDomainOverRange(d.id, start90, end90, 90);

                // HABITUDES (sur la fenêtre habitude : 7j si scope == day, sinon scope calendaire)
                final doneH =
                    _doneHabitsForDomainCalendar(d.id, startHabits, endHabits);
                final tgtH = _targetHabitsForDomainCalendar(
                    d.id, startHabits, endHabits);

                final progHabit =
                    tgtH > 0 ? (doneH / tgtH).clamp(0.0, 1.0) : 0.0;

                final agg = computeDailyPacingAggregate(logic, domainId: d.id);
                final progHab =
                    agg.target > 0 ? (agg.done / agg.target).clamp(0, 1) : 0.0;

                final avg90TxtD = "Moy 90j : ${(progTime90 * 100).round()}%";

                final h24 = dur.inMinutes / 60.0;

                final goalH24 = goalMinD / 60.0; // standard fixe / jour
                final prog24 =
                    goalH24 > 0 ? (h24 / goalH24).clamp(0.0, 1.0) : 0.0;

                // ✅ Routines aujourd’hui (domaine)
                final doneTodayD =
                    _doneHabitsForDomainCalendar(d.id, today, tomorrow);
                final tgtTodayD =
                    _targetHabitsForDomainCalendar(d.id, today, tomorrow);
                final rateTodayD =
                    tgtTodayD == 0 ? 0.0 : (doneTodayD / tgtTodayD);

// ✅ Moyenne 7j (domaine)
                final done7D = _doneHabitsForDomainCalendar(d.id, start7, end7);
                final tgt7D =
                    _targetHabitsForDomainCalendar(d.id, start7, end7);
                final rateWeekD = tgt7D == 0 ? 0.0 : (done7D / tgt7D);

// ✅ Anneau principal = norme 7j (ramenée sur 24h ?)
// Ici routines = taux, donc on garde direct 0..1
                final bigProgressD = rateWeekD.clamp(0.0, 1.0);

// ✅ Label dynamique (done / +X tant qu’on est sous la semaine)
                final isBelowWeekD = rateTodayD < rateWeekD;
                final needD = _neededToBeatWeek(
                  doneToday: doneTodayD,
                  tgtToday: tgtTodayD,
                  done7: done7D,
                  tgt7: tgt7D,
                );

                final done90D =
                    _doneHabitsForDomainCalendar(d.id, start90, end90);
                final tgt90D =
                    _targetHabitsForDomainCalendar(d.id, start90, end90);
                final rate90D = tgt90D == 0 ? 0.0 : (done90D / tgt90D);

                smallProgress:
                rate90D.clamp(0.0, 1.0);
                smallColor:
                _colorForProgress(rate90D, context);

                final aggPD = _primaryAggForDomain(d.id, today);
                final routinesLabelD = "${aggPD.done} / ${aggPD.target}";
                final outerProgressD = aggPD.target == 0
                    ? 0.0
                    : (aggPD.done / aggPD.target).clamp(0.0, 1.0);

                return SectionCard(
                  // si tu n’utilises pas SectionCard, remplace par ton Container/Card
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(d.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Builder(builder: (_) {
                            final txt = _domainBadgeText(d);
                            if (txt == null) return const SizedBox.shrink();
                            final isUp = txt.startsWith('↑');
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isUp ? Colors.green : Colors.orange)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: (isUp ? Colors.green : Colors.orange)
                                        .withValues(alpha: 0.6)),
                              ),
                              child: Text(txt,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          isUp ? Colors.green : Colors.orange)),
                            );
                          }),
                        ],
                      ),
/*                       const SizedBox(height: 6),
                      // NEW: pacing centré sur les 2 jauges
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Builder(builder: (_) {
                            final agg = computeDailyPacingAggregate(logic,
                                domainId: d.id); // NEW
                            return Center(child: buildPacingChip(agg)); // NEW
                          }),
                        ],
                      ), */
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Jauge TEMPS : / objectif domaine
                          GaugeRing(
                            label: "Temps",
                            centerText: _fmtHoursHM(maxHoursD), // ex: 0h13m
                            subText: "Moy 90j : ${(progTime90 * 100).round()}%",
                            progress: progTime90,
                            size: 140,
                            color: _colorForProgress(progTime90, context),
                            onTap: () => _showDomainDetail(
                                d, startCal, endCal, days,
                                focus: 'time'),
                            // ✅ halo externe 24h
                            outerProgress: prog24,
                            outerColor: Colors
                                .white, // ou fg, ou _colorForProgress(prog24, context)
                          ),

                          // Jauge HABITUDES : / cible cumulée sur la période

/*                           GaugeRing(
                            label: "Habitudes",
                            valueText: "$doneH / $tgtH",
                            progress: progHabit,
                            size: 110,
                            color: _colorForProgress(progHabit, context),
                            onTap: () => _showDomainDetail(
                                d, startCal, endCal, days,
                                focus: 'habit'),
                          ), */
                          NestedGauge(
                            bigProgress: snapToFull(bigProgressD), // ✅ norme 7j
                            smallProgress: snapToFull(rate90D.clamp(0.0,
                                1.0)), // option : tu peux mettre 90j routines domaine si tu veux
                            outerProgress:
                                snapToFull(outerProgressD), // ✅ halo jour

                            bigColor: _colorForProgress(bigProgressD, context),
                            smallColor: _colorForProgress(rate90D, context),
                            outerColor: Colors.cyanAccent,

                            centerText: "", // tu as choisi épuré
                            label: routinesLabelD,
                            size: 140, // ajuste selon ton UI
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

              const SizedBox(height: 80), // marge pour le FAB si tu le gardes
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFocusFab() {
    return GestureDetector(
      onLongPress: () {
        // Focus “domaine courant” si dispo, sinon global
        final domId = selectedDomainId;
        if (domId != null) {
          _openFocusPanel(domainId: domId);
        } else {
          _openFocusPanel();
        }
      },
      child: FloatingActionButton.extended(
        onPressed: () => _openFocusPanel(), // Focus global
        icon: const Icon(Icons.lightbulb),
        label: const Text('Focus'),
      ),
    );
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

  bool isTimeReachedByAvg7(
    AppLogic l,
    Activity a, {
    required List<Session> sessions,
    double snap = 0.95,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();

    // objectif/jour (cohérent avec ton digital : target 7 / 7)
    final d7 = l.timeSliding(a.id, 7);
    final goalHoursPerDay = (d7.targetMin / 7.0) / 60.0;

    if (goalHoursPerDay <= 0) return true;

    // moyenne réelle 7j (cohérente avec ta courbe)
    final start =
        DateTime(t.year, t.month, t.day).subtract(const Duration(days: 59));
    final end = DateTime(t.year, t.month, t.day).add(const Duration(days: 1));

    final minutesByDay = timeByDayForActivity(
      sessions: sessions,
      activityId: a.id,
      start: start,
      end: end,
      now: t,
    );

    final avg7h =
        avgHoursNow(minutesByDay: minutesByDay, today: t, windowDays: 7);

    return avg7h >= goalHoursPerDay * snap;
  }

  void _showDomainDetail(
    Domain? domain,
    DateTime start,
    DateTime end,
    int days, {
    String focus = 'time', // 'time' | 'habit'
  }) {
    final domainId = domain?.id; // null => Tous domaines
    final cs = Theme.of(context).colorScheme;

    // ----- LOCK : fige sections + ordre quand on édite (habits & time) -----
    bool _lockActive = false;
    List<String> _lockUnderIds = <String>[];
    List<String> _lockOverIds = <String>[];
    void _lockNow() => _lockActive = true;
    int _ringAnimToken = 0;

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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (ctx) {
        String tab = (focus == 'habit') ? 'habit' : 'time';
        final scrollCtrl = ScrollController();

        return StatefulBuilder(builder: (ctx, setSB) {
          Future<void> showTimeExplainer(
            BuildContext context, {
            required Activity a,
            required AppLogic logic,
          }) async {
            final cs = Theme.of(context).colorScheme;

            // Stats glissantes utiles
            final d = logic.timeSliding(
                a.id, 1); // ~jour civil (ou 24h glissant selon ton impl)
            final w = logic.timeSliding(a.id, 7);
            final m = logic.timeSliding(a.id, 30);

            final goal = a.goalMin; // objectif/jour courant (minutes)
            String fmtMin(int min) => "${min ~/ 60}h ${min % 60}m";

            // Petites lignes pédagogiques
            final howItWorks =
                "Principe : tu as un objectif quotidien (en minutes). "
                "La jauge de l’anneau montre le progrès d’aujourd’hui. "
                "Les barres indiquent tes cumuls récent (semaine/mois) vs leurs cibles dérivées.";

            final tuning =
                "Ajustement auto : si tu dépasses régulièrement l’objectif (≥120% sur plusieurs jours), "
                "la cible augmente par petits pas. À l’inverse, si tu es souvent en-dessous (≤85%), elle descend. "
                "L’algorithme vise un objectif réaliste proche de ta cadence réelle.";

            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (ctx) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            )),
                        const SizedBox(height: 8),

                        // Objectif du jour
                        Text("Cible quotidienne : ${fmtMin(goal)}",
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),

                        // Récap rapides
                        Text(
                            "Aujourd’hui : ${fmtMin(d.doneMin)} / ${fmtMin(goal)}"),
                        Text(
                            "Semaine (7j) : ${fmtMin(w.doneMin)} / ${fmtMin(w.targetMin)}"),
                        Text(
                            "Mois (30j) : ${fmtMin(m.doneMin)} / ${fmtMin(m.targetMin)}"),
                        const SizedBox(height: 16),

                        Text(howItWorks),
                        const SizedBox(height: 12),
                        Text(tuning),

                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("OK"),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
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
                          Text(habit.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              )),
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

          Future<void> _openHabitManualTargetSheet(
            BuildContext context, {
            required Activity activity,
            required AppLogic logic,
            required VoidCallback
                refreshParent, // pour rafraîchir la liste après "Enregistrer"
          }) async {
            final cs = Theme.of(context).colorScheme;

            // ÉTAT LOCAL (copié depuis l’activité, pour éviter les reset pendant la saisie)
            bool manual = activity.manualTarget;
            final ctrlTarget = TextEditingController(
              text: logic.dayQuotaFor(activity).toString(),
            );

            // Optionnel : focus propre pour le champ
            final targetFocus = FocusNode();

            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (ctx) {
                return StatefulBuilder(
                  builder: (ctx, setSB) {
                    void setManual(bool v) {
                      setSB(() {
                        manual = v;
                        // si on passe en manuel et que la cible est 0 ⇒ seed à 1
                        if (manual &&
                            (int.tryParse(ctrlTarget.text) ?? 0) <= 0) {
                          ctrlTarget.text = '1';
                        }
                      });
                    }

                    void applyQuick(int v) {
                      setSB(() {
                        manual = true;
                        ctrlTarget.text = v.toString();
                      });
                    }

                    Widget quickChip(int v) => Padding(
                          padding: const EdgeInsets.only(right: 6, top: 6),
                          child: ActionChip(
                            label: Text('$v'),
                            onPressed: () => applyQuick(v),
                          ),
                        );

                    return SafeArea(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          16 + MediaQuery.of(ctx).viewInsets.bottom,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Titre
                            Text(activity.name,
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface)),
                            const SizedBox(height: 8),

                            // Explication courte
                            Text(
                              "Tu peux définir une cible quotidienne fixe (ex: 10 ${activity.unit ?? ''}). "
                              "Si tu la désactives, l’app ajustera automatiquement selon tes usages.",
                            ),
                            const SizedBox(height: 12),

                            // Switch manuel
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title:
                                  const Text("Définir la cible manuellement"),
                              value: manual,
                              onChanged: setManual,
                            ),

                            // Champ cible (affiché seulement si manuel)
                            if (manual) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      focusNode: targetFocus,
                                      controller: ctrlTarget,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: "Cible par jour",
                                        hintText: "ex: 10",
                                        suffixText:
                                            activity.unit?.isNotEmpty == true
                                                ? activity.unit
                                                : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                children: [
                                  quickChip(1),
                                  quickChip(2),
                                  quickChip(3),
                                  quickChip(5),
                                  quickChip(10),
                                ],
                              ),
                            ],

                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text("Annuler"),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.icon(
                                  icon: const Icon(Icons.save),
                                  label: const Text("Enregistrer"),
                                  onPressed: () {
                                    logic.onChange(); // persiste
                                    refreshParent(); // rafraîchir la liste appelante
                                    Navigator.pop(ctx); // fermer
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );

            targetFocus.dispose();
            ctrlTarget.dispose();
          }

          Future<void> _openHabitManualEditor(
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
                            Text(a.name,
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface)),
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
          }

          void _openHabitRationale(Activity a) {
            final d = logic.habitSliding(a.id, 1);
            final w = logic.habitSliding(a.id, 7);
            final m = logic.habitSliding(a.id, 30);

            final freq = a.habitFreq ?? HabitFreq.monthly;
            final unit = (a.unit ?? '').isNotEmpty ? ' ${a.unit}' : '';

            // Cibles dérivées (tes helpers)
            final dayTarget = logic.dayQuotaFor(a); // ex. 1 (si daily)
            final weekTarget = logic.weekTargetFrom(a); // ex. 1 (si weekly)
            final monthTarget = logic.monthTargetFrom(a); // ex. 4 (si monthly)

            String freqLabel(HabitFreq f) => f == HabitFreq.daily
                ? 'quotidienne'
                : (f == HabitFreq.weekly ? 'hebdomadaire' : 'mensuelle');

            String primaryLine;
            String rules;
            if (freq == HabitFreq.daily) {
              primaryLine = "Fréquence active : quotidienne \n"
                  "Cible $dayTarget $unit / jour.\n\n"
                  "Aujourd’hui : ${d.done} $unit / $dayTarget  •  "
                  "Semaine : ${w.done} $unit / $weekTarget  •  "
                  "Mois : ${m.done} $unit / $monthTarget.";
            } else if (freq == HabitFreq.weekly) {
              primaryLine = "Fréquence active : hebdomadaire \n"
                  "Cible $weekTarget $unit / semaine.\n"
                  "Semaine : ${w.done} $unit / $weekTarget  •  "
                  "Mois : ${m.done} $unit / $monthTarget.";
            } else {
              primaryLine = "Fréquence active : mensuelle \n"
                  "Cible $monthTarget $unit / mois.\n"
                  "• Mois : ${m.done} $unit / $monthTarget\n"
                  "• Semaine : ${w.done} $unit / $weekTarget.";
            }

            rules =
                "Règles : au-delà de 120% sur le mois, la cible monte automatiquement.\nPatientez le temps d'atteindre votre vitesse de croisière.\nVers ~4/mois on devient « hebdomadaire »\nvers ~30/mois, « quotidienne ».";

            showModalBottomSheet(
              context: ctx,
              showDragHandle: true,
              builder: (_) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(primaryLine),
                    const SizedBox(height: 10),
                    Text(rules,
                        style: TextStyle(
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurface
                                .withOpacity(.75))),
                    // ... après `Text(rules, ...)`
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .surfaceVariant
                            .withOpacity(.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Astuce",
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          SizedBox(height: 6),
                          Text("• Touchez l’anneau pour +1"),
                          Text("• Double-touchez l’anneau pour −1"),
                          Text("• Appui long : réglages & explications"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("OK"),
                      ),
                    )
                  ],
                ),
              ),
            );
          }

          // ---------- Helpers “Option B” (primaire) ----------
          double _habitPrimaryRatio(Activity a) {
            final d = logic.habitSliding(a.id, 1).ratio;
            final w = logic.habitSliding(a.id, 7).ratio;
            final m = logic.habitSliding(a.id, 30).ratio;
            final f = a.habitFreq ?? HabitFreq.monthly; // par défaut: mois
            return (f == HabitFreq.daily) ? d : (f == HabitFreq.weekly ? w : m);
          }

          bool _habitReached(Activity a) => _habitPrimaryRatio(a) >= 1.0;
          int _cmpByExit(Activity a, Activity b) {
            final ra = 1.0 - _habitPrimaryRatio(a);
            final rb = 1.0 - _habitPrimaryRatio(b);
            return ra.compareTo(rb); // plus proche des 100% en haut
          }

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

          Widget _wrapTile(Activity a, int i, int len, Widget tile) =>
              KeyedSubtree(
                key: ValueKey(a.id),
                child: Column(
                  children: [
                    if (i == 0) const SizedBox(height: 4),
                    tile,
                    if (i < len - 1) const Divider(height: 8),
                  ],
                ),
              );

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

            under = base
                .where((a) => !isTimeReachedByAvg7(
                      logic,
                      a,
                      sessions: _state!.sessions,
                      snap: snap,
                    ))
                .toList();

            over = base
                .where((a) => isTimeReachedByAvg7(
                      logic,
                      a,
                      sessions: _state!.sessions,
                      snap: snap,
                    ))
                .toList();
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
          final header = Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'time', label: Text('Temps')),
                  ButtonSegment(value: 'habit', label: Text('Habitudes')),
                ],
                selected: {tab},
                onSelectionChanged: (s) => setSB(() => tab = s.first),
              ),
            ],
          );

          Widget _buildTimeTile(Activity a) {
            final now = DateTime.now();

            // ratios existants (garde ton ring 90j)
            final s90 = logic.timeSliding(a.id, 90);
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

            final goalHoursPerDay = (s7.targetMin / 7.0) / 60.0; // target 7 / 7
            final goalTxt = fmtHhMmFromHours(goalHoursPerDay);

            return ListTile(
              onTap: () => showTimeExplainer(context, a: a, logic: logic),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              leading:
                  /* MiniRing(
                progress: s90.ratio,
                center: Text(
                  "${(s90.ratio * 100).round()}%",
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ), */
                  DigitalAvgText(
                text: goalTxt,
                suffix: "", // ✅ sans /j
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 8),

                  // Graphe (remplace les 2 TinyBar)
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
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text("Go"),
              ),
            );
          }

          void openHabitQuickAdjustSheet({
            required BuildContext context,
            required AppLogic logic,
            required Activity habit,
            required VoidCallback refresh, // setSB((){}) ou setState((){})
          }) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);

            showModalBottomSheet(
              context: context,
              showDragHandle: true,
              builder: (ctx) {
                return StatefulBuilder(
                  builder: (ctx, setLocal) {
                    final d =
                        logic.habitSliding(habit.id, 1).done; // valeur live

                    void _bump(int delta) {
                      logic.incHabit(habit.id, delta, today);
                      setLocal(() {}); // refresh dans le sheet
                      refresh(); // refresh parent si besoin
                    }

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(habit.name,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text("Aujourd’hui : $d ${habit.unit ?? ''}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),

                          // Ligne de gros boutons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              FilledButton.tonal(
                                onPressed: () => _bump(-1),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  child: Icon(Icons.remove),
                                ),
                              ),
                              FilledButton(
                                onPressed: () => _bump(1),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  child: Icon(Icons.add),
                                ),
                              ),
                              // (optionnel) +5 pour aller vite
                              OutlinedButton(
                                onPressed: () => _bump(5),
                                child: const Text("+5"),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("Terminé"),
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

          Widget _buildHabitTile(Activity a) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);

            final dH = logic.habitSliding(a.id, 1);
            final h90 = logic.habitSliding(a.id, 90);

            final quotaD = logic.dayQuotaFor(a);
            final isDaily =
                (a.habitFreq ?? HabitFreq.monthly) == HabitFreq.daily;

            final series30 = List<double>.generate(30, (i) {
              final day = DateTime(now.year, now.month, now.day)
                  .subtract(Duration(days: 29 - i));
              return logic.habitValueOn(a.id, day).toDouble();
            });

            final double histMax =
                isDaily ? quotaD.toDouble().clamp(1.0, 9999.0).toDouble() : 1.0;

            final target = h90.ratio.clamp(0.0, 1.0);
            final token = _ringAnimTokenByHabit[a.id] ?? 0;

            return InkWell(
              onLongPress: () => openHabitEditSheet(
                context: context,
                logic: logic,
                habit: a,
                onSaved: () => setSB(() {}),
              ),
              onTap: () => _openHabitManualEditor(a, setSB),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Gauche : ring 90j + tap dédié

                    SizedBox(
                      width: 56,
                      height: 56,
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey("${a.id}|$token"), // ✅ reset l’animation
                        tween: Tween<double>(begin: 1.0, end: target),
                        duration: const Duration(seconds: 5),
                        curve: Curves.easeOutCubic,
                        builder: (context, p, _) {
                          return MiniRingThick(
                            progress: p,
                            strokeWidth: 7,
                            center: Text(
                              "${(target * 100).round()}%",
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Milieu : titre + histogramme (tap possible sur l'histogramme)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Histogramme 30j
                          SizedBox(
                            height: 26,
                            child: GestureDetector(
                              onTap: () => _openHabitManualEditor(a, setSB),
                              child: MiniHistogram30d(
                                values: series30,
                                maxValue: histMax,
                                highlightLast: true,
                              ),
                            ),
                          ),

                          const SizedBox(height: 4),

                          // ✅ Petit texte explicatif
                          Opacity(
                            opacity: 0.65,
                            child: Text(
                              _habitSubText(
                                freq: a.habitFreq ?? HabitFreq.monthly,
                                dayDone: dH.done,
                                dayQuota: quotaD,
                                weekDone: logic.habitSliding(a.id, 7).done,
                                weekTarget: logic.weekTargetFrom(a),
                                monthDone: logic.habitSliding(a.id, 30).done,
                                monthTarget: logic.monthTargetFrom(a),
                              ),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Droite : + / - vertical
                    SizedBox(
                      width: 44,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StepButton(
                            icon: Icons.add,
                            onTap: () {
                              _triggerRingAnimFor(
                                  a.id, setSB); // 1️⃣ lock + animation
                              logic.incHabit(
                                  a.id, 1, today); // 2️⃣ mise à jour métier
                              _unlockSoon(setSB); // 3️⃣ relâche dans 5s
                            },
                          ),
                          const SizedBox(height: 10),
                          StepButton(
                            icon: Icons.remove,
                            onTap: () {
                              _triggerRingAnimFor(
                                  a.id, setSB); // 1️⃣ lock + animation
                              logic.incHabit(
                                  a.id, -1, today); // 2️⃣ mise à jour métier
                              _unlockSoon(setSB); // 3️⃣ relâche dans 5s
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ---------- Rendu des sections ----------
          final list = ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (under.isNotEmpty) _sectionTitle("À rattraper"),
              ...List.generate(under.length, (i) {
                final a = under[i];
                final tile = a.isHabit ? _buildHabitTile(a) : _buildTimeTile(a);
                return _wrapTile(a, i, under.length, tile);
              }),
              if (over.isNotEmpty && under.isNotEmpty)
                const SizedBox(height: 8),
              if (over.isNotEmpty) _sectionTitle("Déjà atteint"),
              ...List.generate(over.length, (i) {
                final a = over[i];
                final tile = a.isHabit ? _buildHabitTile(a) : _buildTimeTile(a);
                return _wrapTile(a, i, over.length, tile);
              }),
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
    if (p >= 0.99) return Colors.transparent;
    if (p >= 0.50) return Colors.green;
    if (p >= 0.25) return Colors.orange;
    return Colors.redAccent;
  }

  Future<void> _addActivityDialogForDomain(String domainId) async {
    final nameCtrl = TextEditingController();
    final goalCtrl = TextEditingController(text: '15');
    final unitCtrl = TextEditingController(text: 'unités');
    final targetCtrl = TextEditingController(text: '8');
    String kind = 'time';
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (context, setStateSB) => AlertDialog(
              title: const Text('Nouvelle activité / habitude'),
              content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Nom')),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Text('Type : '),
                    DropdownButton<String>(
                      value: kind,
                      items: const [
                        DropdownMenuItem(
                            value: 'time', child: Text('Temps (timer)')),
                        DropdownMenuItem(
                            value: 'habit', child: Text('Habitude (compteur)')),
                      ],
                      onChanged: (v) => setStateSB(() => kind = v ?? 'time'),
                    ),
                  ]),
                  if (kind == 'time')
                    TextField(
                        controller: goalCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Objectif (min)'))
                  else ...[
                    TextField(
                        controller: unitCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Unité (ex: verres, pompes)')),
                    TextField(
                        controller: targetCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Objectif/jour')),
                  ],
                ]),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Annuler')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Ajouter')),
              ],
            ),
          ),
        ) ??
        false;

    if (!ok) return;
    final name = nameCtrl.text.trim().isEmpty
        ? 'Nouvelle activité'
        : nameCtrl.text.trim();
    if (kind == 'time') {
      final goal = int.tryParse(goalCtrl.text.trim()) ?? 15;
      _state!.activities.add(Activity(
          domainId: domainId,
          name: name,
          type: 'time',
          goalMin: goal,
          habitTarget: 1));
    } else {
      final unit = unitCtrl.text.trim().isEmpty
          ? 'unités'
          : nameCtrl.text.trim().isEmpty
              ? 'unités'
              : unitCtrl.text.trim();
      _state!.activities.add(Activity(
          domainId: domainId,
          name: name,
          type: 'habit',
          unit: unit,
          habitTarget: 1));
    }
    await _saveAndRefresh();
  }

  String _fmtMinHM(int min) {
    final h = min ~/ 60, m = min % 60;
    return h > 0 ? "${h}h ${m}m" : "${m}m";
  }

  Widget _miniBar(double frac) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: frac.clamp(0, 1),
        minHeight: 8,
      ),
    );
  }

  Widget _miniProgressRow({required String left, required String right}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(left, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        Text(right,
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }

  void _openFocusPanel({String? domainId}) {
    final candidates = logic.buildFocusCandidates(domainId: domainId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSB) {
            // top 3
            final top = candidates.take(3).toList();

            Widget _tile(FocusItem it) {
              if (it.kind == 'goal') {
                final g = it.goal!;
                final mainP = logic.goalProgress(g);
                final weekP = logic.goalWeeklyPace(g);
                return Card(
                  margin:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceVariant
                      .withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Titre complet
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.flag, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                g.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                softWrap: true,
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: "Options objectif",
                              onSelected: (v) async {
                                if (v == 'next') {
                                  await _editNextActionDialog(context, g, setSB,
                                      initial: g.nextAction);
                                } else if (v == 'done') {
                                  logic.markGoalDone(g.id);
                                  setSB(() {
                                    candidates
                                      ..clear()
                                      ..addAll(logic.buildFocusCandidates(
                                          domainId: domainId));
                                  });
                                } else if (v == 'archive') {
                                  logic.archiveGoal(g.id);
                                  setSB(() {
                                    candidates
                                      ..clear()
                                      ..addAll(logic.buildFocusCandidates(
                                          domainId: domainId));
                                  });
                                } else if (v == 'step+1') {
                                  logic.incGoalStep(g.id, delta: 1);
                                  setSB(() {});
                                }
                              },
                              itemBuilder: (c) => const [
                                PopupMenuItem(
                                    value: 'next',
                                    child: Text(
                                        "Définir/modifier prochaine action")),
                                PopupMenuItem(
                                    value: 'done',
                                    child: Text("Marquer objectif atteint")),
                                PopupMenuItem(
                                    value: 'archive', child: Text("Archiver")),
                                PopupMenuItem(
                                    value: 'step+1', child: Text("Étape +1")),
                              ],
                              icon: const Icon(Icons.more_vert, size: 18),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // --- Prochaine action
                        Text(
                          g.nextAction?.isNotEmpty == true
                              ? "Prochaine action : ${g.nextAction}"
                              : "Définir une prochaine action…",
                          style: TextStyle(
                            fontSize: 14,
                            fontStyle: g.nextAction?.isNotEmpty == true
                                ? FontStyle.normal
                                : FontStyle.italic,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(g.nextAction?.isNotEmpty == true
                                    ? 0.9
                                    : 0.5),
                          ),
                        ),

                        if (mainP.ratio != null) ...[
                          TinyBar(
                            ratio: mainP.ratio!,
                            labelLeft: "Avancement — ${mainP.label}",
                          ),
                          const SizedBox(height: 6),
                        ],
                        TinyBar(
                          ratio: weekP.ratio,
                          labelLeft: weekP.label,
                        ),

                        const SizedBox(height: 12),

                        // --- Boutons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.snooze, size: 20),
                              tooltip: "Snoozer 30 min",
                              onPressed: () {
                                logic.snooze(g.id, minutes: 30);
                                setSB(() {
                                  candidates
                                    ..clear()
                                    ..addAll(logic.buildFocusCandidates(
                                        domainId: domainId));
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (g.nextAction?.isNotEmpty == true) {
                                  // Tu peux aussi lancer un timer ou une session ici
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            "Action lancée : ${g.nextAction}")),
                                  );
                                }
                              },
                              icon: const Icon(Icons.play_arrow),
                              label: const Text("Lancer"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                foregroundColor:
                                    Theme.of(context).colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              } else if (it.kind == 'time') {
                final activity = it.activity!;
                final now = DateTime.now();
                final done = logic.totalForRangeByActivity(
                  activity.id,
                  now.subtract(const Duration(hours: 24)),
                  now,
                );
                final goalMin = activity.goalMin;
                final p = goalMin > 0
                    ? (done.inMinutes / goalMin).clamp(0.0, 1.0)
                    : 0.0;

                final running = _state!.sessions.any(
                  (s) => s.activityId == activity.id && s.endAt == null,
                );

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      children: [
                        // Ligne 1 : titre + actions compactes
                        Row(
                          children: [
                            const Icon(Icons.schedule, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                activity.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700),
                                softWrap: false,
                              ),
                            ),
                            // Snooze 30 min
                            IconButton(
                              tooltip: "Plus tard (30 min)",
                              onPressed: () {
                                logic.snooze(activity.id, minutes: 30);
                                setSB(() {
                                  candidates
                                    ..clear()
                                    ..addAll(logic.buildFocusCandidates(
                                        domainId: domainId));
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "Suggestion reportée de 30 min")),
                                );
                              },
                              icon: const Icon(Icons.snooze, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 2),
                            // Lancer icône seule
                            IconButton.filled(
                              onPressed: () {
                                if (running) {
                                  logic.stopActive();
                                  setSB(() {}); // rafraîchit les boutons
                                } else {
                                  logic.start(activity.id);
                                  Navigator.of(context).pop();
                                }
                              },
                              icon: Icon(
                                  running ? Icons.stop : Icons.play_arrow,
                                  size: 18),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(32, 32),
                                shape: const StadiumBorder(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Ligne 2 : barre + labels
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child:
                              LinearProgressIndicator(value: p, minHeight: 15),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("${done.inMinutes}m",
                                style: const TextStyle(fontSize: 11)),
                            Text("${goalMin}m",
                                style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                final activity = it.activity!;
                final now = DateTime.now();
                final done = logic.habitValueOn(
                    activity.id, DateTime(now.year, now.month, now.day));
                final target = logic.dayQuotaFor(activity);
                final unit = activity.unit ?? '';
                final ratio =
                    target > 0 ? (done / target).clamp(0.0, 1.0) : 0.0;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      children: [
                        // Ligne 1 : titre + actions compactes
                        Row(
                          children: [
                            const Icon(Icons.checklist, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                activity.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700),
                                softWrap: false,
                              ),
                            ),
                            // Snooze 30 min
                            IconButton(
                              tooltip: "Plus tard (30 min)",
                              onPressed: () {
                                logic.snooze(activity.id, minutes: 30);
                                setSB(() {
                                  candidates
                                    ..clear()
                                    ..addAll(logic.buildFocusCandidates(
                                        domainId: domainId));
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "Suggestion reportée de 30 min")),
                                );
                              },
                              icon: const Icon(Icons.snooze, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 2),
                            // +1 rapide (tap = incrémente et reste ouvert)
                            IconButton.filled(
                              tooltip: "+1",
                              onPressed: () {
                                logic.incHabit(activity.id, 1, now);
                                setSB(
                                    () {}); // met à jour le compteur et la barre
                              },
                              icon: const Icon(Icons.add, size: 18),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(32, 32),
                                shape: const StadiumBorder(),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        // Ligne 2 : barre + labels (done / target)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                              value: ratio, minHeight: 15),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              target > 0
                                  ? "$done / $target ${unit.isNotEmpty ? unit : ''}"
                                      .trim()
                                  : "$done ${unit}".trim(),
                              style: const TextStyle(fontSize: 11),
                            ),
                            // Contrôles − / +
                            Row(
                              children: [
                                IconButton(
                                  tooltip: "-1",
                                  onPressed: () {
                                    logic.incHabit(activity.id, -1, now);
                                    setSB(() {});
                                  },
                                  icon: const Icon(Icons.remove, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: "+1",
                                  onPressed: () {
                                    logic.incHabit(activity.id, 1, now);
                                    setSB(() {});
                                  },
                                  icon: const Icon(Icons.add, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // en-tête
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          domainId == null
                              ? "Focus"
                              : "Focus — ${_state!.domains.firstWhere((d) => d.id == domainId).name}",
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        tooltip: "Proposer autre chose (30 min)",
                        onPressed: () {
                          if (candidates.isEmpty) return;
                          final first = candidates.first;

                          // Snooze selon le type
                          if (first.kind == 'goal' && first.goal != null) {
                            logic.snooze('goal:${first.goal!.id}', minutes: 30);
                          } else if (first.activity != null) {
                            logic.snooze(first.activity!.id, minutes: 30);
                          } else {
                            // rien à snoozer (sécurité)
                            return;
                          }

                          // Rebuild la liste
                          setSB(() {
                            candidates
                              ..clear()
                              ..addAll(logic.buildFocusCandidates(
                                  domainId: domainId));
                          });
                        },
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (top.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text("Tout est au vert pour l’instant ✨"),
                    )
                  else
                    Column(
                      children: [
                        // reco principale
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: _tile(top[0]),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // alternatives
                        ...top.skip(1).map((it) => Card(child: _tile(it))),
                      ],
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openQuickAdjustHabitSheet({
    required BuildContext context,
    required AppLogic logic,
    required Activity habit,
    required VoidCallback refresh,
  }) async {
    final unit = (habit.unit ?? '').isNotEmpty ? ' ${habit.unit}' : '';

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSB) {
            int todayVal() {
              final now = DateTime.now();
              final d = DateTime(now.year, now.month, now.day);
              return logic.habitValueOn(habit.id, d);
            }

            final dayQuota = logic.dayQuotaFor(habit);

            void bump(int delta) {
              final now = DateTime.now();
              final d = DateTime(now.year, now.month, now.day);
              logic.incHabit(habit.id, delta, d);
              setSB(() {}); // refresh dans le sheet
              refresh(); // refresh parent
            }

            void resetToday() {
              final now = DateTime.now();
              final d = DateTime(now.year, now.month, now.day);
              final cur = logic.habitValueOn(habit.id, d);
              if (cur > 0) {
                logic.incHabit(habit.id, -cur, d);
                setSB(() {});
                refresh();
              }
            }

            final val = todayVal();

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    habit.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Center(
                    child: Text(
                      "Aujourd’hui : $val / $dayQuota$unit",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 🌟 Les deux gros boutons centraux
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => bump(-1),
                        icon: const Icon(Icons.remove, size: 28),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text("1", style: TextStyle(fontSize: 18)),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => bump(1),
                        icon: const Icon(Icons.add, size: 28),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text("1", style: TextStyle(fontSize: 18)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 🔁 Reset + Fermer
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: resetToday,
                        icon: const Icon(Icons.restore),
                        label: const Text("Réinitialiser"),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Fermer"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  Text(
                    "Astuce : touchez l’anneau pour +1, \ndouble-touchez pour −1.",
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          Theme.of(ctx).colorScheme.onSurface.withOpacity(.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openManagementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (context, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('Gestion',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Ajouter un domaine',
                        onPressed: () async {
                          await _addDomainDialog();
                          setState(() {});
                        },
                        icon: const Icon(Icons.create_new_folder_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _state!.domains.length,
                      itemBuilder: (_, i) {
                        final d = _state!.domains[i];
                        final acts = logic.activitiesOfDomain(d.id);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(d.name,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    IconButton(
                                        onPressed: () => _renameDomainDialog(d),
                                        icon: const Icon(Icons.edit_outlined)),
                                    IconButton(
                                        onPressed: () => _deleteDomain(d),
                                        icon: const Icon(Icons.delete_outline)),
                                    IconButton(
                                      tooltip: 'Ajouter activité',
                                      onPressed: () =>
                                          _addActivityDialogForDomain(d.id),
                                      icon: const Icon(Icons.add),
                                    ),
                                  ],
                                ),
                                const Divider(),
                                if (acts.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 6),
                                    child: Text(
                                        'Aucune activité dans ce domaine.'),
                                  )
                                else
                                  ...acts.map((a) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(a.isHabit
                                            ? Icons.check_circle_outline
                                            : Icons.timer_outlined),
                                        title: Text(a.name),
                                        subtitle: a.isHabit
                                            ? Text(
                                                'Objectif: ${logic.dayQuotaFor(a)} ${a.unit ?? ''} / jour')
                                            : Text(
                                                'Objectif: ${a.goalMin} min'),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                                onPressed: () =>
                                                    _editActivityDialog(a),
                                                icon: const Icon(
                                                    Icons.edit_outlined)),
                                            IconButton(
                                                onPressed: () =>
                                                    _deleteActivity(a),
                                                icon: const Icon(
                                                    Icons.delete_outline)),
                                          ],
                                        ),
                                      )),
                              ],
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

  Future<void> _editNextActionDialog(
      BuildContext ctx, Goal g, void Function(void Function()) setSB,
      {String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? g.nextAction ?? "");
    await showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text("Prochaine action"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: "Décris l’action concrète…"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: const Text("Annuler")),
          TextButton(
            onPressed: () {
              final txt = ctrl.text.trim();
              logic.setGoalNextAction(g.id, txt.isEmpty ? null : txt);
              setSB(() {}); // refresh la feuille Focus
              Navigator.of(dCtx).pop();
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }
}
