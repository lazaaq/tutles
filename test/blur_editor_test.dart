import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutles/blur_editor_page.dart';
import 'package:tutles/main.dart';
import 'package:tutles/picker_page.dart';
import 'package:tutles/process_page.dart';

import 'fakes.dart';

void main() {
  late FakeGallery gallery;
  late FakeNative native;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gallery = FakeGallery();
    native = FakeNative()..install();
  });

  tearDown(() => native.uninstall());

  Future<void> openEditor(WidgetTester tester, List<int> photos) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TutlesApp(source: gallery));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blur'));
    await tester.pumpAndSettle();
    expect(find.byType(PickerPage), findsOneWidget);
    for (final i in photos) {
      await tester.tap(find.byKey(ValueKey('photo-p$i')));
    }
    await tester.pump();
    await tester.tap(find.text('Lanjut (${photos.length} foto)'));
    await tester.pumpAndSettle();
    expect(find.byType(BlurEditorPage), findsOneWidget);
  }

  Rect preview(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('blur-preview')));

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed != null;

  /// One-finger stroke from [from] (relative to the photo, 0..1) moving by [by] logical px.
  Future<void> stroke(WidgetTester tester, Offset from, Offset by, {int steps = 5}) async {
    final r = preview(tester);
    final g = await tester.startGesture(r.topLeft + Offset(from.dx * r.width, from.dy * r.height));
    for (var i = 0; i < steps; i++) {
      await g.moveBy(by / steps.toDouble());
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  Future<String> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('blur-save')));
    await tester.pumpAndSettle();
    final summary = tester.widget<Text>(find.byKey(const ValueKey('save-summary'))).data!;
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    return summary;
  }

  List<Map> sentStrokes(int call) =>
      (((native.calls[call].arguments as Map)['blur'] as Map)['strokes'] as List).cast<Map>();

  testWidgets('feature on the home screen', (tester) async {
    await openEditor(tester, [0]);
    expect(find.text('Blur'), findsOneWidget, reason: 'editor title');
    expect(find.text('Kuas'), findsOneWidget);
    expect(find.text('Penghapus'), findsOneWidget);
    expect(find.text('Kekuatan'), findsOneWidget);
  });

  testWidgets('brush stroke is sent in photo coordinates; ✓ needs a stroke', (tester) async {
    await openEditor(tester, [0]);
    expect(enabled(tester, 'blur-save'), isFalse);
    expect(enabled(tester, 'blur-undo'), isFalse);
    final r = preview(tester);
    expect(r.width / r.height, closeTo(4 / 3, 0.01));

    await stroke(tester, const Offset(0.25, 0.5), Offset(r.width / 2, 0));
    expect(enabled(tester, 'blur-save'), isTrue);

    final summary = await save(tester);
    expect(summary, startsWith('Blur area diusap 4, area lain tajam, tepi 3. Disimpan sebagai foto baru'));
    expect(find.byType(ProcessPage), findsOneWidget);
    expect(native.calls, hasLength(1));
    final args = native.calls.first.arguments as Map;
    expect([args['id'], args['quality'], args['maxSide'], args['format']], ['p0', 90, 0, 'same']);
    final blur = args['blur'] as Map;
    expect([blur['strength'], blur['background'], blur['feather']], [0.02, 0, 0.012]);
    final strokes = sentStrokes(0);
    expect(strokes, hasLength(1));
    final s = strokes.single;
    expect(s['erase'], false);
    expect(s['radius'] as double, closeTo(20 / r.width, 1e-6), reason: '20 px brush on the long side');
    final pts = (s['points'] as List).cast<double>();
    expect(pts.length, greaterThanOrEqualTo(6));
    expect(pts[0], closeTo(0.25, 0.01));
    expect(pts[1], closeTo(0.5, 0.01));
    expect(pts[pts.length - 2], closeTo(0.75, 0.01));
    expect(pts.last, closeTo(0.5, 0.01));

    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih foto'), findsOneWidget, reason: 'selection cleared after saving');
  });

  testWidgets('tap makes a dot; undo and redo', (tester) async {
    await openEditor(tester, [0]);
    final r = preview(tester);
    await tester.tapAt(r.center);
    await tester.pumpAndSettle();
    expect(enabled(tester, 'blur-save'), isTrue);

    await tester.tap(find.byKey(const ValueKey('blur-undo')));
    await tester.pump();
    expect(enabled(tester, 'blur-save'), isFalse);
    expect(enabled(tester, 'blur-redo'), isTrue);
    await tester.tap(find.byKey(const ValueKey('blur-redo')));
    await tester.pump();
    expect(enabled(tester, 'blur-save'), isTrue);

    await save(tester);
    final pts = sentStrokes(0).single['points'] as List;
    expect(pts, hasLength(2));
    expect(pts[0], closeTo(0.5, 0.01));
    expect(pts[1], closeTo(0.5, 0.01));
  });

  testWidgets('eraser strokes are sent with erase; eraser alone cannot be saved', (tester) async {
    await openEditor(tester, [0]);
    await tester.tap(find.byKey(const ValueKey('blur-tool-eraser')));
    await tester.pump();
    await stroke(tester, const Offset(0.2, 0.2), const Offset(60, 0));
    expect(enabled(tester, 'blur-save'), isFalse);
    expect(enabled(tester, 'blur-undo'), isTrue);

    await tester.tap(find.byKey(const ValueKey('blur-tool-brush')));
    await tester.pump();
    await stroke(tester, const Offset(0.2, 0.6), const Offset(60, 0));
    await save(tester);
    expect(sentStrokes(0).map((s) => s['erase']), [true, false], reason: 'drawing order kept');
  });

  testWidgets('two fingers zoom instead of drawing; brush stays the same size on screen', (tester) async {
    await openEditor(tester, [0]);
    final r = preview(tester);
    final a = await tester.startGesture(r.center - const Offset(30, 0), pointer: 1);
    await tester.pump();
    final b = await tester.startGesture(r.center + const Offset(30, 0), pointer: 2);
    for (var i = 0; i < 5; i++) {
      await a.moveBy(const Offset(-12, 0));
      await b.moveBy(const Offset(12, 0));
      await tester.pump();
    }
    await a.up();
    await b.moveBy(const Offset(10, 0)); // remaining finger pans, does not draw
    await tester.pump();
    await b.up();
    await tester.pumpAndSettle();

    expect(enabled(tester, 'blur-undo'), isFalse, reason: 'no stroke');
    expect(find.byKey(const ValueKey('blur-zoom-reset')), findsOneWidget);
    final zoomed = preview(tester);
    expect(zoomed.width, greaterThan(r.width * 1.5));

    // Stroke while zoomed: radius relative to the zoomed photo.
    final g = await tester.startGesture(r.center);
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(20, 0));
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('blur-zoom-reset')));
    await tester.pumpAndSettle();
    expect(preview(tester).width, closeTo(r.width, 0.5));
    await save(tester);
    expect(sentStrokes(0).single['radius'] as double, closeTo(20 / zoomed.width, 1e-6));
  });

  testWidgets('each photo has its own strokes; only edited photos are saved', (tester) async {
    await openEditor(tester, [0, 1, 2]);
    expect(find.text('1 / 3'), findsOneWidget);
    await stroke(tester, const Offset(0.5, 0.5), const Offset(40, 0));
    await tester.tap(find.byKey(const ValueKey('blur-next')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(enabled(tester, 'blur-undo'), isFalse, reason: 'new photo, no strokes');
    await tester.tap(find.byKey(const ValueKey('blur-next')));
    await tester.pumpAndSettle();
    await tester.tapAt(preview(tester).center);
    await tester.tapAt(preview(tester).topLeft + const Offset(20, 20));
    await tester.pumpAndSettle();

    final summary = await save(tester);
    expect(summary, startsWith('Blur area diusap 4, area lain tajam, tepi 3, pada 2 dari 3 foto.'));
    expect(native.calls.map((c) => (c.arguments as Map)['id']), ['p0', 'p2']);
    expect(sentStrokes(0), hasLength(1));
    expect(sentStrokes(1), hasLength(2));
  });

  testWidgets('strength and brush size are sent, remembered and restored', (tester) async {
    await openEditor(tester, [0]);
    await tester.tap(find.byKey(const ValueKey('blur-tool-strength')));
    await tester.pump();
    tester.widget<Slider>(find.byKey(const ValueKey('blur-strength'))).onChanged!(7);
    tester.widget<Slider>(find.byKey(const ValueKey('blur-strength'))).onChangeEnd!(7);
    await tester.pump();
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Tajam'), findsOneWidget, reason: 'area lain 0');
    await tester.tap(find.byKey(const ValueKey('blur-tool-brush')));
    await tester.pump();
    final brush = tester.widget<Slider>(find.byKey(const ValueKey('blur-brush')));
    brush.onChangeStart!(40);
    brush.onChanged!(40);
    await tester.pump();
    expect(find.byKey(const ValueKey('blur-cursor')), findsOneWidget, reason: 'size preview');
    tester.widget<Slider>(find.byKey(const ValueKey('blur-brush'))).onChangeEnd!(40);
    await tester.pump();
    expect(find.byKey(const ValueKey('blur-cursor')), findsNothing);

    final r = preview(tester);
    await tester.tapAt(r.center);
    await tester.pumpAndSettle();
    expect(await save(tester), startsWith('Blur area diusap 7, area lain tajam, tepi 3.'));
    final blur = (native.calls.first.arguments as Map)['blur'] as Map;
    expect(blur['strength'], closeTo(0.035, 1e-12));
    expect(sentStrokes(0).single['radius'] as double, closeTo(40 / r.width, 1e-6));

    final p = await SharedPreferences.getInstance();
    expect([p.getInt('blur.level'), p.getDouble('blur.brush')], [7, 40.0]);

    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('photo-p1')));
    await tester.pump();
    await tester.tap(find.text('Lanjut (1 foto)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('blur-tool-strength')));
    await tester.pump();
    expect(find.text('7'), findsOneWidget, reason: 'restored');
    expect(tester.widget<Slider>(find.byKey(const ValueKey('blur-strength'))).value, 7);
  });

  testWidgets('closing with strokes asks first; nothing is saved', (tester) async {
    await openEditor(tester, [0]);
    await tester.tapAt(preview(tester).center);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Buang perubahan?'), findsOneWidget);
    await tester.tap(find.text('Lanjut edit'));
    await tester.pumpAndSettle();
    expect(find.byType(BlurEditorPage), findsOneWidget);
    expect(enabled(tester, 'blur-save'), isTrue, reason: 'strokes kept');

    await tester.tap(find.byTooltip('Batal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buang'));
    await tester.pumpAndSettle();
    expect(find.byType(BlurEditorPage), findsNothing);
    expect(find.text('Lanjut (1 foto)'), findsOneWidget, reason: 'selection kept');
    expect(native.calls, isEmpty);
  });

  testWidgets('closing without strokes does not ask', (tester) async {
    await openEditor(tester, [0]);
    await tester.tap(find.byTooltip('Batal'));
    await tester.pumpAndSettle();
    expect(find.byType(BlurEditorPage), findsNothing);
  });

  testWidgets('area lain and tepi are sent and remembered', (tester) async {
    await openEditor(tester, [0]);
    await tester.tap(find.byKey(const ValueKey('blur-tool-strength')));
    await tester.pump();
    final bg = tester.widget<Slider>(find.byKey(const ValueKey('blur-background')));
    bg.onChanged!(2);
    bg.onChangeEnd!(2);
    await tester.tap(find.byKey(const ValueKey('blur-tool-edge')));
    await tester.pump();
    final edge = tester.widget<Slider>(find.byKey(const ValueKey('blur-feather')));
    expect(edge.value, 3);
    edge.onChanged!(8);
    edge.onChangeEnd!(8);
    await tester.pump();
    expect(find.text('8'), findsOneWidget);
    await tester.tapAt(preview(tester).center);
    await tester.pumpAndSettle();

    expect(await save(tester), startsWith('Blur area diusap 4, area lain 2, tepi 8.'));
    final blur = (native.calls.first.arguments as Map)['blur'] as Map;
    expect(blur['strength'], 0.02);
    expect(blur['background'], 0.01);
    expect(blur['feather'], closeTo(0.032, 1e-12));
    final p = await SharedPreferences.getInstance();
    expect([p.getInt('blur.background'), p.getInt('blur.feather')], [2, 8]);
  });

  testWidgets('area lain blurred: every photo is saved, strokes optional', (tester) async {
    await openEditor(tester, [0, 1]);
    await tester.tap(find.byKey(const ValueKey('blur-tool-strength')));
    await tester.pump();
    tester.widget<Slider>(find.byKey(const ValueKey('blur-background'))).onChanged!(5);
    await tester.pump();
    expect(enabled(tester, 'blur-save'), isTrue, reason: 'no strokes needed');
    expect(enabled(tester, 'blur-undo'), isFalse);

    // Sharp subject: painted area 0.
    tester.widget<Slider>(find.byKey(const ValueKey('blur-strength'))).onChanged!(0);
    await tester.pump();
    await tester.tapAt(preview(tester).center);
    await tester.pumpAndSettle();

    expect(await save(tester), startsWith('Blur area diusap 0, area lain 5, tepi 3.'));
    expect(native.calls.map((c) => (c.arguments as Map)['id']), ['p0', 'p1']);
    final a = (native.calls[0].arguments as Map)['blur'] as Map;
    expect([a['strength'], a['background']], [0, 0.025]);
    expect(sentStrokes(0), hasLength(1));
    expect(sentStrokes(1), isEmpty);
  });

  testWidgets('both strengths 0: nothing to save', (tester) async {
    await openEditor(tester, [0]);
    await tester.tapAt(preview(tester).center);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('blur-tool-strength')));
    await tester.pump();
    tester.widget<Slider>(find.byKey(const ValueKey('blur-strength'))).onChanged!(0);
    await tester.pump();
    expect(find.text('Tajam'), findsNWidgets(2));
    expect(enabled(tester, 'blur-save'), isFalse);
  });
}
