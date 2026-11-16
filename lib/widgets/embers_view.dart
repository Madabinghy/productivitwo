import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/embers.dart';
import 'package:productivitwo_v1/utils/hard_days.dart' show kHardDayCooldownDays, nextHardDayAfter;
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';

/// Section « PERDU HIER » (refonte 2026-11-06, maquette « Journée difficile ») : UNE carte au lieu d'une ligne par
/// série — « Hier, n séries se sont cassées », la journée difficile en premier quand elle est possible, puis Le minimum. Hier déclarée difficile : « Hier gelée · n séries
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
  AppLogic get logic => widget.logic;

  @override
  Widget build(BuildContext context) {
    if (logic.yesterdayIsHard) return _hardCard(context);
    final lostAll = logic.lostSeriesYesterday();
    if (lostAll.isEmpty) return const SizedBox.shrink();
    // Sans braises (2026-11-07, code retiré le 2026-11-16) : la journée difficile est le recours, dès une série cassée.
    final canHard = logic.canDeclareYesterdayHard;
    final canMin = widget.onMinimum != null && logic.minimumNow == null && lostAll.length >= 2;
    if (!canHard && !canMin) return const SizedBox.shrink();
    final last = logic.lastHardDay;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: kBSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kHardDayColor.withValues(alpha: .45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('PERDU HIER', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kHardDayColor)),
          const InfoDot(kRuleHardDay, size: 16),
          const Spacer(),
          const Text('jusqu’à ce soir', style: TextStyle(fontSize: 11, color: kBText4)),
        ]),
        const SizedBox(height: 4),
        Text('Hier, ${lostAll.length} série${lostAll.length > 1 ? 's se sont cassées' : ' s’est cassée'}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kBText)),
        const SizedBox(height: 4),
        if (canHard) ...[
          const Text('Ça arrive. Si hier a vraiment été une journée difficile, tu peux le geler.',
              style: TextStyle(fontSize: 13, color: kBText3)),
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
      ]),
    );
  }

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

  Future<void> _openHardDay(BuildContext context, List<LostSeries> lost) async {
    final ok = await showHardDaySheet(context, logic: logic, lost: lost);
    if (ok == true) widget.onChanged();
  }

  Future<void> _cancelHard(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la journée difficile ?'),
        content: const Text('Les séries d’hier redeviennent cassées.'),
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
          Text('Hier ne compte pas pour Journée parfaite, Métronome ni Montre suisse.',
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
          child: Text('Non, pas cette fois', style: TextStyle(decoration: TextDecoration.underline)),
        ),
      ],
    );
  });
}
