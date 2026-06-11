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

  // ---- backup ----
  final backup = File('${screenFile.path}.bak');
  backup.writeAsStringSync(currentCode);

  // ---- filename<->class sanity check ----
  for (final w in result.widgets) {
    if (!_filenameMatchesClass(w)) {
      print('⚠️  ${w.filename}: no top-level class matches the filename. '
          'Writing anyway — verify after generation.');
    }
  }

  // ---- normalize then write extracted widgets ----
  // Normalize first so the pub-add scanner below sees the same imports
  // we wrote to disk — otherwise a stripped bogus `package:<x>/app_theme`
  // import gets `flutter pub add`-ed as if it were a real dependency.
  final normalizedWidgets = [
    for (final w in result.widgets)
      GeneratedFile(
        filename: w.filename,
        code: _normalizeAppThemeImport(w.code),
      ),
  ];
  final widgetsDir = Directory(
    '$projectName/lib/features/$featureName/presentation/widgets',
  );
  widgetsDir.createSync(recursive: true);
  final writtenWidgets = <String>[];
  for (final w in normalizedWidgets) {
    final file = File('${widgetsDir.path}/${w.filename}');
    file.writeAsStringSync(w.code);
    writtenWidgets.add(file.path);
  }

  // ---- rewrite screen imports + write ----
  // AI routinely emits the wrong widgets/* path or a filename that doesn't
  // match what it produced, and guesses random AppTheme paths. Replace its
  // import block deterministically before dart fix runs.
  final fixedScreen = _rewriteScreenImports(
    screen: result.screen,
    widgets: result.widgets,
  );
  screenFile.writeAsStringSync(fixedScreen);

  // ---- warn if AI declared state-management classes ----
  // `sm ai implement --design` is UI-only; the prompt forbids new
  // ChangeNotifier/Bloc/Cubit/Controller/Notifier declarations. AI still
  // slips them in. Don't auto-strip (could break the screen body) — flag
  // so the user can extract them to the right layer.
  _warnIfBusinessLogic(
    screen: fixedScreen,
    widgets: normalizedWidgets,
    screenPath: screenFile.path,
    widgetsDirPath: widgetsDir.path,
  );

  // ---- auto-add pub packages the AI used but didn't declare ----
  // SvgPicture/Lottie/etc. fail to compile without their package in
  // pubspec. Detect every `package:<x>/...` import outside the flutter
  // family and the project itself, and `flutter pub add` it. Scans the
  // normalized text so stripped bogus imports don't get added.
  final addedPackages = await _addMissingPackages(
    projectName: projectName,
    screen: fixedScreen,
    widgets: normalizedWidgets,
  );

  // ---- dart fix safety net ----
  // Resolves any symbol we did not anticipate (AppTheme aside) and applies
  // the analyzer's quick-fixes. Non-fatal: a missing dart CLI must not
  // break the implement flow.
  final fixSpinner = Spinner(
    icon: '🔧',
    rightPrompt: (done) =>
        done ? 'dart fix applied' : 'Running dart fix --apply...',
  ).interact();
  try {
    final fixResult = await Process.run(
      'dart',
      ['fix', '--apply'],
      workingDirectory: projectName,
      runInShell: true,
    );
    fixSpinner.done();
    if (fixResult.exitCode != 0) {
      final err = '${fixResult.stderr}'.trim();
      print('⚠️  dart fix exited ${fixResult.exitCode}. '
          'Check imports manually.');
      if (err.isNotEmpty) print('   $err');
    }
  } catch (e) {
    fixSpinner.done();
    print('⚠️  Could not run dart fix ($e). Check imports manually.');
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
  if (addedPackages.isNotEmpty) {
    print('   Packages added: ${addedPackages.join(', ')}');
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

/// Strip every `widgets/...` import the AI emitted (it routinely guesses
/// the path or the filename) and re-inject one correct relative import per
/// file in [widgets]. AppTheme is handled by [_normalizeAppThemeImport]
/// because widget files need the same treatment as the screen.
String _rewriteScreenImports({
  required String screen,
  required List<GeneratedFile> widgets,
}) {
  final importRe = RegExp(
    r'''^\s*import\s+['"]([^'"]+)['"]\s*(?:as\s+\w+\s*)?;\s*$''',
  );
  final lines = screen.split('\n');
  final kept = <String>[];
  var lastImportIdx = -1;

  for (final line in lines) {
    final m = importRe.firstMatch(line);
    if (m != null) {
      final path = m.group(1)!;
      if (path.contains('/widgets/') || path.startsWith('widgets/')) {
        continue;
      }
      lastImportIdx = kept.length;
    }
    kept.add(line);
  }

  if (widgets.isNotEmpty) {
    final injected = [
      for (final w in widgets) "import '../widgets/${w.filename}';",
    ];
    final at = lastImportIdx >= 0 ? lastImportIdx + 1 : 0;
    kept.insertAll(at, injected);
  }
  return _normalizeAppThemeImport(kept.join('\n'));
}

/// AppTheme lives at `lib/core/theme/app_theme.dart`. AI guesses paths
/// like `package:<app>/app/app_theme.dart` or `../../theme/app_theme.dart`
/// constantly. Strip anything ending in `app_theme.dart` that isn't the
/// real location, then re-inject the correct relative path when AppTheme
/// is referenced. Applied to both the screen and every widget file —
/// both sit four directories below `lib/`, so the path is the same.
String _normalizeAppThemeImport(String code) {
  const correctImport =
      "import '../../../../core/theme/app_theme.dart';";
  final importRe = RegExp(
    r'''^\s*import\s+['"]([^'"]+)['"]\s*(?:as\s+\w+\s*)?;\s*$''',
  );
  final lines = code.split('\n');
  final kept = <String>[];
  var lastImportIdx = -1;
  var sawCorrect = false;

  for (final line in lines) {
    final m = importRe.firstMatch(line);
    if (m != null) {
      final path = m.group(1)!;
      if (path.endsWith('core/theme/app_theme.dart')) {
        sawCorrect = true;
        lastImportIdx = kept.length;
      } else if (path.contains('app_theme')) {
        continue;
      } else {
        lastImportIdx = kept.length;
      }
    }
    kept.add(line);
  }

  final references = RegExp(r'\bAppTheme\b').hasMatch(code);
  if (references && !sawCorrect) {
    final at = lastImportIdx >= 0 ? lastImportIdx + 1 : 0;
    kept.insert(at, correctImport);
  }
  return kept.join('\n');
}

/// Scan AI-generated code for `package:<name>/...` imports that aren't
/// already in pubspec and shell out to `flutter pub add` for each. The
/// system prompt forbids new packages, the AI ignores it routinely
/// (`flutter_svg`, `cached_network_image`, `google_fonts`, …) — adding
/// them deterministically beats failing at compile time. Returns the
/// names actually added so the caller can surface them.
Future<List<String>> _addMissingPackages({
  required String projectName,
  required String screen,
  required List<GeneratedFile> widgets,
}) async {
  final pubspec = File('$projectName/pubspec.yaml');
  if (!pubspec.existsSync()) return const [];
  final pubspecText = pubspec.readAsStringSync();
  final ownName = RegExp(r'^name:\s*([a-z0-9_]+)', multiLine: true)
      .firstMatch(pubspecText)
      ?.group(1);

  final skip = <String>{
    'flutter',
    'flutter_localizations',
    'flutter_test',
    if (ownName != null) ownName,
  };
  final pkgRe = RegExp(r'''import\s+['"]package:([a-z0-9_]+)/''');
  final found = <String>{};
  void scan(String code) {
    for (final m in pkgRe.allMatches(code)) {
      found.add(m.group(1)!);
    }
  }

  scan(screen);
  for (final w in widgets) {
    scan(w.code);
  }
  found.removeAll(skip);

  final missing = found.where((pkg) {
    return !RegExp('^\\s+$pkg\\s*:', multiLine: true).hasMatch(pubspecText);
  }).toList()
    ..sort();
  if (missing.isEmpty) return const [];

  // Verify each candidate exists on pub.dev before adding. AI hallucinates
  // brand-derived names (`aliv`, `aliv_app`, etc.) and `flutter pub add`
  // will happily add anything resolvable. Skip with a clear warning so
  // pubspec doesn't accumulate garbage.
  final verified = <String>[];
  for (final pkg in missing) {
    if (await _existsOnPubDev(pkg)) {
      verified.add(pkg);
    } else {
      print('⚠️  Skipping "$pkg" — not found on pub.dev. '
          'AI likely hallucinated this import; review the generated code.');
    }
  }
  if (verified.isEmpty) return const [];

  final added = <String>[];
  for (final pkg in verified) {
    final r = await Process.run(
      'flutter',
      ['pub', 'add', pkg],
      workingDirectory: projectName,
      runInShell: true,
    );
    if (r.exitCode == 0) {
      added.add(pkg);
    } else {
      print('⚠️  flutter pub add $pkg failed:');
      final err = '${r.stderr}'.trim();
      if (err.isNotEmpty) print('   $err');
    }
  }
  return added;
}

/// True iff pub.dev returns 200 for `/api/packages/<name>`. Network
/// errors and timeouts return false: better to skip a real package than
/// pollute pubspec with an AI hallucination.
Future<bool> _existsOnPubDev(String name) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final req = await client.getUrl(
      Uri.parse('https://pub.dev/api/packages/$name'),
    );
    final res = await req.close().timeout(const Duration(seconds: 8));
    await res.drain<void>();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client?.close(force: true);
  }
}

/// Scan generated files for state-mgmt class declarations the design-only
/// prompt forbids (ChangeNotifier, Cubit, Bloc, GetxController,
/// StateNotifier, Notifier, AsyncNotifier). Warn per match — don't
/// auto-strip, since the screen body likely references the class and
/// removing it would break the build.
void _warnIfBusinessLogic({
  required String screen,
  required List<GeneratedFile> widgets,
  required String screenPath,
  required String widgetsDirPath,
}) {
  final patterns = <RegExp>[
    RegExp(r'class\s+(\w+)\s+with\s+ChangeNotifier'),
    RegExp(
      r'class\s+(\w+)\s+extends\s+(Cubit|Bloc|GetxController|StateNotifier|Notifier|AsyncNotifier)\b',
    ),
  ];

  void check(String code, String path) {
    for (final re in patterns) {
      for (final m in re.allMatches(code)) {
        print('⚠️  $path declares `${m.group(0)}`. `sm ai implement --design` '
            'is UI-only — move this to the feature\'s state layer.');
      }
    }
  }

  check(screen, screenPath);
  for (final w in widgets) {
    check(w.code, '$widgetsDirPath/${w.filename}');
  }
}

/// Filename `social_login_button.dart` is expected to declare
/// `class SocialLoginButton`. AI occasionally renames one without the
/// other; warn so the user can spot it before `dart fix` chases ghosts.
bool _filenameMatchesClass(GeneratedFile w) {
  final stem = w.filename.replaceAll(RegExp(r'\.dart$'), '');
  final expected = stem
      .split('_')
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join();
  return RegExp('class\\s+$expected\\b').hasMatch(w.code);
}
