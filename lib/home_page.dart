import 'package:flutter/material.dart';

import 'blur_editor_page.dart';
import 'border_editor_page.dart';
import 'collage_editor_page.dart';
import 'gallery.dart';
import 'picker_page.dart';
import 'settings.dart';

/// Satu fitur edit di beranda.
class Feature {
  const Feature(this.title, this.icon, this.color, this.open);

  final String title;
  final IconData icon;
  final Color color;
  final void Function(BuildContext context, GallerySource source) open;
}

/// Pilih foto -> editor dari [editor] -> simpan. Pilihan dikosongkan bila editor selesai `true`.
void _pickThenEdit(
  BuildContext context,
  GallerySource source,
  String title,
  Future<Widget> Function(List<Photo> photos) editor, {
  String? Function(List<Photo> photos)? check,
}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PickerPage(
      title: title,
      source: source,
      onNext: (ctx, photos) async {
        final problem = check?.call(photos);
        if (problem != null) {
          ScaffoldMessenger.of(ctx)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(problem)));
          return false;
        }
        final page = await editor(photos);
        if (!ctx.mounted) return false;
        final done = await Navigator.of(ctx).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => page));
        return done == true;
      },
    ),
  ));
}

/// Bingkai: semua foto memakai bingkai yang sama.
void openBorder(BuildContext context, GallerySource source) => _pickThenEdit(context, source, 'Bingkai', (photos) async {
      final border = await BorderSettings.load();
      final save = await SaveSettings.load();
      return BorderEditorPage(photos: photos, source: source, initial: border, save: save);
    });

/// Blur: usap area yang ingin di-blur, tiap foto sendiri-sendiri.
void openBlur(BuildContext context, GallerySource source) => _pickThenEdit(context, source, 'Blur', (photos) async {
      final blur = await BlurSettings.load();
      final save = await SaveSettings.load();
      return BlurEditorPage(photos: photos, source: source, initial: blur, save: save);
    });

/// Kolase: 2..5 foto menjadi satu foto baru.
void openCollage(BuildContext context, GallerySource source) => _pickThenEdit(
      context,
      source,
      'Kolase',
      (photos) async {
        final collage = await CollageSettings.load();
        final save = await SaveSettings.load();
        return CollageEditorPage(photos: photos, source: source, initial: collage, save: save);
      },
      check: (photos) => photos.length < 2
          ? 'Pilih minimal 2 foto untuk kolase.'
          : (photos.length > 5 ? 'Kolase paling banyak 5 foto.' : null),
    );

final kFeatures = <Feature>[
  const Feature('Bingkai', Icons.filter_frames, Colors.green, openBorder),
  const Feature('Blur', Icons.blur_on, Colors.blue, openBlur),
  const Feature('Kolase', Icons.dashboard, Colors.orange, openCollage),
];

/// Beranda: ikon kecil berjajar untuk setiap fitur.
class HomePage extends StatelessWidget {
  HomePage({super.key, GallerySource? source}) : source = source ?? DeviceGallery();

  final GallerySource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
          Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.auto_fix_high, size: 32, color: Colors.green),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('tutles', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text('Edit foto sederhana', style: theme.textTheme.bodyMedium),
              ]),
            ),
          ]),
          const SizedBox(height: 32),
          Text('Fitur', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, box) {
            final perRow = (box.maxWidth / 88).floor().clamp(4, 8);
            final w = box.maxWidth / perRow;
            return Wrap(
              runSpacing: 16,
              children: [for (final f in kFeatures) SizedBox(width: w, child: FeatureIcon(feature: f, source: source))],
            );
          }),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.outline),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Semua diproses di perangkat, tanpa internet.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ),
          ]),
        ]),
      ),
    );
  }
}

class FeatureIcon extends StatelessWidget {
  const FeatureIcon({super.key, required this.feature, required this.source});

  final Feature feature;
  final GallerySource source;

  @override
  Widget build(BuildContext context) {
    final f = feature;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => f.open(context, source),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: f.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
            child: Icon(f.icon, size: 28, color: f.color),
          ),
          const SizedBox(height: 6),
          Text(f.title, textAlign: TextAlign.center, maxLines: 2, style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
    );
  }
}
