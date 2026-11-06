import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../models/annotation.dart';

/// Hauteur de ligne (en multiple de la taille de police) utilisée à la fois
/// pour l'aperçu à l'écran et pour l'écriture dans le PDF.
const double kTextLineHeight = 1.2;

enum FieldKind { text, checkbox, radio, combo, list, unsupported }

/// Description d'un champ de formulaire PDF.
class FormFieldInfo {
  FormFieldInfo({
    required this.index,
    required this.name,
    required this.kind,
    this.value = '',
    this.checked = false,
    this.options = const [],
    this.selectedIndex = -1,
    this.readOnly = false,
    this.multiline = false,
  });

  final int index;
  final String name;
  final FieldKind kind;
  String value;
  bool checked;
  final List<String> options;
  int selectedIndex;
  final bool readOnly;
  final bool multiline;
}

/// Opérations d'édition de PDF, 100 % locales (aucun accès réseau).
class PdfService {
  PdfService._();

  // ---------------------------------------------------------------------------
  // Création
  // ---------------------------------------------------------------------------

  /// Crée un PDF vierge (A4 portrait) de [pageCount] pages.
  static Uint8List createBlank({int pageCount = 1}) {
    final doc = sf.PdfDocument();
    doc.pageSettings.size = sf.PdfPageSize.a4;
    doc.pageSettings.margins.all = 0;
    for (var i = 0; i < pageCount; i++) {
      doc.pages.add();
    }
    final bytes = Uint8List.fromList(doc.saveSync());
    doc.dispose();
    return bytes;
  }

  /// Crée un PDF à partir d'images (une image par page, page à la taille de l'image, max A4).
  static Uint8List createFromImages(List<Uint8List> images) {
    final doc = sf.PdfDocument();
    doc.pageSettings.margins.all = 0;
    for (final img in images) {
      final bmp = sf.PdfBitmap(img);
      final a4 = sf.PdfPageSize.a4;
      final landscape = bmp.width > bmp.height;
      final pageSize = landscape ? Size(a4.height, a4.width) : a4;
      final section = doc.sections!.add();
      section.pageSettings.size = pageSize;
      section.pageSettings.margins.all = 0;
      final page = section.pages.add();
      final scale = math.min(pageSize.width / bmp.width, pageSize.height / bmp.height);
      final w = bmp.width * scale, h = bmp.height * scale;
      page.graphics.drawImage(
          bmp, Rect.fromLTWH((pageSize.width - w) / 2, (pageSize.height - h) / 2, w, h));
    }
    final bytes = Uint8List.fromList(doc.saveSync());
    doc.dispose();
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Annotations : écriture définitive dans le PDF
  // ---------------------------------------------------------------------------

  /// Écrit les annotations ([byPage] : index de page 0-based -> annotations)
  /// dans le contenu des pages. Les coordonnées des annotations sont relatives
  /// à la page telle qu'elle est affichée (rotation incluse).
  /// [fontBytes] : police TrueType (Unicode) pour le texte ; Helvetica sinon.
  static Uint8List flattenAnnotations(
    Uint8List bytes,
    Map<int, List<Annot>> byPage, {
    List<int>? fontBytes,
  }) {
    if (byPage.values.every((l) => l.isEmpty)) return bytes;
    final doc = sf.PdfDocument(inputBytes: bytes);
    try {
      for (final entry in byPage.entries) {
        if (entry.value.isEmpty) continue;
        if (entry.key < 0 || entry.key >= doc.pages.count) continue;
        _drawOnPage(doc.pages[entry.key], entry.value, fontBytes);
      }
      return Uint8List.fromList(doc.saveSync());
    } finally {
      doc.dispose();
    }
  }

  static int _quarterTurns(sf.PdfPageRotateAngle a) => switch (a) {
        sf.PdfPageRotateAngle.rotateAngle0 => 0,
        sf.PdfPageRotateAngle.rotateAngle90 => 1,
        sf.PdfPageRotateAngle.rotateAngle180 => 2,
        sf.PdfPageRotateAngle.rotateAngle270 => 3,
      };

  static void _drawOnPage(sf.PdfPage page, List<Annot> annots, List<int>? fontBytes) {
    final g = page.graphics;
    // Taille non pivotée de la zone de dessin (espace des graphiques Syncfusion).
    final size = g.clientSize;
    final w = size.width, h = size.height;
    final turns = _quarterTurns(page.rotation);
    // Taille telle qu'affichée à l'utilisateur.
    final dw = turns.isOdd ? h : w;
    final dh = turns.isOdd ? w : h;

    g.save();
    // Transforme l'espace "page affichée" (y vers le bas) vers l'espace non pivoté.
    switch (turns) {
      case 1:
        g.translateTransform(0, h);
        g.rotateTransform(-90);
      case 2:
        g.translateTransform(w, h);
        g.rotateTransform(180);
      case 3:
        g.translateTransform(w, 0);
        g.rotateTransform(90);
    }

    Offset pt(Offset n) => Offset(n.dx * dw, n.dy * dh);
    Rect rect(Rect n) => Rect.fromLTRB(n.left * dw, n.top * dh, n.right * dw, n.bottom * dh);

    for (final a in annots) {
      final color = _sfColor(a.color);
      sf.PdfPen pen() => sf.PdfPen(color, width: a.strokeWidth)
        ..lineCap = sf.PdfLineCap.round
        ..lineJoin = sf.PdfLineJoin.round;

      switch (a.type) {
        case AnnotType.ink:
          if (a.points.length == 1) {
            final p = pt(a.points.first);
            final r = a.strokeWidth / 2;
            g.drawEllipse(Rect.fromCircle(center: p, radius: r), brush: sf.PdfSolidBrush(color));
          } else if (a.points.length > 1) {
            final path = sf.PdfPath();
            for (var i = 1; i < a.points.length; i++) {
              path.addLine(pt(a.points[i - 1]), pt(a.points[i]));
            }
            g.drawPath(path, pen: pen());
          }
        case AnnotType.highlight:
          final state = g.save();
          g.setTransparency(0.35, mode: sf.PdfBlendMode.multiply);
          g.drawRectangle(bounds: rect(a.normRect), brush: sf.PdfSolidBrush(color));
          g.restore(state);
        case AnnotType.rect:
          g.drawRectangle(bounds: rect(a.normRect), pen: pen());
        case AnnotType.ellipse:
          g.drawEllipse(rect(a.normRect), pen: pen());
        case AnnotType.line:
          g.drawLine(pen(), pt(a.points.first), pt(a.points.last));
        case AnnotType.arrow:
          final p1 = pt(a.points.first), p2 = pt(a.points.last);
          g.drawLine(pen(), p1, p2);
          for (final head in arrowHead(p1, p2, a.strokeWidth)) {
            g.drawLine(pen(), p2, head);
          }
        case AnnotType.text:
          final text = a.text ?? '';
          if (text.isEmpty) break;
          final sf.PdfFont font = fontBytes != null
              ? sf.PdfTrueTypeFont(fontBytes, a.fontSize)
              : sf.PdfStandardFont(sf.PdfFontFamily.helvetica, a.fontSize);
          final brush = sf.PdfSolidBrush(color);
          final origin = pt(a.points.first);
          final lines = text.split('\n');
          for (var i = 0; i < lines.length; i++) {
            g.drawString(lines[i], font,
                brush: brush,
                bounds: Rect.fromLTWH(origin.dx, origin.dy + i * a.fontSize * kTextLineHeight, 0, 0));
          }
        case AnnotType.image:
          final bytes = a.imageBytes;
          if (bytes == null) break;
          g.drawImage(sf.PdfBitmap(bytes), rect(a.normRect));
      }
    }
    g.restore();
  }

  /// Les deux extrémités de la pointe d'une flèche allant de [p1] à [p2].
  static List<Offset> arrowHead(Offset p1, Offset p2, double strokeWidth) {
    final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
    final len = math.max(8.0, strokeWidth * 4);
    const spread = math.pi / 7;
    return [
      p2 - Offset(math.cos(angle - spread), math.sin(angle - spread)) * len,
      p2 - Offset(math.cos(angle + spread), math.sin(angle + spread)) * len,
    ];
  }

  static sf.PdfColor _sfColor(Color c) => sf.PdfColor(
        (c.r * 255).round(),
        (c.g * 255).round(),
        (c.b * 255).round(),
      );

  // ---------------------------------------------------------------------------
  // Formulaires
  // ---------------------------------------------------------------------------

  static List<FormFieldInfo> readFormFields(Uint8List bytes) {
    final doc = sf.PdfDocument(inputBytes: bytes);
    try {
      final fields = doc.form.fields;
      final out = <FormFieldInfo>[];
      for (var i = 0; i < fields.count; i++) {
        final f = fields[i];
        final name = (f.name == null || f.name!.isEmpty) ? 'Champ ${i + 1}' : f.name!;
        if (f is sf.PdfTextBoxField) {
          out.add(FormFieldInfo(
              index: i,
              name: name,
              kind: FieldKind.text,
              value: f.text,
              readOnly: f.readOnly,
              multiline: f.multiline));
        } else if (f is sf.PdfCheckBoxField) {
          out.add(FormFieldInfo(
              index: i, name: name, kind: FieldKind.checkbox, checked: f.isChecked, readOnly: f.readOnly));
        } else if (f is sf.PdfRadioButtonListField) {
          final opts = [for (var j = 0; j < f.items.count; j++) _label(f.items[j].value, j)];
          out.add(FormFieldInfo(
              index: i,
              name: name,
              kind: FieldKind.radio,
              options: opts,
              selectedIndex: f.selectedIndex,
              readOnly: f.readOnly));
        } else if (f is sf.PdfComboBoxField) {
          final opts = [for (var j = 0; j < f.items.count; j++) _label(f.items[j].text, j)];
          final sel = f.selectedIndex;
          out.add(FormFieldInfo(
              index: i,
              name: name,
              kind: FieldKind.combo,
              options: opts,
              selectedIndex: sel,
              value: f.editable ? f.selectedValue : '',
              readOnly: f.readOnly));
        } else if (f is sf.PdfListBoxField) {
          final opts = [for (var j = 0; j < f.items.count; j++) _label(f.items[j].text, j)];
          final sel = f.selectedIndexes;
          out.add(FormFieldInfo(
              index: i,
              name: name,
              kind: FieldKind.list,
              options: opts,
              selectedIndex: sel.isEmpty ? -1 : sel.first,
              readOnly: f.readOnly));
        } else {
          out.add(FormFieldInfo(index: i, name: name, kind: FieldKind.unsupported, readOnly: true));
        }
      }
      return out;
    } finally {
      doc.dispose();
    }
  }

  static String _label(String s, int j) => s.isEmpty ? 'Option ${j + 1}' : s;

  static Uint8List writeFormFields(Uint8List bytes, List<FormFieldInfo> infos, {bool flatten = false}) {
    final doc = sf.PdfDocument(inputBytes: bytes);
    try {
      final form = doc.form;
      form.setDefaultAppearance(false);
      final fields = form.fields;
      for (final info in infos) {
        if (info.readOnly || info.index >= fields.count) continue;
        final f = fields[info.index];
        switch (info.kind) {
          case FieldKind.text:
            if (f is sf.PdfTextBoxField && f.text != info.value) f.text = info.value;
          case FieldKind.checkbox:
            if (f is sf.PdfCheckBoxField && f.isChecked != info.checked) f.isChecked = info.checked;
          case FieldKind.radio:
            if (f is sf.PdfRadioButtonListField &&
                info.selectedIndex >= 0 &&
                f.selectedIndex != info.selectedIndex) {
              f.selectedIndex = info.selectedIndex;
            }
          case FieldKind.combo:
            if (f is sf.PdfComboBoxField &&
                info.selectedIndex >= 0 &&
                f.selectedIndex != info.selectedIndex) {
              f.selectedIndex = info.selectedIndex;
            }
          case FieldKind.list:
            if (f is sf.PdfListBoxField && info.selectedIndex >= 0) {
              f.selectedIndexes = [info.selectedIndex];
            }
          case FieldKind.unsupported:
            break;
        }
      }
      if (flatten) form.flattenAllFields();
      return Uint8List.fromList(doc.saveSync());
    } finally {
      doc.dispose();
    }
  }

}
