import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/world_organic.dart';
import 'package:productivitwo_v1/world_map_gen.dart';

void main() {
  const sample = [
    DomainWeight('sante', 0xFF4F8DF7, 3),
    DomainWeight('travail', 0xFFE0A030, 8),
    DomainWeight('perso', 0xFF50C878, 2),
  ];

  test('déterministe pour un même seed', () {
    final a = buildOrganicMap(sample, seed: 7);
    final b = buildOrganicMap(sample, seed: 7);
    expect(a.cols, b.cols);
    expect(a.owner, b.owner);
    expect(a.biome, b.biome);
    expect(a.elevation, b.elevation);
  });

  test('le lissage des côtes ne fait disparaître aucun domaine', () {
    final m = buildOrganicMap(sample);
    for (final r in m.regions) {
      expect(m.owner.contains(r.domainId), isTrue,
          reason: '${r.domainId} doit rester présent après lissage');
    }
  });

  test('chaque case terre a un biome non‑eau, l\'eau reste eau', () {
    final m = buildOrganicMap(sample);
    for (var y = 0; y < m.rows; y++) {
      for (var x = 0; x < m.cols; x++) {
        if (m.isLand(x, y)) {
          expect(m.biomeAt(x, y), isNot(OrganicBiome.water));
        } else {
          expect(m.biomeAt(x, y), OrganicBiome.water);
        }
      }
    }
  });

  test('le spawn est sur la terre ferme', () {
    final m = buildOrganicMap(sample);
    expect(m.isLand(m.start.x, m.start.y), isTrue);
  });

  test('carte vide → pas de région, pas de crash', () {
    final m = buildOrganicMap(const []);
    expect(m.regions, isEmpty);
  });
}
