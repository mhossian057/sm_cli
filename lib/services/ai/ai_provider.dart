import 'dart:convert';

import 'claude_provider.dart';
import 'design_asset.dart';
import 'gemini_provider.dart';
import 'grok_provider.dart';
import 'openai_provider.dart';
import 'skills.g.dart';

export 'design_asset.dart';

/// AI-generated scaffolding plan. Maps onto the existing generators:
/// `features` → `generateFeature`, `extraPackages` → `flutter pub add`.
class ProjectPlan {
  final List<String> features;
  final List<String> extraPackages;
  final String themeMode;       // 'light' | 'dark' | 'system'
  final String seedColorHex;    // '#RRGGBB'
  final String visualLanguage;  // free-form, e.g. 'brutalist', 'editorial'
  final String displayFont;     // google_fonts family for display
  final String bodyFont;        // google_fonts family for body

  ProjectPlan({
    required this.features,
    required this.extraPackages,
    required this.themeMode,
    required this.seedColorHex,
    required this.visualLanguage,
    required this.displayFont,
    required this.bodyFont,
  });

  factory ProjectPlan.fromJson(Map<String, dynamic> j) {
    return ProjectPlan(
      features: (j['features'] as List? ?? const []).cast<String>(),
      extraPackages: (j['extra_packages'] as List? ?? const []).cast<String>(),
      themeMode: j['theme_mode'] as String? ?? 'system',
      seedColorHex: j['seed_color'] as String? ?? '#2196F3',
      visualLanguage: j['visual_language'] as String? ?? '',
      displayFont: j['display_font'] as String? ?? 'Inter',
      bodyFont: j['body_font'] as String? ?? 'Inter',
    );
  }
}

/// All supported provider ids. Adding a provider = one entry here +
/// one branch in [AiProvider.forId].
const supportedProviderIds = <String>['claude', 'openai', 'gemini', 'grok'];

/// Pretty label per provider id (used in prompts & confirmations).
const providerLabels = <String, String>{
  'claude': 'Anthropic Claude',
  'openai': 'OpenAI ChatGPT',
  'gemini': 'Google Gemini',
  'grok':   'xAI Grok',
};

/// One implementation per AI vendor. Each impl owns its endpoint,
/// auth header style, and response-shape parsing — the prompt itself
/// is shared via [PlanPromptBuilder].
abstract class AiProvider {
  /// Stable id used in the credentials file and CLI prompts.
  String get id;

  /// Default model used when none is configured.
  String get defaultModel;

  /// Env var checked before the credentials file (e.g. `ANTHROPIC_API_KEY`).
  String get envVarName;

  /// Produce a [ProjectPlan] from the user's questionnaire answers.
  ///
  /// [assets] are reference images (Figma exports, screenshots, mockups).
  /// When non-empty the provider switches to its multimodal path; text-only
  /// providers (currently Grok) throw a clear [UnimplementedError].
  Future<ProjectPlan> plan({
    required String apiKey,
    required String model,
    required String scale,
    required String budget,
    required String featuresBrief,
    required String stateMgmt,
    required String designBrief,
    List<DesignAsset> assets = const [],
  });

  /// Rewrite a single feature screen to match a reference design.
  ///
  /// Returns the screen file plus zero-or-more extracted widget files
  /// (see [ImplementResult]). The caller writes them to disk and is
  /// responsible for backing up the originals. Providers without vision
  /// support throw [UnimplementedError].
  Future<ImplementResult> generateCode({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required List<DesignAsset> assets,
  });

  /// Dispatch by id. Throws [ArgumentError] for unknown ids and
  /// [UnimplementedError] for ids whose provider file hasn't landed yet.
  static AiProvider forId(String id) {
    switch (id) {
      case 'claude':
        return ClaudeProvider();
      case 'openai':
        return OpenAiProvider();
      case 'gemini':
        return GeminiProvider();
      case 'grok':
        return GrokProvider();
    }
    if (!supportedProviderIds.contains(id)) {
      throw ArgumentError('Unknown provider: $id');
    }
    throw UnimplementedError(
      'Provider "$id" not wired yet. Implement AiProvider in '
      'lib/services/ai/${id}_provider.dart and dispatch it here.',
    );
  }
}

/// Builds the system + user prompts shared across all providers, and
/// parses the JSON response. Impls only handle transport.
class PlanPromptBuilder {
  static const _systemBase =
      'You output ONLY valid JSON. No markdown, no commentary. '
      'You plan a feature-based Flutter Clean Architecture project.';

  /// System prompt = transport rules + the flutter-frontend design skill.
  /// The skill steers the AI toward bold, distinctive theme + font choices.
  static String get system =>
      '$_systemBase\n\n--- DESIGN SKILL ---\n${flutterFrontendSkill.body}';

  static String user({
    required String scale,
    required String budget,
    required String featuresBrief,
    required String stateMgmt,
    required String designBrief,
    List<DesignAsset> assets = const [],
  }) {
    final maxFeatures = {'small': 3, 'medium': 8, 'complex': 15}[scale] ?? 8;
    final depPolicy = budget == 'high'
        ? 'Best-in-class packages allowed even if heavier.'
        : 'Lightweight, popular, well-maintained packages only.';

    final designSection = assets.isEmpty
        ? ''
        : '''

Reference designs attached (${assets.length}): ${assets.map((a) => a.label).join(', ')}.
Analyze every attached image. Derive `visual_language`, `seed_color`,
`display_font`, and `body_font` directly from what you see.

Feature selection — designs are primary, the brief is additive:
- Include a feature for every distinct screen in the designs (e.g. a
  login screen → "auth", a feed screen → "feed").
- ALSO include any features named in the brief above, even if no
  screen shows them yet (they will be scaffolded as stubs).
- Do NOT invent features absent from both the designs and the brief.
''';

    return '''
Plan a Flutter project.
State management: $stateMgmt
Scale: $scale   Budget: $budget
Design brief: $designBrief
Feature request (plain English): $featuresBrief
$designSection
Rules:
- Max $maxFeatures features.
- Feature names MUST be snake_case, lowercase, start with a letter (regex ^[a-z][a-z0-9_]*\$).
- $depPolicy
- Suggest only extra packages NOT already implied by the state management choice, Dio, or google_fonts.
- Apply the design skill: pick a definitive `visual_language` (e.g. brutalist, editorial, hyper-minimalist, retro-tech), a confident `seed_color`, and a pair of google_fonts families — an expressive `display_font` and a clean `body_font`. Do NOT default to safe choices like Roboto or Space Grotesk for every project.

Return EXACTLY this JSON shape (no extra keys, no markdown):
{
  "features": ["auth", "home"],
  "extra_packages": ["shared_preferences"],
  "theme_mode": "light",
  "seed_color": "#RRGGBB",
  "visual_language": "editorial",
  "display_font": "Fraunces",
  "body_font": "Inter"
}
''';
  }

  /// Strip ```json fences, parse, and filter features through the same
  /// regex `generateFeature` uses so invalid names never reach disk.
  static ProjectPlan parse(String text) {
    final cleaned = text.replaceAll(RegExp(r'```json|```'), '').trim();
    final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    final raw = ProjectPlan.fromJson(parsed);

    final valid = RegExp(r'^[a-z][a-z0-9_]*$');
    final safe = <String>[];
    for (final f in raw.features) {
      final n = f.trim();
      if (valid.hasMatch(n) && !safe.contains(n)) safe.add(n);
    }
    return ProjectPlan(
      features: safe,
      extraPackages: raw.extraPackages,
      themeMode: raw.themeMode,
      seedColorHex: raw.seedColorHex,
      visualLanguage: raw.visualLanguage,
      displayFont: raw.displayFont,
      bodyFont: raw.bodyFont,
    );
  }
}

/// One Dart file the AI returned — either the main screen or an
/// extracted widget. The command layer is responsible for translating
/// [filename] into an absolute path under the feature directory.
class GeneratedFile {
  final String filename; // snake_case, e.g. `phone_input_field.dart`
  final String code;
  GeneratedFile({required this.filename, required this.code});
}

/// Result of `AiProvider.generateCode`. [screen] always present;
/// [widgets] is empty when the screen fits under the 150-line cap.
class ImplementResult {
  final String screen;
  final List<GeneratedFile> widgets;
  ImplementResult({required this.screen, required this.widgets});
}

/// Builds the system + user prompts for `sm ai implement <project> <feature>`.
///
/// The system prompt embeds the flutter-frontend skill — same skill the
/// planner uses — plus strict output rules so the response is a JSON
/// object containing one screen file and zero-or-more extracted widget
/// files. The design skill enforces the ~150-line cap that drives the
/// split.
class ImplementPromptBuilder {
  static String get system => '''
You are a senior Flutter engineer. You output ONLY valid JSON. No
markdown, no triple backticks, no commentary before or after.

Output JSON shape:
{
  "screen": "<complete Dart file source for the screen>",
  "widgets": [
    {"filename": "phone_input_field.dart", "code": "<complete Dart file>"},
    {"filename": "social_login_button.dart", "code": "<complete Dart file>"}
  ]
}

Hard constraints (apply to every emitted file):
- The screen's root widget must be a `Scaffold`.
- Use colors from `AppTheme` (e.g. `AppTheme.seedColor`,
  `Theme.of(context).colorScheme.*`). Never hardcode hex values.
- Use typography from `Theme.of(context).textTheme.*`. Never instantiate
  `TextStyle(fontFamily: ...)` directly — the theme already wires
  GoogleFonts.
- Preserve the screen class name and any route signature exposed to the
  rest of the app. The screen file must `import` each extracted widget
  with a relative path: `import '../widgets/<filename>';`.
- Match the attached reference design as closely as Flutter allows.
- Do not add packages. Only use what is already imported plus
  `package:flutter/material.dart` and the project's own files.

Design-only rewrite (CRITICAL):
- This prompt rebuilds the UI. It is NOT a feature implementation.
- Do NOT declare any new state-management class. Forbidden patterns
  include `class X with ChangeNotifier`, `class X extends Cubit<...>`,
  `class X extends Bloc<...>`, `class X extends GetxController`,
  `class X extends StateNotifier<...>`, `class X extends Notifier<...>`,
  `class X extends AsyncNotifier<...>`, and Riverpod
  `ChangeNotifierProvider`/`StateNotifierProvider` declarations.
- Do NOT include data-layer code: no API calls, no repositories, no
  use cases, no model classes, no persistence. Render only.
- If the existing screen file references an existing
  Provider/Bloc/Cubit/Controller/Notifier, REFERENCE it (watch / build
  with it). Don't redeclare it.
- Purely visual, screen-local state MAY use a `StatefulWidget` with
  `setState` (password obscurity toggle, tab index, carousel page,
  expand/collapse). Use this sparingly and only when no external state
  is involved.
- For interactions you can't render without business logic (a submit
  button, a network refresh), wire the callback to `() {}` and add a
  single-line `// TODO: hook up <foo>`. Do not invent the logic.

File-split rule (from the design skill):
- Keep every emitted file under ~150 lines.
- Extract focused, reusable widgets into the `widgets` array whenever
  the screen would exceed that cap. Each extracted widget is a public
  top-level class in its own file, snake_case filename matching the
  class name. No business logic inside — props in, callbacks out.

--- DESIGN SKILL ---
${flutterFrontendSkill.body}
''';

  static String user({
    required String featureName,
    required String stateMgmt,
    required String currentFile,
    required String appTheme,
  }) {
    final smHint = switch (stateMgmt) {
      'Riverpod' =>
        'State management: Riverpod is already wired by the project. '
            'If the existing screen reads a Notifier/Provider, watch it via '
            '`ref.watch(...)`. Do NOT declare new providers, notifiers, or '
            'AsyncNotifiers in this file.',
      'Bloc' =>
        'State management: Bloc is already wired by the project. If the '
            'existing screen reads a Bloc/Cubit, render via '
            '`BlocBuilder<TheBloc, TheState>`. Do NOT declare new Bloc or '
            'Cubit classes in this file.',
      'GetX' =>
        'State management: GetX is already wired by the project. If the '
            'existing screen uses a Controller, reference it via '
            '`GetView<TheController>` or `Obx(...)`. Do NOT declare new '
            '`GetxController` classes in this file.',
      _ =>
        'State management: Provider is already wired by the project. If '
            'the existing screen consumes a ChangeNotifier, render via '
            '`Consumer<TheProvider>` or `context.watch<TheProvider>()`. Do '
            'NOT declare new `ChangeNotifier` classes in this file — purely '
            'visual local state goes in a `StatefulWidget` + `setState`.',
    };

    return '''
Rebuild the `$featureName` feature's screen to match the attached design.

$smHint

--- CURRENT SCREEN FILE ---
$currentFile

--- APP THEME (for reference; do NOT modify, just read tokens) ---
$appTheme

Return the JSON object described in the system prompt. Nothing else.
''';
  }

  /// Parse the provider's response into an [ImplementResult]. Strips any
  /// stray markdown fences first, then validates the JSON shape.
  /// Filenames are forced through a `snake_case.dart` regex so a
  /// hallucinated path can never escape the widgets directory.
  static ImplementResult parse(String text) {
    var t = text.trim();
    t = t.replaceFirst(RegExp(r'^```(?:json)?\s*\n?'), '');
    t = t.replaceFirst(RegExp(r'\n?```\s*$'), '');
    final json = jsonDecode(t.trim()) as Map<String, dynamic>;

    final screen = (json['screen'] as String? ?? '').trim();
    if (screen.isEmpty) {
      throw FormatException('Missing "screen" in AI response');
    }

    final filenameRe = RegExp(r'^[a-z][a-z0-9_]*\.dart$');
    final widgets = <GeneratedFile>[];
    final rawWidgets = (json['widgets'] as List? ?? const []);
    for (final w in rawWidgets) {
      if (w is! Map) continue;
      final filename = (w['filename'] as String? ?? '').trim();
      final code = (w['code'] as String? ?? '').trim();
      if (filename.isEmpty || code.isEmpty) continue;
      if (!filenameRe.hasMatch(filename)) continue;
      widgets.add(GeneratedFile(filename: filename, code: code));
    }

    return ImplementResult(screen: screen, widgets: widgets);
  }
}
