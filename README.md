# Brookie Babies

A Flutter web app for Brooke Stapleton Photography. Families can see Brooke's
photographs, choose a session package, pick a date and time, pay through Stripe,
and later download their edited photos. The site is hosted on Firebase.

> Status: early MVP. The session times and the package inclusions are still
> placeholders (`lib/models/session_time.dart`, `lib/models/session_package.dart`).

## Features

- **Home page**: one full-bleed photograph with the logo and "Book a session",
  then a short introduction and up to six more photographs, all from Firebase
  Storage (`_admin/gallery`; see "Home page photos").
- **Packages**: Basic ($25), Premium ($50) and Ultimate ($99); choosing one
  opens booking for it.
- **Scheduling**: a calendar (`table_calendar`) and the session times for the
  chosen day.
- **Sign-in**: Google sign-in through Firebase Auth. Customers sign in before
  paying.
- **Payment**: after choosing a time, "Continue to payment" opens the package's
  Stripe Payment Link, tagged with the customer's account so the payment can be
  matched to them.
- **Your sessions**: signed-in customers see their upcoming and past sessions and
  download every photo from a past session as one zip, through a private link
  that expires after an hour.

## Tech stack

- Flutter 3.47.7 (Material 3), **web target only**
- Firebase: Core, Auth (Google), Firestore, Storage, Cloud Functions, Hosting
  (project `brookie-babies`)
- Cloud Functions: TypeScript on Node 24 (`functions/`)
- Design system theme in `lib/theme/brookie_theme.dart` (Print and Darkroom,
  following the device's light or dark setting); Jost and Newsreader bundled in
  `assets/fonts/`
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
`lib/firebase_options.dart`. The home page only shows photographs once the
Storage bucket has files under `_admin/gallery` and CORS is configured (see below).

### Common commands

| Task | Command |
|---|---|
| Run locally | `flutter run -d chrome` |
| Static analysis | `flutter analyze` |
| Tests | `flutter test` |
| Production build | `flutter build web` (output in `build/web`) |
| Deploy to Firebase Hosting | `flutter build web --release && firebase deploy --only hosting` |
| Cloud Functions build and tests | `npm ci --prefix functions && npm test --prefix functions` |
| Deploy functions and rules by hand | `firebase deploy --only functions,firestore:rules,storage` (CI does this on pushes to `main`; see [Deploying the backend](#deploying-the-backend)) |

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
  theme/             The design system: colors, type, spacing, Material theme
  models/            Data types (signed-in user, booking, packages, session times)
  services/          Auth, bookings, photo downloads, app-wide services,
                     Stripe Payment Links
  pages/             Home, Book a session and Your sessions screens
  components/        Page sections (hero, featured photos, packages, calendar,
                     session times, footer, account button, sign-in dialog,
                     booking card)
  widgets/           Reusable widgets (top bar, package card, session slot,
                     status tags, focus ring, photos)
  utilities/         Date and browser helpers
assets/              Logo and fonts
web/                 Web shell (index.html, manifest, icons)
functions/           Cloud Functions (TypeScript, Node 24): getGalleryDownloadUrl
firestore.rules      Firestore security rules (customers read only their own bookings)
storage.rules        Storage security rules (only the home page photo folder is public)
.github/workflows/   CI: analyze, test, build and deploy (ci.yml)
```

See [AGENT.md](AGENT.md) for an architectural walkthrough, conventions and known issues.

## Home page photos

The home page shows the photographs in Storage → `_admin/gallery`, in file-name
order. The **first file by name is the full-screen photo** behind the logo, so
pick one whose subject's face is clear of the center (the logo covers the
middle) and name it so it sorts first, for example `00-hero.jpg`. The next six
appear below the introduction, in full rows only (three across on wider
screens, two on phones; a leftover photo is left out). Only JPEG, PNG and WebP
files are shown (export iPhone HEIC photos first), hidden files such as
`.DS_Store` are skipped, and only the first seven by name are used. Everything
in this folder is public.

## Delivering photos

Customers download their photos from **Your sessions** as soon as the booking's `status` is `paid` and `photosReady` is `true`. The **Download all photos** button appears on the booking's card even before the session date, so check that the booking is right before marking it ready. Photos are never public through the site: customers get a zip download link that expires after one hour.

1. **Find the booking ID.** Firebase console → Firestore Database → `bookings`. Find the customer's booking by `email` and `date`. The document ID is the booking ID.
2. **Upload the photos.** Firebase console → Storage → open `galleries` (create it if needed) → **Create folder** named exactly the booking ID → upload the photos into it. Subfolders are fine. Hidden files such as `.DS_Store` are skipped. Never put customer photos in `_admin/gallery/`: that folder is public (it's the home page photos).
3. **Mark them ready.** Open the booking again and set the field `photosReady` (type **boolean**) to `true`. Do this only after every upload has finished.

> **Never share the Storage console's file links.** For every uploaded file, the console shows a download link with an access token. Anyone with that link can open the photo, permanently, whatever the security rules say. Customers should only get their photos through **Your sessions**. If a link was shared by mistake, revoke that file's access token (Storage → the file → Access token → Revoke).

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
site and the backend. It runs `flutter pub get --enforce-lockfile`,
`flutter analyze --no-fatal-infos` (lint infos are not fatal yet),
`flutter test` and `flutter build web --release` on Flutter 3.47.7 (pinned in
the workflow), and builds and tests the Cloud Functions. It fails if any
tracked file or the web bundle contains a Stripe secret key, webhook secret or
private key. It deploys `build/web` to Firebase Hosting:

- On pull request to `main`: a preview channel that expires after 7 days. The
  preview URL is posted on the pull request. Pull requests from forks are
  checked but not deployed.
- On push to `main` (or a manual run on `main`): first the Cloud Functions and
  Firestore/Storage rules (see [Automatic backend deploys](#automatic-backend-deploys)),
  then the live site, https://brookie-babies.web.app. Both jobs use the
  `production` environment, which `scripts/setup-github-production.sh`
  restricts to `main`.

Deploys only run when the checks pass. The backend deploy uses no stored key.
The Hosting deploys use the `FIREBASE_SERVICE_ACCOUNT_BROOKIE_BABIES`
repository secret, which preview and live deploys share. It's a
repository-level secret, so the `main`-only environment rule doesn't protect
it, and any workflow on any branch of this repository can read it. Moving it
into a `production` environment secret, or switching Hosting to keyless
sign-in too, is on the TODO list.

This repository is public. Never commit secrets or service account keys; see
the security note in [AGENT.md](AGENT.md).

`firebase.json` serves `build/web` as a static site and sends app routes to
`index.html`. To deploy by hand, run `flutter build web --release`, then
`firebase deploy --only hosting`.

### Deploying the backend

`functions/` holds the Cloud Functions, and `firestore.rules` and `storage.rules` hold the security rules. They were first deployed by hand on 2026-10-17. CI now deploys them on every push to `main`. Do the one-time setup below **before** the change that added this reaches `main`.

These files are the source of truth: each deploy **replaces the Firestore and Storage rules set in the Firebase console**, so change rules here, not in the console. Only `_admin/gallery/` (the home page photos) is publicly readable, customers can read only their own bookings, and nothing can be written from the app.

#### Automatic backend deploys

The `deploy-backend` job in `.github/workflows/ci.yml` runs on every push to `main` after the checks pass, and before the live site deploys:

```bash
firebase deploy --only functions,firestore:rules,storage --project brookie-babies --non-interactive --force
```

- **No stored key.** The job trades its GitHub sign-in token for credentials that expire within the hour, belonging to the `github-deployer` service account (Workload Identity Federation). Google only accepts tokens from this repository's `production` environment on `main`, and GitHub only lets `main` deploy to that environment.
- **No direct access, but not a sandbox.** `github-deployer` has no direct permission to read bookings, photos or secret values, to turn Google Cloud APIs on or off, or to change who has access to the project. What it deploys can still reach all of that: functions run as `375587092017-compute@developer.gserviceaccount.com`, and a rules change can open up any data. So anyone who can push to `main`, or get code into the npm packages the deploy installs, effectively has access to all customer data. Keep push access to this repository limited to the owner. The setup script warns if the runtime account has broad (Editor) access.
- **Small no-change deploys.** Unchanged functions are skipped, and the rules are re-released as-is.
- **The site waits for the backend once real deploys are on.** With `BACKEND_DEPLOY_LIVE` set to `true`, a failed backend deploy also holds back the live site, so the site never goes live ahead of the functions it calls. In dry-run mode the site deploys regardless. Deploy backend changes by hand before merging site code that depends on them.
- `--force` deletes any function that has been removed from `functions/src`.

**One-time setup** (project owner, from the repository root). Do steps 1-3 before merging the change that adds `deploy-backend`. Until then, every push to `main` fails the **Deploy functions and rules** job at the Google sign-in step. The live site still deploys.

1. Install the Google Cloud CLI and sign in with the same Google account you use for Firebase:
   ```bash
   brew install --cask gcloud-cli
   gcloud auth login
   ```
2. `bash scripts/setup-gcp-deployer.sh` turns on the APIs it needs, creates the identity pool and provider, creates the `github-deployer` service account and its custom role with the permissions above, and lets only this repository's `production` jobs on `main` act as it. It never creates a key, and it's safe to re-run.
3. `bash scripts/setup-github-production.sh` restricts the `production` environment to `main`. Run it while nothing is being merged.
4. Wait about 5 minutes for the changes to take effect, then merge. If it's already merged, use **Actions → CI → Run workflow** on `main`. The **Deploy functions and rules** job runs as a **dry run**, which changes nothing. It checks:
   - sign-in;
   - that the required APIs, billing and service identities are in place;
   - that the rules and functions compile.

   It does **not** test the permissions to upload, update and release.
5. Once that job is green, turn on real deploys:
   ```bash
   gh variable set BACKEND_DEPLOY_LIVE --body true
   ```
   (Or Settings → Secrets and variables → Actions → Variables.) Watch the next run: it's the first real test of the deploy permissions. To pause automatic deploys, set the variable to anything else, and the job goes back to dry runs.

**If the job fails:**
- **"Failed to generate Google Cloud federated token" in the sign-in step:** the identity pool, provider or condition doesn't match. Re-run `scripts/setup-gcp-deployer.sh`, wait 5 minutes, and re-run the job.
- **Failures in the deploy step:** the error usually names the API call that failed. For more detail, run the same deploy locally as the owner with `firebase deploy --only functions,firestore:rules,storage --debug` (add `--dry-run` to change nothing). Don't add `--debug` in CI: this repository's logs are public, and debug output includes API responses such as the signed URL the function source is uploaded to.
- **A 403:** the error names the missing permission. Add it to `scripts/setup-gcp-deployer.sh` and re-run the script.

**Before merging something new**, prepare the project, because `github-deployer` deliberately can't. Otherwise the CI deploy fails:

- **A function that uses a secret** (`defineSecret`, for example a Stripe key):
  1. Run `firebase functions:secrets:set NAME`.
  2. Grant `375587092017-compute@developer.gserviceaccount.com` **Secret Manager Secret Accessor** on that secret.
  3. Grant `github-deployer@brookie-babies.iam.gserviceaccount.com` **Secret Manager Viewer** on that secret.
- **A function that uses a non-secret param** (`defineString`, `defineInt` and so on, for example a Stripe Price ID): CI deploys non-interactively, so every param needs a value in a committed `functions/.env`.
  - Add `!functions/.env` to `.gitignore`, since `.env` files are ignored by default.
  - Put only non-sensitive values there; use `defineSecret` for anything sensitive.
- **A new kind of trigger.** Add the permissions it needs to `CUSTOM_ROLE_PERMISSIONS` in `scripts/setup-gcp-deployer.sh` and re-run the script:
  - **Firestore triggers:** `datastore.databases.getMetadata`.
  - **Scheduled functions:** `cloudscheduler.jobs.get`, `create`, `update` and `delete`.
  - **Storage and Pub/Sub triggers:** these need owner-only setup the first time, so deploy them once by hand from the feature branch before merging.
- **A function with its own `serviceAccount`:** add `"<that account> roles/iam.serviceAccountUser"` to `SA_ROLE_GRANTS` in the script and re-run it.
- **A Google Cloud API that isn't on yet:** turn it on in the console.

**Deploying by hand** still works. Run it from an up-to-date `main`, except in the case above where you deploy a new trigger type from its branch:

```bash
npm ci --prefix functions
firebase deploy --only functions,firestore:rules,storage
```

#### Function runtime permissions

The functions run as `375587092017-compute@developer.gserviceaccount.com`, which in this project has no broad (Editor) access. `scripts/setup-functions-runtime.sh` (project owner, once, idempotent) gives it exactly what `getGalleryDownloadUrl` needs:

- **Reading bookings:** read-only Firestore access (`roles/datastore.viewer`).
- **Reading photos and saving the zips:** object access on the Storage bucket only (`roles/storage.objectUser`).
- **Signing the download links:** Service Account Token Creator on itself only. The script removes any project-wide Token Creator grant, which would let the functions act as every service account in the project.

Signing also needs the **IAM Service Account Credentials API**, which is turned on.

If downloads fail with "We couldn't get your photos ready just now", check the function's log:
- **A Firestore or Storage permission error:** re-run the script.
- **A `signBlob` error:** check the Token Creator grant and the API.

When a new function needs other data, add the role to this script, scoped as narrowly as possible.

Optional: add a Storage lifecycle rule that deletes objects under `gallery-zips/` after 30 days to save storage. Zips are rebuilt automatically the next time someone downloads.
