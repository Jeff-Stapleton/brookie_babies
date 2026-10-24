import 'package:firebase_core/firebase_core.dart';

/// The studio's own domain. Firebase Hosting serves the site on it once it's
/// connected in the console (TODO.md, "Custom domain"), alongside
/// brookie-babies.web.app.
const siteDomain = 'brookestapletonphotography.com';

/// [options] for the page at [page]. Served from [siteDomain], Google sign-in
/// goes through that domain's own `/__/auth/handler`, so Google's account
/// chooser names it instead of brookie-babies.firebaseapp.com. Anywhere else
/// (web.app, preview channels, localhost) keeps the generated auth domain,
/// which works from every host.
FirebaseOptions withSiteAuthDomain(FirebaseOptions options, Uri page) =>
    page.host == siteDomain ? options.copyWith(authDomain: siteDomain) : options;
