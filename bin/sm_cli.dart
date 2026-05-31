import 'dart:io';

import 'package:args/args.dart';
import 'package:sm_cli/commands/init_command.dart';
import 'package:sm_cli/commands/make_command.dart';
import 'package:sm_cli/commands/remove_command.dart';
import 'package:sm_cli/commands/ai_command.dart';
import 'package:sm_cli/services/config_service.dart';
import 'package:sm_cli/services/prompt_service.dart';

void main(List<String> arguments) async {
  final parser = ArgParser();

  // INIT COMMAND
  final initCommand = ArgParser()
    ..addFlag('riverpod', abbr: 'r', negatable: false)
    ..addFlag('bloc', abbr: 'b', negatable: false)
    ..addFlag('getx', abbr: 'g', negatable: false)
    ..addFlag('provider', abbr: 'p', negatable: false);

  parser.addCommand('init', initCommand);

  // MAKE COMMAND
  final makeFeatureCommand = ArgParser();
  final makeApiCommand = ArgParser();

  final makeCommand = ArgParser()
    ..addCommand('feature', makeFeatureCommand)
    ..addCommand('api', makeApiCommand);

  parser.addCommand('make', makeCommand);

// REMOVE COMMAND
  final removeFeatureCommand = ArgParser()
    ..addFlag('force', abbr: 'f', negatable: false, help: 'Skip confirmation');
  final removeCommand = ArgParser()
    ..addCommand('feature', removeFeatureCommand);
  parser.addCommand('remove', removeCommand);

  // LIST COMMAND
  parser.addCommand('list');

  // AI COMMAND
  parser.addCommand('ai');

  // HELP & VERSION
  parser.addFlag('help', abbr: 'h', negatable: false, help: 'Show help');
  parser.addFlag('version', abbr: 'v', negatable: false, help: 'Show version');

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (e) {
    print('❌ $e');
    _printHelp();
    return;
  }

  if (results['help'] == true || arguments.isEmpty) {
    _printHelp();
    return;
  }

  if (results['version'] == true) {
    print('sm_cli version 1.0.7');
    return;
  }

  // ---- INIT ----
  if (results.command?.name == 'init') {
    final command = results.command!;

    if (command.rest.isEmpty) {
      print('❌ Please provide project name');
      print('   Usage: sm init <project_name>');
      return;
    }

    final projectName = command.rest.first;

    bool riverpod = command['riverpod'] as bool;
    bool bloc = command['bloc'] as bool;
    bool getx = command['getx'] as bool;
    bool provider = command['provider'] as bool;

    String selected;
    if (riverpod) {
      selected = 'Riverpod';
    } else if (bloc) {
      selected = 'Bloc';
    } else if (getx) {
      selected = 'GetX';
    } else if (provider) {
      selected = 'Provider';
    } else {
      selected = selectStateManagement();
    }

    final useGoRouter = enableGoRouter();
    final useTheme = enableTheme();

    await initProject(
      projectName: projectName,
      riverpod: selected == 'Riverpod',
      bloc: selected == 'Bloc',
      getx: selected == 'GetX',
      useGoRouter: useGoRouter,
      useTheme: useTheme,
    );
  }

  // ---- MAKE ----
  else if (results.command?.name == 'make') {
    final subCommand = results.command!.command;

    if (subCommand == null) {
      print('❌ Please provide sub command');
      print('   Usage: sm make feature <project_name> <feature_name>');
      print('          sm make api <project_name>');
      return;
    }

    // FEATURE
    if (subCommand.name == 'feature') {
      if (subCommand.rest.length < 2) {
        print('❌ Please provide project name and feature name');
        print('   Usage: sm make feature <project_name> <feature_name>');
        return;
      }

      final projectName = subCommand.rest[0];
      final featureNames = subCommand.rest.sublist(1);

      if (!Directory('$projectName/lib').existsSync()) {
        print('❌ Project "$projectName" not found');
        print('   Run: sm init $projectName first');
        return;
      }

      for (final featureName in featureNames) {
        await makeFeature(
          projectName: projectName,
          featureName: featureName,
        );
      }
    }

    // API
    else if (subCommand.name == 'api') {
      if (subCommand.rest.isEmpty) {
        print('❌ Please provide project name');
        print('   Usage: sm make api <project_name>');
        return;
      }

      final projectName = subCommand.rest.first;

      if (!Directory('$projectName/lib').existsSync()) {
        print('❌ Project "$projectName" not found');
        print('   Run: sm init $projectName first');
        return;
      }

      await makeApi(projectName: projectName);
    }
  }

  // ---- REMOVE ----
  else if (results.command?.name == 'remove') {
    final subCommand = results.command!.command;

    if (subCommand == null) {
      print('❌ Please provide sub command');
      print('   Usage: sm remove feature <project_name> <feature_name>');
      return;
    }

    if (subCommand.name == 'feature') {
      if (subCommand.rest.length < 2) {
        print('❌ Please provide project name and feature name');
        print('   Usage: sm remove feature <project_name> <feature_name>');
        return;
      }

      final projectName = subCommand.rest[0];
      final featureName = subCommand.rest[1];
      final force = subCommand['force'] as bool;

      if (!Directory('$projectName/lib').existsSync()) {
        print('❌ Project "$projectName" not found');
        return;
      }

      await removeFeature(
        projectName: projectName,
        featureName: featureName,
        force: force,
      );
    }
  }

  // ---- LIST ----
  else if (results.command?.name == 'list') {
    if (results.command!.rest.isEmpty) {
      print('❌ Please provide project name');
      print('   Usage: sm list <project_name>');
      return;
    }

    final projectName = results.command!.rest.first;

    if (!Directory('$projectName/lib/features').existsSync()) {
      print('❌ Project "$projectName" not found');
      return;
    }

    final featuresDir = Directory('$projectName/lib/features');
    final features = featuresDir
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split('/').last)
        .toList();

    if (features.isEmpty) {
      print('📂 No features found in "$projectName"');
      print('   Run: sm make feature $projectName <name>');
      return;
    }

    final stateManagement = ConfigService.readStateManagement(projectName);

    print('📦 $projectName Features ($stateManagement):');
    print('');
    for (final feature in features) {
      final featureDir = Directory('$projectName/lib/features/$feature');
      final fileCount = featureDir
          .listSync(recursive: true)
          .whereType<File>()
          .length;
      print('  ✅ $feature ($fileCount files)');
    }
    print('');
    print('Total: ${features.length} feature(s)');
  }

  // ---- AI ----
  else if (results.command?.name == 'ai') {
    if (results.command!.rest.isEmpty) {
      print('❌ Please provide project name');
      print('   Usage: sm ai <project_name>');
      return;
    }
    await runAiInit(results.command!.rest.first);
  }

  else {
    _printHelp();
  }
}

void _printHelp() {
  print('''
🚀 SM CLI - Flutter Clean Architecture Generator

Usage:
  sm init <project_name>                        Create new Flutter project
  sm make feature <project> <feature>           Generate a new feature
  sm make api <project>                         Generate API layer (Dio)
  sm remove feature <project> <feature>         Remove a feature
  sm list <project>                             List all features
  sm ai <project>                               AI-assisted project setup

Flags for init:
  -r, --riverpod    Use Riverpod (default: interactive)
  -b, --bloc        Use Bloc
  -g, --getx        Use GetX
  -p, --provider    Use Provider
  -h, --help        Show this help
  -v, --version     Show version

Examples:
  sm init my_app
  sm init my_app --riverpod
  sm make feature my_app auth
  sm make api my_app
  sm remove feature my_app auth
  sm list my_app
''');
}