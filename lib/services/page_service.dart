import 'dart:typed_data';
import 'dart:ui';

import 'package:pdfrx_engine/pdfrx_engine.dart' as rx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// Une page dans une opération de réorganisation.
class PageSpec {
  const PageSpec(this.docIndex, this.pageIndex, {this.quarterTurns = 0, this.blankSize});

  /// 0 = document courant, 1.. = documents ajoutés (fusion).
  final int docIndex;

  /// Index (0-based) de la page dans le document source.
  final int pageIndex;

  /// Rotation supplémentaire en quarts de tour horaires.
  final int quarterTurns;

  /// Si non nul : page blanche de cette taille (points), docIndex/pageIndex ignorés.
  final Size? blankSize;

  PageSpec rotated(int delta) =>
      PageSpec(docIndex, pageIndex, quarterTurns: (quarterTurns + delta) % 4, blankSize: blankSize);
}

/// Opérations sur les pages (moteur PDFium via pdfrx), 100 % locales.
class PageService {
  PageService._();

  // ---------------------------------------------------------------------------
  // Pages : réorganiser, pivoter, supprimer, fusionner, insérer des pages blanches
  // ---------------------------------------------------------------------------

  /// Construit un nouveau PDF à partir de [specs]. Les pages proviennent de
  /// [current] (docIndex 0) ou de [extras] (docIndex 1..).
  static Future<Uint8List> rebuildPages(
    Uint8List current,
    List<PageSpec> specs, {
    List<Uint8List> extras = const [],
  }) async {
    // Les pages blanches sont fabriquées dans un petit document dédié.
    final blanks = specs.where((s) => s.blankSize != null).toList();
    Uint8List? blankDocBytes;
    if (blanks.isNotEmpty) {
      final d = sf.PdfDocument();
      d.pageSettings.margins.all = 0;
      for (final b in blanks) {
        final section = d.sections!.add();
        section.pageSettings.size = b.blankSize!;
        section.pageSettings.margins.all = 0;
        section.pages.add();
      }
      blankDocBytes = Uint8List.fromList(d.saveSync());
      d.dispose();
    }

    final docs = <rx.PdfDocument>[];
    try {
      docs.add(await rx.PdfDocument.openData(current, sourceName: 'current-${_uid()}'));
      for (final e in extras) {
        docs.add(await rx.PdfDocument.openData(e, sourceName: 'extra-${_uid()}'));
      }
      rx.PdfDocument? blankDoc;
      if (blankDocBytes != null) {
        blankDoc = await rx.PdfDocument.openData(blankDocBytes, sourceName: 'blank-${_uid()}');
        docs.add(blankDoc);
      }

      var blankCursor = 0;
      final pages = <rx.PdfPage>[];
      for (final s in specs) {
        rx.PdfPage page;
        if (s.blankSize != null) {
          page = blankDoc!.pages[blankCursor++];
        } else {
          page = docs[s.docIndex].pages[s.pageIndex];
        }
        if (s.quarterTurns % 4 != 0) {
          page = page.rotatedBy(rx.PdfPageRotation.values[s.quarterTurns % 4]);
        }
        pages.add(page);
      }
      final target = docs.first;
      target.pages = pages;
      return await target.encodePdf();
    } finally {
      for (final d in docs.reversed) {
        await d.dispose();
      }
    }
  }

  static int _uidCounter = 0;
  static String _uid() => '${DateTime.now().microsecondsSinceEpoch}-${_uidCounter++}';
}
