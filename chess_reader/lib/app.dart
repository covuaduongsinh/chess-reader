import 'package:flutter/material.dart';

import 'features/reader/presentation/reader_screen.dart';

class ChessReaderApp extends StatelessWidget {
  const ChessReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.brown,
          brightness: Brightness.dark,
        ),
      ),
      home: const ReaderScreen(),
    );
  }
}
