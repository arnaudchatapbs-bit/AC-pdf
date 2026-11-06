import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../models/annotation.dart';
import '../services/document_store.dart';
import '../services/page_service.dart';
import '../services/pdf_service.dart';
import '../widgets/annotation_painter.dart';
import '../widgets/dialogs.dart';
import '../widgets/page_image.dart';
import 'form_screen.dart';
import 'pages_screen.dart';
import 'signature_screen.dart';

// Tâches exécutées en arrière-plan (isolate) pour ne pas figer l'interface.
Uint8List _flattenJob((Uint8List, Map<int, List<Annot>>, Uint8List?) a) =>
    PdfService.flattenAnnotations(a.$1, a.$2, fontBytes: a.$3);

Uint8List _writeFormJob((Uint8List, List<FormFieldInfo>, bool) a) =>
    PdfService.writeFormFields(a.$1, a.$2, flatten: a.$3);

enum Tool { pan, select, ink, highlight, text, rect, ellipse, line, arrow, eraser }

class _ToolInfo {
  const _ToolInfo(this.icon, this.label);
  final IconData icon;
  final String label;
}

const _tools = <Tool, _ToolInfo>{
  Tool.pan: _ToolInfo(Icons.pan_tool_outlined, 'Naviguer'),
  Tool.select: _ToolInfo(Icons.near_me_outlined, 'Sélection'),
  Tool.ink: _ToolInfo(Icons.edit, 'Stylo'),
  Tool.highlight: _ToolInfo(Icons.highlight, 'Surligner'),
  Tool.text: _ToolInfo(Icons.text_fields, 'Texte'),
  Tool.rect: _ToolInfo(Icons.crop_square, 'Rectangle'),
  Tool.ellipse: _ToolInfo(Icons.circle_outlined, 'Cercle'),
  Tool.line: _ToolInfo(Icons.horizontal_rule, 'Ligne'),
  Tool.arrow: _ToolInfo(Icons.arrow_right_alt, 'Flèche'),
  Tool.eraser: _ToolInfo(Icons.auto_fix_normal_outlined, 'Gomme'),
};

const _palette = <Color>[
  Color(0xFFE53935),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFF000000),
  Color(0xFFFFEB3B),
  Color(0xFFFB8C00),
  Color(0xFF8E24AA),
  Color(0xFFFFFFFF),
];

class _Snapshot {
  _Snapshot(this.bytes, Map<int, List<Annot>> annots)
      : annots = {for (final e in annots.entries) e.key: [for (final a in e.value) a.copy(keepId: true)]};
  final Uint8List bytes;
  final Map<int, List<Annot>> annots;
}

enum _Drag { none, draw, move, resize, erase }

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.file});
  final File file;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late File _file = widget.file;
  Uint8List? _bytes;
  PdfDocument? _doc;
  int _page = 0;
  Map<int, List<Annot>> _annots = {};
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  bool _dirty = false;
  String? _error;

  Tool _tool = Tool.pan;
  Color _color = _palette.first;
  double _stroke = 2;
  double _fontSize = 14;
  Color _highlightColor = const Color(0xFFFFEB3B);

  String? _selectedId;
  _Drag _drag = _Drag.none;
  Annot? _active;
  Offset? _downPx;
  Offset? _lastPx;
  bool _undoPushedForGesture = false;
  final Set<int> _pointers = {};
  int? _mainPointer;

  final _tc = TransformationController();
  double _zoom = 1;
  final Map<String, ui.Image> _images = {};
  Uint8List? _fontBytes;
  int _docCounter = 0;

  List<Annot> get _pageAnnots => _annots.putIfAbsent(_page, () => []);
  bool get _hasAnnots => _annots.values.any((l) => l.isNotEmpty);
  Annot? get _selected {
    if (_selectedId == null) return null;
    for (final a in _pageAnnots) {
      if (a.id == _selectedId) return a;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _tc.addListener(() {
      final z = _tc.value.getMaxScaleOnAxis();
      if ((z - _zoom).abs() > 0.05) setState(() => _zoom = z);
    });
    _init();
  }

  Future<void> _init() async {
    try {
      final font = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      _fontBytes = font.buffer.asUint8List();
      await _loadBytes(await _file.readAsBytes());
    } catch (e) {
      setState(() => _error = 'Impossible d\'ouvrir ce PDF.\n$e');
    }
  }

  @override
  void dispose() {
    _doc?.dispose();
    for (final img in _images.values.toSet()) {
      if (!identical(img, _placeholder)) img.dispose();
    }
    _tc.dispose();
    super.dispose();
  }

  Future<void> _loadBytes(Uint8List bytes) async {
    final doc = await PdfDocument.openData(bytes, sourceName: '${_file.path}#${_docCounter++}');
    final old = _doc;
    if (!mounted) {
      doc.dispose();
      return;
    }
    setState(() {
      _bytes = bytes;
      _doc = doc;
      _page = _page.clamp(0, doc.pages.length - 1);
    });
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  // ---------------------------------------------------------------------------
  // Historique
  // ---------------------------------------------------------------------------

  void _pushUndo() {
    _undo.add(_Snapshot(_bytes!, _annots));
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
    _dirty = true;
  }

  Future<void> _restore(_Snapshot s) async {
    _annots = {for (final e in s.annots.entries) e.key: [for (final a in e.value) a.copy(keepId: true)]};
    _selectedId = null;
    if (!identical(s.bytes, _bytes)) {
      await _loadBytes(s.bytes);
    }
    _dirty = true;
    setState(() {});
  }

  Future<void> _doUndo() async {
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(_bytes!, _annots));
    await _restore(_undo.removeLast());
  }

  Future<void> _doRedo() async {
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(_bytes!, _annots));
    await _restore(_redo.removeLast());
  }

  // ---------------------------------------------------------------------------
  // Écriture dans le PDF
  // ---------------------------------------------------------------------------

  /// Intègre les annotations en cours dans le PDF (nécessaire avant les
  /// opérations sur les pages ou le formulaire, et à l'enregistrement).
  Future<void> _commitAnnotations() async {
    if (!_hasAnnots) return;
    final bytes = _bytes!;
    final annots = _annots;
    final font = _fontBytes;
    final out = await compute(_flattenJob, (bytes, annots, font));
    _annots = {};
    _selectedId = null;
    await _loadBytes(out);
  }

  Future<bool> _save() async {
    try {
      await withProgress(context, () async {
        await _commitAnnotations();
        await _file.writeAsBytes(_bytes!, flush: true);
      }, message: 'Enregistrement…');
      setState(() => _dirty = false);
      if (mounted) toast(context, 'Enregistré');
      return true;
    } catch (e) {
      if (mounted) toast(context, 'Erreur à l\'enregistrement : $e');
      return false;
    }
  }

  Future<Uint8List> _currentBytes() async {
    if (_hasAnnots) {
      _pushUndo();
      await withProgress(context, _commitAnnotations, message: 'Application des annotations…');
    }
    return _bytes!;
  }

  Future<void> _share() async {
    final bytes = await _currentBytes();
    final tmp = await Directory.systemTemp.createTemp('share');
    final f = await File('${tmp.path}/${DocumentStore.displayName(_file)}').writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/pdf')]));
  }

  Future<void> _exportCopy() async {
    final bytes = await _currentBytes();
    final uri = await FilePicker.saveFile(
        fileName: DocumentStore.displayName(_file), bytes: bytes, mimeType: 'application/pdf');
    if (uri != null && mounted) toast(context, 'Copie enregistrée');
  }

  Future<void> _rename() async {
    final current = DocumentStore.displayName(_file).replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final name = await askText(context, title: 'Renommer', initial: current);
    if (name == null) return;
    try {
      final f = await DocumentStore.rename(_file, name);
      setState(() => _file = f);
    } on FileSystemException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  // ---------------------------------------------------------------------------
  // Pages et formulaires
  // ---------------------------------------------------------------------------

  Future<void> _openPages() async {
    await _currentBytes();
    if (!mounted) return;
    final result = await Navigator.of(context)
        .push<PagesResult>(MaterialPageRoute(builder: (_) => PagesScreen(document: _doc!)));
    if (result == null || !mounted) return;
    final specs = result.specs;
    var unchanged = result.extras.isEmpty && specs.length == _doc!.pages.length;
    for (var i = 0; unchanged && i < specs.length; i++) {
      final s = specs[i];
      unchanged = s.docIndex == 0 && s.blankSize == null && s.quarterTurns == 0 && s.pageIndex == i;
    }
    if (unchanged) return;
    try {
      final out = await withProgress(
          context, () => PageService.rebuildPages(_bytes!, result.specs, extras: result.extras),
          message: 'Mise à jour des pages…');
      _pushUndo();
      await _loadBytes(out);
      setState(() => _page = 0);
    } catch (e) {
      if (mounted) toast(context, 'Opération impossible : $e');
    }
  }

  Future<void> _openForm() async {
    final bytes = await _currentBytes();
    final fields = await compute(PdfService.readFormFields, bytes);
    if (!mounted) return;
    if (fields.isEmpty) {
      toast(context, 'Ce PDF ne contient pas de champs de formulaire. Utilisez l\'outil Texte pour écrire dessus.');
      return;
    }
    final result = await Navigator.of(context)
        .push<FormResult>(MaterialPageRoute(builder: (_) => FormScreen(fields: fields)));
    if (result == null || !mounted) return;
    try {
      final out = await withProgress(
          context,
          () => compute(_writeFormJob, (bytes, result.fields, result.flatten)),
          message: 'Remplissage du formulaire…');
      _pushUndo();
      await _loadBytes(out);
      if (mounted) toast(context, 'Formulaire mis à jour');
    } catch (e) {
      if (mounted) toast(context, 'Erreur : $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Images et signatures
  // ---------------------------------------------------------------------------

  Future<void> _insertImageBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final aspect = img.width / img.height;
    final page = _doc!.pages[_page];
    // Largeur par défaut : 40 % de la page (35 % pour une signature large).
    final w = aspect > 2.5 ? 0.35 : 0.4;
    final h = w * page.width / aspect / page.height;
    final a = Annot(
      type: AnnotType.image,
      points: [Offset(0.5 - w / 2, 0.5 - h / 2), Offset(0.5 + w / 2, 0.5 + h / 2)],
      imageBytes: bytes,
      imageAspect: aspect,
    );
    _images[a.id] = img;
    _pushUndo();
    setState(() {
      _pageAnnots.add(a);
      _selectedId = a.id;
      _tool = Tool.select;
    });
    if (mounted) toast(context, 'Faites glisser pour déplacer, la poignée pour redimensionner');
  }

  Future<void> _insertSignature() async {
    final png = await pickSignature(context);
    if (png != null) await _insertImageBytes(png);
  }

  Future<void> _insertImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Appareil photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ]),
      ),
    );
    if (source == null) return;
    final x = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 88);
    if (x == null) return;
    await _insertImageBytes(await x.readAsBytes());
  }

  /// S'assure que les images des annotations (ex. après annuler) sont décodées.
  void _ensureImages() {
    for (final a in _pageAnnots) {
      if (a.type == AnnotType.image && a.imageBytes != null && !_images.containsKey(a.id)) {
        _images[a.id] = _placeholder;
        decodeImageFromList(a.imageBytes!).then((img) {
          if (!mounted) return;
          setState(() => _images[a.id] = img);
        });
      }
    }
  }

  static final ui.Image _placeholder = () {
    final r = ui.PictureRecorder();
    Canvas(r);
    return r.endRecording().toImageSync(1, 1);
  }();

  // ---------------------------------------------------------------------------
  // Texte
  // ---------------------------------------------------------------------------

  Future<void> _editText({Annot? existing, Offset? at}) async {
    final ctrl = TextEditingController(text: existing?.text ?? '');
    var size = existing?.fontSize ?? _fontSize;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? 'Ajouter du texte' : 'Modifier le texte'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 1,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'Votre texte', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Taille'),
              Expanded(
                child: Slider(
                    min: 6, max: 48, divisions: 42, value: size, label: '${size.round()}',
                    onChanged: (v) => setD(() => size = v)),
              ),
              SizedBox(width: 28, child: Text('${size.round()}')),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (result == null) return;
    _fontSize = size;
    _pushUndo();
    setState(() {
      if (existing != null) {
        if (result.trim().isEmpty) {
          _pageAnnots.remove(existing);
          _selectedId = null;
        } else {
          existing
            ..text = result
            ..fontSize = size;
        }
      } else if (result.trim().isNotEmpty && at != null) {
        final a = Annot(type: AnnotType.text, points: [at], text: result, fontSize: size, color: _color);
        _pageAnnots.add(a);
        _selectedId = a.id;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Gestes sur la page
  // ---------------------------------------------------------------------------

  void _onDown(PointerDownEvent e, AnnotGeometry geo) {
    _pointers.add(e.pointer);
    if (_pointers.length > 1) {
      _cancelGesture();
      return;
    }
    if (_tool == Tool.pan) return;
    _mainPointer = e.pointer;
    _downPx = e.localPosition;
    _lastPx = e.localPosition;
    _undoPushedForGesture = false;
    final n = geo.toNorm(e.localPosition);

    switch (_tool) {
      case Tool.ink:
        _beginUndo();
        _active = Annot(type: AnnotType.ink, points: [n], color: _color, strokeWidth: _stroke);
        _pageAnnots.add(_active!);
        _drag = _Drag.draw;
      case Tool.highlight:
      case Tool.rect:
      case Tool.ellipse:
      case Tool.line:
      case Tool.arrow:
        _beginUndo();
        final type = switch (_tool) {
          Tool.highlight => AnnotType.highlight,
          Tool.rect => AnnotType.rect,
          Tool.ellipse => AnnotType.ellipse,
          Tool.line => AnnotType.line,
          _ => AnnotType.arrow,
        };
        _active = Annot(
          type: type,
          points: [n, n],
          color: type == AnnotType.highlight ? _highlightColor : _color,
          strokeWidth: _stroke,
        );
        _pageAnnots.add(_active!);
        _drag = _Drag.draw;
      case Tool.select:
        final sel = _selected;
        if (sel != null && isResizable(sel) && (geo.handle(sel) - e.localPosition).distance <= kHandleRadius * 1.6) {
          _active = sel;
          _drag = _Drag.resize;
        } else {
          final hit = geo.hitTest(_pageAnnots, e.localPosition);
          _selectedId = hit?.id;
          _active = hit;
          _drag = hit == null ? _Drag.none : _Drag.move;
        }
      case Tool.eraser:
        _drag = _Drag.erase;
        _eraseAt(geo, e.localPosition);
      case Tool.text:
        _drag = _Drag.none;
      case Tool.pan:
        break;
    }
    setState(() {});
  }

  void _beginUndo() {
    if (_undoPushedForGesture) return;
    _pushUndo();
    _undoPushedForGesture = true;
  }

  void _eraseAt(AnnotGeometry geo, Offset px) {
    final hit = geo.hitTest(_pageAnnots, px);
    if (hit != null) {
      _beginUndo();
      _pageAnnots.remove(hit);
    }
  }

  void _onMove(PointerMoveEvent e, AnnotGeometry geo) {
    if (e.pointer != _mainPointer || _pointers.length > 1) return;
    final px = e.localPosition;
    final n = geo.toNorm(px);
    final a = _active;
    switch (_drag) {
      case _Drag.draw:
        if (a == null) break;
        if (a.type == AnnotType.ink) {
          if ((px - _lastPx!).distance < 1.5) return;
          a.points = [...a.points, n];
        } else {
          a.points = [a.points.first, n];
        }
      case _Drag.move:
        if (a == null) break;
        if ((px - _downPx!).distance < 4 && !_undoPushedForGesture) return;
        _beginUndo();
        a.translate(geo.toNorm(px) - geo.toNorm(_lastPx!));
      case _Drag.resize:
        if (a == null) break;
        _beginUndo();
        var end = n;
        if (a.type == AnnotType.image && a.imageAspect != null) {
          final start = a.points.first;
          final wPx = (end.dx - start.dx) * geo.size.width;
          final hPx = wPx / a.imageAspect!;
          end = Offset(end.dx, start.dy + hPx / geo.size.height);
        }
        a.points = [a.points.first, end];
      case _Drag.erase:
        _eraseAt(geo, px);
      case _Drag.none:
        break;
    }
    _lastPx = px;
    setState(() {});
  }

  void _onUp(PointerEvent e, AnnotGeometry geo) {
    _pointers.remove(e.pointer);
    if (e.pointer != _mainPointer) return;
    _mainPointer = null;
    final a = _active;
    final tap = _downPx != null && (e.localPosition - _downPx!).distance < 8;

    if (_drag == _Drag.draw && a != null && a.type != AnnotType.ink) {
      // Forme trop petite : on l'abandonne.
      final r = Rect.fromPoints(geo.toPx(a.points.first), geo.toPx(a.points.last));
      if (r.longestSide < 6) {
        _pageAnnots.remove(a);
        if (_undo.isNotEmpty) _undo.removeLast();
      }
    }
    if (_drag == _Drag.draw && a != null && a.type == AnnotType.ink && a.points.length > 2) {
      a.points = _simplify(a.points, 0.0008);
    }

    if (_tool == Tool.text && tap && e is PointerUpEvent) {
      final hit = geo.hitTest(_pageAnnots.where((x) => x.type == AnnotType.text).toList(), e.localPosition);
      if (hit != null) {
        _editText(existing: hit);
      } else {
        _editText(at: geo.toNorm(_downPx!));
      }
    }
    if (_tool == Tool.select && tap && a != null && a.type == AnnotType.text && _lastTapId == a.id &&
        DateTime.now().difference(_lastTapTime) < const Duration(milliseconds: 400)) {
      _editText(existing: a);
    }
    if (tap && a != null) {
      _lastTapId = a.id;
      _lastTapTime = DateTime.now();
    }

    _drag = _Drag.none;
    _active = null;
    setState(() {});
  }

  String? _lastTapId;
  DateTime _lastTapTime = DateTime(2000);

  void _cancelGesture() {
    if (_drag == _Drag.draw && _active != null) {
      _pageAnnots.remove(_active);
      if (_undoPushedForGesture && _undo.isNotEmpty) _undo.removeLast();
    }
    _drag = _Drag.none;
    _active = null;
    _mainPointer = null;
    setState(() {});
  }

  /// Simplification Ramer-Douglas-Peucker (coordonnées normalisées).
  List<Offset> _simplify(List<Offset> pts, double eps) {
    if (pts.length < 3) return pts;
    var maxD = 0.0, idx = 0;
    final a = pts.first, b = pts.last;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = _perp(pts[i], a, b);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD <= eps) return [a, b];
    final left = _simplify(pts.sublist(0, idx + 1), eps);
    final right = _simplify(pts.sublist(idx), eps);
    return [...left.sublist(0, left.length - 1), ...right];
  }

  double _perp(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len = ab.distance;
    if (len == 0) return (p - a).distance;
    return ((p.dx - a.dx) * ab.dy - (p.dy - a.dy) * ab.dx).abs() / len;
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _goTo(int page) {
    final doc = _doc;
    if (doc == null) return;
    final p = page.clamp(0, doc.pages.length - 1);
    if (p == _page) return;
    _cancelGesture();
    setState(() {
      _page = p;
      _selectedId = null;
      _tc.value = Matrix4.identity();
    });
  }

  Future<void> _showPageGrid() async {
    final doc = _doc;
    if (doc == null) return;
    final p = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.7,
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.72),
          itemCount: doc.pages.length,
          itemBuilder: (_, i) => InkWell(
            onTap: () => Navigator.pop(ctx, i),
            child: Column(children: [
              Expanded(child: Center(child: PageThumbnail(page: doc.pages[i], maxHeight: 140))),
              const SizedBox(height: 4),
              Text('${i + 1}',
                  style: TextStyle(fontWeight: i == _page ? FontWeight.bold : FontWeight.normal)),
            ]),
          ),
        ),
      ),
    );
    if (p != null) _goTo(p);
  }

  Future<void> _showStyleSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        void update(VoidCallback f) {
          setS(f);
          setState(() {});
        }

        final isHighlight = _tool == Tool.highlight || _selected?.type == AnnotType.highlight;
        final current = isHighlight ? _highlightColor : _color;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Couleur'),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => update(() {
                      if (isHighlight) {
                        _highlightColor = c;
                      } else {
                        _color = c;
                      }
                      final sel = _selected;
                      if (sel != null && sel.type != AnnotType.image) {
                        _pushUndo();
                        sel.color = c;
                      }
                    }),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: current == c ? Theme.of(ctx).colorScheme.primary : Colors.grey.shade400,
                            width: current == c ? 4 : 1),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              Text('Épaisseur du trait : ${_stroke.toStringAsFixed(1)} pt'),
              Slider(
                min: 0.5,
                max: 12,
                value: _stroke,
                onChanged: (v) => update(() {
                  _stroke = v;
                  final sel = _selected;
                  if (sel != null && sel.type != AnnotType.text && sel.type != AnnotType.image) {
                    sel.strokeWidth = v;
                    _dirty = true;
                  }
                }),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _onWillPop() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text('Voulez-vous enregistrer vos modifications ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Ne pas enregistrer')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'save' && !await _save()) return;
    if (mounted) {
      _dirty = false;
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------------------
  // Construction de l'interface
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onWillPop();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        appBar: AppBar(
          title: GestureDetector(
            onTap: _rename,
            child: Text(DocumentStore.displayName(_file), overflow: TextOverflow.ellipsis),
          ),
          actions: [
            IconButton(
                tooltip: 'Annuler', icon: const Icon(Icons.undo), onPressed: _undo.isEmpty ? null : _doUndo),
            IconButton(
                tooltip: 'Rétablir', icon: const Icon(Icons.redo), onPressed: _redo.isEmpty ? null : _doRedo),
            IconButton(
              tooltip: 'Enregistrer',
              icon: Badge(isLabelVisible: _dirty, smallSize: 8, child: const Icon(Icons.save_outlined)),
              onPressed: doc == null ? null : _save,
            ),
            PopupMenuButton<String>(
              enabled: doc != null,
              onSelected: (v) {
                switch (v) {
                  case 'pages':
                    _openPages();
                  case 'form':
                    _openForm();
                  case 'share':
                    _share();
                  case 'export':
                    _exportCopy();
                  case 'rename':
                    _rename();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'pages', child: ListTile(leading: Icon(Icons.auto_awesome_motion_outlined), title: Text('Gérer les pages'))),
                PopupMenuItem(
                    value: 'form', child: ListTile(leading: Icon(Icons.assignment_outlined), title: Text('Remplir le formulaire'))),
                PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share_outlined), title: Text('Partager'))),
                PopupMenuItem(
                    value: 'export', child: ListTile(leading: Icon(Icons.save_alt), title: Text('Enregistrer une copie…'))),
                PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Renommer'))),
              ],
            ),
          ],
        ),
        body: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
            : doc == null
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    Expanded(child: _buildPageArea(doc)),
                    _buildBottomBar(doc),
                  ]),
      ),
    );
  }

  Widget _buildPageArea(PdfDocument doc) {
    final page = doc.pages[_page];
    _ensureImages();
    return LayoutBuilder(builder: (context, constraints) {
      const margin = 12.0;
      final maxW = constraints.maxWidth - margin * 2, maxH = constraints.maxHeight - margin * 2;
      final k = (maxW / page.width) < (maxH / page.height) ? maxW / page.width : maxH / page.height;
      final size = Size(page.width * k, page.height * k);
      final geo = AnnotGeometry(size, page.width);

      return InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 8,
        panEnabled: _tool == Tool.pan,
        scaleEnabled: true,
        onInteractionEnd: (d) {
          // Balayage horizontal pour changer de page (sans zoom).
          if (_tool != Tool.pan || _zoom > 1.05) return;
          final vx = d.velocity.pixelsPerSecond.dx;
          if (vx < -600) _goTo(_page + 1);
          if (vx > 600) _goTo(_page - 1);
        },
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: Stack(children: [
              Positioned.fill(child: PageImage(key: ValueKey(page), page: page, zoom: _zoom)),
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _onDown(e, geo),
                  onPointerMove: (e) => _onMove(e, geo),
                  onPointerUp: (e) => _onUp(e, geo),
                  onPointerCancel: (e) => _onUp(e, geo),
                  child: CustomPaint(
                    painter: AnnotationPainter(
                      annots: _pageAnnots,
                      pageWidthPts: page.width,
                      images: _images,
                      selectedId: _tool == Tool.select ? _selectedId : null,
                      selectionColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _buildBottomBar(PdfDocument doc) {
    final scheme = Theme.of(context).colorScheme;
    final sel = _tool == Tool.select ? _selected : null;
    final styleColor = _tool == Tool.highlight ? _highlightColor : _color;
    return Material(
      color: scheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (sel != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                const Icon(Icons.check_box_outlined, size: 18),
                const SizedBox(width: 6),
                const Expanded(child: Text('Élément sélectionné')),
                if (sel.type == AnnotType.text)
                  IconButton(
                      tooltip: 'Modifier le texte',
                      icon: const Icon(Icons.edit_note),
                      onPressed: () => _editText(existing: sel)),
                IconButton(
                  tooltip: 'Dupliquer',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () {
                    _pushUndo();
                    final c = sel.copy()..translate(const Offset(0.03, 0.03));
                    if (c.type == AnnotType.image) _images[c.id] = _images[sel.id] ?? _placeholder;
                    setState(() {
                      _pageAnnots.add(c);
                      _selectedId = c.id;
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    _pushUndo();
                    setState(() {
                      _pageAnnots.remove(sel);
                      _selectedId = null;
                    });
                  },
                ),
              ]),
            ),
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                for (final t in Tool.values) _toolButton(t),
                const VerticalDivider(indent: 12, endIndent: 12),
                _actionButton(Icons.draw_outlined, 'Signature', _insertSignature),
                _actionButton(Icons.image_outlined, 'Image', _insertImage),
                _actionButton(Icons.assignment_outlined, 'Formulaire', _openForm),
                _actionButton(Icons.auto_awesome_motion_outlined, 'Pages', _openPages),
              ],
            ),
          ),
          Row(children: [
            const SizedBox(width: 4),
            InkWell(
              onTap: _showStyleSheet,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                        color: styleColor, shape: BoxShape.circle, border: Border.all(color: Colors.grey)),
                  ),
                  const SizedBox(width: 6),
                  Text('${_stroke.toStringAsFixed(1)} pt'),
                ]),
              ),
            ),
            const Spacer(),
            IconButton(
                tooltip: 'Page précédente',
                icon: const Icon(Icons.chevron_left),
                onPressed: _page > 0 ? () => _goTo(_page - 1) : null),
            TextButton(onPressed: _showPageGrid, child: Text('${_page + 1} / ${doc.pages.length}')),
            IconButton(
                tooltip: 'Page suivante',
                icon: const Icon(Icons.chevron_right),
                onPressed: _page < doc.pages.length - 1 ? () => _goTo(_page + 1) : null),
          ]),
        ]),
      ),
    );
  }

  Widget _toolButton(Tool t) {
    final info = _tools[t]!;
    final selected = _tool == t;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _tool = t;
          if (t != Tool.select) _selectedId = null;
        }),
        child: Container(
          width: 64,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(info.icon, color: selected ? scheme.onPrimaryContainer : null),
            Text(info.label, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon),
            Text(label, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}
