import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

// ─── ÉDITEUR DE DÉROULÉ (session_template) ───────────────────────────────────
//
// La playlist ordonnée d'une séance : étapes simples (+ checklist) et
// étapes-routines (compteur/palier chez la routine). Réordonnancement en
// long-press, sauvegarde explicite. Le player de Maintenant suit cet ordre.

class SessionTemplateEditor extends StatefulWidget {
  final AppLogic logic;
  final Activity activity; // l'activité-temps propriétaire
  final SessionTemplate? existing; // null = création

  const SessionTemplateEditor(
      {super.key, required this.logic, required this.activity, this.existing});

  @override
  State<SessionTemplateEditor> createState() => _SessionTemplateEditorState();
}

class _SessionTemplateEditorState extends State<SessionTemplateEditor> {
  final _sync = FirestoreSync();
  late final TextEditingController _title;
  late final List<SessionStep> _steps;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    // Copie de travail — rien n'est écrit avant « Enregistrer ».
    _steps = [
      for (final s in widget.existing?.steps ?? const <SessionStep>[])
        SessionStep(
            id: s.id,
            title: s.title,
            kind: s.kind,
            routineId: s.routineId,
            checklist: [...s.checklist]),
    ];
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Activity? _routineOf(SessionStep s) {
    if (s.routineId == null) return null;
    for (final a in widget.logic.state.activities) {
      if (a.id == s.routineId) return a;
    }
    return null;
  }

  Future<void> _addStep() async {
    final routines = widget.logic.state.activities
        .where((a) => a.isHabit && !a.deleted)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final ctrl = TextEditingController();
    final added = await showModalBottomSheet<SessionStep>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nouvelle étape',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  hintText: 'Étape simple (ex. Préparer la débroussailleuse)'),
              onSubmitted: (v) {
                final t = v.trim();
                if (t.isNotEmpty) {
                  Navigator.pop(ctx, SessionStep(title: t));
                }
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final t = ctrl.text.trim();
                  if (t.isNotEmpty) {
                    Navigator.pop(ctx, SessionStep(title: t));
                  }
                },
                child: const Text('Ajouter l\'étape'),
              ),
            ),
            if (routines.isNotEmpty) ...[
              const Divider(height: 24),
              Text('OU UNE ROUTINE (compteur, palier, streak)',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: Theme.of(ctx).colorScheme.tertiary)),
              const SizedBox(height: 4),
              SizedBox(
                height: 220,
                child: ListView(
                  children: [
                    for (final r in routines)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.repeat_rounded, size: 18),
                        title: Text(r.name),
                        onTap: () => Navigator.pop(
                            ctx,
                            SessionStep(
                                title: r.name,
                                kind: 'routine',
                                routineId: r.id)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (added != null) setState(() => _steps.add(added));
  }

  Future<void> _editChecklist(SessionStep s) async {
    final ctrl = TextEditingController(text: s.checklist.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Checklist — ${s.title}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 8,
          minLines: 3,
          decoration:
              const InputDecoration(hintText: 'Un sous-item par ligne'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('OK')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => s.checklist = ctrl.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList());
    }
    ctrl.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    final t = widget.existing ??
        SessionTemplate(title: title, activityId: widget.activity.id);
    t.title = title;
    t.steps = _steps;
    try {
      await _sync.saveSessionTemplate(t);
      if (mounted) Navigator.pop(context, t);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — rien n\'a changé, réessaie.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Nouveau déroulé'
            : 'Modifier le déroulé'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text('Activité : ${widget.activity.name} — le chrono de la séance '
              'tracera son temps là.',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Titre',
                hintText: 'Séance A — haut du corps, Couper les herbes…'),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Text('ÉTAPES',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: cs.onSurface.withOpacity(.4))),
            const Spacer(),
            TextButton.icon(
              onPressed: _addStep,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Ajouter'),
            ),
          ]),
          if (_steps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Ajoute les étapes dans l\'ordre de la séance — items simples '
                'ou routines (leur compteur et leur palier suivront).',
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withOpacity(.5)),
              ),
            ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorder: (from, to) => setState(() {
              if (to > from) to--;
              final s = _steps.removeAt(from);
              _steps.insert(to, s);
            }),
            children: [
              for (var i = 0; i < _steps.length; i++)
                ListTile(
                  key: ValueKey(_steps[i].id),
                  contentPadding: const EdgeInsets.only(left: 4, right: 40),
                  leading: Icon(
                      _steps[i].kind == 'routine'
                          ? Icons.repeat_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: _steps[i].kind == 'routine'
                          ? Colors.teal
                          : cs.onSurface.withOpacity(.5)),
                  title: Text(_steps[i].title,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  subtitle: _steps[i].kind == 'routine'
                      ? Text(
                          _routineOf(_steps[i]) != null
                              ? 'Routine · ${_routineOf(_steps[i])!.name}'
                              : 'Routine supprimée',
                          style: const TextStyle(fontSize: 11.5))
                      : _steps[i].checklist.isNotEmpty
                          ? Text('${_steps[i].checklist.length} sous-item(s)',
                              style: const TextStyle(fontSize: 11.5))
                          : null,
                  onTap: _steps[i].kind == 'check'
                      ? () => _editChecklist(_steps[i])
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _steps.removeAt(i)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Long-press pour réordonner · tap sur une étape simple pour sa '
            'checklist.',
            style:
                TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.45)),
          ),
        ],
      ),
    );
  }
}
