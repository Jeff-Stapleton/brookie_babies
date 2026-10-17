# TODO

Open items for sign-in, bookings, photo downloads and site content. Last updated 2026-10-17 (design-system restyle).

## 1. Test photo downloads

- [ ] **First, give the function access to bookings and photos:**
      `bash scripts/setup-functions-runtime.sh` from the repo root. Without
      it, downloads fail: the function's runtime account can't read
      Firestore or Storage yet.

PR #7 is merged and the backend is deployed: the `getGalleryDownloadUrl`
function, the Firestore and Storage rules, and the signing permission. What's
left is one real download, on the live site: https://brookie-babies.web.app

- [ ] **Sign in** on the site with your Google account.
- [ ] **Copy your user ID:** Firebase console → Authentication → Users →
      your account's **User UID**.
- [ ] **Create a test booking:** Firestore Database → Start collection
      `bookings` → Auto-ID, with these fields:
      | Field | Type | Value |
      |---|---|---|
      | `uid` | string | your User UID |
      | `packageName` | string | `Premium` |
      | `date` | string | `2026-10-10` |
      | `status` | string | `paid` |
      | `photosReady` | boolean | `true` |

      Copy the generated document ID.
- [ ] **Upload photos:** Storage → folder `galleries` → folder named exactly
      that document ID → upload 2 or 3 photos.
- [ ] **Download:** open the avatar menu → **Your sessions**.
      The booking shows under **Past**. Click **Download all photos**: you
      should see "Preparing your photos…", then a zip downloads.
- [ ] **Privacy check:** sign in with a second Google account; it should
      show no sessions.
- [ ] Optional: delete the test booking and its `galleries/` folder.

If the download fails, note the message shown on the page. The function's
logs explain why: run `firebase functions:log`, or open Firebase console →
Functions → getGalleryDownloadUrl → Logs.

## 2. Security follow-ups (skip any you've already done)

- [ ] **Roll the old Stripe live secret key** in the Stripe Dashboard
      (Developers → API keys). It's still in this public repo's git history.
      Then check Developers → Logs and Webhooks for anything you don't
      recognize.
- [ ] **Delete the `firebase-adminsdk` service account key** downloaded on
      2026-10-16: Google Cloud Console → IAM & Admin → Service Accounts →
      `firebase-adminsdk-…` → Keys → delete it. Then delete the `.json` file
      from Downloads. Nothing in the app uses it.

## 3. Settings now that sign-in is live

- [ ] **Stripe:** for each of the three Payment Links, set **After payment**
      to redirect to `https://brookie-babies.web.app`. Checkout now opens in
      the same tab, so without a redirect customers have no way back to the
      site.
- [ ] **Firebase console → Authentication → Sign-in method → Google:** set
      the public-facing project name and support email. Both appear on
      Google's sign-in screen.

## 4. Next development

- [ ] **Server-side Stripe checkout**, so bookings, with their date and
      time, are recorded automatically and Payment Links are no longer
      needed. Needed from you first:
  - a Stripe **test-mode restricted key**
  - the **Price IDs** for Basic, Premium and Ultimate
  - the **real session schedule**: days, start times, session length,
    address and timezone
- [ ] **Turn on automatic backend deploys** (README, "Automatic backend
      deploys"):
  1. `brew install --cask gcloud-cli`, then `gcloud auth login`.
  2. From the repo root: `bash scripts/setup-gcp-deployer.sh`.
  3. `bash scripts/setup-github-production.sh` (while nothing is merging).
  4. Wait about 5 minutes, then merge the CI pull request. Its push to `main`
     runs **Deploy functions and rules** as a dry run. Check that it's green.
  5. `gh variable set BACKEND_DEPLOY_LIVE --body true`, then watch the next
     run (the first real deploy).
- [ ] **Hardening (optional, after the above):**
  - Move the Hosting deploy key `FIREBASE_SERVICE_ACCOUNT_BROOKIE_BABIES` into
    a `production` environment secret (any branch can read it today), or
    switch Hosting deploys to keyless sign-in too.
  - Give the functions a dedicated runtime service account with only what
    they need (Firestore, the Storage bucket, signing their own links)
    instead of the default compute account. This is worth doing if the setup
    script warns that the compute account has Editor.
  - Add a branch ruleset on `main` that blocks force-pushes and deletion.

## 5. Site content needed from Brooke

The site now follows the design system; these are facts only the studio can
supply. Each lives in one place in the code.

- [ ] **Hero photo:** today the first file in `_admin/gallery` is a portrait
      with the face in the center, so the logo covers it. Choose a photo with
      the face clear of the middle and rename it to sort first (README, "Home
      page photos").
- [ ] **What each package includes:** all three list the same inclusions
      (`lib/models/session_package.dart`), so families would pay more for
      nothing. Optionally add a one-sentence description per package.
- [ ] **Session times and length:** the booking page offers 9, 10, 11 am, 1 and
      2 pm every day, 30 minutes each (`lib/models/session_time.dart`), while
      the packages say "15-minute session". Which days and times, how long,
      and how much notice?
- [ ] **Address line:** every time says "Address sent after you book". Is that
      what happens, and who sends it?
- [ ] **Contact and social links:** the footer has none, and one error message
      says "Let Brooke know". An email address (and Instagram, if wanted)
      would give families a way to reach the studio.
- [ ] **Introduction copy:** "Little ones, while they’re little" and "Calm,
      unhurried sessions for newborns, babies and the people who hold them."
      are drafts from the design system.
- [ ] **Logo for dark backgrounds:** the black brush strokes past the disc
      nearly disappear on the dark theme (footer, loading screen, browser
      tab). A light-ink version would fix that.
- [ ] **Stripe Checkout branding:** in the Stripe Dashboard, set the accent
      color to ink `#1C1B19`, the background to paper `#F6F6F3`, and the logo
      as the icon, so the payment page matches the site.
- [ ] **Custom domain:** link previews point at https://brookie-babies.web.app/;
      update `web/index.html` if the site moves to its own domain.
