import 'package:flutter/material.dart';

/// Display currency, theme, app lock, and the import/export/backup entry
/// points. Phases 4 and 5.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings land here in phases 4 and 5.')),
    );
  }
}
