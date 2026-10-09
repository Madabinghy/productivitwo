import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show canCancelBlock, kSkipUnavailable;
import 'package:productivitwo_v1/web/desktop_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// Éditeur de bloc du programme, version desktop (refonte web § 2.3 « Modifier »).
/// Retourne le bloc modifié (ou créé) via `Navigator.pop`, ou `null` si annulé.
/// La suppression est un soft-delete : `status: 'deleted'` sur le bloc rendu.
Future<ScheduleBlock?> showScheduleBlockDialog(
  BuildContext context, {
  required ScheduleBlock block,
  bool isNew = false,
}) {
  return showDesktopDialog<ScheduleBlock>(
    context,
    maxWidth: 460,
    builder: (_) => _ScheduleBlockDialog(block: block, isNew: isNew),
  );
}

const _kCategories = [
  ('project', 'Projet'),
  ('routine', 'Routine'),
  ('personal', 'Perso'),
  ('break', 'Pause'),
];

class _ScheduleBlockDialog extends StatefulWidget {
  final ScheduleBlock block;
  final bool isNew;
  const _ScheduleBlockDialog({required this.block, required this.isNew});

  @override
  State<_ScheduleBlockDialog> createState() => _ScheduleBlockDialogState();
}

class _ScheduleBlockDialogState extends State<_ScheduleBlockDialog> {
  late final TextEditingController _title;
  late final TextEditingController _start;
  late final TextEditingController _duration;
  late String _category;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.block.title);
    _start = TextEditingController(text: widget.block.startTime);
    _duration = TextEditingController(text: '${widget.block.durationMin}');
    _category = widget.block.category;
  }

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _duration.dispose();
    super.dispose();
  }

  String? get _startError {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_start.text.trim());
    if (m == null) return 'Format HH:mm';
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return 'Heure invalide';
    return null;
  }

  String? get _durationError {
    final d = int.tryParse(_duration.text.trim());
    if (d == null || d <= 0) return 'Minutes > 0';
    if (d > 12 * 60) return '12 h max';
    return null;
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty &&
      _startError == null &&
      _durationError == null;

  ScheduleBlock _result({String? status}) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_start.text.trim())!;
    final b = widget.block;
    b.title = _title.text.trim();
    b.startTime =
        '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
    b.durationMin = int.parse(_duration.text.trim());
    b.category = _category;
    if (status != null) b.status = status;
    return b;
  }

  Future<void> _pickTime() async {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_start.text.trim());
    final initial = m == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!));
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t == null) return;
    setState(() => _start.text =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final linked = widget.block.projectId != null || widget.block.activityId != null;
    return Container(
      color: kBSurface,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.isNew ? 'Nouveau bloc' : 'Modifier le bloc',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: kBText)),
          const SizedBox(height: 18),
          TextField(
            controller: _title,
            autofocus: widget.isNew,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: kBText),
            decoration: const InputDecoration(labelText: 'Titre'),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _start,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: kBText, fontFeatures: [FontFeature.tabularFigures()]),
                decoration: InputDecoration(
                  labelText: 'Début',
                  hintText: 'HH:mm',
                  errorText: _start.text.isEmpty ? null : _startError,
                  suffixIcon: IconButton(
                    tooltip: 'Choisir l\'heure',
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    onPressed: _pickTime,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _duration,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: kBText, fontFeatures: [FontFeature.tabularFigures()]),
                decoration: InputDecoration(
                  labelText: 'Durée (min)',
                  errorText: _duration.text.isEmpty ? null : _durationError,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          Wrap(spacing: 8, children: [
            for (final (id, label) in _kCategories)
              ChoiceChip(
                label: Text(label),
                selected: _category == id,
                avatar: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: kBCategoryColor[id],
                      borderRadius: BorderRadius.circular(3)),
                ),
                onSelected: (_) => setState(() => _category = id),
              ),
          ]),
          if (linked) ...[
            const SizedBox(height: 12),
            const Text(
              'Bloc lié à un projet ou une activité : le lien est conservé.',
              style: TextStyle(fontSize: 12, color: kBText3),
            ),
          ],
          const SizedBox(height: 22),
          Row(children: [
            if (!widget.isNew)
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_result(status: 'deleted')),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Supprimer'),
                style: TextButton.styleFrom(foregroundColor: kBAlert),
              ),
            if (!widget.isNew && canCancelBlock(widget.block))
              Tooltip(
                message: 'Annuler ce bloc : il sort du programme, sans report ni déplacement',
                child: TextButton.icon(
                  onPressed: _valid
                      ? () {
                          final b = _result(status: 'skipped');
                          b.skipReason = kSkipUnavailable;
                          Navigator.of(context).pop(b);
                        }
                      : null,
                  icon: const Icon(Icons.event_busy_rounded, size: 18),
                  label: const Text('Pas disponible'),
                  style: TextButton.styleFrom(foregroundColor: kBText2),
                ),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _valid ? () => Navigator.of(context).pop(_result()) : null,
              style: FilledButton.styleFrom(
                  backgroundColor: kBPrimary, foregroundColor: kBBg),
              child: Text(widget.isNew ? 'Ajouter' : 'Enregistrer'),
            ),
          ]),
        ],
      ),
    );
  }
}
