import 'dart:io';
import 'package:interact/interact.dart';

import '../services/prompt_service.dart';
import '../services/ai/ai_provider.dart';
import '../services/ai/credential_service.dart';
import 'init_command.dart';
import 'make_command.dart';

/// `sm ai <project_name>` — AI-assisted project scaffolding.
///
/// Flow: pick provider → resolve/prompt for key → 5 questions → AI plan
/// → confirm → reuse existing `initProject` + `makeFeature` generators.
Future<void> runAiInit(String projectName) async {
  if (Directory('$projectName/lib').existsSync()) {
    print('⚠️ Project "$projectName" already exists.');
    print('   Use `sm make feature $projectName <name>` to add to it.');
    return;
  }

  // ---- provider + key ----
  final providerId =
      CredentialService.getDefaultProvider() ?? selectProvider();
  final provider = AiProvider.forId(providerId);
  final label = providerLabels[providerId] ?? providerId;

  var apiKey = CredentialService.resolveKey(provider);
  final isNewKey = apiKey == null;
  if (isNewKey) {
    print('🔑 No saved key for $label. Enter one to continue.');
    apiKey = askApiKey(label);
    if (apiKey.trim().isEmpty) {
      print('❌ Empty API key. Aborted.');
      return;
    }
  }
  final model = CredentialService.resolveModel(provider);

  // ---- questionnaire ----
  final scale = selectProjectScale();
  final budget = selectProjectBudget();
  final featuresBrief = askFeaturesBrief();
  final sm = selectStateManagement();
  final designBrief = askDesignBrief();

  // ---- plan ----
  late ProjectPlan plan;
  final spinner = Spinner(
    icon: '✅',
    rightPrompt: (done) =>
        done ? 'Plan ready' : '$label is planning your project...',
  ).interact();
  try {
    plan = await provider.plan(
      apiKey: apiKey,
      model: model,
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

  // Persist key only after a successful call so bad keys never get saved.
  if (isNewKey) {
    CredentialService.set(providerId, ProviderCredentials(apiKey: apiKey));
    if (CredentialService.getDefaultProvider() == null) {
      CredentialService.setDefaultProvider(providerId);
    }
    print('🔐 Saved $label key to ${CredentialService.path}');
  }

  if (plan.features.isEmpty) {
    print('❌ AI returned no valid features.');
    print('   Try describing the features more concretely.');
    return;
  }

  // ---- confirm before writing anything to disk ----
  print('\n📋 Proposed plan');
  print('   Provider   : $label ($model)');
  print('   State mgmt : $sm');
  print('   Features   : ${plan.features.join(', ')}');
  print('   Theme      : ${plan.themeMode}, seed ${plan.seedColorHex}');
  if (plan.extraPackages.isNotEmpty) {
    print('   Extra deps : ${plan.extraPackages.join(', ')}');
  }
  print('');

  final go =
      Confirm(prompt: 'Generate this project?', defaultValue: true).interact();
  if (!go) {
    print('Aborted. Nothing was written.');
    return;
  }

  // ---- generate ----
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
