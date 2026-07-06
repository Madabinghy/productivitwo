import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/gamification_flags.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';

Future<void> showDayReviewSheet(
  BuildContext context, {
  required AppLogic logic,
  List<Project> projects = const [],
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DayReviewSheet(logic: logic, projects: projects),
  );
}

class _DayReviewSheet extends StatefulWidget {
  final AppLogic logic;
  final List<Project> projects;
  const _DayReviewSheet({required this.logic, this.projects = const []});

  @override
  State<_DayReviewSheet> createState() => _DayReviewSheetState();
}

class _DayReviewSheetState extends State<_DayReviewSheet> {
  AppLogic get logic => widget.logic;
  AppState get st => logic.state;

  bool _showRoutines = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final ymd = yyyymmdd(today);

    // ── Score ──────────────────────────────────────────────────────────────
    final score = logic.dailyScore(ymd);
    final scorePct = (score * 100).round();

    // ── Sous-actions Gantt cochées aujourd'hui ─────────────────────────────
    final List<({String taskTitle, String actionTitle})> ganttDone = [];
    for (final project in widget.projects) {
      for (final task in project.tasks) {
        for (final action in task.actions) {
          if (action.done && action.doneAt != null) {
            final d = action.doneAt!;
            if (d.year == today.year && d.month == today.month && d.day == today.day) {
              ganttDone.add((taskTitle: task.title, actionTitle: action.title));
            }
          }
        }
      }
    }

    // ── Routines ───────────────────────────────────────────────────────────
    final routines = st.activities
        .where((a) =>
            a.isHabit && logic.effectiveHabitFreq(a) == HabitFreq.daily)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final routinesDone =
        routines.where((a) => logic.habitReached(a)).length;

    // ── Badges gagnés aujourd'hui ──────────────────────────────────────────
    final todayBadges =
        st.earnedBadges.where((b) => b.earnedAt == ymd).toList();
    final lv = logic.userLevelData();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Text(
            'Résumé du ${_formatDate(today)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 20),

          // ── Score ─────────────────────────────────────────────────────────
          _ScoreCard(score: score, scorePct: scorePct, cs: cs),
          const SizedBox(height: 20),

          // ── Or provisoire du jour (crédité au total ce soir) ──────────────
          // Coupé avec l'ancienne gamification (kOldGamificationEnabled).
          if (kOldGamificationEnabled)
            Builder(builder: (_) {
            final todayXp = logic.provisionalGoldToday();
            if (todayXp <= 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                children: [
                  const Text('⭐', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text('+$todayXp XP aujourd\'hui',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cs.primary)),
                ],
              ),
            );
          }),

          // ── Sous-actions Gantt cochées aujourd'hui ────────────────────────
          if (ganttDone.isNotEmpty) ...[
            _sectionHeader(
              cs,
              icon: Icons.account_tree_outlined,
              title: 'Projets  ${ganttDone.length} sous-action${ganttDone.length > 1 ? 's' : ''}',
            ),
            const SizedBox(height: 8),
            for (final item in ganttDone)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: Colors.green.shade400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurface.withOpacity(.8)),
                          children: [
                            TextSpan(
                              text: '${item.taskTitle} · ',
                              style: TextStyle(
                                  color: cs.onSurface.withOpacity(.45),
                                  fontSize: 12),
                            ),
                            TextSpan(text: item.actionTitle),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
          ],

          // ── Routines ──────────────────────────────────────────────────────
          _sectionHeader(
            cs,
            icon: Icons.repeat,
            title: 'Routines  $routinesDone/${routines.length}',
          ),
          const SizedBox(height: 8),
          if (routines.isNotEmpty)
            _expandable(
              cs,
              label:
                  '$routinesDone validée${routinesDone > 1 ? 's' : ''} sur ${routines.length}',
              color: cs.primary,
              expanded: _showRoutines,
              onTap: () =>
                  setState(() => _showRoutines = !_showRoutines),
              children: routines.map((a) {
                final reached = logic.habitReached(a);
                final val = logic.habitValueOn(a.id, today);
                final quota = logic.dayQuotaFor(a);
                final suffix = quota > 1 ? '  $val/$quota' : '';
                return _actionRow(cs, '${a.name}$suffix', done: reached);
              }).toList(),
            ),
          if (routines.isEmpty)
            _emptyHint(cs, 'Aucune routine quotidienne configurée.'),
          const SizedBox(height: 20),

          // ── Badges ────────────────────────────────────────────────────────
          // Section coupée avec l'ancienne gamification (kOldGamificationEnabled).
          if (kOldGamificationEnabled) ...[
            _sectionHeader(cs, icon: Icons.emoji_events_outlined, title: 'Badges & XP'),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.star, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${lv.xp} XP — Niveau ${lv.level} ${lv.title}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary),
                  ),
                ],
              ),
            ),
            if (todayBadges.isEmpty)
              _emptyHint(cs, 'Pas de nouveau badge aujourd\'hui.')
            else
              ...todayBadges.map((b) {
                final meta = badgeMeta(b.id);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(meta.emoji,
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(meta.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            Text(meta.description,
                                style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        cs.onSurface.withOpacity(.5))),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) {
    const months = [
      '', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    const days = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month]}';
  }

  Widget _sectionHeader(ColorScheme cs,
      {required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.onSurface.withOpacity(.5)),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: cs.onSurface.withOpacity(.7))),
      ],
    );
  }

  Widget _expandable(
    ColorScheme cs, {
    required String label,
    required Color color,
    required bool expanded,
    required VoidCallback onTap,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color)),
                const Spacer(),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: cs.onSurface.withOpacity(.4),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children),
          ),
      ],
    );
  }

  Widget _actionRow(ColorScheme cs, String title,
      {required bool done, bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: done
                ? Colors.green
                : muted
                    ? cs.onSurface.withOpacity(.3)
                    : cs.onSurface.withOpacity(.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                decoration: done ? TextDecoration.lineThrough : null,
                color: done
                    ? cs.onSurface.withOpacity(.4)
                    : muted
                        ? cs.onSurface.withOpacity(.55)
                        : cs.onSurface.withOpacity(.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text,
            style:
                TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.4))),
      );
}

// ── Score card ───────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final double score;
  final int scorePct;
  final ColorScheme cs;

  const _ScoreCard(
      {required this.score, required this.scorePct, required this.cs});

  String get _emoji {
    if (score >= 1.0) return '🎉';
    if (score >= 0.8) return '⭐';
    if (score >= 0.6) return '👍';
    if (score >= 0.4) return '📈';
    if (score >= 0.2) return '💪';
    return '🌱';
  }

  String get _label {
    if (score >= 1.0) return 'Journée parfaite !';
    if (score >= 0.8) return 'Excellente journée !';
    if (score >= 0.6) return 'Bonne journée';
    if (score >= 0.4) return 'Journée correcte';
    if (score >= 0.2) return 'Journée difficile';
    return 'Demain sera mieux';
  }

  Color get _color {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.lightGreen;
    if (score >= 0.4) return Colors.orange;
    return cs.error;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _color.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withOpacity(.2)),
      ),
      child: Row(
        children: [
          Text(_emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$scorePct%',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: _color),
                ),
                Text(_label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(.7))),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 8,
              height: 64,
              child: RotatedBox(
                quarterTurns: -1,
                child: LinearProgressIndicator(
                  value: score.clamp(0.0, 1.0),
                  backgroundColor: cs.onSurface.withOpacity(.1),
                  color: _color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
