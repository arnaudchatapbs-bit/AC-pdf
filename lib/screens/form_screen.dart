import 'package:flutter/material.dart';

import '../services/pdf_service.dart';

/// Résultat de l'écran de formulaire.
class FormResult {
  FormResult(this.fields, this.flatten);
  final List<FormFieldInfo> fields;
  final bool flatten;
}

/// Liste éditable des champs de formulaire du PDF.
class FormScreen extends StatefulWidget {
  const FormScreen({super.key, required this.fields});
  final List<FormFieldInfo> fields;

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  bool _flatten = false;
  late final Map<int, TextEditingController> _ctrls = {
    for (final f in widget.fields)
      if (f.kind == FieldKind.text) f.index: TextEditingController(text: f.value),
  };

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    for (final f in widget.fields) {
      final c = _ctrls[f.index];
      if (c != null) f.value = c.text;
    }
    Navigator.pop(context, FormResult(widget.fields, _flatten));
  }

  Widget _fieldWidget(FormFieldInfo f) {
    final enabled = !f.readOnly;
    switch (f.kind) {
      case FieldKind.text:
        return TextField(
          controller: _ctrls[f.index],
          enabled: enabled,
          minLines: f.multiline ? 2 : 1,
          maxLines: f.multiline ? 6 : 1,
          decoration: InputDecoration(labelText: f.name, border: const OutlineInputBorder()),
        );
      case FieldKind.checkbox:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.name),
          value: f.checked,
          onChanged: enabled ? (v) => setState(() => f.checked = v) : null,
        );
      case FieldKind.radio:
      case FieldKind.combo:
      case FieldKind.list:
        return DropdownButtonFormField<int>(
          initialValue: f.selectedIndex >= 0 && f.selectedIndex < f.options.length ? f.selectedIndex : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: f.name, border: const OutlineInputBorder()),
          items: [
            for (var i = 0; i < f.options.length; i++) DropdownMenuItem(value: i, child: Text(f.options[i])),
          ],
          onChanged: enabled ? (v) => setState(() => f.selectedIndex = v ?? -1) : null,
        );
      case FieldKind.unsupported:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.block),
          title: Text(f.name),
          subtitle: const Text('Type de champ non modifiable ici (ex. signature numérique)'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remplir le formulaire'),
        actions: [
          FilledButton(onPressed: _apply, child: const Text('Appliquer')),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final f in widget.fields) ...[
            _fieldWidget(f),
            const SizedBox(height: 14),
          ],
          const Divider(),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _flatten,
            onChanged: (v) => setState(() => _flatten = v ?? false),
            title: const Text('Figer le formulaire'),
            subtitle: const Text('Les champs deviennent du texte définitif et ne sont plus modifiables.'),
          ),
        ],
      ),
    );
  }
}
