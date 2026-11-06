import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/word_export.dart';
import 'dialogs.dart';

/// Parcours complet : choix du mode, conversion, puis enregistrement ou partage.
Future<void> exportToWord(BuildContext context, Uint8List pdf, String pdfName) async {
  var mode = await showModalBottomSheet<WordExportMode>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Exporter en Word (.docx)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        ListTile(
          leading: const Icon(Icons.text_snippet_outlined),
          title: const Text('Texte modifiable'),
          subtitle: const Text('Le texte est extrait pour être modifié dans Word. '
              'La mise en page est simplifiée ; les images et tableaux ne sont pas repris.'),
          onTap: () => Navigator.pop(ctx, WordExportMode.text),
        ),
        ListTile(
          leading: const Icon(Icons.image_outlined),
          title: const Text('Mise en page identique'),
          subtitle: const Text('Chaque page est insérée comme une image : rendu fidèle, '
              'mais le texte n\'est pas modifiable. Idéal pour les documents scannés.'),
          onTap: () => Navigator.pop(ctx, WordExportMode.layout),
        ),
      ]),
    ),
  );
  if (mode == null || !context.mounted) return;

  final title = pdfName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
  Uint8List? docx;
  while (docx == null) {
    try {
      docx = await _convert(context, pdf, mode!, title);
    } on NoTextException {
      if (!context.mounted) return;
      final ok = await confirm(
        context,
        'Aucun texte trouvé',
        'Ce PDF ne contient pas de texte (document scanné ou image). '
            'Voulez-vous l\'exporter avec la mise en page identique (pages en images) ?',
        okLabel: 'Exporter en images',
      );
      if (!ok || !context.mounted) return;
      mode = WordExportMode.layout;
    } catch (e) {
      if (context.mounted) toast(context, 'Conversion impossible : $e');
      return;
    }
    if (!context.mounted) return;
  }

  final fileName = '$title.docx';
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(fileName, style: const TextStyle(fontWeight: FontWeight.w600))),
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: const Text('Enregistrer sur le téléphone'),
          onTap: () => Navigator.pop(ctx, 'save'),
        ),
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: const Text('Partager / ouvrir avec…'),
          onTap: () => Navigator.pop(ctx, 'share'),
        ),
      ]),
    ),
  );
  if (action == 'save') {
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: docx, mimeType: WordExport.mimeType);
    if (uri != null && context.mounted) toast(context, 'Document Word enregistré');
  } else if (action == 'share') {
    final tmp = await Directory.systemTemp.createTemp('word');
    final f = await File('${tmp.path}/$fileName').writeAsBytes(docx);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: WordExport.mimeType)]));
  }
}

Future<Uint8List> _convert(BuildContext context, Uint8List pdf, WordExportMode mode, String title) async {
  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Conversion en Word…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: v > 0 ? v : null),
            const SizedBox(height: 12),
            Text('${(v * 100).round()} %'),
          ]),
        ),
      ),
    ),
  );
  try {
    return await WordExport.fromPdf(pdf, mode, title: title, onProgress: (v) => progress.value = v);
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
  }
}
