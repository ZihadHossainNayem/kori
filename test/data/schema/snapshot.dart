import 'package:drift/drift.dart';

/// The versioned DDL of [db], normalised into one sorted line per entity.
///
/// Views are left out on purpose: they are dropped and recreated on every open,
/// so editing one needs no schema version bump. Everything here does.
Future<String> schemaSnapshotOf(GeneratedDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT type, name, sql FROM sqlite_master '
        "WHERE name NOT LIKE 'sqlite_%' AND type != 'view' "
        'ORDER BY type, name',
      )
      .get();

  final lines = rows.map((row) {
    final type = row.read<String>('type');
    final name = row.read<String>('name');
    final sql = row.readNullable<String>('sql');
    // Autoincrement rowid tables get an sql-less internal index entry.
    final ddl = sql == null
        ? '(implicit)'
        : sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    return '$type $name :: $ddl';
  });

  return '${lines.join('\n')}\n';
}
