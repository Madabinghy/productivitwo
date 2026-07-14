import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_match.dart';

void main() {
  final acts = [
    Activity(id: 'r1', name: 'Vitamines', domainId: 'd1', type: 'habit'),
    Activity(id: 'r2', name: 'Hygiène du soir', domainId: 'd1', type: 'habit'),
    Activity(id: 'a1', name: 'Sport', domainId: 'd1'), // activité temps, ignorée
  ];

  test('bloc sans lien → routine du même nom (accents/casse ignorés)', () {
    expect(routineForBlockTitle('Vitamines', acts)?.id, 'r1');
    expect(routineForBlockTitle('vitamines du matin', acts)?.id, 'r1');
    expect(routineForBlockTitle('Hygiene du soir', acts)?.id, 'r2');
  });

  test('zéro ou plusieurs candidates → pas de lien deviné', () {
    expect(routineForBlockTitle('Réunion équipe', acts), isNull);
    expect(
        routineForBlockTitle('Vitamines + hygiène du soir', acts), isNull);
    // Une activité TEMPS du même nom ne compte pas comme routine.
    expect(routineForBlockTitle('Sport', acts), isNull);
  });
}
