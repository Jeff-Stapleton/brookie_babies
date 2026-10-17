// The Brookie Babies design system, applied to Flutter: colors, type, spacing
// and the Material theme built from them.
//
// Source of truth: the "Brookie Babies" design system (tokens.json and its
// Flutter theme section). Two themes: Print (light, the default) and Darkroom
// (dark, used when the device asks for it).
//
// Read the system's own colors with `BrookieColors.of(context)`; Material
// widgets pick the rest up from the theme.

import 'package:flutter/material.dart';

/// The design system's colors for the current theme.
@immutable
class BrookieColors extends ThemeExtension<BrookieColors> {
  const BrookieColors({
    required this.paper,
    required this.surface,
    required this.surfaceSunk,
    required this.ink,
    required this.inkSoft,
    required this.onInk,
    required this.line,
    required this.lineStrong,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.scrim,
    required this.shadowPrint,
    required this.shadowDialog,
  });

  /// Page background behind everything that is not a photograph.
  final Color paper;

  /// Cards, dialogs, inputs and menus, set on [paper] and edged with [line].
  final Color surface;

  /// Quiet bands and a photo's placeholder while it loads.
  final Color surfaceSunk;

  /// All primary text; the primary button's fill; the selected-state ring.
  final Color ink;

  /// Secondary text: times, addresses, helper text, past calendar days.
  final Color inkSoft;

  /// Text and icons on an [ink] fill.
  final Color onInk;

  /// Decorative hairlines only: card edges, dividers.
  final Color line;

  /// Edges that carry meaning: input borders, the secondary button, today.
  final Color lineStrong;

  /// Confirmed states (Paid, Booked, Ready to download), always with a word.
  final Color success;
  final Color successSoft;

  /// Errors, always with a word and a way out.
  final Color danger;
  final Color dangerSoft;

  /// Behind a dialog or the photo viewer.
  final Color scrim;

  /// A photograph laid on paper. None in Darkroom.
  final List<BoxShadow> shadowPrint;

  /// Dialogs, above [scrim].
  final List<BoxShadow> shadowDialog;

  /// The logo's disc, the system's only accent. The same in both themes.
  ///
  /// Measured from assets/logo.png. A fill, never text, and never a meaning on
  /// its own: on [paper] it is about 1.4:1, so a selected state always adds an
  /// [ink] ring.
  Color get butter => const Color(0xFFD5D0B3);

  /// Text and icons on a [butter] fill, in both themes.
  Color get onButter => const Color(0xFF1C1B19);

  /// Keyboard focus ring.
  Color get focus => ink;

  static const light = BrookieColors( // Print
    paper: Color(0xFFF6F6F3),
    surface: Color(0xFFFFFFFF),
    surfaceSunk: Color(0xFFEEEDE9),
    ink: Color(0xFF1C1B19),
    inkSoft: Color(0xFF5C5953),
    onInk: Color(0xFFF6F6F3),
    line: Color(0xFFDCD9D3),
    lineStrong: Color(0xFF8B877F),
    success: Color(0xFF2C5866),
    successSoft: Color(0xFFE2EDF0),
    danger: Color(0xFFA3342B),
    dangerSoft: Color(0xFFF7E4E1),
    scrim: Color(0x8F141412), // rgba(20, 20, 18, 0.56)
    shadowPrint: [
      BoxShadow(color: Color(0x1F1C1B19), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x381C1B19), offset: Offset(0, 10), blurRadius: 24, spreadRadius: -10),
    ],
    shadowDialog: [
      BoxShadow(color: Color(0x471C1B19), offset: Offset(0, 24), blurRadius: 48, spreadRadius: -12),
    ],
  );

  static const dark = BrookieColors( // Darkroom
    paper: Color(0xFF141412),
    surface: Color(0xFF1E1D1B),
    surfaceSunk: Color(0xFF0E0E0D),
    ink: Color(0xFFF0EFEA),
    inkSoft: Color(0xFFAAA69E),
    onInk: Color(0xFF141412),
    line: Color(0xFF34322F),
    lineStrong: Color(0xFF77736B),
    success: Color(0xFF93C6D4),
    successSoft: Color(0xFF1B2D33),
    danger: Color(0xFFF0A097),
    dangerSoft: Color(0xFF3A1F1C),
    scrim: Color(0xA8000000), // rgba(0, 0, 0, 0.66)
    shadowPrint: [],
    shadowDialog: [
      BoxShadow(color: Color(0x99000000), offset: Offset(0, 24), blurRadius: 48, spreadRadius: -12),
    ],
  );

  /// The colors of the nearest theme. Every theme in this app carries them.
  static BrookieColors of(BuildContext context) => Theme.of(context).extension<BrookieColors>()!;

  @override
  BrookieColors copyWith({
    Color? paper,
    Color? surface,
    Color? surfaceSunk,
    Color? ink,
    Color? inkSoft,
    Color? onInk,
    Color? line,
    Color? lineStrong,
    Color? success,
    Color? successSoft,
    Color? danger,
    Color? dangerSoft,
    Color? scrim,
    List<BoxShadow>? shadowPrint,
    List<BoxShadow>? shadowDialog,
  }) {
    return BrookieColors(
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
      surfaceSunk: surfaceSunk ?? this.surfaceSunk,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      onInk: onInk ?? this.onInk,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      scrim: scrim ?? this.scrim,
      shadowPrint: shadowPrint ?? this.shadowPrint,
      shadowDialog: shadowDialog ?? this.shadowDialog,
    );
  }

  @override
  BrookieColors lerp(ThemeExtension<BrookieColors>? other, double t) {
    if (other is! BrookieColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return BrookieColors(
      paper: l(paper, other.paper),
      surface: l(surface, other.surface),
      surfaceSunk: l(surfaceSunk, other.surfaceSunk),
      ink: l(ink, other.ink),
      inkSoft: l(inkSoft, other.inkSoft),
      onInk: l(onInk, other.onInk),
      line: l(line, other.line),
      lineStrong: l(lineStrong, other.lineStrong),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      scrim: l(scrim, other.scrim),
      shadowPrint: BoxShadow.lerpList(shadowPrint, other.shadowPrint, t)!,
      shadowDialog: BoxShadow.lerpList(shadowDialog, other.shadowDialog, t)!,
    );
  }
}

/// The design system's text styles, without color (the theme supplies [ink]).
///
/// Jost for everything people scan; Newsreader for everything they read.
abstract final class BrookieType {
  static const _sans = 'Jost';
  static const _serif = 'Newsreader';

  static TextStyle _style(String family, double size, double lineHeight, FontWeight weight,
          {double letterSpacingEm = 0, FontStyle? fontStyle}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: lineHeight / size,
        fontWeight: weight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacingEm * size,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// One per page at most, on paper. Never near the logo.
  static final display = _style(_sans, 64, 68, FontWeight.w300, letterSpacingEm: -0.015);

  /// [display] on phones (below [BrookieBreakpoint.gutter]), where 64px would
  /// fill the first screen after the hero.
  static final displayCompact = _style(_sans, 44, 48, FontWeight.w300, letterSpacingEm: -0.015);

  /// Page titles.
  static final headline = _style(_sans, 40, 46, FontWeight.w300, letterSpacingEm: -0.01);

  /// Package names, dialog titles, section titles.
  static final title = _style(_sans, 26, 32, FontWeight.w400);

  /// Package price and totals. Whole dollars.
  static final price = _style(_sans, 34, 38, FontWeight.w300);

  /// Buttons, tabs, calendar numerals, the top bar's title.
  static final label = _style(_sans, 16, 20, FontWeight.w500, letterSpacingEm: 0.01);

  /// Times, addresses, list rows, package inclusions. The default for [Text].
  static final ui = _style(_sans, 15, 22, FontWeight.w400);

  /// Helper text, status tags, weekday headings, fine print. Never smaller.
  static final small = _style(_sans, 13, 18, FontWeight.w400);

  /// The first paragraph under a headline. One per page.
  static final lede = _style(_serif, 21, 32, FontWeight.w400);

  /// Anything people read rather than scan.
  static final body = _style(_serif, 17, 28, FontWeight.w400);

  /// Client words only, in light italic.
  static final quote = _style(_serif, 22, 32, FontWeight.w300, fontStyle: FontStyle.italic);
}

/// Spacing on a 4px base.
abstract final class BrookieSpace {
  /// Icon to its label; a status tag's vertical padding.
  static const double s1 = 4;

  /// Gaps inside a row.
  static const double s2 = 8;

  /// Between related lines in a card.
  static const double s3 = 12;

  /// Page gutter on phones; between cards in a grid.
  static const double s4 = 16;

  /// Card and dialog padding; page gutter from 600px wide.
  static const double s5 = 24;

  /// Between a headline and the content it introduces.
  static const double s6 = 32;

  /// Between page sections on phones.
  static const double s7 = 48;

  /// Between page sections from 900px wide.
  static const double s8 = 64;

  /// Above and below the hero's content on large screens.
  static const double s9 = 96;
}

abstract final class BrookieRadius {
  /// Photographs are prints: square corners, always.
  static const double print = 0;

  /// Inputs, status tags, session slots.
  static const double sm = 6;

  /// Cards, dialogs, menus.
  static const double md = 14;
}

abstract final class BrookieSize {
  /// Height of buttons and inputs.
  static const double control = 52;

  /// The sign-in chip, the avatar and small buttons in a top bar.
  static const double controlSm = 40;

  /// Calendar day disc: the smallest comfortable tap target.
  static const double day = 44;

  /// Max width of page content. Hero photographs bleed past it.
  static const double contentWidth = 1120;

  /// Max width of any block of body or lede text (about 70 characters).
  static const double readingWidth = 640;
}

/// Widths at which the layout steps up.
abstract final class BrookieBreakpoint {
  /// Gutters widen from [BrookieSpace.s4] to [BrookieSpace.s5].
  static const double gutter = 600;

  /// From here package cards may sit side by side, once all three fit their
  /// longest button label on one line (Packages measures it; about 830px).
  static const double packages = 720;

  /// Sections space out to [BrookieSpace.s8]; the calendar and its session
  /// times sit side by side.
  static const double wide = 900;
}

/// Layout values that depend on the window width.
abstract final class BrookieLayout {
  /// The page's side gutter.
  static double gutter(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= BrookieBreakpoint.gutter ? BrookieSpace.s5 : BrookieSpace.s4;

  /// The space between page sections.
  static double sectionGap(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= BrookieBreakpoint.wide ? BrookieSpace.s8 : BrookieSpace.s7;
}

/// Color and border changes take 150ms; selection is instant.
const kBrookieStateDuration = Duration(milliseconds: 150);

/// Dialogs and images fade in over 200ms.
const kBrookieFadeDuration = Duration(milliseconds: 200);

/// The app's theme: [Brightness.light] is Print, [Brightness.dark] Darkroom.
ThemeData brookieTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? BrookieColors.dark : BrookieColors.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.ink,
    onPrimary: c.onInk,
    secondary: c.butter,
    onSecondary: c.onButter,
    error: c.danger,
    onError: c.onInk,
    surface: c.paper,
    onSurface: c.ink,
    onSurfaceVariant: c.inkSoft,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.surfaceSunk,
    outline: c.lineStrong,
    outlineVariant: c.line,
    shadow: Colors.black,
    scrim: c.scrim,
    surfaceTint: Colors.transparent, // no Material tint on raised surfaces
  );

  // Every slot is set, so no Material default (Roboto) is left anywhere.
  final text = TextTheme(
    displayLarge: BrookieType.display,
    displayMedium: BrookieType.headline,
    displaySmall: BrookieType.headline,
    headlineLarge: BrookieType.headline,
    headlineMedium: BrookieType.headline,
    headlineSmall: BrookieType.title,
    titleLarge: BrookieType.title,
    titleMedium: BrookieType.label,
    titleSmall: BrookieType.ui.copyWith(fontWeight: FontWeight.w500),
    bodyLarge: BrookieType.body, // reading text
    bodyMedium: BrookieType.ui, // the default for Text widgets
    bodySmall: BrookieType.small,
    labelLarge: BrookieType.label, // buttons
    labelMedium: BrookieType.small.copyWith(fontWeight: FontWeight.w500),
    labelSmall: BrookieType.small,
  ).apply(bodyColor: c.ink, displayColor: c.ink);

  const pill = StadiumBorder();
  const controlSize = Size(64, BrookieSize.control);
  const controlPadding = EdgeInsets.symmetric(horizontal: BrookieSpace.s5);

  // Focus: a solid 2px ring outside the control. Never removed.
  BorderSide focusRing() => brookieFocusSide(c.focus);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: c.paper,
    canvasColor: c.paper,
    dividerColor: c.line,
    splashFactory: NoSplash.splashFactory, // nearly still: no ink ripples
    visualDensity: VisualDensity.standard, // the same sizes on desktop as on phones
    extensions: [c],
    appBarTheme: AppBarThemeData(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: text.labelLarge,
      iconTheme: IconThemeData(color: c.ink, size: 20),
      actionsIconTheme: IconThemeData(color: c.ink, size: 20),
      shape: Border(bottom: BorderSide(color: c.line)),
    ),
    iconTheme: IconThemeData(color: c.ink, size: 20),
    // The same back arrow everywhere (Flutter would show a chevron on Apple
    // devices).
    actionIconTheme: ActionIconThemeData(backButtonIconBuilder: (context) => const Icon(Icons.arrow_back)),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.surfaceSunk;
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return c.inkSoft;
          return c.ink;
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? c.inkSoft : c.onInk),
        iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? c.inkSoft : c.onInk),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused) ? focusRing() : null),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(controlSize),
        padding: const WidgetStatePropertyAll(controlPadding),
        iconSize: const WidgetStatePropertyAll(20),
        shape: const WidgetStatePropertyAll(pill),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        animationDuration: kBrookieStateDuration,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? c.inkSoft : c.ink),
        iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? c.inkSoft : c.ink),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return focusRing();
          if (states.contains(WidgetState.disabled)) return BorderSide(color: c.line, width: 1.5);
          if (states.contains(WidgetState.hovered)) return BorderSide(color: c.ink, width: 1.5);
          return BorderSide(color: c.lineStrong, width: 1.5);
        }),
        minimumSize: const WidgetStatePropertyAll(controlSize),
        padding: const WidgetStatePropertyAll(controlPadding),
        iconSize: const WidgetStatePropertyAll(20),
        shape: const WidgetStatePropertyAll(pill),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        animationDuration: kBrookieStateDuration,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? c.inkSoft : c.ink),
        iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? c.inkSoft : c.ink),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused) ? focusRing() : null),
        minimumSize: const WidgetStatePropertyAll(Size(48, BrookieSize.control)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: BrookieSpace.s3)),
        iconSize: const WidgetStatePropertyAll(20),
        shape: const WidgetStatePropertyAll(pill),
        // Quiet buttons underline on hover.
        textStyle: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.hovered)
            ? text.labelLarge!.copyWith(decoration: TextDecoration.underline)
            : text.labelLarge),
        animationDuration: kBrookieStateDuration,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? c.inkSoft : c.ink),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.hovered) ? c.surfaceSunk : Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused) ? focusRing() : null),
        minimumSize: const WidgetStatePropertyAll(Size.square(BrookieSize.controlSm)),
        iconSize: const WidgetStatePropertyAll(20),
        shape: const WidgetStatePropertyAll(CircleBorder()),
        animationDuration: kBrookieStateDuration,
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrookieRadius.md),
        side: BorderSide(color: c.line),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      elevation: 24,
      shadowColor: Colors.black.withValues(alpha: brightness == Brightness.dark ? 0.6 : 0.28),
      barrierColor: c.scrim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrookieRadius.md)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyLarge,
      insetPadding: const EdgeInsets.all(BrookieSpace.s4),
      actionsPadding: const EdgeInsets.fromLTRB(BrookieSpace.s5, 0, BrookieSpace.s5, BrookieSpace.s5),
      constraints: const BoxConstraints(maxWidth: 440),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      // Edges come from hairlines; only photographs and dialogs cast shadows.
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrookieRadius.md),
        side: BorderSide(color: c.line),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => BrookieType.ui.copyWith(
          color: states.contains(WidgetState.disabled) ? c.inkSoft : c.ink)),
      menuPadding: const EdgeInsets.symmetric(vertical: BrookieSpace.s2),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(BrookieRadius.sm)),
      textStyle: BrookieType.small.copyWith(color: c.onInk),
      waitDuration: const Duration(milliseconds: 500),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: BrookieType.ui.copyWith(color: c.onInk),
      actionTextColor: c.butter,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrookieRadius.sm)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.ink, linearTrackColor: c.surfaceSunk),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: c.surface,
      labelStyle: BrookieType.small.copyWith(color: c.inkSoft),
      hintStyle: BrookieType.ui.copyWith(color: c.inkSoft),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BrookieRadius.sm),
        borderSide: BorderSide(color: c.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BrookieRadius.sm),
        borderSide: BorderSide(color: c.ink, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BrookieRadius.sm),
        borderSide: BorderSide(color: c.danger, width: 2),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.ink,
      // Light ink on full butter is 1.4:1 in Darkroom; a thinner wash keeps
      // selected text readable (about 7:1).
      selectionColor: c.butter.withValues(alpha: brightness == Brightness.dark ? 0.3 : 0.7),
    ),
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final platform in TargetPlatform.values) platform: const _FadePageTransitionsBuilder(),
    }),
  );
}

/// The keyboard focus ring as a button side: a 2px gap, then a solid 2px ring.
///
/// strokeAlign 3 centers the 2px stroke 3px outside the control's edge, so it
/// covers 2–4px out. Pass [BrookieColors.onButter] on a butter fill. On a
/// photograph use [FocusRing.onPhoto] instead (lib/widgets/focus_ring.dart).
/// In a widget-level ButtonStyle, return [BorderSide.none] rather than null
/// for "no ring": null falls back to the theme's ring.
BorderSide brookieFocusSide(Color color) => BorderSide(color: color, width: 2, strokeAlign: 3);

/// The button style for the one action on a photograph, such as the hero's
/// "Book a session": butter, like the logo's disc. Never on paper.
///
/// It draws no focus ring of its own (no single color shows on every
/// photograph): wrap the button in [FocusRing.onPhoto]
/// (lib/widgets/focus_ring.dart), shown while it has focus.
ButtonStyle onPhotoButtonStyle(BuildContext context) {
  final c = BrookieColors.of(context);
  return ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(c.butter),
    foregroundColor: WidgetStatePropertyAll(c.onButter),
    iconColor: WidgetStatePropertyAll(c.onButter),
    // None rather than null when focused, or the theme's ink ring comes back.
    side: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.hovered) ? BorderSide(color: c.onButter, width: 1.5) : BorderSide.none),
  );
}

/// Pages cross-fade instead of sliding: the site keeps nearly still. With
/// reduced motion on, they switch instantly.
class _FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadePageTransitionsBuilder();

  static final _fade = CurveTween(curve: Curves.easeOut);

  @override
  Duration get transitionDuration => kBrookieFadeDuration;

  @override
  Duration get reverseTransitionDuration => kBrookieFadeDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    // drive() rather than a CurvedAnimation, which this method (run every
    // frame of a transition) would create, and leak, each time.
    return FadeTransition(opacity: animation.drive(_fade), child: child);
  }
}
