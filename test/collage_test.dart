import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutles/border.dart';
import 'package:tutles/collage.dart';
import 'package:tutles/settings.dart';

void main() {
  List<Object> geo(int cols, int rows, double ratio, int longSide, double gap) {
    final g = CollageGeometry.compute(cols, rows, ratio: ratio, longSide: longSide, gap: gap);
    return [
      g.width,
      g.height,
      for (final c in g.cells) [c.x, c.y, c.w, c.h],
    ];
  }

  /// Same cases as CollageGeometryTest.java and ios/EncoderTests/main.swift.
  test('geometry matches the native shared cases', () {
    expect(geo(2, 1, 1, 1000, 0.02), [
      1000,
      1000,
      [20, 20, 470, 960],
      [510, 20, 470, 960],
    ]);
    expect(geo(3, 1, 16 / 9, 1920, 0.01), [
      1920, 1080, [19, 19, 615, 1042], [653, 19, 614, 1042], [1286, 19, 615, 1042], //
    ]);
    expect(geo(1, 3, 0.8, 1000, 0.03), [
      800,
      1000,
      [30, 30, 740, 293],
      [30, 353, 740, 294],
      [30, 677, 740, 293],
    ]);
    expect(geo(2, 2, 1, 1001, 0.02), [
      1001, 1001, [20, 20, 471, 471], [511, 20, 470, 471], [20, 511, 471, 470], [511, 511, 470, 470], //
    ]);
    expect(geo(5, 1, 1, 1000, 0), [
      1000, 1000, [0, 0, 200, 1000], [200, 0, 200, 1000], [400, 0, 200, 1000], [600, 0, 200, 1000],
      [800, 0, 200, 1000], //
    ]);
    expect(geo(1, 2, 9 / 16, 1600, 0.05), [
      900,
      1600,
      [80, 80, 740, 680],
      [80, 840, 740, 680],
    ]);
  });

  test('cover crop matches the native shared cases', () {
    List<int> c(int iw, int ih, int cw, int ch, [CropPosition p = kCropCenter]) {
      final r = CollageGeometry.cover(iw, ih, cw, ch, p);
      return [r.x, r.y, r.w, r.h];
    }

    expect(c(4000, 3000, 500, 1000), [1250, 0, 1500, 3000]);
    expect(c(3000, 4000, 1000, 500), [0, 1250, 3000, 1500]);
    expect(c(1000, 1000, 300, 300), [0, 0, 1000, 1000]);
    expect(c(1200, 800, 601, 400), [0, 0, 1200, 799]);
    // Crop position: 0 = left/top, 1 = right/bottom.
    expect(c(4000, 3000, 500, 1000, (x: 0, y: 0)), [0, 0, 1500, 3000]);
    expect(c(4000, 3000, 500, 1000, (x: 1, y: 1)), [2500, 0, 1500, 3000]);
    expect(c(4000, 3000, 500, 1000, (x: 0.3, y: 0.9)), [750, 0, 1500, 3000]);
    expect(c(3000, 4000, 1000, 500, (x: 0.1, y: 0.75)), [0, 1875, 3000, 1500]);
    expect(c(3000, 4000, 1000, 500, (x: 0.5, y: 2)), [0, 2500, 3000, 1500], reason: 'clamped');
  });

  test('layouts: labels, sizes, default per count', () {
    expect(CollageLayout.values.map((l) => l.label), [
      'Mendatar 2',
      'Mendatar 3',
      'Mendatar 4',
      'Mendatar 5',
      'Vertikal 2',
      'Vertikal 3',
      'Grid 2×2',
    ]);
    // Mendatar: stacked top to bottom; vertikal: side by side.
    expect(CollageLayout.values.map((l) => (l.cols, l.rows)), [(1, 2), (1, 3), (1, 4), (1, 5), (2, 1), (3, 1), (2, 2)]);
    expect([2, 3, 4, 5].map(CollageLayout.forCount), [
      CollageLayout.vertical2,
      CollageLayout.vertical3,
      CollageLayout.grid2x2,
      CollageLayout.horizontal5,
    ]);
    expect(kCollageRatios, isNot(contains(BorderRatio.original)));
  });

  test('options: label and channel map', () {
    expect(const CollageOptions().gapLabel, '2%');
    expect(const CollageOptions(gap: 0.005).gapLabel, '0,5%');
    expect(
      const CollageOptions(
        layout: CollageLayout.horizontal3,
        gap: 0.01,
        color: BorderColor.navy,
        ratio: BorderRatio.story,
      ).toMap(),
      {'cols': 1, 'rows': 3, 'gap': 0.01, 'color': 0x1F2A44, 'ratio': 9 / 16, 'crops': <double>[]},
    );
    expect(const CollageOptions().toMap([kCropCenter, (x: 0.2, y: 1.0)])['crops'], [0.5, 0.5, 0.2, 1.0]);
  });

  test('settings: round trip, bad values ignored', () async {
    SharedPreferences.setMockInitialValues({});
    var o = await CollageSettings.load();
    expect([o.gap, o.color, o.ratio], [CollageOptions.defaultGap, BorderColor.white, BorderRatio.square]);
    await CollageSettings.save(
      const CollageOptions(gap: 0.05, color: BorderColor.black, ratio: BorderRatio.portrait45),
    );
    o = await CollageSettings.load();
    expect([o.gap, o.color, o.ratio], [0.05, BorderColor.black, BorderRatio.portrait45]);

    SharedPreferences.setMockInitialValues({'collage.gap': 3.0, 'collage.ratio': 'original', 'collage.color': 'x'});
    o = await CollageSettings.load();
    expect([o.gap, o.color, o.ratio], [CollageOptions.defaultGap, BorderColor.white, BorderRatio.square]);
  });
}
