import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/widgets/focus_day_sheet.dart';

void main() {
  test('nextMonday : lundi strictement après aujourd\'hui', () {
    expect(nextMonday(DateTime(2026, 10, 30, 9)), DateTime(2026, 11, 2)); // vendredi → lundi
    expect(nextMonday(DateTime(2026, 11, 1)), DateTime(2026, 11, 2)); // dimanche → lundi
    expect(nextMonday(DateTime(2026, 11, 2)), DateTime(2026, 11, 9)); // lundi → le suivant
  });
}
