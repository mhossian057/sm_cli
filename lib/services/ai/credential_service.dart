import 'dart:convert';
import 'dart:io';

import 'ai_provider.dart';

/// Per-provider stored credentials.
class ProviderCredentials {
  final String apiKey;
  final String? model;

  ProviderCredentials({required this.apiKey, this.model});

  factory ProviderCredentials.fromJson(Map<String, dynamic> j) =>
      ProviderCredentials(
        apiKey: j['api_key'] as String,
        model: j['model'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'api_key': apiKey,
        if (model != null) 'model': model,
      };
}

/// Reads/writes `~/.sm_cli/credentials.json` (chmod 600 on POSIX).
///
/// This service is *pure storage* — it never prompts. The command
/// layer composes:
///   resolveKey(provider) -> if null, prompt user -> set(...)
///
/// File shape:
/// {
///   "default_provider": "claude",
///   "claude": { "api_key": "sk-ant-...", "model": "claude-sonnet-4-6" },
///   "openai": { "api_key": "sk-...",     "model": "gpt-4o" }
/// }
class CredentialService {
  static String get _home {
    final h = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (h == null) {
      throw StateError(
        'Cannot locate home directory (HOME / USERPROFILE unset).',
      );
    }
    return h;
  }

  static String get _dir => '$_home/.sm_cli';
  static String get path => '$_dir/credentials.json';

  static Map<String, dynamic> _read() {
    final f = File(path);
    if (!f.existsSync()) return <String, dynamic>{};
    try {
      return (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
    } on FormatException {
      // Corrupt file — start fresh rather than crash. Don't overwrite
      // until the caller actually sets something.
      return <String, dynamic>{};
    }
  }

  static void _write(Map<String, dynamic> data) {
    Directory(_dir).createSync(recursive: true);
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    // chmod 600 — best-effort, POSIX only.
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['600', path]);
    }
  }

  // ---- default provider ----

  static String? getDefaultProvider() =>
      _read()['default_provider'] as String?;

  static void setDefaultProvider(String id) {
    if (!supportedProviderIds.contains(id)) {
      throw ArgumentError('Unknown provider: $id');
    }
    final data = _read();
    data['default_provider'] = id;
    _write(data);
  }

  // ---- per-provider credentials ----

  static ProviderCredentials? get(String providerId) {
    final p = _read()[providerId];
    if (p is! Map) return null;
    return ProviderCredentials.fromJson(p.cast<String, dynamic>());
  }

  static void set(String providerId, ProviderCredentials creds) {
    if (!supportedProviderIds.contains(providerId)) {
      throw ArgumentError('Unknown provider: $providerId');
    }
    final data = _read();
    data[providerId] = creds.toJson();
    _write(data);
  }

  static void clear(String providerId) {
    final data = _read();
    data.remove(providerId);
    if (data['default_provider'] == providerId) {
      data.remove('default_provider');
    }
    _write(data);
  }

  /// Wipe the entire credentials file. Used by `sm ai config --reset`.
  static void clearAll() {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  /// Providers that have a stored key. Used by `sm ai config --list`.
  static List<String> configuredProviders() {
    return _read()
        .keys
        .where((k) =>
            k != 'default_provider' && supportedProviderIds.contains(k))
        .toList();
  }

  // ---- figma token (top-level, not provider-scoped) ----

  /// Env var `FIGMA_TOKEN` > stored token > null.
  static String? resolveFigmaToken() {
    final env = Platform.environment['FIGMA_TOKEN'];
    if (env != null && env.isNotEmpty) return env;
    return _read()['figma_token'] as String?;
  }

  static void setFigmaToken(String token) {
    final data = _read();
    data['figma_token'] = token;
    _write(data);
  }

  static void clearFigmaToken() {
    final data = _read();
    data.remove('figma_token');
    _write(data);
  }

  // ---- resolution ----

  /// Env var > stored credentials > null.
  /// Callers handle the null case by prompting the user.
  static String? resolveKey(AiProvider p) {
    final env = Platform.environment[p.envVarName];
    if (env != null && env.isNotEmpty) return env;
    return get(p.id)?.apiKey;
  }

  /// Env var > stored model > provider's default. Never null.
  static String resolveModel(AiProvider p) {
    return get(p.id)?.model ?? p.defaultModel;
  }

  // ---- display ----

  /// `sk-ant-…ab12` — for `sm ai config --list`. Never logs the full key.
  static String mask(String key) {
    if (key.length <= 8) return '…';
    return '${key.substring(0, 6)}…${key.substring(key.length - 4)}';
  }
}
