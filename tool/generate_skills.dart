// Build-time generator: reads every `skills/*.md`, strips YAML frontmatter,
// and emits `lib/services/ai/skills.g.dart` with one const per skill plus a
// map keyed by skill name. Re-run after editing any skill markdown:
//
//   dart run tool/generate_skills.dart
//
// The generated file is checked in so `pub global activate` users get the
// skills without needing to read from disk at runtime.

import 'dart:io';

const _skillsDir = 'skills';
const _outputPath = 'lib/services/ai/skills.g.dart';

void main() {
  final dir = Directory(_skillsDir);
  if (!dir.existsSync()) {
    stderr.writeln('No $_skillsDir directory found.');
    exit(1);
  }

  final entries = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final buf = StringBuffer()
    ..writeln('// GENERATED FILE. Do not edit by hand.')
    ..writeln('// Run: dart run tool/generate_skills.dart')
    ..writeln('// ignore_for_file: constant_identifier_names')
    ..writeln()
    ..writeln('class Skill {')
    ..writeln('  final String name;')
    ..writeln('  final String description;')
    ..writeln('  final String body;')
    ..writeln('  const Skill({')
    ..writeln('    required this.name,')
    ..writeln('    required this.description,')
    ..writeln('    required this.body,')
    ..writeln('  });')
    ..writeln('}')
    ..writeln();

  final mapEntries = <String>[];
  for (final file in entries) {
    final raw = file.readAsStringSync();
    final parsed = _parse(raw);
    final identifier = _toIdentifier(parsed.name);
    mapEntries.add('  ${_inlineString(parsed.name)}: $identifier,');

    buf
      ..writeln('const $identifier = Skill(')
      ..writeln('  name: ${_inlineString(parsed.name)},')
      ..writeln('  description: ${_inlineString(parsed.description)},')
      ..writeln('  body: ${_blockString(parsed.body)},')
      ..writeln(');')
      ..writeln();
  }

  buf
    ..writeln('const Map<String, Skill> skillsByName = {')
    ..writeAll(mapEntries.map((e) => '$e\n'))
    ..writeln('};');

  File(_outputPath).writeAsStringSync(buf.toString());
  stdout.writeln('Wrote $_outputPath (${entries.length} skill(s))');
}

class _ParsedSkill {
  final String name;
  final String description;
  final String body;
  _ParsedSkill(this.name, this.description, this.body);
}

_ParsedSkill _parse(String raw) {
  var name = '';
  var description = '';
  var body = raw;

  final fm = RegExp(r'^---\s*\n(.*?)\n---\s*\n', dotAll: true).firstMatch(raw);
  if (fm != null) {
    final frontmatter = fm.group(1)!;
    for (final line in frontmatter.split('\n')) {
      final idx = line.indexOf(':');
      if (idx < 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key == 'name') name = value;
      if (key == 'description') description = value;
    }
    body = raw.substring(fm.end);
  }

  return _ParsedSkill(name, description, body.trim());
}

String _toIdentifier(String name) {
  // Convert `flutter-frontend` → `flutterFrontendSkill` (lowerCamelCase).
  final parts = name
      .split(RegExp(r'[^a-zA-Z0-9]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'skill';
  final head = parts.first.toLowerCase();
  final tail = parts
      .skip(1)
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .join();
  return '$head${tail}Skill';
}

String _inlineString(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

String _blockString(String s) {
  // Raw triple-quoted preserves the markdown verbatim. Falls back to escaped
  // when the body contains either `'''` or a `$` that Dart would interpolate.
  if (!s.contains("'''") && !s.contains(r'$')) {
    return "r'''\n$s\n'''";
  }
  return _inlineString(s);
}
