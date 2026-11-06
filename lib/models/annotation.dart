import 'dart:typed_data';
import 'dart:ui';

/// Types d'annotations que l'utilisateur peut poser sur une page.
enum AnnotType { ink, highlight, rect, ellipse, line, arrow, text, image }

/// Une annotation en attente, exprimée en coordonnées normalisées (0..1)
/// dans l'espace de la page telle qu'elle est affichée (rotation incluse).
///
/// - ink : [points] = tracé à main levée
/// - highlight / rect / ellipse / line / arrow / image : [points] = [début, fin]
/// - text : [points] = [coin haut-gauche]
class Annot {
  Annot({
    required this.type,
    required this.points,
    this.color = const Color(0xFFE53935),
    this.strokeWidth = 2,
    this.text,
    this.fontSize = 14,
    this.imageBytes,
    this.imageAspect,
    String? id,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  static int _counter = 0;

  final String id;
  final AnnotType type;
  List<Offset> points;
  Color color;

  /// Épaisseur du trait en points PDF.
  double strokeWidth;

  String? text;

  /// Taille de police en points PDF.
  double fontSize;

  /// Image PNG/JPEG (images et signatures).
  Uint8List? imageBytes;

  /// Ratio largeur/hauteur de l'image source (pour le redimensionnement).
  double? imageAspect;

  /// Copie indépendante. [keepId] conserve l'identifiant (historique annuler/rétablir).
  Annot copy({bool keepId = false}) => Annot(
        id: keepId ? id : null,
        type: type,
        points: List.of(points),
        color: color,
        strokeWidth: strokeWidth,
        text: text,
        fontSize: fontSize,
        imageBytes: imageBytes,
        imageAspect: imageAspect,
      );

  /// Rectangle normalisé formé par les deux premiers points.
  Rect get normRect => Rect.fromPoints(points.first, points.length > 1 ? points[1] : points.first);

  void translate(Offset delta) {
    points = [for (final p in points) p + delta];
  }
}
