# Brookie Babies

A Flutter web app for the Brookie Babies photography business. Visitors can
browse a photo gallery, choose a session package, pick a date and time, and pay
through Stripe. The site is hosted on Firebase.

> Status: early MVP. Much of the copy, the session times and the package
> details are still placeholders.

## Features

- **Hero carousel**: full-screen, auto-advancing gallery loaded from Firebase
  Storage (`_admin/gallery`).
- **Packages**: Basic ($25), Premium ($50) and Ultimate ($99) pricing cards.
- **Scheduling**: a calendar (`table_calendar`) with a list of available sessions
  for the selected day.
- **Payment**: choosing a session opens the matching Stripe Payment Link.

## Tech stack

- Flutter (Material 3) / Dart `^3.5.3`, **web target only**
- Firebase: Core, Storage, Hosting (project `brookie-babies`)
- Stripe: Payment Links, plus `flutter_stripe_web` (experimental)
- `table_calendar`, `url_launcher`

## Getting started

### Prerequisites

1. **Flutter SDK** (stable channel, with Dart 3.5.3 or newer)
   - macOS: `brew install --cask flutter`
   - Other platforms: see https://docs.flutter.dev/get-started/install
2. **Google Chrome** (to run the web app locally)
3. Optional, for deploying or managing Firebase:
   - Firebase CLI: `npm install -g firebase-tools`, then `firebase login`
   - FlutterFire CLI: `dart pub global activate flutterfire_cli`
   - Google Cloud SDK (`gsutil`), for Storage CORS configuration

Check your setup:

```bash
flutter doctor
```

Only the **Chrome** and **Flutter** checks need to pass. You don't need Xcode or
Android Studio, because the app targets web only.

### Install and run

```bash
git clone https://github.com/Jeff-Stapleton/brookie_babies.git
cd brookie_babies
flutter pub get
flutter run -d chrome
```

The app connects to the `brookie-babies` Firebase project with the web config in
`lib/firebase_options.dart`. The carousel only shows images once the Storage
bucket has files under `_admin/gallery` and CORS is configured (see below).

### Common commands

| Task | Command |
|---|---|
| Run locally | `flutter run -d chrome` |
| Static analysis | `flutter analyze` |
| Tests | `flutter test` |
| Production build | `flutter build web` (output in `build/web`) |
| Deploy to Firebase Hosting | `firebase deploy --only hosting` |

### Firebase setup notes

- **Storage CORS**: browsers need CORS to load the gallery images. Apply the
  included rule once per bucket:
  ```bash
  gsutil cors set cors.json gs://brookie-babies.firebasestorage.app
  ```
- **Using a different Firebase project**: run `flutterfire configure` to
  regenerate `lib/firebase_options.dart`, and update `.firebaserc`.

## Project structure

```
lib/
  main.dart          App entry point, Firebase init, theme, routes
  pages/             Home, Scheduling, Checkout screens
  components/        Page sections (carousel, packages, session list, footer)
  widgets/           Reusable widgets (cards, text styles, lists)
  utilities/         Calendar helpers
assets/              Logo
web/                 Web shell (index.html, manifest, icons)
.github/workflows/   Firebase Hosting deploy workflows
```

See [AGENT.md](AGENT.md) for an architectural walkthrough, conventions and known issues.

## Deployment

The GitHub Actions workflows in `.github/workflows/` deploy to Firebase Hosting:

- On pull request: a preview channel
- On push to `main`: the live site

They need the `FIREBASE_SERVICE_ACCOUNT_BROOKIE_BABIES` repository secret.

> Note: the workflows currently run `npm ci` without a `package.json` and never
> build the Flutter app, so they need updating before CI deploys will work. Until
> then, deploy manually with `flutter build web` and `firebase deploy --only hosting`.
