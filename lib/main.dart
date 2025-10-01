import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/time_scope.dart';
import 'package:productivitwo_v1/widgets/tiny_bar.dart';
import 'package:productivitwo_v1/widgets/today_view.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/storage.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:productivitwo_v1/utils/pacing.dart';

enum _Tab { dashboard, stats, today }

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
  final String valueText;
  final double progress; // 0..1
  final double size;
  final Color? color;
  final VoidCallback? onTap;

  const GaugeRing({
    super.key,
    required this.label,
    required this.valueText,
    required this.progress,
    this.size = 140,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.primary;
    final bg = cs.surfaceContainerHighest.withValues(alpha: 0.35);

    // largeur utile pour le texte au centre
    final innerW = size * 0.74; // tu peux ajuster 0.70–0.78

    final ring = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (_, val, __) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // piste
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 10,
                  valueColor: AlwaysStoppedAnimation<Color>(bg),
                ),
              ),
              // progression
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: val,
                  strokeWidth: 10,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                  backgroundColor: Colors.transparent,
                ),
              ),
              // ----- contenu centré anti-overflow -----
              SizedBox(
                width: innerW,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // valueText s’adapte à la largeur (une seule ligne)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        valueText,
                        maxLines: 1,
                        softWrap: false,
                        overflow:
                            TextOverflow.visible, // on scale plutôt que couper
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // label : plus petit et atténué
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.7)),
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
            child: ring);
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
  int days = 7; // 7 ou 30
  bool onlyDomain = true; // Domaine sélectionné vs Tous
  String? statsDomainId; // null = Tous

  @override
  void initState() {
    super.initState();
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

// --- TEST FORCÉ (à retirer après) ---
/*     _state!.lastGoalsReview = null; // reset du garde-fou "une fois par jour"
    final changes = await logic.reviewGoals(
      lookbackDays: 1,
      neededHits: 1,
      lower: -1.0, // empêche la baisse
      upper: 0.0, // toute perf compte "au-dessus"
      high: 0.0, // active le boost
      pctStep: 0.1, // +10% du goal (gros pas pour bien voir)
      minStepMin: 5,
      maxWeeklyPct: 10.0, // enlève le cap hebdo pour ce test
    );
    debugPrint("reviewGoals FORCÉ -> ${changes.length} changements"); */
// ------------------------------------

    // Appel APRÈS setState
    final changes = await logic.reviewGoals();

    if (mounted) {
      setState(() {
        _recentGoalChanges = changes;

        // agrège les deltas des activités vers leur domaine si le domaine est autoGoal
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

      // purge auto des badges au bout de 10 minutes (optionnel)
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

  Future<void> _saveAndRefresh() async {
    setState(() {});
    await store.save(_state!);
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
        final target = int.tryParse(targetCtrl.text.trim()) ?? 1;
        _state!.activities.add(Activity(
            domainId: selectedDomainId!,
            name: name,
            type: 'habit',
            unit: unit,
            dailyTarget: target,
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
        TextEditingController(text: (a.dailyTarget ?? 1).toString());
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
        a.dailyTarget =
            int.tryParse(targetCtrl.text.trim()) ?? a.dailyTarget ?? 1;
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
                        final tgt = a.habitTarget ?? (a.dailyTarget ?? 0);
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
                                'freq=${a.habitFreq} tgt=${a.habitTarget ?? a.dailyTarget} '
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
    final (startCal, endCal, days) = _rangeForScope(now);

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

// 4) Totaux HABITUDES (global + par domaine) — reste CALENDAIRE
    final habitByDomain = logic.habitTotalsByDomain(startCal, endCal);
    final targetHabitsByDomain = {
      for (final d in _state!.domains)
        d.id: _state!.activities
            .where((a) => a.domainId == d.id && a.isHabit)
            .fold<int>(0, (sum, a) => sum + (a.dailyTarget ?? 0) * days),
    };
    final totalHabitsDone = habitByDomain.values.fold<int>(0, (a, b) => a + b);
    final totalHabitsTarget =
        targetHabitsByDomain.values.fold<int>(0, (a, b) => a + b);
    final totalHabitProgress = totalHabitsTarget == 0
        ? 0.0
        : (totalHabitsDone / totalHabitsTarget).clamp(0.0, 1.0);
    final running = _state!.sessions.any((x) => x.endAt == null);

    return Column(
      children: [
        if (running) _runningBanner(),

        // Anneaux globaux (Temps & Habitudes)
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GaugeRing(
                label: "${_scopeLabel()} — Temps",
                valueText:
                    "${_fmtHoursHM(totalHours)} / ${_fmtHoursHM(maxHours)}",
                progress: totalTimeProgress,
                color: _colorForProgress(totalTimeProgress, context),
                onTap: () => _showDomainDetail(null, startCal, endCal, days,
                    focus: 'time'),
              ),
              GaugeRing(
                label: "${_scopeLabel()} — Habitudes",
                valueText: totalHabitsTarget == 0
                    ? "0 / 0"
                    : "$totalHabitsDone / $totalHabitsTarget",
                progress: totalHabitProgress,
                color: _colorForProgress(totalHabitProgress, context),
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

                // HABITUDES (calendaires)
                final doneH = habitByDomain[d.id] ?? 0;
                final tgtH = targetHabitsByDomain[d.id] ?? 0;
                final progHabit =
                    tgtH > 0 ? (doneH / tgtH).clamp(0.0, 1.0) : 0.0;

                final agg = computeDailyPacingAggregate(logic, domainId: d.id);
                final progHab =
                    agg.target > 0 ? (agg.done / agg.target).clamp(0, 1) : 0.0;

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
                              valueText:
                                  "${_fmtHoursHM(h)} / ${_fmtHoursHM(maxHoursD)}",
                              progress: progTime,
                              size: 110,
                              color: _colorForProgress(progTime, context),
                              onTap: () => _showDomainDetail(
                                  d, startCal, endCal, days,
                                  focus: 'time')),

                          // Jauge HABITUDES : / cible cumulée sur la période
                          GaugeRing(
                            label: "Habitudes",
                            valueText: "$doneH / $tgtH",
                            progress: progHabit,
                            size: 110,
                            color: _colorForProgress(progHabit, context),
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
    final int tgt = a.dailyTarget ?? 0;
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
    void _unlockSoon(StateSetter setSB) {
      Future.delayed(const Duration(milliseconds: 1400), () {
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
  final d = logic.timeSliding(a.id, 1);   // ~jour civil (ou 24h glissant selon ton impl)
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
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),

              // Récap rapides
              Text("Aujourd’hui : ${fmtMin(d.doneMin)} / ${fmtMin(goal)}"),
              Text("Semaine (7j) : ${fmtMin(w.doneMin)} / ${fmtMin(w.targetMin)}"),
              Text("Mois (30j) : ${fmtMin(m.doneMin)} / ${fmtMin(m.targetMin)}"),
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
          final bool isGlobal = (domain == null);
          final bool isHabitsTab = (tab == 'habit');

          final base = isHabitsTab
              ? logic.listUnderCapSorted(
                  domainId: domainId,
                  habits: true,
                  onlyUnderCap: false,
                  dailyStrict: false)
              : logic.listUnderCapSorted(
                  domainId: domainId,
                  habits: false,
                  onlyUnderCap: false,
                  dailyStrict: false);

          // ---------- Split under/over ----------
          List<Activity> under, over;
          if (isHabitsTab) {
            // Habitudes : séparation via la primaire
            under = base.where((a) => !_habitReached(a)).toList();
            over = base.where(_habitReached).toList();
            // tri “sortie la plus proche” en haut
            under.sort(_cmpByExit);
            over.sort(_cmpByExit);
            // Global : on masque les atteintes (on ne montre que under)
            if (isGlobal) {
              over = const [];
            }
          } else {
            // Temps : on garde ta règle existante
            if (isGlobal) {
              under = base
                  .where((a) => !isTimeOverCap(logic, a, dailyStrict: true))
                  .toList();
              over = base
                  .where((a) => isTimeOverCap(logic, a, dailyStrict: true))
                  .toList();
            } else {
              under = base
                  .where((a) => !isTimeOverCap(logic, a, dailyStrict: false))
                  .toList();
              over = base
                  .where((a) => isTimeOverCap(logic, a, dailyStrict: false))
                  .toList();
            }
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

          // ---------- Tuiles ----------
          Widget _buildTimeTile(Activity a) {
            final now = DateTime.now();
            final done24h = logic.totalForRangeByActivity(
                a.id, DateTime(now.year, now.month, now.day), now);
            final dayRatio = a.goalMin > 0
                ? (done24h.inMinutes / a.goalMin).clamp(0.0, 1.0)
                : 0.0;

            final w = logic.timeSliding(a.id, 7);
            final m = logic.timeSliding(a.id, 30);

            return ListTile(
              onTap: () => showTimeExplainer(context, a: a, logic: logic),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              leading: MiniRing(
                progress: dayRatio,
                center: Text("${(dayRatio * 100).round()}%",
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  TinyBar(
                    ratio: m.ratio,
                    labelLeft:
                        "Mois ${fmtCompactFromMin(m.doneMin)} / ${fmtCompactFromMin(m.targetMin)}",
                  ),
                  TinyBar(
                    ratio: w.ratio,
                    labelLeft:
                        "Sem ${fmtCompactFromMin(w.doneMin)} / ${fmtCompactFromMin(w.targetMin)}",
                    padding: const EdgeInsets.only(top: 2),
                  ),
                ],
              ),
              trailing: FilledButton.icon(
                onPressed: () {
                  logic.start(a.id);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text("Start"),
              ),
            );
          }

          Widget _buildHabitTile(Activity a) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);

            // Totaux (jour/semaine/mois) + cibles déduites
            final dH = logic.habitSliding(a.id, 1);
            final wH = logic.habitSliding(a.id, 7);
            final mH = logic.habitSliding(a.id, 30);
            final quotaD = logic.dayQuotaFor(a); // cible jour (déduite)
            final tgtW = logic.weekTargetFrom(a); // cible semaine (déduite)
            final tgtM = logic.monthTargetFrom(a); // cible mois (déduite)

            final f = a.habitFreq ?? HabitFreq.monthly;
// ringRatio
            final double ringRatio = (f == HabitFreq.daily)
                ? (quotaD > 0
                    ? ((dH.done / quotaD).clamp(0.0, 1.0)).toDouble()
                    : 0.0)
                : (f == HabitFreq.weekly)
                    ? (tgtW > 0
                        ? ((wH.done / tgtW).clamp(0.0, 1.0)).toDouble()
                        : 0.0)
                    : (tgtM > 0
                        ? ((mH.done / tgtM).clamp(0.0, 1.0)).toDouble()
                        : 0.0);

            final isDayPrimary = f == HabitFreq.daily;
            final isWeekPrimary = f == HabitFreq.weekly;
            final isMonthPrimary = f == HabitFreq.monthly;

            final unit = (a.unit ?? '').isNotEmpty ? ' ${a.unit}' : '';

            return ListTile(
              onTap: () => _openHabitRationale(a),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              leading: MiniRing(
                progress: ringRatio,
                center: Text("${(ringRatio * 100).round()}%",
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  Opacity(
                    opacity: isMonthPrimary ? 1.0 : .45,
                    child: TinyBar(
                      ratio: tgtM > 0 ? (mH.done / tgtM).clamp(0, 1) : 0,
                      labelLeft: "Mois ${mH.done} / $tgtM$unit",
                    ),
                  ),
                  Opacity(
                    opacity: isWeekPrimary ? 1.0 : .45,
                    child: TinyBar(
                      ratio: tgtW > 0 ? (wH.done / tgtW).clamp(0, 1) : 0,
                      labelLeft: "Semaine ${wH.done} / $tgtW$unit",
                      padding: const EdgeInsets.only(top: 2),
                    ),
                  ),
                  if (isDayPrimary)
                    TinyBar(
                      ratio: quotaD > 0 ? (dH.done / quotaD).clamp(0, 1) : 0,
                      labelLeft: "Jour ${dH.done} / $quotaD$unit",
                      padding: const EdgeInsets.only(top: 2),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () {
                      setSB(() {
                        _lockNow();
                      });
                      logic.incHabit(a.id, -1, today);
                      setSB(() {});
                      _unlockSoon(setSB);

                      final act = logic.state.activities
                          .firstWhere((x) => x.id == a.id);
                      final tgt = effectiveTarget(act); // ← unifié
                      if ((tgt ?? 0) > 0 &&
                          logic.habitValueOn(a.id, today) >= (tgt ?? 0)) {
                        logic.movePlannedToTomorrowIfPresent(
                            PlanKind.habit, a.id,
                            addIfMissing: true);
                      }
                    },
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    onPressed: () {
                      setSB(() {
                        _lockNow();
                      });
                      logic.incHabit(a.id, 1, today);
                      setSB(() {});
                      _unlockSoon(setSB);

                      final act = logic.state.activities
                          .firstWhere((x) => x.id == a.id);
                      final tgt = effectiveTarget(act); // ← unifié
                      if ((tgt ?? 0) > 0 &&
                          logic.habitValueOn(a.id, today) >= (tgt ?? 0)) {
                        logic.movePlannedToTomorrowIfPresent(
                            PlanKind.habit, a.id,
                            addIfMissing: true);
                      }
                    },
                    icon: const Icon(Icons.add),
                  ),
                ],
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
    if (p >= 0.90) return Colors.green;
    if (p >= 0.50) return Colors.orange;
    return Colors.red;
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
                final target = activity.dailyTarget ?? 0;
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
                                                'Objectif: ${a.dailyTarget ?? 1} ${a.unit ?? ''} / jour')
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
