import 'dart:convert';

import 'package:productivitwo_v1/utils/life_natures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La nature choisie à la main pour un domaine (Organisation, appui long sur
/// sa tuile) : gardée sur l'appareil (`life_natures`). Lue par Organisation et
/// par le calcul du temps de détente.
class LifeNatureStore {
  static const _kPref = 'life_natures';
  static Map<String, DomainNature> overrides = const {};

  static Future<Map<String, DomainNature>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kPref);
      overrides = raw == null ? const {} : parseNatures(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {}
    return overrides;
  }

  static Future<void> set(String domainId, DomainNature nature) async {
    overrides = {...overrides, domainId: nature};
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPref, jsonEncode(overrides.map((k, v) => MapEntry(k, v.name))));
    } catch (_) {}
  }
}
