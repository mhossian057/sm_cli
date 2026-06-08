import 'dart:convert';
import 'package:http/http.dart' as http;

import 'ai_provider.dart';

/// Anthropic Messages API impl.
/// See https://docs.claude.com/en/api/messages
class ClaudeProvider extends AiProvider {
  @override
  String get id => 'claude';

  @override
  String get defaultModel => 'claude-sonnet-4-6';

  @override
  String get envVarName => 'ANTHROPIC_API_KEY';

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

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
    final userText = PlanPromptBuilder.user(
      scale: scale,
      budget: budget,
      featuresBrief: featuresBrief,
      stateMgmt: stateMgmt,
      designBrief: designBrief,
      assets: assets,
    );

    // Claude messages with vision: array of content blocks, images first
    // so the text below can reference them.
    final content = <Map<String, dynamic>>[
      for (final a in assets)
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': a.mimeType,
            'data': a.base64Data,
          },
        },
      {'type': 'text', 'text': userText},
    ];

    final http.Response res;
    try {
      res = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'content-type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': model,
          'max_tokens': 1024,
          'system': PlanPromptBuilder.system,
          'messages': [
            {'role': 'user', 'content': content},
          ],
        }),
      ).timeout(const Duration(seconds: 90));
    } on Exception catch (e) {
      throw Exception('Could not reach Anthropic API: $e');
    }

    if (res.statusCode != 200) {
      throw Exception('Claude request failed (${res.statusCode}): ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final text = (body['content'] as List)
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join('\n');

    try {
      return PlanPromptBuilder.parse(text);
    } on FormatException catch (e) {
      throw Exception('Claude did not return valid JSON: $e\nGot:\n$text');
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
    final content = <Map<String, dynamic>>[
      for (final a in assets)
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': a.mimeType,
            'data': a.base64Data,
          },
        },
      {'type': 'text', 'text': userPrompt},
    ];

    final http.Response res;
    try {
      res = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'content-type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': model,
          // Multi-file JSON output: 1 screen + N widgets, often ~600 lines
          // of code embedded in escaped strings. 8192 covers that headroom.
          'max_tokens': 8192,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': content},
          ],
        }),
      ).timeout(const Duration(seconds: 180));
    } on Exception catch (e) {
      throw Exception('Could not reach Anthropic API: $e');
    }

    if (res.statusCode != 200) {
      throw Exception('Claude request failed (${res.statusCode}): ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final text = (body['content'] as List)
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join('\n');
    try {
      return ImplementPromptBuilder.parse(text);
    } on FormatException catch (e) {
      throw Exception('Claude did not return valid JSON: $e\nGot:\n$text');
    }
  }
}
