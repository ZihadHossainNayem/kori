import 'package:flutter/material.dart';

/// Day-grouped transaction history with search and filters. Phase 1.
class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: const Center(child: Text('Transaction list lands here in phase 1.')),
    );
  }
}
