import 'package:brookie_babies/components/home_photo_library.dart';
import 'package:brookie_babies/components/home_photo_order.dart';
import 'package:brookie_babies/components/upload_progress_list.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/pages/home_photos_admin_page.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:brookie_babies/utilities/upload_queue.dart';
import 'package:brookie_babies/widgets/network_photo.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_photos.dart';
import '../support/fakes.dart';

const _studio = AppUser(uid: 'studio', email: 'studio@example.com', displayName: 'Brooke');

/// 'IMG_01.jpg', 'IMG_02.jpg', ... in name order.
List<String> _photos(int count) => [
      for (var i = 1; i <= count; i++) 'IMG_${i.toString().padLeft(2, '0')}.jpg',
    ];

/// Counts the home page's photo loads, to see HomePage.reloadPhotos at work.
class _CountingPortfolio extends FakePortfolioService {
  int loads = 0;

  @override
  Future<List<Uri>> photoUrls({int? limit}) {
    loads++;
    return super.photoUrls(limit: limit);
  }
}

void main() {
  // Library photos stay loading, so they show their placeholders.
  final server = FakePhotoServer();
  late FakeAdminService admin;
  late FakePhotoPicker picker;
  late _CountingPortfolio portfolio;

  void photoTest(String description, Future<void> Function(WidgetTester tester) body) {
    testWidgets(description, (tester) async {
      addTearDown(LeaveWarning.reset);
      server.start();
      try {
        await body(tester);
      } finally {
        server.stop();
      }
    });
  }

  setUp(() {
    admin = FakeAdminService(library: _photos(10), homeNames: ['IMG_03.jpg', 'IMG_01.jpg', 'IMG_05.jpg']);
    picker = FakePhotoPicker();
    portfolio = _CountingPortfolio();
  });

  /// The home page with the admin's page over it, as the admin page opens
  /// it.
  Future<void> pumpPage(
    WidgetTester tester, {
    // Tall, so the library's first rows are built without scrolling.
    Size size = const Size(1440, 2400),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(
      auth: FakeAuthService(signedInAs: _studio, admin: true),
      admin: admin,
      portfolio: portfolio,
      pickPhotos: picker.call,
      brightness: brightness,
      home: const HomePage(),
    ));
    await tester.pumpAndSettle();
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (context) => const HomePhotosAdminPage()));
    await tester.pumpAndSettle();
  }

  /// The names in "On the home page", in order.
  List<String> chosen(WidgetTester tester) {
    final order = find.byType(HomePhotoOrder);
    if (order.evaluate().isEmpty) return const [];
    return [for (final photo in tester.widget<HomePhotoOrder>(order).photos) photo.name];
  }

  Finder row(String name) => find.descendant(of: find.byType(HomePhotoOrder), matching: find.byKey(ValueKey(name)));
  Finder rowButton(String name, IconData icon) =>
      find.descendant(of: row(name), matching: find.widgetWithIcon(IconButton, icon));
  Finder tile(String name) =>
      find.descendant(of: find.byType(HomePhotoLibrary), matching: find.byKey(ValueKey(name)));
  Finder check(String name) =>
      find.descendant(of: tile(name), matching: find.widgetWithText(OutlinedButton, 'On the home page'));
  Finder deleteButton(Finder within) =>
      find.descendant(of: within, matching: find.widgetWithIcon(IconButton, Icons.delete_outline));
  bool isChecked(WidgetTester tester, String name) =>
      isSemantics(hasCheckedState: true, isChecked: true).matches(tester.getSemantics(check(name)), {});
  bool isEnabled(WidgetTester tester, Finder button) => tester.widget<ButtonStyleButton>(button).onPressed != null;
  bool iconEnabled(WidgetTester tester, Finder button) => tester.widget<IconButton>(button).onPressed != null;
  FocusNode focusOf(WidgetTester tester, Finder button) => tester.widget<IconButton>(button).focusNode!;
  Finder save() => find.widgetWithText(FilledButton, 'Save home page');
  Finder discard() => find.widgetWithText(TextButton, 'Discard changes');

  /// Scrolls [finder] into view, building it first if the library hasn't
  /// yet.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 300,
          scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Focuses [button] and presses Enter on it, as a keyboard user would.
  Future<void> pressWithKeyboard(WidgetTester tester, Finder button) async {
    await reveal(tester, button);
    focusOf(tester, button).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  group('loading', () {
    photoTest('the saved photos in order, each where it goes on the home page', (tester) async {
      await pumpPage(tester);

      expect(admin.calls, containsAll(['listHomeLibrary()', 'homePhotoNames()']));
      expect(chosen(tester), ['IMG_03.jpg', 'IMG_01.jpg', 'IMG_05.jpg']);
      expect(find.descendant(of: row('IMG_03.jpg'), matching: find.text(HomePhotoOrder.heroLabel)), findsOneWidget);
      expect(
        find.descendant(of: row('IMG_01.jpg'), matching: find.text(HomePhotoOrder.featuredLabel)),
        findsOneWidget,
      );
      expect(find.text('3 of 7'), findsOneWidget);
      expect(find.text('10 photos'), findsOneWidget);
      // Nothing changed yet.
      expect(discard(), findsNothing);
      expect(LeaveWarning.active.value, isFalse);
    });

    photoTest('the library: a lazily built grid of photos decoded at about their tile size', (tester) async {
      admin.library
        ..clear()
        ..addAll(_photos(90));
      await pumpPage(tester, size: const Size(1440, 900));
      await reveal(tester, tile('IMG_01.jpg'));

      final tiles = find.descendant(of: find.byType(HomePhotoLibrary), matching: find.byType(NetworkPhoto));
      final built = tiles.evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(90), reason: 'only the rows near the window are built');

      final tileWidth = tester.getSize(tiles.first).width;
      for (final photo in tester.widgetList<NetworkPhoto>(tiles)) {
        final decode = photo.decodeSize!;
        expect(decode.width, greaterThanOrEqualTo(tileWidth));
        expect(decode.width, lessThan(tileWidth + 128));
        expect(decode.height, decode.width * 5 / 4);
      }
      expect(tester.widget<NetworkPhoto>(tiles.first).url, Uri.parse('https://storage.example.com/IMG_01.jpg'));
    });

    photoTest('photos shown stay as they are when one is added or deleted before them', (tester) async {
      admin.autoCompleteUploads = true;
      picker.next = [testPhoto('IMG_00.jpg')];
      await pumpPage(tester);
      State photo(String name) =>
          tester.state(find.descendant(of: tile(name), matching: find.byType(NetworkPhoto)));
      // Five a row: the next slot along, the next row, and the row after.
      const names = ['IMG_01.jpg', 'IMG_05.jpg', 'IMG_10.jpg'];
      final before = {for (final name in names) name: photo(name)};

      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));
      await reveal(tester, tile('IMG_10.jpg'));
      for (final name in names) {
        expect(photo(name), same(before[name]), reason: '$name after an upload');
      }

      await tapAndSettle(tester, deleteButton(tile('IMG_00.jpg')));
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete photo'));
      for (final name in names) {
        expect(photo(name), same(before[name]), reason: '$name after a delete');
      }
    });

    photoTest('decode sizes follow the device’s pixel ratio', (tester) async {
      tester.view.physicalSize = const Size(1440 * 2, 900 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testApp(
        auth: FakeAuthService(signedInAs: _studio, admin: true),
        admin: admin,
        home: const HomePhotosAdminPage(),
      ));
      await tester.pumpAndSettle();

      final photo = find.descendant(of: tile('IMG_01.jpg'), matching: find.byType(NetworkPhoto));
      await reveal(tester, photo);
      final width = tester.getSize(photo).width;
      expect(tester.widget<NetworkPhoto>(photo).decodeSize!.width, greaterThanOrEqualTo(width * 2));
    });

    photoTest('photos on the home page say so under the photo, in butter with an ink edge', (tester) async {
      await pumpPage(tester);

      expect(isChecked(tester, 'IMG_01.jpg'), isTrue);
      expect(isChecked(tester, 'IMG_02.jpg'), isFalse);

      final c = BrookieColors.light;
      final style = tester.widget<OutlinedButton>(check('IMG_01.jpg')).style!;
      expect(style.backgroundColor!.resolve({}), c.butter);
      expect(style.side!.resolve({}), BorderSide(color: c.ink, width: 1.5));
      final off = tester.widget<OutlinedButton>(check('IMG_02.jpg')).style!;
      expect(off.backgroundColor!.resolve({}), Colors.transparent);

      // The photograph itself is left alone: nothing tints it, dims it or
      // sits on it.
      final print = find.descendant(of: tile('IMG_01.jpg'), matching: find.byType(HomeLibraryPhoto));
      for (final type in [Icon, Opacity, ColorFiltered, Text]) {
        expect(find.descendant(of: print, matching: find.byType(type)), findsNothing, reason: '$type');
      }
      expect(find.descendant(of: tile('IMG_01.jpg'), matching: find.byType(Stack)), findsNothing);
    });

    photoTest('the shown-count note says how many featured photos wide screens and phones show', (tester) async {
      await pumpPage(tester);

      expect(find.text('Wide screens and phones show both photos below the introduction.'), findsOneWidget);
    });

    test('the shown-count note for every number of photos', () {
      expect([for (var n = 0; n <= 7; n++) homePhotosShownNote(n)], [
        'With no photos, the home page shows the logo on a plain band.',
        'Just the full-screen photo. Add more to show photos below the introduction.',
        'One photo below the introduction is left out: it takes two to fill a row. Add another to show them.',
        'Wide screens and phones show both photos below the introduction.',
        'Photos below the introduction fill whole rows, so wide screens show all 3 and phones show the first 2 '
            'of 3.',
        'Photos below the introduction fill whole rows, so wide screens show the first 3 of 4 and phones show '
            'all 4.',
        'Photos below the introduction fill whole rows, so wide screens show the first 3 of 5 and phones show '
            'the first 4 of 5.',
        'Wide screens and phones show all 6 photos below the introduction.',
      ]);
    });

    photoTest('a load error says so, and "Try again" loads again', (tester) async {
      admin.errors['listHomeLibrary'] = adminError(AdminErrorKind.offline);
      await pumpPage(tester);

      expect(find.text('We couldn’t load the home page photos. Check your connection and try again.'),
          findsOneWidget);
      expect(find.byType(HomePhotoLibrary), findsNothing);
      expect(find.byType(FilledButton), findsNothing);

      admin.errors.clear();
      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Try again'));

      expect(chosen(tester), ['IMG_03.jpg', 'IMG_01.jpg', 'IMG_05.jpg']);
      expect(find.textContaining('We couldn’t load'), findsNothing);
    });

    photoTest('an error reading the chosen names is a load error too', (tester) async {
      admin.errors['homePhotoNames'] = adminError(AdminErrorKind.denied);
      await pumpPage(tester);

      expect(find.textContaining('We couldn’t load the home page photos.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    photoTest('chosen photos the library no longer has are left out, and named', (tester) async {
      admin.homeNames = ['gone.jpg', 'IMG_02.jpg', 'IMG_02.jpg'];
      await pumpPage(tester);

      expect(chosen(tester), ['IMG_02.jpg']);
      expect(find.text('gone.jpg was chosen but isn’t in the library any more, so the site leaves it out.'),
          findsOneWidget);
      expect(LeaveWarning.active.value, isFalse);
    });
  });

  group('never chosen (no site/home yet)', () {
    photoTest('preselects the first 7 photos by name and says the site shows them now', (tester) async {
      admin
        ..homeNames = null
        ..library.addAll(['.DS_Store', 'A_raw.HEIC']);
      await pumpPage(tester);

      expect(chosen(tester), _photos(7));
      expect(
        find.text('No photos have been chosen yet, so the site shows the first 7 photos in the library, in '
            'file-name order. Save to keep them, or change them first.'),
        findsOneWidget,
      );
      // That's what the site shows already: nothing to lose.
      expect(discard(), findsNothing);
      expect(LeaveWarning.active.value, isFalse);
      // And uploading changes it.
      expect(find.text(kHomeUploadsGoLiveNote), findsOneWidget);

      await tapAndSettle(tester, save());

      expect(admin.calls.last, 'saveHomePhotos(${_photos(7).join(', ')})');
      expect(find.textContaining('No photos have been chosen yet'), findsNothing);
      expect(find.text(kHomeUploadsGoLiveNote), findsNothing);
      expect(find.text('Saved. The home page shows these photos now.'), findsOneWidget);
    });

    photoTest('a new photo that sorts first joins them, as it would on the site', (tester) async {
      admin
        ..homeNames = null
        ..autoCompleteUploads = true;
      picker.next = [testPhoto('IMG_00.jpg')];
      await pumpPage(tester);

      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));

      expect(chosen(tester), ['IMG_00.jpg', ..._photos(6)]);
      expect(LeaveWarning.active.value, isFalse);
    });

    photoTest('an upload that changes the site’s photos has the home page look again, once the uploads stop',
        (tester) async {
      admin.homeNames = null;
      picker.next = [testPhoto('IMG_00.jpg'), testPhoto('IMG_99.jpg')];
      await pumpPage(tester);
      final loads = portfolio.loads;
      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));

      admin.uploads.first.complete();
      await tester.pumpAndSettle();
      expect(portfolio.loads, loads, reason: 'still uploading');
      admin.uploads.last.complete();
      await tester.pumpAndSettle();

      expect(portfolio.loads, loads + 1);
    });

    photoTest('leaving with uploads still running, the home page looks again for the ones that landed',
        (tester) async {
      admin.homeNames = null;
      picker.next = [testPhoto('IMG_00.jpg'), testPhoto('IMG_99.jpg')];
      await pumpPage(tester);
      final loads = portfolio.loads;
      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));
      admin.uploads.first.complete();
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.byTooltip('Back'));
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Stop and leave'));

      expect(find.byType(HomePhotosAdminPage), findsNothing);
      expect(portfolio.loads, loads + 1);
    });

    photoTest('an upload that sorts after the site’s photos leaves the home page alone', (tester) async {
      admin
        ..homeNames = null
        ..autoCompleteUploads = true;
      picker.next = [testPhoto('IMG_99.jpg')];
      await pumpPage(tester);
      final loads = portfolio.loads;

      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));

      expect(chosen(tester), _photos(7));
      expect(portfolio.loads, loads);
    });

    photoTest('a photo that lands during the first save leaves what’s being saved alone', (tester) async {
      admin
        ..homeNames = null
        ..writeDelay = const Duration(seconds: 1);
      picker.next = [testPhoto('IMG_00.jpg')];
      await pumpPage(tester);
      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));

      await reveal(tester, save());
      await tester.tap(save());
      await tester.pump();
      admin.uploads.single.complete();
      await tester.pump();
      expect(chosen(tester), _photos(7));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(admin.homeNames, _photos(7));
      expect(chosen(tester), _photos(7));
      expect(discard(), findsNothing);
      expect(find.text('Saved. The home page shows these photos now.'), findsOneWidget);
      expect(LeaveWarning.active.value, isFalse);
    });

    photoTest('with changes, a new photo still moves what the site shows, so discarding goes back to it',
        (tester) async {
      admin
        ..homeNames = null
        ..autoCompleteUploads = true;
      picker.next = [testPhoto('IMG_00.jpg')];
      await pumpPage(tester);
      await tapAndSettle(tester, rowButton('IMG_07.jpg', Icons.close));

      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));

      // The admin's choice stays as she left it.
      expect(chosen(tester), _photos(6));
      await tapAndSettle(tester, discard());
      expect(chosen(tester), ['IMG_00.jpg', ..._photos(6)]);
      expect(LeaveWarning.active.value, isFalse);
    });
  });

  group('choosing', () {
    photoTest('"On the home page" adds a photo at the end, and takes it off again', (tester) async {
      await pumpPage(tester);

      await tapAndSettle(tester, check('IMG_08.jpg'));

      expect(chosen(tester), ['IMG_03.jpg', 'IMG_01.jpg', 'IMG_05.jpg', 'IMG_08.jpg']);
      expect(isChecked(tester, 'IMG_08.jpg'), isTrue);
      expect(find.text('4 of 7'), findsOneWidget);
      expect(find.text(homePhotosShownNote(4)), findsOneWidget);
      expect(discard(), findsOneWidget);
      expect(LeaveWarning.active.value, isTrue);

      await tapAndSettle(tester, check('IMG_08.jpg'));

      expect(chosen(tester), ['IMG_03.jpg', 'IMG_01.jpg', 'IMG_05.jpg']);
      expect(isChecked(tester, 'IMG_08.jpg'), isFalse);
      // Back as saved: nothing to lose.
      expect(discard(), findsNothing);
      expect(LeaveWarning.active.value, isFalse);
    });

    photoTest('at most 7: the rest can’t be added until one is removed, and the page says why', (tester) async {
      admin.homeNames = _photos(7);
      await pumpPage(tester);

      expect(find.text('The home page has 7 photos, the most it shows. Remove one to add another.'), findsOneWidget);
      await reveal(tester, check('IMG_08.jpg'));
      expect(isEnabled(tester, check('IMG_08.jpg')), isFalse);
      // The ones on it can still come off.
      expect(isEnabled(tester, check('IMG_01.jpg')), isTrue);

      await tapAndSettle(tester, rowButton('IMG_02.jpg', Icons.close));

      expect(isEnabled(tester, check('IMG_08.jpg')), isTrue);
      expect(find.textContaining('the most it shows'), findsNothing);
    });

    photoTest('Move up, Move down and Remove reorder the rows', (tester) async {
      await pumpPage(tester);

      await tapAndSettle(tester, rowButton('IMG_05.jpg', Icons.arrow_upward));
      expect(chosen(tester), ['IMG_03.jpg', 'IMG_05.jpg', 'IMG_01.jpg']);

      await tapAndSettle(tester, rowButton('IMG_03.jpg', Icons.arrow_downward));
      expect(chosen(tester), ['IMG_05.jpg', 'IMG_03.jpg', 'IMG_01.jpg']);
      // The new first photo is the full-screen one.
      expect(find.descendant(of: row('IMG_05.jpg'), matching: find.text(HomePhotoOrder.heroLabel)), findsOneWidget);

      await tapAndSettle(tester, rowButton('IMG_03.jpg', Icons.close));
      expect(chosen(tester), ['IMG_05.jpg', 'IMG_01.jpg']);
      expect(isChecked(tester, 'IMG_03.jpg'), isFalse);

      // The first can't go up, nor the last down.
      expect(iconEnabled(tester, rowButton('IMG_05.jpg', Icons.arrow_upward)), isFalse);
      expect(iconEnabled(tester, rowButton('IMG_01.jpg', Icons.arrow_downward)), isFalse);
    });

    photoTest('removing every photo leaves an empty state, and the note says what the site shows', (tester) async {
      admin.homeNames = ['IMG_01.jpg'];
      await pumpPage(tester);
      expect(find.text(homePhotosShownNote(1)), findsOneWidget);

      await tapAndSettle(tester, rowButton('IMG_01.jpg', Icons.close));

      expect(find.byType(HomePhotoOrder), findsNothing);
      expect(find.text('No photos on the home page. Choose some from the library below.'), findsOneWidget);
      expect(find.text('With no photos, the home page shows the logo on a plain band.'), findsOneWidget);
    });

    photoTest('"Discard changes" goes back to the saved photos', (tester) async {
      await pumpPage(tester);
      await tapAndSettle(tester, rowButton('IMG_05.jpg', Icons.close));
      await tapAndSettle(tester, check('IMG_09.jpg'));
      expect(LeaveWarning.active.value, isTrue);

      await tapAndSettle(tester, discard());

      expect(chosen(tester), ['IMG_03.jpg', 'IMG_01.jpg', 'IMG_05.jpg']);
      expect(discard(), findsNothing);
      expect(LeaveWarning.active.value, isFalse);
      expect(admin.calls, isNot(contains(startsWith('saveHomePhotos'))));
    });
  });

  group('keyboard', () {
    photoTest('focus stays on the button that moved a row, in its new place', (tester) async {
      await pumpPage(tester);
      final down = rowButton('IMG_03.jpg', Icons.arrow_downward);
      final node = focusOf(tester, down);

      await pressWithKeyboard(tester, down);

      expect(chosen(tester), ['IMG_01.jpg', 'IMG_03.jpg', 'IMG_05.jpg']);
      expect(node.hasPrimaryFocus, isTrue);
      expect(focusOf(tester, rowButton('IMG_03.jpg', Icons.arrow_downward)), same(node));

      // Again: it can go no further, so focus moves to its "Move up".
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(chosen(tester), ['IMG_01.jpg', 'IMG_05.jpg', 'IMG_03.jpg']);
      expect(focusOf(tester, rowButton('IMG_03.jpg', Icons.arrow_upward)).hasPrimaryFocus, isTrue);
    });

    photoTest('moved to the top, focus goes to "Move down"', (tester) async {
      await pumpPage(tester);

      await pressWithKeyboard(tester, rowButton('IMG_01.jpg', Icons.arrow_upward));

      expect(chosen(tester), ['IMG_01.jpg', 'IMG_03.jpg', 'IMG_05.jpg']);
      expect(focusOf(tester, rowButton('IMG_01.jpg', Icons.arrow_downward)).hasPrimaryFocus, isTrue);
    });

    photoTest('with two rows, focus still goes to the other button at the top and the bottom', (tester) async {
      admin.homeNames = ['IMG_01.jpg', 'IMG_02.jpg'];
      await pumpPage(tester);

      await pressWithKeyboard(tester, rowButton('IMG_02.jpg', Icons.arrow_upward));
      expect(chosen(tester), ['IMG_02.jpg', 'IMG_01.jpg']);
      expect(focusOf(tester, rowButton('IMG_02.jpg', Icons.arrow_downward)).hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(chosen(tester), ['IMG_01.jpg', 'IMG_02.jpg']);
      expect(focusOf(tester, rowButton('IMG_02.jpg', Icons.arrow_upward)).hasPrimaryFocus, isTrue);
    });

    photoTest('removing a row hands focus to the row that takes its place, then to Save', (tester) async {
      admin.homeNames = ['IMG_01.jpg', 'IMG_02.jpg'];
      await pumpPage(tester);

      await pressWithKeyboard(tester, rowButton('IMG_01.jpg', Icons.close));
      expect(chosen(tester), ['IMG_02.jpg']);
      expect(focusOf(tester, rowButton('IMG_02.jpg', Icons.close)).hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(chosen(tester), isEmpty);
      expect(Focus.of(tester.element(find.text('Save home page'))).hasPrimaryFocus, isTrue);
    });

    photoTest('every control names its photo, for screen readers', (tester) async {
      admin.library.add('IMG_50.HEIC');
      await pumpPage(tester);

      expect(
        tester.getSemantics(rowButton('IMG_01.jpg', Icons.arrow_upward)),
        isSemantics(tooltip: 'Move IMG_01.jpg up'),
      );
      expect(
        tester.getSemantics(rowButton('IMG_01.jpg', Icons.arrow_downward)),
        isSemantics(tooltip: 'Move IMG_01.jpg down'),
      );
      expect(tester.getSemantics(rowButton('IMG_01.jpg', Icons.close)), isSemantics(tooltip: 'Remove IMG_01.jpg'));
      expect(tester.getSemantics(deleteButton(tile('IMG_02.jpg'))), isSemantics(tooltip: 'Delete IMG_02.jpg'));
      expect(
        tester.getSemantics(deleteButton(tile('IMG_01.jpg'))),
        isSemantics(tooltip: 'Can’t delete IMG_01.jpg: remove it from the home page first'),
      );
      expect(
        tester.getSemantics(check('IMG_02.jpg')),
        isSemantics(label: 'IMG_02.jpg on the home page', hasCheckedState: true, isChecked: false),
      );
      final heic = find.ancestor(of: find.text('IMG_50.HEIC'), matching: find.byKey(const ValueKey('IMG_50.HEIC')));
      await reveal(tester, heic);
      expect(tester.getSemantics(deleteButton(heic)), isSemantics(tooltip: 'Delete IMG_50.HEIC'));
    });

    photoTest('a move says where the photo went', (tester) async {
      await pumpPage(tester);
      tester.takeAnnouncements();

      await pressWithKeyboard(tester, rowButton('IMG_05.jpg', Icons.arrow_upward));
      await pressWithKeyboard(tester, rowButton('IMG_05.jpg', Icons.arrow_upward));
      await pressWithKeyboard(tester, rowButton('IMG_05.jpg', Icons.arrow_downward));

      expect([for (final announcement in tester.takeAnnouncements()) announcement.message], [
        'IMG_05.jpg is now photo 2 of 3',
        'IMG_05.jpg is now photo 1 of 3, the full-screen photo',
        'IMG_05.jpg is now photo 2 of 3',
      ]);
    });

    photoTest('"Discard changes" hands focus to Save as it goes', (tester) async {
      await pumpPage(tester);
      await tapAndSettle(tester, check('IMG_09.jpg'));

      await reveal(tester, discard());
      Focus.of(tester.element(find.text('Discard changes'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(discard(), findsNothing);
      expect(Focus.of(tester.element(find.text('Save home page'))).hasPrimaryFocus, isTrue);
    });

    photoTest('deleting a photo hands focus to the one that takes its place', (tester) async {
      await pumpPage(tester);
      final delete = deleteButton(tile('IMG_07.jpg'));

      await pressWithKeyboard(tester, delete);
      // The confirmation's focus starts on neither button.
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete photo'));

      expect(tile('IMG_07.jpg'), findsNothing);
      expect(focusOf(tester, deleteButton(tile('IMG_08.jpg'))).hasPrimaryFocus, isTrue);
    });
  });

  group('saving', () {
    photoTest('"Save home page" saves the order, says so, and reloads the home page', (tester) async {
      await pumpPage(tester);
      final loads = portfolio.loads;
      await tapAndSettle(tester, rowButton('IMG_05.jpg', Icons.arrow_upward));
      expect(LeaveWarning.active.value, isTrue);

      await tapAndSettle(tester, save());

      expect(admin.calls.last, 'saveHomePhotos(IMG_03.jpg, IMG_05.jpg, IMG_01.jpg)');
      expect(admin.homeNames, ['IMG_03.jpg', 'IMG_05.jpg', 'IMG_01.jpg']);
      const message = 'Saved. The home page shows these photos now.';
      expect(tester.widget<InlineMessage>(find.widgetWithText(InlineMessage, message)).tone, StatusTone.success);
      expect(portfolio.loads, loads + 1);
      expect(discard(), findsNothing);
      expect(LeaveWarning.active.value, isFalse);

      // A change after saving: the message no longer describes them.
      await tapAndSettle(tester, check('IMG_09.jpg'));
      expect(find.text('Saved. The home page shows these photos now.'), findsNothing);
    });

    photoTest('while saving, the button says so and keeps focus; a second press waits', (tester) async {
      admin.writeDelay = const Duration(seconds: 1);
      await pumpPage(tester);
      await reveal(tester, save());
      Focus.of(tester.element(find.text('Save home page'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(Focus.of(tester.element(find.text('Saving…'))).hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(admin.calls.where((call) => call.startsWith('saveHomePhotos')), hasLength(1));
      expect(find.text('Save home page'), findsOneWidget);
      expect(find.text('Saved. The home page shows these photos now.'), findsOneWidget);
    });

    photoTest('a save error says what happened; the changes stay, and saving again works', (tester) async {
      await pumpPage(tester);
      await tapAndSettle(tester, check('IMG_09.jpg'));
      admin.nextError = adminError(AdminErrorKind.denied);

      await tapAndSettle(tester, save());

      expect(find.text(kAdminDeniedMessage), findsOneWidget);
      expect(find.text('Saved. The home page shows these photos now.'), findsNothing);
      expect(chosen(tester).last, 'IMG_09.jpg');
      expect(LeaveWarning.active.value, isTrue);

      await tapAndSettle(tester, save());

      expect(find.text(kAdminDeniedMessage), findsNothing);
      expect(admin.homeNames, ['IMG_03.jpg', 'IMG_01.jpg', 'IMG_05.jpg', 'IMG_09.jpg']);
      expect(LeaveWarning.active.value, isFalse);
    });

    photoTest('an unexpected error gets a message of its own', (tester) async {
      await pumpPage(tester);
      admin.nextError = StateError('boom');

      await tapAndSettle(tester, save());

      expect(find.text('We couldn’t save the home page photos. Check your connection and try again.'),
          findsOneWidget);
    });
  });

  group('deleting', () {
    photoTest('asks first, deletes, and reloads the home page', (tester) async {
      await pumpPage(tester);
      final loads = portfolio.loads;

      await tapAndSettle(tester, deleteButton(tile('IMG_07.jpg')));
      expect(find.text('Delete this photo?'), findsOneWidget);
      expect(find.text('IMG_07.jpg will be deleted from the library. This can’t be undone.'), findsOneWidget);

      await tapAndSettle(tester, find.text('Cancel'));
      expect(admin.calls, isNot(contains(startsWith('deletePhoto'))));

      await tapAndSettle(tester, deleteButton(tile('IMG_07.jpg')));
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete photo'));

      expect(admin.calls.last, 'deletePhoto(_admin/gallery/IMG_07.jpg)');
      expect(tile('IMG_07.jpg'), findsNothing);
      expect(find.text('9 photos'), findsOneWidget);
      expect(portfolio.loads, loads + 1);
    });

    photoTest('photos on the home page, saved or not, can’t be deleted, and the page says why', (tester) async {
      await pumpPage(tester);
      expect(find.text('Photos on the home page can’t be deleted. Remove them from the home page first.'),
          findsOneWidget);
      // Saved, then taken off but not saved: still on the site.
      await tapAndSettle(tester, rowButton('IMG_05.jpg', Icons.close));
      // Not saved yet.
      await tapAndSettle(tester, check('IMG_08.jpg'));

      for (final name in ['IMG_01.jpg', 'IMG_08.jpg']) {
        await reveal(tester, tile(name));
        final delete = tester.widget<IconButton>(deleteButton(tile(name)));
        expect(delete.onPressed, isNull, reason: name);
        expect(delete.tooltip, 'Can’t delete $name: remove it from the home page first', reason: name);
      }
      // Already taken off: saving is what's left.
      final removed = tester.widget<IconButton>(deleteButton(tile('IMG_05.jpg')));
      expect(removed.onPressed, isNull);
      expect(removed.tooltip, 'Can’t delete IMG_05.jpg: the site shows it until you save the home page');
      expect(iconEnabled(tester, deleteButton(tile('IMG_02.jpg'))), isTrue);
      expect(
        find.text('Photos on the home page can’t be deleted. Remove them from the home page and save first: until '
            'you save, the site still shows the ones you removed.'),
        findsOneWidget,
      );

      await tapAndSettle(tester, save());

      expect(iconEnabled(tester, deleteButton(tile('IMG_05.jpg'))), isTrue);
      expect(find.text('Photos on the home page can’t be deleted. Remove them from the home page first.'),
          findsOneWidget);
    });

    photoTest('a delete error says what happened, and the photo stays', (tester) async {
      await pumpPage(tester);
      admin.nextError = adminError(AdminErrorKind.offline);

      await tapAndSettle(tester, deleteButton(tile('IMG_07.jpg')));
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete photo'));

      expect(find.text(kAdminOfflineMessage), findsOneWidget);
      expect(tile('IMG_07.jpg'), findsOneWidget);
    });

    photoTest('files the site can’t show are listed with why, and can be deleted', (tester) async {
      admin.library.addAll(['IMG_50.HEIC', '.DS_Store', 'notes']);
      await pumpPage(tester);

      await reveal(tester, find.byType(HomeLibraryOtherFiles));
      expect(find.text('Can’t be shown on the site (HEIC)'), findsOneWidget);
      expect(find.text('Can’t be shown on the site (hidden file)'), findsOneWidget);
      expect(find.text('Can’t be shown on the site'), findsOneWidget);
      // Not in the grid, and never preselected.
      expect(tile('IMG_50.HEIC'), findsNothing);

      final heic = find.ancestor(of: find.text('IMG_50.HEIC'), matching: find.byKey(const ValueKey('IMG_50.HEIC')));
      await tapAndSettle(tester, deleteButton(heic));
      expect(find.text('Delete this file?'), findsOneWidget);
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete file'));

      expect(admin.calls.last, 'deletePhoto(_admin/gallery/IMG_50.HEIC)');
      expect(find.text('IMG_50.HEIC'), findsNothing);
    });

    test('why a file can’t be shown, by its extension', () {
      expect(HomeLibraryOtherFiles.reason('IMG_1.heic'), 'Can’t be shown on the site (HEIC)');
      expect(HomeLibraryOtherFiles.reason('a.tar.gz'), 'Can’t be shown on the site (GZ)');
      expect(HomeLibraryOtherFiles.reason('.DS_Store'), 'Can’t be shown on the site (hidden file)');
      expect(HomeLibraryOtherFiles.reason('README'), 'Can’t be shown on the site');
      expect(HomeLibraryOtherFiles.reason('odd.'), 'Can’t be shown on the site');
    });
  });

  group('uploading', () {
    photoTest('the library says it’s public, near the upload button', (tester) async {
      await pumpPage(tester);

      expect(
        find.text('Anyone can see every photo in the library, even the ones that aren’t on the home page. '
            'Don’t upload clients’ photos without their permission.'),
        findsOneWidget,
      );
      expect(find.text('JPEG, PNG or WebP, each under 20 MB.'), findsOneWidget);
      // Photos are chosen, so new ones wait to be.
      expect(find.text(kHomeUploadsGoLiveNote), findsNothing);
    });

    photoTest('picks JPEG, PNG or WebP; checks each; skips names already here; adds new ones to the library',
        (tester) async {
      picker.next = [
        testPhoto('IMG_99.jpg'),
        testPhoto('IMG_01.jpg'),
        testPhoto('raw.HEIC', contentType: 'image/heic'),
      ];
      await pumpPage(tester);
      final listings = admin.calls.where((call) => call == 'listHomeLibrary()').length;

      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));

      expect(picker.accepts, [PhotoRules.homeAccept]);
      expect(admin.calls.where((call) => call.startsWith('uploadToHomeLibrary')), [
        'uploadToHomeLibrary(_admin/gallery/IMG_99.jpg)',
      ]);
      expect(uploadSummary(_queueOf(tester)), 'Uploading 0 of 2 · 1 failed · 1 skipped');
      expect(LeaveWarning.active.value, isTrue);

      admin.uploads.single.complete();
      await tester.pumpAndSettle();

      expect(tile('IMG_99.jpg'), findsOneWidget);
      expect(find.text('11 photos'), findsOneWidget);
      expect(LeaveWarning.active.value, isFalse);
      // One listing for the batch, for the new photo's link.
      expect(admin.calls.where((call) => call == 'listHomeLibrary()'), hasLength(listings + 1));
      final photo = find.descendant(of: tile('IMG_99.jpg'), matching: find.byType(NetworkPhoto));
      await reveal(tester, photo);
      expect(tester.widget<NetworkPhoto>(photo).url, Uri.parse('https://storage.example.com/IMG_99.jpg'));
      // And it can go on the home page.
      await tapAndSettle(tester, check('IMG_99.jpg'));
      expect(chosen(tester).last, 'IMG_99.jpg');
    });

    photoTest('a chosen photo uploaded again after it was deleted is back on the home page', (tester) async {
      admin
        ..homeNames = ['IMG_03.jpg', 'gone.jpg', 'IMG_01.jpg']
        ..autoCompleteUploads = true;
      picker.next = [testPhoto('gone.jpg')];
      await pumpPage(tester);
      final loads = portfolio.loads;
      expect(chosen(tester), ['IMG_03.jpg', 'IMG_01.jpg']);

      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));

      // As the site shows it again: in its place, and not to be deleted.
      expect(chosen(tester), ['IMG_03.jpg', 'gone.jpg', 'IMG_01.jpg']);
      expect(find.textContaining('isn’t in the library any more'), findsNothing);
      expect(discard(), findsNothing);
      expect(iconEnabled(tester, deleteButton(tile('gone.jpg'))), isFalse);
      expect(portfolio.loads, loads + 1);
    });

    photoTest('a name passed on twice joins the library once', (tester) async {
      picker.next = [testPhoto('IMG_99.jpg')];
      await pumpPage(tester);
      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));
      admin.uploads.single.complete();
      await tester.pumpAndSettle();

      // As the queue does for a name it finds already stored.
      final queue = _queueOf(tester);
      queue.onUploaded!(queue.items.single);
      await tester.pumpAndSettle();

      expect(tile('IMG_99.jpg'), findsOneWidget);
      expect(find.text('11 photos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    photoTest('a cancelled picker changes nothing, and the page never waits on it', (tester) async {
      picker.neverAnswers = true;
      await pumpPage(tester);

      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));

      expect(_queueOf(tester).items, isEmpty);
      expect(LeaveWarning.active.value, isFalse);
      // Still usable.
      await tapAndSettle(tester, check('IMG_09.jpg'));
      expect(chosen(tester).last, 'IMG_09.jpg');
    });

    photoTest('without a link from the listing, a new photo shows its placeholder', (tester) async {
      picker.next = [testPhoto('IMG_99.jpg')];
      await pumpPage(tester);
      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));
      admin.errors['listHomeLibrary'] = adminError(AdminErrorKind.offline);

      admin.uploads.single.complete();
      await tester.pumpAndSettle();

      expect(tile('IMG_99.jpg'), findsOneWidget);
      expect(find.descendant(of: tile('IMG_99.jpg'), matching: find.byType(NetworkPhoto)), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('leaving', () {
    Finder back() => find.byTooltip('Back');

    photoTest('with unsaved changes: "Leave without saving?"', (tester) async {
      await pumpPage(tester);
      await tapAndSettle(tester, check('IMG_09.jpg'));

      await tapAndSettle(tester, back());
      expect(find.text('Leave without saving?'), findsOneWidget);
      await tapAndSettle(tester, find.text('Keep editing'));
      expect(find.byType(HomePhotosAdminPage), findsOneWidget);
      expect(LeaveWarning.active.value, isTrue);

      await tapAndSettle(tester, back());
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Leave without saving'));

      expect(find.byType(HomePhotosAdminPage), findsNothing);
      expect(admin.calls, isNot(contains(startsWith('saveHomePhotos'))));
      expect(LeaveWarning.active.value, isFalse);
    });

    photoTest('while saving: "Leave while saving?", and leaving still saves', (tester) async {
      admin.writeDelay = const Duration(seconds: 1);
      await pumpPage(tester);
      final loads = portfolio.loads;
      await tapAndSettle(tester, check('IMG_09.jpg'));
      await reveal(tester, save());
      await tester.tap(save());
      await tester.pump();

      await tapAndSettle(tester, back());
      expect(find.text('Leave while saving?'), findsOneWidget);
      expect(
        find.text('Your changes are still saving. If you leave now, they’ll still be saved, but you won’t see it if '
            'saving fails.'),
        findsOneWidget,
      );
      expect(find.textContaining('will be lost'), findsNothing);
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Leave'));
      expect(find.byType(HomePhotosAdminPage), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(admin.homeNames, ['IMG_03.jpg', 'IMG_01.jpg', 'IMG_05.jpg', 'IMG_09.jpg']);
      expect(portfolio.loads, loads + 1);
    });

    photoTest('with uploads running: "Stop uploading?", and leaving stops them', (tester) async {
      picker.next = [testPhoto('IMG_99.jpg')];
      await pumpPage(tester);
      await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));

      await tapAndSettle(tester, back());
      expect(find.text('Stop uploading?'), findsOneWidget);
      expect(
        find.text('Photos still uploading will stop. The ones already uploaded stay in the library.'),
        findsOneWidget,
      );
      await tapAndSettle(tester, find.text('Keep uploading'));
      expect(admin.uploads.single.cancelled, isFalse);

      await tapAndSettle(tester, back());
      await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Stop and leave'));

      expect(find.byType(HomePhotosAdminPage), findsNothing);
      expect(admin.uploads.single.cancelled, isTrue);
      expect(LeaveWarning.active.value, isFalse);
    });

    photoTest('the account menu has no "Your sessions", whose pages could leave without asking', (tester) async {
      await pumpPage(tester);

      await tapAndSettle(tester, find.byType(CircleAvatar));

      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Your sessions'), findsNothing);
      expect(find.text('Admin'), findsNothing);
    });

    photoTest('with nothing to lose, back just goes back', (tester) async {
      await pumpPage(tester);

      await tapAndSettle(tester, back());

      expect(find.byType(HomePhotosAdminPage), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    photoTest('the warning is cleared when the page goes, however it goes', (tester) async {
      await pumpPage(tester);
      await tapAndSettle(tester, check('IMG_09.jpg'));
      expect(LeaveWarning.active.value, isTrue);

      // Signing out, say: the gate takes the page's place.
      await tester.pumpWidget(const SizedBox());

      expect(LeaveWarning.active.value, isFalse);
    });
  });

  group('layout', () {
    for (final brightness in Brightness.values) {
      for (final width in [320.0, 390.0, 1440.0]) {
        for (final textScale in [1.0, 2.0]) {
          photoTest(
              'fits ${width.toInt()}px in ${brightness.name} at text ×$textScale, with one primary button, '
              'all the way down', (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = textScale;
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
            admin
              ..homeNames = _photos(7)
              ..library.addAll(['a-very-long-file-name-from-a-camera-roll-export.jpg', 'IMG_50.HEIC']);
            picker.next = [testPhoto('IMG_99.jpg'), testPhoto('raw.HEIC', contentType: 'image/heic')];
            await pumpPage(tester, size: Size(width, 800), brightness: brightness);
            await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Upload photos'));
            await tapAndSettle(tester, rowButton('IMG_02.jpg', Icons.close));
            expect(tester.takeException(), isNull);
            expect(find.byType(FilledButton), findsOneWidget);

            for (var i = 0; i < 40; i++) {
              await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
              await tester.pump();
              expect(tester.takeException(), isNull);
            }
            expect(find.text('IMG_50.HEIC').hitTestable(), findsOneWidget);
          });
        }
      }
    }

    photoTest('the library takes more columns on wider screens, and fewer with larger text', (tester) async {
      /// How many photos share the first photo's row.
      int columns(WidgetTester tester) {
        double top(String name) =>
            tester.getTopLeft(find.descendant(of: tile(name), matching: find.byType(HomeLibraryPhoto))).dy;
        return [
          for (final name in _photos(10))
            if (tile(name).evaluate().isNotEmpty && top(name) == top('IMG_01.jpg')) name,
        ].length;
      }

      await pumpPage(tester, size: const Size(390, 844));
      await reveal(tester, tile('IMG_01.jpg'));
      expect(columns(tester), 2);

      await pumpPage(tester, size: const Size(1440, 900));
      await reveal(tester, tile('IMG_01.jpg'));
      expect(columns(tester), 5);

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await reveal(tester, tile('IMG_01.jpg'));
      expect(columns(tester), 3);
    });
  });
}

/// The upload queue behind the page's progress list.
UploadQueue _queueOf(WidgetTester tester) =>
    tester.widget<UploadProgressList>(find.byType(UploadProgressList)).queue;
