import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';

class ProductivityStatsCard extends StatelessWidget {
  final AppLogic logic;
  const ProductivityStatsCard({super.key, required this.logic});

  static const _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  Color _scoreColor(double score, ColorScheme cs, bool hasData) {
    if (!hasData) return cs.onSurface.withOpacity(.06);
    if (score <= 0) return cs.onSurface.withOpacity(.10);
    if (score >= 1.0) return Colors.green.shade500;
    if (score >= 0.8) return Colors.green.shade400;
    if (score >= 0.6) return Colors.lightGreen.shade400;
    if (score >= 0.4) return Colors.orange.shade300;
    return Colors.orange.shade200;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final weekdayAvgs = logic.weekdayAverageScores();
    final dailyScores = logic.recentDailyScores();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Titre section ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Productivité',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(.6),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Meilleur de : routines · temps · projets',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withOpacity(.4),
                ),
              ),
            ],
          ),
        ),

        // ── Heatmap ───────────────────────────────────────────────────────
        _HeatmapSection(
            dailyScores: dailyScores, cs: cs, scoreColor: _scoreColor),
        const SizedBox(height: 20),

        // ── Moyenne par jour ──────────────────────────────────────────────
        _WeekdayBarsSection(
            weekdayAvgs: weekdayAvgs,
            cs: cs,
            scoreColor: _scoreColor,
            dayLabels: _dayLabels),
      ],
    );
  }
}

// ── Heatmap ───────────────────────────────────────────────────────────────────

class _HeatmapSection extends StatelessWidget {
  final List<({String ymd, double score, bool hasData})> dailyScores;
  final ColorScheme cs;
  final Color Function(double, ColorScheme, bool) scoreColor;

  const _HeatmapSection({
    required this.dailyScores,
    required this.cs,
    required this.scoreColor,
  });

  @override
  Widget build(BuildContext context) {
    // 84 jours = 12 semaines, aligné sur lundi
    // On réorganise en colonnes (semaines) × lignes (jours)
    const cellSize = 13.0;
    const gap = 3.0;

    // Trouver le lundi de la semaine du premier jour
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Premier jour = today - 83 jours
    final firstDay = today.subtract(const Duration(days: 83));
    // Décalage pour commencer un lundi
    final offsetToMonday = (firstDay.weekday - 1) % 7;
    final startMonday = firstDay.subtract(Duration(days: offsetToMonday));

    // Nombre de semaines à afficher
    final totalDays = today.difference(startMonday).inDays + 1;
    final weeks = (totalDays / 7).ceil();

    // Map ymd → score
    final scoreMap = {
      for (final s in dailyScores) s.ymd: (score: s.score, hasData: s.hasData)
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Historique 12 semaines',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withOpacity(.45))),
            Row(children: [
              _legendDot(scoreColor(0.2, cs, true)),
              const SizedBox(width: 3),
              _legendDot(scoreColor(0.6, cs, true)),
              const SizedBox(width: 3),
              _legendDot(scoreColor(1.0, cs, true)),
              const SizedBox(width: 4),
              Text('faible → élevé',
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurface.withOpacity(.35))),
            ]),
          ],
        ),
        const SizedBox(height: 8),
        // Étiquettes jours à gauche + grille
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Labels L M M J V S D
            Column(
              children: List.generate(7, (row) => Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: SizedBox(
                  width: 12,
                  height: cellSize,
                  child: Center(
                    child: Text(
                      row.isEven ? ['L', 'M', 'V', 'D'][row ~/ 2] : '',
                      style: TextStyle(
                          fontSize: 9,
                          color: cs.onSurface.withOpacity(.35)),
                    ),
                  ),
                ),
              )),
            ),
            const SizedBox(width: 4),
            // Grille
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(weeks, (col) {
                return Padding(
                  padding: const EdgeInsets.only(right: gap),
                  child: Column(
                    children: List.generate(7, (row) {
                      final d = startMonday
                          .add(Duration(days: col * 7 + row));
                      if (d.isAfter(today)) {
                        return SizedBox(
                            height: cellSize + gap,
                            width: cellSize);
                      }
                      final ymd =
                          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
                      final entry = scoreMap[ymd];
                      final score = entry?.score ?? 0.0;
                      final hasData = entry?.hasData ?? false;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: gap),
                        child: Tooltip(
                          message:
                              '${_fmtDate(d)} : ${hasData ? '${(score * 100).round()}%' : '—'}',
                          child: Container(
                            width: cellSize,
                            height: cellSize,
                            decoration: BoxDecoration(
                              color: scoreColor(score, cs, hasData),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(2)),
      );

  String _fmtDate(DateTime d) {
    const months = ['', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
        'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${months[d.month]}';
  }
}

// ── Barres par jour de la semaine ─────────────────────────────────────────────

class _WeekdayBarsSection extends StatelessWidget {
  final List<double> weekdayAvgs;
  final ColorScheme cs;
  final Color Function(double, ColorScheme, bool) scoreColor;
  final List<String> dayLabels;

  const _WeekdayBarsSection({
    required this.weekdayAvgs,
    required this.cs,
    required this.scoreColor,
    required this.dayLabels,
  });

  @override
  Widget build(BuildContext context) {
    const barMaxHeight = 48.0;
    final now = DateTime.now();
    final todayWeekday = now.weekday - 1; // 0=Lun

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Moyenne par jour',
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withOpacity(.45))),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(7, (i) {
            final avg = weekdayAvgs[i];
            final hasData = avg >= 0;
            final pct = hasData ? avg.clamp(0.0, 1.0) : 0.0;
            final isToday = i == todayWeekday;
            final barColor = hasData
                ? scoreColor(avg, cs, true)
                : cs.onSurface.withOpacity(.08);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Pourcentage
                Text(
                  hasData ? '${(avg * 100).round()}%' : '',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(.5),
                  ),
                ),
                const SizedBox(height: 3),
                // Barre
                Container(
                  width: 28,
                  height: (pct * barMaxHeight).clamp(4.0, barMaxHeight),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                // Label jour
                Text(
                  dayLabels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday
                        ? FontWeight.w800
                        : FontWeight.normal,
                    color: isToday
                        ? cs.primary
                        : cs.onSurface.withOpacity(.5),
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}
