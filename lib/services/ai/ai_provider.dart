import 'dart:convert';

import 'claude_provider.dart';
import 'gemini_provider.dart';
import 'grok_provider.dart';
import 'openai_provider.dart';

/// AI-generated scaffolding plan. Maps onto the existing generators:
/// `features` → `generateFeature`, `extraPackages` → `flutter pub add`.
class ProjectPlan {
  final List<String> features;
  final List<String> extraPackages;
  final String themeMode;     // 'light' | 'dark' | 'system'
  final String seedColorHex;  // '#RRGGBB'

  ProjectPlan({
    required this.features,
    required this.extraPackages,
    required this.themeMode,
    required this.seedColorHex,
  });

  factory ProjectPlan.fromJson(Map<String, dynamic> j) {
    return ProjectPlan(
      features: (j['features'] as List? ?? const []).cast<String>(),
      extraPackages: (j['extra_packages'] as List? ?? const []).cast<String>(),
      themeMode: j['theme_mode'] as String? ?? 'system',
      seedColorHex: j['seed_color'] as String? ?? '#2196F3',
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
  Future<ProjectPlan> plan({
    required String apiKey,
    required String model,
    required String scale,
    required String budget,
    required String featuresBrief,
    required String stateMgmt,
    required String designBrief,
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
  static const system =
      'You output ONLY valid JSON. No markdown, no commentary. '
      'You plan a feature-based Flutter Clean Architecture project.';

  static String user({
    required String scale,
    required String budget,
    required String featuresBrief,
    required String stateMgmt,
    required String designBrief,
  }) {
    final maxFeatures = {'small': 3, 'medium': 8, 'complex': 15}[scale] ?? 8;
    final depPolicy = budget == 'high'
        ? 'Best-in-class packages allowed even if heavier.'
        : 'Lightweight, popular, well-maintained packages only.';

    return '''
Plan a Flutter project.
State management: $stateMgmt
Scale: $scale   Budget: $budget
Design brief: $designBrief
Feature request (plain English): $featuresBrief

Rules:
- Max $maxFeatures features.
- Feature names MUST be snake_case, lowercase, start with a letter (regex ^[a-z][a-z0-9_]*\$).
- $depPolicy
- Suggest only extra packages NOT already implied by the state management choice or Dio.

Return EXACTLY this JSON shape:
{
  "features": ["auth", "home"],
  "extra_packages": ["shared_preferences"],
  "theme_mode": "light",
  "seed_color": "#RRGGBB"
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
    );
  }
}
