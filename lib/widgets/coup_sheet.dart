import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject;
import 'package:productivitwo_v1/utils/coups.dart';
import 'package:productivitwo_v1/widgets/rest_sheet.dart';

/// Lancer un coup (Modes et coups § 2.3) : trois champs — quoi · cible ·
/// jusqu'à quand — plus la source (un projet OU une activité-temps), puis la
/// proposition de mettre les autres domaines en veille jusqu'à la fin du coup.
/// Même modèle qu'un objectif (`horizon: "tactical"`) : même fiche, même graphe.
Future<StrategicObjective?> showCoupSheet(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  required List<Project> projects,
}) async {
  final saved = await showModalBottomSheet<StrategicObjective>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _CoupForm(logic: logic, sync: sync, projects: projects),
    ),
  );
  if (saved == null || !context.mounted) return null;
  final st = logic.state;
  await showRestSheet(context,
      logic: logic,
      sync: sync,
      untilYmd: coupRestUntil(saved),
      excludeDomainIds: coupDomainIds(saved, projects, st.activities),
      title: 'Coup lancé · mettre le reste en veille jusqu\'au ${dayMonthFr(saved.endDate!)} ?');
  return saved;
}

class _CoupForm extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final List<Project> projects;
  const _CoupForm({required this.logic, required this.sync, required this.projects});
  @override
  State<_CoupForm> createState() => _CoupFormState();
}

class _CoupFormState extends State<_CoupForm> {
  final _title = TextEditingController();
  final _target = TextEditingController();
  final _minutes = TextEditingController(text: '60');
  DateTime? _end;
  String? _projectId;
  String? _activityId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = DateTime.now();
    _end = DateTime(t.year, t.month, t.day + 4); // 5 jours, fin incluse
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final today = DateTime.now();
    final err = validateCoup(title: _title.text, endDate: _end, today: today, hasSource: _projectId != null || _activityId != null);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _saving = true);
    final minPerDay = int.tryParse(_minutes.text.trim()) ?? 0;
    Project? p;
    for (final x in widget.projects) {
      if (x.id == _projectId) p = x;
    }
    Activity? a;
    for (final x in widget.logic.state.activities) {
      if (x.id == _activityId) a = x;
    }
    final o = StrategicObjective(
      title: _title.text.trim(),
      kpiTarget: _target.text.trim().isEmpty ? null : _target.text.trim(),
      horizon: 'tactical',
      domainId: p?.domainId ?? a?.domainId,
      startDate: DateTime(today.year, today.month, today.day),
      endDate: _end,
      checkInEvery: 1,
      projectIds: [if (p != null) p.id],
      timeCommitments: [if (a != null && minPerDay > 0) ObjectiveTimeCommitment(activityId: a.id, weeklyMin: minPerDay * 7)],
    );
    try {
      await widget.sync.saveStrategicObjective(o);
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = 'Enregistrement impossible — réessaie.';
      });
      return;
    }
    if (mounted) Navigator.pop(context, o);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final all = widget.projects;
    final projects = all.where((p) => p.status == 'active' && !p.paused && !isFolderProject(p, all)).toList()
      ..sort((x, y) => x.title.toLowerCase().compareTo(y.title.toLowerCase()));
    final acts = widget.logic.state.activeActivities.where((x) => !x.isHabit).toList()
      ..sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
    final days = _end == null ? null : DateTime(_end!.year, _end!.month, _end!.day).difference(DateTime(today.year, today.month, today.day)).inDays + 1;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Lancer un coup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('3 à 10 jours, une cible, tout le reste en veille.', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6))),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Quoi ?', hintText: 'Finir le chapitre 3', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _target,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Cible', hintText: 'chapitre relu et envoyé · 5 h de rédaction', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          Text('JUSQU\'À QUAND', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: cs.onSurface.withValues(alpha: .55))),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in const [3, 5, 7, 10])
              ChoiceChip(
                label: Text('$n j'),
                selected: days == n,
                onSelected: (_) => setState(() => _end = DateTime(today.year, today.month, today.day + n - 1)),
              ),
            ActionChip(
              avatar: const Icon(Icons.event_outlined, size: 16),
              label: Text(_end == null ? 'Date' : dayMonthFr(_end!)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _end ?? today,
                    firstDate: today,
                    lastDate: today.add(const Duration(days: 30)),
                    locale: const Locale('fr', 'FR'));
                if (d != null) setState(() => _end = d);
              },
            ),
          ]),
          const SizedBox(height: 14),
          Text('POUR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: cs.onSurface.withValues(alpha: .55))),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _projectId == null && _activityId == null ? null : (_projectId != null ? 'p:$_projectId' : 'a:$_activityId'),
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Projet ou activité'),
            items: [
              for (final p in projects) DropdownMenuItem(value: 'p:${p.id}', child: Text('📁 ${p.title}', maxLines: 1, overflow: TextOverflow.ellipsis)),
              for (final a in acts) DropdownMenuItem(value: 'a:${a.id}', child: Text('⏱ ${a.name}', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _projectId = v != null && v.startsWith('p:') ? v.substring(2) : null;
              _activityId = v != null && v.startsWith('a:') ? v.substring(2) : null;
            }),
          ),
          if (_activityId != null) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minutes par jour', border: OutlineInputBorder(), suffixText: 'min / j'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(fontSize: 12.5, color: cs.error, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
            icon: const Icon(Icons.bolt_rounded),
            label: Text(days == null ? 'Lancer le coup' : 'Lancer le coup · $days j'),
          ),
        ]),
      ),
    );
  }
}
