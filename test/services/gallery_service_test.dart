import 'package:brookie_babies/services/gallery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("shows the function's message for failed-precondition", () {
    expect(galleryErrorMessage('failed-precondition', "Your photos aren't ready yet."),
        "Your photos aren't ready yet.");
  });

  test('hides other server messages behind friendly ones', () {
    expect(galleryErrorMessage('not-found', 'No booking abc'), "We couldn't find this session.");
    expect(galleryErrorMessage('internal', 'stack trace...'), kGalleryErrorFallback);
  });
}
