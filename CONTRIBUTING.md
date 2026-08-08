# Contributing to Kori

Thanks for considering it. Kori exists so that basic personal finance tools stay free — that only
works if the project stays easy to build, review, and trust.

## Ground rules

- **No account, no server, no network on the critical path.** Kori doesn't request the `INTERNET`
  permission at all. Any change that would need it (sync, telemetry, remote config) is out of
  scope — see the README for what's deliberately not being built.
- **Money is `int` minor units, never `double`.** All arithmetic goes through `core/money.dart`;
  nothing else does math on an amount.
- **Widgets never touch the database.** Screens read Riverpod providers; providers wrap DAO
  streams. All SQL lives in `lib/data/daos/`.

## Setup

Requires Flutter 3.44.9 or newer.

```sh
flutter config --enable-swift-package-manager   # once, if building for iOS
flutter pub get
dart run build_runner build                     # generates drift database code
flutter run
```

## Before opening a PR

CI runs all of these; running them locally first saves a round trip:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

If you touched a drift table or DAO, re-run `dart run build_runner build --delete-conflicting-outputs`
and commit the regenerated `.g.dart` files alongside your change.

Schema changes need a migration — see `lib/data/db.dart` and the existing migration tests in
`test/data/migration_test.dart` for the pattern. A schema bump without a tested migration will not
be merged, since it's the one class of bug that can quietly destroy a user's data.

## Code style

- Follow `analysis_options.yaml`; `flutter analyze` must be clean.
- One short comment line at most, only where the *why* isn't obvious from the code. No paragraph
  comments, no restating what the code already says.
- Match the existing DAO/provider/screen split for a feature (see `lib/features/*` for the pattern)
  rather than introducing a new structure for one screen.

## Reporting bugs / proposing features

Open a GitHub issue. For anything that touches the data model, storage format, or the no-network
guarantee, open an issue to discuss the approach before writing code — those are the areas hardest
to walk back after the fact.

## Licence

By contributing, you agree your contribution is licensed under GPL-3.0, the same licence as the
rest of the project.
