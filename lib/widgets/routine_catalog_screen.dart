import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/catalog/routine_catalog.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;

/// Catalogue de routines (maquette validée 2026-11-01) : les routines
/// composées par l'administrateur, chacune avec sa carte illustrée, rangées
/// par rubrique ; tap = la fiche (texte, réglages de départ, domaine) et
/// « Activer la routine » (ou « Lier la carte » quand la personne a déjà une
/// routine du même nom). Logique : `catalog/routine_catalog.dart`.
Future<void> showRoutineCatalog(BuildContext context, {required AppLogic logic, required FirestoreSync sync, VoidCallback? onSuggestions}) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoutineCatalogScreen(logic: logic, sync: sync, onSuggestions: onSuggestions)));
}

/// Une carte du catalogue : cadre neutre, dessin sur son fond, nom.
class CatalogCardView extends StatelessWidget {
  final CatalogRoutine routine;
  final double width;
  final bool activated;
  const CatalogCardView({super.key, required this.routine, this.width = 100, this.activated = false});

  @override
  Widget build(BuildContext context) {
    final c = routine;
    final w = width;
    return SizedBox(
      width: w,
      height: w * 7 / 5,
      child: Container(
        padding: EdgeInsets.all(w * .04),
        decoration: BoxDecoration(color: const Color(0xFF2A3A33), borderRadius: BorderRadius.circular(w * .11)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(w * .08),
          child: Stack(children: [
            Container(
              color: const Color(0xFF101A15),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: RadialGradient(center: const Alignment(0, -.1), radius: .9, colors: [Color(c.bg), const Color(0xFF101A15)])),
                    child: Padding(padding: EdgeInsets.all(w * .14), child: SvgPicture.string(c.svg)),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(w * .07, w * .03, w * .07, w * .06),
                  child: Text(c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: (w * .095).clamp(8, 18).toDouble(), height: 1.15, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ]),
            ),
            if (activated)
              Positioned(
                top: w * .06,
                right: w * .06,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: w * .04, vertical: w * .01),
                  decoration: BoxDecoration(color: const Color(0xFF3DDC84), borderRadius: BorderRadius.circular(w * .04)),
                  child: Text('ACTIVÉE', style: TextStyle(fontSize: (w * .065).clamp(7, 11).toDouble(), fontWeight: FontWeight.w800, color: const Color(0xFF062A14))),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class RoutineCatalogScreen extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final VoidCallback? onSuggestions;
  const RoutineCatalogScreen({super.key, required this.logic, required this.sync, this.onSuggestions});

  @override
  State<RoutineCatalogScreen> createState() => _RoutineCatalogScreenState();
}

class _RoutineCatalogScreenState extends State<RoutineCatalogScreen> {
  List<CatalogRoutine> _all = catalogOrSeed(const []);
  String? _rubric;

  @override
  void initState() {
    super.initState();
    widget.sync.fetchRoutineCatalog().then((remote) {
      if (mounted && remote.isNotEmpty) setState(() => _all = catalogOrSeed(remote));
    });
  }

  bool _activated(CatalogRoutine c) => catalogMatch(c, widget.logic.state.activities).linked != null;

  @override
  Widget build(BuildContext context) {
    final rubrics = [for (final r in kCatalogRubrics) if (_all.any((c) => c.rubric == r)) r, ...{for (final c in _all) if (!kCatalogRubrics.contains(c.rubric)) c.rubric}];
    final shown = _rubric == null ? rubrics : [_rubric!];
    final active = _all.where(_activated).length;
    final w = (MediaQuery.sizeOf(context).width - 32 - 2 * 10) / 3;
    return Scaffold(
      backgroundColor: kBBg,
      appBar: AppBar(backgroundColor: kBBar, foregroundColor: kBText, title: const Text('Catalogue')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Text('${_all.length} routines · $active activée${active > 1 ? 's' : ''}', style: const TextStyle(fontSize: 13, color: kBText3)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final r in [null, ...rubrics])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(r ?? 'Tout'),
                  selected: _rubric == r,
                  onSelected: (_) => setState(() => _rubric = r),
                  selectedColor: kBadgeGold,
                  labelStyle: TextStyle(color: _rubric == r ? const Color(0xFF2A2312) : kBText2, fontWeight: FontWeight.w700),
                  backgroundColor: kBSurface,
                  side: const BorderSide(color: kBLine),
                ),
              ),
          ]),
        ),
        for (final r in shown) ...[
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 8),
            child: Row(children: [
              Text(r.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: kBText3)),
              const Spacer(),
              Text('${_all.where((c) => c.rubric == r).length}', style: const TextStyle(fontSize: 12, color: kBText4)),
            ]),
          ),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in _all.where((c) => c.rubric == r))
              GestureDetector(
                onTap: () => _open(c),
                child: CatalogCardView(routine: c, width: w, activated: _activated(c)),
              ),
          ]),
        ],
        if (widget.onSuggestions != null) ...[
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: widget.onSuggestions,
            icon: const Icon(Icons.library_add_outlined),
            label: const Text('Domaines et activités suggérés'),
            style: TextButton.styleFrom(foregroundColor: kBText2),
          ),
        ],
      ]),
    );
  }

  Future<void> _open(CatalogRoutine c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBSurface,
      showDragHandle: true,
      builder: (_) => _CatalogRoutineSheet(routine: c, logic: widget.logic),
    );
    if (mounted) setState(() {});
  }
}

class _CatalogRoutineSheet extends StatefulWidget {
  final CatalogRoutine routine;
  final AppLogic logic;
  const _CatalogRoutineSheet({required this.routine, required this.logic});

  @override
  State<_CatalogRoutineSheet> createState() => _CatalogRoutineSheetState();
}

class _CatalogRoutineSheetState extends State<_CatalogRoutineSheet> {
  late String? _domainId = domainForRubric(widget.routine.rubric, widget.logic.state.activeDomains);

  AppLogic get logic => widget.logic;

  void _activate() {
    final d = _domainId;
    if (d == null) return;
    logic.state.activities.add(activityFromCatalog(widget.routine, d));
    logic.onChange();
    _done('« ${widget.routine.name} » activée · retrouve-la dans tes routines');
  }

  void _link(Activity a) {
    a.catalogId = widget.routine.id;
    logic.onChange();
    _done('« ${a.name} » porte maintenant sa carte du catalogue');
  }

  void _done(String msg) {
    final m = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    m.showClosingSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Text(k, style: const TextStyle(fontSize: 14, color: kBText2)),
          const Spacer(),
          Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.routine;
    final m = catalogMatch(c, logic.state.activities);
    final domains = logic.state.activeDomains;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: CatalogCardView(routine: c, width: 150, activated: m.linked != null)),
          const SizedBox(height: 10),
          Text(c.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBText)),
          Text('${c.rubric} · ${c.cadence} · ${momentLabel(c)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: kBText3)),
          if (c.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kBBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBLine)),
              child: Text(c.text, style: const TextStyle(fontSize: 14, height: 1.45, color: kBText)),
            ),
          ],
          const SizedBox(height: 14),
          const Text('RÉGLÉE POUR TOI', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: kBText3)),
          _row('Cible', c.cadence),
          _row('Moment', momentLabel(c)),
          if (c.timerMin != null) _row('Minuteur', '${c.timerMin} min'),
          if (m.linked == null && m.sameName == null && domains.isNotEmpty)
            Row(children: [
              const Text('Domaine', style: TextStyle(fontSize: 14, color: kBText2)),
              const Spacer(),
              DropdownButton<String>(
                value: _domainId,
                dropdownColor: kBSurface,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText),
                items: [for (final d in domains) DropdownMenuItem(value: d.id, child: Text(d.name))],
                onChanged: (v) => setState(() => _domainId = v),
              ),
            ]),
          const SizedBox(height: 4),
          const Text('Tu pourras tout changer ensuite dans la fiche de la routine.', style: TextStyle(fontSize: 12, color: kBText4)),
          const SizedBox(height: 14),
          if (m.linked != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF3DDC84).withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Text('Déjà dans tes routines : « ${m.linked!.name} ».', style: const TextStyle(fontSize: 14, color: kBText)),
            )
          else if (m.sameName != null) ...[
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => _link(m.sameName!),
                style: FilledButton.styleFrom(backgroundColor: kBadgeGold, foregroundColor: const Color(0xFF2A2312), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('C’est ma routine « ${m.sameName!.name} » · lier la carte', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Ta routine garde ses réglages ; elle prend seulement le dessin de cette carte.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: kBText4)),
          ] else
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _domainId == null ? null : _activate,
                style: FilledButton.styleFrom(backgroundColor: kBadgeGold, foregroundColor: const Color(0xFF2A2312), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Activer la routine', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
    );
  }
}

const kBadgeGold = Color(0xFFFFD36A);
