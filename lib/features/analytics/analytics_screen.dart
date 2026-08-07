import 'package:flutter/material.dart';

/// Five SQL-aggregated chart views. Phase 3.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: const Center(child: Text('Charts land here in phase 3.')),
    );
  }
}
