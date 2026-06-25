// Prototype « Expédition de la semaine » — la semaine = une ascension.
//
// Lundi = camp de base (en bas), Dimanche = sommet (en haut). Entre les deux, un
// parcours de nœuds à gravir. Chaque nœud = un défi rattaché à une activité ou
// routine (son « espace réservé »). On avance en faisant les choses IRL ; les
// nœuds de combat lancent le tower defense (puissance = régularité). Au sommet :
// boss + butin + score de la semaine.
//
// Données de démo (le branchement sur les vraies activités viendra ensuite, comme
// pour la galaxie). Dessiné en code. Accès : ?proto=expedition (sans auth).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'td_prototype.dart' show TdGameScreen;

enum ExpeKind { camp, activity, routine, combat, summit }

enum ExpeStatus { done, active, locked }

class ExpeNode {
  ExpeNode(this.kind, this.day, this.title, this.color, this.challenge,
      {this.targetWave = 2});
  final ExpeKind kind;
  final String day; // "Lun", "Mar"…
  final String title;
  final Color color;
  final String challenge;
  final int targetWave;
  ExpeStatus status = ExpeStatus.locked;
}

const _kBg0 = Color(0xFF0B1020);
const _kBg1 = Color(0xFF05070F);
const _kInk = Color(0xFF8FA0C8);
const _kFluo = Color(0xFFB6FF3C);
const _kGold = Color(0xFFFFD36B);
const _kCyan = Color(0xFF35E0FF);
const _kRed = Color(0xFFFF4D5E);

class ExpeditionScreen extends StatefulWidget {
  const ExpeditionScreen({super.key});
  @override
  State<ExpeditionScreen> createState() => _ExpeditionScreenState();
}

class _ExpeditionScreenState extends State<ExpeditionScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  Duration _last = Duration.zero;

  late List<ExpeNode> _nodes;
  int? _selected; // nœud ouvert dans le panneau
  int _score = 0;
  final List<String> _loot = [];
  bool _summited = false;

  @override
  void initState() {
    super.initState();
    _nodes = _demoWeek();
    _recomputeStatus();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration e) {
    final dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (dt <= 0) return;
    setState(() => _t += dt);
  }

  // ── Données de démo : une semaine type ────────────────────────────────────
  List<ExpeNode> _demoWeek() {
    const sante = Color(0xFF35E0C8);
    const travail = Color(0xFF6EA8FF);
    const perso = Color(0xFFFF9F45);
    return [
      ExpeNode(ExpeKind.camp, 'Lun', 'Camp de base', _kInk,
          'Le départ de la semaine. Ton expédition commence ici.'),
      ExpeNode(ExpeKind.activity, 'Lun', 'Sport', sante,
          'Fais 30 min de sport aujourd\'hui pour gravir ce palier.'),
      ExpeNode(ExpeKind.routine, 'Mar', 'Lecture', perso,
          'Coche ta routine lecture du soir.'),
      ExpeNode(ExpeKind.combat, 'Mar', 'Le col gardé', _kRed,
          'Un gardien bloque le col. Ta régularité = ta puissance.',
          targetWave: 2),
      ExpeNode(ExpeKind.activity, 'Mer', 'Travail focus', travail,
          'Une session focus d\'1 h sur ton projet.'),
      ExpeNode(ExpeKind.routine, 'Jeu', 'Méditation', sante,
          'Coche ta routine méditation.'),
      ExpeNode(ExpeKind.activity, 'Ven', 'Course', perso,
          'Sors courir — le sentier monte.'),
      ExpeNode(ExpeKind.combat, 'Sam', 'La crevasse', _kRed,
          'Passage technique gardé. Tiens 3 vagues.',
          targetWave: 3),
      ExpeNode(ExpeKind.summit, 'Dim', 'Sommet', _kGold,
          'Le sommet de la semaine. Termine tous les paliers pour le conquérir.'),
    ];
  }

  void _recomputeStatus() {
    // Le camp (0) est acquis d'office. Le 1er nœud non-fait est « actif ».
    bool activeSet = false;
    for (var i = 0; i < _nodes.length; i++) {
      final n = _nodes[i];
      if (n.kind == ExpeKind.camp) {
        n.status = ExpeStatus.done;
        continue;
      }
      if (n.status == ExpeStatus.done) continue;
      if (!activeSet) {
        n.status = ExpeStatus.active;
        activeSet = true;
      } else {
        n.status = ExpeStatus.locked;
      }
    }
  }

  int get _doneCount => _nodes.where((n) => n.status == ExpeStatus.done).length;

  // « Force » = régularité (démo) : monte avec les paliers franchis.
  double get _force => (0.25 + 0.09 * (_doneCount - 1)).clamp(0.0, 1.0);

  void _completeNode(int i) {
    final n = _nodes[i];
    n.status = ExpeStatus.done;
    _score += switch (n.kind) {
      ExpeKind.combat => 30,
      ExpeKind.summit => 50,
      _ => 10,
    };
    if (n.kind == ExpeKind.combat) _loot.add('🎖️ ${n.title}');
    _recomputeStatus();
    if (n.kind == ExpeKind.summit) {
      _summited = true;
      _loot.add('👑 Semaine conquise');
    }
    setState(() => _selected = null);
  }

  Future<void> _fight(int i) async {
    final n = _nodes[i];
    setState(() => _selected = null);
    final won = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TdGameScreen(
        initialFuel: _force,
        combatLabel: 'Combat · ${n.title}',
        targetWave: n.targetWave,
      ),
    ));
    if (!mounted) return;
    if (won == true) {
      _completeNode(i);
    } else {
      setState(() {});
    }
  }

  bool get _allBeforeSummitDone => _nodes
      .where((n) => n.kind != ExpeKind.summit)
      .every((n) => n.status == ExpeStatus.done);

  // ── Géométrie : parcours serpentin, camp en bas, sommet en haut ───────────
  List<Offset> _centers(Size s) {
    final n = _nodes.length;
    final topPad = 118.0, botPad = 96.0;
    final usableH = s.height - topPad - botPad;
    final cx = s.width / 2;
    final amp = math.min(s.width * 0.30, 130.0);
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final f = i / (n - 1); // 0 (camp) → 1 (sommet)
      final y = s.height - botPad - f * usableH;
      final x = cx + amp * math.sin(i * 0.95);
      out.add(Offset(x, y));
    }
    return out;
  }

  void _onTapUp(Offset p, Size s) {
    final c = _centers(s);
    for (var i = 0; i < _nodes.length; i++) {
      if ((p - c[i]).distance <= 34) {
        setState(() => _selected = (_selected == i) ? null : i);
        return;
      }
    }
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: _kBg1,
      body: LayoutBuilder(builder: (context, cons) {
        final size = Size(cons.maxWidth, cons.maxHeight);
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTapUp: (d) => _onTapUp(d.localPosition, size),
              child: CustomPaint(
                painter: _ExpePainter(_nodes, _centers(size), _t, _force,
                    _doneCount, _score),
                size: size,
              ),
            ),
          ),
          if (canPop)
            Positioned(
              left: 14,
              top: 14,
              child: _chip('← Retour', _kCyan,
                  onTap: () => Navigator.of(context).maybePop()),
            ),
          if (_selected != null) _panel(_selected!),
          if (_summited) _victory(),
        ]);
      }),
    );
  }

  // ── Panneau d'un nœud ─────────────────────────────────────────────────────
  Widget _panel(int i) {
    final n = _nodes[i];
    final locked = n.status == ExpeStatus.locked;
    final done = n.status == ExpeStatus.done;
    return Positioned(
      left: 14,
      right: 14,
      bottom: 18,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1424),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: n.color.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(color: n.color.withOpacity(0.18), blurRadius: 24)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(_emoji(n.kind), style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${n.day} · ${n.title}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              Text(_badge(n.kind),
                  style: TextStyle(
                      color: n.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(n.challenge,
                style: const TextStyle(
                    color: _kInk, fontSize: 13, height: 1.35)),
            const SizedBox(height: 14),
            if (done)
              _pill('✓ Palier franchi', n.color)
            else if (locked)
              _pill('🔒 Termine les paliers précédents', _kInk)
            else if (n.kind == ExpeKind.combat)
              _chip('Affronter  ▶', _kRed, big: true, onTap: () => _fight(i))
            else if (n.kind == ExpeKind.summit)
              (_allBeforeSummitDone
                  ? _chip('Conquérir le sommet  👑', _kGold,
                      big: true, onTap: () => _completeNode(i))
                  : _pill('🔒 Il reste des paliers avant le sommet', _kInk))
            else
              _chip('Marquer fait  ✓', _kFluo,
                  big: true, onTap: () => _completeNode(i)),
          ],
        ),
      ),
    );
  }

  Widget _victory() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.62),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          decoration: BoxDecoration(
            color: const Color(0xFF11182B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kGold.withOpacity(0.7)),
            boxShadow: [BoxShadow(color: _kGold.withOpacity(0.25), blurRadius: 40)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🏔️', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 6),
            const Text('Sommet atteint !',
                style: TextStyle(
                    color: _kGold, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Semaine conquise · Score $_score',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [for (final l in _loot) _pill(l, _kCyan)],
            ),
            const SizedBox(height: 18),
            _chip('Rejouer la semaine  ↻', _kFluo, big: true, onTap: () {
              setState(() {
                _nodes = _demoWeek();
                _recomputeStatus();
                _score = 0;
                _loot.clear();
                _summited = false;
                _selected = null;
              });
            }),
          ]),
        ),
      ),
    );
  }

  // ── Petits widgets ────────────────────────────────────────────────────────
  Widget _chip(String label, Color c, {bool big = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: big ? 18 : 12, vertical: big ? 12 : 7),
        decoration: BoxDecoration(
          color: c.withOpacity(0.16),
          borderRadius: BorderRadius.circular(big ? 14 : 12),
          border: Border.all(color: c.withOpacity(0.85)),
        ),
        child: Text(label,
            style: TextStyle(
                color: c,
                fontSize: big ? 15 : 12.5,
                fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _pill(String label, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withOpacity(0.5)),
        ),
        child: Text(label,
            style: TextStyle(
                color: c, fontSize: 12.5, fontWeight: FontWeight.w700)),
      );

  static String _emoji(ExpeKind k) => switch (k) {
        ExpeKind.camp => '🏕️',
        ExpeKind.activity => '⏱️',
        ExpeKind.routine => '🔁',
        ExpeKind.combat => '⚔️',
        ExpeKind.summit => '🏔️',
      };
  static String _badge(ExpeKind k) => switch (k) {
        ExpeKind.camp => 'départ',
        ExpeKind.activity => 'activité',
        ExpeKind.routine => 'routine',
        ExpeKind.combat => 'combat',
        ExpeKind.summit => 'sommet',
      };
}

class _ExpePainter extends CustomPainter {
  _ExpePainter(this.nodes, this.centers, this.t, this.force, this.done,
      this.score);
  final List<ExpeNode> nodes;
  final List<Offset> centers;
  final double t;
  final double force;
  final int done;
  final int score;

  @override
  void paint(Canvas canvas, Size size) {
    // Fond montagne nocturne
    canvas.drawRect(Offset.zero & size,
        Paint()..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_kBg0, _kBg1]).createShader(Offset.zero & size));
    _mountains(canvas, size);

    // Chemin reliant les nœuds
    for (var i = 0; i < centers.length - 1; i++) {
      final a = centers[i], b = centers[i + 1];
      final reached = nodes[i + 1].status == ExpeStatus.done ||
          nodes[i + 1].status == ExpeStatus.active;
      final col = nodes[i + 1].status == ExpeStatus.done
          ? _kFluo.withOpacity(0.7)
          : _kInk.withOpacity(reached ? 0.45 : 0.22);
      final p = Paint()
        ..color = col
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      if (nodes[i + 1].status == ExpeStatus.done) {
        _line(canvas, a, b, p);
      } else {
        _dashed(canvas, a, b, p);
      }
    }

    // Nœuds
    for (var i = 0; i < nodes.length; i++) {
      _node(canvas, nodes[i], centers[i]);
    }

    // Héros sur le dernier nœud acquis
    final heroIdx = (done - 1).clamp(0, nodes.length - 1);
    _hero(canvas, centers[heroIdx]);

    _hud(canvas, size);
  }

  void _mountains(Canvas canvas, Size s) {
    final p = Paint()..color = Colors.white.withOpacity(0.035);
    final path = Path()..moveTo(0, s.height * 0.42);
    path.lineTo(s.width * 0.22, s.height * 0.24);
    path.lineTo(s.width * 0.40, s.height * 0.38);
    path.lineTo(s.width * 0.62, s.height * 0.16);
    path.lineTo(s.width * 0.82, s.height * 0.34);
    path.lineTo(s.width, s.height * 0.22);
    path.lineTo(s.width, s.height);
    path.lineTo(0, s.height);
    path.close();
    canvas.drawPath(path, p);
  }

  void _node(Canvas canvas, ExpeNode n, Offset c) {
    final done = n.status == ExpeStatus.done;
    final active = n.status == ExpeStatus.active;
    final r = n.kind == ExpeKind.summit ? 28.0 : 22.0;
    final col = n.color;

    if (active) {
      final pulse = 0.5 + 0.5 * math.sin(t * 3.2);
      canvas.drawCircle(
          c,
          r + 8 + pulse * 6,
          Paint()
            ..color = col.withOpacity(0.10 + 0.16 * pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(
          c,
          r + 6 + pulse * 5,
          Paint()
            ..color = col.withOpacity(0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }

    // disque
    canvas.drawCircle(
        c, r, Paint()..color = done ? col.withOpacity(0.92) : const Color(0xFF101830));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = done ? Colors.white.withOpacity(0.5) : col.withOpacity(active ? 0.95 : 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // icône (emoji)
    final em = _ExpeditionScreenState._emoji(n.kind);
    _emojiText(canvas, em, c, r * 0.95);

    // étiquette jour + titre sous le nœud
    final dim = n.status == ExpeStatus.locked;
    _label(canvas, n.day.toUpperCase(), c.translate(0, -r - 13), 10,
        col.withOpacity(dim ? 0.5 : 0.95), bold: true);
    _label(canvas, n.title, c.translate(0, r + 15), 11.5,
        Colors.white.withOpacity(dim ? 0.4 : 0.92), bold: true);

    if (done) {
      _emojiText(canvas, '✓', c.translate(r * 0.7, -r * 0.7), 13);
    }
  }

  void _hero(Canvas canvas, Offset c) {
    final pos = c.translate(0, -2);
    final glow = 0.5 + 0.5 * math.sin(t * 2.4);
    canvas.drawCircle(
        pos,
        16 + glow * 4,
        Paint()
          ..color = _kFluo.withOpacity(0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // petit grimpeur : triangle + tête
    final body = Path()
      ..moveTo(pos.dx, pos.dy - 12)
      ..lineTo(pos.dx - 8, pos.dy + 8)
      ..lineTo(pos.dx + 8, pos.dy + 8)
      ..close();
    canvas.drawPath(body, Paint()..color = _kFluo);
    canvas.drawPath(
        body,
        Paint()
          ..color = Colors.white.withOpacity(0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4);
    canvas.drawCircle(pos.translate(0, -14), 4, Paint()..color = _kFluo);
    canvas.drawCircle(pos.translate(0, -14), 4,
        Paint()..color = Colors.white.withOpacity(0.8)..style = PaintingStyle.stroke..strokeWidth = 1.2);
  }

  void _hud(Canvas canvas, Size s) {
    _label(canvas, 'EXPÉDITION · LA SEMAINE', Offset(s.width / 2, 34), 17,
        _kInk, bold: true);
    final total = nodes.where((n) => n.kind != ExpeKind.camp).length;
    final cleared = nodes
        .where((n) => n.kind != ExpeKind.camp && n.status == ExpeStatus.done)
        .length;
    _label(canvas, 'Paliers $cleared/$total   ·   Score $score',
        Offset(s.width / 2, 56), 12, _kInk.withOpacity(0.85));

    // jauge de Force (régularité) en bas
    final gw = s.width * 0.62, gx = (s.width - gw) / 2, gy = s.height - 52;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(gx, gy, gw, 10), const Radius.circular(6)),
        Paint()..color = Colors.white.withOpacity(0.08));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(gx, gy, gw * force, 10), const Radius.circular(6)),
        Paint()..color = _kCyan);
    _label(canvas, '⚡ Force ${(force * 100).round()}%  (ta régularité)',
        Offset(s.width / 2, gy - 12), 11, _kCyan, bold: true);
  }

  // helpers dessin
  void _line(Canvas canvas, Offset a, Offset b, Paint p) =>
      canvas.drawLine(a, b, p);
  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 7.0, gap = 6.0;
    final d = b - a;
    final len = d.distance;
    final dir = d / len;
    var t = 0.0;
    while (t < len) {
      final s = a + dir * t;
      final e = a + dir * math.min(t + dash, len);
      canvas.drawLine(s, e, p);
      t += dash + gap;
    }
  }

  void _label(Canvas canvas, String s, Offset center, double size, Color color,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color,
              fontSize: size,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(canvas, center.translate(-tp.width / 2, -tp.height / 2));
  }

  void _emojiText(Canvas canvas, String s, Offset center, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center.translate(-tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ExpePainter old) => true;
}
