import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/utils/receipts.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;

/// Fiche d'un ticket de caisse lu par Claude (maquette validée 2026-11-03
/// « Où va mon argent ») : le ticket recomposé (magasin, lieu, jour, heure,
/// numéro, lignes imprimées, total), puis les articles avec leur domaine et
/// leur rayon, et la répartition. Tap sur un article = changer son domaine.

const _kPaper = Color(0xFFF1EFE8);
const _kPaperInk = Color(0xFF1D1F1C);
const _kNoDomain = Color(0xFF8F9B96);
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String _eur(int cents) {
  final neg = cents < 0;
  final c = cents.abs();
  return '${neg ? '−' : ''}${c ~/ 100},${(c % 100).toString().padLeft(2, '0')} €';
}

String _num(int cents) => '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

String receiptDayLabel(String ymd) {
  final p = ymd.split('-');
  if (p.length != 3) return ymd;
  final m = int.tryParse(p[1]) ?? 1;
  return '${int.tryParse(p[2]) ?? p[2]} ${_months[(m - 1).clamp(0, 11)]}';
}

Future<void> showReceiptSheet(BuildContext context, {required AppLogic logic, required String receiptId}) {
  return showFiche<void>(context, builder: (ctx, scroll) => ReceiptSheet(logic: logic, receiptId: receiptId, scroll: scroll));
}

class ReceiptSheet extends StatefulWidget {
  final AppLogic logic;
  final String receiptId;
  final ScrollController? scroll;
  const ReceiptSheet({super.key, required this.logic, required this.receiptId, this.scroll});

  @override
  State<ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<ReceiptSheet> {
  AppLogic get logic => widget.logic;

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

  Color _dc(String? id) => id == null ? _kNoDomain : (domainColor(id, logic.state.activeDomains) ?? _kNoDomain);
  String _dn(String? id) => id == null ? 'Sans domaine' : (logic.state.domains.where((d) => d.id == id).firstOrNull?.name ?? 'Domaine retiré');

  Future<void> _pickDomain(Receipt r, int i) async {
    final cs = Theme.of(context).colorScheme;
    final cur = r.lines[i].domainId;
    final picked = await showModalBottomSheet<(String?,)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), children: [
          Text('« ${r.lines[i].name} » pour quel domaine ?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          for (final d in logic.state.activeDomains)
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 6, backgroundColor: _dc(d.id)),
              title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: d.id == cur ? Icon(Icons.check_rounded, color: cs.primary) : null,
              onTap: () => Navigator.pop(ctx, (d.id,)),
            ),
          ListTile(
            dense: true,
            leading: const CircleAvatar(radius: 6, backgroundColor: _kNoDomain),
            title: const Text('Sans domaine'),
            trailing: cur == null ? Icon(Icons.check_rounded, color: cs.primary) : null,
            onTap: () => Navigator.pop(ctx, (null,)),
          ),
        ]),
      ),
    );
    if (picked == null || picked.$1 == cur) return;
    await logic.setReceiptLineDomain(r.id, i, picked.$1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final r = logic.finances.receipts[widget.receiptId];
    if (r == null) {
      return ListView(controller: widget.scroll, padding: const EdgeInsets.all(24), children: [Text('Ce ticket n\'existe plus.', style: TextStyle(color: mute))]);
    }
    final parts = receiptParts(r);
    const mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Courier', 'Menlo'], fontSize: 12.5, color: _kPaperInk, height: 1.35);
    Widget paperRow(String a, String b, {bool bold = false}) => Row(children: [
          Expanded(child: Text(a, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold ? mono.copyWith(fontWeight: FontWeight.w800) : mono)),
          const SizedBox(width: 8),
          Text(b, style: bold ? mono.copyWith(fontWeight: FontWeight.w800) : mono),
        ]);
    Widget dash() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('-' * 60, maxLines: 1, overflow: TextOverflow.clip, style: mono.copyWith(color: const Color(0xFF9A9A92))),
        );
    final p = r.ymd.split('-');
    final printedDay = p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : r.ymd;
    Text section(String t) => Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: mute));

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Row(children: [
        Expanded(child: Text(r.store ?? 'Ticket', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .08), borderRadius: BorderRadius.circular(20)),
          child: Text('lu par Claude', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: mute)),
        ),
      ]),
      Text('${receiptDayLabel(r.ymd)}${r.time != null ? ' à ${r.time}' : ''} · ${_eur(r.total)}', style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 12),
      Container(
        key: const Key('receipt-paper'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: const BoxDecoration(
          color: _kPaper,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text([if (r.store != null) r.store!.toUpperCase(), if (r.place != null) r.place!.toUpperCase()].join(' · '),
              textAlign: TextAlign.center, style: mono.copyWith(fontWeight: FontWeight.w800, letterSpacing: .6)),
          const SizedBox(height: 2),
          paperRow('$printedDay${r.time != null ? ' ${r.time}' : ''}', r.ref != null ? 'Ticket ${r.ref}' : ''),
          dash(),
          for (final l in r.lines) paperRow(l.label, _num(l.price)),
          dash(),
          paperRow('TOTAL', _num(r.total), bold: true),
        ]),
      ),
      const SizedBox(height: 18),
      section('LES ARTICLES'),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .04), borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(children: [
          for (var i = 0; i < r.lines.length; i++)
            InkWell(
              onTap: () => _pickDomain(r, i),
              child: Container(
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: cs.onSurface.withValues(alpha: .06)))),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.lines[i].name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                      Row(children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: _dc(r.lines[i].domainId), shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text([_dn(r.lines[i].domainId), if (r.lines[i].aisle != null) r.lines[i].aisle!].join(' · '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: mute)),
                        ),
                      ]),
                    ]),
                  ),
                  Text(_eur(r.lines[i].price), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Text('Touche un article pour changer son domaine : la répartition suit.', style: TextStyle(fontSize: 11.5, color: mute)),
      const SizedBox(height: 16),
      section('RÉPARTI'),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: 10,
          child: Row(children: [
            for (final part in parts)
              if (part.amount > 0) Expanded(flex: part.amount, child: Container(color: _dc(part.domainId), margin: const EdgeInsets.only(right: 2))),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      for (final part in parts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _dc(part.domainId), borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(child: Text(_dn(part.domainId), style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(_eur(part.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        ),
    ]);
  }
}
