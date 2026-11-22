import 'package:shared_preferences/shared_preferences.dart';

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
