import 'package:flutter/material.dart';

Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? label,
  String okLabel = 'OK',
  bool obscure = false,
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(okLabel)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String message, {String okLabel = 'OK'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okLabel)),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Affiche un indicateur de chargement bloquant pendant [task].
Future<T> withProgress<T>(BuildContext context, Future<T> Function() task, {String message = 'Traitement…'}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(message)),
        ]),
      ),
    ),
  );
  try {
    // Laisse le temps au dialogue de s'afficher avant un traitement lourd.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return await task();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}
