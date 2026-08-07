import 'package:flutter/material.dart';

/// Wallet balances and the converted total. Filled in during phase 1.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kori')),
      body: const Center(child: Text('Wallets land here in phase 1.')),
    );
  }
}
