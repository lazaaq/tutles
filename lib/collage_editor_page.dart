import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'border.dart';
import 'border_editor_page.dart' show ChoiceTile;
import 'collage.dart';
import 'gallery.dart';
import 'native.dart';
import 'process_page.dart';
import 'save_sheet.dart';
import 'settings.dart';

enum _Tool { layout, gap, color, ratio }

/// Ukuran hasil kolase; 0 = bawaan ([CollageOptions.defaultLongSide]).
const kCollageSizes = <int, String>{0: '4096 px', 6000: '6000 px', 3000: '3000 px', 2048: '2048 px'};

/// Editor kolase layar penuh: pratinjau di atas, alat di bawah. Foto mengisi kotak sesuai urutan
/// dipilih (dipotong di tengah). ✓ membuka opsi simpan lalu halaman proses; route ini lalu
/// selesai dengan `true`. Batal: `null`.
class CollageEditorPage extends StatefulWidget {
  const CollageEditorPage({
    super.key,
    required this.photos,
    required this.source,
    this.initial = const CollageOptions(),
    this.save = const SaveSettings(),
  });

  /// 2..5 foto.
  final List<Photo> photos;
  final GallerySource source;
  final CollageOptions initial;
  final SaveSettings save;

  @override
  State<CollageEditorPage> createState() => _CollageEditorPageState();
}

class _CollageEditorPageState extends State<CollageEditorPage> {
  late CollageOptions _o = widget.initial.copyWith(layout: CollageLayout.forCount(widget.photos.length));
  late SaveSettings _save = widget.save;
  _Tool _tool = _Tool.layout;

  /// Posisi potongan per foto (id); tidak ada = di tengah.
  final Map<String, CropPosition> _crops = {};

  List<Photo> get _used => widget.photos.take(_o.layout.count).toList();

  void _set(CollageOptions o) => setState(() => _o = o);

  Future<void> _done() async {
    CollageSettings.save(_o);
    final used = _used;
    final unused = widget.photos.length - used.length;
    final save = await showSaveSheet(
      context,
      title: 'Simpan kolase?',
      summary:
          '${_o.layout.label}, rasio ${_o.ratio.label}, jarak ${_o.gapLabel} ${_o.color.label.toLowerCase()}'
          '${unused > 0 ? '; $unused foto terakhir tidak dipakai' : ''}.',
      initial: _save,
      sizes: kCollageSizes,
    );
    if (save == null || !mounted) return;
    _save = save;
    final ids = [for (final p in used) p.id];
    final collage = _o.toMap([for (final p in used) _crops[p.id] ?? kCropCenter]);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProcessPage(
          photos: [used.first],
          run: (_) => TutlesNative.collage(ids, quality: save.quality, maxSide: save.maxSide, collage: collage),
        ),
      ),
      result: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorSchemeSeed: Theme.of(context).colorScheme.primary,
      brightness: Brightness.dark,
      useMaterial3: true,
    );
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(tooltip: 'Batal', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          title: const Text('Kolase'),
          actions: [
            IconButton(
              key: const ValueKey('collage-save'),
              tooltip: 'Lanjut',
              icon: const Icon(Icons.check),
              onPressed: _done,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: CollagePreview(
                  photos: _used,
                  options: _o,
                  source: widget.source,
                  crops: _crops,
                  onCrop: (p, c) => setState(() => _crops[p.id] = c),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Geser foto di kotaknya untuk mengatur bagian yang terlihat.',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            ),
            SizedBox(height: 96, child: _panel()),
            const Divider(height: 1),
            SafeArea(top: false, child: _toolBar(theme)),
          ],
        ),
      ),
    );
  }

  Widget _panel() => switch (_tool) {
    _Tool.layout => _strip([
      for (final l in CollageLayout.values)
        ChoiceTile(
          key: ValueKey('collage-layout-${l.name}'),
          label: l.label,
          selected: _o.layout == l,
          onTap: l.count > widget.photos.length ? null : () => _set(_o.copyWith(layout: l)),
          child: LayoutIcon(layout: l),
        ),
    ]),
    _Tool.gap => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Slider(
              key: const ValueKey('collage-gap'),
              value: _o.gap,
              max: CollageOptions.maxGap,
              divisions: 20, // langkah 0,5%
              label: _o.gapLabel,
              onChanged: (v) => _set(_o.copyWith(gap: v)),
            ),
          ),
          SizedBox(width: 48, child: Text(_o.gapLabel, textAlign: TextAlign.end)),
        ],
      ),
    ),
    _Tool.color => _strip([
      for (final c in BorderColor.values)
        ChoiceTile(
          key: ValueKey('collage-color-${c.name}'),
          label: c.label,
          selected: _o.color == c,
          onTap: () => _set(_o.copyWith(color: c)),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | c.rgb),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
          ),
        ),
    ]),
    _Tool.ratio => _strip([
      for (final r in kCollageRatios)
        ChoiceTile(
          key: ValueKey('collage-ratio-${r.name}'),
          label: r.label,
          selected: _o.ratio == r,
          onTap: () => _set(_o.copyWith(ratio: r)),
          child: SizedBox.square(
            dimension: 40,
            child: Center(
              child: Container(
                width: r.value >= 1 ? 32 : 32 * r.value,
                height: r.value >= 1 ? 32 / r.value : 32,
                decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 1.5)),
              ),
            ),
          ),
        ),
    ]),
  };

  Widget _strip(List<Widget> children) => ListView(
    key: ValueKey('collage-strip-${_tool.name}'),
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    children: children,
  );

  Widget _toolBar(ThemeData theme) {
    Widget tool(_Tool t, IconData icon, String label) {
      final on = _tool == t;
      final color = on ? theme.colorScheme.primary : Colors.white70;
      return Expanded(
        child: InkWell(
          key: ValueKey('collage-tool-${t.name}'),
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
        tool(_Tool.layout, Icons.dashboard_outlined, 'Tata letak'),
        tool(_Tool.gap, Icons.padding, 'Jarak'),
        tool(_Tool.color, Icons.palette_outlined, 'Warna'),
        tool(_Tool.ratio, Icons.aspect_ratio, 'Rasio'),
      ],
    );
  }
}

/// Gambar kecil kotak-kotak tata letak.
class LayoutIcon extends StatelessWidget {
  const LayoutIcon({super.key, required this.layout});

  final CollageLayout layout;

  @override
  Widget build(BuildContext context) {
    final g = CollageGeometry.compute(layout.cols, layout.rows, ratio: 1, longSide: 32, gap: 0.08);
    return SizedBox.square(
      dimension: 40,
      child: Center(
        child: SizedBox.square(
          dimension: 32,
          child: Stack(
            children: [
              for (final c in g.cells)
                Positioned(
                  left: c.x.toDouble(),
                  top: c.y.toDouble(),
                  width: c.w.toDouble(),
                  height: c.h.toDouble(),
                  child: const ColoredBox(color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kolase sebesar mungkin di ruang yang tersedia. Rumus sama dengan hasil native.
/// Menggeser foto di kotaknya memanggil [onCrop] dengan posisi potongan baru.
class CollagePreview extends StatelessWidget {
  const CollagePreview({
    super.key,
    required this.photos,
    required this.options,
    required this.source,
    this.crops = const {},
    this.onCrop,
  });

  final List<Photo> photos;
  final CollageOptions options;
  final GallerySource source;
  final Map<String, CropPosition> crops;
  final void Function(Photo photo, CropPosition crop)? onCrop;

  @override
  Widget build(BuildContext context) {
    final o = options;
    final g = CollageGeometry.compute(o.layout.cols, o.layout.rows, ratio: o.ratio.value, longSide: 1000, gap: o.gap);
    return LayoutBuilder(
      builder: (context, box) {
        final s = math.min(box.maxWidth / g.width, box.maxHeight / g.height);
        return Center(
          child: Container(
            key: const ValueKey('collage-canvas'),
            width: g.width * s,
            height: g.height * s,
            color: Color(0xFF000000 | o.color.rgb),
            child: Stack(
              children: [
                for (var i = 0; i < g.cells.length && i < photos.length; i++)
                  Positioned(
                    key: ValueKey('collage-cell-$i'),
                    left: g.cells[i].x * s,
                    top: g.cells[i].y * s,
                    width: g.cells[i].w * s,
                    height: g.cells[i].h * s,
                    child: _cell(photos[i], Size(g.cells[i].w * s, g.cells[i].h * s)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cell(Photo p, Size cell) {
    final c = crops[p.id] ?? kCropCenter;
    // Ukuran tidak diketahui: anggap 4:3 mendatar.
    final known = p.width > 0 && p.height > 0;
    final iw = known ? p.width.toDouble() : 4000.0;
    final ih = known ? p.height.toDouble() : 3000.0;
    // Foto diperbesar sampai menutupi kotak; sisa yang terpotong bisa digeser.
    final k = math.max(cell.width / iw, cell.height / ih);
    final spareX = iw * k - cell.width;
    final spareY = ih * k - cell.height;
    return GestureDetector(
      onPanUpdate: onCrop == null
          ? null
          : (d) => onCrop!(p, (
              x: spareX > 0.5 ? (c.x - d.delta.dx / spareX).clamp(0.0, 1.0) : c.x,
              y: spareY > 0.5 ? (c.y - d.delta.dy / spareY).clamp(0.0, 1.0) : c.y,
            )),
      child: ClipRect(child: source.image(p, size: 800, alignment: Alignment(c.x * 2 - 1, c.y * 2 - 1))),
    );
  }
}
