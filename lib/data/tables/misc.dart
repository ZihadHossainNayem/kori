import 'package:drift/drift.dart';

/// One unit of [base] costs [rate] units of [quote].
///
/// Always hand-entered: the app has no internet permission, so there is nothing
/// that could fetch these.
@DataClassName('ExchangeRate')
class ExchangeRates extends Table {
  TextColumn get base => text().withLength(min: 3, max: 3)();

  TextColumn get quote => text().withLength(min: 3, max: 3)();

  RealColumn get rate => real()();

  /// When the rate was recorded. Shown as an age, because a hand-entered rate
  /// drifts out of date and the user is the only one who can refresh it.
  DateTimeColumn get fetchedAt => dateTime().nullable()();

  BoolColumn get manual => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {base, quote};

  @override
  List<String> get customConstraints => [
    'CHECK (rate > 0)',
    'CHECK (base != quote)',
  ];
}

/// App settings: display currency, theme, app lock, onboarding seen.
@DataClassName('Preference')
class Preferences extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
