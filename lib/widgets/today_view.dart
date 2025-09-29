import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
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

  String get _ymd {
    final d = _planTomorrow ? _base.add(const Duration(days: 1)) : _base;
    return yyyymmdd(d);
  }

  @override
  void initState() {
    super.initState();
    _base = DateTime.now();
    // Suggestion : si on est après 18h, basculer l’UI par défaut sur "Demain"
    if (_base.hour >= 18) _planTomorrow = true;
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
            onSelectionChanged: (s) => setState(() => _planTomorrow = s.first),
          ),
        ),
      ),

      // 🔁 Réorganisation par drag & drop
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        itemCount: items.length,
        onReorder: (oldIndex, newIndex) {
          setState(() => widget.logic.reorderPlan(ymd, oldIndex, newIndex));
        },
        itemBuilder: (ctx, i) {
          final it = items[i];
          return _todayTile(ctx, it, key: ValueKey(it.id));
        },
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

Widget _todayTile(BuildContext context, DayPlanItem it, {required Key key}) {
  Widget leading;
  Widget title;
  Widget? subtitle;
  Widget trailing;

  final menu = PopupMenuButton<String>(
    onSelected: (v) {
      if (v == 'delete') {
        setState(() {
          widget.state.dayPlan.removeWhere((e) => e.id == it.id);
          widget.logic.onChange();
        });
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'delete', child: Text('Supprimer de la journée')),
    ],
  );

  switch (it.kind) {
    // ---------------- ACTION ----------------
    case PlanKind.action:
      leading = const Icon(Icons.drag_handle);
      title = Text(it.title,
          style: const TextStyle(fontWeight: FontWeight.w600));
      subtitle = null;
      trailing = Checkbox(
        value: it.done,
        onChanged: (v) =>
            setState(() => widget.logic.toggleDone(it.id, v ?? false)),
      );
      break;

    // ---------------- ACTIVITY (time) ----------------
    case PlanKind.activityTime:
      leading = const Icon(Icons.drag_handle);
      title = Text(it.title,
          style: const TextStyle(fontWeight: FontWeight.w600));
      final now = DateTime.now();
      final dur = widget.logic.totalForRangeByActivity(
          it.refId!, now.subtract(const Duration(hours: 24)), now);
      subtitle = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Aujourd’hui :",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400)),
          Text("${dur.inMinutes ~/ 60}h ${dur.inMinutes % 60}m",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      );
      trailing = FilledButton.icon(
        onPressed: () => widget.logic.start(it.refId!),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Lancer'),
      );
      break;

    // ---------------- HABIT (new compact layout) ----------------
    case PlanKind.habit:
      leading = const Icon(Icons.drag_handle);
      final today = DateTime.now();
      final done = widget.logic.habitValueOn(it.refId!, today);
      final act = widget.state.activities.firstWhere((a) => a.id == it.refId!);
      final target = act.dailyTarget ?? 0;
      final unit = (act.unit ?? '').isNotEmpty ? ' ${act.unit}' : '';

      title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            it.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text("Aujourd’hui :",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400)),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(
                      () => widget.logic.incHabit(it.refId!, -1, today)),
                  icon: const Icon(Icons.remove),
                ),
                Text("$done / $target$unit",
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(
                      () => widget.logic.incHabit(it.refId!, 1, today)),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ],
      );

      subtitle = null;
      trailing = const SizedBox.shrink();
      break;
  }

  return Card(
    key: key,
    margin: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        // poignée drag
        ReorderableDragStartListener(
          index: widget.logic
              .planFor(yyyymmdd(_planTomorrow
                  ? DateTime.now().add(const Duration(days: 1))
                  : DateTime.now()))
              .indexWhere((e) => e.id == it.id),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.drag_handle),
          ),
        ),
        // contenu principal
        Expanded(
          child: ListTile(
            contentPadding: const EdgeInsets.only(right: 8, left: 0),
            title: title,
            subtitle: subtitle,
            trailing: menu, // uniquement le "…" reste
          ),
        ),
        if (it.kind != PlanKind.habit &&
            it.kind != PlanKind.action) trailing, // activité → bouton "Lancer"
        if (it.kind == PlanKind.action) trailing, // action → checkbox
      ],
    ),
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
              // 1) Action volante
              ListTile(
                leading: const Icon(Icons.checklist),
                title: const Text('Ajouter une action'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final title = await _askText(context, 'Nouvelle action');
                  if (title != null && title.trim().isNotEmpty) {
                    setState(() => widget.logic
                        .addPlanAction(ymd: _ymd, title: title.trim()));
                  }
                },
              ),
              const Divider(),
              // 2) Sélectionner une activité temps existante
              ListTile(
                leading: const Icon(Icons.timelapse),
                title: const Text('Ajouter une activité (temps)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final act = await _pickActivity(isHabit: false);
                  if (act != null) {
                    setState(() => widget.logic.addPlanActivity(
                        ymd: _ymd, activityId: act.id, isHabit: false));
                  }
                },
              ),
              // 3) Sélectionner une habitude existante
              ListTile(
                leading: const Icon(Icons.task_alt),
                title: const Text('Ajouter une routine'),
                subtitle: const Text('Option : suivre toute la journée'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final act = await _pickActivity(isHabit: true);
                  if (act != null) {
                    // pour l’instant, on met allDay=true par défaut (modifiable plus tard)
                    setState(() => widget.logic.addPlanActivity(
                        ymd: _ymd,
                        activityId: act.id,
                        isHabit: true,
                        allDay: true));
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
}
