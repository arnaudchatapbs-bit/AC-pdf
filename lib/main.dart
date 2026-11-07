import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  runApp(const AcPdfApp());
}

class AcPdfApp extends StatelessWidget {
  const AcPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Tons bleus et gris clair.
    const seed = Color(0xFF1E6FD9);
    final light = ColorScheme.fromSeed(seedColor: seed).copyWith(
      primary: const Color(0xFF1E6FD9),
      surface: const Color(0xFFF5F7FA),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF0F2F5),
      surfaceContainer: const Color(0xFFEBEEF2),
      surfaceContainerHigh: const Color(0xFFE5E8ED),
      surfaceContainerHighest: const Color(0xFFDFE3E8),
    );
    final dark = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return MaterialApp(
      title: 'ACpdf',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: light,
        useMaterial3: true,
        scaffoldBackgroundColor: light.surface,
        appBarTheme: AppBarTheme(backgroundColor: light.surfaceContainer, foregroundColor: const Color(0xFF1F2933)),
      ),
      darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
