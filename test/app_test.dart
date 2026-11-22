import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutles/border_editor_page.dart';
import 'package:tutles/home_page.dart';
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

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TutlesApp(source: gallery));
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Bingkai'));
    await tester.pumpAndSettle();
    expect(find.byType(PickerPage), findsOneWidget);
  }

  /// Select photos by index and open the editor.
  Future<void> openEditor(WidgetTester tester, List<int> photos) async {
    await openPicker(tester);
    for (final i in photos) {
      await tester.tap(find.byKey(ValueKey('photo-p$i')));
    }
    await tester.pump();
    await tester.tap(find.text('Lanjut (${photos.length} foto)'));
    await tester.pumpAndSettle();
    expect(find.byType(BorderEditorPage), findsOneWidget);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    // Choices at the far right are only built after swiping the strip, like on a phone.
    if (find.byKey(ValueKey(key)).evaluate().isEmpty) {
      await tester.dragUntilVisible(find.byKey(ValueKey(key)), find.byType(ListView), const Offset(-150, 0));
    }
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  /// ✓ in the editor, then Simpan in the save sheet.
  Future<String> save(WidgetTester tester) async {
    await tap(tester, 'border-save');
    final summary = tester.widget<Text>(find.byKey(const ValueKey('save-summary'))).data!;
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    return summary;
  }

  Size canvas(WidgetTester tester) => tester.getSize(find.byKey(const ValueKey('border-canvas')).first);

  group('home', () {
    testWidgets('shows the app and its features without touching the gallery', (tester) async {
      await pumpApp(tester);
      expect(find.text('tutles'), findsOneWidget);
      expect(find.byType(FeatureIcon), findsNWidgets(kFeatures.length));
      expect(find.text('Bingkai'), findsOneWidget);
      expect(gallery.loads, isEmpty);
    });
  });

  group('picker', () {
    testWidgets('permission denied: message and settings button', (tester) async {
      gallery.access = false;
      await openPicker(tester);
      expect(find.text('Izin galeri dibutuhkan untuk memilih foto.'), findsOneWidget);
      await tester.tap(find.text('Buka Pengaturan'));
      expect(gallery.settingsOpened, 1);
    });

    testWidgets('empty gallery', (tester) async {
      gallery.total = 0;
      await openPicker(tester);
      expect(find.text('Tidak ada foto di galeri.'), findsOneWidget);
    });

    testWidgets('selection keeps tap order and can be cleared', (tester) async {
      await openPicker(tester);
      expect(find.text('Pilih foto'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('photo-p2')));
      await tester.tap(find.byKey(const ValueKey('photo-p0')));
      await tester.pump();
      expect(find.text('2 dipilih'), findsOneWidget);
      expect(find.text('Lanjut (2 foto)'), findsOneWidget);
      final badge1 = find.descendant(of: find.byKey(const ValueKey('photo-p2')), matching: find.text('1'));
      expect(badge1, findsOneWidget, reason: 'first tapped is number 1');

      await tester.tap(find.byTooltip('Batalkan pilihan'));
      await tester.pump();
      expect(find.text('Pilih foto'), findsOneWidget);
    });

    testWidgets('large gallery loads in pages while scrolling', (tester) async {
      gallery.total = 500;
      await openPicker(tester);
      expect(gallery.loads.first, (0, 120));
      await tester.drag(find.byType(GridView), const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(gallery.loads.length, greaterThan(1));
      expect(gallery.loads[1], (120, 240));
    });
  });

  group('border editor', () {
    testWidgets('defaults: white 5% border, original size, same format', (tester) async {
      await openEditor(tester, [1, 0]);
      expect(find.text('Bingkai · 1 / 2'), findsOneWidget);
      expect(find.text('5%'), findsOneWidget);

      final summary = await save(tester);
      expect(summary, startsWith('Bingkai putih 5%. Disimpan sebagai foto baru'));
      expect(find.byType(ProcessPage), findsOneWidget);
      expect(find.text('Selesai'), findsOneWidget);
      expect(native.calls.map((c) => c.arguments), [
        for (final id in ['p1', 'p0'])
          {
            'id': id, 'quality': 90, 'maxSide': 0, 'format': 'same',
            'border': {'width': 0.05, 'color': 0xFFFFFF, 'ratio': 0.0},
          },
      ]);

      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(find.byType(PickerPage), findsOneWidget);
      expect(find.text('Pilih foto'), findsOneWidget, reason: 'selection cleared after saving');
    });

    testWidgets('full width preview above the tools; follows ratio and thickness', (tester) async {
      await openEditor(tester, [0]);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      var c = canvas(tester);
      expect(c.width, closeTo(screen.width - 16, 0.5), reason: 'full width minus 8 px margins');
      expect(c.width / c.height, closeTo(4400 / 3400, 0.01));
      expect(tester.getCenter(find.text('Ketebalan')).dy,
          greaterThan(tester.getBottomLeft(find.byKey(const ValueKey('border-canvas'))).dy));

      await tap(tester, 'border-tool-ratio');
      await tap(tester, 'border-ratio-square');
      c = canvas(tester);
      expect(c.width, closeTo(c.height, 0.5));
      await tap(tester, 'border-ratio-landscape169');
      c = canvas(tester);
      expect(c.width / c.height, closeTo(16 / 9, 0.01));

      await tap(tester, 'border-tool-width');
      tester.widget<Slider>(find.byKey(const ValueKey('border-fraction'))).onChanged!(0);
      await tester.pumpAndSettle();
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('portrait photo preview is portrait', (tester) async {
      gallery = FakeGallery(sizes: {'p0': (3000, 4000)});
      await openEditor(tester, [0]);
      final c = canvas(tester);
      expect(c.width / c.height, closeTo(3400 / 4400, 0.01));
    });

    testWidgets('choices and save options are sent, remembered and restored', (tester) async {
      await openEditor(tester, [0, 1]);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Bingkai · 2 / 2'), findsOneWidget);

      tester.widget<Slider>(find.byKey(const ValueKey('border-fraction'))).onChanged!(0.1);
      await tap(tester, 'border-tool-color');
      await tap(tester, 'border-color-navy');
      await tap(tester, 'border-tool-ratio');
      await tap(tester, 'border-ratio-portrait45');
      await tap(tester, 'border-save');
      await tester.tap(find.byKey(const ValueKey('save-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2048 px').last);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('save-summary'))).data,
          startsWith('Bingkai biru tua 10%, rasio 4:5.'));
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      expect(native.calls.first.arguments, {
        'id': 'p0', 'quality': 90, 'maxSide': 2048, 'format': 'same',
        'border': {'width': 0.1, 'color': 0x1F2A44, 'ratio': 0.8},
      });
      final p = await SharedPreferences.getInstance();
      expect([p.getDouble('border.fraction'), p.getString('border.color'), p.getString('border.ratio')],
          [0.1, 'navy', 'portrait45']);
      expect(p.getInt('save.maxSide'), 2048);

      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('photo-p2')));
      await tester.pump();
      await tester.tap(find.text('Lanjut (1 foto)'));
      await tester.pumpAndSettle();
      expect(find.text('10%'), findsOneWidget, reason: 'restored');
    });

    testWidgets('closing the editor or the save sheet saves nothing', (tester) async {
      await openEditor(tester, [0]);
      await tap(tester, 'border-save');
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.byType(BorderEditorPage), findsOneWidget);

      await tester.tap(find.byTooltip('Batal'));
      await tester.pumpAndSettle();
      expect(find.byType(BorderEditorPage), findsNothing);
      expect(find.text('Lanjut (1 foto)'), findsOneWidget, reason: 'selection kept');
      expect(native.calls, isEmpty);
    });
  });

  group('process', () {
    testWidgets('failures are listed by name, others still saved', (tester) async {
      native.results['p1'] = PlatformException(code: 'render_failed', message: 'Foto terlalu besar');
      await openEditor(tester, [0, 1, 2]);
      await save(tester);
      expect(native.calls, hasLength(3));
      final ok = find.ancestor(of: find.text('Berhasil'), matching: find.byType(Row));
      expect(find.descendant(of: ok, matching: find.text('2')), findsOneWidget);
      expect(find.text('IMG_1.JPG'), findsOneWidget);
      expect(find.text('Foto terlalu besar'), findsOneWidget);
    });

    testWidgets('Hentikan stops after the current photo; back is blocked while running', (tester) async {
      final gate = Gate();
      native.gate = gate.call;
      await openEditor(tester, [0, 1, 2]);
      await tap(tester, 'border-save');
      await tester.tap(find.text('Simpan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Menyimpan…'), findsOneWidget);

      await tester.tap(find.text('Hentikan'));
      await tester.pump();
      gate.release('p0');
      await tester.pumpAndSettle();
      expect(native.calls, hasLength(1));
      expect(find.text('Dihentikan: 1 dari 3 foto diproses'), findsOneWidget);
    });
  });
}
