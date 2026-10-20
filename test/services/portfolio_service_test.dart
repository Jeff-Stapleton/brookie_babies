import 'dart:async';

import 'package:brookie_babies/services/portfolio_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `_admin/gallery` folder, holding [files]. Fetching a link fails for
/// the names in [broken], and for any name not in [files].
class _FakeStorage extends Fake implements FirebaseStorage {
  _FakeStorage(this.files, {this.broken = const {}});

  final List<String> files;
  final Set<String> broken;
  final linksFetched = <String>[];
  var listed = false;

  @override
  Reference ref([String? path]) {
    expect(path, StoragePortfolioService.folder);
    return _FakeFolder(this);
  }
}

class _FakeFolder extends Fake implements Reference {
  _FakeFolder(this._storage);

  final _FakeStorage _storage;

  @override
  Future<ListResult> listAll() async {
    _storage.listed = true;
    return _FakeListing([for (final name in _storage.files) _FakeFile(_storage, name)]);
  }

  @override
  Reference child(String path) => _FakeFile(_storage, path);
}

class _FakeListing extends Fake implements ListResult {
  _FakeListing(this.items);

  @override
  final List<Reference> items;
}

class _FakeFile extends Fake implements Reference {
  _FakeFile(this._storage, this.name);

  final _FakeStorage _storage;

  @override
  final String name;

  @override
  Future<String> getDownloadURL() async {
    _storage.linksFetched.add(name);
    if (_storage.broken.contains(name) || !_storage.files.contains(name)) {
      throw FirebaseException(plugin: 'firebase_storage', code: 'object-not-found');
    }
    return 'https://storage.example.com/$name?alt=media';
  }
}

void main() {
  List<String> names(List<Uri> urls) => [for (final url in urls) url.pathSegments.last];

  /// The service with no home page photos chosen yet.
  StoragePortfolioService byName(FirebaseStorage storage) =>
      StoragePortfolioService(storage, homePhotoNames: () async => null);

  group('none chosen: the folder by name', () {
    test('lists the photos sorted by file name', () async {
      final storage = _FakeStorage(['b.jpg', 'a.jpg', 'c.jpg']);

      expect(names(await byName(storage).photoUrls()), ['a.jpg', 'b.jpg', 'c.jpg']);
    });

    test('skips hidden files and anything browsers can’t show, so neither becomes the hero', () async {
      final storage = _FakeStorage([
        'IMG_2.jpg',
        '.DS_Store',
        '._IMG_1.jpg',
        'IMG_1.HEIC',
        'notes.txt',
        'IMG_3.JPG',
        'IMG_4.jpeg',
        'IMG_5.png',
        'IMG_6.WebP',
        'IMG_0',
      ]);

      final urls = await byName(storage).photoUrls();

      expect(names(urls), ['IMG_2.jpg', 'IMG_3.JPG', 'IMG_4.jpeg', 'IMG_5.png', 'IMG_6.WebP']);
      expect(storage.linksFetched, unorderedEquals(names(urls)));
    });

    test('one link that can’t be fetched leaves out that photo, not all of them', () async {
      final storage = _FakeStorage(['1.jpg', '2.jpg', '3.jpg', '4.jpg'], broken: {'2.jpg'});

      expect(names(await byName(storage).photoUrls()), ['1.jpg', '3.jpg', '4.jpg']);
    });

    test('fetches links only for the first photos it was asked for', () async {
      final storage = _FakeStorage([for (var i = 9; i >= 1; i--) '$i.jpg']);

      final urls = await byName(storage).photoUrls(limit: 7);

      expect(names(urls), [for (var i = 1; i <= 7; i++) '$i.jpg']);
      expect(storage.linksFetched, hasLength(7));
    });
  });

  group('chosen on the admin page', () {
    test('keeps the chosen order, fetching only their links', () async {
      final storage = _FakeStorage(['a.jpg', 'b.jpg', 'c.jpg']);
      final service = StoragePortfolioService(storage, homePhotoNames: () async => ['c.jpg', 'a.jpg']);

      expect(names(await service.photoUrls()), ['c.jpg', 'a.jpg']);
      expect(storage.linksFetched, ['c.jpg', 'a.jpg']);
    });

    test('skips names that aren’t photos, aren’t in the folder itself, or come twice', () async {
      final storage = _FakeStorage(['a.jpg', 'b.png', 'IMG_1.HEIC', 'notes.txt', '.hidden.jpg']);
      final service = StoragePortfolioService(
        storage,
        homePhotoNames: () async => ['IMG_1.HEIC', 'b.png', 'notes.txt', 'b.png', '.hidden.jpg', 'x/a.jpg', 'a.jpg'],
      );

      expect(names(await service.photoUrls()), ['b.png', 'a.jpg']);
      expect(storage.linksFetched, ['b.png', 'a.jpg']);
    });

    test('takes the limit after skipping, fetching only those links', () async {
      final storage = _FakeStorage([for (var i = 1; i <= 9; i++) '$i.jpg']);
      final service = StoragePortfolioService(
        storage,
        homePhotoNames: () async => ['9.jpg', '9.jpg', 'x.txt', '8.jpg', '7.jpg', '6.jpg'],
      );

      expect(names(await service.photoUrls(limit: 2)), ['9.jpg', '8.jpg']);
      expect(storage.linksFetched, ['9.jpg', '8.jpg']);
    });

    test('a chosen photo that has since been deleted is left out', () async {
      final storage = _FakeStorage(['a.jpg', 'c.jpg']);
      final service = StoragePortfolioService(storage, homePhotoNames: () async => ['a.jpg', 'b.jpg', 'c.jpg']);

      expect(names(await service.photoUrls()), ['a.jpg', 'c.jpg']);
    });

    test('an empty choice means no photos, not the folder', () async {
      final storage = _FakeStorage(['a.jpg']);
      final service = StoragePortfolioService(storage, homePhotoNames: () async => []);

      expect(await service.photoUrls(), isEmpty);
      expect(storage.linksFetched, isEmpty);
    });
  });

  group('falls back to the folder by name', () {
    Future<void> expectFallback(StoragePortfolioService service, _FakeStorage storage) async {
      expect(names(await service.photoUrls()), ['a.jpg', 'b.jpg']);
      expect(storage.listed, isTrue);
    }

    test('when the choice can’t be read', () async {
      final storage = _FakeStorage(['b.jpg', 'a.jpg']);
      await expectFallback(
        StoragePortfolioService(storage, homePhotoNames: () async => throw Exception('permission-denied')),
        storage,
      );
    });

    test('when reading it throws at once (as an unbuilt service does)', () async {
      final storage = _FakeStorage(['b.jpg', 'a.jpg']);
      await expectFallback(
        StoragePortfolioService(storage, homePhotoNames: () => throw UnimplementedError()),
        storage,
      );
    });

    test('when reading it takes too long', () async {
      final storage = _FakeStorage(['b.jpg', 'a.jpg']);
      final never = Completer<List<String>?>();
      await expectFallback(
        StoragePortfolioService(
          storage,
          homePhotoNames: () => never.future,
          homePhotoNamesTimeLimit: const Duration(milliseconds: 10),
        ),
        storage,
      );
    });

    test('waits three seconds by default', () {
      final service = StoragePortfolioService(_FakeStorage([]), homePhotoNames: () async => null);

      expect(service.homePhotoNamesTimeLimit, const Duration(seconds: 3));
    });

    test('lists the folder while it waits, so falling back takes no longer than the wait', () async {
      final storage = _FakeStorage(['b.jpg', 'a.jpg']);
      final read = Completer<List<String>?>();
      final urls = StoragePortfolioService(storage, homePhotoNames: () => read.future).photoUrls();
      await Future<void>.delayed(Duration.zero);

      expect(storage.listed, isTrue);
      read.complete(['b.jpg']);
      expect(names(await urls), ['b.jpg']);
    });
  });

  group('a choice that answers too late', () {
    /// The service with a short wait, reading [reads] in turn, and counting
    /// its onLateChoice calls in [lateChoices].
    late List<Completer<List<String>?>> reads;
    late int lateChoices;
    StoragePortfolioService slow(_FakeStorage storage) {
      reads = [];
      lateChoices = 0;
      return StoragePortfolioService(
        storage,
        homePhotoNames: () => (reads..add(Completer())).last.future,
        homePhotoNamesTimeLimit: const Duration(milliseconds: 10),
        onLateChoice: () => lateChoices++,
      );
    }

    /// Lets the late answer be handled.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('asks to be shown, and is what a read that is slow again shows', () async {
      final storage = _FakeStorage(['b.jpg', 'a.jpg', 'c.jpg']);
      final service = slow(storage);

      expect(names(await service.photoUrls()), ['a.jpg', 'b.jpg', 'c.jpg']);
      reads.last.complete(['c.jpg', 'a.jpg']);
      await settle();
      expect(lateChoices, 1);

      // The home page asks again, and this read is slow too.
      expect(names(await service.photoUrls()), ['c.jpg', 'a.jpg']);
      reads.last.complete(['c.jpg', 'a.jpg']);
      await settle();
      expect(lateChoices, 1, reason: 'already shown');
    });

    test('changes nothing when it is what was shown anyway', () async {
      final storage = _FakeStorage(['b.jpg', 'a.jpg', 'c.jpg']);
      final service = slow(storage);

      // None chosen: the folder by name, as shown.
      await service.photoUrls(limit: 2);
      reads.last.complete(null);
      await settle();
      // Chosen, but the same photos the folder gave, once skipped and cut.
      await service.photoUrls(limit: 2);
      reads.last.complete(['a.jpg', 'notes.txt', 'a.jpg', 'b.jpg', 'c.jpg']);
      await settle();

      expect(lateChoices, 0);
    });

    test('a read that fails late changes nothing', () async {
      final service = slow(_FakeStorage(['a.jpg']));

      expect(names(await service.photoUrls()), ['a.jpg']);
      reads.last.completeError(Exception('permission-denied'));
      await settle();

      expect(lateChoices, 0);
    });

    test('only the newest read’s answer counts', () async {
      final storage = _FakeStorage(['a.jpg', 'b.jpg']);
      final service = slow(storage);

      await service.photoUrls();
      final first = reads.last;
      // The next read answers in time.
      final urls = service.photoUrls();
      reads.last.complete(['b.jpg']);
      expect(names(await urls), ['b.jpg']);
      first.complete(['a.jpg']);
      await settle();

      expect(lateChoices, 0);
      expect(names(await service.photoUrls()), ['b.jpg']);
    });

    test('a read that fails in time shows the last one read', () async {
      var fail = false;
      final service = StoragePortfolioService(
        _FakeStorage(['a.jpg', 'b.jpg']),
        homePhotoNames: () async => fail ? throw Exception('unavailable') : ['b.jpg'],
      );
      expect(names(await service.photoUrls()), ['b.jpg']);

      fail = true;
      expect(names(await service.photoUrls()), ['b.jpg']);
    });
  });

  test('isPhoto: JPEG, PNG and WebP in any case; never hidden files', () {
    for (final name in ['a.jpg', 'a.JPG', 'a.jpeg', 'a.Jpeg', 'a.png', 'a.PNG', 'a.webp', 'a.WEBP']) {
      expect(StoragePortfolioService.isPhoto(name), isTrue, reason: name);
    }
    for (final name in ['.DS_Store', '.hidden.jpg', 'a.heic', 'a.gif', 'a.jpg.txt', 'jpg', 'a.tiff', '']) {
      expect(StoragePortfolioService.isPhoto(name), isFalse, reason: name);
    }
  });
}
