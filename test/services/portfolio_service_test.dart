import 'package:brookie_babies/services/portfolio_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `_admin/gallery` folder, holding [files]. Fetching a link fails for
/// the names in [broken].
class _FakeStorage extends Fake implements FirebaseStorage {
  _FakeStorage(this.files, {this.broken = const {}});

  final List<String> files;
  final Set<String> broken;
  final linksFetched = <String>[];

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
  Future<ListResult> listAll() async =>
      _FakeListing([for (final name in _storage.files) _FakeFile(_storage, name)]);
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
    if (_storage.broken.contains(name)) {
      throw FirebaseException(plugin: 'firebase_storage', code: 'object-not-found');
    }
    return 'https://storage.example.com/$name?alt=media';
  }
}

void main() {
  List<String> names(List<Uri> urls) => [for (final url in urls) url.pathSegments.last];

  test('lists the photos sorted by file name', () async {
    final storage = _FakeStorage(['b.jpg', 'a.jpg', 'c.jpg']);

    expect(names(await StoragePortfolioService(storage).photoUrls()), ['a.jpg', 'b.jpg', 'c.jpg']);
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

    final urls = await StoragePortfolioService(storage).photoUrls();

    expect(names(urls), ['IMG_2.jpg', 'IMG_3.JPG', 'IMG_4.jpeg', 'IMG_5.png', 'IMG_6.WebP']);
    expect(storage.linksFetched, unorderedEquals(names(urls)));
  });

  test('one link that can’t be fetched leaves out that photo, not all of them', () async {
    final storage = _FakeStorage(['1.jpg', '2.jpg', '3.jpg', '4.jpg'], broken: {'2.jpg'});

    expect(names(await StoragePortfolioService(storage).photoUrls()), ['1.jpg', '3.jpg', '4.jpg']);
  });

  test('fetches links only for the first photos it was asked for', () async {
    final storage = _FakeStorage([for (var i = 9; i >= 1; i--) '$i.jpg']);

    final urls = await StoragePortfolioService(storage).photoUrls(limit: 7);

    expect(names(urls), [for (var i = 1; i <= 7; i++) '$i.jpg']);
    expect(storage.linksFetched, hasLength(7));
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
