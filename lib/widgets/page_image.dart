import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Affiche une page PDF en la rendant à la résolution réellement visible
/// ([zoom] = facteur de zoom courant), pour un texte net même zoomé.
class PageImage extends StatefulWidget {
  const PageImage({super.key, required this.page, this.zoom = 1, this.rotationOverride});

  final PdfPage page;
  final double zoom;
  final PdfPageRotation? rotationOverride;

  @override
  State<PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<PageImage> {
  ui.Image? _image;
  Size? _renderedFor;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant PageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page || oldWidget.rotationOverride != widget.rotationOverride) {
      _renderedFor = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render(Size target) async {
    final gen = ++_generation;
    final page = widget.page;
    final img = await page.renderForDisplay(
      fullWidth: target.width,
      fullHeight: target.height,
      rotationOverride: widget.rotationOverride,
      pixelSizeThreshold: 4096,
    );
    if (!mounted || gen != _generation) {
      img?.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = img;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      // Paliers de zoom pour éviter de re-rendre en continu.
      final zoomStep = widget.zoom <= 1.2 ? 1.0 : math.pow(2, (math.log(widget.zoom) / math.ln2).ceil()).toDouble();
      final factor = math.min(dpr * zoomStep, 6.0);
      final target = Size((size.width * factor).roundToDouble(), (size.height * factor).roundToDouble());
      if (target.width > 0 && target != _renderedFor) {
        _renderedFor = target;
        scheduleMicrotask(() => _render(target));
      }
      final img = _image;
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: img == null
            ? const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)))
            : RawImage(image: img, width: size.width, height: size.height, fit: BoxFit.fill),
      );
    });
  }
}

/// Miniature simple d'une page (pour les listes).
class PageThumbnail extends StatelessWidget {
  const PageThumbnail({super.key, required this.page, this.rotationOverride, this.maxHeight = 120});

  final PdfPage page;
  final PdfPageRotation? rotationOverride;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    var w = page.width, h = page.height;
    if (rotationOverride != null && (rotationOverride!.index - page.rotation.index).isOdd) {
      final t = w;
      w = h;
      h = t;
    }
    final scale = maxHeight / math.max(w, h);
    return SizedBox(
      width: w * scale,
      height: h * scale,
      child: PageImage(page: page, rotationOverride: rotationOverride),
    );
  }
}
