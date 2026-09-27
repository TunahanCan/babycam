import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// These rules protect existing extension boundaries. They do not prescribe
/// a new layer for every class or restrict platform adapters to pure Dart.
void main() {
  final lib = Directory('lib').absolute;
  final directives = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  final graph = <String, List<String>>{};
  for (final file in lib.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final path = lib.uri.relativize(file.uri);
    graph[path] = [
      for (final match in directives.allMatches(file.readAsStringSync()))
        _resolve(lib.uri, file.uri, match.group(1)!),
    ];
  }

  test('core and analysis do not depend on application owners or adapters', () {
    expect(graph, isNotEmpty, reason: 'Run from the Flutter project root.');
    final violations = <String>[];
    for (final entry in graph.entries) {
      if (!entry.key.startsWith('core/') &&
          !entry.key.startsWith('analysis/')) {
        continue;
      }
      for (final dependency in entry.value) {
        if (['app/', 'features/', 'services/'].any(dependency.startsWith)) {
          violations.add('${entry.key} -> $dependency');
        }
        if (entry.key.startsWith('analysis/') &&
            (dependency.startsWith('package:flutter/') ||
                dependency == 'dart:io')) {
          violations.add('${entry.key} -> $dependency');
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('billing values stay pure and orchestration uses injected room ports',
      () {
    const values = [
      'services/monetization/broadcast_access_models.dart',
      'services/monetization/purchase_verification_result.dart',
    ];
    final visited = <String>{};
    void checkValueDependencies(String path) {
      if (!visited.add(path)) return;
      expect(graph, contains(path));
      for (final dependency in graph[path]!) {
        expect(dependency.startsWith('package:'), isFalse,
            reason: '$path must not pull a platform SDK into billing values.');
        expect(dependency, isNot('dart:io'));
        if (graph.containsKey(dependency)) checkValueDependencies(dependency);
      }
    }

    values.forEach(checkValueDependencies);
    final coordinator = graph['app/broadcast_purchase_coordinator.dart']!;
    expect(
      coordinator.where((path) =>
          path.startsWith('features/') ||
          path.startsWith('package:shared_preferences/')),
      isEmpty,
      reason: 'Concrete room/storage adapters belong in the composition root.',
    );
  });

  test('project import and export graph has no dependency cycles', () {
    final visited = <String>{};
    final active = <String>[];
    void visit(String path) {
      if (active.contains(path)) {
        fail('Dependency cycle: ${[...active, path].join(' -> ')}');
      }
      if (!visited.add(path)) return;
      active.add(path);
      for (final dependency in graph[path]!) {
        if (graph.containsKey(dependency)) visit(dependency);
      }
      active.removeLast();
    }

    graph.keys.forEach(visit);
  });
}

String _resolve(Uri lib, Uri file, String directive) {
  const package = 'package:miucam/';
  if (directive.startsWith(package)) return directive.substring(package.length);
  if (Uri.parse(directive).hasScheme) return directive;
  return lib.relativize(file.resolve(directive));
}

extension on Uri {
  String relativize(Uri child) => child.path.substring(path.length);
}
