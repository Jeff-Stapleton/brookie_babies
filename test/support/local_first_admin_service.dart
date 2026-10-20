// A FakeAdminService whose writes show before they're saved, as
// Firestore's latency compensation does on the web.

import 'package:brookie_babies/models/booking.dart';

import 'fakes.dart';

/// Like [FakeAdminService], but [setPhotosReady] has the live streams emit
/// the new value at once, before its [writeDelay], and the old one again if
/// the write then fails: what the web SDK does with a local write.
class LocalFirstAdminService extends FakeAdminService {
  LocalFirstAdminService({super.sessions, super.sessionPhotos, super.autoCompleteUploads});

  @override
  Future<void> setPhotosReady(String id, bool ready) async {
    final before = sessions[id];
    if (before != null) {
      sessions[id] = _withPhotosReady(before, ready);
      notifyChanged();
    }
    try {
      await super.setPhotosReady(id, ready);
    } catch (_) {
      if (before != null) {
        sessions[id] = before;
        notifyChanged();
      }
      rethrow;
    }
  }

  static Booking _withPhotosReady(Booking s, bool ready) => Booking(
        id: s.id,
        packageName: s.packageName,
        date: s.date,
        time: s.time,
        location: s.location,
        status: s.status,
        photosReady: ready,
        uid: s.uid,
        email: s.email,
        name: s.name,
      );
}
