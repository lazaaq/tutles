import 'dart:math' as math;

/// Warna bingkai (RGB, selalu tidak transparan).
enum BorderColor {
  white('Putih', 0xFFFFFF),
  black('Hitam', 0x000000),
  cream('Krem', 0xF3EBDD),
  lightGrey('Abu muda', 0xD9D9D9),
  darkGrey('Abu tua', 0x3A3A3A),
  sand('Pasir', 0xD8C3A5),
  sage('Sage', 0xB7C4A8),
  blush('Merah muda', 0xF2D4D7),
  navy('Biru tua', 0x1F2A44);

  const BorderColor(this.label, this.rgb);
  final String label;
  final int rgb;
}

/// Rasio hasil (lebar : tinggi). Sisa ruang diisi warna bingkai.
enum BorderRatio {
  original('Asli', 0),
  square('1:1', 1),
  portrait45('4:5', 4 / 5),
  portrait34('3:4', 3 / 4),
  portrait23('2:3', 2 / 3),
  story('9:16', 9 / 16),
  landscape43('4:3', 4 / 3),
  landscape32('3:2', 3 / 2),
  landscape169('16:9', 16 / 9);

  const BorderRatio(this.label, this.value);
  final String label;

  /// Lebar / tinggi. 0 = ikuti foto + bingkai.
  final double value;
}

class BorderOptions {
  const BorderOptions({
    this.fraction = defaultFraction,
    this.color = BorderColor.white,
    this.ratio = BorderRatio.original,
  });

  static const defaultFraction = 0.05;

  /// Batas slider ketebalan.
  static const maxFraction = 0.15;

  /// Bingkai di tiap sisi, relatif terhadap sisi terpanjang foto (0.05 = 5%).
  final double fraction;
  final BorderColor color;
  final BorderRatio ratio;

  /// "5%", "2,5%".
  String get fractionLabel {
    final p = (fraction * 1000).round() / 10;
    return '${p == p.roundToDouble() ? p.round() : p.toString().replaceAll('.', ',')}%';
  }

  BorderOptions copyWith({double? fraction, BorderColor? color, BorderRatio? ratio}) => BorderOptions(
        fraction: fraction ?? this.fraction,
        color: color ?? this.color,
        ratio: ratio ?? this.ratio,
      );

  /// Argumen `border` untuk native `convert`.
  Map<String, Object> toMap() => {'width': fraction, 'color': color.rgb, 'ratio': ratio.value};

  @override
  bool operator ==(Object other) =>
      other is BorderOptions && other.fraction == fraction && other.color == color && other.ratio == ratio;

  @override
  int get hashCode => Object.hash(fraction, color, ratio);
}

/// Posisi foto di kanvas bingkai. Rumus yang sama dipakai native iOS (ImageEncoder.swift)
/// dan Android (BorderLayout.java).
class BorderLayout {
  const BorderLayout(this.canvasWidth, this.canvasHeight, this.x, this.y, this.width, this.height);

  final int canvasWidth;
  final int canvasHeight;

  /// Kotak foto di dalam kanvas.
  final int x;
  final int y;
  final int width;
  final int height;

  /// Bingkai [fraction] × sisi terpanjang di tiap sisi, lalu kanvas diperlebar/dipertinggi
  /// sampai [ratio] (0 = tidak), lalu semuanya diperkecil agar sisi terpanjang ≤ [maxSide]
  /// (0 = tidak dibatasi; tidak pernah diperbesar).
  factory BorderLayout.compute(int w, int h, {required double fraction, double ratio = 0, int maxSide = 0}) {
    final b = (fraction * math.max(w, h)).round();
    var cw = w + 2 * b;
    var ch = h + 2 * b;
    if (ratio > 0) {
      if (cw / ch < ratio) {
        cw = (ch * ratio).round();
      } else {
        ch = (cw / ratio).round();
      }
    }
    final long = math.max(cw, ch);
    final s = maxSide > 0 && long > maxSide ? maxSide / long : 1.0;
    final canvasW = (cw * s).round();
    final canvasH = (ch * s).round();
    final iw = math.min((w * s).round(), canvasW);
    final ih = math.min((h * s).round(), canvasH);
    return BorderLayout(canvasW, canvasH, (canvasW - iw) ~/ 2, (canvasH - ih) ~/ 2, iw, ih);
  }

  @override
  String toString() => 'BorderLayout(${canvasWidth}x$canvasHeight, foto ${width}x$height di $x,$y)';
}
