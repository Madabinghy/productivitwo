import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

/// Sélecteur de contexte GTD (@maison, @bureau…) : chips défauts + customs
/// + « + Nouveau… ». [value] = contexte courant (null = sans contexte).
/// Partagé web + mobile (dialogs d'action, sheets de création).
class ContextPicker extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final FirestoreSync sync;

  const ContextPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.sync,
  });

  @override
  State<ContextPicker> createState() => _ContextPickerState();
}

class _ContextPickerState extends State<ContextPicker> {
  List<String> _contexts = List.of(kDefaultGtdContexts);

  @override
  void initState() {
    super.initState();
    widget.sync.fetchAvailableContexts().then((list) {
      if (mounted) setState(() => _contexts = list);
    });
  }

  Future<void> _addNew() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau contexte'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex : @atelier'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Ajouter')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final normalized = result.startsWith('@') ? result : '@$result';
    await widget.sync.addCustomContext(normalized);
    if (!mounted) return;
    setState(() {
      if (!_contexts.contains(normalized)) _contexts.add(normalized);
    });
    widget.onChanged(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in _contexts)
          ChoiceChip(
            selected: widget.value == c,
            onSelected: (_) =>
                widget.onChanged(widget.value == c ? null : c),
            showCheckmark: false,
            label: Text(c),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight:
                  widget.value == c ? FontWeight.w600 : FontWeight.w500,
              color: widget.value == c
                  ? cs.primary
                  : cs.onSurface.withOpacity(.65),
            ),
            selectedColor: cs.primary.withOpacity(.14),
            backgroundColor: cs.surfaceVariant.withOpacity(.35),
            side: BorderSide(
                color: widget.value == c
                    ? cs.primary.withOpacity(.5)
                    : Colors.transparent),
            visualDensity: VisualDensity.compact,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ActionChip(
          onPressed: _addNew,
          avatar: Icon(Icons.add, size: 14, color: cs.onSurface.withOpacity(.6)),
          label: const Text('Nouveau…'),
          labelStyle: TextStyle(
              fontSize: 12.5, color: cs.onSurface.withOpacity(.65)),
          backgroundColor: cs.surfaceVariant.withOpacity(.35),
          visualDensity: VisualDensity.compact,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ],
    );
  }
}
