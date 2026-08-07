import 'package:drift/drift.dart';

import 'db.dart';
import 'tables/categories.dart';

/// Starting categories, roughly ordered by how often they get tapped.
///
/// A starting point, not a taxonomy: all are renameable, archivable and
/// deletable, and no code special-cases any of them.
const List<_SeedCategory> _defaults = [
  _SeedCategory('Food & Dining', CategoryType.expense, 'utensils', 0xFFF97316),
  _SeedCategory('Groceries', CategoryType.expense, 'shopping-cart', 0xFF84CC16),
  _SeedCategory('Transport', CategoryType.expense, 'car', 0xFF3B82F6),
  _SeedCategory('Shopping', CategoryType.expense, 'shopping-bag', 0xFFA855F7),
  _SeedCategory('Bills & Utilities', CategoryType.expense, 'zap', 0xFFF59E0B),
  _SeedCategory('Rent', CategoryType.expense, 'home', 0xFF0EA5E9),
  _SeedCategory('Health', CategoryType.expense, 'heart', 0xFFEF4444),
  _SeedCategory('Education', CategoryType.expense, 'book', 0xFF14B8A6),
  _SeedCategory('Entertainment', CategoryType.expense, 'tv', 0xFFEC4899),
  _SeedCategory('Family', CategoryType.expense, 'users', 0xFF8B5CF6),
  _SeedCategory('Other', CategoryType.expense, 'more-horizontal', 0xFF6B7280),
  _SeedCategory('Salary', CategoryType.income, 'briefcase', 0xFF22C55E),
  _SeedCategory('Freelance', CategoryType.income, 'laptop', 0xFF10B981),
  _SeedCategory('Business', CategoryType.income, 'trending-up', 0xFF059669),
  _SeedCategory('Gift', CategoryType.income, 'gift', 0xFFF472B6),
  _SeedCategory('Other', CategoryType.income, 'plus-circle', 0xFF6B7280),
];

/// Runs once, from `beforeOpen` on a freshly created database.
Future<void> seedDefaults(KoriDatabase db) async {
  await db.batch((batch) {
    batch.insertAll(
      db.categories,
      [
        for (final (index, category) in _defaults.indexed)
          CategoriesCompanion.insert(
            name: category.name,
            type: category.type,
            icon: Value(category.icon),
            color: category.color,
            sortOrder: Value(index),
          ),
      ],
    );
  });
}

class _SeedCategory {
  const _SeedCategory(this.name, this.type, this.icon, this.color);
  final String name;
  final CategoryType type;
  final String icon;
  final int color;
}
