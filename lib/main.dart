import 'package:flutter/material.dart';

import 'gallery.dart';
import 'home_page.dart';

void main() => runApp(const TutlesApp());

class TutlesApp extends StatelessWidget {
  const TutlesApp({super.key, this.source});

  /// Untuk test: galeri palsu. null = galeri perangkat.
  final GallerySource? source;

  @override
  Widget build(BuildContext context) {
    const seed = Colors.green;
    return MaterialApp(
      title: 'tutles',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: HomePage(source: source),
    );
  }
}
