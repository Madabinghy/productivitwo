import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

/// Modale Gantt 14 jours (ex-Focus « Vue 14 jours »), ouverte depuis
/// « Cette semaine ».
void showWideGanttDialog(BuildContext context,
    {required List<Project> projects, required List<Domain> domains}) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => WideGanttDialog(projects: projects, domains: domains),
  );
}

Color? _parseTaskColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    final clean = hex.replaceAll('#', '').replaceAll(RegExp(r'^0[xX]'), '');
    if (clean.length == 6) return Color(int.parse('FF$clean', radix: 16));
    if (clean.length == 8) return Color(int.parse(clean, radix: 16));
  } catch (_) {}
  return null;
}

// ── Modale Gantt 14 jours ─────────────────────────────────────────────────────

class WideGanttDialog extends StatelessWidget {
  final List<Project> projects;
  final List<Domain> domains;
  const WideGanttDialog({required this.projects, required this.domains});

  static const int _numDays = 14;
  static const List<String> _shortDayNames = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  static Color _domainColor(Domain? domain, ColorScheme cs, List<Domain> allDomains) {
    if (domain == null) return cs.onSurface.withOpacity(0.4);
    if (domain.colorValue != null) return Color(domain.colorValue!);
    final idx = allDomains.indexWhere((d) => d.id == domain.id);
    if (idx >= 0) return kDomainPalette[idx % kDomainPalette.length];
    return cs.primary;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day);
    final endDate = startDate.add(const Duration(days: _numDays - 1));

    // Filtrer les tâches qui chevauchent la fenêtre 14 jours
    final pairs = <({ProjectTask task, Project project})>[];
    for (final p in projects) {
      if (p.status == 'archived' || p.status == 'done') continue;
      for (final t in p.tasks) {
        if (t.status == 'skipped') continue;
        final effectiveEnd = t.endDate ?? t.startDate;
        if (!t.startDate.isAfter(endDate) && !effectiveEnd.isBefore(startDate)) {
          pairs.add((task: t, project: p));
        }
      }
    }

    // Grouper par domaine
    final byDomain = <String?, List<({ProjectTask task, Project project})>>{};
    for (final pair in pairs) {
      byDomain.putIfAbsent(pair.project.domainId, () => []).add(pair);
    }
    final domainGroups = <({Domain? domain, List<({ProjectTask task, Project project})> pairs})>[];
    for (final d in domains) {
      if (d.deleted) continue;
      final list = byDomain[d.id] ?? [];
      if (list.isNotEmpty) domainGroups.add((domain: d, pairs: list));
    }
    final orphans = byDomain[null] ?? [];
    if (orphans.isNotEmpty) domainGroups.add((domain: null, pairs: orphans));

    return LayoutBuilder(
      builder: (ctx, screen) {
        // Dimensions modale (95% de l'écran)
        final modalW = (screen.maxWidth * 0.95).clamp(700.0, 1800.0);
        final modalH = (screen.maxHeight * 0.92).clamp(500.0, 1000.0);
        // Label fixe à gauche
        final labelW = (modalW * 0.22).clamp(180.0, 320.0);
        // 14 colonnes jours dynamiques
        const innerPadding = 24.0;
        final daysAvailableW = modalW - labelW - innerPadding * 2;
        final dayW = daysAvailableW / _numDays;
        const rowH = 30.0;
        const headerH = 50.0;
        const domainHeaderH = 26.0;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: modalW,
              constraints: BoxConstraints(maxHeight: modalH),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 14),
                    child: Row(
                      children: [
                        Icon(Icons.view_timeline_outlined, size: 18, color: cs.primary),
                        const SizedBox(width: 10),
                        Text(
                          '14 prochains jours',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_fmtDate(startDate)} → ${_fmtDate(endDate)}',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.45)),
                        ),
                        const Spacer(),
                        Text(
                          '${pairs.length} tâche${pairs.length > 1 ? 's' : ''}',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.45)),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                          tooltip: 'Fermer',
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
                  // ── Contenu Gantt ──────────────────────────────────────
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(innerPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header jours
                          Row(
                            children: [
                              SizedBox(width: labelW),
                              for (int d = 0; d < _numDays; d++)
                                _buildDayHeader(cs, startDate.add(Duration(days: d)), startDate, dayW, headerH),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Groupes domaines
                          if (domainGroups.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text(
                                  'Aucune tâche dans les 14 prochains jours',
                                  style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.35)),
                                ),
                              ),
                            )
                          else
                            for (final group in domainGroups)
                              _buildDomainGroup(cs, group.domain, group.pairs, startDate, labelW, dayW, rowH, domainHeaderH),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDayHeader(ColorScheme cs, DateTime day, DateTime startDate, double width, double height) {
    final isToday = day.year == startDate.year && day.month == startDate.month && day.day == startDate.day;
    final dayOfWeek = day.weekday; // 1=Mon..7=Sun
    final letter = _shortDayNames[dayOfWeek - 1];
    final isWeekend = dayOfWeek >= 6;

    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: isToday
              ? BoxDecoration(color: Colors.teal.withOpacity(0.15), borderRadius: BorderRadius.circular(6))
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                letter,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isToday
                      ? Colors.teal.shade700
                      : isWeekend
                          ? cs.onSurface.withOpacity(0.3)
                          : cs.onSurface.withOpacity(0.5),
                ),
              ),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                  color: isToday
                      ? Colors.teal.shade700
                      : isWeekend
                          ? cs.onSurface.withOpacity(0.4)
                          : cs.onSurface.withOpacity(0.65),
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDomainGroup(
    ColorScheme cs,
    Domain? domain,
    List<({ProjectTask task, Project project})> pairs,
    DateTime startDate,
    double labelW,
    double dayW,
    double rowH,
    double domainHeaderH,
  ) {
    final color = _domainColor(domain, cs, domains);
    final name = domain?.name ?? 'Sans domaine';
    final totalW = labelW + _numDays * dayW;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: totalW,
          child: Container(
            height: domainHeaderH,
            margin: const EdgeInsets.only(bottom: 3, top: 8),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Text(
                  name.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: color),
                ),
                const Spacer(),
                Text(
                  '${pairs.length}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.withOpacity(0.6)),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
        for (final pair in pairs)
          _buildTaskRow(cs, pair.task, pair.project, startDate, labelW, dayW, rowH, color),
      ],
    );
  }

  Widget _buildTaskRow(
    ColorScheme cs,
    ProjectTask task,
    Project project,
    DateTime startDate,
    double labelW,
    double dayW,
    double rowH,
    Color domainColor,
  ) {
    final isDone = task.status == 'done';
    final endDate = startDate.add(const Duration(days: _numDays - 1));
    final totalDayW = dayW * _numDays;

    final tStart = DateTime(task.startDate.year, task.startDate.month, task.startDate.day);
    final tEnd = task.endDate != null
        ? DateTime(task.endDate!.year, task.endDate!.month, task.endDate!.day)
        : tStart;
    final barStart = tStart.isBefore(startDate) ? startDate : tStart;
    final barEnd = tEnd.isAfter(endDate) ? endDate : tEnd;
    final startOffset = barStart.difference(startDate).inDays * dayW;
    final barDays = barEnd.difference(barStart).inDays + 1;
    final barWidth = barDays * dayW;
    final phase = project.phases.where((p) => p.id == task.phaseId).firstOrNull ??
        project.phases.where((p) => p.label == task.groupLabel).firstOrNull;
    final resolvedColor =
        _parseTaskColor(task.color) ?? _parseTaskColor(phase?.color) ?? domainColor;
    final barColor = isDone ? resolvedColor.withOpacity(0.35) : resolvedColor.withOpacity(0.75);

    return SizedBox(
      height: rowH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: labelW,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  if (isDone) ...[
                    Icon(Icons.check_circle, size: 11, color: Colors.green.shade500),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(isDone ? 0.35 : 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: totalDayW,
            height: rowH,
            child: Stack(
              children: [
                // Aujourd'hui surligné
                Positioned(
                  left: 0,
                  top: 0,
                  width: dayW,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.08),
                      border: const Border(
                        left: BorderSide(color: Color(0x2227C48F), width: 1),
                        right: BorderSide(color: Color(0x2227C48F), width: 1),
                      ),
                    ),
                  ),
                ),
                // Séparateurs verticaux légers (chaque 7e jour plus fort)
                for (int d = 0; d < _numDays; d++)
                  Positioned(
                    left: d * dayW,
                    top: 4,
                    bottom: 4,
                    width: 1,
                    child: Container(color: cs.outlineVariant.withOpacity(d == 7 ? 0.25 : 0.08)),
                  ),
                // Jalon ou barre
                if (task.isMilestone) ...[
                  Positioned(
                    left: startOffset + dayW / 2 - 6,
                    top: rowH / 2 - 6,
                    child: Transform.rotate(
                      angle: 0.785398,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isDone ? Colors.green.shade600 : Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ] else if (barWidth > 0) ...[
                  Positioned(
                    left: startOffset,
                    top: rowH / 2 - 5,
                    width: barWidth,
                    height: 10,
                    child: Container(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    const months = ['jan','fév','mar','avr','mai','juin','juil','aoû','sep','oct','nov','déc'];
    return '${d.day} ${months[d.month - 1]}';
  }
}
