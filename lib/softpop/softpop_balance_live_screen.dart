import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Équilibre des domaines branché sur les vraies données (AppLogic).
///
/// Roue de **régularité sur 7 jours** par domaine (proxy réel du « % du
/// standard »), temps loggué, routines rattachées, meilleure série. Données
/// réelles. XP/niveau par domaine viendront avec l'économie.
class SoftPopBalanceLiveScreen extends StatelessWidget {
  final AppLogic logic;
  const SoftPopBalanceLiveScreen({super.key, required this.logic});

  static const _palette = [
    SoftPop.violet, SoftPop.coral, SoftPop.teal, SoftPop.amber, SoftPop.pink,
  ];
  Color _color(int idx, Domain d) =>
      d.colorValue != null ? Color(d.colorValue!) : _palette[idx % _palette.length];

  List<Activity> _habits(Domain d) => logic.state.activeActivities
      .where((a) => a.domainId == d.id && a.isHabit)
      .toList();

  // Régularité 7 jours : part des routines quotidiennes du domaine atteintes.
  double _balance(Domain d) {
    final habits = _habits(d)
        .where((a) => logic.effectiveHabitFreq(a) == HabitFreq.daily)
        .toList();
    if (habits.isEmpty) return 0;
    var met = 0, slots = 0;
    final today = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final day = today.subtract(Duration(days: i));
      for (final h in habits) {
        slots++;
        final tgt = logic.activeHabitTarget(h);
        if (tgt > 0 && logic.habitValueOn(h.id, day) >= tgt) met++;
      }
    }
    return slots == 0 ? 0 : met / slots;
  }

  @override
  Widget build(BuildContext context) {
    final domains = logic.state.activeDomains;
    final data = [
      for (var i = 0; i < domains.length; i++)
        (domain: domains[i], color: _color(i, domains[i]), bal: _balance(domains[i])),
    ];
    final neglected = data.isEmpty
        ? null
        : data.reduce((a, b) => a.bal <= b.bal ? a : b);
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Équilibre')),
        body: domains.isEmpty
            ? Center(
                child: Text('Aucun domaine.',
                    style: SoftPop.ui(color: SoftPop.inkSecondary)))
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                    SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
                children: [
                  Text('Ta régularité · 7 derniers jours',
                      style: SoftPop.ui(size: 13, color: SoftPop.inkSecondary)),
                  const SizedBox(height: SoftPop.s12),
                  if (data.length >= 3)
                    SoftCard(
                      child: Center(
                        child: SizedBox(
                          height: 220,
                          width: 220,
                          child: CustomPaint(
                            painter: _RadarPainter([
                              for (final d in data) (d.color, d.bal),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  if (neglected != null && neglected.bal < 0.6) ...[
                    const SizedBox(height: SoftPop.s12),
                    _nudge(neglected.domain, neglected.color),
                  ],
                  const SizedBox(height: SoftPop.s20),
                  Text('Tes domaines',
                      style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
                  const SizedBox(height: SoftPop.s12),
                  for (final d in data) ...[
                    _domainCard(context, d.domain, d.color, d.bal),
                    const SizedBox(height: SoftPop.s8),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _nudge(Domain d, Color c) => Container(
        padding: const EdgeInsets.all(SoftPop.s12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(SoftPop.rCardSm),
        ),
        child: Row(
          children: [
            const Text('💛', style: TextStyle(fontSize: 18)),
            const SizedBox(width: SoftPop.s8),
            Expanded(
              child: Text(
                  '${d.name} est un peu délaissé en ce moment. Et si tu lui accordais un moment aujourd’hui ?',
                  style: SoftPop.ui(size: 12, color: SoftPop.inkSecondary, height: 1.3)),
            ),
          ],
        ),
      );

  Widget _domainCard(BuildContext context, Domain d, Color c, double bal) {
    final habits = _habits(d);
    final mins = logic.totalForDay(DateTime.now(), domainId: d.id).inMinutes;
    final best = habits.isEmpty
        ? 0
        : habits.map((a) => logic.habitCurrentStreak(a.id)).fold(0, math.max);
    return SoftCard(
      padding: const EdgeInsets.all(SoftPop.s12),
      radius: SoftPop.rCardSm,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _DomainDetail(logic: logic, domain: d, color: c))),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 40,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(6)),
          ),
          const SizedBox(width: SoftPop.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name,
                    style: SoftPop.ui(size: 15, weight: FontWeight.w700)),
                const SizedBox(height: SoftPop.s4),
                SoftXpBar(
                    value: bal,
                    height: 8,
                    gradient: LinearGradient(colors: [c, c]),
                    track: c.withValues(alpha: .15)),
                const SizedBox(height: SoftPop.s4),
                Text(
                    '${habits.length} routine${habits.length > 1 ? 's' : ''} · ⏱ ${mins}min · 🔥 $best j',
                    style: SoftPop.ui(size: 10, color: SoftPop.inkMuted)),
              ],
            ),
          ),
          const SizedBox(width: SoftPop.s8),
          Text('${(bal * 100).round()}%',
              style: SoftPop.mono(size: 14, color: c)),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<(Color, double)> data; // (couleur, 0..1)
  _RadarPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2 - 14;
    final n = data.length;
    double angle(int i) => -math.pi / 2 + i * 2 * math.pi / n;
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
    for (var i = 0; i < n; i++) {
      final p = center + Offset(math.cos(angle(i)), math.sin(angle(i))) * maxR;
      canvas.drawLine(center, p, grid);
    }
    final fill = Path();
    for (var i = 0; i < n; i++) {
      final r = maxR * data[i].$2.clamp(0.0, 1.0);
      final p = center + Offset(math.cos(angle(i)), math.sin(angle(i))) * r;
      i == 0 ? fill.moveTo(p.dx, p.dy) : fill.lineTo(p.dx, p.dy);
    }
    fill.close();
    canvas.drawPath(fill, Paint()..color = SoftPop.violet.withValues(alpha: .16));
    canvas.drawPath(
        fill,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = SoftPop.violet);
    for (var i = 0; i < n; i++) {
      final r = maxR * data[i].$2.clamp(0.0, 1.0);
      final p = center + Offset(math.cos(angle(i)), math.sin(angle(i))) * r;
      canvas.drawCircle(p, 4, Paint()..color = data[i].$1);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => true;
}

/// Détail d'un domaine (réel) : routines rattachées + temps.
class _DomainDetail extends StatelessWidget {
  final AppLogic logic;
  final Domain domain;
  final Color color;
  const _DomainDetail(
      {required this.logic, required this.domain, required this.color});

  @override
  Widget build(BuildContext context) {
    final habits = logic.state.activeActivities
        .where((a) => a.domainId == domain.id && a.isHabit)
        .toList();
    final times = logic.state.activeActivities
        .where((a) => a.domainId == domain.id && !a.isHabit)
        .toList();
    final mins = logic.totalForDay(DateTime.now(), domainId: domain.id).inMinutes;
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: Text(domain.name)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            SoftCard(
              gradient: LinearGradient(colors: [color, color.withValues(alpha: .7)]),
              padding: const EdgeInsets.all(SoftPop.s20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(domain.name,
                      style: SoftPop.ui(
                          size: 18, weight: FontWeight.w700, color: Colors.white)),
                  Text('⏱ ${mins}min',
                      style: SoftPop.mono(size: 14, color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: SoftPop.s16),
            if (habits.isNotEmpty) ...[
              Text('Routines',
                  style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
              const SizedBox(height: SoftPop.s12),
              for (final a in habits) _row(a, color, streak: true),
            ],
            if (times.isNotEmpty) ...[
              const SizedBox(height: SoftPop.s16),
              Text('Activités-temps',
                  style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
              const SizedBox(height: SoftPop.s12),
              for (final a in times) _row(a, color, streak: false),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(Activity a, Color c, {required bool streak}) {
    final s = streak ? logic.habitCurrentStreak(a.id) : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: SoftPop.s8),
      child: SoftCard(
        padding: const EdgeInsets.all(SoftPop.s12),
        radius: SoftPop.rCardSm,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: c.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(
                a.iconCode != null
                    // ignore: non_const_argument_for_const_parameter
                    ? IconData(a.iconCode!, fontFamily: 'MaterialIcons')
                    : (streak ? Icons.bolt : Icons.timer_outlined),
                size: 18,
                color: c,
              ),
            ),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Text(a.name,
                  style: SoftPop.ui(size: 14, weight: FontWeight.w600)),
            ),
            if (streak && s > 0)
              Text('🔥 $s j',
                  style: SoftPop.ui(size: 11, color: SoftPop.coralDark)),
          ],
        ),
      ),
    );
  }
}
