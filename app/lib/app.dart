import 'package:flutter/material.dart';

import 'ui/pages/library_page.dart';

/// 应用根 Widget。
class KeyDropApp extends StatelessWidget {
  const KeyDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeyDrop Piano',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LibraryPage(),
    );
  }
}
