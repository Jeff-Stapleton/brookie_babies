import 'dart:async';

import 'package:brookie_babies/services/gallery_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

/// A progress chunk as the function sends it.
Map<String, Object?> _chunk(Object? done, Object? count, [Object? totalBytes = 4800000000]) =>
    {'stage': 'zipping', 'photosDone': done, 'photoCount': count, 'totalBytes': totalBytes};

GalleryCallEvent _progress(Object? data) => (isResult: false, data: data);

GalleryCallEvent _result(Object? data) => (isResult: true, data: data);

const _link = 'https://storage.googleapis.com/bucket/gallery-zips/b1.zip?X-Goog-Signature=abc';

/// The function's final answer.
final _answer = {'url': _link, 'photoCount': 150, 'expiresAt': '2026-10-25T12:00:00.000Z', 'totalBytes': 4800000000};

void main() {
  test("shows the function's message for failed-precondition", () {
    expect(galleryErrorMessage('failed-precondition', 'Your photos aren’t ready yet.'),
        'Your photos aren’t ready yet.');
    expect(galleryErrorMessage('failed-precondition', null), 'Your photos aren’t ready yet.');
  });

  test('leaves out the status the JS SDK adds to a message', () {
    expect(galleryErrorMessage('failed-precondition', 'This session isn’t paid for yet. [0]'),
        'This session isn’t paid for yet.');
    expect(galleryErrorMessage('failed-precondition', 'Your photos aren’t ready yet. [400]'),
        'Your photos aren’t ready yet.');
    // Nothing left but the status: the usual words.
    expect(galleryErrorMessage('failed-precondition', '[400]'), 'Your photos aren’t ready yet.');
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
    expect(kGalleryErrorFallback, isNot(contains("'")));
    expect(kGalleryErrorFallback, isNot(contains('"')));
  });

  test('isFallback: only for the generic message', () {
    expect(const GalleryException(kGalleryErrorFallback).isFallback, isTrue);
    expect(const GalleryException('Your photos aren’t ready yet.').isFallback, isFalse);
  });

  group('GalleryProgress.fromChunk', () {
    test('reads a chunk, ints or doubles alike', () {
      final progress = GalleryProgress.fromChunk(_chunk(37, 150))!;
      expect(progress.photosDone, 37);
      expect(progress.photoCount, 150);
      expect(progress.totalBytes, 4800000000);

      // What dartify can hand back for the same chunk.
      final doubles = GalleryProgress.fromChunk(_chunk(37.0, 150.0, 4800000000.0))!;
      expect([doubles.photosDone, doubles.photoCount, doubles.totalBytes], [37, 150, 4800000000]);
    });

    test('a missing, null or 0 totalBytes is unknown', () {
      expect(GalleryProgress.fromChunk({'stage': 'zipping', 'photosDone': 0, 'photoCount': 3})!.totalBytes, isNull);
      expect(GalleryProgress.fromChunk(_chunk(0, 3, null))!.totalBytes, isNull);
      expect(GalleryProgress.fromChunk(_chunk(0, 3, 0))!.totalBytes, isNull);
    });

    test('anything else is ignored, so a newer function can’t fail the download', () {
      final bad = <Object?>[
        null,
        'zipping',
        [0, 3],
        {..._chunk(0, 3), 'stage': 'uploading'},
        {'photoCount': 3, 'totalBytes': 1},
        {'stage': 'zipping', 'photosDone': 0},
        {'stage': 'zipping', 'photoCount': 3},
        _chunk('37', 150),
        _chunk(37, '150'),
        _chunk(-1, 150),
        _chunk(37, -150),
        _chunk(double.nan, 150),
        _chunk(37, double.infinity),
        _chunk(37, 150, '4800000000'),
        _chunk(37, 150, -1),
        _chunk(0, 0),
      ];
      for (final data in bad) {
        expect(GalleryProgress.fromChunk(data), isNull, reason: '$data');
      }
    });

    test('photosDone never passes photoCount', () {
      expect(GalleryProgress.fromChunk(_chunk(151, 150))!.photosDone, 150);
    });
  });

  test('fraction and finishing go by photos', () {
    const start = GalleryProgress(photosDone: 0, photoCount: 150);
    const middle = GalleryProgress(photosDone: 75, photoCount: 150);
    const done = GalleryProgress(photosDone: 150, photoCount: 150);
    expect([start.fraction, middle.fraction, done.fraction], [0, 0.5, 1]);
    expect([start.finishing, middle.finishing, done.finishing], [false, false, true]);
  });

  group('parseGalleryDownload', () {
    test('reads the link, the count and the size', () {
      final download = parseGalleryDownload(_answer);
      expect(download.url, Uri.parse(_link));
      expect(download.photoCount, 150);
      expect(download.totalBytes, 4800000000);
    });

    test('a function too old to say, or a size it couldn’t list, has no size', () {
      expect(parseGalleryDownload({'url': _link, 'photoCount': 3}).totalBytes, isNull);
      expect(parseGalleryDownload({'url': _link, 'photoCount': 3, 'totalBytes': null}).totalBytes, isNull);
      final zero = parseGalleryDownload({'url': _link, 'photoCount': 3.0, 'totalBytes': 0});
      expect(zero.photoCount, 3);
      expect(zero.totalBytes, isNull);
    });

    test('anything else is the generic failure', () {
      for (final data in <Object?>[null, 'https://example.com', {'url': _link}, {'photoCount': 3}]) {
        expect(
          () => parseGalleryDownload(data),
          throwsA(isA<GalleryException>().having((e) => e.isFallback, 'isFallback', isTrue)),
          reason: '$data',
        );
      }
    });
  });

  group('readGalleryDownload', () {
    Matcher fails(String message) => throwsA(isA<GalleryException>().having((e) => e.message, 'message', message));

    test('hands each chunk to onProgress in order, then returns the link', () async {
      final seen = <int>[];
      final download = await readGalleryDownload(
        Stream.fromIterable([
          _progress(_chunk(0, 3)),
          _progress(_chunk(1, 3)),
          _progress(_chunk(3, 3)),
          _result(_answer),
        ]),
        onProgress: (progress) => seen.add(progress.photosDone),
      );

      expect(seen, [0, 1, 3]);
      expect(download.url, Uri.parse(_link));
      expect(download.totalBytes, 4800000000);
    });

    test('a result alone (a zip already built, or an older function) gives no progress', () async {
      var heard = 0;
      final download = await readGalleryDownload(
        Stream.value(_result({'url': _link, 'photoCount': 3})),
        onProgress: (_) => heard++,
      );

      expect(heard, 0);
      expect(download.photoCount, 3);
      expect(download.totalBytes, isNull);
    });

    test('skips chunks it doesn’t understand', () async {
      final seen = <int>[];
      await readGalleryDownload(
        Stream.fromIterable([
          _progress({'stage': 'checking'}),
          _progress(_chunk(1, 3)),
          _progress('nonsense'),
          _progress(_chunk(2, 3)),
          _result(_answer),
        ]),
        onProgress: (progress) => seen.add(progress.photosDone),
      );

      expect(seen, [1, 2]);
    });

    test('a failure showing progress still returns the link', () async {
      final download = await readGalleryDownload(
        Stream.fromIterable([_progress(_chunk(0, 3)), _result(_answer)]),
        onProgress: (_) => throw StateError('a display bug'),
      );

      expect(download.url, Uri.parse(_link));
    });

    test('a stream that ends without a result is the generic failure', () async {
      await expectLater(
        readGalleryDownload(Stream.fromIterable([_progress(_chunk(0, 3))])),
        fails(kGalleryErrorFallback),
      );
    });

    test('gives up after its time limit, and ignores what comes later', () async {
      final events = StreamController<GalleryCallEvent>();
      addTearDown(events.close);
      var heard = 0;

      await expectLater(
        readGalleryDownload(events.stream, onProgress: (_) => heard++, timeLimit: const Duration(milliseconds: 10)),
        fails(kGalleryErrorFallback),
      );
      events.add(_progress(_chunk(1, 3)));
      await pumpEventQueue();

      expect(heard, 0);
      // It stopped listening.
      expect(events.hasListener, isFalse);
    });

    Stream<GalleryCallEvent> failsAfterAChunk(Object error) async* {
      yield _progress(_chunk(0, 3));
      throw error;
    }

    test('the function’s own message for failed-precondition, without the status', () async {
      var heard = 0;
      await expectLater(
        readGalleryDownload(
          failsAfterAChunk(
            FirebaseFunctionsException(code: 'failed-precondition', message: 'Your photos aren’t ready yet. [0]'),
          ),
          onProgress: (_) => heard++,
        ),
        fails('Your photos aren’t ready yet.'),
      );
      expect(heard, 1);
    });

    test('other function errors are the generic failure', () async {
      await expectLater(
        readGalleryDownload(failsAfterAChunk(FirebaseFunctionsException(code: 'internal', message: 'INTERNAL [0]'))),
        fails(kGalleryErrorFallback),
      );
    });

    test('so is any other error', () async {
      await expectLater(
        readGalleryDownload(failsAfterAChunk(StateError('fetch failed'))),
        fails(kGalleryErrorFallback),
      );
    });

    test('so is a result it can’t read', () async {
      await expectLater(readGalleryDownload(Stream.value(_result({'url': 42}))), fails(kGalleryErrorFallback));
    });
  });
}
