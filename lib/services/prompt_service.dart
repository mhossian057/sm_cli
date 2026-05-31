import 'package:interact/interact.dart';

import 'ai/ai_provider.dart';

/// Prompts user to select state management interactively.
///
/// Returns one of: `'Riverpod'`, `'Bloc'`, `'GetX'`, `'Provider'`

String selectStateManagement() {
  final options = [
    'Riverpod',
    'Bloc',
    'GetX',
    'Provider',
  ];

  final selected = Select(
    prompt: 'Select State Management',
    options: options,
  ).interact();

  return options[selected];
}
/// Prompts user to enable GoRouter.

bool enableGoRouter() {
  return Confirm(
    prompt: 'Enable GoRouter?',
    defaultValue: true,
  ).interact();
}
/// Prompts user to enable Theme setup.

bool enableTheme() {
  return Confirm(
    prompt: 'Enable Theme?',
    defaultValue: true,
  ).interact();
}
// ---- AI questionnaire additions ----

/// Q1: project type / scale. Returns: 'small' | 'medium' | 'complex'.
String selectProjectScale() {
  final options = [
    'Small (MVP, 1-3 features)',
    'Medium (5-8 features)',
    'Complex (modular, many features)',
  ];
  final i = Select(prompt: 'Project type?', options: options).interact();
  return ['small', 'medium', 'complex'][i];
}

/// Q2: project cost / budget — controls scope. Returns: 'low' | 'medium' | 'high'.
String selectProjectBudget() {
  final i = Select(
    prompt: 'Project cost / budget?',
    options: ['Low', 'Medium', 'High'],
  ).interact();
  return ['low', 'medium', 'high'][i];
}

/// Q3: free-text features (AI cleans these into snake_case names).
String askFeaturesBrief() {
  return Input(prompt: 'Describe the features you need (plain English):')
      .interact();
}

/// Q5: design brief for theme.
String askDesignBrief() {
  return Input(prompt: 'Design style? (e.g. "Material 3, dark, teal accent")')
      .interact();
}

/// Pick AI provider. Returns the provider id (e.g. 'claude').
String selectProvider() {
  final ids = supportedProviderIds;
  final labels = ids.map((id) => providerLabels[id] ?? id).toList();
  final i = Select(prompt: 'Which AI provider?', options: labels).interact();
  return ids[i];
}

/// Prompt for an API key (masked input — won't echo to terminal).
String askApiKey(String providerLabel) {
  return Password(
    prompt: 'Enter $providerLabel API key',
    confirmation: false,
  ).interact();
}
