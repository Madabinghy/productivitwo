import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// « Chronos du jour » (web, 2026-10) : les sessions de la journée, comme la
/// feuille « Dernières 24 h » du mobile — voir, corriger début / fin /
/// activité, supprimer, et **rattacher après coup à un bloc du programme**
/// (`attachSessionToBlock` : la session prend la tâche et l'action du bloc,
/// son temps compte alors pour lui).
class SessionsCard extends StatelessWidget {
  final String date; // YYYY-MM-DD
  final List<Session> sessions;
  final List<ScheduleBlock> blocks;
  final List<Activity> activities;
  final List<Project> projects;
  final List<Domain> domains;
  final FirestoreSync sync;
  final VoidCallback onChanged;
  const SessionsCard({
    super.key,
    required this.date,
    required this.sessions,
    required this.blocks,
    required this.activities,
    required this.projects,
    required this.domains,
    required this.sync,
    required this.onChanged,
  });

  DateTime get _day => DateTime.parse(date);

  List<Session> get _ofDay {
    final d = _day, next = d.add(const Duration(days: 1));
    return sessions
        .where((s) => !s.deleted && s.startAt.isBefore(next) && (s.endAt ?? DateTime.now()).isAfter(d))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  Activity? _act(String? id) => id == null ? null : activities.where((a) => a.id == id).firstOrNull;
  Project? _proj(String? id) => id == null ? null : projects.where((p) => p.id == id).firstOrNull;

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Bloc que la session sert (même règle d'affichage que la frise).
  ScheduleBlock? _blockOf(Session s) => blocks
      .where((b) => b.status != 'deleted')
      .where((b) => sessionMatchesBlock(s, b,
          projectLinkedActivityId: _proj(b.projectId)?.linkedActivityId,
          activityLinkedActivityId: _act(b.activityId)?.linkedActivityId))
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final list = _ofDay;
    final total = list.fold<int>(0, (n, s) => n + s.duration.inMinutes);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: kBSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('CHRONOS DU JOUR',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
          const Spacer(),
          Text(list.isEmpty ? '—' : '${list.length} · ${fmtMin(total)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kBText3)),
        ]),
        const SizedBox(height: 6),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('Aucun chrono aujourd\'hui.', style: TextStyle(fontSize: 13, color: kBText3)),
          ),
        for (final s in list) _row(context, s),
      ]),
    );
  }

  Widget _row(BuildContext context, Session s) {
    final a = _act(s.activityId);
    final color = domainColor(a?.domainId, domains) ?? kBPrimary;
    final b = _blockOf(s);
    final open = s.endAt == null;
    return InkWell(
      onTap: () => _edit(context, s),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(width: 4, height: 30, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a?.name ?? 'Activité',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kBText)),
              Text(
                '${_hm(s.startAt)} → ${open ? 'en cours' : _hm(s.endAt!)} · ${fmtMin(s.duration.inMinutes)}'
                '${b != null ? ' · ${b.title}' : ' · hors bloc'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: b != null || open ? kBText3 : kBAttention),
              ),
            ]),
          ),
          IconButton(
            tooltip: 'Modifier · rattacher à un bloc',
            icon: const Icon(Icons.edit_outlined, size: 16, color: kBText3),
            visualDensity: VisualDensity.compact,
            onPressed: () => _edit(context, s),
          ),
          IconButton(
            tooltip: 'Supprimer ce chrono',
            icon: const Icon(Icons.delete_outline, size: 16, color: kBText4),
            visualDensity: VisualDensity.compact,
            onPressed: () => _delete(context, s),
          ),
        ]),
      ),
    );
  }

  Future<void> _delete(BuildContext context, Session s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Supprimer ce chrono ?'),
        content: Text('${_act(s.activityId)?.name ?? 'Activité'} · ${_hm(s.startAt)} → '
            '${s.endAt == null ? 'en cours' : _hm(s.endAt!)} (${fmtMin(s.duration.inMinutes)}). '
            'Le temps ne comptera plus nulle part.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await sync.deleteSession(s.id);
    onChanged();
  }

  Future<void> _edit(BuildContext context, Session s) async {
    final start = TextEditingController(text: _hm(s.startAt));
    final end = TextEditingController(text: s.endAt == null ? '' : _hm(s.endAt!));
    String activityId = s.activityId;
    final candidates = blockCandidatesForSession(s, blocks, _day, activityOf: _act, projectOf: _proj);
    ScheduleBlock? block = _blockOf(s);
    bool detach = false;
    String? error;
    final acts = activities.where((a) => !a.isHabit && !a.deleted).toList()
      ..sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
    if (acts.every((a) => a.id != activityId)) {
      final cur = _act(activityId);
      if (cur != null) acts.insert(0, cur);
    }

    DateTime? parse(String hm, {bool allowEmpty = false}) {
      final t = hm.trim();
      if (t.isEmpty) return allowEmpty ? null : DateTime(0);
      final m = RegExp(r'^(\d{1,2})[:h](\d{2})$').firstMatch(t);
      if (m == null) return DateTime(0);
      final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
      if (h > 23 || mi > 59) return DateTime(0);
      return DateTime(_day.year, _day.month, _day.day, h, mi);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setSt) => AlertDialog(
          title: const Text('Modifier le chrono'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                value: activityId,
                decoration: const InputDecoration(labelText: 'Activité', border: OutlineInputBorder(), isDense: true),
                items: [for (final a in acts) DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setSt(() => activityId = v ?? activityId),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: start,
                    decoration: const InputDecoration(labelText: 'Début', hintText: '09:00', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: end,
                    decoration: const InputDecoration(
                        labelText: 'Fin (vide = en cours)', hintText: '11:00', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: detach ? '' : block?.id ?? '',
                decoration: const InputDecoration(
                    labelText: 'Bloc du programme (le temps compte pour lui)',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Aucun — hors bloc')),
                  for (final c in candidates)
                    DropdownMenuItem(
                      value: c.block.id,
                      child: Text(
                        '${c.block.startTime} · ${c.block.title}${c.overlapMin > 0 ? ' (${c.overlapMin} min en commun)' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setSt(() {
                  if (v == null || v.isEmpty) {
                    block = null;
                    detach = true;
                  } else {
                    block = candidates.firstWhere((c) => c.block.id == v).block;
                    detach = false;
                  }
                }),
              ),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Aucun bloc rattachable ce jour (il faut un bloc de tâche ou d\'activité).',
                      style: TextStyle(fontSize: 11.5, color: kBText4)),
                ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(fontSize: 12.5, color: kBAlert)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final st = parse(start.text);
                final en = parse(end.text, allowEmpty: true);
                if (st == null || st.year == 0 || (en != null && en.year == 0)) {
                  setSt(() => error = 'Heures au format HH:mm.');
                } else if (en != null && !en.isAfter(st)) {
                  setSt(() => error = 'La fin doit être après le début.');
                } else {
                  Navigator.pop(d, true);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    final st = parse(start.text), en = parse(end.text, allowEmpty: true);
    start.dispose();
    end.dispose();
    if (ok != true || st == null) return;

    s.startAt = st;
    s.endAt = en;
    s.activityId = activityId;
    if (detach) {
      s.taskId = null;
      s.actionId = null;
    } else if (block != null) {
      final r = attachSessionToBlock(s, block!,
          blockActivity: _act(block!.activityId), project: _proj(block!.projectId));
      if (r == AttachResult.sessionAndBlock) {
        // Le bloc prend l'activité du chrono (le chrono fait foi).
        await sync.upsertScheduleBlock(date, block!);
      }
    }
    await sync.saveSession(s);
    onChanged();
  }
}
