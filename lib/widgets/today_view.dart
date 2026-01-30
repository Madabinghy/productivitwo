import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/main.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:collection/collection.dart';
import 'package:productivitwo_v1/widgets/habit_tile_30d.dart'
    show NowHabit30dBar;
import 'package:productivitwo_v1/widgets/tiny_bar.dart';

class TodayView extends StatefulWidget {
  final AppLogic logic;
  final AppState state;
  final void Function(String habitId)? onGoNow;
  final VoidCallback? onGoNowTab; // ✅ juste switch d’onglet
  const TodayView({
    super.key,
    required this.logic,
    required this.state,
    this.onGoNow,
    this.onGoNowTab,
  });

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  // Choix JOUR: aujourd’hui / demain
  late DateTime _base;
  bool _planTomorrow = false;
  bool _showDone = false;

  Timer? _runWatch;
  String? _lastRunningId;
  bool _showAll = true;
  bool _showShopping = true;
  bool _showCourses = false; // repli/dépli manuel

  Widget _coursesSection({
    required List<DayPlanItem> courses,
    required bool autoExpanded,
    required Activity? shoppingAct,
  }) {
    if (courses.isEmpty) return const SizedBox.shrink();

    final expanded = autoExpanded || _showCourses;

    // Map habitId -> nom de routine
    final habitsById = {
      for (final a in widget.logic.state.activities.where((x) => x.isHabit))
        a.id: a
    };

    String habitName(String? habitId) {
      if (habitId == null || habitId.isEmpty) return "Sans routine";
      return habitsById[habitId]?.name ?? "Routine";
    }

    // Group: habitId -> items
    final byHabit = <String?, List<DayPlanItem>>{};
    for (final it in courses) {
      (byHabit[it.habitId] ??= []).add(it);
    }

    // Tri interne + tri des groupes
    for (final list in byHabit.values) {
      list.sort((a, b) => a.title.compareTo(b.title));
    }
    final habitIds = byHabit.keys.toList()
      ..sort((a, b) => habitName(a).compareTo(habitName(b)));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showCourses = !_showCourses),
              onLongPress: shoppingAct == null
                  ? null
                  : () {
                      final running = widget.logic.runningActivity();
                      if (running == null || running.id != shoppingAct.id) {
                        widget.logic.start(shoppingAct.id);
                        setState(() {});
                      }
                    },
              child: Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Courses (${courses.length})",
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 8),

              // Groupes par routine
              for (final hid in habitIds) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Text(
                    "${habitName(hid)} (${byHabit[hid]!.length})",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(.75),
                    ),
                  ),
                ),
                for (final it in byHabit[hid]!)
                  _todayTile(
                    context,
                    it,
                    key: ValueKey("courses:${hid ?? "none"}:${it.id}"),
                    showDrag: false,
                    indexForDrag: 0,
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Activity? _activityById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final a in widget.state.activities) {
      if (a.id == id) return a;
    }
    return null;
  }

  Widget _actionCardContent(DayPlanItem it) {
    // Lookup activity (time) / routine (habit) / domain name
    Activity? habit;
    if (it.habitId != null && it.habitId!.isNotEmpty) {
      for (final a in widget.state.activities) {
        if (a.id == it.habitId) {
          habit = a;
          break;
        }
      }
    }

    Activity? activity;
    if (it.activityId != null && it.activityId!.isNotEmpty) {
      for (final a in widget.state.activities) {
        if (a.id == it.activityId) {
          activity = a;
          break;
        }
      }
    }

    String? domName;
    if ((it.domainId ?? '').isNotEmpty) {
      for (final d in widget.state.domains) {
        if (d.id == it.domainId) {
          domName = d.name;
          break;
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // ⬅️ Play (compact)
            SizedBox(
              width: 50,
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.play_arrow, size: 20),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: "Faire maintenant",
                  onPressed: () async {
                    await _startOrPickActivityForAction(it);
                    widget.logic.setNowFocus(it.id);
                    widget.onGoNowTab?.call();
                  },
                ),
              ),
            ),

            // ➡️ Contenu
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // TITRE
                  Text(
                    it.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 4, // ou null pour illimité
                    overflow: TextOverflow.visible, // ou TextOverflow.clip
                    softWrap: true,
                  ),

                  // Routine + pin
                  if (habit != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Routine • ${habit!.name}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.55),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => widget.onGoNow?.call(it.habitId!),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.push_pin_outlined,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Activité + X
                  if (activity != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Activité • ${activity!.name}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.55),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setState(() => it.activityId = null);
                            widget.logic.onChange();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Domaine fallback
                  if (habit == null && activity == null && domName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      "Domaine • $domName",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                    ),
                  ],

                  // Hint suppression si done
                  if (it.done) ...[
                    const SizedBox(height: 2),
                    Text(
                      "Glisser pour supprimer",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.45),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ✅ Checkbox à droite
            const SizedBox(width: 8),
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: it.done,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) {
                  final newDone = v ?? false;

                  setState(() {
                    it.done = newDone;

                    // ✅ ARCHIVAGE AUTO
                    if (newDone && it.habitId != null) {
                      widget.logic.archiveAction(it);

                      // optionnel mais logique : on enlève du "à prévoir"
                      // it.toPlan = false; // si tu l’utilises
                    }
                  });

                  widget.logic.onChange();
                },
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  void _deleteActionWithUndo(DayPlanItem it) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final idx = widget.logic.state.dayPlan.indexWhere((e) => e.id == it.id);
    if (idx < 0) return;

    final removed = widget.logic.state.dayPlan[idx];

    setState(() {
      widget.logic.state.dayPlan.removeAt(idx);
    });
    widget.logic.onChange();

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          "Action supprimée : ${removed.title}",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        action: SnackBarAction(
          label: "Annuler",
          onPressed: () {
            setState(() {
              final safeIdx = idx.clamp(0, widget.logic.state.dayPlan.length);
              widget.logic.state.dayPlan.insert(safeIdx, removed);
            });
            widget.logic.onChange();
          },
        ),
      ),
    );
  }

  Future<void> _startOrPickActivityForAction(DayPlanItem it) async {
    // 1) Récupérer / choisir l’activité
    Activity? act = _activityById(it.activityId);

    if (act == null) {
      act = await _pickActivity(isHabit: false);
      if (act == null) return;

      // associer automatiquement
      setState(() {
        it.activityId = act!.id;
        it.domainId = act.domainId;
      });
      widget.logic.onChange();
    }

    // 2) Vérifier activité en cours
    final running = widget.logic.runningActivity();

    // ✅ Aucun running (ou déjà la même) => start direct
    if (running == null || running.id == act.id) {
      widget.logic.start(act.id);
      return;
    }

    // 3) Conflit => SnackBar de confirmation (AUCUN start/stop ici)
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      // Si jamais tu n’as plus de Scaffold au-dessus, fallback : on ne fait rien
      debugPrint("No ScaffoldMessenger found (no Scaffold above?)");
      return;
    }

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          "« ${running.name}» en cours . "
          "Changer pour « ${act.name} » ?",
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        action: SnackBarAction(
          label: "Changer",
          onPressed: () {
            widget.logic.stopActive();
            widget.logic.start(act!.id);
          },
        ),
      ),
    );
  }

  Activity? _actById(String? id) {
    if (id == null) return null;
    for (final a in widget.state.activities) {
      if (a.id == id) return a;
    }
    return null;
  }

  String? _domainName(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final d in widget.state.domains) {
      if (d.id == id) return d.name;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();

    _base = DateTime.now();

    Future<Activity?> _pickActivity(BuildContext context,
        {String? domainId}) async {
      final acts = widget.logic.state.activities
          .where(
              (a) => !a.isHabit && (domainId == null || a.domainId == domainId))
          .toList();

      if (acts.isEmpty) return null;

      return showModalBottomSheet<Activity>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text("Associer à une activité",
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              for (final a in acts)
                ListTile(
                  title: Text(a.name),
                  onTap: () => Navigator.pop(ctx, a),
                ),
            ],
          ),
        ),
      );
    }

    // 1) housekeeping après build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupHousekeeping();
      widget.logic.backfillDomainIdsForPlan();
      if (mounted) setState(() {});
    });

    // 2) watcher start/stop activité => refresh "À faire"
    _lastRunningId = widget.logic.runningActivity()?.id;
    _runWatch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final cur = widget.logic.runningActivity()?.id;
      if (cur != _lastRunningId) {
        _lastRunningId = cur;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _runWatch?.cancel();
    super.dispose();
  }
  // --- Pulse de validation (coche verte animée) ---
/*   final Set<String> _habitPulse = {};

  void _firePulse(String planItemId) {
    setState(() => _habitPulse.add(planItemId));
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _habitPulse.remove(planItemId));
    });
  } */

  Widget _domainHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(.75),
        ),
      ),
    );
  }

  Widget _nowChecklistActions() {
    final habitId = widget.logic.nowHabitId;
    if (habitId == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final ymd = yyyymmdd(DateTime(now.year, now.month, now.day));
    widget.logic.ensureChecklistDay(ymd);

    final items = widget.logic.checklistForHabit(habitId);
    final checked = widget.logic.checkedTodayForHabit(habitId);
    final remaining = items.where((x) => !checked.contains(x)).toList();

    if (remaining.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Titre comme "Actions"
        Row(
          children: [
            const Expanded(
              child: Text(
                "Pour maintenant",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                widget.onGoNow?.call(habitId);
              },
              icon: const Icon(Icons.push_pin_outlined, size: 18),
              label: const Text("Aller à Maintenant"),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Liste "simple" (pas de Card)
        ...remaining.map((label) {
          return CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            value: false,
            onChanged: (v) {
              setState(() {
                widget.logic.setCheckedToday(habitId, label, v == true);
              });
            },
          );
        }),

        const SizedBox(height: 12),
      ],
    );
  }

  String get _ymd {
    final d = _planTomorrow ? _base.add(const Duration(days: 1)) : _base;
    return yyyymmdd(d);
  }

  void _startupHousekeeping() {
    widget.logic.maybeCarryFromYesterday();
    widget.logic.ensureDailyHabitsPlanned();
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
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final ymd = _ymd;
    final isTodayTab = ymd == yyyymmdd(now);

    // 1) Base: plan du jour affiché
    final basePlan = widget.logic.planFor(ymd).toList();

    final isEmptyHabitsToday =
        isTodayTab && basePlan.where((it) => it.kind == PlanKind.habit).isEmpty;

    // ✅ running / planning AVANT planOrAuto
    final running = widget.logic.runningActivity();
    final hasRunning = isTodayTab && running != null;

    final isPlanning = hasRunning && (running!.role == ActivityRole.planning);

    debugPrint(
        "RUNNING=${running?.name} role=${running?.role} isPlanning=$isPlanning hasRunning=$hasRunning dom=${running?.domainId}");

    final forceAutoHabits = isTodayTab && isPlanning;

    // --- planOrAuto utilise forceAutoHabits ---
    List<DayPlanItem> planOrAuto() {
      // ✅ En planification, on force l'ajout des "virtHabits" même si le plan n’est pas vide
      if (!isEmptyHabitsToday && !forceAutoHabits) return basePlan;

      final habits =
          widget.logic.state.activities.where((a) => a.isHabit).toList();

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

      final plannedHabitIds = basePlan
          .where((x) => x.kind == PlanKind.habit && x.refId != null)
          .map((x) => x.refId!)
          .toSet();

      final virtHabits = under
          .where((a) => !plannedHabitIds.contains(a.id))
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

      return [...basePlan, ...virtHabits];
    }

    final baseOrAuto = planOrAuto();

    final shoppingAct = widget.logic.shoppingActivity();
    final shoppingId = shoppingAct?.id;

// ✅ Source unique pour tout l’écran
    final allActions =
        baseOrAuto.where((x) => x.kind == PlanKind.action).toList();

// ✅ Dédup au cas où (safe)
    final seen = <String>{};
    allActions.removeWhere((a) => !seen.add(a.id));

    final autoExpanded =
        running != null && shoppingId != null && running.id == shoppingId;

    final domId = (hasRunning && !isPlanning) ? running.domainId : null;
    final actId = (hasRunning && !isPlanning) ? running.id : null;

// 1) DONE (non archivé) — jamais ailleurs
    final doneActions =
        allActions.where((a) => a.done && a.archived != true).toList();

// 2) OPEN POOL = actions actives (non done, non archivé)
    final openPool =
        allActions.where((a) => !a.done && a.archived != true).toList();

// 3) COURSES = subset de OPEN POOL
    final shoppingActions = (shoppingId == null)
        ? <DayPlanItem>[]
        : openPool.where((a) => a.activityId == shoppingId).toList();

    final coursesByHabitId = <String?, List<DayPlanItem>>{};
    for (final a in shoppingActions) {
      (coursesByHabitId[a.habitId] ??= []).add(a);
    }

// tri interne
    for (final list in coursesByHabitId.values) {
      list.sort((a, b) => a.title.compareTo(b.title));
    }

// 4) CONTEXTE = subset de OPEN POOL, en excluant Courses
    final byActivity = <DayPlanItem>[];
    final byDomainOnly = <DayPlanItem>[];

    if (hasRunning && !isPlanning && domId != null && domId.isNotEmpty) {
      byActivity.addAll(openPool.where((a) =>
          a.activityId == actId &&
          (shoppingId == null || a.activityId != shoppingId)));

      byDomainOnly.addAll(
          openPool.where((a) => a.activityId == null && a.domainId == domId));
    }

// 5) ACTIONS = le reste (OPEN POOL - Courses - Contexte)
    final usedIds = <String>{
      ...shoppingActions.map((e) => e.id),
      ...byActivity.map((e) => e.id),
      ...byDomainOnly.map((e) => e.id),
    };

    final actions = openPool.where((a) => !usedIds.contains(a.id)).toList();

// 6) Groupement par domaine UNIQUEMENT sur actions
    final actionsByDomain = <String?, List<DayPlanItem>>{};
    for (final a in actions) {
      (actionsByDomain[a.domainId] ??= []).add(a);
    }
    assert(() {
      final seen = <String>{};
      bool ok = true;

      void addAll(String label, Iterable<DayPlanItem> xs) {
        for (final x in xs) {
          if (!seen.add(x.id)) {
            debugPrint("DUPLICATE RENDER ($label): ${x.id} ${x.title}");
            ok = false;
          }
        }
      }

      addAll("shoppingActions", shoppingActions);
      addAll("byActivity", byActivity);
      addAll("byDomainOnly", byDomainOnly);
      addAll("actions", actions);
      addAll("doneActions", doneActions);

      return ok;
    }());

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          //_nowChecklistActions(), // ton bloc "Pour maintenant" (déjà OK)
          if (hasRunning &&
              (byActivity.isNotEmpty || byDomainOnly.isNotEmpty)) ...[
            Text(
              "Contexte • ${running!.name}",
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (byActivity.isNotEmpty) ...[
              Text(
                "Liées à l’activité",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(.7),
                ),
              ),
              const SizedBox(height: 6),
              ...byActivity.map((it) => _todayTile(context, it,
                  key: ValueKey('context:${it.id}'),
                  showDrag: false,
                  indexForDrag: 0)),
              const SizedBox(height: 12),
            ],
            if (byDomainOnly.isNotEmpty) ...[
              Text(
                "Dans le domaine",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(.7),
                ),
              ),
              const SizedBox(height: 6),
              ...byDomainOnly.map((it) => _todayTile(context, it,
                  key: ValueKey('domaines:${it.id}'),
                  showDrag: false,
                  indexForDrag: 0)),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 12),
          _coursesSection(
            courses: shoppingActions,
            autoExpanded: autoExpanded,
            shoppingAct: shoppingAct,
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Actions",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(_showAll ? "Masquer" : "Voir tout"),
              ),
            ],
          ),

          if (_showAll) ...[
            const SizedBox(height: 8),

            // Domaine “Sans domaine” d’abord si présent
            if ((actionsByDomain[null] ?? const []).isNotEmpty ||
                (actionsByDomain[''] ?? const []).isNotEmpty) ...[
              _domainHeader("Sans domaine"),
              ...[
                ...(actionsByDomain[null] ?? const []),
                ...(actionsByDomain[''] ?? const []),
              ].map((it) => _todayTile(
                    context,
                    it,
                    key: ValueKey('sans_domaines:${it.id}'),
                    showDrag: false,
                    indexForDrag: 0,
                  )),
              const SizedBox(height: 12),
            ],

            // Puis chaque domaine connu
            for (final d in widget.logic.state.domains) ...[
              if ((actionsByDomain[d.id] ?? const []).isNotEmpty) ...[
                _domainHeader(d.name),
                ...(actionsByDomain[d.id]!).map((it) => _todayTile(
                      context,
                      it,
                      key: ValueKey('domain${d.id}:${it.id}'),
                      showDrag: false,
                      indexForDrag: 0,
                    )),
                const SizedBox(height: 12),
              ],
            ],

            // Si vraiment aucune action (dans otherActions)
            if (actions.isEmpty) ...[
              Text(
                "Aucune action pour l’instant.",
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(.7),
                ),
              ),
            ],
          ],
          if (doneActions.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _showDone = !_showDone),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Faits (${doneActions.length})",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.75),
                        ),
                      ),
                    ),
                    Icon(
                      _showDone ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ],
                ),
              ),
            ),
            if (_showDone) ...[
              ...doneActions.map((it) {
                // tu peux réutiliser ton Dismissible + _actionCardContent
                final content = _actionCardContent(it);
                return Dismissible(
                  key: ValueKey("done:${it.id}"),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    color: Colors.red.withOpacity(0.15),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                  onDismissed: (_) => _deleteActionWithUndo(it),
                  child: Opacity(opacity: 0.55, child: content),
                );
              }),
            ],
          ],
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
    final rootKey = key;

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
          final habitName = (it.habitId == null)
              ? null
              : widget.state.activities
                  .firstWhere(
                    (a) => a.id == it.habitId,
                    orElse: () => Activity(
                      id: it.habitId!,
                      name: "Routine",
                      domainId: it.domainId ?? "",
                      type: 'habit',
                    ),
                  )
                  .name;

          final domainName = (it.domainId == null)
              ? null
              : widget.state.domains
                  .firstWhere(
                    (d) => d.id == it.domainId,
                    orElse: () => Domain(id: it.domainId!, name: "Domaine"),
                  )
                  .name;

          final activityName = (it.activityId == null)
              ? null
              : widget.state.activities
                  .firstWhere((a) => a.id == it.activityId,
                      orElse: () => Activity(domainId: '', name: 'Activité'))
                  .name;

          final habit = _actById(it.habitId);
          final activity = _actById(it.activityId);
          final domName = _domainName(it.domainId);

          final content = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => it.done = !it.done);
              widget.logic.onChange();
            },
            child: _actionCardContent(it),
          );

          return Dismissible(
            key: rootKey, // ✅ utilise la key "context:...", "courses:...", etc.
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              color: Colors.red.withOpacity(0.15),
              child: const Icon(Icons.delete, color: Colors.red),
            ),
            onDismissed: (_) => _deleteActionWithUndo(it),
            child: content,
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
                title: Text(
                  it.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  maxLines: 4, // ou null pour illimité
                  overflow: TextOverflow.visible, // ou TextOverflow.clip
                  softWrap: true,
                ),
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

  Future<String?> _pickDomainId(BuildContext context) async {
    final domains = widget.logic.state.domains;

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
                leading: const Icon(Icons.add_task),
                title: const Text('Ajouter une action (GTD)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final title = await _askText(context, "Nouvelle action");
                  final t = (title ?? '').trim();
                  if (t.isEmpty) return;

                  // ✅ contexte = activité en cours sinon picker domaine
                  final running = widget.logic.runningActivity();
                  String? domainId;
                  String? activityId;

                  if (running != null && running.domainId.isNotEmpty) {
                    domainId = running.domainId;
                    activityId = running.id;
                  } else {
                    domainId = await _pickDomainId(context);
                    if (domainId == null) return;
                  }

                  await widget.logic.addPlanAction(
                    ymd: _ymd,
                    title: t,
                    domainId: domainId,
                    activityId: activityId,
                    habitId: null, // ✅ important
                  );

                  if (!mounted) return;
                  setState(() {});
                },
              ),

              if (widget.logic.nowHabitId != null)
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: const Text('Ajouter à la routine actuelle'),
                  subtitle: Text(widget.logic.state.activities
                      .firstWhere((a) => a.id == widget.logic.nowHabitId!)
                      .name),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final title =
                        await _askText(context, "Action pour la routine");
                    final t = (title ?? '').trim();
                    if (t.isEmpty) return;

                    final habitId = widget.logic.nowHabitId!;
                    final habitAct = widget.logic.state.activities
                        .firstWhere((a) => a.id == habitId);

                    await widget.logic.addPlanAction(
                      ymd: _ymd,
                      title: t,
                      domainId: habitAct.domainId,
                      activityId: null,
                      habitId: habitId, // ✅ explicite
                    );

                    if (!mounted) return;
                    setState(() {});
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
  final Map<String, Set<String>> _checkedChecklistByPlan = {};
  bool _showArchives = false;
  bool _showGlobalArchives = false;

  String? _skippedYmd;

  List<String> checklistForHabit(String habitName) {
    switch (habitName.toLowerCase()) {
      case 'Prendre un bain de mer':
        return ['Lait', 'Fruits', 'Légumes'];
      case 'soin':
        return ['Douche', 'Dents', 'Peau'];
      default:
        return ['Courses', 'Dents', 'Peau'];
    }
  }

  Widget _nowActionCard(BuildContext context, DayPlanItem it) {
    // Subtitle sympa (domaine / activité)
    String? subtitle;

    final domId = it.domainId;
    if (domId != null && domId.isNotEmpty) {
      final dom = widget.st.domains.firstWhere(
        (d) => d.id == domId,
        orElse: () => Domain(id: domId, name: "Domaine"),
      );
      subtitle = "Domaine • ${dom.name}";
    }

    if (it.activityId != null) {
      final act = widget.st.activities.firstWhere(
        (a) => a.id == it.activityId,
        orElse: () =>
            Activity(domainId: domId ?? '', name: "Activité", type: 'time'),
      );
      subtitle = (subtitle == null)
          ? "Activité • ${act.name}"
          : "$subtitle  ·  Activité • ${act.name}";
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
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
                // Petit bouton pour quitter le focus
                TextButton(
                  onPressed: () {
                    setState(() {
                      it.isNowFocus = false;
                    });
                    widget.logic.onChange();
                  },
                  child: const Text("Retour"),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Titre action
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

            // Boutons
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        it.done = true; // ✅ terminé
                        it.isNowFocus = false; // ✅ libère le focus
                      });
                      widget.logic.onChange();
                    },
                    child: const Text("Fait"),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      it.isNowFocus =
                          false; // ✅ on sort du focus sans marquer fait
                    });
                    widget.logic.onChange();
                  },
                  child: const Text("Passer"),
                ),
              ],
            ),
          ],
        ),
      ),
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

  void _applyForcedHabitIfAny(List<RowItem> rows) {
    final forced = widget.logic.forcedNowHabitId;
    if (forced == null) return;

    RowPlan? match;
    for (final r in rows.whereType<RowPlan>()) {
      if (r.it.kind == PlanKind.habit && r.it.refId == forced) {
        match = r;
        break;
      }
    }

    if (match == null) {
      widget.logic.forcedNowHabitId = null;
      return;
    }

    _skippedIds.remove(match.it.id);
    _doneTodayIds.remove(match.it.id);
    _lockedPlanId = match.it.id;

    widget.logic.forcedNowHabitId = null;
  }

  Widget _routineChecklist(DayPlanItem it) {
    if (it.kind != PlanKind.habit || it.refId == null) {
      return const SizedBox.shrink();
    }

    final habitId = it.refId!;

    // Activity (habit) + freq
    final act = widget.st.activities.firstWhere((a) => a.id == habitId);
    final freq = widget.logic.effectiveHabitFreq(act);

    String scopeLabel() {
      switch (freq) {
        case HabitFreq.daily:
          return "Aujourd’hui";
        case HabitFreq.weekly:
          return "Cette semaine";
        case HabitFreq.monthly:
          return "Ce mois-ci";
      }
    }

    final items = widget.logic.checklistForHabit(habitId);

    // ✅ coches persistées par période (daily/weekly/monthly)
    final doneSet = widget.logic.checklistDoneSet(habitId, widget.day);

    final total = items.length;
    final checkedCount = doneSet.length.clamp(0, total);
    final ratio = total == 0 ? 0.0 : checkedCount / total;

    Future<bool> _confirmReset() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Réinitialiser la checklist ?"),
          content: Text(
            "Cela efface les coches pour : ${scopeLabel().toLowerCase()}.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Réinitialiser"),
            ),
          ],
        ),
      );
      return ok == true;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Checklist • ${scopeLabel()}",
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                if (doneSet.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      final ok = await _confirmReset();
                      if (!ok) return;
                      widget.logic.clearChecklistForPeriod(habitId, widget.day);
                      setState(() {});
                    },
                    child: const Text("Réinitialiser"),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (items.isNotEmpty) ...[
              TinyBar(
                ratio: ratio,
                labelLeft: "${scopeLabel()} : $checkedCount / $total",
                padding: const EdgeInsets.only(top: 6, bottom: 6),
              ),
            ],
            if (items.isEmpty)
              Text(
                "Aucun item. Appuie sur + pour en ajouter.",
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              )
            else
              for (int i = 0; i < items.length; i++)
                _checklistRow(
                  habitId: habitId,
                  index: i,
                  label: items[i],
                  doneSet: doneSet,
                ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: "Ajouter un item",
                onPressed: () async {
                  final txt = await _promptText(title: "Ajouter un item");
                  if (txt == null || txt.trim().isEmpty) return;
                  widget.logic.addChecklistItem(habitId, txt.trim());
                  setState(() {});
                },
                icon: const Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checklistRow({
    required String habitId,
    required int index,
    required String label,
    required Set<int> doneSet,
  }) {
    final isChecked = doneSet.contains(index);

    return Row(
      children: [
        Checkbox(
          value: isChecked,
          onChanged: (_) {
            widget.logic.toggleChecklistItem(habitId, widget.day, index);
            setState(() {});
          },
        ),
        Expanded(
          child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          tooltip: "Renommer",
          onPressed: () async {
            final txt = await _promptText(title: "Renommer", initial: label);
            if (txt == null || txt.isEmpty) return;

            // Renommer ne change PAS l'index -> les coches restent OK
            widget.logic.renameChecklistItem(habitId, index, txt);
            setState(() {});
          },
          icon: const Icon(Icons.edit),
        ),
        IconButton(
          tooltip: "Supprimer",
          onPressed: () {
            // ⚠️ suppression d'item = décalage d'index -> il faut réaligner les coches
            widget.logic
                .removeChecklistItemAndFixDone(habitId, widget.day, index);
            setState(() {});
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  void _persistNowSets() {
    final ymd = _skippedYmd;
    if (ymd == null) return;

    widget.logic.setNowSkipped(ymd, _skippedIds);
    widget.logic.setNowDone(ymd, _doneTodayIds);
  }

  void _loadPersistedForDay(String ymd) {
    _skippedIds
      ..clear()
      ..addAll(widget.logic.nowSkippedSet(ymd));

    _doneTodayIds
      ..clear()
      ..addAll(widget.logic.nowDoneSet(ymd));
  }

  void _ensureDay(String ymd) {
    if (_skippedYmd == null) {
      _skippedYmd = ymd;
      _loadPersistedForDay(ymd);
      return;
    }
    if (_skippedYmd != ymd) {
      _skippedYmd = ymd;
      _loadPersistedForDay(ymd);
      _lockedPlanId = null;
    }
  }

  List<DayPlanItem> _archivedForHabit(DayPlanItem it) {
    final habitId = it.refId;
    if (habitId == null) return const [];

    final list = widget.st.dayPlan.where((a) {
      if (a.kind != PlanKind.action) return false;
      if (a.habitId != habitId) return false;
      return a.archived == true;
    }).toList();

    list.sort((a, b) => a.title.compareTo(b.title));
    return list;
  }

  Widget _archivesSection(DayPlanItem it) {
    final items = _archivedForHabit(it);
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _showArchives = !_showArchives),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Archives (${items.length})",
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _showArchives ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
            if (_showArchives) ...[
              const SizedBox(height: 8),
              for (final a in items)
                Row(
                  children: [
                    const Icon(Icons.archive_outlined, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _reactivateArchivedAction(a),
                      child: const Text("Activer"),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _reactivateArchivedAction(DayPlanItem a) {
    setState(() {
      a.archived = false;
      a.done = false;
      _showGlobalArchives = false;
      _showArchives = false;
    });
    widget.logic.onChange();
  }

  List<DayPlanItem> _archivedGlobal() {
    final list = widget.st.dayPlan.where((a) {
      if (a.kind != PlanKind.action) return false;
      if (a.archived != true) return false;
      return a.habitId == null; // ✅ global
    }).toList();

    list.sort((a, b) => a.title.compareTo(b.title));
    return list;
  }

  Widget _archivesGlobalSection() {
    final items = _archivedGlobal();
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () =>
                  setState(() => _showGlobalArchives = !_showGlobalArchives),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Archives globales (${items.length})",
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _showGlobalArchives ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
            if (_showGlobalArchives) ...[
              const SizedBox(height: 8),
              for (final a in items)
                Row(
                  children: [
                    const Icon(Icons.history, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _reactivateArchivedAction(a),
                      child: const Text("Activer"),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<DayPlanItem> _actionsToPlanForHabit(DayPlanItem it) {
    final habitId = it.refId;
    if (habitId == null) return const [];

    final list = widget.st.dayPlan.where((a) {
      if (a.kind != PlanKind.action) return false;
      if (a.done) return false;
      return a.habitId == habitId; // ✅ liées à la routine, toutes dates
    }).toList();

    // tri : les plus anciennes d'abord, puis ordre
    list.sort((a, b) {
      final c = a.yyyymmdd.compareTo(b.yyyymmdd);
      if (c != 0) return c;
      return a.order.compareTo(b.order);
    });

    return list;
  }

  Widget _toPlanSection(DayPlanItem it) {
    final habitId = it.refId;
    if (habitId == null) return const SizedBox.shrink();

    final actions = _actionsToPlanForHabit(it);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "À prévoir",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 6),
            if (actions.isEmpty)
              Text(
                "Rien à prévoir pour l’instant.",
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              )
            else
              for (final a in actions)
                Row(
                  children: [
                    const Icon(Icons.push_pin_outlined, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: "Marquer fait",
                      icon: const Icon(Icons.check, size: 18),
                      onPressed: () {
                        setState(() {
                          a.done = true;

                          // ✅ ARCHIVAGE AUTO si l’action appartient à une routine (donc "à prévoir")
                          if (a.habitId != null) {
                            a.archived = true;
                          }
                        });

                        widget.logic.onChange();
                      },
                    ),
                  ],
                ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: "Ajouter à prévoir",
                icon: const Icon(Icons.add),
                onPressed: () async {
                  final txt = await _promptText(title: "Ajouter à prévoir");
                  if (txt == null || txt.trim().isEmpty) return;

                  final habitAct = widget.st.activities.firstWhere(
                    (a) => a.id == habitId,
                    orElse: () => Activity(
                      domainId: it.domainId ?? "",
                      name: "Routine",
                      type: 'habit',
                    ),
                  );

                  await widget.logic.addToPlanAction(
                    ymd: yyyymmdd(DateTime(
                        widget.day.year, widget.day.month, widget.day.day)),
                    title: txt.trim(),
                    habitId: habitId, // ✅ liée à la routine
                    domainId: habitAct.domainId, // ✅ domaine
                  );

                  if (!mounted) return;
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _askInt(BuildContext context, String title,
      {String? initial}) async {
    final s =
        await _promptText(title: title, initial: initial ?? ""); // tu l'as déjà
    if (s == null) return null;
    return int.tryParse(s.trim());
  }

  String freqLabelForActivity(Activity act) {
    final f = widget.logic.effectiveHabitFreq(act);
    return freqLabel(f);
  }

  String freqLabel(HabitFreq f) {
    switch (f) {
      case HabitFreq.daily:
        return "jour";
      case HabitFreq.weekly:
        return "semaine";
      case HabitFreq.monthly:
        return "mois";
    }
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

    widget.logic.onChange();

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

  Future<void> _openHabitSettings(Activity act) async {
    final res = await showModalBottomSheet<_HabitSettingsResult>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        HabitFreq freq = act.habitFreq ?? HabitFreq.daily;
        int target = (act.habitTarget ?? 1);
        bool isAuto = act.autoTune && !act.manualTarget;

        // garde-fous
        if (target <= 0) target = 1;

        return StatefulBuilder(
          builder: (ctx, setSB) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _renameRoutine(act),
                  child: Text(
                    act.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ---- Auto / Manuel
                Row(
                  children: [
                    const Text("Mode",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    ChoiceChip(
                      label: const Text("Auto"),
                      selected: isAuto,
                      onSelected: (_) => setSB(() => isAuto = true),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text("Manuel"),
                      selected: !isAuto,
                      onSelected: (_) => setSB(() => isAuto = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ---- Fréquence
                Row(
                  children: [
                    const Text("Fréquence",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    DropdownButton<HabitFreq>(
                      value: freq,
                      items: HabitFreq.values
                          .map((f) => DropdownMenuItem(
                                value: f,
                                child: Text(freqLabel(f)),
                              ))
                          .toList(),
                      onChanged: (v) => setSB(() {
                        if (v == null) return;
                        freq = v;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ---- Cible
                Row(
                  children: [
                    const Text("Cible",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      onPressed: () =>
                          setSB(() => target = (target - 1).clamp(1, 999)),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text("$target",
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      onPressed: () =>
                          setSB(() => target = (target + 1).clamp(1, 999)),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(
                          ctx,
                          _HabitSettingsResult(
                              freq: freq, target: target, isAuto: isAuto),
                        ),
                        child: const Text("Enregistrer"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (res == null) return;

    setState(() {
      // fréquence + cible
      act.habitFreq = res.freq;
      act.habitTarget = res.target;

      // mode auto/manuel
      if (res.isAuto) {
        act.manualTarget = false;
        act.autoTune = true;
      } else {
        act.autoTune = false;
        act.manualTarget = true;
        if (act.habitTarget == null || act.habitTarget! <= 0)
          act.habitTarget = 1;
      }
    });

    widget.logic.onChange();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "Réglages enregistrés : ${freqLabel(res.freq)} • cible ${res.target}"),
          duration: const Duration(milliseconds: 2000),
        ),
      );
    });
  }

  Widget autoManualBadge(
      {required Activity act,
      required VoidCallback onToggle,
      required VoidCallback onLongPress}) {
    final isAuto = act.autoTune && !act.manualTarget;

    final color = isAuto
        ? Colors.cyanAccent.withOpacity(0.85)
        : Colors.white.withOpacity(0.75);

    final bg = isAuto
        ? Colors.cyanAccent.withOpacity(0.15)
        : Colors.white.withOpacity(0.08);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onToggle,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAuto ? Icons.trending_up : Icons.horizontal_rule,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              isAuto ? "A" : "M",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
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

    _applyForcedHabitIfAny(rows);

    final plans = rows.whereType<RowPlan>().toList();
    final actionable = plans.where((rp) => _isActionable(rp.it)).toList();
    debugPrint("NOW actionable=${actionable.length}");
    if (actionable.isNotEmpty) {
      debugPrint(
          "NOW first actionable kind=${actionable.first.it.kind} id=${actionable.first.it.id} done=${actionable.first.it.done}");
    }

// ✅ 1) Si une action a été "envoyée vers Maintenant", elle est prioritaire
    DayPlanItem? focusedAction;
    for (final x in widget.items) {
      if (x.kind == PlanKind.action && x.isNowFocus == true && !x.done) {
        focusedAction = x;
        break;
      }
    }

    if (focusedAction != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: _nowActionCard(context, focusedAction),
      );
    }

    final next = _pickNow(rows); // <-- doit renvoyer RowPlan?

    if (next != null &&
        next.it.kind == PlanKind.habit &&
        next.it.refId != null) {
      final ymd =
          yyyymmdd(DateTime(widget.day.year, widget.day.month, widget.day.day));
      widget.logic.ensureChecklistDay(ymd);
      widget.logic.nowHabitId = next.it.refId!;
    }

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

    final habitId = next.it.refId;
    if (habitId == null) return _allDoneView(context);
    ; // sécurité

    final act = widget.st.activities.firstWhere(
      (a) => a.id == habitId,
    );

    // ✅ sinon on affiche la carte "Maintenant"
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          16, 16, 16, 120), // 👈 120 pour éviter l’overflow avec la bottom bar
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
                autoManualBadge(
                  act: act,
                  onLongPress: () async {
                    await _openHabitSettings(act);
                  },
                  onToggle: () {
                    setState(() {
                      final isAuto = act.autoTune && !act.manualTarget;

                      if (isAuto) {
                        // ➜ passage en MANUEL
                        act.autoTune = false;
                        act.manualTarget = true;

                        // ✅ garde-fou: en manuel, target >= 1
                        if (act.habitTarget == null || act.habitTarget! <= 0) {
                          act.habitTarget = 1;
                        }
                      } else {
                        // ➜ retour en AUTO
                        act.manualTarget = false;
                        act.autoTune = true;
                      }
                    });

                    widget.logic.onChange();

                    final isAutoNow = act.autoTune && !act.manualTarget;
                    final msg = isAutoNow
                        ? "Mode auto : la cible s’ajuste selon vos saisies"
                        : "Mode manuel : cible fixe — appui long pour modifier";

                    // ✅ safe: pas pendant build
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          duration: const Duration(milliseconds: 2500),
                        ),
                      );
                    });
                  },
                ),
              ],
            ),
          ],
          if (next.it.kind == PlanKind.habit) ...[
            const SizedBox(height: 10),
            _routineChecklist(next.it),
          ],
          const SizedBox(height: 12),
          _activitiesSuggestionForCurrent(next.it),
          if (next.it.kind == PlanKind.habit) ...[
            const SizedBox(height: 10),
            _toPlanSection(next.it),
            const SizedBox(height: 10),
            _archivesSection(next.it),
            const SizedBox(height: 10),
            _archivesGlobalSection(),
          ],
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
    if (it.kind != PlanKind.habit) return false;
    if (_skippedIds.contains(it.id)) return false;
    if (_doneTodayIds.contains(it.id)) return false;

    // refId obligatoire
    if (it.refId == null) return false;

    return true;
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
    if (_doneTodayIds.contains(it.id)) return false;
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
    final doneToday = (it.kind == PlanKind.habit && it.refId != null)
        ? widget.logic.habitValueOn(it.refId!, widget.day)
        : 0;

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
                      _persistNowSets();
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
    if (it.kind == PlanKind.habit) {
      setState(() {
        _doneTodayIds.add(it.id);
        _lockedPlanId = null;
      });
      _persistNowSets();
    }
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
      if (_lockedPlanId != null) _skippedIds.add(_lockedPlanId!);
      _lockedPlanId = null;
    });
    _persistNowSets();
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

class _HabitSettingsResult {
  final HabitFreq freq;
  final int target;
  final bool isAuto;
  const _HabitSettingsResult({
    required this.freq,
    required this.target,
    required this.isAuto,
  });
}
