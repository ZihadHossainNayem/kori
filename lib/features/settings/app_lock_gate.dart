import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'settings_providers.dart';

final localAuthProvider = Provider<LocalAuthentication>(
  (ref) => LocalAuthentication(),
);

/// Covers the app until the device unlocks it, and again after a resume.
///
/// Deliberately a cover rather than a route: the screens behind it never build
/// with data on show, so nothing leaks into a screenshot or the task switcher.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _prompting = false;
  bool _checkedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _enabled) {
      setState(() => _locked = true);
    }
  }

  bool get _enabled => ref.read(appLockEnabledProvider).value ?? false;

  Future<void> _unlock() async {
    if (_prompting) return;
    setState(() => _prompting = true);

    var unlocked = false;
    try {
      unlocked = await ref
          .read(localAuthProvider)
          .authenticate(
            localizedReason: 'Unlock Kori',
            persistAcrossBackgrounding: true,
          );
    } catch (_) {
      // No biometrics enrolled, hardware missing, user cancelled — all the same
      // outcome: stay locked rather than fail open.
      unlocked = false;
    }

    if (!mounted) return;
    setState(() {
      _prompting = false;
      _locked = !unlocked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(appLockEnabledProvider).value ?? false;

    // Lock on first build once the setting is known.
    if (enabled && !_checkedOnce) {
      _checkedOnce = true;
      _locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
    if (!enabled) {
      _locked = false;
      _checkedOnce = false;
    }

    return Stack(
      children: [
        widget.child,
        if (_locked) _LockCover(onUnlock: _prompting ? null : _unlock),
      ],
    );
  }
}

class _LockCover extends StatelessWidget {
  const _LockCover({required this.onUnlock});

  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: Material(
        color: scheme.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 56, color: scheme.primary),
                const SizedBox(height: 20),
                Text(
                  'Kori is locked',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
