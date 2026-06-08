import 'dart:io';

import '../generators/folder_generator.dart';
import '../generators/main_generator.dart';
import '../services/flutter_service.dart';
import '../services/config_service.dart';
import '../generators/router_generator.dart';
import '../generators/theme_generator.dart';
import '../generators/routes_constant_generator.dart';

Future<void> initProject({
  required String projectName,
  required bool riverpod,
  required bool bloc,
  required bool getx,
  bool useGoRouter = true,
  bool useTheme = true,
  String themeMode = 'system',
  String seedColorHex = '#2196F3',
  String? displayFont,
  String? bodyFont,
}) async {
  await createFlutterProject(projectName);

  createFolders(projectName);

  createMainFile(
    projectName: projectName,
    riverpod: riverpod,
    bloc: bloc,
    getx: getx,
  );

  if (useGoRouter) {
    createRouterFile(projectName);
    createRoutesFile(projectName);
  }

  if (useTheme) {
    createThemeFile(
      projectName,
      themeMode: themeMode,
      seedColorHex: seedColorHex,
      displayFont: displayFont,
      bodyFont: bodyFont,
    );
  }

  // Config save karo
  final stateManagement = riverpod
      ? 'Riverpod'
      : bloc
      ? 'Bloc'
      : getx
      ? 'GetX'
      : 'Provider';

  ConfigService.saveConfig(
    projectName: projectName,
    stateManagement: stateManagement,
  );

  // Dependencies
  final packages = <String>[];
  if (useGoRouter) packages.add('go_router');

  if (riverpod) {
    print('📦 Adding Riverpod + Dio...');
    packages.addAll(['flutter_riverpod', 'dio']);
    await _addPackages(projectName, packages);
    print('🔥 Riverpod architecture ready');
  } else if (bloc) {
    print('📦 Adding Bloc + Dio...');
    packages.addAll(['flutter_bloc', 'equatable', 'dio']);
    await _addPackages(projectName, packages);
    print('🔥 Bloc architecture ready');
  } else if (getx) {
    print('📦 Adding GetX + Dio...');
    packages.addAll(['get', 'dio']);
    await _addPackages(projectName, packages);
    print('🔥 GetX architecture ready');
  } else {
    print('📦 Adding Provider + Dio...');
    packages.addAll(['provider', 'dio']);
    await _addPackages(projectName, packages);
    print('🔥 Provider architecture ready');
  }

  // ← Yahan hona chahiye — _addPackages ke bahar
  print('\n✅ Project "$projectName" created successfully!');
  print('');
  print('📋 Next steps:');
  print('   sm make feature $projectName auth');
  print('   sm make feature $projectName home');
  print('   sm make api $projectName');
  print('   cd $projectName && flutter run');
  print('');
  print('📖 Docs: https://pub.dev/packages/sm_cli');
}



Future<void> _addPackages(String projectName, List<String> packages) async {
  if (packages.isEmpty) return;
  final result = await Process.run(
    'flutter',
    ['pub', 'add', ...packages],
    workingDirectory: './$projectName',
    runInShell: true,
  );
  if (result.exitCode != 0) {
    print('⚠️ ${result.stderr}');
  } else {
    print(result.stdout);
  }
}