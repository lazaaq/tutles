import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutles/gallery.dart';

const nativeChannel = MethodChannel('tutles/native');

/// Gallery with [total] photos named p0, p1, … (4000x3000 unless [sizes] says otherwise).
class FakeGallery implements GallerySource {
  FakeGallery({this.total = 3, this.access = true, Map<String, (int, int)>? sizes}) : sizes = sizes ?? {};

  int total;
  bool access;
  final Map<String, (int, int)> sizes;
  final List<(int, int)> loads = [];
  int settingsOpened = 0;

  Photo photo(int i) {
    final id = 'p$i';
    final (w, h) = sizes[id] ?? (4000, 3000);
    return Photo(id: id, width: w, height: h, title: 'IMG_$i.JPG');
  }

  @override
  Future<bool> requestAccess() async => access;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<int> count() async => total;

  @override
  Future<List<Photo>> load(int start, int end) async {
    loads.add((start, end));
    return [for (var i = start; i < end && i < total; i++) photo(i)];
  }

  @override
  Widget image(Photo photo, {required int size, BoxFit fit = BoxFit.cover, Alignment alignment = Alignment.center}) =>
      ColoredBox(key: ValueKey('img-${photo.id}'), color: Colors.grey);
}

/// Records `render` calls; per-id results or [PlatformException]s.
class FakeNative {
  final List<MethodCall> calls = [];
  final Map<String, Object> results = {};

  /// Optional gate: render(id) waits for this before answering.
  Future<void> Function(String id)? gate;

  void install() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(nativeChannel, _handle);

  void uninstall() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(nativeChannel, null);

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    final id = (call.arguments as Map)['id'] as String;
    if (gate != null) await gate!(id);
    final r = results[id];
    if (r is PlatformException) throw r;
    return r ?? {'newId': 'new-$id', 'inBytes': 3000000, 'outBytes': 3500000};
  }
}

class Gate {
  final Map<String, Completer<void>> _pending = {};

  Future<void> call(String id) => (_pending[id] ??= Completer<void>()).future;

  void release(String id) => (_pending[id] ??= Completer<void>()).complete();
}
