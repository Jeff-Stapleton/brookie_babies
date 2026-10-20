// AdminSessionPage: a session's details, who can download and the message
// for them, making the photos available, uploading, the photo list, and
// deleting photos or the whole (ad hoc) session.

import 'dart:async';

import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/picked_photo.dart';
import 'package:brookie_babies/models/session_lookup.dart';
import 'package:brookie_babies/pages/admin_page.dart';
import 'package:brookie_babies/pages/admin_session_page.dart';
import 'package:brookie_babies/pages/session_form_page.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:brookie_babies/widgets/brookie_dialog.dart';
import 'package:brookie_babies/widgets/empty_state.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/admin_test_app.dart';
import '../support/fakes.dart';
import '../support/local_first_admin_service.dart';

const _photos = ['IMG_1.jpg', 'IMG_2.jpg', 'edits/IMG_3.jpg'];

/// The Harper family's ad hoc session 's1', with [photos], and others.
FakeAdminService _service({
  bool ready = false,
  List<String> photos = _photos,
  bool autoCompleteUploads = false,
}) =>
    FakeAdminService(
      sessions: [
        testSession('s1', time: (hour: 10, minute: 30), location: 'Liberty Park', photosReady: ready),
        testSession('paid', name: null, email: 'parent@example.com', status: BookingStatus.paid, photosReady: ready),
      ],
      sessionPhotos: {'s1': photos, 'paid': photos},
      autoCompleteUploads: autoCompleteUploads,
    );

Future<void> _pumpSession(
  WidgetTester tester, {
  FakeAdminService? admin,
  FakePhotoPicker? picker,
  String id = 's1',
  Size size = const Size(1440, 900),
  Brightness brightness = Brightness.light,
}) =>
    pumpAdminPage(tester, AdminSessionPage(sessionId: id),
        admin: admin ?? _service(), picker: picker, size: size, brightness: brightness);

/// [label] inside the open dialog.
Finder _inDialog(String label) => find.descendant(of: find.byType(BrookieDialog), matching: find.text(label));

/// The delete button beside [name] in the photo list.
Finder _deleteButton(String name) =>
    find.ancestor(of: find.byTooltip('Delete $name'), matching: find.byType(IconButton));

/// The photo names listed, in order.
List<String> _listed(WidgetTester tester) => [
      for (final tooltip in tester.widgetList<Tooltip>(find.byType(Tooltip)))
        if (tooltip.message case final message? when message.startsWith('Delete ')) message.substring(7),
    ];

/// Picks [photos] with "Upload photos" and lets the queue start them.
Future<void> _upload(WidgetTester tester, FakePhotoPicker picker, List<String> photos) async {
  picker.next = [
    for (final name in photos)
      name.endsWith('.txt') ? testPhoto(name, contentType: 'text/plain') : testPhoto(name),
  ];
  await tapInView(tester, find.text('Upload photos'));
  await tester.pump();
  await tester.pump();
}

/// Lets uploads report back, and the queue's progress reach the page.
Future<void> _settleUploads(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  tearDown(LeaveWarning.reset);
  tearDown(AdminPage.clearNotice);

  group('details', () {
    testWidgets('an ad hoc session: named in the top bar and the headline, with when and where', (tester) async {
      await _pumpSession(tester);

      expect(tester.widget<BrookieTopBar>(find.byType(BrookieTopBar)).title, 'The Harper family');
      expect(find.text('The Harper family'), findsNWidgets(2));
      expect(find.text('Photo session'), findsOneWidget);
      expect(find.text('Ad hoc'), findsOneWidget);
      expect(find.text('Mon, Mar 4, 2999'), findsOneWidget);
      expect(find.text('10:30 am'), findsOneWidget);
      expect(find.text('Liberty Park'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Edit details'), findsOneWidget);
      expect(find.text('Delete session'), findsOneWidget);
    });

    testWidgets('a booking: named by its email, and its details can’t be edited or the session deleted',
        (tester) async {
      await _pumpSession(tester, id: 'paid');

      expect(tester.widget<BrookieTopBar>(find.byType(BrookieTopBar)).title, 'parent@example.com');
      expect(findDisplayName('parent@example.com'), findsNWidgets(2));
      expect(find.text('Premium session'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Edit details'), findsNothing);
      expect(find.text('Delete session'), findsNothing);
    });

    testWidgets('"Edit details" opens the form on this session', (tester) async {
      await _pumpSession(tester);

      await tapInView(tester, find.text('Edit details'));
      await tester.pumpAndSettle();

      expect(tester.widget<SessionFormPage>(find.byType(SessionFormPage)).session?.id, 's1');
    });

    testWidgets('the account menu has no way off the page but back and "Sign out"', (tester) async {
      await _pumpSession(tester);

      await tester.tap(find.byType(CircleAvatar));
      await tester.pumpAndSettle();

      // "Your sessions" leads to "Admin" and "See packages", which would
      // close this page without asking, stopping its uploads.
      expect(find.text('Your sessions'), findsNothing);
      expect(find.text('Admin'), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('changes made elsewhere show at once', (tester) async {
      final admin = _service();
      await _pumpSession(tester, admin: admin);

      admin.sessions['s1'] = testSession('s1', name: 'The Harpers');
      admin.notifyChanged();
      await tester.pumpAndSettle();

      expect(tester.widget<BrookieTopBar>(find.byType(BrookieTopBar)).title, 'The Harpers');
      expect(admin.calls.where((call) => call.startsWith('listSessionPhotos')), hasLength(1));
    });
  });

  group('who can download', () {
    testWidgets('an ad hoc session: anyone signed in as its email', (tester) async {
      await _pumpSession(tester);

      expect(find.widgetWithText(SelectableText, 'Anyone signed in with Google as harper@example.com'),
          findsOneWidget);
    });

    testWidgets('a booking: the Google account that paid, and the email noted on it', (tester) async {
      await _pumpSession(tester, id: 'paid');

      expect(find.widgetWithText(SelectableText, 'The Google account with user ID uid-paid'), findsOneWidget);
      expect(find.widgetWithText(SelectableText, 'Email on the booking: parent@example.com'), findsOneWidget);
    });

    testWidgets('a booking without a uid: nobody yet, and how to fix it', (tester) async {
      final admin = FakeAdminService(sessions: [
        Booking(id: 'b', packageName: 'Basic', date: DateTime(2999), status: BookingStatus.paid),
      ]);
      await _pumpSession(tester, admin: admin, id: 'b');

      expect(find.textContaining('Nobody yet: no Google account is linked to this booking.'), findsOneWidget);
    });

    testWidgets('"Copy message" copies the message for the family', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pumpSession(tester);

      // Tests don't run on http(s), so the link is the live site's.
      const message = 'Your photos from Brooke are ready. Open https://brookie-babies.web.app/#/profile and sign in '
          'with Google as harper@example.com to download them.';
      expect(find.widgetWithText(SelectableText, message), findsOneWidget);
      expect(find.text('Send it once the photos are available.'), findsOneWidget);
      await tapInView(tester, find.text('Copy message'));
      await tester.pumpAndSettle();

      expect(copied, message);
      expect(find.widgetWithText(OutlinedButton, 'Message copied'), findsOneWidget);
    });

    testWidgets('a booking’s message says to use the account they booked with', (tester) async {
      await _pumpSession(tester, admin: _service(ready: true), id: 'paid');

      expect(
        find.text('Your photos from Brooke are ready. Open https://brookie-babies.web.app/#/profile and sign in '
            'with the Google account you booked with to download them.'),
        findsOneWidget,
      );
      expect(find.text('Send it once the photos are available.'), findsNothing);
    });
  });

  group('making the photos available', () {
    testWidgets('with photos and nothing uploading, it’s the one primary button', (tester) async {
      await _pumpSession(tester);

      expect(tester.widget<StatusTag>(find.widgetWithText(StatusTag, 'Not ready')).tone, StatusTone.neutral);
      expect(find.widgetWithText(FilledButton, 'Make photos available'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Upload photos'), findsOneWidget);
      expect(filledButtons(), 1);
    });

    testWidgets('asks first, with the count and who can download, then makes them available', (tester) async {
      final admin = _service();
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Make photos available'));
      await tester.pumpAndSettle();
      expect(find.text('Make photos available?'), findsOneWidget);
      expect(find.text('3 photos. Anyone signed in with Google as harper@example.com can download them.'),
          findsOneWidget);
      await tester.tap(_inDialog('Make photos available'));
      await tester.pumpAndSettle();

      expect(admin.calls, contains('setPhotosReady(s1, true)'));
      expect(tester.widget<StatusTag>(find.widgetWithText(StatusTag, 'Ready to download')).tone, StatusTone.success);
      expect(find.widgetWithText(OutlinedButton, 'Hide photos'), findsOneWidget);
      expect(find.text('Make photos available'), findsNothing);
      // Nothing is the page's primary action once they're available.
      expect(filledButtons(), 0);
    });

    testWidgets('a booking’s confirmation names the account by its user ID', (tester) async {
      await _pumpSession(tester, id: 'paid');

      await tapInView(tester, find.text('Make photos available'));
      await tester.pumpAndSettle();

      expect(find.text('3 photos. The Google account with user ID uid-paid can download them.'), findsOneWidget);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final admin = _service();
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Make photos available'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();

      expect(admin.calls.where((call) => call.startsWith('setPhotosReady')), isEmpty);
      expect(find.text('Not ready'), findsOneWidget);
    });

    testWidgets('with no photos: switched off, saying why, and uploading is the primary', (tester) async {
      await _pumpSession(tester, admin: _service(photos: const []));

      final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Make photos available'));
      expect(button.onPressed, isNull);
      expect(find.text('Upload photos first.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Upload photos'), findsOneWidget);
      expect(filledButtons(), 1);
      expect(find.widgetWithText(EmptyState, 'No photos yet. Upload them above.'), findsOneWidget);
    });

    testWidgets('"Hide photos" is never switched off, and asks nothing', (tester) async {
      final admin = _service(ready: true, photos: const []);
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Hide photos'));
      await tester.pumpAndSettle();

      expect(find.byType(BrookieDialog), findsNothing);
      expect(admin.calls, contains('setPhotosReady(s1, false)'));
      expect(find.text('Not ready'), findsOneWidget);
    });

    testWidgets('says why when the change isn’t saved', (tester) async {
      final admin = _service(ready: true)..errors['setPhotosReady'] = adminError(AdminErrorKind.denied);
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Hide photos'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InlineMessage, kAdminDeniedMessage), findsOneWidget);
      expect(find.text('Ready to download'), findsOneWidget);
    });

    testWidgets('keyboard: focus stays on the button while it works, and as it turns into "Hide photos"',
        (tester) async {
      final admin = _service()..writeDelay = const Duration(seconds: 1);
      await _pumpSession(tester, admin: admin);
      Focus.of(tester.element(find.text('Make photos available'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      // The confirmation's primary action takes focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(kThemeAnimationDuration);

      expect(find.text('Making photos available…'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Making photos available…')).onPressed,
          isNotNull);
      expect(hasFocus(tester, find.text('Making photos available…')), isTrue);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(hasFocus(tester, find.text('Hide photos')), isTrue);
    });

    testWidgets('the pressed button stays busy until the server has the change, though it shows locally at once',
        (tester) async {
      final admin = LocalFirstAdminService(
        sessions: [testSession('s1')],
        sessionPhotos: {'s1': _photos},
      )..writeDelay = const Duration(seconds: 1);
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Make photos available'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Make photos available'));
      await tester.pump();
      await tester.pump(kThemeAnimationDuration);

      expect(admin.sessions['s1']!.photosReady, isTrue);
      expect(find.text('Making photos available…'), findsOneWidget);
      expect(find.text('Hiding photos…'), findsNothing);
      expect(find.text('Not ready'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, 'Hide photos'), findsOneWidget);
      expect(find.text('Ready to download'), findsOneWidget);

      await tester.tap(find.text('Hide photos'));
      await tester.pump();

      expect(admin.sessions['s1']!.photosReady, isFalse);
      expect(find.text('Hiding photos…'), findsOneWidget);
      expect(find.text('Making photos available…'), findsNothing);
      expect(find.text('Ready to download'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Make photos available'), findsOneWidget);
      expect(find.text('Not ready'), findsOneWidget);
    });

    for (final (status, note) in [
      (
        BookingStatus.pending,
        'Payment is still pending, so the family can’t download photos yet, even once they’re available.',
      ),
      (BookingStatus.cancelled, 'This booking was cancelled, so the family can’t download its photos.'),
      (BookingStatus.refunded, 'This booking was refunded, so the family can’t download its photos.'),
    ]) {
      testWidgets('a ${status.name} booking says the family can’t download', (tester) async {
        final admin = FakeAdminService(sessions: [testSession('b', status: status)], sessionPhotos: {'b': _photos});
        await _pumpSession(tester, admin: admin, id: 'b');

        expect(find.widgetWithText(InlineMessage, note), findsOneWidget);
        // It can still be set: the family sees them if the booking is paid.
        expect(find.widgetWithText(FilledButton, 'Make photos available'), findsOneWidget);
      });
    }

    for (final ready in [false, true]) {
      testWidgets('an ID the download refuses (${ready ? 'available' : 'not available'}): says to recreate it, '
          'and offers only to hide the photos', (tester) async {
        const id = 'smith family';
        final admin = FakeAdminService(
          sessions: [testSession(id, status: BookingStatus.paid, uid: 'uid-smith', photosReady: ready)],
          sessionPhotos: {id: _photos},
        );
        await _pumpSession(tester, admin: admin, id: id, size: const Size(320, 800));

        expect(
          find.widgetWithText(InlineMessage,
              'Families can’t download this session’s photos: its document ID, “smith family”, may only use '
              'letters, numbers, - and _. Recreate it in the Firestore console with an Auto-ID.'),
          findsOneWidget,
        );
        expect(find.text('Make photos available'), findsNothing);
        expect(find.byType(StatusTag), findsOneWidget); // Only the booking's status.
        expect(find.text('Hide photos'), ready ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
        expect(filledButtons(), lessThanOrEqualTo(1));
      });
    }

    testWidgets('IDs with letters, numbers, - and _ are fine', (tester) async {
      const id = 'Harper_2026-b';
      final admin = FakeAdminService(sessions: [testSession(id)], sessionPhotos: {id: _photos});
      await _pumpSession(tester, admin: admin, id: id);

      expect(find.textContaining('document ID'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Make photos available'), findsOneWidget);
    });

    testWidgets('available on a booking that can’t be delivered: the tag says why, not "Ready to download"',
        (tester) async {
      final admin = FakeAdminService(
        sessions: [testSession('b', status: BookingStatus.pending, photosReady: true)],
        sessionPhotos: {'b': _photos},
      );
      await _pumpSession(tester, admin: admin, id: 'b');

      expect(tester.widget<StatusTag>(find.widgetWithText(StatusTag, 'Ready once paid')).tone, StatusTone.neutral);
      expect(find.text('Ready to download'), findsNothing);
    });
  });

  group('uploading', () {
    testWidgets('picks any photo, uploads it into the session and adds it to the list', (tester) async {
      final admin = _service();
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: admin, picker: picker);

      await _upload(tester, picker, ['IMG_4.jpg', 'IMG_0.jpg']);

      expect(picker.accepts, ['image/*']);
      expect(admin.calls, containsAllInOrder(['uploadSessionPhoto(galleries/s1/IMG_4.jpg)',
          'uploadSessionPhoto(galleries/s1/IMG_0.jpg)']));
      expect(find.text('Uploading 0 of 2'), findsOneWidget);
      expect(LeaveWarning.active.value, isTrue);
      // Not while photos are on their way; uploading is the primary meanwhile.
      expect(find.text('Wait for the uploads to finish.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Upload photos'), findsOneWidget);
      expect(filledButtons(), 1);

      for (final upload in admin.pendingUploads) {
        upload.complete();
      }
      await _settleUploads(tester);

      expect(find.text('Uploaded 2 photos'), findsOneWidget);
      expect(_listed(tester), ['IMG_0.jpg', 'IMG_1.jpg', 'IMG_2.jpg', 'IMG_4.jpg', 'edits/IMG_3.jpg']);
      expect(find.text('5 photos'), findsOneWidget);
      expect(LeaveWarning.active.value, isFalse);
      expect(find.widgetWithText(FilledButton, 'Make photos available'), findsOneWidget);
      // The new photos are added as they're stored, not by listing again.
      expect(admin.calls.where((call) => call.startsWith('listSessionPhotos')), hasLength(1));
    });

    testWidgets('skips photos already here, and refuses files that aren’t photos without sending them',
        (tester) async {
      final admin = _service();
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: admin, picker: picker);

      await _upload(tester, picker, ['IMG_1.jpg', 'notes.txt', 'IMG_9.jpg']);

      expect(admin.uploads.map((upload) => upload.fullPath), ['galleries/s1/IMG_9.jpg']);
      expect(find.text('Uploading 0 of 2 · 1 failed · 1 skipped'), findsOneWidget);
      expect(find.text('notes.txt isn’t a photo.'), findsOneWidget);

      admin.uploads.single.complete();
      await _settleUploads(tester);

      // A failure holds back "Make photos available" until it's dealt with;
      // this one can't be retried.
      expect(
        find.text('Some files can’t be uploaded (see below). Clear the upload list to go ahead without them.'),
        findsOneWidget,
      );
      expect(find.text('Retry failed'), findsNothing);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Make photos available')).onPressed,
          isNull);
      await tapInView(tester, find.text('Clear upload list'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Uploaded'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Make photos available'), findsOneWidget);
    });

    testWidgets('keyboard: "Clear upload list" hands focus to "Make photos available"', (tester) async {
      final picker = FakePhotoPicker();
      await _pumpSession(tester, picker: picker);
      await _upload(tester, picker, ['notes.txt']);
      await _settleUploads(tester);
      Focus.of(tester.element(find.text('Clear upload list'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Clear upload list'), findsNothing);
      expect(hasFocus(tester, find.text('Make photos available')), isTrue);
    });

    testWidgets('keyboard: "Hide photos" while uploading hands focus to "Upload photos"', (tester) async {
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: _service(ready: true), picker: picker);
      await _upload(tester, picker, ['IMG_4.jpg']);
      Focus.of(tester.element(find.text('Hide photos'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // It's "Make photos available" now, switched off until the upload ends.
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Make photos available')).onPressed,
          isNull);
      expect(hasFocus(tester, find.text('Upload photos')), isTrue);
    });

    testWidgets('a failed upload says why, and can be retried', (tester) async {
      final admin = _service();
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: admin, picker: picker);

      await _upload(tester, picker, ['IMG_4.jpg']);
      admin.uploads.single.fail(AdminErrorKind.offline);
      await _settleUploads(tester);

      expect(find.text(kAdminOfflineMessage), findsOneWidget);
      expect(LeaveWarning.active.value, isFalse);
      expect(
        find.text('Some photos didn’t upload. Retry them, or clear the upload list to go ahead without them.'),
        findsOneWidget,
      );
      await tapInView(tester, find.text('Retry failed'));
      await tester.pump();
      admin.uploads.last.complete();
      await _settleUploads(tester);

      expect(admin.uploads, hasLength(2));
      expect(_listed(tester), contains('IMG_4.jpg'));
      expect(find.widgetWithText(FilledButton, 'Make photos available'), findsOneWidget);
    });

    testWidgets('"Cancel uploads" stops them', (tester) async {
      final admin = _service();
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: admin, picker: picker);

      await _upload(tester, picker, ['IMG_4.jpg', 'IMG_5.jpg']);
      await tapInView(tester, find.text('Cancel uploads'));
      await _settleUploads(tester);

      expect(admin.uploads.every((upload) => upload.cancelled), isTrue);
      expect(find.text('Uploaded 0 of 2 · 2 cancelled'), findsOneWidget);
      expect(LeaveWarning.active.value, isFalse);
      expect(_listed(tester), _photos);
    });

    testWidgets('a cancelled picker changes nothing', (tester) async {
      final admin = _service();
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: admin, picker: picker);

      await _upload(tester, picker, []);

      expect(admin.uploads, isEmpty);
      expect(find.textContaining('Uploading'), findsNothing);
    });

    testWidgets('a picker that never answers doesn’t hold the page up', (tester) async {
      final picker = FakePhotoPicker()..neverAnswers = true;
      await _pumpSession(tester, picker: picker);

      await tapInView(tester, find.text('Upload photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload photos'));
      await tester.pumpAndSettle();

      expect(picker.accepts, hasLength(2));
      expect(find.widgetWithText(FilledButton, 'Make photos available'), findsOneWidget);
    });

    testWidgets('photos added once they’re available: families need to download again', (tester) async {
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: _service(ready: true, autoCompleteUploads: true), picker: picker);

      expect(find.textContaining('need to download again'), findsNothing);
      await _upload(tester, picker, ['IMG_4.jpg']);
      await _settleUploads(tester);

      expect(
        find.widgetWithText(InlineMessage, 'Families who already downloaded need to download again to get these.'),
        findsOneWidget,
      );
    });

    testWidgets('only photos added after they’re available need downloading again, while they’re still here',
        (tester) async {
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: _service(autoCompleteUploads: true), picker: picker);
      const note = 'Families who already downloaded need to download again to get these.';

      // Uploaded first, then made available: nobody could have downloaded.
      await _upload(tester, picker, ['IMG_4.jpg']);
      await _settleUploads(tester);
      await tapInView(tester, find.text('Make photos available'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Make photos available'));
      await tester.pumpAndSettle();
      expect(find.text('Ready to download'), findsOneWidget);
      expect(find.text(note), findsNothing);

      await _upload(tester, picker, ['IMG_5.jpg']);
      await _settleUploads(tester);
      expect(find.widgetWithText(InlineMessage, note), findsOneWidget);

      // Gone again, so there's nothing new to get.
      await tapInView(tester, find.byTooltip('Delete IMG_5.jpg'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete photo'));
      await tester.pumpAndSettle();
      expect(find.text(note), findsNothing);

      // Hiding them starts over.
      await _upload(tester, picker, ['IMG_6.jpg']);
      await _settleUploads(tester);
      expect(find.text(note), findsOneWidget);
      await tapInView(tester, find.text('Hide photos'));
      await tester.pumpAndSettle();
      await tapInView(tester, find.text('Make photos available'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Make photos available'));
      await tester.pumpAndSettle();
      expect(find.text('Ready to download'), findsOneWidget);
      expect(find.text(note), findsNothing);
    });

    group('leaving', () {
      /// The session page over a page to go back to.
      Future<void> pumpOver(WidgetTester tester, FakeAdminService admin, FakePhotoPicker picker) async {
        await pumpAdminPage(tester, const Scaffold(body: Text('Below')), admin: admin, picker: picker);
        tester.state<NavigatorState>(find.byType(Navigator)).push(
              MaterialPageRoute<void>(builder: (context) => const AdminSessionPage(sessionId: 's1')),
            );
        await tester.pumpAndSettle();
      }

      testWidgets('with nothing uploading, back just goes back', (tester) async {
        await pumpOver(tester, _service(), FakePhotoPicker());

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        expect(find.text('Below'), findsOneWidget);
      });

      testWidgets('while uploading, back asks first; stopping cancels the uploads', (tester) async {
        final admin = _service();
        final picker = FakePhotoPicker();
        await pumpOver(tester, admin, picker);
        await _upload(tester, picker, ['IMG_4.jpg']);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Stop uploading?'), findsOneWidget);
        await tester.tap(_inDialog('Keep uploading'));
        await tester.pumpAndSettle();
        expect(find.byType(AdminSessionPage), findsOneWidget);
        expect(admin.uploads.single.cancelled, isFalse);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(_inDialog('Stop uploading'));
        await tester.pumpAndSettle();

        expect(find.text('Below'), findsOneWidget);
        expect(find.byType(AdminSessionPage), findsNothing);
        expect(admin.uploads.single.cancelled, isTrue);
        expect(LeaveWarning.active.value, isFalse);
      });
    });
  });

  group('the photos', () {
    testWidgets('every photo, subfolders too, by name, with the count', (tester) async {
      await _pumpSession(tester);

      expect(_listed(tester), ['IMG_1.jpg', 'IMG_2.jpg', 'edits/IMG_3.jpg']);
      expect(find.text('3 photos'), findsOneWidget);
    });

    testWidgets('one photo is deleted after asking', (tester) async {
      final admin = _service();
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.byTooltip('Delete IMG_2.jpg'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this photo?'), findsOneWidget);
      expect(find.text('IMG_2.jpg will be deleted for good.'), findsOneWidget);
      await tester.tap(_inDialog('Delete photo'));
      await tester.pumpAndSettle();

      expect(admin.calls, contains('deletePhoto(galleries/s1/IMG_2.jpg)'));
      expect(_listed(tester), ['IMG_1.jpg', 'edits/IMG_3.jpg']);
      expect(find.text('2 photos'), findsOneWidget);
    });

    testWidgets('cancelling keeps the photo', (tester) async {
      final admin = _service();
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.byTooltip('Delete IMG_2.jpg'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();

      expect(admin.calls.where((call) => call.startsWith('deletePhoto')), isEmpty);
      expect(_listed(tester), _photos);
    });

    testWidgets('a photo that isn’t deleted stays, and says why', (tester) async {
      final admin = _service()..errors['deletePhoto'] = adminError(AdminErrorKind.offline);
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.byTooltip('Delete IMG_2.jpg'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete photo'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InlineMessage, kAdminOfflineMessage), findsOneWidget);
      expect(_listed(tester), _photos);
    });

    testWidgets('keyboard: a deleted photo hands focus to the next one, and the last to the one before',
        (tester) async {
      await _pumpSession(tester);

      tester.widget<IconButton>(_deleteButton('IMG_2.jpg')).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete photo'));
      await tester.pumpAndSettle();

      expect(tester.widget<IconButton>(_deleteButton('edits/IMG_3.jpg')).focusNode!.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete photo'));
      await tester.pumpAndSettle();

      expect(tester.widget<IconButton>(_deleteButton('IMG_1.jpg')).focusNode!.hasPrimaryFocus, isTrue);
    });

    testWidgets('"Delete all photos": one confirmation, then progress, then the empty band', (tester) async {
      final names = [for (var i = 1; i <= 5; i++) 'IMG_$i.jpg'];
      final admin = _service(photos: names)..writeDelay = const Duration(milliseconds: 100);
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Delete all photos'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all photos?'), findsOneWidget);
      expect(find.text('All 5 photos in this session will be deleted for good.'), findsOneWidget);
      await tester.tap(_inDialog('Delete all photos'));
      await tester.pump();
      expect(find.text('Deleting 0 of 5…'), findsOneWidget);
      // Uploading and "Make photos available" wait meanwhile.
      expect(find.text('Wait for the photos to finish deleting.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Upload photos')).onPressed, isNull);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Deleting 3 of 5…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(admin.calls.where((call) => call.startsWith('deletePhoto')), hasLength(5));
      expect(find.widgetWithText(EmptyState, 'No photos yet. Upload them above.'), findsOneWidget);
      expect(find.text('Delete all photos'), findsNothing);
      expect(find.text('Upload photos first.'), findsOneWidget);
    });

    testWidgets('"Delete all photos" stops at a failure, and says how far it got', (tester) async {
      final names = [for (var i = 1; i <= 5; i++) 'IMG_$i.jpg'];
      final admin = _service(photos: names);
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Delete all photos'));
      await tester.pumpAndSettle();
      // The first of the three deleted at once fails; the other two finish.
      admin.nextError = adminError(AdminErrorKind.offline);
      await tester.tap(_inDialog('Delete all photos'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InlineMessage, 'Deleted 2 of 5. $kAdminOfflineMessage'), findsOneWidget);
      expect(_listed(tester), hasLength(3));
      expect(find.text('Delete all photos'), findsOneWidget);
    });

    testWidgets('"Delete all photos" hides available photos from the family first, and says so', (tester) async {
      final admin = _service(ready: true);
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Delete all photos'));
      await tester.pumpAndSettle();
      expect(
        find.text('All 3 photos in this session will be deleted for good. They’ll be hidden from the family first.'),
        findsOneWidget,
      );
      await tester.tap(_inDialog('Delete all photos'));
      await tester.pumpAndSettle();

      final hidden = admin.calls.indexOf('setPhotosReady(s1, false)');
      expect(hidden, isNonNegative);
      expect(admin.calls.indexWhere((call) => call.startsWith('deletePhoto')), greaterThan(hidden));
      expect(admin.sessionPhotos['s1'], isEmpty);
      expect(find.text('Not ready'), findsOneWidget);
    });

    testWidgets('"Delete all photos" deletes nothing if the photos can’t be hidden first', (tester) async {
      final admin = _service(ready: true)..errors['setPhotosReady'] = adminError(AdminErrorKind.offline);
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Delete all photos'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete all photos'));
      await tester.pumpAndSettle();

      expect(admin.calls.where((call) => call.startsWith('deletePhoto')), isEmpty);
      expect(
        find.widgetWithText(InlineMessage, 'The photos weren’t hidden, so none were deleted. $kAdminOfflineMessage'),
        findsOneWidget,
      );
      expect(_listed(tester), _photos);
      expect(find.text('Ready to download'), findsOneWidget);
    });

    testWidgets('available with no photos: says the family’s download has nothing in it', (tester) async {
      await _pumpSession(tester, admin: _service(ready: true, photos: const []));

      expect(find.text('There are no photos to download. Upload them, or hide the photos until you do.'),
          findsOneWidget);
      expect(find.textContaining('every photo below'), findsNothing);
    });

    testWidgets('keyboard: after "Delete all photos", focus goes to "Upload photos"', (tester) async {
      await _pumpSession(tester);
      Focus.of(tester.element(find.text('Delete all photos'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete all photos'));
      await tester.pumpAndSettle();

      expect(hasFocus(tester, find.text('Upload photos')), isTrue);
    });

    testWidgets('says so when the photos can’t be listed, and holds back what needs them', (tester) async {
      final admin = _service()..errors['listSessionPhotos'] = adminError(AdminErrorKind.offline);
      await _pumpSession(tester, admin: admin);

      const message = 'We couldn’t list this session’s photos. Refresh the page to try again.';
      expect(find.widgetWithText(InlineMessage, message), findsOneWidget);
      expect(find.text('Refresh the page to load the photos first.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Upload photos')).onPressed, isNull);
    });
  });

  group('deleting the session', () {
    /// The admin page with [admin]'s sessions, and the session 's1' opened
    /// from it.
    Future<void> openFromAdmin(WidgetTester tester, FakeAdminService admin) async {
      await pumpAdminPage(tester, const AdminPage(), admin: admin);
      await tapInView(tester, find.byKey(const ValueKey('s1')));
      await tester.pumpAndSettle();
    }

    testWidgets('asks, deletes, and goes back to Admin, which says so', (tester) async {
      final admin = _service();
      await openFromAdmin(tester, admin);

      await tapInView(tester, find.text('Delete session'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this session?'), findsOneWidget);
      expect(find.text('The session and its 3 photos will be deleted for good.'), findsOneWidget);
      await tester.tap(_inDialog('Delete session'));
      // On its way out, it doesn't flash "deleted".
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('This session was deleted.'), findsNothing);
      }
      await tester.pumpAndSettle();

      expect(admin.calls, contains('deleteSession(s1)'));
      expect(find.byType(AdminSessionPage), findsNothing);
      expect(find.widgetWithText(InlineMessage, 'Deleted the Harper family’s session.'), findsOneWidget);
      expect(find.byKey(const ValueKey('s1')), findsNothing);
    });

    testWidgets('a name that doesn’t start with "The" is kept as it is', (tester) async {
      final admin = FakeAdminService(sessions: [testSession('s1', name: 'Grandma Jo')]);
      await openFromAdmin(tester, admin);

      await tapInView(tester, find.text('Delete session'));
      await tester.pumpAndSettle();
      expect(find.text('The session will be deleted for good.'), findsOneWidget);
      await tester.tap(_inDialog('Delete session'));
      await tester.pumpAndSettle();

      expect(find.text('Deleted Grandma Jo’s session.'), findsOneWidget);
    });

    testWidgets('stops uploads first, so nothing lands in its folder afterwards', (tester) async {
      final admin = _service();
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: admin, picker: picker);
      await _upload(tester, picker, ['IMG_4.jpg']);

      await tapInView(tester, find.text('Delete session'));
      await tester.pumpAndSettle();
      expect(find.text('The session and its 3 photos will be deleted for good. Uploads still running will stop.'),
          findsOneWidget);
      await tester.tap(_inDialog('Delete session'));
      await tester.pumpAndSettle();

      expect(admin.uploads.single.cancelled, isTrue);
      expect(admin.calls.last, 'deleteSession(s1)');
    });

    testWidgets('failed uploads can’t be retried into it while it’s being deleted', (tester) async {
      final admin = _service()..writeDelay = const Duration(seconds: 1);
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: admin, picker: picker);
      await _upload(tester, picker, ['IMG_4.jpg', 'IMG_5.jpg']);
      for (final upload in admin.pendingUploads) {
        upload.fail(AdminErrorKind.offline);
      }
      await _settleUploads(tester);
      expect(find.text('Retry failed'), findsOneWidget);

      await tapInView(tester, find.text('Delete session'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete session'));
      await tester.pump();

      expect(find.text('Deleting session…'), findsOneWidget);
      expect(find.text('Retry failed'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(admin.uploads, hasLength(2));
    });

    testWidgets('photos picked before it started deleting aren’t uploaded into it', (tester) async {
      final admin = _service()..writeDelay = const Duration(seconds: 1);
      final picker = _LatePicker();
      await _pumpSession(tester, admin: admin, picker: picker);
      await tapInView(tester, find.text('Upload photos'));
      await tester.pumpAndSettle();

      await tapInView(tester, find.text('Delete session'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete session'));
      await tester.pump();
      picker.answer.complete([testPhoto('IMG_9.jpg')]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(admin.calls, contains('deleteSession(s1)'));
      expect(admin.uploads, isEmpty);
    });

    testWidgets('says why when it isn’t deleted, and stays', (tester) async {
      final admin = _service(photos: const [])..errors['deleteSession'] = adminError(AdminErrorKind.denied);
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Delete session'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete session'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InlineMessage, kAdminDeniedMessage), findsOneWidget);
      expect(find.byType(AdminSessionPage), findsOneWidget);
      expect(find.text('Delete session'), findsOneWidget);
    });

    testWidgets('failing part way: lists the photos again, so the page shows only what’s left', (tester) async {
      final admin = _PartDeletingAdminService(
        sessions: [testSession('s1', photosReady: true)],
        sessionPhotos: {'s1': _photos},
      );
      await _pumpSession(tester, admin: admin);

      await tapInView(tester, find.text('Delete session'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Delete session'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(InlineMessage,
            '$kAdminOfflineMessage Some of its photos may already be deleted: the list shows what’s left.'),
        findsOneWidget,
      );
      expect(_listed(tester), ['edits/IMG_3.jpg']);
      expect(find.text('1 photo'), findsOneWidget);
      await tapInView(tester, find.text('Make photos available'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 photo. '), findsOneWidget);
    });
  });

  group('when there’s no session to show', () {
    testWidgets('deleted (or never there): says so, with the way back to Admin', (tester) async {
      final admin = _service();
      await _pumpSession(tester, admin: admin, id: 'gone');

      expect(find.widgetWithText(EmptyState, 'This session was deleted.'), findsOneWidget);
      expect(tester.widget<BrookieTopBar>(find.byType(BrookieTopBar)).title, 'Session');
      expect(admin.calls.where((call) => call.startsWith('listSessionPhotos')), isEmpty);
      await tester.tap(find.text('Go to Admin'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminPage), findsOneWidget);
      expect(ModalRoute.of(tester.element(find.byType(AdminPage)))!.settings.name, AdminPage.routeName);
    });

    testWidgets('deleted elsewhere while open: says so, and stops its uploads', (tester) async {
      final admin = _service();
      final picker = FakePhotoPicker();
      await _pumpSession(tester, admin: admin, picker: picker);
      await _upload(tester, picker, ['IMG_4.jpg']);

      admin.sessions.remove('s1');
      admin.notifyChanged();
      await tester.pumpAndSettle();

      expect(find.text('This session was deleted.'), findsOneWidget);
      expect(admin.uploads.single.cancelled, isTrue);
      expect(tester.widget<BrookieTopBar>(find.byType(BrookieTopBar)).title, 'Session');
    });

    testWidgets('unreadable: says what’s wrong, with its id to find it by', (tester) async {
      final admin =
          FakeAdminService(unreadable: [const UnreadableBooking(id: 'bad1', problem: 'date isn’t YYYY-MM-DD')]);
      await _pumpSession(tester, admin: admin, id: 'bad1');

      expect(
        find.widgetWithText(InlineMessage,
            'This session couldn’t be read: date isn’t YYYY-MM-DD. Fix it in the Firestore console.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SelectableText, 'Document ID: bad1'), findsOneWidget);
      expect(find.text('Go to Admin'), findsOneWidget);
    });

    testWidgets('can’t be loaded: says so', (tester) async {
      await _pumpSession(tester, admin: _service()..watchError = adminError(AdminErrorKind.denied));

      expect(find.widgetWithText(InlineMessage, 'We couldn’t load this session. Refresh the page to try again.'),
          findsOneWidget);
    });

    testWidgets('not an admin: the gate, and nothing asked of Firestore', (tester) async {
      final admin = _service();
      await pumpAdminPage(tester, const AdminSessionPage(sessionId: 's1'),
          admin: admin, auth: FakeAuthService(signedInAs: testUser));

      expect(find.textContaining('isn’t an admin'), findsOneWidget);
      expect(admin.calls, isEmpty);
    });

    testWidgets('signing out: the top bar stops naming the session', (tester) async {
      final auth = FakeAuthService(signedInAs: studio, admin: true);
      await pumpAdminPage(tester, const AdminSessionPage(sessionId: 's1'), admin: _service(), auth: auth);
      expect(tester.widget<BrookieTopBar>(find.byType(BrookieTopBar)).title, 'The Harper family');

      await auth.signOut();
      await tester.pumpAndSettle();

      expect(find.textContaining('Sign in with the studio’s Google account'), findsOneWidget);
      expect(tester.widget<BrookieTopBar>(find.byType(BrookieTopBar)).title, 'Session');
    });
  });

  for (final brightness in Brightness.values) {
    for (final width in adminTestWidths) {
      testWidgets('fits ${width.toInt()}px in ${brightness.name} while uploading, with one primary button',
          (tester) async {
        final admin = _service();
        final picker = FakePhotoPicker();
        await _pumpSession(tester, admin: admin, picker: picker, size: Size(width, 800), brightness: brightness);
        expect(filledButtons(), 1);

        await _upload(tester, picker, ['a_very_long_file_name_from_the_camera_0001.jpg', 'notes.txt', 'IMG_1.jpg']);
        admin.uploads.single.setProgress(0.5);
        await _settleUploads(tester);

        expect(tester.takeException(), isNull);
        expect(filledButtons(), 1);
      });

      testWidgets('a booking with its photos available fits ${width.toInt()}px in ${brightness.name}',
          (tester) async {
        final admin = FakeAdminService(sessions: [
          testSession('b',
              name: null,
              email: 'a.very.long.address.for.a.family@example.com',
              status: BookingStatus.pending,
              uid: 'AbCdEfGhIjKlMnOpQrStUvWxYz012',
              photosReady: true),
        ], sessionPhotos: {
          'b': ['a/very/deep/folder/with/a_long_photo_name_0001.jpg'],
        });
        await _pumpSession(tester, admin: admin, id: 'b', size: Size(width, 800), brightness: brightness);

        expect(tester.takeException(), isNull);
        expect(filledButtons(), 0);
      });
    }
  }
}

/// A file picker that answers only when the test completes [answer], as a
/// person still choosing files does.
class _LatePicker extends FakePhotoPicker {
  final answer = Completer<List<PickedPhoto>>();

  @override
  Future<List<PickedPhoto>> call({required String accept}) {
    accepts.add(accept);
    return answer.future;
  }
}

/// Deletes a session's photos as AdminService does (hidden first, then the
/// photos) but goes offline after the first two, before the document.
class _PartDeletingAdminService extends FakeAdminService {
  _PartDeletingAdminService({super.sessions, super.sessionPhotos});

  @override
  Future<void> deleteSession(String id) async {
    calls.add('deleteSession($id)');
    await setPhotosReady(id, false);
    final names = sessionPhotos[id]!..sort();
    names.removeRange(0, 2);
    throw adminError(AdminErrorKind.offline);
  }
}
