import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/focus_context.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/web/checklist_widget.dart';
import 'package:productivitwo_v1/web/document_viewer_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// Bande Focus (Aujourd'hui web) : quand un chrono tourne sur une action, la
/// carte MAINTENANT se déploie en pleine largeur — étapes à gauche, contexte
/// à droite. Sans état propre : tout vient du parent (session, blocs,
/// projets) qui persiste via `FirestoreSync`.
class FocusBand extends StatelessWidget {
  final FocusTarget target;
  final Session open;
  final List<ScheduleBlock> blocks;
  final StrategicObjective? objective;
  final List<Map<String, dynamic>> documents;
  final FirestoreSync sync;
  final void Function(Project project, {String? taskId}) onOpenProject;
  final Future<void> Function(TaskAction a, ChecklistItem c, bool done) onToggleChecklist;
  final Future<void> Function(TaskAction a, String title) onAddChecklist;
  final Future<void> Function(TaskAction a, bool done) onToggleAction;
  final VoidCallback onPause;
  final VoidCallback onDone;
  /// Tiroir (barre du haut, autres onglets) : tout en colonne, bouton ✕.
  final bool compact;
  final VoidCallback? onClose;

  const FocusBand({
    super.key,
    required this.target,
    required this.open,
    required this.blocks,
    required this.objective,
    required this.documents,
    required this.sync,
    required this.onOpenProject,
    required this.onToggleChecklist,
    required this.onAddChecklist,
    required this.onToggleAction,
    required this.onPause,
    required this.onDone,
    this.compact = false,
    this.onClose,
  });

  static const _tabular = [FontFeature.tabularFigures()];

  String _clock(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  String _hm(int min) =>
      '${(min ~/ 60) % 24}:${(min % 60).toString().padLeft(2, '0')}';

  String _date(DateTime d) {
    const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final t = target;
    final b = t.block;
    final elapsed = DateTime.now().difference(open.startAt);
    final totalMin = b?.durationMin ?? 0;
    final progress = totalMin > 0 ? (elapsed.inSeconds / (totalMin * 60)).clamp(0.0, 1.0) : 0.0;
    final ctx = t.action.primaryContext;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF11261B), kBSurface]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBPrimary.withOpacity(.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── En-tête : anneau, fil, titre, boutons ─────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 12,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 56, height: 56,
                    child: CustomPaint(
                      painter: _SmallRing(progress),
                      child: Center(
                        child: Text(_clock(elapsed),
                            style: const TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w700,
                                color: kBText, fontFeatures: _tabular)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => onOpenProject(t.project, taskId: t.task.id),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: t.project.title,
                                style: const TextStyle(color: Color(0xFF5BA4F5))),
                            if (t.phase != null) TextSpan(text: ' › ${t.phase!.label}'),
                            TextSpan(text: ' › ${t.task.title}'),
                          ]),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600, color: kBText3),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                        Text(t.action.title,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800,
                                color: kBText, height: 1.2, letterSpacing: -.2)),
                        if (ctx != null) _chip(ctx),
                      ]),
                    ]),
                  ),
                ]),
              ),
              if (compact)
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18, color: kBText3),
                )
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _btn('Pause', onPause),
                  const SizedBox(width: 8),
                  _btn('Terminé', onDone, primary: true),
                ]),
            ],
          ),
        ),
        const Divider(height: 1, color: kBLine),
        // ── Corps : étapes | contexte ─────────────────────────────────────
        LayoutBuilder(builder: (ctx, box) {
          final narrow = compact || box.maxWidth < 820;
          final steps = Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16), child: _steps(context));
          final info = Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16), child: _context(context));
          if (narrow) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              steps,
              const Divider(height: 1, color: kBLine),
              info,
              if (compact) ...[
                const Divider(height: 1, color: kBLine),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: Row(children: [
                    Expanded(child: _btn('Pause', onPause)),
                    const SizedBox(width: 8),
                    Expanded(child: _btn('Terminé', onDone, primary: true)),
                  ]),
                ),
              ],
            ]);
          }
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 115, child: steps),
              const VerticalDivider(width: 1, color: kBLine),
              Expanded(flex: 100, child: info),
            ]),
          );
        }),
      ]),
    );
  }

  // ── Étapes ──────────────────────────────────────────────────────────────
  Widget _steps(BuildContext context) {
    final t = target;
    final a = t.action;
    if (t.stepsAreTaskActions) {
      final list = taskSteps(t.task);
      final done = list.where((x) => x.done).length;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('ÉTAPES', trailing: '$done / ${list.length} · actions de la tâche'),
        const SizedBox(height: 10),
        for (final x in list) _stepRow(x.title, x.done, current: x.id == a.id,
            onTap: () => onToggleAction(x, !x.done)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('ÉTAPES',
          trailing: a.checklist.isEmpty
              ? 'aucune — ajoute la première'
              : '${a.checklistDone} / ${a.checklistTotal} · dernière cochée = action faite'),
      const SizedBox(height: 10),
      ChecklistEditor(
        items: a.checklist,
        onToggle: (c, v) => onToggleChecklist(a, c, v),
        onAdd: (title) => onAddChecklist(a, title),
      ),
    ]);
  }

  Widget _stepRow(String title, bool done, {required bool current, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: current ? kBActive : const Color(0x06FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: current ? Border.all(color: kBPrimary.withOpacity(.35)) : null,
        ),
        child: Row(children: [
          Icon(done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 18, color: done ? kBPrimary : kBText4),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 13.5,
                    color: done ? kBText4 : kBText,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: kBText4)),
          ),
        ]),
      ),
    );
  }

  // ── Contexte ────────────────────────────────────────────────────────────
  Widget _context(BuildContext context) {
    final t = target;
    final spec = taskSpecLines(t.task);
    final desc = t.task.description?.trim();
    final due = t.task.endDate;
    final b = t.block;
    final next = b != null ? nextBlockAfter(blocks, b) : null;
    final nextStep = nextStepAfter(t.task, t.action);
    final why = <String>[
      if (objective != null) 'Objectif « ${objective!.title} »',
      if (due != null) 'échéance ${_date(due)}',
      if (b != null) 'bloc jusqu\'à ${_hm(blockEndMin(b))}',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('CONTEXTE'),
      const SizedBox(height: 10),
      if (why.isNotEmpty) _kv('Pourquoi', Text(why.join(' · '), style: _v)),
      if (spec.isNotEmpty)
        _kv('Consignes de la tâche', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in spec)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 84, child: Text(l.label,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kBText3))),
                Expanded(child: Text(l.text, style: _v)),
              ]),
            ),
        ]))
      else if (desc != null && desc.isNotEmpty)
        _kv('Description', Text(desc, style: _v, maxLines: 4, overflow: TextOverflow.ellipsis)),
      if (documents.isNotEmpty)
        _kv('Documents liés', Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in documents) _docChip(context, d),
        ])),
      if (next != null || nextStep != null)
        _kv('Ensuite', Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0x08FFFFFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBLine),
          ),
          child: Row(children: [
            const Text('→', style: TextStyle(color: kBText4)),
            const SizedBox(width: 10),
            Expanded(
              child: next != null
                  ? Text.rich(TextSpan(children: [
                      TextSpan(text: next.title, style: const TextStyle(color: kBText)),
                      TextSpan(text: '  ${_hm(blockStartMin(next))}',
                          style: const TextStyle(color: kBText2, fontWeight: FontWeight.w700, fontFeatures: _tabular)),
                    ]), style: _v, maxLines: 1, overflow: TextOverflow.ellipsis)
                  : Text('${nextStep!.title}  · même tâche', style: _v, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
        )),
    ]);
  }

  static const _v = TextStyle(fontSize: 13, color: kBText2, height: 1.4);

  Widget _kv(String k, Widget v) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1, color: kBText4)),
          const SizedBox(height: 4),
          v,
        ]),
      );

  Widget _docChip(BuildContext context, Map<String, dynamic> d) {
    final title = (d['title'] as String?) ?? 'Document';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => DocumentViewerDialog(
          projectTitle: target.project.title,
          documents: [d, ...documents.where((x) => x != d)],
          sync: sync,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.description_outlined, size: 14, color: kBText3),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: kBText2)),
          ),
        ]),
      ),
    );
  }

  // ── Atomes ──────────────────────────────────────────────────────────────
  Widget _label(String text, {String? trailing}) => Row(children: [
        Text(text,
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
        if (trailing != null) ...[
          const Spacer(),
          Flexible(
            child: Text(trailing, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: kBText4)),
          ),
        ],
      ]);

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: kBRaised, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kBText2)),
      );

  Widget _btn(String label, VoidCallback onTap, {bool primary = false}) => SizedBox(
        height: 38,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: primary ? kBPrimary : const Color(0x12FFFFFF),
            foregroundColor: primary ? kBBg : kBText,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: TextStyle(
                fontSize: 13, fontWeight: primary ? FontWeight.w700 : FontWeight.w600),
          ),
          child: Text(label),
        ),
      );
}

class _SmallRing extends CustomPainter {
  final double progress;
  _SmallRing(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 3;
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = kBRaised);
    if (progress > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -1.5708, 6.2832 * progress, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..color = kBPrimary);
    }
  }

  @override
  bool shouldRepaint(_SmallRing old) => old.progress != progress;
}
