import 'package:brookie_babies/firebase_options.dart';
import 'package:brookie_babies/utilities/site_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const generated = DefaultFirebaseOptions.web;

  test('the site’s own domain signs in through itself', () {
    final options = withSiteAuthDomain(generated, Uri.parse('https://brookestapletonphotography.com/#/profile'));

    expect(options.authDomain, 'brookestapletonphotography.com');
    expect(options, generated.copyWith(authDomain: 'brookestapletonphotography.com'));
  });

  test('every other host keeps the generated auth domain', () {
    const pages = [
      'https://brookie-babies.web.app/',
      'https://brookie-babies.firebaseapp.com/#/admin',
      'https://brookie-babies--pr22-feat-domain-abc123.web.app/',
      'https://www.brookestapletonphotography.com/',
      'http://localhost:5000/',
    ];
    for (final page in pages) {
      expect(withSiteAuthDomain(generated, Uri.parse(page)), generated, reason: page);
    }
    expect(generated.authDomain, 'brookie-babies.firebaseapp.com');
  });
}
