import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

/// Sélecteur de contexte GTD (@maison, @bureau…) : chips défauts + customs
/// + « + Nouveau… ». Deux modes :
/// - mono  : [value] + [onChanged] (null = sans contexte)
/// - multi : [values] + [onValuesChanged] — une action peut être réalisable
///   dans plusieurs contextes (@maison ET @ordinateur)
/// Partagé web + mobile (dialogs d'action, sheets de création).
class ContextPicker extends StatefulWidget {
  final String? value;
  final ValueChanged<String?>? onChanged;
  final List<String>? values;
  final ValueChanged<List<String>>? onValuesChanged;
  final FirestoreSync sync;

  const ContextPicker({
    super.key,
    this.value,
    this.onChanged,
    this.values,
    this.onValuesChanged,
    required this.sync,
  }) : assert(values != null ? onValuesChanged != null : onChanged != null);

  bool get _multi => values != null;

  @override
  State<ContextPicker> createState() => _ContextPickerState();
}

class _ContextPickerState extends State<ContextPicker> {
  List<String> _contexts = List.of(kDefaultGtdContexts);
  // Sélection tenue EN INTERNE : certains parents (AlertDialog sans
  // StatefulBuilder) ne rebuildent pas au callback — sans copie locale, les
  // chips ne refléteraient jamais la sélection.
  String? _mono;
  List<String> _multi = [];

  @override
  void initState() {
    super.initState();
    _mono = widget.value;
    _multi = List.of(widget.values ?? const []);
    widget.sync.fetchAvailableContexts().then((list) {
      if (mounted) setState(() => _contexts = list);
    });
  }

  @override
  void didUpdateWidget(ContextPicker old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) _mono = widget.value;
    if (!listEquals(widget.values, old.values)) {
      _multi = List.of(widget.values ?? const []);
    }
  }

  bool _isSelected(String c) =>
      widget._multi ? _multi.contains(c) : _mono == c;

  void _toggle(String c) {
    setState(() {
      if (widget._multi) {
        _multi.contains(c) ? _multi.remove(c) : _multi.add(c);
      } else {
        _mono = _mono == c ? null : c;
      }
    });
    widget._multi
        ? widget.onValuesChanged!(List.of(_multi))
        : widget.onChanged!(_mono);
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
      if (widget._multi) {
        if (!_multi.contains(normalized)) _multi.add(normalized);
      } else {
        _mono = normalized;
      }
    });
    widget._multi
        ? widget.onValuesChanged!(List.of(_multi))
        : widget.onChanged!(normalized);
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
            selected: _isSelected(c),
            onSelected: (_) => _toggle(c),
            showCheckmark: false,
            label: Text(c),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight:
                  _isSelected(c) ? FontWeight.w600 : FontWeight.w500,
              color: _isSelected(c)
                  ? cs.primary
                  : cs.onSurface.withOpacity(.65),
            ),
            selectedColor: cs.primary.withOpacity(.14),
            backgroundColor: cs.surfaceVariant.withOpacity(.35),
            side: BorderSide(
                color: _isSelected(c)
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
