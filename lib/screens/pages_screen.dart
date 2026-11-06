import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/page_service.dart';
import '../services/pdf_import.dart';
import '../widgets/dialogs.dart';
import '../widgets/page_image.dart';

/// Résultat de la gestion des pages.
class PagesResult {
  PagesResult(this.specs, this.extras);
  final List<PageSpec> specs;
  final List<Uint8List> extras;
}

class _Item {
  _Item(this.spec) : key = UniqueKey();
  PageSpec spec;
  final Key key;
}

/// Réorganiser, pivoter, dupliquer, supprimer des pages ; fusionner avec
/// d'autres PDF ; ajouter des pages blanches.
class PagesScreen extends StatefulWidget {
  const PagesScreen({super.key, required this.document});
  final PdfDocument document;

  @override
  State<PagesScreen> createState() => _PagesScreenState();
}

class _PagesScreenState extends State<PagesScreen> {
  late final List<_Item> _items = [
    for (var i = 0; i < widget.document.pages.length; i++) _Item(PageSpec(0, i)),
  ];
  final List<Uint8List> _extraBytes = [];
  final List<PdfDocument> _extraDocs = [];
  final Set<Key> _selected = {};

  @override
  void dispose() {
    for (final d in _extraDocs) {
      d.dispose();
    }
    super.dispose();
  }

  PdfDocument _docFor(PageSpec s) => s.docIndex == 0 ? widget.document : _extraDocs[s.docIndex - 1];

  Future<void> _merge() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (picked.isEmpty || !mounted) return;
    final raw = await picked.first.readAsBytes();
    if (!mounted) return;
    final bytes = await preparePdfForEditing(context, raw);
    if (bytes == null) return;
    final doc = await PdfDocument.openData(bytes, sourceName: 'merge-${DateTime.now().microsecondsSinceEpoch}');
    setState(() {
      _extraBytes.add(bytes);
      _extraDocs.add(doc);
      final idx = _extraDocs.length;
      for (var i = 0; i < doc.pages.length; i++) {
        _items.add(_Item(PageSpec(idx, i)));
      }
    });
    if (mounted) toast(context, '${doc.pages.length} page(s) ajoutée(s) à la fin');
  }

  void _addBlank() {
    // Même format que la dernière page (ou A4).
    Size size = const Size(595.28, 841.89);
    if (_items.isNotEmpty) {
      final last = _items.last.spec;
      if (last.blankSize != null) {
        size = last.blankSize!;
      } else {
        final p = _docFor(last).pages[last.pageIndex];
        size = Size(p.width, p.height);
      }
    }
    setState(() => _items.add(_Item(PageSpec(0, 0, blankSize: size))));
  }

  void _rotate(_Item it, int delta) => setState(() => it.spec = it.spec.rotated(delta < 0 ? 3 : 1));

  void _duplicate(int index) {
    setState(() => _items.insert(index + 1, _Item(_items[index].spec)));
  }

  void _delete(Iterable<_Item> items) {
    if (_items.length - items.length < 1) {
      toast(context, 'Le document doit garder au moins une page');
      return;
    }
    setState(() {
      final keys = items.map((e) => e.key).toSet();
      _items.removeWhere((e) => keys.contains(e.key));
      _selected.removeAll(keys);
    });
  }

  Widget _thumb(_Item it) {
    final s = it.spec;
    if (s.blankSize != null) {
      var w = s.blankSize!.width, h = s.blankSize!.height;
      if (s.quarterTurns.isOdd) (w, h) = (h, w);
      final k = 110 / (w > h ? w : h);
      return Container(
        width: w * k,
        height: h * k,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
        alignment: Alignment.center,
        child: const Text('Vierge', style: TextStyle(color: Colors.grey, fontSize: 11)),
      );
    }
    final page = _docFor(s).pages[s.pageIndex];
    final rot = s.quarterTurns == 0
        ? null
        : PdfPageRotation.values[(page.rotation.index + s.quarterTurns) % 4];
    return PageThumbnail(page: page, rotationOverride: rot, maxHeight: 110);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selection = _items.where((e) => _selected.contains(e.key)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(selection.isEmpty ? 'Pages (${_items.length})' : '${selection.length} sélectionnée(s)'),
        actions: [
          if (selection.isNotEmpty) ...[
            IconButton(
                tooltip: 'Pivoter la sélection',
                icon: const Icon(Icons.rotate_right),
                onPressed: () => setState(() {
                      for (final it in selection) {
                        it.spec = it.spec.rotated(1);
                      }
                    })),
            IconButton(
                tooltip: 'Supprimer la sélection',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(selection)),
          ],
          FilledButton(
            onPressed: () => Navigator.pop(
                context, PagesResult([for (final it in _items) it.spec], List.of(_extraBytes))),
            child: const Text('Valider'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _items.length,
        buildDefaultDragHandles: false,
        onReorderItem: (from, to) => setState(() {
          _items.insert(to, _items.removeAt(from));
        }),
        itemBuilder: (context, i) {
          final it = _items[i];
          final s = it.spec;
          final selected = _selected.contains(it.key);
          final origin = s.blankSize != null
              ? 'Page blanche'
              : s.docIndex == 0
                  ? 'Page d\'origine ${s.pageIndex + 1}'
                  : 'PDF ajouté n°${s.docIndex}, page ${s.pageIndex + 1}';
          return Material(
            key: it.key,
            color: selected ? scheme.primaryContainer : null,
            child: InkWell(
              onTap: () => setState(() => selected ? _selected.remove(it.key) : _selected.add(it.key)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator)),
                  ),
                  SizedBox(width: 110, height: 110, child: Center(child: _thumb(it))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Page ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(origin, style: Theme.of(context).textTheme.bodySmall),
                      Wrap(children: [
                        IconButton(
                            tooltip: 'Pivoter à gauche',
                            icon: const Icon(Icons.rotate_left),
                            onPressed: () => _rotate(it, -1)),
                        IconButton(
                            tooltip: 'Pivoter à droite',
                            icon: const Icon(Icons.rotate_right),
                            onPressed: () => _rotate(it, 1)),
                        IconButton(
                            tooltip: 'Dupliquer', icon: const Icon(Icons.copy_outlined), onPressed: () => _duplicate(i)),
                        IconButton(
                            tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline), onPressed: () => _delete([it])),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                  onPressed: _merge, icon: const Icon(Icons.merge_type), label: const Text('Ajouter un PDF')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                  onPressed: _addBlank, icon: const Icon(Icons.note_add_outlined), label: const Text('Page blanche')),
            ),
          ]),
        ),
      ),
    );
  }
}
