import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'blur.dart';
import 'gallery.dart';
import 'process_page.dart';
import 'save_sheet.dart';
import 'settings.dart';

enum _Tool { brush, eraser, strength, edge }

/// Usapan dan riwayat redo satu foto.
class _Edit {
  final List<BlurStroke> strokes = [];
  final List<BlurStroke> redo = [];

  bool get hasPaint => strokes.any((s) => !s.erase);
}

/// Editor blur layar penuh: usap foto dengan satu jari untuk mem-blur area itu, dua jari untuk
/// memperbesar/menggeser. Tiap foto punya area sendiri; kekuatan (area diusap dan area lain) dan
/// kelembutan tepi berlaku untuk semua. ✓ membuka opsi simpan lalu halaman proses (hanya foto
/// yang berubah); route ini lalu
/// selesai dengan `true`. Batal: `null`.
class BlurEditorPage extends StatefulWidget {
  const BlurEditorPage({
    super.key,
    required this.photos,
    required this.source,
    this.initial = const BlurSettings(),
    this.save = const SaveSettings(),
  });

  final List<Photo> photos;
  final GallerySource source;
  final BlurSettings initial;
  final SaveSettings save;

  @override
  State<BlurEditorPage> createState() => _BlurEditorPageState();
}

class _BlurEditorPageState extends State<BlurEditorPage> {
  late double _strength = widget.initial.strength;
  late double _background = widget.initial.background;
  late double _feather = widget.initial.feather;
  late double _brush = widget.initial.brush;
  late SaveSettings _save = widget.save;
  _Tool _tool = _Tool.brush;
  int _page = 0;
  bool _showBrush = false;
  final Map<String, _Edit> _edits = {};

  Photo get _photo => widget.photos[_page];
  _Edit get _edit => _edits.putIfAbsent(_photo.id, _Edit.new);
  BlurOptions _options(List<BlurStroke> strokes) =>
      BlurOptions(strength: _strength, background: _background, feather: _feather, strokes: strokes);

  /// Foto yang hasilnya berbeda dari aslinya (area lain di-blur: semua foto).
  List<Photo> get _edited => [
    for (final p in widget.photos)
      if (_options(_edits[p.id]?.strokes ?? const []).changesPhoto) p,
  ];
  bool get _dirty => _edits.values.any((e) => e.strokes.isNotEmpty);

  void _add(BlurStroke s) => setState(() {
    _edit.strokes.add(s);
    _edit.redo.clear();
  });

  void _undo() => setState(() => _edit.redo.add(_edit.strokes.removeLast()));

  void _redo() => setState(() => _edit.strokes.add(_edit.redo.removeLast()));

  void _remember() =>
      BlurSettings(strength: _strength, background: _background, feather: _feather, brush: _brush).save();

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buang perubahan?'),
        content: const Text('Area blur yang sudah dibuat akan hilang.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Lanjut edit')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buang')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _close() async {
    if (await _confirmDiscard() && mounted) Navigator.pop(context);
  }

  /// Opsi simpan, lalu proses foto yang diberi blur.
  Future<void> _done() async {
    final photos = _edited;
    if (photos.isEmpty) return;
    _remember();
    final n = widget.photos.length;
    final bg = BlurOptions.levelOf(_background);
    final save = await showSaveSheet(
      context,
      title: 'Simpan ${photos.length} foto?',
      summary:
          'Blur area diusap ${BlurOptions.levelOf(_strength)}, area lain ${bg == 0 ? 'tajam' : bg}, '
          'tepi ${BlurOptions.featherLevelOf(_feather)}'
          '${photos.length < n ? ', pada ${photos.length} dari $n foto' : ''}.',
      initial: _save,
    );
    if (save == null || !mounted) return;
    _save = save;
    final blur = {for (final p in photos) p.id: _options(List.of(_edits[p.id]?.strokes ?? const [])).toMap()};
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProcessPage(
          photos: photos,
          edits: (p) => {'blur': blur[p.id]!},
          quality: save.quality,
          maxSide: save.maxSide,
        ),
      ),
      result: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.photos.length;
    final theme = ThemeData(
      colorSchemeSeed: Theme.of(context).colorScheme.primary,
      brightness: Brightness.dark,
      useMaterial3: true,
    );
    final edit = _edit;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Theme(
        data: theme,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            leading: IconButton(tooltip: 'Batal', icon: const Icon(Icons.close), onPressed: _close),
            title: const Text('Blur'),
            actions: [
              IconButton(
                key: const ValueKey('blur-undo'),
                tooltip: 'Urungkan',
                icon: const Icon(Icons.undo),
                onPressed: edit.strokes.isEmpty ? null : _undo,
              ),
              IconButton(
                key: const ValueKey('blur-redo'),
                tooltip: 'Ulangi',
                icon: const Icon(Icons.redo),
                onPressed: edit.redo.isEmpty ? null : _redo,
              ),
              IconButton(
                key: const ValueKey('blur-save'),
                tooltip: 'Lanjut',
                icon: const Icon(Icons.check),
                onPressed: _edited.isEmpty ? null : _done,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: BlurCanvas(
                  key: ValueKey('blur-canvas-${_photo.id}'),
                  photo: _photo,
                  source: widget.source,
                  strokes: List.unmodifiable(edit.strokes),
                  strength: _strength,
                  background: _background,
                  feather: _feather,
                  brush: _brush,
                  erase: _tool == _Tool.eraser,
                  showBrush: _showBrush,
                  tint: theme.colorScheme.primary,
                  onStroke: _add,
                ),
              ),
              if (n > 1) _pager(n),
              SizedBox(height: 96, child: _panel()),
              const Divider(height: 1),
              SafeArea(top: false, child: _toolBar(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pager(int n) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        key: const ValueKey('blur-prev'),
        tooltip: 'Foto sebelumnya',
        icon: const Icon(Icons.chevron_left),
        onPressed: _page == 0 ? null : () => setState(() => _page--),
      ),
      Text('${_page + 1} / $n'),
      IconButton(
        key: const ValueKey('blur-next'),
        tooltip: 'Foto berikutnya',
        icon: const Icon(Icons.chevron_right),
        onPressed: _page == n - 1 ? null : () => setState(() => _page++),
      ),
    ],
  );

  /// Slider tingkat 0..10 dengan label di kiri dan angka di kanan.
  Widget _level(String key, String label, int value, ValueChanged<int> onChanged, {String? zero}) => SizedBox(
    height: 44,
    child: Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(
            key: ValueKey(key),
            value: value.toDouble(),
            max: BlurOptions.maxLevel.toDouble(),
            divisions: BlurOptions.maxLevel,
            label: value == 0 && zero != null ? zero : '$value',
            onChanged: (v) => setState(() => onChanged(v.round())),
            onChangeEnd: (_) => _remember(),
          ),
        ),
        SizedBox(width: 40, child: Text(value == 0 && zero != null ? zero : '$value', textAlign: TextAlign.end)),
      ],
    ),
  );

  Widget _panel() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: switch (_tool) {
      _Tool.strength => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _level(
            'blur-strength',
            'Diusap',
            BlurOptions.levelOf(_strength),
            (l) => _strength = BlurOptions.strengthOf(l),
            zero: 'Tajam',
          ),
          _level(
            'blur-background',
            'Area lain',
            BlurOptions.levelOf(_background),
            (l) => _background = BlurOptions.strengthOf(l),
            zero: 'Tajam',
          ),
        ],
      ),
      _Tool.edge => Center(
        child: _level(
          'blur-feather',
          'Lembut',
          BlurOptions.featherLevelOf(_feather),
          (l) => _feather = BlurOptions.featherOf(l),
        ),
      ),
      _ => Row(
        children: [
          const Text('Ukuran'),
          Expanded(
            child: Slider(
              key: const ValueKey('blur-brush'),
              value: _brush,
              min: BlurSettings.minBrush,
              max: BlurSettings.maxBrush,
              onChangeStart: (_) => setState(() => _showBrush = true),
              onChanged: (v) => setState(() => _brush = v),
              onChangeEnd: (_) {
                setState(() => _showBrush = false);
                _remember();
              },
            ),
          ),
        ],
      ),
    },
  );

  Widget _toolBar(ThemeData theme) {
    Widget tool(_Tool t, IconData icon, String label) {
      final on = _tool == t;
      final color = on ? theme.colorScheme.primary : Colors.white70;
      return Expanded(
        child: InkWell(
          key: ValueKey('blur-tool-${t.name}'),
          onTap: () => setState(() => _tool = t),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 4),
                Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tool(_Tool.brush, Icons.brush, 'Kuas'),
        tool(_Tool.eraser, Icons.auto_fix_off, 'Penghapus'),
        tool(_Tool.strength, Icons.blur_on, 'Kekuatan'),
        tool(_Tool.edge, Icons.gradient, 'Tepi'),
      ],
    );
  }
}

/// Foto sebesar mungkin di ruang yang tersedia, dengan blur di area [strokes].
/// Satu jari: usapan baru ([onStroke] saat jari diangkat; ketuk = titik). Dua jari: perbesar
/// (sampai 8×) dan geser; jari yang tersisa setelahnya hanya menggeser.
class BlurCanvas extends StatefulWidget {
  const BlurCanvas({
    super.key,
    required this.photo,
    required this.source,
    required this.strokes,
    required this.strength,
    required this.brush,
    required this.erase,
    this.background = 0,
    this.feather = BlurOptions.defaultFeather,
    required this.onStroke,
    this.showBrush = false,
    this.tint = Colors.green,
  });

  final Photo photo;
  final GallerySource source;
  final List<BlurStroke> strokes;
  final double strength;
  final double background;
  final double feather;

  /// Jari-jari kuas di layar (titik logis), tidak ikut zoom.
  final double brush;
  final bool erase;
  final ValueChanged<BlurStroke> onStroke;

  /// Tampilkan lingkaran ukuran kuas di tengah (saat slider ukuran digeser).
  final bool showBrush;

  /// Warna area yang sedang diusap.
  final Color tint;

  static const maxZoom = 8.0;

  @override
  State<BlurCanvas> createState() => _BlurCanvasState();
}

class _BlurCanvasState extends State<BlurCanvas> {
  Size _box = Size.zero;
  Size _fit = Size.zero;
  double _scale = 1;

  /// Geseran foto dari posisi tengahnya.
  Offset _offset = Offset.zero;

  int _pointers = 0;

  /// Lebih dari satu jari sejak jari pertama turun: tidak menggambar sampai semua diangkat.
  bool _multi = false;
  Offset? _down;
  BlurStroke? _current;
  Offset? _cursor;
  Offset? _lastPoint;
  double _lastScale = 1;
  Offset _lastFocal = Offset.zero;

  Rect get _rect {
    final w = _fit.width * _scale;
    final h = _fit.height * _scale;
    final base = Offset((_box.width - _fit.width) / 2, (_box.height - _fit.height) / 2);
    return (base + _offset) & Size(w, h);
  }

  Offset _norm(Offset p) {
    final r = _rect;
    return Offset((p.dx - r.left) / r.width, (p.dy - r.top) / r.height);
  }

  BlurStroke _newStroke(List<Offset> screen) {
    final r = _rect;
    return BlurStroke(
      radius: widget.brush / math.max(r.width, r.height),
      points: [for (final p in screen) _norm(p)],
      erase: widget.erase,
    );
  }

  void _cancelStroke() => setState(() {
    _current = null;
    _cursor = null;
  });

  /// Perbesar [factor]× di sekitar [focal], lalu geser [pan].
  void _zoom(double factor, Offset focal, Offset pan) {
    final r = _rect;
    final base = r.topLeft - _offset;
    final scale = (_scale * factor).clamp(1.0, BlurCanvas.maxZoom);
    final q = (focal - pan - r.topLeft) / _scale;
    var off = focal - base - q * scale;
    // Tidak ada celah di tepi bila foto lebih besar dari layar; di tengah bila lebih kecil.
    double clampAxis(double o, double b, double fit, double box) {
      final size = fit * scale;
      final left = size <= box ? (box - size) / 2 : (b + o).clamp(box - size, 0.0);
      return left - b;
    }

    off = Offset(
      clampAxis(off.dx, base.dx, _fit.width, _box.width),
      clampAxis(off.dy, base.dy, _fit.height, _box.height),
    );
    setState(() {
      _scale = scale;
      _offset = off;
    });
  }

  void _resetZoom() => setState(() {
    _scale = 1;
    _offset = Offset.zero;
  });

  void _onDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers == 1) {
      _down = e.localPosition;
    } else {
      _multi = true;
      _cancelStroke();
    }
  }

  void _onUp(PointerEvent e) {
    _pointers = math.max(0, _pointers - 1);
    if (_pointers == 0) _multi = false;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _lastScale = 1;
    _lastFocal = d.localFocalPoint;
    if (d.pointerCount == 1 && !_multi) {
      final start = _down ?? d.localFocalPoint;
      _lastPoint = d.localFocalPoint;
      setState(() {
        _current = _newStroke([start, d.localFocalPoint]);
        _cursor = d.localFocalPoint;
      });
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final cur = _current;
    if (cur != null) {
      final p = d.localFocalPoint;
      setState(() => _cursor = p);
      if ((p - _lastPoint!).distance >= 2) {
        _lastPoint = p;
        setState(() => _current = cur.withPoints([...cur.points, _norm(p)]));
      }
      return;
    }
    _zoom(d.scale / _lastScale, d.localFocalPoint, d.localFocalPoint - _lastFocal);
    _lastScale = d.scale;
    _lastFocal = d.localFocalPoint;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final cur = _current;
    if (cur == null) return;
    // pointerCount > 0: jari kedua turun di tengah usapan (berubah jadi zoom), bukan selesai.
    if (d.pointerCount == 0 && !_multi) widget.onStroke(cur);
    _cancelStroke();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photo;
    // Ukuran tidak diketahui: anggap 4:3 mendatar.
    final known = p.width > 0 && p.height > 0;
    final src = Size(known ? p.width.toDouble() : 4000, known ? p.height.toDouble() : 3000);
    return LayoutBuilder(
      builder: (context, box) {
        _box = box.biggest;
        final fit = applyBoxFit(BoxFit.contain, src, Size(_box.width - 16, _box.height - 24)).destination;
        if (fit != _fit) {
          _fit = fit;
          _scale = 1;
          _offset = Offset.zero;
        }
        final r = _rect;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final long = math.max(r.width, r.height) * dpr;
        final size = long <= 1400 ? 1200 : (long <= 2800 ? 2400 : 3600);
        final c = widget.showBrush ? _box.center(Offset.zero) : _cursor;
        return ClipRect(
          child: Listener(
            onPointerDown: _onDown,
            onPointerUp: _onUp,
            onPointerCancel: _onUp,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                if (!_multi) widget.onStroke(_newStroke([d.localPosition]));
              },
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: r,
                    child: BlurPreview(
                      key: const ValueKey('blur-preview'),
                      photo: p,
                      source: widget.source,
                      strokes: [...widget.strokes, ?_current],
                      strength: widget.strength,
                      background: widget.background,
                      feather: widget.feather,
                      imageSize: size,
                      tint: _current == null ? null : widget.tint.withValues(alpha: 0.35),
                    ),
                  ),
                  if (c != null)
                    Positioned(
                      left: c.dx - widget.brush,
                      top: c.dy - widget.brush,
                      child: IgnorePointer(
                        child: Container(
                          key: const ValueKey('blur-cursor'),
                          width: widget.brush * 2,
                          height: widget.brush * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
                          ),
                        ),
                      ),
                    ),
                  if (_scale > 1)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton.filledTonal(
                        key: const ValueKey('blur-zoom-reset'),
                        tooltip: 'Ukuran semula',
                        icon: const Icon(Icons.zoom_out_map),
                        onPressed: _resetZoom,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Foto dengan blur [strength] di area [strokes] dan [background] di luarnya, dengan tepi
/// selembut [feather]; mengisi seluruh ukurannya (rasio diatur pemanggil). Semua relatif terhadap
/// sisi terpanjang, sama dengan hasil native.
class BlurPreview extends StatelessWidget {
  const BlurPreview({
    super.key,
    required this.photo,
    required this.source,
    required this.strokes,
    required this.strength,
    this.background = 0,
    this.feather = BlurOptions.defaultFeather,
    this.imageSize = 1200,
    this.tint,
  });

  final Photo photo;
  final GallerySource source;
  final List<BlurStroke> strokes;
  final double strength;
  final double background;
  final double feather;
  final int imageSize;

  /// Bila ada: area blur juga diwarnai (saat sedang mengusap).
  final Color? tint;

  @override
  Widget build(BuildContext context) => _MaskedBlur(
    options: BlurOptions(strength: strength, background: background, feather: feather, strokes: strokes),
    tint: tint,
    child: source.image(photo, size: imageSize, fit: BoxFit.fill),
  );
}

/// Menggambar [child] dua kali: dengan blur area lain, lalu dengan blur area usapan di atasnya.
class _MaskedBlur extends SingleChildRenderObjectWidget {
  const _MaskedBlur({required this.options, this.tint, super.child});

  final BlurOptions options;
  final Color? tint;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMaskedBlur(options, tint);

  @override
  void updateRenderObject(BuildContext context, _RenderMaskedBlur r) => r
    ..options = options
    ..tint = tint;
}

class _RenderMaskedBlur extends RenderProxyBox {
  _RenderMaskedBlur(this._options, this._tint);

  BlurOptions _options;
  set options(BlurOptions v) {
    final o = _options;
    if (identical(v.strokes, o.strokes) &&
        v.strength == o.strength &&
        v.background == o.background &&
        v.feather == o.feather) {
      return;
    }
    _options = v;
    markNeedsPaint();
  }

  Color? _tint;
  set tint(Color? v) {
    if (v == _tint) return;
    _tint = v;
    markNeedsPaint();
  }

  void _drawMask(Canvas canvas, Offset offset) {
    final long = math.max(size.width, size.height);
    final feather = _options.featherSigma(size.width, size.height);
    for (final s in _options.strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..blendMode = s.erase ? BlendMode.dstOut : BlendMode.srcOver;
      if (feather >= 0.5) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, feather);
      final r = s.radius * long;
      Offset at(Offset p) => offset + Offset(p.dx * size.width, p.dy * size.height);
      if (s.points.length == 1) {
        canvas.drawCircle(at(s.points.first), r, paint);
      } else {
        final path = Path()..moveTo(at(s.points.first).dx, at(s.points.first).dy);
        for (final p in s.points.skip(1)) {
          final q = at(p);
          path.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(
          path,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * r
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
  }

  /// [child] di-blur [sigma] px (0 = tajam); [blend] dipakai saat layer digabung.
  void _paintBlurred(PaintingContext context, Offset offset, Rect rect, double sigma, BlendMode blend) {
    final paint = Paint()..blendMode = blend;
    if (sigma > 0) paint.imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp);
    context.canvas.saveLayer(rect, paint);
    context.paintChild(child!, offset);
    context.canvas.restore();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    // Blur dan mask digambar dalam satu kanvas; anak dengan layer sendiri digambar biasa.
    if (child.needsCompositing) return context.paintChild(child, offset);
    final rect = offset & size;
    final o = _options;
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(rect);
    _paintBlurred(context, offset, rect, o.backgroundSigma(size.width, size.height), BlendMode.srcOver);
    if (o.strokes.isNotEmpty) {
      canvas.saveLayer(rect, Paint());
      _drawMask(canvas, offset);
      _paintBlurred(context, offset, rect, o.sigma(size.width, size.height), BlendMode.srcIn);
      canvas.restore();
      final tint = _tint;
      if (tint != null) {
        canvas.saveLayer(rect, Paint());
        _drawMask(canvas, offset);
        canvas.drawRect(
          rect,
          Paint()
            ..color = tint
            ..blendMode = BlendMode.srcIn,
        );
        canvas.restore();
      }
    }
    canvas.restore();
  }
}
