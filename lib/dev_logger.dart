import 'package:flutter/material.dart';

/// Logger in-app pour le debug — accessible via la vue développeur.
/// Ne fait rien en production sauf collecter les logs en mémoire.
class DevLogger {
  DevLogger._();
  static final DevLogger instance = DevLogger._();

  final List<_LogEntry> _entries = [];
  final _notifier = ValueNotifier<int>(0);

  ValueNotifier<int> get notifier => _notifier;
  List<_LogEntry> get entries => List.unmodifiable(_entries);

  void log(String message, {String? tag, bool isError = false}) {
    _entries.insert(
      0,
      _LogEntry(
        time: DateTime.now(),
        tag: tag ?? 'APP',
        message: message,
        isError: isError,
      ),
    );
    if (_entries.length > 200) _entries.removeLast();
    _notifier.value++;
  }

  void error(String message, {String? tag, Object? error}) {
    log(
      error != null ? '$message\n$error' : message,
      tag: tag ?? 'ERROR',
      isError: true,
    );
  }

  void clear() {
    _entries.clear();
    _notifier.value++;
  }
}

class _LogEntry {
  final DateTime time;
  final String tag;
  final String message;
  final bool isError;

  const _LogEntry({
    required this.time,
    required this.tag,
    required this.message,
    required this.isError,
  });

  String get timeStr {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// Raccourci global
final devLog = DevLogger.instance;

// ── Vue développeur ───────────────────────────────────────────────────────────

class DevConsoleScreen extends StatelessWidget {
  const DevConsoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Console dev'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Effacer',
            onPressed: () {
              devLog.clear();
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: devLog.notifier,
        builder: (_, __, ___) {
          final entries = devLog.entries;
          if (entries.isEmpty) {
            return Center(
              child: Text(
                'Aucun log',
                style: TextStyle(color: cs.onSurface.withOpacity(.4)),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: e.isError
                      ? cs.errorContainer.withOpacity(.3)
                      : cs.surfaceContainerHighest.withOpacity(.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: cs.onSurface.withOpacity(.45),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: e.isError
                            ? cs.error.withOpacity(.15)
                            : cs.primary.withOpacity(.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        e.tag,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color:
                              e.isError ? cs.error : cs.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e.message,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: e.isError
                              ? cs.error
                              : cs.onSurface.withOpacity(.85),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
