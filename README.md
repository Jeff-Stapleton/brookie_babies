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
- **My sessions**: signed-in customers see their upcoming and past sessions and
  download every photo from a past session as one zip, through a private link
  that expires after an hour.

## Tech stack

- Flutter 3.47.7 (Material 3), **web target only**
- Firebase: Core, Auth (Google), Firestore, Storage, Cloud Functions, Hosting
  (project `brookie-babies`)
- Cloud Functions: TypeScript on Node 24 (`functions/`)
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
| Cloud Functions build and tests | `npm ci --prefix functions && npm test --prefix functions` |
| Deploy functions and rules | `firebase deploy --only functions,firestore:rules,storage` (see [Deploying the backend](#deploying-the-backend)) |

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
  models/            Data types (signed-in user, booking)
  services/          Auth, bookings, photo downloads, app-wide services,
                     Stripe Payment Links
  pages/             Home, Scheduling and My sessions screens
  components/        Page sections (carousel, packages, session list, footer,
                     account button, sign-in dialog, booking card)
  widgets/           Reusable widgets (cards, text styles, lists)
  utilities/         Calendar and browser helpers
assets/              Logo
web/                 Web shell (index.html, manifest, icons)
functions/           Cloud Functions (TypeScript, Node 24): getGalleryDownloadUrl
firestore.rules      Firestore security rules (customers read only their own bookings)
storage.rules        Storage security rules (only the carousel folder is public)
.github/workflows/   CI: analyze, test, build and deploy (ci.yml)
```

See [AGENT.md](AGENT.md) for an architectural walkthrough, conventions and known issues.

## Delivering photos

Customers download their photos from **My sessions** as soon as the booking's `status` is `paid` and `photosReady` is `true`. The **Download all photos** button appears on the booking's card even before the session date, so check that the booking is right before marking it ready. Photos are never public through the site: customers get a zip download link that expires after one hour.

1. **Find the booking ID.** Firebase console → Firestore Database → `bookings`. Find the customer's booking by `email` and `date`. The document ID is the booking ID.
2. **Upload the photos.** Firebase console → Storage → open `galleries` (create it if needed) → **Create folder** named exactly the booking ID → upload the photos into it. Subfolders are fine. Hidden files such as `.DS_Store` are skipped. Never put customer photos in `_admin/gallery/`: that folder is public (it's the home page carousel).
3. **Mark them ready.** Open the booking again and set the field `photosReady` (type **boolean**) to `true`. Do this only after every upload has finished.

> **Never share the Storage console's file links.** For every uploaded file, the console shows a download link with an access token. Anyone with that link can open the photo, permanently, whatever the security rules say. Customers should only get their photos through **My sessions**. If a link was shared by mistake, revoke that file's access token (Storage → the file → Access token → Revoke).

The first download builds a zip of the whole folder, which can take a few minutes for a large gallery. Later downloads reuse it. If you add, replace or delete photos afterwards, the next download rebuilds the zip automatically. (If you replace a photo while a customer's download is being built, that one download may contain the old version.)

**Adding a booking by hand** (for example, a payment made through a Stripe Payment Link): Firestore Database → `bookings` → **Add document** → **Auto-ID**, with these fields:

| Field | Type | Value |
|---|---|---|
| `uid` | string | **Required.** The customer's Firebase user ID: the `client_reference_id` on their Stripe payment's Checkout Session |
| `email` | string | The customer's email |
| `packageName` | string | `Basic`, `Premium` or `Ultimate` |
| `date` | string | Session date as `YYYY-MM-DD`, for example `2026-11-03` |
| `time` | string | 24-hour `HH:mm`, for example `14:30` (optional) |
| `location` | string | Optional |
| `status` | string | `paid` |
| `photosReady` | boolean | `false` until the photos are uploaded |
| `createdAt` | timestamp | Now |

**Check the uid before saving: the booking gives that account access to the photos.** Anyone can edit `client_reference_id` in a Payment Link address, and the email on the Stripe payment comes from the same editable link (`locked_prefilled_email`), so neither proves who paid. Look up the uid under **Authentication → Users** and compare its email and name with what you know from outside Stripe, such as the email the customer used to arrange the session, and with the cardholder name on the Stripe payment. If they don't match, confirm with the customer before setting `uid`.

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

### Deploying the backend

`functions/` holds the `getGalleryDownloadUrl` Cloud Function. `firestore.rules` and `storage.rules` hold the security rules. CI builds and tests them but does not deploy them, so you deploy them by hand.

**One-time setup**

1. **Blaze plan:** Firebase console → Usage and billing → Modify plan. Cloud Functions require it. Set a budget alert while you're there.
2. **Tools:** install Node 24 and the Firebase CLI (`npm install -g firebase-tools`), then run `firebase login`.
3. **Firestore:** the database already exists (Native mode, `nam5`), so there is nothing to do.
4. **Allow the function to sign download links.** It signs them with its own service account through Google's IAM API rather than a key file, so it needs:
   ```bash
   gcloud services enable iamcredentials.googleapis.com --project=brookie-babies
   gcloud iam service-accounts add-iam-policy-binding \
     375587092017-compute@developer.gserviceaccount.com \
     --member="serviceAccount:375587092017-compute@developer.gserviceaccount.com" \
     --role="roles/iam.serviceAccountTokenCreator" \
     --project=brookie-babies
   ```
   Or use the Google Cloud console:
   - APIs & Services → enable **IAM Service Account Credentials API**.
   - IAM & Admin → Service Accounts → `375587092017-compute@developer.gserviceaccount.com` → Permissions → Grant access → enter that same account as the principal, with the role **Service Account Token Creator**.

   Without this, downloads fail with "We couldn't prepare your photos" and the function log shows a `signBlob` permission error. If the log shows permission errors reading Firestore or Storage instead, also grant that account **Cloud Datastore User** and **Storage Object Admin**.

**Deploy** (from the repository root):

```bash
npm ci --prefix functions
firebase deploy --only functions,firestore:rules,storage
```

The first functions deploy turns on a few Google Cloud APIs and asks how long to keep container images. The default is fine.

> **Warning:** this deploy **replaces the Firestore and Storage rules currently set in the Firebase console**. Copy the current rules first (Firestore Database → Rules, and Storage → Rules) so you can compare or restore them. Afterwards only `_admin/gallery/` (the carousel) is publicly readable, customers can read only their own bookings, and nothing can be written from the app. Check that the home page carousel still loads after deploying.

Optional: add a Storage lifecycle rule that deletes objects under `gallery-zips/` after 30 days to save storage. Zips are rebuilt automatically the next time someone downloads.
