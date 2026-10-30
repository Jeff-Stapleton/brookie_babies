// The words "Your sessions" shows while a zip is built and once the browser
// has it. The card itself is tested through the page
// (test/pages/profile_page_test.dart).

import 'package:brookie_babies/components/booking_card.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:flutter_test/flutter_test.dart';

GalleryProgress _at(int done, {int of = 150, int? totalBytes = 4800000000}) =>
    GalleryProgress(photosDone: done, photoCount: of, totalBytes: totalBytes);

final _zip = Uri.parse('https://storage.googleapis.com/bucket/gallery-zips/b1.zip');

void main() {
  test('the line names the photo being added, then the finishing', () {
    expect(zipProgressLine(_at(0)), 'Adding photo 1 of 150');
    expect(zipProgressLine(_at(37)), 'Adding photo 38 of 150');
    expect(zipProgressLine(_at(150)), 'Finishing your zip file');
    expect(zipProgressLine(_at(0, of: 1)), 'Adding your photo');
    expect(zipProgressLine(_at(1, of: 1)), 'Finishing your zip file');
  });

  test('the hint gives the size when it’s known', () {
    expect(
      zipProgressHint(_at(37)),
      'This can take a few minutes. Your 4.8 GB zip file starts downloading by itself when it’s ready, so keep '
      'this page open and on screen.',
    );
    expect(
      zipProgressHint(_at(37, totalBytes: null)),
      'This can take a few minutes. Your zip file starts downloading by itself when it’s ready, so keep this '
      'page open and on screen.',
    );
  });

  test('screen readers hear each quarter, then the finishing, not every photo', () {
    expect(zipProgressAnnouncement(_at(0, of: 100)), isNull);
    expect(zipProgressAnnouncement(_at(24, of: 100)), isNull);
    expect(zipProgressAnnouncement(_at(25, of: 100)), 'Preparing your photos… 25% done');
    expect(zipProgressAnnouncement(_at(50, of: 100)), 'Preparing your photos… 50% done');
    expect(zipProgressAnnouncement(_at(75, of: 100)), 'Preparing your photos… 75% done');
    expect(zipProgressAnnouncement(_at(99, of: 100)), 'Preparing your photos… 75% done');
    expect(zipProgressAnnouncement(_at(100, of: 100)), 'Preparing your photos… finishing up');
    // Each keeps the button's visible words.
    for (var done = 25; done <= 100; done++) {
      expect(zipProgressAnnouncement(_at(done, of: 100)), contains('Preparing your photos'), reason: '$done');
    }
  });

  test('the success message gives the count and the size, and how to retry', () {
    expect(
      downloadStartedMessage(GalleryDownload(url: _zip, photoCount: 150, totalBytes: 4800000000)),
      'Your download has started: 150 photos, 4.8 GB. If your browser asks, allow it; if nothing happens, '
      'choose “Download all photos” again.',
    );
    expect(
      downloadStartedMessage(GalleryDownload(url: _zip, photoCount: 150)),
      'Your download has started: 150 photos. If your browser asks, allow it; if nothing happens, choose '
      '“Download all photos” again.',
    );
    expect(
      downloadStartedMessage(GalleryDownload(url: _zip, photoCount: 1, totalBytes: 12000000)),
      startsWith('Your download has started: 1 photo, 12 MB. '),
    );
  });

  test('every message uses typographic apostrophes and quotes', () {
    final messages = [
      kDownloadInterruptedMessage,
      kOneDownloadAtATimeMessage,
      zipProgressHint(_at(37)),
      downloadStartedMessage(GalleryDownload(url: _zip, photoCount: 150)),
    ];
    for (final message in messages) {
      expect(message, isNot(contains("'")), reason: message);
      expect(message, isNot(contains('"')), reason: message);
    }
  });
}
