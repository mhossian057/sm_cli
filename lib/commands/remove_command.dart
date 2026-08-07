import 'dart:io';

Future<void> removeFeature({
  required String projectName,
  required String featureName,
  bool force = false,
}) async {
  final featureDir = Directory('$projectName/lib/features/$featureName');

  if (!featureDir.existsSync()) {
    print('❌ Feature "$featureName" not found in "$projectName"');
    return;
  }

  // Force flag nahi hai to confirm karo
  if (!force) {
    stdout.write('⚠️  Delete feature "$featureName"? (y/n): ');
    final confirm = stdin.readLineSync();
    if (confirm?.toLowerCase() != 'y') {
      print('❌ Cancelled');
      return;
    }
  }

  featureDir.deleteSync(recursive: true);
  print('🗑️  Feature folder deleted');

  _removeRouteConstant(projectName, featureName);
  _removeRoute(projectName, featureName);

  print('✅ Feature "$featureName" removed successfully!');
}

void _removeRouteConstant(String projectName, String featureName) {
  final file = File('$projectName/lib/core/routes/app_routes.dart');
  if (!file.existsSync()) return;

  final content = file.readAsStringSync();
  final updated = content.replaceAll(
    "  static const $featureName = '/$featureName';\n",
    '',
  );
  file.writeAsStringSync(updated);
  print('🧭 Route constant removed');
}

void _removeRoute(String projectName, String featureName) {
  final file = File('$projectName/lib/core/routes/app_router.dart');
  if (!file.existsSync()) return;

  final content = file.readAsStringSync();

  // Import remove karo
  final updatedImport = content.replaceAll(
    "import '../../features/$featureName/presentation/screens/${featureName}_screen.dart';\n",
    '',
  );

  // Route block remove karo
  final routeBlock = '''
    GoRoute(
      path: AppRoutes.$featureName,
      builder: (context, state) => const ${_capitalize(featureName)}Screen(),
    ),
''';

  final updated = updatedImport.replaceAll(routeBlock, '');
  file.writeAsStringSync(updated);
  print('🛣️ Route removed');
}

String _capitalize(String text) {
  return text
      .split('_')
      .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
      .join();
}