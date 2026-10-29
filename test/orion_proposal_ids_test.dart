import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';

/// Une proposition qui regroupe plusieurs idées les consomme toutes.
void main() {
  test('OrionProposal.captureIds : toutes les idées regroupées, anciennes propositions comprises', () {
    final grouped = OrionProposal.from({'id': 'p', 'kind': 'new_project', 'title': 't', 'sourceCaptureId': 'a', 'sourceCaptureIds': ['a', 'b', 'c']});
    expect(grouped.captureIds, {'a', 'b', 'c'});
    final legacy = OrionProposal.from({'id': 'q', 'kind': 'new_project', 'title': 't', 'sourceCaptureId': 'a'});
    expect(legacy.captureIds, {'a'});
  });
}
