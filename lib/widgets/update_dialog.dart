import 'package:flutter/material.dart';

import '../services/update_service.dart';
import 'dialogs.dart';

/// Propose la mise à jour, la télécharge puis ouvre l'installeur Android.
Future<void> offerUpdate(BuildContext context, UpdateInfo info) async {
  final sizeMb = info.size > 0 ? ' (${(info.size / 1024 / 1024).toStringAsFixed(0)} Mo)' : '';
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update),
      title: const Text('Mise à jour disponible'),
      content: Text(
        'ACpdf ${info.version} est disponible (vous avez la ${info.currentVersion}).\n\n'
        'Le téléchargement$sizeMb nécessite Internet. Vos documents sont conservés.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mettre à jour')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Téléchargement…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: v > 0 ? v : null),
            const SizedBox(height: 12),
            Text('${(v * 100).round()} %'),
          ]),
        ),
      ),
    ),
  );
  try {
    final apk = await UpdateService.download(info, (v) => progress.value = v);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    final error = await UpdateService.install(apk);
    if (error != null && context.mounted) toast(context, 'Installation impossible : $error');
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      toast(context, 'Échec du téléchargement. Vérifiez votre connexion et réessayez.');
    }
  } finally {
    progress.dispose();
  }
}

/// Vérification manuelle depuis le menu.
Future<void> checkForUpdateManually(BuildContext context) async {
  try {
    final info = await withProgress(context, () => UpdateService.check(throwOnError: true),
        message: 'Recherche de mise à jour…');
    if (!context.mounted) return;
    if (info == null) {
      toast(context, 'ACpdf est à jour');
    } else {
      await offerUpdate(context, info);
    }
  } catch (_) {
    if (context.mounted) toast(context, 'Impossible de vérifier : pas de connexion Internet ?');
  }
}
