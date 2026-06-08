import 'dart:io';

/// Writes `lib/core/theme/app_theme.dart`.
///
/// When [seedColorHex] / [displayFont] / [bodyFont] come from the AI planner
/// the generated theme uses them; otherwise sensible defaults are emitted so
/// non-AI `sm init` still produces a working theme.
void createThemeFile(
  String projectName, {
  String themeMode = 'system',
  String seedColorHex = '#2196F3',
  String? displayFont,
  String? bodyFont,
}) {
  final seedInt = _parseHexColor(seedColorHex);
  final useGoogleFonts = displayFont != null || bodyFont != null;

  final imports = StringBuffer("import 'package:flutter/material.dart';\n");
  if (useGoogleFonts) {
    imports.writeln("import 'package:google_fonts/google_fonts.dart';");
  }

  final textThemeBuilder = useGoogleFonts
      ? '''
  static TextTheme _textTheme(TextTheme base) {
    final display = GoogleFonts.${_fontMethod(displayFont ?? bodyFont!)}TextTheme(base);
    final body = GoogleFonts.${_fontMethod(bodyFont ?? displayFont!)}TextTheme(base);
    return display.copyWith(
      bodySmall:   body.bodySmall,
      bodyMedium:  body.bodyMedium,
      bodyLarge:   body.bodyLarge,
      labelSmall:  body.labelSmall,
      labelMedium: body.labelMedium,
      labelLarge:  body.labelLarge,
    );
  }
'''
      : '';

  final textThemeCall = useGoogleFonts
      ? '    textTheme: _textTheme(ThemeData(brightness: Brightness.light).textTheme),'
      : '';
  final darkTextThemeCall = useGoogleFonts
      ? '    textTheme: _textTheme(ThemeData(brightness: Brightness.dark).textTheme),'
      : '';

  final file = File('$projectName/lib/core/theme/app_theme.dart');
  file.writeAsStringSync('''
${imports.toString()}
class AppTheme {
  static const ThemeMode mode = ThemeMode.${_themeMode(themeMode)};
  static const Color seedColor = Color($seedInt);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: seedColor,
$textThemeCall
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: seedColor,
$darkTextThemeCall
  );
$textThemeBuilder}
''');

  print('🎨 Theme generated');
}

String _themeMode(String mode) {
  switch (mode.toLowerCase()) {
    case 'light':
      return 'light';
    case 'dark':
      return 'dark';
    default:
      return 'system';
  }
}

int _parseHexColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  return int.tryParse(h, radix: 16) ?? 0xFF2196F3;
}

/// Maps a Google Fonts family name to its `GoogleFonts.<name>TextTheme` method.
/// Strips non-alphanumerics so families like "Plus Jakarta Sans" → `plusJakartaSans`.
String _fontMethod(String family) {
  final parts = family
      .split(RegExp(r'[^a-zA-Z0-9]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'inter';
  return parts.first[0].toLowerCase() +
      parts.first.substring(1) +
      parts
          .skip(1)
          .map((p) => p[0].toUpperCase() + p.substring(1))
          .join();
}
