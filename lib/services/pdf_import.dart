import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../widgets/dialogs.dart';

/// Vérifie qu'un fichier est un PDF lisible. S'il est protégé par mot de
/// passe, demande le mot de passe puis renvoie une copie déverrouillée
/// (nécessaire pour pouvoir le modifier). Renvoie null si annulé / invalide.
Future<Uint8List?> preparePdfForEditing(BuildContext context, Uint8List bytes) async {
  var askedPassword = false;
  PdfDocument? doc;
  try {
    doc = await PdfDocument.openData(
      bytes,
      sourceName: 'import-${DateTime.now().microsecondsSinceEpoch}',
      passwordProvider: () async {
        askedPassword = true;
        if (!context.mounted) return null;
        return askText(context, title: 'PDF protégé', label: 'Mot de passe', obscure: true, okLabel: 'Ouvrir');
      },
    );
    if (!askedPassword) return bytes;
    return await doc.encodePdf(removeSecurity: true);
  } catch (e) {
    if (context.mounted) {
      toast(context, askedPassword ? 'Mot de passe incorrect ou annulé' : 'Fichier PDF illisible');
    }
    return null;
  } finally {
    await doc?.dispose();
  }
}
