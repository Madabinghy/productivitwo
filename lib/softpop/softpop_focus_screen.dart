import 'dart:async';
import 'package:flutter/material.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Routine en file (mock).
class _Focus {
  final String emoji, name, target;
  final Color color, bg;
  final bool chrono; // a un minuteur ?
  _Focus(this.emoji, this.name, this.target, this.color, this.bg,
      {this.chrono = false});
}

/// Écran « Maintenant / Focus » (preview).
///
/// Réf : maquette `01_design_produit` (B · Maintenant/Focus). Met en avant UNE
/// chose à faire maintenant + chrono + « plus tard » (remet en fin de file).
/// Données mock (→ file dérivée des routines du jour + `Session` pour le chrono).
class SoftPopFocusScreen extends StatefulWidget {
  const SoftPopFocusScreen({super.key});

  @override
  State<SoftPopFocusScreen> createState() => _SoftPopFocusScreenState();
}

class _SoftPopFocusScreenState extends State<SoftPopFocusScreen> {
  final List<_Focus> _queue = [
    _Focus('🧘', 'Méditer 10 min', '10 min', SoftPop.violet, SoftPop.violetSoft,
        chrono: true),
    _Focus('💧', "Boire de l'eau", '3 / 8 verres', SoftPop.coral,
        SoftPop.coralSoft),
    _Focus('📖', 'Lire 10 pages', '20 min', SoftPop.amber, SoftPop.amberSoft,
        chrono: true),
    _Focus('🏋️', 'Salle de sport', '1 séance', SoftPop.coral,
        SoftPop.coralSoft, chrono: true),
    _Focus('📓', 'Journal de gratitude', '3 lignes', SoftPop.pink,
        SoftPop.pinkSoft),
  ];
  int _done = 0;

  Timer? _timer;
  int _elapsed = 0;
  bool get _running => _timer != null;

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _elapsed = 0;
  }

  void _toggleChrono() {
    setState(() {
      if (_running) {
        _timer!.cancel();
        _timer = null;
      } else {
        _timer = Timer.periodic(
            const Duration(seconds: 1), (_) => setState(() => _elapsed++));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _markDone() {
    final r = _queue.first;
    setState(() {
      _stopTimer();
      _queue.removeAt(0);
      _done++;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Bravo ! « ${r.name} » ✓  +XP',
            style: SoftPop.ui(color: Colors.white, weight: FontWeight.w600)),
        backgroundColor: SoftPop.teal,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1100),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SoftPop.rChip)),
      ));
  }

  void _later() {
    setState(() {
      _stopTimer();
      _queue.add(_queue.removeAt(0)); // en fin de file
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        body: SafeArea(
          child: _queue.isEmpty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      SoftPop.s16, SoftPop.s16, SoftPop.s16, SoftPop.s32),
                  children: [
                    _header(),
                    const SizedBox(height: SoftPop.s16),
                    _focusCard(_queue.first),
                    const SizedBox(height: SoftPop.s24),
                    if (_queue.length > 1) ...[
                      Text('À suivre',
                          style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
                      const SizedBox(height: SoftPop.s12),
                      for (final r in _queue.skip(1).take(3)) _upNextTile(r),
                      if (_queue.length > 4)
                        Padding(
                          padding: const EdgeInsets.only(top: SoftPop.s4),
                          child: Text('+ ${_queue.length - 4} autres routines',
                              style: SoftPop.ui(
                                  size: 12, color: SoftPop.inkMuted)),
                        ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Maintenant',
              style: SoftPop.ui(size: 24, weight: FontWeight.w700)),
          Text('$_done faites · ${_queue.length} à faire',
              style: SoftPop.ui(size: 12, color: SoftPop.inkMuted)),
        ],
      );

  // ── Carte focus (l'unique chose à faire maintenant) ────────────────────────
  Widget _focusCard(_Focus r) {
    final mm = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final ss = (_elapsed % 60).toString().padLeft(2, '0');
    return SoftCard(
      radius: SoftPop.rCardLg,
      padding: const EdgeInsets.all(SoftPop.s24),
      child: Column(
        children: [
          Text('À FAIRE MAINTENANT',
              style: SoftPop.ui(
                  size: 11,
                  weight: FontWeight.w700,
                  color: r.color,
                  letterSpacing: 1)),
          const SizedBox(height: SoftPop.s16),
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: r.bg,
              shape: BoxShape.circle,
            ),
            child: Text(r.emoji, style: const TextStyle(fontSize: 40)),
          ),
          const SizedBox(height: SoftPop.s12),
          Text(r.name,
              textAlign: TextAlign.center,
              style: SoftPop.ui(size: 20, weight: FontWeight.w700)),
          Text(r.target, style: SoftPop.ui(size: 13, color: SoftPop.inkMuted)),
          if (r.chrono && _running) ...[
            const SizedBox(height: SoftPop.s12),
            Text('$mm:$ss',
                style: SoftPop.mono(
                    size: 34, weight: FontWeight.w700, color: r.color)),
          ],
          const SizedBox(height: SoftPop.s20),
          Row(
            children: [
              Expanded(
                child: SoftHeroButton(
                    label: "Je l'ai fait ✓", onPressed: _markDone),
              ),
              if (r.chrono) ...[
                const SizedBox(width: SoftPop.s8),
                _chronoBtn(r),
              ],
            ],
          ),
          const SizedBox(height: SoftPop.s12),
          TextButton(
            onPressed: _later,
            child: Text('Plus tard · remettre en fin de file ↓',
                style: SoftPop.ui(size: 13, color: SoftPop.inkSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _chronoBtn(_Focus r) => Material(
        color: _running ? r.bg : null,
        borderRadius: BorderRadius.circular(SoftPop.rPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(SoftPop.rPill),
          onTap: _toggleChrono,
          child: Ink(
            decoration: BoxDecoration(
              gradient: _running
                  ? null
                  : LinearGradient(colors: [r.color, r.color]),
              borderRadius: BorderRadius.circular(SoftPop.rPill),
            ),
            child: Container(
              padding: const EdgeInsets.all(SoftPop.s16),
              child: Icon(_running ? Icons.pause : Icons.play_arrow,
                  color: _running ? r.color : Colors.white, size: 24),
            ),
          ),
        ),
      );

  Widget _upNextTile(_Focus r) => Padding(
        padding: const EdgeInsets.only(bottom: SoftPop.s8),
        child: SoftCard(
          padding: const EdgeInsets.all(SoftPop.s12),
          radius: SoftPop.rCardSm,
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: r.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(r.emoji, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: SoftPop.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        style: SoftPop.ui(size: 14, weight: FontWeight.w600)),
                    Text(r.target,
                        style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
                  ],
                ),
              ),
              if (r.chrono)
                Icon(Icons.timer_outlined, size: 18, color: r.color),
            ],
          ),
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(SoftPop.s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PomoMascot(size: 96),
              const SizedBox(height: SoftPop.s20),
              Text('Tout est fait ! 🎉',
                  style: SoftPop.ui(size: 22, weight: FontWeight.w700)),
              const SizedBox(height: SoftPop.s8),
              Text('$_done routines accomplies aujourd’hui. Profite de ta journée 💛',
                  textAlign: TextAlign.center,
                  style: SoftPop.ui(
                      size: 14, color: SoftPop.inkSecondary, height: 1.4)),
            ],
          ),
        ),
      );
}
