import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:productivitwo_v1/catalog/catalog_art.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart';

/// Un badge en carte à collectionner (maquette validée 2026-11-01) : cadre de
/// la rareté, symbole en grand sur le fond de sa famille, nom, points des
/// paliers ; commencée = grisée avec sa jauge ; jamais commencée = de dos avec
/// un indice. Rapport 5 / 7. Logique : `utils/badge_cards.dart`.
class BadgeCardView extends StatefulWidget {
  final BadgeState state;
  final double width;
  /// Sous le nom : « 3 / 5 j », « le 12 oct. »… (rien si null).
  final String? footer;
  /// Jauge qui avance ce soir (trait ambre).
  final bool tonight;
  /// Pastille « NOUVEAU » en haut à gauche.
  final bool isNew;
  /// Album en pochettes : une carte jamais commencée devient une pochette vide
  /// numérotée (pointillés, numéro, nom) au lieu d'une carte de dos.
  final int? pocket;
  const BadgeCardView({super.key, required this.state, this.width = 110, this.footer, this.tonight = false, this.isNew = false, this.pocket});

  @override
  State<BadgeCardView> createState() => _BadgeCardViewState();
}

const kCardBack = Color(0xFF16251F);

/// Fond du dessin, par famille.
Color familyArtColor(BadgeFamily f) => switch (f) {
      BadgeFamily.routines => const Color(0xFF5A2E1F),
      BadgeFamily.objectives => const Color(0xFF3D3366),
      BadgeFamily.days => const Color(0xFF5C4A1D),
      BadgeFamily.discipline => const Color(0xFF1F4A5C),
      BadgeFamily.chain => const Color(0xFF2B5A46),
      BadgeFamily.actions => const Color(0xFF2B4A2B),
      BadgeFamily.time => const Color(0xFF4A2B4A),
    };

/// Encre du symbole, par famille.
Color familyInkColor(BadgeFamily f) => switch (f) {
      BadgeFamily.routines => const Color(0xFFFFB38A),
      BadgeFamily.objectives => const Color(0xFFD3C6FF),
      BadgeFamily.days => const Color(0xFFFFD98A),
      BadgeFamily.discipline => const Color(0xFF7FD3FF),
      BadgeFamily.chain => const Color(0xFF9FF0C1),
      BadgeFamily.actions => const Color(0xFFB8F08A),
      BadgeFamily.time => const Color(0xFFF0A8E8),
    };

/// Couleurs du cadre et de l'encre de la rareté.
List<Color> rarityFrame(CardRarity r) => switch (r) {
      CardRarity.bronze => const [Color(0xFFC98A4B), Color(0xFF7A4A22), Color(0xFFD9A06A)],
      CardRarity.argent => const [Color(0xFFE6EDF2), Color(0xFF8796A3), Color(0xFFCFD8DF)],
      CardRarity.or => const [Color(0xFFFFE28A), Color(0xFFB8862B), Color(0xFFFFD36A)],
      CardRarity.legend => const [Color(0xFFFF8A8A), Color(0xFFFFD36A), Color(0xFF8AFFC1), Color(0xFF7FD3FF), Color(0xFFC59BFF), Color(0xFFFF8A8A)],
      CardRarity.none => const [Color(0xFF2A3A33), Color(0xFF2A3A33)],
    };

Color rarityInk(CardRarity r) => switch (r) {
      CardRarity.bronze => const Color(0xFFE0A56B),
      CardRarity.argent => const Color(0xFFCFD8DF),
      CardRarity.or => const Color(0xFFFFD36A),
      CardRarity.legend => Colors.white,
      CardRarity.none => const Color(0xFF8FA69A),
    };

class _BadgeCardViewState extends State<BadgeCardView> with SingleTickerProviderStateMixin {
  AnimationController? _shine;

  @override
  void initState() {
    super.initState();
    _syncShine();
  }

  @override
  void didUpdateWidget(BadgeCardView old) {
    super.didUpdateWidget(old);
    _syncShine();
  }

  void _syncShine() {
    final legend = rarityOf(widget.state) == CardRarity.legend;
    if (legend && _shine == null) {
      _shine = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    } else if (!legend && _shine != null) {
      _shine!.dispose();
      _shine = null;
    }
  }

  @override
  void dispose() {
    _shine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.state;
    final w = widget.width;
    final face = faceOf(b);
    final r = rarityOf(b);
    if (face == CardFace.hidden && widget.pocket != null) return _pocket(b, w);
    final pad = w * .045;
    final radius = w * .12;
    final small = w < 90;
    final frame = face == CardFace.won
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: r == CardRarity.legend
                ? SweepGradient(colors: rarityFrame(r))
                : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: rarityFrame(r)),
          )
        : BoxDecoration(borderRadius: BorderRadius.circular(radius), color: face == CardFace.hidden ? const Color(0xFF1D2B25) : const Color(0xFF2A3A33));
    return Semantics(
      label: '${b.def.name}${face == CardFace.won ? ', carte ${rarityLabel(r).toLowerCase()}' : ', pas encore gagnée'}',
      child: SizedBox(
        width: w,
        height: w * 7 / 5,
        child: Container(
          decoration: frame,
          padding: EdgeInsets.all(pad),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - pad),
            child: face == CardFace.hidden ? _back(b, w, small) : _front(b, w, face, r, small),
          ),
        ),
      ),
    );
  }

  Widget _pocket(BadgeState b, double w) => Semantics(
        label: '${b.def.name}, pochette vide',
        child: CustomPaint(
          painter: _DashedPainter(radius: w * .12),
          child: SizedBox(
            width: w,
            height: w * 7 / 5,
            child: Padding(
              padding: EdgeInsets.all(w * .07),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${widget.pocket}', style: TextStyle(fontSize: w * .22, height: 1, fontWeight: FontWeight.w900, color: const Color(0xFF2F4A3E))),
                SizedBox(height: w * .04),
                Text(b.def.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: (w * .085).clamp(8, 13).toDouble(), height: 1.15, fontWeight: FontWeight.w700, color: const Color(0xFF5E7D6E))),
                SizedBox(height: w * .03),
                Text(cardHint(b), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: (w * .07).clamp(7, 11).toDouble(), height: 1.15, color: const Color(0xFF4A6558))),
              ]),
            ),
          ),
        ),
      );

  Widget _back(BadgeState b, double w, bool small) => CustomPaint(
        painter: _StripesPainter(),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('?', style: TextStyle(fontSize: w * .32, height: 1, fontWeight: FontWeight.w900, color: const Color(0xFF2F4A3E))),
            if (!small) ...[
              SizedBox(height: w * .04),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * .08),
                child: Text(cardHint(b), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: (w * .09).clamp(9, 13).toDouble(), height: 1.2, color: const Color(0xFF8FA69A))),
              ),
            ],
          ]),
        ),
      );

  Widget _front(BadgeState b, double w, CardFace face, CardRarity r, bool small) {
    final won = face == CardFace.won;
    // Routine du catalogue : son dessin et son fond au lieu de la flamme.
    final cat = b.def.family == BadgeFamily.routines || b.def.id.startsWith('fois-') ? CatalogArt.forActivity(b.def.subjectId) : null;
    final art = cat == null ? familyArtColor(b.def.family) : Color(cat.bg);
    final ink = won ? familyInkColor(b.def.family) : const Color(0xFF8FA69A);
    // Nom en petit, sur deux lignes, pour qu'il s'affiche en entier (retour user 2026-11-01).
    final nameSize = (w * .078).clamp(7.5, 16).toDouble();
    final footSize = (w * .085).clamp(8, 13).toDouble();
    return Container(
      color: const Color(0xFF101A15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: const Alignment(0, -.1), radius: .9, colors: won ? [art, const Color(0xFF101A15)] : const [Color(0xFF1D2B25), Color(0xFF101A15)]),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(w * .1),
              child: Opacity(
                opacity: won ? 1 : .4,
                child: cat == null
                    ? CustomPaint(painter: _SymbolPainter(b.def.symbol, ink))
                    : (won
                        ? SvgPicture.string(cat.svg)
                        : ColorFiltered(colorFilter: const ColorFilter.matrix(_kGrey), child: SvgPicture.string(cat.svg))),
              ),
            ),
            if (_shine != null)
              AnimatedBuilder(
                animation: _shine!,
                builder: (_, __) => FractionalTranslation(
                  translation: Offset(_shine!.value * 2 - 1, 0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment(-1, -.3), end: Alignment(1, .3), colors: [Color(0x00FFFFFF), Color(0x2EFFFFFF), Color(0x00FFFFFF)], stops: [.3, .5, .7]),
                    ),
                  ),
                ),
              ),
            if (widget.isNew)
              Positioned(
                top: w * .05,
                left: w * .05,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: w * .04, vertical: w * .01),
                  decoration: BoxDecoration(color: const Color(0xFFFF5E57), borderRadius: BorderRadius.circular(w * .04)),
                  child: Text('NOUVEAU', style: TextStyle(fontSize: (w * .065).clamp(7, 11).toDouble(), fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
          ]),
        ),
        if (!small)
          Padding(
            padding: EdgeInsets.fromLTRB(w * .06, w * .035, w * .06, 0),
            child: Text(b.def.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: nameSize, height: 1.15, fontWeight: FontWeight.w800, color: won ? Colors.white : const Color(0xFFB4C8BE))),
          ),
        if (!won && b.showGauge)
          Padding(
            padding: EdgeInsets.fromLTRB(w * .06, w * .03, w * .06, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LinearProgressIndicator(
                value: b.progress ?? 0,
                minHeight: math.max(3, w * .035),
                backgroundColor: const Color(0xFF1D2B25),
                color: widget.tonight ? kBadgeGaugeToday : kBadgeGaugeFill,
              ),
            ),
          ),
        if (!small)
          Padding(
            padding: EdgeInsets.fromLTRB(w * .06, w * .02, w * .06, w * .045),
            child: Row(children: [
              Expanded(
                child: Text(
                  won ? rarityLabel(r).toUpperCase() : (widget.footer ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: footSize, fontWeight: won ? FontWeight.w800 : FontWeight.w500, letterSpacing: won ? .6 : 0, color: won ? rarityInk(r) : (widget.tonight ? kBadgeGaugeToday : const Color(0xFF8FA69A))),
                ),
              ),
              if (b.def.tiers.length >= 2) _pips(b, w, won ? rarityInk(r) : const Color(0xFF8FA69A)),
            ]),
          )
        else
          SizedBox(height: w * .05),
      ]),
    );
  }

  Widget _pips(BadgeState b, double w, Color c) {
    final n = b.def.tiers.length.clamp(0, 6);
    final d = (w * .055).clamp(4, 9).toDouble();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < n; i++)
        Container(
          width: d,
          height: d,
          margin: EdgeInsets.only(left: d * .35),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < b.level ? c : null,
            border: Border.all(color: c.withValues(alpha: i < b.level ? 1 : .5), width: 1.2),
          ),
        ),
    ]);
  }
}

/// Le symbole du gabarit, agrandi pour remplir l'image de la carte : les
/// symboles tiennent dans le cercle r 22 centré (50, 42).
class _SymbolPainter extends CustomPainter {
  final String symbol;
  final Color ink;
  const _SymbolPainter(this.symbol, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(side / 56);
    canvas.translate(-50, -42);
    BadgePainter.paintSymbol(canvas, symbol, ink, const Color(0xFF101A15));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.symbol != symbol || old.ink != ink;
}

class _StripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF13201B));
    final p = Paint()
      ..color = kCardBack
      ..strokeWidth = 8;
    for (double x = -size.height; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) => false;
}


/// Bord en pointillés d'une pochette vide.
class _DashedPainter extends CustomPainter {
  final double radius;
  const _DashedPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(1);
    final path = Path()..addRRect(rr);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF2F4A3E);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), p);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.radius != radius;
}

/// Matrice de niveaux de gris (carte commencée d'une routine du catalogue).
const _kGrey = <double>[
  .2126, .7152, .0722, 0, 0,
  .2126, .7152, .0722, 0, 0,
  .2126, .7152, .0722, 0, 0,
  0, 0, 0, 1, 0,
];
