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

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scrollController = ScrollController();
  final _packagesKey = GlobalKey();

  /// The portfolio photographs, sorted by name; null while loading. The first
  /// is the hero, the rest are featured below the introduction.
  List<Uri>? _photos;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    final portfolio = AppServices.of(context).portfolio;
    List<Uri> photos;
    try {
      photos = await portfolio.photoUrls();
    } catch (e) {
      // The page still works without photographs, so carry on without them.
      log('Could not list the portfolio photos: $e');
      photos = const [];
    }
    if (mounted) setState(() => _photos = photos);
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
    final photos = _photos ?? const <Uri>[];
    final sectionGap = BrookieLayout.sectionGap(context);
    return Scaffold(
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeHero(
              photo: photos.isEmpty ? null : photos.first,
              loading: _photos == null,
              onBook: _scrollToPackages,
            ),
            SizedBox(height: sectionGap),
            const _Introduction(),
            ContentWidth(
              child: FeaturedPhotos(
                photos: photos.skip(1).toList(),
                padding: const EdgeInsets.only(top: BrookieSpace.s6),
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
    final display = phone
        ? text.displayLarge?.copyWith(fontSize: 44, height: 48 / 44, letterSpacing: -0.015 * 44)
        : text.displayLarge;
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
