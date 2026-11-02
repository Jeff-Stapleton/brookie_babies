import 'dart:convert';

import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/network_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_photos.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  testWidgets(
      'loads the preview before the original and crossfades between them',
      (tester) async {
    final server = FakePhotoServer()..start();
    final preview =
        Uri.parse('https://storage.example/.previews/photo.webp?sig=preview');
    final original = Uri.parse('https://storage.example/photo.jpg?sig=full');
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: brookieTheme(Brightness.light),
          home: SizedBox(
            width: 320,
            height: 240,
            child: NetworkPhoto(url: original, previewUrl: preview),
          ),
        ),
      );
      await tester.pump();

      expect(server.requested, [preview]);

      server.serve(preview, _png);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(server.requested, [preview, original]);
      var fades = tester
          .widgetList<AnimatedOpacity>(
            find.descendant(
              of: find.byType(NetworkPhoto),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .toList();
      expect(fades.map((fade) => fade.opacity), [1, 0]);

      server.serve(original, _png);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.pumpAndSettle();

      fades = tester
          .widgetList<AnimatedOpacity>(
            find.descendant(
              of: find.byType(NetworkPhoto),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .toList();
      expect(fades.map((fade) => fade.opacity), [0, 1]);
    } finally {
      server.stop();
    }
  });
}
