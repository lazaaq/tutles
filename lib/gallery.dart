import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// Satu foto di galeri.
class Photo {
  const Photo({required this.id, required this.width, required this.height, this.title = ''});

  final String id;

  /// Ukuran setelah orientasi EXIF diterapkan (0 bila tidak diketahui).
  final int width;
  final int height;
  final String title;
}

/// Sumber foto galeri; diganti dengan versi palsu di test.
abstract class GallerySource {
  /// true bila boleh membaca galeri (penuh atau terbatas).
  Future<bool> requestAccess();

  Future<void> openSettings();

  Future<int> count();

  /// Foto ke [start] sampai sebelum [end], terbaru dulu.
  Future<List<Photo>> load(int start, int end);

  Widget image(Photo photo, {required int size, BoxFit fit = BoxFit.cover});
}

/// Galeri asli lewat photo_manager.
class DeviceGallery implements GallerySource {
  AssetPathEntity? _all;
  final Map<String, AssetEntity> _entities = {};

  @override
  Future<bool> requestAccess() async {
    final p = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(type: RequestType.image, mediaLocation: true),
      ),
    );
    return p.hasAccess;
  }

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  Future<AssetPathEntity?> _path() async {
    if (_all != null) return _all;
    final paths = await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);
    return _all = paths.firstOrNull;
  }

  @override
  Future<int> count() async => await (await _path())?.assetCountAsync ?? 0;

  @override
  Future<List<Photo>> load(int start, int end) async {
    final path = await _path();
    if (path == null) return [];
    final list = await path.getAssetListRange(start: start, end: end);
    return [
      for (final e in list)
        if (e.type == AssetType.image) _remember(e),
    ];
  }

  Photo _remember(AssetEntity e) {
    _entities[e.id] = e;
    return Photo(id: e.id, width: e.orientatedWidth, height: e.orientatedHeight, title: e.title ?? '');
  }

  @override
  Widget image(Photo photo, {required int size, BoxFit fit = BoxFit.cover}) {
    final e = _entities[photo.id];
    if (e == null) return const ColoredBox(color: Color(0xFF555555));
    return AssetEntityImage(
      e,
      isOriginal: false,
      thumbnailSize: ThumbnailSize.square(size),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF555555)),
    );
  }
}
