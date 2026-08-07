/// How often a recurring rule fires.
///
/// Lives in `core` so the date math in `dates.dart` can use it without
/// depending on the data layer.
enum RecurrenceFrequency { daily, weekly, monthly, yearly }
