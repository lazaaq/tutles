import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutles/border.dart';
import 'package:tutles/native.dart';
import 'package:tutles/settings.dart';

void main() {
  /// Same cases as BorderLayoutTest.java and ios/EncoderTests/main.swift.
  test('layout matches the native shared cases', () {
    List<int> l(int w, int h, double f, double r, int m) {
      final b = BorderLayout.compute(w, h, fraction: f, ratio: r, maxSide: m);
      return [b.canvasWidth, b.canvasHeight, b.x, b.y, b.width, b.height];
    }

    expect(l(1200, 800, 0.05, 0, 0), [1320, 920, 60, 60, 1200, 800]);
    expect(l(1200, 800, 0.05, 1, 0), [1320, 1320, 60, 260, 1200, 800]);
    expect(l(800, 1200, 0.05, 0.8, 0), [1056, 1320, 128, 60, 800, 1200]);
    expect(l(1200, 800, 0.02, 9 / 16, 1000), [562, 1000, 10, 319, 541, 361]);
    expect(l(1000, 1000, 0.1, 0, 600), [600, 600, 50, 50, 500, 500]);
    expect(l(1200, 800, 0, 0, 0), [1200, 800, 0, 0, 1200, 800]);
    expect(l(1200, 800, 0.05, 0, 5000), [1320, 920, 60, 60, 1200, 800], reason: 'never enlarged');
  });

  test('options: label, channel map, ratios', () {
    expect(const BorderOptions().fractionLabel, '5%');
    expect(const BorderOptions(fraction: 0.025).fractionLabel, '2,5%');
    expect(const BorderOptions(fraction: 0).fractionLabel, '0%');
    expect(const BorderOptions(color: BorderColor.navy, ratio: BorderRatio.portrait45).toMap(),
        {'width': 0.05, 'color': 0x1F2A44, 'ratio': 0.8});
    expect(BorderRatio.values.map((r) => r.label), ['Asli', '1:1', '4:5', '3:4', '2:3', '9:16', '4:3', '3:2', '16:9']);
  });

  test('settings: defaults, round trip, invalid stored values fall back', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await BorderSettings.load(), const BorderOptions());
    expect((await SaveSettings.load()).quality, 90);

    const o = BorderOptions(fraction: 0.1, color: BorderColor.black, ratio: BorderRatio.square);
    await BorderSettings.save(o);
    expect(await BorderSettings.load(), o);
    await const SaveSettings(quality: 70, maxSide: 2048).save();
    final s = await SaveSettings.load();
    expect([s.quality, s.maxSide], [70, 2048]);

    SharedPreferences.setMockInitialValues({
      'border.fraction': 0.9,
      'border.color': 'purple',
      'border.ratio': 'x',
      'save.quality': 5,
      'save.maxSide': 1234,
    });
    expect(await BorderSettings.load(), const BorderOptions());
    final d = await SaveSettings.load();
    expect([d.quality, d.maxSide], [90, 0]);
  });

  test('formatBytes', () {
    expect(formatBytes(0), '-');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
  });
}
