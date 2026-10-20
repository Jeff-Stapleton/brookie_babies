// The browser's file picker, for AppServices.pickPhotos. Web only: only
// main.dart imports it, so tests (on the Dart VM) never do.

import 'dart:async';
import 'dart:js_interop';

import 'package:brookie_babies/models/picked_photo.dart';
import 'package:web/web.dart' as web;

/// Opens the file picker for photos matching [accept] and completes with
/// the chosen files, or none if the admin cancels. Matches PickPhotos.
///
/// Browsers only open a picker while handling a tap, so this clicks a new
/// hidden `<input type=file>` at once, before returning. Browsers without
/// the input's `cancel` event never complete it on a cancel.
Future<List<PickedPhoto>> pickPhotos({required String accept}) {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..accept = accept;
  input.style.display = 'none';
  // Attached, so Safari fires its events.
  web.document.body!.append(input);

  final picked = Completer<List<PickedPhoto>>();
  void finish(List<PickedPhoto> photos) {
    if (picked.isCompleted) return;
    input.remove();
    picked.complete(photos);
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      final files = input.files;
      finish([
        if (files != null)
          for (var i = 0; i < files.length; i++)
            if (files.item(i) case final file?)
              PickedPhoto(name: file.name, size: file.size, contentType: file.type, data: file),
      ]);
    }).toJS,
  );
  input.addEventListener('cancel', ((web.Event _) => finish(const [])).toJS);
  input.click();
  return picked.future;
}
