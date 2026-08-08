import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/daos/settings_dao.dart';
import '../../data/providers.dart';

/// False until onboarding finishes, so a fresh install starts there.
final onboardingSeenProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(settingsDaoProvider)
      .watch(PreferenceKeys.onboardingSeen)
      .map((value) => value == 'true'),
);

/// Dark by default until the user picks otherwise — not the platform's
/// system mode.
final themeModeProvider = StreamProvider<ThemeMode>(
  (ref) => ref
      .watch(settingsDaoProvider)
      .watch(PreferenceKeys.themeMode)
      .map(
        (value) => switch (value) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark, // unset — the app's own default, not the OS's
        },
      ),
);

final appLockEnabledProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(settingsDaoProvider)
      .watch(PreferenceKeys.appLock)
      .map((value) => value == 'true'),
);

extension SettingsWrites on WidgetRef {
  Future<void> setThemeMode(ThemeMode mode) =>
      read(settingsDaoProvider).write(PreferenceKeys.themeMode, switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      });

  Future<void> setAppLock({required bool enabled}) =>
      read(settingsDaoProvider).write(PreferenceKeys.appLock, '$enabled');

  Future<void> finishOnboarding() =>
      read(settingsDaoProvider).write(PreferenceKeys.onboardingSeen, 'true');
}
