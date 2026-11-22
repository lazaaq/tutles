import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutles/collage_editor_page.dart';
import 'package:tutles/main.dart';
import 'package:tutles/picker_page.dart';
import 'package:tutles/process_page.dart';

import 'fakes.dart';

void main() {
  late FakeGallery gallery;
  late FakeNative native;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gallery = FakeGallery(total: 6);
    native = FakeNative()..install();
  });

  tearDown(() => native.uninstall());

  Future<void> openPicker(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TutlesApp(source: gallery));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kolase'));
    await tester.pumpAndSettle();
    expect(find.byType(PickerPage), findsOneWidget);
  }

  Future<void> next(WidgetTester tester, List<int> photos) async {
    for (final i in photos) {
      await tester.tap(find.byKey(ValueKey('photo-p$i')));
    }
    await tester.pump();
    await tester.tap(find.text('Lanjut (${photos.length} foto)'));
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester, List<int> photos) async {
    await openPicker(tester);
    await next(tester, photos);
    expect(find.byType(CollageEditorPage), findsOneWidget);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    if (find.byKey(ValueKey(key)).evaluate().isEmpty) {
      // Back to the start of the strip, then swipe until the choice is built.
      await tester.drag(find.byType(ListView), const Offset(3000, 0));
      await tester.pumpAndSettle();
      if (find.byKey(ValueKey(key)).evaluate().isEmpty) {
        await tester.dragUntilVisible(find.byKey(ValueKey(key)), find.byType(ListView), const Offset(-150, 0));
      }
    }
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Size canvas(WidgetTester tester) => tester.getSize(find.byKey(const ValueKey('collage-canvas')));

  Future<String> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('collage-save')));
    await tester.pumpAndSettle();
    final summary = tester.widget<Text>(find.byKey(const ValueKey('save-summary'))).data!;
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    return summary;
  }

  testWidgets('needs 2 to 5 photos', (tester) async {
    await openPicker(tester);
    await next(tester, [0]);
    expect(find.text('Pilih minimal 2 foto untuk kolase.'), findsOneWidget);
    expect(find.byType(CollageEditorPage), findsNothing);

    await tester.tap(find.byTooltip('Batalkan pilihan'));
    await tester.pump();
    await next(tester, [0, 1, 2, 3, 4, 5]);
    expect(find.text('Kolase paling banyak 5 foto.'), findsOneWidget);
    expect(find.byType(CollageEditorPage), findsNothing);
  });

  testWidgets('2 photos: Vertikal 2 (side by side), square, white 2%; one collage saved', (tester) async {
    await openEditor(tester, [1, 0]);
    final c = canvas(tester);
    expect(c.width, closeTo(c.height, 0.5));
    final a = tester.getRect(find.byKey(const ValueKey('collage-cell-0')));
    final b = tester.getRect(find.byKey(const ValueKey('collage-cell-1')));
    expect(a.top, closeTo(b.top, 0.5));
    expect(a.left, lessThan(b.left));
    expect(find.byKey(const ValueKey('img-p1')), findsOneWidget, reason: 'first picked is first cell');

    final summary = await save(tester);
    expect(summary, startsWith('Vertikal 2, rasio 1:1, jarak 2% putih. Disimpan sebagai foto baru'));
    expect(find.byType(ProcessPage), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
    expect(native.calls, hasLength(1));
    expect(native.calls.single.method, 'collage');
    expect(native.calls.single.arguments, {
      'ids': ['p1', 'p0'],
      'quality': 90,
      'maxSide': 0,
      'cols': 2,
      'rows': 1,
      'gap': 0.02,
      'color': 0xFFFFFF,
      'ratio': 1.0,
      'crops': [0.5, 0.5, 0.5, 0.5],
    });

    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih foto'), findsOneWidget, reason: 'selection cleared after saving');
  });

  testWidgets('layouts need enough photos; choices are sent and remembered', (tester) async {
    await openEditor(tester, [0, 1, 2]);
    // 3 photos: Vertikal 3 by default; Mendatar 4/5 and Grid 2×2 are disabled.
    expect(
      tester.widget<Opacity>(find.ancestor(of: find.text('Mendatar 4'), matching: find.byType(Opacity)).first).opacity,
      lessThan(1),
    );
    await tap(tester, 'collage-layout-grid2x2');
    expect(find.byKey(const ValueKey('collage-cell-3')), findsNothing, reason: 'still Vertikal 3');

    await tap(tester, 'collage-layout-horizontal2');
    final a = tester.getRect(find.byKey(const ValueKey('collage-cell-0')));
    final b = tester.getRect(find.byKey(const ValueKey('collage-cell-1')));
    expect(a.left, closeTo(b.left, 0.5));
    expect(a.top, lessThan(b.top));

    await tap(tester, 'collage-tool-ratio');
    await tap(tester, 'collage-ratio-story');
    final c = canvas(tester);
    expect(c.width / c.height, closeTo(9 / 16, 0.01));
    await tap(tester, 'collage-tool-color');
    await tap(tester, 'collage-color-navy');
    await tap(tester, 'collage-tool-gap');
    tester.widget<Slider>(find.byKey(const ValueKey('collage-gap'))).onChanged!(0.05);
    await tester.pumpAndSettle();
    expect(find.text('5%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collage-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-size')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2048 px').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('save-summary'))).data,
      startsWith('Mendatar 2, rasio 9:16, jarak 5% biru tua; 1 foto terakhir tidak dipakai.'),
    );
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(native.calls.single.arguments, {
      'ids': ['p0', 'p1'],
      'quality': 90,
      'maxSide': 2048,
      'cols': 1,
      'rows': 2,
      'gap': 0.05,
      'color': 0x1F2A44,
      'ratio': 9 / 16,
      'crops': [0.5, 0.5, 0.5, 0.5],
    });
    final p = await SharedPreferences.getInstance();
    expect(
      [p.getDouble('collage.gap'), p.getString('collage.color'), p.getString('collage.ratio')],
      [0.05, 'navy', 'story'],
    );
  });

  testWidgets('4 photos: grid 2×2 by default', (tester) async {
    await openEditor(tester, [0, 1, 2, 3]);
    final r = [for (var i = 0; i < 4; i++) tester.getRect(find.byKey(ValueKey('collage-cell-$i')))];
    expect(r[0].top, closeTo(r[1].top, 0.5));
    expect(r[2].top, greaterThan(r[0].bottom));
    expect(r[2].left, closeTo(r[0].left, 0.5));
  });

  testWidgets('dragging a photo moves its crop; kept per photo', (tester) async {
    // p0 landscape 4000x3000 in a tall Vertikal 2 cell: spare width, no spare height.
    await openEditor(tester, [0, 1]);
    final cell = tester.getRect(find.byKey(const ValueKey('collage-cell-0')));
    final spare = 4000 * (cell.height / 3000) - cell.width;
    await tester.dragFrom(cell.center, Offset(spare / 4, 40));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('collage-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    final crops = ((native.calls.single.arguments as Map)['crops'] as List).cast<double>();
    expect(crops[0], lessThan(0.5), reason: 'dragged right: shows more of the left');
    expect(crops[0], greaterThan(0.15));
    expect(crops[1], 0.5, reason: 'no spare height');
    expect(crops.sublist(2), [0.5, 0.5], reason: 'other photo untouched');
  });
}
