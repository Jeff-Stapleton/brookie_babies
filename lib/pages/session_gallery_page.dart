import 'dart:developer';
import 'dart:math' as math;

import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:brookie_babies/widgets/network_photo.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final _viewerFade = CurveTween(curve: Curves.easeOut);

/// A family's private session: a full-bleed cover photograph followed by
/// every photo in the gallery. Selecting a print opens the full photograph.
class SessionGalleryPage extends StatefulWidget {
  const SessionGalleryPage({
    super.key,
    required this.booking,
    this.adminPreview = false,
  });

  final Booking booking;

  /// Loads the gallery with the admin claim even before it is available to
  /// the family. The page itself stays the same as the customer's view.
  final bool adminPreview;

  @override
  State<SessionGalleryPage> createState() => _SessionGalleryPageState();
}

class _SessionGalleryPageState extends State<SessionGalleryPage> {
  late Future<List<GalleryPhoto>> _photos;

  @override
  void initState() {
    super.initState();
    _photos = _load();
  }

  Future<List<GalleryPhoto>> _load() => AppServices.of(context).gallery.loadPhotos(
        widget.booking.id,
        adminPreview: widget.adminPreview,
      );

  void _retry() {
    final photos = _load();
    setState(() {
      _photos = photos;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A customer has no Admin link. Keep it out of the preview too, so the
      // gallery itself is what the family will see; Back still returns to the
      // session's admin page.
      appBar: BrookieTopBar(title: 'Photo gallery', showAdminLink: !widget.adminPreview),
      body: FutureBuilder<List<GalleryPhoto>>(
        future: _photos,
        builder: (context, snapshot) {
          final photos = snapshot.data;
          if (photos != null && photos.isNotEmpty) {
            return _Gallery(booking: widget.booking, photos: photos);
          }
          if (snapshot.hasError || (photos != null && photos.isEmpty)) {
            final error = snapshot.error;
            if (error != null && error is! GalleryException) {
              log('Opening gallery ${widget.booking.id} failed: $error');
            }
            return _GalleryStatus(
              booking: widget.booking,
              message: error is GalleryException ? error.message : kGalleryLoadErrorFallback,
              onRetry: _retry,
            );
          }
          return _GalleryStatus(booking: widget.booking);
        },
      ),
    );
  }
}

/// Always includes the year: galleries are keepsakes that may be revisited
/// long after the session.
String galleryDateLabel(DateTime date) => '${formatDayHeading(date)}, ${date.year}';

class _GalleryStatus extends StatelessWidget {
  const _GalleryStatus({
    required this.booking,
    this.message,
    this.onRetry,
  });

  final Booking booking;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= BrookieBreakpoint.wide;
    final message = this.message;
    return SingleChildScrollView(
      child: ContentWidth(
        child: Padding(
          padding: EdgeInsets.only(
            top: wide ? BrookieSpace.s7 : BrookieSpace.s6,
            bottom: BrookieLayout.sectionGap(context),
          ),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      booking.familyTitle,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                  const SizedBox(height: BrookieSpace.s2),
                  Text(
                    galleryDateLabel(booking.date),
                    style: TextStyle(
                      color: BrookieColors.of(context).inkSoft,
                    ),
                  ),
                  const SizedBox(height: BrookieSpace.s6),
                  if (message == null)
                    const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else ...[
                    InlineMessage(message: message),
                    const SizedBox(height: BrookieSpace.s4),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.booking, required this.photos});

  final Booking booking;
  final List<GalleryPhoto> photos;

  void _open(BuildContext context, int index) {
    showSessionPhotoViewer(
      context,
      booking: booking,
      photos: photos,
      initialIndex: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = photos.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = MediaQuery.sizeOf(context).width < BrookieBreakpoint.gutter;
        // A normal caption completes the first screen. A long or enlarged
        // title may make the landing section taller, without squeezing the
        // cover below a useful size or overflowing a fixed-height column.
        final coverHeight = math.max(
          320.0,
          constraints.maxHeight - (compact ? 224 : 200),
        );
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: coverHeight,
                    child: Semantics(
                      image: true,
                      label: 'Cover photo from ${booking.familyTitle}',
                      child: LayoutBuilder(
                        builder: (context, coverConstraints) {
                          final ratio = MediaQuery.devicePixelRatioOf(context);
                          return NetworkPhoto(
                            key: ValueKey(photos.first.url),
                            url: photos.first.url,
                            decodeSize: Size(
                              coverConstraints.maxWidth * ratio,
                              coverConstraints.maxHeight * ratio,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  _SessionCaption(booking: booking),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: ContentWidth(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: BrookieLayout.sectionGap(context),
                    bottom: BrookieSpace.s5,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Your photos',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                      ),
                      const SizedBox(height: BrookieSpace.s2),
                      Text(
                        count == 1 ? '1 photograph' : '$count photographs',
                        style: TextStyle(
                          color: BrookieColors.of(context).inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverLayoutBuilder(
              builder: (context, gridConstraints) {
                final viewportWidth = gridConstraints.crossAxisExtent;
                final gutter = viewportWidth >= BrookieBreakpoint.gutter ? BrookieSpace.s5 : BrookieSpace.s4;
                final side = math.max(
                  gutter,
                  (viewportWidth - BrookieSize.contentWidth) / 2,
                );
                final gridWidth = viewportWidth - 2 * side;
                final columns = switch (gridWidth) {
                  < 600 => 2,
                  < 900 => 3,
                  _ => 4,
                };
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    side,
                    0,
                    side,
                    BrookieLayout.sectionGap(context),
                  ),
                  sliver: SliverGrid.builder(
                    itemCount: count,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: BrookieSpace.s4,
                      crossAxisSpacing: BrookieSpace.s4,
                      childAspectRatio: 4 / 5,
                    ),
                    itemBuilder: (context, index) => _GalleryTile(
                      key: ValueKey(photos[index].name),
                      photo: photos[index],
                      index: index,
                      count: count,
                      onOpen: () => _open(context, index),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _SessionCaption extends StatelessWidget {
  const _SessionCaption({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < BrookieBreakpoint.gutter;
    return ColoredBox(
      color: BrookieColors.of(context).paper,
      child: ContentWidth(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BrookieSpace.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  booking.familyTitle,
                  style: compact ? BrookieType.displayCompact : BrookieType.display,
                ),
              ),
              const SizedBox(height: BrookieSpace.s2),
              Text(
                galleryDateLabel(booking.date),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: BrookieColors.of(context).inkSoft,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryTile extends StatefulWidget {
  const _GalleryTile({
    super.key,
    required this.photo,
    required this.index,
    required this.count,
    required this.onOpen,
  });

  final GalleryPhoto photo;
  final int index;
  final int count;
  final VoidCallback onOpen;

  @override
  State<_GalleryTile> createState() => _GalleryTileState();
}

class _GalleryTileState extends State<_GalleryTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final open = CallbackAction<Intent>(
      onInvoke: (_) {
        widget.onOpen();
        return null;
      },
    );
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: 'View photo ${widget.index + 1} of ${widget.count}',
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          actions: {
            ActivateIntent: open,
            ButtonActivateIntent: open,
          },
          child: GestureDetector(
            onTap: widget.onOpen,
            behavior: HitTestBehavior.opaque,
            child: FocusRing.onPhoto(
              visible: _focused,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: BrookieColors.of(context).shadowPrint,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pixels = constraints.maxWidth * MediaQuery.devicePixelRatioOf(context);
                    final decodeWidth = ((pixels / 128).ceil() * 128).toDouble();
                    return NetworkPhoto(
                      url: widget.photo.url,
                      decodeSize: Size(decodeWidth, decodeWidth / (4 / 5)),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens one gallery photograph full-screen, with previous/next controls.
Future<void> showSessionPhotoViewer(
  BuildContext context, {
  required Booking booking,
  required List<GalleryPhoto> photos,
  required int initialIndex,
}) {
  assert(photos.isNotEmpty);
  assert(initialIndex >= 0 && initialIndex < photos.length);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close photo',
    barrierColor: BrookieColors.of(context).scrim,
    transitionDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : kBrookieFadeDuration,
    pageBuilder: (context, animation, secondaryAnimation) => _PhotoViewer(
      booking: booking,
      photos: photos,
      initialIndex: initialIndex,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
      opacity: animation.drive(_viewerFade),
      child: child,
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.booking,
    required this.photos,
    required this.initialIndex,
  });

  final Booking booking;
  final List<GalleryPhoto> photos;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late int _index = widget.initialIndex;
  final _keyboardFocus = FocusNode(debugLabel: 'Photo viewer keyboard');

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _move(int by) {
    final next = _index + by;
    if (next >= 0 && next < widget.photos.length) {
      setState(() => _index = next);
      // A pointer press on an arrow must not make the viewer lose its
      // left/right/Escape keyboard controls.
      _keyboardFocus.requestFocus();
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _move(-1);
      case LogicalKeyboardKey.arrowRight:
        _move(1);
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final count = widget.photos.length;
    final number = _index + 1;
    final photo = widget.photos[_index];
    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Material(
        color: c.surfaceSunk,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.paper,
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      const SizedBox(width: BrookieSpace.s2),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Close photo',
                      ),
                      const SizedBox(width: BrookieSpace.s2),
                      Expanded(
                        child: Text(
                          widget.booking.familyTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(
                        width: BrookieSize.controlSm + BrookieSpace.s4,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(BrookieSpace.s4),
                  child: Semantics(
                    image: true,
                    excludeSemantics: true,
                    label: 'Photo $number of $count from ${widget.booking.familyTitle}',
                    child: LayoutBuilder(
                      builder: (context, constraints) => InteractiveViewer(
                        key: ValueKey(photo.url),
                        minScale: 1,
                        maxScale: 4,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: Image.network(
                            photo.url.toString(),
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                            loadingBuilder: (context, child, loadingProgress) => loadingProgress == null
                                ? child
                                : const Center(
                                    child: SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                            errorBuilder: (context, error, stackTrace) => Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: BrookieSize.readingWidth,
                                ),
                                child: Text(
                                  'This photo couldn’t be shown. Close it and refresh the gallery to try again.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: c.inkSoft),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.paper,
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      const SizedBox(width: BrookieSpace.s2),
                      IconButton(
                        onPressed: _index > 0 ? () => _move(-1) : null,
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Previous photo',
                      ),
                      Expanded(
                        child: Text(
                          '$number of $count',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: _index + 1 < count ? () => _move(1) : null,
                        icon: const Icon(Icons.arrow_forward),
                        tooltip: 'Next photo',
                      ),
                      const SizedBox(width: BrookieSpace.s2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
