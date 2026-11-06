import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:productivitwo_v1/utils/guerilla.dart' show kGuerillaKind;
import 'package:productivitwo_v1/utils/offensive.dart' show kOffensiveKind;

/// Icônes des modes (maquette validée 2026-11-03 « Modes en tuile ») :
/// Guérilla = shuriken en plein vol vers le haut à droite, trois traînées ;
/// Offensive = l'infini du Deep work (depuis le 2026-11-06, avant : la percée) ; Sniper =
/// le viseur (`Icons.gps_fixed`, inchangé). Dessins SVG en noir, teintés par
/// [color] (les opacités internes sont gardées).

const _shuriken = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
<g transform="translate(14.2 9.8) translate(-12 -11)"><path fill="#000" fill-rule="evenodd" transform="rotate(22 12 11)" d="M12 3l1.8 6.2L20 11l-6.2 1.8L12 19l-1.8-6.2L4 11l6.2-1.8z M13.6 11a1.6 1.6 0 1 0 -3.2 0a1.6 1.6 0 1 0 3.2 0z"/></g>
<g fill="none" stroke="#000" stroke-linecap="round"><path d="M3 21 9 15" stroke-width="2.1" stroke-opacity=".7"/><path d="M2 16 5.6 12.4" stroke-width="1.7" stroke-opacity=".45"/><path d="M8 22 11.6 18.4" stroke-width="1.7" stroke-opacity=".45"/></g>
</svg>''';

const _infinity = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
<path fill="none" stroke="#000" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" d="M12 12c-2-2.7-3.6-4-5.5-4a4 4 0 0 0 0 8c1.9 0 3.5-1.3 5.5-4s3.6-4 5.5-4a4 4 0 0 1 0 8c-1.9 0-3.5-1.3-5.5-4z"/>
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
      kOffensiveKind => _infinity,
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
