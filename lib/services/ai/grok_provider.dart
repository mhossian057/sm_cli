import 'dart:convert';
import 'package:http/http.dart' as http;

import 'ai_provider.dart';

/// xAI Grok impl. OpenAI-compatible chat completions API — only the
/// endpoint, env var, and default model differ from [OpenAiProvider].
/// See https://docs.x.ai/api
class GrokProvider extends AiProvider {
  @override
  String get id => 'grok';

  @override
  String get defaultModel => 'grok-3-mini';

  @override
  String get envVarName => 'XAI_API_KEY';

  static const _endpoint = 'https://api.x.ai/v1/chat/completions';

  @override
  Future<ProjectPlan> plan({
    required String apiKey,
    required String model,
    required String scale,
    required String budget,
    required String featuresBrief,
    required String stateMgmt,
    required String designBrief,
    List<DesignAsset> assets = const [],
  }) async {
    if (assets.isNotEmpty) {
      throw UnimplementedError(
        'Grok vision is not wired up. Re-run without --design / --figma, '
        'or switch provider with `sm ai config` (Claude/OpenAI/Gemini all '
        'accept reference images).',
      );
    }
    final http.Response res;
    try {
      res = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'max_tokens': 1024,
          'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'system', 'content': PlanPromptBuilder.system},
            {
              'role': 'user',
              'content': PlanPromptBuilder.user(
                scale: scale,
                budget: budget,
                featuresBrief: featuresBrief,
                stateMgmt: stateMgmt,
                designBrief: designBrief,
              ),
            },
          ],
        }),
      ).timeout(const Duration(seconds: 60));
    } on Exception catch (e) {
      throw Exception('Could not reach Grok API: $e');
    }

    if (res.statusCode != 200) {
      throw Exception('Grok request failed (${res.statusCode}): ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = body['choices'] as List? ?? const [];
    if (choices.isEmpty) {
      throw Exception('Grok returned no choices:\n${res.body}');
    }
    final text = ((choices.first as Map)['message'] as Map)['content']
            as String? ??
        '';

    try {
      return PlanPromptBuilder.parse(text);
    } on FormatException catch (e) {
      throw Exception('Grok did not return valid JSON: $e\nGot:\n$text');
    }
  }

  @override
  Future<ImplementResult> generateCode({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required List<DesignAsset> assets,
  }) async {
    throw UnimplementedError(
      'Grok vision is not wired up. `sm ai implement` requires a vision-'
      'capable provider — switch via `sm ai config` to Claude, OpenAI, '
      'or Gemini.',
    );
  }
}
