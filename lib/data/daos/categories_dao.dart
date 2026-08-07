import 'package:drift/drift.dart';

import '../db.dart';
import '../tables/categories.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<KoriDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.attachedDatabase);

  Stream<List<Category>> watchByType(
    CategoryType type, {
    bool includeArchived = false,
  }) {
    final query = select(categories)
      ..where((c) => c.type.equalsValue(type))
      ..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.id),
      ]);
    if (!includeArchived) {
      query.where((c) => c.archived.equals(false));
    }
    return query.watch();
  }

  Future<Category?> byId(int id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<int> createCategory(CategoriesCompanion category) =>
      into(categories).insert(category);

  Future<bool> updateCategory(Category category) =>
      update(categories).replace(category);

  /// Archiving keeps existing transactions pointing at the category; deleting
  /// sets their category to null.
  Future<int> setArchived(int id, {required bool archived}) =>
      (update(categories)..where((c) => c.id.equals(id)))
          .write(CategoriesCompanion(archived: Value(archived)));

  Future<int> deleteCategory(int id) =>
      (delete(categories)..where((c) => c.id.equals(id))).go();

  /// Moves [ids] into the given order, writing sortOrder to match.
  Future<void> reorder(List<int> ids) async {
    await batch((batch) {
      for (final (index, id) in ids.indexed) {
        batch.update(
          categories,
          CategoriesCompanion(sortOrder: Value(index)),
          where: (c) => c.id.equals(id),
        );
      }
    });
  }
}
