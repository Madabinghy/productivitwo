import 'package:productivitwo_v1/utils/week_stats.dart' show DomainWeek;

/// Widget iOS « Mes domaines » (maquette validée 2026-11-05) : l'app dessine chaque tuile
/// d'Organisation en image et dépose ici la liste ; le widget n'affiche que ces images.

/// Où en est un domaine face à son attendu (0 = rien fait, 1 = au rythme, au-delà = en avance) :
/// sert à « Choisir pour moi » (les plus bas d'abord). Sans attendu ni routine, ou en veille : à la fin.
double domainPace(DomainWeek? w) {
  if (w == null || w.resting) return 9;
  final parts = <double>[];
  if (w.hasGoal && w.expectedMin > 0) parts.add(w.doneMin / w.expectedMin);
  if (w.routinesTotal > 0) parts.add(w.routinesReached / w.routinesTotal);
  if (parts.isEmpty) return 5;
  return parts.reduce((a, b) => a < b ? a : b);
}

/// Une case du widget, telle que l'app la dépose.
class WidgetDomain {
  final String id;
  final String name;
  final int color; // ARGB
  final String link; // chemin du lien de l'app : domain/<id>
  final double pace;
  final bool wide; // une image pleine largeur existe (grille routines × jours)
  const WidgetDomain({required this.id, required this.name, required this.color, required this.link, required this.pace, this.wide = false});
}

/// Clé de l'image d'une case (fichier `home_widget/<clé>.png` de l'espace partagé).
String domainImageKey(String id, {bool wide = false}) => 'dom_${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}${wide ? '_wide' : ''}';

/// Le JSON `domains_json` : les domaines dans l'ordre d'Organisation, `rank` = ordre de « Choisir pour moi ».
Map<String, dynamic> domainsWidgetJson(List<WidgetDomain> domains, {required int bg, required DateTime at}) {
  final ranked = [...domains]..sort((a, b) => a.pace.compareTo(b.pace));
  return {
    'bg': bg & 0xFFFFFF,
    'at': at.millisecondsSinceEpoch,
    'domains': [
      for (final d in domains)
        {
          'id': d.id,
          'name': d.name,
          'color': d.color & 0xFFFFFF,
          'link': d.link,
          'rank': ranked.indexOf(d),
          'wide': d.wide,
          'img': domainImageKey(d.id),
          if (d.wide) 'imgWide': domainImageKey(d.id, wide: true),
        },
    ],
  };
}
