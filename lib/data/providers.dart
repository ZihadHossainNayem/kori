import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';

/// The single database instance for the app's lifetime.
///
/// Tests override it with an in-memory executor:
/// `databaseProvider.overrideWithValue(KoriDatabase(NativeDatabase.memory()))`.
final Provider<KoriDatabase> databaseProvider = Provider<KoriDatabase>((ref) {
  final database = KoriDatabase();
  ref.onDispose(database.close);
  return database;
});
