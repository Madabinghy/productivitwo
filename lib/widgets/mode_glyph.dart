import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:productivitwo_v1/utils/guerilla.dart' show kGuerillaKind;
import 'package:productivitwo_v1/utils/offensive.dart' show kOffensiveKind;

/// Icônes des modes (maquette validée 2026-11-03 « Modes en tuile ») :
/// Guérilla = shuriken en plein vol vers le haut à droite, trois traînées ;
/// Offensive = la percée (un mur fendu par la foudre, éclats) ; Sniper =
/// le viseur (`Icons.gps_fixed`, inchangé). Dessins SVG en noir, teintés par
/// [color] (les opacités internes sont gardées).

const _shuriken = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
<g transform="translate(14.2 9.8) translate(-12 -11)"><path fill="#000" fill-rule="evenodd" transform="rotate(22 12 11)" d="M12 3l1.8 6.2L20 11l-6.2 1.8L12 19l-1.8-6.2L4 11l6.2-1.8z M13.6 11a1.6 1.6 0 1 0 -3.2 0a1.6 1.6 0 1 0 3.2 0z"/></g>
<g fill="none" stroke="#000" stroke-linecap="round"><path d="M3 21 9 15" stroke-width="2.1" stroke-opacity=".7"/><path d="M2 16 5.6 12.4" stroke-width="1.7" stroke-opacity=".45"/><path d="M8 22 11.6 18.4" stroke-width="1.7" stroke-opacity=".45"/></g>
</svg>''';

const _breach = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
<path fill="#000" fill-opacity=".5" d="M1.5 3.5h7l-2.6 7.3h3.4L6.6 20.5H1.5z"/>
<path fill="#000" fill-opacity=".5" d="M22.5 3.5h-6.3l-1.6 6h3.2L14.4 20.5h8.1z"/>
<path fill="#000" d="M14 1 8.5 11.5h4.2L10.2 23l7.6-13h-4.6z"/>
<path fill="none" stroke="#000" stroke-width="1.6" stroke-linecap="round" stroke-opacity=".6" d="M4 22.5h3M17 22.5h3"/>
<rect fill="#000" fill-opacity=".8" x="7.5" y="13.5" width="1.6" height="1.6" transform="rotate(20 8.3 14.3)"/>
<rect fill="#000" fill-opacity=".8" x="16.6" y="6" width="1.5" height="1.5" transform="rotate(-15 17.3 6.7)"/>
</svg>''';

/// L'icône d'un mode (`kGuerillaKind`, `kOffensiveKind`, sinon le viseur).
class ModeGlyph extends StatelessWidget {
  final String kind;
  final double size;
  final Color color;
  final String? semanticLabel;
  const ModeGlyph({super.key, required this.kind, required this.size, required this.color, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final svg = switch (kind) {
      kGuerillaKind => _shuriken,
      kOffensiveKind => _breach,
      _ => null,
    };
    if (svg == null) return Icon(Icons.gps_fixed, size: size, color: color, semanticLabel: semanticLabel);
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
    );
  }
}
