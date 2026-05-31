import 'package:args/args.dart';
import 'package:interact/interact.dart';

import '../services/ai/ai_provider.dart';
import '../services/ai/credential_service.dart';
import '../services/prompt_service.dart';

/// `sm ai config [--list|--reset]`
///
/// With no flag: interactive menu (set key / change default / change model /
/// remove provider / reset / list).
Future<void> runAiConfig(ArgResults args) async {
  if (args['list'] as bool) {
    _printList();
    return;
  }
  if (args['reset'] as bool) {
    _reset();
    return;
  }
  await _interactiveMenu();
}

void _printList() {
  final configured = CredentialService.configuredProviders();
  if (configured.isEmpty) {
    print('No providers configured.');
    print('   Run `sm ai <project>` to set one up.');
    return;
  }
  final defaultProvider = CredentialService.getDefaultProvider();
  print('📁 ${CredentialService.path}');
  for (final id in configured) {
    final creds = CredentialService.get(id)!;
    final label = providerLabels[id] ?? id;
    final star = id == defaultProvider ? ' (default)' : '';
    print('  $label$star');
    print('    key   : ${CredentialService.mask(creds.apiKey)}');
    print('    model : ${creds.model ?? _safeDefaultModel(id) ?? '—'}');
  }
}

void _reset() {
  final go = Confirm(
    prompt: 'Wipe all stored AI credentials?',
    defaultValue: false,
  ).interact();
  if (!go) {
    print('Aborted.');
    return;
  }
  CredentialService.clearAll();
  print('✅ Cleared.');
}

Future<void> _interactiveMenu() async {
  const actions = [
    'List configured providers',
    'Set / update an API key',
    'Change default provider',
    'Change model for a provider',
    'Remove a provider',
    'Reset all credentials',
    'Exit',
  ];
  final i = Select(prompt: 'AI config', options: actions).interact();
  switch (i) {
    case 0:
      _printList();
      return;
    case 1:
      await _setKey();
      return;
    case 2:
      _setDefault();
      return;
    case 3:
      _setModel();
      return;
    case 4:
      _removeProvider();
      return;
    case 5:
      _reset();
      return;
    case 6:
      return;
  }
}

Future<void> _setKey() async {
  final providerId = selectProvider();
  final label = providerLabels[providerId] ?? providerId;
  final key = askApiKey(label);
  if (key.trim().isEmpty) {
    print('❌ Empty key. Aborted.');
    return;
  }
  final existing = CredentialService.get(providerId);
  CredentialService.set(
    providerId,
    ProviderCredentials(apiKey: key, model: existing?.model),
  );
  if (CredentialService.getDefaultProvider() == null) {
    CredentialService.setDefaultProvider(providerId);
  }
  print('🔐 Saved $label key.');
}

void _setDefault() {
  final configured = CredentialService.configuredProviders();
  if (configured.isEmpty) {
    print('No providers configured yet.');
    return;
  }
  final labels =
      configured.map((id) => providerLabels[id] ?? id).toList();
  final i = Select(prompt: 'Default provider', options: labels).interact();
  CredentialService.setDefaultProvider(configured[i]);
  print('✅ Default set to ${labels[i]}.');
}

void _setModel() {
  final configured = CredentialService.configuredProviders();
  if (configured.isEmpty) {
    print('No providers configured yet.');
    return;
  }
  final labels =
      configured.map((id) => providerLabels[id] ?? id).toList();
  final i = Select(prompt: 'Which provider?', options: labels).interact();
  final providerId = configured[i];
  final creds = CredentialService.get(providerId)!;
  final defaultModel = _safeDefaultModel(providerId);
  final current = creds.model ?? defaultModel ?? '';

  final entered = Input(
    prompt: 'Model (blank = default${defaultModel != null ? ' "$defaultModel"' : ''})',
    defaultValue: current,
  ).interact().trim();

  CredentialService.set(
    providerId,
    ProviderCredentials(
      apiKey: creds.apiKey,
      // Blank or matching the default → clear it so future default
      // changes are picked up automatically.
      model: (entered.isEmpty || entered == defaultModel) ? null : entered,
    ),
  );
  print('✅ Model updated.');
}

void _removeProvider() {
  final configured = CredentialService.configuredProviders();
  if (configured.isEmpty) {
    print('No providers configured.');
    return;
  }
  final labels =
      configured.map((id) => providerLabels[id] ?? id).toList();
  final i =
      Select(prompt: 'Remove which provider?', options: labels).interact();
  final go = Confirm(
    prompt: 'Remove ${labels[i]}?',
    defaultValue: false,
  ).interact();
  if (!go) return;
  CredentialService.clear(configured[i]);
  print('✅ Removed.');
}

/// `AiProvider.forId` throws for unwired ids — wrap so config flows
/// keep working as new providers come online.
String? _safeDefaultModel(String id) {
  try {
    return AiProvider.forId(id).defaultModel;
  } on UnimplementedError {
    return null;
  }
}
