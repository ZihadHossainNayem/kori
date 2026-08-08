import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/daos/wallets_dao.dart';
import '../../data/providers.dart';

/// Picks a wallet, returning its id. [excludeId] hides the source wallet when
/// choosing a transfer destination.
Future<int?> showWalletPicker(
  BuildContext context, {
  int? selectedId,
  int? excludeId,
  String title = 'Choose wallet',
}) {
  return showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => _WalletPicker(
      selectedId: selectedId,
      excludeId: excludeId,
      title: title,
    ),
  );
}

class _WalletPicker extends ConsumerWidget {
  const _WalletPicker({required this.title, this.selectedId, this.excludeId});

  final String title;
  final int? selectedId;
  final int? excludeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider).value ?? const [];
    final options = wallets.where((w) => w.wallet.id != excludeId).toList();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          if (options.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No other wallets yet.'),
            ),
          for (final option in options)
            _WalletTile(
              option: option,
              selected: option.wallet.id == selectedId,
              onTap: () => Navigator.of(context).pop(option.wallet.id),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _WalletTile extends StatelessWidget {
  const _WalletTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final WalletWithBalance option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(option.wallet.color);

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(KoriRadius.small),
        ),
        child: Icon(iconFor(option.wallet.icon), color: color, size: 20),
      ),
      title: Text(option.wallet.name),
      // An empty style still layers onto ListTile's own subtitle style — Text
      // merges the two, so only the digit feature is added.
      subtitle: Text(option.balance.format(), style: const TextStyle().tabular),
      trailing: selected ? const Icon(Icons.check) : null,
    );
  }
}
