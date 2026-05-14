import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

/// Affiche un picker de blocs et retourne l'id sélectionné,
/// '' pour désassigner, null si annulé.
Future<String?> showBlockPickerSheet(
  BuildContext context, {
  required AppLogic logic,
  String? currentBlockId,
}) async {
  final blocks = [...logic.state.blocks]
    ..sort((a, b) => a.order.compareTo(b.order));

  if (blocks.isEmpty) return null;

  return showModalBottomSheet<String>(
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
              child: Text(
                'Assigner à un bloc',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
          const Divider(height: 1),
          for (final b in blocks)
            ListTile(
              leading: Text(b.emoji ?? '📦',
                  style: const TextStyle(fontSize: 20)),
              title: Text(b.name),
              trailing:
                  b.id == currentBlockId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, b.id),
            ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Sans bloc'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> showDayBlocksSheet(
  BuildContext context, {
  required AppLogic logic,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DayBlocksSheet(logic: logic),
  );
}

class _DayBlocksSheet extends StatefulWidget {
  final AppLogic logic;
  const _DayBlocksSheet({required this.logic});

  @override
  State<_DayBlocksSheet> createState() => _DayBlocksSheetState();
}

class _DayBlocksSheetState extends State<_DayBlocksSheet> {
  AppLogic get logic => widget.logic;
  AppState get st => logic.state;

  List<DayBlock> get sortedBlocks =>
      [...st.blocks]..sort((a, b) => a.order.compareTo(b.order));

  Future<void> _createBlock() async {
    final result = await _showBlockDialog(context);
    if (result == null) return;
    logic.createBlock(result.$1, emoji: result.$2);
    setState(() {});
  }

  Future<void> _editBlock(DayBlock block) async {
    final result =
        await _showBlockDialog(context, name: block.name, emoji: block.emoji);
    if (result == null) return;
    logic.updateBlock(
      block.id,
      name: result.$1,
      emoji: result.$2,
      clearEmoji: result.$2 == null,
    );
    setState(() {});
  }

  Future<void> _deleteBlock(DayBlock block) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le bloc ?'),
        content: Text(
            'Les routines et actions assignées à "${block.name}" seront désassignées.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    logic.deleteBlock(block.id);
    setState(() {});
  }

  Future<void> _manageActivities(DayBlock block) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BlockActivitiesSheet(logic: logic, block: block),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final blocks = sortedBlocks;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, sc) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Blocs journaliers',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nouveau'),
                  onPressed: _createBlock,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: blocks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Aucun bloc pour l\'instant.',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Créer un bloc'),
                            onPressed: _createBlock,
                          ),
                        ],
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    scrollController: sc,
                    padding: const EdgeInsets.only(bottom: 32),
                    buildDefaultDragHandles: false,
                    itemCount: blocks.length,
                    onReorder: (oldIndex, newIndex) {
                      logic.reorderBlocks(oldIndex, newIndex);
                      setState(() {});
                    },
                    itemBuilder: (context, i) {
                      final b = blocks[i];
                      final habitCount = b.activityIds.length;

                      return ListTile(
                        key: ValueKey(b.id),
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle),
                        ),
                        title: Text(
                          '${b.emoji != null ? "${b.emoji} " : ""}${b.name}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          habitCount == 0
                              ? 'Aucune routine assignée'
                              : '$habitCount routine${habitCount > 1 ? "s" : ""}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Gérer les routines',
                              icon: const Icon(Icons.repeat, size: 20),
                              onPressed: () => _manageActivities(b),
                            ),
                            IconButton(
                              tooltip: 'Modifier',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _editBlock(b),
                            ),
                            IconButton(
                              tooltip: 'Supprimer',
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _deleteBlock(b),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Sheet pour assigner/retirer des routines d'un bloc
class _BlockActivitiesSheet extends StatefulWidget {
  final AppLogic logic;
  final DayBlock block;
  const _BlockActivitiesSheet({required this.logic, required this.block});

  @override
  State<_BlockActivitiesSheet> createState() => _BlockActivitiesSheetState();
}

class _BlockActivitiesSheetState extends State<_BlockActivitiesSheet> {
  AppLogic get logic => widget.logic;
  DayBlock get block => widget.block;

  List<Activity> get habits =>
      logic.state.activities.where((a) => a.isHabit).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, sc) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${block.emoji != null ? "${block.emoji} " : ""}${block.name} — Routines',
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: habits.isEmpty
                ? const Center(child: Text('Aucune routine créée.'))
                : ListView.builder(
                    controller: sc,
                    itemCount: habits.length,
                    itemBuilder: (context, i) {
                      final a = habits[i];

                      // Vérifie si cette routine est dans un autre bloc
                      final otherBlock = logic.state.blocks.firstWhereOrNull(
                        (b) =>
                            b.id != block.id && b.activityIds.contains(a.id),
                      );
                      final inThisBlock = block.activityIds.contains(a.id);

                      return CheckboxListTile(
                        value: inThisBlock,
                        title: Text(a.name),
                        subtitle: otherBlock != null && !inThisBlock
                            ? Text(
                                'Déjà dans : ${otherBlock.emoji ?? ""}${otherBlock.name}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurface.withOpacity(0.6)),
                              )
                            : null,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              // Retirer de l'autre bloc si présent
                              if (otherBlock != null) {
                                logic.removeActivityFromBlock(
                                    otherBlock.id, a.id);
                              }
                              logic.addActivityToBlock(block.id, a.id);
                            } else {
                              logic.removeActivityFromBlock(block.id, a.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Dialogue création/édition d'un bloc
Future<(String, String?)?> _showBlockDialog(
  BuildContext context, {
  String? name,
  String? emoji,
}) async {
  final nameCtrl = TextEditingController(text: name ?? '');
  final emojiCtrl = TextEditingController(text: emoji ?? '');

  return showDialog<(String, String?)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(name == null ? 'Nouveau bloc' : 'Modifier le bloc'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 60,
                child: TextField(
                  controller: emojiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Emoji',
                    hintText: '🌅',
                  ),
                  textAlign: TextAlign.center,
                  maxLength: 2,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nom du bloc'),
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) {
                    final n = nameCtrl.text.trim();
                    if (n.isEmpty) return;
                    final e = emojiCtrl.text.trim();
                    Navigator.pop(ctx, (n, e.isEmpty ? null : e));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final n = nameCtrl.text.trim();
            if (n.isEmpty) return;
            final e = emojiCtrl.text.trim();
            Navigator.pop(ctx, (n, e.isEmpty ? null : e));
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
