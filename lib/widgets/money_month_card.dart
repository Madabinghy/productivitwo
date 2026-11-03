import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/utils/month_spend.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/finance_sheet.dart' show kMoneyAccent, showExpenseSheet;
import 'package:productivitwo_v1/widgets/receipt_sheet.dart' show receiptDayLabel, showReceiptSheet;

/// « Où va mon argent » (maquette validée 2026-11-03, lot 2) : le mois en un
/// coup d'œil, par domaine, enveloppe ou magasin ; tap sur une ligne = la page
/// de la catégorie (détail, tickets et dépenses) ; tap sur un ticket = sa fiche.

const _kPalette = [
  Color(0xFF3987E5), Color(0xFF199E70), Color(0xFFD95926), Color(0xFF9085E9),
  Color(0xFFC98500), Color(0xFFD55181), Color(0xFF5FB8C9), Color(0xFF8DB04A),
];
const _kGrey = Color(0xFF6B7772);

Map<String, String> _domainNames(AppLogic logic) => {for (final d in logic.state.domains) d.id: d.name};

Color _catColor(AppLogic logic, MonthBy by, SpendCategory c, int index) {
  if (c.id == kFixedKey || (by == MonthBy.domain && c.id.isEmpty)) return _kGrey;
  if (by == MonthBy.domain) return domainColor(c.id, logic.state.activeDomains) ?? _kPalette[index % _kPalette.length];
  return _kPalette[index % _kPalette.length];
}

class MoneyMonthCard extends StatefulWidget {
  final AppLogic logic;
  final String todayYmd;
  const MoneyMonthCard({super.key, required this.logic, required this.todayYmd});

  @override
  State<MoneyMonthCard> createState() => _MoneyMonthCardState();
}

class _MoneyMonthCardState extends State<MoneyMonthCard> {
  late String _month = monthOf(widget.todayYmd);
  MonthBy _by = MonthBy.domain;

  @override
  Widget build(BuildContext context) {
    final logic = widget.logic;
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final f = logic.finances;
    final current = monthOf(widget.todayYmd);
    final items = monthSpends(f, _month, widget.todayYmd);
    final total = items.fold<int>(0, (s, i) => s + i.amount);
    final names = _domainNames(logic);
    final cats = monthCategories(items, _by, f, domainNames: names);
    final tickets = items.where((i) => i.receipt != null).toList();
    final ticketCount = tickets.map((i) => i.receipt!.id).toSet().length;
    final ticketSum = tickets.fold<int>(0, (s, i) => s + i.amount);
    final m = monthName(_month);

    return Container(
      key: const Key('money-month'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('OÙ VA MON ARGENT · ${m.toUpperCase()}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: kMoneyAccent)),
          ),
          IconButton(
            tooltip: 'Mois d\'avant',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => setState(() => _month = shiftMonth(_month, -1)),
          ),
          IconButton(
            tooltip: 'Mois d\'après',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _month.compareTo(current) >= 0 ? null : () => setState(() => _month = shiftMonth(_month, 1)),
          ),
        ]),
        Text(euros(total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
        Text(
          ticketCount == 0
              ? (total == 0 ? 'Rien de dépensé en $m.' : 'dépensé en $m')
              : 'dont ${euros(ticketSum)} en $ticketCount ticket${ticketCount > 1 ? 's' : ''} lu${ticketCount > 1 ? 's' : ''} par Claude',
          style: TextStyle(fontSize: 12.5, color: mute),
        ),
        const SizedBox(height: 10),
        SegmentedButton<MonthBy>(
          segments: const [
            ButtonSegment(value: MonthBy.domain, label: Text('Domaines')),
            ButtonSegment(value: MonthBy.envelope, label: Text('Enveloppes')),
            ButtonSegment(value: MonthBy.store, label: Text('Magasins')),
          ],
          selected: {_by},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          onSelectionChanged: (v) => setState(() => _by = v.first),
        ),
        if (cats.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(children: [
                for (var i = 0; i < cats.length; i++)
                  if (cats[i].total > 0)
                    Expanded(flex: cats[i].total, child: Container(color: _catColor(logic, _by, cats[i], i), margin: const EdgeInsets.only(right: 2))),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < cats.length; i++)
            InkWell(
              onTap: () => showSpendCategorySheet(context, logic: logic, month: _month, todayYmd: widget.todayYmd, by: _by, categoryId: cats[i].id),
              child: Container(
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: cs.onSurface.withValues(alpha: .06)))),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: _catColor(logic, _by, cats[i], i), borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cats[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                      Text(categoryHint(cats[i], _by, f, domainNames: names),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: mute)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(euros(cats[i].total), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                    Text('${total == 0 ? 0 : (cats[i].total * 100 / total).round()} %', style: TextStyle(fontSize: 11.5, color: mute)),
                  ]),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}

/// La page d'une catégorie du mois : son détail par un autre regroupement,
/// puis ses tickets et dépenses (tap = la fiche du ticket ou la dépense).
Future<void> showSpendCategorySheet(BuildContext context,
    {required AppLogic logic, required String month, required String todayYmd, required MonthBy by, required String categoryId}) {
  return showFiche<void>(
    context,
    builder: (ctx, scroll) => _CategoryPage(logic: logic, month: month, todayYmd: todayYmd, by: by, categoryId: categoryId, scroll: scroll),
  );
}

class _CategoryPage extends StatefulWidget {
  final AppLogic logic;
  final String month;
  final String todayYmd;
  final MonthBy by;
  final String categoryId;
  final ScrollController? scroll;
  const _CategoryPage({required this.logic, required this.month, required this.todayYmd, required this.by, required this.categoryId, this.scroll});

  @override
  State<_CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<_CategoryPage> {
  AppLogic get logic => widget.logic;
  String get month => widget.month;
  String get todayYmd => widget.todayYmd;
  MonthBy get by => widget.by;
  String get categoryId => widget.categoryId;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final f = logic.finances;
    final names = _domainNames(logic);
    final items = monthSpends(f, month, todayYmd).where((i) => spendKey(i, by) == categoryId).toList();
    final cat = SpendCategory(
      id: categoryId,
      name: monthCategories(items, by, f, domainNames: names).firstOrNull?.name ?? '',
      total: items.fold<int>(0, (s, i) => s + i.amount),
      items: items,
    );
    final subBy = by == MonthBy.domain ? MonthBy.envelope : MonthBy.domain;
    final sub = breakdown(cat, by, f, domainNames: names);
    Text section(String t) => Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: mute));

    // « Où, ce mois » : les magasins de la catégorie (hors vue magasin).
    final stores = by == MonthBy.store ? const <SpendCategory>[] : monthCategories(items.where((i) => !i.fixed).toList(), MonthBy.store, f);

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Row(children: [
        Expanded(child: Text(cat.name.isEmpty ? 'Catégorie' : cat.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: kMoneyAccent.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
          child: Text('${euros(cat.total)} · ${monthName(month)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kMoneyAccent)),
        ),
      ]),
      if (items.isEmpty)
        Padding(padding: const EdgeInsets.only(top: 24), child: Text('Plus rien dans cette catégorie ce mois-ci.', style: TextStyle(color: mute))),
      if (sub.length > 1 || (sub.length == 1 && categoryId != kFixedKey)) ...[
        const SizedBox(height: 16),
        section(subBy == MonthBy.envelope ? 'PAR ENVELOPPE' : 'PAR DOMAINE'),
        const SizedBox(height: 6),
        for (var i = 0; i < sub.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _catColor(logic, subBy, sub[i], i), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(child: Text(sub[i].name, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(euros(sub[i].total), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: cat.total == 0 ? 0 : sub[i].total / cat.total,
                  minHeight: 5,
                  color: _catColor(logic, subBy, sub[i], i),
                  backgroundColor: cs.onSurface.withValues(alpha: .08),
                ),
              ),
            ]),
          ),
      ],
      if (items.isNotEmpty) ...[
        const SizedBox(height: 16),
        section(categoryId == kFixedKey ? 'LES FIXES' : 'TICKETS ET DÉPENSES'),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .04), borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            for (var i = 0; i < items.length; i++) _itemRow(context, cs, mute, f, items[i], first: i == 0),
          ]),
        ),
      ],
      if (stores.length > 1) ...[
        const SizedBox(height: 16),
        section('OÙ, CE MOIS'),
        const SizedBox(height: 6),
        Text(
          stores.map((s) {
            final n = s.items.map((i) => i.receipt?.id ?? i.id).toSet().length;
            return '${s.name}${n > 1 ? ' $n fois' : ''} · ${euros(s.total)}';
          }).join('  ·  '),
          style: TextStyle(fontSize: 13, color: mute, height: 1.4),
        ),
      ],
    ]);
  }

  Widget _itemRow(BuildContext context, ColorScheme cs, Color mute, Finances f, SpendItem i, {required bool first}) {
    final r = i.receipt;
    final title = i.fixed ? i.label : i.store;
    final meta = [
      receiptDayLabel(i.ymd),
      if (r?.ref != null) 'ticket ${r!.ref}',
      if (r != null) '${r.lines.length} article${r.lines.length > 1 ? 's' : ''}',
      if (r == null && !i.fixed) ((i.expense?.items.isNotEmpty ?? false) ? i.expense!.items.take(3).join(', ') : 'noté à la main'),
      if (i.fixed) 'fixe passé',
    ].join(' · ');
    final partial = r != null && r.total > i.amount;
    final letter = i.fixed ? '↻' : (r == null ? '✎' : (title.isEmpty ? '?' : title.characters.first.toUpperCase()));
    return InkWell(
      onTap: i.fixed
          ? null
          : () => r != null ? showReceiptSheet(context, logic: logic, receiptId: r.id) : showExpenseSheet(context, logic: logic, edit: i.expense),
      child: Container(
        decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: cs.onSurface.withValues(alpha: .06)))),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)),
            child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: mute)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(euros(i.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            if (partial) Text('sur ${euros(r.total)}', style: TextStyle(fontSize: 11, color: mute)),
          ]),
        ]),
      ),
    );
  }
}
