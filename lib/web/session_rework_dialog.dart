import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/utils/intervention_builder.dart' show interventionDayLabel;
import 'package:productivitwo_v1/utils/interventions.dart';
import 'package:productivitwo_v1/utils/session_rework.dart';
import 'package:productivitwo_v1/web/desktop_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// « Retoucher la séance » (Cette semaine, 2026-11-16) : changer ce qu'on fait
/// pendant une séance sans ouvrir le projet — son thème, les actions de sa
/// préparation, les étapes de son déroulé. Renvoie true si quelque chose a été
/// enregistré (`applySessionRework` + `saveProject`).
Future<bool> showSessionReworkDialog(
  BuildContext context, {
  required Intervention session,
  required FirestoreSync sync,
  VoidCallback? onOpenProject,
}) async {
  final saved = await showDesktopDialog<bool>(
    context,
    maxWidth: 560,
    builder: (_) => _SessionReworkDialog(session: session, sync: sync, onOpenProject: onOpenProject),
  );
  return saved == true;
}

class _Line {
  final String? id;
  final TextEditingController c;
  _Line(this.id, String text) : c = TextEditingController(text: text);
}

class _SessionReworkDialog extends StatefulWidget {
  final Intervention session;
  final FirestoreSync sync;
  final VoidCallback? onOpenProject;
  const _SessionReworkDialog({required this.session, required this.sync, this.onOpenProject});

  @override
  State<_SessionReworkDialog> createState() => _SessionReworkDialogState();
}

class _SessionReworkDialogState extends State<_SessionReworkDialog> {
  late final TextEditingController _title;
  late final List<_Line> _prep;
  late final List<_Line> _steps;
  final _newPrep = TextEditingController();
  final _newStep = TextEditingController();
  bool _saving = false;

  Intervention get _s => widget.session;
  bool get _hasScript => _s.milestone.actions.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: _s.title);
    _prep = [for (final l in prepLinesOf(_s)) _Line(l.id, l.text)];
    _steps = [for (final l in stepLinesOf(_s)) _Line(l.id, l.text)];
  }

  @override
  void dispose() {
    _title.dispose();
    _newPrep.dispose();
    _newStep.dispose();
    for (final l in [..._prep, ..._steps]) {
      l.c.dispose();
    }
    super.dispose();
  }

  void _add(List<_Line> list, TextEditingController field) {
    final t = field.text.trim();
    if (t.isEmpty) return;
    setState(() {
      list.add(_Line(null, t));
      field.clear();
    });
  }

  Future<void> _save() async {
    // Une ligne tapée mais pas encore validée compte aussi.
    _add(_prep, _newPrep);
    _add(_steps, _newStep);
    setState(() => _saving = true);
    final changed = applySessionRework(
      _s,
      title: _title.text,
      prep: [for (final l in _prep) ReworkLine(l.id, l.c.text)],
      steps: _hasScript ? [for (final l in _steps) ReworkLine(l.id, l.c.text)] : null,
    );
    if (changed) await widget.sync.saveProject(_s.project);
    if (mounted) Navigator.of(context).pop(changed);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
      );

  Widget _lines(String keyPrefix, List<_Line> list, TextEditingController field, String hint) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < list.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                key: ValueKey('$keyPrefix-$i'),
                controller: list[i].c,
                style: const TextStyle(fontSize: 13.5, color: kBText),
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              ),
            ),
            IconButton(
              key: ValueKey('$keyPrefix-remove-$i'),
              tooltip: 'Retirer',
              icon: const Icon(Icons.close, size: 16, color: kBText3),
              onPressed: () => setState(() => list.removeAt(i).c.dispose()),
            ),
          ]),
        ),
      Row(children: [
        Expanded(
          child: TextField(
            key: ValueKey('$keyPrefix-new'),
            controller: field,
            onSubmitted: (_) => _add(list, field),
            style: const TextStyle(fontSize: 13.5, color: kBText),
            decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: hint),
          ),
        ),
        IconButton(
          key: ValueKey('$keyPrefix-add'),
          tooltip: 'Ajouter',
          icon: const Icon(Icons.add, size: 18, color: kBPrimary),
          onPressed: () => _add(list, field),
        ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final native = _s.native != null;
    final prepDone = _s.prep?.actions.where((a) => a.done).length ?? 0;
    final when = '${interventionDayLabel(_s.date)}${_s.timeRange != null ? ' · ${_s.timeRange}' : ''}';
    return Container(
      color: kBSurface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Retoucher la séance', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kBText)),
          const SizedBox(height: 2),
          Text('${_s.project.title} · $when', style: const TextStyle(fontSize: 12.5, color: kBText3)),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('rework-title'),
            controller: _title,
            enabled: native,
            style: const TextStyle(color: kBText),
            decoration: InputDecoration(
              labelText: 'Ce que tu fais pendant cette séance',
              helperText: native
                  ? 'Le titre de la séance : sa préparation, son bloc et sa clôture le suivent.'
                  : 'Séance d’avant les séances natives : son titre se change dans le projet.',
              helperMaxLines: 2,
            ),
          ),
          if (_s.prep != null) ...[
            _label('PRÉPARATION · ${_prep.length} À FAIRE${prepDone > 0 ? ' · $prepDone FAITE${prepDone > 1 ? 'S' : ''}' : ''}'),
            _lines('rework-prep', _prep, _newPrep, 'Ajouter une action de préparation…'),
          ],
          if (_hasScript) ...[
            _label('DÉROULÉ · ${_steps.length} ÉTAPE${_steps.length > 1 ? 'S' : ''} À VENIR'),
            _lines('rework-step', _steps, _newStep, 'Ajouter une étape (« 13h45 Fiche 01 »)…'),
          ],
          const SizedBox(height: 20),
          Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (widget.onOpenProject != null)
              TextButton.icon(
                key: const ValueKey('rework-open-project'),
                onPressed: () {
                  Navigator.of(context).pop(false);
                  widget.onOpenProject!();
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Ouvrir dans le projet'),
                style: TextButton.styleFrom(foregroundColor: kBText2),
              ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('rework-save'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: kBPrimary, foregroundColor: kBBg),
                child: const Text('Enregistrer'),
              ),
            ]),
          ]),
        ]),
      ),
    );
  }
}
