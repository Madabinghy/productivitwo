import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/hour_segments.dart';

void main() {
  test('tranches dans l\'ordre des domaines', () {
    expect(hourSegments({'b': 20, 'a': 40}, ['a', 'b']), [('a', 40), ('b', 20)]);
    expect(hourSegments({'b': 20, 'a': 40}, ['b', 'a']), [('b', 20), ('a', 40)]);
  });

  test('pilule : une tranche courte se fond dans la plus grosse', () {
    expect(hourSegments({'a': 40, 'b': 5, 'c': 15}, ['a', 'b', 'c'], mergeBelow: 10), [('a', 45), ('c', 15)]);
    expect(hourSegments({'a': 5}, ['a'], mergeBelow: 10), [('a', 5)]);
    expect(hourSegments({}, ['a']), isEmpty);
  });
}
