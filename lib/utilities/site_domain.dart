import 'package:firebase_core/firebase_core.dart';

/// The studio's own domain, where the site lives. Firebase Hosting also serves
/// it on brookie-babies.web.app and brookie-babies.firebaseapp.com, which
/// web/index.html sends on to this domain.
const siteDomain = 'brookestapletonphoto.com';

/// [options] for the page at [page]. Served from [siteDomain], Google sign-in
/// goes through that domain's own `/__/auth/handler`, so Google's account
/// chooser names it instead of brookie-babies.firebaseapp.com. Anywhere else
/// (web.app, preview channels, localhost) keeps the generated auth domain,
/// which works from every host.
FirebaseOptions withSiteAuthDomain(FirebaseOptions options, Uri page) =>
    page.host == siteDomain ? options.copyWith(authDomain: siteDomain) : options;
