import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/moment_card.dart';
import 'package:productivitwo_v1/widgets/status_row.dart';

/// « Une carte, une fiche » : aucun texte long ne doit déborder (RenderFlex)
/// sur un petit écran (360 px) — la carte du moment, la ligne, la fiche.
const long = 'Corriger les contrôles de soustractions posées et préparer la remédiation pour la séance de vendredi';
const longSub = 'CM — Nombres et calculs › 📝 Préparer — Séance du 30 oct · ⚑ éch. −3 j · ≈ 45 min · ⏱ 1h05 passées · @bureau @école';

Widget app(Widget child, {double width = 360}) => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, colorScheme: ColorScheme.fromSeed(seedColor: kBPrimary, brightness: Brightness.dark, surface: kBBg), useMaterial3: true),
      home: Scaffold(body: Center(child: SizedBox(width: width, child: ListView(padding: const EdgeInsets.all(8), children: [child])))),
    );

void main() {
  _momentCardLinksTests();
  testWidgets('MomentCard : titre, contexte, bouton et pastille longs', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(app(MomentCard(
      accent: kBPrimary,
      eyebrow: 'ACTION DU MOMENT',
      pill: 'bloc en cours · 14:00 → 15:30 · reste 52 min',
      ring: .4,
      ringBig: '2 / 5',
      ringSmall: 'ÉTAPES',
      context_: longSub,
      contextIcon: Icons.account_tree_outlined,
      title: long,
      sub: longSub,
      primaryLabel: 'Étape faite : $long',
      primaryIcon: Icons.check_rounded,
      onPrimary: () {},
      onFiche: () {},
      chainLabel: 'Enchaîner · 12 choses pour cet objectif qui a un titre vraiment très long',
      onChain: () {},
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('StatusRow : titre et sous-ligne longs, chip long', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(app(Column(children: [
      StatusRow(leading: const Icon(Icons.flag), title: long, sub: longSub, bar: (done: 3, total: 10, expected: 5), pct: 60, chip: 'au point mort · 12 j', onTap: () {}),
      const SizedBox(height: 8),
      StatusRow(leading: const Icon(Icons.flag), title: long, sub: longSub, delta: '−12 h 40 sur le plan', onTap: () {}),
      const SizedBox(height: 8),
      StatusRow(leading: const Icon(Icons.flag), title: long, trailing: TextButton(onPressed: () {}, child: const Text('Réactiver')), onTap: () {}),
      ListSectionTitle('UNE SECTION AU TITRE INTERMINABLE QUI NE TIENT PAS SUR UNE LIGNE DE 360 PX', action: 'Tout afficher', onAction: () {}),
    ])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fiche : en-tête, titres de section, étapes, gestes', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(app(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FicheHeader(title: long, chip: 'chrono en cours · reste 52 min', chipColor: kBPrimary, kpi: longSub, leading: const Icon(Icons.play_circle_fill)),
      FicheTitle('CETTE SEMAINE · LES MOYENS ET LES ROUTINES', trailing: FicheDelta('3 actions avant la séance de vendredi', color: kBPrimary)),
      FicheStep(title: long, detail: longSub, current: true, onTap: () {}, trailing: const Icon(Icons.play_circle_outline)),
      const FicheNote(longSub),
      FicheActions(primaryLabel: 'Définir la prochaine action', onPrimary: () {}, secondary: [
        (label: 'Plan d\'action', onTap: () {}),
        (label: 'Mettre en veille', onTap: () {}),
        (label: 'Rattacher à un projet', onTap: () {}),
      ]),
    ])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

void _momentCardLinksTests() {
  testWidgets('MomentCard : visuel, liens sous le bouton, feuille « Autres »', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    var tapped = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MomentCard(
            accent: Colors.green,
            eyebrow: 'ACTION DU MOMENT',
            ring: .4,
            ringBig: '2 / 5',
            ringSmall: 'ÉTAPES',
            title: 'Corriger les copies',
            sub: 'au programme · 14:00',
            visual: const MomentLegend('Étape en cours : Sloann', right: '⏱ 31 min'),
            primaryLabel: 'Étape faite',
            onPrimary: () => tapped = 'primary',
            onFiche: () => tapped = 'fiche',
            chainLabel: 'Enchaîner · 4',
            onChain: () => tapped = 'chain',
            moreActions: [MomentAction('Chrono', icon: Icons.play_arrow_rounded, onTap: () => tapped = 'chrono')],
          ),
        ),
      ),
    ));
    expect(find.text('Étape en cours : Sloann'), findsOneWidget);
    expect(find.text('⋯ Autres'), findsNothing);
    await tester.tap(find.text('Fiche'));
    expect(tapped, 'fiche');
    await tester.tap(find.text('Enchaîner · 4'));
    expect(tapped, 'chain');
    // Geste rare = bouton rond à icône, libellé en infobulle.
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(tapped, 'chrono');
    expect(find.byTooltip('Chrono'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MomentActionIcons : cinq ronds au plus, « ⋯ » compris, icônes distinctes', (tester) async {
    final tapped = <String>[];
    MomentAction a(String l, IconData i) => MomentAction(l, icon: i, onTap: () => tapped.add(l));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MomentActionIcons(title: 'T', actions: [
          a('Chrono A', Icons.play_arrow_rounded),
          a('Chrono B', Icons.play_arrow_rounded), // même icône → derrière « ⋯ »
          a('Fait', Icons.check_circle_outline),
          a('Viser', Icons.wb_sunny_outlined),
          a('Caser', Icons.event_rounded),
          a('Projet', Icons.account_tree_outlined),
          a('Sixième', Icons.bolt_rounded), // au-delà de 5 → derrière « ⋯ »
        ]),
      ),
    ));
    expect(find.byType(OutlinedButton), findsNWidgets(5)); // 4 + « ⋯ » : cinq ronds au plus
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Chrono B'), findsOneWidget);
    expect(find.text('Projet'), findsOneWidget);
    expect(find.text('Sixième'), findsOneWidget);
    await tester.tap(find.text('Chrono B'));
    await tester.pumpAndSettle();
    expect(tapped, ['Chrono B']);
    expect(tester.takeException(), isNull);
  });
}
