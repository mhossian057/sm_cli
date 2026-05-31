import 'dart:io';
import 'package:interact/interact.dart';

import '../services/prompt_service.dart';
import '../services/ai_service.dart';
import 'init_command.dart';
import 'make_command.dart';

/// `sm ai <project_name>` — AI-assisted project scaffolding.
///
/// Flow: 5 questions -> AI returns a plan -> confirm -> reuse the existing
/// `initProject` + `makeFeature` generators to write files.
Future<void> runAiInit(String projectName) async {
  if (Directory('$projectName/lib').existsSync()) {
    print('⚠️ Project "$projectName" already exists.');
    print('   Use `sm make feature $projectName <name>` to add to it.');
    return;
  }

  // 5 questions
  final scale = selectProjectScale();
  final budget = selectProjectBudget();
  final featuresBrief = askFeaturesBrief();
  final sm = selectStateManagement(); // existing prompt
  final designBrief = askDesignBrief();

  // AI plans
  late ProjectPlan plan;
  final spinner = Spinner(
    icon: '✅',
    rightPrompt: (done) => done ? 'Plan ready' : 'AI is planning your project...',
  ).interact();
  try {
    plan = await AiService.plan(
      scale: scale,
      budget: budget,
      featuresBrief: featuresBrief,
      stateMgmt: sm,
      designBrief: designBrief,
    );
  } catch (e) {
    spinner.done();
    print('❌ $e');
    return;
  }
  spinner.done();

  if (plan.features.isEmpty) {
    print('❌ AI returned no valid features.');
    print('   Try describing the features more concretely.');
    return;
  }

  // Confirm BEFORE writing anything to disk.
  print('\n📋 Proposed plan');
  print('   State mgmt : $sm');
  print('   Features   : ${plan.features.join(', ')}');
  print('   Theme      : ${plan.themeMode}, seed ${plan.seedColorHex}');
  if (plan.extraPackages.isNotEmpty) {
    print('   Extra deps : ${plan.extraPackages.join(', ')}');
  }
  print('');

  final go = Confirm(prompt: 'Generate this project?', defaultValue: true).interact();
  if (!go) {
    print('Aborted. Nothing was written.');
    return;
  }

  // Reuse existing generators — no changes needed to them.
  await initProject(
    projectName: projectName,
    riverpod: sm == 'Riverpod',
    bloc: sm == 'Bloc',
    getx: sm == 'GetX',
    useGoRouter: true,
    useTheme: true,
  );

  for (final feature in plan.features) {
    await makeFeature(projectName: projectName, featureName: feature);
  }

  // extra_packages -> flutter pub add (same pattern initProject uses).
  if (plan.extraPackages.isNotEmpty) {
    print('📦 Adding extra packages: ${plan.extraPackages.join(', ')}');
    final result = await Process.run(
      'flutter',
      ['pub', 'add', ...plan.extraPackages],
      workingDirectory: './$projectName',
      runInShell: true,
    );
    if (result.exitCode != 0) {
      print('⚠️ ${result.stderr}');
    }
  }

  print('\n✅ AI-generated project "$projectName" ready '
      'with ${plan.features.length} feature(s).');
  print('   cd $projectName && flutter run');
}
