import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/main.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:collection/collection.dart';
import 'package:productivitwo_v1/widgets/habit_tile_30d.dart'
    show NowHabit30dBar;

class TodayView extends StatefulWidget {
  final AppLogic logic;
  final AppState state;
  const TodayView({super.key, required this.logic, required this.state});

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  // Choix JOUR: aujourd’hui / demain
  late DateTime _base;
  bool _planTomorrow = false;

  // --- Pulse de validation (coche verte animée) ---
/*   final Set<String> _habitPulse = {};

  void _firePulse(String planItemId) {
    setState(() => _habitPulse.add(planItemId));
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _habitPulse.remove(planItemId));
    });
  } */

  String get _ymd {
    final d = _planTomorrow ? _base.add(const Duration(days: 1)) : _base;
    return yyyymmdd(d);
  }

  void _startupHousekeeping() {
    widget.logic.maybeCarryFromYesterday();
    widget.logic.ensureDailyHabitsPlanned();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupHousekeeping();
      widget.logic.backfillDomainIdsForPlan();
      setState(() {});
    });
    _base = DateTime.now();
  }

  bool isHabitReached(DayPlanItem it) {
    if (it.kind != PlanKind.habit || it.refId == null) return false;
    final act =
        widget.state.activities.firstWhereOrNull((a) => a.id == it.refId);
    if (act == null) return false;

    final freq = widget.logic.effectiveHabitFreq(act);
    final target = widget.logic.effectiveHabitTarget(act);

    int done;
    switch (freq) {
      case HabitFreq.daily:
        done = widget.logic.habitValueOn(act.id, DateTime.now());
        break;
      case HabitFreq.weekly:
        done = widget.logic.habitSliding(act.id, 7).done;
        break;
      case HabitFreq.monthly:
        done = widget.logic.habitSliding(act.id, 30).done;
        break;
    }
    return target > 0 && done >= target;
  }

  Widget _focusSection(AppLogic logic) {
    final acts = logic.focusToday;
    if (acts.isEmpty) return const SizedBox.shrink();

    Widget ringFor(Activity a) {
      if (a.isHabit) {
        final done = logic.activeHabitDone(a);
        final tgt = logic.activeHabitTarget(a);
        final prog = (tgt > 0) ? (done / tgt).clamp(0.0, 1.0) : 0.0;
        return MiniRing(
          progress: prog,
          center: Text("$done/$tgt",
              style:
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
        );
      } else {
        final now = DateTime.now();
        final doneMin = logic
            .totalForRangeByActivity(
                a.id, now.subtract(const Duration(hours: 24)), now)
            .inMinutes;
        final tgt = a.goalMin;
        final prog = (tgt > 0) ? (doneMin / tgt).clamp(0.0, 1.0) : 0.0;
        return MiniRing(
          progress: prog,
          center: Text("${doneMin}m",
              style:
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("🎯 Focus du jour",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ...acts.map((a) => Card(
                child: ListTile(
                  leading: ringFor(a),
                  title: Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: IconButton(
                    tooltip: "Retirer du focus",
                    onPressed: () => setState(() => logic.toggleFocus(a.id)),
                    icon: const Icon(Icons.close),
                  ),
                  // Optionnel : tap → lancer / inc / explications…
                  onTap: () {
                    if (!a.isHabit) {
                      logic.start(a.id);
                    } else {
                      // par ex. incrémenter 1 pour une routine
                      final today = DateTime.now();
                      logic.incHabit(a.id, 1, today);
                      setState(() {});
                    }
                  },
                ),
              )),
          // Ligne d’actions rapide
          Row(
            children: [
              TextButton.icon(
                onPressed: () =>
                    setState(() => logic.suggestAutoFocusForToday()),
                icon: const Icon(Icons.auto_awesome),
                label: const Text("Proposer"),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => setState(() {
                  logic.state.focusTodayIds.clear();
                  logic.onChange();
                }),
                icon: const Icon(Icons.clear_all),
                label: const Text("Vider"),
              ),
            ],
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortByDashboard = widget.logic.state.sortTodayByDashboard;

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final ymd = _ymd;
    final isTodayTab = ymd == yyyymmdd(now);

    final runningAct = widget.logic.runningActivity();
    final currentDomainId =
        (runningAct != null && (runningAct.domainId).isNotEmpty)
            ? runningAct.domainId
            : null;

    final hasRunning = isTodayTab && currentDomainId != null;

    // Mode test : hors activité, on force uniquement les non-atteints
    const forceOnlyUnderWhenNoRunning = true;

    // Reorder: on interdit en focus et quand tri dashboard activé
    final canReorder = !sortByDashboard && !hasRunning;

    // 1) Base: plan du jour affiché
    final basePlan = widget.logic.planFor(ymd).toList();

    final isEmptyHabitsToday =
        isTodayTab && basePlan.where((it) => it.kind == PlanKind.habit).isEmpty;

    List<DayPlanItem> planOrAuto() {
      if (!isEmptyHabitsToday) return basePlan;

      // construit une liste UI-only de "habits à faire"
      final habits =
          widget.logic.state.activities.where((a) => a.isHabit).toList();

      // garde seulement ceux sous seuil (selon freq)
      final under = habits.where((a) {
        final freq = widget.logic.effectiveHabitFreq(a);
        final target = widget.logic.effectiveHabitTarget(a);
        int done;
        switch (freq) {
          case HabitFreq.daily:
            done = widget.logic.habitValueOn(a.id, todayDate);
            break;
          case HabitFreq.weekly:
            done = widget.logic.habitSliding(a.id, 7).done;
            break;
          case HabitFreq.monthly:
            done = widget.logic.habitSliding(a.id, 30).done;
            break;
        }
        return target > 0 && done < target;
      });

      // transforme en DayPlanItem virtuel habit (UI-only)
      return under
          .map((a) => DayPlanItem(
                id: 'virt:${a.id}',
                kind: PlanKind.habit,
                refId: a.id,
                domainId: a.domainId,
                title: a.name,
                yyyymmdd: ymd,
                done: false,
                doneCount: 0,
                allDay: true,
                order: 1 << 30,
              ))
          .toList();
    }

    final baseOrAuto = planOrAuto();

    // 2) Focus : ne garder QUE les habits (pas d'actions, pas d'autres activités)
    // Hors focus : on garde tout
    final focusFiltered = hasRunning
        ? baseOrAuto.where((it) {
            if (it.kind != PlanKind.habit) return false;

            // ✅ domaine résolu (fallback sur l’activité si domainId vide)
            final act = (it.refId != null)
                ? widget.state.activities
                    .firstWhereOrNull((a) => a.id == it.refId)
                : null;

            final dom = (it.domainId != null && it.domainId!.isNotEmpty)
                ? it.domainId!
                : (act?.domainId ?? '');

            return dom == currentDomainId;
          }).toList()
        : baseOrAuto;

    debugPrint(
        'baseOrAuto=${baseOrAuto.length} focusFiltered=${focusFiltered.length} '
        'currentDomainId=$currentDomainId hasRunning=$hasRunning');

    // 3) Virtuels (focus seulement) : ajouter les habits du domaine courant absents du plan
/*     final extraHabits = <DayPlanItem>[];
    if (hasRunning) {
      final alreadyHabitIds = <String>{
        for (final it in focusFiltered)
          if (it.kind == PlanKind.habit && it.refId != null) it.refId!,
      };

      final habitsOfDomain = widget.logic.state.activities.where(
        (a) => a.isHabit && a.domainId == currentDomainId,
      );

      for (final a in habitsOfDomain) {
        if (alreadyHabitIds.contains(a.id)) continue;

        // Reached selon la période effective (daily/weekly/monthly)
        final freq = widget.logic.effectiveHabitFreq(a);
        final target = widget.logic.effectiveHabitTarget(a);

        int done;
        switch (freq) {
          case HabitFreq.daily:
            done = widget.logic.habitValueOn(a.id, todayDate);
            break;
          case HabitFreq.weekly:
            done = widget.logic.habitSliding(a.id, 7).done;
            break;
          case HabitFreq.monthly:
            done = widget.logic.habitSliding(a.id, 30).done;
            break;
        }

        final reached = target > 0 && done >= target;

        extraHabits.add(
          DayPlanItem(
            id: 'virt:${a.id}',
            kind: PlanKind.habit,
            refId: a.id,
            domainId: a.domainId,
            title: a.name,
            yyyymmdd: ymd,
            done: reached, // ✅ pilotera barré + coche dans ta card
            doneCount: done,
            allDay: true,
            order: 1 << 30,
          ),
        );
      }
    } */

    // 4) Merge
    //final merged = [...focusFiltered, ...extraHabits];
    final merged = focusFiltered;

    // 5) Filtre "test" hors focus : Today + pas d'activité => uniquement non atteints
    List<DayPlanItem> visible;
    if (isTodayTab && !hasRunning && forceOnlyUnderWhenNoRunning) {
      visible = merged.where((it) {
        // ✅ on garde toujours les virtuels auto-seed
        if (it.id.startsWith('virt:') || it.id.startsWith('virtAct:'))
          return true;

        if (it.kind != PlanKind.habit || it.refId == null) return true;

        final act =
            widget.state.activities.firstWhereOrNull((a) => a.id == it.refId);
        if (act == null) return true;

        final freq = widget.logic.effectiveHabitFreq(act);
        final target = widget.logic.effectiveHabitTarget(act);

        int done;
        switch (freq) {
          case HabitFreq.daily:
            done = widget.logic.habitValueOn(act.id, todayDate);
            break;
          case HabitFreq.weekly:
            done = widget.logic.habitSliding(act.id, 7).done;
            break;
          case HabitFreq.monthly:
            done = widget.logic.habitSliding(act.id, 30).done;
            break;
        }

        final reached = target > 0 && done >= target;
        return !reached;
      }).toList();
    } else {
      visible = merged;
    }

    // 6) Tri habits : sous seuil d'abord, atteints en bas (focus seulement)
    // Hors focus : tu peux laisser ton ordre existant
    List<DayPlanItem> finalItems;
    if (hasRunning) {
      final under = <DayPlanItem>[];
      final reached = <DayPlanItem>[];

      for (final it in visible) {
        // En focus visible ne contient que des habits, mais on garde robuste
        if (it.kind == PlanKind.habit) {
          (isHabitReached(it) ? reached : under).add(it);
        } else {
          under.add(it);
        }
      }
      finalItems = [...under, ...reached];
    } else {
      finalItems = visible;
    }

    // 7) Tri dashboard : on ne le fait pas en focus (sinon ça mélange ton ordre under/reached)
    const haloReachedThreshold = 0.99;
    final domainRank = widget.logic
        .computeDashboardDomainOrder(haloReachedThreshold: haloReachedThreshold)
        .rankByDomain;

    final sorted = (!hasRunning && sortByDashboard)
        ? widget.logic.viewItemsSortedByDashboard(finalItems, domainRank)
        : finalItems;

    final items = widget.logic.injectSuggestedActivities(
      items: sorted,
      ymd: ymd,
      now: now,
    );

    debugPrint('baseOrAuto=${baseOrAuto.length}');
    debugPrint('focusFiltered=${focusFiltered.length}');
    debugPrint('merged=${merged.length}');
    debugPrint('visible=${visible.length}');
    debugPrint('finalItems=${finalItems.length}');
    debugPrint('sorted=${sorted.length}');
    debugPrint('items(after inject)=${items.length}');
    if (items.isNotEmpty) {
      debugPrint(
          'first=${items.first.kind} id=${items.first.id} ref=${items.first.refId}');
    }

/* 
    debugPrint('--- DOMAIN RANKS ---');
    final sorted = widget.logic.computeDashboardDomainOrder().sortedDomains;
    for (final d in sorted) {
      debugPrint('DOMAIN ${d.name} id=${d.id} rank=${domainRank[d.id]}');
    }

    final order = widget.logic.computeDashboardDomainOrder();
    debugPrint(
        'Pomodoro domain reached=${order.haloReachedByDomain["b706..."]} score=${order.scoreByDomain["b706..."]}');
 */
/*     void dbg(DayPlanItem it) {
      final d = it.domainId;
      final r = d == null ? null : domainRank[d];
      debugPrint(
          'ITEM "${it.title}" kind=${it.kind} domain=$d rank=$r order=${it.order}');
    } */

// Exemple: log tous les items
/*     for (final it in itemsRaw) {
      dbg(it);
    } */

    final st = widget.logic.state;

    // 1️⃣ associations routines -> activités
    final assoc =
        widget.logic.routineToActivityId(widget.logic.habitAssocEvents);

    final rows = widget.logic.buildRowsGrouped(
      items: items, // List<DayPlanItem>
      st: st, // AppState
      logic: widget.logic, // ta logique
      assoc: assoc, // routine -> activité
    );

    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
            icon:
                Icon(sortByDashboard ? Icons.auto_awesome : Icons.drag_handle),
            onPressed: () {
              setState(() {
                widget.logic.setSortTodayByDashboard(!sortByDashboard);
              });
            },
          ),
          automaticallyImplyLeading: false, // pas de flèche retour
          title: Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Action!')),
                ButtonSegment(value: true, label: Text('Demain')),
              ],
              selected: {_planTomorrow},
              onSelectionChanged: (s) =>
                  setState(() => _planTomorrow = s.first),
            ),
          ),
          actions: [
            // … tes autres actions …

            IconButton(
              tooltip: 'Reporter le non-fait → Demain',
              icon: const Icon(Icons.redo),
              onPressed: () {
                setState(() {
                  widget.logic.rolloverUnfinishedToTomorrow();
                });
              },
            ),
          ]),

      // 🔁 Réorganisation par drag & drop
      body: Column(
        children: [
          // Section Focus en haut (ne prend de la place que s’il y a des items)
          _focusSection(widget.logic),

          // Ta liste réordonnable existante
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              itemCount: rows.length,
              itemBuilder: (ctx, i) {
                final row = rows[i];
                if (row is RowHeader) {
                  // header
                  return Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Text(
                      row.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.8),
                      ),
                    ),
                  );
                } else if (row is RowPlan) {
                  // ton rendu existant
                  return _todayTile(
                    ctx,
                    row.it,
                    key: ValueKey(row.id),
                    showDrag: false, // plus de reorder
                    indexForDrag: i,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          )
/*           Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              itemCount: items.length,

              // ✅ On gère les handles nous-mêmes (sinon Flutter rend toute la tile draggable)
              buildDefaultDragHandles: false,

              // ✅ Reorder seulement si autorisé
              onReorder: (oldIndex, newIndex) {
                if (!canReorder) return;
                setState(
                    () => widget.logic.reorderPlan(ymd, oldIndex, newIndex));
              },

              itemBuilder: (ctx, i) {
                final it = items[i];
                final isVirtual = it.id.startsWith('virt:');

                return _todayTile(
                  ctx,
                  it,
                  key: ValueKey(it.id),
                  showDrag: canReorder &&
                      !isVirtual, // ✅ poignée seulement si autorisé
                  indexForDrag: i, // ✅ nouveau param
                );
              },
            ),
          ), */
        ],
      ),

      floatingActionButton: _buildFab(), // ton FAB existant pour ajouter
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Map<String, String?> buildHabitToActivityMap(List<HabitAssocEvent> events) {
    final pinned = <String, String>{};
    final suggested = <String, String>{};

    for (final e in events) {
      switch (e.type) {
        case HabitAssocEventType.pinned:
          if (e.toActivityId != null) pinned[e.habitId] = e.toActivityId!;
          break;
        case HabitAssocEventType.changeSuggested:
          if (e.toActivityId != null) suggested[e.habitId] = e.toActivityId!;
          break;
      }
    }

    // pinned gagne toujours
    final out = <String, String?>{};
    for (final habitId in {...pinned.keys, ...suggested.keys}) {
      out[habitId] = pinned[habitId] ?? suggested[habitId];
    }
    return out;
  }

  Widget _domainHeader(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(t,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );

  Widget _sectionHeader(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Text(t,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
            )),
      );

  Widget _buildFab() {
    return FloatingActionButton.extended(
      onPressed: _openAddSheet,
      icon: const Icon(Icons.add),
      label: const Text('Ajouter'),
    );
  }

  DateTime _dayStart({bool tomorrow = false}) {
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    return tomorrow ? d0.add(const Duration(days: 1)) : d0;
  }

  DateTime _dayEnd({bool tomorrow = false}) =>
      _dayStart(tomorrow: tomorrow).add(const Duration(days: 1));

  Widget _todayTile(BuildContext context, DayPlanItem it,
      {required Key key, bool showDrag = true, int? indexForDrag}) {
    // Jour affiché selon l’onglet
    final now = DateTime.now();
    final viewed = _planTomorrow ? now.add(const Duration(days: 1)) : now;
    final day = DateTime(viewed.year, viewed.month, viewed.day);

    // Sommes-nous sur l'onglet "Aujourd'hui" ?
    final bool isTodayTab = !_planTomorrow;

    // Libellé dyn. "Aujourd’hui :" / "Demain :"
    final todayLabel = _planTomorrow ? 'Demain :' : 'Aujourd’hui :';

    // menu "…"
    final removeBtn = IconButton(
      icon: const Icon(Icons.close, size: 18),
      tooltip: 'Retirer de la liste du jour',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      onPressed: () {
        setState(() {
          widget.state.dayPlan.removeWhere((e) => e.id == it.id);
          widget.logic.onChange(); // persiste
        });
      },
    );

    Widget moveArrowIfAny() {
      if (!isTodayTab) return const SizedBox.shrink();

      // ✅ Actions jetables: refId null mais on veut quand même pouvoir déplacer
      final canMove = (it.kind == PlanKind.action) || (it.refId != null);
      if (!canMove) return const SizedBox.shrink();

      return IconButton(
        tooltip: 'Déplacer vers demain',
        icon: const Icon(Icons.arrow_forward, size: 20),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        visualDensity: VisualDensity.compact,
        onPressed: () {
          if (it.kind == PlanKind.action) {
            widget.logic.moveItemToTomorrowById(it.id); // ✅ nouvelle méthode
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Action déplacée vers demain')),
            );
          } else {
            widget.logic.movePlannedToTomorrowIfPresent(
              it.kind,
              it.refId!,
              addIfMissing: true,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Déplacé vers demain')),
            );
          }
          setState(() {});
        },
      );
    }

    // poignée de drag
    Widget dragHandle() {
      final enabled = showDrag && indexForDrag != null;
      final icon = Icon(
        Icons.drag_handle,
        size: 20,
        color: enabled
            ? Colors.white.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.25),
      );

      if (!enabled)
        return SizedBox(width: 32, height: 32, child: Center(child: icon));

      return ReorderableDragStartListener(
        index: indexForDrag!,
        child: SizedBox(width: 32, height: 32, child: Center(child: icon)),
      );
    }

    ReorderableDragStartListener dragHandleFor(DayPlanItem it) {
      return ReorderableDragStartListener(
        index: widget.logic
            .planFor(yyyymmdd(_planTomorrow
                ? DateTime.now().add(const Duration(days: 1))
                : DateTime.now()))
            .indexWhere((e) => e.id == it.id),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8), // au lieu de 12
          child: Icon(Icons.drag_handle, size: 20),
        ),
      );
    }

    // helpers d’affichage
    Widget buildTitle(String title) => Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        );

    Widget buildSub(String text) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        );

    Widget moveDownIfAny() {
      // Perso: je l’afficherais seulement sur l’onglet Aujourd’hui
      if (!isTodayTab) return const SizedBox.shrink();

      return IconButton(
        tooltip: 'Mettre plus tard (fin de liste)',
        icon: const Icon(Icons.arrow_downward, size: 18),
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        onPressed: () {
          final ymd = yyyymmdd(DateTime.now()); // ou basé sur viewed si tu veux
          widget.logic.movePlanItemToEnd(ymd, it.id);
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mis en fin de liste')),
          );
        },
      );
    }

    switch (it.kind) {
      // ---------------- ACTION ----------------
      case PlanKind.action:
        {
          return Card(
            key: key,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showDrag) dragHandleFor(it),

                      // Mettre plus tard (fin de liste) — si tu veux le garder pour les routines
                      IconButton(
                        icon: const Icon(Icons.arrow_downward),
                        tooltip: 'Mettre plus tard (fin de liste)',
                        onPressed: () {
                          final ymd = yyyymmdd(
                              DateTime(viewed.year, viewed.month, viewed.day));
                          widget.logic.movePlanItemToEnd(ymd, it.id);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            it.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        /*                        Checkbox(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          value: it.done,
                          onChanged: (v) {
                            if (v == null) return;

                            final removed = widget.logic
                                .toggleDonePlanItem(it.yyyymmdd, it.id, v);

                            setState(() {});

                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  it.kind == PlanKind.action
                                      ? 'Action supprimée'
                                      : 'Routine Ok',
                                ),
                                duration: const Duration(seconds: 3),
                                action: SnackBarAction(
                                  label: 'Annuler',
                                  onPressed: () {
                                    if (it.kind == PlanKind.action &&
                                        removed != null) {
                                      widget.logic.restorePlanItem(removed);
                                    } else {
                                      widget.logic.toggleDonePlanItem(
                                          it.yyyymmdd, it.id, false);
                                    }
                                    setState(() {});
                                  },
                                ),
                              ),
                            );
                          },
                        ), */
                        removeBtn,
                        moveArrowIfAny(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

      // ---------------- ACTIVITÉ (temps) ----------------
      case PlanKind.activityTime:
        {
          final now = DateTime.now();
          final dayStart = DateTime(now.year, now.month, now.day);
          final dur =
              widget.logic.totalForRangeByActivity(it.refId!, dayStart, now);

          final startBtn = FilledButton.icon(
            onPressed: () {
              widget.logic.start(it.refId!);
              setState(() {});
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Lancer'),
          );

          return Card(
            key: key,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  if (showDrag) dragHandleFor(it),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildTitle(it.title),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // "Aujourd’hui :" + valeur
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Aujourd’hui :",
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400)),
                                  buildSub(
                                    "${dur.inMinutes ~/ 60}h ${dur.inMinutes % 60}m",
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            startBtn,
                            removeBtn,
                            moveArrowIfAny(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

      // ---------------- HABITUDE ----------------
// ---------------- HABITUDE ----------------
      case PlanKind.habit:
        {
          // IMPORTANT: `day` doit déjà être le jour affiché (aujourd’hui/demain),
          // comme dans ton code actuel.

          final act =
              widget.state.activities.firstWhereOrNull((a) => a.id == it.refId);

          if (act == null) {
            return Card(
              key: key,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(it.title),
                subtitle: const Text("Activité introuvable (supprimée ?)"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    setState(() {
                      widget.state.dayPlan.removeWhere((e) => e.id == it.id);
                      widget.logic.onChange();
                    });
                  },
                ),
              ),
            );
          }

          final freq = widget.logic.effectiveHabitFreq(act);

          final dayDone = widget.logic.habitValueOn(it.refId!, day);
          final dayQuota = widget.logic.dayQuotaFor(act);

          final weekDone = widget.logic.habitSliding(it.refId!, 7).done;
          final weekTarget = widget.logic.weekTargetFrom(act);

          final monthDone = widget.logic.habitSliding(it.refId!, 30).done;
          final monthTarget = widget.logic.monthTargetFrom(act);

          int doneShown;
          int targetShown;

          switch (freq) {
            case HabitFreq.daily:
              doneShown = dayDone;
              targetShown = dayQuota;
              break;
            case HabitFreq.weekly:
              doneShown = weekDone;
              targetShown = weekTarget;
              break;
            case HabitFreq.monthly:
              doneShown = monthDone;
              targetShown = monthTarget;
              break;
          }
          final done = doneShown;
          final target = targetShown;

          String subText() => widget.logic.habitSubText(
                freq: freq,
                dayDone: dayDone,
                dayQuota: dayQuota,
                weekDone: weekDone,
                weekTarget: weekTarget,
                monthDone: monthDone,
                monthTarget: monthTarget,
                swowTodayText: true,
              );

          // UI rules:
          // - target <= 1  -> checkbox
          // - 2..10        -> ticks (cercles), auto ou manuel
          // - >= 11        -> counter (+/- + saisir)
          final isAuto = act.autoTune && !act.manualTarget;
          final isCheckbox = !isAuto && target <= 1;
          final showTicks = !isAuto && !isCheckbox && target <= 8;
          final isCounterMode = isAuto || target >= 9;
          final isManual = act.manualTarget;

          void inc(int delta) => setState(() {
                widget.logic.incHabit(it.refId!, delta, day);
              });

          Future<int?> _askInt(BuildContext context, String title) async {
            final s = await _askNumbersOnly(context, title);
            if (s == null) return null;
            return int.tryParse(s.trim());
          }

          Widget moreCompact() => SizedBox(
                width: 32,
                height: 32,
                child: Center(child: removeBtn),
              );

          Widget moveArrowIfAny() {
            if (!isTodayTab) return const SizedBox.shrink();

            // ✅ Actions jetables: refId null mais on veut quand même pouvoir déplacer
            final canMove = (it.kind == PlanKind.action) || (it.refId != null);
            if (!canMove) return const SizedBox.shrink();

            return IconButton(
              tooltip: 'Déplacer vers demain',
              icon: const Icon(Icons.arrow_forward, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (it.kind == PlanKind.action) {
                  widget.logic
                      .moveItemToTomorrowById(it.id); // ✅ nouvelle méthode
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Action déplacée vers demain')),
                  );
                } else {
                  widget.logic.movePlannedToTomorrowIfPresent(
                    it.kind,
                    it.refId!,
                    addIfMissing: true,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Déplacé vers demain')),
                  );
                }
                setState(() {});
              },
            );
          }

          Widget autoBackBtnIfManual() {
            if (!isManual) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'Repasser en mode auto',
              icon: const Icon(
                Icons.horizontal_rule,
                size: 18,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  act.manualTarget = false;
                  act.autoTune = true; // sécurité
                });
                widget.logic.onChange();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Mode auto activé'),
                    duration: Duration(milliseconds: 900),
                  ),
                );
              },
            );
          }

          Widget checkboxCompact() => Checkbox(
                value: done >= 1,
                onChanged: (v) => inc((v == true ? 1 : 0) - done),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );

          final isVirtual = it.id.startsWith('virt:');

// ✅ vrai "atteint" pour les habits réels
          final reached = target > 0 && done >= target;

// ✅ pour virtuels, on garde it.done
          final isReachedToday = isVirtual ? it.done : reached;

          return Card(
            key: key,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showDrag) dragHandle(),

                      // Mettre plus tard (fin de liste) — si tu veux le garder pour les routines
                      IconButton(
                        icon: const Icon(Icons.arrow_downward),
                        tooltip: isVirtual
                            ? 'Raccourci (non planifié)'
                            : 'Mettre plus tard (fin de liste)',
                        onPressed: isVirtual
                            ? null
                            : () {
                                final ymd = yyyymmdd(DateTime(
                                    viewed.year, viewed.month, viewed.day));
                                widget.logic.movePlanItemToEnd(ymd, it.id);
                                setState(() {});
                              },
                      ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Ligne 1 — Titre + checkbox (uniquement si target <= 1)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DefaultTextStyle.merge(
                                style: TextStyle(
                                  color: isReachedToday
                                      ? Colors.white.withValues(alpha: 0.55)
                                      : Colors.white.withValues(alpha: 0.90),
                                  decoration: isReachedToday
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(child: buildTitle(it.title)),
                                    if (isReachedToday) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: Colors.greenAccent
                                            .withValues(alpha: 0.85),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (isCheckbox) ...[
                              const SizedBox(width: 8),
                              checkboxCompact(),
                            ],
                          ],
                        ),

                        // Ligne 2 — "Aujourd’hui/Demain : X / Y" + (… + →)
                        // On la garde pour checkbox et ticks (pas pour compteur).

                        // Ligne 3 — cercles (2..10) OU compteur (>= 11)
                        if (isCounterMode) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => inc(-1),
                                visualDensity: VisualDensity.compact,
                              ),

                              Text(
                                widget.logic.habitSubText(
                                  freq: freq,
                                  dayDone: dayDone,
                                  dayQuota: dayQuota,
                                  weekDone: weekDone,
                                  weekTarget: weekTarget,
                                  monthDone: monthDone,
                                  monthTarget: monthTarget,
                                  swowTodayText: false,
                                ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => inc(1),
                                visualDensity: VisualDensity.compact,
                              ),

                              IconButton(
                                tooltip: "Saisir",
                                icon: const Icon(Icons.keyboard_alt_outlined,
                                    size: 20),
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                    width: 34, height: 34),
                                padding: EdgeInsets.zero,
                                onPressed: () async {
                                  final v = await _askInt(
                                      context, "Valeur pour aujourd'hui");
                                  if (v == null) return;
                                  final delta = v - done;
                                  if (delta != 0) {
                                    widget.logic
                                        .incHabit(it.refId!, delta, day);
                                    setState(() {});
                                  }
                                },
                              ),
                              const Spacer(),

                              // ✅ Toggle Auto/Manuel ultra compact
                              Builder(builder: (context) {
                                final isAutoMode =
                                    act.autoTune && !act.manualTarget;

                                return InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    setState(() {
                                      if (isAutoMode) {
                                        act.manualTarget =
                                            true; // passe en manuel
                                        act.autoTune =
                                            false; // garantit auto inactif
                                      } else {
                                        act.manualTarget =
                                            false; // repasse en auto
                                        act.autoTune =
                                            true; // garantit auto actif
                                      }
                                    });
                                    widget.logic.onChange();

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(isAutoMode
                                            ? "Mode manuel"
                                            : "Mode auto"),
                                        duration:
                                            const Duration(milliseconds: 900),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 4),
                                    child: Icon(
                                      isAutoMode
                                          ? Icons.trending_up
                                          : Icons.horizontal_rule,
                                      size: 16,
                                      color: isAutoMode
                                          ? Colors.cyanAccent
                                              .withValues(alpha: 0.9)
                                          : Colors.white
                                              .withValues(alpha: 0.85),
                                    ),
                                  ),
                                );
                              }),

                              if (!isVirtual) moreCompact(),
                              if (!isVirtual) moveArrowIfAny(),
                            ],
                          ),
                        ] else if (showTicks) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: isAuto
                                    ? HabitAutoTicksRow(
                                        done: doneShown,
                                        target: targetShown,
                                        onIncOne: () => inc(1),
                                        onDecOne: () => inc(-1),
                                      )
                                    : HabitTicksRow(
                                        done: doneShown,
                                        target: targetShown,
                                        onIncOne: () => inc(1),
                                        onDecOne: () => inc(-1),
                                        onOpenFull: () => showHabitChecklist(
                                          context,
                                          title: it.title,
                                          done: doneShown,
                                          target:
                                              targetShown, // ✅ ici aussi (tu avais target)
                                          onSet: (newDone) {
                                            final delta = newDone - doneShown;
                                            if (delta != 0) {
                                              widget.logic.incHabit(
                                                  it.refId!, delta, day);
                                              setState(() {});
                                            }
                                          },
                                        ),
                                      ),
                              ),

                              // ✅ bouton retour auto si on est en manuel
                              autoBackBtnIfManual(),
                              if (!isVirtual) moreCompact(),
                              if (!isVirtual) moveArrowIfAny(),
                            ],
                          ),
                        ] else if (!isCounterMode) ...[
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  subText(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  autoBackBtnIfManual(), // ✅ nouveau
                                  if (!isVirtual) moreCompact(),
                                  if (!isVirtual) moveArrowIfAny(),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
    }
  }

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1) Ajouter une action volante
              ListTile(
                leading: const Icon(Icons.check_box_outlined),
                title: const Text('Ajouter une action'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final title = await _askText(context, "Nouvelle action");
                  if ((title ?? '').trim().isNotEmpty) {
                    await widget.logic
                        .addPlanAction(ymd: _ymd, title: title!.trim());
                    if (!mounted) return;
                    setState(() {});
                  }
                },
              ),
              const Divider(),
              // 2) Ajouter une activité
              ListTile(
                leading: const Icon(Icons.timelapse),
                title: const Text('Ajouter une activité (temps)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final act = await _pickActivity(isHabit: false);
                  if (act != null) {
                    await widget.logic.addPlanActivity(
                      ymd: _ymd,
                      activityId: act.id,
                      isHabit: false,
                    );
                    if (!mounted) return;
                    setState(() {}); // synchrone, après l’await
                  }
                },
              ),
              // 2) Ajouter une routine (habitude)
              ListTile(
                leading: const Icon(Icons.task_alt),
                title: const Text('Ajouter une routine'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final act = await _pickActivity(isHabit: true);
                  if (act != null) {
                    await widget.logic.addPlanActivity(
                      ymd: _ymd,
                      activityId: act.id,
                      isHabit: true,
                    );
                    if (!mounted) return;
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

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

  Future<String?> _askNumbersOnly(
    BuildContext context,
    String title,
  ) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number, // ✅ clavier chiffres
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly, // ✅ uniquement chiffres
            ],
            onSubmitted: (_) => Navigator.of(context).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<Activity?> _pickActivity({required bool isHabit}) async {
    final acts = widget.state.activities
        .where((a) => a.isHabit == isHabit)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return await showModalBottomSheet<Activity>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        children: acts
            .map((a) => ListTile(
                  title: Text(a.name),
                  onTap: () => Navigator.pop(ctx, a),
                ))
            .toList(),
      ),
    );
  }

  void _showItemMenu(DayPlanItem it) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Supprimer de la liste'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() {
                widget.state.dayPlan.removeWhere((e) => e.id == it.id);
                widget.logic.onChange(); // persistance via callback
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> showHabitChecklist(
    BuildContext context, {
    required String title,
    required int done,
    required int target,
    required void Function(int newDone) onSet,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        int local = done;
        return StatefulBuilder(builder: (ctx, setSB) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: target,
                      itemBuilder: (_, i) {
                        final checked = i < local;
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) => setSB(() {
                            // cocher = régler "local" à max(i+1, local)
                            // décocher = régler à min(i, local)
                            local = v == true ? i + 1 : i;
                          }),
                          title: Text("Unité ${i + 1}"),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        onSet(local);
                        Navigator.pop(ctx);
                      },
                      child: const Text("Valider"),
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
}

class HabitAutoTicksRow extends StatelessWidget {
  final int done; // ex: 3
  final int target; // ex: 1 (info, pas limitant)
  final VoidCallback onIncOne;
  final VoidCallback onDecOne;

  const HabitAutoTicksRow({
    super.key,
    required this.done,
    required this.target,
    required this.onIncOne,
    required this.onDecOne,
  });

  @override
  Widget build(BuildContext context) {
    // On aligne sur HabitTicksRow : 10 ronds max en ligne
    const int show = 10;

    Widget dot(bool filled, {bool isBonus = false}) => GestureDetector(
          onTap: () => filled ? onDecOne() : onIncOne(),
          onLongPress: () {
            // boost ±5 simple (même logique que HabitTicksRow)
            for (int k = 0; k < 5; k++) {
              if (!filled) {
                onIncOne();
              } else {
                onDecOne();
              }
            }
          },
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // plein -> primary ; vide -> transparent
              color: filled ? Theme.of(context).colorScheme.primary : null,
              border: Border.all(
                color: isBonus
                    // bonus un poil plus visible (optionnel)
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.65)
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
              ),
            ),
          ),
        );

    final cappedDone = done.clamp(0, show);
    final canShowBonus = cappedDone < show; // tant qu'on n'a pas 10 pleins

    return Row(
      children: [
        // ronds validés
        for (int i = 0; i < cappedDone; i++) dot(true),

        // 1 rond "bonus" vide cliquable (+1)
        if (canShowBonus) dot(false, isBonus: true),

        // (optionnel) petit texte
        const SizedBox(width: 8),
        Text(
          "$done / $target",
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class HabitTicksRow extends StatelessWidget {
  final int done; // ex: 3
  final int target; // ex: 10
  final VoidCallback onIncOne;
  final VoidCallback onDecOne;
  final Future<void> Function()? onOpenFull; // ouvre la checklist complète

  const HabitTicksRow({
    super.key,
    required this.done,
    required this.target,
    required this.onIncOne,
    required this.onDecOne,
    this.onOpenFull,
  });

  @override
  Widget build(BuildContext context) {
    final show = target.clamp(0, 10); // max 10 ronds en ligne
    final extra = (target - show).clamp(0, 999);

    Widget dot(int i, bool filled) => GestureDetector(
          onTap: () => filled ? onDecOne() : onIncOne(),
          onLongPress: () {
            // boost ±5 simple
            for (int k = 0; k < 5; k++) {
              if (!filled)
                onIncOne();
              else
                onDecOne();
            }
          },
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? Theme.of(context).colorScheme.primary : null,
              border: Border.all(
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
              ),
            ),
          ),
        );

    return Row(
      children: [
        // ticks
        for (int i = 0; i < show; i++) dot(i, i < done),
        // +X pour les cibles longues
        if (extra > 0)
          TextButton(
            onPressed: onOpenFull,
            child: Text("+$extra"),
          ),
      ],
    );
  }
}

class NowTab extends StatefulWidget {
  final AppLogic logic;
  final AppState st;
  final List<DayPlanItem> items;
  final DateTime day;

  final List<RowItem> Function({
    required List<DayPlanItem> items,
    required AppState st,
    required AppLogic logic,
    required Map<String, String?> assoc,
  }) buildRowsGrouped;

  final VoidCallback? onGoTodo; // ✅ AJOUT

  const NowTab({
    super.key,
    required this.logic,
    required this.st,
    required this.items,
    required this.day,
    required this.buildRowsGrouped,
    this.onGoTodo, // ✅ AJOUT
  });

  @override
  State<NowTab> createState() => _NowTabState();
}

class _NowTabState extends State<NowTab> {
  String? _lockedPlanId; // 👉 gèle “ce qu’on fait maintenant”
  bool _skipDone = true; // option: sauter les items déjà “faits”
  final Set<String> _skippedIds = {};
  final Set<String> _doneTodayIds = {};

  String? _skippedYmd;

  void _ensureDay(String ymd) {
    if (_skippedYmd == null) {
      _skippedYmd = ymd;
      return;
    }
    if (_skippedYmd != ymd) {
      _skippedYmd = ymd;
      _skippedIds.clear();
      _doneTodayIds.clear();
      _lockedPlanId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ymd =
        yyyymmdd(DateTime(widget.day.year, widget.day.month, widget.day.day));
    _ensureDay(ymd);
    final assoc =
        widget.logic.routineToActivityId(widget.logic.habitAssocEvents);

    final rows = widget.buildRowsGrouped(
      items: widget.items,
      st: widget.st,
      logic: widget.logic,
      assoc: assoc,
    );

    final plans = rows.whereType<RowPlan>().toList();
    final actionable = plans.where((rp) => _isActionable(rp.it)).toList();
    debugPrint("NOW actionable=${actionable.length}");
    if (actionable.isNotEmpty) {
      debugPrint(
          "NOW first actionable kind=${actionable.first.it.kind} id=${actionable.first.it.id} done=${actionable.first.it.done}");
    }

    final next = _pickNow(rows); // <-- doit renvoyer RowPlan?

    // ✅ IMPORTANT : on ne montre “tout est fait” que si next == null
    if (next == null) {
      // si tu as des actionnables mais tous skippés -> vue "tout skippé"
      final hasActionableIgnoringSkips =
          plans.any((rp) => _isActionableIgnoringSkips(rp.it));
      if (hasActionableIgnoringSkips) {
        return _allSkippedView();
      }
      return _allDoneView(context);
    }

    // ✅ sinon on affiche la carte "Maintenant"
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _nowCard(context, next),
          if (next.it.kind == PlanKind.habit && next.it.refId != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  onPressed:
                      _canAdjust(next.it) ? () => _onDelta(next.it, -1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Expanded(
                  child: NowHabit30dBar(
                    logic: widget.logic,
                    st: widget.st,
                    habitId: next.it.refId!,
                    day: widget.day,
                  ),
                ),
                IconButton(
                  onPressed:
                      _canAdjust(next.it) ? () => _onDelta(next.it, 1) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _activitiesSuggestionForCurrent(next.it),
        ],
      ),
    );
  }

  Widget _activitiesSuggestionForCurrent(DayPlanItem it) {
    // On ne propose que si l’item actuel est une routine
    if (it.kind != PlanKind.habit) return const SizedBox.shrink();

    // Domain du plan item (déjà stocké chez toi dans DayPlanItem)
    final domId = it.domainId;
    if (domId == null) return const SizedBox.shrink();

    // Activités time du domaine
    final acts = widget.st.activities
        .where((a) => !a.isHabit && a.domainId == domId)
        .toList();

    if (acts.isEmpty) return const SizedBox.shrink();

    // (option) éviter de proposer l’activité déjà en cours
    final running = widget.logic.runningActivity();
    final filtered =
        running == null ? acts : acts.where((a) => a.id != running.id).toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    // Nom du domaine
    final domName = widget.st.domains
        .firstWhere((d) => d.id == domId,
            orElse: () => Domain(id: domId, name: "Domaine"))
        .name;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Activités • $domName",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in filtered)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      widget.logic
                          .start(a.id); // ✅ adapte le nom exact si besoin
                      setState(() {
                        // Optionnel: on peut locker l’item actuel pour rester dessus
                        // (et l’utilisateur clique ensuite "Fait" => assoc)
                      });
                    },
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(a.name),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isActionable(DayPlanItem it) {
    if (_skippedIds.contains(it.id)) return false;
    if (_doneTodayIds.contains(it.id)) return false;

    switch (it.kind) {
      case PlanKind.habit:
        {
          final habitId = it.refId;
          if (habitId == null) return false;

          final act = widget.st.activities.firstWhere((a) => a.id == habitId);

          // uniquement pour daily : on saute si quota atteint
          final freq = widget.logic.effectiveHabitFreq(act);
          if (freq == HabitFreq.daily) {
            final quota = widget.logic.dayQuotaFor(act);
            if (quota > 0) {
              final done = widget.logic.habitValueOn(habitId, widget.day);
              if (done >= quota) return false;
            }
          }

          // sinon actionnable
          return true;
        }

      case PlanKind.activityTime:
        return true;

      case PlanKind.action:
        return !it.done; // ✅ ici, done a du sens
    }
  }

  RowPlan? _pickNow(List<RowItem> rows) {
    // lock
    if (_lockedPlanId != null) {
      for (final rp in rows.whereType<RowPlan>()) {
        if (rp.it.id == _lockedPlanId && _isActionable(rp.it)) return rp;
      }
      _lockedPlanId = null;
    }

    // first actionable
    for (final rp in rows.whereType<RowPlan>()) {
      if (_isActionable(rp.it)) {
        _lockedPlanId = rp.it.id;
        return rp;
      }
    }
    return null;
  }

  bool _isActionableIgnoringSkips(DayPlanItem it) {
    if (_skipDone && it.done) return false;
    switch (it.kind) {
      case PlanKind.habit:
      case PlanKind.activityTime:
      case PlanKind.action:
        return true;
      default:
        return false;
    }
  }

  Widget _allSkippedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("😌 Tu as tout passé",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text(
                "Il reste des choses à faire, mais tu les as mises de côté.",
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _skippedIds.clear()),
              child: const Text("Réinitialiser les passes"),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: widget.onGoTodo,
              child: const Text("Voir la liste"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nowCard(BuildContext context, RowPlan rp) {
    final it = rp.it;
    final subtitle = _subtitleFor(it);
    final doneToday = widget.logic.habitValueOn(it.refId!, widget.day);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "MAINTENANT",
                    style: TextStyle(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ),
                ),
                if (_skippedIds.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      setState(() {
                        _skippedIds.clear();
                        _lockedPlanId = null;
                      });
                    },
                    child: Text(
                      "Réinitialiser (${_skippedIds.length})",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              it.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: doneToday > 0
                        ? Colors.green
                        : Theme.of(context).colorScheme.secondary,
                  ),
                  onPressed: () => _onPrimary(it),
                  child: Text(_primaryLabel(it)),
                )),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _onSkip,
                  child: const Text("Passer"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onPrimary(DayPlanItem it) {
    if (it.kind == PlanKind.habit && it.refId != null) {
      final doneToday = widget.logic.habitValueOn(it.refId!, widget.day);

      setState(() {
        // 🔒 verrouille cette routine pour aujourd’hui
        _lockedPlanId = it.id;

        // ➕ on l’ajoute aux "skipped" du jour
        // (même logique que Passer, mais intention différente)
        _skippedIds.add(it.id);
      });

      return;
    }

    // fallback pour actions / activités
  }

  String _primaryLabel(DayPlanItem it) {
    if (it.kind != PlanKind.habit || it.refId == null) {
      return "Fait";
    }

    final doneToday = widget.logic.habitValueOn(it.refId!, widget.day);

    return doneToday > 0 ? "Ok pour aujourd’hui" : "Pas aujourd’hui";
  }

  bool _canAdjust(DayPlanItem it) {
    return !_skippedIds.contains(it.id) && !_doneTodayIds.contains(it.id);
  }

  void _onDelta(DayPlanItem it, int delta) {
    if (!_canAdjust(it)) return;
    if (it.kind != PlanKind.habit || it.refId == null) return;

    widget.logic.incHabit(it.refId!, delta, widget.day);
    setState(() {}); // refresh jauge
  }

  String? _subtitleFor(DayPlanItem it) {
    // Si tu veux afficher domaine / association, tu peux.
    // On a domainId sur DayPlanItem, sinon via refId->Activity.
    final dom = it.domainId;
    if (dom == null) return null;
    final d = widget.st.domains.firstWhere(
      (x) => x.id == dom,
      orElse: () => Domain(id: dom, name: "Domaine"),
    );
    return "Domaine : ${d.name}";
  }

  void _onSkip() {
    setState(() {
      if (_lockedPlanId != null) {
        _skippedIds.add(_lockedPlanId!);
      }
      _lockedPlanId = null; // force pickNext
    });
  }

  Widget _allDoneView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("✨ Tout est fait",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              "Tu peux lancer une activité ou ajouter une routine dans l’onglet À faire.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
