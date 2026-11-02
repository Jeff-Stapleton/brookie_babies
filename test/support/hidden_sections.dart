// The home page sections the site hides until Brooke settles them
// (HomePage.showsIntroduction, HomePage.offersPackages), shown for one test.

import 'package:brookie_babies/pages/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shows the home page's introduction for the rest of the test.
void showIntroduction() {
  final was = HomePage.showsIntroduction;
  HomePage.showsIntroduction = true;
  addTearDown(() => HomePage.showsIntroduction = was);
}

/// Offers the packages for the rest of the test: the home page's packages,
/// "Book a session" in the hero and "See packages" on the other pages.
void offerPackages() {
  final was = HomePage.offersPackages;
  HomePage.offersPackages = true;
  addTearDown(() => HomePage.offersPackages = was);
}
