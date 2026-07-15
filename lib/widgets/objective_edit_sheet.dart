import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/firestore_sync.dart';

/// Sheet de définition/édition guidée d'un objectif stratégique (SMART).
/// 4 étapes : ① Spécifique ② Mesurable ③ Temporel ④ Moyens.
/// Partagée web + mobile. Persiste via [sync.saveStrategicObjective] et
/// retourne l'objectif sauvegardé (null si annulé).
Future<StrategicObjective?> showObjectiveEditSheet(
  BuildContext context, {
  StrategicObjective? existing,
  required List<Domain> domains,
  required List<Activity> activities,
  required List<Project> projects,
  required FirestoreSync sync,
}) {
  return showModalBottomSheet<StrategicObjective>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ObjectiveEditSheet(
      existing: existing,
      domains: domains,
      activities: activities,
      projects: projects,
      sync: sync,
    ),
  );
}

class _ObjectiveEditSheet extends StatefulWidget {
  final StrategicObjective? existing;
  final List<Domain> domains;
  final List<Activity> activities;
  final List<Project> projects;
  final FirestoreSync sync;

  const _ObjectiveEditSheet({
    required this.existing,
    required this.domains,
    required this.activities,
    required this.projects,
    required this.sync,
  });

  @override
  State<_ObjectiveEditSheet> createState() => _ObjectiveEditSheetState();
}

class _ObjectiveEditSheetState extends State<_ObjectiveEditSheet> {
  static const _accent = Color(0xFF00897B); // teal — identité objectifs 🎯

  int _step = 0;
  bool _saving = false;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _kpiCtrl;
  late final TextEditingController _horizonCtrl;
  String? _domainId;
  DateTime? _startDate;
  DateTime? _endDate;
  late final Map<String, int> _timeCommitments; // activityId → weeklyMin
  late final Set<String> _routineIds;
  late final Set<String> _projectIds;

  List<Activity> get _timeActivities => widget.activities
      .where((a) => !a.deleted && a.type == 'time')
      .toList();
  List<Activity> get _routines =>
      widget.activities.where((a) => !a.deleted && a.isHabit).toList();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _kpiCtrl = TextEditingController(text: e?.kpiTarget ?? '');
    _horizonCtrl = TextEditingController(text: e?.horizonLabel ?? '');
    _domainId = e?.domainId;
    _startDate = e?.startDate;
    _endDate = e?.endDate;
    _timeCommitments = {
      for (final c in e?.timeCommitments ?? <ObjectiveTimeCommitment>[])
        c.activityId: c.weeklyMin,
    };
    _routineIds = {
      for (final c in e?.routineCommitments ?? <ObjectiveRoutineCommitment>[])
        c.activityId,
    };
    _projectIds = {...?e?.projectIds};
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _kpiCtrl.dispose();
    _horizonCtrl.dispose();
    super.dispose();
  }

  // ── Validations par étape (le SMART guidé) ─────────────────────────────────
  bool get _step1Ok => _titleCtrl.text.trim().isNotEmpty;
  bool get _step2Ok => _kpiCtrl.text.trim().isNotEmpty;
  bool get _step3Ok => _horizonCtrl.text.trim().isNotEmpty || _endDate != null;
  bool get _step4Ok =>
      _timeCommitments.isNotEmpty ||
      _routineIds.isNotEmpty ||
      _projectIds.isNotEmpty;

  bool _stepOk(int step) => switch (step) {
        0 => _step1Ok,
        1 => _step2Ok,
        2 => _step3Ok,
        _ => _step4Ok,
      };

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final e = widget.existing;
    final obj = StrategicObjective(
      id: e?.id,
      title: _titleCtrl.text.trim(),
      description:
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      domainId: _domainId,
      kpiTarget: _kpiCtrl.text.trim(),
      horizonLabel:
          _horizonCtrl.text.trim().isEmpty ? null : _horizonCtrl.text.trim(),
      startDate: _startDate ?? e?.startDate ?? DateTime.now(),
      endDate: _endDate,
      status: e?.status ?? 'active',
      projectIds: _projectIds.toList(),
      timeCommitments: _timeCommitments.entries
          .map((en) =>
              ObjectiveTimeCommitment(activityId: en.key, weeklyMin: en.value))
          .toList(),
      routineCommitments: _routineIds
          .map((id) => ObjectiveRoutineCommitment(activityId: id))
          .toList(),
      createdAt: e?.createdAt,
      updatedAt: DateTime.now(),
    );
    try {
      await widget.sync.saveStrategicObjective(obj);
      if (!mounted) return;
      Navigator.pop(context, obj);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur de sauvegarde — réessaie.')));
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  InputDecoration _dec(BuildContext context,
      {required String label, String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(color: cs.onSurface.withOpacity(.35), fontSize: 13),
      alignLabelWithHint: true,
      filled: true,
      fillColor: cs.surfaceVariant.withOpacity(.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _accent, width: 1.6),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _hint(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 2),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, color: cs.onSurface.withOpacity(.5), height: 1.4)),
    );
  }

  ChoiceChip _chip(BuildContext context,
      {required bool selected,
      required String label,
      Widget? avatar,
      required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      avatar: avatar,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected ? _accent : cs.onSurface.withOpacity(.7),
      ),
      selectedColor: _accent.withOpacity(.14),
      backgroundColor: cs.surfaceVariant.withOpacity(.35),
      side: BorderSide(
          color: selected ? _accent.withOpacity(.55) : Colors.transparent),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // ── Étapes ─────────────────────────────────────────────────────────────────

  Widget _stepSpecific(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: _dec(context,
                label: 'Résultat visé',
                hint: 'Ex : Lancer mon app et trouver mes premiers clients'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: _dec(context,
                label: 'Pourquoi ça compte (optionnel)',
                hint: 'La motivation derrière — dans tes mots'),
          ),
          if (widget.domains.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.domains
                  .map((d) => _chip(
                        context,
                        selected: d.id == _domainId,
                        label: d.name,
                        onTap: () => setState(
                            () => _domainId = d.id == _domainId ? null : d.id),
                      ))
                  .toList(),
            ),
          ],
          _hint(context,
              'Spécifique : un résultat concret, dans tes mots — pas un vœu.'),
        ],
      );

  Widget _stepMeasurable(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _kpiCtrl,
            decoration: _dec(context,
                label: 'Indicateur de succès',
                hint: 'Ex : 100 clients payants · MRR 500€'),
            onChanged: (_) => setState(() {}),
          ),
          _hint(context,
              'Mesurable : un chiffre + une unité. Comment sauras-tu que c\'est atteint ?'),
        ],
      );

  Widget _stepTemporal(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _horizonCtrl,
          decoration: _dec(context,
              label: 'Horizon', hint: 'Ex : 3 mois, Q2 2026'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickEndDate,
                icon: const Icon(Icons.event, size: 18),
                label: Text(_endDate == null
                    ? 'Choisir une échéance'
                    : 'Échéance : ${_ymd(_endDate!)}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _endDate != null
                      ? _accent
                      : cs.onSurface.withOpacity(.7),
                  side: BorderSide(
                      color: _endDate != null
                          ? _accent.withOpacity(.55)
                          : cs.onSurface.withOpacity(.2)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            if (_endDate != null)
              IconButton(
                onPressed: () => setState(() => _endDate = null),
                icon: Icon(Icons.close,
                    size: 18, color: cs.onSurface.withOpacity(.5)),
              ),
          ],
        ),
        _hint(context,
            'Temporel : un horizon lisible ou une date — sans échéance, un objectif reste un rêve.'),
      ],
    );
  }

  Widget _stepMeans(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_timeActivities.isNotEmpty) ...[
          Text('TEMPS HEBDO SUR TES ACTIVITÉS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  color: cs.onSurface.withOpacity(.45))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _timeActivities.map((a) {
              final selected = _timeCommitments.containsKey(a.id);
              return _chip(
                context,
                selected: selected,
                label: a.name,
                onTap: () => setState(() {
                  if (selected) {
                    _timeCommitments.remove(a.id);
                  } else {
                    _timeCommitments[a.id] = 120;
                  }
                }),
              );
            }).toList(),
          ),
          for (final entry in _timeCommitments.entries) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _timeActivities
                            .where((a) => a.id == entry.key)
                            .map((a) => a.name)
                            .firstOrNull ??
                        entry.key,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: entry.value > 15
                      ? () => setState(() => _timeCommitments[entry.key] =
                          (entry.value - 15).clamp(15, 1200))
                      : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color: _accent,
                  visualDensity: VisualDensity.compact,
                ),
                SizedBox(
                  width: 84,
                  child: Text(
                    '${_fmtWeeklyMin(entry.value)}/sem',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: entry.value < 1200
                      ? () => setState(() => _timeCommitments[entry.key] =
                          (entry.value + 15).clamp(15, 1200))
                      : null,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  color: _accent,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in const [30, 60, 120, 180, 300, 420])
                  _chip(
                    context,
                    selected: entry.value == preset,
                    label: _fmtWeeklyMin(preset),
                    onTap: () => setState(
                        () => _timeCommitments[entry.key] = preset),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
        ],
        if (_routines.isNotEmpty) ...[
          Text('ROUTINES SUIVIES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  color: cs.onSurface.withOpacity(.45))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _routines.map((a) {
              final selected = _routineIds.contains(a.id);
              final freq = switch (a.effHabitFreq) {
                HabitFreq.daily => '/j',
                HabitFreq.weekly => '/sem',
                HabitFreq.monthly => '/mois',
              };
              return _chip(
                context,
                selected: selected,
                label: '${a.name} · ${a.effHabitTarget}$freq',
                onTap: () => setState(() {
                  selected ? _routineIds.remove(a.id) : _routineIds.add(a.id);
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
        ],
        if (widget.projects.isNotEmpty) ...[
          Text('PROJETS RATTACHÉS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  color: cs.onSurface.withOpacity(.45))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.projects.map((p) {
              final selected = _projectIds.contains(p.id);
              return _chip(
                context,
                selected: selected,
                label: p.title,
                onTap: () => setState(() {
                  selected ? _projectIds.remove(p.id) : _projectIds.add(p.id);
                }),
              );
            }).toList(),
          ),
        ],
        _hint(context,
            'Atteignable : au moins un moyen concret — du temps hebdo, une routine ou un projet. Sous-engage au début, tu réviseras à la hausse.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLast = _step == 3;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scroll) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_accent, Colors.teal.shade300],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.flag,
                              size: 20, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  widget.existing == null
                                      ? 'Nouvel objectif'
                                      : 'Réviser l\'objectif',
                                  style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                'Étape ${_step + 1}/4 · ${const [
                                  'Spécifique',
                                  'Mesurable',
                                  'Temporel',
                                  'Moyens'
                                ][_step]}',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurface.withOpacity(.5)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Barre de progression des étapes
                    Row(
                      children: List.generate(4, (i) {
                        final active = i <= _step;
                        return Expanded(
                          child: Container(
                            margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                            height: 4,
                            decoration: BoxDecoration(
                              color: active
                                  ? _accent
                                  : cs.onSurface.withOpacity(.12),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 22),
                    switch (_step) {
                      0 => _stepSpecific(context),
                      1 => _stepMeasurable(context),
                      2 => _stepTemporal(context),
                      _ => _stepMeans(context),
                    },
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        if (_step > 0)
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() => _step--),
                            child: const Text('Retour'),
                          ),
                        const Spacer(),
                        FilledButton(
                          onPressed: !_stepOk(_step) || _saving
                              ? null
                              : () {
                                  if (isLast) {
                                    _save();
                                  } else {
                                    setState(() => _step++);
                                  }
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 26, vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(isLast ? 'Enregistrer' : 'Continuer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _ymd(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// « 30 min », « 2 h », « 2 h 30 » — affichage des engagements hebdo.
String _fmtWeeklyMin(int min) {
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}
