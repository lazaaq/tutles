import 'package:shared_preferences/shared_preferences.dart';

import 'blur.dart';
import 'collage.dart';
import 'border.dart';

/// Pilihan ukuran sisi terpanjang hasil. 0 = resolusi asli.
const kSizeOptions = <int, String>{
  0: 'Asli',
  6000: '6000 px',
  4096: '4096 px',
  3000: '3000 px',
  2048: '2048 px',
};

/// Pilihan simpan terakhir (kualitas, ukuran).
class SaveSettings {
  const SaveSettings({this.quality = 90, this.maxSide = 0});

  final int quality;
  final int maxSide;

  static Future<SaveSettings> load() async {
    const d = SaveSettings();
    try {
      final p = await SharedPreferences.getInstance();
      final q = p.getInt('save.quality');
      final m = p.getInt('save.maxSide');
      return SaveSettings(
        quality: q != null && q >= 50 && q <= 100 ? q : d.quality,
        maxSide: m != null && kSizeOptions.containsKey(m) ? m : d.maxSide,
      );
    } catch (_) {
      return d;
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('save.quality', quality);
      await p.setInt('save.maxSide', maxSide);
    } catch (_) {}
  }
}

/// Pilihan bingkai terakhir.
class BorderSettings {
  static const _k = 'border.';

  static Future<BorderOptions> load() async {
    const d = BorderOptions();
    try {
      final p = await SharedPreferences.getInstance();
      T pick<T extends Enum>(List<T> values, String key, T fallback) =>
          values.where((v) => v.name == p.getString('$_k$key')).firstOrNull ?? fallback;
      final f = p.getDouble('${_k}fraction');
      return BorderOptions(
        fraction: f != null && f >= 0 && f <= BorderOptions.maxFraction ? f : d.fraction,
        color: pick(BorderColor.values, 'color', d.color),
        ratio: pick(BorderRatio.values, 'ratio', d.ratio),
      );
    } catch (_) {
      return d;
    }
  }

  static Future<void> save(BorderOptions o) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('${_k}fraction', o.fraction);
      await p.setString('${_k}color', o.color.name);
      await p.setString('${_k}ratio', o.ratio.name);
    } catch (_) {}
  }
}

/// Pilihan blur terakhir: kekuatan, tepi, dan ukuran kuas (jari-jari di layar, titik logis).
class BlurSettings {
  const BlurSettings({
    this.strength = BlurOptions.defaultStrength,
    this.background = 0,
    this.feather = BlurOptions.defaultFeather,
    this.brush = defaultBrush,
  });

  static const minBrush = 6.0;
  static const maxBrush = 48.0;
  static const defaultBrush = 20.0;

  final double strength;
  final double background;
  final double feather;
  final double brush;

  static Future<BlurSettings> load() async {
    const d = BlurSettings();
    try {
      final p = await SharedPreferences.getInstance();
      int? level(String k) {
        final v = p.getInt(k);
        return v != null && v >= 0 && v <= BlurOptions.maxLevel ? v : null;
      }

      final l = level('blur.level');
      final bg = level('blur.background');
      final f = level('blur.feather');
      final b = p.getDouble('blur.brush');
      return BlurSettings(
        strength: l != null ? BlurOptions.strengthOf(l) : d.strength,
        background: bg != null ? BlurOptions.strengthOf(bg) : d.background,
        feather: f != null ? BlurOptions.featherOf(f) : d.feather,
        brush: b != null && b >= minBrush && b <= maxBrush ? b : d.brush,
      );
    } catch (_) {
      return d;
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('blur.level', BlurOptions.levelOf(strength));
      await p.setInt('blur.background', BlurOptions.levelOf(background));
      await p.setInt('blur.feather', BlurOptions.featherLevelOf(feather));
      await p.setDouble('blur.brush', brush);
    } catch (_) {}
  }
}

/// Pilihan kolase terakhir (tata letak dipilih ulang sesuai jumlah foto).
class CollageSettings {
  static const _k = 'collage.';

  static Future<CollageOptions> load() async {
    const d = CollageOptions();
    try {
      final p = await SharedPreferences.getInstance();
      T pick<T extends Enum>(List<T> values, String key, T fallback) =>
          values.where((v) => v.name == p.getString('$_k$key')).firstOrNull ?? fallback;
      final g = p.getDouble('${_k}gap');
      final ratio = pick(BorderRatio.values, 'ratio', d.ratio);
      return CollageOptions(
        gap: g != null && g >= 0 && g <= CollageOptions.maxGap ? g : d.gap,
        color: pick(BorderColor.values, 'color', d.color),
        ratio: ratio == BorderRatio.original ? d.ratio : ratio,
      );
    } catch (_) {
      return d;
    }
  }

  static Future<void> save(CollageOptions o) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('${_k}gap', o.gap);
      await p.setString('${_k}color', o.color.name);
      await p.setString('${_k}ratio', o.ratio.name);
    } catch (_) {}
  }
}
