import 'dart:developer';

import 'package:brookie_babies/components/featured_photos.dart';
import 'package:brookie_babies/components/home_hero.dart';
import 'package:brookie_babies/components/packages.dart';
import 'package:brookie_babies/components/page_footer.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The landing page: the hero photograph, a short introduction with a few
/// more photographs, the packages, and the footer.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  /// Goes back to the home page and scrolls to the packages, as "See
  /// packages" on the other pages promises. The home page is always the first
  /// route, deep links included.
  static void showPackages(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _packagesRequests.value++;
  }

  static final _packagesRequests = ValueNotifier<int>(0);

  /// Fetches the home page photos again, and gives ones that couldn't be
  /// loaded another try: the admin's home page photos page calls it after a
  /// change, so the home page under it shows the change without a refresh.
  static void reloadPhotos() => _photosRequests.value++;

  static final _photosRequests = ValueNotifier<int>(0);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scrollController = ScrollController();
  final _packagesKey = GlobalKey();

  /// The portfolio photographs, in the order they're shown; null while
  /// loading.
  List<Uri>? _photos;

  /// Photographs that couldn't be loaded. They are left out: the hero moves
  /// on to the next one, and the featured grid closes up.
  final _failedPhotos = <Uri>{};

  /// Counts photo loads, so an older one that answers late can't replace a
  /// newer one's photos.
  int _photoLoads = 0;

  /// The load whose photos are shown; 0 for none yet.
  int _shownLoad = 0;

  /// Loads still waiting for their answer.
  final _pendingLoads = <int>{};

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    HomePage._packagesRequests.addListener(_onPackagesRequested);
    HomePage._photosRequests.addListener(_onPhotosRequested);
  }

  @override
  void dispose() {
    HomePage._packagesRequests.removeListener(_onPackagesRequested);
    HomePage._photosRequests.removeListener(_onPhotosRequested);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPhotosRequested() => _loadPhotos();

  void _onPackagesRequested() {
    // After the pop has rebuilt this page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToPackages();
    });
  }

  Future<void> _loadPhotos() async {
    final load = ++_photoLoads;
    final portfolio = AppServices.of(context).portfolio;
    _pendingLoads.add(load);
    List<Uri> photos;
    try {
      photos = await portfolio.photoUrls(limit: 1 + FeaturedPhotos.maxCount);
    } catch (e) {
      log('Could not list the portfolio photos: $e');
      // A load that fails keeps the photos already shown, or waits for an
      // older load's.
      if (_photos != null || _pendingLoads.any((other) => other < load)) return;
      // The page still works without photographs, so carry on without them.
      photos = const [];
    } finally {
      _pendingLoads.remove(load);
    }
    // Only a newer answer than the one shown counts, so a load that fails
    // doesn't throw away an older one that works.
    if (!mounted || load < _shownLoad) return;
    setState(() {
      _shownLoad = load;
      _photos = photos;
      // A fresh list: photos that failed before get another try.
      _failedPhotos.clear();
    });
  }

  void _leaveOut(Uri photo) {
    if (mounted) setState(() => _failedPhotos.add(photo));
  }

  /// Scrolls so the packages section starts at the top of the window, with
  /// its section gap above the title.
  void _scrollToPackages() {
    final section = _packagesKey.currentContext?.findRenderObject();
    if (section == null) return;
    final position = _scrollController.position;
    final target = (RenderAbstractViewport.of(section).getOffsetToReveal(section, 0).offset -
            BrookieLayout.sectionGap(context))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(target);
    } else {
      position.animateTo(target, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The first is the hero, the rest are featured below the introduction.
    final photos = [
      for (final photo in _photos ?? const <Uri>[])
        if (!_failedPhotos.contains(photo)) photo,
    ];
    final hero = photos.isEmpty ? null : photos.first;
    final sectionGap = BrookieLayout.sectionGap(context);
    return Scaffold(
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeHero(
              photo: hero,
              loading: _photos == null,
              onBook: _scrollToPackages,
              onPhotoFailed: hero == null ? null : () => _leaveOut(hero),
            ),
            SizedBox(height: sectionGap),
            const _Introduction(),
            ContentWidth(
              child: FeaturedPhotos(
                photos: photos.skip(1).toList(),
                padding: const EdgeInsets.only(top: BrookieSpace.s6),
                onPhotoFailed: _leaveOut,
              ),
            ),
            SizedBox(height: sectionGap),
            Packages(key: _packagesKey),
            SizedBox(height: sectionGap),
            const PageFooter(),
          ],
        ),
      ),
    );
  }
}

/// One display line and a lede paragraph on paper, below the hero.
class _Introduction extends StatelessWidget {
  const _Introduction();

  /// Narrower than the reading width so this short lede breaks into two
  /// even lines instead of leaving one word on the second.
  static const _ledeWidth = 520.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final phone = MediaQuery.sizeOf(context).width < BrookieBreakpoint.gutter;
    // Display is set for wide screens; on a phone it would take the whole
    // first screen after the hero.
    final display = phone ? text.displayLarge?.merge(BrookieType.displayCompact) : text.displayLarge;
    return ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('Little ones, while they’re little', style: display)),
          const SizedBox(height: BrookieSpace.s5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _ledeWidth),
            child: Text(
              'Calm, unhurried sessions for newborns, babies and the people who hold them.',
              style: text.bodyLarge?.merge(BrookieType.lede),
            ),
          ),
        ],
      ),
    );
  }
}
