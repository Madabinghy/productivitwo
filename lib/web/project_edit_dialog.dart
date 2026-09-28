import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/web/desktop_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// Création / modification d'un projet : titre, domaine, dates, description,
/// phases (ajout, renommage, dates, suppression). Persiste via `saveProject`
/// (le doc entier : phases et tâches comprises). Retourne true si enregistré.
Future<bool> showProjectEditDialog(
  BuildContext context, {
  required Project project,
  required List<Domain> domains,
  required FirestoreSync sync,
  bool isNew = false,
}) async {
  final ok = await showDesktopDialog<bool>(
    context,
    maxWidth: 560,
    builder: (_) => _ProjectEditDialog(project: project, domains: domains, isNew: isNew),
  );
  if (ok != true) return false;
  await sync.saveProject(project);
  return true;
}

const _kMonthShort = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
];
String _fmt(DateTime d) => '${d.day} ${_kMonthShort[d.month - 1]} ${d.year}';

class _PhaseDraft {
  final String? id; // null = nouvelle phase
  String label;
  DateTime start;
  DateTime end;
  String? color;
  _PhaseDraft({this.id, required this.label, required this.start, required this.end, this.color});
}

class _ProjectEditDialog extends StatefulWidget {
  final Project project;
  final List<Domain> domains;
  final bool isNew;
  const _ProjectEditDialog({required this.project, required this.domains, required this.isNew});

  @override
  State<_ProjectEditDialog> createState() => _ProjectEditDialogState();
}

class _ProjectEditDialogState extends State<_ProjectEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  String? _domainId;
  late DateTime _start;
  DateTime? _end;
  late final List<_PhaseDraft> _phases;
  final List<TextEditingController> _phaseCtrls = [];

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _title = TextEditingController(text: widget.isNew ? '' : p.title);
    _desc = TextEditingController(text: p.description ?? '');
    _domainId = p.domainId;
    _start = DateTime(p.startDate.year, p.startDate.month, p.startDate.day);
    _end = p.endDate == null ? null : DateTime(p.endDate!.year, p.endDate!.month, p.endDate!.day);
    _phases = [
      for (final ph in List.of(p.phases)..sort((a, b) => a.startDate.compareTo(b.startDate)))
        _PhaseDraft(id: ph.id, label: ph.label, start: ph.startDate, end: ph.endDate, color: ph.color),
    ];
    for (final ph in _phases) {
      _phaseCtrls.add(TextEditingController(text: ph.label));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    for (final c in _phaseCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid => _title.text.trim().isNotEmpty && (_end == null || !_end!.isBefore(_start));

  void _addPhase() {
    final last = _phases.isEmpty ? null : _phases.last;
    final start = last == null ? _start : last.end.add(const Duration(days: 1));
    final end = start.add(const Duration(days: 13));
    setState(() {
      _phases.add(_PhaseDraft(label: 'Phase ${_phases.length + 1}', start: start, end: end));
      _phaseCtrls.add(TextEditingController(text: _phases.last.label));
    });
  }

  void _removePhase(int i) {
    setState(() {
      _phases.removeAt(i);
      _phaseCtrls.removeAt(i).dispose();
    });
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime(2032),
      );

  /// Applique le brouillon au projet (l'appelant sauvegarde).
  void _apply() {
    final p = widget.project;
    p.title = _title.text.trim();
    final d = _desc.text.trim();
    p.description = d.isEmpty ? null : d;
    p.domainId = _domainId;
    p.startDate = _start;
    p.endDate = _end;

    final kept = <String>{};
    final result = <ProjectPhase>[];
    for (var i = 0; i < _phases.length; i++) {
      final ph = _phases[i];
      final label = _phaseCtrls[i].text.trim().isEmpty ? 'Phase ${i + 1}' : _phaseCtrls[i].text.trim();
      final existing = ph.id == null ? null : p.phases.where((x) => x.id == ph.id).firstOrNull;
      if (existing != null) {
        existing.label = label;
        existing.startDate = ph.start;
        existing.endDate = ph.end;
        result.add(existing);
        kept.add(existing.id);
        // Le groupe visuel des tâches suit le libellé de la phase (comme le Gantt).
        for (final t in p.tasks) {
          if (t.phaseId == existing.id) t.groupLabel = label;
        }
      } else {
        result.add(ProjectPhase(label: label, startDate: ph.start, endDate: ph.end, color: ph.color));
      }
    }
    // Phases supprimées : leurs tâches redeviennent « sans phase ».
    for (final t in p.tasks) {
      if (t.phaseId != null && !kept.contains(t.phaseId) && !result.any((x) => x.id == t.phaseId)) {
        t.phaseId = null;
        t.groupLabel = null;
      }
    }
    p.phases
      ..clear()
      ..addAll(result);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBSurface,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.isNew ? 'Nouveau projet' : 'Modifier le projet',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kBText)),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _title,
                  autofocus: widget.isNew,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: kBText),
                  decoration: const InputDecoration(labelText: 'Titre'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _desc,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(color: kBText),
                  decoration: const InputDecoration(labelText: 'Description (optionnel)'),
                ),
                const SizedBox(height: 18),
                _section('DOMAINE'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    label: const Text('Aucun'),
                    selected: _domainId == null,
                    onSelected: (_) => setState(() => _domainId = null),
                  ),
                  for (final d in widget.domains.where((d) => !d.deleted))
                    ChoiceChip(
                      avatar: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: domainColor(d.id, widget.domains) ?? kBText3,
                            shape: BoxShape.circle),
                      ),
                      label: Text(d.name),
                      selected: _domainId == d.id,
                      onSelected: (_) => setState(() => _domainId = d.id),
                    ),
                ]),
                const SizedBox(height: 18),
                _section('DATES'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _dateField('Début', _fmt(_start), () async {
                      final d = await _pick(_start);
                      if (d != null) setState(() => _start = d);
                    }),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dateField(
                      'Échéance (optionnel)',
                      _end == null ? '—' : _fmt(_end!),
                      () async {
                        final d = await _pick(_end ?? _start.add(const Duration(days: 30)));
                        if (d != null) setState(() => _end = d);
                      },
                      onClear: _end == null ? null : () => setState(() => _end = null),
                      error: _end != null && _end!.isBefore(_start) ? 'Avant le début' : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: _section('PHASES')),
                  TextButton.icon(
                    onPressed: _addPhase,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Ajouter une phase'),
                    style: TextButton.styleFrom(
                        foregroundColor: kBPrimary, visualDensity: VisualDensity.compact),
                  ),
                ]),
                if (_phases.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 4),
                    child: Text('Sans phase, les tâches sont listées à plat. Les phases structurent le plan d\'action.',
                        style: TextStyle(fontSize: 12, color: kBText3, height: 1.4)),
                  )
                else
                  for (var i = 0; i < _phases.length; i++) _phaseRow(i),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            const Spacer(),
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _valid
                  ? () {
                      _apply();
                      Navigator.of(context).pop(true);
                    }
                  : null,
              style: FilledButton.styleFrom(backgroundColor: kBPrimary, foregroundColor: kBBg),
              child: Text(widget.isNew ? 'Créer le projet' : 'Enregistrer'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _phaseRow(int i) {
    final ph = _phases[i];
    final bad = ph.end.isBefore(ph.start);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          flex: 5,
          child: TextField(
            controller: _phaseCtrls[i],
            style: const TextStyle(color: kBText, fontSize: 13.5),
            decoration: InputDecoration(isDense: true, hintText: 'Phase ${i + 1}'),
          ),
        ),
        const SizedBox(width: 10),
        _miniDate(_fmt(ph.start), () async {
          final d = await _pick(ph.start);
          if (d != null) setState(() => ph.start = d);
        }),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('→', style: TextStyle(color: kBText4)),
        ),
        _miniDate(_fmt(ph.end), () async {
          final d = await _pick(ph.end);
          if (d != null) setState(() => ph.end = d);
        }, error: bad),
        IconButton(
          tooltip: 'Supprimer la phase',
          icon: const Icon(Icons.close, size: 16, color: kBText4),
          visualDensity: VisualDensity.compact,
          onPressed: () => _removePhase(i),
        ),
      ]),
    );
  }

  Widget _section(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3));

  Widget _dateField(String label, String value, VoidCallback onTap,
      {VoidCallback? onClear, String? error}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          errorText: error,
          suffixIcon: onClear != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact)
              : const Icon(Icons.calendar_today_outlined, size: 16),
        ),
        child: Text(value,
            style: TextStyle(
                fontSize: 14, color: value == '—' ? kBText4 : kBText)),
      ),
    );
  }

  Widget _miniDate(String value, VoidCallback onTap, {bool error = false}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: error ? kBAlert : kBLine),
          ),
          child: Text(value,
              style: TextStyle(
                  fontSize: 12.5,
                  color: error ? kBAlert : kBText2,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      );
}
