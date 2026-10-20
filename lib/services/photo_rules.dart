// What firestore.rules and storage.rules accept from admins, in Dart.
//
// The app checks each of these before it writes or uploads, so a rule
// rejection only ever means a real access problem, never a bad file or
// field. Change a limit here and in the rules together: each points at the
// other.

import 'package:brookie_babies/models/picked_photo.dart';
import 'package:brookie_babies/services/portfolio_service.dart';

/// The storage.rules limits on uploaded photos, and the reasons a photo
/// breaks them, written for the admin.
abstract final class PhotoRules {
  /// Session photos (`galleries/{bookingId}/`) must be smaller than this.
  static const sessionMaxBytes = 100 * 1024 * 1024;

  /// Home page library photos (`_admin/gallery/`) must be smaller than this.
  static const homeMaxBytes = 20 * 1024 * 1024;

  /// The types the home page library takes: what every browser can show.
  /// Session photos may be any `image/` type (the family downloads them).
  static const homeContentTypes = {'image/jpeg', 'image/png', 'image/webp'};

  /// What a session's upload offers in the file picker: any photo.
  static const sessionAccept = 'image/*';

  /// What the home page library's upload offers in the file picker.
  static const homeAccept = 'image/jpeg,image/png,image/webp';

  /// At most this many home page photos (`site/home.photos`): the hero and
  /// FeaturedPhotos.maxCount more (test/services/photo_rules_test.dart
  /// checks they agree).
  static const homeMaxPhotos = 7;

  /// Types for when the browser doesn't say (common for HEIC), by extension.
  static const _typesByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'gif': 'image/gif',
    'tif': 'image/tiff',
    'tiff': 'image/tiff',
  };

  /// The type to upload [photo] as: the browser's, else one from its
  /// extension, else null.
  static String? contentTypeFor(PickedPhoto photo) {
    final type = photo.contentType.trim().toLowerCase();
    // Old browsers' names for JPEG, which the rules wouldn't recognize.
    if (type == 'image/jpg' || type == 'image/pjpeg') return 'image/jpeg';
    if (type.isNotEmpty) return type;
    final dot = photo.name.lastIndexOf('.');
    return dot < 0 ? null : _typesByExtension[photo.name.substring(dot + 1).toLowerCase()];
  }

  static final _unsafe = RegExp(r'[\x00-\x1F\x7F#\[\]*?/]');

  /// [name] as a Storage object name: control characters and `# [ ] * ? /`
  /// (which Storage advises against, or which would make a folder) become
  /// `_`. Never empty.
  static String safeObjectName(String name) {
    final safe = name.replaceAll(_unsafe, '_');
    // "." and ".." aren't allowed as object names.
    if (safe == '.' || safe == '..') return '_' * safe.length;
    return safe.isEmpty ? 'photo' : safe;
  }

  /// Why [photo] can't be uploaded to a session, or null if it can. A name
  /// starting with "." (a Mac's "._IMG_1.JPG" on a memory card, say) isn't
  /// a photo: the session's listing and the family's zip leave those out.
  static String? sessionPhotoProblem(PickedPhoto photo) {
    final type = contentTypeFor(photo);
    if (type == null || !type.startsWith('image/') || photo.name.startsWith('.')) {
      return '${photo.name} isn’t a photo.';
    }
    return _sizeProblem(photo, sessionMaxBytes, 'Session photos');
  }

  /// Why [photo] can't be uploaded to the home page library, or null if it
  /// can. It must also have a photo's extension, so the site lists it.
  static String? homePhotoProblem(PickedPhoto photo) {
    final type = contentTypeFor(photo);
    if (type == null || !type.startsWith('image/') || photo.name.startsWith('.')) {
      return '${photo.name} isn’t a photo.';
    }
    if (!homeContentTypes.contains(type)) {
      return '${photo.name} isn’t a JPEG, PNG or WebP. Export it as JPEG and upload it again.';
    }
    if (!StoragePortfolioService.isPhoto(safeObjectName(photo.name))) {
      return '${photo.name} needs a .jpg, .png or .webp ending. Rename it and upload it again.';
    }
    return _sizeProblem(photo, homeMaxBytes, 'Home page photos');
  }

  static String? _sizeProblem(PickedPhoto photo, int maxBytes, String what) {
    if (photo.size <= 0) return '${photo.name} is empty.';
    if (photo.size < maxBytes) return null;
    // Rounded up, so a photo just over the limit never reads as within it.
    final megabytes = (photo.size / (1024 * 1024)).ceil();
    return '${photo.name} is $megabytes MB. $what must be under ${maxBytes ~/ (1024 * 1024)} MB.';
  }
}

/// The firestore.rules limits on an ad hoc session's fields (a `bookings`
/// document with status `adhoc`), for the session form and AdminService.
abstract final class SessionRules {
  /// `name`, once trimmed, is 1 to this many characters.
  static const nameMaxLength = 100;

  /// `location` is at most this many characters.
  static const locationMaxLength = 200;

  /// The packages a session may name (SessionPackage.all;
  /// test/services/photo_rules_test.dart checks they agree).
  static const packageNames = ['Basic', 'Premium', 'Ultimate'];

  /// What the rules take as an email, once [normalizeEmail]ed.
  static final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// [email] as stored and matched against the guest's sign-in: trimmed and
  /// lowercase.
  static String normalizeEmail(String email) => email.trim().toLowerCase();
}
