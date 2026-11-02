import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/finance_sheet.dart' show kMoneyAccent, kMoneyInk;
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;

/// « Le point de la semaine » (maquette validée 2026-11-02, Finances lot 3) :
/// on recopie le solde du compte, l'app calcule ce qu'elle attendait depuis le
/// dernier point et propose de classer l'écart (une dépense oubliée, un fixe
/// passé, un revenu reçu). Le solde recopié devient la base du point suivant.

const _kAmber = Color(0xFFF0B44C);
const _mShort = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

String _dayLabel(String ymd) {
  final d = DateTime.parse(ymd);
  return '${_days[d.weekday - 1]} ${d.day} ${_mShort[d.month - 1]}';
}

/// L'activité-temps « Budget » du domaine Finances (chrono du point), sinon null.
Activity? budgetTimeActivity(AppLogic logic) {
  final acts = logic.state.activities.where((a) => !a.deleted && !a.isHabit).toList();
  return acts.where((a) => isBudgetRoutineName(a.name)).firstOrNull;
}

Future<void> showBalanceCheck(BuildContext context, {required AppLogic logic}) {
  return showFiche<void>(context, builder: (ctx, scroll) => BalanceCheckSheet(logic: logic, scroll: scroll));
}

class BalanceCheckSheet extends StatefulWidget {
  final AppLogic logic;
  final ScrollController? scroll;
  const BalanceCheckSheet({super.key, required this.logic, this.scroll});

  @override
  State<BalanceCheckSheet> createState() => _BalanceCheckSheetState();
}

class _BalanceCheckSheetState extends State<BalanceCheckSheet> {
  final _ctrl = TextEditingController();
  bool _negative = false;
  /// Solde saisi et validé (étape 2), en centimes.
  int? _balance;
  bool _done = false;
  late bool _chrono = false;
  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    _ctrl.dispose();
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  int? get _typed {
    final v = parseEuros(_ctrl.text) ?? (_ctrl.text.trim() == '0' ? 0 : null);
    if (v == null) return null;
    return _negative ? -v : v;
  }

  void _toggleChrono(bool on, Activity a) {
    setState(() => _chrono = on);
    if (on) {
      if (logic.runningActivity()?.id != a.id) logic.start(a.id);
    } else if (logic.runningActivity()?.id == a.id) {
      logic.stopActive();
    }
  }

  Future<void> _record(String message) async {
    final b = _balance;
    if (b == null) return;
    await logic.recordBalance(b);
    if (!mounted) return;
    setState(() => _done = true);
    ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  Future<void> _forgotten(int amount) async {
    final f = logic.finances;
    final env = f.envelopeOf('imprevus')?.id ?? f.envelopes.last.id;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('${euros(amount)} oubliés · dans quelle enveloppe ?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          for (final e in f.envelopes)
            ListTile(
              title: Text(e.name),
              trailing: e.id == env ? const Icon(Icons.check, color: kMoneyAccent) : null,
              onTap: () => Navigator.pop(ctx, e.id),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    await logic.logExpense(amount: amount, envelopeId: picked, note: 'oubli · point du ${_dayLabel(logic.livedTodayYmd)}');
    await _record('✓ ${euros(amount)} notés · le point est fait');
  }

  Future<void> _recurringPaid(Recurring r) async {
    await logic.setPaid(r.id, r.amount);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final f = logic.finances;
    final today = logic.livedTodayYmd;
    final check = balanceCheck(f, today);
    final budget = budgetTimeActivity(logic);
    final running = budget != null && logic.runningActivity()?.id == budget.id;

    final head = [
      Row(children: [
        const Expanded(child: Text('Le point de la semaine', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
        if (budget != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Chrono ${budget.name}', style: TextStyle(fontSize: 12, color: mute)),
            Switch(value: running || _chrono, activeColor: kMoneyAccent, onChanged: (v) => _toggleChrono(v, budget)),
          ]),
      ]),
    ];

    if (_done) {
      return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        ...head,
        const SizedBox(height: 24),
        const Center(child: Text('✓', style: TextStyle(fontSize: 44, color: kMoneyAccent, fontWeight: FontWeight.w900))),
        const SizedBox(height: 8),
        Center(child: Text('Solde posé : ${euros(_balance!)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        const SizedBox(height: 4),
        Center(child: Text('Le prochain point partira de là.', style: TextStyle(fontSize: 13.5, color: mute))),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kMoneyAccent, foregroundColor: kMoneyInk, minimumSize: const Size.fromHeight(48)),
          onPressed: () {
            if (running) logic.stopActive();
            Navigator.of(context).pop();
          },
          child: Text(running ? 'Terminer · arrêter le chrono' : 'Terminer', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]);
    }

    if (_balance == null) {
      final v = _typed;
      return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        ...head,
        const SizedBox(height: 6),
        const Text('Ton compte dit ?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          check.lastYmd == null
              ? 'Ouvre ton appli bancaire et recopie le solde. Ce premier point sert de base : la semaine prochaine, l’app te dira si rien n’a été oublié.'
              : 'Ouvre ton appli bancaire et recopie le solde. Dernier point : ${_dayLabel(check.lastYmd!)} (${euros(check.lastBalance!)}).',
          style: TextStyle(fontSize: 13.5, color: mute, height: 1.4),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          autofocus: true,
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          decoration: InputDecoration(
            prefixText: _negative ? '− ' : null,
            suffixText: '€',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kMoneyAccent, width: 1.5)),
          ),
          onChanged: (_) => setState(() {}),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('À découvert (solde négatif)'),
          value: _negative,
          onChanged: (x) => setState(() => _negative = x ?? false),
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kMoneyAccent, foregroundColor: kMoneyInk, minimumSize: const Size.fromHeight(48)),
          onPressed: v == null
              ? null
              : () {
                  setState(() => _balance = v);
                  if (check.lastYmd == null) _record('✓ Premier point posé · on comparera la semaine prochaine');
                },
          child: const Text('Comparer', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]);
    }

    // Étape 2 : l'écart.
    final b = _balance!;
    final expected = check.expected!;
    final gap = b - expected;
    final month = f.paid[monthOf(today)] ?? const {};
    final openFixed = [for (final r in f.recurring) if (!r.income && !month.containsKey(r.id)) r];
    final openIncome = [for (final r in f.recurring) if (r.income && !month.containsKey(r.id)) r];
    Widget line(String l, String r, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(l, style: TextStyle(fontSize: 13.5, color: color))),
            Text(r, style: TextStyle(fontSize: 13.5, color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ]),
        );
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      ...head,
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          line('Point du ${_dayLabel(check.lastYmd!)}', euros(check.lastBalance!)),
          if (check.spentSince > 0) line('Dépenses notées', euros(-check.spentSince)),
          if (check.paidOutSince > 0) line('Fixes passés', euros(-check.paidOutSince)),
          if (check.paidInSince > 0) line('Revenus reçus', euros(check.paidInSince, sign: true)),
          line('D’après l’app', euros(expected), bold: true),
          line('Ton compte', euros(b), bold: true),
          line('Écart', euros(gap, sign: true), bold: true, color: gapIsZero(gap) ? kMoneyAccent : _kAmber),
        ]),
      ),
      const SizedBox(height: 12),
      if (gapIsZero(gap)) ...[
        const Text('✓ Tout est noté.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kMoneyAccent)),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kMoneyAccent, foregroundColor: kMoneyInk, minimumSize: const Size.fromHeight(48)),
          onPressed: () => _record('✓ Le point est fait'),
          child: const Text('Poser ce solde', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ] else if (gap < 0) ...[
        Text('${euros(-gap)} sont sortis sans être notés : une dépense oubliée, ou un fixe passé ?', style: const TextStyle(fontSize: 14, height: 1.4)),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kMoneyAccent, foregroundColor: kMoneyInk, minimumSize: const Size.fromHeight(48)),
          onPressed: () => _forgotten(-gap),
          child: Text('Noter ${euros(-gap)} oubliés', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        if (openFixed.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text('UN FIXE PAS ENCORE COCHÉ ?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute)),
          ),
          for (final r in openFixed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(r.name),
              subtitle: Text('${euros(r.amount)} · le ${r.day}'),
              trailing: TextButton(onPressed: () => _recurringPaid(r), child: const Text('C’est lui')),
            ),
        ],
      ] else ...[
        Text('${euros(gap)} de plus que prévu : un revenu pas coché, ou un remboursement ?', style: const TextStyle(fontSize: 14, height: 1.4)),
        if (openIncome.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text('UN REVENU PAS ENCORE COCHÉ ?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute)),
          ),
          for (final r in openIncome)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(r.name),
              subtitle: Text('${euros(r.amount)} · le ${r.day}'),
              trailing: TextButton(onPressed: () => _recurringPaid(r), child: const Text('C’est lui')),
            ),
        ],
      ],
      if (!gapIsZero(gap)) ...[
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          onPressed: () => _record('✓ Solde posé · l’écart reste comme il est'),
          child: const Text('Garder ce solde tel quel'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Je vérifierai plus tard')),
      ],
    ]);
  }
}
