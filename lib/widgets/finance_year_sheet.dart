import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/finance_charts.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/finance_sheet.dart' show kMoneyAccent, editEnvelopeCap;

/// « Mon année » (maquette validée 2026-11-03 « Finances, en courbes », lot 2) :
/// rentré · dépensé · gardé, une barre par mois découpée par enveloppe, par
/// domaine ou par fixe, puis une ligne par catégorie (total, moyenne, 12 mois,
/// tendance sur 3 mois). Tap sur une enveloppe = son année face au plafond.

const _mShort = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _mLong = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
// Ordre catégoriel fixe (jamais recyclé) ; au-delà de 8, gris.
const _kPalette = [
  Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500),
  Color(0xFFD55181), Color(0xFF2E9E2E), Color(0xFF9085E9), Color(0xFFE66767),
];
const _kGrey = Color(0xFF7D8984);
const _kAmber = Color(0xFFF0B44C);
const _kRed = Color(0xFFF07A6A);

Future<void> showFinanceYearSheet(BuildContext context, {required AppLogic logic}) =>
    showFiche<void>(context, builder: (ctx, scroll) => _YearSheet(logic: logic, scroll: scroll));

class _YearSheet extends StatefulWidget {
  final AppLogic logic;
  final ScrollController scroll;
  const _YearSheet({required this.logic, required this.scroll});
  @override
  State<_YearSheet> createState() => _YearSheetState();
}

class _YearSheetState extends State<_YearSheet> {
  late int _year = int.parse(widget.logic.livedTodayYmd.substring(0, 4));
  YearBy _by = YearBy.envelope;
  int? _month;

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.addListener(_on);
  }

  @override
  void dispose() {
    logic.removeListener(_on);
    super.dispose();
  }

  void _on() {
    if (mounted) setState(() {});
  }

  Color _colorOf(CategoryYear c, int i) {
    if (_by == YearBy.domain) {
      if (c.id.isEmpty) return _kGrey;
      return domainColor(c.id, logic.state.domains) ?? (i < _kPalette.length ? _kPalette[i] : _kGrey);
    }
    return i < _kPalette.length ? _kPalette[i] : _kGrey;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final f = logic.finances;
    final today = logic.livedTodayYmd;
    final years = financeYears(f, int.parse(today.substring(0, 4)));
    final y = yearSummary(f, _year, today);
    final cats = yearCategories(f, _year, _by, domainNames: {for (final d in logic.state.domains) d.id: d.name});
    final colors = [for (var i = 0; i < cats.length; i++) _colorOf(cats[i], i)];
    Widget stat(String v, String l, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color))),
              Text(l, style: TextStyle(fontSize: 11, color: mute)),
            ]),
          ),
        );
    Widget seg(YearBy v, String l) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _by = v;
              _month = null;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _by == v ? cs.surface : null, borderRadius: BorderRadius.circular(8)),
              child: Text(l, style: TextStyle(fontSize: 12.5, fontWeight: _by == v ? FontWeight.w700 : FontWeight.w500, color: _by == v ? null : mute)),
            ),
          ),
        );
    final sel = _month;
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Row(children: [
        const Expanded(child: Text('Mon année', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
        PopupMenuButton<int>(
          initialValue: _year,
          onSelected: (v) => setState(() {
            _year = v;
            _month = null;
          }),
          itemBuilder: (_) => [for (final v in years) PopupMenuItem(value: v, child: Text('$v'))],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: kMoneyAccent.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
            child: Text('$_year ▾', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kMoneyAccent)),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Text('−${euros(y.spentTotal)}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
      Text(
        y.spentTotal == 0
            ? 'rien de noté en $_year'
            : 'dépensé depuis ${_mLong[y.firstMonth - 1]} · ${euros(y.perMonth)} par mois en moyenne',
        style: TextStyle(fontSize: 12.5, color: mute),
      ),
      const SizedBox(height: 10),
      Row(children: [
        stat('+${euros(y.incomeTotal)}', 'rentré', color: kMoneyAccent),
        const SizedBox(width: 6),
        stat('−${euros(y.spentTotal)}', 'dépensé'),
        const SizedBox(width: 6),
        stat(euros(y.kept, sign: true), y.kept < 0 ? 'manqué' : 'gardé', color: y.kept < 0 ? _kRed : null),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .6), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [seg(YearBy.envelope, 'Par enveloppe'), seg(YearBy.domain, 'Par domaine'), seg(YearBy.fixed, 'Fixes')]),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final i = ((d.localPosition.dx - _BarsPainter.left) / ((w - _BarsPainter.left) / 12)).floor().clamp(0, 11);
            setState(() => _month = _month == i ? null : i);
          },
          child: CustomPaint(
            size: Size(w, 160),
            painter: _BarsPainter(
              stacks: [for (var m = 0; m < 12; m++) [for (final cy in cats) cy.months[m]]],
              colors: colors,
              mute: mute,
              grid: cs.onSurface.withValues(alpha: .08),
              current: _year == int.parse(today.substring(0, 4)) ? int.parse(today.substring(5, 7)) - 1 : -1,
              selected: sel,
            ),
          ),
        );
      }),
      const SizedBox(height: 6),
      if (sel != null)
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(border: Border.all(color: cs.onSurface.withValues(alpha: .12)), borderRadius: BorderRadius.circular(12)),
          child: Text(
            '${_mLong[sel]} $_year · −${euros(cats.fold<int>(0, (a, cy) => a + cy.months[sel]))}'
            '${[for (final cy in cats) if (cy.months[sel] > 0) '${cy.name} ${euros(cy.months[sel])}'].isEmpty ? '' : ' : ${[for (final cy in cats) if (cy.months[sel] > 0) '${cy.name} ${euros(cy.months[sel])}'].join(' · ')}'}',
            style: TextStyle(fontSize: 12.5, color: mute, height: 1.3),
          ),
        ),
      if (cats.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _by == YearBy.fixed ? 'Aucun fixe coché en $_year.' : 'Aucune dépense notée en $_year.',
            style: TextStyle(fontSize: 13, color: mute),
          ),
        ),
      for (var i = 0; i < cats.length; i++) _catRow(cs, mute, cats[i], colors[i], y),
    ]);
  }

  Widget _catRow(ColorScheme cs, Color mute, CategoryYear c, Color color, YearSummary y) {
    final tr = trend3(c.months, y.lastMonth, firstMonth: y.firstMonth);
    final avg = y.monthCount <= 0 ? 0 : (c.total / y.monthCount).round();
    final peak = c.months.fold<int>(1, math.max);
    final env = _by == YearBy.envelope ? logic.finances.envelopeOf(c.id) : null;
    return InkWell(
      onTap: env == null ? null : () => _openEnvelope(env, c, color),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: .08)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 10),
            Expanded(child: Text(c.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
            Text(euros(c.total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            if (env != null) Icon(Icons.chevron_right, size: 18, color: mute),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 2),
            child: Row(children: [
              Expanded(child: Text('${euros(avg)} / mois${c.cap > 0 ? ' · plafond ${euros(c.cap)}' : ''}', style: TextStyle(fontSize: 11.5, color: mute))),
              if (tr != null)
                Text('${tr > 0 ? '+' : ''}$tr % sur 3 mois', style: TextStyle(fontSize: 11.5, color: tr > 0 ? _kAmber : kMoneyAccent)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 6),
            child: SizedBox(
              height: 20,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var m = 0; m < 12; m++) ...[
                  if (m > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: c.months[m] == 0 ? 1 : math.max(2, c.months[m] / peak * 20),
                      decoration: BoxDecoration(
                        color: c.months[m] == 0 ? cs.onSurface.withValues(alpha: .1) : color.withValues(alpha: m + 1 == y.lastMonth ? .55 : 1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  void _openEnvelope(Envelope e, CategoryYear c, Color color) {
    showFiche<void>(context, builder: (ctx, scroll) => _EnvelopeYear(logic: logic, envelopeId: e.id, year: _year, color: color, scroll: scroll));
  }
}

/// L'année d'une enveloppe : ses mois face au plafond, les plus grosses, la tendance.
class _EnvelopeYear extends StatefulWidget {
  final AppLogic logic;
  final String envelopeId;
  final int year;
  final Color color;
  final ScrollController scroll;
  const _EnvelopeYear({required this.logic, required this.envelopeId, required this.year, required this.color, required this.scroll});
  @override
  State<_EnvelopeYear> createState() => _EnvelopeYearState();
}

class _EnvelopeYearState extends State<_EnvelopeYear> {
  @override
  void initState() {
    super.initState();
    widget.logic.addListener(_on);
  }

  @override
  void dispose() {
    widget.logic.removeListener(_on);
    super.dispose();
  }

  void _on() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final logic = widget.logic;
    final f = logic.finances;
    final env = f.envelopeOf(widget.envelopeId);
    final today = logic.livedTodayYmd;
    final y = yearSummary(f, widget.year, today);
    final c = yearCategories(f, widget.year, YearBy.envelope).where((x) => x.id == widget.envelopeId).firstOrNull ??
        CategoryYear(widget.envelopeId, env?.name ?? 'Enveloppe', List.filled(12, 0), cap: env?.monthly ?? 0);
    final over = monthsOverCap(c, y.lastMonth);
    final tr = trend3(c.months, y.lastMonth, firstMonth: y.firstMonth);
    final avg = y.monthCount <= 0 ? 0 : (c.total / y.monthCount).round();
    final big = biggestOf(f, widget.envelopeId, widget.year);
    final says = [
      if (c.cap > 0) over == 0 ? 'Jamais au-dessus du plafond en ${widget.year}.' : '$over mois au-dessus du plafond sur ${y.monthCount}.',
      tr == null ? 'Pas encore six mois clos pour une tendance.' : 'Sur les 3 derniers mois : ${tr > 0 ? '+' : ''}$tr % face aux 3 d’avant.',
    ].join(' ');
    String day(String ymd) {
      final d = DateTime.parse(ymd);
      return '${d.day} ${_mShort[d.month - 1]}';
    }

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 8),
        Expanded(child: Text(c.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
        if (c.cap > 0) Text('plafond ${euros(c.cap)} / mois', style: TextStyle(fontSize: 12, color: mute)),
      ]),
      const SizedBox(height: 8),
      Text(euros(c.total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'en ${widget.year} · ${euros(avg)} par mois'),
        if (over > 0) TextSpan(text: ' · $over mois au-dessus du plafond', style: const TextStyle(color: _kAmber)),
      ]), style: TextStyle(fontSize: 12.5, color: mute)),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, k) => CustomPaint(
          size: Size(k.maxWidth, 150),
          painter: _BarsPainter(
            stacks: [for (var m = 0; m < 12; m++) [c.months[m]]],
            colors: [widget.color],
            mute: mute,
            grid: cs.onSurface.withValues(alpha: .08),
            current: widget.year == int.parse(today.substring(0, 4)) ? int.parse(today.substring(5, 7)) - 1 : -1,
            cap: c.cap,
            capColor: cs.onSurface,
          ),
        ),
      ),
      if (big.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text('LES PLUS GROSSES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute)),
        ),
        for (final x in big)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Text('${day(x.ymd)} · ${x.note?.trim().isNotEmpty == true ? x.note!.trim() : c.name}', style: const TextStyle(fontSize: 13.5))),
              Text('−${euros(x.amount)}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ]),
          ),
      ],
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text('CE QUE ÇA DIT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute)),
      ),
      Text(says, style: const TextStyle(fontSize: 13.5, height: 1.4)),
      if (env != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => editEnvelopeCap(context, logic, env), child: Text(c.cap > 0 ? 'Changer le plafond' : 'Poser un plafond')),
        ),
    ]);
  }
}

/// Une barre par mois, empilée ; [cap] = trait pointillé du plafond.
class _BarsPainter extends CustomPainter {
  static const left = 34.0;
  final List<List<int>> stacks;
  final List<Color> colors;
  final Color mute;
  final Color grid;
  final int current;
  final int? selected;
  final int cap;
  final Color? capColor;
  _BarsPainter({required this.stacks, required this.colors, required this.mute, required this.grid, required this.current, this.selected, this.cap = 0, this.capColor});

  void _text(Canvas c, String t, Offset at, {TextAlign align = TextAlign.right, Color? color}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: 9.5, color: color ?? mute)), textDirection: TextDirection.ltr)..layout();
    final dx = align == TextAlign.right ? at.dx - tp.width : at.dx - tp.width / 2;
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  String _k(int cents) {
    final e = cents / 100;
    return e >= 1000 ? '${(e / 1000).toStringAsFixed(e >= 10000 ? 0 : 1).replaceAll('.', ',')} k' : '${e.round()}';
  }

  @override
  void paint(Canvas canvas, Size size) {
    const top = 6.0, bottom = 16.0;
    final h = size.height - top - bottom;
    final totals = [for (final s in stacks) s.fold<int>(0, (a, b) => a + b)];
    var peak = math.max(totals.fold<int>(0, math.max), cap);
    if (peak <= 0) peak = 10000;
    final niceStep = _nice(peak / 3);
    final mx = (niceStep * (peak / niceStep).ceil()).toDouble();
    double y(num v) => top + h - v / mx * h;
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = 0.0; v <= mx + 1; v += niceStep) {
      canvas.drawLine(Offset(left, y(v)), Offset(size.width, y(v)), gp);
      _text(canvas, v == 0 ? '0' : _k(v.round()), Offset(left - 4, y(v)));
    }
    final slot = (size.width - left) / 12;
    final bw = slot - 5;
    for (var m = 0; m < 12; m++) {
      final x = left + slot * m + 2.5;
      if (m.isEven) _text(canvas, _mShort[m], Offset(x + bw / 2, size.height - 5), align: TextAlign.center);
      if (selected == m) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 2, top, bw + 4, h), const Radius.circular(4)), Paint()..color = grid);
      }
      var acc = 0;
      final s = stacks[m];
      final lastIdx = s.lastIndexWhere((v) => v > 0);
      for (var k = 0; k < s.length; k++) {
        if (s[k] <= 0) continue;
        final y0 = y(acc), y1 = y(acc + s[k]);
        final rect = Rect.fromLTRB(x, y1 + (k == lastIdx ? 0 : 1), x + bw, y0 - (acc == 0 ? 0 : 1));
        final r = k == lastIdx ? const Radius.circular(3) : Radius.zero;
        canvas.drawRRect(RRect.fromRectAndCorners(rect, topLeft: r, topRight: r),
            Paint()..color = colors[k % colors.length].withValues(alpha: m == current ? .55 : 1));
        acc += s[k];
      }
    }
    if (cap > 0) {
      final cy = y(cap);
      final p = Paint()
        ..color = (capColor ?? mute).withValues(alpha: .85)
        ..strokeWidth = 1.5;
      for (var x = left; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, cy), Offset(math.min(x + 4, size.width), cy), p);
      }
      _text(canvas, 'plafond', Offset(size.width, cy - 7), color: capColor);
    }
  }

  double _nice(double v) {
    if (v <= 0) return 1000;
    final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final n = v / p;
    return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p;
  }

  @override
  bool shouldRepaint(covariant _BarsPainter o) => true;
}
