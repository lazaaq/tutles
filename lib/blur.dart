import 'dart:math' as math;
import 'dart:ui';

/// Satu usapan kuas. Koordinat relatif terhadap foto tegak (0..1 untuk lebar dan tinggi),
/// jadi tidak bergantung pada resolusi pratinjau atau hasil.
class BlurStroke {
  const BlurStroke({required this.radius, required this.points, this.erase = false});

  /// Jari-jari kuas, relatif terhadap sisi terpanjang foto.
  final double radius;
  final List<Offset> points;

  /// true = penghapus: area ini tidak di-blur lagi.
  final bool erase;

  BlurStroke withPoints(List<Offset> points) => BlurStroke(radius: radius, points: points, erase: erase);

  Map<String, Object> toMap() => {
    'radius': radius,
    'erase': erase,
    'points': [
      for (final p in points) ...[p.dx, p.dy],
    ],
  };
}

/// Blur sebagian foto: area yang diusap kuas di-blur dengan [strength], sisanya dengan
/// [background] (0 = tetap tajam), dengan peralihan selembut [feather]. Rumus yang sama dipakai
/// native iOS (`BlurSpec` di ImageEncoder.swift) dan Android (BlurSpec.java).
class BlurOptions {
  const BlurOptions({
    this.strength = defaultStrength,
    this.background = 0,
    this.feather = defaultFeather,
    this.strokes = const [],
  });

  /// Kekuatan per tingkat; tingkat 0..[maxLevel] (0 = tajam).
  static const levelStep = 0.005;
  static const maxLevel = 10;
  static const defaultStrength = 4 * levelStep;

  /// Kelembutan tepi per tingkat; tingkat 0 = [minFeather] (hanya anti-alias).
  static const featherStep = 0.004;
  static const minFeather = 0.001;
  static const defaultFeather = 3 * featherStep;

  /// Sigma blur area yang diusap, relatif terhadap sisi terpanjang foto (0.02 = 2%).
  final double strength;

  /// Sigma blur area lain, relatif terhadap sisi terpanjang foto.
  final double background;

  /// Sigma tepi lembut (mask di-blur), relatif terhadap sisi terpanjang foto.
  final double feather;
  final List<BlurStroke> strokes;

  static double strengthOf(int level) => level.clamp(0, maxLevel) * levelStep;

  /// 0..10.
  static int levelOf(double strength) => (strength / levelStep).round().clamp(0, maxLevel);

  static double featherOf(int level) => level <= 0 ? minFeather : level.clamp(1, maxLevel) * featherStep;

  /// 0..10.
  static int featherLevelOf(double feather) =>
      feather <= minFeather * 1.5 ? 0 : (feather / featherStep).round().clamp(1, maxLevel);

  /// Ada area yang di-blur (bukan cuma penghapus).
  bool get hasPaint => strokes.any((s) => !s.erase);

  /// Hasilnya berbeda dari foto asli.
  bool get changesPhoto => background > 0 || (strength > 0 && hasPaint);

  /// Sigma blur area yang diusap, dalam piksel untuk foto [w]x[h].
  double sigma(num w, num h) => strength * math.max(w, h);

  /// Sigma blur area lain, dalam piksel.
  double backgroundSigma(num w, num h) => background * math.max(w, h);

  /// Sigma tepi lembut, dalam piksel.
  double featherSigma(num w, num h) => feather * math.max(w, h);

  BlurOptions copyWith({double? strength, double? background, double? feather, List<BlurStroke>? strokes}) =>
      BlurOptions(
        strength: strength ?? this.strength,
        background: background ?? this.background,
        feather: feather ?? this.feather,
        strokes: strokes ?? this.strokes,
      );

  /// Argumen `blur` untuk native `render`.
  Map<String, Object> toMap() => {
    'strength': strength,
    'background': background,
    'feather': feather,
    'strokes': [for (final s in strokes) s.toMap()],
  };
}
