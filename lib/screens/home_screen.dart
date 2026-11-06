import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../services/document_store.dart';
import '../services/pdf_import.dart';
import '../services/pdf_service.dart';
import '../services/update_service.dart';
import '../widgets/dialogs.dart';
import '../widgets/update_dialog.dart';
import '../widgets/word_export_flow.dart';
import 'editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _autoCheckUpdate();
  }

  /// Une vérification discrète par lancement ; sans réseau, rien ne s'affiche.
  static bool _updateChecked = false;
  Future<void> _autoCheckUpdate() async {
    if (_updateChecked || !UpdateService.supported) return;
    _updateChecked = true;
    final info = await UpdateService.check();
    if (info != null && mounted) await offerUpdate(context, info);
  }

  Future<void> _about() async {
    final p = await PackageInfo.fromPlatform();
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'PDF Facile',
      applicationVersion: 'Version ${p.version}',
      applicationIcon: Icon(Icons.picture_as_pdf, color: Theme.of(context).colorScheme.primary, size: 40),
      children: const [
        Text('Éditeur PDF hors ligne. Internet sert uniquement à vérifier les mises à jour ; '
            'vos documents restent sur le téléphone.'),
      ],
    );
  }

  Future<void> _refresh() async {
    final files = await DocumentStore.list();
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  Future<void> _openEditor(File file) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(file: file)));
    _refresh();
  }

  Future<void> _importPdf() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (picked.isEmpty || !mounted) return;
    final f = picked.first;
    final raw = await f.readAsBytes();
    if (!mounted) return;
    final bytes = await preparePdfForEditing(context, raw);
    if (bytes == null) return;
    final file = await DocumentStore.create(f.name, bytes);
    await _openEditor(file);
  }

  Future<void> _newBlank() async {
    final name = await askText(context, title: 'Nouveau PDF', label: 'Nom du fichier', initial: 'Nouveau document');
    if (name == null) return;
    final file = await DocumentStore.create(name, PdfService.createBlank());
    await _openEditor(file);
  }

  Future<void> _fromPhotos(ImageSource source) async {
    final picker = ImagePicker();
    final images = <Uint8List>[];
    if (source == ImageSource.gallery) {
      final xs = await picker.pickMultiImage(maxWidth: 2400, maxHeight: 2400, imageQuality: 85);
      for (final x in xs) {
        images.add(await x.readAsBytes());
      }
    } else {
      final x = await picker.pickImage(source: ImageSource.camera, maxWidth: 2400, maxHeight: 2400, imageQuality: 85);
      if (x != null) images.add(await x.readAsBytes());
    }
    if (images.isEmpty || !mounted) return;
    final bytes = await withProgress(context, () async => PdfService.createFromImages(images),
        message: 'Création du PDF…');
    final stamp = DateTime.now();
    final file = await DocumentStore.create(
        'Photos ${stamp.day.toString().padLeft(2, '0')}-${stamp.month.toString().padLeft(2, '0')}-${stamp.year}',
        bytes);
    await _openEditor(file);
  }

  void _showCreateMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Ouvrir un PDF depuis le téléphone'),
            onTap: () {
              Navigator.pop(ctx);
              _importPdf();
            },
          ),
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: const Text('Nouveau PDF vierge'),
            onTap: () {
              Navigator.pop(ctx);
              _newBlank();
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('PDF à partir de photos'),
            onTap: () {
              Navigator.pop(ctx);
              _fromPhotos(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('Photographier un document'),
            onTap: () {
              Navigator.pop(ctx);
              _fromPhotos(ImageSource.camera);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _fileMenu(File file) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(DocumentStore.displayName(file), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Renommer'),
              onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Partager'),
              onTap: () => Navigator.pop(ctx, 'share')),
          ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Enregistrer une copie sur le téléphone'),
              onTap: () => Navigator.pop(ctx, 'export')),
          ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Exporter en Word (.docx)'),
              onTap: () => Navigator.pop(ctx, 'word')),
          ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer'),
              onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        final current = DocumentStore.displayName(file);
        final name = await askText(context,
            title: 'Renommer', initial: current.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''));
        if (name == null) return;
        try {
          await DocumentStore.rename(file, name);
        } on FileSystemException catch (e) {
          if (mounted) toast(context, e.message);
        }
      case 'share':
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]));
      case 'export':
        final uri = await FilePicker.saveFile(
            fileName: DocumentStore.displayName(file), bytes: await file.readAsBytes(), mimeType: 'application/pdf');
        if (uri != null && mounted) toast(context, 'Copie enregistrée');
      case 'word':
        final pdf = await file.readAsBytes();
        if (mounted) await exportToWord(context, pdf, DocumentStore.displayName(file));
      case 'delete':
        final ok = await confirm(context, 'Supprimer ?',
            '« ${DocumentStore.displayName(file)} » sera supprimé de l\'application.',
            okLabel: 'Supprimer');
        if (ok) await file.delete();
    }
    _refresh();
  }

  String _subtitle(File f) {
    final stat = f.statSync();
    final d = stat.modified;
    final size = stat.size;
    final sizeStr = size > 1024 * 1024
        ? '${(size / 1024 / 1024).toStringAsFixed(1)} Mo'
        : '${(size / 1024).ceil()} Ko';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)} · $sizeStr';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Facile'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'update' ? checkForUpdateManually(context) : _about(),
            itemBuilder: (_) => [
              if (UpdateService.supported)
                const PopupMenuItem(
                    value: 'update',
                    child: ListTile(leading: Icon(Icons.system_update), title: Text('Rechercher une mise à jour'))),
              const PopupMenuItem(
                  value: 'about', child: ListTile(leading: Icon(Icons.info_outline), title: Text('À propos'))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateMenu,
        icon: const Icon(Icons.add),
        label: const Text('Ouvrir / Créer'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.picture_as_pdf_outlined, size: 96, color: scheme.primary),
                      const SizedBox(height: 16),
                      Text('Aucun document', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                        'Ouvrez un PDF pour l\'annoter, le signer, remplir un formulaire '
                        'ou réorganiser ses pages. Tout fonctionne hors ligne.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                          onPressed: _importPdf, icon: const Icon(Icons.folder_open), label: const Text('Ouvrir un PDF')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: _files.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final f = _files[i];
                      return ListTile(
                        leading: Icon(Icons.picture_as_pdf, color: scheme.primary, size: 36),
                        title: Text(DocumentStore.displayName(f), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(_subtitle(f)),
                        onTap: () => _openEditor(f),
                        onLongPress: () => _fileMenu(f),
                        trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _fileMenu(f)),
                      );
                    },
                  ),
                ),
    );
  }
}
