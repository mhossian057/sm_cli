import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Plan the AI returns. Maps directly onto the existing generators.
///
/// The AI does NOT write file contents — it only expands the user's
/// free-text answers into a structured plan that drives `initProject`
/// and `generateFeature`.
class ProjectPlan {
  /// snake_case feature names, fed one-by-one to `generateFeature`.
  final List<String> features;

  /// Packages to add on top of the state-management + Dio defaults.
  final List<String> extraPackages;

  /// 'light' | 'dark' | 'system'. Surfaced to the user; theme wiring
  /// is parameterized in Phase 2.
  final String themeMode;

  /// '#RRGGBB' seed color suggestion (Phase 2 theme parameterization).
  final String seedColorHex;

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

/// Talks to the Anthropic Messages API to produce a [ProjectPlan].
class AiService {
  // TODO: set to the current model string.
  // Check https://docs.claude.com/en/docs/about-claude/models
  static const _model = 'claude-sonnet-4-5';

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  /// Reads ANTHROPIC_API_KEY from the environment. Returns null if missing.
  static String? get _apiKey => Platform.environment['ANTHROPIC_API_KEY'];

  static Future<ProjectPlan> plan({
    required String scale,
    required String budget,
    required String featuresBrief,
    required String stateMgmt,
    required String designBrief,
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      throw Exception(
        'ANTHROPIC_API_KEY not set. Export it before running `sm ai`:\n'
        '   export ANTHROPIC_API_KEY="sk-ant-..."',
      );
    }

    final maxFeatures = {'small': 3, 'medium': 8, 'complex': 15}[scale] ?? 8;
    final depPolicy = budget == 'high'
        ? 'Best-in-class packages allowed even if heavier.'
        : 'Lightweight, popular, well-maintained packages only.';

    final system = 'You output ONLY valid JSON. No markdown, no commentary. '
        'You plan a feature-based Flutter Clean Architecture project.';

    final user = '''
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

    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 1024,
              'system': system,
              'messages': [
                {'role': 'user', 'content': user},
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));
    } on Exception catch (e) {
      throw Exception('Could not reach the AI API: $e');
    }

    if (res.statusCode != 200) {
      throw Exception('AI request failed (${res.statusCode}): ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final text = (body['content'] as List)
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join('\n');

    final cleaned = text.replaceAll(RegExp(r'```json|```'), '').trim();

    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw Exception('AI did not return valid JSON: $e\nGot:\n$cleaned');
    }

    final plan = ProjectPlan.fromJson(parsed);

    // Defensive: drop anything the AI got wrong so generateFeature() won't
    // reject it (it validates with the same regex and aborts otherwise).
    final valid = RegExp(r'^[a-z][a-z0-9_]*$');
    final safeFeatures = <String>[];
    for (final f in plan.features) {
      final name = f.trim();
      if (valid.hasMatch(name) && !safeFeatures.contains(name)) {
        safeFeatures.add(name);
      }
    }

    return ProjectPlan(
      features: safeFeatures,
      extraPackages: plan.extraPackages,
      themeMode: plan.themeMode,
      seedColorHex: plan.seedColorHex,
    );
  }
}
