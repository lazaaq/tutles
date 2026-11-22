import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'border.dart';
import 'gallery.dart';
import 'process_page.dart';
import 'save_sheet.dart';
import 'settings.dart';

enum _Tool { width, color, ratio }

/// Editor bingkai layar penuh: foto selebar layar di atas, pilihan alat di bawah
/// (geser ke kanan untuk pilihan lain). ✓ membuka opsi simpan lalu halaman proses;
/// route ini lalu selesai dengan `true`. Batal: `null`.
class BorderEditorPage extends StatefulWidget {
  const BorderEditorPage({
    super.key,
    required this.photos,
    required this.source,
    this.initial = const BorderOptions(),
    this.save = const SaveSettings(),
  });

  /// Foto yang dipilih; semuanya memakai bingkai yang sama. Geser untuk melihat yang lain.
  final List<Photo> photos;
  final GallerySource source;
  final BorderOptions initial;
  final SaveSettings save;

  @override
  State<BorderEditorPage> createState() => _BorderEditorPageState();
}

class _BorderEditorPageState extends State<BorderEditorPage> {
  late BorderOptions _o = widget.initial;
  late SaveSettings _save = widget.save;
  _Tool _tool = _Tool.width;
  int _page = 0;

  void _set(BorderOptions o) => setState(() => _o = o);

  /// Opsi simpan, lalu proses semua foto.
  Future<void> _done() async {
    BorderSettings.save(_o);
    final save = await showSaveSheet(
      context,
      title: 'Simpan ${widget.photos.length} foto berbingkai?',
      summary: 'Bingkai ${_o.color.label.toLowerCase()} ${_o.fractionLabel}'
          '${_o.ratio == BorderRatio.original ? '' : ', rasio ${_o.ratio.label}'}.',
      initial: _save,
    );
    if (save == null || !mounted) return;
    _save = save;
    final border = _o.toMap();
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProcessPage(
          photos: widget.photos,
          edits: (_) => {'border': border},
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
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            tooltip: 'Batal',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(n > 1 ? 'Bingkai · ${_page + 1} / $n' : 'Bingkai'),
          actions: [
            IconButton(
              key: const ValueKey('border-save'),
              tooltip: 'Lanjut',
              icon: const Icon(Icons.check),
              onPressed: _done,
            ),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: PageView.builder(
              itemCount: n,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: BorderPreview(
                  key: ValueKey('border-preview-$i'),
                  photo: widget.photos[i],
                  options: _o,
                  source: widget.source,
                ),
              ),
            ),
          ),
          SizedBox(height: 96, child: _panel(theme)),
          const Divider(height: 1),
          SafeArea(top: false, child: _toolBar(theme)),
        ]),
      ),
    );
  }

  Widget _panel(ThemeData theme) => switch (_tool) {
        _Tool.width => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: Slider(
                  key: const ValueKey('border-fraction'),
                  value: _o.fraction,
                  max: BorderOptions.maxFraction,
                  divisions: 30, // langkah 0,5%
                  label: _o.fractionLabel,
                  onChanged: (v) => _set(_o.copyWith(fraction: v)),
                ),
              ),
              SizedBox(width: 48, child: Text(_o.fractionLabel, textAlign: TextAlign.end)),
            ]),
          ),
        _Tool.color => _strip([
            for (final c in BorderColor.values)
              ChoiceTile(
                key: ValueKey('border-color-${c.name}'),
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
            for (final r in BorderRatio.values)
              ChoiceTile(
                key: ValueKey('border-ratio-${r.name}'),
                label: r.label,
                selected: _o.ratio == r,
                onTap: () => _set(_o.copyWith(ratio: r)),
                child: SizedBox.square(
                  dimension: 40,
                  child: Center(
                    child: r == BorderRatio.original
                        ? const Icon(Icons.crop_original)
                        : Container(
                            width: r.value >= 1 ? 32 : 32 * r.value,
                            height: r.value >= 1 ? 32 / r.value : 32,
                            decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 1.5)),
                          ),
                  ),
                ),
              ),
          ]),
      };

  /// Pilihan berjajar yang bisa digeser ke kanan.
  /// Tiap alat punya daftar sendiri, jadi posisi geser tidak terbawa saat pindah alat.
  Widget _strip(List<Widget> children) => ListView(
        key: ValueKey('border-strip-${_tool.name}'),
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
          key: ValueKey('border-tool-${t.name}'),
          onTap: () => setState(() => _tool = t),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [
      tool(_Tool.width, Icons.line_weight, 'Ketebalan'),
      tool(_Tool.color, Icons.palette_outlined, 'Warna'),
      tool(_Tool.ratio, Icons.aspect_ratio, 'Rasio'),
    ]);
  }
}

/// Pilihan bergambar dengan label di bawahnya; dipakai di strip alat editor.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({super.key, required this.label, required this.selected, required this.onTap, required this.child});

  final String label;
  final bool selected;

  /// null = tidak bisa dipilih (ditampilkan redup).
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          child,
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: selected ? scheme.primary : null),
          ),
        ]),
      ),
      ),
    );
  }
}

/// Foto berbingkai, sebesar mungkin di ruang yang tersedia. Rumus sama dengan hasil native.
class BorderPreview extends StatelessWidget {
  const BorderPreview({super.key, required this.photo, required this.options, required this.source});

  final Photo photo;
  final BorderOptions options;
  final GallerySource source;

  @override
  Widget build(BuildContext context) {
    // Ukuran tidak diketahui: anggap 4:3 mendatar.
    final known = photo.width > 0 && photo.height > 0;
    final w = known ? photo.width : 4000;
    final h = known ? photo.height : 3000;
    final o = options;
    final l = BorderLayout.compute(w, h, fraction: o.fraction, ratio: o.ratio.value);
    return LayoutBuilder(builder: (context, box) {
      final s = math.min(box.maxWidth / l.canvasWidth, box.maxHeight / l.canvasHeight);
      return Center(
        child: Container(
          key: const ValueKey('border-canvas'),
          width: l.canvasWidth * s,
          height: l.canvasHeight * s,
          color: Color(0xFF000000 | o.color.rgb),
          child: Stack(children: [
            Positioned(
              left: l.x * s,
              top: l.y * s,
              width: l.width * s,
              height: l.height * s,
              child: source.image(photo, size: 1200),
            ),
          ]),
        ),
      );
    });
  }
}
