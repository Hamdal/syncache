// Validates every ```dart code block in the repository READMEs.
//
// Convention (see CONTRIBUTING.md):
// - A block that starts with `import` is a **complete sample**: it is
//   analyzed verbatim and must define everything it uses.
// - Any other block is a **fragment**: it must be pure statements (no
//   top-level declarations) and is analyzed inside a generated function
//   body, preceded by the package's shared preamble (common imports plus
//   small stubs like `User` / `api` / `fetchUser`).
//
// The script writes each sample into a scratch package under
// `.dart_tool/readme_samples/` and runs `dart analyze` on it, failing on
// any error or warning. Run it from the repository root:
//
//   dart run tool/validate_readme_samples.dart
import 'dart:io';

/// One README to validate, with the stub preamble its fragments may rely on.
class _Target {
  final String readmePath;
  final String packageDir;
  final String preamble;

  const _Target(this.readmePath, this.packageDir, this.preamble);
}

void main() {
  final repoRoot = Directory.current.path;
  final scratch = Directory('$repoRoot/.dart_tool/readme_samples');
  _writeScratchPackage(scratch, repoRoot);

  final targets = [
    _Target('README.md', 'syncache', _corePreamble),
    _Target('packages/syncache/README.md', 'syncache', _corePreamble),
    _Target('packages/syncache_flutter/README.md', 'syncache_flutter',
        _flutterPreamble),
    _Target('packages/syncache_hive/README.md', 'syncache_hive', _hivePreamble),
    _Target(
        'packages/syncache_drift/README.md', 'syncache_drift', _driftPreamble),
  ];

  var totalBlocks = 0;
  var failed = false;

  for (final target in targets) {
    final file = File('$repoRoot/${target.readmePath}');
    if (!file.existsSync()) {
      stderr.writeln('SKIP (missing): ${target.readmePath}');
      continue;
    }
    final blocks = _extractDartBlocks(file.readAsStringSync());
    for (var i = 0; i < blocks.length; i++) {
      totalBlocks++;
      final name = _sampleFileName(target.readmePath, i);
      final isComplete = _startsWithImport(blocks[i]);
      final source = isComplete
          ? '${blocks[i]}\n// ignore_for_file: $_ignoredLints\n'
          : '${target.preamble}\n\nFuture<void> sample() async {\n'
              '${blocks[i]}\n}\n// ignore_for_file: $_ignoredLints\n';
      File('${scratch.path}/$name').writeAsStringSync(source);
    }
  }

  if (totalBlocks == 0) {
    stderr.writeln('No dart blocks found — nothing to validate.');
    exit(1);
  }

  stdout.writeln('Validating $totalBlocks dart sample(s)...');
  _runOrFail(const ['flutter', 'pub', 'get'], scratch, quiet: true);
  final analyze = _runOrFail(
    const ['dart', 'analyze', '--format', 'machine', '.'],
    scratch,
  );

  // Machine format lines look like:
  // SEVERITY|TYPE|CODE|file|line|col|length|message
  final problems = analyze.stdout
      .toString()
      .split('\n')
      .map((line) => line.split('|'))
      .where((parts) => parts.length >= 8)
      .where((parts) => parts.first == 'ERROR' || parts.first == 'WARNING')
      .toList();

  for (final parts in problems) {
    failed = true;
    final file = parts[3].replaceFirst('${scratch.path}/', '');
    stderr.writeln('${parts.first.toLowerCase()}: ${parts[7]}\n    in $file');
  }

  final infos = analyze.stdout
      .toString()
      .split('\n')
      .where((line) => line.startsWith('INFO|'))
      .length;
  if (infos > 0) stdout.writeln('($infos info-level diagnostic(s) ignored)');

  if (failed) {
    stderr.writeln('README sample validation FAILED.');
    exit(1);
  }
  stdout.writeln('README sample validation passed.');
}

/// Runs [command] in [cwd]; exits non-zero when the process itself fails.
/// Returns the completed process result otherwise.
ProcessResult _runOrFail(
  List<String> command,
  Directory cwd, {
  bool quiet = false,
}) {
  final result = Process.runSync(command.first, command.sublist(1),
      workingDirectory: cwd.path);
  if (result.exitCode != 0) {
    stderr.write(result.stdout);
    stderr.write(result.stderr);
    stderr.writeln('Command failed (${result.exitCode}): '
        '${command.join(' ')}');
    exit(result.exitCode);
  }
  if (!quiet) stdout.write(result.stdout);
  return result;
}

String _sampleFileName(String readmePath, int index) {
  final slug = readmePath
      .replaceAll('/', '_')
      .replaceAll('.md', '')
      .replaceAll(RegExp(r'[^a-z0-9_]', caseSensitive: false), '');
  return '${slug}_block${index.toString().padLeft(2, '0')}.dart';
}

bool _startsWithImport(String block) => RegExp(r'^\s*import\s').hasMatch(block);

/// Harness-generated code naturally has unused preamble members; samples
/// are validated for compilation (errors), not lint cleanliness.
const String _ignoredLints =
    'unused_import, unused_local_variable, unused_element, unused_field, '
    'unused_shown_name, dead_code';

/// Extracts the contents of every ```dart fenced block, in order.
List<String> _extractDartBlocks(String markdown) {
  final blocks = <String>[];
  final fence = RegExp(r'^```dart\s*$', multiLine: true);
  for (final match in fence.allMatches(markdown)) {
    final start = match.end;
    final end = markdown.indexOf('```', start);
    if (end == -1) break;
    blocks.add(markdown.substring(start, end).trim());
  }
  return blocks;
}

void _writeScratchPackage(Directory scratch, String repoRoot) {
  if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  scratch.createSync(recursive: true);

  // A Flutter package so samples may import package:flutter as well.
  File('${scratch.path}/pubspec.yaml').writeAsStringSync('''
name: readme_samples
publish_to: none
environment:
  sdk: ^3.0.0
dependencies:
  flutter:
    sdk: flutter
  syncache:
    path: $repoRoot/packages/syncache
  syncache_flutter:
    path: $repoRoot/packages/syncache_flutter
  syncache_hive:
    path: $repoRoot/packages/syncache_hive
  syncache_drift:
    path: $repoRoot/packages/syncache_drift
  hive_ce: ^2.20.2
  hive_ce_flutter: ^2.4.0
dependency_overrides:
  syncache:
    path: $repoRoot/packages/syncache
''');

  Directory('${scratch.path}/lib').createSync();
  // An (almost) empty library so `dart analyze .` has a stable entry point.
  File('${scratch.path}/lib/readme_samples.dart')
      .writeAsStringSync('library readme_samples;\n');
}

// ============================================================
// Shared preambles (stubs README fragments may reference)
// ============================================================

/// Stub types shared by the core / flutter / hive preambles.
const String _sharedStubs = '''
class User {
  final int id;
  final String name;
  const User({required this.id, required this.name});

  User copyWith({int? id, String? name}) =>
      User(id: id ?? this.id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static User fromJson(Map<String, dynamic> json) =>
      User(id: json['id'] as int, name: json['name'] as String);
}

class Post {
  final int id;
  final String title;
  const Post({required this.id, required this.title});
}

final api = Api();
final analytics = Analytics();

class Api {
  Future<User> getUser(int id) async => User(id: id, name: 'User \$id');
  Future<User> updateUser(User user) async => user;
  Future<List<Post>> getPosts() async => const [Post(id: 1, title: 't')];
}

final fetchUser = (_) async => const User(id: 1, name: 'User');
final fetchUser1 = (_) async => const User(id: 1, name: 'User');
final fetchUser2 = (_) async => const User(id: 2, name: 'User');
final fetchUser3 = (_) async => const User(id: 3, name: 'User');
final fetchPosts = (_) async => const <Post>[Post(id: 1, title: 't')];
final fetchConfig = (_) async => 'config';
final fetchEvents = (_) async => 'events';

class Analytics {
  void track(String event, Map<String, Object?> properties) {}
}
''';

const String _corePreamble = '''
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';
import 'package:syncache_hive/syncache_hive.dart';

$_sharedStubs

late final Syncache<User> cache;
late final Syncache<User> userCache;
late final HiveStore<User> store;
var user = const User(id: 123, name: 'Old Name');
final mutation = Mutation<User>(apply: (u) => u, send: (u) async => u);
void showSyncBanner(bool visible) {}

class Connectivity {
  bool get hasConnection => true;
}

class MyApp extends StatelessWidget {
  const MyApp();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<Mutation<User>> resolvePending(PendingMutationRecord record) async {
  return Mutation<User>(apply: (u) => u, send: (u) async => u);
}
''';

const String _flutterPreamble = '''
import 'package:flutter/material.dart';
import 'package:syncache/syncache.dart';
import 'package:syncache_flutter/syncache_flutter.dart';

$_sharedStubs

late final Syncache<User> cache;
late final Syncache<User> userCache;
late final Syncache<Post> postCache;
late final Syncache<Settings> settingsCache;
late final FlutterNetwork flutterNetwork;
late final FlutterNetwork network;
late final User cachedUser;
final logger = Logger();

class Settings {}

class Logger {
  void warning(String message) {}
}

class MyApp extends StatelessWidget {
  const MyApp();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

late final BuildContext context;
void showSyncBanner(bool visible) {}
void showStaleDataBanner() {}
void showOldDataWarning() {}
void updateUI(Object? value) {}
void showStaleIndicator() {}
void showError(Object error) {}
void updateEventsList(Object? events) {}
''';

const String _hivePreamble = '''
import 'package:syncache/syncache.dart';
import 'package:syncache_hive/syncache_hive.dart';

$_sharedStubs

late final HiveStore<User> store;
late final Syncache<String> cache;
''';

const String _driftPreamble = '''
import 'package:syncache/syncache.dart';
import 'package:syncache_drift/syncache_drift.dart';

$_sharedStubs

late final DriftStore<User> store;
late final DriftMutationOutbox outbox;
late final SyncacheDriftDatabase db;
late final Syncache<String> cache;
late final Stored<User> entry;
late final PendingMutationRecord record;
var key = 'user:1';
''';
