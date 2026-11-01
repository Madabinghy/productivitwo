import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart';
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart';

/// Carte « Relevé de la semaine » : les objectifs dont un relevé de métrique
/// est attendu (`isReadingDue`), saisie en place (valeur + ✓), tap sur le
/// titre = fiche trajectoire. Invisible quand rien n'est dû. Mobile :
/// Objectifs et Aujourd'hui (segment Actions).
class ObjectiveReadingsCard extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final List<Project> projects;
  const ObjectiveReadingsCard({super.key, required this.logic, required this.sync, required this.projects});

  @override
  State<ObjectiveReadingsCard> createState() => _ObjectiveReadingsCardState();
}

class _ObjectiveReadingsCardState extends State<ObjectiveReadingsCard> {
  static const _accent = Color(0xFF00897B);
  // Cache partagé entre les instances (Objectifs et Aujourd'hui) : rendu
  // immédiat, rafraîchi derrière.
  static List<StrategicObjective>? _cache;

  List<StrategicObjective> _due = const [];
  final Map<String, TextEditingController> _ctrls = {};
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    if (_cache != null) _due = _dueOf(_cache!);
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<StrategicObjective> _dueOf(List<StrategicObjective> all) {
    final now = DateTime.now();
    return all.where((o) => o.status == 'active' && isReadingDue(o, now)).toList();
  }

  Future<void> _load() async {
    List<StrategicObjective> all;
    try {
      all = await widget.sync.fetchStrategicObjectives();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _cache = all;
    setState(() => _due = _dueOf(all));
  }

  TextEditingController _ctrl(StrategicObjective o) => _ctrls.putIfAbsent(o.id, () => TextEditingController());

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Future<void> _save(StrategicObjective o) async {
    final raw = _ctrl(o).text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null || _saving.contains(o.id)) return;
    setState(() => _saving.add(o.id));
    o.readings = upsertReading(o.readings, ObjectiveReading(date: todayYmd(DateTime.now()), value: value));
    o.updatedAt = DateTime.now();
    try {
      await widget.sync.saveStrategicObjective(o);
    } catch (_) {
      if (mounted) {
        setState(() => _saving.remove(o.id));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(persist: false, content: Text('Erreur de sauvegarde — réessaie.')));
      }
      return;
    }
    if (!mounted) return;
    final t = computeObjectiveTrajectory(o, widget.logic.state.sessions, DateTime.now());
    final r = t.result;
    final unit = o.metric?.unit == null ? '' : ' ${o.metric!.unit}';
    final msg = r == null
        ? 'Relevé noté.'
        : r.delta == 0
            ? 'Relevé noté : ${_fmt(value)}$unit · pile sur la trajectoire.'
            : 'Relevé noté : ${_fmt(value)}$unit · ${r.delta > 0 ? '${_fmt(r.delta)}$unit d\'avance' : '${_fmt(-r.delta)}$unit de retard'} (attendu ${_fmt(r.expectedValue)}$unit).';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(persist: false, content: Text(msg)));
    setState(() {
      _saving.remove(o.id);
      _due = _due.where((x) => x.id != o.id).toList();
      _cache = _cache?.map((x) => x.id == o.id ? o : x).toList();
    });
  }

  Future<void> _open(StrategicObjective o) async {
    final changed = await showObjectiveTrajectorySheet(
      context,
      logic: widget.logic,
      sync: widget.sync,
      objective: o,
      projects: widget.projects,
    );
    if (changed) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_due.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _accent.withOpacity(.35))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.add_chart, size: 15, color: _accent.withOpacity(.9)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('RELEVÉ DE LA SEMAINE · ${_due.length}',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .8, color: cs.onSurface.withOpacity(.5))),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Où en est le résultat ? Note la valeur du jour, la courbe fait le reste.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
          const SizedBox(height: 10),
          for (final o in _due) _row(cs, o, now),
        ]),
      ),
    );
  }

  Widget _row(ColorScheme cs, StrategicObjective o, DateTime now) {
    final m = o.metric!;
    final last = latestReading(o);
    final t = computeObjectiveTrajectory(o, widget.logic.state.sessions, now);
    final exp = t.result?.expectedValue;
    final ctrl = _ctrl(o);
    final sub = [
      m.label,
      if (last != null) 'dernier ${_fmt(last.value)}${m.unit == null ? '' : ' ${m.unit}'} il y a ${t.daysSinceReading} j' else 'aucun relevé',
      if (exp != null) 'attendu ${_fmt(exp)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: InkWell(
            onTap: () => _open(o),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.5))),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 86,
          child: TextField(
            controller: ctrl,
            textAlign: TextAlign.end,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(
              isDense: true,
              hintText: last == null ? _fmt(m.startValue) : _fmt(last.value),
              suffixText: m.unit,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(o),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Enregistrer le relevé',
          onPressed: _saving.contains(o.id) || double.tryParse(ctrl.text.trim().replaceAll(',', '.')) == null ? null : () => _save(o),
          icon: _saving.contains(o.id)
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_circle, color: _accent),
        ),
      ]),
    );
  }
}

/// Saisie rapide d'un relevé (geste « Noter » d'un enjeu, Aujourd'hui mobile et
/// web) : une valeur, enregistrée au jour même. Renvoie true si noté.
Future<bool> noteReadingQuick(BuildContext context, {required FirestoreSync sync, required StrategicObjective objective}) async {
  final m = objective.metric;
  if (m == null) return false;
  final ctrl = TextEditingController();
  final last = latestReading(objective);
  String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  final value = await showDialog<double>(
    context: context,
    builder: (d) {
      void submit() {
        final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
        if (v != null) Navigator.pop(d, v);
      }

      return AlertDialog(
        title: Text('Relevé · ${m.label.isEmpty ? objective.title : m.label}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(objective.title, style: TextStyle(fontSize: 13, color: Theme.of(d).colorScheme.onSurface.withValues(alpha: .6))),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              suffixText: m.unit,
              hintText: last == null ? 'valeur du jour' : 'dernier : ${fmt(last.value)}',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: submit, child: const Text('Noter')),
        ],
      );
    },
  );
  ctrl.dispose();
  if (value == null) return false;
  objective.readings = upsertReading(objective.readings, ObjectiveReading(date: todayYmd(DateTime.now()), value: value));
  objective.updatedAt = DateTime.now();
  try {
    await sync.saveStrategicObjective(objective);
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(persist: false, content: Text('Erreur de sauvegarde — réessaie.')));
    return false;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(persist: false, content: Text('Relevé noté : ${fmt(value)}${m.unit == null || m.unit!.isEmpty ? '' : ' ${m.unit}'}')));
  }
  return true;
}
