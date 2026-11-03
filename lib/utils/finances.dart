/// Suivi des finances, 100 % manuel (maquette validée 2026-11-02 « Suivi des
/// finances ») — logique pure. Stocké dans `data/meta.finances` :
/// `{envelopes: [{id, name, monthly}], recurring: [{id, name, amount, day, income?}],
/// expenses: {<id>: {ymd, amount, envelopeId, note?}}, nothing: [ymd],
/// months: {<YYYY-MM>: {paid: {<recurringId>: {amount, ymd}}}},
/// checks: {<ymd>: balance}}`. Les montants sont en CENTIMES (int).
///
/// Un **jour suivi** = au moins une dépense notée ce jour-là, ou « Rien
/// dépensé ». Une dépense ne se note que pour aujourd'hui ou hier.

class Envelope {
  final String id;
  final String name;
  /// Plafond du mois en centimes ; 0 = pas de plafond.
  final int monthly;
  const Envelope({required this.id, required this.name, this.monthly = 0});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'monthly': monthly};
  static Envelope? from(Object? raw) {
    if (raw is! Map || raw['id'] == null) return null;
    return Envelope(id: '${raw['id']}', name: '${raw['name'] ?? ''}', monthly: (raw['monthly'] as num?)?.toInt() ?? 0);
  }
}

/// Un fixe (loyer, abonnement…) ou un revenu (`income`) qui revient chaque mois.
class Recurring {
  final String id;
  final String name;
  final int amount;
  /// Jour du mois attendu (1 → 31, ramené au dernier jour d'un mois court).
  final int day;
  final bool income;
  const Recurring({required this.id, required this.name, required this.amount, this.day = 1, this.income = false});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'amount': amount, 'day': day, if (income) 'income': true};
  static Recurring? from(Object? raw) {
    if (raw is! Map || raw['id'] == null) return null;
    return Recurring(
      id: '${raw['id']}',
      name: '${raw['name'] ?? ''}',
      amount: (raw['amount'] as num?)?.toInt() ?? 0,
      day: ((raw['day'] as num?)?.toInt() ?? 1).clamp(1, 31),
      income: raw['income'] == true,
    );
  }
}

class Expense {
  final String id;
  final String ymd;
  final int amount;
  final String envelopeId;
  final String? note;
  /// Domaine de vie et projet servis (courses générales, 2026-11-02) ; null = sans.
  final String? domainId;
  final String? projectId;
  /// Lignes de courses couvertes par cette dépense (passage en caisse).
  final List<String> items;
  /// Moment de la saisie (ms) : départage une dépense et une mise à jour du solde du même jour.
  final int? at;
  /// Montant par rayon (Épicerie, Frais…) d'une dépense de courses, en centimes (placards, 2026-11-03).
  final Map<String, int> byAisle;
  const Expense({required this.id, required this.ymd, required this.amount, required this.envelopeId, this.note, this.domainId, this.projectId, this.items = const [], this.at, this.byAisle = const {}});

  Map<String, dynamic> toJson() => {
        'ymd': ymd,
        'amount': amount,
        'envelopeId': envelopeId,
        if (note != null && note!.isNotEmpty) 'note': note,
        if (domainId != null) 'domainId': domainId,
        if (projectId != null) 'projectId': projectId,
        if (items.isNotEmpty) 'items': items,
        if (at != null) 'at': at,
        if (byAisle.isNotEmpty) 'byAisle': byAisle,
      };
  static Expense? from(String id, Object? raw) {
    if (raw is! Map || raw['ymd'] == null) return null;
    return Expense(
      id: id,
      ymd: '${raw['ymd']}',
      amount: (raw['amount'] as num?)?.toInt() ?? 0,
      envelopeId: '${raw['envelopeId'] ?? ''}',
      note: raw['note'] as String?,
      domainId: raw['domainId'] as String?,
      projectId: raw['projectId'] as String?,
      items: raw['items'] is List ? [for (final x in raw['items'] as List) '$x'] : const [],
      at: (raw['at'] as num?)?.toInt(),
      byAisle: raw['byAisle'] is Map
          ? {for (final e in (raw['byAisle'] as Map).entries) '${e.key}': (e.value as num?)?.toInt() ?? 0}
          : const {},
    );
  }
}

/// Une rentrée ponctuelle (facture encaissée, remboursement…), 2026-11-02 :
/// pour qui n'a pas de salaire fixe.
class Income {
  final String id;
  final String ymd;
  final int amount;
  /// De qui (client), facultatif.
  final String? from;
  final String? domainId;
  final String? projectId;
  final int? at;
  const Income({required this.id, required this.ymd, required this.amount, this.from, this.domainId, this.projectId, this.at});

  Map<String, dynamic> toJson() => {
        'ymd': ymd,
        'amount': amount,
        if (from != null && from!.isNotEmpty) 'from': from,
        if (domainId != null) 'domainId': domainId,
        if (projectId != null) 'projectId': projectId,
        if (at != null) 'at': at,
      };
  static Income? fromJson(String id, Object? raw) {
    if (raw is! Map || raw['ymd'] == null) return null;
    return Income(
      id: id,
      ymd: '${raw['ymd']}',
      amount: (raw['amount'] as num?)?.toInt() ?? 0,
      from: raw['from'] as String?,
      domainId: raw['domainId'] as String?,
      projectId: raw['projectId'] as String?,
      at: (raw['at'] as num?)?.toInt(),
    );
  }
}

/// Un fixe passé ce mois-ci : le montant réel et le jour où on l'a coché.
class Paid {
  final int amount;
  final String ymd;
  final int? at;
  const Paid(this.amount, this.ymd, {this.at});
  Map<String, dynamic> toJson() => {'amount': amount, 'ymd': ymd, if (at != null) 'at': at};
  static Paid? from(Object? raw) {
    if (raw is! Map || raw['ymd'] == null) return null;
    return Paid((raw['amount'] as num?)?.toInt() ?? 0, '${raw['ymd']}', at: (raw['at'] as num?)?.toInt());
  }
}

/// Enveloppes proposées au premier passage (sans plafond : chacun pose le sien).
const kDefaultEnvelopes = [
  Envelope(id: 'courses', name: 'Courses'),
  Envelope(id: 'essence', name: 'Essence'),
  Envelope(id: 'sorties', name: 'Sorties'),
  Envelope(id: 'maison', name: 'Maison'),
  Envelope(id: 'imprevus', name: 'Imprévus'),
];

class Finances {
  final List<Envelope> envelopes;
  final List<Recurring> recurring;
  final Map<String, Expense> expenses;
  final Set<String> nothing;
  /// Fixes passés, par mois (`YYYY-MM`) puis par id de fixe.
  final Map<String, Map<String, Paid>> paid;
  /// Soldes recopiés (point de la semaine, mise à jour du solde), par jour.
  final Map<String, int> checks;
  /// Moment (ms) de chaque solde recopié.
  final Map<String, int> checksAt;
  /// Rentrées ponctuelles (factures encaissées…).
  final Map<String, Income> incomes;
  const Finances({
    this.envelopes = kDefaultEnvelopes,
    this.recurring = const [],
    this.expenses = const {},
    this.nothing = const {},
    this.paid = const {},
    this.checks = const {},
    this.checksAt = const {},
    this.incomes = const {},
  });

  Finances copyWith({
    List<Envelope>? envelopes,
    List<Recurring>? recurring,
    Map<String, Expense>? expenses,
    Set<String>? nothing,
    Map<String, Map<String, Paid>>? paid,
    Map<String, int>? checks,
    Map<String, int>? checksAt,
    Map<String, Income>? incomes,
  }) =>
      Finances(
        envelopes: envelopes ?? this.envelopes,
        recurring: recurring ?? this.recurring,
        expenses: expenses ?? this.expenses,
        nothing: nothing ?? this.nothing,
        paid: paid ?? this.paid,
        checks: checks ?? this.checks,
        checksAt: checksAt ?? this.checksAt,
        incomes: incomes ?? this.incomes,
      );

  Envelope? envelopeOf(String id) {
    for (final e in envelopes) {
      if (e.id == id) return e;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'envelopes': [for (final e in envelopes) e.toJson()],
        'recurring': [for (final r in recurring) r.toJson()],
        'expenses': {for (final x in expenses.values) x.id: x.toJson()},
        'nothing': nothing.toList()..sort(),
        'months': {
          for (final m in paid.entries) m.key: {'paid': m.value.map((k, v) => MapEntry(k, v.toJson()))}
        },
        'checks': checks,
        'checksAt': checksAt,
        'incomes': {for (final x in incomes.values) x.id: x.toJson()},
      };
}

Finances parseFinances(Object? raw) {
  if (raw is! Map) return const Finances();
  final envs = raw['envelopes'] is List ? [for (final e in raw['envelopes'] as List) if (Envelope.from(e) case final v?) v] : null;
  final rec = raw['recurring'] is List ? [for (final e in raw['recurring'] as List) if (Recurring.from(e) case final v?) v] : const <Recurring>[];
  final exp = <String, Expense>{};
  if (raw['expenses'] is Map) {
    for (final e in (raw['expenses'] as Map).entries) {
      final x = Expense.from('${e.key}', e.value);
      if (x != null) exp[x.id] = x;
    }
  }
  final nothing = raw['nothing'] is List ? {for (final y in raw['nothing'] as List) '$y'} : <String>{};
  final paid = <String, Map<String, Paid>>{};
  if (raw['months'] is Map) {
    for (final m in (raw['months'] as Map).entries) {
      final p = m.value is Map ? (m.value as Map)['paid'] : null;
      if (p is! Map) continue;
      paid['${m.key}'] = {
        for (final e in p.entries)
          if (Paid.from(e.value) case final v?) '${e.key}': v,
      };
    }
  }
  final checks = <String, int>{};
  if (raw['checks'] is Map) {
    for (final e in (raw['checks'] as Map).entries) {
      if (e.value is num) checks['${e.key}'] = (e.value as num).toInt();
    }
  }
  final checksAt = <String, int>{};
  if (raw['checksAt'] is Map) {
    for (final e in (raw['checksAt'] as Map).entries) {
      if (e.value is num) checksAt['${e.key}'] = (e.value as num).toInt();
    }
  }
  final incomes = <String, Income>{};
  if (raw['incomes'] is Map) {
    for (final e in (raw['incomes'] as Map).entries) {
      final x = Income.fromJson('${e.key}', e.value);
      if (x != null) incomes[x.id] = x;
    }
  }
  return Finances(
    envelopes: envs == null || envs.isEmpty ? kDefaultEnvelopes : envs,
    recurring: rec,
    expenses: exp,
    nothing: nothing,
    paid: paid,
    checks: checks,
    checksAt: checksAt,
    incomes: incomes,
  );
}

// ── Dates ───────────────────────────────────────────────────────────────────

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String monthOf(String ymd) => ymd.substring(0, 7);
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
String prevYmd(String ymd) => _ymd(DateTime.parse(ymd).subtract(const Duration(days: 1)));

/// Une dépense ne se note que pour aujourd'hui ou hier (journée vécue).
bool canLogOn(String ymd, String todayYmd) => ymd == todayYmd || ymd == prevYmd(todayYmd);

// ── Jours suivis ────────────────────────────────────────────────────────────

Set<String> trackedDays(Finances f) => {...f.nothing, for (final x in f.expenses.values) x.ymd};

bool isTracked(Finances f, String ymd) => trackedDays(f).contains(ymd);

/// Jours suivis d'affilée jusqu'à aujourd'hui ; un aujourd'hui pas encore
/// suivi ne casse rien (la journée n'est pas finie).
int trackingStreak(Finances f, String todayYmd) {
  final days = trackedDays(f);
  var d = days.contains(todayYmd) ? todayYmd : prevYmd(todayYmd);
  var n = 0;
  while (days.contains(d)) {
    n++;
    d = prevYmd(d);
  }
  return n;
}

/// Jours suivis depuis [fromYmd] inclus (le relevé « Suivi » d'un objectif).
int trackedSince(Finances f, String fromYmd) => trackedDays(f).where((d) => d.compareTo(fromYmd) >= 0).length;

// ── Le mois ─────────────────────────────────────────────────────────────────

class EnvelopeMonth {
  final Envelope envelope;
  final int spent;
  /// Attendu à ce jour = plafond × jours écoulés / jours du mois.
  final int expected;
  const EnvelopeMonth(this.envelope, this.spent, this.expected);
  /// Dépense plus vite que le mois (seulement avec un plafond).
  bool get ahead => envelope.monthly > 0 && spent > expected;
  bool get over => envelope.monthly > 0 && spent > envelope.monthly;
  double get ratio => envelope.monthly <= 0 ? 0 : spent / envelope.monthly;
}

class MonthSummary {
  final String month;
  final int income;
  final int fixed;
  final int spent;
  final int daysLeft;
  final List<EnvelopeMonth> envelopes;
  /// Fixes (hors revenus) du mois : passés / total.
  final int fixedPaidCount;
  final int fixedCount;
  const MonthSummary({
    required this.month,
    required this.income,
    required this.fixed,
    required this.spent,
    required this.daysLeft,
    required this.envelopes,
    required this.fixedPaidCount,
    required this.fixedCount,
  });

  /// Reste à vivre = revenus − fixes − dépenses (montants prévus ou réels).
  int get remaining => income - fixed - spent;
  int get perDay => daysLeft <= 0 ? remaining : (remaining / daysLeft).floor();
  bool get hasIncome => income > 0;
}

/// Le mois de [todayYmd] : un fixe passé compte pour son montant réel, sinon
/// pour son montant prévu ; idem pour les revenus.
MonthSummary monthSummary(Finances f, String todayYmd) {
  final month = monthOf(todayYmd);
  final d = DateTime.parse(todayYmd);
  final total = daysInMonth(d.year, d.month);
  final paidNow = f.paid[month] ?? const {};
  int amountOf(Recurring r) => paidNow[r.id]?.amount ?? r.amount;
  final oneOff = f.incomes.values.where((x) => monthOf(x.ymd) == month && x.ymd.compareTo(todayYmd) <= 0).fold<int>(0, (s, x) => s + x.amount);
  final income = f.recurring.where((r) => r.income).fold<int>(0, (s, r) => s + amountOf(r)) + oneOff;
  final fixedList = f.recurring.where((r) => !r.income).toList();
  final fixed = fixedList.fold<int>(0, (s, r) => s + amountOf(r));
  final mine = f.expenses.values.where((x) => monthOf(x.ymd) == month && x.ymd.compareTo(todayYmd) <= 0);
  final byEnv = <String, int>{};
  for (final x in mine) {
    byEnv[x.envelopeId] = (byEnv[x.envelopeId] ?? 0) + x.amount;
  }
  final spent = byEnv.values.fold<int>(0, (s, v) => s + v);
  return MonthSummary(
    month: month,
    income: income,
    fixed: fixed,
    spent: spent,
    daysLeft: total - d.day + 1,
    envelopes: [
      for (final e in f.envelopes) EnvelopeMonth(e, byEnv[e.id] ?? 0, (e.monthly * d.day / total).round()),
    ],
    fixedPaidCount: fixedList.where((r) => paidNow.containsKey(r.id)).length,
    fixedCount: fixedList.length,
  );
}

/// Jour attendu d'un fixe dans le mois de [todayYmd] (dernier jour d'un mois court).
String dueYmdOf(Recurring r, String todayYmd) {
  final d = DateTime.parse(todayYmd);
  final day = r.day.clamp(1, daysInMonth(d.year, d.month));
  return _ymd(DateTime(d.year, d.month, day));
}

// ── Le point de la semaine ──────────────────────────────────────────────────

class BalanceCheck {
  /// Dernier solde recopié avant ce point (null = premier point).
  final String? lastYmd;
  final int? lastBalance;
  final int spentSince;
  final int paidOutSince;
  final int paidInSince;
  const BalanceCheck({this.lastYmd, this.lastBalance, this.spentSince = 0, this.paidOutSince = 0, this.paidInSince = 0});

  /// Solde d'après l'app (null sans point précédent).
  int? get expected => lastBalance == null ? null : lastBalance! - spentSince - paidOutSince + paidInSince;

  /// Écart = ce que dit la banque − ce que dit l'app ; négatif = de l'argent
  /// est sorti sans être noté.
  int? gap(int balance) => expected == null ? null : balance - expected!;
}

/// Le point du jour [todayYmd] face au dernier solde recopié AVANT lui :
/// dépenses notées après ce jour-là, fixes et revenus cochés après lui.
BalanceCheck balanceCheck(Finances f, String todayYmd) {
  String? last;
  for (final k in f.checks.keys) {
    if (k.compareTo(todayYmd) < 0 && (last == null || k.compareTo(last) > 0)) last = k;
  }
  if (last == null) return const BalanceCheck();
  final m = _movesSince(f, last, f.checksAt[last], todayYmd);
  return BalanceCheck(lastYmd: last, lastBalance: f.checks[last], spentSince: m.spent, paidOutSince: m.out, paidInSince: m.inc);
}

/// Un mouvement daté [ymd] / [at] est-il APRÈS le solde recopié le [cYmd] à
/// [cAt] ? Un autre jour : par la date ; le même jour : par l'heure. Un
/// mouvement sans heure face à un solde horodaté est compté APRÈS (retour user
/// 2026-11-03 : une dépense du soir n'était pas retranchée du solde posé le même
/// soir) ; un ancien solde sans heure contient tout son jour.
bool _after(String ymd, int? at, String cYmd, int? cAt) =>
    ymd.compareTo(cYmd) > 0 || (ymd == cYmd && cAt != null && (at == null || at > cAt));

({int spent, int out, int inc}) _movesSince(Finances f, String cYmd, int? cAt, String todayYmd) {
  bool keep(String ymd, int? at) => _after(ymd, at, cYmd, cAt) && ymd.compareTo(todayYmd) <= 0;
  final spent = f.expenses.values.where((x) => keep(x.ymd, x.at)).fold<int>(0, (s, x) => s + x.amount);
  var out = 0, inc = 0;
  final byId = {for (final r in f.recurring) r.id: r};
  for (final month in f.paid.values) {
    for (final e in month.entries) {
      if (!keep(e.value.ymd, e.value.at)) continue;
      if (byId[e.key]?.income == true) {
        inc += e.value.amount;
      } else {
        out += e.value.amount;
      }
    }
  }
  inc += f.incomes.values.where((x) => keep(x.ymd, x.at)).fold<int>(0, (s, x) => s + x.amount);
  return (spent: spent, out: out, inc: inc);
}

/// Ce que dit le compte maintenant, d'après le dernier solde recopié (jusqu'à
/// aujourd'hui compris) et ce qui a été noté depuis ; null sans solde.
class AccountNow {
  final String sinceYmd;
  final int base;
  final int balance;
  /// Fixes du mois pas encore passés, revenus mensuels pas encore reçus.
  final int fixedLeft;
  final int incomeLeft;
  final int daysLeft;
  /// Heure du solde recopié (ms), null si inconnue.
  final int? sinceAt;
  /// Ce qui a été retranché / ajouté depuis ce solde.
  final int spentSince;
  final int outSince;
  final int inSince;
  /// Dépenses du jour du solde notées AVANT lui : supposées déjà dedans.
  final List<Expense> before;
  const AccountNow({
    required this.sinceYmd,
    required this.base,
    required this.balance,
    required this.fixedLeft,
    required this.incomeLeft,
    required this.daysLeft,
    this.sinceAt,
    this.spentSince = 0,
    this.outSince = 0,
    this.inSince = 0,
    this.before = const [],
  });
  /// Reste à vivre jusqu'à la fin du mois = compte + revenus attendus − fixes à venir.
  int get remaining => balance + incomeLeft - fixedLeft;
  int get perDay => daysLeft <= 0 ? remaining : (remaining / daysLeft).floor();
}

AccountNow? accountNow(Finances f, String todayYmd) {
  String? last;
  for (final k in f.checks.keys) {
    if (k.compareTo(todayYmd) <= 0 && (last == null || k.compareTo(last) > 0)) last = k;
  }
  if (last == null) return null;
  final m = _movesSince(f, last, f.checksAt[last], todayYmd);
  final base = f.checks[last]!;
  final month = monthOf(todayYmd);
  final paidNow = f.paid[month] ?? const {};
  var fixedLeft = 0, incomeLeft = 0;
  for (final r in f.recurring) {
    if (paidNow.containsKey(r.id)) continue;
    r.income ? incomeLeft += r.amount : fixedLeft += r.amount;
  }
  final d = DateTime.parse(todayYmd);
  final cAt = f.checksAt[last];
  return AccountNow(
    sinceYmd: last,
    base: base,
    balance: base - m.spent - m.out + m.inc,
    fixedLeft: fixedLeft,
    incomeLeft: incomeLeft,
    daysLeft: daysInMonth(d.year, d.month) - d.day + 1,
    sinceAt: cAt,
    spentSince: m.spent,
    outSince: m.out,
    inSince: m.inc,
    before: [for (final x in f.expenses.values) if (x.ymd == last && !_after(x.ymd, x.at, last, cAt)) x],
  );
}

/// Rentrées du mois de [todayYmd] (ponctuelles), jusqu'à aujourd'hui.
List<Income> monthIncomes(Finances f, String todayYmd) {
  final month = monthOf(todayYmd);
  return f.incomes.values.where((x) => monthOf(x.ymd) == month && x.ymd.compareTo(todayYmd) <= 0).toList()..sort((a, b) => b.ymd.compareTo(a.ymd));
}

// ── Affichage ───────────────────────────────────────────────────────────────

/// « 1 240 € », « 23,40 € », « − 40 € ».
String euros(int cents, {bool sign = false}) {
  final neg = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final rest = abs % 100;
  final s = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  final body = rest == 0 ? '$buf €' : '$buf,${rest.toString().padLeft(2, '0')} €';
  if (neg) return '− $body';
  return sign ? '+ $body' : body;
}

/// « 23,40 » / « 23.4 » / « 23 » → centimes ; null si illisible ou ≤ 0.
int? parseEuros(String raw) {
  final t = raw.replaceAll(RegExp(r'[\s€ ]'), '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v <= 0) return null;
  return (v * 100).round();
}

/// La routine « Suivre mon budget » (carte du catalogue `budget`, sinon par le nom).
bool isBudgetRoutineName(String name) {
  final n = name.toLowerCase();
  return n.contains('budget') || n.contains('dépenses') || n.contains('depenses') || n.contains('finances');
}

/// Dernier solde recopié (le plus récent), ou null.
String? lastCheckYmd(Finances f) {
  String? last;
  for (final k in f.checks.keys) {
    if (last == null || k.compareTo(last) > 0) last = k;
  }
  return last;
}

/// Le point est dû : jamais fait, ou le dernier date d'au moins 7 jours.
bool checkDue(Finances f, String todayYmd) {
  final last = lastCheckYmd(f);
  if (last == null) return true;
  return DateTime.parse(todayYmd).difference(DateTime.parse(last)).inDays >= 7;
}

/// Un écart de moins d'un euro ne compte pas (arrondis, centimes).
bool gapIsZero(int gap) => gap.abs() < 100;
