import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/focus_gauge.dart';
import 'package:productivitwo_v1/utils/half_days.dart';
import 'package:productivitwo_v1/widgets/focus_gauge_guide.dart';

void main() {
  final a = Activity(id: 'm', domainId: 'd', name: 'Bain de mer', goalMin: 10);

  test('histoire de la jauge avec les chiffres de l’activité', () {
    final s = FocusGaugeStory.of(ActivityPace(a, 49, 70, todayMin: 23));
    expect(s.pastMin, 26);
    expect(s.targetMin, 44);
    expect(s.ringPct, 52);
    expect(s.lateMin, 34);
    expect(s.endLine, contains('1h10'));
    expect(s.tickLine, contains('26 min'));
    expect(s.targetLine, contains('44 min'));
    expect(s.targetLine, contains('34 min de retard'));
    expect(s.verdict, contains('encore 21 min'));
  });

  test('exemple préféré : trait avancé et du temps aujourd’hui', () {
    final b = Activity(id: 'b', domainId: 'd', name: 'B', goalMin: 10);
    final c = Activity(id: 'c', domainId: 'd', name: 'C', goalMin: 10);
    final ex = pickGaugeExample([
      ActivityPace(b, 0, 70),
      ActivityPace(c, 30, 70, todayMin: 10),
      ActivityPace(a, 75, 70),
    ]);
    expect(ex?.activity.id, 'c');
    expect(pickGaugeExample(const []), isNull);
  });

  testWidgets('tuto : la ligne, cinq étapes, le verdict', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FocusGaugeGuide(story: FocusGaugeStory.of(ActivityPace(a, 49, 70, todayMin: 23)), color: Colors.teal)),
    ));
    expect(find.text('Avec ta ligne « Bain de mer »'), findsOneWidget);
    expect(find.byType(GaugeBar), findsNWidgets(5));
    await tester.scrollUntilVisible(find.text('Compris'), 200);
    expect(find.textContaining('En clair'), findsOneWidget);
  });
}
