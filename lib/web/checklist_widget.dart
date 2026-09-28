import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// Checklist d'une action (web) : items cochables, ajout à la volée (Entrée),
/// suppression. Sans état métier : l'appelant applique la règle d'achèvement
/// (`setChecklistItem`) et persiste.
class ChecklistEditor extends StatefulWidget {
  final List<ChecklistItem> items;
  final void Function(ChecklistItem item, bool done) onToggle;
  final void Function(String title)? onAdd; // null = lecture/coche seulement
  final void Function(ChecklistItem item)? onDelete;
  final bool dense;

  const ChecklistEditor({
    super.key,
    required this.items,
    required this.onToggle,
    this.onAdd,
    this.onDelete,
    this.dense = false,
  });

  @override
  State<ChecklistEditor> createState() => _ChecklistEditorState();
}

class _ChecklistEditorState extends State<ChecklistEditor> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _adding = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isNotEmpty) widget.onAdd?.call(t);
    _ctrl.clear();
    // Reste en saisie : on enchaîne souvent plusieurs micro-actions.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.dense ? 12.0 : 12.5;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final c in widget.items)
        _Row(
          item: c,
          fontSize: size,
          onToggle: (v) => widget.onToggle(c, v),
          onDelete: widget.onDelete == null ? null : () => widget.onDelete!(c),
        ),
      if (widget.onAdd != null)
        _adding
            ? Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  const SizedBox(width: 2),
                  const Icon(Icons.add, size: 14, color: kBText4),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autofocus: true,
                      onSubmitted: (_) => _submit(),
                      onTapOutside: (_) {
                        if (_ctrl.text.trim().isEmpty) setState(() => _adding = false);
                      },
                      style: TextStyle(fontSize: size, color: kBText),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Micro-action, Entrée pour ajouter',
                        hintStyle: TextStyle(fontSize: size, color: kBText4),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Terminer',
                    icon: const Icon(Icons.close, size: 14, color: kBText4),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _ctrl.clear();
                      _adding = false;
                    }),
                  ),
                ]),
              )
            : InkWell(
                onTap: () => setState(() => _adding = true),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    const SizedBox(width: 2),
                    const Icon(Icons.add, size: 14, color: kBText4),
                    const SizedBox(width: 8),
                    Text(widget.items.isEmpty ? 'Ajouter une checklist' : 'Ajouter un item',
                        style: TextStyle(fontSize: size - .5, color: kBText4)),
                  ]),
                ),
              ),
    ]);
  }
}

class _Row extends StatefulWidget {
  final ChecklistItem item;
  final double fontSize;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onDelete;
  const _Row({required this.item, required this.fontSize, required this.onToggle, this.onDelete});

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: () => widget.onToggle(!c.done),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Icon(c.done ? Icons.check_box : Icons.check_box_outline_blank,
                size: 15, color: c.done ? kBPrimaryDark : kBText3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(c.title,
                  style: TextStyle(
                      fontSize: widget.fontSize,
                      color: c.done ? kBText4 : kBText2,
                      decoration: c.done ? TextDecoration.lineThrough : null,
                      decorationColor: kBText4)),
            ),
            if (widget.onDelete != null && _hover)
              InkWell(
                onTap: widget.onDelete,
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 13, color: kBText4),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Compteur « 2/5 » d'une action (null sans checklist).
Widget? checklistBadge(TaskAction a, {double fontSize = 11}) {
  if (a.checklist.isEmpty) return null;
  final all = a.checklistDone == a.checklistTotal;
  return Text('${a.checklistDone}/${a.checklistTotal}',
      style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: all ? kBPrimaryDark : kBText3,
          fontFeatures: const [FontFeature.tabularFigures()]));
}
