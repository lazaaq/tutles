import 'dart:math' as math;

import 'border.dart';

/// Tata letak kolase: kotak-kotak sama besar dalam [cols] kolom × [rows] baris.
/// Mendatar = tiap foto jadi pita mendatar, bertumpuk ke bawah; vertikal = tiap foto jadi pita
/// tegak, berjajar ke samping.
enum CollageLayout {
  horizontal2('Mendatar 2', 1, 2),
  horizontal3('Mendatar 3', 1, 3),
  horizontal4('Mendatar 4', 1, 4),
  horizontal5('Mendatar 5', 1, 5),
  vertical2('Vertikal 2', 2, 1),
  vertical3('Vertikal 3', 3, 1),
  grid2x2('Grid 2×2', 2, 2);

  const CollageLayout(this.label, this.cols, this.rows);
  final String label;
  final int cols;
  final int rows;

  int get count => cols * rows;

  /// Tata letak bawaan untuk [n] foto.
  static CollageLayout forCount(int n) => switch (n) {
    <= 2 => vertical2,
    3 => vertical3,
    4 => grid2x2,
    _ => horizontal5,
  };
}

/// Rasio kanvas kolase (tanpa "Asli").
final kCollageRatios = [
  for (final r in BorderRatio.values)
    if (r != BorderRatio.original) r,
];

class CollageOptions {
  const CollageOptions({
    this.layout = CollageLayout.vertical2,
    this.gap = defaultGap,
    this.color = BorderColor.white,
    this.ratio = BorderRatio.square,
  });

  static const defaultGap = 0.02;
  static const maxGap = 0.1;

  /// Sisi terpanjang hasil bila ukuran "Asli" dipilih.
  static const defaultLongSide = 4096;

  final CollageLayout layout;

  /// Jarak antar foto dan di tepi, relatif terhadap sisi terpanjang kanvas.
  final double gap;
  final BorderColor color;
  final BorderRatio ratio;

  /// "2%", "0,5%".
  String get gapLabel {
    final p = (gap * 1000).round() / 10;
    return '${p == p.roundToDouble() ? p.round() : p.toString().replaceAll('.', ',')}%';
  }

  CollageOptions copyWith({CollageLayout? layout, double? gap, BorderColor? color, BorderRatio? ratio}) =>
      CollageOptions(
        layout: layout ?? this.layout,
        gap: gap ?? this.gap,
        color: color ?? this.color,
        ratio: ratio ?? this.ratio,
      );

  /// Argumen native `collage` (selain id, kualitas, ukuran). [crops]: posisi potongan tiap foto
  /// (lihat [CollageGeometry.cover]), urut sama dengan id; kosong = semua di tengah.
  Map<String, Object> toMap([List<CropPosition> crops = const []]) => {
    'cols': layout.cols,
    'rows': layout.rows,
    'gap': gap,
    'color': color.rgb,
    'ratio': ratio.value,
    'crops': [
      for (final c in crops) ...[c.x, c.y],
    ],
  };
}

/// Posisi potongan foto di kotaknya: 0 = tepi kiri/atas foto, 1 = tepi kanan/bawah, 0.5 = tengah.
typedef CropPosition = ({double x, double y});

const CropPosition kCropCenter = (x: 0.5, y: 0.5);

/// Kotak piksel bilangan bulat, origin kiri atas.
typedef IntRect = ({int x, int y, int w, int h});

/// Geometri kolase. Rumus yang sama dipakai native iOS (`CollageSpec` di ImageEncoder.swift)
/// dan Android (CollageGeometry.java).
class CollageGeometry {
  const CollageGeometry(this.width, this.height, this.cells);

  final int width;
  final int height;

  /// Kotak foto, baris demi baris dari kiri atas.
  final List<IntRect> cells;

  /// Kanvas dengan sisi terpanjang [longSide] dan rasio [ratio] (lebar/tinggi); jarak [gap] ×
  /// sisi terpanjang di antara dan di sekeliling kotak. Sisa pembulatan dibagi rata.
  factory CollageGeometry.compute(
    int cols,
    int rows, {
    required double ratio,
    required int longSide,
    required double gap,
  }) {
    final w = ratio >= 1 ? longSide : math.max(1, (longSide * ratio).round());
    final h = ratio >= 1 ? math.max(1, (longSide / ratio).round()) : longSide;
    final g = (gap * math.max(w, h)).round();
    List<(int, int)> split(int total, int n) {
      final avail = math.max(n, total - (n + 1) * g);
      return [
        for (var i = 0; i < n; i++)
          (g + i * g + (avail * i / n).round(), (avail * (i + 1) / n).round() - (avail * i / n).round()),
      ];
    }

    final xs = split(w, cols);
    final ys = split(h, rows);
    return CollageGeometry(w, h, [
      for (final (y, ch) in ys)
        for (final (x, cw) in xs) (x: x, y: y, w: cw, h: ch),
    ]);
  }

  /// Bagian foto [iw]x[ih] yang mengisi kotak [cw]x[ch] penuh. Sisa foto yang terpotong dibagi
  /// menurut [pos] (0.5 = di tengah).
  static IntRect cover(int iw, int ih, int cw, int ch, [CropPosition pos = kCropCenter]) {
    if (iw * ch > ih * cw) {
      final sw = math.max(1, (ih * cw / ch).round());
      return (x: ((iw - sw) * pos.x.clamp(0.0, 1.0)).floor(), y: 0, w: sw, h: ih);
    }
    final sh = math.max(1, (iw * ch / cw).round());
    return (x: 0, y: ((ih - sh) * pos.y.clamp(0.0, 1.0)).floor(), w: iw, h: sh);
  }
}
