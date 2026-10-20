import 'dart:math' as math;

import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';

/// A month of days for choosing when to book, where the chosen day takes the
/// shape of the logo's disc.
///
/// [TableCalendar] dressed in the design system: month view only, weeks start
/// on Sunday, days outside the month left blank, days with openings dotted
/// (unless [showOpenings] is off). By keyboard, Tab visits each open day in
/// reading order and the arrow keys move to the nearest open day in their
/// direction.
class BookingCalendar extends StatefulWidget {
  const BookingCalendar({
    super.key,
    required this.firstDay,
    required this.lastDay,
    required this.today,
    required this.selectedDay,
    required this.onDaySelected,
    this.isOpen,
    this.edgeToEdge = false,
    this.showOpenings = true,
  });

  /// The bookable range. Days outside it can't be chosen.
  final DateTime firstDay;
  final DateTime lastDay;

  /// Ringed, so families can find their place in the month.
  final DateTime today;

  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  /// Whether a day in range has openings. Days without them look and act like
  /// past days.
  final bool Function(DateTime day)? isOpen;

  /// Whether the calendar spans the window from edge to edge, as a band with
  /// hairlines above and below instead of a card. For windows too narrow to
  /// fit a card of [minCardWidth] inside the page gutter.
  final bool edgeToEdge;

  /// Whether days with openings are dotted, with the "Openings that day"
  /// legend under the month. Off where any day in range can be chosen and
  /// openings mean nothing, such as an admin dating a session.
  final bool showOpenings;

  /// The card's widest; the days stay [BrookieSize.day] apart or more.
  static const maxWidth = 400.0;

  /// The narrowest card that still fits seven full-size days with room for
  /// their focus rings. Narrower than this, lay the calendar [edgeToEdge].
  static const minCardWidth = 7 * BrookieSize.day + 2 * BrookieSpace.s2 + 2;

  @override
  State<BookingCalendar> createState() => _BookingCalendarState();
}

class _BookingCalendarState extends State<BookingCalendar> {
  late DateTime _focusedDay = _clamp(widget.selectedDay ?? widget.firstDay);

  final _previousMonth = FocusNode(debugLabel: 'Previous month');
  final _nextMonth = FocusNode(debugLabel: 'Next month');

  /// Tab reads the days a week at a time; the page scrolls a focused day
  /// into view, but the month pages never move.
  final _dayTraversal = ReadingOrderTraversalPolicy(requestFocusCallback: requestFocusInView);

  /// The arrow keys move from day to day. On the web they would otherwise
  /// scroll the nearest scroll view, the month pages, nudging the month
  /// sideways while focus stays put.
  static const _arrowKeys = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(TraversalDirection.left),
    SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(TraversalDirection.right),
    SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
    SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
  };

  DateTime get _first => _date(widget.firstDay);
  DateTime get _last => _date(widget.lastDay);

  // TableCalendar hands out days as UTC midnights; compare in the same terms.
  static DateTime _date(DateTime day) => DateTime.utc(day.year, day.month, day.day);

  @override
  void dispose() {
    _previousMonth.dispose();
    _nextMonth.dispose();
    super.dispose();
  }

  DateTime _clamp(DateTime day) {
    final date = _date(day);
    if (date.isBefore(_first)) return _first;
    if (date.isAfter(_last)) return _last;
    return date;
  }

  bool _isBookable(DateTime day) {
    final date = _date(day);
    return !date.isBefore(_first) && !date.isAfter(_last) && (widget.isOpen?.call(date) ?? true);
  }

  bool _isFirstMonth(DateTime month) => month.year == _first.year && month.month == _first.month;
  bool _isLastMonth(DateTime month) => month.year == _last.year && month.month == _last.month;

  void _showMonth(int offset) {
    final month = _clamp(DateTime.utc(_focusedDay.year, _focusedDay.month + offset));
    // At the window's edge the button just pressed switches off, and keyboard
    // focus would fall back to the top bar. Hand it to the other month button
    // instead, once the rebuild has switched that one on.
    final pressed = offset > 0 ? _nextMonth : _previousMonth;
    final other = offset > 0 ? _previousMonth : _nextMonth;
    final atEdge = offset > 0 ? _isLastMonth(month) : _isFirstMonth(month);
    if (atEdge && pressed.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && other.canRequestFocus) other.requestFocus();
      });
    }
    setState(() => _focusedDay = month);
  }

  void _select(DateTime day) {
    setState(() => _focusedDay = _clamp(day));
    widget.onDaySelected(_date(day));
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final weekday = BrookieType.small.copyWith(color: c.inkSoft);
    // The weekday row grows with the text so its letters keep their room.
    final weekdayHeight = math.max(
      28.0,
      MediaQuery.textScalerOf(context).scale(weekday.fontSize!) * weekday.height! + BrookieSpace.s2,
    );

    final edgeToEdge = widget.edgeToEdge;
    final decoration = edgeToEdge
        ? BoxDecoration(
            color: c.surface,
            border: Border.symmetric(horizontal: BorderSide(color: c.line)),
          )
        : BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(BrookieRadius.md),
          );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: edgeToEdge ? double.infinity : BookingCalendar.maxWidth),
      child: DecoratedBox(
        decoration: decoration,
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final double side;
          if (edgeToEdge) {
            // Seven full-size days across the window, the rest split evenly.
            side = ((width - 7 * BrookieSize.day) / 2).clamp(BrookieSpace.s1, BrookieSpace.s4);
          } else {
            // On narrow phones, trade card padding for full-size days.
            final roomy = width >= 7 * BrookieSize.day + 2 * BrookieSpace.s4 + 2;
            side = roomy ? BrookieSpace.s4 : BrookieSpace.s2;
          }
          // The month and the legend line up with the page in a band, and with
          // the days in a card.
          final chrome = edgeToEdge ? BrookieSpace.s4 : side;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(chrome, BrookieSpace.s3, chrome, 0),
                child: _MonthHeader(
                  month: _focusedDay,
                  previousFocusNode: _previousMonth,
                  nextFocusNode: _nextMonth,
                  onPrevious: _isFirstMonth(_focusedDay) ? null : () => _showMonth(-1),
                  onNext: _isLastMonth(_focusedDay) ? null : () => _showMonth(1),
                ),
              ),
              const SizedBox(height: BrookieSpace.s2),
              // Its own group, so Tab reads the days a week at a time instead
              // of sorting them in with the session times beside the calendar.
              Shortcuts(
                shortcuts: _arrowKeys,
                child: FocusTraversalGroup(
                  policy: _dayTraversal,
                  child: TableCalendar<void>(
                    firstDay: _first,
                    lastDay: _last,
                    focusedDay: _focusedDay,
                    currentDay: widget.today,
                    // Our own header: the package's chevrons have no tooltips
                    // and no focus ring.
                    headerVisible: false,
                    calendarFormat: CalendarFormat.month,
                    availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                    availableGestures: AvailableGestures.horizontalSwipe,
                    startingDayOfWeek: StartingDayOfWeek.sunday,
                    rowHeight: BrookieSize.day + BrookieSpace.s1,
                    daysOfWeekHeight: weekdayHeight,
                    pageAnimationEnabled: !still,
                    pageAnimationDuration: kBrookieFadeDuration,
                    formatAnimationDuration: still ? Duration.zero : kBrookieFadeDuration,
                    formatAnimationCurve: Curves.easeOut,
                    enabledDayPredicate: _isBookable,
                    selectedDayPredicate: (day) => isSameDay(widget.selectedDay, day),
                    onDaySelected: (day, focusedDay) => _select(day),
                    onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
                    // Past and closed days get their semantics too, so a screen
                    // reader hears them as unavailable rather than skipping them.
                    loadEventsForDisabledDays: true,
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      cellMargin: EdgeInsets.zero,
                      // The month pages clip at their edges. The padding sits
                      // inside them, so the chosen day's ring and the focus ring
                      // on the outer columns and the last week stay whole.
                      tablePadding: EdgeInsets.fromLTRB(side, 0, side, BrookieSpace.s3),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      dowTextFormatter: (day, locale) => weekdayInitial(day),
                      weekdayStyle: weekday,
                      weekendStyle: weekday,
                    ),
                    calendarBuilders: CalendarBuilders<void>(
                      prioritizedBuilder: (context, day, focusedDay) => _DayDisc(
                        day: day,
                        bookable: _isBookable(day),
                        selected: isSameDay(widget.selectedDay, day),
                        today: isSameDay(widget.today, day),
                        showOpenings: widget.showOpenings,
                        onSelected: () => _select(day),
                      ),
                      // TableCalendar wraps each day in its own label and drops
                      // ours, so the state rides along on the marker layer.
                      markerBuilder: (context, day, events) => _DaySemantics(
                        bookable: _isBookable(day),
                        selected: isSameDay(widget.selectedDay, day),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.showOpenings)
                Padding(
                  padding: EdgeInsets.fromLTRB(chrome, 0, chrome, BrookieSpace.s4),
                  child: const _Legend(),
                )
              else
                // The last week's s3 below it, and s1 more: what the month
                // header has above.
                const SizedBox(height: BrookieSpace.s1),
            ],
          );
        }),
      ),
    );
  }
}

/// "October 2026" between the previous and next month buttons.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.previousFocusNode,
    required this.nextFocusNode,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final FocusNode previousFocusNode;
  final FocusNode nextFocusNode;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    // Past the booking window the buttons switch off and step back to
    // ink-soft (the theme's disabled icon button).
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          focusNode: previousFocusNode,
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              formatMonth(month),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          focusNode: nextFocusNode,
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// The 4px dot that marks a day with openings.
class _OpeningsDot extends StatelessWidget {
  const _OpeningsDot({required this.color});

  final Color color;

  static const size = 4.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
    );
  }
}

/// Explains the dot under the days: "Openings that day".
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final style = BrookieType.small.copyWith(color: c.inkSoft);
    return Row(
      children: [
        _OpeningsDot(color: c.ink),
        const SizedBox(width: BrookieSpace.s2),
        Flexible(child: Text('Openings that day', style: style)),
      ],
    );
  }
}

/// One day: a 44px disc. Ink numerals with a dot beneath for days with
/// openings (when [showOpenings]), ink-soft for the rest, a fine ring for
/// today, and butter with an ink ring when chosen.
class _DayDisc extends StatefulWidget {
  const _DayDisc({
    required this.day,
    required this.bookable,
    required this.selected,
    required this.today,
    required this.showOpenings,
    required this.onSelected,
  });

  final DateTime day;
  final bool bookable;
  final bool selected;
  final bool today;
  final bool showOpenings;
  final VoidCallback onSelected;

  @override
  State<_DayDisc> createState() => _DayDiscState();
}

class _DayDiscState extends State<_DayDisc> {
  bool _hovered = false;
  bool _focused = false;

  /// The most room a numeral gets, centered in the disc: its line box at 1.5
  /// times the label size. Jost's figures sit in the middle of the line box,
  /// so even at that size they end clear of the openings dot.
  static const _numeralBox = Size(BrookieSize.day - 2 * BrookieSpace.s1, 30);

  /// The openings dot sits this far above the disc's bottom edge.
  static const _dotInset = 6.0;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final selected = widget.selected;
    final bookable = widget.bookable;

    final Color fill;
    if (selected) {
      fill = c.butter;
    } else if (bookable && _hovered) {
      fill = c.surfaceSunk;
    } else {
      fill = Colors.transparent;
    }

    final Color numeral;
    if (selected) {
      numeral = c.onButter;
    } else {
      numeral = bookable ? c.ink : c.inkSoft;
    }

    // Taps reach TableCalendar's own gesture detector around this; the
    // detector here adds keyboard focus, Enter/Space and hover.
    return FocusableActionDetector(
      enabled: bookable,
      mouseCursor: bookable ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onSelected();
          return null;
        }),
      },
      child: Center(
        child: FocusRing.circle(
          visible: _focused,
          child: AnimatedContainer(
            // Hover eases in; selection is instant.
            duration: selected || MediaQuery.disableAnimationsOf(context) ? Duration.zero : kBrookieStateDuration,
            width: BrookieSize.day,
            height: BrookieSize.day,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              // Butter is nearly invisible on paper, so the chosen day also
              // gets a 1.5px ink ring.
              boxShadow: selected ? [BoxShadow(color: c.ink, spreadRadius: 1.5)] : null,
            ),
            // Today's ring is painted over the disc rather than set as its
            // border, which would pad the numeral and the dot inward.
            foregroundDecoration: widget.today && !selected
                ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.lineStrong))
                : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Large text grows to 1.5 times, then shrinks to fit rather
                // than wrapping or running into the dot.
                SizedBox.fromSize(
                  size: _numeralBox,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${widget.day.day}',
                      maxLines: 1,
                      softWrap: false,
                      // Unavailable days are set lighter as well as softer.
                      style: BrookieType.label.copyWith(
                        color: numeral,
                        fontWeight: bookable || selected ? null : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                if (bookable && widget.showOpenings) Positioned(bottom: _dotInset, child: _OpeningsDot(color: numeral)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts a day's state on the node TableCalendar labels "Saturday, October
/// 24, 2026": a button, selected or not, unavailable for past days.
class _DaySemantics extends StatelessWidget {
  const _DaySemantics({required this.bookable, required this.selected});

  final bool bookable;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(button: true, enabled: bookable, selected: selected, child: const SizedBox.shrink());
  }
}
