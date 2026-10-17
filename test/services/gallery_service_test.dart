import 'package:brookie_babies/services/gallery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("shows the function's message for failed-precondition", () {
    expect(galleryErrorMessage('failed-precondition', 'Your photos aren’t ready yet.'),
        'Your photos aren’t ready yet.');
    expect(galleryErrorMessage('failed-precondition', null), 'Your photos aren’t ready yet.');
  });

  test('hides other server messages behind friendly ones', () {
    expect(galleryErrorMessage('not-found', 'No booking abc'),
        'We couldn’t find this session’s photos. Refresh the page to try again.');
    expect(galleryErrorMessage('internal', 'stack trace...'), kGalleryErrorFallback);
  });

  test('an expired sign-in says what happened and how to fix it', () {
    expect(galleryErrorMessage('unauthenticated', 'Sign in first.'),
        'Your sign-in has expired. Sign out, sign in again, then download your photos.');
  });

  test('client messages use typographic apostrophes', () {
    for (final code in ['failed-precondition', 'not-found', 'unauthenticated', 'internal', 'deadline-exceeded']) {
      expect(galleryErrorMessage(code, null), isNot(contains("'")), reason: code);
    }
  });
}
