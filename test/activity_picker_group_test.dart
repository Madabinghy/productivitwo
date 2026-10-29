import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart';

void main() {
  test('groupActivitiesByDomain : ordre des domaines, domaine préféré en tête, sans domaine à la fin', () {
    final sante = Domain(id: 's', name: 'Santé');
    final biz = Domain(id: 'b', name: 'Business');
    final acts = [
      Activity(domainId: 'b', name: 'Réseau'),
      Activity(domainId: 's', name: 'Courir'),
      Activity(domainId: 'b', name: 'Contenu'),
      Activity(domainId: 'x', name: 'Orpheline'),
    ];
    final g = groupActivitiesByDomain(acts, [sante, biz]);
    expect(g.map((e) => e.name), ['Santé', 'Business', 'Sans domaine']);
    expect(g[1].activities.map((a) => a.name), ['Contenu', 'Réseau']);
    final pref = groupActivitiesByDomain(acts, [sante, biz], preferDomainId: 'b');
    expect(pref.first.name, 'Business');
  });
}
