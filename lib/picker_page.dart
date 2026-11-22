import 'package:flutter/material.dart';

import 'gallery.dart';

/// Pilih beberapa foto dari galeri, lalu [onNext] membuka langkah berikutnya.
/// Bila [onNext] mengembalikan true (foto sudah diproses), pilihan dikosongkan.
class PickerPage extends StatefulWidget {
  const PickerPage({super.key, required this.title, required this.source, required this.onNext});

  final String title;
  final GallerySource source;
  final Future<bool> Function(BuildContext context, List<Photo> photos) onNext;

  @override
  State<PickerPage> createState() => _PickerPageState();
}

class _PickerPageState extends State<PickerPage> {
  static const _pageSize = 120;

  bool? _access;
  int _total = 0;
  final List<Photo> _photos = [];
  bool _loadingMore = false;
  String? _error;

  /// Urutan memilih dipertahankan: foto pertama dipilih tampil pertama di editor.
  final List<String> _selected = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _access = null;
      _error = null;
    });
    try {
      final ok = await widget.source.requestAccess();
      if (!ok) return setState(() => _access = false);
      final total = await widget.source.count();
      final first = await widget.source.load(0, total < _pageSize ? total : _pageSize);
      if (!mounted) return;
      setState(() {
        _access = true;
        _total = total;
        _photos
          ..clear()
          ..addAll(first);
        _selected.removeWhere((id) => !_photos.any((p) => p.id == id));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _photos.length >= _total) return;
    _loadingMore = true;
    try {
      final start = _photos.length;
      final end = start + _pageSize > _total ? _total : start + _pageSize;
      final more = await widget.source.load(start, end);
      if (!mounted) return;
      setState(() => _photos.addAll(more));
      if (more.isEmpty) _total = _photos.length; // galeri berubah: berhenti memuat
    } finally {
      _loadingMore = false;
    }
  }

  List<Photo> get _selectedPhotos =>
      [for (final id in _selected) _photos.firstWhere((p) => p.id == id)];

  Future<void> _next() async {
    final done = await widget.onNext(context, _selectedPhotos);
    if (done && mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? widget.title : '${_selected.length} dipilih'),
        actions: [
          if (_selected.isNotEmpty)
            IconButton(
              tooltip: 'Batalkan pilihan',
              icon: const Icon(Icons.deselect),
              onPressed: () => setState(_selected.clear),
            ),
        ],
      ),
      body: _body(),
      bottomNavigationBar: _access == true && _photos.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _selected.isEmpty ? null : _next,
                  label: Text(_selected.isEmpty ? 'Pilih foto' : 'Lanjut (${_selected.length} foto)'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _body() {
    if (_error != null) {
      return _message(Icons.error_outline, _error!, FilledButton(onPressed: _init, child: const Text('Coba lagi')));
    }
    if (_access == null) return const Center(child: CircularProgressIndicator());
    if (_access == false) {
      return _message(
        Icons.lock_outline,
        'Izin galeri dibutuhkan untuk memilih foto.',
        FilledButton(onPressed: widget.source.openSettings, child: const Text('Buka Pengaturan')),
      );
    }
    if (_photos.isEmpty) {
      return _message(Icons.photo_library_outlined, 'Tidak ada foto di galeri.',
          OutlinedButton(onPressed: _init, child: const Text('Muat ulang')));
    }
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _photos.length,
      itemBuilder: (_, i) {
        if (i >= _photos.length - 30) _loadMore();
        final p = _photos[i];
        final order = _selected.indexOf(p.id);
        final sel = order >= 0;
        return GestureDetector(
          key: ValueKey('photo-${p.id}'),
          onTap: () => setState(() => sel ? _selected.remove(p.id) : _selected.add(p.id)),
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: scheme.surfaceContainerHighest, child: widget.source.image(p, size: 250)),
            if (sel) DecoratedBox(decoration: BoxDecoration(border: Border.all(color: scheme.primary, width: 3))),
            Positioned(
              top: 4,
              right: 4,
              child: sel
                  ? CircleAvatar(
                      radius: 11,
                      backgroundColor: scheme.primary,
                      child: Text('${order + 1}', style: TextStyle(fontSize: 11, color: scheme.onPrimary)),
                    )
                  : const Icon(Icons.radio_button_unchecked, color: Colors.white, shadows: [Shadow(blurRadius: 4)]),
            ),
          ]),
        );
      },
    );
  }

  Widget _message(IconData icon, String text, Widget action) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            action,
          ]),
        ),
      );
}
