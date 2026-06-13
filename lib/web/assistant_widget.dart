import 'dart:async';
import 'package:flutter/material.dart';
import 'assistant_engine.dart';

// Vitesse d'écriture (ms par caractère)
const _kTypeSpeed = Duration(milliseconds: 22);

// ── Canal global ──────────────────────────────────────────────────────────────
// Les messages de l'assistant sont évalués DANS l'écran d'accueil, mais doivent
// s'afficher AU-DESSUS de toutes les routes/sheets (sinon une modale les cache).
// On les remonte via ce notifier global, lu par [GlobalAssistantOverlay] placé
// dans `MaterialApp.builder` (donc au-dessus du Navigator).
final ValueNotifier<List<AssistantMessageData>> assistantMessagesNotifier =
    ValueNotifier<List<AssistantMessageData>>(const []);

/// Coupe l'overlay assistant (Orion) tant que true — ex. dans l'arène/le Monde,
/// où il gênerait le jeu. Posé par l'écran qui veut le silence, remis à false en
/// sortant.
final ValueNotifier<bool> assistantOverlaySuppressed = ValueNotifier<bool>(false);

/// Handler d'action (navigation) enregistré par l'écran d'accueil.
void Function(AssistantActionData action)? assistantActionHandler;

/// À placer dans `MaterialApp.builder` : rend l'overlay de l'assistant au-dessus
/// du Navigator → visible même quand un bottom sheet / une modale est ouvert.
class GlobalAssistantOverlay extends StatelessWidget {
  final Widget child;
  const GlobalAssistantOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          right: 16,
          bottom: 90,
          child: AnimatedBuilder(
            animation: Listenable.merge(
                [assistantMessagesNotifier, assistantOverlaySuppressed]),
            builder: (context, _) {
              final msgs = assistantMessagesNotifier.value;
              if (assistantOverlaySuppressed.value || msgs.isEmpty) {
                return const SizedBox.shrink();
              }
              // Material : fournit le contexte Material requis par l'overlay
              // (il vit hors de tout Scaffold ici).
              return Material(
                color: Colors.transparent,
                child: AssistantOverlay(
                  key: ValueKey(msgs.first.id),
                  messages: msgs,
                  onAction: assistantActionHandler,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AssistantOverlay extends StatefulWidget {
  final List<AssistantMessageData> messages;
  final void Function(AssistantActionData action)? onAction;

  const AssistantOverlay({
    super.key,
    required this.messages,
    this.onAction,
  });

  @override
  State<AssistantOverlay> createState() => _AssistantOverlayState();
}

class _AssistantOverlayState extends State<AssistantOverlay>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  String _displayed = '';
  bool _typing = false;
  bool _dismissed = false;
  Timer? _timer;
  late AnimationController _enterAnim;
  late Animation<double> _enterOpacity;
  late Animation<Offset> _enterSlide;

  AssistantMessageData get _current => widget.messages[_index];

  @override
  void initState() {
    super.initState();
    _enterAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _enterOpacity = CurvedAnimation(parent: _enterAnim, curve: Curves.easeOut);
    _enterSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterAnim, curve: Curves.easeOut));

    _enterAnim.forward();
    _startTyping();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _enterAnim.dispose();
    super.dispose();
  }

  void _startTyping() {
    _displayed = '';
    _typing = true;
    final fullText = _current.text;
    int charIndex = 0;

    _timer?.cancel();
    _timer = Timer.periodic(_kTypeSpeed, (t) {
      if (!mounted) { t.cancel(); return; }
      if (charIndex >= fullText.length) {
        t.cancel();
        setState(() => _typing = false);
        return;
      }
      setState(() => _displayed = fullText.substring(0, ++charIndex));
    });
  }

  void _skipTyping() {
    if (_typing) {
      _timer?.cancel();
      setState(() {
        _displayed = _current.text;
        _typing = false;
      });
    }
  }

  void _next() {
    if (_index < widget.messages.length - 1) {
      setState(() => _index++);
      _startTyping();
    } else {
      _dismiss();
    }
  }

  void _dismiss() {
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || widget.messages.isEmpty) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _enterOpacity,
      child: SlideTransition(
        position: _enterSlide,
        child: _DialogBox(
          message: _current,
          displayedText: _displayed,
          typing: _typing,
          isLast: _index >= widget.messages.length - 1,
          onTap: _typing ? _skipTyping : _next,
          onDismiss: _dismiss,
          onAction: widget.onAction,
        ),
      ),
    );
  }
}

// ── Boîte de dialogue ─────────────────────────────────────────────────────────

class _DialogBox extends StatefulWidget {
  final AssistantMessageData message;
  final String displayedText;
  final bool typing;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final void Function(AssistantActionData)? onAction;

  const _DialogBox({
    required this.message,
    required this.displayedText,
    required this.typing,
    required this.isLast,
    required this.onTap,
    required this.onDismiss,
    this.onAction,
  });

  @override
  State<_DialogBox> createState() => _DialogBoxState();
}

class _DialogBoxState extends State<_DialogBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorAnim;

  @override
  void initState() {
    super.initState();
    _cursorAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorAnim.dispose();
    super.dispose();
  }

  static const _bg = Color(0xFF0f0f0f);
  static const _gold = Color(0xFFe8c94a);
  static const _surface = Color(0xFF181818);
  static const _border = Color(0xFF2a2a2a);
  static const _muted = Color(0xFF747070);

  @override
  Widget build(BuildContext context) {
    final hasAction = !widget.typing &&
        widget.message.action != null &&
        widget.message.action!.type.isNotEmpty;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 340,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold.withOpacity(0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _gold.withOpacity(0.08),
              blurRadius: 24,
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header personnage ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: const BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                border: Border(bottom: BorderSide(color: _border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: _gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.message.characterName,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: _gold,
                    ),
                  ),
                  const Spacer(),
                  // Bouton fermer
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: const Icon(Icons.close, size: 14, color: _muted),
                  ),
                ],
              ),
            ),

            // ── Texte typewriter ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: AnimatedBuilder(
                animation: _cursorAnim,
                builder: (_, __) {
                  final showCursor = widget.typing && _cursorAnim.value > 0.5;
                  return RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.65,
                        color: Color(0xFFf0ece0),
                      ),
                      children: [
                        TextSpan(text: widget.displayedText),
                        if (showCursor)
                          const TextSpan(
                            text: '█',
                            style: TextStyle(color: _gold),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── Bouton action ────────────────────────────────────────────
            if (hasAction)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: _gold.withOpacity(0.1),
                    foregroundColor: _gold,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(color: _gold.withOpacity(0.3)),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  onPressed: () => widget.onAction?.call(widget.message.action!),
                  child: Text(
                    (widget.message.action!.label ?? 'Voir').toUpperCase(),
                  ),
                ),
              ),

            // ── Footer navigation ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicateur progression si plusieurs messages
                  // (invisible si un seul)
                  Opacity(
                    opacity: 0.4,
                    child: Text(
                      widget.typing ? 'Appuie pour passer...' : '',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: _muted,
                      ),
                    ),
                  ),
                  if (!widget.typing)
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.isLast ? 'Fermer' : 'Suivant',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              color: _gold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 8,
                            color: _gold,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
