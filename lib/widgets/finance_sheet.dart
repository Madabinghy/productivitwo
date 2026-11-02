import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;

/// Feuille « Finances » (maquette validée 2026-11-02 « Suivi des finances »,
/// lot 2) : reste à vivre du mois, la question du jour (« + Dépense » ou
/// « Rien dépensé »), les enveloppes face à l'attendu, les fixes à cocher, la
/// grille des 90 jours suivis. 100 % manuel.

const kMoneyAccent = Color(0xFF5FD4C4);
const kMoneyInk = Color(0xFF08140E);
const _kAmber = Color(0xFFF0B44C);
const _kRed = Color(0xFFF07A6A);

const kRuleFinances = GameRule('Les finances', [
  RuleCard('📅', 'Un jour suivi', 'Une dépense notée, ou « Rien dépensé ». C’est tout.'),
  RuleCard('🔁', 'Ça compte tout seul', 'La routine « Suivre mon budget » prend son +1 du jour, sans rien cocher d’autre.'),
  RuleCard('⏪', 'Hier se rattrape', 'Une dépense oubliée se note pour hier, jamais plus loin : on ne réécrit pas la semaine.'),
  RuleCard('✉️', 'Les enveloppes', 'Un plafond par mois ; le trait blanc dit où tu devrais en être aujourd’hui. Ambre = tu dépenses plus vite que le mois.'),
]);

const _months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _mShort = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _dayLabel(String ymd) {
  final d = DateTime.parse(ymd);
  return '${_days[d.weekday - 1]} ${d.day} ${_mShort[d.month - 1]}';
}

Future<void> showFinanceSheet(BuildContext context, {required AppLogic logic}) {
  return showFiche<void>(context, builder: (ctx, scroll) => FinanceSheet(logic: logic, scroll: scroll));
}

class FinanceSheet extends StatefulWidget {
  final AppLogic logic;
  final ScrollController? scroll;
  const FinanceSheet({super.key, required this.logic, this.scroll});

  @override
  State<FinanceSheet> createState() => _FinanceSheetState();
}

class _FinanceSheetState extends State<FinanceSheet> {
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

  Future<void> _nothing(String ymd) async {
    final first = !isTracked(logic.finances, ymd);
    await logic.setNothingSpent(ymd, true);
    if (!mounted || !first) return;
    _trackedSnack(context, logic, ymd);
  }

  Future<void> _removeExpense(Expense x) async {
    await logic.removeExpense(x.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
      content: Text('${euros(x.amount)} retirés'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () => logic.logExpense(amount: x.amount, envelopeId: x.envelopeId, note: x.note, ymd: x.ymd),
      ),
    ));
  }

  Future<void> _editEnvelope(Envelope e) async {
    final r = await _askAmount(context, title: 'Plafond · ${e.name}', hint: 'par mois · vide = pas de plafond', initial: e.monthly, allowEmpty: true);
    if (r == null) return;
    await logic.saveEnvelopes([for (final x in logic.finances.envelopes) x.id == e.id ? Envelope(id: x.id, name: x.name, monthly: r) : x]);
  }

  Future<void> _togglePaid(Recurring r, bool paid) async {
    if (paid) {
      await logic.setPaid(r.id, null);
      return;
    }
    final amount = await _askAmount(context, title: r.income ? '${r.name} · reçu' : '${r.name} · passé', hint: 'montant réel', initial: r.amount);
    if (amount == null || amount <= 0) return;
    await logic.setPaid(r.id, amount);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final f = logic.finances;
    final today = logic.livedTodayYmd;
    final yesterday = prevYmd(today);
    final m = monthSummary(f, today);
    final streak = trackingStreak(f, today);
    final todayList = f.expenses.values.where((x) => x.ymd == today).toList();
    final nothingToday = f.nothing.contains(today);
    final yesterdayTracked = isTracked(f, yesterday);
    final paidNow = f.paid[m.month] ?? const {};
    final monthName = _months[int.parse(m.month.substring(5)) - 1];

    Widget title(String t, [String? right]) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Row(children: [
            Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
            if (right != null) Text(right, style: TextStyle(fontSize: 11.5, color: mute)),
          ]),
        );
    final box = BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(14));

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Row(children: [
        const Expanded(child: Text('Finances', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
        if (streak > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: kMoneyAccent.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
            child: Text('🔥 $streak jour${streak > 1 ? 's' : ''} suivi${streak > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kMoneyAccent)),
          ),
        const SizedBox(width: 6),
        const InfoDot(kRuleFinances),
      ]),
      const SizedBox(height: 10),
      // Reste à vivre.
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF0F2B27), Color(0xFF0B1D18)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kMoneyAccent.withValues(alpha: .25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('RESTE À VIVRE · ${monthName.toUpperCase()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: kMoneyAccent)),
          const SizedBox(height: 2),
          if (m.hasIncome) ...[
            Text(euros(m.remaining), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: m.remaining < 0 ? _kRed : Colors.white)),
            Text(
              m.remaining <= 0
                  ? 'revenus − fixes − dépenses · le mois est dépassé'
                  : 'sur ${m.daysLeft} jour${m.daysLeft > 1 ? 's' : ''} · ≈ ${euros(m.perDay)} par jour',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFB9CFC4)),
            ),
          ] else ...[
            Text('${euros(m.spent)} dépensés', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
            const Text('pose tes revenus et tes fixes pour voir ce qu’il te reste', style: TextStyle(fontSize: 12.5, color: Color(0xFFB9CFC4))),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => showRecurringSheet(context, logic: logic), child: const Text('Revenus et fixes ›')),
            ),
          ],
        ]),
      ),
      title('AUJOURD’HUI', _dayLabel(today)),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: box,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (todayList.isEmpty && !nothingToday) const Text('Rien noté aujourd’hui.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          if (nothingToday)
            Row(children: [
              const Expanded(child: Text('✓ Rien dépensé aujourd’hui', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kMoneyAccent))),
              TextButton(onPressed: () => logic.setNothingSpent(today, false), child: const Text('Retirer')),
            ]),
          for (final x in todayList) _expenseRow(cs, mute, f, x),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kMoneyAccent, foregroundColor: kMoneyInk, minimumSize: const Size.fromHeight(46)),
                onPressed: () => showExpenseSheet(context, logic: logic),
                child: const Text('+ Dépense', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            if (todayList.isEmpty && !nothingToday) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  onPressed: () => _nothing(today),
                  child: const Text('✓ Rien dépensé'),
                ),
              ),
            ],
          ]),
          if (!yesterdayTracked) ...[
            const SizedBox(height: 8),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
              Text('Hier n’est pas suivi :', style: TextStyle(fontSize: 12.5, color: _kAmber.withValues(alpha: .9))),
              TextButton(onPressed: () => showExpenseSheet(context, logic: logic, ymd: yesterday), child: const Text('Dépense d’hier')),
              TextButton(onPressed: () => _nothing(yesterday), child: const Text('Rien hier')),
            ]),
          ],
        ]),
      ),
      title('ENVELOPPES DU MOIS', 'trait = attendu à ce jour'),
      for (final e in m.envelopes) _envelopeRow(cs, mute, e),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: () => showEnvelopesSheet(context, logic: logic), child: const Text('Gérer les enveloppes ›')),
      ),
      title('LES FIXES', m.fixedCount == 0 ? null : '${m.fixedPaidCount} / ${m.fixedCount} passés'),
      if (f.recurring.isEmpty)
        Text('Loyer, abonnements, salaire : pose-les une fois, coche-les chaque mois.', style: TextStyle(fontSize: 13, color: mute)),
      for (final r in [...f.recurring]..sort((a, b) => a.income == b.income ? a.day.compareTo(b.day) : (a.income ? -1 : 1)))
        _recurringRow(cs, mute, r, paidNow[r.id], today),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: () => showRecurringSheet(context, logic: logic), child: Text(f.recurring.isEmpty ? '+ Revenus et fixes' : 'Gérer les fixes ›')),
      ),
      title('90 JOURS SUIVIS', '${_last90(f, today).where((x) => x > 0).length} / 90'),
      _grid(cs, f, today),
    ]);
  }

  Widget _expenseRow(ColorScheme cs, Color mute, Finances f, Expense x) {
    final env = f.envelopeOf(x.envelopeId)?.name ?? 'Autre';
    return Dismissible(
      key: ValueKey('exp-${x.id}'),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 12), child: const Icon(Icons.delete_outline, color: _kRed)),
      onDismissed: (_) => _removeExpense(x),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: env, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (x.note != null && x.note!.isNotEmpty) TextSpan(text: ' · ${x.note}', style: TextStyle(color: mute)),
            ]), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text(euros(x.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _envelopeRow(ColorScheme cs, Color mute, EnvelopeMonth e) {
    final has = e.envelope.monthly > 0;
    final color = e.over ? _kRed : (e.ahead ? _kAmber : kMoneyAccent);
    final ratio = has ? e.ratio.clamp(0.0, 1.0) : 0.0;
    final mark = has ? (e.expected / e.envelope.monthly).clamp(0.0, 1.0) : null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _editEnvelope(e.envelope),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(e.envelope.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
            Text(has ? '${euros(e.spent)} / ${euros(e.envelope.monthly)}' : (e.spent == 0 ? 'pas de plafond' : euros(e.spent)),
                style: TextStyle(fontSize: 12.5, color: has && (e.ahead || e.over) ? color : mute)),
          ]),
          const SizedBox(height: 5),
          SizedBox(
            height: 11,
            child: LayoutBuilder(builder: (ctx, c) {
              final w = c.maxWidth;
              return Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 2,
                  height: 7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(children: [
                      Positioned.fill(child: ColoredBox(color: cs.onSurface.withValues(alpha: .08))),
                      Positioned(left: 0, top: 0, bottom: 0, width: w * ratio, child: ColoredBox(color: color)),
                    ]),
                  ),
                ),
                if (mark != null)
                  Positioned(
                    left: (w * mark - 1).clamp(0.0, w - 2),
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: DecoratedBox(decoration: BoxDecoration(color: cs.onSurface, borderRadius: BorderRadius.circular(1))),
                  ),
              ]);
            }),
          ),
        ]),
      ),
    );
  }

  Widget _recurringRow(ColorScheme cs, Color mute, Recurring r, Paid? paid, String today) {
    final due = dueYmdOf(r, today);
    final late = paid == null && !r.income && due.compareTo(today) < 0;
    return InkWell(
      onTap: () => _togglePaid(r, paid != null),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: paid != null ? kMoneyAccent : null,
              border: Border.all(color: paid != null ? kMoneyAccent : mute, width: 2),
            ),
            child: paid != null ? const Icon(Icons.check, size: 14, color: kMoneyInk) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${r.income ? '↓ ' : ''}${r.name}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: r.income ? kMoneyAccent : null)),
          ),
          Text(
            '${euros(paid?.amount ?? r.amount)} · ${paid != null ? (r.income ? 'reçu' : 'passé') : (late ? 'pas encore coché' : 'le ${DateTime.parse(due).day}')}',
            style: TextStyle(fontSize: 12, color: late ? _kAmber : mute),
          ),
        ]),
      ),
    );
  }

  /// 90 derniers jours jusqu'à aujourd'hui : 2 = dépense notée, 1 = rien dépensé, 0 = pas suivi.
  List<int> _last90(Finances f, String today) {
    final days = {for (final x in f.expenses.values) x.ymd};
    final t = DateTime.parse(today);
    return [
      for (var i = 89; i >= 0; i--)
        () {
          final y = _ymd(DateTime(t.year, t.month, t.day - i));
          return days.contains(y) ? 2 : (f.nothing.contains(y) ? 1 : 0);
        }(),
    ];
  }

  Widget _grid(ColorScheme cs, Finances f, String today) {
    final cells = _last90(f, today);
    return GridView.count(
      crossAxisCount: 15,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      children: [
        for (final (i, v) in cells.indexed)
          Container(
            decoration: BoxDecoration(
              color: v == 2 ? kMoneyAccent : (v == 1 ? kMoneyAccent.withValues(alpha: .45) : cs.onSurface.withValues(alpha: .07)),
              borderRadius: BorderRadius.circular(3),
              border: i == cells.length - 1 ? Border.all(color: cs.onSurface, width: 1.5) : null,
            ),
          ),
      ],
    );
  }
}

void _trackedSnack(BuildContext context, AppLogic logic, String ymd) {
  final streak = trackingStreak(logic.finances, logic.livedTodayYmd);
  final routine = logic.budgetRoutine;
  ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
    content: Text([
      '✓ Jour suivi',
      if (routine != null) '${routine.name} +1',
      if (streak > 1 && ymd == logic.livedTodayYmd) '🔥 $streak jours',
    ].join(' · ')),
    duration: const Duration(seconds: 3),
  ));
}

/// Montant en euros (boîte de dialogue) ; [allowEmpty] : vide = 0.
Future<int?> _askAmount(BuildContext context, {required String title, String? hint, int initial = 0, bool allowEmpty = false}) {
  final ctrl = TextEditingController(text: initial > 0 ? (initial % 100 == 0 ? '${initial ~/ 100}' : (initial / 100).toStringAsFixed(2).replaceAll('.', ',')) : '');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
        decoration: InputDecoration(suffixText: '€', helperText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final v = parseEuros(ctrl.text);
            if (v == null && !(allowEmpty && ctrl.text.trim().isEmpty)) return;
            Navigator.pop(ctx, v ?? 0);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Saisie d'une dépense en cinq secondes : montant (clavier ouvert), enveloppe
/// (la dernière utilisée en avant), note facultative, aujourd'hui ou hier.
Future<void> showExpenseSheet(BuildContext context, {required AppLogic logic, String? ymd}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _ExpenseEntry(logic: logic, ymd: ymd, host: context),
    ),
  );
}

class _ExpenseEntry extends StatefulWidget {
  final AppLogic logic;
  final String? ymd;
  final BuildContext host;
  const _ExpenseEntry({required this.logic, this.ymd, required this.host});

  @override
  State<_ExpenseEntry> createState() => _ExpenseEntryState();
}

class _ExpenseEntryState extends State<_ExpenseEntry> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _ymd = widget.ymd ?? widget.logic.livedTodayYmd;
  late String _env = _lastEnvelope();

  String _lastEnvelope() {
    final f = widget.logic.finances;
    final list = f.expenses.values.toList()..sort((a, b) => b.ymd.compareTo(a.ymd) != 0 ? b.ymd.compareTo(a.ymd) : b.id.compareTo(a.id));
    for (final x in list) {
      if (f.envelopeOf(x.envelopeId) != null) return x.envelopeId;
    }
    return f.envelopes.first.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseEuros(_amount.text);
    if (v == null) return;
    final logic = widget.logic;
    final first = !isTracked(logic.finances, _ymd);
    final id = await logic.logExpense(amount: v, envelopeId: _env, note: _note.text, ymd: _ymd);
    if (!mounted || id == null) return;
    Navigator.of(context).pop();
    if (first && widget.host.mounted) _trackedSnack(widget.host, logic, _ymd);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final f = widget.logic.finances;
    final today = widget.logic.livedTodayYmd;
    final v = parseEuros(_amount.text);
    final envName = f.envelopeOf(_env)?.name ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Une dépense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        TextField(
          controller: _amount,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
          decoration: InputDecoration(hintText: '0', suffixText: '€', suffixStyle: TextStyle(fontSize: 22, color: mute), border: InputBorder.none),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in f.envelopes)
            ChoiceChip(
              label: Text(e.name),
              selected: e.id == _env,
              selectedColor: kMoneyAccent,
              labelStyle: TextStyle(fontWeight: FontWeight.w700, color: e.id == _env ? kMoneyInk : null),
              onSelected: (_) => setState(() => _env = e.id),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note', hintText: 'facultatif · Lidl, plein…', isDense: true),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: today, label: const Text('Aujourd’hui')),
            ButtonSegment(value: prevYmd(today), label: const Text('Hier')),
          ],
          selected: {_ymd},
          onSelectionChanged: (s) => setState(() => _ymd = s.first),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kMoneyAccent, foregroundColor: kMoneyInk, minimumSize: const Size.fromHeight(50)),
          onPressed: v == null ? null : _save,
          child: Text(v == null ? 'Noter' : 'Noter · ${euros(v)} $envName', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

/// Les enveloppes : nom, plafond, ajouter, retirer.
Future<void> showEnvelopesSheet(BuildContext context, {required AppLogic logic}) {
  return showFiche<void>(context, builder: (ctx, scroll) => _EnvelopesEditor(logic: logic, scroll: scroll));
}

class _EnvelopesEditor extends StatefulWidget {
  final AppLogic logic;
  final ScrollController scroll;
  const _EnvelopesEditor({required this.logic, required this.scroll});

  @override
  State<_EnvelopesEditor> createState() => _EnvelopesEditorState();
}

class _EnvelopesEditorState extends State<_EnvelopesEditor> {
  AppLogic get logic => widget.logic;

  Future<void> _rename(Envelope e) async {
    final name = await _askText(context, 'Renommer', e.name);
    if (name == null || name.isEmpty) return;
    await logic.saveEnvelopes([for (final x in logic.finances.envelopes) x.id == e.id ? Envelope(id: x.id, name: name, monthly: x.monthly) : x]);
    setState(() {});
  }

  Future<void> _add() async {
    final name = await _askText(context, 'Nouvelle enveloppe', '');
    if (name == null || name.isEmpty) return;
    final id = '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    await logic.saveEnvelopes([...logic.finances.envelopes, Envelope(id: id, name: name)]);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final list = logic.finances.envelopes;
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      const Text('Enveloppes', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      Text('Peu nombreuses : cinq suffisent. Une dépense déjà notée garde son enveloppe.', style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 10),
      for (final e in list)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(e.monthly > 0 ? '${euros(e.monthly)} par mois' : 'pas de plafond'),
          onTap: () async {
            final r = await _askAmount(context, title: 'Plafond · ${e.name}', hint: 'par mois · vide = pas de plafond', initial: e.monthly, allowEmpty: true);
            if (r == null) return;
            await logic.saveEnvelopes([for (final x in logic.finances.envelopes) x.id == e.id ? Envelope(id: x.id, name: x.name, monthly: r) : x]);
            setState(() {});
          },
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Renommer', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _rename(e)),
            if (list.length > 1)
              IconButton(
                tooltip: 'Retirer',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () async {
                  await logic.saveEnvelopes([for (final x in logic.finances.envelopes) if (x.id != e.id) x]);
                  setState(() {});
                },
              ),
          ]),
        ),
      Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _add, child: const Text('+ Une enveloppe'))),
    ]);
  }
}

/// Revenus et fixes : nom, montant, jour du mois.
Future<void> showRecurringSheet(BuildContext context, {required AppLogic logic}) {
  return showFiche<void>(context, builder: (ctx, scroll) => _RecurringEditor(logic: logic, scroll: scroll));
}

class _RecurringEditor extends StatefulWidget {
  final AppLogic logic;
  final ScrollController scroll;
  const _RecurringEditor({required this.logic, required this.scroll});

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  AppLogic get logic => widget.logic;

  Future<void> _edit(Recurring? r, {bool income = false}) async {
    final res = await showDialog<Recurring>(context: context, builder: (ctx) => _RecurringDialog(initial: r, income: r?.income ?? income));
    if (res == null) return;
    final list = logic.finances.recurring;
    await logic.saveRecurring(r == null ? [...list, res] : [for (final x in list) x.id == r.id ? res : x]);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final list = logic.finances.recurring;
    Widget section(String t, bool income) {
      final mine = list.where((r) => r.income == income).toList()..sort((a, b) => a.day.compareTo(b.day));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute)),
        ),
        for (final r in mine)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${euros(r.amount)} · le ${r.day} du mois'),
            onTap: () => _edit(r),
            trailing: IconButton(
              tooltip: 'Retirer',
              icon: const Icon(Icons.close, size: 20),
              onPressed: () async {
                await logic.saveRecurring([for (final x in logic.finances.recurring) if (x.id != r.id) x]);
                setState(() {});
              },
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => _edit(null, income: income), child: Text(income ? '+ Un revenu' : '+ Un fixe')),
        ),
      ]);
    }

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      const Text('Revenus et fixes', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      Text('Posés une fois, ils reviennent chaque mois ; tu les coches quand ils passent sur le compte.', style: TextStyle(fontSize: 13, color: mute)),
      section('REVENUS', true),
      section('FIXES', false),
    ]);
  }
}

class _RecurringDialog extends StatefulWidget {
  final Recurring? initial;
  final bool income;
  const _RecurringDialog({this.initial, required this.income});

  @override
  State<_RecurringDialog> createState() => _RecurringDialogState();
}

class _RecurringDialogState extends State<_RecurringDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _amount = TextEditingController(
      text: widget.initial == null ? '' : (widget.initial!.amount % 100 == 0 ? '${widget.initial!.amount ~/ 100}' : (widget.initial!.amount / 100).toStringAsFixed(2).replaceAll('.', ',')));
  late int _day = widget.initial?.day ?? 1;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = parseEuros(_amount.text);
    final ok = v != null && _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.initial != null ? 'Modifier' : (widget.income ? 'Un revenu' : 'Un fixe')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _name,
          autofocus: widget.initial == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Nom', hintText: widget.income ? 'Salaire, vacations…' : 'Loyer, forfait…'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
          decoration: const InputDecoration(labelText: 'Montant par mois', suffixText: '€'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Text('Le'),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _day,
            items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d'))],
            onChanged: (d) => setState(() => _day = d ?? 1),
          ),
          const SizedBox(width: 8),
          const Text('du mois'),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: !ok
              ? null
              : () => Navigator.pop(
                    context,
                    Recurring(
                      id: widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
                      name: _name.text.trim(),
                      amount: v,
                      day: _day,
                      income: widget.income,
                    ),
                  ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

Future<String?> _askText(BuildContext context, String title, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.sentences),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}
