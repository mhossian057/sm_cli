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
    List<DesignAsset> assets = const [],
  }) async {
    final url = Uri.parse('$_base/$model:generateContent');

    // Gemini vision: a `parts` array combining `inlineData` (base64 image)
    // and `text` entries. Order doesn't matter; we put text last so the
    // model sees the references before the instructions.
    final requestParts = <Map<String, dynamic>>[
      for (final a in assets)
        {
          'inlineData': {'mimeType': a.mimeType, 'data': a.base64Data},
        },
      {
        'text': PlanPromptBuilder.user(
          scale: scale,
          budget: budget,
          featuresBrief: featuresBrief,
          stateMgmt: stateMgmt,
          designBrief: designBrief,
          assets: assets,
        ),
      },
    ];

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
            {'role': 'user', 'parts': requestParts},
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
      ).timeout(const Duration(seconds: 90));
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

  @override
  Future<ImplementResult> generateCode({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required List<DesignAsset> assets,
  }) async {
    if (assets.isEmpty) {
      throw ArgumentError('generateCode requires at least one DesignAsset.');
    }
    final url = Uri.parse('$_base/$model:generateContent');
    final requestParts = <Map<String, dynamic>>[
      for (final a in assets)
        {
          'inlineData': {'mimeType': a.mimeType, 'data': a.base64Data},
        },
      {'text': userPrompt},
    ];

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
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {'role': 'user', 'parts': requestParts},
          ],
          'generationConfig': {
            // JSON output now — {screen, widgets[]}.
            'responseMimeType': 'application/json',
            'maxOutputTokens': 8192,
            'thinkingConfig': {'thinkingBudget': 0},
          },
        }),
      ).timeout(const Duration(seconds: 180));
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
        'Gemini hit maxOutputTokens before finishing the code. '
        'Retry on a smaller screen or raise maxOutputTokens.\n'
        'Partial output:\n$text',
      );
    }
    try {
      return ImplementPromptBuilder.parse(text);
    } on FormatException catch (e) {
      throw Exception('Gemini did not return valid JSON: $e\nGot:\n$text');
    }
  }
}
