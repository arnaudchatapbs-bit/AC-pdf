import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/word_export.dart';
import 'dialogs.dart';

/// Parcours complet : conversion (pages en images), puis enregistrement ou partage.
Future<void> exportToWord(BuildContext context, Uint8List pdf, String pdfName) async {
  final title = pdfName.replaceAll(RegExp(r'.pdf$', caseSensitive: false), '');
  final Uint8List docx;
  try {
    docx = await _convert(context, pdf, title);
  } catch (e) {
    if (context.mounted) toast(context, 'Conversion impossible : $e');
    return;
  }
  if (!context.mounted) return;

  final fileName = '$title.docx';
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text(fileName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text("Chaque page est insérée comme une image, à l'identique du PDF."),
        ),
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

Future<Uint8List> _convert(BuildContext context, Uint8List pdf, String title) async {
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
    return await WordExport.fromPdf(pdf, title: title, onProgress: (v) => progress.value = v);
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
  }
}
