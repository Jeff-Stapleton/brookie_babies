// The admin session pages at twice the text size on small phones, and at
// the usual size on a desktop, measured with the real fonts (the test font
// sets every glyph a full em wide, which would overflow where the site
// doesn't).

import 'package:brookie_babies/components/booking_calendar.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_lookup.dart';
import 'package:brookie_babies/pages/admin_page.dart';
import 'package:brookie_babies/pages/admin_session_page.dart';
import 'package:brookie_babies/pages/session_form_page.dart';
import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/admin_test_app.dart';
import '../support/fakes.dart';

const _longEmail = 'a.very.long.address.for.a.family@example.com';

FakeAdminService _service() => FakeAdminService(
      sessions: [
        testSession('s1', time: (hour: 10, minute: 30), location: 'The big oak tree in Liberty Park, by the pond'),
        testSession('paid',
            name: null, email: _longEmail, status: BookingStatus.paid, uid: 'AbCdEfGhIjKlMnOpQrStUvWxYz01'),
        testSession('old', name: 'Grandma Jo', status: BookingStatus.refunded, date: DateTime(2001, 2, 3)),
      ],
      unreadable: [const UnreadableBooking(id: 'Kd83jsAa0PqLm', problem: 'date isn’t YYYY-MM-DD')],
      sessionPhotos: {
        's1': ['IMG_0001.jpg', 'edits/a_long_name_from_the_camera_0002.jpg'],
        'paid': ['IMG_1.jpg'],
      },
    );

/// Whether some word of [text] is wider than its line, so it must break
/// inside the word. Zero-width spaces (offered breaks) count as gaps.
bool _breaksAWord(WidgetTester tester, Finder text) {
  final paragraph =
      tester.renderObject<RenderParagraph>(find.descendant(of: text, matching: find.byType(RichText), matchRoot: true));
  for (final word in paragraph.text.toPlainText().split(RegExp('[\\s​-]+'))) {
    final painter = TextPainter(
      text: TextSpan(text: word, style: paragraph.text.style),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    final tooWide = painter.width > paragraph.constraints.maxWidth + 0.5;
    painter.dispose();
    if (tooWide) return true;
  }
  return false;
}

void main() {
  setUpAll(loadBrookieFonts);
  tearDown(LeaveWarning.reset);
  tearDown(AdminPage.clearNotice);

  for (final (width, scale) in [(320.0, 2.0), (390.0, 2.0), (1440.0, 1.0)]) {
    final at = '${width.toInt()}px at ${scale}x text';

    testWidgets('Admin at $at: nothing overflows', (tester) async {
      await pumpAdminPage(tester, const AdminPage(), admin: _service(), size: Size(width, 800), textScale: scale);
      AdminPage.returnWithNotice(tester.element(find.byType(AdminPage)), 'Deleted the Harper family’s session.');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_breaksAWord(tester, find.text('Sessions')), isFalse);
    });

    testWidgets('an ad hoc session at $at, uploading: nothing overflows', (tester) async {
      final admin = _service();
      final picker = FakePhotoPicker()
        ..next = [testPhoto('IMG_0003.jpg'), testPhoto('notes.txt', contentType: 'text/plain')];
      await pumpAdminPage(tester, const AdminSessionPage(sessionId: 's1'),
          admin: admin, picker: picker, size: Size(width, 800), textScale: scale);
      expect(tester.takeException(), isNull);

      await tapInView(tester, find.text('Upload photos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a booking named by a long email at $at: it breaks at its dots, not mid-word', (tester) async {
      await pumpAdminPage(tester, const AdminSessionPage(sessionId: 'paid'),
          admin: _service(), size: Size(width, 800), textScale: scale);

      expect(tester.takeException(), isNull);
      final headline = find.descendant(of: find.byType(SingleChildScrollView), matching: findDisplayName(_longEmail));
      expect(_breaksAWord(tester, headline), isFalse);
    });

    testWidgets('the form at $at, with its errors and the calendar: nothing overflows', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(session: testSession('s1')),
          admin: _service(), size: Size(width, 800), textScale: scale);
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'not an email');
      await tapInView(tester, find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tapInView(tester, find.text('Mon, Mar 4, 2999'));
      await tester.pumpAndSettle();
      expect(find.byType(BookingCalendar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
