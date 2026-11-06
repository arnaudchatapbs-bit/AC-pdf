import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import 'docx_builder.dart';

/// Conversion PDF -> Word (.docx), entièrement sur le téléphone : chaque page
/// est insérée comme une image (rendu identique à l'original).
class WordExport {
  WordExport._();

  static const String mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  static Future<Uint8List> fromPdf(
    Uint8List pdf, {
    String title = '',
    void Function(double progress)? onProgress,
  }) async {
    final doc = await PdfDocument.openData(pdf, sourceName: 'word-${DateTime.now().microsecondsSinceEpoch}');
    try {
      final first = doc.pages.first;
      final blocks = await _imageBlocks(doc, onProgress);
      final builder = DocxBuilder(pageWidthPt: first.width, pageHeightPt: first.height, title: title);
      return await compute(_buildJob, (builder, blocks));
    } finally {
      await doc.dispose();
    }
  }

  static Uint8List _buildJob((DocxBuilder, List<DocxBlock>) a) => a.$1.build(a.$2);

  static Future<List<DocxBlock>> _imageBlocks(PdfDocument doc, void Function(double)? onProgress) async {
    const dpi = 150.0;
    final blocks = <DocxBlock>[];
    for (var i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      const k = dpi / 72;
      final img = await page.renderForDisplay(
        fullWidth: page.width * k,
        fullHeight: page.height * k,
        backgroundColor: 0xffffffff,
        pixelSizeThreshold: 2400,
      );
      if (img == null) continue;
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (data == null) continue;
      blocks.add(DocxPageImage(data.buffer.asUint8List(), widthPt: page.width, heightPt: page.height));
      onProgress?.call((i + 1) / doc.pages.length * 0.9);
    }
    return blocks;
  }
}
