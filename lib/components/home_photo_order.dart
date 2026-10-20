import 'dart:math' as math;

import 'package:brookie_babies/components/home_photo_library.dart';
import 'package:brookie_babies/models/stored_photo.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// The home page photos in their order, one row each: a thumbnail, where
/// the photo goes on the home page, its name, and "Move up", "Move down"
/// and "Remove".
///
/// Moving a photo with the keyboard keeps focus on the button that moved
/// it, in its new place (at the top or bottom, where that way is closed,
/// on the button for the other way). Removing one hands focus to the row
/// that takes its place. No dragging: the buttons work the same for
/// everyone. Shows nothing for no photos.
class HomePhotoOrder extends StatefulWidget {
  const HomePhotoOrder({super.key, required this.photos, required this.onChanged, this.focusWhenEmptied});

  /// The home page photos, in order: the first is the hero.
  final List<StoredPhoto> photos;

  /// Called with the names in their new order after a move or a removal.
  final ValueChanged<List<String>> onChanged;

  /// Takes focus when the last photo is removed with the keyboard focused
  /// on its row.
  final FocusNode? focusWhenEmptied;

  /// Where the first photo goes, and what to mind when choosing it.
  static const heroLabel = 'Full-screen photo, behind the logo: keep faces clear of the middle';

  /// Where the rest go.
  static const featuredLabel = 'Below the introduction';

  @override
  State<HomePhotoOrder> createState() => _HomePhotoOrderState();
}

/// One row's buttons.
class _RowFocus {
  _RowFocus(String name)
      : up = FocusNode(debugLabel: 'Move $name up'),
        down = FocusNode(debugLabel: 'Move $name down'),
        remove = FocusNode(debugLabel: 'Remove $name');

  final FocusNode up;
  final FocusNode down;
  final FocusNode remove;

  bool get hasFocus => up.hasFocus || down.hasFocus || remove.hasFocus;

  void dispose() {
    up.dispose();
    down.dispose();
    remove.dispose();
  }
}

class _HomePhotoOrderState extends State<HomePhotoOrder> {
  /// Each row's focus nodes by photo name, so they move with the row.
  final _focus = <String, _RowFocus>{};

  _RowFocus _focusFor(String name) => _focus.putIfAbsent(name, () => _RowFocus(name));

  List<String> get _names => [for (final photo in widget.photos) photo.name];

  @override
  void didUpdateWidget(HomePhotoOrder oldWidget) {
    super.didUpdateWidget(oldWidget);
    final names = _names.toSet();
    for (final name in [..._focus.keys]) {
      if (names.contains(name)) continue;
      final gone = _focus.remove(name)!;
      // The removed row's buttons hold them until this frame is built.
      WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
    }
  }

  @override
  void dispose() {
    for (final focus in _focus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  void _move(int index, int by) {
    final names = _names;
    final name = names.removeAt(index);
    final to = index + by;
    names.insert(to, name);
    // At the top "Move up" is disabled (at the bottom, "Move down"), which
    // would drop focus: it goes to the other one first.
    final focus = _focusFor(name);
    if (focus.up.hasFocus && to == 0) focus.down.requestFocus();
    if (focus.down.hasFocus && to == names.length - 1) focus.up.requestFocus();
    widget.onChanged(names);
    // Focus stays on the button, so nothing else says where the photo went.
    final hero = to == 0 ? ', the full-screen photo' : '';
    SemanticsService.sendAnnouncement(
      View.of(context),
      '$name is now photo ${to + 1} of ${names.length}$hero',
      Directionality.of(context),
    );
  }

  void _remove(int index) {
    final names = _names;
    final name = names.removeAt(index);
    // Focus would go with the row: it goes to the row taking its place, or
    // the one before it.
    if (_focusFor(name).hasFocus) {
      if (names.isEmpty) {
        widget.focusWhenEmptied?.requestFocus();
      } else {
        _focusFor(names[math.min(index, names.length - 1)]).remove.requestFocus();
      }
    }
    widget.onChanged(names);
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, photo) in photos.indexed) ...[
          if (i > 0) const SizedBox(height: BrookieSpace.s3),
          _OrderRow(
            // Keyed by name, so a moved row keeps its focus.
            key: ValueKey(photo.name),
            photo: photo,
            position: i + 1,
            focus: _focusFor(photo.name),
            onMoveUp: i > 0 ? () => _move(i, -1) : null,
            onMoveDown: i < photos.length - 1 ? () => _move(i, 1) : null,
            onRemove: () => _remove(i),
          ),
        ],
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    super.key,
    required this.photo,
    required this.position,
    required this.focus,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final StoredPhoto photo;

  /// 1 for the hero.
  final int position;

  final _RowFocus focus;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;

  static const _thumbnailWidth = 48.0;

  /// Below this width (at normal text size) the buttons go under the name.
  static const _sideBySideWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final sideBySideWidth = textScaler.scale(_sideBySideWidth);

    // One node: "2. IMG_2.jpg. Below the introduction".
    final about = MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The same width on every row, growing with the text, so the
          // thumbnails line up.
          SizedBox(
            width: textScaler.scale(BrookieSpace.s5),
            child: Text('$position', style: BrookieType.label.copyWith(color: c.inkSoft)),
          ),
          HomeLibraryPhoto(photo: photo, width: _thumbnailWidth),
          const SizedBox(width: BrookieSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(photo.name, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: BrookieSpace.s1),
                Text(
                  position == 1 ? HomePhotoOrder.heroLabel : HomePhotoOrder.featuredLabel,
                  style: BrookieType.small.copyWith(color: c.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Each names its photo: a screen reader lists them all together.
        IconButton(
          focusNode: focus.up,
          tooltip: 'Move ${photo.name} up',
          onPressed: onMoveUp,
          icon: const Icon(Icons.arrow_upward),
        ),
        const SizedBox(width: BrookieSpace.s1),
        IconButton(
          focusNode: focus.down,
          tooltip: 'Move ${photo.name} down',
          onPressed: onMoveDown,
          icon: const Icon(Icons.arrow_downward),
        ),
        const SizedBox(width: BrookieSpace.s1),
        IconButton(
          focusNode: focus.remove,
          tooltip: 'Remove ${photo.name}',
          onPressed: onRemove,
          icon: const Icon(Icons.close),
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(BrookieRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BrookieSpace.s3),
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= sideBySideWidth) {
            return Row(
              children: [
                Expanded(child: about),
                const SizedBox(width: BrookieSpace.s3),
                buttons,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [about, buttons],
          );
        }),
      ),
    );
  }
}
