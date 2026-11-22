import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gallery.dart';
import 'native.dart';

/// Simpan foto satu per satu (hemat memori). Foto asli tidak pernah diubah.
class ProcessPage extends StatefulWidget {
  const ProcessPage({
    super.key,
    required this.photos,
    this.edits,
    this.quality = 90,
    this.maxSide = 0,
    this.run,
  });

  final List<Photo> photos;

  /// Edit untuk tiap foto, misalnya `{'border': …}` atau `{'blur': …}`.
  final Map<String, Object> Function(Photo photo)? edits;
  final int quality;
  final int maxSide;

  /// Pengganti `render` per foto (misalnya kolase: satu langkah untuk semua foto).
  final Future<void> Function(Photo photo)? run;

  @override
  State<ProcessPage> createState() => _ProcessPageState();
}

class _ProcessPageState extends State<ProcessPage> {
  int _index = 0;
  int _ok = 0;
  bool _cancel = false;
  bool _done = false;
  final List<({String name, String error})> _failed = [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (final p in widget.photos) {
      if (_cancel) break;
      try {
        final run = widget.run;
        if (run != null) {
          await run(p);
        } else {
          await TutlesNative.render(
            p.id,
            quality: widget.quality,
            maxSide: widget.maxSide,
            edits: widget.edits?.call(p) ?? const {},
          );
        }
        _ok++;
      } on PlatformException catch (e) {
        _failed.add((name: _name(p), error: e.message ?? e.code));
      } catch (e) {
        _failed.add((name: _name(p), error: '$e'));
      }
      if (!mounted) return;
      setState(() => _index++);
    }
    if (mounted) setState(() => _done = true);
  }

  String _name(Photo p) => p.title.isNotEmpty ? p.title : 'Foto ${widget.photos.indexOf(p) + 1}';

  @override
  Widget build(BuildContext context) {
    final total = widget.photos.length;
    return PopScope(
      canPop: _done,
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false, title: Text(_done ? 'Selesai' : 'Menyimpan…')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          LinearProgressIndicator(value: total == 0 ? 1 : _index / total, minHeight: 8),
          const SizedBox(height: 12),
          Text(
            !_done
                ? (_index < total ? 'Foto ${_index + 1} dari $total' : 'Menyelesaikan…')
                : _cancel && _index < total
                    ? 'Dihentikan: $_index dari $total foto diproses'
                    : '$total foto diproses',
          ),
          const SizedBox(height: 24),
          _stat('Berhasil', '$_ok'),
          _stat('Gagal', '${_failed.length}'),
          if (_done && _ok > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Hasil tersimpan di galeri sebagai foto baru (Android: album tutles). Foto asli tidak diubah.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_failed.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Gagal disimpan', style: Theme.of(context).textTheme.titleSmall),
            for (final f in _failed)
              ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(f.name), subtitle: Text(f.error)),
          ],
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _done
                ? FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))
                : OutlinedButton(
                    onPressed: _cancel ? null : () => setState(() => _cancel = true),
                    child: Text(_cancel ? 'Menghentikan…' : 'Hentikan'),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Expanded(child: Text(k)), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}
