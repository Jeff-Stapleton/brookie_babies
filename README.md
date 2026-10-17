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
- **Sign-in**: Google sign-in through Firebase Auth. Customers sign in before
  paying.
- **Payment**: choosing a session opens the matching Stripe Payment Link,
  tagged with the customer's account so the payment can be matched to them.

## Tech stack

- Flutter 3.47.7 (Material 3), **web target only**
- Firebase: Core, Auth (Google), Storage, Hosting (project `brookie-babies`)
- Stripe: Payment Links
- `table_calendar`, `url_launcher`

## Getting started

### Prerequisites

1. **Flutter SDK 3.47.7** (stable channel; the version CI uses)
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
| Deploy to Firebase Hosting | `flutter build web --release && firebase deploy --only hosting` |

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
  models/            Data types (signed-in user)
  services/          Auth, app-wide services, Stripe Payment Links
  pages/             Home and Scheduling screens
  components/        Page sections (carousel, packages, session list, footer,
                     account button, sign-in dialog)
  widgets/           Reusable widgets (cards, text styles, lists)
  utilities/         Calendar and browser helpers
assets/              Logo
web/                 Web shell (index.html, manifest, icons)
.github/workflows/   CI: analyze, test, build and deploy (ci.yml)
```

See [AGENT.md](AGENT.md) for an architectural walkthrough, conventions and known issues.

## Deployment

One GitHub Actions workflow, `.github/workflows/ci.yml`, checks and deploys the
site. It runs `flutter pub get --enforce-lockfile`,
`flutter analyze --no-fatal-infos` (lint infos are not fatal yet),
`flutter test` and `flutter build web --release` on Flutter 3.47.7 (pinned in
the workflow). It fails if any tracked file or the web bundle contains a Stripe
secret key, webhook secret or private key, and otherwise deploys `build/web` to
Firebase Hosting:

- On pull request to `main`: a preview channel that expires after 7 days. The
  preview URL is posted on the pull request. Pull requests from forks are
  checked but not deployed.
- On push to `main` (or a manual run on `main`): the live site,
  https://brookie-babies.web.app. The job uses the `production` environment,
  but GitHub creates it with no protection rules. To make it a real gate, add
  a deployment-branch rule for `main` (and a reviewer if wanted) and move the
  live credential into it as an environment secret.

Deploys only run when the checks pass. They need the
`FIREBASE_SERVICE_ACCOUNT_BROOKIE_BABIES` repository secret, which preview
and live deploys currently share.

This repository is public. Never commit secrets or service account keys; see
the security note in [AGENT.md](AGENT.md).

`firebase.json` serves `build/web` as a static site and sends app routes to
`index.html`. To deploy by hand, run `flutter build web --release`, then
`firebase deploy --only hosting`.
