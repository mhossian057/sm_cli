import 'dart:io';
import 'package:interact/interact.dart';

import '../services/ai/ai_provider.dart';
import '../services/ai/credential_service.dart';
import '../services/config_service.dart';
import '../services/prompt_service.dart';
import 'make_command.dart';

/// `sm ai implement <project> <feature> --design <path>` — rewrite the
/// feature's screen file to match a reference design.
///
/// Flow:
///   1. Validate project + feature exist, exactly one image supplied.
///   2. Read the current screen file + AppTheme + state-management hint.
///   3. Resolve provider + key (same precedence as `sm ai`).
///   4. Confirm overwrite, generate code, back up original to `.bak`,
///      write result.
///
/// Grok throws — implementation requires vision support.
Future<void> runAiImplement({
  required String projectName,
  required String featureName,
  required List<String> designPaths,
}) async {
  final screenFile = File(
    '$projectName/lib/features/$featureName/presentation/screens/${featureName}_screen.dart',
  );
  final themeFile = File('$projectName/lib/core/theme/app_theme.dart');

  if (!Directory('$projectName/lib').existsSync()) {
    print('❌ Project "$projectName" not found.');
    print('   Run: sm init $projectName');
    return;
  }
  if (!screenFile.existsSync()) {
    print('⚠️  Feature "$featureName" not found in $projectName.');
    final scaffold = Confirm(
      prompt: 'Auto-scaffold "$featureName" now and continue?',
      defaultValue: true,
    ).interact();
    if (!scaffold) {
      print('Aborted. Run `sm make feature $projectName $featureName` '
          'when ready.');
      return;
    }
    await makeFeature(
      projectName: projectName,
      featureName: featureName,
    );
    if (!screenFile.existsSync()) {
      // makeFeature already prints its own error on invalid names /
      // disk failures. Bail out so we don't try to read a missing file.
      print('❌ Scaffolding "$featureName" did not produce '
          '${screenFile.path}. Aborting.');
      return;
    }
  }
  if (designPaths.isEmpty) {
    print('❌ Pass --design <path/to/screenshot.png>.');
    return;
  }
  if (designPaths.length > 1) {
    print('❌ `sm ai implement` rewrites one screen — pass exactly one '
        '--design file. Got ${designPaths.length}.');
    return;
  }

  final designFile = File(designPaths.first);
  if (!designFile.existsSync()) {
    print('❌ Design file not found: ${designFile.path}');
    return;
  }
  final mime = _mimeFor(designFile.path);
  if (mime == null) {
    print('❌ Unsupported image type: ${designFile.path} '
        '(expected .png/.jpg/.jpeg/.webp).');
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

  // ---- context the prompt needs ----
  final currentCode = screenFile.readAsStringSync();
  final appTheme = themeFile.existsSync()
      ? themeFile.readAsStringSync()
      : '// (AppTheme not generated for this project)';
  final stateMgmt = ConfigService.readStateManagement(projectName);

  final asset = DesignAsset(
    bytes: designFile.readAsBytesSync(),
    mimeType: mime,
    label: designFile.uri.pathSegments.last,
  );

  print('\n📋 About to rewrite');
  print('   Provider : $label ($model)');
  print('   Screen   : ${screenFile.path}');
  print('   Design   : ${designFile.path}');
  print('   State    : $stateMgmt');
  print('');
  final go = Confirm(
    prompt: 'Overwrite the screen file with AI-generated code?',
    defaultValue: true,
  ).interact();
  if (!go) {
    print('Aborted. Nothing was written.');
    return;
  }

  // ---- generate ----
  late ImplementResult result;
  final spinner = Spinner(
    icon: '✅',
    rightPrompt: (done) =>
        done ? 'Code ready' : '$label is implementing the screen...',
  ).interact();
  try {
    result = await provider.generateCode(
      apiKey: apiKey,
      model: model,
      systemPrompt: ImplementPromptBuilder.system,
      userPrompt: ImplementPromptBuilder.user(
        featureName: featureName,
        stateMgmt: stateMgmt,
        currentFile: currentCode,
        appTheme: appTheme,
      ),
      assets: [asset],
    );
  } catch (e) {
    spinner.done();
    print('❌ $e');
    return;
  }
  spinner.done();

  if (isNewKey) {
    CredentialService.set(providerId, ProviderCredentials(apiKey: apiKey));
    if (CredentialService.getDefaultProvider() == null) {
      CredentialService.setDefaultProvider(providerId);
    }
    print('🔐 Saved $label key to ${CredentialService.path}');
  }

  // ---- backup + write screen ----
  final backup = File('${screenFile.path}.bak');
  backup.writeAsStringSync(currentCode);
  screenFile.writeAsStringSync(result.screen);

  // ---- write extracted widgets ----
  final widgetsDir = Directory(
    '$projectName/lib/features/$featureName/presentation/widgets',
  );
  widgetsDir.createSync(recursive: true);
  final writtenWidgets = <String>[];
  for (final w in result.widgets) {
    final file = File('${widgetsDir.path}/${w.filename}');
    file.writeAsStringSync(w.code);
    writtenWidgets.add(file.path);
  }

  // Also save the design alongside other references.
  final designDir = Directory('$projectName/design');
  designDir.createSync(recursive: true);
  final savedDesign = File('${designDir.path}/${featureName}_'
      '${designFile.uri.pathSegments.last}');
  savedDesign.writeAsBytesSync(asset.bytes);

  print('\n✅ Rewrote ${screenFile.path}');
  print('   Backup  : ${backup.path}');
  print('   Design  : ${savedDesign.path}');
  if (writtenWidgets.isNotEmpty) {
    print('   Widgets : ${writtenWidgets.length}');
    for (final p in writtenWidgets) {
      print('     • $p');
    }
  }
  print('\n   Verify with:  cd $projectName && flutter analyze');
  print('   Revert with:  mv ${backup.path} ${screenFile.path}');
}

String? _mimeFor(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  return null;
}
