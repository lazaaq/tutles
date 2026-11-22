import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutles/blur.dart';
import 'package:tutles/settings.dart';

void main() {
  /// Same cases as BlurSpecTest.java and ios/EncoderTests/main.swift.
  test('sigmas match the native shared cases', () {
    const a = BlurOptions(strength: 0.02, background: 0.01, feather: 0.012);
    expect(a.sigma(4000, 3000), closeTo(80, 1e-9));
    expect(a.backgroundSigma(4000, 3000), closeTo(40, 1e-9));
    expect(a.featherSigma(4000, 3000), closeTo(48, 1e-9));
    const b = BlurOptions(strength: 0.005, background: 0, feather: 0.004);
    expect(b.sigma(800, 1200), closeTo(6, 1e-9));
    expect(b.backgroundSigma(800, 1200), 0);
    expect(b.featherSigma(800, 1200), closeTo(4.8, 1e-9));
    expect(const BlurOptions(strength: 0.05).sigma(1000, 1000), closeTo(50, 1e-9));
  });

  test('levels: strength 0..10 = 0..5%, edge 0..10 = 0,1%..4%', () {
    expect(BlurOptions.levelOf(BlurOptions.defaultStrength), 4);
    expect(BlurOptions.strengthOf(0), 0);
    expect(BlurOptions.strengthOf(1), 0.005);
    expect(BlurOptions.strengthOf(10), closeTo(0.05, 1e-12));
    expect(BlurOptions.strengthOf(12), closeTo(0.05, 1e-12), reason: 'clamped');
    expect(BlurOptions.levelOf(BlurOptions.strengthOf(7)), 7);

    expect(BlurOptions.featherLevelOf(BlurOptions.defaultFeather), 3);
    expect(BlurOptions.featherOf(0), BlurOptions.minFeather);
    expect(BlurOptions.featherOf(10), closeTo(0.04, 1e-12));
    for (var l = 0; l <= 10; l++) {
      expect(BlurOptions.featherLevelOf(BlurOptions.featherOf(l)), l);
    }
  });

  test('channel map: points flattened x,y; eraser flag kept', () {
    const o = BlurOptions(
      strength: 0.01,
      background: 0.005,
      feather: 0.008,
      strokes: [
        BlurStroke(radius: 0.05, points: [Offset(0.1, 0.2), Offset(0.3, 0.4)]),
        BlurStroke(radius: 0.02, points: [Offset(0.5, 0.5)], erase: true),
      ],
    );
    expect(o.toMap(), {
      'strength': 0.01,
      'background': 0.005,
      'feather': 0.008,
      'strokes': [
        {
          'radius': 0.05,
          'erase': false,
          'points': [0.1, 0.2, 0.3, 0.4],
        },
        {
          'radius': 0.02,
          'erase': true,
          'points': [0.5, 0.5],
        },
      ],
    });
    expect(o.hasPaint, isTrue);
    expect(BlurOptions(strokes: [o.strokes.last]).hasPaint, isFalse, reason: 'eraser only');
  });

  test('changesPhoto: painted area blurred, or the rest blurred', () {
    const paint = [
      BlurStroke(radius: 0.1, points: [Offset(0.5, 0.5)]),
    ];
    const erase = [
      BlurStroke(radius: 0.1, points: [Offset(0.5, 0.5)], erase: true),
    ];
    expect(const BlurOptions(strokes: paint).changesPhoto, isTrue);
    expect(const BlurOptions().changesPhoto, isFalse, reason: 'no strokes');
    expect(const BlurOptions(strokes: erase).changesPhoto, isFalse);
    expect(const BlurOptions(strength: 0, strokes: paint).changesPhoto, isFalse, reason: 'sharp everywhere');
    expect(
      const BlurOptions(strength: 0, background: 0.01, strokes: paint).changesPhoto,
      isTrue,
      reason: 'sharp subject, blurred background',
    );
    expect(const BlurOptions(background: 0.01).changesPhoto, isTrue, reason: 'whole photo');
  });

  test('settings: defaults, round trip, out of range ignored', () async {
    SharedPreferences.setMockInitialValues({});
    var s = await BlurSettings.load();
    expect(
      [s.strength, s.background, s.feather, s.brush],
      [BlurOptions.defaultStrength, 0, BlurOptions.defaultFeather, BlurSettings.defaultBrush],
    );

    await BlurSettings(
      strength: BlurOptions.strengthOf(0),
      background: BlurOptions.strengthOf(6),
      feather: BlurOptions.featherOf(8),
      brush: 30,
    ).save();
    s = await BlurSettings.load();
    expect(BlurOptions.levelOf(s.strength), 0);
    expect(BlurOptions.levelOf(s.background), 6);
    expect(BlurOptions.featherLevelOf(s.feather), 8);
    expect(s.brush, 30);

    SharedPreferences.setMockInitialValues({
      'blur.level': 99,
      'blur.background': -1,
      'blur.feather': 11,
      'blur.brush': 500.0,
    });
    s = await BlurSettings.load();
    expect(
      [s.strength, s.background, s.feather, s.brush],
      [BlurOptions.defaultStrength, 0, BlurOptions.defaultFeather, BlurSettings.defaultBrush],
    );
  });
}
