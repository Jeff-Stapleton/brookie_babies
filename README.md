# Brookie Babies

A Flutter web app for Brooke Stapleton Photography. Families can see Brooke's
photographs, choose a session package, pick a date and time, pay through Stripe,
and later download their edited photos. The site is hosted on Firebase.

> Status: early MVP. The session times and the package inclusions are still
> placeholders (`lib/models/session_time.dart`, `lib/models/session_package.dart`).

## Features

- **Home page**: one full-bleed photograph with the logo and "Book a session",
  then a short introduction and up to six more photographs, all from Firebase
  Storage (`_admin/gallery`), chosen and ordered in the admin portal (see
  "Home page photos").
- **Packages**: Basic ($25), Premium ($50) and Ultimate ($99); choosing one
  opens booking for it.
- **Scheduling**: a calendar (`table_calendar`) and the session times for the
  chosen day.
- **Sign-in**: Google sign-in through Firebase Auth. Customers sign in before
  paying.
- **Payment**: after choosing a time, "Continue to payment" opens the package's
  Stripe Payment Link, tagged with the customer's account so the payment can be
  matched to them.
- **Your sessions**: signed-in customers see their upcoming and past sessions,
  including ad hoc sessions shared with their Google email, and download every
  photo from a session as one zip, through a private link that expires after
  an hour.
- **Admin portal** (`/#/admin`, or **Admin** in the account menu, shown only to
  admins): every session; ad hoc sessions for family and friends, shared by
  email; uploading a session's photos; **Make photos available**; a message to
  copy and send to the family; and choosing the home page photos. See "Admin
  portal".

## Tech stack

- Flutter 3.47.7 (Material 3), **web target only**
- Firebase: Core, Auth (Google; a custom claim marks admins), Firestore,
  Storage, Cloud Functions, Hosting (project `brookie-babies`)
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
| Check the rules before deploying (read-only) | `bash scripts/test-rules.sh` (see [Deploying the backend](#deploying-the-backend)) |
| Deploy functions and rules by hand | `firebase deploy --only functions,firestore:rules,storage` (CI does this on pushes to `main`; see [Deploying the backend](#deploying-the-backend)) |
| Make an account an admin (owner) | `bash scripts/grant-admin.sh <email>` (`--revoke` to undo; see [Admin portal](#admin-portal)) |

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
  main.dart          App entry point, Firebase init, theme, routes, the
                     browser's leave-page warning
  theme/             The design system: colors, type, spacing, Material theme
  models/            Data types (signed-in user, booking, packages, session times,
                     ad hoc session details, picked and stored photos)
  services/          Auth, bookings, photo downloads, home page photos, the admin
                     service and the rules' limits in Dart (photo_rules.dart),
                     app-wide services, Stripe Payment Links
  pages/             Home, Book a session and Your sessions screens, and the
                     admin pages (Admin, one session, the session form, Home
                     page photos)
  components/        Page sections (hero, featured photos, packages, calendar,
                     session times, footer, account button, sign-in dialog,
                     booking card, and for the admin pages: the gate, session
                     cards, upload progress, home page photo order and library)
  widgets/           Reusable widgets (top bar, package card, session slot,
                     status tags, focus ring, photos, dialogs, busy button)
  utilities/         Date and browser helpers, the upload queue, the file picker,
                     the leave-page warning
assets/              Logo and fonts
web/                 Web shell (index.html, manifest, icons)
functions/           Cloud Functions (TypeScript, Node 24): getGalleryDownloadUrl
firestore.rules      Firestore security rules (families read their own bookings and
                     ad hoc sessions shared with their email; admins manage sessions
                     and the home page photo choice)
storage.rules        Storage security rules (the home page photo library is public;
                     admins upload and delete photos; nothing is overwritten)
scripts/             Owner scripts: one-time Google Cloud and GitHub setup, and
                     grant-admin.sh
.github/workflows/   CI: analyze, test, build and deploy (ci.yml)
```

See [AGENT.md](AGENT.md) for an architectural walkthrough, conventions and known issues.

## Admin portal

Brooke's tools live on the site itself, at https://brookie-babies.web.app/#/admin,
or **Admin** in the account menu (shown only to admins). Admins can:

- see every session, paid bookings and ad hoc ones, upcoming and past, with
  whether its photos are ready to download. A booking the app can't read (a
  typo in one entered by hand) is listed with its document ID and what's wrong,
  to fix in the Firestore console;
- add, edit and delete ad hoc sessions for family and friends (see "Ad hoc
  sessions");
- upload and delete a session's photos, make them available or hide them, and
  copy a message for the family (see "Delivering photos");
- choose and order the home page photos, and upload photos to their library or
  delete them (see "Home page photos").

A paid booking's details (date, time, `uid`) can't be changed in the portal;
use the Firestore console. Anyone who isn't an admin is asked to sign in with
the studio's Google account, or told their account isn't an admin. The
security rules enforce this, not only the page.

**Making someone an admin.** Admins are Google accounts with the Firebase Auth
custom claim `admin: true`. The person signs in to the site with Google once.
Then, as the project owner, from the repository root (it needs the Google
Cloud CLI and `jq`: `brew install --cask gcloud-cli` and `brew install jq`):

```bash
gcloud auth login            # as the project owner, once
bash scripts/grant-admin.sh brooke@example.com
```

They refresh the site, and **Admin** appears in their account menu. To take it
away, run `bash scripts/grant-admin.sh <email> --revoke`. That also signs them
out everywhere, but a sign-in they already have keeps admin access until it
expires, which can take up to an hour. The script only grants to a Google
account with a verified email that is the only account using it. It prints
only the account's uid, email, sign-in providers and claims, never the access
token. It's safe to re-run.

## Home page photos

The home page shows up to seven photos from Storage → `_admin/gallery` (the
photo library). The **first is the full-screen photo** behind the logo, so
choose one whose subject's face is clear of the center (the logo covers the
middle). The next six appear below the introduction, in full rows only (three
across on wider screens, two on phones; a leftover photo is left out).

Choose them in the admin portal: **Admin → Edit home page photos**. Under a
library photo, **On the home page** adds it (up to seven). **Move up**, **Move
down** and **Remove** set the order, and the page says how many of the photos
below the introduction wide screens and phones will show. **Save home page**
saves the choice in Firestore as `site/home` (the file names, in order), and
the site shows it at once. Saving with none chosen leaves the home page
without photos.

**Upload photos** on the same page adds photos to the library: JPEG, PNG or
WebP, each under 20 MB, named `.jpg`, `.jpeg`, `.png` or `.webp` (export iPhone
HEIC photos as JPEG first). A photo whose name is already in the library is
skipped, never overwritten: to replace one, delete it and upload it again. A
photo on the home page can't be deleted until you remove it from the home page
and save. Files the site can't show, such as HEIC, are listed under "Other
files" and can be deleted.

Until the first save (no `site/home` yet), or if `site/home` can't be read
within 3 seconds, the site falls back to the first seven JPEG, PNG or WebP
files in `_admin/gallery` by file name, skipping hidden files such as
`.DS_Store`; if the chosen photos arrive later, it switches to them. The
portal starts from those, so saving keeps them. Until that first save, a new
upload that sorts first by name changes the live home page at once (the page
says so by **Upload photos**).

> **Everything in `_admin/gallery` is public.** Anyone can list the folder and download every file in it, whether it's on the home page or not. Don't upload clients' photos there without their permission, and never put a family's session photos there.

## Delivering photos

Families download their photos from **Your sessions** once the session's `photosReady` is `true` and its `status` is `paid` or `adhoc`. The **Download all photos** button appears on the session's card even before the session date, so check that the session is right before making its photos available. Photos are never public through the site: families get a zip download link that expires after one hour. Hiding the photos, deleting one, or changing who an ad hoc session is shared with also deletes the cached zip, so links already handed out stop working at once (if that delete fails, the change still goes through and those links expire within the hour).

### In the admin portal

1. **Open the session** from **Admin**. A paid booking appears there once it's in Firestore (for now you add those by hand; see "Adding a paid booking by hand"). For family and friends, **Add a session** first (see "Ad hoc sessions").
2. **Upload photos** and pick the edited photos: any image type, each under 100 MB. They upload three at a time; keep the page open until they finish (leaving or closing the tab asks first, and stops them). A photo whose name is already in the session is skipped, never overwritten, so after a problem you can pick the whole folder again. To replace a photo, delete it first. **Retry failed** tries failed ones again.
3. **Make photos available.** It becomes the page's main button once there are photos and nothing is still uploading or failed, and it asks first, saying how many photos and who can download them. **Hide photos** stops downloads again. **Delete all photos** on a session whose photos are available hides them first, so a family never downloads a half-deleted gallery.
4. **Tell the family.** Under **Share with the family**, **Copy message** copies a note with the link to Your sessions and the Google account to sign in with, ready to paste into an email or a text. The site doesn't email families itself.

The first download builds a zip of the whole folder, which can take a few minutes for a large gallery. Later downloads reuse it. If you add, replace or delete photos afterwards, the next download rebuilds the zip automatically; families who already downloaded need to download again to get the changes. (If you replace a photo while a family's download is being built, that one download may contain the old version.)

### Ad hoc sessions

An ad hoc session is for family, friends and anyone not booked on the site: no payment, and no `uid`. It's a `bookings` document with `status` `adhoc`, shared by email: whoever signs in to the site with Google as that email, verified by Google, sees it under **Your sessions** (with no payment tag) and can download its photos once they're available.

**Admin → Add a session**: a name (who it's for, such as "The Harper family"), the email they use to sign in to Google (exactly as their Google account shows it: Google sign-in accepts `janedoe@gmail.com` for `jane.doe@gmail.com`, but the site matches the account's own address, dots included; the form refuses addresses no Google sign-in could match, such as ones with angle brackets, `mailto:`, spaces or a Gmail `+tag`), a date, and optionally a package, time and location. **Add session** opens its page, ready for photos. **Edit details** changes them; changing the email of a session whose photos are available asks first, because it hands the photos to the new address. **Delete session** deletes the session and its photos for good. Only ad hoc sessions can be edited or deleted in the portal. A family signed in with a different Google account sees, under Your sessions, which account they're signed in as, so they can switch.

**Add ad hoc sessions in the portal, not in the Firebase console.** The portal writes exactly what the rules and the download function check. A session typed in the console with `status` other than exactly `adhoc`, or an email with a capital letter or a space, is shared with nobody.

> **Never set `status` to `adhoc` on a hand-entered paid booking.** Its email came from the Stripe Payment Link, which anyone can edit (`locked_prefilled_email`), so as an ad hoc session that email would become the key to the photos. Paid bookings are shared by `uid` only, after the check below.

The portal saves these fields:

| Field | Type | Value |
|---|---|---|
| `status` | string | `adhoc`, exactly |
| `name` | string | Who it's for, 1 to 100 characters |
| `email` | string | The guest's Google email, trimmed and lowercase |
| `packageName` | string | Optional: `Basic`, `Premium` or `Ultimate` |
| `date` | string | `YYYY-MM-DD` |
| `time` | string | Optional: 24-hour `HH:mm` |
| `location` | string | Optional: up to 200 characters |
| `photosReady` | boolean | `false` until you make the photos available |
| `createdAt`, `createdBy` | timestamp, string | When it was added, and the admin's uid |
| `updatedAt` | timestamp | When the portal last changed it (set on any booking it changes) |

### Adding a paid booking by hand

Nothing on the site records paid bookings yet. For a payment made through a Stripe Payment Link: Firestore Database → `bookings` → **Add document** → **Auto-ID** (keep the Auto-ID: downloads need a document ID of letters, numbers, `-` and `_` only, and the session page warns about any other), with these fields:

| Field | Type | Value |
|---|---|---|
| `uid` | string | **Required.** The customer's Firebase user ID: the `client_reference_id` on their Stripe payment's Checkout Session |
| `email` | string | The customer's email |
| `name` | string | Optional: who it's for, shown on the Admin page (otherwise the email) |
| `packageName` | string | `Basic`, `Premium` or `Ultimate` |
| `date` | string | Session date as `YYYY-MM-DD`, for example `2026-11-03` |
| `time` | string | 24-hour `HH:mm`, for example `14:30` (optional) |
| `location` | string | Optional |
| `status` | string | `paid` |
| `photosReady` | boolean | `false` until the photos are uploaded |
| `createdAt` | timestamp | Now |

**Check the uid before saving: the booking gives that account access to the photos.** Anyone can edit `client_reference_id` in a Payment Link address, and the email on the Stripe payment comes from the same editable link (`locked_prefilled_email`), so neither proves who paid. Look up the uid under **Authentication → Users** and compare its email and name with what you know from outside Stripe, such as the email the customer used to arrange the session, and with the cardholder name on the Stripe payment. If they don't match, confirm with the customer before setting `uid`.

Then deliver its photos in the portal as above. Its share message tells the family to sign in with the Google account they booked with.

### In the Firebase console (fallback)

The portal is the easier way, but the console still works:

1. **Find the booking ID.** Firestore Database → `bookings`. Find the booking by `email` and `date`. The document ID is the booking ID.
2. **Upload the photos.** Storage → open `galleries` (create it if needed) → **Create folder** named exactly the booking ID → upload the photos into it. Subfolders are fine; the portal lists them too. Hidden files such as `.DS_Store` are skipped. Never put customer photos in `_admin/gallery/`: that folder is public (it's the home page photo library).
3. **Mark them ready.** Open the booking again and set the field `photosReady` (type **boolean**) to `true`. Do this only after every upload has finished.

> **Never share the Storage console's file links.** For every uploaded file, the console shows a download link with an access token. Anyone with that link can open the photo, permanently, whatever the security rules say. Families should only get their photos through **Your sessions**. If a link was shared by mistake, revoke that file's access token (Storage → the file → Access token → Revoke).

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

`functions/` holds the Cloud Functions, and `firestore.rules` and `storage.rules` hold the security rules. They were first deployed by hand on 2026-10-17. CI deploys them on pushes to `main` once the repository variable `BACKEND_DEPLOY_LIVE` is `true` (see "Automatic backend deploys"); until then its backend job is a dry run, so deploy them by hand before merging a site that needs them (see "Deploy order"). Do the one-time setup below **before** the change that added this reaches `main`.

These files are the source of truth: each deploy **replaces the Firestore and Storage rules set in the Firebase console**, so change rules here, not in the console. Only `_admin/gallery/` (the home page photo library) and `site/home` (which of its photos the home page shows) are publicly readable, families can read only their own bookings and the ad hoc sessions shared with them, and only admins can write from the app.

#### What the rules allow

Admins are accounts whose ID token carries the custom claim `admin: true` (see "Admin portal"); both rules files check it the same way. The admin pages write straight from the browser, so the rules are the only check on what they write. The app checks the same limits first (`lib/services/photo_rules.dart`, `lib/services/admin_service.dart`), so change them together.

- **Bookings.** A family reads the bookings carrying their `uid`, and ad hoc sessions (`status` exactly `adhoc`) whose `email` is the email they verified with Google, lowercased. Admins read every booking. They create only ad hoc sessions (the fields in "Ad hoc sessions", never a `uid`), change only `photosReady` on other bookings and only the details and `photosReady` of ad hoc sessions, stamping `updatedAt` each time, and delete only ad hoc sessions. `uid`, `status`, `createdAt` and `createdBy` never change.
- **`site/home`.** Anyone reads it. Admins save it whole: `photos` (at most seven file names), `updatedAt` and `updatedBy`.
- **Storage.** `_admin/gallery/` stays publicly readable (get and list). Admins add photos directly in it (JPEG, PNG or WebP, named `.jpg`, `.jpeg`, `.png` or `.webp`, under 20 MiB) and delete them. Under `galleries/<bookingId>/` only admins read, add (any image type, under 100 MiB) and delete. Admins may delete a cached zip in `gallery-zips/`, nothing more. There's no update anywhere, so nothing is ever overwritten.
- **`getGalleryDownloadUrl`** serves the same people: the booking's `uid`, or for an ad hoc session the caller whose verified Google email matches. Ad hoc sessions need no payment.

No new IAM roles, function permissions, APIs or secrets are needed: the function reads the same bookings and bucket as before, and everything admins do goes through the rules.

CI doesn't evaluate the rules (it has no emulator); `flutter test` only checks that the app's limits match them. Before you deploy a rules change, compile it with `firebase deploy --only firestore:rules,storage --dry-run`, then check it against the cases in `rules-tests/`:

```bash
gcloud auth login            # once, as the owner
bash scripts/test-rules.sh   # "firestore.rules: 149 of 149 cases pass", then storage.rules
```

Both are read-only: the script sends the rules and each case to the Firebase Rules API's test endpoint (`projects/brookie-babies:test`), which deploys nothing and reads no live data, and it never prints your access token. It lists any case that fails and exits with an error. Add cases to `rules-tests/firestore-cases.mjs` or `rules-tests/storage-cases.mjs` for what you change. Never test rules by writing to the live project.

#### Deploy order

Deploy the rules and the function **before** (or with) the site that relies on them. A site that's already live keeps working with newer rules and function (today's site only asks for what the new ones still allow). If a new site goes live first:

- the query for ad hoc sessions shared by email is refused, so families see only their own bookings (it's logged, nothing breaks);
- reading `site/home` is refused, so the home page falls back to the first seven photos by name;
- admins' reads and writes are refused, so the admin pages say they couldn't load or save;
- with the new rules but the old function, guests see their ad hoc session but its download fails ("We couldn’t find this session’s photos").

On pushes to `main`, CI deploys the backend before the site, but only once `BACKEND_DEPLOY_LIVE` is `true` (see below). Until then, deploy backend changes by hand from their branch before merging it (see "Deploying by hand").

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
- **"Could not build the function due to a missing permission on the build service account":** the functions are built as `375587092017-compute@developer.gserviceaccount.com`, which needs the build grants in `scripts/setup-functions-runtime.sh` (see "Function runtime permissions"). Run the script, wait about 5 minutes, then re-run the failed job. The build log is empty when this happens, because the account can't write logs either; `gcloud builds describe <build id> --region=us-central1 --project=brookie-babies` shows which step failed (`gcs-fetcher` means it couldn't read the source) and a warning about the missing Logs Writer role. Don't fix it with Editor or the project-wide Cloud Build roles.

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

**Deploying by hand** still works. Run it from an up-to-date `main`, except when you deploy a new trigger type (above) or rules and functions a branch's site needs (see "Deploy order") from that branch:

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

The same account also **builds** the functions. Since 2024 Cloud Build uses the default compute account for projects like this one (it has no organization, so the old Cloud Build account can't be chosen, and neither firebase-tools nor firebase-functions can name another build account). The first deploy only worked because the account still had the Editor role Google grants it by default; removing Editor on 2026-10-17 left it unable to build. The script gives it Google's documented minimum for a build account, each as narrow as it can be:

- **Fetching the uploaded source:** `roles/storage.objectViewer` on the `gcf-v2-sources-375587092017-us-central1` bucket only.
- **Saving the built image:** `roles/artifactregistry.writer` on the `gcf-artifacts` repository only.
- **Writing build logs:** `roles/logging.logWriter` (project; it can't be granted lower).

Never fix a failed build with Editor or `roles/cloudbuild.builds.builder`: this account also runs `getGalleryDownloadUrl`, and those roles reach every bucket, families' photos included. Even these narrow grants let the running function write to `gcf-artifacts`, the next build's image cache; giving the functions their own runtime account (`setGlobalOptions({serviceAccount})`, on the TODO list) would leave the compute account only building.

When a new function needs other data, add the role to this script, scoped as narrowly as possible.

Optional: add a Storage lifecycle rule that deletes objects under `gallery-zips/` after 30 days to save storage. Zips are rebuilt automatically the next time someone downloads.
