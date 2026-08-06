import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/web/coaching_screen.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';

// ─── CONSOLE COACH 8a (web, desktop-first) ───────────────────────────────────
//
// L'écran de travail quotidien du coach (design :
// docs/specs/espace-coach-design, écran 8a) — au-dessus de la brique
// coaching existante (coachApi : listClients / dashboard / message /
// consentLink). Trois colonnes : QUI (rail trié par attention, jamais
// alphabétique) · QUOI (panneau central, structure identique pour tous,
// seul le bandeau d'état change) · QUAND (aujourd'hui / 4 semaines).
//
// Principe à préserver : la donnée est partagée, l'interprétation reste
// humaine — l'app n'écrit jamais le sens des chiffres à la place du coach.

// Échelle de couleur des paliers : source unique lib/utils/palier_colors.dart
// (partagée avec le tableau de bord du coaché). Alias privés pour la
// lisibilité locale.
const _kGreen = kPalierGreen;
const _kAmber = kPalierAmber;
const _kCoral = kPalierCoral;
const _kMuted = kPalierMuted;
const _kFaint = Color(0xFF6E8A7B);

Color _tierColor(int pct) => palierColor(pct);

/// Machine à états du bandeau central : une même carte, plusieurs rendus.
/// Adaptée aux données réellement disponibles aujourd'hui (le boost « coup
/// de main » et le refus d'ajustement viendront avec leurs chantiers).
enum _CState { silence, retard, rien, attente, revoque, bien, suivi }

class _Coachee {
  final Map<String, dynamic> fiche;
  Map<String, dynamic>? dash; // dashboard serveur (consentement requis)
  String? reason; // no_scope | no_account | … quand dash == null

  _Coachee(this.fiche);

  String get id => fiche['id'] as String;
  String get name => (fiche['name'] as String?)?.trim().isNotEmpty == true
      ? fiche['name'] as String
      : fiche['email'] as String;
  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();
  String get consent => (fiche['consent'] as String?) ?? 'pending';
  int get domainCount =>
      ((fiche['sharing'] as Map?)?['domainCount'] as num?)?.toInt() ?? 0;
  bool get detail => (fiche['sharing'] as Map?)?['granularity'] == 'detail';

  List<Map<String, dynamic>> get engagements =>
      ((dash?['engagements'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  List<Map<String, dynamic>> get weeks => ((dash?['weeks'] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  int get kept => engagements.where((e) => e['kept'] == true).length;
  int get total => engagements.length;
  int get weekPct => weeks.isEmpty
      ? 0
      : ((weeks.last['pct'] as num?)?.toInt() ?? 0);
  int get prevPct => weeks.length < 2
      ? weekPct
      : ((weeks[weeks.length - 2]['pct'] as num?)?.toInt() ?? 0);
  DateTime? get lastActivityAt =>
      DateTime.tryParse(dash?['lastActivityAt']?.toString() ?? '');

  _CState get state {
    if (consent == 'revoked') return _CState.revoque;
    if (consent != 'granted') return _CState.attente;
    if (domainCount == 0 || reason == 'no_scope') return _CState.rien;
    if (dash == null) return _CState.attente; // no_account, erreur…
    final last = lastActivityAt;
    if (last == null || DateTime.now().difference(last).inDays >= 5) {
      return _CState.silence;
    }
    if (total > 0 && weekPct < 60) return _CState.retard;
    if (weeks.length >= 3 &&
        weeks
            .skip(weeks.length - 3)
            .every((w) => ((w['pct'] as num?)?.toInt() ?? 0) >= 85)) {
      return _CState.bien;
    }
    if (fiche['status'] == 'explo') return _CState.suivi;
    return _CState.suivi;
  }

  /// Rang d'attention : ce qui a besoin du coach d'abord (rail).
  int get attention => switch (state) {
        _CState.silence => 0,
        _CState.retard => 1,
        _CState.rien => 2,
        _CState.attente => 3,
        _CState.revoque => 4,
        _CState.suivi => 5,
        _CState.bien => 6,
      };

  bool get needsAction =>
      state == _CState.silence ||
      state == _CState.retard ||
      state == _CState.rien;
}

({Color color, String pill, String title}) _stateSpec(_Coachee c) {
  final days = c.lastActivityAt == null
      ? null
      : DateTime.now().difference(c.lastActivityAt!).inDays;
  return switch (c.state) {
    _CState.silence => (
        color: _kCoral,
        pill: 'SILENCE',
        title: days == null
            ? 'Aucune activité visible depuis l\'ouverture du partage.'
            : 'Aucune activité visible depuis $days jours.',
      ),
    _CState.retard => (
        color: _kAmber,
        pill: 'EN RETARD',
        title:
            '7 derniers jours difficiles : ${c.kept} engagement(s) tenu(s) sur ${c.total}.',
      ),
    _CState.rien => (
        color: _kFaint,
        pill: 'RIEN DE PARTAGÉ',
        title:
            'Consentement donné, mais aucun domaine partagé pour l\'instant.',
      ),
    _CState.attente => (
        color: _kMuted,
        pill: 'EN ATTENTE',
        title: 'Le lien n\'est pas encore actif — consentement en attente.',
      ),
    _CState.revoque => (
        color: _kCoral,
        pill: 'RÉVOQUÉ',
        title: 'Le coaché a coupé l\'accès. À aborder en séance, pas par app.',
      ),
    _CState.bien => (
        color: _kGreen,
        pill: 'SOLIDE',
        title: '3 semaines pleines — le moment de proposer le palier suivant.',
      ),
    _CState.suivi => (
        color: _kMuted,
        pill: 'EN COURS',
        title:
            'Au fil de l\'eau — ${c.kept} / ${c.total} engagements tenus sur 7 jours.',
      ),
  };
}

class CoachConsoleScreen extends StatefulWidget {
  const CoachConsoleScreen({super.key});

  @override
  State<CoachConsoleScreen> createState() => _CoachConsoleScreenState();
}

class _CoachConsoleScreenState extends State<CoachConsoleScreen> {
  List<_Coachee> _all = [];
  bool _loading = true;
  String? _error;
  String? _selectedId;
  String _railFilter = 'tous'; // tous | traiter
  String _timeView = 'semaines'; // jour | semaines

  // Panneau central — état par coaché sélectionné.
  final Set<String> _highlighted = {}; // engagements mis en avant
  final _motCtrl = TextEditingController();
  String _tone = 'neutre';
  bool _sending = false;

  static const _tones = <String, (String, String)>{
    // ton → (libellé, phrase d'intro — SEULE chose qui change, le corps
    // reste écrit par le coach : design 3a).
    'encourageant': (
      'Encourageant',
      'Beau travail cette semaine — voici ce que je retiens.'
    ),
    'neutre': ('Neutre', 'Voici ce que je retiens de ta semaine.'),
    'exigeant': (
      'Exigeant',
      'On regarde ta semaine en face — parlons-en.'
    ),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _motCtrl.dispose();
    _motFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await coachCall({'action': 'listClients'});
      final fiches = ((r['clients'] as List?) ?? [])
          .map((c) => _Coachee(Map<String, dynamic>.from(c as Map)))
          .toList();
      // Dashboards en parallèle — uniquement les liens consentis.
      await Future.wait(fiches
          .where((c) => c.consent == 'granted')
          .map((c) async {
        try {
          final d = await coachCall({'action': 'dashboard', 'id': c.id});
          if (d['ok'] == true) {
            c.dash = Map<String, dynamic>.from(d['dashboard'] as Map);
          } else {
            c.reason = d['reason']?.toString();
          }
        } catch (e) {
          c.reason = '$e';
        }
      }));
      fiches.sort((a, b) => a.attention != b.attention
          ? a.attention - b.attention
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _all = fiches;
      if (_all.isNotEmpty &&
          (_selectedId == null || _all.every((c) => c.id != _selectedId))) {
        _selectedId = _all.first.id;
      }
    } on CoachAccessDenied {
      _error = 'Accès coach requis — active le droit dans /admin.html (🎓).';
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  _Coachee? get _selected =>
      _all.where((c) => c.id == _selectedId).firstOrNull;

  void _select(_Coachee c) {
    setState(() {
      _selectedId = c.id;
      _highlighted.clear();
      _motCtrl.clear();
      _tone = 'neutre';
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _sendMot(_Coachee c) async {
    final mot = _motCtrl.text.trim();
    if (mot.isEmpty) return;
    setState(() => _sending = true);
    final lines = <String>[_tones[_tone]!.$2, '', mot];
    final joined = c.engagements
        .where((e) => _highlighted.contains(e['id'].toString()))
        .toList();
    if (joined.isNotEmpty) {
      lines
        ..add('')
        ..add('Les chiffres qu\'on regarde ensemble :');
      for (final e in joined) {
        lines.add(
            '· ${e['label']} — ${e['done']} / ${e['target']}${e['kept'] == true ? ' ✓' : ''}');
      }
    }
    try {
      final r = await coachCall({
        'action': 'message',
        'id': c.id,
        'text': lines.join('\n'),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(r['ok'] == true
                ? '✉️ Constat envoyé — il le verra à sa prochaine ouverture, signé de ton nom.'
                : 'Impossible (${r['reason']}).')));
        if (r['ok'] == true) {
          setState(() {
            _motCtrl.clear();
            _highlighted.clear();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  /// « Garder pour la séance » : le mot rejoint les notes de la fiche,
  /// daté — rien n'est envoyé au coaché.
  Future<void> _keepForSession(_Coachee c) async {
    final mot = _motCtrl.text.trim();
    if (mot.isEmpty) return;
    final now = DateTime.now();
    final stamp =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}';
    final notes = [
      ((c.fiche['notes'] as String?) ?? '').trim(),
      '[$stamp — préparé pour la séance] $mot',
    ].where((s) => s.isNotEmpty).join('\n\n');
    try {
      await coachCall({'action': 'updateClient', 'id': c.id, 'notes': notes});
      c.fiche['notes'] = notes;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Gardé dans la fiche — rien n\'est parti chez lui.')));
        setState(() => _motCtrl.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _copyConsentLink(_Coachee c) async {
    try {
      final r = await coachCall({'action': 'consentLink', 'id': c.id});
      final url = r['url'] as String?;
      if (url != null && mounted) {
        await showConsentLinkDialog(context, url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Action principale du bandeau d'état — colorée par l'état.
  (String, Future<void> Function())? _stateAction(_Coachee c) {
    switch (c.state) {
      case _CState.silence:
        // Hors de l'app : le canal in-app est peut-être mort (design 6a).
        return (
          'Copier son email pour un mot hors de l\'app',
          () async {
            await Clipboard.setData(
                ClipboardData(text: c.fiche['email'] as String));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Email copié — un SMS ou un mail vaut mieux qu\'une notification de plus.')));
            }
          }
        );
      case _CState.retard:
        return (
          'Écrire un mot (sans morale)',
          () async => _focusMot(),
        );
      case _CState.rien:
        return (
          'Relancer sur le partage',
          () async {
            _motCtrl.text =
                'Quand tu es prêt, ouvre Paramètres → Mon coach et choisis '
                'ce que tu veux me montrer — même juste les statuts. '
                'Rien ne presse.';
            _focusMot();
          }
        );
      case _CState.attente:
        return ('Copier le lien de consentement', () => _copyConsentLink(c));
      case _CState.bien:
        return (
          'Proposer le palier suivant',
          () async {
            _motCtrl.text =
                'Trois semaines pleines — solide. Est-ce qu\'on monte d\'un '
                'cran la semaine prochaine, ou on consolide ?';
            _focusMot();
          }
        );
      case _CState.revoque:
      case _CState.suivi:
        return null;
    }
  }

  final _motFocus = FocusNode();
  void _focusMot() => _motFocus.requestFocus();

  /// US-3 : rapport de pré-séance — le serveur compose, le coach relit,
  /// copie, et prépare sa séance avec.
  Future<void> _presession(_Coachee c) async {
    try {
      final r = await coachCall({'action': 'presession', 'id': c.id});
      if (!mounted) return;
      if (r['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(switch (r['reason']) {
          'no_scope' => 'Rien de partagé — pas de rapport possible.',
          'no_account' => 'Pas encore de compte coaché.',
          _ => 'Indisponible (${r['reason']}).',
        })));
        return;
      }
      final report = r['report'] as String? ?? '';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rapport de pré-séance'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: SelectableText(report,
                  style: const TextStyle(
                      fontSize: 12.5, fontFamily: 'monospace', height: 1.5)),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: report));
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Rapport copié')));
                  }
                } catch (_) {}
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copier'),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fermer')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final traiter = _all.where((c) => c.needsAction).length;
    final now = DateTime.now();
    const wd = [
      'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
    ];
    const months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
      'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ];

    Widget pill(String text, Color color) => Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 24,
        title: Row(children: [
          const Text('Espace coach',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: _kGreen, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            'en direct · ${wd[now.weekday - 1]} ${now.day} ${months[now.month - 1]}, '
            '${now.hour} h ${now.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
                fontSize: 12.5, color: cs.onSurface.withOpacity(.55)),
          ),
          const Spacer(),
          if (traiter > 0) pill('$traiter à traiter', _kCoral),
          pill('${_all.length} coaché(s)', _kMuted),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const CoachingScreen()));
              _load();
            },
            icon: const Icon(Icons.folder_shared_outlined, size: 16),
            label: const Text('Fiches & pipeline'),
          ),
          IconButton(
              tooltip: 'Rafraîchir',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.error)),
                  ),
                )
              : _all.isEmpty
                  ? Center(
                      child: Text(
                          'Aucun coaché — crée les fiches dans « Fiches & pipeline ».',
                          style:
                              TextStyle(color: cs.onSurface.withOpacity(.5))),
                    )
                  : LayoutBuilder(builder: (ctx, box) {
                      final wide = box.maxWidth >= 1150;
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 264, child: _rail(cs)),
                            VerticalDivider(
                                width: 1,
                                color: Colors.white.withOpacity(.07)),
                            Expanded(child: _centerPanel(cs)),
                            VerticalDivider(
                                width: 1,
                                color: Colors.white.withOpacity(.07)),
                            SizedBox(width: 348, child: _timeColumn(cs)),
                          ],
                        );
                      }
                      // Étroit : rail horizontal, puis panneau, puis temps.
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          SizedBox(height: 64, child: _railHorizontal(cs)),
                          const SizedBox(height: 12),
                          _centerPanel(cs, scrollable: false),
                          const SizedBox(height: 12),
                          _timeColumn(cs, scrollable: false),
                        ],
                      );
                    }),
    );
  }

  // ── Colonne 1 : le rail (qui) ───────────────────────────────────────────────

  List<_Coachee> get _railItems => _railFilter == 'traiter'
      ? _all.where((c) => c.needsAction).toList()
      : _all;

  Widget _rail(ColorScheme cs) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Row(children: [
          _railFilterChip(cs, 'tous', 'Tous · ${_all.length}'),
          const SizedBox(width: 6),
          _railFilterChip(cs, 'traiter',
              'À traiter · ${_all.where((c) => c.needsAction).length}'),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          children: [for (final c in _railItems) _railTile(cs, c)],
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Trié par ce qui a besoin de toi — jamais par ordre alphabétique.',
          style: TextStyle(
              fontSize: 10.5, color: cs.onSurface.withOpacity(.4)),
        ),
      ),
    ]);
  }

  Widget _railHorizontal(ColorScheme cs) {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final c in _railItems)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _railTile(cs, c, compact: true),
          ),
      ],
    );
  }

  Widget _railFilterChip(ColorScheme cs, String value, String label) {
    final sel = _railFilter == value;
    return ChoiceChip(
      selected: sel,
      onSelected: (_) => setState(() => _railFilter = value),
      label: Text(label),
      labelStyle: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: sel ? _kGreen : cs.onSurface.withOpacity(.6)),
      selectedColor: _kGreen.withOpacity(.12),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _railTile(ColorScheme cs, _Coachee c, {bool compact = false}) {
    final spec = _stateSpec(c);
    final sel = c.id == _selectedId;
    return Container(
      width: compact ? 190 : null,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: sel ? const Color(0xFF12241B) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: sel ? _kGreen.withOpacity(.35) : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _select(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: spec.color.withOpacity(.16),
              child: Text(c.initial,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: spec.color)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  Text(spec.pill.toLowerCase(),
                      style: TextStyle(fontSize: 11.5, color: spec.color)),
                ],
              ),
            ),
            if (c.total > 0)
              Text('${c.kept}/${c.total}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: cs.onSurface.withOpacity(.7))),
          ]),
        ),
      ),
    );
  }

  // ── Colonne 2 : le panneau central (quoi) ───────────────────────────────────

  Widget _centerPanel(ColorScheme cs, {bool scrollable = true}) {
    final c = _selected;
    if (c == null) return const SizedBox.shrink();
    final spec = _stateSpec(c);
    final action = _stateAction(c);
    final delta = c.weekPct - c.prevPct;
    final days = c.lastActivityAt == null
        ? null
        : DateTime.now().difference(c.lastActivityAt!).inDays;

    Widget chiffre(String label, String value, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: color ?? cs.onSurface)),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withOpacity(.45))),
          ],
        );

    Widget sectionLabel(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(t,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.35,
                  color: cs.onSurface.withOpacity(.45))),
        );

    final children = <Widget>[
      // En-tête : identité + les 3 chiffres de l'US-2.
      Row(children: [
        CircleAvatar(
          radius: 23,
          backgroundColor: spec.color.withOpacity(.16),
          child: Text(c.initial,
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: spec.color)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700)),
              Text(
                c.consent != 'granted'
                    ? 'Lien non actif'
                    : c.domainCount == 0
                        ? 'Rien de partagé — même pas les statuts'
                        : '${c.domainCount} domaine(s) partagé(s) · '
                            '${c.detail ? 'détail' : 'statuts seulement'}',
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurface.withOpacity(.55)),
              ),
            ],
          ),
        ),
        if (c.total > 0) ...[
          chiffre('ENGAGEMENTS · 7 J', '${c.kept} / ${c.total}',
              color: _tierColor(c.total == 0
                  ? 0
                  : ((c.kept / c.total) * 100).round())),
          const SizedBox(width: 22),
          chiffre('TENDANCE', '${delta >= 0 ? '+' : ''}$delta pts',
              color: delta >= 0 ? _kGreen : _kCoral),
          const SizedBox(width: 22),
          chiffre(
              'DERNIÈRE ACTIVITÉ',
              days == null
                  ? '—'
                  : days <= 0
                      ? 'auj.'
                      : days == 1
                          ? 'hier'
                          : '$days j',
              color: days != null && days >= 5 ? _kCoral : null),
        ],
      ]),
      const SizedBox(height: 18),

      // Bandeau d'état : la seule partie qui change de nature.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: spec.color.withOpacity(.09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: spec.color.withOpacity(.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: spec.color.withOpacity(.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(spec.pill,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: spec.color)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(spec.title,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600)),
            if (action != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: spec.color,
                    foregroundColor: const Color(0xFF07100D)),
                onPressed: () => action.$2(),
                child: Text(action.$1),
              ),
            ],
          ],
        ),
      ),

      // Ses 7 derniers jours (fenêtre glissante) : cliquer met en avant —
      // ça ordonne, ça ne filtre pas.
      sectionLabel('SES 7 DERNIERS JOURS — CLIQUE POUR METTRE EN AVANT'),
      if (c.engagements.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(.12)),
          ),
          child: Text(
            c.consent != 'granted' || c.domainCount == 0
                ? 'Aucun chiffre à joindre : rien n\'est partagé, même pas les statuts.'
                : 'Aucun engagement hebdo dans le périmètre partagé.',
            style:
                TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.5)),
          ),
        )
      else ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in c.engagements) _engagementCard(cs, e),
          ],
        ),
        if (_highlighted.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${_highlighted.length} chiffre(s) joint(s) au mot.',
                style: const TextStyle(fontSize: 11.5, color: _kGreen)),
          ),
      ],

      // Ton mot : l'app ne l'écrit jamais à ta place.
      sectionLabel('TON MOT'),
      Row(children: [
        for (final e in _tones.entries)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              selected: _tone == e.key,
              onSelected: (_) => setState(() => _tone = e.key),
              label: Text(e.value.$1),
              labelStyle: TextStyle(
                  fontSize: 11.5,
                  color: _tone == e.key
                      ? _kGreen
                      : cs.onSurface.withOpacity(.6)),
              selectedColor: _kGreen.withOpacity(.12),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
            ),
          ),
        const Spacer(),
        Text('Intro : « ${_tones[_tone]!.$2} »',
            style: TextStyle(
                fontSize: 11, color: cs.onSurface.withOpacity(.4))),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _motCtrl,
        focusNode: _motFocus,
        minLines: 4,
        maxLines: 8,
        enabled: c.consent == 'granted',
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText:
              'Ce que les chiffres ne disent pas. Sans ça, ce n\'est qu\'un bilan automatique.',
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        FilledButton(
          onPressed:
              c.consent == 'granted' && !_sending ? () => _sendMot(c) : null,
          child: Text(c.consent == 'granted'
              ? 'Envoyer le constat et le mot'
              : 'Rien à envoyer tant que le lien n\'est pas actif'),
        ),
        const SizedBox(width: 10),
        TextButton(
          onPressed: _sending ? null : () => _keepForSession(c),
          child: const Text('Garder pour la séance'),
        ),
        const Spacer(),
        // US-3 : le rapport de pré-séance — composé serveur, prêt à copier.
        TextButton.icon(
          onPressed: c.consent == 'granted' ? () => _presession(c) : null,
          icon: const Icon(Icons.description_outlined, size: 15),
          label: const Text('Rapport de pré-séance'),
        ),
      ]),
      const SizedBox(height: 24),
    ];

    final column = Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
    return scrollable
        ? ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [column])
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: column);
  }

  Widget _engagementCard(ColorScheme cs, Map<String, dynamic> e) {
    final id = e['id'].toString();
    final sel = _highlighted.contains(id);
    final kept = e['kept'] == true;
    return SizedBox(
      width: 240,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          sel ? _highlighted.remove(id) : _highlighted.add(id);
        }),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: sel ? const Color(0xFF12241B) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color:
                    sel ? _kGreen : Colors.white.withOpacity(.1)),
          ),
          child: Row(children: [
            Icon(kept ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: kept ? _kGreen : cs.onSurface.withOpacity(.35)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${e['label']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
            ),
            Text('${e['done']} / ${e['target']}',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: kept ? _kGreen : cs.onSurface.withOpacity(.7))),
          ]),
        ),
      ),
    );
  }

  // ── Colonne 3 : le temps (quand) ────────────────────────────────────────────

  Widget _timeColumn(ColorScheme cs, {bool scrollable = true}) {
    final c = _selected;
    if (c == null) return const SizedBox.shrink();

    final children = <Widget>[
      Row(children: [
        Expanded(child: _timeTab(cs, 'jour', 'Aujourd\'hui')),
        const SizedBox(width: 6),
        Expanded(child: _timeTab(cs, 'semaines', '4 semaines')),
      ]),
      const SizedBox(height: 16),
      if (_timeView == 'jour') ..._todayView(cs, c) else ..._weeksView(cs, c),
    ];

    final column = Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
    return scrollable
        ? ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [column])
        : column;
  }

  Widget _timeTab(ColorScheme cs, String value, String label) {
    final sel = _timeView == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _timeView = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? _kGreen.withOpacity(.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? _kGreen.withOpacity(.5) : Colors.white.withOpacity(.1)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: sel ? _kGreen : cs.onSurface.withOpacity(.6))),
      ),
    );
  }

  List<Widget> _todayView(ColorScheme cs, _Coachee c) {
    final blocks = ((c.dash?['todayBlocks'] as List?) ?? [])
        .map((b) => Map<String, dynamic>.from(b as Map))
        .toList();
    // L'intention du jour du coaché (onglet Objectifs) — granularité détail.
    final intention = c.dash?['intention'] as String?;
    final intentionWidget = intention == null
        ? const <Widget>[]
        : <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.flag_rounded, size: 14, color: _kGreen),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('« $intention »',
                          style: const TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
            ),
          ];
    if (!c.detail) {
      return [
        Text(
          'Partage en « statuts seulement » : le programme du jour n\'apparaît '
          'pas. Il voit ce que tu vois — rien de plus, rien d\'autre.',
          style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.5)),
        ),
      ];
    }
    if (blocks.isEmpty) {
      return [
        ...intentionWidget,
        Text('Rien de programmé aujourd\'hui (${c.dash?['date'] ?? ''}).',
            style:
                TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.5))),
      ];
    }
    return [
      ...intentionWidget,
      for (final b in blocks)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Text('${b['startTime']}',
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onSurface.withOpacity(.55))),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${b['title']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      decoration: b['status'] == 'done'
                          ? TextDecoration.lineThrough
                          : null,
                      color: cs.onSurface.withOpacity(
                          b['status'] == 'pending' ? .9 : .5))),
            ),
            if (b['status'] == 'done')
              const Icon(Icons.check, size: 14, color: _kGreen)
            else if (b['status'] == 'skipped')
              Text('sauté',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurface.withOpacity(.4))),
          ]),
        ),
      if (c.dash?['pendingIdeas'] != null) ...[
        const SizedBox(height: 10),
        Text('💡 ${c.dash?['pendingIdeas']} idée(s) dans sa boîte.',
            style:
                TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
      ],
    ];
  }

  List<Widget> _weeksView(ColorScheme cs, _Coachee c) {
    final weeks = c.weeks;
    if (weeks.isEmpty) {
      return [
        Text('Pas encore de tendance — rien n\'est partagé.',
            style:
                TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.5))),
      ];
    }
    // Libellés fournis par le serveur (S-3/S-2/S-1 calendaires + « 7 j »
    // glissants) — repli sur l'ancien schéma si absents.
    const fallback = ['S-3', 'S-2', 'S-1', 'S'];
    return [
      Row(children: [
        for (var i = 0; i < weeks.length; i++) ...[
          Expanded(
            child: Column(children: [
              Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tierColor(
                          (weeks[i]['pct'] as num?)?.toInt() ?? 0)
                      .withOpacity(.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _tierColor(
                          (weeks[i]['pct'] as num?)?.toInt() ?? 0)),
                ),
                child: Text('${weeks[i]['pct']} %',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
              const SizedBox(height: 4),
              Text(
                  (weeks[i]['label'] as String?) ??
                      (i < fallback.length ? fallback[i] : ''),
                  style: TextStyle(
                      fontSize: 10.5, color: cs.onSurface.withOpacity(.45))),
            ]),
          ),
          if (i < weeks.length - 1) const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 14),
      Text(
        '% d\'engagements tenus — semaines calendaires révolues, puis les '
        '7 derniers jours glissants. Périmètre partagé uniquement. '
        '≥ 85 vert · 60-84 ambre · < 60 corail.',
        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.4)),
      ),
    ];
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
