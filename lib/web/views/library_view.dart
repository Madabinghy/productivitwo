import 'package:flutter/material.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// Bibliothèque (refonte web, § 6) : deux pills « Documents » / « Organisation »
/// au-dessus des vues existantes, gardées en `IndexedStack` pour conserver
/// leur état. Les vues elles-mêmes ne sont pas redessinées dans ce lot.
class LibraryView extends StatefulWidget {
  final Widget documents;
  final Widget organisation;
  const LibraryView({
    super.key,
    required this.documents,
    required this.organisation,
  });

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  int _tab = 0;

  Widget _pill(String label, int index) {
    final selected = _tab == index;
    return SizedBox(
      height: 36,
      child: TextButton(
        onPressed: () => setState(() => _tab = index),
        style: TextButton.styleFrom(
          backgroundColor: selected ? kBActive : Colors.transparent,
          foregroundColor: selected ? kBText : kBText2,
          shape: StadiumBorder(
            side: BorderSide(
                color: selected ? kBPrimary.withOpacity(.35) : kBLine),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
          child: Row(children: [
            _pill('Documents', 0),
            const SizedBox(width: 8),
            _pill('Organisation', 1),
          ]),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [widget.documents, widget.organisation],
          ),
        ),
      ],
    );
  }
}
