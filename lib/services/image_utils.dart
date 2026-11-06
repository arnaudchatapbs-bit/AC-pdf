import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Applique l'orientation EXIF d'une photo aux pixels.
///
/// Sur Android, les photos gardent souvent leur rotation dans les métadonnées
/// EXIF : Flutter l'applique à l'affichage, mais pas le PDF. Sans cette étape,
/// une photo prise à la verticale apparaîtrait couchée dans le document.
Future<Uint8List> normalizePhoto(Uint8List bytes) => compute(_normalize, bytes);

Uint8List _normalize(Uint8List bytes) {
  // Seuls les JPEG portent une orientation EXIF.
  if (bytes.length < 3 || bytes[0] != 0xFF || bytes[1] != 0xD8) return bytes;
  final decoded = img.decodeJpg(bytes);
  if (decoded == null) return bytes;
  final orientation = decoded.exif.imageIfd.orientation ?? 1;
  if (orientation == 1) return bytes;
  return img.encodeJpg(img.bakeOrientation(decoded), quality: 88);
}
