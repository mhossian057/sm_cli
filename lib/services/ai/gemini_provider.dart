import 'dart:convert';
import 'package:http/http.dart' as http;

import 'ai_provider.dart';

/// Google Gemini `generateContent` impl.
/// See https://ai.google.dev/api/generate-content
class GeminiProvider extends AiProvider {
  @override
  String get id => 'gemini';

  @override
  String get defaultModel => 'gemini-2.5-flash';

  @override
  String get envVarName => 'GEMINI_API_KEY';

  static const _base = 'https://generativelanguage.googleapis.com/v1beta/models';

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
    final url = Uri.parse('$_base/$model:generateContent');
    final http.Response res;
    try {
      res = await http.post(
        url,
        headers: {
          'content-type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: jsonEncode({
          'system_instruction': {
            'parts': [
              {'text': PlanPromptBuilder.system},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'text': PlanPromptBuilder.user(
                    scale: scale,
                    budget: budget,
                    featuresBrief: featuresBrief,
                    stateMgmt: stateMgmt,
                    designBrief: designBrief,
                  ),
                },
              ],
            },
          ],
          'generationConfig': {
            // Forces well-formed JSON output (no markdown fences).
            'responseMimeType': 'application/json',
            'maxOutputTokens': 2048,
            // Gemini 2.5 is a thinking model; thinking tokens count toward
            // maxOutputTokens and can truncate the JSON. Disable for this
            // structured-output task.
            'thinkingConfig': {'thinkingBudget': 0},
          },
        }),
      ).timeout(const Duration(seconds: 60));
    } on Exception catch (e) {
      throw Exception('Could not reach Gemini API: $e');
    }

    if (res.statusCode != 200) {
      throw Exception('Gemini request failed (${res.statusCode}): ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = body['candidates'] as List? ?? const [];
    if (candidates.isEmpty) {
      throw Exception('Gemini returned no candidates:\n${res.body}');
    }
    final candidate = candidates.first as Map;
    final finishReason = candidate['finishReason'] as String?;
    final parts = (candidate['content'] as Map?)?['parts'] as List? ?? const [];
    final text = parts
        .map((p) => (p as Map)['text'] as String? ?? '')
        .join('\n');

    if (finishReason == 'MAX_TOKENS') {
      throw Exception(
        'Gemini hit maxOutputTokens before finishing the JSON. '
        'Raise maxOutputTokens or disable thinking.\nPartial output:\n$text',
      );
    }

    try {
      return PlanPromptBuilder.parse(text);
    } on FormatException catch (e) {
      throw Exception('Gemini did not return valid JSON: $e\nGot:\n$text');
    }
  }
}
