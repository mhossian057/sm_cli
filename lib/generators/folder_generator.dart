import 'dart:io';

void createFolders(String projectName) {
  final folders = [
    'lib/core/constants',
    'lib/core/network',
    'lib/core/routes',
    'lib/core/theme',
    'lib/core/utils',
    'lib/features',
    'lib/shared',
    'design',
  ];

  for (final folder in folders) {
    Directory('$projectName/$folder').createSync(recursive: true);
  }

  File('$projectName/design/README.md').writeAsStringSync('''
# Design references

Drop Figma exports, screenshots, mockups, or any visual reference here.
The `sm ai` command reads files in this folder (when invoked with
`--design design/`) and copies any `--design` / `--figma` inputs back
into this directory so the project carries its own design provenance.
''');

  print('📁 Clean Architecture folders created');
}