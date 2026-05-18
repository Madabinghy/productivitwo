import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

class NewGoalResult {
  final String title;
  final String domainId;
  final String? firstAction;
  const NewGoalResult({
    required this.title,
    required this.domainId,
    this.firstAction,
  });
}

Future<NewGoalResult?> showNewGoalSheet(
  BuildContext context, {
  required AppLogic logic,
  String? initialDomainId,
}) {
  return showModalBottomSheet<NewGoalResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NewGoalSheet(logic: logic, initialDomainId: initialDomainId),
  );
}

class _NewGoalSheet extends StatefulWidget {
  final AppLogic logic;
  final String? initialDomainId;
  const _NewGoalSheet({required this.logic, this.initialDomainId});

  @override
  State<_NewGoalSheet> createState() => _NewGoalSheetState();
}

class _NewGoalSheetState extends State<_NewGoalSheet> {
  final _titleCtrl = TextEditingController();
  final _actionCtrl = TextEditingController();
  late String? _domainId;

  AppLogic get logic => widget.logic;
  AppState get st => logic.state;

  @override
  void initState() {
    super.initState();
    _domainId = widget.initialDomainId ?? (st.domains.isNotEmpty ? st.domains.first.id : null);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _actionCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _domainId == null) return;
    Navigator.pop(
      context,
      NewGoalResult(
        title: title,
        domainId: _domainId!,
        firstAction: _actionCtrl.text.trim().isEmpty ? null : _actionCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final domains = [...st.domains]..sort((a, b) => a.name.compareTo(b.name));
    final selectedDomain = domains.where((d) => d.id == _domainId).firstOrNull;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Nouvel objectif',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 16),

          // Titre
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Objectif',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          // Domaine
          _GoalPickerRow(
            icon: Icons.folder_outlined,
            label: 'Domaine',
            value: selectedDomain?.name,
            onTap: () => _showDomainPicker(context, domains),
          ),
          const SizedBox(height: 12),

          // Première action
          TextField(
            controller: _actionCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Première action (optionnel)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.arrow_forward_ios_rounded, size: 14),
            ),
          ),
          const SizedBox(height: 16),

          FilledButton(
            onPressed: _titleCtrl.text.trim().isEmpty || _domainId == null ? null : _submit,
            child: const Text('Ajouter'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDomainPicker(BuildContext context, List<Domain> domains) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Domaine',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final d in domains)
                    ListTile(
                      title: Text(d.name),
                      trailing: d.id == _domainId ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(ctx, d.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _domainId = picked);
  }
}

class _GoalPickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  const _GoalPickerRow({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasValue = value != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.6)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasValue ? value! : label,
                style: TextStyle(
                  color: hasValue ? cs.onSurface : cs.onSurface.withOpacity(0.5),
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurface.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}
