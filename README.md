# PlateRunner

A minimal Flutter starter app (counter with increment & decrement) to bootstrap further development.

The Dart package name (per `pubspec.yaml`) is `plate_runner`, while the project directory and displayed app title use `PlateRunner`.

---

## Features

- Material 3 theme with seeded color scheme
- Counter stateful widget
- Two sets of controls:
  - Elevated buttons (Increment / Decrement)
  - Floating action buttons (center docked)
- Never decrements below zero
- Widget tests validating behavior

---

## Prerequisites

1. Install Flutter (Stable channel recommended):  
   https://docs.flutter.dev/get-started/install

2. Confirm installation:
   ```
   flutter --version
   ```

3. (Optional) Enable desktop targets if you want to run on macOS, Windows, or Linux:
   ```
   flutter config --enable-macos-desktop
   flutter config --enable-windows-desktop
   flutter config --enable-linux-desktop
   ```

4. Get dependencies:
   ```
   flutter pub get
   ```

---

## Running the App

Run on a connected device or emulator:
```
flutter run
```

Specify a device (example):
```
flutter devices
flutter run -d chrome
```

Hot reload / restart:
- Press `r` in the terminal for hot reload
- Press `R` for hot restart

---

## Project Structure (Relevant Parts)

```
PlateRunner/
  lib/
    main.dart          # App entrypoint with counter UI
  test/
    counter_test.dart  # Widget tests
  pubspec.yaml         # Dependencies & metadata
```

---

## Testing

Run all widget tests:
```
flutter test
```

Run with coverage (Linux/macOS):
```
flutter test --coverage
```
(Generates `coverage/lcov.info`.)

You can view coverage in an HTML report (requires `lcov`):
```
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## Linting & Analysis

```
flutter analyze
```

The project uses `flutter_lints` (see `pubspec.yaml`). Adjust or extend rules by adding an `analysis_options.yaml` later if needed.

---

## Building Release Artifacts

Android (APK):
```
flutter build apk --release
```

Android (AppBundle):
```
flutter build appbundle
```

iOS:
```
flutter build ios --release
```
(Then open Xcode workspace for code signing & distribution.)

Web:
```
flutter build web
```
Outputs to `build/web`.

Desktop (example macOS):
```
flutter build macos
```

---

## Customization Ideas (Next Steps)

- Add routing & navigation shell
- State management (Provider, Riverpod, Bloc, etc.)
- Theming variants (dark mode toggle)
- CI workflow (GitHub Actions) for tests & analysis
- Integration tests using `flutter_test` + `integration_test` package
- Local persistence (e.g., shared_preferences) for counter value

---

## Troubleshooting

Common commands:
```
flutter clean
flutter pub get
flutter doctor -v
```

If you see dependency version conflicts, ensure your Flutter SDK is up to date:
```
flutter upgrade
```

---

## License

Currently unlicensed (private/internal). Add a proper `LICENSE` file before distribution.

---

Happy building!