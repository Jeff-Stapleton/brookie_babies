import 'package:brookie_babies/components/featured_photos.dart';
import 'package:brookie_babies/models/session_package.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/services/portfolio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _mb = 1024 * 1024;

void main() {
  group('contentTypeFor', () {
    test('takes the browser’s type, lowercase', () {
      expect(PhotoRules.contentTypeFor(testPhoto('a.jpg', contentType: 'image/png')), 'image/png');
      expect(PhotoRules.contentTypeFor(testPhoto('a.heic', contentType: ' Image/HEIC ')), 'image/heic');
    });

    test('reads old browsers’ names for JPEG as image/jpeg', () {
      expect(PhotoRules.contentTypeFor(testPhoto('a.jpg', contentType: 'image/jpg')), 'image/jpeg');
      expect(PhotoRules.contentTypeFor(testPhoto('a.jpg', contentType: 'image/pjpeg')), 'image/jpeg');
    });

    test('goes by the extension, in any case, when the browser doesn’t say', () {
      for (final (name, type) in [
        ('a.jpg', 'image/jpeg'),
        ('a.JPEG', 'image/jpeg'),
        ('a.png', 'image/png'),
        ('a.WebP', 'image/webp'),
        ('IMG_1.HEIC', 'image/heic'),
        ('a.heif', 'image/heif'),
        ('a.gif', 'image/gif'),
        ('a.tif', 'image/tiff'),
        ('a.tiff', 'image/tiff'),
        ('archive.tar.png', 'image/png'),
      ]) {
        expect(PhotoRules.contentTypeFor(testPhoto(name, contentType: '')), type, reason: name);
      }
    });

    test('null when neither says', () {
      for (final name in ['notes.txt', 'IMG_1', 'a.', '']) {
        expect(PhotoRules.contentTypeFor(testPhoto(name, contentType: '')), isNull, reason: name);
      }
    });
  });

  test('safeObjectName replaces what Storage advises against, and slashes', () {
    expect(PhotoRules.safeObjectName('IMG_1.jpg'), 'IMG_1.jpg');
    expect(PhotoRules.safeObjectName('Harper #1 [edit]*?.jpg'), 'Harper _1 _edit___.jpg');
    expect(PhotoRules.safeObjectName('a/b.jpg'), 'a_b.jpg');
    expect(PhotoRules.safeObjectName('tab\there\n.jpg'), 'tab_here_.jpg');
    expect(PhotoRules.safeObjectName('del\x7F.jpg'), 'del_.jpg');
    // Everything else, accents and spaces included, is kept.
    expect(PhotoRules.safeObjectName('Café – 2 .jpg'), 'Café – 2 .jpg');
  });

  test('safeObjectName is never empty, "." or ".."', () {
    expect(PhotoRules.safeObjectName(''), 'photo');
    expect(PhotoRules.safeObjectName('.'), '_');
    expect(PhotoRules.safeObjectName('..'), '__');
  });

  group('sessionPhotoProblem', () {
    test('takes any image under 100 MB', () {
      for (final photo in [
        testPhoto('a.jpg'),
        testPhoto('IMG_1.HEIC', contentType: ''),
        testPhoto('a.tiff', contentType: 'image/tiff'),
        testPhoto('big.png', size: PhotoRules.sessionMaxBytes - 1),
        testPhoto('tiny.jpg', size: 1),
      ]) {
        expect(PhotoRules.sessionPhotoProblem(photo), isNull, reason: photo.name);
      }
    });

    test('says what’s wrong, by name', () {
      expect(PhotoRules.sessionPhotoProblem(testPhoto('notes.txt', contentType: 'text/plain')),
          'notes.txt isn’t a photo.');
      expect(PhotoRules.sessionPhotoProblem(testPhoto('notes', contentType: '')), 'notes isn’t a photo.');
      // A Mac's metadata beside each photo on a memory card, typed by its
      // ending: the listing and the zip leave it out.
      expect(PhotoRules.sessionPhotoProblem(testPhoto('._DSC_0001.JPG', size: 4096)),
          '._DSC_0001.JPG isn’t a photo.');
      expect(PhotoRules.sessionPhotoProblem(testPhoto('.hidden.jpg')), '.hidden.jpg isn’t a photo.');
      expect(PhotoRules.sessionPhotoProblem(testPhoto('IMG_3.jpg', size: 0)), 'IMG_3.jpg is empty.');
      expect(PhotoRules.sessionPhotoProblem(testPhoto('raw.jpg', size: PhotoRules.sessionMaxBytes)),
          'raw.jpg is 100 MB. Session photos must be under 100 MB.');
      expect(PhotoRules.sessionPhotoProblem(testPhoto('raw.jpg', size: 140 * _mb + 1)),
          'raw.jpg is 141 MB. Session photos must be under 100 MB.');
    });
  });

  group('homePhotoProblem', () {
    test('takes JPEG, PNG and WebP under 20 MB', () {
      for (final photo in [
        testPhoto('a.jpg'),
        testPhoto('a.JPEG', contentType: ''),
        testPhoto('a.png', contentType: 'image/png'),
        testPhoto('a.webp', contentType: 'image/webp'),
        testPhoto('a.jpg', size: PhotoRules.homeMaxBytes - 1),
      ]) {
        expect(PhotoRules.homePhotoProblem(photo), isNull, reason: photo.name);
      }
    });

    test('says what’s wrong, by name', () {
      expect(PhotoRules.homePhotoProblem(testPhoto('IMG_1.HEIC', contentType: '')),
          'IMG_1.HEIC isn’t a JPEG, PNG or WebP. Export it as JPEG and upload it again.');
      expect(PhotoRules.homePhotoProblem(testPhoto('a.gif', contentType: 'image/gif')),
          'a.gif isn’t a JPEG, PNG or WebP. Export it as JPEG and upload it again.');
      expect(PhotoRules.homePhotoProblem(testPhoto('IMG_2.png', contentType: 'image/png', size: 24 * _mb)),
          'IMG_2.png is 24 MB. Home page photos must be under 20 MB.');
      expect(PhotoRules.homePhotoProblem(testPhoto('notes.txt', contentType: '')), 'notes.txt isn’t a photo.');
      expect(PhotoRules.homePhotoProblem(testPhoto('IMG_3.jpg', size: 0)), 'IMG_3.jpg is empty.');
    });

    test('needs a photo’s extension, so the site lists it', () {
      expect(PhotoRules.homePhotoProblem(testPhoto('IMG_4', contentType: 'image/jpeg')),
          'IMG_4 needs a .jpg, .png or .webp ending. Rename it and upload it again.');
      expect(PhotoRules.homePhotoProblem(testPhoto('.hidden.jpg')), '.hidden.jpg isn’t a photo.');
    });

    test('every photo it takes is one the home page can show', () {
      for (final name in ['a.jpg', 'b.PNG', 'c.webp', 'd #1.jpeg']) {
        final photo = testPhoto(name, contentType: '');
        expect(PhotoRules.homePhotoProblem(photo), isNull, reason: name);
        expect(StoragePortfolioService.isPhoto(PhotoRules.safeObjectName(name)), isTrue, reason: name);
      }
    });
  });

  test('the home page holds the hero and every featured photo', () {
    expect(PhotoRules.homeMaxPhotos, 1 + FeaturedPhotos.maxCount);
  });

  test('the home page library’s picker offers only what it takes', () {
    expect(PhotoRules.homeAccept.split(','), unorderedEquals(PhotoRules.homeContentTypes));
  });

  group('SessionRules', () {
    test('packages are the site’s packages', () {
      expect(SessionRules.packageNames, [for (final package in SessionPackage.all) package.name]);
    });

    test('emails are trimmed and lowercase, then need one @ and a dot after it', () {
      expect(SessionRules.normalizeEmail(' Harper@Example.COM '), 'harper@example.com');
      for (final email in ['harper@example.com', 'a.b+c@mail.co.uk']) {
        expect(SessionRules.emailPattern.hasMatch(email), isTrue, reason: email);
      }
      for (final email in ['harper', 'harper@example', 'a@b@c.com', 'a b@c.com', '@example.com', 'a@.com ']) {
        expect(SessionRules.emailPattern.hasMatch(email), isFalse, reason: email);
      }
    });
  });
}
