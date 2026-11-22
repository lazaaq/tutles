import 'package:flutter/services.dart';

class RenderResult {
  const RenderResult({required this.newId, required this.inBytes, required this.outBytes});

  final String newId;
  final int inBytes;
  final int outBytes;
}

/// Jembatan ke renderer native (iOS: ImageIO/Core Graphics, Android: Bitmap/MediaStore).
class TutlesNative {
  static const _ch = MethodChannel('tutles/native');

  /// Simpan versi baru foto [id] sebagai foto baru di galeri; foto asli tidak diubah.
  /// [edits] berisi `border` (lihat `BorderOptions.toMap`) dan/atau `blur` (`BlurOptions.toMap`).
  /// [maxSide] membatasi sisi terpanjang hasil (0 = asli). Format tetap sama dengan asli
  /// (Android: HEIC menjadi JPG).
  static Future<RenderResult> render(
    String id, {
    required int quality,
    required int maxSide,
    Map<String, Object> edits = const {},
  }) async {
    final m = await _ch.invokeMapMethod<String, dynamic>('render', {
      'id': id,
      'quality': quality,
      'maxSide': maxSide,
      'format': 'same',
      ...edits,
    });
    return RenderResult(
      newId: m?['newId'] as String? ?? '',
      inBytes: (m?['inBytes'] as num?)?.toInt() ?? 0,
      outBytes: (m?['outBytes'] as num?)?.toInt() ?? 0,
    );
  }

  /// Satu foto baru berisi [ids] (urutan = kotak dari kiri atas) dengan tata letak [collage]
  /// (lihat `CollageOptions.toMap`). Sisi terpanjang [maxSide] (0 = 4096). Format, tanggal, dan
  /// lokasi mengikuti foto pertama.
  static Future<RenderResult> collage(
    List<String> ids, {
    required int quality,
    required int maxSide,
    required Map<String, Object> collage,
  }) async {
    final m = await _ch.invokeMapMethod<String, dynamic>('collage', {
      'ids': ids,
      'quality': quality,
      'maxSide': maxSide,
      ...collage,
    });
    return RenderResult(
      newId: m?['newId'] as String? ?? '',
      inBytes: (m?['inBytes'] as num?)?.toInt() ?? 0,
      outBytes: (m?['outBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

String formatBytes(int b) {
  if (b <= 0) return '-';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}
