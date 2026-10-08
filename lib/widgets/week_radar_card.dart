import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show groupByFolder;
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/interventions.dart';

/// Radar « Cette semaine » mobile (onglet Projets, brief 2.1) : même logique
/// pure que la carte web (`weekRadar`). Une ligne par projet vivant : date et
/// créneau du prochain jalon, état de la prépa, clôture précédente. Tap → la
/// fiche projet sur la tâche Préparer ; ▶ sur une séance du jour → le player.
class WeekRadarCard extends StatefulWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final void Function(Project project, {String? taskId}) onOpen;
  final void Function(Project project, Intervention intervention) onPlay;
  const WeekRadarCard({
    super.key,
    required this.projects,
    required this.domains,
    required this.onOpen,
    required this.onPlay,
  });

  @override
  State<WeekRadarCard> createState() => _WeekRadarCardState();
}

class _WeekRadarCardState extends State<WeekRadarCard> {
  bool _showQuiet = false;

  static const _kDays = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  static const _kMonths = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  String _dm(DateTime d) => '${_kDays[d.weekday - 1]} ${d.day} ${_kMonths[d.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final radar = weekRadar(widget.projects, today);
    if (radar.isEmpty) return const SizedBox.shrink();
    final hot = radar.where((r) => !r.isQuiet(today)).toList();
    final quiet = radar.where((r) => r.isQuiet(today)).toList();
    final shown = _showQuiet ? radar : hot;
    final byId = {for (final r in radar) r.project.id: r};
    final groups = groupByFolder([for (final r in shown) r.project], widget.projects);
    final late = hot.where((r) => (r.daysTo(today) ?? 0) < 0).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(children: [
              Icon(Icons.radar, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text('CETTE SEMAINE',
                  style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurface.withOpacity(.5))),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${hot.length} séance${hot.length > 1 ? 's' : ''} à 14 j${late > 0 ? ' · $late en retard' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5)),
                ),
              ),
            ]),
          ),
          if (hot.isEmpty && !_showQuiet)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Text('Aucune séance dans les 14 prochains jours.',
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.55))),
            ),
          for (final g in groups) ...[
            if (g.folder != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(children: [
                  Icon(Icons.folder_outlined, size: 13, color: cs.onSurface.withOpacity(.45)),
                  const SizedBox(width: 6),
                  Text(g.folder!.title.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurface.withOpacity(.45))),
                ]),
              ),
            for (final p in g.projects) _row(cs, byId[p.id]!, today, indent: g.folder != null),
          ],
          if (quiet.isNotEmpty)
            InkWell(
              onTap: () => setState(() => _showQuiet = !_showQuiet),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Row(children: [
                  Icon(_showQuiet ? Icons.expand_less : Icons.expand_more, size: 16, color: cs.onSurface.withOpacity(.5)),
                  const SizedBox(width: 6),
                  Text(
                    _showQuiet
                        ? 'Masquer les projets sans séance à 14 j'
                        : '${quiet.length} projet${quiet.length > 1 ? 's' : ''} sans séance à 14 j · Afficher',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5)),
                  ),
                ]),
              ),
            )
          else
            const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _row(ColorScheme cs, ProjectRadar r, DateTime today, {bool indent = false}) {
    final p = r.project;
    final next = r.next;
    final prev = r.previous;
    final days = r.daysTo(today);
    final color = domainColor(p.domainId, widget.domains) ?? cs.primary;
    final dateColor = days == null
        ? cs.onSurface.withOpacity(.5)
        : days < 0
            ? cs.error
            : days <= 2
                ? Colors.orange.shade700
                : cs.onSurface;
    final when = next == null
        ? 'Pas de séance'
        : days == 0
            ? 'Aujourd\'hui'
            : days == 1
                ? 'Demain'
                : _dm(next.date);
    final time = next?.timeRange;
    String prep() => switch (next?.prepState) {
          null || PrepState.none => '',
          PrepState.done => 'Prépa faite',
          PrepState.ready => 'Prépa prête',
          PrepState.readyToPrint => 'Prépa prête à imprimer',
          PrepState.todo => 'Prépa ${next!.prepTotal - next.prepOpen}/${next.prepTotal}',
        };
    final prepText = prep();
    final prepGood = next?.prepState == PrepState.done ||
        next?.prepState == PrepState.ready ||
        next?.prepState == PrepState.readyToPrint;
    final closure = prev == null || prev.closureState == ClosureState.none
        ? null
        : prev.closureState == ClosureState.done
            ? 'Clôture du ${_dm(prev.date)} faite'
            : 'Clôture du ${_dm(prev.date)} : ${prev.closureOpen} à faire';
    final playable = next != null && days != null && days <= 0 && !next.isDone;
    final target = next?.prep?.id ?? next?.milestone.id ?? prev?.closure?.id;

    return InkWell(
      onTap: () => widget.onOpen(p, taskId: target),
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent ? 26 : 14, 8, 8, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(when,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: dateColor)),
                if (time != null) ...[
                  const SizedBox(width: 6),
                  Text(time, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
                ],
                if (days != null && days < 0) ...[
                  const SizedBox(width: 6),
                  Text('non coché', style: TextStyle(fontSize: 11, color: cs.error)),
                ],
              ]),
              const SizedBox(height: 2),
              Text(
                next == null ? p.title : '${p.title} · ${stripLeadEmoji(next.milestone.title)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(.9)),
              ),
              if (prepText.isNotEmpty || closure != null) ...[
                const SizedBox(height: 2),
                Text(
                  [if (prepText.isNotEmpty) prepText, if (closure != null) closure].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: prepGood
                          ? cs.primary
                          : (prev?.closureState == ClosureState.todo || (days != null && days <= 1))
                              ? Colors.orange.shade700
                              : cs.onSurface.withOpacity(.5)),
                ),
              ],
            ]),
          ),
          if (playable)
            IconButton(
              tooltip: 'Séance en cours',
              icon: Icon(Icons.play_circle_fill, color: cs.primary, size: 28),
              onPressed: () => widget.onPlay(p, next),
            )
          else if (next != null && next.native != null && !next.isDone)
            // Séance à venir : aperçu du déroulé (même écran, mode aperçu).
            IconButton(
              tooltip: 'Aperçu de la séance',
              icon: Icon(Icons.visibility_outlined, color: cs.onSurface.withOpacity(.5), size: 22),
              onPressed: () => widget.onPlay(p, next),
            )
          else
            Icon(Icons.chevron_right, size: 18, color: cs.onSurface.withOpacity(.35)),
        ]),
      ),
    );
  }
}
