# Kori

A free, open-source personal finance app for Android and iOS. Your data stays on your phone.

Kori exists because the people who most need to see where their money goes are the least able to
pay a monthly subscription to find out. Everything other apps put behind a paid tier — unlimited
wallets, unlimited budgets, multi-currency, real analytics — is free here.

## How it works

- **No account.** First launch goes straight into the app. No email, no sign-in.
- **No server.** Everything lives in SQLite on your device and works fully offline.
- **No network, at all.** Kori does not request the `INTERNET` permission, so it cannot phone home
  even if a future dependency tried. No analytics, no crash reporting, no ads, nothing to fetch.
  You can verify this yourself in the manifest of any release build, and a test in the suite fails
  if anyone changes it.
- **Your data is a file you hold.** Export to CSV or Excel, or take an encrypted backup, at any
  time. There is nothing to lock you in.

## Status

Early development, and the feature list above describes the finished app rather than today's build.

Working on Android and iOS: wallets in any currency with hand-entered exchange rates, transaction
entry, transfers, day-grouped history with search and filters, editable categories, monthly budgets
with alerts, repeating transactions, five insight charts, CSV and spreadsheet export, import with a
preview, and encrypted backup.

Exchange rates are entered by hand and never fetched — that is the cost of having no network
permission.

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

The bundled type, [Manrope](https://github.com/sharanda/manrope), is licensed separately under the
SIL Open Font License 1.1 (`assets/fonts/Manrope-OFL.txt`) and is not itself GPL-3.0.
