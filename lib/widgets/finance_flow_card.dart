import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/finance_charts.dart';
import 'package:productivitwo_v1/utils/finances.dart';

/// Carte « 30 jours » de la feuille Finances (maquette validée 2026-11-03
/// « Finances, en courbes ») : en haut le solde jour par jour (points = soldes
/// recopiés), en bas une barre par jour — rentrées vers le haut, sorties vers
/// le bas — sur le même axe des jours. Tap / glisser = le détail d'un jour.
const _kIn = Color(0xFF199E70);
const _kOut = Color(0xFFD95926);
const _kLine = Color(0xFFE8ECE9);
const _mShort = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

String _short(String ymd) {
  final d = DateTime.parse(ymd);
  return '${d.day} ${_mShort[d.month - 1]}';
}

String _long(String ymd) {
  final d = DateTime.parse(ymd);
  return '${_days[d.weekday - 1]} ${d.day} ${_mShort[d.month - 1]}';
}

class FinanceFlowCard extends StatefulWidget {
  final Finances finances;
  final String todayYmd;
  final Color accent;
  const FinanceFlowCard({super.key, required this.finances, required this.todayYmd, required this.accent});

  @override
  State<FinanceFlowCard> createState() => _FinanceFlowCardState();
}

class _FinanceFlowCardState extends State<FinanceFlowCard> {
  int _range = 30;
  int? _sel;

  void _pick(Offset p, double width, int n) {
    final i = ((p.dx - _ChartGeom.left) / (width - _ChartGeom.left - _ChartGeom.right) * n).floor().clamp(0, n - 1);
    if (i != _sel) setState(() => _sel = i);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final s = flowSeries(widget.finances, widget.todayYmd, days: _range);
    final t = flowTotals(s);
    final sel = s[(_sel ?? s.length - 1).clamp(0, s.length - 1)];
    final hasBalance = s.any((d) => d.balance != null);
    Widget seg(int v) => GestureDetector(
          onTap: () => setState(() {
            _range = v;
            _sel = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: _range == v ? cs.surface : null, borderRadius: BorderRadius.circular(8)),
            child: Text('$v j', style: TextStyle(fontSize: 12.5, fontWeight: _range == v ? FontWeight.w700 : FontWeight.w500, color: _range == v ? null : mute)),
          ),
        );
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
    Widget legend(Color c, String l, {bool line = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: line ? 12 : 9, height: line ? 2 : 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(line ? 1 : 3))),
          const SizedBox(width: 5),
          Text(l, style: TextStyle(fontSize: 11.5, color: mute)),
        ]);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .25), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('$_range JOURS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .6), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [seg(30), seg(90)]),
          ),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _pick(d.localPosition, w, s.length),
            onHorizontalDragUpdate: (d) => _pick(d.localPosition, w, s.length),
            child: CustomPaint(
              size: Size(w, 200),
              painter: _FlowPainter(s, (_sel ?? s.length - 1).clamp(0, s.length - 1), mute, cs.onSurface.withValues(alpha: .08), cs.surface),
            ),
          );
        }),
        const SizedBox(height: 4),
        Wrap(spacing: 12, runSpacing: 4, children: [
          if (hasBalance) legend(_kLine, 'Solde', line: true),
          legend(_kIn, 'Rentrées'),
          legend(_kOut, 'Sorties'),
        ]),
        const SizedBox(height: 8),
        // Le détail du jour touché (par défaut : aujourd'hui).
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(border: Border.all(color: cs.onSurface.withValues(alpha: .12)), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(_long(sel.ymd), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              if (sel.balance != null) Text('solde ${euros(sel.balance!)}${sel.checked ? ' · recopié' : ''}', style: TextStyle(fontSize: 12.5, color: mute)),
            ]),
            const SizedBox(height: 2),
            Text(
              sel.inCents == 0 && sel.outCents == 0
                  ? 'Rien n’a bougé ce jour-là.'
                  : [
                      if (sel.inCents > 0) '+${euros(sel.inCents)}',
                      if (sel.outCents > 0) '−${euros(sel.outCents)}',
                    ].join(' · ') +
                      (sel.labels.isEmpty ? '' : ' : ${sel.labels.take(4).join(', ')}${sel.labels.length > 4 ? '…' : ''}'),
              style: TextStyle(fontSize: 12.5, color: mute, height: 1.3),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          stat('+${euros(t.inCents)}', 'rentré', color: widget.accent),
          const SizedBox(width: 6),
          stat('−${euros(t.outCents)}', 'sorti'),
          const SizedBox(width: 6),
          stat(euros(t.net, sign: true), 'sur $_range j', color: t.net < 0 ? const Color(0xFFF07A6A) : null),
        ]),
        if (!hasBalance)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('La courbe du compte démarre au premier solde recopié.', style: TextStyle(fontSize: 11.5, color: mute)),
          ),
      ]),
    );
  }
}

class _ChartGeom {
  static const left = 38.0;
  static const right = 4.0;
  static const balanceH = 116.0;
  static const gap = 18.0;
}

/// Version mini (tuile Finances d'Organisation) : la courbe du solde et les barres entré / sorti, sans légendes.
class FinanceFlowMini extends StatelessWidget {
  final Finances finances;
  final String todayYmd;
  final int days;
  final double height;
  /// Cible de saison (centimes) : trait violet en pointillés sur la courbe du solde.
  final int? targetCents;
  const FinanceFlowMini({super.key, required this.finances, required this.todayYmd, this.days = 30, this.height = 48, this.targetCents});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = flowSeries(finances, todayYmd, days: days);
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _FlowPainter(s, s.length - 1, cs.onSurface.withValues(alpha: .55), cs.onSurface.withValues(alpha: .08), cs.surface, compact: true, target: targetCents),
    );
  }
}

class _FlowPainter extends CustomPainter {
  final List<DayFlow> s;
  final int sel;
  final Color mute;
  final Color grid;
  final Color surface;
  final bool compact;
  final int? target;
  _FlowPainter(this.s, this.sel, this.mute, this.grid, this.surface, {this.compact = false, this.target});

  void _text(Canvas c, String t, Offset at, {TextAlign align = TextAlign.right, Color? color, FontWeight? weight}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: 9.5, color: color ?? mute, fontWeight: weight)), textDirection: TextDirection.ltr)..layout();
    final dx = align == TextAlign.right ? at.dx - tp.width : (align == TextAlign.center ? at.dx - tp.width / 2 : at.dx);
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  String _k(int cents) {
    final e = cents / 100;
    if (e.abs() >= 1000) return '${(e / 1000).toStringAsFixed(e.abs() >= 10000 ? 0 : 1).replaceAll('.', ',')} k';
    return e.round().toString();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final l = compact ? 0.0 : _ChartGeom.left, r = compact ? 0.0 : _ChartGeom.right;
    final n = s.length;
    final w = size.width - l - r;
    final step = w / n;
    double cx(int i) => l + step * (i + .5);
    final gridP = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // ── Solde ──
    final top = compact ? 2.0 : 6.0, bh = compact ? size.height * .58 : _ChartGeom.balanceH;
    final vals = [for (final d in s) if (d.balance != null) d.balance!, if (target != null) target!];
    if (vals.isNotEmpty) {
      var mn = vals.reduce(math.min).toDouble(), mx = vals.reduce(math.max).toDouble();
      if (mx - mn < 10000) {
        mn -= 5000;
        mx += 5000;
      }
      final pad = (mx - mn) * .08;
      mn -= pad;
      mx += pad;
      double y(num v) => top + (mx - v) / (mx - mn) * (bh - top);
      for (var k = 0; k <= 2 && !compact; k++) {
        final v = (mn + (mx - mn) * k / 2).round();
        canvas.drawLine(Offset(l, y(v)), Offset(size.width - r, y(v)), gridP);
        _text(canvas, _k(v), Offset(l - 5, y(v)));
      }
      if (target != null) {
        final ty = y(target!);
        final dash = Paint()
          ..color = const Color(0xFFB79CF2)
          ..strokeWidth = 1.5;
        for (var x0 = l; x0 < size.width - r; x0 += 7) {
          canvas.drawLine(Offset(x0, ty), Offset(math.min(x0 + 4, size.width - r), ty), dash);
        }
      }
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final b = s[i].balance;
        if (b == null) continue;
        started ? path.lineTo(cx(i), y(b)) : path.moveTo(cx(i), y(b));
        started = true;
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = _kLine
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round);
      for (var i = 0; i < n && !compact; i++) {
        final b = s[i].balance;
        if (b == null || !s[i].checked) continue;
        canvas.drawCircle(Offset(cx(i), y(b)), 5, Paint()..color = surface);
        canvas.drawCircle(Offset(cx(i), y(b)), 3.5, Paint()..color = _kLine);
      }
      final sb = s[sel].balance;
      if (sb != null) canvas.drawCircle(Offset(cx(sel), y(sb)), compact ? 2.5 : 4.5, Paint()..color = _kLine);
    } else if (!compact) {
      _text(canvas, 'pas encore de solde recopié', Offset(l + w / 2, top + bh / 2), align: TextAlign.center);
    }

    // ── Rentrées / sorties (échelle racine : un loyer n'écrase pas les cafés) ──
    final fTop = bh + (compact ? 3 : _ChartGeom.gap);
    final fh = size.height - fTop - (compact ? 0 : 14);
    final mid = fTop + fh / 2;
    final peak = s.fold<int>(1, (a, d) => math.max(a, math.max(d.inCents, d.outCents)));
    double h(int v) => math.sqrt(v / peak) * (fh / 2 - 2);
    canvas.drawLine(Offset(l, mid), Offset(size.width - r, mid), gridP);
    if (!compact) {
      _text(canvas, 'entré', Offset(l - 5, fTop + 6));
      _text(canvas, 'sorti', Offset(l - 5, fTop + fh - 6));
    }
    final bw = math.max(1.5, step - (n > 40 ? 1 : 2));
    for (var i = 0; i < n; i++) {
      final x0 = l + step * i + (step - bw) / 2;
      final d = s[i];
      final dim = i == sel ? 1.0 : .85;
      if (d.inCents > 0) {
        canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x0, mid - 1 - h(d.inCents), bw, h(d.inCents)), topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
            Paint()..color = _kIn.withValues(alpha: dim));
      }
      if (d.outCents > 0) {
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(x0, mid + 1, bw, h(d.outCents)), bottomLeft: const Radius.circular(2), bottomRight: const Radius.circular(2)),
            Paint()..color = _kOut.withValues(alpha: dim));
      }
    }

    if (compact) return;
    // ── Jour touché + dates ──
    canvas.drawLine(Offset(cx(sel), top), Offset(cx(sel), size.height - 14),
        Paint()
          ..color = mute.withValues(alpha: .5)
          ..strokeWidth = 1);
    for (final i in [0, n ~/ 3, 2 * n ~/ 3, n - 1]) {
      _text(canvas, _short(s[i].ymd), Offset(cx(i), size.height - 5), align: i == n - 1 ? TextAlign.right : (i == 0 ? TextAlign.left : TextAlign.center));
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter o) => o.s != s || o.sel != sel;
}
