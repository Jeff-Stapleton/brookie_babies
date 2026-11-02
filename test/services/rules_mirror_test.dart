// The client checks against the rules themselves: what firestore.rules and
// storage.rules accept, read from the files, next to what the app writes
// (through FirebaseAdminService) and PhotoRules / SessionRules. A change to
// either side that leaves the other behind fails here, so a rule rejection
// still only ever means an access problem.

import 'dart:io';

import 'package:brookie_babies/models/session_details.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/services/portfolio_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_firebase.dart';
import '../support/fakes.dart';

/// The text of the `{ … }` block that [opening] (ending in its `{`) starts
/// in [rules].
String _block(String rules, String opening) {
  final start = rules.indexOf(opening);
  if (start < 0) fail('No “$opening” in the rules.');
  var depth = 0;
  for (var i = start + opening.length - 1; i < rules.length; i++) {
    if (rules[i] == '{') depth++;
    if (rules[i] == '}' && --depth == 0) return rules.substring(start, i + 1);
  }
  fail('“$opening” never closes.');
}

/// The quoted strings in the `[ … ]` list just after [marker] in [text].
Set<String> _listAfter(String text, String marker) {
  final at = text.indexOf(marker);
  if (at < 0) fail('No “$marker” in:\n$text');
  final open = text.indexOf('[', at);
  final list = text.substring(open, text.indexOf(']', open));
  return {for (final match in RegExp("'([^']*)'").allMatches(list)) match[1]!};
}

/// The first group of [pattern] in [text], as written there.
String _find(String text, String pattern) {
  final match = RegExp(pattern).firstMatch(text);
  if (match == null) fail('No /$pattern/ in:\n$text');
  return match[1]!;
}

/// The `N * 1024 * 1024` in "request.resource.size < N * 1024 * 1024", in
/// bytes. Strictly less than, as PhotoRules checks.
int _maxBytes(String block) =>
    int.parse(_find(block, r'request\.resource\.size < (\d+) \* 1024 \* 1024')) * 1024 * 1024;

/// A pattern in the rules' string form ('\\s') as the regex it means (\s).
String _unescape(String rulesString) => rulesString.replaceAll(r'\\', r'\');

void main() {
  final firestore = File('firestore.rules').readAsStringSync();
  final storage = File('storage.rules').readAsStringSync();
  final bookings = _block(firestore, 'match /bookings/{bookingId} {');
  final adHocUpdate = _block(firestore, 'function validAdHocUpdate() {');
  final siteHome = _block(firestore, 'match /site/home {');
  final library = _block(storage, 'match /_admin/gallery/{name} {');
  final galleries = _block(storage, 'match /galleries/{bookingId}/{allPaths=**} {');

  group('firestore.rules', () {
    late FakeFirestore db;
    late FirebaseAdminService admin;

    setUp(() {
      db = FakeFirestore();
      admin = FirebaseAdminService(db, FakeStorage(), FakeFirebaseAuth(uid: 'admin-uid'));
    });

    final everything = SessionDetails(
      name: 'The Harper family',
      emails: ['harper@example.com', 'pat@example.com'],
      date: DateTime(2026, 11, 14),
      packageName: 'Premium',
      time: (hour: 9, minute: 0),
      location: 'Liberty Park',
    );
    final onlyRequired = SessionDetails(name: 'The Harpers', emails: ['pat@example.com'], date: DateTime(2026, 12, 1));

    Set<String> keysOf(Map<Object, Object?> data) => {for (final key in data.keys) key as String};

    test('a new session has exactly the keys create requires, and only ones it allows', () async {
      await admin.createSession(onlyRequired);
      await admin.createSession(everything);

      // Who it's shared with besides: validGuests takes `emails`, or the one
      // `email` that only sites from before several emails send.
      final guests = _block(firestore, 'function validGuests(data) {');
      expect(guests, contains("('emails' in data) != ('email' in data)"));
      expect(keysOf(db.writes[0].data), {..._listAfter(bookings, 'keys().hasAll('), 'emails'});
      expect(keysOf(db.writes[1].data), _listAfter(bookings, 'keys().hasOnly(').difference({'email'}));
      expect(_find(bookings, r"request\.resource\.data\.status == '(\w+)'"), db.writes[1].data['status']);
    });

    test('an ad hoc edit changes only the keys the rules allow, and removes only the optional ones', () async {
      final session = testSession(
        's1',
        date: DateTime(2026, 11, 14),
        packageName: 'Premium',
        time: (hour: 9, minute: 0),
        location: 'Liberty Park',
      );
      db.docs['bookings/s1'] = {'status': 'adhoc'};

      await admin.updateSession(
        session,
        SessionDetails(
          name: 'The Harpers',
          emails: ['pat@example.com'],
          date: DateTime(2026, 12, 1),
          packageName: 'Basic',
          time: (hour: 10, minute: 30),
          location: 'The studio',
        ),
      );
      await admin.setPhotosReady('s1', true);
      await admin.updateSession(session, onlyRequired);
      // One from before several emails moves its email to emails.
      await admin.updateSession(testSession('s1', email: 'harper@example.com'), onlyRequired);

      expect(
        {...keysOf(db.writes[0].data), ...keysOf(db.writes[1].data), ...keysOf(db.writes[3].data)},
        _listAfter(adHocUpdate, 'changed.hasOnly('),
      );
      final removed = {
        for (final write in db.writes.skip(2))
          for (final MapEntry(:key, :value) in write.data.entries)
            if (value == FieldValue.delete()) key as String,
      };
      expect(removed, _listAfter(adHocUpdate, 'removedKeys().hasOnly('));
    });

    test('a customer’s booking changes only photosReady (and updatedAt)', () async {
      db.docs['bookings/b1'] = {'status': 'paid', 'uid': 'customer-uid'};

      await admin.setPhotosReady('b1', true);

      expect(keysOf(db.writes.single.data), _listAfter(bookings, ': changedKeys().hasOnly('));
    });

    test('the field limits match SessionRules', () {
      final name = _block(firestore, 'function validName(data) {');
      expect(int.parse(_find(name, r'data\.name\.size\(\) <= (\d+)')), SessionRules.nameMaxLength);
      expect(_find(name, r'data\.name\.size\(\) >= (\d+)'), '1');

      final location = _block(firestore, 'function validLocation(data) {');
      expect(int.parse(_find(location, r'data\.location\.size\(\) <= (\d+)')), SessionRules.locationMaxLength);

      final package = _block(firestore, 'function validPackageName(data) {');
      expect(_listAfter(package, 'data.packageName in'), SessionRules.packageNames.toSet());

      final email = _block(firestore, 'function validEmail(email) {');
      expect(_unescape(_find(email, r"email\.matches\('([^']*)'\)")), SessionRules.emailPattern.pattern);
      expect(email, contains('email == email.trim().lower()'));
      expect(int.parse(_find(email, r'email\.size\(\) <= (\d+)')), SessionRules.emailMaxLength);

      final list = _block(firestore, 'function validEmailList(list, min) {');
      final most = int.parse(_find(list, r'list\.size\(\) <= (\d+)'));
      expect(most, SessionRules.emailListMaxLength);
      expect(list, contains('list.toSet().size() == list.size()'));
      // Rules can't loop, so each place has its own check, up to the most.
      expect(
        [for (final at in RegExp(r'validEmailAt\(list, (\d+)\)').allMatches(list)) int.parse(at[1]!)],
        [for (var i = 0; i < most; i++) i],
      );
      final guests = _block(firestore, 'function validGuests(data) {');
      expect(_find(guests, r'validEmailList\(data\.emails, (\d+)\)'), '1');
    });

    test('site/home: exactly the keys saveHomePhotos sets, and at most homeMaxPhotos photos', () async {
      await admin.saveHomePhotos(['a.jpg']);

      expect(keysOf(db.writes.single.data), _listAfter(siteHome, 'keys().hasOnly('));
      expect(int.parse(_find(siteHome, r'data\.photos\.size\(\) <= (\d+)')), PhotoRules.homeMaxPhotos);
    });
  });

  group('storage.rules', () {
    test('home page library: the types, size limit and endings match PhotoRules', () {
      final types = _find(library, r"request\.resource\.contentType\.matches\('image/\(([^)]*)\)'\)");
      expect({for (final type in types.split('|')) 'image/$type'}, PhotoRules.homeContentTypes);
      expect(PhotoRules.homeAccept.split(',').toSet(), PhotoRules.homeContentTypes);
      expect(_maxBytes(library), PhotoRules.homeMaxBytes);
      expect(library, contains('request.resource.size > 0'));

      // The endings the rules take are the ones the site lists.
      final ending = _unescape(_find(library, r"name\.matches\('\(\?i\)([^']*)'\)"));
      final rulesEnding = RegExp('^(?:$ending)\$', caseSensitive: false);
      for (final name in ['a.jpg', 'a.JPEG', 'a.Png', 'a.webp', 'a.gif', 'a.heic', 'a.jpg.txt', 'a', 'ajpg']) {
        expect(rulesEnding.hasMatch(name), StoragePortfolioService.isPhoto(name), reason: name);
      }
    });

    test('session photos: any image type, and the size limit matches PhotoRules', () {
      expect(_find(galleries, r"request\.resource\.contentType\.matches\('([^']*)'\)"), 'image/.*');
      expect(PhotoRules.sessionAccept, 'image/*');
      expect(_maxBytes(galleries), PhotoRules.sessionMaxBytes);
      expect(galleries, contains('request.resource.size > 0'));
    });

    test('nothing is overwritten: no rule allows update or write', () {
      expect(storage, isNot(matches(RegExp(r'allow [a-z, ]*\b(update|write)\b'))));
    });
  });
}
