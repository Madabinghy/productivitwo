import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/onboarding_slots.dart';
import 'package:productivitwo_v1/widgets/domain_naming_sheet.dart';
import 'package:productivitwo_v1/widgets/domain_session_screen.dart';

/// Onboarding domaines (maquettes 18a/18b) : NOMMER D'ABORD, DÉFINIR ENSUITE.
/// 18a — nommer 3 domaines max (nom + couleur + rang), 2 min, garde-fou sur le
/// 4ᵉ. Écrit des docs domaine `definitionStatus: "named"` — un domaine `named`
/// n'existe pas pour le coach (aucun vital inventé). 18b — UNE session lancée
/// (rang 1) ; les autres posées comme de VRAIS engagements dans la semaine
/// (blocs kind:"session"), visibles du check-in comme les autres.
class DomainOnboardingScreen extends StatefulWidget {
  final AppLogic logic;
  const DomainOnboardingScreen({super.key, required this.logic});

  @override
  State<DomainOnboardingScreen> createState() => _DomainOnboardingScreenState();
}

enum _Stage { naming, sessions }

class _Row {
  final TextEditingController ctrl;
  int colorIdx;
  _Row(String initial, this.colorIdx)
      : ctrl = TextEditingController(text: initial);
}

// Palette partagée avec le nommage in-place (22a).
const _kPalette = kDomainPalette;

class _DomainOnboardingScreenState extends State<DomainOnboardingScreen> {
  final _sync = FirestoreSync();
  _Stage _stage = _Stage.naming;
  final List<_Row> _rows = [_Row('', 0)];
  bool _saving = false;

  // ── 18b ─────────────────────────────────────────────────────────────────────
  List<Domain> _others = const [];
  List<DateTime> _slots = const [];
  String? _firstName;
  bool _firstDefined = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.ctrl.dispose();
    }
    super.dispose();
  }

  List<String> get _names => _rows
      .map((r) => r.ctrl.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _addRow() async {
    if (_rows.length >= 3) {
      // Garde-fou sur le 4ᵉ : possible, mais on le dit en face.
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Vraiment ?', style: TextStyle(fontSize: 16)),
          content: const Text(
              'Trois max — un domaine que tu ne défends pas n\'est pas un domaine, '
              'c\'est une liste de souhaits. Deux suffisent si c\'est ta vérité.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Tu as raison')),
            TextButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('J\'assume un 4ᵉ')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _rows.add(_Row('', _rows.length % _kPalette.length)));
  }

  /// Écrit les domaines nommés (sans doublonner un domaine existant), lance la
  /// session du n° 1, puis passe à la pose des sessions des autres (18b).
  Future<void> _start() async {
    if (_saving || _names.isEmpty) return;
    setState(() => _saving = true);
    try {
      // Même chemin d'écriture que le nommage in-place (22a) — une seule
      // implémentation pour les deux entrées.
      final created = saveNamedDomains(widget.logic, [
        for (final r in _rows)
          if (r.ctrl.text.trim().isNotEmpty)
            (name: r.ctrl.text.trim(), color: _kPalette[r.colorIdx]),
      ]);

      _firstName = created.first.name;
      _others = created.skip(1).toList();
      _slots = definitionSessionSlots(DateTime.now(), _others.length);

      if (!mounted) return;
      setState(() => _saving = false);
      // Le n° 1 se définit MAINTENANT — les autres attendront leur session.
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            DomainSessionScreen(logic: widget.logic, domainName: _firstName!),
      ));
      if (!mounted) return;
      if (_others.isEmpty) {
        Navigator.pop(context);
        return;
      }
      // La fiche a-t-elle été finalisée ? (bannière « le coach est opérationnel »)
      try {
        final fresh = await _sync.fetchDomains();
        _firstDefined = fresh.any((d) =>
            d.name.trim().toLowerCase() == _firstName!.trim().toLowerCase() &&
            d.isDefined);
      } catch (_) {}
      if (mounted) setState(() => _stage = _Stage.sessions);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editSlot(int i) async {
    final now = DateTime.now();
    final current = _slots[i];
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null || !mounted) return;
    setState(() {
      _slots = [..._slots];
      _slots[i] =
          DateTime(day.year, day.month, day.day, time.hour, time.minute);
    });
  }

  /// « Ça me va » — pose les sessions comme de vrais engagements (kind:session).
  Future<void> _confirmSlots() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      for (var i = 0; i < _others.length; i++) {
        final d = _others[i];
        final slot = _slots[i];
        await _sync.addScheduleBlock(
          _ymd(slot),
          ScheduleBlock(
            startTime:
                '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}',
            durationMin: 20,
            title: 'Définir « ${d.name} » avec Orion',
            category: 'personal',
            kind: 'session',
            domainId: d.id,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — rien n\'a été posé, réessaie.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tes domaines',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(
              _stage == _Stage.naming
                  ? 'ONBOARDING · NOMMER D\'ABORD, DÉFINIR ENSUITE'
                  : 'ONBOARDING · LES AUTRES SESSIONS, CETTE SEMAINE',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: cs.primary),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children:
            _stage == _Stage.naming ? _namingBody(cs) : _sessionsBody(cs),
      ),
    );
  }

  // ── 18a — nommer ─────────────────────────────────────────────────────────────

  List<Widget> _namingBody(ColorScheme cs) {
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withOpacity(.25)),
          color: cs.primary.withOpacity(.05),
        ),
        child: Text(
          'Trois max — un domaine que tu ne défends pas n\'est pas un domaine, '
          'c\'est une liste de souhaits. Deux suffisent si c\'est ta vérité.',
          style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: cs.onSurface.withOpacity(.85)),
        ),
      ),
      const SizedBox(height: 14),
      for (var i = 0; i < _rows.length; i++) _nameRow(cs, i),
      OutlinedButton(
        onPressed: _addRow,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: cs.onSurface.withOpacity(.2)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          _rows.length >= 3 ? '+ un autre (vraiment ?)' : '+ un autre',
          style: TextStyle(
              fontSize: 13, color: cs.onSurface.withOpacity(.55)),
        ),
      ),
      const SizedBox(height: 14),
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'L\'ordre compte : on définit le n° 1 '),
          const TextSpan(
              text: 'maintenant',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const TextSpan(
              text: '. Les autres, cette semaine — je te propose quand.'),
        ]),
        style: TextStyle(
            fontSize: 12.5, height: 1.4, color: cs.onSurface.withOpacity(.6)),
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: _saving || _names.isEmpty ? null : _start,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: Text(_names.isEmpty
            ? 'Nomme au moins un domaine'
            : 'Définir « ${_names.first} » — 15 min'),
      ),
    ];
  }

  Widget _nameRow(ColorScheme cs, int i) {
    final r = _rows[i];
    final color = Color(_kPalette[r.colorIdx]);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: i == 0 && r.ctrl.text.trim().isNotEmpty
                ? cs.primary.withOpacity(.6)
                : cs.onSurface.withOpacity(.15)),
      ),
      child: Row(
        children: [
          // Pastille couleur — tap = couleur suivante de la palette.
          GestureDetector(
            onTap: () => setState(
                () => r.colorIdx = (r.colorIdx + 1) % _kPalette.length),
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              child: Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: r.ctrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: i == 0
                    ? 'Santé'
                    : i == 1
                        ? 'Business'
                        : 'Perso — couple & amis',
              ),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Text(
            i == 0 ? '1 — ça urge' : '${i + 1}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color:
                    i == 0 ? cs.primary : cs.onSurface.withOpacity(.4)),
          ),
        ],
      ),
    );
  }

  // ── 18b — poser les autres sessions ─────────────────────────────────────────

  List<Widget> _sessionsBody(ColorScheme cs) {
    return [
      if (_firstDefined)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: cs.primary.withOpacity(.12),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('$_firstName défini — le coach est opérationnel',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withOpacity(.25)),
          color: cs.primary.withOpacity(.05),
        ),
        child: Text(
          'On ne fait pas tout ce soir — une définition à la va-vite ne vaut '
          'rien. Je pose ${_others.length > 1 ? 'les autres' : 'l\'autre'} comme '
          'de vraies sessions, dans ta semaine :',
          style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: cs.onSurface.withOpacity(.85)),
        ),
      ),
      const SizedBox(height: 14),
      for (var i = 0; i < _others.length; i++) _sessionRow(cs, i),
      const SizedBox(height: 6),
      Text(
        'Ce sont des engagements comme les autres : s\'ils sautent, on en '
        'parlera au check-in — le système commence ce soir. Tape un créneau '
        'pour le changer.',
        style: TextStyle(
            fontSize: 12, height: 1.4, color: cs.onSurface.withOpacity(.55)),
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: _saving ? null : _confirmSlots,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: Text(_saving ? 'Enregistrement…' : 'Ça me va'),
      ),
    ];
  }

  Widget _sessionRow(ColorScheme cs, int i) {
    final d = _others[i];
    final slot = _slots[i];
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _editSlot(i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.onSurface.withOpacity(.15)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(
                slotShortLabel(slot),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: slot.weekday == DateTime.sunday
                        ? cs.error
                        : cs.tertiary),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Définir « ${d.name} » avec Orion',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('20 min · ${slotRationale(slot)}',
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
            Icon(Icons.swap_vert_rounded,
                size: 18, color: cs.onSurface.withOpacity(.35)),
          ],
        ),
      ),
    );
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
