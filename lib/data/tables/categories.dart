import 'package:drift/drift.dart';

/// A category is income or expense, never both, so the add screen can filter
/// chips by the selected direction.
enum CategoryType { income, expense }

@TableIndex(name: 'idx_categories_type_sort', columns: {#type, #sortOrder})
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 40)();

  TextColumn get type => textEnum<CategoryType>()();

  TextColumn get icon => text().withDefault(const Constant('tag'))();

  /// ARGB.
  IntColumn get color => integer()();

  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
