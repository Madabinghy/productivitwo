import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

const _uuid = Uuid();
const _kGoldDefault = Color(0xFFC9A84C);
const _kGreen = Color(0xFF1D9E75);

/// Document de pilotage interactif d'un projet, affiché sous le Gantt (toggle).
/// Markdown contraint stocké dans un Document (category `playbook`).
///
/// Conventions :
///   `# Titre`              → bannière hero (titre + sous-titre = 1ʳᵉ ligne `>`/paragraphe)
///   `## 🎬 Bloc`           → ouvre une CARTE (rebord coloré = couleur du domaine)
///   `_texte_`              → ligne « objectif » en italique sous un titre
///   `> ⚠️/✅/💡 texte`       → bloc « point d'attention » coloré
///   `- [ ] N · Titre — desc` → case : N = numéro (gold), Titre gras, desc grise, pastille à droite
///   ligne(s) indentée(s) sous un item (`  ⚠️ note`) → note de l'item (couleur selon emoji)
class ProjectDocView extends StatefulWidget {
  final Project project;
  final FirestoreSync sync;
  final Color accentColor;
  final VoidCallback? onProjectChanged; // notifié quand une action Gantt liée bascule
  const ProjectDocView({
    super.key,
    required this.project,
    required this.sync,
    this.accentColor = _kGoldDefault,
    this.onProjectChanged,
  });

  @override
  State<ProjectDocView> createState() => _ProjectDocViewState();
}

class _ProjectDocViewState extends State<ProjectDocView> {
  bool _loading = true;
  bool _editing = false;
  Map<String, dynamic>? _doc;
  final _editCtrl = TextEditingController();

  Color get _accent => widget.accentColor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final docs = await widget.sync.fetchDocuments(projectId: widget.project.id);
    final pb = docs.where((d) => (d['category'] as String?) == 'playbook').toList();
    if (!mounted) return;
    setState(() {
      _doc = pb.isNotEmpty ? Map<String, dynamic>.from(pb.first) : null;
      _loading = false;
    });
    _reconcileLinkedState();
  }

  // À l'ouverture : aligne l'état [x] des items liés sur l'état réel des actions
  // Gantt (au cas où elles ont été cochées ailleurs — onglet Actions, Claude…).
  Future<void> _reconcileLinkedState() async {
    if (_doc == null || !_content.contains('^task:')) return;
    final refRe = RegExp(r'\^task:([\w-]+)/([\w-]+)');
    final lines = _content.split('\n');
    var changed = false;
    for (var i = 0; i < lines.length; i++) {
      final m = refRe.firstMatch(lines[i]);
      if (m == null) continue;
      final a = _resolveAction('${m.group(1)}/${m.group(2)}');
      if (a == null) continue;
      final desired = a.done ? '[x]' : '[ ]';
      final fixed = lines[i].replaceFirst(RegExp(r'\[[ xX]\]'), desired);
      if (fixed != lines[i]) {
        lines[i] = fixed;
        changed = true;
      }
    }
    if (changed) await _saveContent(lines.join('\n'));
  }

  String get _content => (_doc?['content'] as String?) ?? '';

  Future<void> _saveContent(String c) async {
    final doc = _doc;
    if (doc == null) return;
    doc['content'] = c;
    doc['updatedAt'] = DateTime.now().toIso8601String();
    setState(() => _doc = doc);
    await widget.sync.saveDocument(doc);
  }

  Future<void> _createStarter() async {
    final now = DateTime.now().toIso8601String();
    final starter = '# 🚀 ${widget.project.title}\n\n'
        '> 💡 Document de pilotage — demande à Claude de l\'enrichir, ou édite-le ici.\n\n'
        '## Étapes\n\n'
        '- [ ] 1 · Première étape — courte description\n'
        '- [ ] 2 · Deuxième étape\n';
    final doc = <String, dynamic>{
      'id': _uuid.v4(),
      'title': 'Pilotage — ${widget.project.title}',
      'content': starter,
      'category': 'playbook',
      'projectId': widget.project.id,
      'createdAt': now,
      'updatedAt': now,
    };
    await widget.sync.saveDocument(doc);
    if (!mounted) return;
    setState(() => _doc = doc);
  }

  Future<void> _toggleCheck(int lineIndex, bool checked) async {
    final lines = _content.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    lines[lineIndex] = checked
        ? lines[lineIndex].replaceFirst(RegExp(r'\[\s\]'), '[x]')
        : lines[lineIndex].replaceFirst(RegExp(r'\[[xX]\]'), '[ ]');
    await _saveContent(lines.join('\n'));
  }

  // Item lié à une action Gantt (^task:TID/AID) : trouve la TaskAction.
  TaskAction? _resolveAction(String taskRef) {
    final parts = taskRef.split('/');
    if (parts.length != 2) return null;
    final task = widget.project.tasks.where((t) => t.id == parts[0]).firstOrNull;
    if (task == null) return null;
    return task.actions.where((a) => a.id == parts[1]).firstOrNull;
  }

  // Toggle d'un item lié : la TaskAction est la source de vérité.
  Future<void> _toggleLinked(_Node n, TaskAction a) async {
    setState(() {
      a.done = !a.done;
      a.doneAt = a.done ? DateTime.now() : null;
    });
    await widget.sync.saveProjectTasks(widget.project.id, widget.project.tasks);
    await _toggleCheck(n.lineIndex!, a.done); // garde le markdown cohérent
    widget.onProjectChanged?.call();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_doc == null) return _emptyState(cs);
    if (_editing) return _editor(cs);

    final nodes = _parse(_content);
    String? heroTitle;
    final heroIntro = <_Node>[];
    final cards = <_CardData>[];
    _CardData? cur;
    for (final n in nodes) {
      if (n.kind == _K.heading && n.level == 1 && heroTitle == null) {
        heroTitle = n.text;
        continue;
      }
      if (n.kind == _K.heading && n.level == 2) {
        cur = _CardData(n.text);
        cards.add(cur);
        continue;
      }
      if (cur == null) {
        heroIntro.add(n);
      } else {
        cur.children.add(n);
      }
    }

    // Compteurs (items liés : état = action Gantt ; items libres : état du doc)
    var done = 0, total = 0;
    for (final n in nodes) {
      if (n.kind != _K.check) continue;
      total++;
      final a = n.taskRef != null ? _resolveAction(n.taskRef!) : null;
      if (a?.done ?? n.checked) done++;
    }

    return Column(
      children: [
        _toolbar(cs, done, total),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 60),
                children: [
                  _hero(cs, heroTitle ?? widget.project.title, heroIntro, done, total),
                  const SizedBox(height: 14),
                  for (final c in cards) _cardSection(cs, c),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _toolbar(ColorScheme cs, int d, int t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(.4))),
      ),
      child: Row(
        children: [
          Icon(Icons.checklist_rounded, size: 16, color: _accent),
          const SizedBox(width: 8),
          Text(t == 0 ? 'Document de pilotage' : '$d/$t fait',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(.6))),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: const Text('Éditer'),
            onPressed: () {
              _editCtrl.text = _content;
              setState(() => _editing = true);
            },
          ),
        ],
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────────────────

  Widget _hero(ColorScheme cs, String title, List<_Node> intro, int d, int t) {
    final subtitle = intro
        .where((n) => n.kind == _K.callout || n.kind == _K.paragraph || n.kind == _K.note)
        .map((n) => _stripLeadEmoji(n.text))
        .where((s) => s.isNotEmpty)
        .take(1)
        .join();
    final pct = t > 0 ? d / t : 0.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHighest.withOpacity(.6),
            _accent.withOpacity(.06),
          ],
        ),
        border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.4, color: cs.onSurface)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(fontSize: 13.5, color: cs.onSurface.withOpacity(.6), height: 1.5)),
          ],
          if (t > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: cs.onSurface.withOpacity(.08),
                color: _accent,
              ),
            ),
            const SizedBox(height: 8),
            Text('$d / $t fait', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _accent)),
          ],
        ],
      ),
    );
  }

  // ── Carte par bloc (rebord coloré) ───────────────────────────────────────────

  Widget _cardSection(ColorScheme cs, _CardData c) {
    // L'éventuelle ligne « objectif » (note en tête) est rendue AU-DESSUS de la carte.
    final goal = <_Node>[];
    final body = <_Node>[];
    var leading = true;
    for (final n in c.children) {
      if (leading && n.kind == _K.spacer) continue;
      if (leading && n.kind == _K.note) {
        goal.add(n);
        continue;
      }
      leading = false;
      body.add(n);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6, left: 2),
          child: Text(c.heading,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: cs.onSurface)),
        ),
        for (final g in goal)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(g.text,
                style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: cs.onSurface.withOpacity(.5))),
          ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(.4)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 3, color: _accent), // accent en HAUT de la carte
                Container(
                  color: cs.surfaceContainerHighest.withOpacity(.22),
                  padding: const EdgeInsets.fromLTRB(18, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final n in body) _renderNode(cs, n)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _renderNode(ColorScheme cs, _Node n) {
    switch (n.kind) {
      case _K.spacer:
        return const SizedBox(height: 4);
      case _K.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(n.text,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(.85))),
        );
      case _K.note:
        return Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Text(n.text,
              style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: cs.onSurface.withOpacity(.5))),
        );
      case _K.paragraph:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(n.text, style: TextStyle(fontSize: 13.5, height: 1.5, color: cs.onSurface.withOpacity(.85))),
        );
      case _K.callout:
        return _callout(cs, n.text);
      case _K.check:
        return _check(cs, n);
    }
  }

  Widget _callout(ColorScheme cs, String text) {
    Color color = const Color(0xFF5B8DEF);
    if (text.startsWith('⚠')) {
      color = const Color(0xFFE07B39);
    } else if (text.startsWith('✅')) {
      color = _kGreen;
    } else if (text.startsWith('💡')) {
      color = _kGoldDefault;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.45)),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurface.withOpacity(.9))),
    );
  }

  // ── Item : numéro · titre/desc/notes · pastille statut ───────────────────────

  Widget _check(ColorScheme cs, _Node n) {
    final linked = n.taskRef != null ? _resolveAction(n.taskRef!) : null;
    final checked = linked?.done ?? n.checked;
    void toggle() {
      if (linked != null) {
        _toggleLinked(n, linked);
      } else {
        _toggleCheck(n.lineIndex!, !n.checked);
      }
    }

    return InkWell(
      onTap: toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.22))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 42,
              child: n.numLabel != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(n.numLabel!,
                          style: TextStyle(
                              fontFamily: 'monospace', fontSize: 13.5, fontWeight: FontWeight.w700, color: _accent)),
                    )
                  : Icon(
                      checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      size: 17,
                      color: checked ? _kGreen : cs.onSurface.withOpacity(.3)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.text,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: cs.onSurface.withOpacity(checked ? .4 : .92),
                        decoration: checked ? TextDecoration.lineThrough : null,
                      )),
                  if (n.desc != null && n.desc!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(n.desc!,
                          style: TextStyle(fontSize: 12.5, height: 1.45, color: cs.onSurface.withOpacity(.55))),
                    ),
                  for (final note in n.notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(note, style: TextStyle(fontSize: 11.5, height: 1.4, color: _noteColor(note))),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _statusPill(cs, checked, linked != null),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(ColorScheme cs, bool done, bool linked) {
    final color = done ? _kGreen : cs.onSurface.withOpacity(.45);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: done ? _kGreen.withOpacity(.16) : cs.surfaceContainerHighest.withOpacity(.7),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: done ? _kGreen.withOpacity(.4) : cs.outlineVariant.withOpacity(.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (linked)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.link, size: 11, color: color),
            ),
          Text(done ? '✓ fait' : 'à faire',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Color _noteColor(String s) {
    if (s.startsWith('⚠')) return const Color(0xFFE07B39);
    if (s.startsWith('★') || s.startsWith('💡')) return _kGoldDefault;
    if (s.startsWith('✅')) return _kGreen;
    return const Color(0xFF9aa3b2);
  }

  // ── Parsing ──────────────────────────────────────────────────────────────────

  List<_Node> _parse(String content) {
    final lines = content.split('\n');
    final out = <_Node>[];
    final checkRe = RegExp(r'^[-*]\s+\[([ xX])\]\s?(.*)$');
    final headRe = RegExp(r'^(#{1,3})\s+(.*)$');
    final taskRefRe = RegExp(r'\s*\^task:([\w-]+)/([\w-]+)\s*$');
    final numRe = RegExp(r'^(\d+(?:\.\d+)*)\s*·\s*(.*)$');

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final indented = raw.startsWith('  ') || raw.startsWith('\t');
      final line = raw.trim();

      if (indented && line.isNotEmpty && out.isNotEmpty && out.last.kind == _K.check) {
        out.last.notes.add(line);
        continue;
      }
      if (line.isEmpty) {
        out.add(_Node(_K.spacer));
        continue;
      }
      final hm = headRe.firstMatch(line);
      if (hm != null) {
        out.add(_Node(_K.heading, text: hm.group(2)!.trim(), level: hm.group(1)!.length));
        continue;
      }
      final cm = checkRe.firstMatch(line);
      if (cm != null) {
        var text = cm.group(2)!.trim();
        String? taskRef;
        final tm = taskRefRe.firstMatch(text);
        if (tm != null) {
          taskRef = '${tm.group(1)}/${tm.group(2)}';
          text = text.replaceFirst(taskRefRe, '').trim();
        }
        String? numLabel;
        final nm = numRe.firstMatch(text);
        if (nm != null) {
          numLabel = nm.group(1);
          text = nm.group(2)!.trim();
        }
        String title = text;
        String? desc;
        final dash = text.indexOf(' — ');
        if (dash > 0) {
          title = text.substring(0, dash).trim();
          desc = text.substring(dash + 3).trim();
        }
        title = title.replaceAll('**', '');
        out.add(_Node(_K.check,
            text: title,
            desc: desc,
            numLabel: numLabel,
            checked: cm.group(1) != ' ',
            lineIndex: i,
            taskRef: taskRef));
        continue;
      }
      if (line.startsWith('>')) {
        out.add(_Node(_K.callout, text: line.substring(1).trim()));
        continue;
      }
      if (line.length > 2 && line.startsWith('_') && line.endsWith('_')) {
        out.add(_Node(_K.note, text: line.substring(1, line.length - 1)));
        continue;
      }
      out.add(_Node(_K.paragraph, text: line.replaceAll('**', '')));
    }
    return out;
  }

  String _stripLeadEmoji(String s) => s.replaceFirst(RegExp(r'^[^\w\s]{1,2}\s*'), '').trim();

  // ── États annexes ────────────────────────────────────────────────────────────

  Widget _emptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 40, color: cs.onSurface.withOpacity(.3)),
            const SizedBox(height: 14),
            Text('Aucun document de pilotage',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(.7))),
            const SizedBox(height: 6),
            Text(
              'Demande à Claude de créer le document de pilotage de ce projet,\nou pars d\'un document vierge.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.45), height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Créer un document vierge'),
              onPressed: _createStarter,
            ),
          ],
        ),
      ),
    );
  }

  Widget _editor(ColorScheme cs) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(.4))),
          ),
          child: Row(
            children: [
              Text('Édition markdown',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(.6))),
              const Spacer(),
              TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Annuler')),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () async {
                  await _saveContent(_editCtrl.text);
                  if (mounted) setState(() => _editing = false);
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _editCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '# Titre\n\n> 💡 Sous-titre\n\n## Bloc\n\n- [ ] 1 · Étape — description\n  ⚠️ note',
                alignLabelWithHint: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _K { spacer, heading, paragraph, note, callout, check }

class _Node {
  final _K kind;
  final String text;
  final int level;
  final bool checked;
  final int? lineIndex;
  final String? desc;
  final String? numLabel;
  final String? taskRef;
  final List<String> notes = [];
  _Node(this.kind,
      {this.text = '',
      this.level = 1,
      this.checked = false,
      this.lineIndex,
      this.desc,
      this.numLabel,
      this.taskRef});
}

class _CardData {
  final String heading;
  final List<_Node> children = [];
  _CardData(this.heading);
}
