# Kori

A free, open-source personal finance app for Android and iOS. Your data stays on your phone.

Kori exists because the people who most need to see where their money goes are the least able to
pay a monthly subscription to find out. Everything other apps put behind a paid tier — unlimited
wallets, unlimited budgets, multi-currency, real analytics — is free here.

## How it works

- **No account.** First launch goes straight into the app. No email, no sign-in.
- **No server.** Everything lives in SQLite on your device and works fully offline.
- **No tracking.** No analytics, no crash reporting, no ads. The only network request in the whole
  app is an exchange-rate refresh you tap yourself.
- **Your data is a file you hold.** Export to CSV or Excel, or take an encrypted backup, at any
  time. There is nothing to lock you in.

## Status

Early development, and the feature list above describes the finished app rather than today's build.

Working on Android and iOS: wallets in any currency, transaction entry, transfers, and day-grouped
history with search and filters. Budgets, recurring transactions, analytics, and import/export are
still to come.

## Building

Requires Flutter 3.44.9 or newer. iOS builds with Swift Package Manager, which
Flutter enables globally rather than per project, so run the first line once:

```sh
flutter config --enable-swift-package-manager
flutter pub get
dart run build_runner build    # generates the drift database code
flutter run
```

Tests:

```sh
flutter test                                        # unit and widget
flutter test integration_test/app_test.dart -d <id>  # on a real device
```

## Licence

GPL-3.0. You may use, study, modify and share it; derivative works must stay open source too. That
is deliberate: nobody should be able to re-skin this into the paid app it was written to replace.
