import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/catalog/routine_catalog.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/routine_catalog_screen.dart';

void main() {
  test('le premier lot : ids uniques, rubriques connues, triés', () {
    final ids = kRoutineCatalogSeed.map((c) => c.id).toSet();
    expect(ids.length, kRoutineCatalogSeed.length);
    expect(kRoutineCatalogSeed.every((c) => kCatalogRubrics.contains(c.rubric)), isTrue);
    final list = catalogOrSeed(const []);
    expect(list.first.rubric, 'Santé');
    expect(list.last.rubric, 'Travail');
  });

  test('aller-retour JSON, routine non publiée écartée', () {
    final c = kRoutineCatalogSeed.firstWhere((c) => c.id == 'pompes');
    final back = CatalogRoutine.from(c.toJson())!;
    expect(back.target, 20);
    expect(back.splitMoments, ['morning', 'evening']);
    expect(CatalogRoutine.from({...c.toJson(), 'published': false}), isNull);
  });

  test('correspondance : lien par catalogId, sinon même nom', () {
    final c = kRoutineCatalogSeed.firstWhere((c) => c.id == 'pompes');
    final mine = Activity(domainId: 'd', name: 'Pompes', type: 'habit');
    expect(catalogMatch(c, [mine]).sameName, mine);
    mine.catalogId = 'pompes';
    expect(catalogMatch(c, [mine]).linked, mine);
    expect(catalogMatch(kRoutineCatalogSeed.firstWhere((c) => c.id == 'lecture'), [Activity(domainId: 'd', name: 'Lecture', type: 'time')]).sameName, isNull);
  });

  test('activer : la routine réglée, rattachée au domaine de la rubrique', () {
    final domains = [Domain(name: 'Business'), Domain(name: 'Musculation')];
    final c = kRoutineCatalogSeed.firstWhere((c) => c.id == 'pompes');
    final d = domainForRubric('Sport', domains);
    expect(d, domains[1].id);
    final a = activityFromCatalog(c, d!);
    expect(a.isHabit, isTrue);
    expect(a.habitTarget, 20);
    expect(a.splitMoments, ['morning', 'evening']);
    expect(a.catalogId, 'pompes');
    expect(Activity.from(a.toJson()).catalogId, 'pompes');
    expect(momentLabel(c), 'matin et soir');
  });

  testWidgets('chaque dessin du premier lot s’affiche', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: Wrap(children: [for (final c in kRoutineCatalogSeed) CatalogCardView(routine: c, width: 120)]))),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNWidgets(kRoutineCatalogSeed.length));
    expect(tester.takeException(), isNull);
  });
}
