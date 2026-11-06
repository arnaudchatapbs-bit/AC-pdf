import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/annotation.dart';
import '../services/pdf_service.dart';

/// Police utilisée à l'écran pour le texte (identique à celle écrite dans le PDF).
const String kAnnotFont = 'PdfRoboto';

/// Rayon (px) de la poignée de redimensionnement.
const double kHandleRadius = 14;

bool isResizable(Annot a) => a.type != AnnotType.ink && a.type != AnnotType.text;

/// Géométrie d'une annotation dans l'espace écran de la page.
class AnnotGeometry {
  AnnotGeometry(this.size, this.pageWidthPts);

  /// Taille de la page à l'écran (px).
  final Size size;

  /// Largeur de la page affichée en points PDF.
  final double pageWidthPts;

  /// Pixels par point PDF.
  double get scale => size.width / pageWidthPts;

  Offset toPx(Offset n) => Offset(n.dx * size.width, n.dy * size.height);
  Offset toNorm(Offset px) => Offset(px.dx / size.width, px.dy / size.height);

  List<String> lines(Annot a) => (a.text ?? '').split('\n');

  TextPainter textPainter(Annot a, String line) => TextPainter(
        text: TextSpan(
          text: line,
          style: TextStyle(
            fontFamily: kAnnotFont,
            fontSize: a.fontSize * scale,
            fontWeight: a.bold ? FontWeight.w700 : FontWeight.w400,
            color: a.color,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  /// Rectangle englobant (px), sans marge de tolérance.
  Rect bounds(Annot a) {
    if (a.type == AnnotType.text) {
      final origin = toPx(a.points.first);
      var w = 0.0;
      final ls = lines(a);
      for (final l in ls) {
        w = math.max(w, textPainter(a, l).width);
      }
      final h = ls.length * a.fontSize * kTextLineHeight * scale;
      return Rect.fromLTWH(origin.dx, origin.dy, math.max(w, 8), h);
    }
    var r = Rect.fromPoints(toPx(a.points.first), toPx(a.points.first));
    for (final p in a.points) {
      r = r.expandToInclude(Rect.fromCenter(center: toPx(p), width: 0, height: 0));
    }
    return r.inflate(a.strokeWidth * scale / 2);
  }

  Offset handle(Annot a) {
    if (a.type == AnnotType.line || a.type == AnnotType.arrow) return toPx(a.points.last);
    return bounds(a).bottomRight;
  }

  bool hits(Annot a, Offset px, {double tolerance = 14}) {
    if (a.type == AnnotType.ink || a.type == AnnotType.line || a.type == AnnotType.arrow) {
      final tol = math.max(tolerance, a.strokeWidth * scale / 2 + 4);
      final pts = [for (final p in a.points) toPx(p)];
      if (pts.length == 1) return (pts.first - px).distance <= tol;
      for (var i = 1; i < pts.length; i++) {
        if (_distToSegment(px, pts[i - 1], pts[i]) <= tol) return true;
      }
      return false;
    }
    return bounds(a).inflate(tolerance / 2).contains(px);
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// Annotation la plus haute sous le point, ou null.
  Annot? hitTest(List<Annot> annots, Offset px) {
    for (final a in annots.reversed) {
      if (hits(a, px)) return a;
    }
    return null;
  }
}

class AnnotationPainter extends CustomPainter {
  AnnotationPainter({
    required this.annots,
    required this.pageWidthPts,
    required this.images,
    this.selectedId,
    required this.selectionColor,
  });

  final List<Annot> annots;
  final double pageWidthPts;
  final Map<String, ui.Image> images;
  final String? selectedId;
  final Color selectionColor;

  @override
  void paint(Canvas canvas, Size size) {
    final geo = AnnotGeometry(size, pageWidthPts);
    final s = geo.scale;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final a in annots) {
      final stroke = Paint()
        ..color = a.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = a.strokeWidth * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      switch (a.type) {
        case AnnotType.ink:
          if (a.points.length == 1) {
            canvas.drawCircle(geo.toPx(a.points.first), a.strokeWidth * s / 2, Paint()..color = a.color);
          } else {
            final path = Path()..moveTo(geo.toPx(a.points.first).dx, geo.toPx(a.points.first).dy);
            for (final p in a.points.skip(1)) {
              final q = geo.toPx(p);
              path.lineTo(q.dx, q.dy);
            }
            canvas.drawPath(path, stroke);
          }
        case AnnotType.highlight:
          canvas.drawRect(
            Rect.fromPoints(geo.toPx(a.points.first), geo.toPx(a.points.last)),
            Paint()
              ..color = a.color.withValues(alpha: 0.35)
              ..blendMode = BlendMode.multiply,
          );
        case AnnotType.rect:
          canvas.drawRect(Rect.fromPoints(geo.toPx(a.points.first), geo.toPx(a.points.last)), stroke);
        case AnnotType.ellipse:
          canvas.drawOval(Rect.fromPoints(geo.toPx(a.points.first), geo.toPx(a.points.last)), stroke);
        case AnnotType.line:
          canvas.drawLine(geo.toPx(a.points.first), geo.toPx(a.points.last), stroke);
        case AnnotType.arrow:
          final p1 = geo.toPx(a.points.first), p2 = geo.toPx(a.points.last);
          canvas.drawLine(p1, p2, stroke);
          // La pointe est calculée en points PDF puis convertie (même rendu que dans le PDF).
          final heads = PdfService.arrowHead(p1 / s, p2 / s, a.strokeWidth);
          for (final h in heads) {
            canvas.drawLine(p2, h * s, stroke);
          }
        case AnnotType.text:
          final origin = geo.toPx(a.points.first);
          final ls = geo.lines(a);
          for (var i = 0; i < ls.length; i++) {
            geo.textPainter(a, ls[i]).paint(canvas, origin + Offset(0, i * a.fontSize * kTextLineHeight * s));
          }
        case AnnotType.image:
          final r = Rect.fromPoints(geo.toPx(a.points.first), geo.toPx(a.points.last));
          final img = images[a.id];
          if (img != null) {
            paintImage(canvas: canvas, rect: r, image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
          } else {
            canvas.drawRect(r, Paint()..color = const Color(0x22000000));
          }
      }

      if (a.id == selectedId) {
        final b = geo.bounds(a).inflate(6);
        final sel = Paint()
          ..color = selectionColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        _dashedRect(canvas, b, sel);
        if (isResizable(a)) {
          final h = geo.handle(a);
          canvas.drawCircle(h, kHandleRadius * 0.6, Paint()..color = Colors.white);
          canvas.drawCircle(h, kHandleRadius * 0.6, sel..strokeWidth = 2);
        }
      }
    }
    canvas.restore();
  }

  void _dashedRect(Canvas canvas, Rect r, Paint p) {
    const dash = 6.0, gap = 4.0;
    void line(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      var d = 0.0;
      while (d < total) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), p);
        d += dash + gap;
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter old) => true;
}
