import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/document_store.dart';

/// Choix d'une signature : enregistrée ou nouvelle. Renvoie le PNG.
Future<Uint8List?> pickSignature(BuildContext context) async {
  final saved = await DocumentStore.listSignatures();
  if (!context.mounted) return null;
  if (saved.isEmpty) return _drawNew(context);
  return showModalBottomSheet<Uint8List>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SignatureChooser(saved: saved),
  );
}

Future<Uint8List?> _drawNew(BuildContext context) =>
    Navigator.of(context).push<Uint8List>(MaterialPageRoute(builder: (_) => const SignatureScreen(), fullscreenDialog: true));

class _SignatureChooser extends StatefulWidget {
  const _SignatureChooser({required this.saved});
  final List<File> saved;

  @override
  State<_SignatureChooser> createState() => _SignatureChooserState();
}

class _SignatureChooserState extends State<_SignatureChooser> {
  late final List<File> _saved = List.of(widget.saved);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Mes signatures', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(shrinkWrap: true, children: [
              for (final f in _saved)
                Card(
                  child: InkWell(
                    onTap: () async {
                      final bytes = await f.readAsBytes();
                      if (context.mounted) Navigator.pop(context, bytes);
                    },
                    child: Row(children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Container(
                            color: Colors.white,
                            height: 70,
                            child: Image.file(f, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await f.delete();
                          setState(() => _saved.remove(f));
                        },
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.draw),
            label: const Text('Nouvelle signature'),
            onPressed: () async {
              final png = await _drawNew(context);
              if (context.mounted && png != null) Navigator.pop(context, png);
            },
          ),
        ]),
      ),
    );
  }
}

/// Pavé de signature plein écran.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final List<List<Offset>> _strokes = [];
  Color _color = const Color(0xFF0D1B6E);
  double _width = 3;
  bool _remember = true;

  Future<void> _done() async {
    if (_strokes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    // Recadrage sur le tracé, rendu à 3x pour une bonne qualité.
    var bounds = Rect.fromPoints(_strokes.first.first, _strokes.first.first);
    for (final s in _strokes) {
      for (final p in s) {
        bounds = bounds.expandToInclude(Rect.fromCenter(center: p, width: 0, height: 0));
      }
    }
    bounds = bounds.inflate(_width * 2);
    const k = 3.0;
    final w = math.max(1, (bounds.width * k).ceil()), h = math.max(1, (bounds.height * k).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(k);
    canvas.translate(-bounds.left, -bounds.top);
    _SigPainter(_strokes, _color, _width).paint(canvas, bounds.size);
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final png = data!.buffer.asUint8List();
    if (_remember) await DocumentStore.saveSignature(png);
    if (mounted) Navigator.pop(context, png);
  }

  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFF0D1B6E), Colors.black, Color(0xFFC62828)];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signer'),
        actions: [
          TextButton(onPressed: () => setState(_strokes.clear), child: const Text('Effacer')),
          FilledButton(onPressed: _done, child: const Text('Valider')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            for (final c in colors)
              GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  margin: const EdgeInsets.all(6),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: _color == c ? Colors.amber : Colors.transparent, width: 3),
                  ),
                ),
              ),
            Expanded(
              child: Slider(min: 1.5, max: 8, value: _width, onChanged: (v) => setState(() => _width = v)),
            ),
          ]),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(children: [
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 60,
                  child: Container(height: 1, color: Colors.grey.shade300),
                ),
                if (_strokes.isEmpty)
                  const Center(child: Text('Signez ici avec le doigt', style: TextStyle(color: Colors.grey))),
                GestureDetector(
                  onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                  onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                  child: CustomPaint(painter: _SigPainter(_strokes, _color, _width), size: Size.infinite),
                ),
              ]),
            ),
          ),
        ),
        CheckboxListTile(
          value: _remember,
          onChanged: (v) => setState(() => _remember = v ?? true),
          title: const Text('Mémoriser cette signature'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ]),
    );
  }
}

class _SigPainter extends CustomPainter {
  _SigPainter(this.strokes, this.color, this.width);
  final List<List<Offset>> strokes;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, width / 2, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length; i++) {
        // Lissage par courbes quadratiques entre points médians.
        final mid = (s[i - 1] + s[i]) / 2;
        path.quadraticBezierTo(s[i - 1].dx, s[i - 1].dy, mid.dx, mid.dy);
      }
      path.lineTo(s.last.dx, s.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter old) => true;
}
