import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';

// ── Étapes d'une action (mobile : fiche de tâche, onglet Actions) ───────────────────────────────

/// Checklist dépliée sous une action : cocher (règle « dernière étape cochée =
/// action faite », appliquée par l'appelant), ajouter (Entrée enchaîne),
/// appui long = renommer ou retirer. Le modèle est celui du web et du MCP.
class StepsSection extends StatefulWidget {
  final TaskAction action;
  final void Function(ChecklistItem, bool) onToggle;
  final void Function(String) onAdd;
  final void Function(ChecklistItem) onRemove;
  final void Function(ChecklistItem, String) onRename;
  final double leftInset;
  const StepsSection({
    super.key,
    required this.action,
    required this.onToggle,
    required this.onAdd,
    required this.onRemove,
    required this.onRename,
    this.leftInset = 44,
  });

  @override
  State<StepsSection> createState() => _StepsSectionState();
}

class _StepsSectionState extends State<StepsSection> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    widget.onAdd(t);
    _ctrl.clear();
    _focus.requestFocus();
  }

  Future<void> _editItem(ChecklistItem c) async {
    final ctrl = TextEditingController(text: c.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Étape'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text('Retirer', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    if (result.isEmpty) {
      widget.onRemove(c);
    } else {
      widget.onRename(c, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = widget.action;
    final next = nextChecklistItem(a);
    return Padding(
      padding: EdgeInsets.only(left: widget.leftInset, right: 8, bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (a.checklist.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              'Découpe cette action en étapes : la dernière cochée la marque faite.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.45)),
            ),
          ),
        for (final c in a.checklist)
          InkWell(
            onTap: () => widget.onToggle(c, !c.done),
            onLongPress: () => _editItem(c),
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(children: [
                Icon(c.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    size: 18,
                    color: c.done
                        ? Colors.green
                        : c.id == next?.id && !a.done
                            ? cs.primary
                            : cs.onSurface.withOpacity(.35)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.title,
                      style: TextStyle(
                          fontSize: 13,
                          color: c.done ? cs.onSurface.withOpacity(.4) : cs.onSurface,
                          decoration: c.done ? TextDecoration.lineThrough : null)),
                ),
              ]),
            ),
          ),
        Row(children: [
          Icon(Icons.add, size: 18, color: cs.onSurface.withOpacity(.35)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              style: const TextStyle(fontSize: 13),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Ajouter une étape…',
                hintStyle: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.35)),
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ]),
      ]),
    );
  }
}
