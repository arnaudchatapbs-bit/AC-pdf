import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Bibliothèque locale des PDF de l'application (stockage interne, hors ligne).
class DocumentStore {
  DocumentStore._();

  static Future<Directory> _dir(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$name');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> documentsDir() => _dir('pdf');
  static Future<Directory> signaturesDir() => _dir('signatures');

  /// Liste des PDF, du plus récent au plus ancien.
  static Future<List<File>> list() async {
    final dir = await documentsDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// Nettoie un nom de fichier et garantit l'extension .pdf.
  static String sanitize(String name) {
    var n = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (n.isEmpty) n = 'document';
    if (!n.toLowerCase().endsWith('.pdf')) n = '$n.pdf';
    return n;
  }

  /// Crée un nouveau fichier sans écraser un fichier existant.
  static Future<File> create(String name, Uint8List bytes) async {
    final dir = await documentsDir();
    final clean = sanitize(name);
    final base = clean.substring(0, clean.length - 4);
    var candidate = File('${dir.path}${Platform.pathSeparator}$clean');
    var i = 2;
    while (await candidate.exists()) {
      candidate = File('${dir.path}${Platform.pathSeparator}$base ($i).pdf');
      i++;
    }
    return candidate.writeAsBytes(bytes, flush: true);
  }

  static Future<File> rename(File file, String newName) async {
    final dir = file.parent;
    final target = File('${dir.path}${Platform.pathSeparator}${sanitize(newName)}');
    if (await target.exists()) {
      throw const FileSystemException('Un fichier porte déjà ce nom');
    }
    return file.rename(target.path);
  }

  static String displayName(File f) {
    final name = f.uri.pathSegments.last;
    return Uri.decodeComponent(name);
  }

  // --- Signatures enregistrées ---------------------------------------------

  static Future<List<File>> listSignatures() async {
    final dir = await signaturesDir();
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  static Future<File> saveSignature(Uint8List png) async {
    final dir = await signaturesDir();
    return File('${dir.path}${Platform.pathSeparator}sig_${DateTime.now().millisecondsSinceEpoch}.png')
        .writeAsBytes(png, flush: true);
  }
}
