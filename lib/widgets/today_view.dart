import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/main.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:collection/collection.dart';

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
  final Set<String> _habitPulse = {};

  void _firePulse(String planItemId) {
    setState(() => _habitPulse.add(planItemId));
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _habitPulse.remove(planItemId));
    });
  }

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
    //_planTomorrow = false; //Forcer le tab à aujourd'hui
    // Décaler la maintenance après le 1er frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupHousekeeping(); // -> maybeCarryFromYesterday + ensureDailyHabitsPlanned
    });

    _base = DateTime.now();
    //if (_base.hour >= 22) _planTomorrow = true;
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
    final ymd = _ymd;
    final isTodayTab = ymd == yyyymmdd(DateTime.now());

    final items = widget.logic.planFor(ymd).where((it) {
      if (!isTodayTab) return true; // Demain : on montre tout

      // Aujourd’hui : on cache uniquement les routines clôturées via OK
      final isRoutine = it.kind != PlanKind.action;
      if (isRoutine && it.done) return false;

      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
          automaticallyImplyLeading: false, // pas de flèche retour
          title: Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Aujourd’hui')),
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
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              itemCount: items.length,
              onReorder: (oldIndex, newIndex) {
                setState(
                    () => widget.logic.reorderPlan(ymd, oldIndex, newIndex));
              },
              itemBuilder: (ctx, i) {
                final it = items[i];
                return _todayTile(ctx, it, key: ValueKey(it.id));
              },
            ),
          ),
        ],
      ),

      floatingActionButton: _buildFab(), // ton FAB existant pour ajouter
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

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

  Widget _todayTile(BuildContext context, DayPlanItem it, {required Key key}) {
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

    // poignée de drag
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
                      dragHandleFor(it),

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
                        Checkbox(
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
                        ),
                        removeBtn,
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

              // Déplace l'activité planifiée d'aujourd'hui vers demain (comme les routines)
              widget.logic.movePlannedToTomorrowIfPresent(
                PlanKind.activityTime,
                it.refId!,
                addIfMissing:
                    false, // true si tu veux forcer l'ajout demain même si pas planifiée
              );

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
                  dragHandleFor(it),
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

          final freq = act.habitFreq ?? HabitFreq.monthly;

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
              );

          // UI rules:
          // - target <= 1  -> checkbox
          // - 2..10        -> ticks (cercles), auto ou manuel
          // - >= 11        -> counter (+/- + saisir)
          final isAuto = act.autoTune && !act.manualTarget;
          final isCheckbox = !isAuto && target <= 1;
          final showTicks = !isAuto && !isCheckbox && target <= 10;
          final isCounterMode = isAuto || target >= 11;
          final isManual = act.manualTarget;

          void inc(int delta) => setState(() {
                widget.logic.incHabit(it.refId!, delta, day);
              });

          Future<int?> _askInt(BuildContext context, String title) async {
            final s = await _askText(context, title);
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
            if (it.refId == null) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'Déplacer cette routine vers demain',
              icon: const Icon(Icons.arrow_forward, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                widget.logic.movePlannedToTomorrowIfPresent(
                  PlanKind.habit,
                  it.refId!,
                  addIfMissing: true,
                );
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Routine déplacée vers demain')),
                );
              },
            );
          }

          Widget autoBackBtnIfManual() {
            if (!isManual) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'Repasser en mode auto',
              icon: const Icon(Icons.auto_awesome, size: 18),
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
                      dragHandleFor(it),

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Ligne 1 — Titre + checkbox (uniquement si target <= 1)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: buildTitle(it.title)),
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
                                "$done / $target",
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),

                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => inc(1),
                                visualDensity: VisualDensity.compact,
                              ),

                              TextButton(
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
                                child: const Text("Saisir"),
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
                                          ? Icons.auto_awesome
                                          : Icons.pan_tool_alt,
                                      size: 16,
                                    ),
                                  ),
                                );
                              }),

                              moreCompact(),
                              moveArrowIfAny(),
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

                              // Optionnel : garder aussi tes actions compactes ici si tu veux
                              // moreCompact(),
                              // moveArrowIfAny(),
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
                                  moreCompact(),
                                  moveArrowIfAny(),
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
