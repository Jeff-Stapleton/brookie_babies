import 'package:brookie_babies/models/stored_photo.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/network_photo.dart';
import 'package:flutter/material.dart';

/// Library photos are shown in the home page's own 4:5 crop.
const _aspectRatio = 4 / 5;

/// Photos decode in steps of this many physical pixels, as FeaturedPhotos'
/// do, so resizing the window only decodes them again now and then.
const _decodeStep = 128;

/// One photo from the home page library at [width] wide, cropped 4:5 and
/// decoded at about that size (not the camera's). Until it has a link (a
/// photo just uploaded), its placeholder.
///
/// A print: nothing is ever laid over it, so its state is said beside it.
class HomeLibraryPhoto extends StatelessWidget {
  const HomeLibraryPhoto({super.key, required this.photo, required this.width});

  final StoredPhoto photo;
  final double width;

  @override
  Widget build(BuildContext context) {
    final url = photo.url;
    final pixels = width * MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = ((pixels / _decodeStep).ceil() * _decodeStep).toDouble();
    return SizedBox(
      width: width,
      height: width / _aspectRatio,
      child: url == null
          ? ColoredBox(color: BrookieColors.of(context).surfaceSunk)
          : NetworkPhoto(
              // Keyed by link, so a photo's state never passes to another.
              key: ValueKey(url),
              url: url,
              decodeSize: Size(decodeWidth, decodeWidth / _aspectRatio),
            ),
    );
  }
}

/// Hands keyboard focus on from a file that is gone (deleted) to the one
/// now at its [index] in [names], or the one before it: to the first of
/// [nodesFor]'s nodes for it that [canFocus].
///
/// After the frame: the gone file's button only lets go of focus as the
/// frame finishes, and would take a request made sooner with it.
void _focusNear(
  State state,
  List<String> Function() names,
  int index,
  List<FocusNode> Function(String name) nodesFor,
  bool Function(String name, FocusNode node) canFocus,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted) return;
    final now = names();
    for (final i in [index, index - 1]) {
      if (i < 0 || i >= now.length) continue;
      for (final node in nodesFor(now[i])) {
        if (!canFocus(now[i], node)) continue;
        node.requestFocus();
        return;
      }
    }
  });
}

/// The home page library's photos as a grid of prints, built a row at a
/// time as they scroll into view: a library can hold hundreds. Under each,
/// its name, "Delete", and whether it's on the home page.
///
/// A sliver, for the admin page's scroll view. Each row of the grid is one
/// item rather than a SliverGrid's fixed-height tiles, so the captions can
/// grow with the text size without overflowing. Deleting a photo with the
/// keyboard hands focus to the photo that takes its place.
class HomePhotoLibrary extends StatefulWidget {
  const HomePhotoLibrary({
    super.key,
    required this.photos,
    required this.chosen,
    required this.canAdd,
    required this.locked,
    required this.deleting,
    required this.onToggle,
    required this.onDelete,
  });

  /// The photos the site can show (StoragePortfolioService.isPhoto), in
  /// order.
  final List<StoredPhoto> photos;

  /// The names chosen for the home page, saved or not.
  final Set<String> chosen;

  /// Whether another photo can be chosen (fewer than
  /// PhotoRules.homeMaxPhotos are).
  final bool canAdd;

  /// Names that can't be deleted: on the home page, saved or not.
  final Set<String> locked;

  /// Names being deleted.
  final Set<String> deleting;

  /// Puts the photo named on the home page, or takes it off.
  final ValueChanged<String> onToggle;

  final ValueChanged<StoredPhoto> onDelete;

  /// The narrowest a tile gets at normal text size: wide enough for "On the
  /// home page" on one line, and two columns on most phones.
  static const _minTileWidth = 150.0;

  /// Past this many columns the prints get too small to judge.
  static const _maxColumns = 5;

  static const _columnGap = BrookieSpace.s4;
  static const _rowGap = BrookieSpace.s5;

  @override
  State<HomePhotoLibrary> createState() => _HomePhotoLibraryState();
}

/// One tile's controls.
class _TileFocus {
  _TileFocus(String name)
      : toggle = FocusNode(debugLabel: '$name on the home page'),
        delete = FocusNode(debugLabel: 'Delete $name');

  final FocusNode toggle;
  final FocusNode delete;

  bool get hasFocus => toggle.hasFocus || delete.hasFocus;

  void dispose() {
    toggle.dispose();
    delete.dispose();
  }
}

class _HomePhotoLibraryState extends State<HomePhotoLibrary> {
  /// Each tile's focus nodes by photo name, so they stay with the photo as
  /// tiles move between rows.
  final _focus = <String, _TileFocus>{};

  _TileFocus _focusFor(String name) => _focus.putIfAbsent(name, () => _TileFocus(name));

  List<String> _names() => [for (final photo in widget.photos) photo.name];

  @override
  void didUpdateWidget(HomePhotoLibrary oldWidget) {
    super.didUpdateWidget(oldWidget);
    final names = _names().toSet();
    for (final (i, photo) in oldWidget.photos.indexed) {
      if (names.contains(photo.name)) continue;
      final gone = _focus.remove(photo.name);
      if (gone == null) continue;
      if (gone.hasFocus) {
        _focusNear(
          this,
          _names,
          i,
          (name) => [_focusFor(name).delete, _focusFor(name).toggle],
          (name, node) => node == _focusFor(name).delete
              ? !widget.locked.contains(name)
              : widget.chosen.contains(name) || widget.canAdd,
        );
      }
      // Its tile's buttons hold them until this frame is built.
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

  @override
  Widget build(BuildContext context) {
    // Wider tiles for larger text, so the captions still fit.
    final minTile = MediaQuery.textScalerOf(context).scale(HomePhotoLibrary._minTileWidth);
    const gap = HomePhotoLibrary._columnGap;
    return SliverLayoutBuilder(builder: (context, constraints) {
      final width = constraints.crossAxisExtent;
      final columns = ((width + gap) / (minTile + gap)).floor().clamp(1, HomePhotoLibrary._maxColumns);
      final tileWidth = (width - gap * (columns - 1)) / columns;
      final photos = widget.photos;
      return SliverList.builder(
        itemCount: (photos.length / columns).ceil(),
        itemBuilder: (context, row) {
          final start = row * columns;
          return Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : HomePhotoLibrary._rowGap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = start; i < start + columns; i++) ...[
                  if (i > start) const SizedBox(width: gap),
                  SizedBox(
                    width: tileWidth,
                    child: i < photos.length ? _tile(photos[i], tileWidth) : null,
                  ),
                ],
              ],
            ),
          );
        },
      );
    });
  }

  Widget _tile(StoredPhoto photo, double width) {
    final name = photo.name;
    final selected = widget.chosen.contains(name);
    final deleting = widget.deleting.contains(name);
    return _LibraryTile(
      key: ValueKey(name),
      photo: photo,
      width: width,
      focus: _focusFor(name),
      selected: selected,
      onToggle: !deleting && (selected || widget.canAdd) ? () => widget.onToggle(name) : null,
      locked: widget.locked.contains(name),
      deleting: deleting,
      onDelete: () => widget.onDelete(photo),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    super.key,
    required this.photo,
    required this.width,
    required this.focus,
    required this.selected,
    required this.onToggle,
    required this.locked,
    required this.deleting,
    required this.onDelete,
  });

  final StoredPhoto photo;
  final double width;
  final _TileFocus focus;
  final bool selected;

  /// Null while the home page is full and this photo isn't on it, or while
  /// it's being deleted.
  final VoidCallback? onToggle;

  final bool locked;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Laid on paper as a print, like the home page's.
        DecoratedBox(
          decoration: BoxDecoration(boxShadow: c.shadowPrint),
          child: HomeLibraryPhoto(photo: photo, width: width),
        ),
        const SizedBox(height: BrookieSpace.s1),
        Row(
          children: [
            Expanded(
              child: Text(
                photo.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrookieType.small.copyWith(color: c.inkSoft),
              ),
            ),
            _DeleteButton(
              focusNode: focus.delete,
              tooltip: 'Delete ${photo.name}',
              lockedReason: locked ? 'Can’t delete ${photo.name}: remove it from the home page first' : null,
              deleting: deleting,
              onDelete: onDelete,
            ),
          ],
        ),
        _OnHomePageCheck(name: photo.name, focusNode: focus.toggle, selected: selected, onToggle: onToggle),
      ],
    );
  }
}

/// "On the home page", checked or not: a checkbox in a caption-sized
/// button under the photo. Checked, it turns butter with the 1.5px ink edge
/// of every selected state; disabled, it's quiet.
class _OnHomePageCheck extends StatelessWidget {
  const _OnHomePageCheck({
    required this.name,
    required this.focusNode,
    required this.selected,
    required this.onToggle,
  });

  /// The photo's, for screen readers: every tile has one of these.
  final String name;

  final FocusNode focusNode;
  final bool selected;
  final VoidCallback? onToggle;

  static const _shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(BrookieRadius.sm)));

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final enabled = onToggle != null;
    final Color foreground;
    if (selected) {
      foreground = c.onButter;
    } else {
      foreground = enabled ? c.ink : c.inkSoft;
    }
    // One node: "IMG_1.jpg on the home page", checked or not.
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        child: OutlinedButton(
          focusNode: focusNode,
          onPressed: onToggle,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (selected) return c.butter;
              return states.contains(WidgetState.hovered) ? c.surfaceSunk : Colors.transparent;
            }),
            foregroundColor: WidgetStatePropertyAll(foreground),
            iconColor: WidgetStatePropertyAll(foreground),
            // Butter is nearly invisible on paper, so the choice also gets
            // an ink edge.
            side: WidgetStateProperty.resolveWith((states) {
              if (selected || states.contains(WidgetState.hovered)) return BorderSide(color: c.ink, width: 1.5);
              if (!enabled) return BorderSide(color: c.line, width: 1.5);
              return BorderSide(color: c.lineStrong, width: 1.5);
            }),
            // The theme's ring, outside the edge, on this button's own
            // shape (the theme's would make it a pill).
            shape: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused)
                ? FocusRingBorder(shape: _shape, ring: brookieFocusSide(c.focus))
                : _shape),
            minimumSize: const WidgetStatePropertyAll(Size(0, BrookieSize.controlSm)),
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: BrookieSpace.s2)),
            alignment: AlignmentDirectional.centerStart,
            textStyle: WidgetStatePropertyAll(BrookieType.ui),
            // Selection is instant, as everywhere. A button has one duration
            // for every change, so its hover is instant too.
            animationDuration: Duration.zero,
          ),
          child: Row(
            children: [
              // Grows with the words beside it at large text sizes.
              Icon(selected ? Icons.check_box : Icons.check_box_outline_blank, size: 20, applyTextScaling: true),
              const SizedBox(width: BrookieSpace.s2),
              Expanded(child: Text('On the home page', semanticsLabel: '$name on the home page')),
            ],
          ),
        ),
      ),
    );
  }
}

/// The trash can beside a library file's name. While the file is on the
/// home page it's disabled, and its tooltip says why; while it's being
/// deleted it turns into a spinner but keeps focus.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({
    required this.focusNode,
    required this.tooltip,
    required this.onDelete,
    this.lockedReason,
    this.deleting = false,
  });

  final FocusNode focusNode;

  /// "Delete IMG_1.jpg": a screen reader lists every file's together.
  final String tooltip;

  final VoidCallback onDelete;

  /// Why it can't be deleted, if it can't, naming it as [tooltip] does.
  final String? lockedReason;

  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final reason = lockedReason;
    final VoidCallback? onPressed;
    if (reason != null) {
      onPressed = null;
    } else {
      // Pressed again while deleting, it waits for the same delete.
      onPressed = deleting ? () {} : onDelete;
    }
    return IconButton(
      focusNode: focusNode,
      tooltip: reason ?? tooltip,
      onPressed: onPressed,
      icon: deleting
          ? SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: BrookieColors.of(context).inkSoft),
            )
          : const Icon(Icons.delete_outline),
    );
  }
}

/// Files in the library the site can't show (not a JPEG, PNG or WebP by
/// name, or hidden), each with why and "Delete". Shows nothing when
/// there are none.
class HomeLibraryOtherFiles extends StatefulWidget {
  const HomeLibraryOtherFiles({super.key, required this.files, required this.deleting, required this.onDelete});

  final List<StoredPhoto> files;
  final Set<String> deleting;
  final ValueChanged<StoredPhoto> onDelete;

  /// "Can’t be shown on the site (HEIC)": why the site leaves [name] out.
  static String reason(String name) {
    const cant = 'Can’t be shown on the site';
    if (name.startsWith('.')) return '$cant (hidden file)';
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return cant;
    return '$cant (${name.substring(dot + 1).toUpperCase()})';
  }

  @override
  State<HomeLibraryOtherFiles> createState() => _HomeLibraryOtherFilesState();
}

class _HomeLibraryOtherFilesState extends State<HomeLibraryOtherFiles> {
  /// Each file's "Delete" by name.
  final _focus = <String, FocusNode>{};

  FocusNode _focusFor(String name) => _focus.putIfAbsent(name, () => FocusNode(debugLabel: 'Delete $name'));

  List<String> _names() => [for (final file in widget.files) file.name];

  @override
  void didUpdateWidget(HomeLibraryOtherFiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    final names = _names().toSet();
    for (final (i, file) in oldWidget.files.indexed) {
      if (names.contains(file.name)) continue;
      final gone = _focus.remove(file.name);
      if (gone == null) continue;
      if (gone.hasFocus) _focusNear(this, _names, i, (name) => [_focusFor(name)], (name, node) => true);
      // Its row's button holds it until this frame is built.
      WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
    }
  }

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    if (files.isEmpty) return const SizedBox.shrink();
    final c = BrookieColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Other files', style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: BrookieSpace.s2),
        for (final file in files)
          DecoratedBox(
            key: ValueKey(file.name),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: BrookieSpace.s2),
              child: Row(
                children: [
                  Expanded(
                    // One node: the name, then why.
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(file.name, style: Theme.of(context).textTheme.titleSmall),
                          Text(
                            HomeLibraryOtherFiles.reason(file.name),
                            style: BrookieType.small.copyWith(color: c.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: BrookieSpace.s2),
                  _DeleteButton(
                    focusNode: _focusFor(file.name),
                    tooltip: 'Delete ${file.name}',
                    deleting: widget.deleting.contains(file.name),
                    onDelete: () => widget.onDelete(file),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
