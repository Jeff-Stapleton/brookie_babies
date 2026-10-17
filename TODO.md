# TODO

Open items for sign-in, bookings and photo downloads. Last updated 2026-10-17.

## 1. Test photo downloads, then merge PR #7

The backend is deployed: the `getGalleryDownloadUrl` function, the Firestore
and Storage rules, and the signing permission. What's left is one real
download.

Preview: https://brookie-babies--pr7-feat-profile-page-zycqsulq.web.app
(preview links expire 7 days after the last push to the PR).

- [ ] **Sign in** on the preview with your Google account.
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
- [ ] **Download:** on the preview, open the avatar menu → **My sessions**.
      The booking shows under **Past**. Click **Download all photos**: you
      should see "Preparing your photos…", then a zip downloads.
- [ ] **Privacy check:** sign in with a second Google account; it should
      show no sessions.
- [ ] **Merge PR #7** once the download works.
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
- [ ] Optional: **deploy functions and rules from CI** on merges to `main`.
      Pick keyless GitHub-to-Google sign-in (Workload Identity Federation,
      recommended) or a deploy-only service account key.
