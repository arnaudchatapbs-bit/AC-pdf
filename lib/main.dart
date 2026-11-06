import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  runApp(const PdfFacileApp());
}

class PdfFacileApp extends StatelessWidget {
  const PdfFacileApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFD84315);
    return MaterialApp(
      title: 'PDF Facile',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
