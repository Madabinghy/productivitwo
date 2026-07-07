import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';

const _kCategoryColor = {
  'project': Color(0xFF1D9E75),
  'routine': Color(0xFFE07B39),
  'personal': Color(0xFF5B8DEF),
  'break': Color(0xFF8E9AAF),
};

/// « Programme du jour » web, COCHABLE depuis Focus.
///
/// `_FocusView` n'a pas d'AppLogic → on le construit ici (modèle
/// `chrono_launcher.dart`) pour pouvoir, comme sur mobile, valider la routine
/// liée à un bloc quand on le coche (`incHabit`) — sinon le jardin / la Mise du
/// jour ne refléteraient pas la validation. Stream Firestore du programme.
class WebDailyScheduleCard extends StatefulWidget {
  final FirestoreSync sync;
  const WebDailyScheduleCard({required this.sync, super.key});

  @override
  State<WebDailyScheduleCard> createState() => _WebDailyScheduleCardState();
}

class _WebDailyScheduleCardState extends State<WebDailyScheduleCard> {
  AppLogic? _logic;
  final Set<String> _hit = {}; // blocs déjà comptés (anti double-incrément)
  bool _busy = false;

  String get _todayStr {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await widget.sync.pull();
    if (state == null || !mounted) return;
    final logic = AppLogic(state, () {
      if (mounted) setState(() {});
    });
    logic.sync = widget.sync;
    setState(() => _logic = logic);
  }

  Future<void> _toggle(ScheduleBlock block) async {
    if (_busy) return;
    _busy = true;
    try {
      final newStatus = block.status == 'done' ? 'pending' : 'done';
      await widget.sync.updateBlockStatus(_todayStr, block.id, newStatus);
      if (newStatus == 'done') _completeLinkedRoutine(block);
    } finally {
      _busy = false;
    }
  }

  /// Valide la routine liée à un bloc (1 incrément, capé à la cible, 1×/bloc),
  /// puis persiste la progression + le hit. Calqué sur le mobile.
  void _completeLinkedRoutine(ScheduleBlock block) {
    final logic = _logic;
    final id = block.activityId;
    if (logic == null || id == null || _hit.contains(block.id)) return;
    Activity? act;
    for (final a in logic.state.activities) {
      if (a.id == id) {
        act = a;
        break;
      }
    }
    if (act == null || !act.isHabit) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tgt = logic.activeHabitTarget(act);
    if (tgt > 0 && logic.habitValueOn(id, today) >= tgt) {
      _hit.add(block.id); // déjà atteinte → on marque, sans incrémenter
      return;
    }
    _hit.add(block.id);
    logic.incHabit(id, 1, today);
    // Persiste la HabitProgress du jour + le dernier HabitHit (AppLogic transient).
    final key = yyyymmdd(today);
    HabitProgress? hp;
    for (final h in logic.state.habitProgress) {
      if (h.activityId == id && h.yyyymmdd == key) hp = h;
    }
    if (hp != null) widget.sync.saveHabitProgress(hp);
    if (logic.state.habitHits.isNotEmpty) {
      widget.sync.saveHabitHit(logic.state.habitHits.last);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Routine validée : ${act.name}'),
        duration: const Duration(milliseconds: 1200),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DailySchedule?>(
      stream: widget.sync.streamDailySchedule(_todayStr),
      builder: (context, snap) {
        final blocks =
            snap.data?.blocks.where((b) => b.status != 'deleted').toList() ?? [];
        if (blocks.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(.18),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: cs.outlineVariant.withOpacity(.25), width: 1),
            ),
            child: Row(children: [
              Icon(Icons.wb_sunny_outlined,
                  size: 14, color: cs.onSurface.withOpacity(.3)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aucun programme — demande à Claude de planifier ta journée',
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface.withOpacity(.35)),
                ),
              ),
            ]),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final b in blocks) _row(cs, b)],
        );
      },
    );
  }

  Widget _row(ColorScheme cs, ScheduleBlock block) {
    final isDone = block.status == 'done';
    final isSkipped = block.status == 'skipped';
    final color = _kCategoryColor[block.category] ?? const Color(0xFF8E9AAF);
    final dimmed = isDone || isSkipped;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              color.withOpacity(dimmed ? 0.05 : 0.12),
              cs.surfaceContainerHighest.withOpacity(.15),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
                color: color.withOpacity(dimmed ? 0.3 : 0.8), width: 3),
          ),
        ),
        child: Row(children: [
          // Case à cocher : valider l'item directement depuis Focus.
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _toggle(block),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                isDone
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 18,
                color: isDone
                    ? Colors.green.shade500
                    : color.withOpacity(.8),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 36,
            child: Text(
              block.startTime,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: dimmed
                    ? cs.onSurface.withOpacity(.3)
                    : color.withOpacity(.9),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              block.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurface.withOpacity(dimmed ? .3 : .85),
                decoration: isSkipped ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (!isDone)
            Text(
              fmtMin(block.durationMin),
              style:
                  TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(.3)),
            ),
        ]),
      ),
    );
  }
}
