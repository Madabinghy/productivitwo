import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/main.dart';
import 'package:productivitwo_v1/models.dart';

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

    // Décaler la maintenance après le 1er frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupHousekeeping(); // -> maybeCarryFromYesterday + ensureDailyHabitsPlanned
    });

    _base = DateTime.now();
    if (_base.hour >= 18) _planTomorrow = true;
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
    final ymd = _ymd; // aujourd’hui ou demain selon ton toggle
    final items = widget.logic.planFor(ymd); // triés par 'order'

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
    final more = PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'delete') {
          setState(() {
            widget.state.dayPlan.removeWhere((e) => e.id == it.id);
            widget.logic.onChange(); // persiste
          });
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'delete', child: Text('Supprimer de la journée')),
      ],
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
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.drag_handle),
        ),
      );
    }

    // helpers d’affichage
    Widget buildTitle(String title) => Text(
          title,
          maxLines: 1,
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
                  dragHandleFor(it),
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
                          value: it.done,
                          onChanged: (v) => setState(
                              () => widget.logic.toggleDone(it.id, v ?? false)),
                        ),
                        more,
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
            onPressed: () => widget.logic.start(it.refId!),
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
                            more,
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
      case PlanKind.habit:
        {
          final done = widget.logic.habitValueOn(it.refId!, day);
          final act =
              widget.state.activities.firstWhere((a) => a.id == it.refId!);
          final target = widget.logic.dayQuotaFor(act);
          final unit = (act.unit ?? '').isNotEmpty ? ' ${act.unit}' : '';

          void inc(int delta) => setState(() {
                widget.logic.incHabit(it.refId!, delta, day); // basé sur "day"
              });

          // ---- Bouton flèche "→ Demain" (routines / onglet Aujourd'hui) ----
          Widget moveArrowIfAny() {
            if (!isTodayTab) return const SizedBox.shrink();
            if (it.refId == null) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'Déplacer cette routine vers demain',
              icon: const Icon(Icons.arrow_forward),
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

          // Trailing haut (checkbox si cible 1), + flèche → Demain + menu …
          Widget trailingTop;
          if (target <= 1) {
            trailingTop = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: done >= 1, // basé sur "day"
                  onChanged: (v) => inc((v == true ? 1 : 0) - done),
                ),
                more,
                moveArrowIfAny(),
              ],
            );
          } else {
            trailingTop = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                more,
                moveArrowIfAny(),
              ],
            );
          }

          return Card(
            key: key,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  dragHandleFor(it),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Ligne 1 — Titre + trailing
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: buildTitle(it.title)),
                            const SizedBox(width: 8),
                            trailingTop,
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Ligne 2 — "Aujourd’hui/Demain : X / Y"
                        Text(
                          "$todayLabel $done / $target$unit",
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),

                        // Ligne 3 — Pastilles si cible > 1
                        if (target > 1) ...[
                          const SizedBox(height: 4),
                          HabitTicksRow(
                            done: done,
                            target: target,
                            onIncOne: () => inc(1),
                            onDecOne: () => inc(-1),
                            onOpenFull: () => showHabitChecklist(
                              context,
                              title: it.title,
                              done: done,
                              target: target,
                              onSet: (newDone) {
                                final delta = newDone - done;
                                if (delta != 0) {
                                  widget.logic.incHabit(it.refId!, delta, day);
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                        ]
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
