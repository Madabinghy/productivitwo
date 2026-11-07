import 'package:productivitwo_v1/gamification_flags.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show routineReachedDays, kRoutineTiers;
import 'package:productivitwo_v1/utils/embers.dart';
import 'package:productivitwo_v1/utils/hard_days.dart' show kHardDayCooldownDays, nextHardDayAfter;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart' show kEmberColor;
import 'package:productivitwo_v1/widgets/fiche.dart';

/// Braises, écrans (lot 2, maquette « Braises de rattrapage » 2026-10-30).

/// La réserve en trois flammes ; [extra] = la braise forgée ce soir (pointillé).
class EmberDots extends StatelessWidget {
  final int stock;
  final bool extra;
  final String? label;
  const EmberDots({super.key, required this.stock, this.extra = false, this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < kEmberCap; i++)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            i < stock ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
            size: 20,
            color: i < stock ? kEmberColor : (extra && i == stock ? kEmberColor.withValues(alpha: .7) : kBText4),
          ),
        ),
      if (label != null) ...[
        const SizedBox(width: 4),
        Flexible(child: Text(label!, style: const TextStyle(fontSize: 12, color: kBText3))),
      ],
    ]);
  }
}

String emberCountLabel(int n) => n == 0 ? 'aucune braise en réserve' : '$n braise${n > 1 ? 's' : ''} en réserve';

/// Une série cassée hier : « Rallumer · 🔥1 », ou en attente de la routine du
/// jour (faite ailleurs, par le geste habituel ; ✕ = annuler avec confirmation),
/// ou indisponible avec la raison.
class LostSeriesRow extends StatelessWidget {
  final LostSeries lost;
  final int todayCount;
  final int target;
  final VoidCallback? onRekindle;
  final VoidCallback? onCancel;
  const LostSeriesRow({super.key, required this.lost, this.todayCount = 0, this.target = 1, this.onRekindle, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final l = lost;
    final sub = l.pending
        ? 'rallumée · fais ${l.name} aujourd’hui ($todayCount / $target) pour garder la série'
        : (l.blocked ?? '${l.nextTier == null ? '' : 'palier ${l.nextTier} j dans ${l.nextTier! - l.length} j · '}rattrapable jusqu’à ce soir');
    final Widget action;
    if (l.pending) {
      action = onCancel == null
          ? const SizedBox.shrink()
          : IconButton(tooltip: 'Annuler le rallumage', visualDensity: VisualDensity.compact, onPressed: onCancel, icon: const Icon(Icons.close_rounded, size: 20, color: kBText3));
    } else if (l.rekindlable) {
      action = _pill('Rallumer · 🔥1', kEmberColor, onRekindle, filled: true);
    } else {
      action = _pill('Indisponible', kBText3, null);
    }
    return Opacity(
      opacity: l.blocked != null && !l.pending ? .7 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: kBSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: l.pending ? kEmberColor.withValues(alpha: .5) : (l.rekindlable ? kBAlert.withValues(alpha: .35) : kBLine)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${l.name} · série de ${l.length} j cassée', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: l.pending ? kEmberColor : kBText3)),
            ]),
          ),
          const SizedBox(width: 8),
          action,
        ]),
      ),
    );
  }

  Widget _pill(String label, Color c, VoidCallback? onTap, {bool filled = false}) => SizedBox(
        height: 34,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: filled ? c : Colors.transparent,
            foregroundColor: filled ? const Color(0xFF1F0B02) : c,
            disabledBackgroundColor: Colors.transparent,
            disabledForegroundColor: c,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: filled ? null : BorderSide(color: c.withValues(alpha: .4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        ),
      );
}

/// Section « PERDU HIER » (refonte 2026-11-06, maquette « Journée difficile ») : UNE carte au lieu d'une ligne par
/// série — « Hier, n séries se sont cassées », la journée difficile en premier quand elle est possible, puis « Ou
/// garder une série » avec la braise (3 lignes, le reste replié). Hier déclarée difficile : « Hier gelée · n séries
/// gardées » avec « Annuler ». [all] = feuille des enjeux (séries indisponibles comprises).
class LostYesterdaySection extends StatefulWidget {
  final AppLogic logic;
  final bool all;
  final VoidCallback onChanged;
  /// Ouvre le choix du minimum en prenant hier avec lui (`showMinimumSheet(fromYesterday: true)`).
  final Future<bool?> Function()? onMinimum;
  const LostYesterdaySection({super.key, required this.logic, required this.onChanged, this.all = false, this.onMinimum});

  @override
  State<LostYesterdaySection> createState() => _LostYesterdaySectionState();
}

const kHardDayColor = Color(0xFF7D95FF);

class _LostYesterdaySectionState extends State<LostYesterdaySection> {
  bool _expanded = false;

  AppLogic get logic => widget.logic;

  @override
  Widget build(BuildContext context) {
    if (logic.yesterdayIsHard) return _hardCard(context);
    final lostAll = logic.lostSeriesYesterday();
    if (lostAll.isEmpty) return const SizedBox.shrink();
    // Sans braises (2026-11-07) : la journée difficile est le seul recours, dès une série cassée.
    final canHard = logic.canDeclareYesterdayHard && lostAll.where((l) => !l.pending).length >= (kEmbersEnabled ? 2 : 1);
    final lost = lostAll.where((l) => l.pending || (kEmbersEnabled && (widget.all || l.rekindlable))).toList();
    final canMin = widget.onMinimum != null && logic.minimumNow == null && lostAll.length >= 2;
    if (lost.isEmpty && !canHard && !canMin) return const SizedBox.shrink();
    final ledger = logic.emberLedgerNow();
    final pending = lost.where((l) => l.pending).toList();
    final rest = lost.where((l) => !l.pending).toList()..sort((x, y) => y.length.compareTo(x.length));
    final shown = _expanded ? rest : rest.take(3).toList();
    final hidden = rest.length - shown.length;
    final last = logic.lastHardDay;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: kBSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: canHard ? kHardDayColor.withValues(alpha: .45) : kEmberColor.withValues(alpha: .4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('PERDU HIER', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: canHard ? kHardDayColor : kEmberColor)),
          const InfoDot(kRuleHardDay, size: 16),
          const Spacer(),
          const Text('jusqu’à ce soir', style: TextStyle(fontSize: 11, color: kBText4)),
        ]),
        const SizedBox(height: 4),
        Text('Hier, ${lostAll.length} série${lostAll.length > 1 ? 's se sont cassées' : ' s’est cassée'}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kBText)),
        const SizedBox(height: 4),
        if (canHard) ...[
          Text(kEmbersEnabled ? 'Ça arrive. Tu peux encaisser la journée, ou garder une seule série avec ta braise.' : 'Ça arrive. Si hier a vraiment été une journée difficile, tu peux le geler.',
              style: const TextStyle(fontSize: 13, color: kBText3)),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('hard-day-open'),
            onPressed: () => _openHardDay(context, lostAll),
            style: FilledButton.styleFrom(
              backgroundColor: kHardDayColor,
              foregroundColor: const Color(0xFF0A1033),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('C’était une journée difficile', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Text('${lostAll.length > 1 ? 'les ${lostAll.length} séries gelées' : 'la série gelée'} · possible 1 fois tous les $kHardDayCooldownDays jours',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: kBText4)),
        ] else if (last != null && lostAll.length >= 2)
          Text('Journée difficile déjà prise le ${_dayLabel(last)} · à nouveau possible le ${_dayLabel(nextHardDayAfter(last))}',
              style: const TextStyle(fontSize: 12.5, color: kBText3)),
        // Le minimum (2026-11-06) : quand ça dure, gèle hier et aujourd'hui, on choisit ce qu'on garde.
        if (canMin) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('lost-to-minimum'),
            onPressed: () async {
              final ok = await widget.onMinimum?.call();
              if (ok == true) widget.onChanged();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: kBText,
              side: BorderSide(color: kHardDayColor.withValues(alpha: .5)),
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('Ça dure · passer au minimum', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          const Text('gèle hier et aujourd’hui · tu choisis ce que tu gardes', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: kBText4)),
        ],
        for (final l in pending)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LostSeriesRow(
              lost: l,
              todayCount: _todayCount(logic, l.activityId),
              target: (_act(l.activityId)?.habitTarget ?? 1).clamp(1, 999),
              onCancel: () => _cancel(context, l),
            ),
          ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(canHard ? 'OU GARDER UNE SÉRIE' : 'GARDER UNE SÉRIE',
                  style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
            ),
            const Icon(Icons.local_fire_department_rounded, size: 16, color: kEmberColor),
            const SizedBox(width: 2),
            Text(ledger.available == 0 ? 'aucune braise' : '${ledger.available} braise${ledger.available > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: kEmberColor)),
          ]),
          for (final l in shown) _compactRow(context, l),
          if (hidden > 0)
            TextButton(
              key: const ValueKey('lost-more'),
              onPressed: () => setState(() => _expanded = true),
              style: TextButton.styleFrom(foregroundColor: kBText3, alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
              child: Text('+ $hidden autre${hidden > 1 ? 's' : ''} · ${rest.skip(shown.length).take(2).map((l) => l.name).join(', ')}${hidden > 2 ? '…' : ''}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
            ),
        ],
      ]),
    );
  }

  Widget _compactRow(BuildContext context, LostSeries l) {
    final can = l.rekindlable;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBLine))),
      child: Row(children: [
        Expanded(child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText))),
        Text('${l.length} j', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kBText3)),
        const SizedBox(width: 10),
        if (can)
          SizedBox(
            height: 32,
            child: FilledButton(
              key: ValueKey('rekindle-${l.activityId}'),
              onPressed: () => _rekindle(context, l),
              style: FilledButton.styleFrom(
                backgroundColor: kEmberColor,
                foregroundColor: const Color(0xFF1F0B02),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: const Text('Garder', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
          )
        else
          Tooltip(
            message: l.blocked ?? '',
            child: Text(l.blocked == null ? '' : _shortBlocked(l.blocked!), style: const TextStyle(fontSize: 12, color: kBText4)),
          ),
      ]),
    );
  }

  static String _shortBlocked(String reason) => reason.contains('aucune braise') || reason.contains('Aucune braise') ? 'plus de braise' : 'indisponible';

  Widget _hardCard(BuildContext context) {
    final saved = logic.lostSeriesIfNotHard().length;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(18), border: Border.all(color: kHardDayColor.withValues(alpha: .45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.ac_unit_rounded, size: 18, color: kHardDayColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(saved > 0 ? 'Hier gelée · $saved série${saved > 1 ? 's' : ''} gardée${saved > 1 ? 's' : ''}' : 'Hier gelée · journée difficile',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kBText)),
          ),
          const InfoDot(kRuleHardDay, size: 16),
        ]),
        const SizedBox(height: 4),
        Text('Tes séries reprennent aujourd’hui. Prochaine journée difficile possible le ${_dayLabel(nextHardDayAfter(logic.livedYesterdayYmd))}.',
            style: const TextStyle(fontSize: 13, color: kBText3)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('hard-day-cancel'),
            onPressed: () => _cancelHard(context),
            style: TextButton.styleFrom(foregroundColor: kBText3, padding: EdgeInsets.zero),
            child: const Text('Annuler, je préfère perdre ces séries', style: TextStyle(fontSize: 13, decoration: TextDecoration.underline)),
          ),
        ),
      ]),
    );
  }

  Activity? _act(String id) => logic.state.activeActivities.where((a) => a.id == id).firstOrNull;

  Future<void> _openHardDay(BuildContext context, List<LostSeries> lost) async {
    final ok = await showHardDaySheet(context, logic: logic, lost: lost);
    if (ok == true) widget.onChanged();
  }

  Future<void> _rekindle(BuildContext context, LostSeries l) async {
    final a = _act(l.activityId);
    if (a == null) return;
    final ok = await showRekindleSheet(context, logic: logic, routine: a, lost: l);
    if (ok) widget.onChanged();
  }

  Future<void> _cancel(BuildContext context, LostSeries l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler le rallumage ?'),
        content: Text('La braise revient dans ta réserve et la série de ${l.name} reste cassée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Garder')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler le rallumage')),
        ],
      ),
    );
    if (ok != true) return;
    await logic.cancelRekindle(l.activityId);
    widget.onChanged();
  }

  Future<void> _cancelHard(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la journée difficile ?'),
        content: const Text('Les séries d’hier redeviennent cassées. Tu pourras encore en garder une avec une braise.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Garder le gel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler')),
        ],
      ),
    );
    if (ok != true) return;
    await logic.cancelYesterdayHard();
    widget.onChanged();
  }

  static int _todayCount(AppLogic logic, String id) {
    final today = logic.livedTodayYmd;
    return logic.state.habitHits.where((h) => h.habitId == id && ymdOf(livedDate(h.ts, logic.dayStartMin)) == today).length;
  }
}

const _kMonths = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _kWeekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

String _dayLabel(String ymd) {
  final d = DateTime.parse(ymd);
  return '${d.day} ${_kMonths[d.month - 1]}';
}

/// Feuille « Hier était une journée difficile ? » : ce que ça fait, ce que ça coûte, puis le geste.
/// Renvoie true quand la journée est déclarée.
Future<bool?> showHardDaySheet(BuildContext context, {required AppLogic logic, required List<LostSeries> lost}) {
  final yesterday = logic.livedYesterdayYmd;
  final d = DateTime.parse(yesterday);
  final sorted = [...lost]..sort((a, b) => b.length.compareTo(a.length));
  return showFiche<bool>(context, builder: (ctx, scroll) {
    Widget section(String title, List<Widget> children) => Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBLine)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
            const SizedBox(height: 6),
            ...children,
          ]),
        );
    Widget line(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(a, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText))),
            Text(b, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kBText3)),
          ]),
        );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        const Text('Hier était une journée difficile ?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBText)),
        const SizedBox(height: 2),
        Text('${_kWeekdays[d.weekday - 1][0].toUpperCase()}${_kWeekdays[d.weekday - 1].substring(1)} ${d.day} ${_kMonths[d.month - 1]}',
            style: const TextStyle(fontSize: 13, color: kBText3)),
        section('CE QUE ÇA FAIT', [
          Text('${lost.length > 1 ? 'Les ${lost.length} séries cassées hier sont gelées : elles reprennent là où elles étaient' : 'La série cassée hier est gelée : elle reprend là où elle était'}, sans gagner de jour.',
              style: const TextStyle(fontSize: 13.5, color: kBText2)),
          const SizedBox(height: 4),
          for (final l in sorted.take(3)) line(l.name, '${l.length} j → ${l.length} j'),
          if (sorted.length > 3) line('+ ${sorted.length - 3} autre${sorted.length > 4 ? 's' : ''}', 'gardée${sorted.length > 4 ? 's' : ''}'),
        ]),
        section('CE QUE ÇA COÛTE', [
          Text('Hier ne compte pas pour Journée parfaite, Métronome ni Montre suisse${kEmbersEnabled ? ', et ne forge pas de braise' : ''}.',
              style: const TextStyle(fontSize: 13.5, color: kBText2)),
          const SizedBox(height: 6),
          Text('La prochaine journée difficile sera possible dès le ${_dayLabel(nextHardDayAfter(yesterday))}.',
              style: const TextStyle(fontSize: 13.5, color: kBText2)),
        ]),
        const SizedBox(height: 10),
        const Text('À faire avant la fin de la journée : après, hier est clos.', style: TextStyle(fontSize: 12.5, color: kBText4)),
        const SizedBox(height: 14),
        FilledButton(
          key: const ValueKey('hard-day-confirm'),
          onPressed: () async {
            await logic.declareYesterdayHard();
            if (ctx.mounted) Navigator.pop(ctx, true);
          },
          style: FilledButton.styleFrom(
            backgroundColor: kHardDayColor,
            foregroundColor: const Color(0xFF0A1033),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: const Text('Oui, je gèle la journée d’hier', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: kBText3),
          child: Text(kEmbersEnabled ? 'Non, j’utilise plutôt ma braise' : 'Non, pas cette fois', style: const TextStyle(decoration: TextDecoration.underline)),
        ),
      ],
    );
  });
}

/// Feuille « Rallumer X ? » : les six derniers jours, prix, condition,
/// résultat, trace. Renvoie true si le rallumage est armé.
Future<bool> showRekindleSheet(BuildContext context, {required AppLogic logic, required Activity routine, required LostSeries lost}) async {
  final ok = await showFiche<bool>(context, builder: (ctx, scroll) {
    final today = logic.livedTodayYmd;
    final reached = routineReachedDays(routine, logic.state.habitHits, dayStartMin: logic.dayStartMin);
    final bridged = logic.bridgedOf(routine.id);
    final ledger = logic.emberLedgerNow();
    final target = (routine.habitTarget ?? 1).clamp(1, 999);
    final doneToday = reached.contains(today);
    final after = lost.length + 2;
    final nextTier = kRoutineTiers.where((t) => t > after).firstOrNull;
    const days = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    Widget cell(String ymd) {
      final d = DateTime.parse(ymd);
      final label = days[d.weekday - 1];
      final isToday = ymd == today, isLost = ymd == lost.lostYmdOf(today);
      final Color? fill;
      final Color border;
      final Color fg;
      if (isToday) {
        fill = doneToday ? const Color(0xFF2FB3A3) : null;
        border = const Color(0xFF2FB3A3);
        fg = doneToday ? kBBg : const Color(0xFF2FB3A3);
      } else if (isLost) {
        fill = kEmberColor.withValues(alpha: .18);
        border = kEmberColor;
        fg = kEmberColor;
      } else if (reached.contains(ymd) || bridged.contains(ymd)) {
        fill = const Color(0xFF2FB3A3).withValues(alpha: .55);
        border = Colors.transparent;
        fg = kBBg;
      } else {
        fill = kBRaised;
        border = Colors.transparent;
        fg = kBText3;
      }
      return Expanded(
        child: Container(
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(7), border: Border.all(color: border, width: 1.5)),
          child: Text(isLost ? '🔥' : label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ),
      );
    }

    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 92, child: Text(k, style: const TextStyle(fontSize: 13, color: kBText3))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13, color: kBText))),
          ]),
        );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        FicheHeader(title: 'Rallumer ${routine.name} ?', chip: 'série cassée hier', chipColor: kEmberColor, kpi: 'Série de ${lost.length} j tenue jusqu’à avant-hier'),
        const SizedBox(height: 14),
        Row(children: [for (var i = 5; i >= 0; i--) cell(ymdShift(today, -i))]),
        const SizedBox(height: 4),
        Row(children: [
          Text('${lost.length} jour${lost.length > 1 ? 's' : ''} tenu${lost.length > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11, color: kBText4)),
          const Spacer(),
          const Text('hier comblé · aujourd’hui à faire', style: TextStyle(fontSize: 11, color: kBText4)),
        ]),
        const SizedBox(height: 14),
        kv('Prix', '1 braise · réserve ${ledger.available} → ${ledger.available - 1}'),
        kv('Condition', doneToday ? '${routine.name} est déjà atteinte aujourd’hui' : 'atteindre ${routine.name} aujourd’hui (0 / $target)'),
        kv('Résultat', 'série de $after j ce soir${nextTier == null ? '' : ' · palier $nextTier j dans ${nextTier - after} j'}'),
        kv('Trace', 'hier marqué d’une braise dans l’historique de la série'),
        const SizedBox(height: 14),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kEmberColor, foregroundColor: const Color(0xFF1F0B02), shape: const StadiumBorder()),
            onPressed: () async {
              await logic.rekindle(routine.id);
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            icon: const Icon(Icons.local_fire_department_rounded),
            label: const Text('Rallumer avec une braise', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          doneToday
              ? 'La braise est brûlée tout de suite : la routine est déjà faite.'
              : 'Si ${routine.name} n’est pas atteinte avant la bascule, la braise revient dans la réserve.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: kBText3),
        ),
      ],
    );
  });
  return ok == true;
}

extension LostSeriesYmd on LostSeries {
  String lostYmdOf(String todayYmd) => ymdShift(todayYmd, -1);
}

/// Bloc « Braises » de « Badges en jeu » : réserve, prochaine braise, historique.
class EmberLedgerPanel extends StatelessWidget {
  final EmberLedger ledger;
  final Map<String, String> names;
  const EmberLedgerPanel({super.key, required this.ledger, this.names = const {}});

  @override
  Widget build(BuildContext context) {
    final events = ledger.history.where((e) => e.kind != EmberEventKind.capped).take(5).toList();
    String date(String ymd) {
      const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
      final d = DateTime.parse(ymd);
      return '${d.day} ${months[d.month - 1]}';
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(14), border: Border.all(color: kEmberColor.withValues(alpha: .3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('BRAISES', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
          const InfoDot(kRuleEmbers, size: 16),
          const Spacer(),
          Text('${ledger.available} sur $kEmberCap', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kEmberColor)),
        ]),
        const SizedBox(height: 8),
        EmberDots(stock: ledger.available, label: ledger.available >= kEmberCap ? 'réserve pleine' : 'prochaine : une journée parfaite'),
        if (events.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                SizedBox(
                  width: 28,
                  child: Text(e.kind == EmberEventKind.earned ? '+1' : '−1', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kEmberColor)),
                ),
                Expanded(
                  child: Text(
                    e.kind == EmberEventKind.earned ? (e.week ? 'Semaine tenue' : 'Journée parfaite') : '${names[e.activityId] ?? 'Série'} rallumée',
                    style: const TextStyle(fontSize: 13, color: kBText),
                  ),
                ),
                Text(date(e.ymd), style: const TextStyle(fontSize: 12, color: kBText3)),
              ]),
            ),
        ],
      ]),
    );
  }
}
