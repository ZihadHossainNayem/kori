import 'package:flutter/material.dart';

/// Icons are stored as names, not font code points, so the icon set can change
/// without migrating anyone's data.
const Map<String, IconData> _icons = {
  // Wallets
  'wallet': Icons.account_balance_wallet,
  'bank': Icons.account_balance,
  'phone': Icons.smartphone,
  'card': Icons.credit_card,
  'piggy-bank': Icons.savings,
  'cash': Icons.payments,
  'safe': Icons.lock,

  // Categories
  'utensils': Icons.restaurant,
  'shopping-cart': Icons.shopping_cart,
  'car': Icons.directions_car,
  'shopping-bag': Icons.shopping_bag,
  'zap': Icons.bolt,
  'home': Icons.home,
  'heart': Icons.favorite,
  'book': Icons.menu_book,
  'tv': Icons.tv,
  'users': Icons.people,
  'more-horizontal': Icons.more_horiz,
  'briefcase': Icons.work,
  'laptop': Icons.laptop_mac,
  'trending-up': Icons.trending_up,
  'gift': Icons.card_giftcard,
  'plus-circle': Icons.add_circle_outline,
  'tag': Icons.label_outline,
  'phone-call': Icons.phone,
  'plane': Icons.flight,
  'pet': Icons.pets,
  'gym': Icons.fitness_center,
  'coffee': Icons.local_cafe,
  'fuel': Icons.local_gas_station,
  'medicine': Icons.medical_services,
  'school': Icons.school,
  'baby': Icons.child_care,
  'tools': Icons.build,
};

/// Falls back to a neutral tag rather than throwing, so an unknown name from a
/// restored backup or a newer version still renders.
IconData iconFor(String name) => _icons[name] ?? Icons.label_outline;

/// Names offered in the wallet icon picker.
const List<String> walletIconNames = [
  'wallet',
  'cash',
  'bank',
  'phone',
  'card',
  'piggy-bank',
  'safe',
];

/// Names offered in the category icon picker.
const List<String> categoryIconNames = [
  'utensils',
  'coffee',
  'shopping-cart',
  'shopping-bag',
  'car',
  'fuel',
  'plane',
  'home',
  'zap',
  'phone-call',
  'heart',
  'medicine',
  'gym',
  'book',
  'school',
  'tv',
  'users',
  'baby',
  'pet',
  'tools',
  'briefcase',
  'laptop',
  'trending-up',
  'gift',
  'tag',
  'more-horizontal',
];

/// Palette for wallets and categories — chosen to stay distinguishable from
/// each other and legible on both light and dark surfaces.
const List<int> palette = [
  0xFF0F766E,
  0xFF0EA5E9,
  0xFF3B82F6,
  0xFF6366F1,
  0xFF8B5CF6,
  0xFFA855F7,
  0xFFEC4899,
  0xFFEF4444,
  0xFFF97316,
  0xFFF59E0B,
  0xFF84CC16,
  0xFF22C55E,
  0xFF10B981,
  0xFF14B8A6,
  0xFF6B7280,
  0xFF475569,
];
