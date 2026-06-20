import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/settings/app_settings.dart';
import 'features/library/about.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerStockfishLicense();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const ChessReaderApp(),
    ),
  );
}
