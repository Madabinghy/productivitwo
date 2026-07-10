import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

/// Nommage in-place (Partie D, maquettes 22a/22b) : bottom sheet par-dessus
/// Maintenant — jamais de navigation vers un écran qu'il faudrait connaître.
/// MÊME chemin d'écriture que l'onboarding 18a ([saveNamedDomains]) : docs
/// domaine `definitionStatus: "named"`, sans doublonner, sans rétrograder.

// Palette partagée 18a/22a (vert / violet / corail, puis rotation).
const kDomainPalette = [0xFF2BC48A, 0xFF8B7CF6, 0xFFF07167, 0xFFF4A261, 0xFF4CC9F0];

/// Écrit les domaines nommés — réutilise un domaine existant du même nom
/// (insensible à la casse), ne rétrograde jamais un domaine déjà en session ou
/// défini, pose `namedAt` (« nommé depuis N j », 21c). Retourne les domaines
/// dans l'ordre des rangs.
List<Domain> saveNamedDomains(
    AppLogic logic, List<({String name, int color})> entries) {
  final out = <Domain>[];
  for (final e in entries) {
    final name = e.name.trim();
    if (name.isEmpty) continue;
    Domain? d;
    for (final existing in logic.state.activeDomains) {
      if (existing.name.trim().toLowerCase() == name.toLowerCase()) {
        d = existing;
        break;
      }
    }
    d ??= logic.createDomain(name);
    d.colorValue ??= e.color;
    if (d.definitionStatus == 'none') {
      d.definitionStatus = 'named';
      d.namedAt = DateTime.now();
    }
    out.add(d);
  }
  logic.onChange();
  return out;
}

/// Ouvre le sheet de nommage. Retourne les domaines nommés (ordre = rang) ou
/// null si l'utilisateur a fermé sans valider.
Future<List<Domain>?> showDomainNamingSheet(
  BuildContext context, {
  required AppLogic logic,
}) {
  return showModalBottomSheet<List<Domain>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NamingSheet(logic: logic),
  );
}

class _Row {
  final TextEditingController ctrl;
  int colorIdx;
  _Row(String initial, this.colorIdx)
      : ctrl = TextEditingController(text: initial);
}

class _NamingSheet extends StatefulWidget {
  final AppLogic logic;
  const _NamingSheet({required this.logic});

  @override
  State<_NamingSheet> createState() => _NamingSheetState();
}

class _NamingSheetState extends State<_NamingSheet> {
  final List<_Row> _rows = [_Row('', 0)];
  static const _suggestions = ['Santé', 'Business', 'Perso', 'Famille'];

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

  void _fillSuggestion(String name) {
    // La chip remplit la première ligne vide (ou en ajoute une, 3 max).
    for (final r in _rows) {
      if (r.ctrl.text.trim().isEmpty) {
        setState(() => r.ctrl.text = name);
        return;
      }
    }
    if (_rows.length < 3) {
      setState(() => _rows.add(_Row(name, _rows.length % kDomainPalette.length)));
    }
  }

  Future<void> _addRow() async {
    if (_rows.length >= 3) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Vraiment ?', style: TextStyle(fontSize: 16)),
          content: const Text(
              'Un domaine que tu ne défends pas n\'est pas un domaine, c\'est '
              'une liste de souhaits. Deux suffisent si c\'est ta vérité.'),
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
    setState(() => _rows.add(_Row('', _rows.length % kDomainPalette.length)));
  }

  void _validate() {
    final entries = <({String name, int color})>[
      for (final r in _rows)
        if (r.ctrl.text.trim().isNotEmpty)
          (name: r.ctrl.text.trim(), color: kDomainPalette[r.colorIdx]),
    ];
    if (entries.isEmpty) return;
    final domains = saveNamedDomains(widget.logic, entries);
    Navigator.pop(context, domains);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = _names.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Tes domaines',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                  n >= 2 ? '$n / 3 · L\'ORDRE COMPTE' : 'NOMMER · ~2 MIN',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: cs.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Un mot suffit — on définira après. Domaine 1 : celui qui urge le plus.',
              style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: cs.onSurface.withOpacity(.7)),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _rows.length; i++) _nameRow(cs, i),
            OutlinedButton(
              onPressed: _addRow,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                side: BorderSide(color: cs.onSurface.withOpacity(.2)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _rows.length >= 3 ? '+ un autre (vraiment ?)' : '+ un autre',
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withOpacity(.55)),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final s in _suggestions)
                  if (!_names
                      .any((x) => x.toLowerCase() == s.toLowerCase()))
                    ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 12.5)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _fillSuggestion(s),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Un domaine que tu ne défends pas n\'est pas un domaine. Deux suffisent si c\'est ta vérité — le rang dit qui passe en premier quand ça frotte.',
              style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: cs.onSurface.withOpacity(.55)),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: n == 0 ? null : _validate,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
              child: Text(n == 0
                  ? 'Nomme au moins un domaine'
                  : 'C\'est nommé — $n domaine${n > 1 ? 's' : ''}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nameRow(ColorScheme cs, int i) {
    final r = _rows[i];
    final color = Color(kDomainPalette[r.colorIdx]);
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
          GestureDetector(
            onTap: () => setState(
                () => r.colorIdx = (r.colorIdx + 1) % kDomainPalette.length),
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
              autofocus: i == 0,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: i == 0 ? 'Santé' : i == 1 ? 'Business' : 'Perso',
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
                color: i == 0 ? cs.primary : cs.onSurface.withOpacity(.4)),
          ),
        ],
      ),
    );
  }
}
