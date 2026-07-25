import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/pro_manager.dart';
import 'package:productivitwo_v1/storage.dart';
import 'package:productivitwo_v1/utils/backup.dart';
import 'package:productivitwo_v1/utils/backup_saver.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paramètres → « Mes données » (spec : docs/specs/export-import-donnees).
/// Un seul endroit : sortir ses données (export .json), les faire rentrer
/// (restauration Fusionner/Remplacer), ou tout effacer.

const _kPrefLastAt = 'backup.lastAt';
const _kPrefLastBytes = 'backup.lastBytes';
const _kPrefUndoPath = 'backup.undoPath';
const _kPrefUndoAt = 'backup.undoAt';

const _kMonthsFr = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
  'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

String _dateLong(DateTime d) => '${d.day} ${_kMonthsFr[d.month - 1]} ${d.year}';
String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class DataSettingsScreen extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final FileStore store;

  const DataSettingsScreen({
    super.key,
    required this.logic,
    required this.sync,
    required this.store,
  });

  @override
  State<DataSettingsScreen> createState() => _DataSettingsScreenState();
}

class _DataSettingsScreenState extends State<DataSettingsScreen> {
  DateTime? _lastAt;
  int? _lastBytes;
  DateTime? _undoAt;
  String? _undoPath;
  bool _busy = false;

  bool get _hasData =>
      widget.logic.state.sessions.isNotEmpty ||
      widget.logic.state.habitHits.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    var undoAt = DateTime.tryParse(p.getString(_kPrefUndoAt) ?? '');
    var undoPath = p.getString(_kPrefUndoPath);
    // La sauvegarde d'annulation est purgée après 7 jours (spec 3.3).
    if (undoAt != null &&
        DateTime.now().difference(undoAt) > const Duration(days: 7)) {
      if (undoPath != null) {
        try {
          final f = File(undoPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      await p.remove(_kPrefUndoAt);
      await p.remove(_kPrefUndoPath);
      undoAt = null;
      undoPath = null;
    }
    if (!mounted) return;
    setState(() {
      _lastAt = DateTime.tryParse(p.getString(_kPrefLastAt) ?? '');
      _lastBytes = p.getInt(_kPrefLastBytes);
      _undoAt = undoAt;
      _undoPath = undoPath;
    });
  }

  Future<void> _recordBackup(int bytes) async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await p.setString(_kPrefLastAt, now.toIso8601String());
    await p.setInt(_kPrefLastBytes, bytes);
    if (mounted) {
      setState(() {
        _lastAt = now;
        _lastBytes = bytes;
      });
    }
  }

  // ── Export ──────────────────────────────────────────────────────────────────

  /// CTA « Sauvegarder maintenant » : export direct, tout inclus.
  Future<void> _quickBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final builder =
          BackupBuilder(state: widget.logic.state, sync: widget.sync);
      await builder.fetch();
      final bundle = builder.build(includeDocuments: true);
      final ok = await saveBackupFile(bundle.fileName, bundle.encoded,
          origin: _shareOrigin());
      if (ok) await _recordBackup(bundle.sizeBytes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _openExportSheet() async {
    final builder = BackupBuilder(state: widget.logic.state, sync: widget.sync);
    BackupBundle? withDocs;
    BackupBundle? withoutDocs;
    var includeDocs = true;
    var loading = true;
    var fetchStarted = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        if (!fetchStarted) {
          fetchStarted = true;
          // Taille estimée AVANT l'écriture (spec 3.2) : le bundle est
          // construit à l'ouverture, le CTA affiche la taille réelle.
          builder.fetch().then((_) {
            if (!ctx.mounted) return;
            withDocs = builder.build(includeDocuments: true);
            withoutDocs = builder.build(includeDocuments: false);
            setLocal(() => loading = false);
          });
        }
        final cs = Theme.of(ctx).colorScheme;
        final counts = loading ? null : builder.counts();
        final bundle = includeDocs ? withDocs : withoutDocs;

        Widget invRow(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withOpacity(.75))),
                ),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontFamily: 'monospace',
                        fontFeatures: [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w600)),
              ]),
            );

        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 4, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Exporter une sauvegarde',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Tout est inclus. Rien à choisir.',
                  style: TextStyle(
                      fontSize: 14, color: cs.onSurface.withOpacity(.6))),
              const SizedBox(height: 16),
              if (loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ))
              else ...[
                invRow('Domaines & intentions', '${counts!['domains']}'),
                invRow('Activités & routines', '${counts['activities']}'),
                invRow('Sessions de temps', '${counts['sessions']}'),
                invRow('Coches de routines', '${counts['habitHits']}'),
                invRow('Projets, tâches, objectifs',
                    '${counts['projects']! + counts['objectives']!}'),
                invRow('Programmes horaires',
                    '${counts['dailySchedules']} jours'),
                invRow('Blocs, inbox, réglages', '✓'),
                const SizedBox(height: 6),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeDocs,
                  onChanged: (v) => setLocal(() => includeDocs = v ?? true),
                  title: const Text('Inclure les documents et livrables',
                      style: TextStyle(fontSize: 14.5)),
                  subtitle: Text(
                      'Briefs et programmes HTML (${counts['documents']})',
                      style: const TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final b = bundle!;
                      final ok = await saveBackupFile(b.fileName, b.encoded,
                          origin: _shareOrigin());
                      if (ok) await _recordBackup(b.sizeBytes);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text('Exporter — ${bundle!.sizeLabel}'),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Le fichier ne contient aucun mot de passe.\n'
                    'Il porte la date et le numéro de schéma.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withOpacity(.5)),
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }

  // ── Restauration ────────────────────────────────────────────────────────────

  Future<void> _openRestoreFlow() async {
    final typeGroup = XTypeGroup(
      label: 'Sauvegarde Productivitwo',
      extensions: const ['json'],
      uniformTypeIdentifiers: const ['public.json'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) return;

    BackupPreview preview;
    try {
      preview = parseBackup(await file.readAsString());
    } on BackupParseError catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restauration impossible'),
          content: Text(e == BackupParseError.schemaTooRecent
              ? 'Cette sauvegarde vient d\'une version plus récente de '
                  'Productivitwo (l\'app lit jusqu\'au schéma '
                  '$kBackupSchemaVersion). Mets à jour Productivitwo '
                  'puis réessaie.'
              : 'Ce n\'est pas une sauvegarde Productivitwo, ou le fichier '
                  'est incomplet. Rien n\'a été modifié.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    } catch (_) {
      return;
    }
    if (!mounted) return;

    final mode = await _showRestorePreview(preview, file.name);
    if (mode == null || !mounted) return;
    await _applyRestore(preview, mode);
  }

  Future<RestoreMode?> _showRestorePreview(
      BackupPreview p, String fileName) async {
    var mode = RestoreMode.merge;
    final range = p.dateRange();
    return showModalBottomSheet<RestoreMode>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final cs = Theme.of(ctx).colorScheme;

        Widget modeCard(RestoreMode m, String title, String body) {
          final selected = mode == m;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                width: 2,
                color: selected ? cs.primary : cs.outlineVariant,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setLocal(() => mode = m),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(body,
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withOpacity(.7))),
                  ],
                ),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 4, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Restaurer une sauvegarde',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              // Carte fichier : décrire AVANT de toucher à quoi que ce soit.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(.35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontFamily: 'monospace')),
                    const SizedBox(height: 6),
                    Text(
                        '${p.domainCount} domaines · ${p.activityCount} '
                        'activités · ${p.sessionCount} sessions · '
                        '${p.projectCount} projets',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    if (range.first != null && range.last != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                            'Du ${_ddmmyyyy(range.first!)} au ${_ddmmyyyy(range.last!)}',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: cs.onSurface.withOpacity(.6))),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('Schéma compatible',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: cs.primary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              modeCard(
                  RestoreMode.merge,
                  'Fusionner — recommandé',
                  'Ajoute ce qui manque, met à jour ce qui est plus ancien. '
                      'Rien n\'est supprimé.'),
              modeCard(RestoreMode.replace, 'Remplacer tout',
                  'Repartir exactement de cette sauvegarde. Pour changer d\'appareil.'),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Une sauvegarde de ton état actuel est créée avant '
                  'l\'opération. Tu peux annuler pendant 7 jours.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF6B4A00)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, mode),
                  child: Text(mode == RestoreMode.merge
                      ? 'Fusionner ce fichier'
                      : 'Remplacer par ce fichier'),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _applyRestore(BackupPreview preview, RestoreMode mode) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    RestoreReport report;
    try {
      // Filet : l'état ACTUEL complet est sauvegardé localement avant toute
      // écriture — c'est lui qu'« Annuler la restauration » rejoue.
      final undoBuilder =
          BackupBuilder(state: widget.logic.state, sync: widget.sync);
      await undoBuilder.fetch();
      final undoBundle = undoBuilder.build(includeDocuments: true);
      final dir = await getApplicationDocumentsDirectory();
      final undoFile = File('${dir.path}/productivitwo-avant-restauration.json');
      await undoFile.writeAsString(undoBundle.encoded, flush: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefUndoPath, undoFile.path);
      await prefs.setString(_kPrefUndoAt, DateTime.now().toIso8601String());

      final result = await applyRestore(
        backup: preview,
        current: widget.logic.state,
        sync: widget.sync,
        store: widget.store,
        mode: mode,
      );
      report = result.report;
    } catch (_) {
      if (mounted) Navigator.pop(context); // spinner
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('La restauration a échoué. Rien n\'a été modifié.')));
      }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context); // spinner

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restauration terminée'),
        content: Text(mode == RestoreMode.merge
            ? '${report.added} éléments ajoutés · ${report.alreadyThere} déjà '
                'présents · 0 supprimé.\n\nL\'app va redémarrer pour '
                'recharger tes données. Tu peux annuler la restauration '
                'pendant 7 jours depuis « Mes données ».'
            : '${report.overwritten} éléments restaurés · 0 supprimé.\n\n'
                'L\'app va redémarrer pour recharger tes données. Tu peux '
                'annuler la restauration pendant 7 jours depuis '
                '« Mes données ».'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Redémarrer')),
        ],
      ),
    );
    // L'état en mémoire (AppLogic, streams) est irrécupérablement mélangé
    // après un remplacement : redémarrage propre, comme la suppression de
    // compte (le fichier local et Firestore sont déjà à jour).
    exit(0);
  }

  Future<void> _undoRestore() async {
    final path = _undoPath;
    if (path == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la restauration ?'),
        content: Text(
            'Ton état d\'avant la restauration du '
            '${_undoAt == null ? '' : _dateLong(_undoAt!)} sera remis en '
            'place (mode Remplacer). L\'app redémarrera.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Garder l\'état actuel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Annuler la restauration')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    BackupPreview preview;
    try {
      preview = parseBackup(await File(path).readAsString());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sauvegarde d\'annulation introuvable.')));
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefUndoPath);
    await prefs.remove(_kPrefUndoAt);
    await _applyRestore(preview, RestoreMode.replace);
  }

  // ── Suppression ─────────────────────────────────────────────────────────────

  Future<void> _deleteFlow() async {
    // « Propose d'abord une sauvegarde » (spec 3.1) — l'export est proposé
    // AVANT le flux de suppression existant.
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer mes données'),
        content: const Text(
            'Toutes tes données seront supprimées définitivement (activités, '
            'routines, sessions, projets, documents).\n\n'
            'Exporte d\'abord une sauvegarde : elle te permettra de tout '
            'retrouver, ici ou ailleurs.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'export'),
              child: const Text('Exporter d\'abord')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'export') {
      await _quickBackup();
      if (mounted) await _deleteFlow();
      return;
    }
    if (choice != 'delete') return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    // Même flux que Paramètres → Supprimer mon compte.
    try {
      await widget.sync.deleteAccount();
    } catch (_) {}
    await widget.store.wipe();
    await ProManager.deactivate();
    exit(0);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final firstDay = BackupBuilder(state: widget.logic.state, sync: widget.sync)
        .firstDataDay();

    Widget row({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback? onTap,
      Color? color,
    }) {
      final c = color ?? cs.onSurface;
      final enabled = onTap != null;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: (color ?? cs.primary).withOpacity(.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: color ?? cs.primary),
        ),
        title: Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: enabled ? c : c.withOpacity(.4))),
        subtitle: Text(subtitle,
            style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurface.withOpacity(enabled ? .55 : .35))),
        trailing: enabled
            ? Icon(Icons.chevron_right,
                size: 18, color: cs.onSurface.withOpacity(.35))
            : null,
        onTap: onTap,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mes données')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_lastAt != null && _lastBytes != null)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(.35),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DERNIÈRE SAUVEGARDE',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .8,
                          color: cs.primary)),
                  const SizedBox(height: 6),
                  Text(
                      '${_dateLong(_lastAt!)} · ${_hhmm(_lastAt!)} — '
                      '${formatBytes(_lastBytes!)}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(
                      firstDay == null
                          ? 'Enregistrée dans Fichiers.'
                          : 'Enregistrée dans Fichiers. Elle contient tout ton '
                              'historique depuis le ${_dateLong(firstDay)}.',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(.65))),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _quickBackup,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sauvegarder maintenant'),
                    ),
                  ),
                ],
              ),
            ),
          row(
            icon: Icons.south_rounded,
            title: 'Exporter une sauvegarde',
            subtitle: _hasData
                ? 'Fichier .json — tout, lisible, réimportable'
                : 'Tes données apparaîtront ici dès ta première journée suivie.',
            onTap: _hasData ? _openExportSheet : null,
          ),
          const Divider(height: 1),
          row(
            icon: Icons.north_rounded,
            title: 'Restaurer une sauvegarde',
            subtitle: 'Depuis un fichier .json de Productivitwo',
            onTap: _openRestoreFlow,
          ),
          if (_undoAt != null) ...[
            const Divider(height: 1),
            row(
              icon: Icons.undo_rounded,
              title: 'Annuler la restauration',
              subtitle:
                  'Revenir à l\'état du ${_dateLong(_undoAt!)} (7 jours max)',
              onTap: _undoRestore,
            ),
          ],
          const Divider(height: 1),
          row(
            icon: Icons.backspace_outlined,
            title: 'Supprimer mes données',
            subtitle: 'Propose d\'abord une sauvegarde',
            color: cs.error,
            onTap: _deleteFlow,
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Paramètres → Mes données. Un seul endroit : sortir, rentrer, effacer.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withOpacity(.45)),
            ),
          ),
        ],
      ),
    );
  }
}
