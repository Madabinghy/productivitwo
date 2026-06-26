import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Domaine de vie (mock).
class _Dom {
  final String name, emoji, rank, min, items;
  final Color color, colorDk, bg;
  final int lvl, xpCur, xpNext, streak, bal; // bal = équilibre 0..100
  final List<(String, String, String)> routines; // (emoji, nom, sous-titre)
  const _Dom(this.name, this.emoji, this.rank, this.color, this.colorDk,
      this.bg, this.lvl, this.xpCur, this.xpNext, this.streak, this.bal,
      this.min, this.items, this.routines);
}

const _domains = <_Dom>[
  _Dom('Santé', '💪', 'Athlète', SoftPop.coral, SoftPop.coralDark,
      SoftPop.coralSoft, 9, 820, 900, 6, 82, '4h10', '3 routines · 1 projet', [
    ('💧', "Boire de l'eau", 'Série 12 j 🔥'),
    ('🏋️', 'Salle de sport', 'Série 5 j'),
    ('😴', 'Dormir 7h', 'Série 3 j'),
  ]),
  _Dom('Esprit', '🧠', 'Sage', SoftPop.violet, SoftPop.violetDark,
      SoftPop.violetSoft, 7, 540, 700, 3, 70, '2h05', '2 routines', [
    ('🧘', 'Méditer 15 min', 'Série 3 j 🔥'),
    ('📖', 'Lire 10 pages', 'Série 8 j'),
  ]),
  _Dom('Création', '🎨', 'Artisan', SoftPop.amber, SoftPop.amberDark,
      SoftPop.amberSoft, 6, 1240, 1400, 4, 92, '3h00', '1 routine · 1 projet', [
    ('✏️', 'Dessiner 15 min', 'Série 4 j 🔥'),
  ]),
  _Dom('Argent', '💰', 'Gestionnaire', SoftPop.teal, SoftPop.tealDark,
      SoftPop.tealSoft, 5, 300, 600, 2, 55, '1h40', '1 routine · 1 projet', [
    ('💸', 'Virement épargne', 'Série 2 j'),
  ]),
  _Dom('Relations', '❤️', 'Lien naissant', SoftPop.pink, SoftPop.pinkDark,
      SoftPop.pinkSoft, 3, 210, 400, 0, 28, '0h30', '1 routine', [
    ('📓', 'Journal de gratitude', 'À reprendre'),
  ]),
];

/// Écran « Équilibre des domaines » — roue d'équilibre + nudge + détail (preview).
///
/// Réf : maquette `01_design_produit` (Roue d'équilibre & détail domaine).
/// Pousse à l'équilibre (pas seulement à empiler une série) en mettant en avant
/// le domaine le plus délaissé. Données mock.
class SoftPopBalanceScreen extends StatelessWidget {
  const SoftPopBalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final neglected =
        _domains.reduce((a, b) => a.bal <= b.bal ? a : b); // plus bas équilibre
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Équilibre')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            Text('Tes domaines de vie · cette semaine',
                style: SoftPop.ui(size: 13, color: SoftPop.inkSecondary)),
            const SizedBox(height: SoftPop.s12),
            SoftCard(
              child: Center(
                child: SizedBox(
                  height: 240,
                  width: 240,
                  child: CustomPaint(painter: _WheelPainter(_domains)),
                ),
              ),
            ),
            const SizedBox(height: SoftPop.s12),
            _nudge(neglected),
            const SizedBox(height: SoftPop.s20),
            Text('Tes domaines',
                style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: SoftPop.s12),
            for (final d in _domains) ...[
              _domainCard(context, d),
              const SizedBox(height: SoftPop.s8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _nudge(_Dom d) => Container(
        padding: const EdgeInsets.all(SoftPop.s12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [d.bg, SoftPop.violetSoft],
          ),
          borderRadius: BorderRadius.circular(SoftPop.rCardSm),
        ),
        child: Row(
          children: [
            Text(d.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: SoftPop.s8),
            Expanded(
              child: Text(
                '${d.name} est un peu délaissé cette semaine. Et si tu lui accordais un moment aujourd’hui ?',
                style: SoftPop.ui(size: 12, color: d.colorDk, height: 1.3),
              ),
            ),
          ],
        ),
      );

  Widget _domainCard(BuildContext context, _Dom d) => SoftCard(
        padding: const EdgeInsets.all(SoftPop.s12),
        radius: SoftPop.rCardSm,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _DomainDetailScreen(d)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: d.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(d.emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(d.name,
                          style:
                              SoftPop.ui(size: 14, weight: FontWeight.w700)),
                      const SizedBox(width: SoftPop.s8),
                      Text('Niv. ${d.lvl} · ${d.rank}',
                          style: SoftPop.ui(size: 10, color: d.colorDk)),
                    ],
                  ),
                  const SizedBox(height: SoftPop.s8),
                  SoftXpBar(
                    value: d.xpCur / d.xpNext,
                    height: 8,
                    gradient: LinearGradient(colors: [d.color, d.colorDk]),
                    track: d.bg,
                  ),
                  const SizedBox(height: SoftPop.s4),
                  Text('⏱ ${d.min} · ${d.items}',
                      style: SoftPop.ui(size: 10, color: SoftPop.inkMuted)),
                ],
              ),
            ),
            const SizedBox(width: SoftPop.s8),
            Column(
              children: [
                Text('${d.bal}%',
                    style: SoftPop.mono(size: 14, color: d.colorDk)),
                Text('équil.',
                    style: SoftPop.ui(size: 9, color: SoftPop.inkMuted)),
              ],
            ),
          ],
        ),
      );
}

/// Roue d'équilibre = radar pentagonal (un axe par domaine).
class _WheelPainter extends CustomPainter {
  final List<_Dom> domains;
  _WheelPainter(this.domains);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2 - 26; // marge pour les emojis
    final n = domains.length;
    double angle(int i) => -math.pi / 2 + i * 2 * math.pi / n;

    // Grille concentrique.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = SoftPop.inkMuted.withValues(alpha: .18);
    for (var ring = 1; ring <= 4; ring++) {
      final r = maxR * ring / 4;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = center + Offset(math.cos(angle(i)), math.sin(angle(i))) * r;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, grid);
    }
    // Rayons.
    for (var i = 0; i < n; i++) {
      final p = center + Offset(math.cos(angle(i)), math.sin(angle(i))) * maxR;
      canvas.drawLine(center, p, grid);
    }

    // Polygone d'équilibre rempli.
    final fillPath = Path();
    for (var i = 0; i < n; i++) {
      final r = maxR * (domains[i].bal / 100);
      final p = center + Offset(math.cos(angle(i)), math.sin(angle(i))) * r;
      i == 0 ? fillPath.moveTo(p.dx, p.dy) : fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.close();
    canvas.drawPath(
        fillPath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = SoftPop.violet.withValues(alpha: .16));
    canvas.drawPath(
        fillPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = SoftPop.violet);

    // Points + emojis aux sommets.
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < n; i++) {
      final r = maxR * (domains[i].bal / 100);
      final p = center + Offset(math.cos(angle(i)), math.sin(angle(i))) * r;
      canvas.drawCircle(p, 4, Paint()..color = domains[i].color);
      final labelPos =
          center + Offset(math.cos(angle(i)), math.sin(angle(i))) * (maxR + 16);
      tp.text = TextSpan(
          text: domains[i].emoji, style: const TextStyle(fontSize: 18));
      tp.layout();
      tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Détail d'un domaine (niveau, XP, temps, routines rattachées).
class _DomainDetailScreen extends StatelessWidget {
  final _Dom d;
  const _DomainDetailScreen(this.d);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: Text('${d.emoji} ${d.name}')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            SoftCard(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [d.color, d.colorDk],
              ),
              padding: const EdgeInsets.all(SoftPop.s20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Niveau ${d.lvl} · ${d.rank}',
                          style: SoftPop.ui(
                              size: 16,
                              weight: FontWeight.w700,
                              color: Colors.white)),
                      Text('${d.bal}% équilibre',
                          style: SoftPop.mono(
                              size: 13,
                              color: Colors.white.withValues(alpha: .9))),
                    ],
                  ),
                  const SizedBox(height: SoftPop.s12),
                  SoftXpBar(
                    value: d.xpCur / d.xpNext,
                    track: Colors.white.withValues(alpha: .25),
                    gradient: const LinearGradient(
                        colors: [Colors.white, Colors.white]),
                  ),
                  const SizedBox(height: SoftPop.s4),
                  Text('${d.xpCur} / ${d.xpNext} XP · ${d.xpNext - d.xpCur} → Niv. ${d.lvl + 1}',
                      style: SoftPop.mono(
                          size: 11,
                          color: Colors.white.withValues(alpha: .9))),
                ],
              ),
            ),
            const SizedBox(height: SoftPop.s12),
            Row(
              children: [
                Expanded(child: _statTile('⏱', d.min, 'temps cette semaine')),
                const SizedBox(width: SoftPop.s8),
                Expanded(child: _statTile('🔥', '${d.streak} j', 'meilleure série')),
              ],
            ),
            const SizedBox(height: SoftPop.s20),
            Text('Routines rattachées',
                style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: SoftPop.s12),
            for (final r in d.routines) ...[
              SoftCard(
                padding: const EdgeInsets.all(SoftPop.s12),
                radius: SoftPop.rCardSm,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: d.bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(r.$1, style: const TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: SoftPop.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.$2,
                              style: SoftPop.ui(
                                  size: 14, weight: FontWeight.w600)),
                          Text(r.$3,
                              style: SoftPop.ui(
                                  size: 11, color: SoftPop.inkMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SoftPop.s8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statTile(String emoji, String value, String label) => SoftCard(
        radius: SoftPop.rCardSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: SoftPop.s4),
              Text(value, style: SoftPop.mono(size: 18, color: SoftPop.ink)),
            ]),
            const SizedBox(height: 2),
            Text(label, style: SoftPop.ui(size: 11, color: SoftPop.inkSecondary)),
          ],
        ),
      );
}
