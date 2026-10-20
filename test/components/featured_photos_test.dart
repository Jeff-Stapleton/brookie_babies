import 'package:brookie_babies/components/featured_photos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shownCount: full rows only, of three on wide screens and two on phones', () {
    // n photos after the hero → how many the grid shows.
    const wide = [0, 0, 2, 3, 3, 3, 6, 6];
    const phone = [0, 0, 2, 2, 4, 4, 6, 6];

    for (var n = 0; n <= 7; n++) {
      test('$n photos', () {
        expect(FeaturedPhotos.shownCount(n, wide: true), wide[n], reason: 'wide');
        expect(FeaturedPhotos.shownCount(n, wide: false), phone[n], reason: 'phone');
      });
    }

    test('never more than maxCount', () {
      expect(FeaturedPhotos.shownCount(20, wide: true), FeaturedPhotos.maxCount);
      expect(FeaturedPhotos.shownCount(20, wide: false), FeaturedPhotos.maxCount);
    });
  });
}
