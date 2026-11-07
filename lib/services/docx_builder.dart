import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Élément d'un document Word.
sealed class DocxBlock {}

class DocxParagraph extends DocxBlock {
  DocxParagraph(this.text,
      {this.fontSize = 11, this.indent = 0, this.firstLine = 0, this.spaceBefore = 0, this.lineSpacing = 0});
  final String text;

  /// Taille de police en points.
  final double fontSize;

  /// Retrait gauche en points (par rapport à la marge).
  final double indent;

  /// Retrait supplémentaire de la première ligne (alinéa), en points.
  final double firstLine;

  /// Espace avant le paragraphe en points.
  final double spaceBefore;

  /// Interligne (distance entre lignes de base) en points ; 0 = automatique.
  final double lineSpacing;
}

/// Une page rendue en image (mode « mise en page identique »).
class DocxPageImage extends DocxBlock {
  DocxPageImage(this.png, {required this.widthPt, required this.heightPt});
  final Uint8List png;
  final double widthPt;
  final double heightPt;
}

/// Saut de page (mode texte).
class DocxPageBreak extends DocxBlock {}

/// Génère un fichier .docx (Office Open XML) minimal mais valide.
class DocxBuilder {
  DocxBuilder({
    required this.pageWidthPt,
    required this.pageHeightPt,
    this.marginPt = 56.7,
    double? marginTopPt,
    double? marginBottomPt,
    this.title = '',
  })  : marginTopPt = marginTopPt ?? marginPt,
        marginBottomPt = marginBottomPt ?? marginPt;

  /// Format de page par défaut (mode texte).
  final double pageWidthPt;
  final double pageHeightPt;
  /// Marges gauche/droite (et haut/bas par défaut), en points.
  final double marginPt;
  final double marginTopPt;
  final double marginBottomPt;
  final String title;

  static int _tw(double pt) => (pt * 20).round(); // twips
  static int _emu(double pt) => (pt * 12700).round();

  static final _invalidXml = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]');

  static String esc(String s) => s
      .replaceAll(_invalidXml, '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _sectPr(double w, double h, double margin, {double? top, double? bottom}) {
    final orient = w > h ? ' w:orient="landscape"' : '';
    final m = _tw(margin);
    return '<w:sectPr><w:pgSz w:w="${_tw(w)}" w:h="${_tw(h)}"$orient/>'
        '<w:pgMar w:top="${_tw(top ?? margin)}" w:right="$m" w:bottom="${_tw(bottom ?? margin)}" w:left="$m" '
        'w:header="0" w:footer="0" w:gutter="0"/>'
        '</w:sectPr>';
  }

  Uint8List build(List<DocxBlock> blocks) {
    final body = StringBuffer();
    final images = <Uint8List>[];
    const imgMargin = 14.0;

    var pendingBreak = false;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      switch (b) {
        case DocxParagraph():
          final sz = (b.fontSize * 2).round();
          body.write('<w:p><w:pPr>');
          if (pendingBreak) body.write('<w:pageBreakBefore/>');
          pendingBreak = false;
          final line = b.lineSpacing > 0 ? ' w:line="${_tw(b.lineSpacing)}" w:lineRule="atLeast"' : '';
          final before = b.spaceBefore;
          body.write('<w:spacing w:before="${_tw(before)}" w:after="0"$line/>');
          if (b.indent > 1 || b.firstLine > 1) {
            body.write('<w:ind w:left="${_tw(b.indent)}" w:firstLine="${_tw(b.firstLine)}"/>');
          }
          body.write('</w:pPr><w:r><w:rPr><w:sz w:val="$sz"/><w:szCs w:val="$sz"/></w:rPr>'
              '<w:t xml:space="preserve">${esc(b.text)}</w:t></w:r></w:p>');
        case DocxPageBreak():
          // Porté par le paragraphe suivant ; page vide d'origine -> paragraphe vide.
          if (pendingBreak) body.write('<w:p><w:pPr><w:pageBreakBefore/></w:pPr></w:p>');
          pendingBreak = true;
        case DocxPageImage():
          images.add(b.png);
          final n = images.length;
          // Image légèrement plus petite que la zone utile : évite une page blanche ajoutée par Word.
          final maxW = b.widthPt - imgMargin * 2, maxH = b.heightPt - imgMargin * 2 - 2;
          final k = math.min(maxW / b.widthPt, maxH / b.heightPt);
          final cx = _emu(b.widthPt * k), cy = _emu(b.heightPt * k);
          final isLast = i == blocks.length - 1;
          body.write('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
              '<w:jc w:val="center"/>');
          // Chaque page image forme sa propre section (taille / orientation de la page d'origine).
          if (!isLast) body.write(_sectPr(b.widthPt, b.heightPt, imgMargin));
          body.write('</w:pPr><w:r><w:drawing>'
              '<wp:inline distT="0" distB="0" distL="0" distR="0">'
              '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$n" name="Page $n"/>'
              '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
              '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
              '<pic:pic><pic:nvPicPr><pic:cNvPr id="$n" name="page$n.png"/><pic:cNvPicPr/></pic:nvPicPr>'
              '<pic:blipFill><a:blip r:embed="rIdImg$n"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
              '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
              '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
              '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>');
      }
    }

    // Section finale.
    final last = blocks.isNotEmpty ? blocks.last : null;
    final finalSect = last is DocxPageImage
        ? _sectPr(last.widthPt, last.heightPt, imgMargin)
        : _sectPr(pageWidthPt, pageHeightPt, marginPt, top: marginTopPt, bottom: marginBottomPt);

    final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$body$finalSect</w:body></w:document>';

    const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '</Types>';

    const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
        'Target="docProps/core.xml"/>'
        '</Relationships>';

    final docRels = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        'Target="styles.xml"/>');
    for (var n = 1; n <= images.length; n++) {
      docRels.write('<Relationship Id="rIdImg$n" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/page$n.png"/>');
    }
    docRels.write('</Relationships>');

    const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>'
        '<w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="fr-FR"/></w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="252" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
        '</w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
        '</w:styles>';

    final now = DateTime.now().toUtc().toIso8601String().split('.').first;
    final core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${esc(title)}</dc:title><dc:creator>ACpdf</dc:creator>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${now}Z</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">${now}Z</dcterms:modified>'
        '</cp:coreProperties>';

    final archive = Archive();
    void add(String name, List<int> data) => archive.addFile(ArchiveFile(name, data.length, data));
    add('[Content_Types].xml', utf8.encode(contentTypes));
    add('_rels/.rels', utf8.encode(rootRels));
    add('word/document.xml', utf8.encode(document));
    add('word/_rels/document.xml.rels', utf8.encode(docRels.toString()));
    add('word/styles.xml', utf8.encode(styles));
    add('docProps/core.xml', utf8.encode(core));
    for (var n = 1; n <= images.length; n++) {
      add('word/media/page$n.png', images[n - 1]);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
