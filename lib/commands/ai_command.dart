import 'dart:io';
import 'package:interact/interact.dart';

import '../services/prompt_service.dart';
import '../services/ai/ai_provider.dart';
import '../services/ai/credential_service.dart';
import '../services/figma_service.dart';
import 'init_command.dart';
import 'make_command.dart';

/// Max images per individual plan API call. Sized for Gemini's
/// server-side processing deadline (`503 UNAVAILABLE: Deadline expired`
/// trips at ~15+ large mobile mockups in one request).
const _kMaxAssetsPerPass = 12;

/// Raw image bytes per individual call. Each provider base64-encodes
/// images (adds ~33% overhead), so 8 MB raw ≈ 10.7 MB on the wire —
/// safely under Gemini's 20 MB inline-data limit.
const _kMaxBytesPerPass = 8 * 1024 * 1024;

/// Max number of plan passes to run when more representatives exist
/// than fit in one call. 4 passes × 12 = up to 48 images analyzed.
/// Beyond that, even sampling kicks in so the cost stays bounded.
const _kMaxPlanPasses = 4;

/// `sm ai <project_name>` — AI-assisted project scaffolding.
///
/// Flow: pick provider → resolve/prompt for key → resolve design assets
/// (local + Figma) → 5 questions → AI plan → confirm → reuse existing
/// `initProject` + `makeFeature` generators → copy assets into
/// `<project>/design/` so the project carries its design provenance.
Future<void> runAiInit(
  String projectName, {
  List<String> designPaths = const [],
  String? figmaKey,
  List<String> figmaNodeIds = const [],
}) async {
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

  // ---- design assets (local + figma) ----
  final assets = <DesignAsset>[];
  try {
    assets.addAll(_loadLocalAssets(designPaths));
    if (figmaKey != null && figmaKey.isNotEmpty) {
      assets.addAll(await _loadFigmaAssets(figmaKey, figmaNodeIds));
    }
  } catch (e) {
    print('❌ $e');
    return;
  }
  if (assets.isNotEmpty) {
    print('🖼️  ${assets.length} reference design(s) attached: '
        '${assets.map((a) => a.label).join(', ')}');
  }

  // Cluster + cap into representatives, then split into API-sized
  // batches. Each batch becomes one plan call; results are merged.
  final reps = _selectRepresentatives(assets);
  final batches = _chunkForPasses(reps);

  // ---- questionnaire ----
  final scale = selectProjectScale();
  final budget = selectProjectBudget();
  final featuresBrief = askFeaturesBrief();
  final sm = selectStateManagement();
  final designBrief = askDesignBrief();

  // ---- plan (one pass when no images or fits in one call, multi-pass
  // when there are more representatives than fit one API request) ----
  final passes = batches.isEmpty ? 1 : batches.length;
  if (passes > 1) {
    print('🔁 Planning across $passes pass(es) so every cluster is seen '
        '(${reps.length} representatives, batches of '
        '${batches.map((b) => b.length).join('/')}).');
  } else if (reps.isNotEmpty) {
    final mb = (batches.first.fold<int>(0, (s, a) => s + a.bytes.length) /
            (1024 * 1024))
        .toStringAsFixed(1);
    print('🖼️  Sending ${reps.length} representative image(s) ($mb MB) '
        'to the AI (the full ${assets.length} stay saved in '
        '<project>/design/).');
  }

  late ProjectPlan plan;
  final spinner = Spinner(
    icon: '✅',
    rightPrompt: (done) =>
        done ? 'Plan ready' : '$label is planning your project...',
  ).interact();
  try {
    ProjectPlan? merged;
    final callBatches = batches.isEmpty ? [<DesignAsset>[]] : batches;
    for (var i = 0; i < callBatches.length; i++) {
      final passPlan = await provider.plan(
        apiKey: apiKey,
        model: model,
        scale: scale,
        budget: budget,
        featuresBrief: featuresBrief,
        stateMgmt: sm,
        designBrief: designBrief,
        assets: callBatches[i],
      );
      merged = merged == null ? passPlan : _mergePlans(merged, passPlan);
    }
    plan = merged!;
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
  if (plan.visualLanguage.isNotEmpty) {
    print('   Aesthetic  : ${plan.visualLanguage}');
  }
  print('   Fonts      : ${plan.displayFont} (display) / ${plan.bodyFont} (body)');
  if (plan.extraPackages.isNotEmpty) {
    print('   Extra deps : ${plan.extraPackages.join(', ')}');
  }
  if (assets.isNotEmpty) {
    print('   Designs    : ${assets.length} image(s) → $projectName/design/');
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
    themeMode: plan.themeMode,
    seedColorHex: plan.seedColorHex,
    displayFont: plan.displayFont,
    bodyFont: plan.bodyFont,
  );

  for (final feature in plan.features) {
    await makeFeature(projectName: projectName, featureName: feature);
  }

  // google_fonts is required by the generated theme; merge it with any
  // extras the AI requested (deduped) so we don't run pub add twice.
  final extras = {'google_fonts', ...plan.extraPackages}.toList();
  print('📦 Adding extra packages: ${extras.join(', ')}');
  final result = await Process.run(
    'flutter',
    ['pub', 'add', ...extras],
    workingDirectory: './$projectName',
    runInShell: true,
  );
  if (result.exitCode != 0) {
    print('⚠️ ${result.stderr}');
  }

  // ---- copy design assets into the project ----
  if (assets.isNotEmpty) {
    final designDir = Directory('$projectName/design');
    designDir.createSync(recursive: true);
    for (final a in assets) {
      File('${designDir.path}/${a.savedFilename}').writeAsBytesSync(a.bytes);
    }
    print('🖼️  Saved ${assets.length} design file(s) to $projectName/design/');
  }

  print('\n✅ AI-generated project "$projectName" ready '
      'with ${plan.features.length} feature(s).');
  print('   cd $projectName && flutter run');
}

/// Reads every `--design <path>` argument. Each path may be a file or a
/// directory; directories are scanned one level deep for `.png` / `.jpg`
/// / `.jpeg` / `.webp` images. Throws if a path doesn't exist or matches
/// nothing.
List<DesignAsset> _loadLocalAssets(List<String> paths) {
  if (paths.isEmpty) return const [];
  final out = <DesignAsset>[];
  for (final raw in paths) {
    final entity = FileSystemEntity.typeSync(raw);
    if (entity == FileSystemEntityType.notFound) {
      throw Exception('Design path not found: $raw');
    }
    final files = entity == FileSystemEntityType.directory
        ? Directory(raw)
            .listSync()
            .whereType<File>()
            .where((f) => _isImage(f.path))
            .toList()
        : [File(raw)];
    if (files.isEmpty) {
      throw Exception('No images found at $raw '
          '(expected .png/.jpg/.jpeg/.webp)');
    }
    for (final f in files) {
      out.add(DesignAsset(
        bytes: f.readAsBytesSync(),
        mimeType: _mimeFor(f.path),
        label: f.uri.pathSegments.last,
      ));
    }
  }
  return out;
}

Future<List<DesignAsset>> _loadFigmaAssets(
  String fileKey,
  List<String> nodeIds,
) async {
  var token = CredentialService.resolveFigmaToken();
  final isNewToken = token == null;
  if (isNewToken) {
    print('🔑 No saved Figma token. Personal Access Tokens are free — '
        'generate one in Figma → Account Settings → Personal access tokens.');
    token = askApiKey('Figma');
    if (token.trim().isEmpty) {
      throw Exception('Empty Figma token. Aborted.');
    }
  }

  print('🎨 Fetching Figma frames for $fileKey...');
  final assets = await FigmaService.renderFrames(
    fileKey: fileKey,
    token: token,
    nodeIds: nodeIds,
  );

  if (isNewToken) {
    CredentialService.setFigmaToken(token);
    print('🔐 Saved Figma token to ${CredentialService.path}');
  }
  return assets;
}

bool _isImage(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp');
}

String _mimeFor(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/png';
}

/// Normalize a filename into a cluster key. `Login.png`, `Login-1.png`,
/// `02 Login.png` all collapse to `login`. Preserves semantically
/// distinct names like `Forget OTP` vs `Forget Password` (no trailing
/// number → different clusters).
String _clusterKey(String filename) {
  var name = filename.toLowerCase();
  name = name.replaceAll(RegExp(r'\.(png|jpe?g|webp)$'), '');
  // Drop leading sequence prefixes like "02 ", "1_", "3-".
  name = name.replaceFirst(RegExp(r'^\d+[\s_-]+'), '');
  // Iteratively strip trailing "-1", " 137", "_4418" style suffixes.
  while (RegExp(r'[\s_-]+\d+$').hasMatch(name)) {
    name = name.replaceFirst(RegExp(r'[\s_-]+\d+$'), '');
  }
  return name.trim();
}

/// True if the asset came from a Figma render — those labels look like
/// `figma_1:23` and have no meaningful prefix to cluster on.
bool _isFigmaAsset(DesignAsset a) => a.label.startsWith('figma_');

/// Cluster local files by filename prefix, keep figma renders as-is,
/// then cap the total at [_kMaxPlanPasses] × [_kMaxAssetsPerPass] reps.
/// The returned list feeds [_chunkForPasses] which splits it into
/// batches the API can actually swallow.
List<DesignAsset> _selectRepresentatives(List<DesignAsset> assets) {
  // Split: local files can cluster; figma renders cannot.
  final local = assets.where((a) => !_isFigmaAsset(a)).toList();
  final figma = assets.where(_isFigmaAsset).toList();

  // Build clusters by prefix, preserve first-seen order for stable output.
  final clusters = <String, List<DesignAsset>>{};
  for (final a in local) {
    clusters.putIfAbsent(_clusterKey(a.label), () => []).add(a);
  }
  final localReps = clusters.values.map((group) {
    group.sort((a, b) => a.label.compareTo(b.label));
    return group.first;
  }).toList();

  var picked = <DesignAsset>[...localReps, ...figma];

  if (clusters.isNotEmpty || figma.isNotEmpty) {
    print('🧮 Clustered ${assets.length} image(s) → ${clusters.length} '
        'local cluster(s)${figma.isNotEmpty ? ' + ${figma.length} figma' : ''}');
    for (final entry in clusters.entries) {
      if (entry.value.length > 1) {
        print('   • ${entry.key} (${entry.value.length} variants → '
            '${entry.value.first.label})');
      }
    }
  }

  // Bound the absolute representative count so multi-pass cost stays
  // predictable. Even-sample to keep coverage diverse if we trim.
  final hardCap = _kMaxPlanPasses * _kMaxAssetsPerPass;
  if (picked.length > hardCap) {
    final step = picked.length / hardCap;
    final sampled = [for (var i = 0; i < hardCap; i++) picked[(i * step).floor()]];
    print('⚠️  ${picked.length} representatives exceed the $hardCap-cap '
        '($_kMaxPlanPasses passes × $_kMaxAssetsPerPass). '
        'Sampling $hardCap evenly.');
    picked = sampled;
  }

  return picked;
}

/// Pack [reps] into batches, each ≤ [_kMaxAssetsPerPass] images AND
/// ≤ [_kMaxBytesPerPass] raw bytes. Multi-pass planning runs one API
/// call per batch and merges the results.
List<List<DesignAsset>> _chunkForPasses(List<DesignAsset> reps) {
  final batches = <List<DesignAsset>>[];
  var current = <DesignAsset>[];
  var currentBytes = 0;
  for (final a in reps) {
    final wouldExceed = current.length >= _kMaxAssetsPerPass ||
        currentBytes + a.bytes.length > _kMaxBytesPerPass;
    if (wouldExceed && current.isNotEmpty) {
      batches.add(current);
      current = <DesignAsset>[];
      currentBytes = 0;
    }
    current.add(a);
    currentBytes += a.bytes.length;
  }
  if (current.isNotEmpty) batches.add(current);
  return batches;
}

/// Merge feature/package lists from multi-pass planning. The first
/// pass's theme tokens win — they're usually consistent across passes
/// and the alternative (averaging) produces muddy colors.
ProjectPlan _mergePlans(ProjectPlan a, ProjectPlan b) {
  final features = <String>{...a.features, ...b.features}.toList();
  final packages = <String>{...a.extraPackages, ...b.extraPackages}.toList();
  return ProjectPlan(
    features: features,
    extraPackages: packages,
    themeMode: a.themeMode,
    seedColorHex: a.seedColorHex,
    visualLanguage: a.visualLanguage,
    displayFont: a.displayFont,
    bodyFont: a.bodyFont,
  );
}
