import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/world_map_gen.dart';

void main() {
  test('overworld vide → carte minimale', () {
    final m = generateOverworld(const []);
    expect(m.regions, isEmpty);
    expect(m.walkable(m.start.x, m.start.y), isFalse); // pas de terre
  });

  test('chaque domaine a une région non vide + spawn praticable', () {
    final m = generateOverworld(const [
      DomainWeight('sante', 0xFF4F8DF7, 3),
      DomainWeight('travail', 0xFFE0A030, 8),
      DomainWeight('perso', 0xFF50C878, 2),
    ]);
    expect(m.regions.length, 3);
    for (final r in m.regions) {
      expect(r.size, greaterThan(0), reason: '${r.domainId} doit avoir des cases');
    }
    expect(m.walkable(m.start.x, m.start.y), isTrue);
  });

  test('taille de région ∝ poids (le plus lourd domine)', () {
    final m = generateOverworld(const [
      DomainWeight('petit', null, 1),
      DomainWeight('gros', null, 12),
    ]);
    final petit = m.byDomain['petit']!;
    final gros = m.byDomain['gros']!;
    expect(gros.size, greaterThan(petit.size));
  });

  test('déterministe pour un même seed', () {
    final a = generateOverworld(
        const [DomainWeight('a', null, 4), DomainWeight('b', null, 6)],
        seed: 42);
    final b = generateOverworld(
        const [DomainWeight('a', null, 4), DomainWeight('b', null, 6)],
        seed: 42);
    expect(a.cols, b.cols);
    expect(a.owner, b.owner);
  });
}
