import 'package:flutter/material.dart';

import 'settings.dart';

/// Opsi simpan (kualitas, ukuran) di bawah layar. Pilihan langsung diingat.
/// Hasil: pengaturan bila Simpan ditekan, null bila batal. [sizes]: pilihan ukuran (kunci 0 wajib).
Future<SaveSettings?> showSaveSheet(
  BuildContext context, {
  required String title,
  required String summary,
  required SaveSettings initial,
  Map<int, String> sizes = kSizeOptions,
}) async {
  var save = initial;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        void up(SaveSettings s) {
          setSheet(() => save = s);
          s.save();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Kualitas'),
                  Expanded(
                    child: Slider(
                      value: save.quality.toDouble(),
                      min: 50,
                      max: 100,
                      divisions: 50,
                      label: '${save.quality}',
                      onChanged: (v) => setSheet(() => save = SaveSettings(quality: v.round(), maxSide: save.maxSide)),
                      onChangeEnd: (_) => save.save(),
                    ),
                  ),
                  SizedBox(width: 32, child: Text('${save.quality}', textAlign: TextAlign.end)),
                ],
              ),
              Row(
                children: [
                  const Text('Ukuran'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<int>(
                      key: const ValueKey('save-size'),
                      isExpanded: true,
                      value: sizes.containsKey(save.maxSide) ? save.maxSide : 0,
                      items: [
                        for (final e in sizes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => up(SaveSettings(quality: save.quality, maxSide: v ?? save.maxSide)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$summary Disimpan sebagai foto baru dengan format yang sama; foto asli tidak diubah.',
                key: const ValueKey('save-summary'),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
  return ok == true ? save : null;
}
