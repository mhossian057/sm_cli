import 'dart:convert';
import 'package:http/http.dart' as http;

import 'ai_provider.dart';

/// OpenAI Chat Completions impl.
/// See https://platform.openai.com/docs/api-reference/chat
class OpenAiProvider extends AiProvider {
  @override
  String get id => 'openai';

  @override
  String get defaultModel => 'gpt-4o-mini';

  @override
  String get envVarName => 'OPENAI_API_KEY';

  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  @override
  Future<ProjectPlan> plan({
    required String apiKey,
    required String model,
    required String scale,
    required String budget,
    required String featuresBrief,
    required String stateMgmt,
    required String designBrief,
  }) async {
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
          // Forces well-formed JSON output. Requires the word "JSON"
          // somewhere in the prompt — PlanPromptBuilder.system has it.
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
      throw Exception('Could not reach OpenAI API: $e');
    }

    if (res.statusCode != 200) {
      throw Exception('OpenAI request failed (${res.statusCode}): ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = body['choices'] as List? ?? const [];
    if (choices.isEmpty) {
      throw Exception('OpenAI returned no choices:\n${res.body}');
    }
    final text = ((choices.first as Map)['message'] as Map)['content']
            as String? ??
        '';

    try {
      return PlanPromptBuilder.parse(text);
    } on FormatException catch (e) {
      throw Exception('OpenAI did not return valid JSON: $e\nGot:\n$text');
    }
  }
}
