import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import 'docx_builder.dart';

enum WordExportMode {
  /// Texte extrait et modifiable dans Word (mise en page approximative).
  text,

  /// Chaque page devient une image : rendu identique, texte non modifiable.
  layout,
}

class NoTextException implements Exception {
  const NoTextException();
}

/// Conversion PDF -> Word (.docx), entièrement sur le téléphone.
class WordExport {
  WordExport._();

  static const String mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  static Future<Uint8List> fromPdf(
    Uint8List pdf,
    WordExportMode mode, {
    String title = '',
    void Function(double progress)? onProgress,
  }) async {
    final doc = await PdfDocument.openData(pdf, sourceName: 'word-${DateTime.now().microsecondsSinceEpoch}');
    try {
      final first = doc.pages.first;
      final (blocks, margins) = mode == WordExportMode.text
          ? await _textBlocks(doc, onProgress)
          : (await _imageBlocks(doc, onProgress), (56.7, 56.7, 56.7));
      final builder = DocxBuilder(
        pageWidthPt: first.width,
        pageHeightPt: first.height,
        marginPt: margins.$1,
        marginTopPt: margins.$2,
        marginBottomPt: margins.$3,
        title: title,
      );
      return await compute(_buildJob, (builder, blocks));
    } finally {
      await doc.dispose();
    }
  }

  static Uint8List _buildJob((DocxBuilder, List<DocxBlock>) a) => a.$1.build(a.$2);

  // ---------------------------------------------------------------------------
  // Mode texte
  // ---------------------------------------------------------------------------

  /// Renvoie les blocs et les marges (gauche, haut, bas) en points.
  static Future<(List<DocxBlock>, (double, double, double))> _textBlocks(PdfDocument doc, void Function(double)? onProgress) async {
    final perPage = <List<TextLine>>[];
    for (var i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final text = await page.loadStructuredText(ensureLoaded: true);
      perPage.add(_lines(text, page.height));
      onProgress?.call((i + 1) / doc.pages.length * 0.9);
    }
    final all = perPage.expand((l) => l).toList();
    if (all.isEmpty) throw const NoTextException();

    // Marge gauche commune : position la plus à gauche du texte (bornée).
    final lefts = all.map((l) => l.left).toList()..sort();
    final margin = lefts[(lefts.length * 0.05).floor()].clamp(28.0, 90.0);
    // Haut : début du texte. Bas : fin du texte moins une réserve, car Word
    // n'a pas exactement les mêmes polices et accumulerait un débordement.
    final pageH = doc.pages.first.height;
    final top = all.map((l) => l.top).reduce(math.min).clamp(20.0, 90.0);
    final bottom = (pageH - all.map((l) => l.bottom).reduce(math.max) - 24).clamp(14.0, 90.0);

    final blocks = <DocxBlock>[];
    for (var i = 0; i < perPage.length; i++) {
      if (i > 0) blocks.add(DocxPageBreak());
      blocks.addAll(linesToParagraphs(perPage[i], marginLeft: margin));
    }
    return (blocks, (margin, top, bottom));
  }

  /// Découpe le texte de la page en lignes avec leur position (Y vers le bas).
  static List<TextLine> _lines(PdfPageText text, double pageHeight) {
    final out = <TextLine>[];
    final full = text.fullText;
    var start = 0;
    while (start <= full.length) {
      var end = full.indexOf('\n', start);
      if (end < 0) end = full.length;
      final lineText = full.substring(start, end).replaceAll('\r', '');
      if (lineText.trim().isNotEmpty) {
        double l = double.infinity, r = -double.infinity, t = -double.infinity, b = double.infinity;
        for (var k = start; k < end && k < text.charRects.length; k++) {
          final rc = text.charRects[k];
          if (rc.isEmpty) continue;
          l = math.min(l, rc.left);
          r = math.max(r, rc.right);
          t = math.max(t, rc.top);
          b = math.min(b, rc.bottom);
        }
        if (l.isFinite) {
          out.add(TextLine(lineText, left: l, right: r, top: pageHeight - t, bottom: pageHeight - b));
        }
      }
      start = end + 1;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Mode mise en page identique
  // ---------------------------------------------------------------------------

  static Future<List<DocxBlock>> _imageBlocks(PdfDocument doc, void Function(double)? onProgress) async {
    const dpi = 150.0;
    final blocks = <DocxBlock>[];
    for (var i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final k = dpi / 72;
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
