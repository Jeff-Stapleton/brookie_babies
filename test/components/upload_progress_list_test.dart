import 'package:brookie_babies/components/upload_progress_list.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/upload_queue.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeAdminService admin;
  late UploadQueue queue;

  setUp(() {
    admin = FakeAdminService();
    queue = UploadQueue(
      upload: (photo, name) => admin.uploadSessionPhoto('s1', photo, name),
      validate: PhotoRules.sessionPhotoProblem,
      progressInterval: Duration.zero,
    );
  });

  Future<void> pumpList(WidgetTester tester, {Brightness brightness = Brightness.light, double width = 1440}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: brookieTheme(brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(BrookieSpace.s4),
          child: UploadProgressList(queue: queue),
        ),
      ),
    ));
  }

  /// Takes the list down before the queue goes, as a page would.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    queue.dispose();
  }

  /// Lets uploads report back, and the queue's progress (gathered on a
  /// zero timer here) reach the list.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  String summary(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: find.byType(UploadProgressList), matching: find.byType(Text)).first)
      .data!;

  testWidgets('shows nothing until photos are picked', (tester) async {
    await pumpList(tester);

    expect(tester.getSize(find.byType(UploadProgressList)), Size.zero);
    await finish(tester);
  });

  testWidgets('one summary line counts what’s done, failed and skipped', (tester) async {
    await pumpList(tester);
    queue.add([
      testPhoto('IMG_1.jpg'),
      testPhoto('IMG_2.jpg'),
      testPhoto('IMG_3.jpg'),
      testPhoto('notes.txt', contentType: 'text/plain'),
    ], existing: ['IMG_3.jpg']);
    await settle(tester);
    expect(summary(tester), 'Uploading 0 of 3 · 1 failed · 1 skipped');

    admin.uploads[0].complete();
    await settle(tester);
    expect(summary(tester), 'Uploading 1 of 3 · 1 failed · 1 skipped');

    admin.uploads[1].complete();
    await settle(tester);
    expect(summary(tester), 'Uploaded 2 of 3 · 1 failed · 1 skipped');
    await finish(tester);
  });

  testWidgets('once all are stored: "Uploaded 3 photos", or "1 photo"', (tester) async {
    await pumpList(tester);
    queue.add([testPhoto('IMG_1.jpg')]);
    admin.uploads.single.complete();
    await settle(tester);
    expect(summary(tester), 'Uploaded 1 photo');

    queue.add([testPhoto('IMG_2.jpg'), testPhoto('IMG_3.jpg')]);
    for (final upload in admin.pendingUploads) {
      upload.complete();
    }
    await settle(tester);
    expect(summary(tester), 'Uploaded 3 photos');
    await finish(tester);
  });

  testWidgets('every photo already here: nothing new to upload', (tester) async {
    await pumpList(tester);
    queue.add([testPhoto('IMG_1.jpg'), testPhoto('IMG_2.jpg')], existing: ['IMG_1.jpg', 'IMG_2.jpg']);
    await settle(tester);

    expect(summary(tester), 'Nothing new to upload · 2 skipped');
    await finish(tester);
  });

  testWidgets('cancelled uploads are counted as cancelled', (tester) async {
    await pumpList(tester);
    queue.add([for (var i = 1; i <= 4; i++) testPhoto('IMG_$i.jpg')]);
    admin.uploads.first.complete();
    await settle(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel uploads'));
    await settle(tester);

    expect(summary(tester), 'Uploaded 1 of 4 · 3 cancelled');
    expect(find.text('Cancel uploads'), findsNothing);
    await finish(tester);
  });

  testWidgets('the summary is the only live region', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester);
    queue.add([testPhoto('IMG_1.jpg'), testPhoto('notes.txt', contentType: 'text/plain')], existing: ['IMG_9.jpg']);
    await settle(tester);

    final live = find.descendant(
      of: find.byType(UploadProgressList),
      matching: find.byWidgetPredicate((widget) => widget is Semantics && (widget.properties.liveRegion ?? false)),
    );
    expect(live, findsOneWidget);
    expect(find.descendant(of: live, matching: find.text('Uploading 0 of 2 · 1 failed')), findsOneWidget);
    semantics.dispose();
    await finish(tester);
  });

  testWidgets('lists only the photos uploading now, with their progress', (tester) async {
    await pumpList(tester);
    queue.add([for (var i = 1; i <= 5; i++) testPhoto('IMG_$i.jpg')]);
    admin.uploads.first.complete();
    await settle(tester);
    admin.uploads[1].setProgress(0.25);
    await settle(tester);

    // IMG_1 is done and IMG_5 is waiting: neither is listed.
    expect(find.text('IMG_1.jpg'), findsNothing);
    expect(find.text('IMG_5.jpg'), findsNothing);
    for (final name in ['IMG_2.jpg', 'IMG_3.jpg', 'IMG_4.jpg']) {
      expect(find.text(name), findsOneWidget);
    }
    final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
    expect(bars.map((bar) => bar.value), [0.25, 0, 0]);
    expect(bars.first.semanticsLabel, 'IMG_2.jpg');
    expect(bars.first.semanticsValue, '25%');
    await finish(tester);
  });

  testWidgets('failed photos are listed open, each with why', (tester) async {
    await pumpList(tester);
    queue.add([testPhoto('notes.txt', contentType: 'text/plain'), testPhoto('IMG_1.jpg')]);
    admin.uploads.single.fail(AdminErrorKind.quota);
    await settle(tester);

    expect(find.widgetWithText(TextButton, '2 failed'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('notes.txt isn’t a photo.'), findsOneWidget);
    expect(find.text('IMG_1.jpg'), findsOneWidget);
    expect(find.text(kAdminQuotaMessage), findsOneWidget);

    await tester.tap(find.text('2 failed'));
    await settle(tester);
    expect(find.text('notes.txt'), findsNothing);
    await finish(tester);
  });

  testWidgets('skipped photos are listed closed, and open to say why', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester);
    queue.add([testPhoto('IMG_1.jpg'), testPhoto('IMG_2.jpg')], existing: ['IMG_1.jpg', 'IMG_2.jpg']);
    await settle(tester);

    final toggle = find.widgetWithText(TextButton, '2 skipped');
    expect(tester.getSemantics(toggle), isSemantics(isButton: true, hasExpandedState: true, isExpanded: false));
    expect(find.text('IMG_1.jpg'), findsNothing);

    await tester.tap(toggle);
    await settle(tester);

    expect(tester.getSemantics(toggle), isSemantics(isButton: true, hasExpandedState: true, isExpanded: true));
    expect(find.text('IMG_1.jpg'), findsOneWidget);
    expect(find.text(kUploadAlreadyHere), findsNWidgets(2));
    semantics.dispose();
    await finish(tester);
  });

  testWidgets('"Retry failed" retries the ones that can be; "Cancel uploads" shows only while busy', (tester) async {
    await pumpList(tester);
    queue.add([testPhoto('IMG_1.jpg'), testPhoto('IMG_2.jpg')]);
    admin.uploads[0].fail(AdminErrorKind.offline);
    await settle(tester);
    expect(find.widgetWithText(OutlinedButton, 'Retry failed'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel uploads'), findsOneWidget);

    admin.uploads[1].complete();
    await settle(tester);
    expect(find.text('Cancel uploads'), findsNothing);

    await tester.tap(find.text('Retry failed'));
    await settle(tester);
    expect(admin.uploads, hasLength(3));
    expect(summary(tester), 'Uploading 1 of 2');
    expect(find.text('Retry failed'), findsNothing);
    expect(find.text('Cancel uploads'), findsOneWidget);

    admin.uploads.last.complete();
    await settle(tester);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    await finish(tester);
  });

  group('a focused button that goes hands keyboard focus on', () {
    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    Future<void> pressWithKeyboard(WidgetTester tester, String label) async {
      final button = find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>());
      tester.widget<ButtonStyleButton>(button).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
    }

    testWidgets('"Retry failed" to "Cancel uploads", as the retries run', (tester) async {
      await pumpList(tester);
      queue.add([testPhoto('IMG_1.jpg'), testPhoto('IMG_2.jpg')]);
      admin.uploads[0].fail(AdminErrorKind.offline);
      admin.uploads[1].complete();
      await settle(tester);

      await pressWithKeyboard(tester, 'Retry failed');

      expect(find.text('Retry failed'), findsNothing);
      expect(focused(), 'Cancel uploads');
      await finish(tester);
    });

    testWidgets('"Cancel uploads" to "Retry failed", once the cancel is through', (tester) async {
      await pumpList(tester);
      queue.add([testPhoto('IMG_1.jpg'), testPhoto('IMG_2.jpg')]);
      admin.uploads[0].fail(AdminErrorKind.offline);
      await settle(tester);

      await pressWithKeyboard(tester, 'Cancel uploads');

      expect(find.text('Cancel uploads'), findsNothing);
      expect(focused(), 'Retry failed');
      await finish(tester);
    });

    testWidgets('with neither left, to the summary, in a focus ring', (tester) async {
      await pumpList(tester);
      queue.add([testPhoto('IMG_1.jpg')]);
      await settle(tester);

      await pressWithKeyboard(tester, 'Cancel uploads');

      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(focused(), 'Upload summary');
      final ring = find.descendant(of: find.byType(UploadProgressList), matching: find.byType(FocusRing));
      expect(tester.widget<FocusRing>(ring).visible, isTrue);
      await finish(tester);
    });

    testWidgets('or to the page’s control, when the page names one', (tester) async {
      final upload = FocusNode(debugLabel: 'Upload photos');
      addTearDown(upload.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: brookieTheme(Brightness.light),
        home: Scaffold(
          body: Column(children: [
            OutlinedButton(focusNode: upload, onPressed: () {}, child: const Text('Upload photos')),
            UploadProgressList(queue: queue, focusWhenDone: upload),
          ]),
        ),
      ));
      queue.add([testPhoto('IMG_1.jpg')]);
      await settle(tester);

      await pressWithKeyboard(tester, 'Cancel uploads');

      expect(focused(), 'Upload photos');
      await finish(tester);
    });

    testWidgets('a tap moves no focus', (tester) async {
      await pumpList(tester);
      queue.add([testPhoto('IMG_1.jpg')]);
      await settle(tester);

      await tester.tap(find.text('Cancel uploads'));
      await settle(tester);

      expect(focused(), isNot(anyOf('Upload summary', 'Cancel uploads', 'Retry failed')));
      await finish(tester);
    });
  });

  testWidgets('only photos the rules refuse failed: nothing to retry', (tester) async {
    await pumpList(tester);
    queue.add([testPhoto('notes.txt', contentType: 'text/plain')]);
    await settle(tester);

    expect(find.text('Retry failed'), findsNothing);
    await finish(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets('a long name fits a 320px phone, with no primary button (${brightness.name})', (tester) async {
      await pumpList(tester, brightness: brightness, width: 320);
      const long = 'IMG_20261019_123456789_HDR_PORTRAIT_FAMILY_SESSION_FINAL_EDIT_V2.jpg';
      queue.add([testPhoto(long), testPhoto('notes $long', contentType: 'text/plain')], existing: ['x.jpg']);
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FilledButton), findsNothing);
      final colors = brightness == Brightness.dark ? BrookieColors.dark : BrookieColors.light;
      final reason = find.text('notes $long isn’t a photo.');
      expect(tester.renderObject<RenderParagraph>(reason).text.style!.color, colors.inkSoft);
      await finish(tester);
    });
  }
}
