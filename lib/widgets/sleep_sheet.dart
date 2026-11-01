import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/elan_bands.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/mode_colors.dart';
import 'package:productivitwo_v1/utils/sleep_stats.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/mode_sheet.dart' show kRechargeBand, kRechargeColor, kRechargeInk;

const _kOk = Color(0xFF7FB2E8);
const _kShort = Color(0xFFF0B44C);
const _kDanger = Color(0xFFE5675B);

const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String _dayLabel(DateTime d) => '${_days[d.weekday - 1]} ${d.day}';

/// « 45 min » / « 1 h 20 » pour un écart.
String _gap(int min) => fmtNight(min.abs());

/// Feuille « Sommeil » (maquette validée 2026-11-01) : tap sur les barres de
/// sommeil de la barre du haut. Cette nuit, trois chiffres, 14 nuits, ton
/// coucher, ce que ça change le lendemain, 30 nuits, ce soir.
Future<void> showSleepSheet(
  BuildContext context, {
  required AppLogic logic,
  FirestoreSync? sync,
  required VoidCallback onOpenActivity,
  required Future<void> Function(BuildContext ctx, Session s) onEditSession,
  required void Function(Session s) onDeleteSession,
}) {
  return showFiche<void>(
    context,
    builder: (ctx, scroll) => SleepSheet(
      logic: logic,
      sync: sync,
      scroll: scroll,
      onOpenActivity: onOpenActivity,
      onEditSession: onEditSession,
      onDeleteSession: onDeleteSession,
    ),
  );
}

class SleepSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync? sync;
  final ScrollController? scroll;
  final VoidCallback onOpenActivity;
  final Future<void> Function(BuildContext ctx, Session s) onEditSession;
  final void Function(Session s) onDeleteSession;
  const SleepSheet({
    super.key,
    required this.logic,
    this.sync,
    this.scroll,
    required this.onOpenActivity,
    required this.onEditSession,
    required this.onDeleteSession,
  });

  @override
  State<SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends State<SleepSheet> {
  List<DailySchedule> _schedules = const [];

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
    _load();
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final sync = widget.sync;
    if (sync == null) return;
    final now = DateTime.now();
    try {
      final s = await sync.fetchDailySchedulesRange(ymdOf(now.subtract(const Duration(days: 31))), ymdOf(now));
      if (mounted) setState(() => _schedules = s);
    } catch (_) {}
  }

  /// Le lendemain de chaque nuit, vu par l'élan, les actions et les journées parfaites.
  Map<String, SleepNextDay> _nextDays(DateTime now) {
    final st = logic.state;
    final byYmd = {for (final s in _schedules) s.date: s};
    final marks = logic.elanMarksWithRecharge(byYmd);
    final days = buildElanDays(
        marks: marks, schedulesByYmd: byYmd, hits: st.habitHits, activities: st.activities, now: now, days: 31, dayStartMin: logic.dayStartMin);
    final actions = <String, int>{};
    for (final a in doneActionsOf(logic.currentProjects, st.activities)) {
      final k = ymdOf(livedDate(a.at, logic.dayStartMin));
      actions[k] = (actions[k] ?? 0) + 1;
    }
    final perfect = logic.embers.perfectYmds.toSet();
    final out = <String, SleepNextDay>{};
    for (final d in days) {
      final cells = elanCellsOfDay(marks, d.ymd, now, logic.dayStartMin);
      final share = modeShareOf([cells]);
      out[d.ymd] = SleepNextDay(
        elan: d.mean,
        lowShare: share.said == 0 ? null : share.low / share.said,
        actions: actions[d.ymd] ?? 0,
        perfect: perfect.contains(d.ymd),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = logic.state;
    final now = DateTime.now();
    final sleep = sleepActivityOf(st.activities);
    final ids = sleepActivityIds(st.activities);
    final target = sleepTargetMin(sleep);
    final nights30 = sleepNightList(sessions: st.sessions, activities: st.activities, now: now, dayStartMin: logic.dayStartMin, nights: 30);
    final nights14 = nights30.sublist(16);
    final week = nights14.sublist(7);
    final stats = sleepStats(week, target);
    final planned = plannedSleep(_schedules, ids);
    final last = nights14.reversed.whereType<SleepNight>().firstOrNull;
    final running = sleep != null && st.sessions.any((s) => !s.deleted && s.endAt == null && ids.contains(s.activityId));
    final todayYmd = ymdOf(livedDate(now, logic.dayStartMin));
    final impact = sleepImpact(nights30, _nextDays(now), target, todayYmd);
    final mute = cs.onSurface.withValues(alpha: .55);

    Widget title(String t, [String? right]) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Row(children: [
            Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
            if (right != null) Text(right, style: TextStyle(fontSize: 11.5, color: mute)),
          ]),
        );

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(children: [
          const Expanded(child: Text('Sommeil', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
          if (last != null && last.minutes < target - 30) _chip('nuit courte', _kShort),
          if (last != null && last.minutes >= target - 30) _chip('nuit complète', _kOk),
        ]),
        const SizedBox(height: 10),
        _hero(last, target),
        if (stats.nights > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            _stat(cs, fmtNight(stats.avgMin!), 'moyenne ${stats.nights} nuit${stats.nights > 1 ? 's' : ''}'),
            const SizedBox(width: 8),
            _stat(cs, '± ${stats.spreadMin} min', 'régularité du coucher'),
            const SizedBox(width: 8),
            _stat(cs, fmtNight(stats.debtMin), 'dette sur 7 nuits', color: stats.debtMin > 0 ? _kShort : null),
          ]),
        ],
        title('14 NUITS', 'touche une nuit'),
        _NightsChart(
          nights: nights14,
          target: target,
          planned: planned,
          onTap: (n) => _openNight(n, planned, target),
        ),
        const SizedBox(height: 6),
        Text(
          planned == null
              ? 'Une barre = une nuit, du coucher au lever. Ambre = sous ta cible de ${fmtNight(target)}.'
              : 'Une barre = une nuit, du coucher au lever. La bande bleue = ton bloc Sommeil (${clockOf(planned.bed)} → ${clockOf(planned.bed + planned.durationMin)}). Ambre = sous ta cible.',
          style: TextStyle(fontSize: 12, color: mute),
        ),
        if (stats.avgBed != null) ...[
          title('TON COUCHER', '7 nuits'),
          _BedDots(nights: week.whereType<SleepNight>().toList(), avgBed: stats.avgBed!, plannedBed: planned?.bed),
          const SizedBox(height: 6),
          _bedText(cs, stats, planned),
        ],
        title('UNE NUIT COURTE CHANGE-T-ELLE TA JOURNÉE ?', '30 jours'),
        _impact(cs, impact),
        title('30 NUITS', 'plus c’est clair, plus c’est long'),
        _Grid30(nights: nights30, target: target, onTap: (n) => _openNight(n, planned, target)),
        const SizedBox(height: 6),
        Text('✕ = nuit sans chrono Sommeil. Tap sur une case = la nuit.', style: TextStyle(fontSize: 12, color: mute)),
        title('CE SOIR'),
        _tonight(cs, planned, stats, target, sleep, running),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
          if (last != null) TextButton(onPressed: () => _openNight(last, planned, target), child: const Text('Corriger une nuit')),
          if (sleep != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenActivity();
              },
              child: const Text('Cible & fiche de l’activité'),
            ),
        ]),
      ],
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
      );

  Widget _hero(SleepNight? n, int target) {
    final body = n == null
        ? [
            const Text('Pas de nuit chronométrée', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 4),
            const Text('Lance le chrono Sommeil en te couchant : tes nuits se dessineront ici.', style: TextStyle(fontSize: 13, color: kRechargeInk)),
          ]
        : [
            Text('${n.pivot.isAfter(DateTime.now()) && DateTime.now().difference(n.wake).inMinutes < 2 ? 'Nuit en cours' : 'Cette nuit'} · ${_dayLabel(n.bed)} → ${_dayLabel(n.pivot)}',
                style: TextStyle(fontSize: 12, color: kRechargeInk.withValues(alpha: .85))),
            Text(fmtNight(n.minutes), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, height: 1.15)),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${_hm(n.bed)} → ${_hm(n.wake)} · '),
                if (n.minutes < target)
                  TextSpan(text: '${_gap(target - n.minutes)} de moins', style: const TextStyle(fontWeight: FontWeight.w800))
                else
                  TextSpan(text: '${_gap(n.minutes - target)} de plus', style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: ' que ta cible de ${fmtNight(target)}'),
              ]),
              style: const TextStyle(fontSize: 13, color: kRechargeInk),
            ),
          ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kRechargeColor, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body),
    );
  }

  Widget _stat(ColorScheme cs, String big, String small, {Color? color}) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(big, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color))),
            Text(small, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: .55))),
          ]),
        ),
      );

  Widget _bedText(ColorScheme cs, SleepStats s, ({int bed, int durationMin})? planned) {
    final wake = s.avgWake == null ? '' : ' Ton lever : ${clockOf(s.avgWake!)} en moyenne.';
    if (planned == null) {
      return Text('Tu te couches en moyenne à ${clockOf(s.avgBed!)}.$wake Pose un bloc Sommeil pour voir l’écart.',
          style: const TextStyle(fontSize: 14));
    }
    final late = s.avgBed! - planned.bed;
    final rel = late.abs() < 10
        ? 'pile à l’heure de ton bloc'
        : late > 0
            ? '${_gap(late)} après ton bloc'
            : '${_gap(late)} avant ton bloc';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Tu te couches en moyenne à '),
            TextSpan(text: clockOf(s.avgBed!), style: const TextStyle(fontWeight: FontWeight.w900)),
            TextSpan(text: ', $rel.$wake'),
          ]),
          style: const TextStyle(fontSize: 14)),
      if (late >= 15)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('C’est le coucher qui te coûte : ≈ ${fmtNight(late * 7)} par semaine.',
              style: const TextStyle(fontSize: 12, color: _kShort, fontWeight: FontWeight.w700)),
        ),
    ]);
  }

  Widget _impact(ColorScheme cs, SleepImpact imp) {
    final mute = TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .6), height: 1.35);
    // Retour user 2026-11-01 : dire ce qu'on compare avant de dire ce qu'il manque.
    final intro = Text(
      'On compare tes journées qui suivent une nuit longue (≥ ${fmtNight(imp.longMin)}) à celles qui suivent une nuit '
      'courte (< ${fmtNight(imp.shortMin)}) : ton élan, ton temps en Flemme, tes actions faites.',
      style: mute,
    );
    if (!imp.enough) {
      String days(int n) => '$n journée${n > 1 ? 's' : ''}';
      final fewShort = imp.short.days < kSleepImpactMinNights && imp.long.days >= kSleepImpactMinNights;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        intro,
        const SizedBox(height: 8),
        Text(
          'Il en faut au moins $kSleepImpactMinNights de chaque sorte sur 30 jours. Pour l’instant : '
          '${days(imp.long.days)} après une nuit longue, ${days(imp.short.days)} après une nuit courte.'
          '${fewShort ? ' Peu de nuits courtes : tant mieux, la comparaison attendra.' : ''}',
          style: mute,
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      intro,
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _side(cs, 'Après ≥ ${fmtNight(imp.longMin)}', imp.long, _kOk)),
        const SizedBox(width: 8),
        Expanded(child: _side(cs, 'Après < ${fmtNight(imp.shortMin)}', imp.short, _kShort)),
      ]),
      if (imp.sentence != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(imp.sentence!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
    ]);
  }

  Widget _side(ColorScheme cs, String label, SleepSide s, Color c) {
    final dark = cs.brightness == Brightness.dark;
    Widget line(String k, String v, double? frac, Color bar) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(k, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6)))),
              Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            ]),
            if (frac != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: frac.clamp(0.0, 1.0), minHeight: 5, color: bar, backgroundColor: cs.onSurface.withValues(alpha: .08)),
                ),
              ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: label, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
          TextSpan(text: ' · ${s.days} j', style: TextStyle(color: cs.onSurface.withValues(alpha: .5))),
        ]), style: const TextStyle(fontSize: 12)),
        line('élan moyen', s.elan == null ? '—' : s.elan!.toStringAsFixed(1).replaceAll('.', ','), s.elan == null ? null : s.elan! / 5,
            modeChipColor(DayMode.normal, dark: dark)),
        line('en Flemme', s.lowShare == null ? '—' : '${(s.lowShare! * 100).round()} %', s.lowShare, modeChipColor(DayMode.low, dark: dark)),
        line('actions faites', '${s.actions.toStringAsFixed(s.actions >= 10 ? 0 : 1).replaceAll('.', ',')} / j', s.actions / 8, _kOk),
        line('journées parfaites', '${s.perfect}', null, _kOk),
      ]),
    );
  }

  Widget _tonight(ColorScheme cs, ({int bed, int durationMin})? planned, SleepStats s, int target, Activity? sleep, bool running) {
    final lines = <Widget>[
      Text(planned == null ? 'Pas de bloc Sommeil au programme' : 'Bloc Sommeil ${clockOf(planned.bed)} → ${clockOf(planned.bed + planned.durationMin)}',
          style: const TextStyle(fontWeight: FontWeight.w800)),
    ];
    if (s.avgWake != null && s.debtMin > 0) {
      final night = target + (s.debtMin > 30 ? 30 : s.debtMin);
      lines.add(Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('Pour rattraper un peu ta dette, une nuit de ${fmtNight(night)} : couché à ${clockOf(bedFor(s.avgWake!, night))}.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6))),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
      ),
      if (sleep != null) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: running ? kRechargeColor : kRechargeBand, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
          onPressed: running
              ? () => logic.stopActive()
              : () {
                  logic.start(sleep.id);
                  Navigator.of(context).pop();
                },
          icon: Icon(running ? Icons.wb_sunny_outlined : Icons.bedtime_outlined),
          label: Text(running ? 'Je me lève · arrêter le chrono Sommeil' : 'Je vais me coucher'),
        ),
      ],
    ]);
  }

  Future<void> _openNight(SleepNight n, ({int bed, int durationMin})? planned, int target) async {
    await showFiche<void>(context, builder: (ctx, scroll) => _NightSheet(
          logic: logic,
          night: n,
          planned: planned,
          target: target,
          schedules: _schedules,
          scroll: scroll,
          onEditSession: widget.onEditSession,
          onDeleteSession: widget.onDeleteSession,
        ));
    if (mounted) setState(() {});
  }
}

// ── 14 nuits : barres du coucher au lever ───────────────────────────────────

class _NightsChart extends StatelessWidget {
  final List<SleepNight?> nights;
  final int target;
  final ({int bed, int durationMin})? planned;
  final void Function(SleepNight n) onTap;
  const _NightsChart({required this.nights, required this.target, required this.planned, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      const h = 200.0;
      return GestureDetector(
        onTapUp: (d) {
          final i = ((d.localPosition.dx - _NightsPainter.left) / ((w - _NightsPainter.left) / nights.length)).floor();
          if (i >= 0 && i < nights.length && nights[i] != null) onTap(nights[i]!);
        },
        child: CustomPaint(
          size: Size(w, h),
          painter: _NightsPainter(nights, target, planned, cs.onSurface, MaterialLocalizations.of(context)),
        ),
      );
    });
  }
}

class _NightsPainter extends CustomPainter {
  static const left = 30.0;
  final List<SleepNight?> nights;
  final int target;
  final ({int bed, int durationMin})? planned;
  final Color ink;
  final MaterialLocalizations loc;
  _NightsPainter(this.nights, this.target, this.planned, this.ink, this.loc);

  /// Minutes depuis 18:00 la veille du lendemain.
  int _m(DateTime t, DateTime pivot) {
    final base = DateTime(pivot.year, pivot.month, pivot.day - 1, 18);
    return t.difference(base).inMinutes;
  }

  @override
  void paint(Canvas canvas, Size size) {
    var lo = 21 * 60 - 18 * 60, hi = 10 * 60 + 6 * 60; // 21:00 → 10:00
    for (final n in nights.whereType<SleepNight>()) {
      lo = lo < _m(n.bed, n.pivot) ? lo : _m(n.bed, n.pivot);
      hi = hi > _m(n.wake, n.pivot) ? hi : _m(n.wake, n.pivot);
    }
    if (planned != null) {
      final pb = planned!.bed + 6 * 60;
      lo = lo < pb ? lo : pb;
      hi = hi > pb + planned!.durationMin ? hi : pb + planned!.durationMin;
    }
    // Trait rouge « maintenant » (retour user 2026-11-01), de 18 h à 10 h.
    final nowClock = bedClockMin(DateTime.now());
    final nowM = nowClock >= -360 && nowClock <= 600 ? nowClock + 6 * 60 : null;
    if (nowM != null) {
      lo = lo < nowM ? lo : nowM;
      hi = hi > nowM ? hi : nowM;
    }
    lo = (lo ~/ 60) * 60;
    hi = ((hi + 59) ~/ 60) * 60;
    const top = 6.0, bottom = 18.0;
    final plotH = size.height - top - bottom;
    double y(int m) => top + (m - lo) / (hi - lo) * plotH;
    final grid = Paint()..color = ink.withValues(alpha: .08);
    final step = (hi - lo) > 13 * 60 ? 180 : 120;
    for (var m = lo; m <= hi; m += step) {
      canvas.drawLine(Offset(left, y(m)), Offset(size.width, y(m)), grid);
      final tp = TextPainter(
          text: TextSpan(text: '${((m ~/ 60) + 18) % 24} h', style: TextStyle(fontSize: 10, color: ink.withValues(alpha: .4))),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(0, y(m) - 6));
    }
    if (planned != null) {
      final pb = planned!.bed + 6 * 60;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(left, y(pb), size.width, y(pb + planned!.durationMin)), const Radius.circular(6)),
          Paint()..color = kRechargeBand.withValues(alpha: .22));
    }
    if (nowM != null) {
      final ny = y(nowM);
      canvas.drawLine(Offset(left, ny), Offset(size.width, ny), Paint()
        ..color = _kDanger
        ..strokeWidth = 2);
      final tp = TextPainter(
          text: TextSpan(text: 'maintenant ${clockOf(nowClock)}', style: const TextStyle(fontSize: 10, color: _kDanger, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(size.width - tp.width, ny < top + 14 ? ny + 2 : ny - 13));
    }
    final colW = (size.width - left) / nights.length;
    final barW = (colW * .62).clamp(6.0, 18.0);
    for (var i = 0; i < nights.length; i++) {
      final n = nights[i];
      final cx = left + colW * i + colW / 2;
      if (n != null) {
        final short = n.minutes < target - 30;
        final last = i == nights.length - 1 || nights.skip(i + 1).every((x) => x == null);
        final paint = Paint()..color = (short ? _kShort : _kOk).withValues(alpha: last ? 1 : .8);
        for (final s in n.spans) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTRB(cx - barW / 2, y(_m(s.start, n.pivot)), cx + barW / 2, y(_m(s.end, n.pivot))), const Radius.circular(5)),
              paint);
        }
        if (last) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTRB(cx - barW / 2 - 1.5, y(_m(n.bed, n.pivot)) - 1.5, cx + barW / 2 + 1.5, y(_m(n.wake, n.pivot)) + 1.5),
                  const Radius.circular(6)),
              Paint()
                ..color = ink.withValues(alpha: .85)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5);
        }
      }
      final day = DateTime.now().subtract(Duration(days: nights.length - 1 - i));
      final label = n == null ? _days[day.weekday - 1].substring(0, 2) : _days[n.pivot.weekday - 1].substring(0, 2);
      final tp = TextPainter(text: TextSpan(text: label, style: TextStyle(fontSize: 9, color: ink.withValues(alpha: .4))), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - 12));
    }
  }

  @override
  bool shouldRepaint(covariant _NightsPainter old) => true;
}

// ── Ton coucher : un point par nuit autour du bloc ───────────────────────────

class _BedDots extends StatelessWidget {
  final List<SleepNight> nights;
  final int avgBed;
  final int? plannedBed;
  const _BedDots({required this.nights, required this.avgBed, this.plannedBed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Trait rouge « maintenant » (retour user 2026-11-01) : où tomberait le
    // coucher si on allait se coucher là — seulement de 18 h à 10 h.
    final now = bedClockMin(DateTime.now());
    final nowClock = now >= -360 && now <= 600 ? now : null;
    return SizedBox(height: 62, width: double.infinity, child: CustomPaint(painter: _BedPainter(nights, avgBed, plannedBed, cs.onSurface, nowClock: nowClock)));
  }
}

class _BedPainter extends CustomPainter {
  final List<SleepNight> nights;
  final int avgBed;
  final int? plannedBed;
  final Color ink;
  final int? nowClock;
  _BedPainter(this.nights, this.avgBed, this.plannedBed, this.ink, {this.nowClock});

  void _text(Canvas c, String t, Offset o, Color color, {bool center = true}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, Offset(center ? o.dx - tp.width / 2 : o.dx, o.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final beds = [for (final n in nights) bedClockMin(n.bed)];
    final pts = [...beds, avgBed, if (plannedBed != null) plannedBed!, if (nowClock != null) nowClock!];
    var lo = pts.reduce((a, b) => a < b ? a : b) - 30;
    var hi = pts.reduce((a, b) => a > b ? a : b) + 30;
    lo = (lo ~/ 60) * 60 - (lo < 0 && lo % 60 != 0 ? 60 : 0);
    hi = ((hi + 59) ~/ 60) * 60;
    double x(int m) => 8 + (m - lo) / (hi - lo) * (size.width - 16);
    final axisY = size.height - 20;
    canvas.drawLine(Offset(8, axisY), Offset(size.width - 8, axisY), Paint()..color = ink.withValues(alpha: .12));
    for (var m = lo; m <= hi; m += 60) {
      _text(canvas, clockOf(m), Offset(x(m), axisY + 6), ink.withValues(alpha: .4));
    }
    if (plannedBed != null) {
      final px = x(plannedBed!);
      final dash = Paint()
        ..color = _kOk
        ..strokeWidth = 2;
      for (var yy = 12.0; yy < axisY; yy += 6) {
        canvas.drawLine(Offset(px, yy), Offset(px, yy + 3), dash);
      }
      _text(canvas, 'bloc ${clockOf(plannedBed!)}', Offset(px, 0), _kOk);
    }
    for (var i = 0; i < beds.length; i++) {
      canvas.drawCircle(Offset(x(beds[i]), 22.0 + (i % 3) * 7), 5, Paint()..color = _kShort.withValues(alpha: .85));
    }
    if (nowClock != null) {
      final nx = x(nowClock!);
      canvas.drawLine(Offset(nx, 12), Offset(nx, axisY), Paint()
        ..color = _kDanger
        ..strokeWidth = 2);
      final right = nx < size.width - 60;
      _text(canvas, 'maintenant ${clockOf(nowClock!)}', Offset(right ? nx + 4 : nx - 92, axisY - 14), _kDanger, center: false);
    }
    final ax = x(avgBed);
    canvas.drawLine(Offset(ax, 14), Offset(ax, axisY), Paint()
      ..color = _kShort
      ..strokeWidth = 2);
    if (plannedBed == null || (ax - x(plannedBed!)).abs() > 60) {
      _text(canvas, 'moy. ${clockOf(avgBed)}', Offset(ax, 0), _kShort);
    } else {
      _text(canvas, 'moy. ${clockOf(avgBed)}', Offset(ax + 4, axisY - 14), _kShort, center: false);
    }
  }

  @override
  bool shouldRepaint(covariant _BedPainter old) => true;
}

// ── 30 nuits ────────────────────────────────────────────────────────────────

class _Grid30 extends StatelessWidget {
  final List<SleepNight?> nights;
  final int target;
  final void Function(SleepNight n) onTap;
  const _Grid30({required this.nights, required this.target, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (var i = 0; i < nights.length; i++)
          GestureDetector(
            onTap: nights[i] == null ? null : () => onTap(nights[i]!),
            child: Container(
              decoration: BoxDecoration(
                color: nights[i] == null
                    ? cs.onSurface.withValues(alpha: .05)
                    : _kOk.withValues(alpha: ((nights[i]!.minutes - (target - 150)) / 210).clamp(.15, 1.0).toDouble()),
                borderRadius: BorderRadius.circular(4),
                border: i == nights.length - 1 ? Border.all(color: cs.onSurface.withValues(alpha: .8), width: 1.5) : null,
              ),
              // Nuit sans chrono Sommeil : une croix rouge, pour la voir d'un coup d'œil.
              child: nights[i] == null ? const Center(child: Icon(Icons.close_rounded, size: 18, color: _kDanger)) : null,
            ),
          ),
      ],
    );
  }
}

// ── Une nuit ────────────────────────────────────────────────────────────────

class _NightSheet extends StatelessWidget {
  final AppLogic logic;
  final SleepNight night;
  final ({int bed, int durationMin})? planned;
  final int target;
  final List<DailySchedule> schedules;
  final ScrollController scroll;
  final Future<void> Function(BuildContext ctx, Session s) onEditSession;
  final void Function(Session s) onDeleteSession;
  const _NightSheet({
    required this.logic,
    required this.night,
    required this.planned,
    required this.target,
    required this.schedules,
    required this.scroll,
    required this.onEditSession,
    required this.onDeleteSession,
  });

  List<Session> _sessions() {
    final ids = sleepActivityIds(logic.state.activities);
    final from = night.pivot.subtract(const Duration(hours: 10));
    final to = night.pivot.add(const Duration(hours: 7));
    return logic.state.sessions
        .where((s) => !s.deleted && ids.contains(s.activityId) && !s.startAt.isBefore(from) && s.startAt.isBefore(to))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final mute = cs.onSurface.withValues(alpha: .55);
    final sessions = _sessions();
    final p = night.pivot;
    final prev = DateTime(p.year, p.month, p.day - 1);
    final head = 'NUIT DU ${_days[prev.weekday - 1].toUpperCase()} ${prev.day} AU ${_days[p.weekday - 1].toUpperCase()} ${p.day} ${_months[p.month - 1].toUpperCase()}';
    final late = planned == null ? null : bedClockMin(night.bed) - planned!.bed;
    final byYmd = {for (final s in schedules) s.date: s};
    final marks = logic.elanMarksWithRecharge(byYmd);
    final next = night.nextYmd;
    final now = DateTime.now();
    final cells = elanCellsOfDay(marks, next, now, logic.dayStartMin);
    final elanDay = buildElanDays(
            marks: marks, schedulesByYmd: byYmd, hits: logic.state.habitHits, activities: logic.state.activities, now: now, days: 31, dayStartMin: logic.dayStartMin)
        .where((d) => d.ymd == next)
        .firstOrNull;
    final wins = elanDay == null ? 0 : lowWinsOf(elanDay);
    final actions = doneActionsOf(logic.currentProjects, logic.state.activities).where((a) => ymdOf(livedDate(a.at, logic.dayStartMin)) == next).length;

    Widget title(String t, [String? right]) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Row(children: [
            Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
            if (right != null) Text(right, style: TextStyle(fontSize: 11.5, color: mute)),
          ]),
        );
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [Expanded(child: Text(k, style: TextStyle(color: mute))), Text(v, style: const TextStyle(fontWeight: FontWeight.w800))]),
        );

    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Text(head, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .7, color: mute)),
      const SizedBox(height: 4),
      Text(fmtNight(night.minutes), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
      Text(
          '${_hm(night.bed)} → ${_hm(night.wake)}${planned == null ? '' : ' · prévu ${clockOf(planned!.bed)} → ${clockOf(planned!.bed + planned!.durationMin)}'}',
          style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, children: [
        if (night.minutes < target) _pill('${fmtNight(target - night.minutes)} sous ta cible', _kShort) else _pill('cible tenue', _kOk),
        if (late != null && late >= 15) _pill('couché ${_gap(late)} après ton bloc', _kShort),
        if (late != null && late <= -15) _pill('couché ${_gap(late)} avant ton bloc', _kOk),
      ]),
      title('LA NUIT'),
      SizedBox(height: 56, width: double.infinity, child: CustomPaint(painter: _OneNightPainter(night, planned, cs.onSurface))),
      title('CHRONOS', '${sessions.length}'),
      for (final s in sessions)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          elevation: 0,
          color: cs.onSurface.withValues(alpha: .05),
          child: ListTile(
            dense: true,
            title: Text('${_hm(s.startAt)} → ${s.endAt == null ? 'en cours' : _hm(s.endAt!)}'),
            trailing: Text(fmtNight((s.endAt ?? now).difference(s.startAt).inMinutes), style: const TextStyle(fontWeight: FontWeight.w800)),
            onTap: () => onEditSession(context, s),
          ),
        ),
      if (night.awakeMin >= 5)
        Text('Réveil de ${fmtNight(night.awakeMin)} : il ne compte pas dans la nuit.', style: TextStyle(fontSize: 12, color: mute)),
      if (next.compareTo(ymdOf(livedDate(now, logic.dayStartMin))) <= 0) ...[
        title('LE LENDEMAIN', '${_days[p.weekday - 1]} ${p.day}'),
        if (cells.any((v) => v != null))
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 20,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final v in cells)
                  Expanded(
                    child: ColoredBox(
                      color: switch (bandModeOf(v)) {
                        BandMode.low => modeChipColor(DayMode.low, dark: dark),
                        BandMode.normal => modeChipColor(DayMode.normal, dark: dark),
                        BandMode.high => modeChipColor(DayMode.high, dark: dark),
                        BandMode.recharge => kRechargeBand,
                        null => cs.onSurface.withValues(alpha: .06),
                      },
                    ),
                  ),
              ]),
            ),
          )
        else
          Text('Rien de dit ce jour-là.', style: TextStyle(fontSize: 12.5, color: mute)),
        if (elanDay?.mean != null) kv('élan moyen', elanDay!.mean!.toStringAsFixed(1).replaceAll('.', ',')),
        kv('victoires sur la flemme', '$wins'),
        kv('actions faites', '$actions'),
      ],
      const SizedBox(height: 18),
      if (sessions.isNotEmpty)
        OutlinedButton(
          onPressed: () => onEditSession(context, sessions.first),
          child: Text(sessions.length > 1 ? 'Modifier le premier chrono' : 'Modifier les heures'),
        ),
      if (sessions.isNotEmpty)
        TextButton(
          style: TextButton.styleFrom(foregroundColor: _kDanger),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Supprimer cette nuit ?'),
                content: Text('${sessions.length} chrono${sessions.length > 1 ? 's' : ''} Sommeil ${sessions.length > 1 ? 'seront supprimés' : 'sera supprimé'}.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
                  TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer')),
                ],
              ),
            );
            if (ok != true || !context.mounted) return;
            for (final s in sessions) {
              onDeleteSession(s);
            }
            Navigator.of(context).pop();
          },
          child: const Text('Supprimer cette nuit'),
        ),
    ]);
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
      );
}

class _OneNightPainter extends CustomPainter {
  final SleepNight night;
  final ({int bed, int durationMin})? planned;
  final Color ink;
  _OneNightPainter(this.night, this.planned, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    int m(DateTime t) => bedClockMin(t);
    var lo = m(night.bed), hi = m(night.wake);
    if (planned != null) {
      lo = lo < planned!.bed ? lo : planned!.bed;
      hi = hi > planned!.bed + planned!.durationMin ? hi : planned!.bed + planned!.durationMin;
    }
    lo = (lo / 60).floor() * 60;
    hi = (hi / 60).ceil() * 60;
    double x(int v) => 4 + (v - lo) / (hi - lo) * (size.width - 8);
    if (planned != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x(planned!.bed), 4, x(planned!.bed + planned!.durationMin), 34), const Radius.circular(8)),
          Paint()..color = kRechargeBand.withValues(alpha: .25));
    }
    for (final s in night.spans) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x(m(s.start)), 8, x(m(s.end)), 30), const Radius.circular(6)),
          Paint()..color = _kOk);
    }
    final step = (hi - lo) > 10 * 60 ? 120 : 60;
    for (var v = lo; v <= hi; v += step) {
      final tp = TextPainter(text: TextSpan(text: clockOf(v), style: TextStyle(fontSize: 10, color: ink.withValues(alpha: .4))), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset((x(v) - tp.width / 2).clamp(0.0, size.width - tp.width), 40));
    }
  }

  @override
  bool shouldRepaint(covariant _OneNightPainter old) => true;
}
