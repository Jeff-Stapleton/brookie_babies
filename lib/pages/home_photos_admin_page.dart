import 'dart:developer';
import 'dart:math' as math;

import 'package:brookie_babies/components/admin_gate.dart';
import 'package:brookie_babies/components/featured_photos.dart';
import 'package:brookie_babies/components/home_photo_library.dart';
import 'package:brookie_babies/components/home_photo_order.dart';
import 'package:brookie_babies/components/upload_progress_list.dart';
import 'package:brookie_babies/models/stored_photo.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/services/portfolio_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:brookie_babies/utilities/upload_queue.dart';
import 'package:brookie_babies/widgets/brookie_dialog.dart';
import 'package:brookie_babies/widgets/empty_state.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// "Home page photos", for admins: which photos the home page shows, in
/// order (`site/home.photos`), chosen from the public photo library
/// (`_admin/gallery`), where photos are also uploaded and deleted.
class HomePhotosAdminPage extends StatelessWidget {
  const HomePhotosAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      // No "Your sessions" either: the pages it leads to can leave this one
      // without asking, losing uploads and changes.
      appBar: BrookieTopBar(title: 'Home page photos', showSessionsLink: false, showAdminLink: false),
      body: AdminGate(child: _HomePhotosEditor()),
    );
  }
}

class _HomePhotosEditor extends StatefulWidget {
  const _HomePhotosEditor();

  @override
  State<_HomePhotosEditor> createState() => _HomePhotosEditorState();
}

class _HomePhotosEditorState extends State<_HomePhotosEditor> {
  late final UploadQueue _queue;
  final _saveFocus = FocusNode(debugLabel: 'Save home page');
  final _discardFocus = FocusNode(debugLabel: 'Discard changes');

  /// Every file in the library, by name; null until loaded.
  List<StoredPhoto>? _library;
  bool _loadFailed = false;

  /// The home page photos as the site shows them now.
  List<String> _saved = const [];

  /// The home page photos as chosen here.
  List<String> _chosen = const [];

  /// No photos were ever chosen (no `site/home`), so the site shows the
  /// library's first photos by name, and [_saved] follows them.
  bool _neverChosen = false;

  /// Chosen photos the library no longer has, which the site leaves out.
  List<String> _missing = const [];

  bool _saving = false;
  bool _justSaved = false;
  String? _saveError;

  /// Why the last delete failed.
  String? _deleteError;
  final _deleting = <String>{};

  bool _wasUploading = false;

  bool get _changed => !listEquals(_saved, _chosen);

  /// Whether leaving now would lose something.
  bool get _hasWorkToLose => _changed || _queue.isBusy;

  @override
  void initState() {
    super.initState();
    final admin = AppServices.of(context).admin;
    _queue = UploadQueue(
      upload: admin.uploadToHomeLibrary,
      validate: PhotoRules.homePhotoProblem,
      onUploaded: _onUploaded,
    )..addListener(_onQueueChanged);
    _load();
  }

  @override
  void dispose() {
    LeaveWarning.set(this, false);
    _queue
      ..removeListener(_onQueueChanged)
      ..dispose();
    _saveFocus.dispose();
    _discardFocus.dispose();
    super.dispose();
  }

  /// Changes the page's state, and keeps [LeaveWarning] in step with it.
  void _set(VoidCallback change) {
    setState(change);
    LeaveWarning.set(this, _hasWorkToLose);
  }

  /// Changes which photos are chosen. The last save's message no longer
  /// describes them.
  void _choose(List<String> names) {
    _set(() {
      _chosen = names;
      _justSaved = false;
      _saveError = null;
    });
  }

  Future<void> _load() async {
    final admin = AppServices.of(context).admin;
    try {
      // Both at once; if the library fails, the names' answer doesn't matter.
      final names = admin.homePhotoNames()..ignore();
      final library = await admin.listHomeLibrary();
      final chosen = await names;
      if (!mounted) return;
      _set(() {
        _library = [...library]..sort((a, b) => a.name.compareTo(b.name));
        _neverChosen = chosen == null;
        if (chosen == null) {
          _saved = _firstPhotos();
        } else {
          // As the site does: the photos still in the library, once each,
          // up to the most it shows.
          final photos = _photoNames();
          _saved = chosen.where(photos.contains).toSet().take(PhotoRules.homeMaxPhotos).toList();
          _missing = chosen.where((name) => !photos.contains(name)).toSet().toList();
        }
        _chosen = _saved;
      });
    } catch (e) {
      log('Could not load the home page photos: $e');
      if (mounted) _set(() => _loadFailed = true);
    }
  }

  void _retryLoad() {
    _set(() => _loadFailed = false);
    _load();
  }

  Set<String> _photoNames() => {
        for (final file in _library ?? const <StoredPhoto>[])
          if (StoragePortfolioService.isPhoto(file.name)) file.name,
      };

  /// What the site shows while nothing has been chosen: the library's first
  /// photos by name.
  List<String> _firstPhotos() => [
        for (final file in _library ?? const <StoredPhoto>[])
          if (StoragePortfolioService.isPhoto(file.name)) file.name,
      ].take(PhotoRules.homeMaxPhotos).toList();

  /// Until photos are chosen, the site's photos follow the library's names,
  /// so the page's saved ones do too, and its chosen ones unless the admin
  /// has changed them or is saving them.
  void _followFirstPhotos() {
    if (!_neverChosen) return;
    final first = _firstPhotos();
    if (!_changed && !_saving) _chosen = first;
    _saved = first;
  }

  void _toggle(String name) {
    final chosen = [..._chosen];
    if (!chosen.remove(name) && chosen.length < PhotoRules.homeMaxPhotos) chosen.add(name);
    _choose(chosen);
  }

  void _discard() {
    // The button goes once nothing has changed: focus stays in reach.
    if (_discardFocus.hasFocus) _saveFocus.requestFocus();
    _choose(_saved);
  }

  Future<void> _save() async {
    // The button stays enabled while saving (a disabled one drops keyboard
    // focus); another press waits for the same save.
    if (_saving) return;
    final admin = AppServices.of(context).admin;
    final names = _chosen;
    _set(() {
      _saving = true;
      _justSaved = false;
      _saveError = null;
    });
    try {
      await admin.saveHomePhotos(names);
      // Saved even if the admin has left: the home page under this one
      // shows the change.
      HomePage.reloadPhotos();
      if (!mounted) return;
      _set(() {
        _saved = names;
        _neverChosen = false;
        _missing = const [];
        _justSaved = true;
      });
    } catch (e) {
      log('Could not save the home page photos: $e');
      if (!mounted) return;
      _set(() => _saveError = e is AdminException
          ? e.message
          : 'We couldn’t save the home page photos. Check your connection and try again.');
    } finally {
      if (mounted) _set(() => _saving = false);
    }
  }

  Future<void> _delete(StoredPhoto file) async {
    final admin = AppServices.of(context).admin;
    final photo = StoragePortfolioService.isPhoto(file.name);
    final confirmed = await showBrookieConfirm(
      context,
      title: photo ? 'Delete this photo?' : 'Delete this file?',
      message: '${file.name} will be deleted from the library. This can’t be undone.',
      confirmLabel: photo ? 'Delete photo' : 'Delete file',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    _set(() {
      _deleting.add(file.name);
      _deleteError = null;
    });
    try {
      await admin.deletePhoto(file);
      // Until photos are chosen the site shows the library's first ones,
      // so the home page under this one looks again either way.
      HomePage.reloadPhotos();
      if (!mounted) return;
      _set(() {
        _library = [
          for (final other in _library!)
            if (other.name != file.name) other,
        ];
        _followFirstPhotos();
      });
    } catch (e) {
      log('Could not delete ${file.fullPath}: $e');
      if (!mounted) return;
      _set(() => _deleteError = e is AdminException
          ? e.message
          : 'We couldn’t delete ${file.name}. Check your connection and try again.');
    } finally {
      if (mounted) _set(() => _deleting.remove(file.name));
    }
  }

  void _pickPhotos() {
    // First thing, before any await: browsers only open the file picker
    // straight from a tap.
    final picked = AppServices.of(context).pickPhotos(accept: PhotoRules.homeAccept);
    // Never waited on with the page held up: some browsers don't say when
    // the picker is cancelled.
    picked.then(
      (photos) {
        final library = _library;
        if (!mounted || library == null || photos.isEmpty) return;
        _queue.add(photos, existing: [for (final file in library) file.name]);
      },
      onError: (Object e) => log('Could not pick photos: $e'),
    );
  }

  /// A photo just stored joins the library at once, for now without a
  /// link to show it by (they come with the next listing). Once: the queue
  /// also passes on a name it found already stored.
  void _onUploaded(UploadItem item) {
    final library = _library;
    if (!mounted || library == null || library.any((file) => file.name == item.name)) return;
    _set(() {
      _library = [
        ...library,
        StoredPhoto(name: item.name, fullPath: '${StoragePortfolioService.folder}/${item.name}'),
      ]..sort((a, b) => a.name.compareTo(b.name));
      _followFirstPhotos();
    });
  }

  void _onQueueChanged() {
    final uploading = _queue.isBusy;
    if (uploading == _wasUploading) return;
    _wasUploading = uploading;
    _set(() {});
    if (!uploading) _fetchLinks();
  }

  /// Lists the library once the uploads are done, for the links to show
  /// the new photos by: once per batch, not once per photo. Only the links
  /// are taken from it; the page's own list stays as it is.
  Future<void> _fetchLinks() async {
    bool unlinked(StoredPhoto file) => file.url == null && StoragePortfolioService.isPhoto(file.name);
    if (!(_library?.any(unlinked) ?? false)) return;
    final admin = AppServices.of(context).admin;
    try {
      final listed = {for (final file in await admin.listHomeLibrary()) file.name: file.url};
      if (!mounted) return;
      _set(() {
        _library = [
          for (final file in _library!)
            if (unlinked(file) && listed[file.name] != null)
              StoredPhoto(name: file.name, fullPath: file.fullPath, url: listed[file.name])
            else
              file,
        ];
      });
    } catch (e) {
      // The new photos are listed and can be chosen; only their previews
      // wait for the page to be opened again.
      log('Could not fetch links for the new home page photos: $e');
    }
  }

  Future<void> _confirmLeave() async {
    final uploading = _queue.isBusy;
    final String message;
    if (!uploading) {
      message = 'The changes you made to the home page photos will be lost.';
    } else if (_changed) {
      message = 'Photos still uploading will stop, and changes you haven’t saved will be lost.';
    } else {
      message = 'Photos still uploading will stop. The ones already uploaded stay in the library.';
    }
    final leave = await showBrookieConfirm(
      context,
      title: uploading ? 'Stop uploading?' : 'Leave without saving?',
      message: message,
      confirmLabel: uploading ? 'Stop and leave' : 'Leave without saving',
      cancelLabel: uploading ? 'Keep uploading' : 'Keep editing',
      destructive: true,
    );
    if (!leave || !mounted) return;
    // Navigator.pop leaves whatever PopScope says.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // The content column ContentWidth would set, for the slivers.
    final side = math.max(BrookieLayout.gutter(context), (width - BrookieSize.contentWidth) / 2);
    final top = width >= BrookieBreakpoint.wide ? BrookieSpace.s7 : BrookieSpace.s6;
    final sectionGap = BrookieLayout.sectionGap(context);
    final library = _library;

    final slivers = <Widget>[
      SliverPadding(
        padding: EdgeInsets.fromLTRB(side, top, side, 0),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Introduction(),
              SizedBox(height: sectionGap),
              if (library != null) ...[
                _chosenSection(library),
                SizedBox(height: sectionGap),
                _librarySection(library),
              ] else if (_loadFailed)
                _LoadFailed(onRetry: _retryLoad)
              else
                const Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
      ),
      if (library != null) ...[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, BrookieSpace.s5, side, 0),
          sliver: HomePhotoLibrary(
            photos: [
              for (final file in library)
                if (StoragePortfolioService.isPhoto(file.name)) file,
            ],
            chosen: _chosen.toSet(),
            canAdd: _chosen.length < PhotoRules.homeMaxPhotos,
            locked: {..._chosen, ..._saved},
            deleting: _deleting,
            onToggle: _toggle,
            onDelete: _delete,
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, sectionGap, side, 0),
          sliver: SliverToBoxAdapter(
            child: _ListColumn(
              child: HomeLibraryOtherFiles(
                files: [
                  for (final file in library)
                    if (!StoragePortfolioService.isPhoto(file.name)) file,
                ],
                deleting: _deleting,
                onDelete: _delete,
              ),
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(child: SizedBox(height: sectionGap)),
    ];

    return PopScope(
      canPop: !_hasWorkToLose,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: CustomScrollView(slivers: slivers),
    );
  }

  /// "On the home page": the chosen photos in order, what the home page
  /// does with them, and saving.
  Widget _chosenSection(List<StoredPhoto> library) {
    final c = BrookieColors.of(context);
    final byName = {for (final file in library) file.name: file};
    final missing = _missing;
    final firstShown = _saved.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: 'On the home page',
          detail: '${_chosen.length} of ${PhotoRules.homeMaxPhotos}',
        ),
        if (_neverChosen && firstShown > 0) ...[
          const SizedBox(height: BrookieSpace.s4),
          _Note(
            firstShown == 1
                ? 'No photos have been chosen yet, so the site shows the library’s only photo. Save to keep it, '
                    'or change it first.'
                : 'No photos have been chosen yet, so the site shows the first $firstShown photos in the library, '
                    'in file-name order. Save to keep them, or change them first.',
          ),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: BrookieSpace.s4),
          _Note(
            missing.length == 1
                ? '${missing.single} was chosen but isn’t in the library any more, so the site leaves it out.'
                : '${missing.length} chosen photos aren’t in the library any more, so the site leaves them out.',
          ),
        ],
        const SizedBox(height: BrookieSpace.s4),
        if (_chosen.isEmpty)
          const EmptyState(message: 'No photos on the home page. Choose some from the library below.')
        else
          _ListColumn(
            child: HomePhotoOrder(
              photos: [
                for (final name in _chosen) byName[name] ?? StoredPhoto(name: name, fullPath: name),
              ],
              onChanged: _choose,
              focusWhenEmptied: _saveFocus,
            ),
          ),
        const SizedBox(height: BrookieSpace.s3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
          child: Text(homePhotosShownNote(_chosen.length), style: TextStyle(color: c.inkSoft)),
        ),
        const SizedBox(height: BrookieSpace.s5),
        Wrap(
          spacing: BrookieSpace.s3,
          runSpacing: BrookieSpace.s3,
          children: [
            FilledButton(
              focusNode: _saveFocus,
              onPressed: _save,
              style: _saving ? _busyStyle(c) : null,
              child: Text(_saving ? 'Saving…' : 'Save home page'),
            ),
            if (_changed)
              TextButton(focusNode: _discardFocus, onPressed: _discard, child: const Text('Discard changes')),
          ],
        ),
        if (_saveError case final error?) ...[
          const SizedBox(height: BrookieSpace.s4),
          InlineMessage(message: error),
        ] else if (_justSaved && !_changed) ...[
          const SizedBox(height: BrookieSpace.s4),
          const InlineMessage(message: 'Saved. The home page shows these photos now.', tone: StatusTone.success),
        ],
      ],
    );
  }

  /// "Photo library": who can see it, uploading, and the notes about the
  /// grid below.
  Widget _librarySection(List<StoredPhoto> library) {
    final c = BrookieColors.of(context);
    final photoCount = library.where((file) => StoragePortfolioService.isPhoto(file.name)).length;
    // Taken off the home page, but on the site until it's saved.
    final removed = _saved.any((name) => !_chosen.contains(name));
    final notes = [
      if (_chosen.length >= PhotoRules.homeMaxPhotos)
        'The home page has ${PhotoRules.homeMaxPhotos} photos, the most it shows. Remove one to add another.',
      if (removed)
        'Photos on the home page can’t be deleted. Remove them from the home page and save first: until you '
            'save, the site still shows the ones you removed.'
      else if (_chosen.isNotEmpty)
        'Photos on the home page can’t be deleted. Remove them from the home page first.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title: 'Photo library', detail: photoCount == 1 ? '1 photo' : '$photoCount photos'),
        const SizedBox(height: BrookieSpace.s4),
        const _Note(
          'Anyone can see every photo in the library, even the ones that aren’t on the home page. '
          'Don’t upload clients’ photos without their permission.',
          icon: Icons.public,
        ),
        const SizedBox(height: BrookieSpace.s4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _pickPhotos,
            icon: const Icon(Icons.upload_outlined),
            label: const Text('Upload photos'),
          ),
        ),
        const SizedBox(height: BrookieSpace.s2),
        Text(
          'JPEG, PNG or WebP, each under ${PhotoRules.homeMaxBytes ~/ (1024 * 1024)} MB.',
          style: BrookieType.small.copyWith(color: c.inkSoft),
        ),
        // Takes no room until photos are picked.
        ListenableBuilder(
          listenable: _queue,
          builder: (context, child) => Padding(
            padding: EdgeInsets.only(top: _queue.items.isEmpty ? 0 : BrookieSpace.s4),
            child: child,
          ),
          child: UploadProgressList(queue: _queue),
        ),
        if (_deleteError case final error?) ...[
          const SizedBox(height: BrookieSpace.s4),
          InlineMessage(message: error),
        ],
        if (photoCount == 0) ...[
          const SizedBox(height: BrookieSpace.s5),
          const EmptyState(message: 'No photos in the library yet. Upload some to choose from.'),
        ],
        for (final note in notes) ...[
          const SizedBox(height: BrookieSpace.s3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
            child: Text(note, style: TextStyle(color: c.inkSoft)),
          ),
        ],
      ],
    );
  }

  /// While saving, the button looks disabled but keeps focus.
  static ButtonStyle _busyStyle(BrookieColors c) => ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(c.surfaceSunk),
        foregroundColor: WidgetStatePropertyAll(c.inkSoft),
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.progress),
      );
}

/// What the home page does with [count] chosen photos: how many of the ones
/// after the hero wide screens and phones show (FeaturedPhotos.shownCount).
@visibleForTesting
String homePhotosShownNote(int count) {
  if (count == 0) return 'With no photos, the home page shows the logo on a plain band.';
  final featured = count - 1;
  if (featured == 0) return 'Just the full-screen photo. Add more to show photos below the introduction.';
  final wide = FeaturedPhotos.shownCount(featured, wide: true);
  final phone = FeaturedPhotos.shownCount(featured, wide: false);
  if (wide == 0 && phone == 0) {
    return 'One photo below the introduction is left out: it takes two to fill a row. Add another to show them.';
  }
  if (wide == featured && phone == featured) {
    final all = featured == 2 ? 'both photos' : 'all $featured photos';
    return 'Wide screens and phones show $all below the introduction.';
  }
  String shown(int n) => n == featured ? 'all $featured' : 'the first $n of $featured';
  return 'Photos below the introduction fill whole rows, so wide screens show ${shown(wide)} and phones '
      'show ${shown(phone)}.';
}

class _Introduction extends StatelessWidget {
  const _Introduction();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('Home page photos', style: Theme.of(context).textTheme.headlineLarge),
        ),
        const SizedBox(height: BrookieSpace.s3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
          child: Text(
            'Choose the photos on the home page and their order, from the photo library below.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

/// A section's title, with a count at its side.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: BrookieSpace.s3,
      children: [
        Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        Text(detail, style: TextStyle(color: BrookieColors.of(context).inkSoft)),
      ],
    );
  }
}

/// A list held to the column "Your sessions" lists sessions in (the empty
/// state's width), so a row's buttons stay near its name on wide screens.
class _ListColumn extends StatelessWidget {
  const _ListColumn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: EmptyState.maxWidth), child: child),
    );
  }
}

/// A neutral note, held to the reading width.
class _Note extends StatelessWidget {
  const _Note(this.message, {this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
        child: InlineMessage(message: message, tone: StatusTone.neutral, icon: icon),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
            child: const InlineMessage(
                message: 'We couldn’t load the home page photos. Check your connection and try again.'),
          ),
        ),
        const SizedBox(height: BrookieSpace.s4),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
