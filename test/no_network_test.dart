import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kori's central promise is that nothing leaves the phone. These tests make
/// that structural rather than aspirational: a release build has no INTERNET
/// permission, so the OS refuses a socket even if some future dependency tries.
///
/// If one of these fails, either revert the change or update every claim in the
/// README, Settings and store listing first.
void main() {
  test('the release manifest asks for no INTERNET permission', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest.contains('android.permission.INTERNET'),
      isFalse,
      reason: 'A release build must not be able to open a socket',
    );
  });

  test('debug builds may keep it, for hot reload', () {
    // Flutter needs it for the dev tooling; it never ships.
    final debug = File(
      'android/app/src/debug/AndroidManifest.xml',
    ).readAsStringSync();
    expect(debug.contains('android.permission.INTERNET'), isTrue);
  });

  test('no networking package is a dependency', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final dependencies = pubspec
        .split('dev_dependencies:')
        .first
        .split('\n')
        .map((line) => line.trim());

    for (final banned in ['http:', 'dio:', 'web_socket_channel:', 'grpc:']) {
      expect(
        dependencies.any((line) => line.startsWith(banned)),
        isFalse,
        reason: '$banned would give the app a way to phone home',
      );
    }
  });

  test('no source file reaches for the network', () {
    final offenders = <String>[];
    final pattern = RegExp(
      r'HttpClient|HttpRequest|WebSocket|package:http/|package:dio/'
      r'|Socket\.connect|InternetAddress',
    );

    for (final directory in ['lib', 'integration_test']) {
      for (final entity in Directory(directory).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (pattern.hasMatch(entity.readAsStringSync())) {
          offenders.add(entity.path);
        }
      }
    }

    expect(offenders, isEmpty);
  });
}
