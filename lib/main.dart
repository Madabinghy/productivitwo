import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/time_scope.dart';
import 'package:productivitwo_v1/widgets/tiny_bar.dart';
import 'models.dart';
import 'storage.dart';
import 'app_logic.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'utils/pacing.dart';

enum _Tab { dashboard, stats }

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
    final habitDailyTarget = widget.logic.habitDailyTarget(domainId: domainId);

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

  Future<void> _runDevScan() async {
    final bumps = await logic.scanAllActivities();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Scan global terminé : $bumps objectif(s) ajusté(s)"),
        duration: const Duration(seconds: 2),
      ),
    );
    await store.save(_state!); // sauve le nouvel état
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
              orElse: () => Activity(domainId: '', name: 'deleted'));
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
            goalMin: goal));
      } else {
        final unit =
            unitCtrl.text.trim().isEmpty ? 'unités' : unitCtrl.text.trim();
        final target = int.tryParse(targetCtrl.text.trim()) ?? 1;
        _state!.activities.add(Activity(
            domainId: selectedDomainId!,
            name: name,
            type: 'habit',
            unit: unit,
            dailyTarget: target));
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
      orElse: () => Activity(domainId: '', name: 'Activité supprimée'),
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
        title: const Text('Go Get It'),
        actions: [
          // Pastille rouge si une activité tourne (facultatif si tu l’as déjà)
          if (_currentSession() != null)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child:
                  Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
            ),
          // Sélecteur Jour/Semaine/Mois (si tu l’utilises)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: DropdownButton<TimeScope>(
              value: scope,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: TimeScope.day, child: Text('Jour')),
                DropdownMenuItem(value: TimeScope.week, child: Text('Semaine')),
                DropdownMenuItem(value: TimeScope.month, child: Text('Mois')),
              ],
              onChanged: (v) => setState(() => scope = v ?? TimeScope.day),
            ),
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
          IconButton(
            tooltip: "Scan global (dev)",
            onPressed: _runDevScan,
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),

      // 👉 Bascule entre Dashboard et Stats
      body: _tab == _Tab.dashboard
          ? _buildDashboardBody(context)
          : StatsView(
              logic: logic,
              state: _state!,
              selectedDomainId: null,
            ),

      // FAB seulement sur le Dashboard
/*       floatingActionButton: _tab == _Tab.dashboard
          ? FloatingActionButton.extended(
              onPressed: _openLauncher,
              icon: const Icon(Icons.play_circle),
              label: const Text('Lancer'),
            )
          : null, */
      floatingActionButton: _tab == _Tab.dashboard ? _buildFocusFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab == _Tab.dashboard ? 0 : 1,
        onTap: (i) =>
            setState(() => _tab = i == 0 ? _Tab.dashboard : _Tab.stats),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'Stats',
          ),
        ],
      ),
    );
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
    final unitCtrl = TextEditingController();
    final targetCtrl = TextEditingController(text: "1");
    final goalCtrl = TextEditingController(text: "15");
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
                        labelText: "Unité (ex: verres, pompes)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: targetCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Objectif quotidien (nombre)"),
                  ),
                ] else ...[
                  TextField(
                    controller: goalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Objectif/jour (minutes)"),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("Annuler")),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty || selectedDomainId == null) return;
                if (isHabit) {
                  final tgt = int.tryParse(targetCtrl.text.trim()) ?? 0;
                  _state!.activities.add(Activity(
                    domainId: selectedDomainId!,
                    name: name,
                    type: 'habit',
                    unit: unitCtrl.text.trim().isEmpty
                        ? null
                        : unitCtrl.text.trim(),
                    dailyTarget: tgt,
                  ));
                } else {
                  final goal = int.tryParse(goalCtrl.text.trim()) ?? 15;
                  _state!.activities.add(Activity(
                    domainId: selectedDomainId!,
                    name: name,
                    type: 'time',
                    goalMin: goal,
                  ));
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

  void _openLauncher() {
    String? launcherDomainId =
        selectedDomainId; // point de départ = domaine courant
    final searchCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        List<Activity> _filtered() {
          final q = searchCtrl.text.trim().toLowerCase();
          Iterable<Activity> items = _state!.activities;
          if (launcherDomainId != null) {
            items = items.where((a) => a.domainId == launcherDomainId);
          }
          if (q.isNotEmpty) {
            items = items.where((a) => a.name.toLowerCase().contains(q));
          }
          final list = items.toList();
          list.sort((a, b) {
            if (a.isHabit == b.isHabit) return a.name.compareTo(b.name);
            return a.isHabit ? 1 : -1;
          });
          return list;
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSB) {
              final domains = _state!.domains;
              //final acts = _filtered();
              final acts = logic.listUnderCapSorted(
                  domainId: launcherDomainId, habits: false); // temps
              final habits = logic.listUnderCapSorted(
                  domainId: launcherDomainId, habits: true); // routines

              Widget hint(StateSetter setSB) {
                if (_launcherHintSeen) return const SizedBox.shrink();
                final cs = Theme.of(ctx).colorScheme;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant.withValues(
                        alpha: 0.6), // ok si tu gardes l’API ancienne
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "Astuce :\n• Tap activité = Start/Stop\n• Tap habitude = +1\n• Appui long = Modifier",
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _dismissLauncherHint(setSB), // <-- clé
                        child: const Text("OK"),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Titre + ajout
                  Row(
                    children: [
                      const Text('Lanceur',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Ajouter activité / habitude',
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _addActivityDialog();
                          _openLauncher(); // rouvre
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),

                  // HINT
                  hint(setSB),

                  // Chips domaines
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('Tous'),
                            selected: launcherDomainId == null,
                            onSelected: (_) =>
                                setSB(() => launcherDomainId = null),
                          ),
                        ),
                        ...domains.map((d) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(d.name),
                                selected: launcherDomainId == d.id,
                                onSelected: (_) =>
                                    setSB(() => launcherDomainId = d.id),
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Recherche
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setSB(() {}),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une activité…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Liste
                  Flexible(
                    child: acts.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Aucune activité. Ajoute-en avec le +'),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: acts.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 8),
                            itemBuilder: (_, i) {
                              final a = acts[i];
                              if (!a.isHabit) {
                                final running = _state!.sessions.any((s) =>
                                    s.activityId == a.id && s.endAt == null);
                                return ListTile(
                                  title: Text(a.name),
                                  subtitle: Text("Objectif: ${a.goalMin} min"),
                                  // tap = Start/Stop
// Activité temps — tap
                                  onTap: () {
                                    final run = _state!.sessions.any((s) =>
                                        s.activityId == a.id &&
                                        s.endAt == null);
                                    if (run) {
                                      logic.stopActive(); // ne ferme pas
                                      setSB(() {});
                                    } else {
                                      logic.start(a.id);
                                      _dismissLauncherHint(
                                          setSB); // <-- ajoute cette ligne
                                      Navigator.of(ctx)
                                          .pop(); // ferme le lanceur

                                      Navigator.of(ctx)
                                          .pop(); // ferme après Start
                                    }
                                  },

                                  // long-press = éditer
                                  onLongPress: () => _editActivityDialog(a),
                                  trailing: FilledButton.icon(
                                    onPressed: () {
                                      final run = _state!.sessions.any((s) =>
                                          s.activityId == a.id &&
                                          s.endAt == null);
                                      if (run) {
                                        logic.stopActive();
                                        setSB(() {});
                                      } else {
                                        logic.start(a.id);
                                        Navigator.of(ctx)
                                            .pop(); // ← auto-fermeture à START
                                      }
                                    },
                                    icon: Icon(running
                                        ? Icons.stop
                                        : Icons.play_arrow),
                                    label: Text(running ? 'Stop' : 'Start'),
                                  ),
                                );
                              } else {
                                final today = DateTime.now();
                                final value = logic.habitValueOn(a.id, today);
                                final target = a.dailyTarget ?? 1;
                                return ListTile(
                                  title: Text(a.name),
                                  subtitle: Text(
                                      "$target ${a.unit ?? ''} / jour • Réalisé: $value"),

                                  // Habitude — tap / tap = +1
                                  onTap: () {
                                    logic.incHabit(a.id, 1, DateTime.now());
                                    _dismissLauncherHint(setSB);
                                  },

                                  // long-press = éditer
                                  onLongPress: () => _editActivityDialog(a),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                          onPressed: () {
                                            logic.incHabit(a.id, -1, today);
                                            setSB(() {});
                                          },
                                          icon: const Icon(Icons.remove)),
                                      IconButton(
                                          onPressed: () {
                                            logic.incHabit(a.id, 1, today);
                                            setSB(() {});
                                          },
                                          icon: const Icon(Icons.add)),
                                    ],
                                  ),
                                );
                              }
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _domainPickerRow(Domain domain) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          const Text('Domaine : ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: domain.id,
              items: _state!.domains
                  .map(
                      (d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                  .toList(),
              onChanged: (v) => setState(() => selectedDomainId = v),
            ),
          ),
          IconButton(
            tooltip: 'Renommer',
            onPressed: () => _renameDomainDialog(domain),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Supprimer',
            onPressed: () => _deleteDomain(domain),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  void _showDomainDetail(
    Domain? domain,
    DateTime start,
    DateTime end,
    int days, {
    String focus = 'time', // 'time' | 'habit'
  }) {
    final domainId = domain?.id; // null => Tous domaines

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        String tab = (focus == 'habit') ? 'habit' : 'time'; // onglet courant
        final scrollCtrl = ScrollController();

        String _fmtHoursHM(double h) {
          final m = (h * 60).round();
          return "${m ~/ 60}h ${m % 60}m";
        }

        String _fmt(Duration dur) {
          final h = dur.inHours, m = dur.inMinutes.remainder(60);
          return h > 0 ? "${h}h ${m}m" : "${m}m";
        }

        // --- SUPPRIMER _activities() et _filteredItems() ---
        // et coller ces 2 helpers à la place :

        // Récupération triée par proximité de 100% (jour/sem/mois), déjà filtrée par domaine & type
        List<Activity> _itemsTime() =>
            logic.listUnderCapSorted(domainId: domainId, habits: false);

        List<Activity> _itemsHabit() =>
            logic.listUnderCapSorted(domainId: domainId, habits: true);

        return StatefulBuilder(
          builder: (ctx, setSB) {
        // APRÈS
            final items = (tab == 'habit') ? _itemsHabit() : _itemsTime();

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

            final list = ListView.builder(
              controller: scrollCtrl,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final a = items[i];
                final now = DateTime.now();
                final done = logic.totalForRangeByActivity(
                    a.id, now.subtract(const Duration(hours: 24)), now);
                final goalMin = a.goalMin;
                final prog = goalMin > 0 ? (done.inMinutes / goalMin) : 0.0;

                final dayDur = logic.totalForRangeByActivity(
                    a.id, now.subtract(const Duration(hours: 24)), now);
                final dayGoal = a.goalMin;
                final dayRatio = dayGoal > 0
                    ? (dayDur.inMinutes / dayGoal).clamp(0.0, 1.0)
                    : 0.0;

                final w = logic.timeSliding(a.id, 7);
                final m = logic.timeSliding(a.id, 30);

                Widget tile;
                if (!a.isHabit) {
                  // ---------- Activité TEMPS ----------
                  final dur = logic.totalForRangeByActivity(a.id, start, end);
                  final h = dur.inMinutes / 60.0;
                  final running = _state!.sessions
                      .any((s) => s.activityId == a.id && s.endAt == null);

                  tile = ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    leading: MiniRing(
                      progress: prog,
                      center: Text("${(prog * 100).round()}%",
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        // Mois (en haut), puis Semaine
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
                } else {
                  // ---------- Routine / HABITUDE ----------
                  final sum = logic.habitSumForRange(a.id, start, end);
                  final tgt = (a.dailyTarget ?? 0) * days;
                  final today = DateTime(now.year, now.month, now.day);

                  final d = DateTime(now.year, now.month, now.day);
                  final doneH = logic.habitValueOn(a.id, d);
                  final target = a.dailyTarget ?? 0;
                  final ratio = target > 0 ? (doneH / target) : 0.0;

                  final doneToday = logic.habitValueOn(a.id, today);
                  final targetDay = a.dailyTarget ?? 0;
                  final dayRatioH = targetDay > 0
                      ? (doneToday / targetDay).clamp(0.0, 1.0)
                      : 0.0;

                  final wH = logic.habitSliding(a.id, 7);
                  final mH = logic.habitSliding(a.id, 30);

                  tile = ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    leading: MiniRing(
                      progress: dayRatioH,
                      center: Text(targetDay > 0 ? "$doneToday" : "—",
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    // Colonne à droite :
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        TinyBar(
                          ratio: mH.ratio,
                          labelLeft:
                              "Mois ${mH.done} / ${mH.target}${(a.unit ?? '').isNotEmpty ? ' ${a.unit}' : ''}",
                        ),
                        TinyBar(
                          ratio: wH.ratio,
                          labelLeft:
                              "Semaine ${wH.done} / ${wH.target}${(a.unit ?? '').isNotEmpty ? ' ${a.unit}' : ''}",
                          padding: const EdgeInsets.only(top: 2),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            onPressed: () {
                              logic.incHabit(
                                  a.id, -1, d); // met à jour le state
                              setSB(() {}); // ← rebuild la feuille
                            },
                            icon: const Icon(Icons.remove)),
                        IconButton(
                            onPressed: () {
                              logic.incHabit(a.id, 1, d); // met à jour le state
                              setSB(() {}); // ← rebuild la feuille
                            },
                            icon: const Icon(Icons.add)),
                      ],
                    ),
                  );
                }

                // Divider manuel uniquement entre de vrais items
                return Column(
                  children: [
                    if (i == 0) const SizedBox(height: 4),
                    tile,
                    if (i < items.length - 1) const Divider(height: 8),
                  ],
                );
              },
            );

            // Corps avec padding
            final body = Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  header,
                  const SizedBox(height: 8),
                  Expanded(child: list),
                ],
              ),
            );

            // Scaffold pour afficher un FAB contextuel qui suit l’onglet
            return Scaffold(
              backgroundColor: Colors.transparent,
              body: body,
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () async {
                  final isHabit = (tab == 'habit');
                  await _createActivityDialog(
                    domainId:
                        domainId, // null => le dialog proposera un dropdown
                    isHabit: isHabit,
                  );
                  setSB(() {}); // rafraîchir la liste après création
                },
                icon: Icon(tab == 'habit' ? Icons.add_task : Icons.timelapse),
                label: Text(
                    tab == 'habit' ? "Nouvelle routine" : "Nouvelle activité"),
              ),
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.endFloat,
            );
          },
        );
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
          domainId: domainId, name: name, type: 'time', goalMin: goal));
    } else {
      final unit = unitCtrl.text.trim().isEmpty
          ? 'unités'
          : nameCtrl.text.trim().isEmpty
              ? 'unités'
              : unitCtrl.text.trim();
      final target = int.tryParse(targetCtrl.text.trim()) ?? 1;
      _state!.activities.add(Activity(
          domainId: domainId,
          name: name,
          type: 'habit',
          unit: unit,
          dailyTarget: target));
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
