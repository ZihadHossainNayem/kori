import 'package:flutter/material.dart';

/// The three-tap entry screen — keypad first, category chips second. Phase 1.
class AddTransactionScreen extends StatelessWidget {
  const AddTransactionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add')),
      body: const Center(child: Text('Fast entry lands here in phase 1.')),
    );
  }
}
