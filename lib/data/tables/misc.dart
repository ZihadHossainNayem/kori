import 'package:drift/drift.dart';

/// One unit of [base] costs [rate] units of [quote].
///
/// Rates are hand-entered by default so the app works with no network. The
/// optional "Update rates" button is the app's only outbound request, and it
/// writes only here.
@DataClassName('ExchangeRate')
class ExchangeRates extends Table {
  TextColumn get base => text().withLength(min: 3, max: 3)();

  TextColumn get quote => text().withLength(min: 3, max: 3)();

  RealColumn get rate => real()();

  /// Null for a hand-entered rate.
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
