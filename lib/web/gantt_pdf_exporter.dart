import 'dart:math';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:productivitwo_v1/models.dart';

class GanttPdfExporter {
  static const _labelW = 155.0;
  static const _rowH = 22.0;
  static const _barVPad = 5.0;

  static Future<pw.Document> build(Project project) async {
    final fontRegular = await PdfGoogleFonts.interRegular();
    final fontBold = await PdfGoogleFonts.interBold();
    final fontMedium = await PdfGoogleFonts.interMedium();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        icons: fontMedium,
      ),
    );

    final pageFormat = PdfPageFormat.a4.landscape;
    final usableW = pageFormat.availableWidth;

    final start = project.startDate;
    final end = project.endDate ?? start.add(const Duration(days: 84));
    final weeks = max(4, ((end.difference(start).inDays / 7).ceil() + 1));
    final timeW = usableW - _labelW;
    final cellW = timeW / weeks;

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Généré par Productivitwo',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey400)),
            pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey400)),
          ],
        ),
        build: (context) => [
          _buildHeader(project),
          pw.SizedBox(height: 10),
          _buildStats(project),
          pw.SizedBox(height: 14),
          _buildGantt(project, start, weeks, cellW, timeW),
        ],
      ),
    );

    return doc;
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  static pw.Widget _buildHeader(Project project) {
    final endDate = project.endDate ?? project.startDate.add(const Duration(days: 84));
    final desc = project.description;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_s(project.title),
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey900)),
                  if (desc != null && desc.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Text(
                        _s(desc.length > 120 ? '${desc.substring(0, 120)}...' : desc),
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey600),
                        maxLines: 2,
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(_fmtDate(project.startDate),
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
                pw.Text(_fmtDate(endDate),
                    style: pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey500,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColors.grey200, thickness: 1),
      ],
    );
  }

  // ── Stats ───────────────────────────────────────────────────────────────────

  static pw.Widget _buildStats(Project project) {
    final realTasks = project.tasks.where((t) => !t.isMilestone).toList();
    final done = realTasks.where((t) => t.status == 'done').length;
    final total = realTasks.length;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final overdue = realTasks.where((t) =>
        t.endDate != null &&
        DateTime(t.endDate!.year, t.endDate!.month, t.endDate!.day)
            .isBefore(todayDate) &&
        t.status != 'done' &&
        t.status != 'skipped').length;
    final milestones = project.tasks.where((t) => t.isMilestone).toList();
    final milestonesReached = milestones.where((m) => m.status == 'done').length;
    final pct = total > 0 ? (done / total * 100).round() : 0;

    return pw.Row(
      children: [
        _statBox('AVANCEMENT', '$pct%', '$done / $total tâches',
            PdfColors.blue700, PdfColor(0.94, 0.97, 1.0)),
        pw.SizedBox(width: 10),
        _statBox('EN RETARD', '$overdue',
            'tâche${overdue != 1 ? 's' : ''}',
            overdue > 0 ? PdfColors.orange700 : PdfColors.green700,
            overdue > 0 ? PdfColor(1.0, 0.96, 0.91) : PdfColor(0.93, 1.0, 0.95)),
        pw.SizedBox(width: 10),
        _statBox('JALONS', '$milestonesReached / ${milestones.length}',
            'atteint${milestonesReached != 1 ? 's' : ''}',
            PdfColors.purple700, PdfColor(0.97, 0.94, 1.0)),
      ],
    );
  }

  static pw.Widget _statBox(String label, String bigValue, String subValue,
      PdfColor color, PdfColor bg) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border(
            left: pw.BorderSide(color: color, width: 3),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 6.5,
                    color: color,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.6)),
            pw.SizedBox(height: 2),
            pw.Text(bigValue,
                style: pw.TextStyle(
                    fontSize: 20,
                    color: PdfColors.grey900,
                    fontWeight: pw.FontWeight.bold)),
            pw.Text(subValue,
                style: pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      ),
    );
  }

  // ── Gantt ───────────────────────────────────────────────────────────────────

  static pw.Widget _buildGantt(Project project, DateTime start, int weeks,
      double cellW, double timeW) {
    final groups = _buildGroups(project.tasks);
    final totalW = _labelW + timeW;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (project.phases.isNotEmpty)
          _buildPhaseHeader(project, start, cellW, timeW, totalW),
        _buildWeekHeader(start, weeks, cellW, timeW),
        for (final group in groups) ...[
          if (group.label.isNotEmpty)
            _buildGroupRow(group.label, timeW, totalW),
          for (final task in group.tasks)
            _buildTaskRow(task, project.startDate, weeks, cellW, timeW),
        ],
      ],
    );
  }

  static pw.Widget _buildPhaseHeader(Project project, DateTime start,
      double cellW, double timeW, double totalW) {
    return pw.SizedBox(
      width: totalW,
      height: 16,
      child: pw.Row(
        children: [
          pw.SizedBox(width: _labelW),
          pw.SizedBox(
            width: timeW,
            height: 16,
            child: pw.Stack(
              children: project.phases.map((phase) {
                final left = max(
                    0.0,
                    _toX(phase.startDate.difference(start).inDays, cellW));
                final right = min(
                    timeW,
                    _toX(phase.endDate.difference(start).inDays, cellW));
                final w = max(0.0, right - left);
                if (w <= 0) return pw.SizedBox.shrink();
                final bg = _pdfHex(phase.color, PdfColors.purple300);
                return pw.Positioned(
                  left: left,
                  top: 0,
                  child: pw.SizedBox(
                    width: w - 1,
                    height: 16,
                    child: pw.Container(
                      color: bg,
                      padding:
                          const pw.EdgeInsets.symmetric(horizontal: 3),
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        _s(phase.label),
                        style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white),
                        overflow: pw.TextOverflow.clip,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildWeekHeader(
      DateTime start, int weeks, double cellW, double timeW) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: _labelW,
          height: 16,
          child: pw.Container(
            color: PdfColors.grey800,
            padding: const pw.EdgeInsets.only(left: 10),
            alignment: pw.Alignment.centerLeft,
            child: pw.Text('Tâche',
                style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                    letterSpacing: 0.5)),
          ),
        ),
        ...List.generate(weeks, (i) {
          final d = start.add(Duration(days: i * 7));
          final isMonthStart = d.day <= 7;
          return pw.SizedBox(
            width: cellW,
            height: 16,
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: isMonthStart
                    ? PdfColors.grey200
                    : PdfColors.grey100,
                border: pw.Border(
                  left: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 1),
                ),
              ),
              alignment: pw.Alignment.center,
              child: pw.Text('${d.day}/${d.month}',
                  style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: isMonthStart
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                      color: PdfColors.grey700)),
            ),
          );
        }),
      ],
    );
  }

  static pw.Widget _buildGroupRow(
      String label, double timeW, double totalW) {
    return pw.SizedBox(
      width: totalW,
      height: 18,
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: _labelW,
            height: 16,
            child: pw.Container(
              color: PdfColors.grey200,
              padding: const pw.EdgeInsets.only(left: 10),
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                _s(label).toUpperCase(),
                style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                    letterSpacing: 0.8),
              ),
            ),
          ),
          pw.SizedBox(
              width: timeW,
              height: 18,
              child: pw.Container(color: PdfColors.grey200)),
        ],
      ),
    );
  }

  static pw.Widget _buildTaskRow(ProjectTask task, DateTime projectStart,
      int weeks, double cellW, double timeW) {
    final isDone = task.status == 'done';

    return pw.Row(
      children: [
        pw.SizedBox(
          width: _labelW,
          height: _rowH,
          child: pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border(
                  bottom:
                      pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
            ),
            padding: const pw.EdgeInsets.only(left: 8, right: 4),
            alignment: pw.Alignment.centerLeft,
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: 8,
                  height: 8,
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      shape: task.isMilestone
                          ? pw.BoxShape.rectangle
                          : pw.BoxShape.circle,
                      color: isDone ? PdfColors.green400 : PdfColors.grey300,
                    ),
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Text(
                    _s(task.title),
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: isDone ? PdfColors.grey400 : PdfColors.grey800,
                      decoration: isDone
                          ? pw.TextDecoration.lineThrough
                          : null,
                    ),
                    overflow: pw.TextOverflow.clip,
                  ),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(
          width: timeW,
          height: _rowH,
          child: pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Row(
                  children: List.generate(
                    weeks,
                    (i) => pw.SizedBox(
                      width: cellW,
                      height: _rowH,
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border(
                            left: pw.BorderSide(
                                color: PdfColors.grey200, width: 0.5),
                            bottom: pw.BorderSide(
                                color: PdfColors.grey200, width: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (task.isMilestone)
                _buildMilestonePdf(task, projectStart, cellW, timeW)
              else
                _buildBarPdf(task, projectStart, timeW, cellW, isDone),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildBarPdf(ProjectTask task, DateTime projectStart,
      double timeW, double cellW, bool isDone) {
    final end =
        task.endDate ?? task.startDate.add(const Duration(days: 7));
    final startDays =
        task.startDate.difference(projectStart).inDays;
    final endDays = end.difference(projectStart).inDays;
    final left = max(0.0, _toX(startDays, cellW));
    final right = min(timeW, _toX(endDays, cellW));
    final barW = max(4.0, right - left);
    final barColor =
        isDone ? PdfColors.grey300 : _pdfHex(task.color, PdfColors.deepPurple300);

    return pw.Positioned(
      left: left,
      top: _barVPad,
      child: pw.SizedBox(
        width: barW,
        height: _rowH - _barVPad * 2,
        child: pw.Container(
          decoration: pw.BoxDecoration(
            color: barColor,
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 3),
          alignment: pw.Alignment.centerLeft,
          child: task.barLabel != null
              ? pw.Text(_s(task.barLabel!),
                  style: const pw.TextStyle(
                      fontSize: 6, color: PdfColors.white),
                  overflow: pw.TextOverflow.clip)
              : null,
        ),
      ),
    );
  }

  static pw.Widget _buildMilestonePdf(ProjectTask task,
      DateTime projectStart, double cellW, double timeW) {
    final inDays =
        task.startDate.difference(projectStart).inDays;
    final centerX = _toX(inDays, cellW);
    const size = 7.0;
    final color = _pdfHex(task.color, PdfColors.deepPurple400);

    return pw.Positioned(
      left: (centerX - size / 2).clamp(0.0, timeW - size),
      top: _rowH / 2 - size / 2,
      child: pw.SizedBox(
        width: size,
        height: size,
        child: pw.Container(
          decoration: pw.BoxDecoration(
            color: color,
            shape: pw.BoxShape.circle,
          ),
        ),
      ),
    );
  }

  // ── Utilitaires ─────────────────────────────────────────────────────────────

  static double _toX(int days, double cellW) => days / 7 * cellW;

  static String _stripEmoji(String s) {
    final buf = StringBuffer();
    for (final rune in s.runes) {
      // Exclut les plages emoji et symboles
      final isEmoji = (rune >= 0x2600 && rune <= 0x27BF) ||  // Misc symbols
          (rune >= 0xFE00 && rune <= 0xFE0F) ||               // Variation selectors
          (rune >= 0x1F000 && rune <= 0x1FAFF);               // Emoji blocks
      if (!isEmoji) buf.writeCharCode(rune);
    }
    return buf.toString();
  }

  static String _s(String? s) => _stripEmoji(s ?? '')
      .replaceAll('—', '-')   // em dash —
      .replaceAll('–', '-')   // en dash –
      .replaceAll('→', '>')   // →
      .replaceAll('←', '<')   // ←
      .replaceAll('…', '...')  // …
      .replaceAll(''', "'")   // ' left single quote
      .replaceAll(''', "'")   // ' right single quote
      .replaceAll('"', '"')   // " left double quote
      .replaceAll('"', '"')   // " right double quote
      .replaceAll('·', '.')   // ·
      .replaceAll('•', '-')   // •
      .trim();

  static String _fmtDate(DateTime d) {
    const months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static PdfColor _pdfHex(String? hex, PdfColor fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    final s = hex.replaceFirst('#', '');
    if (s.length != 6) return fallback;
    try {
      final v = int.parse(s, radix: 16);
      return PdfColor(
        ((v >> 16) & 0xFF) / 255.0,
        ((v >> 8) & 0xFF) / 255.0,
        (v & 0xFF) / 255.0,
      );
    } catch (_) {
      return fallback;
    }
  }

  static List<({String label, List<ProjectTask> tasks})> _buildGroups(
      List<ProjectTask> tasks) {
    final seen = <String>[];
    final map = <String, List<ProjectTask>>{};
    for (final t in tasks) {
      final g = t.groupLabel ?? '';
      if (!seen.contains(g)) seen.add(g);
      map.putIfAbsent(g, () => []).add(t);
    }
    return seen.map((g) => (label: g, tasks: map[g]!)).toList();
  }
}
