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
  const Expense({required this.id, required this.ymd, required this.amount, required this.envelopeId, this.note});

  Map<String, dynamic> toJson() => {'ymd': ymd, 'amount': amount, 'envelopeId': envelopeId, if (note != null && note!.isNotEmpty) 'note': note};
  static Expense? from(String id, Object? raw) {
    if (raw is! Map || raw['ymd'] == null) return null;
    return Expense(
      id: id,
      ymd: '${raw['ymd']}',
      amount: (raw['amount'] as num?)?.toInt() ?? 0,
      envelopeId: '${raw['envelopeId'] ?? ''}',
      note: raw['note'] as String?,
    );
  }
}

/// Un fixe passé ce mois-ci : le montant réel et le jour où on l'a coché.
class Paid {
  final int amount;
  final String ymd;
  const Paid(this.amount, this.ymd);
  Map<String, dynamic> toJson() => {'amount': amount, 'ymd': ymd};
  static Paid? from(Object? raw) {
    if (raw is! Map || raw['ymd'] == null) return null;
    return Paid((raw['amount'] as num?)?.toInt() ?? 0, '${raw['ymd']}');
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
  /// Soldes recopiés lors du point de la semaine, par jour.
  final Map<String, int> checks;
  const Finances({
    this.envelopes = kDefaultEnvelopes,
    this.recurring = const [],
    this.expenses = const {},
    this.nothing = const {},
    this.paid = const {},
    this.checks = const {},
  });

  Finances copyWith({
    List<Envelope>? envelopes,
    List<Recurring>? recurring,
    Map<String, Expense>? expenses,
    Set<String>? nothing,
    Map<String, Map<String, Paid>>? paid,
    Map<String, int>? checks,
  }) =>
      Finances(
        envelopes: envelopes ?? this.envelopes,
        recurring: recurring ?? this.recurring,
        expenses: expenses ?? this.expenses,
        nothing: nothing ?? this.nothing,
        paid: paid ?? this.paid,
        checks: checks ?? this.checks,
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
  return Finances(
    envelopes: envs == null || envs.isEmpty ? kDefaultEnvelopes : envs,
    recurring: rec,
    expenses: exp,
    nothing: nothing,
    paid: paid,
    checks: checks,
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
  final income = f.recurring.where((r) => r.income).fold<int>(0, (s, r) => s + amountOf(r));
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
  bool inWindow(String ymd) => ymd.compareTo(last!) > 0 && ymd.compareTo(todayYmd) <= 0;
  final spent = f.expenses.values.where((x) => inWindow(x.ymd)).fold<int>(0, (s, x) => s + x.amount);
  var out = 0, inc = 0;
  final byId = {for (final r in f.recurring) r.id: r};
  for (final month in f.paid.values) {
    for (final e in month.entries) {
      if (!inWindow(e.value.ymd)) continue;
      if (byId[e.key]?.income == true) {
        inc += e.value.amount;
      } else {
        out += e.value.amount;
      }
    }
  }
  return BalanceCheck(lastYmd: last, lastBalance: f.checks[last], spentSince: spent, paidOutSince: out, paidInSince: inc);
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
