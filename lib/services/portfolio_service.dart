import 'package:firebase_storage/firebase_storage.dart';

/// The photographs shown on the home page. [StoragePortfolioService] is the
/// real implementation; tests use a fake.
abstract class PortfolioService {
  /// Download links for the portfolio photos, sorted by file name. The first
  /// one is the home page's hero, so the photographer chooses it by naming.
  Future<List<Uri>> photoUrls();
}

/// Lists Firebase Storage's public `_admin/gallery` folder (storage.rules lets
/// anyone read it).
class StoragePortfolioService implements PortfolioService {
  StoragePortfolioService(this._storage);

  final FirebaseStorage _storage;

  static const folder = '_admin/gallery';

  @override
  Future<List<Uri>> photoUrls() async {
    final listing = await _storage.ref(folder).listAll();
    final files = [...listing.items]..sort((a, b) => a.name.compareTo(b.name));
    final urls = await Future.wait(files.map((file) => file.getDownloadURL()));
    return [for (final url in urls) Uri.parse(url)];
  }
}
